--!strict
-- BallDress (DESIGN.md §18): builds the vaporwave ball — near-black core,
-- five engine-rendered wireframe rings (3 axial + 2 diagonal), attachments
-- + slim trail — from a skin/trail item pair. Shared so the server's
-- spawnBall and the client's menu preview dress identically; `scale`
-- renders the preview oversize.

local Config = require(script.Parent.Config)
local Cosmetics = require(script.Parent.Cosmetics)

local BallDress = {}

local RING_ROTS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(math.rad(45), 0, math.rad(90)),
	CFrame.Angles(math.rad(-45), 0, math.rad(90)),
}

local CORE_DEFAULT = Color3.fromRGB(4, 8, 6)

export type Dressed = {
	rings: { CylinderHandleAdornment },
	trail: Trail,
}

-- Dress a bare Ball part. Rings get a RingGroup attribute ("A"/"B") so
-- retint can re-paint without relying on child order. `hues` carries the
-- resolved COLOR LAB channel colors for customA/B/C params (§18).
function BallDress.dress(ball: BasePart, skin: any?, trailItem: any?, scale: number?, hues: Cosmetics.Hues?): Dressed
	local s = scale or 1
	local d = Config.Ball.Diameter * s
	local ringA = Cosmetics.colorOf(skin and skin.ringA, Config.Art.RingA, hues)
	local ringB = Cosmetics.colorOf(skin and skin.ringB, Config.Art.RingB, hues)
	ball.Color = (skin and skin.core) or CORE_DEFAULT

	local rings = {}
	for i, rot in ipairs(RING_ROTS) do
		local group = if i <= 3 then "A" else "B"
		local ring = Instance.new("CylinderHandleAdornment")
		ring.Adornee = ball
		ring.CFrame = rot
		ring.Radius = d / 2 + 0.08 * s
		ring.Height = 0.14 * s
		ring.Color3 = if i <= 3 then ringA else ringB
		ring:SetAttribute("RingGroup", group)
		ring.Parent = ball
		table.insert(rings, ring)
	end

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, d * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -d * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = Config.Art.TrailLifetime
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Cosmetics.colorOf(trailItem and trailItem.color, nil, hues))
	trail.Transparency = NumberSequence.new(0.5, 1)
	trail.WidthScale = NumberSequence.new(0.35, 0.05)
	trail.Parent = ball

	return { rings = rings, trail = trail }
end

-- Re-paint a live ball after an equip change (server-side, replicates).
-- Ring group comes from the RingGroup attribute, not child order.
function BallDress.retint(ball: BasePart, skin: any?, trailItem: any?, hues: Cosmetics.Hues?)
	local ringA = Cosmetics.colorOf(skin and skin.ringA, Config.Art.RingA, hues)
	local ringB = Cosmetics.colorOf(skin and skin.ringB, Config.Art.RingB, hues)
	for _, c in ipairs(ball:GetChildren()) do
		if c:IsA("CylinderHandleAdornment") then
			c.Color3 = if c:GetAttribute("RingGroup") == "B" then ringB else ringA
		end
	end
	ball.Color = (skin and skin.core) or CORE_DEFAULT
	local trail = ball:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(Cosmetics.colorOf(trailItem and trailItem.color, nil, hues))
	end
end

return BallDress
