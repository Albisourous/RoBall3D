--!strict
-- Distance -> tier lookup, shared by server (generation) and client
-- (speed pacing). Pure; driven by Config.Tiers.
-- Speed itself is NOT a tier column — it's the log curve in
-- Tiers.speedAt (Config.Speed): gentler early, forever-rising but
-- slower than linear. forDistance attaches it to the returned tier so
-- `tier.speed` stays the single read for every consumer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

local Tiers = {}

export type TierDef = {
	dist: number,
	speed: number,
	chunkPool: { string },
	widthMin: number,
	widthMax: number,
	index: number,
}

for i, t in ipairs(Config.Tiers) do
	(t :: any).index = i
end

function Tiers.speedAt(dist: number): number
	-- Uncapped by design: Config.Speed.Max only bounds normalization
	-- norms. The curve is the whole ramp — no per-tier steps, no linear
	-- tail: Start + K * ln(1 + d/D).
	local s = Config.Speed
	return s.Start + s.LogGain * math.log(1 + dist / s.LogDist)
end

function Tiers.forDistance(dist: number): TierDef
	local best = Config.Tiers[1] :: TierDef
	for _, t in ipairs(Config.Tiers) do
		if dist >= t.dist then
			best = t :: TierDef
		else
			break
		end
	end
	-- Endless mode (DESIGN.md §9): past the last listed tier, the width
	-- window keeps shrinking toward its floors. Speed needs no tail
	-- clause — the log curve already climbs forever.
	local last = Config.Tiers[#Config.Tiers] :: TierDef
	local out = table.clone(best :: any)
	out.speed = Tiers.speedAt(dist)
	if best == last and dist > last.dist then
		local over = dist - last.dist
		local s = Config.Speed
		out.widthMin = math.max(s.EndlessWidthMinFloor, last.widthMin - over * s.EndlessWidthShrink)
		out.widthMax = math.max(s.EndlessWidthMaxFloor, last.widthMax - over * s.EndlessWidthShrink)
	end
	return out
end

return Tiers
