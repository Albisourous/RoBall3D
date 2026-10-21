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
--   "aurora"— BOREALIS SKY: translucent light curtains hanging high beside
--             the lane, swaying + cycling green→violet.
--   "reef"  — NEON REEF: dense thin neon strands rising out of the void —
--             kelp on a wireframe reef.
--   "meteor"— METEOR SHOWER: thin neon streaks slanting through the sky
--             on real velocities, respawning ahead.
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
-- Per (side,row) frontier: the z where the next recycled tower goes.
local frontZ: { [string]: number } = {}

type PeakTile = { slot: number, side: number, z0: number, lines: { Part }, plates: { Part }, slab: Part }
local peakTiles: { PeakTile } = {}
local peaksSeeded = false
type Theme = "city" | "peaks" | "void" | "grid" | "aurora" | "reef" | "meteor"
local theme: Theme = "city"

-- Star-well pool (§18 "void") + grid-floor pool (§18 "grid") — both
-- lazily built on first activation, non-owners never pay for the parts.
local voidMotes: { Part } = {}
local voidSeeded = false
local gridWires: { Part } = {} -- cross wires (one per GridRows)
local gridRays: { Part } = {} -- longitudinal rays (one per GridCols)
local gridFrontZ = 0 -- nearest cross-wire z; recycles march it forward
local gridSeeded = false

-- Wave-2 world themes (§18) — same lazy-build / park-on-swap contract.
type Curtain = { part: Part, side: number, x: number, z: number, alt: number, phase: number, huePhase: number }
local auroraCurtains: { Curtain } = {}
local auroraFrontZ: { [number]: number } = {} -- per-side recycle frontier
local auroraSeeded = false
type Strand = { part: Part, side: number }
local reefStrands: { Strand } = {}
local reefFrontZ: { [number]: number } = {}
local reefSeeded = false
type Meteor = { part: Part, vel: Vector3, speed: number }
local meteors: { Meteor } = {}
local meteorSeeded = false
local meteorClock = os.clock() -- dt source for real streak motion

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
	local h = crest * 0.82 + (d + 0.5) * 0.18
	local ramp = ((c + 0.3) / Art.PeaksCols) ^ Art.PeaksRampPow
	local env = math.clamp(0.62 + math.noise(row * Art.PeaksEnvF, side * 9.13, Art.PeaksSeed + 57) * 1.5, 0.05, 1)
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

--=========================== BOREALIS SKY (aurora) ==========================--
-- Tall translucent light sheets hanging high beside the lane. Each curtain
-- keeps its z slot and sways in place (y bob + x drift + slow hue cycle
-- between AuroraHueA..B — the band never crosses the red seam); z recycles
-- on a per-side frontier like the towers so the field streams forever.

local function ensureAurora()
	if #auroraCurtains > 0 then
		return
	end
	for side = -1, 1, 2 do
		for _ = 1, Art.AuroraCount do
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Transparency = Art.AuroraFade
			p.CFrame = PARK
			p.Parent = root
			table.insert(auroraCurtains, {
				part = p,
				side = side,
				x = 0,
				z = 0,
				alt = Art.AuroraAlt,
				phase = 0,
				huePhase = 0,
			})
		end
	end
end

local function layCurtain(c: Curtain, anchor: Vector3, z: number)
	c.z = z
	c.x = math.round(anchor.X / Gen.RowSpacing) * Gen.RowSpacing
		+ c.side * rng:NextNumber(Art.AuroraMinX, Art.AuroraMaxX)
	c.alt = Art.AuroraAlt + rng:NextNumber(-Art.AuroraAltJitter, Art.AuroraAltJitter)
	c.phase = rng:NextNumber(0, math.pi * 2)
	c.huePhase = rng:NextNumber()
	local p = c.part
	p.Size = Vector3.new(
		rng:NextNumber(Art.AuroraMinW, Art.AuroraMaxW),
		rng:NextNumber(Art.AuroraMinH, Art.AuroraMaxH),
		Art.AuroraThick
	)
end

-- Per-frame sway + hue cycle: cheap, ~22 parts. The hue never leaves the
-- green→violet window — color law safe without a palette lookup.
local function stepAurora(anchor: Vector3, t: number)
	for _, c in ipairs(auroraCurtains) do
		if c.z > anchor.Z + BACK_MARGIN then
			local key = c.side
			auroraFrontZ[key] = (auroraFrontZ[key] or anchor.Z + Art.AuroraSpacing) - Art.AuroraSpacing
			layCurtain(c, anchor, auroraFrontZ[key])
		end
		local sway = math.sin(t * Art.AuroraWaveF + c.phase)
		local drift = math.sin(t * 0.31 + c.phase * 1.7)
		c.part.Position = Vector3.new(c.x + drift * 7, deckEst(anchor, c.z) + c.alt + sway * Art.AuroraWaveAmp, c.z)
		local h = Art.AuroraHueA
			+ (Art.AuroraHueB - Art.AuroraHueA) * (0.5 + 0.5 * math.sin(t * 0.23 + c.huePhase * 6.283))
		c.part.Color = Color3.fromHSV(h, 0.85, Art.AuroraValue)
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

-- The synthwave sun is built once as a stack of horizontal strips:
-- chord width follows the disk's circle, color slides orange -> magenta
-- top to bottom. The top SunSolidFrac of strips abut into a solid dome;
-- below that they taper to slivers so the disk dissolves into the
-- horizon (the classic striped-sunset read).
-- Sun strips keep their authored sizes so the analyzer pulse can breathe
-- the disk without drifting (AUDIO.md §8).
local sunParts: { { part: Part, base: Vector3 } } = {}
local sunPulse = 0

-- Mid-band punch: a client-local BloomEffect rides the same pulse —
-- kicks bloom a little harder (AUDIO.md §8). Local to us; Lighting never
-- replicates it. bloomBase preserves a place-authored intensity.
local bloom: BloomEffect? = nil
local bloomBase = 0

local function makeSun(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Sun"
	local r = Art.SunRadius
	local n = math.max(Art.SunStrips, 2)
	local yTop, yBot = 0.92 * r, -0.92 * r
	local spacing = (yTop - yBot) / (n - 1)
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local y = yTop - (yTop - yBot) * t
		local halfChord = math.sqrt(math.max(r * r - y * y, 0))
		-- Solid crown: strips overlap their pitch so the dome has no gaps.
		-- Below the solid fraction, heights ease spacing -> SunMinStripH.
		local h
		if t < Art.SunSolidFrac then
			h = spacing * 1.04
		else
			local u = (t - Art.SunSolidFrac) / math.max(1 - Art.SunSolidFrac, 0.001)
			h = spacing + (Art.SunMinStripH - spacing) * u
		end
		local strip = Instance.new("Part")
		strip.Anchored = true
		strip.CanCollide = false
		strip.CastShadow = false
		strip.Material = Enum.Material.Neon
		strip.Color = Art.SunTopColor:Lerp(Art.SunBottomColor, t)
		strip.Size = Vector3.new(halfChord * 2, h, Art.SunDepth)
		strip.Position = Vector3.new(0, y, 0)
		strip.Parent = model
		table.insert(sunParts, { part = strip, base = strip.Size })
	end
	model.Parent = parent
	return model
end

function Backdrop.init()
	root = Instance.new("Folder")
	root.Name = "RoBallBackdrop"
	root.Parent = workspace
	sun = makeSun(root)
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
end

local seeded = false

-- Audio-reactive drive (AUDIO.md §8): 0..1 energy from MusicController's
-- analyzer. Decorative only — the pulse never touches hue or hazards.
function Backdrop.setPulse(p: number)
	sunPulse = math.clamp(p, 0, 1)
	if bloom then
		bloom.Intensity = bloomBase + sunPulse * Art.BloomPulseGain
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
	for _, c in ipairs(auroraCurtains) do
		parkPart(c.part)
	end
	auroraSeeded = false
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

local parkers: { [Theme]: () -> () } = {
	city = parkTowers,
	peaks = parkPeaks,
	void = parkVoid,
	grid = parkGrid,
	aurora = parkAurora,
	reef = parkReef,
	meteor = parkMeteors,
}

local THEMES: { [string]: Theme } = {
	peaks = "peaks",
	void = "void",
	grid = "grid",
	aurora = "aurora",
	reef = "reef",
	meteor = "meteor",
}

function Backdrop.setTheme(t: string)
	local nt: Theme = THEMES[t] or "city"
	if nt == theme then
		return
	end
	-- Park whatever was showing — the incoming theme lazily builds.
	parkers[theme]()
	theme = nt
end

function Backdrop.update(anchor: Vector3)
	if not root then
		return
	end
	local dist = math.max(0, -anchor.Z)

	-- The sun rides a fixed distance ahead and a fixed lift above the ball,
	-- so it always hangs in the upper frame like a sunset at the end of the
	-- slope — deck-relative heights would sink it below the horizon.
	if sun then
		sun:PivotTo(CFrame.new(anchor.X, anchor.Y + Art.SunLift, anchor.Z - Art.SunDist))
		-- Bass pulse: the disk breathes ±10% with the music's low end.
		local s = 1 + sunPulse * 0.10
		for _, sp in ipairs(sunParts) do
			sp.part.Size = Vector3.new(sp.base.X * s, sp.base.Y * s, sp.base.Z)
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

	-- BOREALIS SKY (§18 "aurora"): curtains recycle on a per-side frontier,
	-- then every frame sways + hue-cycles in place.
	if theme == "aurora" then
		ensureAurora()
		if not auroraSeeded then
			auroraSeeded = true
			-- Seed the frontier behind the ball: the first pass fills the
			-- whole window with spaced curtains at once.
			auroraFrontZ[-1] = anchor.Z + BACK_MARGIN
			auroraFrontZ[1] = anchor.Z + BACK_MARGIN
			for _, c in ipairs(auroraCurtains) do
				auroraFrontZ[c.side] -= Art.AuroraSpacing
				layCurtain(c, anchor, auroraFrontZ[c.side])
			end
		end
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

	if not seeded then
		seeded = true
		-- Seed each row's frontier behind the anchor spread across the span,
		-- so the first frame fills the whole window at once.
		for side = -1, 1, 2 do
			for row = 1, Art.CityRows do
				frontZ[side .. ":" .. row] = anchor.Z + Art.CitySpacing
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
		end
	end
end

return Backdrop
