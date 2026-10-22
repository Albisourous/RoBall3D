--!strict
-- CosmeticFx (DESIGN.md §18): client-local vanity surfaces.
-- 1) Garage preview — the try-before-you-buy window at the bottom of
--    the always-on garage rail: a REAL-SCALE slice of the game. A
--    straight Flat ribbon emitted with TrackStreamer's own part recipe,
--    the dressed ball rolling down-grade at the real opener speed, the
--    real Backdrop generators around it, framed by the live chase-cam
--    transform. The loop ends at a lethal-style wall: the ball slams,
--    the browsed DEATH FX's real burst fires into the WorldModel, then
--    the wrap respawns it. Rebuilt on every browse change (unowned
--    items preview too — that's the conversion lever).
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
local BallDress = require(ReplicatedStorage.RoBall.BallDress)
local GemTypes = require(ReplicatedStorage.RoBall.GemTypes)
local Backdrop = require(script.Parent.Backdrop)
local DeathFx = require(script.Parent.DeathFx)

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
local SWAY_AMP = 8 -- studs of lateral weave — sells the trail's stream
local SWAY_W = 1.1 -- weave rate (rad/s): ~1 lazy S per loop
local SWAY_BANK = 0.3 -- steer lean into the weave (rad)
-- Ribbon: one quad pair (core + glow) per sampled position — ~0.4 s of
-- history at the opener pace, same coverage as TrailLifetime ×
-- ROLL_SPEED. Ember motes peel off the wake — the boost-trail look:
-- white-hot at the ball, cooling to the item's color, sparks scattering.
local TRAIL_SEGS = 24
local TRAIL_MOTES = 10
local WHITE = Color3.new(1, 1, 1)
local BALL_D = Config.Ball.Diameter
local ROLL_SPEED = Config.Speed.Start -- real opener pace, studs/s
-- Loop tail: the ball slams a lethal-style slab at the end of its run,
-- the browsed DEATH FX bursts at the impact point, the wrap respawns.
local WALL_H = Config.Obstacles.BlockHeight
local WALL_T = 1.2
local WALL_Z = ROLL_Z0 - ROLL_LEN - BALL_D / 2 - WALL_T / 2 -- face meets the ball's nose
local DEAD_T = 0.85 -- seconds holding on the burst before the respawn
local CYCLE = ROLL_LEN + ROLL_SPEED * DEAD_T
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
local vpGemSize = Config.Gems.Size
local vpBallAlpha = 0 -- rest transparency (capsule skins aren't opaque)
-- Capsule inhabitant preview bits: anchored spheres pinned to the roll
-- CFrame each frame (welds can't ride the diorama's manual CFraming).
local vpMonkey: { { part: BasePart, off: Vector3 } } = {}
local vpDeathItem: any = nil
local vpDead = false
local vpHitPos: Vector3? = nil
local vpTrailSegs: { BasePart } = {}
local vpTrailGlow: { BasePart } = {}
local vpMotes: { BasePart } = {}
local vpTrailPts: { Vector3 } = {}
local vpTrailColor = PK
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
	vpGemSize = Config.Gems.Size
	vpBallAlpha = 0
	vpMonkey = {}
	vpTrailSegs = {}
	vpTrailGlow = {}
	vpMotes = {}
	vpTrailPts = {}
	vpLastRoll = 0
	vpRings = {}
	vpRingRots = {}
	vpBases = {}
	vpDead = false
	vpHitPos = nil

	local hues = Cosmetics.huesOf(player)
	local skin = items.skin
	local trailI = items.trail
	local gemI = items.gemFx
	local deathI = items.deathFx
	local worldI = items.world
	local sunI = items.sun
	vpDeathItem = deathI
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
	-- Capsule skins (§18 skin_capsule): transparent shell + the same toy
	-- monkey spec the live ball welds on — pinned to the roll in step().
	vpBallAlpha = if skin and skin.capsule then Art.CapsuleAlpha else 0
	ball.Transparency = vpBallAlpha
	vpBall = ball
	if skin and skin.inhabitant == "monkey" then
		for _, bit in ipairs(BallDress.monkeySpec(BALL_D)) do
			local m = vpart(Vector3.one * bit.size, ballPos + bit.off, bit.color)
			m.Shape = Enum.PartType.Ball
			m.Material = Enum.Material.SmoothPlastic
			table.insert(vpMonkey, { part = m, off = bit.off })
		end
	end
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

	-- Ribbon: a Trail can't draw inside a ViewportFrame — the same
	-- stroke-swap as the ring cage. The boost-trail read: a bright core
	-- strip over a wider soft-glow layer, plus ember motes that peel off
	-- the wake — all thin Neon quads/spheres bridging the ball's recent
	-- positions on the real spec's taper+fade (WidthScale 0.35→0.05,
	-- Transparency 0.5→1, Lifetime × speed long).
	if trailI and not trailI.none then
		vpTrailColor = Cosmetics.colorOf(trailI.color, PK, hues)
		for i = 1, TRAIL_SEGS do
			local s = vpart(Vector3.one * 0.1, ballPos, vpTrailColor)
			s.Material = Enum.Material.Neon
			s.Transparency = 1
			vpTrailSegs[i] = s
			local g = vpart(Vector3.one * 0.1, ballPos, vpTrailColor)
			g.Material = Enum.Material.Neon
			g.Transparency = 1
			vpTrailGlow[i] = g
		end
		for j = 1, TRAIL_MOTES do
			local m = vpart(Vector3.one * 0.2, ballPos, vpTrailColor)
			m.Material = Enum.Material.Neon
			m.Shape = Enum.PartType.Ball
			m.Transparency = 1
			vpMotes[j] = m
		end
	end

	-- Gem on the lane ahead — the real pickup: corner-balanced cube at
	-- FloatY over the deck, tinted by the browsed GEM FX color. Worlds
	-- carrying a gemStyle (world_sky → "ball") restyle it the same way
	-- TrackStreamer does live: banana orb, tier scale.
	local gemPos = Vector3.new(-4, deckTopAt(-75) + Config.Gems.FloatY, -75)
	local gem: BasePart
	if worldI and worldI.gemStyle == "ball" then
		local shape, gsize, gcol = GemTypes.ball(10)
		vpGemSize = gsize
		gem = vpart(Vector3.one * gsize, gemPos, gcol)
		gem.Shape = if shape == "orb" then Enum.PartType.Ball else Enum.PartType.Block
		vpGemCf = CFrame.new(gemPos)
	else
		vpGemSize = Config.Gems.Size
		gem = vpart(
			Vector3.one * Config.Gems.Size,
			gemPos,
			Cosmetics.colorOf(gemI and gemI.color, Config.Gems.Color, hues)
		)
		vpGemCf = CFrame.new(gemPos) * CFrame.Angles(math.rad(35.264), math.rad(45), 0)
	end
	gem.Material = Enum.Material.Neon
	gem.CFrame = vpGemCf
	vpGem = gem

	-- The wall the ball slams to end its loop: the lethal read — a
	-- near-black slab with a hot-red edge frame. SelectionBox can't draw
	-- inside a ViewportFrame (same swap as the ring cage), so the outline
	-- is real neon strips on the face the ball approaches.
	local wy = deckTopAt(WALL_Z)
	local wallCf = CFrame.new(0, wy + WALL_H / 2, WALL_Z) * CFrame.Angles(DECK_PITCH, 0, 0)
	local wall = vpart(Vector3.new(LANE_W - 1, WALL_H, WALL_T), wallCf.Position, Config.Obstacles.FaceColor)
	wall.Name = "PreviewWall"
	wall.CFrame = wallCf
	local ET = 0.3
	local halfW = (LANE_W - 1) / 2
	for _, f in ipairs({
		{ size = Vector3.new(ET, WALL_H, ET), off = CFrame.new(-halfW + ET / 2, 0, WALL_T / 2 + ET / 2) },
		{ size = Vector3.new(ET, WALL_H, ET), off = CFrame.new(halfW - ET / 2, 0, WALL_T / 2 + ET / 2) },
		{ size = Vector3.new(LANE_W - 1, ET, ET), off = CFrame.new(0, WALL_H / 2 - ET / 2, WALL_T / 2 + ET / 2) },
		{ size = Vector3.new(LANE_W - 1, ET, ET), off = CFrame.new(0, -WALL_H / 2 + ET / 2, WALL_T / 2 + ET / 2) },
	}) do
		local e = vpart(f.size, (wallCf * f.off).Position, Config.LethalColor)
		e.CFrame = wallCf * f.off
		e.Material = Enum.Material.Neon
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
	-- speed (that's why the trail streams like a run), slams the wall at
	-- the loop end — the real browsed DEATH FX bursts at the impact and
	-- the ball hides until the wrap respawns it — the chase cam re-aims
	-- with the live transform, rings ride the roll, the gem beat-pulses.
	if vpBall then
		local tt = tick()
		local roll = (tt * ROLL_SPEED) % CYCLE
		local dead = roll >= ROLL_LEN
		if dead and not vpDead then
			-- Impact: last alive frame sits at the wall face — burst there.
			vpDead = true
			vpHitPos = vpBall.Position
			if wmodel then
				DeathFx.previewBurst(wmodel, vpHitPos :: Vector3, vpDeathItem)
			end
			vpBall.Transparency = 1
			for _, b in ipairs(vpMonkey) do
				b.part.Transparency = 1
			end
			for _, segs in ipairs(vpRings) do
				for _, p in ipairs(segs) do
					p.Transparency = 1
				end
			end
			vpTrailPts = {}
		elseif not dead and vpDead then
			-- Respawn wrap: re-dress the ball at the loop head.
			vpDead = false
			vpHitPos = nil
			vpBall.Transparency = vpBallAlpha
			for _, b in ipairs(vpMonkey) do
				b.part.Transparency = 0
			end
			for _, segs in ipairs(vpRings) do
				for _, p in ipairs(segs) do
					p.Transparency = 0
				end
			end
		end
		local z = ROLL_Z0 - math.min(roll, ROLL_LEN)
		-- Gentle lateral weave — the trail streams in a visible S instead
		-- of a dead-straight line, like real steering input.
		local sway = math.sin((tt * SWAY_W) % TAU) * SWAY_AMP
		local lean = math.cos((tt * SWAY_W) % TAU) * SWAY_BANK
		local bc = CFrame.new(sway, deckTopAt(z) + BALL_D / 2, z)
			* CFrame.Angles((-tt * ROLL_SPEED / (BALL_D / 2)) % TAU, 0, -lean)
		vpBall.CFrame = bc
		for _, b in ipairs(vpMonkey) do
			b.part.CFrame = bc * CFrame.new(b.off)
		end
		for i, segs in ipairs(vpRings) do
			local base = bc * vpRingRots[i] * RING_X
			for j, p in ipairs(segs) do
				p.CFrame = base * SEG_CFS[j]
			end
		end
		if vpCam then
			-- During the dead hold the cam keeps staring at the impact
			-- point so the burst reads.
			local focus = vpHitPos or bc.Position
			vpCam.CFrame = CFrame.lookAt(
				focus + Cam.Offset,
				focus + Gen.TravelAxis * Cam.LookAhead - Vector3.new(0, Gen.Grade * Cam.LookAhead + Cam.LookDrop, 0)
			)
		end
		if roll < vpLastRoll then
			-- Loop wrap: drop the stale ribbon so it doesn't streak back.
			vpTrailPts = {}
		end
		vpLastRoll = roll
		if vpTrailSegs[1] then
			if not vpDead then
				table.insert(vpTrailPts, 1, bc.Position)
				if #vpTrailPts > TRAIL_SEGS + 1 then
					table.remove(vpTrailPts)
				end
			end
			local tcol = vpTrailColor
			if vpRainbowTrail then
				tcol = Color3.fromHSV(h, 0.95, 1)
			elseif vpPaletteTrail then
				tcol = Palette.neonAt(tick() * 40)
			end
			for i, s in ipairs(vpTrailSegs) do
				local a, b = vpTrailPts[i], vpTrailPts[i + 1]
				local g = vpTrailGlow[i]
				if a and b then
					local f = i / TRAIL_SEGS
					local len = (a - b).Magnitude + 0.01
					-- White-hot at the ball cooling to the item color,
					-- plus a per-seg flicker so the wake shimmers.
					local flick = 0.07 * math.sin((tt * 17 + i * 1.9) % TAU)
					local core = CFrame.lookAt((a + b) / 2, b)
					s.CFrame = core
					s.Size = Vector3.new(1.2 * (1 - f) + 0.15, 0.07, len)
					s.Transparency = math.clamp(0.22 + 0.7 * f + flick, 0, 1)
					s.Color = tcol:Lerp(WHITE, math.max(0, 0.65 - f * 1.3))
					g.CFrame = core
					g.Size = Vector3.new(2.6 * (1 - f) + 0.3, 0.05, len)
					g.Transparency = math.clamp(0.55 + 0.43 * f, 0, 1)
					g.Color = tcol
				else
					s.Transparency = 1
					g.Transparency = 1
				end
			end
			-- Ember motes: sparks that peel off the wake, drift up and
			-- out, shrink and die — staggered lifecycles per mote.
			for j, m in ipairs(vpMotes) do
				local ph = (tt * 0.8 + j * 0.618) % 1
				local idx = 1 + ((j * 7) % math.max(#vpTrailPts, 1))
				local p = vpTrailPts[idx]
				if p then
					local jx = math.sin(j * 12.9) * (0.4 + ph * 3.2)
					local jz = math.cos(j * 7.3) * (0.4 + ph * 3.2)
					m.CFrame = CFrame.new(p + Vector3.new(jx, 0.3 + ph * 2.6, jz))
					m.Size = Vector3.one * (0.34 * (1 - ph) + 0.06)
					m.Transparency = 0.2 + ph * 0.78
					m.Color = tcol:Lerp(WHITE, math.max(0, 0.5 - ph))
				else
					m.Transparency = 1
				end
			end
		end
	end
	if vpGem and vpGemCf then
		-- Beat pulse — same swell fraction live pickups use.
		vpGem.Size = Vector3.one * vpGemSize * (1 + Config.Gems.BeatPulse * math.max(0, math.sin((tick() * 4) % TAU)))
		vpGem.CFrame = vpGemCf
	end
	if vpFx and ANIM_FX[vpFx] then
		for i, segs in ipairs(vpRings) do
			local col = fxColor(vpFx, i, h, k, vpBases[i])
			for _, p in ipairs(segs) do
				p.Color = col
			end
		end
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
