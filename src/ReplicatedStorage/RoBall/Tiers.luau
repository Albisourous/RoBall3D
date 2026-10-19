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
	return best
end

function Tiers.speedAt(dist: number): number
	return math.min(Tiers.forDistance(dist).speed, Config.Speed.Max)
end

return Tiers
