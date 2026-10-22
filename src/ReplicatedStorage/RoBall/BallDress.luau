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

-- CAPSULE inhabitant (§18 skin_capsule, APEBALL.md §3): a toy monkey
-- RIDING inside the half-clear shell on an upright constraint rig — the
-- shell rolls around it like the arcade ape's ball instead of dragging
-- it over. Generic primitive build, no borrowed character.
-- Sizes/offsets are ball-diameter fractions; the monkey faces +Z local —
-- the server rider goal yaws that face onto the velocity heading.
local MONKEY: { { any } } = {
	{ 0.3, "fur", Vector3.new(0, -0.13, 0) }, -- torso
	{ 0.4, "fur", Vector3.new(0, 0.1, 0.02) }, -- head
	{ 0.2, "face", Vector3.new(0, 0.04, 0.17) }, -- muzzle
	{ 0.15, "fur", Vector3.new(-0.21, 0.16, -0.02) }, -- ear L
	{ 0.15, "fur", Vector3.new(0.21, 0.16, -0.02) }, -- ear R
	{ 0.055, "eye", Vector3.new(-0.075, 0.12, 0.19) }, -- eye L
	{ 0.055, "eye", Vector3.new(0.075, 0.12, 0.19) }, -- eye R
	{ 0.12, "fur", Vector3.new(0, -0.05, -0.22) }, -- tail — reads from behind once yawed onto travel
}

local function monkeyColor(key: string): Color3
	local a = Config.Art
	return if key == "fur" then a.MonkeyFur elseif key == "face" then a.MonkeyFace else a.MonkeyEye
end

-- Absolute spec (studs) for a ball of diameter d — the diorama consumes
-- the same list so preview and live ball build the same monkey. The
-- MonkeyScale bump lives here so both paths scale together.
export type MonkeyBit = { size: number, color: Color3, off: Vector3 }
function BallDress.monkeySpec(d: number): { MonkeyBit }
	local s = Config.Art.MonkeyScale -- bigger monkey reads through the 0.5 shell (APEBALL §3)
	local out: { MonkeyBit } = {}
	for _, b in ipairs(MONKEY) do
		table.insert(out, { size = b[1] * d * s, color = monkeyColor(b[2]), off = b[3] * d * s })
	end
	return out
end

-- Upright-rider rig (APEBALL.md §3): the monkey hangs on a hidden Root
-- part — its own massless assembly, NOT welded to the ball. An
-- AlignPosition pins Root to the ball center; an AlignOrientation
-- ("RiderOri") steers it toward a world-space goal the server rewrites
-- per frame. The ball spins around the rider instead of dragging it over.
local function buildInhabitant(ball: BasePart, d: number)
	local m = Instance.new("Model")
	m.Name = "Inhabitant"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.5 -- small hidden block the bits weld to
	root.Transparency = 1
	root.CastShadow = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	-- World-upright start: identity orientation at the ball center so the
	-- goal driver never sees a baked-in ball rotation.
	root.CFrame = CFrame.new(ball.Position)
	root.Parent = m

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
		p.CFrame = CFrame.new(ball.Position + bit.off)
		-- Welds go to ROOT, never to the ball — a ball weld would slave
		-- the rider to the spin.
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		p.Parent = m
	end

	-- Ride anchors: ball center ↔ root center. The ball-side attachment
	-- can't live inside the model (attachments need a BasePart parent),
	-- so it sits on the ball and retint cleans it up with the rig.
	local ballAtt = Instance.new("Attachment")
	ballAtt.Name = "Ride"
	ballAtt.Position = Vector3.zero
	ballAtt.Parent = ball
	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "Ride"
	rootAtt.Parent = root

	-- TwoAttachment keeps the rider centered on the shell; the soft
	-- Responsiveness is the suspension bob. Reaction on the ball is ~0 —
	-- the whole rider assembly is massless.
	local aPos = Instance.new("AlignPosition")
	aPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
	aPos.Attachment0 = rootAtt
	aPos.Attachment1 = ballAtt
	aPos.Responsiveness = Config.Art.RiderResponsiveness
	aPos.MaxForce = Config.Art.RiderMaxForce
	aPos.Parent = root

	-- OneAttachment world-space orientation goal — Main's Heartbeat
	-- driver (updateApeOrientation port) rewrites .CFrame per frame;
	-- the soft stiffness plays SMB's incremental uprighting.
	local aOri = Instance.new("AlignOrientation")
	aOri.Name = "RiderOri"
	aOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aOri.Attachment0 = rootAtt
	aOri.Responsiveness = Config.Art.RiderResponsiveness
	aOri.MaxTorque = Config.Art.RiderMaxTorque
	aOri.CFrame = CFrame.new() -- identity until the goal driver takes over
	aOri.Parent = root

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
	-- §2 shell: capsule wears Glass so the half-alpha reads as a specular
	-- bubble; anything else stays SmoothPlastic.
	ball.Material = if skin and skin.capsule then Enum.Material.Glass else Enum.Material.SmoothPlastic
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
	-- shell + inhabitant without a respawn — the material must restore
	-- too, or an unequip leaves a glass shell on a normal skin.
	ball.Transparency = if skin and skin.capsule then Config.Art.CapsuleAlpha else 0
	ball.Material = if skin and skin.capsule then Enum.Material.Glass else Enum.Material.SmoothPlastic
	local inhab = ball:FindFirstChild("Inhabitant")
	if skin and skin.inhabitant == "monkey" then
		if not inhab then
			buildInhabitant(ball, ball.Size.X)
		end
	elseif inhab then
		inhab:Destroy()
		-- The ball-side ride anchor is the one rig piece that couldn't
		-- live inside the model — clean it with the rest.
		local ride = ball:FindFirstChild("Ride")
		if ride then
			ride:Destroy()
		end
	end
	local trail = ball:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(Cosmetics.colorOf(trailItem and trailItem.color, nil, hues))
		trail.Enabled = not (trailItem and trailItem.none == true)
	end
end

return BallDress
