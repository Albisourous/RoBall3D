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
	obstacles: { Obstacle }?,
	gems: { GemSpot }?,
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
local function gemLine(
	length: number,
	t0: number,
	xOff: number,
	value: number,
	count: number,
	yOff: number?
): { GemSpot }
	local out = {}
	for i = 1, count do
		local t = t0 + (i - 1) * Config.Gems.Spacing / length
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

-- Flat: plain ribbon; width may drift toward a random in-tier target.
-- Gems: safe center lines or edge-rail lines (riskier, worth more).
function ChunkDefs.Flat(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(40, 70)
	local target = math.clamp(
		rng:NextNumber(tier.widthMin, tier.widthMax),
		Config.Generation.MinWidth,
		Config.Generation.BaseWidth
	)
	local gems = {}
	local clusters = rng:NextInteger(Config.Gems.ClustersPerChunkMin, Config.Gems.ClustersPerChunkMax)
	for _ = 1, clusters do
		local edge = rng:NextNumber() < 0.5
		local halfW = math.max(st.width, target) / 2
		local xOff = if edge then (rng:NextInteger(0, 1) * 2 - 1) * (halfW - 2) else 0
		appendAll(
			gems,
			gemLine(
				length,
				rng:NextNumber(0.15, 0.7),
				xOff,
				edge and Config.Gems.ValueEdge or Config.Gems.ValueSafe,
				Config.Gems.ClusterSize
			)
		)
	end
	return spec("Flat", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
	end, { centerX = st.centerX, width = target, y = st.y }, nil, gems)
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
	-- xOff=0 rides the swaying centerline — following gems teaches the curve.
	local gems = gemLine(length, rng:NextNumber(0.2, 0.5), 0, Config.Gems.ValueSafe, Config.Gems.ClusterSize)
	return spec("Slalom", st, length, function(t)
		return { width = st.width, centerX = center(t), y = st.y, rollDeg = 0 }
	end, { centerX = center(1), width = st.width, y = st.y }, nil, gems)
end

-- Narrow: width eases toward a (usually smaller) target.
function ChunkDefs.Narrow(rng: Random, st: GenState, tier): ChunkSpec
	local length = rng:NextInteger(35, 60)
	local upper = math.min(st.width, tier.widthMax)
	local lower = math.max(tier.widthMin, Config.Generation.MinWidth)
	local target = rng:NextNumber(lower, math.max(lower, upper))
	-- Beam line down the narrowing middle — the risky but rewarding line.
	local gems = gemLine(length, rng:NextNumber(0.3, 0.6), 0, Config.Gems.ValueBeam, Config.Gems.ClusterSize)
	return spec("Narrow", st, length, function(t)
		return { width = lerp(st.width, target, t), centerX = st.centerX, y = st.y, rollDeg = 0 }
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
	local gems = gemLine(
		length,
		rng:NextNumber(0.3, 0.5),
		side * (st.width / 2 - 2),
		Config.Gems.ValueEdge,
		Config.Gems.ClusterSize
	)
	return spec("Tilt", st, length, function(t)
		return { width = st.width, centerX = st.centerX, y = st.y, rollDeg = rollAt(t) }
	end, { centerX = st.centerX, width = st.width, y = st.y }, nil, gems)
end

-- Pinch: width collapses briefly mid-chunk, then reopens.
function ChunkDefs.Pinch(rng: Random, st: GenState, _tier): ChunkSpec
	local length = rng:NextInteger(45, 70)
	local pinchW = math.max(3, st.width * 0.22)
	-- Thread the pinch for beam value.
	local gems = gemLine(length, 0.4, 0, Config.Gems.ValueBeam, Config.Gems.ClusterSize)
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
	local length = rng:NextInteger(45, 75)
	local rail = rng:NextNumber(3, math.max(3, st.width / 3))
	local cutout = math.max(st.width - rail * 2, 2)
	local cutAt = function(t: number)
		-- fade cutout in/out at chunk ends for clean connections
		local e = math.min(t / 0.15, (1 - t) / 0.15, 1)
		return cutout * e
	end
	-- Rail-center lines through the middle where the split is full.
	local railOff = cutout / 2 + rail / 2
	local gems = {}
	appendAll(gems, gemLine(length, 0.35, -railOff, Config.Gems.ValueBeam, 2))
	appendAll(gems, gemLine(length, 0.35, railOff, Config.Gems.ValueBeam, 2))
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
	local gems = {}
	appendAll(gems, gemLine(length, 0.25, 0, Config.Gems.ValueSafe, Config.Gems.ClusterSize))
	appendAll(gems, gemLine(length, 0.55, 0, Config.Gems.ValueSafe, Config.Gems.ClusterSize))
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
local function gateRow(rng: Random, halfW: number, t: number, height: number, depth: number): ({ Obstacle }, number?)
	local gap = rng:NextNumber(Config.Obstacles.CorridorMin, Config.Obstacles.CorridorMin * 1.8)
	local slack = halfW - gap / 2 - 2 -- keep blocks off the rim; rim death stays an edge death
	if slack < 0.5 then
		return {}, nil
	end
	local gx = rng:NextNumber(-slack, slack)
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
	for i = 1, rows do
		local t = 0.2 + (i - 0.5) / rows * 0.6
		local row, gx = gateRow(rng, halfW, t, Config.Obstacles.BlockHeight, Config.Obstacles.BlockDepth)
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
		local bw = rng:NextNumber(4, math.min(8, st.width * 0.3))
		local xPad = bw / 2 + 1
		if halfW - xPad < 0.5 then
			continue
		end
		local gx = rng:NextNumber(-(halfW - xPad), halfW - xPad)
		table.insert(obstacles, {
			t = t,
			xOff = gx,
			w = bw,
			h = Config.Obstacles.BlockHeight,
			d = Config.Obstacles.BlockDepth,
		})
		-- Near-miss gem hugging the block's flank half the time.
		if rng:NextNumber() < 0.5 then
			local side = rng:NextInteger(0, 1) * 2 - 1
			table.insert(gems, { t = t, xOff = gx + side * (bw / 2 + 1.6), value = Config.Gems.ValueEdge })
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
	local obstacles, gx = gateRow(rng, halfW, 0.5, Config.Obstacles.WallHeight, Config.Obstacles.WallDepth)
	local gems = {}
	if gx then
		table.insert(gems, { t = 0.5, xOff = gx, value = Config.Gems.ValueBeam, yOff = 2.5 })
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

return ChunkDefs
