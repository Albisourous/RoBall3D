--!strict
-- Seed flavor (DESIGN.md §8.7): each run seed derives ONE mutator record —
-- pure weight multipliers over the songform chunk pick, never geometry,
-- contracts, or pacing. Deterministic per seed, so the daily's flavor is
-- identical for every rider that day. GenCore consumes .fams/.types; the
-- UI reads .label (nil on `standard` — a vanilla seed advertises nothing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

export type Flavor = {
	id: string,
	label: string?,
	fams: { [string]: number },
	types: { [string]: number },
	width: number, -- tier width-window multiplier (1 = no shape bias)
}

local Mutator = {}

function Mutator.forSeed(seed: number): Flavor
	local M = Config.Mutators
	local rng = Random.new(seed + M.Salt)
	local id = M.Order[rng:NextInteger(1, #M.Order)]
	local m = M.List[id]
	return {
		id = id,
		label = m.label,
		fams = m.fams or {},
		types = m.types or {},
		width = m.width or 1,
	}
end

return Mutator
