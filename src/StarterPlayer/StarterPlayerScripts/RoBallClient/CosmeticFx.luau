--!strict
-- CosmeticFx (DESIGN.md §18): client-local vanity surfaces.
-- 1) Garage preview diorama — the try-before-you-buy window at the
--    bottom of the always-on garage rail: a mini deck + dressed ball +
--    sun + world motif inside a ViewportFrame, rebuilt on every browse
--    change (unowned items preview too — that's the conversion lever).
-- 2) Animated skin/trail flags ("rainbow"/"pulse") applied to the live
--    ball AND the diorama in the render loop.
--
-- The diorama can't reuse BallDress: adornments/attachments inside a
-- ViewportFrame don't render like the live ball, so rings are real
-- cylinder parts here instead of CylinderHandleAdornments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local player = Players.LocalPlayer

-- The live ball comes from Main's getter (PERFORMANCE.md §1): polling
-- workspace:FindFirstChild by name every render frame was a per-frame
-- string-keyed lookup — the bound ball is already canonical.
local getBall: () -> BasePart? = function()
	return nil
end

local Fx = {}

local skinItem: any = nil
local trailItem: any = nil

type Watched = { rings: { CylinderHandleAdornment }, bases: { Color3 }, trail: Trail? }
local watched: { [BasePart]: Watched } = {}

local function equipped()
	skinItem = Cosmetics.item(player:GetAttribute("RoBallEq_skin") :: string?)
	trailItem = Cosmetics.item(player:GetAttribute("RoBallEq_trail") :: string?)
end

--=================== DIORAMA (menu preview) ===================--
-- Diorama palette — the menu's own vaporwave swatches, kept local so
-- the world-theme motifs can borrow them without importing Ui.
local CY = Color3.fromRGB(0, 230, 255)
local PK = Color3.fromRGB(255, 64, 190)
local DK = Color3.fromRGB(14, 7, 24)
local ICE = Color3.fromRGB(160, 230, 255)
local ORG = Color3.fromRGB(255, 140, 40)
local LIM = Color3.fromRGB(120, 255, 120)

local VP_SCALE = 2.2
local BALL_D = Config.Ball.Diameter * VP_SCALE
local BALL_POS = Vector3.new(0, BALL_D / 2 + 0.8, 8)
local GEM_POS = Vector3.new(8.5, 4, -7)
local SUN_POS = Vector3.new(0, 15, -56)

local wmodel: WorldModel? = nil
local vpBall: BasePart? = nil
local vpRings: { BasePart } = {}
local vpRingRots: { CFrame } = {}
local vpBases: { Color3 } = {}
local vpGem: BasePart? = nil
local vpShards: { BasePart } = {}
local vpTrail: Trail? = nil
local vpFx: string? = nil
local vpRainbowTrail = false
local vpPaletteTrail = false

local RING_ROTS = {
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(math.rad(60), 0, math.rad(35)),
	CFrame.Angles(math.rad(60), 0, math.rad(-35)),
	CFrame.Angles(0, math.rad(55), math.rad(30)),
	CFrame.Angles(0, math.rad(-55), math.rad(30)),
}
local RING_X = CFrame.Angles(0, 0, math.rad(90)) -- part cylinder axis (X) → adornment axis (Y)

local function vpart(size: Vector3, pos: Vector3, col: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = CFrame.new(pos)
	p.Color = col
	p.Parent = wmodel
	return p
end

-- World-theme motif: a few simple props that gesture at the full
-- Backdrop look (§18) without dragging the whole scene into the window.
local MOTIFS: { [string]: () -> () } = {
	city = function()
		for i, t in ipairs({ { -22, 14, -34 }, { -27, 21, -40 }, { 24, 17, -32 }, { 19, 11, -38 } }) do
			local x, h, z = t[1], t[2], t[3]
			vpart(Vector3.new(4, h, 4), Vector3.new(x, h / 2, z), DK)
			vpart(Vector3.new(4.3, 0.6, 4.3), Vector3.new(x, h - 2 - i, z), if i % 2 == 0 then CY else PK)
		end
	end,
	peaks = function()
		for _, s in ipairs({ { -24, 15, -30 }, { 25, 11, -26 } }) do
			local w = Instance.new("WedgePart")
			w.Anchored = true
			w.CanCollide = false
			w.CastShadow = false
			w.Material = Enum.Material.SmoothPlastic
			w.Size = Vector3.new(14, s[2], 10)
			w.CFrame = CFrame.new(s[1], s[2] / 2, s[3])
			w.Color = DK
			w.Parent = wmodel
		end
		vpart(Vector3.new(1, 15, 1), Vector3.new(-24, 8, -30), CY)
		vpart(Vector3.new(1, 11, 1), Vector3.new(25, 6, -26), PK)
	end,
	void = function()
		local rng = Random.new(7)
		for _ = 1, 14 do
			vpart(
				Vector3.one * rng:NextNumber(0.3, 0.8),
				Vector3.new(rng:NextNumber(-26, 26), rng:NextNumber(2, 20), rng:NextNumber(-46, -18)),
				Color3.new(1, 1, 1)
			).Material =
				Enum.Material.Neon
		end
	end,
	grid = function()
		for i = -2, 2 do
			vpart(Vector3.new(0.5, 0.24, 90), Vector3.new(i * 9, 0.05, -14), Color3.fromRGB(0, 120, 140)).Material =
				Enum.Material.Neon
		end
	end,
	aurora = function()
		local a = vpart(Vector3.new(3, 26, 1), Vector3.new(-26, 13, -30), LIM)
		a.Transparency = 0.35
		a.Material = Enum.Material.Neon
		local b = vpart(Vector3.new(3, 30, 1), Vector3.new(27, 15, -36), ICE)
		b.Transparency = 0.4
		b.Material = Enum.Material.Neon
	end,
	reef = function()
		for i, s in ipairs({ { -22, 6, -22, PK }, { 24, 9, -28, CY }, { -26, 4, -34, ORG }, { 20, 5, -18, LIM } }) do
			local c = vpart(Vector3.new(1.6, s[2], 1.6), Vector3.new(s[1], s[2] / 2, s[3]), s[4])
			c.Material = Enum.Material.Neon
			if i % 2 == 1 then
				vpart(Vector3.new(3.4, 0.8, 0.8), Vector3.new(s[1], s[2] - 0.6, s[3]), s[4]).Material =
					Enum.Material.Neon
			end
		end
	end,
	meteor = function()
		for i = 1, 4 do
			local s = vpart(Vector3.new(0.5, 7, 0.5), Vector3.new(-18 + i * 11, 16 + i, -30 - i * 4), ORG)
			s.Material = Enum.Material.Neon
			s.CFrame = CFrame.new(s.Position) * CFrame.Angles(math.rad(50), 0, math.rad(30))
		end
	end,
	palms = function()
		for _, x in ipairs({ -24, 25 }) do
			local t = vpart(Vector3.new(1, 9, 1), Vector3.new(x, 4.5, -18), Color3.fromRGB(80, 40, 120))
			t.Material = Enum.Material.Neon
			for k = 0, 3 do
				local f = vpart(Vector3.new(4.4, 0.5, 0.9), Vector3.new(x, 9, -18), if x < 0 then CY else PK)
				f.Material = Enum.Material.Neon
				f.CFrame = CFrame.new(Vector3.new(x, 9, -18))
					* CFrame.Angles(0, math.rad(k * 90 + 30), math.rad(-18))
					* CFrame.new(1.6, 0, 0)
			end
		end
	end,
}

-- Mount the garage's ViewportFrame: WorldModel for the diorama parts and
-- a fixed camera aimed down the mini deck toward the sun.
function Fx.mountViewport(vp: ViewportFrame)
	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	wmodel = wm
	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam
	cam.FieldOfView = 36
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 8.5, 27), Vector3.new(0, 6, -14))
end

-- Rebuild the diorama from the BROWSED items (one per cosmetic slot) —
-- unowned merch shows up here so cycling the catalog previews the buy.
function Fx.preview(items: { [string]: any })
	local wm = wmodel
	if not wm then
		return
	end
	wm:ClearAllChildren()
	vpBall = nil
	vpGem = nil
	vpTrail = nil
	vpRings = {}
	vpRingRots = {}
	vpBases = {}
	vpShards = {}

	local hues = Cosmetics.huesOf(player)
	local skin = items.skin
	local trailI = items.trail
	local gemI = items.gemFx
	local deathI = items.deathFx
	local worldI = items.world
	local sunI = items.sun
	vpFx = skin and skin.fx or nil
	vpRainbowTrail = trailI ~= nil and trailI.color == "rainbow"
	vpPaletteTrail = trailI ~= nil and trailI.color == "palette"

	-- Mini deck: dark slab + neon rails + faint cross-grid, so trail and
	-- world items read "in gameplay context" rather than floating.
	vpart(Vector3.new(42, 1, 90), Vector3.new(0, -0.5, -14), DK)
	local railL = vpart(Vector3.new(0.7, 0.3, 90), Vector3.new(-21, 0.1, -14), CY)
	railL.Material = Enum.Material.Neon
	local railR = vpart(Vector3.new(0.7, 0.3, 90), Vector3.new(21, 0.1, -14), PK)
	railR.Material = Enum.Material.Neon
	for i = 0, 4 do
		vpart(Vector3.new(42, 0.22, 0.5), Vector3.new(0, 0.02, 4 - i * 16), Color3.fromRGB(30, 70, 90)).Material =
			Enum.Material.Neon
	end

	-- Dressed ball: SmoothPlastic core + five neon ring parts mirroring
	-- BallDress's cage (ringA/ringB/custom hues all resolve via colorOf).
	local ringA = if skin then Cosmetics.colorOf(skin.ringA, CY, hues) else CY
	local ringB = if skin then Cosmetics.colorOf(skin.ringB, PK, hues) else PK
	local ball = vpart(Vector3.one * BALL_D, BALL_POS, if skin then Cosmetics.colorOf(skin.core, DK, hues) else DK)
	ball.Shape = Enum.PartType.Ball
	vpBall = ball
	local ringD = BALL_D + 0.7
	for i, rot in ipairs(RING_ROTS) do
		local r = Instance.new("Part")
		r.Shape = Enum.PartType.Cylinder
		r.Anchored = true
		r.CanCollide = false
		r.CanQuery = false
		r.CanTouch = false
		r.CastShadow = false
		r.Material = Enum.Material.Neon
		r.Size = Vector3.new(0.5, ringD, ringD)
		r.CFrame = CFrame.new(BALL_POS) * rot * RING_X
		r.Color = if i % 2 == 1 then ringA else ringB
		r.Parent = wm
		vpRings[i] = r
		vpRingRots[i] = rot
		vpBases[i] = r.Color
	end

	-- Trail: real Trail + attachments on the ball — the ribbon swings as
	-- the cage tumbles, same as it does in a live run.
	if trailI then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, BALL_D / 2 + 0.5, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, BALL_D / 2 + 0.5, -2.5)
		a1.Parent = ball
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.5
		tr.MinLength = 0
		tr.WidthScale = NumberSequence.new(BALL_D * 0.5)
		local col = Cosmetics.colorOf(trailI.color, PK, hues)
		tr.Color = ColorSequence.new(col)
		tr.Parent = ball
		vpTrail = tr
	end

	-- Gem sample: a spinning neon gem mid-deck tinted by the browsed
	-- GEM FX burst color.
	local gem = vpart(Vector3.new(1.6, 1.6, 1.6), GEM_POS, Cosmetics.colorOf(gemI and gemI.color, CY, hues))
	gem.Material = Enum.Material.Neon
	vpGem = gem

	-- Death shards: two wedges orbiting the ball in the DEATH FX pair
	-- colors — reads as "your burst, sampled" without a run.
	for i, col in ipairs({ deathI and deathI.colorA, deathI and deathI.colorB }) do
		local s = vpart(Vector3.new(1.1, 0.8, 0.5), BALL_POS + Vector3.new(6, 0, 0), col or PK)
		s.Material = Enum.Material.Neon
		vpShards[i] = s
	end

	-- Sun: the §18 strip-stack silhouette, shrunk — solid/gap params give
	-- classic/contiguous domes, grid slats, and the eclipse disc.
	local style = Config.Art.SunStyles[sunI and sunI.sun or "classic"] or Config.Art.SunStyles.classic
	local r = 14 * (style.scale or 1)
	for i = 1, 16 do
		local frac = i / 16
		local yo = r - frac * 2 * r
		if frac <= style.solid or i % 2 == 0 then
			local half = math.sqrt(math.max(r * r - yo * yo, 0.6))
			local s = vpart(
				Vector3.new(half * 2, (2 * r / 16) * (if frac <= style.solid then 0.95 else 0.5), 0.6),
				SUN_POS + Vector3.new(0, yo, 0),
				style.top:Lerp(style.bottom, frac)
			)
			s.Material = Enum.Material.Neon
		end
	end

	-- World motif: gestural props per theme.
	local motif = MOTIFS[worldI and worldI.theme or "city"]
	if motif then
		motif()
	end
end

--=================== LIVE BALL ANIM ===================--
-- Snapshot a dressed ball's rings (+base colors for pulse) and trail.
local function collect(ball: BasePart)
	local w: Watched = { rings = {}, bases = {}, trail = ball:FindFirstChildOfClass("Trail") }
	for _, c in ipairs(ball:GetChildren()) do
		if c:IsA("CylinderHandleAdornment") then
			table.insert(w.rings, c)
			table.insert(w.bases, c.Color3)
		end
	end
	watched[ball] = w
end

local ANIM_FX = { rainbow = true, pulse = true, strobe = true, wave = true }

-- The animated color a ring should wear this frame, given its fx flag,
-- ring index, hue/k clocks and its static base color.
local function fxColor(fx: string, i: number, h: number, k: number, base: Color3): Color3
	if fx == "rainbow" then
		return Color3.fromHSV((h + i * 0.13) % 1, 0.9, 1)
	elseif fx == "strobe" then
		-- Hot flicker: fast hue cycle + per-ring bright/dark
		-- alternation — the CHROMA skin's marquee look.
		local v = if math.floor(tick() * 7 + i) % 2 == 0 then 1 else 0.28
		return Color3.fromHSV((h * 2.2 + i * 0.4) % 1, 0.95, v)
	elseif fx == "wave" then
		-- The run palette flows across the rings, offset per
		-- ring — the IRIS skin's gradient-cage look.
		return Palette.neonAt(tick() * 60 + i * 35)
	end
	return base:Lerp(Color3.new(0, 0, 0), 0.55 * k) -- pulse
end

local function step()
	local h = (tick() * 0.28) % 1
	local k = 0.5 + 0.5 * math.sin(tick() * 2.6)

	local fx = skinItem and skinItem.fx
	local doRings = ANIM_FX[fx] == true
	local doTrail = trailItem ~= nil and trailItem.color == "rainbow"
	if doRings or doTrail then
		for ball, w in pairs(watched) do
			if not ball.Parent then
				watched[ball] = nil
				continue
			end
			if doRings then
				for i, r in ipairs(w.rings) do
					r.Color3 = fxColor(fx, i, h, k, w.bases[i])
				end
			end
			if doTrail and w.trail then
				w.trail.Color = ColorSequence.new(Color3.fromHSV(h, 0.95, 1))
			end
		end
	end

	-- Diorama anims: cage tumble, ring fx, gem spin, shard orbit.
	if vpBall then
		local bc = CFrame.new(BALL_POS) * CFrame.Angles(tick() * 0.9, tick() * 0.5, 0)
		vpBall.CFrame = bc
		for i, r in ipairs(vpRings) do
			r.CFrame = bc * vpRingRots[i] * RING_X
		end
	end
	if vpGem then
		vpGem.CFrame = CFrame.new(GEM_POS) * CFrame.Angles(0.5, tick() * 1.6, 0.7)
	end
	for i, s in ipairs(vpShards) do
		local a = tick() * 1.1 + (i - 1) * math.pi
		s.CFrame = CFrame.new(BALL_POS + Vector3.new(math.cos(a) * 6.5, 0.6, math.sin(a) * 6.5))
			* CFrame.Angles(a, a * 1.3, 0)
	end
	if vpFx and ANIM_FX[vpFx] then
		for i, r in ipairs(vpRings) do
			r.Color = fxColor(vpFx, i, h, k, vpBases[i])
		end
	end
	if vpRainbowTrail and vpTrail then
		vpTrail.Color = ColorSequence.new(Color3.fromHSV(h, 0.95, 1))
	elseif vpPaletteTrail and vpTrail then
		vpTrail.Color = ColorSequence.new(Palette.neonAt(tick() * 40))
	end
end

-- Mode transitions: the live ball just re-reads its equip state; the
-- diorama is menu-bound through the garage panel itself.
function Fx.onMode(_mode: string)
	equipped()
end

-- Equip/attribute change: re-read ids. The live ball's static colors are
-- re-painted server-side (BallDress.retint); the diorama rebuilds via
-- Fx.preview on every garage refresh.
function Fx.refresh()
	equipped()
end

function Fx.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	equipped()
	-- COLOR LAB (§18): a hue write lands on attributes — the diorama
	-- rebuild flows through refreshGarage → Fx.preview.
	for _, attr in pairs(Cosmetics.HueAttr) do
		player:GetAttributeChangedSignal(attr):Connect(Fx.refresh)
	end
	RunService.RenderStepped:Connect(function()
		local fx = skinItem and skinItem.fx
		local anim = ANIM_FX[fx] == true or (trailItem ~= nil and trailItem.color == "rainbow")
		if anim then
			-- Lazy-collect the run ball: replication order of parts vs
			-- adornments isn't guaranteed, so watch until rings show up.
			local b = getBall()
			if b and not watched[b] and b:FindFirstChildOfClass("CylinderHandleAdornment") then
				collect(b)
			end
		end
		step()
	end)
end

return Fx
