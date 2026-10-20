--!strict
-- Backdrop (DESIGN.md §12): side-scenery + the striped synthwave sun parked
-- far down the slope. The WORLD cosmetic slot (§18) swaps the flanks:
--   "city"  — dark towers outlined in palette neon, recycled per row for
--             parallax (the default canyon).
--   "peaks" — NEON PEAKS: a seeded wireframe ridge field, neon edges over
--             near-black facets rising straight out of the void.
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
local theme: "city" | "peaks" = "city"

local FACE_COLOR = Color3.fromRGB(8, 4, 14)
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

-- The synthwave sun is built once as a stack of horizontal strips:
-- chord width follows the disk's circle, color slides orange -> magenta
-- top to bottom, and the gaps between strips widen downward (the classic
-- striped-sunset read).
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
	for i = 1, Art.SunStrips do
		-- Strip centers run from near the top (+0.9R) to below center
		-- (-0.55R); the lowest sliver area is left open so the disk reads
		-- as dissolving into the horizon.
		local t = (i - 1) / math.max(Art.SunStrips - 1, 1)
		local y = r * (0.9 - 1.45 * t)
		local halfChord = math.sqrt(math.max(r * r - y * y, 0))
		local h = Art.SunMaxStripH + (Art.SunMinStripH - Art.SunMaxStripH) * t
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
-- window re-lays on the next update.
function Backdrop.setTheme(t: string)
	local nt: "city" | "peaks" = if t == "peaks" then "peaks" else "city"
	if nt == theme then
		return
	end
	theme = nt
	if theme == "peaks" then
		for _, tower in ipairs(towers) do
			for _, seg in ipairs(tower.segs) do
				parkPart(seg.part)
			end
		end
		peaksSeeded = false
	else
		for _, tile in ipairs(peakTiles) do
			for _, p in ipairs(tile.lines) do
				parkPart(p)
			end
			for _, p in ipairs(tile.plates) do
				parkPart(p)
			end
			parkPart(tile.slab)
		end
		seeded = false
	end
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
		if not peaksSeeded then
			peaksSeeded = true
			-- First lattice row past the keep margin: the nearest tile's
			-- back edge lands just behind the ball, covering the window.
			local back = math.ceil((anchor.Z + BACK_MARGIN) / Art.PeaksCellZ) * Art.PeaksCellZ
			for _, tile in ipairs(peakTiles) do
				tile.z0 = back - tile.slot * tileLen
				layTile(tile, anchor)
			end
		end
		for _, tile in ipairs(peakTiles) do
			if tile.z0 > anchor.Z + BACK_MARGIN then
				tile.z0 -= span
				layTile(tile, anchor)
			end
		end
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
