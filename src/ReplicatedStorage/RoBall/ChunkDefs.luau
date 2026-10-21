--!strict
-- Chunk type definitions (DESIGN.md §8.3).
--
-- Each builder takes (rng, st, tier) and returns a ChunkSpec:
--   length   = studs the chunk spans along -Z
--   section  = (t: 0..1) -> Section — pure geometry, no Instances
--   endState = GenState fields the NEXT chunk must start from
--
-- Section fields:
--   width   = ribbon width (0 => void, nothing emitted)
--   centerX = lane-local X of ribbon center
--   y       = deck TOP surface height
--   rollDeg = bank angle around the travel axis
--   cutout  = optional center strip removed (SplitGap) — leaves two rails
--   wallH   = optional rail wall height at both edges (Bowl)
--
-- Every section fn MUST satisfy: entry geometry == st.{width,centerX,y}
-- and endState carries where it exits, so the stream stays continuable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local MusicGrid = require(ReplicatedStorage.RoBall.MusicGrid)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)

export type GenState = {
	zEnd: number,
	centerX: number,
	width: number,
	y: number,
	dist: number,
	rng: Random,
	-- Musical clock (AUDIO.md §5.2): song-beats elapsed at chunk start and
	-- the SongMap section the ball hears across it. Optional so hand-built
	-- specs (intro) and tests can omit them.
	beatPos: number?,
	section: { kind: string, energy: number }?,
	-- The run's SongMap (per-track bpm/accent data). Optional — falls back
	-- to the default track's map for hand-built specs and tests.
	map: any?,
}

export type Section = {
	width: number,
	centerX: number,
	y: number,
	rollDeg: number,
	cutout: number?,
	cutoutOff: number?, -- lane-local center of the cutout (Fork); 0 = centered
	wallH: number?,
	roofH: number?, -- TunnelSlot: dark ceiling ribbon this high above deck
}

export type ChunkSpec = {
	type: string,
	length: number,
	startZ: number,
	section: (t: number) -> Section,
	endState: { centerX: number, width: number, y: number },
	obstacles: { Obstacle }?,
	gems: { GemSpot }?,
	pads: { Pad }?,
	orbs: { Orb }?, -- OrbHop (flag: Features.JumpOrbs)
	flip: FlipZone?, -- FlipRide (flag: Features.GravityFlip)
	dim: boolean?, -- Blackout: grid/center neon dims (edges + gems stay lit)
	debut: boolean?, -- set by GenCore when this chunk is the feature's gentle showcase
	tierGate: { dist: number, t: number }?, -- arch marker where dist crosses a tier boundary
}

-- Lethal geometry placed on the deck (DESIGN.md §8.3 obstacle rules).
-- xOff is relative to the deck centerX at t; the streamer positions each block
-- at section(t) so it rides the graded/rolled surface.
export type Obstacle = {
	t: number, -- 0..1 along the chunk
	xOff: number, -- lane-local X offset from deck center
	w: number,
	h: number,
	d: number,
	hang: boolean?, -- top anchors to section's roofH (tunnel slabs)
	motion: Motion?, -- beat-locked movement (Pacer/Rotor)
}

export type Motion = {
	kind: string, -- "slideX" | "spin" | "dropY"
	amp: number?, -- slideX: studs of lateral travel
	periodSec: number,
	phase: number,
}

-- LaunchPad (DESIGN.md §8.3): a cyan strip the ball rolls over; the client
-- applies kickY as a one-shot vertical velocity — ballistic flight, no jump
-- input. The builder computes kickY so the arc clears the hazard at tier speed.
export type Pad = {
	t: number,
	xOff: number,
	w: number,
	d: number,
	kickY: number,
}

-- JumpOrb (stretch, flag-off): a tap target floating over a void. The
-- client re-kicks vY to kickY when the player jumps while inside radius —
-- the second arc extends where the pad arc alone can't reach.
export type Orb = {
	t: number,
	xOff: number,
	yOff: number, -- height above deck at t
	kickY: number,
	radius: number,
}

-- FlipRide zone (stretch, flag-off): t0..t1 the client holds vY=+Lift so
-- the ball rides a ceiling ribbon `clearH` above the deck; steering
-- mirrors inside. Zone ends -> gravity resumes, ball drops back.
export type FlipZone = {
	t0: number,
	t1: number,
	clearH: number,
}

-- Gem pickup spot. xOff is relative to deck centerX at t, so a gem on a
-- Slalom's centerline (xOff=0) follows the curve. yOff overrides the
-- default hover height (ramp arcs float higher over the void).
export type GemSpot = {
	t: number,
	xOff: number,
	value: number,
	yOff: number?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local ChunkDefs = {}

-- Constant downhill grade (DESIGN.md §8.1): every section's deck drops by
-- Grade per stud of travel, so the whole track visibly descends and the
-- auto-roll reads as "rolling downhill". Applied here so all chunk types
-- inherit it.
local function applyGrade(length: number, section: (t: number) -> Section): (t: number) -> Section
	local grade = Config.Generation.Grade
	return function(t: number)
		local s = section(t)
		s.y -= grade * t * length
		return s
	end
end

function ChunkDefs.wrapGrade(length: number, section: (t: number) -> Section): (t: number) -> Section
	return applyGrade(length, section)
end

local function spec(
	name: string,
	st: GenState,
	length: number,
	section: (t: number) -> Section,
	endState: { centerX: number, width: number, y: number },
	obstacles: { Obstacle }?,
	gems: { GemSpot }?
): ChunkSpec
	local graded = applyGrade(length, section)
	local gradedEnd =
		{ centerX = endState.centerX, width = endState.width, y = endState.y - Config.Generation.Grade * length }
	return {
		type = name,
		length = length,
		startZ = st.zEnd,
		section = graded,
		endState = gradedEnd,
		obstacles = obstacles,
		gems = gems,
	}
end

-- A short line of gems marching along t. xOff=0 tracks the deck centerline.
-- `spacing` is studs between gems — pass the beat-grid value from
-- gemRhythmLine so pickups land on the music's subdivisions.
local function gemLine(
	length: number,
	t0: number,
	xOff: number,
	value: number,
	count: number,
	yOff: number?,
	spacing: number?
): { GemSpot }
	local out = {}
	local step = (spacing or 3) / length
	for i = 1, count do
		local t = t0 + (i - 1) * step
		if t <= 0.95 then
			table.insert(out, { t = t, xOff = xOff, value = value, yOff = yOff })
		end
	end
	return out
end

ChunkDefs.gemLine = gemLine

local function appendAll(dst: { GemSpot }, src: { GemSpot })
	for _, g in ipairs(src) do
		table.insert(dst, g)
	end
end

-- ===================== rhythmic gem clusters =====================
-- Cluster sizes are note groupings: 8 = sixteenths, 4 = eighths,
-- 2 = quarters, 1 = single accent. Spacing scales with ball speed so the
-- pickup INTERVAL is a constant note value at any pace — the heard BPM is
-- Music.BaseBpm * PlaybackSpeed, and PlaybackSpeed ramps with the same
-- speed curve the ball uses.

local GEM_BOUND = 0.92 -- keep lines off the last sliver of deck

-- Studs between gems for a pickup interval of `subdiv` beats at `speed`.
local function beatSpacing(speed: number, subdiv: number, bpm: number?): number
	local ps = MusicGrid.playbackSpeedAt(speed)
	local beat = 60 / ((bpm or Config.Music.BaseBpm) * ps)
	return speed * beat / subdiv
end

-- Written subdivision per size: 8s read as 16ths, 4s as 8ths, 2s as
-- quarters. If a line wouldn't fit, retry one step denser (32nd-note
-- buzz rolls at high speed) before dropping the size.
-- `energy` (AUDIO.md §5.2): drops prefer the denser read, breaks cap at
-- quarter-note clusters so calm music isn't machine-gunned.
local function rollRhythm(rng: Random, speed: number, maxSpan: number, energy: number?, bpm: number?): (number, number)
	local e = energy or 0.5
	local sizes = Config.Gems.ClusterSizes
	local weights = Config.Gems.ClusterWeights
	local total = 0
	local picks = {}
	for i, sz in ipairs(sizes) do
		if not (e < 0.4 and sz > 4) then
			local subdivs = { math.max(1, sz / 2), math.max(1, sz) }
			if Config.MusicSync.DropDenseGems and e > 0.8 then
				subdivs = { subdivs[2], subdivs[1] } -- densest first in drops
			end
			for _, subdiv in ipairs(subdivs) do
				local sp = beatSpacing(speed, subdiv, bpm)
				if (sz - 1) * sp <= maxSpan then
					picks[sz] = sp
					total += weights[i]
					break
				end
			end
		end
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for i, sz in ipairs(sizes) do
		if picks[sz] then
			acc += weights[i]
			if roll <= acc then
				return sz, picks[sz]
			end
		end
	end
	return 1, 0
end

-- A gem line whose pickups land on the heard beat. Rolls a cluster size
-- that fits the chunk, places t0 inside [tLo, tHi] clipped so the line
-- ends before GEM_BOUND.
local function gemRhythmLine(
	rng: Random,
	speed: number,
	length: number,
	tLo: number,
	tHi: number,
	xOff: number,
	value: number,
	yOff: number?,
	energy: number?,
	bpm: number?
): { GemSpot }
	local size, spacing = rollRhythm(rng, speed, (GEM_BOUND - tLo) * length, energy, bpm)
	local span = (size - 1) * spacing
	local hi = math.min(tHi, GEM_BOUND - span / length)
	local t0 = rng:NextNumber(tLo, math.max(tLo, hi))
	return gemLine(length, t0, xOff, value, size, yOff, spacing)
end

ChunkDefs.gemRhythmLine = gemRhythmLine
ChunkDefs.beatSpacing = beatSpacing

-- Section energy the generator stamped on this chunk's state — 0.5 is the
-- neutral default for hand-built specs and tests with no SongMap context.
local function energyOf(st: GenState): number
	return (st.section and st.section.energy) or 0.5
end

-- Run track's tempo for gem spacing — falls back to the default map's bpm.
local function bpmOf(st: GenState): number
	return (st.map and st.map.bpm) or Config.Music.BaseBpm
end

-- Phrase quantization (AUDIO.md §5.2): studs from this chunk's start to
-- the next accent downbeat, or nil when the clock isn't running
-- (hand-built specs/tests). Set pieces slide their feature onto it.
local function studsToAccent(st: GenState): number?
	if not Config.MusicSync.QuantizeSetPieces or not st.beatPos then
		return nil
	end
	local map = st.map or SongMap
	local bps = MusicGrid.beatsPerStud(Tiers.speedAt(st.dist), map.bpm)
	if bps <= 0 then
		return nil
	end
	return (map.nextAccentBeat(st.beatPos) - st.beatPos) / bps
end

-- Lateral honesty (§8.6, GenVerify reachability): studs of track a ball
-- needs to cross `latD` studs sideways at the SLOWEST survivable entry —
-- a braked ball has the most lateral room per stud, so a transition
-- transit-able while braking is transit-able at any entry speed. Width
-- lerps and cutout mouths size their length so the closing edge never
-- outruns this; the 0.85 factor leaves accel ramp-up slack.
local function latTravel(latD: number, speed: number): number
	return latD * speed * Config.Pads.SlowCrossFrac / (Config.Steering.MaxLateralSpeed * 0.85)
end

-- Inverse: how much lateral room `studs` of lead-in affords at the same
-- conservative entry speed. Gate slots are drawn inside this bound.
local function latReach(studs: number, speed: number): number
	return studs * Config.Steering.MaxLateralSpeed * 0.85 / math.max(speed * Config.Pads.SlowCrossFrac, 1)
end

-- Flat: plain ribbon; width may drift toward a random in-tier target.
-- Gems: safe center lines or edge-rail lines (riskier, worth more).
function ChunkDefs.Flat(rng: Random, st: GenState, tier): ChunkSpec
	local target = math.clamp(
		rng:NextNumber(tier.widthMin, tier.widthMax),
		Config.Generation.MinWidth,
		Config.Generation.BaseWidth
	)
	local speed = Tiers.speedAt(st.dist + 100)
	-- Shrinking drifts grow the chunk so the closing edge stays under
	-- lateral authority from ANY on-deck entry position (GenVerify §8.6).
	local length = math.max(rng:NextInteger(40, 70), math.ceil(latTravel(math.max(st.width - target, 0) / 2, speed)))
	local gems = {}
	local clusters = rng:NextInteger(Config.Gems.ClustersPerChunkMin, Config.Gems.ClustersPerChunkMax)
	for _ = 1, clusters do
		local edge = rng:NextNumber() < 0.5
		-- Edge lines anchor to the lerp's NARROWER end so a shrinking
		-- drift never leaves gems hanging over void mid-chunk.
		local halfW = math.min(st.width, target) / 2
		local xOff = if edge then (rng:NextInteger(0, 1) * 2 - 1) * math.max(0, halfW - 2) else 0
		appendAll(
			gems,
			gemRhythmLine(
				rng,
				speed,
				length,
				0.15,
				0.7,
				xOff,
				edge and Config.Gems.ValueEdge or Config.Gems.ValueSafe,
				nil,
				energyOf(st),
				bpmOf(st)
			)
		)
	end
	return spec("Flat", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y }, nil, gems)
end

-- Slalom: constant width, centerline sways sinusoidally.
function ChunkDefs.Slalom(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(50, 90)
	-- Sway bound: the zero-steer corridor (GenVerify asserts it). Worst-case
	-- center deviation is 2*amp (full sine span), and a ball holding the
	-- entry line must keep radius clearance: 2*amp <= width/2 - BallRadius.
	-- Bounded by the LIVE deck, not the tier ceiling — a width-10 ribbon
	-- can't host a sway the ball survives unsteered.
	local ampHi = math.min(14, st.width / 4 - 0.75)
	local amp = rng:NextNumber(math.min(6, ampHi), ampHi)
	local periods = rng:NextNumber(0.7, 1.4)
	local phase = rng:NextNumber(0, math.pi * 2)
	local s0 = math.sin(phase) -- anchor the seam: center(0) must equal st.centerX
	local center = function(t: number)
		return st.centerX + amp * (math.sin(phase + t * periods * math.pi * 2) - s0)
	end
	-- xOff=0 rides the swaying centerline — following gems teaches the curve.
	local gems = gemRhythmLine(
		rng,
		Tiers.speedAt(st.dist),
		length,
		0.2,
		0.5,
		0,
		Config.Gems.ValueSafe,
		nil,
		energyOf(st),
		bpmOf(st)
	)
	return spec("Slalom", st, length, function(t)
		return { width = st.width, centerX = center(t), y = st.y, rollDeg = 0 }
	end, { centerX = center(1), width = st.width, y = st.y }, nil, gems)
end

-- Narrow: width eases toward a (usually smaller) target.
function ChunkDefs.Narrow(rng: Random, st: GenState, tier): ChunkSpec
	local upper = math.min(st.width, tier.widthMax)
	local lower = math.max(tier.widthMin, Config.Generation.MinWidth)
	local target = rng:NextNumber(lower, math.max(lower, upper))
	-- Same lateral-honesty rule as Flat: the closing edge can't outrun a
	-- braked ball coming in from the far edge.
	local length = math.max(
		rng:NextInteger(35, 60),
		math.ceil(latTravel(math.max(st.width - target, 0) / 2, Tiers.speedAt(st.dist + 100)))
	)
	-- Beam line down the narrowing middle — the risky but rewarding line.
	local gems = gemRhythmLine(
		rng,
		Tiers.speedAt(st.dist),
		length,
		0.3,
		0.6,
		0,
		Config.Gems.ValueBeam,
		nil,
		energyOf(st),
		bpmOf(st)
	)
	return spec("Narrow", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y }, nil, gems)
end

-- Widen: the mirror of Narrow — the deck OPENS back toward the tier
-- ceiling. Late tiers otherwise ratchet width toward widthMin and camp
-- there; alternating Narrow/Widen makes the deep deck sawtooth inside
-- the tier's [widthMin, widthMax] window. It opens fast (first ~35%)
-- then holds, so twin edge-margin gem lines park on real deck — reaching
-- both rails is a full-width lateral commitment, the job Q/E dash is for.
function ChunkDefs.Widen(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(45, 70)
	-- Land clearly wider than entry, biased to the window's upper half —
	-- a vista opening, not a nudge. canRun guarantees ≥4 studs of headroom.
	local lo = math.max(st.width + 4, (tier.widthMin + tier.widthMax) / 2)
	local target = rng:NextNumber(math.min(lo, tier.widthMax), tier.widthMax)
	local gems = {}
	local speed = Tiers.speedAt(st.dist)
	for _, side in ipairs({ -1, 1 }) do
		appendAll(
			gems,
			gemRhythmLine(
				rng,
				speed,
				length,
				0.45,
				0.8,
				side * (target / 2 - 2),
				Config.Gems.ValueEdge,
				nil,
				energyOf(st),
				bpmOf(st)
			)
		)
	end
	return spec("Widen", st, length, function(t)
		return { width = lerp(st.width, target, math.min(t / 0.35, 1)), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y }, nil, gems)
end

-- Tilt: bank the ribbon, hold, return level. Always exits flat.
function ChunkDefs.Tilt(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(40, 70)
	local roll = rng:NextNumber(8, 20) * (rng:NextInteger(0, 1) * 2 - 1)
	local rollAt = function(t: number)
		-- ramp in over first 25%, hold, ramp out over last 25%
		if t < 0.25 then
			return roll * (t / 0.25)
		elseif t > 0.75 then
			return roll * ((1 - t) / 0.25)
		end
		return roll
	end
	local side = roll >= 0 and -1 or 1 -- gems sit on the downhill edge line
	local gems = gemRhythmLine(
		rng,
		Tiers.speedAt(st.dist),
		length,
		0.3,
		0.5,
		side * (st.width / 2 - 2),
		Config.Gems.ValueEdge,
		nil,
		energyOf(st),
		bpmOf(st)
	)
	return spec("Tilt", st, length, function(t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = rollAt(t) }
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- Pinch: width collapses briefly mid-chunk, then reopens.
function ChunkDefs.Pinch(rng: Random, st: GenState, _tier): ChunkSpec
	local pinchW = math.max(Config.Generation.MinWidth, st.width * 0.22)
	-- The collapse's peak edge rate is (w - pinchW)*pi/(2*L) — size the
	-- chunk so it never exceeds lateral authority from an off-center entry.
	local length = math.max(
		rng:NextInteger(45, 70),
		math.ceil(latTravel((st.width - pinchW) * math.pi / 2, Tiers.speedAt(st.dist + 100)))
	)
	-- Thread the pinch for beam value.
	local gems = gemRhythmLine(
		rng,
		Tiers.speedAt(st.dist),
		length,
		0.3,
		0.45,
		0,
		Config.Gems.ValueBeam,
		nil,
		energyOf(st),
		bpmOf(st)
	)
	return spec("Pinch", st, length, function(t)
		local bump = (1 - math.cos(t * math.pi * 2)) / 2 -- 0 -> 1 -> 0, peak at t=0.5
		return {
			width = lerp(st.width, pinchW, bump),
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
		}
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- SplitGap: center channel removed -> two rails to pick between.
function ChunkDefs.SplitGap(rng: Random, st: GenState, _tier): ChunkSpec
	local rail = rng:NextNumber(Config.Generation.MinWidth, math.max(Config.Generation.MinWidth, st.width / 3))
	local cutout = math.max(st.width - rail * 2, 2)
	-- Mouth honesty (GenVerify §8.6): the worst entry is dead center — the
	-- void opens under the ball and it must reach a rail band before the
	-- floor is gone. The fade window gives it latTravel studs to do that;
	-- the chunk grows if the mouth would eat it whole.
	local speed = Tiers.speedAt(st.dist + 100)
	local mouth = latTravel(cutout / 2 + Config.Ball.Diameter / 2 + 0.75, speed)
	local length = math.max(rng:NextInteger(45, 75), math.ceil(mouth / 0.35))
	local mouthT = math.max(mouth / length, 0.15)
	local cutAt = function(t: number)
		-- fade cutout in/out at chunk ends for clean connections
		local e = math.min(t / mouthT, (1 - t) / mouthT, 1)
		return cutout * e
	end
	-- Rail-center lines from the mouth (cutout is full by t=0.15) — two
	-- diverging gold lines at the opening ARE the "pick a rail" tell;
	-- both rails share one roll so the pair reads as the same grouping.
	local railOff = cutout / 2 + rail / 2
	local size, spacing = rollRhythm(rng, Tiers.speedAt(st.dist), (GEM_BOUND - 0.18) * length, energyOf(st), bpmOf(st))
	local gems = {}
	appendAll(gems, gemLine(length, 0.18, -railOff, Config.Gems.ValueBeam, size, nil, spacing))
	appendAll(gems, gemLine(length, 0.18, railOff, Config.Gems.ValueBeam, size, nil, spacing))
	return spec("SplitGap", st, length, function(t)
		return {
			width = st.width,
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
			cutout = cutAt(t),
		}
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- Bowl: banked walls rise on both edges — a safe canyon breather.
function ChunkDefs.Bowl(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(50, 80)
	local wallH = rng:NextNumber(4, 7)
	local wallAt = function(t: number)
		local e = math.min(t / 0.2, (1 - t) / 0.2, 1)
		return wallH * e
	end
	-- Dense safe canyon — the breather pays out.
	local speed = Tiers.speedAt(st.dist)
	local gems = {}
	appendAll(
		gems,
		gemRhythmLine(rng, speed, length, 0.2, 0.35, 0, Config.Gems.ValueSafe, nil, energyOf(st), bpmOf(st))
	)
	appendAll(
		gems,
		gemRhythmLine(rng, speed, length, 0.55, 0.7, 0, Config.Gems.ValueSafe, nil, energyOf(st), bpmOf(st))
	)
	return spec("Bowl", st, length, function(t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0, wallH = wallAt(t) }
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- RampGap: launch ramp, void, lower landing strip. Speed check — entering
-- too slow means the void eats you (that's the point). Tier 5+ only.
function ChunkDefs.RampGap(_rng: Random, st: GenState, tier): ChunkSpec
	local speed = tier.speed
	local rampLen = 18
	local rampH = 8
	local gapLen = math.clamp(speed * 0.35, 18, 34) -- tuned vs launch arc (DESIGN.md §8.3)
	local landingLen = 45
	-- Phrase quantization: the launch apex (mid-gap) is the spectacle beat —
	-- stretch the run-up so the void's middle lands on the accent downbeat.
	local zAcc = studsToAccent(st)
	if zAcc then
		rampLen = math.clamp(zAcc - gapLen / 2, 12, 40)
	end
	local drop = 4
	local length = rampLen + gapLen + landingLen
	local landW = math.min(st.width * 1.3, Config.Generation.BaseWidth) -- forgiving landing
	local yLand = st.y - drop

	-- Gap-arc gems: float along the ballistic arc over the void — max risk.
	local gems = {}
	for i = 0, 3 do
		local frac = (i + 0.5) / 4
		local z = rampLen + frac * gapLen
		table.insert(gems, {
			t = z / length,
			xOff = 0,
			value = Config.Gems.ValueGapArc,
			yOff = rampH + math.sin(frac * math.pi) * 5 + 1,
		})
	end

	return spec("RampGap", st, length, function(t)
		local z = t * length
		if z < rampLen then
			-- rising ramp
			return { width = st.width, centerX = st.centerX, y = st.y + rampH * (z / rampLen), rollDeg = 0 }
		elseif z < rampLen + gapLen then
			-- void
			return { width = 0, centerX = st.centerX, y = st.y + rampH, rollDeg = 0 }
		end
		-- landing strip eases from drop back toward flat width
		local lt = (z - rampLen - gapLen) / landingLen
		return {
			width = lerp(landW, landW, lt),
			centerX = st.centerX,
			y = lerp(yLand, yLand, lt),
			rollDeg = 0,
		}
	end, { centerX = st.centerX, width = landW, y = yLand }, nil, gems)
end

-- Obstacle chunks (DESIGN.md §8.3). All obey the exit-line rule: every lethal
-- row leaves >= CorridorMin of clear deck, and rows are spaced so the player
-- gets Obstacles.ReactionTime seconds at current tier speed between reads.

-- Emit two blocks spanning the deck at t, leaving one gap >= CorridorMin.
-- Returns the blocks plus the gap center so gems can sit in the corridor.
-- The gap draw is CLAMPED into the feasible range: an unclamped draw wider
-- than the deck can host used to return {} — a silently-empty lethal row.
-- Feasible = corridor stays >= CorridorMin with >=0.5 slack of rim margin;
-- canRun's MinEntryWidth gate keeps the range non-degenerate.
local function gateRow(
	rng: Random,
	halfW: number,
	t: number,
	height: number,
	depth: number,
	lead: number,
	speed: number
): ({ Obstacle }, number?)
	local gapMax = math.min(Config.Obstacles.CorridorMin * 1.8, 2 * halfW - 5)
	if gapMax < Config.Obstacles.CorridorMin then
		return {}, nil
	end
	local gap = rng:NextNumber(Config.Obstacles.CorridorMin, gapMax)
	-- Reach-honest slot (§8.6): a ball forced to the far entry edge must
	-- still make the corridor over `lead` studs. Draw inside that bound;
	-- if the budget can't cover even a centered gap, widen it first.
	local reach = latReach(lead, speed)
	local bound = math.min(halfW - gap / 2 - 2, reach + gap / 2 - halfW)
	if bound < 0 then
		gap = math.min(gapMax, 2 * (halfW - reach))
		bound = math.min(halfW - gap / 2 - 2, reach + gap / 2 - halfW)
	end
	if bound < 0 then
		return {}, nil
	end
	local gx = rng:NextNumber(-bound, bound)
	local lw = gx - gap / 2 + halfW
	local rw = halfW - (gx + gap / 2)
	local out = {}
	if lw >= 1.5 then
		table.insert(out, { t = t, xOff = -halfW + lw / 2, w = lw, h = height, d = depth })
	end
	if rw >= 1.5 then
		table.insert(out, { t = t, xOff = gx + gap / 2 + rw / 2, w = rw, h = height, d = depth })
	end
	return out, gx
end

local function flatSection(st: GenState): (t: number) -> Section
	return function(_t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0 }
	end
end

local function rowBudget(rng: Random, tier, length: number, maxRows: number): number
	local spacing = tier.speed * Config.Obstacles.ReactionTime
	return math.clamp(rng:NextInteger(1, maxRows), 1, math.max(1, math.floor(0.6 * length / spacing)))
end

-- BlockGate: rows of red blocks with one gap each — thread it, then the next.
function ChunkDefs.BlockGate(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(50, 80)
	local halfW = st.width / 2
	local rows = rowBudget(rng, tier, length, 3)
	local obstacles = {}
	local gems = {}
	local speed = Tiers.speedAt(st.dist + 100)
	for i = 1, rows do
		local t = 0.2 + (i - 0.5) / rows * 0.6
		local row, gx =
			gateRow(rng, halfW, t, Config.Obstacles.BlockHeight, Config.Obstacles.BlockDepth, t * length, speed)
		for _, ob in ipairs(row) do
			table.insert(obstacles, ob)
		end
		-- A gem floats in the gap: the corridor you must thread pays out.
		if gx then
			table.insert(gems, { t = t, xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.5 })
		end
	end
	return spec(
		"BlockGate",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- BlockField: scattered single blocks — constant weave pressure, density rises
-- with tier via the reaction-time row budget.
function ChunkDefs.BlockField(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(55, 85)
	local halfW = st.width / 2
	local rows = rowBudget(rng, tier, length, 4)
	local obstacles = {}
	local gems = {}
	for i = 1, rows do
		local t = 0.2 + (i - 0.5) / rows * 0.6
		-- The wide flank must stay >= CorridorMin: bw <= width - CorridorMin
		-- - 1 keeps a feasible |gx| band, then gx is drawn inside it.
		local bw = rng:NextNumber(4, math.min(8, st.width * 0.3, st.width - Config.Obstacles.CorridorMin - 1))
		local xPad = bw / 2 + 1
		local gxLo = Config.Obstacles.CorridorMin + bw / 2 - halfW
		if bw < 3 or gxLo >= halfW - xPad then
			continue
		end
		local side = rng:NextInteger(0, 1) * 2 - 1
		local gx = side * rng:NextNumber(math.max(gxLo, 0), halfW - xPad)
		table.insert(obstacles, {
			t = t,
			xOff = gx,
			w = bw,
			h = Config.Obstacles.BlockHeight,
			d = Config.Obstacles.BlockDepth,
		})
		-- Near-miss gem hugging the block's flank half the time.
		if rng:NextNumber() < 0.5 then
			local gemSide = rng:NextInteger(0, 1) * 2 - 1
			table.insert(gems, { t = t, xOff = gx + gemSide * (bw / 2 + 1.6), value = Config.Gems.ValueEdge })
		end
	end
	return spec(
		"BlockField",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- WallSlot: one tall red slab wall with a single slot — commit to a lane early.
function ChunkDefs.WallSlot(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(35, 55)
	local halfW = st.width / 2
	local tWall = 0.5
	local zAcc = studsToAccent(st)
	if zAcc then
		local t = zAcc / length -- wall hits on the downbeat
		if t > 0.25 and t < 0.8 then
			tWall = t
		end
	end
	local obstacles, gx = gateRow(
		rng,
		halfW,
		tWall,
		Config.Obstacles.WallHeight,
		Config.Obstacles.WallDepth,
		tWall * length,
		Tiers.speedAt(st.dist + 100)
	)
	local gems = {}
	if gx then
		table.insert(gems, { t = tWall, xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.5 })
	end
	return spec(
		"WallSlot",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- ===================== feature-ramp chunks (DESIGN.md §8.6) =====================
-- Every feature builder takes an optional `debut` flag: the first spawn past
-- its milestone distance is a gentle showcase (wide corridors, slow cycles,
-- breadcrumb gems) that teaches the read; pool spawns after that run full
-- difficulty.

local G = 196.2 -- workspace gravity, studs/s^2

-- Wall row with the gap pinned to gx — Chicane/DropGate force alternating
-- or accent-marked corridors instead of gateRow's random placement.
local function pinnedRow(
	halfW: number,
	t: number,
	gx: number,
	gapW: number,
	height: number,
	depth: number
): { Obstacle }
	local out = {}
	local lw = gx - gapW / 2 + halfW
	local rw = halfW - (gx + gapW / 2)
	if lw >= 1.5 then
		table.insert(out, { t = t, xOff = -halfW + lw / 2, w = lw, h = height, d = depth })
	end
	if rw >= 1.5 then
		table.insert(out, { t = t, xOff = gx + gapW / 2 + rw / 2, w = rw, h = height, d = depth })
	end
	return out
end

-- Entry contract (§8.6): the narrowest live deck each type can honestly
-- fill. Below it the builder either emits a silently-empty obstacle chunk
-- (a free pass where difficulty should peak) or squeezes the ribbon under
-- Generation.MinWidth — both are generator bugs the pool routes around.
-- Widths cover the DEBUT variant too (debut gaps are wider than pool gaps).
local MinEntryWidth = {
	BlockGate = 12, -- CorridorMin(7) + ~5 rim margin; the EndlessWidthMinFloor rationale
	BlockField = 12,
	WallSlot = 12,
	DropGate = 15, -- debut gap = 1.6*CorridorMin, plus two 1.5-stud flanks
	Chicane = 15, -- debut gap = 1.7*CorridorMin, plus flanks
	SnakeField = 14, -- weave block lower bound halfW*0.45 must reach 3 studs
	SplitGap = 10, -- two MinWidth rails + a 2-stud void
	Slalom = 16, -- sway must leave a ball-width corridor under the worst phase
	Pacer = 26,
	Rotor = 23, -- center-post windmill needs arm half >= 3 with both rim lanes
	Fork = 24,
	TunnelSlot = 18,
	PressRow = 20, -- MinSpan press + a debut-wide side lane
}

-- Eligibility gate for pool + debut picks (§8.6): features that need a
-- songform context or a minimum deck width decline here instead of
-- emitting a degenerate chunk.
function ChunkDefs.canRun(name: string, st: GenState, tier): boolean
	local minW = MinEntryWidth[name]
	if minW and st.width < minW then
		return false
	end
	if name == "DropGate" then
		-- needs an accent downbeat inside the chunk, at drop energy
		local zAcc = studsToAccent(st)
		return zAcc ~= nil and zAcc >= 15 and zAcc <= 45 and energyOf(st) >= 0.8
	elseif name == "Widen" then
		-- only a real opening when there's headroom under the tier ceiling
		return st.width <= tier.widthMax - 4
	elseif name == "Blackout" then
		-- darkness only during break sections — lights out, not lights off-beat
		return st.section ~= nil and st.section.kind == "break"
	elseif name == "OrbHop" then
		return Config.Features.JumpOrbs == true
	elseif name == "FlipRide" then
		return Config.Features.GravityFlip == true
	elseif name == "Rotor" then
		-- Center-post windmill: both rims keep CorridorMin lanes and the
		-- worst entry owes ~halfW of transit — the builder grows the lead
		-- to afford it. Decline when the lead would be a degenerate runway
		-- (wide/fast decks).
		local halfW = st.width / 2
		local lead = latTravel(
			halfW - Config.Obstacles.CorridorMin + Config.Ball.Diameter / 2,
			Tiers.speedAt(st.dist + 100)
		) / 0.45
		return lead <= 2 * Config.Generation.ChunkMaxLength
	end
	return true
end

-- Terrace: the deck descends in lips instead of a smooth grade — gravity
-- pops the ball off each edge for free ballistic hops. Pure spectacle:
-- every landing is deck, never void.
function ChunkDefs.Terrace(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(50, 70)
	local steps = if debut then 2 else rng:NextInteger(3, 5)
	local stepH = if debut then 1 else rng:NextNumber(1.1, 1.8)
	local gems = {}
	-- A small arc floats just past each lip — the hop line pays out.
	for i = 1, steps - 1 do
		local t = i / steps
		if t < GEM_BOUND then
			table.insert(gems, { t = t + 0.03, xOff = 0, value = Config.Gems.ValueEdge, yOff = 2.6 })
		end
	end
	return spec("Terrace", st, length, function(t)
		return {
			width = st.width,
			centerX = st.centerX,
			y = st.y - stepH * math.floor(t * steps),
			rollDeg = 0,
		}
	end, { centerX = st.centerX, width = st.width, y = st.y - stepH * steps }, nil, gems)
end

-- Chained-row chunks (SnakeField/Chicane) size their length around the
-- row spacing instead of cramming rows into a standard chunk: at speed,
-- ReactionTime between lethal reads needs more studs than 90 of deck.
-- Chained rows of ONE repeated pattern get a 0.75x reaction window — the
-- read is already learned from the first row (DESIGN.md §8.6).
local function chainLength(wantRows: number, spacingZ: number, lo: number, hi: number): number
	return math.clamp(60 + spacingZ * (wantRows - 1), lo, hi)
end

local function chainRows(len: number, spacingZ: number, wantRows: number): number
	return math.clamp(wantRows, 1, 1 + math.floor((len * 0.7) / math.max(spacingZ, 1)))
end

-- SnakeField: single blocks flush to alternating rails — the winning line
-- is a literal zig-zag, and the breadcrumb gems draw it. Weave rows use a
-- tighter 0.5x reaction window: each block is a small one-side dodge, not
-- a full-width commit (§8.6).
function ChunkDefs.SnakeField(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	-- Size rows off the chunk-EXIT speed: speed ramps inside the chunk, so
	-- spacing built for the entry tier is already too tight at the last row.
	local spacingZ = Tiers.speedAt(st.dist + 150) * Config.Obstacles.ReactionTime * (if debut then 0.7 else 0.5)
	local length = chainLength(if debut then 3 else rng:NextInteger(4, 6), spacingZ, 80, 150)
	local rows = chainRows(length, spacingZ, 6)
	local halfW = st.width / 2
	local side = rng:NextInteger(0, 1) * 2 - 1
	local obstacles = {}
	local gems = {}
	for i = 1, rows do
		local t = 0.5 + (i - (rows + 1) / 2) * (spacingZ / length)
		-- Block hugs one edge; the far side stays a full corridor.
		local bw = math.min(rng:NextNumber(halfW * 0.45, halfW * 0.7), 2 * halfW - Config.Obstacles.CorridorMin - 0.5)
		if bw < 3 then
			break -- deck too thin to host the weave honestly
		end
		table.insert(obstacles, {
			t = t,
			xOff = side * (halfW - bw / 2),
			w = bw,
			h = Config.Obstacles.BlockHeight,
			d = Config.Obstacles.BlockDepth,
		})
		-- Corridor center is -side * bw/2: the gems literally mark the dodge.
		table.insert(gems, { t = t, xOff = -side * bw / 2, value = Config.Gems.ValueEdge, yOff = 2 })
		side = -side
	end
	return spec(
		"SnakeField",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- Chicane: tall wall rows with gaps pinned to alternating rails — an
-- S-steer under speed, the same read as WallSlot but chained.
function ChunkDefs.Chicane(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local speed = Tiers.speedAt(st.dist + 170)
	local spacingZ = speed * Config.Obstacles.ReactionTime * (if debut then 1 else 0.75)
	local length = chainLength(if debut then 2 else 3, spacingZ, 70, 170)
	local rows = chainRows(length, spacingZ, 3)
	local halfW = st.width / 2
	local side = rng:NextInteger(0, 1) * 2 - 1
	local gapW = Config.Obstacles.CorridorMin * (if debut then 1.7 else rng:NextNumber(1.1, 1.4))
	-- Reach-honest amplitude (§8.6): the alternating amplitude is bounded
	-- twice — the worst entry edge must reach the FIRST gap over its lead,
	-- and a ball inside gap i must reach gap i+1 over one spacing.
	local halfR = Config.Ball.Diameter / 2
	local t1 = 0.5 + (1 - (rows + 1) / 2) * (spacingZ / length)
	local gxAmp = math.max(
		0,
		math.min(
			halfW - gapW / 2 - 3,
			(latReach(spacingZ, speed) + gapW - 2 * halfR) / 2,
			latReach(t1 * length, speed) + gapW / 2 - halfW
		)
	)
	local obstacles = {}
	local gems = {}
	for i = 1, rows do
		local t = 0.5 + (i - (rows + 1) / 2) * (spacingZ / length)
		local gx = side * gxAmp
		for _, ob in ipairs(pinnedRow(halfW, t, gx, gapW, Config.Obstacles.WallHeight, Config.Obstacles.WallDepth)) do
			table.insert(obstacles, ob)
		end
		table.insert(gems, { t = t, xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.5 })
		side = -side
	end
	return spec(
		"Chicane",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- Fork: asymmetric SplitGap — one thin rail loaded with beam-value gems,
-- one wide bare rail that's always safe. A real route decision every time.
-- Uses the cutoutOff section field to push the void off-center.
function ChunkDefs.Fork(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(55, 80)
	local halfW = st.width / 2
	local riskSide = rng:NextInteger(0, 1) * 2 - 1 -- +1 = risk rail on the right
	local riskW = if debut then 9 else rng:NextNumber(5.5, 8)
	local cut = rng:NextNumber(st.width * 0.35, st.width * 0.5)
	local safeW = st.width - cut - riskW
	if safeW < Config.Obstacles.CorridorMin + 1 then
		safeW = Config.Obstacles.CorridorMin + 1
		cut = st.width - riskW - safeW
	end
	-- cutoutOff that leaves exactly riskW of rail on the risk side:
	-- cutout spans [off - cut/2, off + cut/2]; the risk rail is the outer
	-- slice between it and the rim.
	local off = riskSide * (halfW - riskW - cut / 2)
	-- Same mouth-honesty sizing as SplitGap: the void fades in over
	-- latTravel studs so the worst entry still reaches a rail band.
	local mouth = latTravel(cut / 2 + Config.Ball.Diameter / 2 + 0.75, Tiers.speedAt(st.dist + 100))
	length = math.max(length, math.ceil(mouth / 0.35))
	local mouthT = math.max(mouth / length, 0.15)
	local cutAt = function(t: number)
		local e = math.min(t / mouthT, (1 - t) / mouthT, 1)
		return cut * e, off * e -- fade cutout AND asymmetry at the seams
	end
	local riskX = riskSide * (halfW - riskW / 2)
	local safeX = -riskSide * (halfW - safeW / 2)
	local speed = Tiers.speedAt(st.dist)
	local gems = {}
	appendAll(
		gems,
		gemRhythmLine(rng, speed, length, 0.3, 0.7, riskX, Config.Gems.ValueBeam, nil, energyOf(st), bpmOf(st))
	)
	appendAll(
		gems,
		gemRhythmLine(rng, speed, length, 0.4, 0.6, safeX, Config.Gems.ValueSafe, nil, energyOf(st), bpmOf(st))
	)
	return spec("Fork", st, length, function(t)
		local c, o = cutAt(t)
		return {
			width = st.width,
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
			cutout = c,
			cutoutOff = o,
		}
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- PadHop (LaunchPad): a cyan pad kicks the ball ballistic over a lethal
-- strip spanning the deck. The kick is COMPUTED for the whole survivable
-- entry-speed range: the arc holds y >= H for wSec centered on the apex
-- for ANY speed — in studs that's u*[tApex ± wSec/2] — so the strip must
-- sit inside the INTERSECTION of those windows across u in
-- [SlowCrossFrac, Power.Mult]*speed, or some entry (braked, still
-- accelerating, boosted) meets an impossible arc. wSec solves that
-- intersection fixed-point (tApex depends on kick). Miss the pad, eat
-- the strip — the pad line is the solve.
function ChunkDefs.PadHop(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(45, 65)
	local padT = 0.3
	-- Arc math uses the PAD-TIME speed — that's the forward speed the ball
	-- actually carries through the flight. The audit evaluates the same
	-- point; an exit-speed model is faster and plants the strip ~a stud
	-- past the honest window's trailing edge.
	local speed = Tiers.speedAt(st.dist + padT * length)
	local speedLand = Tiers.speedAt(st.dist + length) -- exit: landing margin
	local stripD = if debut then 5 else rng:NextNumber(Config.Pads.StripMin, Config.Pads.StripMax)
	local stripH = Config.Pads.StripH
	local padW = if debut then Config.Pads.DebutWidth else Config.Pads.Width
	local padX = if debut then 0 else rng:NextNumber(-st.width / 5, st.width / 5)
	local h = stripH + Config.Pads.ArcMargin
	local span = stripD + Config.Pads.Length + 2
	local rLo = Config.Pads.SlowCrossFrac
	local rHi = Config.Power.Mult
	-- Intersection width = v*[rLo*(tA+wSec/2) - rHi*(tA-wSec/2)] must hold
	-- the whole span; iterate wSec since tA grows with the kick it forces.
	local wSec = span / speed
	local tApex = math.sqrt(2 * h / G)
	for _ = 1, 6 do
		wSec = 2 * (span / speed + tApex * (rHi - rLo)) / (rLo + rHi)
		tApex = math.sqrt(2 * (h + G * wSec * wSec / 8) / G)
	end
	local kick = G * tApex
	-- Strip centered in the intersection: its leading edge sits just inside
	-- the boosted arc's above-h opening, its trailing edge inside the slow
	-- arc's — every entry speed crosses it airborne.
	local zLo = rHi * speed * (tApex - wSec / 2)
	local zHi = rLo * speed * (tApex + wSec / 2)
	local stripZ = (zLo + zHi) / 2
	-- The kick is inviolable (closed-form clearance). If the strip or the
	-- landing wouldn't fit inside the chunk, the CHUNK grows — never the
	-- kick shrinking below what the crossing demands.
	local landZ = 2 * speedLand * tApex -- symmetric: lands back on deck level
	length = math.max(length, math.ceil(stripZ / (0.78 - padT)), math.ceil(landZ / (0.95 - padT)))
	local stripT = padT + stripZ / length
	local obstacles = { { t = stripT, xOff = 0, w = st.width - 2, h = stripH, d = stripD } }
	local gems = {}
	for i = 0, 3 do
		local f = (i + 0.5) / 4
		local t = padT + (stripT - padT) * 2 * f
		if t < GEM_BOUND then
			table.insert(
				gems,
				{ t = t, xOff = padX, value = Config.Gems.ValueGapArc, yOff = 1.2 + h * math.sin(f * math.pi) }
			)
		end
	end
	local s = spec(
		"PadHop",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
	s.pads = { { t = padT, xOff = padX, w = padW, d = Config.Pads.Length, kickY = kick } }
	return s
end

-- PadVoid: pad-assisted void crossing — the kick supplies the airtime the
-- RampGap ramp needs speed for, so gap-jump spectacle works a tier earlier.
function ChunkDefs.PadVoid(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local speed = Tiers.speedAt(st.dist)
	local apexH = if debut then 4 else 5.5
	local kick = math.sqrt(2 * G * apexH)
	local gapLen = math.clamp(speed * (2 * kick / G) * Config.Pads.VoidAirFrac, 14, 34)
	local runupLen = if debut then 24 else rng:NextInteger(14, 20)
	local landLen = 42
	local length = runupLen + gapLen + landLen
	local padW = if debut then Config.Pads.DebutWidth else Config.Pads.Width
	local padT = (runupLen - Config.Pads.Length) / length -- pad ends at the lip
	local drop = if debut then 3 else 5
	local landW = math.min(st.width * 1.25, Config.Generation.BaseWidth)
	local yLand = st.y - drop
	local gems = {}
	for i = 0, 3 do
		local f = (i + 0.5) / 4
		table.insert(gems, {
			t = (runupLen + f * gapLen) / length,
			xOff = 0,
			value = Config.Gems.ValueGapArc,
			yOff = 1 + math.sin(f * math.pi) * apexH,
		})
	end
	local s = spec("PadVoid", st, length, function(t)
		local z = t * length
		if z < runupLen then
			return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0 }
		elseif z < runupLen + gapLen then
			return { width = 0, centerX = st.centerX, y = st.y, rollDeg = 0 }
		end
		return { width = landW, centerX = st.centerX, y = yLand, rollDeg = 0 }
	end, { centerX = st.centerX, width = landW, y = yLand }, nil, gems)
	s.pads = { { t = padT, xOff = 0, w = padW, d = Config.Pads.Length, kickY = kick } }
	return s
end

-- TunnelSlot: a dark roof ribbon + neon ribs enclose the deck; hanging
-- slabs drop from the ceiling leaving one lateral corridor (the same
-- exit-line rule, read upside-down). Short decorative teeth stay well
-- above the ball — lethal to touch, unreachable by physics.
function ChunkDefs.TunnelSlot(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(55, 75)
	local roofH = Config.Tunnel.RoofH
	local halfW = st.width / 2
	local obstacles = {}
	local gems = {}
	if not debut then -- debut tube is empty: the enclosure alone is the read
		local tWall = rng:NextNumber(0.45, 0.6)
		local row, gx = gateRow(
			rng,
			halfW,
			tWall,
			roofH - 0.5,
			Config.Obstacles.WallDepth,
			tWall * length,
			Tiers.speedAt(st.dist + 100)
		)
		for _, ob in ipairs(row) do
			ob.hang = true
			table.insert(obstacles, ob)
		end
		if gx then
			table.insert(gems, { t = tWall, xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.5 })
		end
		for _ = 1, rng:NextInteger(2, 4) do
			table.insert(obstacles, {
				t = rng:NextNumber(0.2, 0.85),
				xOff = rng:NextNumber(-halfW + 3, halfW - 3),
				w = rng:NextNumber(2, 4),
				h = rng:NextNumber(Config.Tunnel.ToothMin, Config.Tunnel.ToothMax),
				d = 2,
				hang = true,
			})
		end
	end
	appendAll(
		gems,
		gemRhythmLine(
			rng,
			Tiers.speedAt(st.dist),
			length,
			0.25,
			0.4,
			0,
			Config.Gems.ValueSafe,
			nil,
			energyOf(st),
			bpmOf(st)
		)
	)
	return spec("TunnelSlot", st, length, function(t)
		local e = math.min(t / 0.18, (1 - t) / 0.18, 1)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0, roofH = roofH * e }
	end, { centerX = st.centerX, width = st.width, y = st.y }, obstacles, gems)
end

-- DropGate: a full-width wall whose gap threads ON a drop downbeat —
-- canRun gates it to accent hits at high energy, so the geometry slams
-- exactly when the music does. Breadcrumb gems lead into the gap early.
function ChunkDefs.DropGate(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(40, 60)
	local halfW = st.width / 2
	local zAcc = studsToAccent(st) or length * 0.5 -- canRun guarantees real value
	local tWall = math.clamp(zAcc / length, 0.3, 0.7)
	local gapW = Config.Obstacles.CorridorMin * (if debut then 1.6 else 1.15)
	-- Same reach bound as gateRow: the far entry edge must make the gap
	-- over the wall lead-in, not just a center entry.
	local slack = math.max(
		math.min(halfW - gapW / 2 - 2, latReach(tWall * length, Tiers.speedAt(st.dist + 100)) + gapW / 2 - halfW),
		0
	)
	local gx = rng:NextNumber(-slack, slack)
	local obstacles = pinnedRow(halfW, tWall, gx, gapW, Config.Obstacles.WallHeight + 3, Config.Obstacles.WallDepth + 1)
	local gems = {}
	for i = 0, 4 do
		table.insert(gems, { t = tWall * (0.3 + 0.16 * i), xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.2 })
	end
	return spec(
		"DropGate",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- PressRow: a low roof over the deck and ceiling presses that slam on
-- the beat (dropY motion). Each press plate spans all but one side
-- lane — the lane is the guaranteed line; rolling under the plate
-- during its lift window is the shortcut. The side zigzags per row so
-- the safe line still costs lateral commitment.
function ChunkDefs.PressRow(rng: Random, st: GenState, tier, debut: boolean?): ChunkSpec
	local halfW = st.width / 2
	-- Chained timing rows: each press needs its own reaction window —
	-- 0.75x on repeated reads, 1x on the debut showcase.
	local speed = Tiers.speedAt(st.dist + 150)
	local spacingZ = speed * Config.Obstacles.ReactionTime * (if debut then 1 else 0.75)
	local length = chainLength(if debut then 1 else rng:NextInteger(2, 3), spacingZ, 55, 130)
	local rows = chainRows(length, spacingZ, if debut then 1 else 3)
	local roofH = Config.Press.RoofH
	local liftClear = Config.Press.LiftClear
	local map = st.map or SongMap
	local beatSec = 60 / (map.bpm * MusicGrid.playbackSpeedAt(tier.speed))
	local period = beatSec * Config.Movers.PressBeats * (if debut then 1.5 else 1)
	local dropAmp = liftClear - Config.Press.SlamGap
	-- The side lane honors CorridorMin; the press keeps at least MinSpan
	-- of plate or it reads as a pillar, not a press.
	local gapW =
		math.min(Config.Obstacles.CorridorMin * (if debut then 1.6 else 1.15), 2 * halfW - Config.Press.MinSpan)
	local obstacles = {}
	local gems = {}
	if gapW >= Config.Obstacles.CorridorMin then
		-- Zigzag affordance: flipping the lane costs 2·halfW − gapW of
		-- lateral travel. When one beat-gap can't buy that crossing the
		-- lane widens; past MinSpan it holds its side instead — a held
		-- lane is a straight read, never a blind seam.
		local gapForFlip = 2 * halfW - latReach(spacingZ, speed)
		local flip = rows > 1 and gapForFlip <= 2 * halfW - Config.Press.MinSpan
		if flip then
			gapW = math.max(gapW, gapForFlip)
		end
		local side = rng:NextInteger(0, 1) * 2 - 1
		for i = 1, rows do
			local t = 0.5 + (i - (rows + 1) / 2) * (spacingZ / length)
			local pw = 2 * halfW - gapW
			table.insert(obstacles, {
				t = t,
				xOff = -side * gapW / 2, -- plate covers everything but the side lane
				w = pw,
				h = roofH - liftClear,
				d = Config.Obstacles.WallDepth,
				hang = true,
				motion = {
					kind = "dropY",
					amp = dropAmp,
					periodSec = period,
					phase = rng:NextNumber(0, math.pi * 2),
				},
			})
			-- Breadcrumbs: safe gems in the guaranteed lane, a beam gem
			-- under the plate daring the timed shortcut.
			local gx = side * (halfW - gapW / 2)
			table.insert(gems, { t = t, xOff = gx, value = Config.Gems.ValueSafe, yOff = 2 })
			table.insert(gems, {
				t = math.clamp(t - 0.08, 0.15, 0.85),
				xOff = -side * gapW / 2,
				value = Config.Gems.ValueBeam,
				yOff = 2.2,
			})
			if flip then
				side = -side
			end
		end
	end
	return spec("PressRow", st, length, function(t)
		local e = math.min(t / 0.18, (1 - t) / 0.18, 1)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0, roofH = roofH * e }
	end, { centerX = st.centerX, width = st.width, y = st.y }, obstacles, gems)
end

-- Pacer: a wall PAIR whose fixed-width gap slides side-to-side on a
-- beat-quantized sine — the corridor never closes, it just moves, so the
-- dodge is "cross on the right count". Slabs overhang the rim so the gap
-- keeps its width at any offset.
function ChunkDefs.Pacer(rng: Random, st: GenState, tier, debut: boolean?): ChunkSpec
	local length = rng:NextInteger(50, 75)
	local halfW = st.width / 2
	local gapW = Config.Obstacles.CorridorMin + (if debut then 3 else 1)
	local rows = rowBudget(rng, tier, length, if debut then 1 else 2)
	local map = st.map or SongMap
	local beatSec = 60 / (map.bpm * MusicGrid.playbackSpeedAt(tier.speed))
	local period = beatSec * Config.Movers.PacerBeats * (if debut then 2 else 1)
	-- Rest offset c stays under 40% of max amp so the sliding gap never
	-- reaches a rim: |c| + amp + gapW/2 <= halfW - rimMargin.
	local maxAmp = math.max((halfW - gapW / 2 - Config.Movers.PacerRimMargin) / 1.4, 1)
	local span = st.width + 8
	local obstacles = {}
	local gems = {}
	for i = 1, rows do
		local t = 0.25 + (i - 0.5) / rows * 0.5
		local c = rng:NextNumber(-0.4 * maxAmp, 0.4 * maxAmp)
		local phase = rng:NextNumber(0, math.pi * 2)
		local motion =
			{ kind = "slideX", amp = maxAmp * (if debut then 0.55 else 1), periodSec = period, phase = phase }
		for _, s in ipairs({ -1, 1 }) do
			table.insert(obstacles, {
				t = t,
				xOff = c + s * (gapW / 2 + span / 2),
				w = span,
				h = Config.Obstacles.WallHeight - 1,
				d = Config.Obstacles.WallDepth,
				motion = motion,
			})
		end
		table.insert(gems, { t = t, xOff = c, value = Config.Gems.ValueBeam, yOff = 2.5 })
	end
	return spec(
		"Pacer",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- Rotor: a near-center lethal post with a spinning bar — the swept disc
-- can't reach EITHER rim, so both rails are always-clear lanes and the
-- worst entry (mid-deck) only owes ~halfW of transit, not a full-deck
-- cross. Gems inside the sweep zone dare you to time it anyway.
function ChunkDefs.Rotor(rng: Random, st: GenState, tier, debut: boolean?): ChunkSpec
	local halfW = st.width / 2
	local postX = rng:NextNumber(-Config.Movers.RotorPostJitter, Config.Movers.RotorPostJitter) * halfW
	-- Disc must stop CorridorMin short of both rims; canRun requires a
	-- meaningful arm (>= 3 half-length) or the windmill is a stub.
	local armHalf = math.min(halfW * Config.Movers.RotorArmFrac, halfW - Config.Obstacles.CorridorMin - math.abs(postX))
	-- Reach-honest lead (§8.6): worst entry is near the post, ~armHalf +
	-- ball radius from the nearest rim lane. The chunk grows until the
	-- shortest rotor lead (tRot = 0.45) affords that transit.
	local transit = math.max(armHalf + Config.Ball.Diameter / 2 - math.abs(postX), 0)
	local length = math.max(rng:NextInteger(45, 65), math.ceil(latTravel(transit, Tiers.speedAt(st.dist + 100)) / 0.45))
	local map = st.map or SongMap
	local beatSec = 60 / (map.bpm * MusicGrid.playbackSpeedAt(tier.speed))
	local period = beatSec * Config.Movers.RotorBeats * (if debut then 1.5 else 1)
	local tRot = rng:NextNumber(0.45, 0.6)
	local obstacles = {
		{ t = tRot, xOff = postX, w = 1.8, h = Config.Movers.RotorPostH, d = 1.8 },
		{
			t = tRot,
			xOff = postX,
			w = armHalf * 2,
			h = Config.Movers.RotorArmH,
			d = 1.1,
			motion = { kind = "spin", periodSec = period, phase = rng:NextNumber(0, math.pi * 2) },
		},
	}
	-- Bait: gems inside the swept radius — worth beam value for a reason.
	local gems = {}
	for _ = 0, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = armHalf * rng:NextNumber(0.4, 0.8)
		table.insert(gems, {
			t = math.clamp(tRot + rng:NextNumber(-0.06, 0.06), 0.15, 0.85),
			xOff = postX + math.cos(a) * r,
			value = Config.Gems.ValueBeam,
			yOff = 2.2,
		})
	end
	return spec(
		"Rotor",
		st,
		length,
		flatSection(st),
		{ centerX = st.centerX, width = st.width, y = st.y },
		obstacles,
		gems
	)
end

-- Blackout: break-section darkness — same Flat geometry, but grid/center
-- neon dims to near-black (spec.dim) while edge rails and gems stay lit.
function ChunkDefs.Blackout(rng: Random, st: GenState, tier, _debut): ChunkSpec
	local target = math.clamp(
		rng:NextNumber(tier.widthMin, tier.widthMax),
		Config.Generation.MinWidth,
		Config.Generation.BaseWidth
	)
	local length = math.max(
		rng:NextInteger(55, 85),
		math.ceil(latTravel(math.max(st.width - target, 0) / 2, Tiers.speedAt(st.dist + 100)))
	)
	local gems = gemRhythmLine(
		rng,
		Tiers.speedAt(st.dist),
		length,
		0.2,
		0.7,
		0,
		Config.Gems.ValueSafe,
		nil,
		energyOf(st),
		bpmOf(st)
	)
	local s = spec("Blackout", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y }, nil, gems)
	s.dim = true
	return s
end

-- ===================== stretch features (§8.6, flag-off) =====================

-- OrbHop (Features.JumpOrbs): a pad lobs the ball over a void sized so the
-- pad arc alone lands INSIDE the gap — the lime orb mid-flight is the only
-- way across (GD's orb-or-die). kick1 puts the arc apex on the orb; kick2
-- (the tap) carries the remaining distance to the landing. The audit
-- simulates both arcs — see GenVerify.
function ChunkDefs.OrbHop(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local speed = Tiers.speedAt(st.dist + 140) -- exit speed: conservative
	local grade = Config.Generation.Grade
	local padZ = 18
	local lipZ = padZ + 10
	local orbD = lipZ + 18 - padZ -- orb floats 18 studs into the gap
	-- kick1 places the arc apex exactly on the orb: apex at d means
	-- tApex = d/speed = kick1/G -> kick1 = G*d/speed.
	local kick1 = G * orbD / speed
	local apexH = kick1 * kick1 / (2 * G)
	local drop = if debut then 3 else rng:NextNumber(4, 6)
	-- Grade-aware arc-1 landing: applyGrade drops the deck grade*z more,
	-- so the true fall pad->landing lip is drop + grade*u where u is the
	-- pad->lip distance. Solve u = speed*(k1+sqrt(k1^2+2G(drop+grade·u)))/G
	-- as a quadratic in u.
	local A = G / (speed * speed)
	local B = -(2 * kick1 / speed + 2 * grade)
	local C = -2 * drop
	local u = (-B + math.sqrt(B * B - 4 * A * C)) / (2 * A)
	-- The landing lip sits 6 studs PAST where the pad arc reaches deck
	-- level: orb-or-die by construction (the audit asserts arc-1 cannot
	-- clear the gap alone).
	local gapLen = math.max(u + padZ - lipZ + 6, 30)
	-- kick2 (the orb tap) must cover orb -> landing lip + margin. If the
	-- fixed KickH kick can't reach, push the orb deeper into the gap so
	-- the remaining distance shrinks (mandatory margin is preserved).
	local kick2 = math.sqrt(2 * G * Config.Orbs.KickH)
	-- remaining = u + 6 - orbD (lip is padZ+u+6; orb is padZ+orbD), and u
	-- grows ~2*orbD — so a short reach is fixed by pulling the orb CLOSER
	-- to the lip. Iterate: each step shrinks remaining ~the deficit.
	for _ = 1, 4 do
		local remaining = u + 6 - orbD
		local orbDropH = apexH + drop + grade * remaining -- conservative
		local t2 = (kick2 + math.sqrt(kick2 * kick2 + 2 * G * orbDropH)) / G
		if speed * t2 >= remaining * 1.08 or orbD <= lipZ + 10 - padZ then
			break
		end
		orbD = math.max(orbD - (remaining * 1.08 - speed * t2) / 1.08, lipZ + 10 - padZ)
		kick1 = G * orbD / speed
		apexH = kick1 * kick1 / (2 * G)
		B = -(2 * kick1 / speed + 2 * grade)
		u = (-B + math.sqrt(B * B - 4 * A * C)) / (2 * A)
		gapLen = math.max(u + padZ - lipZ + 6, 30)
	end
	local landLen = 45
	local length = lipZ + gapLen + landLen
	local padT = padZ / length
	local gems = {}
	for i = 0, 3 do
		local f = (i + 0.5) / 4
		table.insert(gems, {
			t = (lipZ + f * gapLen) / length,
			xOff = 0,
			value = Config.Gems.ValueGapArc,
			yOff = 2 + apexH * math.sin(f * math.pi),
		})
	end
	local s = spec("OrbHop", st, length, function(t)
		local z = t * length
		if z < lipZ then
			return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0 }
		elseif z < lipZ + gapLen then
			return { width = 0, centerX = st.centerX, y = st.y, rollDeg = 0 }
		end
		return {
			width = math.min(st.width * 1.3, Config.Generation.BaseWidth),
			centerX = st.centerX,
			y = st.y - drop,
			rollDeg = 0,
		}
	end, {
		centerX = st.centerX,
		width = math.min(st.width * 1.3, Config.Generation.BaseWidth),
		y = st.y - drop,
	}, nil, gems)
	s.pads = {
		{
			t = padT,
			xOff = 0,
			w = if debut then Config.Pads.DebutWidth else Config.Pads.Width,
			d = Config.Pads.Length,
			kickY = kick1,
		},
	}
	-- orb.yOff is relative to the graded void plane at orb.t, which sits
	-- grade*orbD below the pad deck — add it back so the orb physically
	-- rests ON the arc apex (tap window centered on the flight path).
	s.orbs = {
		{
			t = (padZ + orbD) / length,
			xOff = 0,
			yOff = apexH + grade * orbD,
			kickY = kick2,
			radius = Config.Orbs.Radius,
		},
	}
	return s
end

-- FlipRide (Features.GravityFlip): portal-framed zone where the client
-- holds vY=+Flip.Lift — the ball rises to a collide ceiling ribbon and
-- rides its underside, controls mirrored. Zone end -> gravity resumes and
-- the ball drops Flip.ClearH back to the deck. No obstacles inside: the
-- ride itself is the read.
function ChunkDefs.FlipRide(rng: Random, st: GenState, _tier, debut: boolean?): ChunkSpec
	local length = if debut then 90 else rng:NextInteger(70, 100)
	local t0, t1 = 0.3, 0.78
	local clearH = Config.Flip.ClearH
	local speed = Tiers.speedAt(st.dist + length)
	local gems = {}
	-- Gems ride the ceiling line — the payout is the flip itself.
	appendAll(
		gems,
		gemRhythmLine(
			rng,
			speed,
			length,
			t0 + 0.08,
			t1 - 0.08,
			0,
			Config.Gems.ValueBeam,
			clearH - 1.5,
			energyOf(st),
			bpmOf(st)
		)
	)
	local s = spec("FlipRide", st, length, flatSection(st), {
		centerX = st.centerX,
		width = st.width,
		y = st.y,
	}, nil, gems)
	s.flip = { t0 = t0, t1 = t1, clearH = clearH }
	return s
end

return ChunkDefs
