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

export type GenState = {
	zEnd: number,
	centerX: number,
	width: number,
	y: number,
	dist: number,
	rng: Random,
}

export type Section = {
	width: number,
	centerX: number,
	y: number,
	rollDeg: number,
	cutout: number?,
	wallH: number?,
}

export type ChunkSpec = {
	type: string,
	length: number,
	startZ: number,
	section: (t: number) -> Section,
	endState: { centerX: number, width: number, y: number },
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
	endState: { centerX: number, width: number, y: number }
): ChunkSpec
	local graded = applyGrade(length, section)
	local gradedEnd =
		{ centerX = endState.centerX, width = endState.width, y = endState.y - Config.Generation.Grade * length }
	return { type = name, length = length, startZ = st.zEnd, section = graded, endState = gradedEnd }
end

-- Flat: plain ribbon; width may drift toward a random in-tier target.
function ChunkDefs.Flat(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(40, 70)
	local target = math.clamp(
		rng:NextNumber(tier.widthMin, tier.widthMax),
		Config.Generation.MinWidth,
		Config.Generation.BaseWidth
	)
	return spec("Flat", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y })
end

-- Slalom: constant width, centerline sways sinusoidally.
function ChunkDefs.Slalom(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(50, 90)
	local amp = rng:NextNumber(6, math.min(14, tier.widthMax / 2))
	local periods = rng:NextNumber(0.7, 1.4)
	local phase = rng:NextNumber(0, math.pi * 2)
	local center = function(t: number)
		return st.centerX + amp * math.sin(phase + t * periods * math.pi * 2)
	end
	return spec("Slalom", st, length, function(t)
		return { width = st.width, centerX = center(t), y = st.y, rollDeg = 0 }
	end, { centerX = center(1), width = st.width, y = st.y })
end

-- Narrow: width eases toward a (usually smaller) target.
function ChunkDefs.Narrow(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(35, 60)
	local upper = math.min(st.width, tier.widthMax)
	local lower = math.max(tier.widthMin, Config.Generation.MinWidth)
	local target = rng:NextNumber(lower, math.max(lower, upper))
	return spec("Narrow", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y })
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
	return spec("Tilt", st, length, function(t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = rollAt(t) }
	end, { centerX = st.centerX, width = st.width, y = st.y })
end

-- Pinch: width collapses briefly mid-chunk, then reopens.
function ChunkDefs.Pinch(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(45, 70)
	local pinchW = math.max(2.5, tier.widthMin - 3)
	return spec("Pinch", st, length, function(t)
		local bump = (1 - math.cos(t * math.pi * 2)) / 2 -- 0 -> 1 -> 0, peak at t=0.5
		return {
			width = lerp(st.width, pinchW, bump),
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
		}
	end, { centerX = st.centerX, width = st.width, y = st.y })
end

-- SplitGap: center channel removed -> two rails to pick between.
function ChunkDefs.SplitGap(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(45, 75)
	local rail = rng:NextNumber(3, math.max(3, st.width / 3))
	local cutout = math.max(st.width - rail * 2, 2)
	local cutAt = function(t: number)
		-- fade cutout in/out at chunk ends for clean connections
		local e = math.min(t / 0.15, (1 - t) / 0.15, 1)
		return cutout * e
	end
	return spec("SplitGap", st, length, function(t)
		return {
			width = st.width,
			centerX = st.centerX,
			y = st.y,
			rollDeg = 0,
			cutout = cutAt(t),
		}
	end, { centerX = st.centerX, width = st.width, y = st.y })
end

-- Bowl: banked walls rise on both edges — a safe canyon breather.
function ChunkDefs.Bowl(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(50, 80)
	local wallH = rng:NextNumber(4, 7)
	local wallAt = function(t: number)
		local e = math.min(t / 0.2, (1 - t) / 0.2, 1)
		return wallH * e
	end
	return spec("Bowl", st, length, function(t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = 0, wallH = wallAt(t) }
	end, { centerX = st.centerX, width = st.width, y = st.y })
end

-- RampGap: launch ramp, void, lower landing strip. Speed check — entering
-- too slow means the void eats you (that's the point). Tier 5+ only.
function ChunkDefs.RampGap(_rng: Random, st: GenState, tier): ChunkSpec
	local speed = tier.speed
	local rampLen = 18
	local rampH = 8
	local gapLen = math.clamp(speed * 0.35, 18, 34) -- tuned vs launch arc (DESIGN.md §8.3)
	local landingLen = 45
	local drop = 4
	local length = rampLen + gapLen + landingLen
	local landW = math.min(st.width * 1.3, Config.Generation.BaseWidth) -- forgiving landing
	local yLand = st.y - drop

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
	end, { centerX = st.centerX, width = landW, y = yLand })
end

return ChunkDefs
