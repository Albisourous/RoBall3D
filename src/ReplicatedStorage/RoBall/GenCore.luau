--!strict
-- Pure seeded track generator (DESIGN.md §8). Emits ChunkSpecs only —
-- no Instances, no math.random, fully determined by the seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)

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
	self.introIndex = 0
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
	local snap: ChunkDefs.GenState = {
		zEnd = st.zEnd,
		centerX = st.centerX,
		width = st.width,
		y = st.y,
		dist = st.dist,
		rng = self.rng,
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
				Config.Gems.ValueSafe
			) or nil,
		}
	else
		local tier = Tiers.forDistance(st.dist)
		local pool = tier.chunkPool
		local name = pool[self.rng:NextInteger(1, #pool)]
		spec = ChunkDefs[name](self.rng, snap, tier)
	end

	st.zEnd -= spec.length
	st.dist += spec.length
	st.centerX = spec.endState.centerX
	st.width = spec.endState.width
	st.y = spec.endState.y
	return spec
end

return GenCore
