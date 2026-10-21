--!strict
-- Pure seeded track generator (DESIGN.md §8). Emits ChunkSpecs only —
-- no Instances, no math.random, fully determined by the seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)
local MusicGrid = require(ReplicatedStorage.RoBall.MusicGrid)
local Mutator = require(ReplicatedStorage.RoBall.Mutator)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)

local GenCore = {}
GenCore.__index = GenCore

export type Gen = typeof(setmetatable({} :: any, GenCore))

function GenCore.new(seed: number): Gen
	local self = setmetatable({}, GenCore)
	self.seed = seed
	self.rng = Random.new(seed)
	self.state = {
		zEnd = 15, -- first chunk starts a bit ahead of the ball's z=0 spawn
		centerX = 0,
		width = Config.Generation.BaseWidth,
		y = Config.Generation.StartY,
		dist = 0,
	}
	-- Musical clock (AUDIO.md §5.2): song-beats elapsed at st.dist on the
	-- nominal speed schedule, accumulated incrementally per chunk so the
	-- integral stays O(chunk) instead of re-summing from zero. The run's
	-- track is the seeded pick the runtime shares (AUDIO.md §3), and it
	-- opens on a seed-rotated accent (§6) — start the clock there so
	-- stamped sections match what the player hears from beat one.
	self.map = SongMap.forTrack(SongMap.trackIdFor(seed, Config.Music.ActiveTracklist))
	-- Seed flavor (§8.7): one mutator record, rolled on a salted stream so
	-- the flavor pick never shifts the chunk roll sequence.
	self.mutator = Mutator.forSeed(seed)
	self.beatPos = Config.MusicSync.SeededStartOffset and self.map.startBeatFor(seed) or 0
	self.introIndex = 0
	-- Feature ramp (DESIGN.md §8.6): name -> true once its gentle debut
	-- showcase has spawned. Debuted types hold out of the pool until then.
	self.debuted = {}
	self.intro = {
		{ type = "Flat", length = 35, widthOut = 48 },
		{ type = "Flat", length = 35, widthOut = 44, gems = true }, -- teaches: gems exist
		{ type = "Slalom", length = 45, amp = 8, periods = 0.6 },
		{ type = "Narrow", length = 55, widthOut = 32 },
	}
	return self
end

local function introSection(st, chunk)
	return function(t: number)
		if chunk.type == "Slalom" then
			return {
				width = st.width,
				centerX = st.centerX + chunk.amp * math.sin(t * chunk.periods * math.pi * 2),
				y = st.y,
				rollDeg = 0,
			}
		end
		local widthOut = chunk.widthOut or st.width
		return {
			width = st.width + (widthOut - st.width) * t,
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
		}
	end
end

function GenCore:nextChunk(): ChunkDefs.ChunkSpec
	local st = self.state
	local spec: ChunkDefs.ChunkSpec

	-- Section closures are evaluated later (buildChunk/yAt), after self.state
	-- has already advanced — hand builders a frozen snapshot so they capture
	-- entry geometry, not the live state table.
	-- Section the ball will be hearing when it reaches this chunk — passed
	-- to builders so gem density and set-piece placement can ride the grid.
	local songSection = self.map.sectionAtBeat(self.beatPos)

	local snap: ChunkDefs.GenState = {
		zEnd = st.zEnd,
		centerX = st.centerX,
		width = st.width,
		y = st.y,
		dist = st.dist,
		rng = self.rng,
		beatPos = self.beatPos,
		section = songSection,
		map = self.map,
	}

	if self.introIndex < #self.intro then
		self.introIndex += 1
		local chunk = self.intro[self.introIndex]
		local section = ChunkDefs.wrapGrade(chunk.length, introSection(snap, chunk))
		spec = {
			type = "Intro_" .. chunk.type,
			length = chunk.length,
			startZ = snap.zEnd,
			section = section,
			endState = {
				centerX = (chunk.type == "Slalom") and snap.centerX + chunk.amp * math.sin(chunk.periods * math.pi * 2)
					or snap.centerX,
				width = chunk.widthOut or snap.width,
				y = snap.y - Config.Generation.Grade * chunk.length,
			},
			gems = chunk.gems and ChunkDefs.gemRhythmLine(
				self.rng,
				Config.Speed.Start,
				chunk.length,
				0.2,
				0.55,
				0,
				Config.Gems.ValueSafe,
				nil,
				songSection.energy,
				self.map.bpm
			) or nil,
		}
	else
		local tier = Tiers.forDistance(st.dist)
		local pool = tier.chunkPool
		local name
		-- Feature debut (DESIGN.md §8.6): the first eligible spawn of each
		-- feature type past its milestone distance is the gentle showcase.
		-- A type holds out of the random pool until its debut has run.
		for _, fname in ipairs(Config.Features.DebutOrder) do
			if
				not self.debuted[fname]
				and st.dist >= (Config.Features.Debut[fname] or math.huge)
				and table.find(pool, fname) ~= nil
				and ChunkDefs.canRun(fname, snap, tier)
			then
				self.debuted[fname] = true
				name = fname
				spec = ChunkDefs[name](self.rng, snap, tier, true)
				spec.debut = true -- marks the showcase so the HUD can name it
				break
			end
		end
		if not name then
			-- Pool candidates: debut-gated types stay out until their
			-- showcase ran; canRun drops context-gated types that don't fit
			-- (DropGate needs an accent, Blackout a break section, movers a
			-- minimum deck width).
			local cand = {}
			for _, cname in ipairs(pool) do
				if
					(not Config.Features.Debut[cname] or self.debuted[cname])
					and ChunkDefs.canRun(cname, snap, tier)
				then
					table.insert(cand, cname)
				end
			end
			if #cand == 0 then
				cand = { "Flat" }
			end
			-- Songform weighting (AUDIO.md §5.2): chunk families reweight
			-- by the section energy under the ball — drops roll lethal,
			-- breaks roll breathers. The seed's flavor (§8.7) then
			-- multiplies in — selection bias only, legality rules untouched.
			-- MusicSync off still carries the flavor over a uniform base.
			local e = songSection.energy
			local mut = self.mutator
			local weights = {}
			local total = 0
			for _, cname in ipairs(cand) do
				local fam = Config.MusicSync.ChunkFamily[cname] or "technical"
				local fw = Config.MusicSync.Families[fam]
				local w = if Config.MusicSync.Enabled then fw.lo + (fw.hi - fw.lo) * e else 1
				w *= (mut.fams[fam] or 1) * (mut.types[cname] or 1)
				weights[cname] = w
				total += w
			end
			local roll = self.rng:NextNumber(0, total)
			for _, cname in ipairs(cand) do
				roll -= weights[cname]
				if roll <= 0 then
					name = cname
					break
				end
			end
			name = name or cand[#cand]
			spec = ChunkDefs[name](self.rng, snap, tier)
		end
	end

	-- Advance the musical clock by the beats this chunk spans, then the
	-- state — next chunk's section lookup starts where this one ended.
	self.beatPos += MusicGrid.beatsBetween(st.dist, st.dist + spec.length, self.map.bpm)
	st.zEnd -= spec.length
	st.dist += spec.length
	st.centerX = spec.endState.centerX
	st.width = spec.endState.width
	st.y = spec.endState.y
	return spec
end

return GenCore
