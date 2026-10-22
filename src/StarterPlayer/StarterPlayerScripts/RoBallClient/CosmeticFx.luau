--!strict
-- CosmeticFx (DESIGN.md §18): client-local vanity surfaces.
-- 1) Garage preview — the try-before-you-buy window at the bottom of
--    the always-on garage rail: a REAL-SCALE slice of the game. A
--    straight Flat ribbon emitted with TrackStreamer's own part recipe,
--    the dressed ball rolling down-grade at the real opener speed, the
--    real Backdrop generators around it, framed by the live chase-cam
--    transform. Rebuilt on every browse change (unowned items preview
--    too — that's the conversion lever).
-- 2) Animated skin/trail flags ("rainbow"/"pulse") applied to the live
--    ball AND the diorama in the render loop.
--
-- The diorama can't reuse BallDress: adornments inside a ViewportFrame
-- don't render like the live ball, so rings are real cylinder parts
-- here instead of CylinderHandleAdornments — same dims as the
-- adornments they stand in for.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Palette = require(ReplicatedStorage.RoBall.Palette)
local Backdrop = require(script.Parent.Backdrop)

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
-- Diorama palette — the menu's own vaporwave swatches, used as fallback
-- colors when the browsed skin doesn't override them.
local CY = Color3.fromRGB(0, 230, 255)
local PK = Color3.fromRGB(255, 64, 190)
local DK = Color3.fromRGB(14, 7, 24)

local Gen = Config.Generation
local Art = Config.Art
local Cam = Config.Camera

-- Everything in this window is at REAL game studs — no shrink pass.
-- The lane is a constant-profile straight Flat: same slab/edge/center/
-- grid recipe as TrackStreamer.emitDeck when every section sample is
-- identical, so the mini-lane IS the game's straight line.
local LANE_W = 44 -- tier-0 flat ribbon (Config.Tiers[1] spans 40..50)
local LANE_Z0 = 40 -- lane runs a little behind the camera
local LANE_Z1 = -430 -- ...and out past the scenery window
local ROLL_Z0 = -30 -- ball loop head
local ROLL_LEN = 150 -- studs per loop before the wrap reset
local BALL_D = Config.Ball.Diameter
local ROLL_SPEED = Config.Speed.Start -- real opener pace, studs/s
local DECK_PITCH = math.atan(-Gen.Grade) -- flat chunk: surface falls Grade/stud toward -z
-- tick() is ~1.8e9 seconds — raw tick-derived angles hit ~4e10 radians,
-- where CFrame.Angles' trig quantizes and the rotation FREEZES (the ball
-- slides without rolling). Always wrap angles into [0, tau) first.
local TAU = math.pi * 2

local function deckTopAt(z: number): number
	return Gen.Grade * z
end

local wmodel: WorldModel? = nil
local vpCam: Camera? = nil
local vpBall: BasePart? = nil
local vpRings: { { BasePart } } = {}
local vpRingRots: { CFrame } = {}
local vpBases: { Color3 } = {}
local vpGem: BasePart? = nil
local vpGemCf: CFrame? = nil
local vpShards: { BasePart } = {}
local vpTrail: Trail? = nil
local vpLastRoll = 0
local vpFx: string? = nil
local vpRainbowTrail = false
local vpPaletteTrail = false

-- Same rotations as BallDress.RING_ROTS: 3 axial + 2 diagonal.
local RING_ROTS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(math.rad(45), 0, math.rad(90)),
	CFrame.Angles(math.rad(-45), 0, math.rad(90)),
}

-- The ring cage is built from segment boxes forming true wireframe
-- rings at the real adornment radius — a solid cylinder part spinning
-- at roll speed strobes as a flickering plate, while segments read as
-- the game's actual wireframe cage at any spin rate.
local RING_R = BALL_D / 2 + 0.08 -- real CylinderHandleAdornment radius
local RING_SEGS = 16
local SEG_T = 0.11
local SEG_LEN = (2 * math.pi * RING_R / RING_SEGS) * 1.12
local SEG_CFS: { CFrame } = {}
for j = 0, RING_SEGS - 1 do
	local th = j * math.pi * 2 / RING_SEGS
	-- Circle in the YZ plane (axis X, same convention as a cylinder
	-- part): each box's long Z runs tangent to the ring.
	SEG_CFS[j + 1] = CFrame.new(0, RING_R * math.cos(th), RING_R * math.sin(th)) * CFrame.Angles(th, 0, 0)
end
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

-- Straight Flat ribbon at real scale — the same boxes TrackStreamer
-- emits for a constant-profile chunk: a pitched deck slab tinted toward
-- the palette, neon edge rails and center line split into GridEvery
-- pieces so each samples the palette at its own z, transverse grid on
-- the same cadence. Shares its dims through Config.Art so menu and
-- runtime can't drift apart.
local function makeLane()
	local span = LANE_Z0 - LANE_Z1
	local function orient(p: BasePart)
		p.CFrame = p.CFrame * CFrame.Angles(DECK_PITCH, 0, 0)
	end

	-- Deck slabs in chunk-length pieces so the DeckTint palette drift
	-- lands the same way it does in a run.
	local nSlab = math.max(1, math.ceil(span / Config.Generation.ChunkMaxLength))
	local slabSpan = span / nSlab
	for i = 0, nSlab - 1 do
		local zm = LANE_Z0 - (i + 0.5) * slabSpan
		local p = vpart(
			Vector3.new(LANE_W, Gen.TrackThickness, slabSpan + 0.2),
			Vector3.new(0, deckTopAt(zm) - Gen.TrackThickness / 2, zm),
			Art.DeckColor:Lerp(Palette.neonAt(-zm), Art.DeckTint)
		)
		orient(p)
	end

	-- Longitudinal neon: edge rails + center line, segmented like
	-- emitDeck's eachStripSeg so the palette flows down the course.
	local nSeg = math.max(1, math.ceil(span / Art.GridEvery))
	local sub = span / nSeg
	for i = 0, nSeg - 1 do
		local z0 = LANE_Z0 - (i + 0.5) * sub
		local y0 = deckTopAt(z0)
		local c = Palette.neonAt(-z0)
		for _, x in ipairs({ -LANE_W / 2 + Art.EdgeW / 2, LANE_W / 2 - Art.EdgeW / 2 }) do
			local e = vpart(Vector3.new(Art.EdgeW, Art.EdgeH, sub + 0.2), Vector3.new(x, y0 + Art.EdgeH / 2, z0), c)
			e.Material = Enum.Material.Neon
			orient(e)
		end
		local cs = vpart(
			Vector3.new(Art.CenterW, Art.GridH, sub + 0.15),
			Vector3.new(0, y0 + Art.GridH / 2 + 0.02, z0),
			Palette.dimAt(-z0, Art.GridValue)
		)
		cs.Material = Enum.Material.Neon
		orient(cs)
	end

	-- Transverse grid strips on the fixed GridEvery cadence.
	for z = LANE_Z0 - Art.GridEvery, LANE_Z1 + 0.01, -Art.GridEvery do
		local g = vpart(
			Vector3.new(math.max(LANE_W - 1, 0.5), Art.GridH, 0.5),
			Vector3.new(0, deckTopAt(z) + Art.GridH / 2 + 0.02, z),
			Palette.dimAt(-z, Art.GridValue)
		)
		g.Material = Enum.Material.Neon
		orient(g)
	end
end

-- Mount the garage's ViewportFrame: WorldModel for the parts and a
-- camera driven by the live chase-cam transform (step() re-aims it at
-- the rolling ball every frame). FOV uses the real speed curve.
function Fx.mountViewport(vp: ViewportFrame)
	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	wmodel = wm
	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam
	cam.FieldOfView = Cam.FovMin + (Cam.FovMax - Cam.FovMin) * math.clamp(ROLL_SPEED / Config.Speed.Max, 0, 1)
	vpCam = cam
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
	vpGemCf = nil
	vpTrail = nil
	vpLastRoll = 0
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

	-- The lane: a straight Flat ribbon built from the real deck recipe —
	-- pitched slab + palette-sampled edge rails, center line, grid.
	makeLane()

	-- The ball sits at the loop head, rolling down-grade in step().
	local ballPos = Vector3.new(0, deckTopAt(ROLL_Z0) + BALL_D / 2, ROLL_Z0)

	-- Dressed ball: real scale, SmoothPlastic core + five neon ring parts
	-- mirroring BallDress's cage (same rotations, same ring dims —
	-- adornment Radius d/2+0.08, Height 0.14 → disc diameter d+0.3).
	local ringA = if skin then Cosmetics.colorOf(skin.ringA, CY, hues) else CY
	local ringB = if skin then Cosmetics.colorOf(skin.ringB, PK, hues) else PK
	local ball = vpart(Vector3.one * BALL_D, ballPos, if skin then Cosmetics.colorOf(skin.core, DK, hues) else DK)
	ball.Shape = Enum.PartType.Ball
	vpBall = ball
	for i, rot in ipairs(RING_ROTS) do
		local col = if i <= 3 then ringA else ringB
		local segs = {}
		for j = 1, RING_SEGS do
			local r = Instance.new("Part")
			r.Anchored = true
			r.CanCollide = false
			r.CanQuery = false
			r.CanTouch = false
			r.CastShadow = false
			r.Material = Enum.Material.Neon
			r.Size = Vector3.new(SEG_T, SEG_T, SEG_LEN)
			r.CFrame = CFrame.new(ballPos) * rot * RING_X * SEG_CFS[j]
			r.Color = col
			r.Parent = wm
			segs[j] = r
		end
		vpRings[i] = segs
		vpRingRots[i] = rot
		vpBases[i] = col
	end

	-- Trail: BallDress's own spec — ±0.3d vertical attachment pair,
	-- 0.35→0.05 taper, half-fade transparency, TrailLifetime clock. The
	-- ball really rolls, so the ribbon streams behind it exactly like a
	-- run. FaceCamera stays on as a readability aid (the chase cam
	-- otherwise sees the ribbon edge-on).
	if trailI then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, BALL_D * 0.3, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -BALL_D * 0.3, 0)
		a1.Parent = ball
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = Art.TrailLifetime
		tr.LightEmission = 1
		tr.MinLength = 0
		tr.FaceCamera = true
		tr.WidthScale = NumberSequence.new(0.35, 0.05)
		tr.Transparency = NumberSequence.new(0.5, 1)
		local col = Cosmetics.colorOf(trailI.color, PK, hues)
		tr.Color = ColorSequence.new(col)
		tr.Parent = ball
		vpTrail = tr
	end

	-- Gem on the lane ahead — the real pickup: corner-balanced cube at
	-- FloatY over the deck, tinted by the browsed GEM FX color.
	local gemPos = Vector3.new(-4, deckTopAt(-75) + Config.Gems.FloatY, -75)
	local gem =
		vpart(Vector3.one * Config.Gems.Size, gemPos, Cosmetics.colorOf(gemI and gemI.color, Config.Gems.Color, hues))
	gem.Material = Enum.Material.Neon
	vpGemCf = CFrame.new(gemPos) * CFrame.Angles(math.rad(35.264), math.rad(45), 0)
	gem.CFrame = vpGemCf
	vpGem = gem

	-- Death shards: two wedges orbiting the ball in the DEATH FX pair
	-- colors — reads as "your burst, sampled" without a run.
	for i, col in ipairs({ deathI and deathI.colorA, deathI and deathI.colorB }) do
		local s = vpart(Vector3.new(1.1, 0.8, 0.5), ballPos + Vector3.new(5.2, 0, 0), col or PK)
		s.Material = Enum.Material.Neon
		vpShards[i] = s
	end

	-- World + sun: one static window of the REAL Backdrop generation —
	-- same lay functions, same tunables, same seeded lattice as the live
	-- scenery — anchored on the ball's start so deckEst lands the
	-- scenery exactly where the lane's surface sits.
	local scene = Instance.new("Model")
	scene.Name = "Scene"
	scene.Parent = wm
	Backdrop.diorama(scene, worldI and worldI.theme or "city", sunI and sunI.sun or "classic", ballPos)
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

	-- Diorama anims: the ball really rolls down the straight at opener
	-- speed (that's why the trail streams like a run), the chase cam
	-- re-aims with the live transform, rings ride the roll, the gem
	-- beat-pulses, shards orbit.
	if vpBall then
		local tt = tick()
		local roll = (tt * ROLL_SPEED) % ROLL_LEN
		local z = ROLL_Z0 - roll
		local bc = CFrame.new(0, deckTopAt(z) + BALL_D / 2, z)
			* CFrame.Angles((-tt * ROLL_SPEED / (BALL_D / 2)) % TAU, 0, 0)
		vpBall.CFrame = bc
		for i, segs in ipairs(vpRings) do
			local base = bc * vpRingRots[i] * RING_X
			for j, p in ipairs(segs) do
				p.CFrame = base * SEG_CFS[j]
			end
		end
		if vpCam then
			vpCam.CFrame = CFrame.lookAt(
				bc.Position + Cam.Offset,
				bc.Position
					+ Gen.TravelAxis * Cam.LookAhead
					- Vector3.new(0, Gen.Grade * Cam.LookAhead + Cam.LookDrop, 0)
			)
		end
		if roll < vpLastRoll and vpTrail then
			-- Loop wrap: drop the stale ribbon so it doesn't streak back.
			vpTrail.Enabled = false
			vpTrail.Enabled = true
		end
		vpLastRoll = roll
	end
	if vpGem and vpGemCf then
		-- Beat pulse — same swell fraction live pickups use.
		vpGem.Size = Vector3.one
			* Config.Gems.Size
			* (1 + Config.Gems.BeatPulse * math.max(0, math.sin((tick() * 4) % TAU)))
		vpGem.CFrame = vpGemCf
	end
	if vpBall then
		for i, s in ipairs(vpShards) do
			local a = (tick() * 1.1 + (i - 1) * math.pi) % TAU
			s.CFrame = CFrame.new(vpBall.Position + Vector3.new(math.cos(a) * 5.2, 0.4, math.sin(a) * 5.2))
				* CFrame.Angles(a, a * 1.3, 0)
		end
	end
	if vpFx and ANIM_FX[vpFx] then
		for i, segs in ipairs(vpRings) do
			local col = fxColor(vpFx, i, h, k, vpBases[i])
			for _, p in ipairs(segs) do
				p.Color = col
			end
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
