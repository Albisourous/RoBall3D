--!strict
-- Distance -> tier lookup, shared by server (generation) and client
-- (speed pacing). Pure; driven by Config.Tiers.
-- Speed itself is NOT a tier column — it's the hybrid log+linear curve
-- in Tiers.speedAt (Config.Speed): gentle early, linear endless tail,
-- never capped. forDistance attaches it to the returned tier so
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
	-- norms. Hybrid curve — log through LinearKnee (the tuned early
	-- milestones), then a linear tail that never decelerates: Start +
	-- K * ln(1 + min(d,Knee)/D) + TailGain * max(0, d - Knee).
	local s = Config.Speed
	local curve = s.Start + s.LogGain * math.log(1 + math.min(dist, s.LinearKnee) / s.LogDist)
	return curve + math.max(0, dist - s.LinearKnee) * s.TailGain
end

-- Scan-only variant (PERFORMANCE.md §1): per-frame callers that only need
-- the tier number skip forDistance's table.clone + endless-floor math.
function Tiers.indexAt(dist: number): number
	local best = 1
	for i, t in ipairs(Config.Tiers) do
		if dist >= t.dist then
			best = i
		else
			break
		end
	end
	return best
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
	-- floor keeps tightening toward its floor — the ceiling never does:
	-- widthMax stays pinned so the deep game always spans the full
	-- floor-to-full-width window. Speed needs no tail clause — the
	-- curve's linear tail already climbs forever.
	local last = Config.Tiers[#Config.Tiers] :: TierDef
	local out = table.clone(best :: any)
	out.speed = Tiers.speedAt(dist)
	if best == last and dist > last.dist then
		local over = dist - last.dist
		local s = Config.Speed
		out.widthMin = math.max(s.EndlessWidthMinFloor, last.widthMin - over * s.EndlessWidthShrink)
	end
	return out
end

return Tiers
