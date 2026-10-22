--!strict
-- GemTypes (DESIGN.md §8.4): a pickup's worth IS its silhouette — each
-- value tier renders a distinct neon shape in a warm-family tint so the
-- payoff telegraphs at speed (small gold chip → fat white-hot crown).
-- One module owns the geometry: TrackStreamer builds the real pickups
-- with it and the client's GemFx pops the collected gem's ghost in the
-- same shape and tint. Recipes live in Config.Gems.Kinds (§AGENTS: all
-- tunables in Config).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

local GemTypes = {}

-- The corner-balanced cube pose every "diamond" silhouette shares —
-- 35.26° pitch + 45° yaw puts a vertex straight up, so a plain cube
-- reads as a hexagonal gem at speed.
local CORNER = CFrame.Angles(math.rad(35.264), math.rad(45), 0)

local function tierOf(value: number): any
	return (Config.Gems.Kinds :: any)[value] or (Config.Gems.Kinds :: any)[Config.Gems.ValueSafe]
end

local function unpack(tier: any, recipe: any): (string, number, Color3)
	return recipe.shape, (recipe.size or 1) * Config.Gems.Size, tier.color
end

-- Deterministic per-spot shape pick: a hash of the emitted spec
-- (chunk startZ, spot t) — NOT rng — so a seed replays the same mix
-- every run without touching the generator stream (§6 purity: this is
-- render-only, it never feeds back into generation or scoring).
function GemTypes.pick(value: number, startZ: number, t: number): (string, number, Color3)
	local tier = tierOf(value)
	local i = math.abs(math.floor(startZ * 7 + t * 997)) % #tier.shapes + 1
	return unpack(tier, tier.shapes[i])
end

-- "ball" pickup style (§18 world_sky / APE BALL): every pickup becomes a
-- banana-yellow capsule orb. The tier's lead size still scales it, so
-- worth keeps telegraphing at speed even with one shape across tiers.
function GemTypes.ball(value: number): (string, number, Color3)
	local tier = tierOf(value)
	local scale = tier.shapes[1].size or 1
	return "orb", scale * Config.Gems.Size, Config.Gems.BallStyleColor
end

-- The recipe for a specific shape — GemFx resolves the collected gem's
-- RoBallGemShape attribute through this so the pop ghost matches what
-- was actually picked up, and TrackStreamer renders a skin-pinned
-- silhouette through it. Unknown shapes fall back to the tier's first.
function GemTypes.of(value: number, shape: string?): (string, number, Color3)
	local tier = tierOf(value)
	if shape then
		for _, r in ipairs(tier.shapes) do
			if r.shape == shape then
				return unpack(tier, r)
			end
		end
		-- Styled pickups stamp shapes outside their tier's own list
		-- (world_sky's "ball" style orbs every tier) — honor the stamped
		-- silhouette at the tier's lead scale so the ghost still matches.
		return shape, (tier.shapes[1].size or 1) * Config.Gems.Size, tier.color
	end
	return unpack(tier, tier.shapes[1])
end

-- Apply a silhouette to a bare Part: Shape/Size, and the pose's local
-- rotation. The caller owns the world CFrame — hover heights and section
-- math stay in the streamer.
function GemTypes.pose(p: Part, shape: string, s: number): CFrame
	if shape == "orb" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * s
		return CFrame.new()
	end
	if shape == "coin" then
		-- Cylinder's axis is X; yaw 90° turns it to Z so the disc faces
		-- the ball head-on — the classic arcade token read.
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(s * 0.4, s * 1.15, s * 1.15)
		return CFrame.Angles(0, math.rad(90), 0)
	end
	if shape == "shard" then
		-- Tall thin corner-balanced obelisk — a crystal spike. (A standing
		-- Wedge was tried: it always reads as a ramp, never a gem.)
		p.Size = Vector3.new(s * 0.5, s * 1.6, s * 0.5)
		return CORNER
	end
	if shape == "rod" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(s * 1.7, s * 0.45, s * 0.45)
		return CFrame.Angles(0, 0, math.rad(90)) -- axis X→Y: standing bar
	end
	-- "diamond" + "crown": the corner-balanced cube silhouette (crown
	-- just carries the tier's fatter scale).
	p.Size = Vector3.one * s
	return CORNER
end

return GemTypes
