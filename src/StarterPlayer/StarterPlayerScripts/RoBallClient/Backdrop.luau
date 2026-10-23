--!strict
-- Backdrop (DESIGN.md §12): side-scenery + the striped synthwave sun parked
-- far down the slope. The WORLD cosmetic slot (§18) swaps the flanks:
--   "city"  — dark towers outlined in palette neon, recycled per row for
--             parallax (the default canyon).
--   "peaks" — NEON PEAKS: a seeded wireframe ridge field, neon edges over
--             near-black facets rising straight out of the void.
--   "void"  — STAR WELL: a shell of neon motes ringing the descent axis,
--             half below the deck plane — the drop reads as open space.
--   "grid"  — GRID PLANE: the retro wireframe floor riding the descent
--             below the deck — cross wires + longitudinal rays.
--   "aurora"— BOREALIS SKY: soft-particle light curtains flanking the
--             lane — the same frozen-burst emitter canopy as "polar",
--             fanned ALONG the track instead of across the sky.
--   "reef"  — NEON REEF: dense thin neon strands rising out of the void —
--             kelp on a wireframe reef.
--   "meteor"— METEOR SHOWER: thin neon streaks slanting through the sky
--             on real velocities, respawning ahead.
--   "palms" — MIAMI NIGHTS: neon palm rows planted beside the track —
--             a trunk, a fan of drooping fronds, two bead coconuts;
--             crowns rustle on a slow breeze sine.
--   "polar" — NORTHERN LIGHTS: the real aurora — a soft-particle canopy
--             of giant velocity-stretched streak sprites frozen
--             mid-flight by drag, fanned across the upper sky from
--             emitters re-anchored ahead of the ball; a sparse star
--             field rides the night band with it.
--   "sky"   — SKY COURT (APE BALL): the day-shift homage — midday
--             lighting so the whole world reads arcade blue, palm-
--             topped islets adrift in the blue, cartoon clouds, giant
--             two-tone goal arches the lane threads, and the shared
--             grove in a day palette.
-- All parts are client-local: zero replication cost, and they read as
-- parallax scenery because they sit in world space while the ball flies past.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local Art = Config.Art
local Gen = Config.Generation
local rng = Random.new()
local player = Players.LocalPlayer

local Backdrop = {}

local root: Folder
local sun: Model

type Seg = { part: Part, outline: SelectionBox }
type Tower = { segs: { Seg }, side: number, row: number }
local towers: { Tower } = {}
-- Outlines ramp in after a re-lay so a recycled tower materializes on
-- the horizon instead of popping in at full brightness.
local towerFades: { [Tower]: number } = {}
-- Per (side,row) frontier: the z where the next recycled tower goes.
local frontZ: { [string]: number } = {}

type PeakTile = { slot: number, side: number, z0: number, lines: { Part }, plates: { Part }, slab: Part }
local peakTiles: { PeakTile } = {}
local peaksSeeded = false
type Theme =
	"city"
	| "peaks"
	| "void"
	| "grid"
	| "aurora"
	| "reef"
	| "meteor"
	| "palms"
	| "polar"
	| "empty"
	| "toxic"
	| "sky"
local theme: Theme = "city"

-- Star-well pool (§18 "void") + grid-floor pool (§18 "grid") — both
-- lazily built on first activation, non-owners never pay for the parts.
local voidMotes: { Part } = {}
local voidSeeded = false

-- TOXIC WASTES pool (§18 "toxic") — same lazy-build contract.
type ToxicBubble = { part: Part, x: number, y0: number, z: number, rise: number, phase: number }
local toxicBubbles: { ToxicBubble } = {}
local toxicSeeded = false
local gridWires: { Part } = {} -- cross wires (one per GridRows)
local gridRays: { Part } = {} -- longitudinal rays (one per GridCols)
local gridFrontZ = 0 -- nearest cross-wire z; recycles march it forward
local gridSeeded = false

-- Wave-2 world themes (§18) — same lazy-build / park-on-swap contract.
type AuroraFan = { part: Part, emitter: ParticleEmitter, side: number, xOff: number, zOff: number, phase: number }
local auroraFans: { AuroraFan } = {}
type Strand = { part: Part, side: number }
local reefStrands: { Strand } = {}
local reefFrontZ: { [number]: number } = {}
local reefSeeded = false
type Meteor = { part: Part, vel: Vector3, speed: number }
local meteors: { Meteor } = {}
local meteorSeeded = false
local meteorClock = os.clock() -- dt source for real streak motion

-- POLAR (§18): soft-particle aurora canopy + a star band, same
-- lazy/park contract.
type PolarFan = {
	part: Part,
	emitter: ParticleEmitter,
	zOff: number,
	yaw: number,
	phase: number,
}
local polarFans: { PolarFan } = {}
local polarStars: { Part } = {}
local polarSeeded = false

-- PALMS (§18): same lazy-build / park-on-swap contract. A palm is a trunk
-- part + a fan of drooping frond blades + two coconut beads; `crown`
-- caches the trunk top so the per-frame breeze can re-fan the fronds.
type Frond = { part: Part, yaw: number, droop: number, len: number, wob: number }
type Palm = {
	side: number,
	row: number,
	trunk: Part,
	fronds: { Frond },
	beads: { Part },
	crown: Vector3,
	phase: number,
}
local palms: { Palm } = {}
local palmFrontZ: { [string]: number } = {}
local palmSeeded = false

-- SKY COURT (§18 "sky", APE BALL): chunky puff clouds drift beside the
-- track and re-enter ahead. `offs` caches each lobe's offset so the
-- per-frame bob only rewrites Position — no per-frame allocation.
type SkyCloud = { parts: { Part }, offs: { Vector3 }, x: number, y: number, z: number, phase: number }
-- The islands-in-the-sky read: each islet is a sandy mass + grass dome
-- + one static palm (own Palm record — never in the grove pool, so
-- stepPalms won't recycle it), laid once per re-entry, hanging at
-- SkyIsleDrop below deck grade in the open blue.
type SkyIsland = { dome: Part, base: Part, palm: Palm, z: number }
-- Goal arches (SMB's finish-gate homage): a full ring standing across
-- the lane, lifted so the ball threads the hole while the lower arc
-- swings beneath the deck into the open blue. Alternating stripe
-- colors carry the finish-line read; recycled on the same frontier
-- pattern as the islets.
type SkyGate = { segs: { Part }, z: number }
local skyClouds: { SkyCloud } = {}
local skyIslands: { SkyIsland } = {}
local skyGates: { SkyGate } = {}
local skySeeded = false

local FACE_COLOR = Color3.fromRGB(8, 4, 14)
local WHITE = Color3.fromRGB(245, 238, 255) -- star glints in the void theme
-- Parked parts sit far below at +z, past the recycle gate: reactivating a
-- theme re-seeds it and every dormant part earns a fresh lay in one pass.
local PARK = CFrame.new(0, -10000, 5000)
local BACK_MARGIN = 80 -- studs behind the ball kept covered before recycle

local function parkPart(p: BasePart)
	p.CFrame = PARK
end

local function makeSeg(parent: Instance): Seg
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color = FACE_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = PARK
	p.Parent = parent
	local box = Instance.new("SelectionBox")
	box.Adornee = p
	box.LineThickness = Art.LineThickness
	box.SurfaceTransparency = 1
	box.Parent = p
	return { part = p, outline = box }
end

local function makeTower(parent: Instance, side: number, row: number): Tower
	local model = Instance.new("Model")
	model.Name = "Tower"
	model.Parent = parent
	local segs = {}
	for _ = 1, Art.CitySegsMax do
		table.insert(segs, makeSeg(model))
	end
	return { segs = segs, side = side, row = row }
end

-- Re-lay a tower: 1-3 stacked segments, each narrower than the one below,
-- bases sunk below the local deck height so the canyon hugs the slope.
local function layTower(tower: Tower, x: number, baseY: number, z: number, color: Color3)
	local w = rng:NextNumber(Art.CityMinW, Art.CityMaxW)
	local d = rng:NextNumber(Art.CityMinD, Art.CityMaxD)
	local hTotal = rng:NextNumber(Art.CityMinH, Art.CityMaxH)
	local nSegs = rng:NextInteger(1, Art.CitySegsMax)
	local y = baseY
	for i, seg in ipairs(tower.segs) do
		if i <= nSegs then
			local h = hTotal * rng:NextNumber(0.28, 0.6) / nSegs * 2
			if i == nSegs then
				h = baseY + hTotal - y -- top seg absorbs rounding
			end
			local shrink = 1 - (i - 1) * rng:NextNumber(0.15, 0.3)
			local sw, sd = w * shrink, d * shrink
			seg.part.Size = Vector3.new(sw, h, sd)
			seg.part.CFrame = CFrame.new(x + rng:NextNumber(-4, 4) * (i - 1), y + h / 2, z)
			seg.outline.Color3 = color
			y += h
		else
			-- parked far below: invisible, no layout cost
			parkPart(seg.part)
		end
	end
end

--============================ NEON PEAKS ============================--
-- A displaced grid mesh: neon edges over near-black tilted facets, plus a
-- dark slab under each tile so the range occludes the void instead of
-- reading as a translucent lattice. Ridge heights are a pure function of
-- (side, column, world-lattice row) — tiles recycle independently yet meet
-- in perfect seams, and the terrain keeps generating fresh forever.

-- Ridge height 0..1: ridged noise (sharp crests) + a detail octave, ramped
-- from ~0 at the road edge to full amplitude at the outermost column, and
-- swelled by a slow along-z envelope so ranges arrive in passes instead of
-- an unbroken wall.
local function peakRidge(side: number, c: number, row: number): number
	local n = math.noise(c * Art.PeaksFreqX + side * 61.7, row * Art.PeaksFreqZ, Art.PeaksSeed)
	local d = math.noise(c * Art.PeaksFreqX * 2.7 + 31.4, row * Art.PeaksFreqZ * 2.7 - side * 17.9, Art.PeaksSeed + 101)
	local crest = math.max(0, 0.5 - math.abs(n)) * 2
	local h = (crest ^ Art.PeaksPeakPow) * 0.85 + (d + 0.5) * 0.15
	local ramp = ((c + 0.3) / Art.PeaksCols) ^ Art.PeaksRampPow
	local env =
		math.clamp(0.62 + math.noise(row * Art.PeaksEnvF, side * 9.13, Art.PeaksSeed + 57) * 1.5, Art.PeaksEnvFloor, 1)
	return h * ramp * env
end

-- Deck-plane estimate at z: the linear grade is the upper bound (gap
-- chunks only subtract), so min() with the ball-derived grade keeps the
-- strip glued through RampGap drops without ballooning on jump arcs.
local function deckEst(anchor: Vector3, z: number): number
	return math.min(Gen.StartY + Gen.Grade * z, anchor.Y - Gen.Grade * (anchor.Z - z))
end

local function makePeakPart(parent: Instance, neon: boolean): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.Color = FACE_COLOR
	p.CFrame = PARK
	p.Parent = parent
	return p
end

-- Built lazily on first activation — non-owners never pay for the parts.
local function ensurePeaks()
	if #peakTiles > 0 then
		return
	end
	local nLines = (Art.PeaksCols + 1) * Art.PeaksRows + Art.PeaksCols * (Art.PeaksRows + 1)
	for side = -1, 1, 2 do
		for slot = 1, Art.PeaksTiles do
			local model = Instance.new("Model")
			model.Name = "Peaks"
			model.Parent = root
			local lines: { Part } = {}
			local plates: { Part } = {}
			for _ = 1, nLines do
				table.insert(lines, makePeakPart(model, true))
			end
			for _ = 1, Art.PeaksCols * Art.PeaksRows do
				table.insert(plates, makePeakPart(model, false))
			end
			table.insert(peakTiles, {
				slot = slot,
				side = side,
				z0 = 0,
				lines = lines,
				plates = plates,
				slab = makePeakPart(model, false),
			})
		end
	end
end

-- Re-lay a tile at its current z0: vertices lock to the world lattice in z
-- and to the lane grid in x, so the strip is internally coherent forever
-- while tiny inter-tile steps read as geological faulting, not cracks.
local function layTile(tile: PeakTile, anchor: Vector3)
	local cols, rows = Art.PeaksCols, Art.PeaksRows
	local cellX, cellZ = Art.PeaksCellX, Art.PeaksCellZ
	local laneX = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
	local side = tile.side

	local verts: { { Vector3 } } = table.create(cols + 1)
	for c = 0, cols do
		local col: { Vector3 } = table.create(rows + 1)
		local x = laneX + side * (Art.PeaksInnerX + c * cellX)
		for r = 0, rows do
			local z = tile.z0 + r * cellZ
			local row = math.round(z / cellZ)
			local y = deckEst(anchor, z) - Art.PeaksSkirt + peakRidge(side, c, row) * Art.PeaksMaxH
			col[r + 1] = Vector3.new(x, y, z)
		end
		verts[c + 1] = col
	end

	-- Edge tint: the distance wheel flows along z like the deck grid, and
	-- outer columns dim a touch for a cheap depth cue.
	local function edgeColor(xMid: number, zMid: number): Color3
		local reach = math.clamp((math.abs(xMid - laneX) - Art.PeaksInnerX) / (cols * cellX), 0, 1)
		return Palette.dimAt(-zMid, Art.PeaksValue * (1 - 0.4 * reach))
	end

	local li = 0
	local function stroke(a: Vector3, b: Vector3)
		li += 1
		local p = tile.lines[li]
		local mid = (a + b) / 2
		p.Size = Vector3.new(Art.PeaksLine, Art.PeaksLine, (b - a).Magnitude)
		p.CFrame = CFrame.lookAt(mid, b)
		p.Color = edgeColor(mid.X, mid.Z)
	end
	for c = 0, cols do
		for r = 0, rows - 1 do
			stroke(verts[c + 1][r + 1], verts[c + 1][r + 2])
		end
	end
	for r = 0, rows do
		for c = 0, cols - 1 do
			stroke(verts[c + 1][r + 1], verts[c + 2][r + 1])
		end
	end

	-- Facets: one tilted plate per quad. Its top face sinks to just under
	-- the lowest corner, so the neon edges always ride on top while the
	-- dark facet still catches slight ambient differences — the shaded
	-- ridge sides from the reference look.
	local pi = 0
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			pi += 1
			local a, b = verts[c + 1][r + 1], verts[c + 2][r + 1]
			local c2, e = verts[c + 1][r + 2], verts[c + 2][r + 2]
			local n = (c2 - b):Cross(e - a)
			local up = if n.Y < 0 then -n.Unit else n.Unit
			local right0 = (b - a) + (e - c2)
			local right = (right0 - up * right0:Dot(up)).Unit
			local cen = (a + b + c2 + e) / 4
			local minK = math.huge
			for _, v in ipairs({ a, b, c2, e }) do
				minK = math.min(minK, (v - cen):Dot(up))
			end
			local plate = tile.plates[pi]
			plate.Size = Vector3.new(cellX * 1.04, 4, cellZ * 1.04)
			plate.CFrame = CFrame.fromMatrix(cen + up * (minK - 0.4 - 2), right, up, right:Cross(up))
			plate.Color = FACE_COLOR:Lerp(Palette.neonAt(-cen.Z), Art.PeaksFaceTint)
		end
	end

	-- Massif body: a grade-pitched dark slab below road level, so the range
	-- silhouettes solid against the sun and the void never shows through.
	local tileLen = rows * cellZ
	local slabT = 24
	local xIn = laneX + side * (Art.PeaksInnerX - 8)
	local xOut = laneX + side * (Art.PeaksInnerX + cols * cellX + 40)
	local cx = (xIn + xOut) / 2
	local zF, zB = tile.z0 - 1, tile.z0 + tileLen + 1
	local a = Vector3.new(cx, deckEst(anchor, zF) - Art.PeaksSkirt - slabT / 2, zF)
	local b = Vector3.new(cx, deckEst(anchor, zB) - Art.PeaksSkirt - slabT / 2, zB)
	local dist = (b - a).Magnitude
	tile.slab.Size = Vector3.new(math.abs(xOut - xIn), slabT, dist)
	tile.slab.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -dist / 2)
	tile.slab.Color = FACE_COLOR
end

--============================ STAR WELL (void) ============================--
-- Neon motes on a shell around the descent axis: azimuth + shell radius are
-- fixed per mote, only z recycles forward — so the field holds structure
-- while the drop sells depth. Half the shell sits below the deck plane;
-- that's what makes it a well and not a skybox.

local function ensureVoid()
	if #voidMotes > 0 then
		return
	end
	for _ = 1, Art.VoidStars do
		local mote = Instance.new("Part")
		mote.Anchored = true
		mote.CanCollide = false
		mote.CanQuery = false
		mote.CastShadow = false
		mote.Material = Enum.Material.Neon
		mote.Shape = Enum.PartType.Ball
		mote.Size = Vector3.new(Art.VoidSize, Art.VoidSize, Art.VoidSize) * rng:NextNumber(0.5, 1.9)
		mote.CFrame = PARK
		mote.Parent = root
		table.insert(voidMotes, mote)
	end
end

local function layVoidMote(mote: Part, anchor: Vector3)
	local az = rng:NextNumber(0, math.pi * 2)
	local r = Art.VoidRadius * rng:NextNumber(0.75, 1.15)
	local z = anchor.Z - rng:NextNumber(0, Art.VoidZSpan)
	mote.Position = Vector3.new(anchor.X + math.cos(az) * r, anchor.Y + math.sin(az) * r, z)
	-- Mostly palette hue, a quarter pure white — the star glint.
	mote.Color = if rng:NextNumber() < 0.25
		then WHITE
		else Palette.dimAt(-z * 0.3 + rng:NextNumber(0, 200), Art.VoidValue)
end

--========================== TOXIC WASTES (toxic) ==========================--
-- Acid runoff flanking the lane: lime Neon spheres boil up out of the
-- dark below deck, climb ToxicRiseSpan on a per-bubble phase, and pop
-- back to base when the phase wraps — a perpetual simmer that never
-- marches in step. z recycles on the usual frontier like the star motes;
-- the climb is computed from the clock, so no velocity state to keep.

local TOXIC_LIME = Color3.fromRGB(170, 255, 60)
local TOXIC_DEEP = Color3.fromRGB(70, 190, 70)
local TOXIC_GLINT = Color3.fromRGB(215, 255, 170)

local function styleToxicBubble(b: Part)
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.one * rng:NextNumber(Art.ToxicSizeMin, Art.ToxicSizeMax)
	b.Transparency = Art.ToxicAlpha + rng:NextNumber(0, 0.3)
	local roll = rng:NextNumber()
	b.Color = if roll < 0.15 then TOXIC_GLINT elseif roll < 0.55 then TOXIC_LIME else TOXIC_DEEP
end

local function ensureToxic()
	if #toxicBubbles > 0 then
		return
	end
	for _ = 1, Art.ToxicCount do
		local part = makePeakPart(root, true)
		styleToxicBubble(part)
		table.insert(toxicBubbles, {
			part = part,
			x = 0,
			y0 = 0,
			z = 0,
			rise = rng:NextNumber(Art.ToxicRiseMin, Art.ToxicRiseMax),
			phase = rng:NextNumber(0, Art.ToxicRiseSpan),
		})
	end
end

local function layToxicBubble(b: ToxicBubble, anchor: Vector3)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	b.x = anchor.X + side * (Art.ToxicSideMin + rng:NextNumber(0, Art.ToxicSideJitter))
	b.z = anchor.Z + BACK_MARGIN - rng:NextNumber(0, Art.ToxicZSpan)
	b.y0 = deckEst(anchor, b.z) - rng:NextNumber(Art.ToxicDepthMin, Art.ToxicDepthMax)
end

-- Every frame: recycle spent bubbles, then advance each climb. The
-- lateral sway keeps the column organic instead of a straight lift.
local function stepToxic(anchor: Vector3)
	local now = os.clock()
	for _, b in ipairs(toxicBubbles) do
		if not toxicSeeded or b.z > anchor.Z + BACK_MARGIN then
			layToxicBubble(b, anchor)
		end
		local climb = (now * b.rise + b.phase) % Art.ToxicRiseSpan
		local wob = math.sin(now * 1.3 + b.phase) * 1.6
		b.part.Position = Vector3.new(b.x + wob, b.y0 + climb, b.z)
	end
	toxicSeeded = true
end

--=========================== GRID PLANE (grid) ===========================--
-- The wireframe floor riding the descent below the deck. Cross wires
-- recycle on a frontier like the tower rows; the long rays stride their
-- own window length — both pitch to the grade so the plane stays parallel
-- to the slope instead of drifting through it.

local function ensureGrid()
	if #gridWires > 0 then
		return
	end
	for _ = 1, Art.GridFloorRows do
		local wire = makePeakPart(root, true)
		table.insert(gridWires, wire)
	end
	for _ = 1, Art.GridFloorCols do
		table.insert(gridRays, makePeakPart(root, true))
	end
end

local function layGridWire(wire: Part, anchor: Vector3, z: number, laneX: number)
	local y = deckEst(anchor, z) - Art.GridFloorDrop
	local x0, x1 = laneX - Art.GridFloorHalfX, laneX + Art.GridFloorHalfX
	wire.Size = Vector3.new(x1 - x0, Art.GridFloorLine, Art.GridFloorLine)
	wire.Position = Vector3.new(laneX, y, z)
	wire.Color = Palette.dimAt(-z, Art.GridFloorValue)
end

local function layGridRay(ray: Part, anchor: Vector3, z0: number, x: number)
	local len = Art.GridFloorRows * Art.GridFloorCellZ
	local zA, zB = z0, z0 - len
	local a = Vector3.new(x, deckEst(anchor, zA) - Art.GridFloorDrop, zA)
	local b = Vector3.new(x, deckEst(anchor, zB) - Art.GridFloorDrop, zB)
	ray.Size = Vector3.new(Art.GridFloorLine, Art.GridFloorLine, (b - a).Magnitude)
	ray.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -(b - a).Magnitude / 2)
	ray.Color = Palette.dimAt(-zA, Art.GridFloorValue)
end

--================= SOFT-PARTICLE FANS (aurora + polar) =================--
-- Both aurora themes share the canonical one-emitter trick: giant
-- VelocityPerpendicular streak sprites burst thousands of studs out of
-- the emitter and Drag freezes them mid-flight — what was a burst lands
-- as a luminous canopy of rays. SpreadAngle (180,0) fans the burst in
-- the emitter part's local X-Y plane, so each part's pose picks where
-- that plane hangs in the sky. Sprites fade in/out on FAN_FADE — the
-- canopy churns without pops.

type FanSpec = {
	texture: string,
	colors: ColorSequence,
	rate: number,
	speed: number,
	drag: number,
	size: number,
	squash: number,
	lifeMin: number,
	lifeMax: number,
	emission: number,
}

local FAN_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 1),
	NumberSequenceKeypoint.new(0.55, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local function makeFanPart(parent: Instance, spec: FanSpec): { part: Part, emitter: ParticleEmitter }
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = PARK
	p.Parent = parent
	local em = Instance.new("ParticleEmitter")
	em.Texture = spec.texture
	em.Color = spec.colors
	em.Transparency = FAN_FADE
	em.Brightness = 1
	em.LightEmission = spec.emission
	em.LightInfluence = 0
	em.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	em.Size = NumberSequence.new(spec.size)
	em.Squash = NumberSequence.new(spec.squash)
	em.Lifetime = NumberRange.new(spec.lifeMin, spec.lifeMax)
	em.Rate = spec.rate
	em.Speed = NumberRange.new(spec.speed)
	em.SpreadAngle = Vector2.new(180, 0)
	em.Drag = spec.drag
	em.EmissionDirection = Enum.NormalId.Top
	em.Enabled = false
	em.Parent = p
	return { part = p, emitter = em }
end

--=========================== BOREALIS SKY (aurora) ==========================--
-- Curtains of light flanking the lane: each emitter fan is yawed 90° so
-- its sprite plane runs ALONG the track at x=±FanX — the fan covers
-- forward + backward + up, so rays streak past and over the deck like
-- hanging curtains (polar's fans span the sky overhead instead). Fans
-- re-anchor beside the ball every frame — no recycling.

local AURORA_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 255, 170)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(160, 235, 255)),
	ColorSequenceKeypoint.new(0.65, Color3.fromRGB(170, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 230)),
})

local function makeAuroraFan(parent: Instance): AuroraFan
	local f = makeFanPart(parent, {
		texture = Art.AuroraTexture,
		colors = AURORA_COLORS,
		rate = Art.AuroraRate,
		speed = Art.AuroraSpeed,
		drag = Art.AuroraDrag,
		size = Art.AuroraSize,
		squash = Art.AuroraSquash,
		lifeMin = Art.AuroraLifeMin,
		lifeMax = Art.AuroraLifeMax,
		emission = Art.AuroraEmission,
	})
	return { part = f.part, emitter = f.emitter, side = 0, xOff = 0, zOff = 0, phase = 0 }
end

local function ensureAurora()
	if #auroraFans > 0 then
		return
	end
	for side = -1, 1, 2 do
		for i = 1, Art.AuroraFanSides do
			local f = makeAuroraFan(root)
			f.side = side
			f.xOff = Art.AuroraFanX + rng:NextNumber(0, Art.AuroraFanXJitter)
			f.zOff = Art.AuroraFanZ + (i - 1) * Art.AuroraFanZGap
			f.phase = rng:NextNumber(0, math.pi * 2)
			table.insert(auroraFans, f)
		end
	end
end

-- Per-frame: re-anchor the fans beside the lane with a slow lateral
-- drift + yaw wobble so the curtains wander.
local function stepAurora(anchor: Vector3, t: number)
	for _, f in ipairs(auroraFans) do
		f.emitter.Enabled = true
		local drift = math.sin(t * 0.11 + f.phase) * 14
		local yaw = math.pi / 2 + math.sin(t * 0.07 + f.phase * 1.3) * 0.1
		f.part.CFrame = CFrame.new(anchor.X + f.side * (f.xOff + drift), anchor.Y + Art.AuroraFanY, anchor.Z - f.zOff)
			* CFrame.Angles(0, yaw, 0)
	end
end

--========================= NORTHERN LIGHTS (polar) =========================--
-- The real aurora look comes from soft particles, not part sheets:
-- huge VelocityPerpendicular streak sprites burst thousands of studs
-- out of the emitter and Drag freezes them mid-flight — what was a
-- burst lands as a soft luminous canopy (the classic one-emitter
-- aurora trick). SpreadAngle (180,0) fans the burst in a plane; the
-- part stays unrotated (emission Top = +Y) so the fan sweeps the whole
-- upper semicircle ACROSS the lane. Emitter parts re-anchor ahead of
-- the ball every frame — the canopy hangs over the track forever with
-- no recycling. A sparse star field rides the band so it reads as
-- night sky, not a ceiling.

local STAR_BLUE = Color3.fromRGB(170, 190, 255)
local STAR_GREEN = Color3.fromRGB(150, 255, 210)

-- Aurora palette — the classic green→white→cyan→green→pale-yellow
-- gradient; every hue sits inside the color law's window.
local POLAR_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(141, 255, 133)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(233, 255, 241)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(165, 243, 255)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(108, 255, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(247, 255, 174)),
})

local function makePolarFan(parent: Instance): PolarFan
	local f = makeFanPart(parent, {
		texture = Art.PolarTexture,
		colors = POLAR_COLORS,
		rate = Art.PolarRate,
		speed = Art.PolarSpeed,
		drag = Art.PolarDrag,
		size = Art.PolarSize,
		squash = Art.PolarSquash,
		lifeMin = Art.PolarLifeMin,
		lifeMax = Art.PolarLifeMax,
		emission = Art.PolarEmission,
	})
	return {
		part = f.part,
		emitter = f.emitter,
		zOff = 0,
		yaw = rng:NextNumber(-Art.PolarFanYaw, Art.PolarFanYaw),
		phase = rng:NextNumber(0, math.pi * 2),
	}
end

local function ensurePolar()
	if #polarFans > 0 then
		return
	end
	for i = 1, Art.PolarFans do
		local f = makePolarFan(root)
		f.zOff = Art.PolarFanZ + (i - 1) * Art.PolarFanZGap
		table.insert(polarFans, f)
	end
	for _ = 1, Art.PolarStars do
		local s = Instance.new("Part")
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CastShadow = false
		s.Material = Enum.Material.Neon
		s.Shape = Enum.PartType.Ball
		s.Size = Vector3.new(1, 1, 1) * rng:NextNumber(0.5, 1.6)
		s.CFrame = PARK
		s.Parent = root
		table.insert(polarStars, s)
	end
end

local function layPolarStar(s: Part, anchor: Vector3)
	local z = anchor.Z - rng:NextNumber(0, Art.PolarStarZSpan)
	s.Position = Vector3.new(
		anchor.X + rng:NextNumber(-Art.PolarStarX, Art.PolarStarX),
		anchor.Y + rng:NextNumber(Art.PolarStarAltMin, Art.PolarStarAltMax),
		z
	)
	-- Mostly white glints, a few tinted to the aurora family.
	local r = rng:NextNumber()
	s.Color = if r < 0.7 then WHITE elseif r < 0.85 then STAR_BLUE else STAR_GREEN
end

-- Per-frame: re-anchor each emitter fan ahead of the ball with a slow
-- yaw drift so the canopy planes wander; stars re-scatter as they pass.
local function stepPolar(anchor: Vector3, t: number)
	for _, f in ipairs(polarFans) do
		f.emitter.Enabled = true
		f.part.CFrame = CFrame.new(anchor.X, anchor.Y + Art.PolarFanY, anchor.Z - f.zOff)
			* CFrame.Angles(0, f.yaw + math.sin(t * 0.05 + f.phase) * 0.15, 0)
	end
	for _, s in ipairs(polarStars) do
		if s.Position.Z > anchor.Z + BACK_MARGIN then
			layPolarStar(s, anchor)
		end
	end
end

--============================ NEON REEF (reef) ============================--
-- Dense thin strands rising out of the void beside the deck — kelp on a
-- wireframe reef. Static parts (no per-frame anim): they read alive purely
-- from the speed of the run. Bases sink below the deck plane, tips may
-- poke above it — the lane threads a glowing weed-bed.

local function ensureReef()
	if #reefStrands > 0 then
		return
	end
	for side = -1, 1, 2 do
		for _ = 1, Art.ReefCount do
			local p = makePeakPart(root, true)
			table.insert(reefStrands, { part = p, side = side })
		end
	end
end

local function layStrand(s: Strand, anchor: Vector3, z: number)
	local laneX = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
	local h = rng:NextNumber(Art.ReefMinH, Art.ReefMaxH)
	local x = laneX + s.side * rng:NextNumber(Art.ReefMinX, Art.ReefMaxX)
	local baseY = deckEst(anchor, z) - rng:NextNumber(0, Art.ReefSink)
	local p = s.part
	p.Size = Vector3.new(Art.ReefW, h, Art.ReefW)
	p.Position = Vector3.new(x, baseY + h / 2 + Art.ReefFloat * 0.4, z)
	p.Color = Palette.dimAt(-z + rng:NextNumber(0, 120), Art.ReefValue)
end

--========================== METEOR SHOWER (meteor) =========================--
-- The one animated sky: thin neon streaks on real velocities, respawning
-- ahead once they fall below the deck or slip behind. Orientation is fixed
-- at spawn (a straight streak) — motion does all the selling.

local function ensureMeteors()
	if #meteors > 0 then
		return
	end
	for _ = 1, Art.MeteorCount do
		local p = makePeakPart(root, true)
		table.insert(meteors, { part = p, vel = Vector3.new(0, -1, 0), speed = 0 })
	end
end

local function layMeteor(m: Meteor, anchor: Vector3)
	local z = anchor.Z - rng:NextNumber(0, Art.MeteorSpan)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local x = anchor.X + side * rng:NextNumber(Art.MeteorMinX, Art.MeteorMaxX)
	local y = deckEst(anchor, z) + rng:NextNumber(Art.MeteorAltMin, Art.MeteorAltMax)
	local dir = Vector3.new(rng:NextNumber(-0.45, 0.45), -1, rng:NextNumber(-0.25, 0.15)).Unit
	m.vel = dir
	m.speed = rng:NextNumber(Art.MeteorSpeedMin, Art.MeteorSpeedMax)
	local p = m.part
	p.Size = Vector3.new(0.55, 0.55, rng:NextNumber(Art.MeteorLenMin, Art.MeteorLenMax))
	p.CFrame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + dir)
	p.Color = if rng:NextNumber() < Art.MeteorWhite then WHITE else Palette.dimAt(-z, Art.MeteorValue)
end

local function stepMeteors(anchor: Vector3, dt: number)
	for _, m in ipairs(meteors) do
		local pos = m.part.Position + m.vel * (m.speed * dt)
		if
			not meteorSeeded
			or pos.Y < deckEst(anchor, pos.Z) - Art.MeteorDrop
			or pos.Z > anchor.Z + 40
			or math.abs(pos.X - anchor.X) > 480
		then
			layMeteor(m, anchor)
		else
			m.part.Position = pos
		end
	end
	meteorSeeded = true
end

--============================ PALMS ============================--
-- Neon palm rows (§18 "palms"): a dark violet trunk, PalmFronds thin
-- blades fanning out of the crown on cyan→magenta, two bead coconuts.
-- Frond yaw/droop/len are authored at lay time; the update loop re-fans
-- them a few degrees on a slow sine so the grove breathes.

local PALM_TRUNK = Color3.fromRGB(46, 16, 64) -- dark violet neon
local PALM_BEAD = Color3.fromRGB(255, 46, 160) -- hot pink coconuts
local PALM_FROND_A = Color3.fromRGB(0, 230, 255)
local PALM_FROND_B = Color3.fromRGB(255, 64, 190)

-- Grove palettes: layPalm restyles trunk/fronds/beads on every recycle,
-- so SKY COURT can grow the same grove in a day palette (brown trunks,
-- green fronds, banana beads, matte plastic) without a second pool.
type PalmStyle = { trunk: Color3, frondA: Color3, frondB: Color3, bead: Color3, shade: Color3, mat: Enum.Material }
local MIAMI_PALM: PalmStyle = {
	trunk = PALM_TRUNK,
	frondA = PALM_FROND_A,
	frondB = PALM_FROND_B,
	bead = PALM_BEAD,
	shade = FACE_COLOR,
	mat = Enum.Material.Neon,
}

local function makePalmPart(parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.CFrame = PARK
	p.Parent = parent
	return p
end

local function makePalm(parent: Instance, side: number, row: number): Palm
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent
	local trunk = makePalmPart(model)
	trunk.Color = PALM_TRUNK
	local fronds: { Frond } = {}
	for _ = 1, Art.PalmFronds do
		table.insert(fronds, {
			part = makePalmPart(model),
			yaw = 0,
			droop = 1,
			len = Art.PalmFrondLen,
			wob = rng:NextNumber(0.6, 1),
		})
	end
	local beads: { Part } = {}
	for _ = 1, 2 do
		local b = makePalmPart(model)
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.new(1.4, 1.4, 1.4)
		b.Color = PALM_BEAD
		table.insert(beads, b)
	end
	return {
		side = side,
		row = row,
		trunk = trunk,
		fronds = fronds,
		beads = beads,
		crown = PARK.Position,
		phase = rng:NextNumber(0, math.pi * 2),
	}
end

local function ensurePalms()
	if #palms > 0 then
		return
	end
	for side = -1, 1, 2 do
		for row = 1, Art.PalmRows do
			for _ = 1, math.floor(Art.PalmSpan / Art.PalmSpacing) do
				table.insert(palms, makePalm(root, side, row))
			end
		end
	end
end

-- Re-lay a palm at (x, baseY, z): lean a fresh trunk, fan the crown with
-- jittered yaw/droop/length, park the beads at its base. Frond blades
-- extend along +X from the crown — yaw fans them, -droop tips them down.
-- `sty` restyles every piece each lay, so a theme swap migrates the
-- shared grove's whole look within one recycle pass.
local function layPalm(palm: Palm, x: number, baseY: number, z: number, sty: PalmStyle)
	local h = rng:NextNumber(Art.PalmTrunkMin, Art.PalmTrunkMax)
	local lean = rng:NextNumber(-0.12, 0.12)
	palm.trunk.Material = sty.mat
	palm.trunk.Color = sty.trunk
	palm.trunk.Size = Vector3.new(1.4, h, 1.4)
	palm.trunk.CFrame = CFrame.new(x, baseY + h / 2, z) * CFrame.Angles(lean, 0, lean * 0.5)
	palm.crown = Vector3.new(x, baseY + h, z)
	local n = #palm.fronds
	local shade = 1 - (palm.row - 1) * 0.3 -- outer row dims like the far tower rows
	for i, f in ipairs(palm.fronds) do
		f.yaw = ((i - 1) / n) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		f.droop = rng:NextNumber(Art.PalmDroopMin, Art.PalmDroopMax)
		f.len = Art.PalmFrondLen * rng:NextNumber(0.85, 1.2)
		f.part.Material = sty.mat
		f.part.Size = Vector3.new(f.len, 0.35, 1.1)
		f.part.Color =
			sty.frondA:Lerp(sty.frondB, (i - 1) / math.max(n - 1, 1)):Lerp(sty.shade, 1 - Art.PalmValue * shade)
		f.part.CFrame = CFrame.new(palm.crown) * CFrame.Angles(0, f.yaw, -f.droop) * CFrame.new(f.len / 2, 0, 0)
	end
	for i, b in ipairs(palm.beads) do
		local a = (i - 1) * 2.1 + rng:NextNumber(0, 0.6)
		b.Material = sty.mat
		b.Color = sty.bead
		b.CFrame = CFrame.new(palm.crown + Vector3.new(math.cos(a) * 0.9, -0.7, math.sin(a) * 0.9))
	end
end

-- The grove step, shared by MIAMI NIGHTS and SKY COURT: rows recycle on
-- a per-(side,row) frontier like the tower canyon; every frame the
-- crowns rustle on a slow sine. `sty` dresses the lay.
local function stepPalms(anchor: Vector3, sty: PalmStyle)
	ensurePalms()
	if not palmSeeded then
		palmSeeded = true
		for side = -1, 1, 2 do
			for row = 1, Art.PalmRows do
				palmFrontZ[side .. ":" .. row] = anchor.Z + Art.PalmSpacing
			end
		end
	end
	local breeze = math.rad(Art.PalmSwayDeg) * math.sin(os.clock() * Art.PalmSwayRate)
	for _, palm in ipairs(palms) do
		if palm.trunk.Position.Z > anchor.Z + 60 then
			local key = palm.side .. ":" .. palm.row
			local z = palmFrontZ[key] - Art.PalmSpacing
			palmFrontZ[key] = z
			local x = anchor.X + palm.side * (Art.PalmMinX + (palm.row - 1) * Art.PalmRowDX + rng:NextNumber(0, 14))
			local ahead = math.max(anchor.Z - z, 0)
			local baseY = anchor.Y - Gen.Grade * ahead - rng:NextNumber(4, 10)
			layPalm(palm, x, baseY, z, sty)
		end
		local sway = breeze * math.cos(palm.phase)
		for _, f in ipairs(palm.fronds) do
			f.part.CFrame = CFrame.new(palm.crown)
				* CFrame.Angles(0, f.yaw + breeze * math.sin(palm.phase) * 0.4, -(f.droop + sway * f.wob))
				* CFrame.new(f.len / 2, 0, 0)
		end
	end
end

--============================ SKY COURT (§18 "sky") ============================--
-- Built lazily on first activation — non-owners never pay for the parts.
-- The grove is SHARED with MIAMI NIGHTS: same palm pool/frontier, just a
-- day palette + matte material at lay time (brown trunks, green fronds,
-- banana beads — the tropical course look).
local SKY_PALM: PalmStyle = {
	trunk = Art.SkyPalmTrunk,
	frondA = Art.SkyPalmFrondA,
	frondB = Art.SkyPalmFrondB,
	bead = Art.SkyPalmBead,
	shade = Art.SkyPalmShade,
	mat = Enum.Material.SmoothPlastic,
}

local function ensureSky()
	if #skyClouds > 0 then
		return
	end
	for _ = 1, Art.SkyClouds do
		local parts: { Part } = {}
		for _ = 1, 4 do
			local puff = makePeakPart(root, false)
			puff.Shape = Enum.PartType.Ball
			puff.Color = Art.SkyCloudColor
			table.insert(parts, puff)
		end
		table.insert(
			skyClouds,
			{ parts = parts, offs = {}, x = 0, y = 0, z = 0, phase = rng:NextNumber(0, math.pi * 2) }
		)
	end
	for _ = 1, Art.SkyIslands do
		local base = makePeakPart(root, false)
		base.Shape = Enum.PartType.Ball
		base.Color = Art.SkyIslandSide
		local dome = makePeakPart(root, false)
		dome.Shape = Enum.PartType.Ball
		dome.Color = Art.SkyIslandTop
		table.insert(skyIslands, { dome = dome, base = base, palm = makePalm(root, 0, 1), z = math.huge })
	end
	for _ = 1, Art.SkyGates do
		local segs: { Part } = {}
		for _ = 1, Art.SkyGateSegs do
			table.insert(segs, makePeakPart(root, false))
		end
		table.insert(skyGates, { segs = segs, z = math.huge })
	end
end

-- Re-lay a puff cloud: a 4-lobe blob drifting beside the lane at a
-- random side/altitude band. Lobe offsets + sizes are re-rolled here
-- once; the per-frame bob then only rewrites Position.
local CLOUD_SIZE = { 16, 11, 10, 8 }
local function laySkyCloud(c: SkyCloud, anchor: Vector3, z: number)
	c.z = z
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	c.x = anchor.X + side * (Art.SkyCloudMinX + rng:NextNumber(0, Art.SkyCloudDX))
	c.y = deckEst(anchor, z) + rng:NextNumber(Art.SkyCloudAltMin, Art.SkyCloudAltMax)
	local s = rng:NextNumber(0.7, 1.6)
	c.offs[1] = Vector3.new(0, 0, 0)
	c.offs[2] = Vector3.new(9, -2, 3) * s
	c.offs[3] = Vector3.new(-8, -1, -4) * s
	c.offs[4] = Vector3.new(2, -5, 1) * s
	for i, p in ipairs(c.parts) do
		local d = CLOUD_SIZE[i] * s
		p.Size = Vector3.new(d, d * 0.72, d)
		p.Position = Vector3.new(c.x + c.offs[i].X, c.y + c.offs[i].Y, c.z + c.offs[i].Z)
	end
end

-- Re-lay an islet at z: a sand mass hangs in the blue, the grass dome
-- caps it, and the islet's own palm stands on top — the floating
-- islands the arcade course sails past. The palm is laid once here
-- (static at this distance — no breeze step).
local function laySkyIsland(isl: SkyIsland, anchor: Vector3, z: number)
	isl.z = z
	local seaY = deckEst(anchor, z) - Art.SkyIsleDrop
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local x = anchor.X + side * (Art.SkyIslandMinX + rng:NextNumber(0, Art.SkyIslandDX))
	local r = rng:NextNumber(Art.SkyIslandMinR, Art.SkyIslandMaxR)
	isl.base.Size = Vector3.new(r * 2.3, r * 0.8, r * 2.3)
	isl.base.Position = Vector3.new(x, seaY + r * 0.18, z)
	isl.dome.Size = Vector3.new(r * 2, r * 0.95, r * 2)
	isl.dome.Position = Vector3.new(x, seaY + r * 0.42, z)
	layPalm(
		isl.palm,
		x + rng:NextNumber(-r * 0.3, r * 0.3),
		seaY + r * 0.85,
		z + rng:NextNumber(-r * 0.2, r * 0.2),
		SKY_PALM
	)
end

-- Re-lay a goal arch at z: a full ring on the lane's cross axis,
-- center lifted SkyGateLift over the deck so the ball threads the
-- hole and the lower arc dips below the lane. Each segment is a
-- tangent box; alternating stripes read as the finish gate.
local function laySkyGate(g: SkyGate, anchor: Vector3, z: number)
	g.z = z
	local laneX = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
	local cy = deckEst(anchor, z) + Art.SkyGateLift
	local step = math.pi * 2 / Art.SkyGateSegs
	local arc = Art.SkyGateR * step + 0.4 -- slight overlap, no ring gaps
	for i, s in ipairs(g.segs) do
		local t = (i - 1) * step
		s.Size = Vector3.new(arc, Art.SkyGateThick, Art.SkyGateThick)
		s.CFrame = CFrame.new(laneX + math.cos(t) * Art.SkyGateR, cy + math.sin(t) * Art.SkyGateR, z)
			* CFrame.Angles(0, 0, t + math.pi / 2)
		s.Color = if i % 2 == 0 then Art.SkyGateA else Art.SkyGateB
	end
end

-- Park a single palm record (grove or islet) — the same three piece
-- sets parkPalms walks.
local function parkPalm(palm: Palm)
	parkPart(palm.trunk)
	for _, f in ipairs(palm.fronds) do
		parkPart(f.part)
	end
	for _, b in ipairs(palm.beads) do
		parkPart(b)
	end
end

-- Day-shift lighting (§18 "sky" only): the world slot is the one thing
-- allowed to re-time the sky. First activation snapshots the server's
-- night rig; swapping to any other world restores it verbatim.
local skyLightSaved: { [string]: any }? = nil
local function applyThemeLight(nt: Theme)
	local lighting = game:GetService("Lighting")
	local atmo = lighting:FindFirstChildOfClass("Atmosphere")
	if nt == "sky" then
		if not skyLightSaved then
			local saved: { [string]: any } = {
				ClockTime = lighting.ClockTime,
				Ambient = lighting.Ambient,
				OutdoorAmbient = lighting.OutdoorAmbient,
				ExposureCompensation = lighting.ExposureCompensation,
			}
			if atmo then
				saved.atmo = { Color = atmo.Color, Decay = atmo.Decay, Haze = atmo.Haze }
			end
			skyLightSaved = saved
		end
		lighting.ClockTime = Art.SkyClockTime
		lighting.Ambient = Art.SkyAmbient
		lighting.OutdoorAmbient = Art.SkyOutdoorAmbient
		if atmo then
			atmo.Color = Art.SkyAtmoColor
			atmo.Decay = Art.SkyAtmoDecay
			atmo.Haze = Art.SkyAtmoHaze
		end
	elseif skyLightSaved then
		local s = skyLightSaved
		skyLightSaved = nil
		lighting.ClockTime = s.ClockTime
		lighting.Ambient = s.Ambient
		lighting.OutdoorAmbient = s.OutdoorAmbient
		lighting.ExposureCompensation = s.ExposureCompensation
		if atmo and s.atmo then
			atmo.Color = s.atmo.Color
			atmo.Decay = s.atmo.Decay
			atmo.Haze = s.atmo.Haze
		end
	end
end

-- The synthwave sun is built as a stack of horizontal strips:
-- chord width follows the disk's circle, color slides style.top ->
-- style.bottom top to bottom (Config.Art.SunStyles — the §18 "sun" slot
-- picks the style). The top `solid` fraction of strips abut into a
-- solid dome; below that they taper to slivers so the disk dissolves
-- into the horizon (the classic striped-sunset read).
-- Sun strips keep their authored sizes so the analyzer pulse can breathe
-- the disk without drifting (AUDIO.md §8).
local sunParts: { { part: Part, base: Vector3 } } = {}
local sunPulse = 0
local sunPulseApplied = -1 -- write-gated scale cache (−1 forces first pass)

-- Mid-band punch: a client-local BloomEffect rides the same pulse —
-- kicks bloom a little harder (AUDIO.md §8). Local to us; Lighting never
-- replicates it. bloomBase preserves a place-authored intensity.
local bloom: BloomEffect? = nil
local bloomBase = 0
local bloomApplied = math.huge -- write-gated intensity cache (huge forces first write)

-- A sun style (Config.Art.SunStyles key — §18 "sun" slot) restyles the
-- stack: crown/base colors, the solid-dome fraction, the thinnest strip,
-- and a radius multiplier. `sunStyle` tracks the live key so setSun can
-- no-op on repeats.
type SunStyle = { top: Color3, bottom: Color3, solid: number, gap: number, scale: number? }
local SUN_STYLES: { [string]: SunStyle } = Art.SunStyles
local sunStyle = "classic"

local function makeSun(parent: Instance, st: SunStyle, collect: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Sun"
	local r = Art.SunRadius * (st.scale or 1)
	local n = math.max(Art.SunStrips, 2)
	local yTop, yBot = 0.92 * r, -0.92 * r
	local spacing = (yTop - yBot) / (n - 1)
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local y = yTop - (yTop - yBot) * t
		local halfChord = math.sqrt(math.max(r * r - y * y, 0))
		-- Solid crown: strips overlap their pitch so the dome has no gaps.
		-- Below the solid fraction, heights ease spacing -> st.gap.
		local h
		if t < st.solid then
			h = spacing * 1.04
		else
			local u = (t - st.solid) / math.max(1 - st.solid, 0.001)
			h = spacing + (st.gap - spacing) * u
		end
		local strip = Instance.new("Part")
		strip.Anchored = true
		strip.CanCollide = false
		strip.CastShadow = false
		strip.Material = Enum.Material.Neon
		strip.Color = st.top:Lerp(st.bottom, t)
		strip.Size = Vector3.new(halfChord * 2, h, Art.SunDepth)
		strip.Position = Vector3.new(0, y, 0)
		strip.Parent = model
		if collect then
			-- Only the LIVE sun registers for the audio pulse — diorama
			-- suns would dangle destroyed parts in the table.
			table.insert(sunParts, { part = strip, base = strip.Size })
		end
	end
	model.Parent = parent
	return model
end

function Backdrop.init()
	root = Instance.new("Folder")
	root.Name = "RoBallBackdrop"
	root.Parent = workspace
	sun = makeSun(root, SUN_STYLES[sunStyle], true)
	-- Mid-band bloom punch — bind the server's named WorldBloom first (a stale
	-- authored Bloom may sit earlier in child order with hot defaults), keeping
	-- its tuned intensity as the pulse baseline.
	local lighting = game:GetService("Lighting")
	bloom = lighting:WaitForChild("WorldBloom", 10) :: BloomEffect?
	if not bloom then
		bloom = lighting:FindFirstChildOfClass("BloomEffect")
	end
	if bloom then
		bloomBase = bloom.Intensity
	else
		local b = Instance.new("BloomEffect")
		b.Name = "AudioBloom"
		b.Intensity = Art.BloomBase
		b.Threshold = 0.85
		b.Size = 24
		b.Parent = game:GetService("Lighting")
		bloom = b
		bloomBase = Art.BloomBase
	end
	-- Towers are created parked and laid out on the first update, when the
	-- ball's lane X is known (lanes sit at laneIndex * RowSpacing).
	for side = -1, 1, 2 do
		for row = 1, Art.CityRows do
			for _ = 1, math.floor(Art.CitySpan / Art.CitySpacing) do
				table.insert(towers, makeTower(root, side, row))
			end
		end
	end

	-- World theme (§18): the world cosmetic slot picks the side scenery.
	-- The attribute lands async after join — the listener catches late
	-- arrivals, the initial read covers ones already set.
	local function themeFromAttr()
		local item = Cosmetics.item(player:GetAttribute("RoBallEq_world") :: string?)
		Backdrop.setTheme(if item and item.theme then item.theme else "city")
	end
	player:GetAttributeChangedSignal("RoBallEq_world"):Connect(themeFromAttr)
	themeFromAttr()

	-- Sun skin (§18 "sun" slot): same attribute-driven swap — the equipped
	-- SunStyles key restyles the strip stack in place.
	local function sunFromAttr()
		local item = Cosmetics.item(player:GetAttribute("RoBallEq_sun") :: string?)
		Backdrop.setSun(if item and item.sun then item.sun else "classic")
	end
	player:GetAttributeChangedSignal("RoBallEq_sun"):Connect(sunFromAttr)
	sunFromAttr()
end

-- Sun swap (§18 sun slot): rebuild the strip stack under the new style —
-- ~16 parts, so a destroy+rebuild beats restyling strips in place. The
-- update loop re-anchors it next frame; sunParts repopulates for the
-- audio pulse.
function Backdrop.setSun(name: string)
	local st = SUN_STYLES[name]
	if not st or name == sunStyle then
		return
	end
	sunStyle = name
	table.clear(sunParts)
	sunPulseApplied = -1 -- rebuilt strips need one write pass at any pulse
	if sun then
		sun:Destroy()
	end
	sun = makeSun(root, st, true)
end

local seeded = false

-- Audio-reactive drive (AUDIO.md §8): 0..1 energy from MusicController's
-- analyzer. Decorative only — the pulse never touches hue or hazards.
function Backdrop.setPulse(p: number)
	sunPulse = math.clamp(p, 0, 1)
	-- Lighting property writes cost more than a part field — quantize the
	-- bloom intensity to 0.01 steps; the pulse is a breathing tint, not a
	-- strobe, so the deadband is invisible.
	local b = bloomBase + sunPulse * Art.BloomPulseGain
	if bloom and math.abs(b - bloomApplied) > 0.01 then
		bloomApplied = b
		bloom.Intensity = b
	end
end

-- Theme swap (§18 world slot): the outgoing system's parts park below the
-- void (and past the recycle gate), the incoming one re-seeds so its whole
-- window re-lays on the next update. One park pass per system keeps the
-- branch honest when the catalog grows.
local function parkTowers()
	for _, tower in ipairs(towers) do
		for _, seg in ipairs(tower.segs) do
			parkPart(seg.part)
		end
	end
	seeded = false
	table.clear(towerFades)
end

local function parkPeaks()
	for _, tile in ipairs(peakTiles) do
		for _, p in ipairs(tile.lines) do
			parkPart(p)
		end
		for _, p in ipairs(tile.plates) do
			parkPart(p)
		end
		parkPart(tile.slab)
	end
	peaksSeeded = false
end

local function parkToxic()
	for _, b in ipairs(toxicBubbles) do
		parkPart(b.part)
	end
	toxicSeeded = false
end

local function parkVoid()
	for _, mote in ipairs(voidMotes) do
		parkPart(mote)
	end
	voidSeeded = false
end

local function parkGrid()
	for _, p in ipairs(gridWires) do
		parkPart(p)
	end
	for _, p in ipairs(gridRays) do
		parkPart(p)
	end
	gridSeeded = false
end

local function parkAurora()
	for _, f in ipairs(auroraFans) do
		f.emitter.Enabled = false -- parked emitters would still churn particles
		parkPart(f.part)
	end
end

local function parkReef()
	for _, s in ipairs(reefStrands) do
		parkPart(s.part)
	end
	reefSeeded = false
end

local function parkMeteors()
	for _, m in ipairs(meteors) do
		parkPart(m.part)
	end
	meteorSeeded = false
end

local function parkPalms()
	for _, palm in ipairs(palms) do
		parkPalm(palm)
	end
	palmSeeded = false
end

local function parkPolar()
	for _, f in ipairs(polarFans) do
		f.emitter.Enabled = false -- parked emitters would still churn particles
		parkPart(f.part)
	end
	for _, s in ipairs(polarStars) do
		parkPart(s)
	end
	polarSeeded = false
end

local function parkSky()
	for _, c in ipairs(skyClouds) do
		for _, p in ipairs(c.parts) do
			parkPart(p)
		end
	end
	for _, isl in ipairs(skyIslands) do
		parkPart(isl.dome)
		parkPart(isl.base)
		parkPalm(isl.palm)
	end
	for _, g in ipairs(skyGates) do
		for _, s in ipairs(g.segs) do
			parkPart(s)
		end
	end
	-- Sky shares the palm pool — park the grove too or the next theme
	-- inherits palms standing where SKY COURT left them.
	parkPalms()
	skySeeded = false
end

local parkers: { [Theme]: () -> () } = {
	city = parkTowers,
	peaks = parkPeaks,
	void = parkVoid,
	grid = parkGrid,
	aurora = parkAurora,
	reef = parkReef,
	meteor = parkMeteors,
	palms = parkPalms,
	polar = parkPolar,
	empty = function() end,
	toxic = parkToxic,
	sky = parkSky,
}

local THEMES: { [string]: Theme } = {
	peaks = "peaks",
	void = "void",
	grid = "grid",
	aurora = "aurora",
	reef = "reef",
	meteor = "meteor",
	palms = "palms",
	polar = "polar",
	empty = "empty",
	toxic = "toxic",
	sky = "sky",
}

function Backdrop.setTheme(t: string)
	local nt: Theme = THEMES[t] or "city"
	if nt == theme then
		return
	end
	-- Park whatever was showing — the incoming theme lazily builds.
	parkers[theme]()
	theme = nt
	applyThemeLight(nt)
end

-- Last anchor z: forward play only ever decreases z (speed is always
-- +TravelAxis and dashes are lateral), so a +z jump means the anchor
-- teleported — menu vista, run restart, death-to-menu. Every recycled
-- field is then stranded ahead of the ball with no part able to cross
-- the recycle gate, so the whole theme parks and re-seeds around the
-- new anchor in one pass.
local lastAnchorZ: number? = nil

function Backdrop.update(anchor: Vector3)
	if not root then
		return
	end
	if lastAnchorZ and anchor.Z - lastAnchorZ > BACK_MARGIN then
		parkers[theme]()
	end
	lastAnchorZ = anchor.Z
	local dist = math.max(0, -anchor.Z)

	-- The sun rides a fixed distance ahead and a fixed lift above the ball,
	-- so it always hangs in the upper frame like a sunset at the end of the
	-- slope — deck-relative heights would sink it below the horizon.
	if sun then
		sun:PivotTo(CFrame.new(anchor.X, anchor.Y + Art.SunLift, anchor.Z - Art.SunDist))
		-- Bass pulse: the disk breathes ±10% with the music's low end.
		-- Write-gated — 16 strips × .Size every frame mostly rewrote the
		-- same value (pulse jitter at rest); ±0.25% deadband keeps the
		-- breathing and skips ~80% of the writes.
		local s = 1 + sunPulse * 0.10
		if math.abs(s - sunPulseApplied) > 0.0025 then
			sunPulseApplied = s
			for _, sp in ipairs(sunParts) do
				sp.part.Size = Vector3.new(sp.base.X * s, sp.base.Y * s, sp.base.Z)
			end
		end
	end

	if theme == "peaks" then
		ensurePeaks()
		local tileLen = Art.PeaksRows * Art.PeaksCellZ
		local span = tileLen * Art.PeaksTiles
		if peaksSeeded then
			-- Anchor teleported behind the strip (run restart after a theme
			-- swap deep into a run): any tile wholly past the window's leading
			-- edge means the whole strip is stranded — re-seed below.
			for _, tile in ipairs(peakTiles) do
				if tile.z0 + tileLen < anchor.Z - span + BACK_MARGIN then
					peaksSeeded = false
					break
				end
			end
		end
		if not peaksSeeded then
			peaksSeeded = true
			-- First lattice row past the keep margin: the nearest tile's
			-- back edge lands just behind the ball, covering the window.
			local back = math.ceil((anchor.Z + BACK_MARGIN) / Art.PeaksCellZ) * Art.PeaksCellZ
			for _, tile in ipairs(peakTiles) do
				tile.z0 = back - tile.slot * tileLen
				layTile(tile, anchor)
			end
			return
		end
		for _, tile in ipairs(peakTiles) do
			if tile.z0 > anchor.Z + BACK_MARGIN then
				tile.z0 -= span
				layTile(tile, anchor)
			end
		end
		return
	end

	-- STAR WELL (§18 "void"): motes hold their azimuth/radius, only z
	-- recycles — the field streams past while the shell stays coherent.
	if theme == "void" then
		ensureVoid()
		for _, mote in ipairs(voidMotes) do
			if not voidSeeded or mote.Position.Z > anchor.Z + BACK_MARGIN then
				layVoidMote(mote, anchor)
			end
		end
		voidSeeded = true
		return
	end

	-- GRID PLANE (§18 "grid"): cross wires recycle on a frontier; the long
	-- rays stride by their own window length when their back edge passes.
	if theme == "grid" then
		ensureGrid()
		local laneX = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
		local len = Art.GridFloorRows * Art.GridFloorCellZ
		if not gridSeeded then
			gridSeeded = true
			gridFrontZ = math.ceil((anchor.Z + BACK_MARGIN) / Art.GridFloorCellZ) * Art.GridFloorCellZ
			for i, wire in ipairs(gridWires) do
				layGridWire(wire, anchor, gridFrontZ - i * Art.GridFloorCellZ, laneX)
			end
			local zMid = gridFrontZ - len / 2
			for i, ray in ipairs(gridRays) do
				local x = laneX - Art.GridFloorHalfX + (i - 0.5) * (2 * Art.GridFloorHalfX / Art.GridFloorCols)
				layGridRay(ray, anchor, zMid + len / 2, x)
			end
			return
		end
		for _, wire in ipairs(gridWires) do
			if wire.Position.Z > anchor.Z + BACK_MARGIN then
				gridFrontZ -= Art.GridFloorCellZ
				layGridWire(wire, anchor, gridFrontZ, laneX)
			end
		end
		for _, ray in ipairs(gridRays) do
			-- Trailing (+z) end: once it passes the keep margin the whole
			-- window slid behind — stride it forward by its own length.
			local back = ray.CFrame.Position - ray.CFrame.LookVector * (ray.Size.Z / 2)
			if back.Z > anchor.Z + BACK_MARGIN then
				layGridRay(ray, anchor, back.Z - len, ray.Position.X)
			end
		end
		return
	end

	-- BOREALIS SKY (§18 "aurora"): emitter fans re-anchor beside the ball
	-- every frame — no frontier.
	if theme == "aurora" then
		ensureAurora()
		stepAurora(anchor, os.clock())
		return
	end

	-- NEON REEF (§18 "reef"): static strands recycle on a frontier — same
	-- pattern as the tower rows, just denser and thinner.
	if theme == "reef" then
		ensureReef()
		if not reefSeeded then
			reefSeeded = true
			reefFrontZ[-1] = anchor.Z + BACK_MARGIN
			reefFrontZ[1] = anchor.Z + BACK_MARGIN
			for _, s in ipairs(reefStrands) do
				reefFrontZ[s.side] -= Art.ReefSpacing
				layStrand(s, anchor, reefFrontZ[s.side])
			end
			return
		end
		for _, s in ipairs(reefStrands) do
			if s.part.Position.Z > anchor.Z + BACK_MARGIN then
				reefFrontZ[s.side] -= Art.ReefSpacing
				layStrand(s, anchor, reefFrontZ[s.side])
			end
		end
		return
	end

	-- METEOR SHOWER (§18 "meteor"): real velocities — the streaks move
	-- every frame on wall-clock dt and respawn once spent.
	if theme == "meteor" then
		ensureMeteors()
		local now = os.clock()
		local dt = math.clamp(now - meteorClock, 0, 0.12)
		meteorClock = now
		stepMeteors(anchor, dt)
		return
	end

	-- MIAMI NIGHTS (§18 "palms"): the grove in neon.
	if theme == "palms" then
		stepPalms(anchor, MIAMI_PALM)
		return
	end

	-- NORTHERN LIGHTS (§18 "polar"): emitter fans re-anchor ahead of the
	-- ball every frame — no frontier; stars re-scatter as they pass.
	if theme == "polar" then
		ensurePolar()
		if not polarSeeded then
			polarSeeded = true
			for _, s in ipairs(polarStars) do
				layPolarStar(s, anchor)
			end
		end
		stepPolar(anchor, os.clock())
		return
	end

	-- SKY COURT (§18 "sky"): clouds re-enter ahead on a random span and
	-- bob lazily on wall-clock sine (Position rewrite only — offs fixed).
	-- The islets and goal arches recycle past in the open blue like the
	-- cloud field — gates re-enter straddling the lane itself.
	-- The day-palm grove runs the same step as MIAMI NIGHTS, day palette.
	if theme == "sky" then
		ensureSky()
		stepPalms(anchor, SKY_PALM)
		if not skySeeded then
			skySeeded = true
			for _, c in ipairs(skyClouds) do
				laySkyCloud(c, anchor, anchor.Z - rng:NextNumber(0, Art.SkyCloudSpan))
			end
			for _, isl in ipairs(skyIslands) do
				laySkyIsland(isl, anchor, anchor.Z - rng:NextNumber(60, Art.SkyIslandZMin + Art.SkyIslandZSpan))
			end
			for i, g in ipairs(skyGates) do
				laySkyGate(g, anchor, anchor.Z - rng:NextNumber(200 + i * 300, Art.SkyGateZMin + Art.SkyGateZSpan))
			end
			return
		end
		for _, isl in ipairs(skyIslands) do
			if isl.z > anchor.Z + Art.SkyIslandBack then
				laySkyIsland(
					isl,
					anchor,
					anchor.Z - rng:NextNumber(Art.SkyIslandZMin, Art.SkyIslandZMin + Art.SkyIslandZSpan)
				)
			end
		end
		for _, g in ipairs(skyGates) do
			if g.z > anchor.Z + Art.SkyGateBack then
				laySkyGate(g, anchor, anchor.Z - rng:NextNumber(Art.SkyGateZMin, Art.SkyGateZMin + Art.SkyGateZSpan))
			end
		end
		local bob = os.clock() * Art.SkyCloudBob
		for _, c in ipairs(skyClouds) do
			if c.z > anchor.Z + BACK_MARGIN then
				laySkyCloud(c, anchor, anchor.Z - rng:NextNumber(30, Art.SkyCloudSpan))
			end
			local cy = c.y + math.sin(bob + c.phase) * Art.SkyCloudBobAmp
			for i, p in ipairs(c.parts) do
				local off = c.offs[i]
				p.Position = Vector3.new(c.x + off.X, cy + off.Y, c.z + off.Z)
			end
		end
		return
	end

	-- VOIDSPACE (§18 "empty"): no scenery at all — just the lane, the sun
	-- on the horizon, and the skybox. The silence IS the product.
	if theme == "empty" then
		return
	end

	-- TOXIC WASTES (§18 "toxic"): bubbles climb on their own phases every
	-- frame — the boil needs a per-frame step like the meteors.
	if theme == "toxic" then
		ensureToxic()
		stepToxic(anchor)
		return
	end

	if not seeded then
		seeded = true
		-- Seed each row's frontier behind the anchor spread across the span,
		-- so the first frame fills the whole window at once. Each (side,row)
		-- chain takes its own lattice phase — otherwise all four chains cross
		-- the recycle gate on the same frame and the skyline regenerates in
		-- synchronized bursts on the horizon.
		for side = -1, 1, 2 do
			for row = 1, Art.CityRows do
				frontZ[side .. ":" .. row] = anchor.Z + Art.CitySpacing * (1 - rng:NextNumber(0, 0.5))
			end
		end
	end

	-- Towers: recycle any that fell behind the anchor to the front of their
	-- row, re-randomized. Static world-z between recycles = real parallax.
	-- Bases follow the deck's downhill grade so the canyon hugs the slope.
	for _, tower in ipairs(towers) do
		if tower.segs[1].part.Position.Z > anchor.Z + 60 then
			local key = tower.side .. ":" .. tower.row
			local z = frontZ[key] - Art.CitySpacing
			frontZ[key] = z
			local x = anchor.X + tower.side * (Art.CityMinX + (tower.row - 1) * Art.CityRowDX + rng:NextNumber(0, 40))
			local ahead = math.max(anchor.Z - z, 0)
			local baseY = anchor.Y - Config.Generation.Grade * ahead - rng:NextNumber(8, 30)
			-- Hue jitter per tower so the skyline mixes cyan/magenta/violet
			-- instead of marching in lockstep.
			local tint =
				Palette.dimAt(dist + ahead * 0.5 + rng:NextNumber(0, 300), Art.CityValue / (1 + (tower.row - 1) * 0.35))
			layTower(tower, x, baseY, z, tint)
			for _, seg in ipairs(tower.segs) do
				seg.outline.Transparency = 1
			end
			towerFades[tower] = os.clock()
		end
	end

	-- Advance outline fades: parked segs ride along harmlessly — they're
	-- invisible at PARK either way.
	for tower, t0 in pairs(towerFades) do
		local k = 1 - (os.clock() - t0) / Art.CityFadeIn
		for _, seg in ipairs(tower.segs) do
			seg.outline.Transparency = math.max(k, 0)
		end
		if k <= 0 then
			towerFades[tower] = nil
		end
	end
end

--=========================== DIORAMA (§18 preview) ===========================--
-- The garage preview window lays ONE static window of the real theme
-- geometry into a caller's container (the ViewportFrame's WorldModel):
-- the same ensure/lay/make functions and tunables as the live scenery,
-- frozen at a synthetic anchor instead of recycled behind the ball.
-- CosmeticFx scales the window down to frame size afterward.
--
-- SelectionBox adornments can't draw inside a ViewportFrame — the
-- diorama traces each laid tower segment with neon edge PARTS instead.
-- The layout is the real layTower math; only the stroke primitive swaps.
local function edgeCage(p: BasePart, color: Color3, parent: Instance)
	local s = p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local th = 1.2
	local function bar(size: Vector3, off: Vector3)
		local b = makePeakPart(parent, true)
		b.Size = size
		b.CFrame = p.CFrame * CFrame.new(off)
		b.Color = color
	end
	for sxn = -1, 1, 2 do
		for szn = -1, 1, 2 do
			bar(Vector3.new(th, s.Y + th, th), Vector3.new(sxn * hx, 0, szn * hz))
		end
		-- Top rim: one bar along X on each z edge + one along Z on each x
		-- edge — the SelectionBox cage's readable skeleton.
		bar(Vector3.new(s.X + th, th, th), Vector3.new(0, hy, sxn * hz))
		bar(Vector3.new(th, th, s.Z + th), Vector3.new(sxn * hx, hy, 0))
	end
end

function Backdrop.diorama(parent: Instance, themeKey: string, sunKey: string, anchor: Vector3)
	-- Sun: the real strip stack, parked at the real offset from the lane.
	local st = SUN_STYLES[sunKey] or SUN_STYLES.classic
	makeSun(parent, st, false):PivotTo(CFrame.new(anchor.X, anchor.Y + Art.SunLift, anchor.Z - Art.SunDist))

	local t: Theme = THEMES[themeKey] or "city"
	if t == "empty" then
		-- Nothing to lay — the sun above is the whole set dressing.
		return
	end
	if t == "toxic" then
		-- Static boil: one window of bubbles frozen mid-climb on random
		-- phases — same lay math as the live frontier.
		for _ = 1, Art.ToxicCount do
			local part = makePeakPart(parent, true)
			styleToxicBubble(part)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local z = anchor.Z + BACK_MARGIN - rng:NextNumber(0, Art.ToxicZSpan)
			local x = anchor.X + side * (Art.ToxicSideMin + rng:NextNumber(0, Art.ToxicSideJitter))
			local y = deckEst(anchor, z) - rng:NextNumber(Art.ToxicDepthMin, Art.ToxicDepthMax)
			part.Position = Vector3.new(x + rng:NextNumber(-1.6, 1.6), y + rng:NextNumber(0, Art.ToxicRiseSpan), z)
		end
		return
	end
	if t == "peaks" then
		-- Same first pass as update(): each side's tiles seeded back from
		-- the keep margin so the whole window fills in one lay.
		local nLines = (Art.PeaksCols + 1) * Art.PeaksRows + Art.PeaksCols * (Art.PeaksRows + 1)
		local tileLen = Art.PeaksRows * Art.PeaksCellZ
		local back = math.ceil((anchor.Z + BACK_MARGIN) / Art.PeaksCellZ) * Art.PeaksCellZ
		for side = -1, 1, 2 do
			for slot = 1, Art.PeaksTiles do
				local model = Instance.new("Model")
				model.Name = "Peaks"
				model.Parent = parent
				local lines: { Part } = {}
				local plates: { Part } = {}
				for _ = 1, nLines do
					table.insert(lines, makePeakPart(model, true))
				end
				for _ = 1, Art.PeaksCols * Art.PeaksRows do
					table.insert(plates, makePeakPart(model, false))
				end
				layTile({
					slot = slot,
					side = side,
					z0 = back - slot * tileLen,
					lines = lines,
					plates = plates,
					slab = makePeakPart(model, false),
				}, anchor)
			end
		end
		return
	end
	if t == "void" then
		for _ = 1, Art.VoidStars do
			local mote = Instance.new("Part")
			mote.Anchored = true
			mote.CanCollide = false
			mote.CanQuery = false
			mote.CastShadow = false
			mote.Material = Enum.Material.Neon
			mote.Shape = Enum.PartType.Ball
			mote.Size = Vector3.new(Art.VoidSize, Art.VoidSize, Art.VoidSize) * rng:NextNumber(0.5, 1.9)
			mote.Parent = parent
			layVoidMote(mote, anchor)
		end
		return
	end
	if t == "grid" then
		local laneX = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
		local front = math.ceil((anchor.Z + BACK_MARGIN) / Art.GridFloorCellZ) * Art.GridFloorCellZ
		for i = 1, Art.GridFloorRows do
			layGridWire(makePeakPart(parent, true), anchor, front - i * Art.GridFloorCellZ, laneX)
		end
		for i = 1, Art.GridFloorCols do
			local x = laneX - Art.GridFloorHalfX + (i - 0.5) * (2 * Art.GridFloorHalfX / Art.GridFloorCols)
			layGridRay(makePeakPart(parent, true), anchor, front, x)
		end
		return
	end
	if t == "aurora" then
		-- ParticleEmitters don't render inside a ViewportFrame — same
		-- stroke-swap as the tower outlines: the fan layout below uses the
		-- real AuroraFanX/Z/Y anchor math, drawn as seeded translucent
		-- curtains flanking the lane so the preview still sells the sky.
		local curtainColors = {
			Color3.fromRGB(120, 255, 170),
			Color3.fromRGB(160, 235, 255),
			Color3.fromRGB(170, 160, 255),
			Color3.fromRGB(255, 160, 230),
		}
		for side = -1, 1, 2 do
			for i = 1, 5 do
				local v = Instance.new("Part")
				v.Anchored = true
				v.CanCollide = false
				v.CanQuery = false
				v.CanTouch = false
				v.CastShadow = false
				v.Material = Enum.Material.Neon
				v.Transparency = 0.45 + rng:NextNumber(0, 0.25)
				v.Size = Vector3.new(1.4, 60 + rng:NextNumber(0, 70), 90 + rng:NextNumber(0, 90))
				local x = anchor.X + side * (Art.AuroraFanX + rng:NextNumber(0, Art.AuroraFanXJitter))
				local z = anchor.Z - Art.AuroraFanZ - (i - 1) * (Art.AuroraFanZGap / 4) + rng:NextNumber(-20, 20)
				local y = anchor.Y + Art.AuroraFanY + rng:NextNumber(-15, 30)
				v.CFrame = CFrame.new(x, y, z)
					* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.25, 0.25))
				v.Color = curtainColors[(i - 1) % #curtainColors + 1]
				v.Parent = parent
			end
		end
		return
	end
	if t == "reef" then
		for side = -1, 1, 2 do
			local z = anchor.Z + BACK_MARGIN
			for _ = 1, Art.ReefCount do
				z -= Art.ReefSpacing
				layStrand({ part = makePeakPart(parent, true), side = side }, anchor, z)
			end
		end
		return
	end
	if t == "meteor" then
		for _ = 1, Art.MeteorCount do
			layMeteor({ part = makePeakPart(parent, true), vel = Vector3.new(0, -1, 0), speed = 0 }, anchor)
		end
		return
	end
	if t == "palms" then
		for side = -1, 1, 2 do
			for row = 1, Art.PalmRows do
				local z = anchor.Z + Art.PalmSpacing
				for _ = 1, math.floor(Art.PalmSpan / Art.PalmSpacing) do
					z -= Art.PalmSpacing
					local x = anchor.X + side * (Art.PalmMinX + (row - 1) * Art.PalmRowDX + rng:NextNumber(0, 14))
					local baseY = anchor.Y - Gen.Grade * math.max(anchor.Z - z, 0) - rng:NextNumber(4, 10)
					layPalm(makePalm(parent, side, row), x, baseY, z, MIAMI_PALM)
				end
			end
		end
		return
	end
	if t == "polar" then
		-- ParticleEmitters don't render inside a ViewportFrame — same
		-- stroke-swap as the tower outlines: the canopy's fan-arc layout
		-- is approximated with seeded translucent veils overhead so the
		-- preview still sells the sky.
		local veilColors = {
			Color3.fromRGB(141, 255, 133),
			Color3.fromRGB(165, 243, 255),
			Color3.fromRGB(108, 255, 120),
			Color3.fromRGB(233, 255, 241),
			Color3.fromRGB(247, 255, 174),
		}
		-- The live canopy sweeps the whole sky; in the chase-cam window
		-- only the horizon band is on-frame, so the veils hang in an arc
		-- over the sun line — where the real fan sprites read.
		for i = 1, 12 do
			local v = Instance.new("Part")
			v.Anchored = true
			v.CanCollide = false
			v.CanQuery = false
			v.CanTouch = false
			v.CastShadow = false
			v.Material = Enum.Material.Neon
			v.Transparency = 0.45 + rng:NextNumber(0, 0.25)
			v.Size = Vector3.new(60 + rng:NextNumber(0, 80), 14 + rng:NextNumber(0, 30), 1.4)
			local arc = (i - 1) / 11 -- 0..1 across the sky band
			local x = anchor.X + (arc - 0.5) * 320 + rng:NextNumber(-15, 15)
			local z = anchor.Z - 150 - arc * 240 + rng:NextNumber(-30, 30)
			local y = anchor.Y + 18 + math.sin(arc * math.pi) * 50 + rng:NextNumber(-8, 8)
			v.CFrame = CFrame.new(x, y, z)
				* CFrame.Angles(
					rng:NextNumber(-0.15, 0.15),
					rng:NextNumber(-Art.PolarFanYaw, Art.PolarFanYaw),
					(arc - 0.5) * 0.6 + rng:NextNumber(-0.1, 0.1)
				)
			v.Color = veilColors[(i - 1) % #veilColors + 1]
			v.Parent = parent
		end
		for _ = 1, Art.PolarStars do
			local s = Instance.new("Part")
			s.Anchored = true
			s.CanCollide = false
			s.CanQuery = false
			s.CastShadow = false
			s.Material = Enum.Material.Neon
			s.Shape = Enum.PartType.Ball
			s.Size = Vector3.new(1, 1, 1) * rng:NextNumber(0.5, 1.6)
			s.Parent = parent
			layPolarStar(s, anchor)
		end
		return
	end
	if t == "sky" then
		-- Same lay math frozen: a few puffs adrift.
		local front = anchor.Z + BACK_MARGIN
		for _ = 1, 5 do
			local parts: { Part } = {}
			for _ = 1, 4 do
				local puff = makePeakPart(parent, false)
				puff.Shape = Enum.PartType.Ball
				puff.Color = Art.SkyCloudColor
				table.insert(parts, puff)
			end
			laySkyCloud(
				{ parts = parts, offs = {}, x = 0, y = 0, z = 0, phase = 0 },
				anchor,
				front - rng:NextNumber(30, Art.SkyCloudSpan * 0.7)
			)
		end
		-- Two islets adrift in the blue — a manual lay inside the frame
		-- (the live MinX band would park them out past the window).
		for side = -1, 1, 2 do
			local r = rng:NextNumber(Art.SkyIslandMinR, Art.SkyIslandMinR + 26)
			local x = anchor.X + side * rng:NextNumber(70, 150)
			local z = anchor.Z - rng:NextNumber(80, 240)
			local y = deckEst(anchor, z) - Art.SkyIsleDrop
			local base = makePeakPart(parent, false)
			base.Shape = Enum.PartType.Ball
			base.Color = Art.SkyIslandSide
			base.Size = Vector3.new(r * 2.3, r * 0.8, r * 2.3)
			base.Position = Vector3.new(x, y + r * 0.18, z)
			local dome = makePeakPart(parent, false)
			dome.Shape = Enum.PartType.Ball
			dome.Color = Art.SkyIslandTop
			dome.Size = Vector3.new(r * 2, r * 0.95, r * 2)
			dome.Position = Vector3.new(x, y + r * 0.42, z)
			layPalm(makePalm(parent, side, 1), x, y + r * 0.85, z, SKY_PALM)
		end
		-- One goal arch threading the lane — the finish-gate read frozen
		-- mid-frame so the preview ball rolls through it.
		local gsegs: { Part } = {}
		for _ = 1, Art.SkyGateSegs do
			table.insert(gsegs, makePeakPart(parent, false))
		end
		laySkyGate({ segs = gsegs, z = 0 }, anchor, anchor.Z - 95)
		-- A few day palms flanking the lane — same lay math as the live
		-- grove's first pass, dressed in the SKY_PALM palette.
		for side = -1, 1, 2 do
			local z = anchor.Z + Art.PalmSpacing
			for _ = 1, 4 do
				z -= Art.PalmSpacing
				local x = anchor.X + side * (Art.PalmMinX + rng:NextNumber(0, 14))
				local baseY = anchor.Y - Gen.Grade * math.max(anchor.Z - z, 0) - rng:NextNumber(4, 10)
				layPalm(makePalm(parent, side, 1), x, baseY, z, SKY_PALM)
			end
		end
		return
	end

	-- NEON CITY (default): lay each (side,row) frontier across the span —
	-- the same seeded-window math update() runs on its first frame.
	local dist = math.max(0, -anchor.Z)
	for side = -1, 1, 2 do
		for row = 1, Art.CityRows do
			local z = anchor.Z + Art.CitySpacing
			for _ = 1, math.floor(Art.CitySpan / Art.CitySpacing) do
				z -= Art.CitySpacing
				local tower = makeTower(parent, side, row)
				local x = anchor.X + side * (Art.CityMinX + (row - 1) * Art.CityRowDX + rng:NextNumber(0, 40))
				local ahead = math.max(anchor.Z - z, 0)
				local baseY = anchor.Y - Gen.Grade * ahead - rng:NextNumber(8, 30)
				local tint =
					Palette.dimAt(dist + ahead * 0.5 + rng:NextNumber(0, 300), Art.CityValue / (1 + (row - 1) * 0.35))
				layTower(tower, x, baseY, z, tint)
				for _, seg in ipairs(tower.segs) do
					if seg.part.CFrame ~= PARK then
						edgeCage(seg.part, seg.outline.Color3, parent)
					end
				end
			end
		end
	end
end

return Backdrop
