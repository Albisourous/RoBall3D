--!strict
-- Backdrop (DESIGN.md §12): vaporwave canyon — rows of dark towers
-- outlined in palette neon flanking the track, plus a giant striped
-- synthwave sun parked far down the slope. All parts are client-local:
-- zero replication cost, and they read as parallax scenery because they
-- sit in world space while the ball flies past.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local Art = Config.Art
local rng = Random.new()

local Backdrop = {}

local root: Folder
local sun: Model

type Seg = { part: Part, outline: SelectionBox }
type Tower = { segs: { Seg }, side: number, row: number }
local towers: { Tower } = {}
-- Per (side,row) frontier: the z where the next recycled tower goes.
local frontZ: { [string]: number } = {}

local FACE_COLOR = Color3.fromRGB(8, 4, 14)

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
			seg.part.CFrame = CFrame.new(0, -10000, 0)
		end
	end
end

-- The synthwave sun is built once as a stack of horizontal strips:
-- chord width follows the disk's circle, color slides orange -> magenta
-- top to bottom, and the gaps between strips widen downward (the classic
-- striped-sunset read).
-- Sun strips keep their authored sizes so the analyzer pulse can breathe
-- the disk without drifting (AUDIO.md §8).
local sunParts: { { part: Part, base: Vector3 } } = {}
local sunPulse = 0

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
	-- Towers are created parked and laid out on the first update, when the
	-- ball's lane X is known (lanes sit at laneIndex * RowSpacing).
	for side = -1, 1, 2 do
		for row = 1, Art.CityRows do
			for _ = 1, math.floor(Art.CitySpan / Art.CitySpacing) do
				table.insert(towers, makeTower(root, side, row))
			end
		end
	end
end

local seeded = false

-- Audio-reactive drive (AUDIO.md §8): 0..1 energy from MusicController's
-- analyzer. Decorative only — the pulse never touches hue or hazards.
function Backdrop.setPulse(p: number)
	sunPulse = math.clamp(p, 0, 1)
end

function Backdrop.update(anchor: Vector3)
	if not root then
		return
	end
	local dist = math.max(0, -anchor.Z)

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
