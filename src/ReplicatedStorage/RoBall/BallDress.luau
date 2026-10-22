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

-- CAPSULE inhabitant (§18 skin_capsule): a toy monkey riding inside the
-- transparent shell — generic primitive build, no borrowed character.
-- Sizes/offsets are ball-diameter fractions; the monkey faces +Z (the
-- chase-cam side — the ball travels -Z).
local MONKEY: { { any } } = {
	{ 0.3, "fur", Vector3.new(0, -0.13, 0) }, -- torso
	{ 0.4, "fur", Vector3.new(0, 0.1, 0.02) }, -- head
	{ 0.2, "face", Vector3.new(0, 0.04, 0.17) }, -- muzzle
	{ 0.15, "fur", Vector3.new(-0.21, 0.16, -0.02) }, -- ear L
	{ 0.15, "fur", Vector3.new(0.21, 0.16, -0.02) }, -- ear R
	{ 0.055, "eye", Vector3.new(-0.075, 0.12, 0.19) }, -- eye L
	{ 0.055, "eye", Vector3.new(0.075, 0.12, 0.19) }, -- eye R
}

local function monkeyColor(key: string): Color3
	local a = Config.Art
	return if key == "fur" then a.MonkeyFur elseif key == "face" then a.MonkeyFace else a.MonkeyEye
end

-- Absolute spec (studs) for a ball of diameter d — the diorama consumes
-- the same list so preview and live ball build the same monkey.
export type MonkeyBit = { size: number, color: Color3, off: Vector3 }
function BallDress.monkeySpec(d: number): { MonkeyBit }
	local out: { MonkeyBit } = {}
	for _, b in ipairs(MONKEY) do
		table.insert(out, { size = b[1] * d, color = monkeyColor(b[2]), off = b[3] * d })
	end
	return out
end

-- Welded inhabitant for a live ball: Massless + no-collide/no-query/
-- no-touch inner parts, welded so the monkey tumbles with the roll.
local function buildInhabitant(ball: BasePart, d: number)
	local m = Instance.new("Model")
	m.Name = "Inhabitant"
	for _, bit in ipairs(BallDress.monkeySpec(d)) do
		local p = Instance.new("Part")
		p.Name = "Bit"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * bit.size
		p.Color = bit.color
		p.Material = Enum.Material.SmoothPlastic
		p.CastShadow = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = ball.CFrame * CFrame.new(bit.off)
		local w = Instance.new("WeldConstraint")
		w.Part0 = ball
		w.Part1 = p
		w.Parent = p
		p.Parent = m
	end
	m.Parent = ball
end

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
	ball.Transparency = if skin and skin.capsule then Config.Art.CapsuleAlpha else 0
	if skin and skin.inhabitant == "monkey" then
		buildInhabitant(ball, d)
	end

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
	-- `none` items (TRAIL ▸ NONE) keep the object parked — equip swaps
	-- just flip Enabled, no rebuild needed.
	trail.Enabled = not (trailItem and trailItem.none == true)
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
	-- Capsule lifecycle: equip swaps can add or remove the transparent
	-- shell + inhabitant without a respawn.
	ball.Transparency = if skin and skin.capsule then Config.Art.CapsuleAlpha else 0
	local inhab = ball:FindFirstChild("Inhabitant")
	if skin and skin.inhabitant == "monkey" then
		if not inhab then
			buildInhabitant(ball, ball.Size.X)
		end
	elseif inhab then
		inhab:Destroy()
	end
	local trail = ball:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(Cosmetics.colorOf(trailItem and trailItem.color, nil, hues))
		trail.Enabled = not (trailItem and trailItem.none == true)
	end
end

return BallDress
