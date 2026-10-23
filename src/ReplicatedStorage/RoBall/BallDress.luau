--!strict
-- BallDress (DESIGN.md §18): builds the vaporwave ball — near-black core,
-- five engine-rendered wireframe rings (3 axial + 2 diagonal), attachments
-- + slim trail — from a skin/trail item pair. Shared so the server's
-- spawnBall and the client's menu preview dress identically; `scale`
-- renders the preview oversize.

local GeometryService = game:GetService("GeometryService")

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

-- CAPSULE shell cap (§18 skin_capsule, APEBALL.md §2): the arcade ball
-- is two half-shells — a translucent RED hemisphere rides the top of
-- the clear shell, welded so the 50/50 split tumbles with the roll.
-- The cap is a real CSG hemisphere via GeometryService (the documented
-- in-game solid-modeling path), built async so dressing never yields.
-- `cb` receives the finished cap part (unparented, at origin) or nil —
-- callers decide weld-vs-CFrame rigging and own the failure fallback.
function BallDress.buildCap(d: number, cb: (BasePart?) -> ())
	task.spawn(function()
		local temp = Instance.new("Part")
		temp.Shape = Enum.PartType.Ball
		-- A hair proud of the shell: the cap IS the outer skin on the top
		-- half, no coplanar z-fight against the glass ball.
		temp.Size = Vector3.one * (d + 0.06)
		local cut = Instance.new("Part")
		cut.Size = Vector3.new(d * 2, d, d * 2)
		cut.Position = Vector3.new(0, -d * 0.5, 0) -- wipes everything below the equator plane
		local ok, res = pcall(function()
			return GeometryService:SubtractAsync(temp, { cut })
		end)
		temp:Destroy()
		cut:Destroy()
		local cap = ok and res and res[1]
		if cap then
			cap.Name = "ShellCap"
			cap.Color = Config.Art.CapsuleRed
			cap.Material = Enum.Material.SmoothPlastic
			cap.Transparency = Config.Art.CapsuleRedAlpha
			cap.CastShadow = false
			cap.CanCollide = false
			cap.CanQuery = false
			cap.CanTouch = false
			cap.Massless = true
		end
		cb(cap)
	end)
end

-- Cap lifecycle shared by dress/retint: capsule skins get exactly one
-- ShellCap welded at ball center; anything else drops it. The CapSeq
-- attribute token-stales a pending CSG build so an equip swap can't
-- weld a cap onto a ball that no longer wants one.
local function syncCap(ball: BasePart, d: number, capsule: boolean)
	local seq = (ball:GetAttribute("CapSeq") or 0) + 1
	ball:SetAttribute("CapSeq", seq)
	local old = ball:FindFirstChild("ShellCap")
	if old then
		old:Destroy()
	end
	if not capsule then
		return
	end
	BallDress.buildCap(d, function(cap)
		if cap and ball.Parent and ball:GetAttribute("CapSeq") == seq then
			cap.CFrame = CFrame.new(ball.Position)
			local w = Instance.new("WeldConstraint")
			w.Part0 = ball
			w.Part1 = cap
			w.Parent = cap
			cap.Parent = ball
		elseif cap then
			cap:Destroy()
		elseif ball.Parent and ball:GetAttribute("CapSeq") == seq then
			-- CSG unavailable: degrade to a whole-shell red tint so the
			-- skin still reads "red capsule", just without the split.
			-- The seq check matters here too — a failed build must not
			-- tint a ball that was re-dressed mid-flight.
			ball.Color = Config.Art.CapsuleRed
		end
	end)
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
	syncCap(ball, d, skin ~= nil and skin.capsule == true)

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
	-- shell + red cap without a respawn — the material must restore
	-- too, or an unequip leaves a glass shell on a normal skin.
	ball.Transparency = if skin and skin.capsule then Config.Art.CapsuleAlpha else 0
	ball.Material = if skin and skin.capsule then Enum.Material.Glass else Enum.Material.SmoothPlastic
	syncCap(ball, ball.Size.X, skin ~= nil and skin.capsule == true)
	local trail = ball:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(Cosmetics.colorOf(trailItem and trailItem.color, nil, hues))
		trail.Enabled = not (trailItem and trailItem.none == true)
	end
end

return BallDress
