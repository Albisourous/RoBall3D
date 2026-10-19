--!strict
-- Distance -> tier lookup, shared by server (generation) and client
-- (speed pacing). Pure; driven by Config.Tiers.

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

function Tiers.forDistance(dist: number): TierDef
	local best = Config.Tiers[1] :: TierDef
	for _, t in ipairs(Config.Tiers) do
		if dist >= t.dist then
			best = t :: TierDef
		else
			break
		end
	end
	-- Endless mode (DESIGN.md §9): past the last listed tier, difficulty
	-- never plateaus — speed ramps linearly forever and the width window
	-- keeps shrinking toward its floors. Same chunk pool; the pool's
	-- existing breadth plus collapsing reaction time does the work.
	local last = Config.Tiers[#Config.Tiers] :: TierDef
	if best == last and dist > last.dist then
		local over = dist - last.dist
		local s = Config.Speed
		return {
			index = last.index,
			dist = last.dist,
			speed = last.speed + over * s.EndlessRamp,
			chunkPool = last.chunkPool,
			widthMin = math.max(s.EndlessWidthMinFloor, last.widthMin - over * s.EndlessWidthShrink),
			widthMax = math.max(s.EndlessWidthMaxFloor, last.widthMax - over * s.EndlessWidthShrink),
		}
	end
	return best
end

function Tiers.speedAt(dist: number): number
	-- Uncapped by design: Config.Speed.Max only bounds normalization norms.
	return Tiers.forDistance(dist).speed
end

return Tiers
