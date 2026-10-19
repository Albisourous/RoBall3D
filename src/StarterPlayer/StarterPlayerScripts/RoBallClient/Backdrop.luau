--!strict
-- Backdrop (DESIGN.md §12): wireframe city canyon — rows of dark towers
-- outlined in neon green flanking the track, recycled as the ball passes.
-- All parts are client-local: zero replication cost, and they read as
-- parallax scenery because they sit in world space while the ball flies past.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local Art = Config.Art
local rng = Random.new()

local Backdrop = {}

local root: Folder

type Seg = { part: Part, outline: SelectionBox }
type Tower = { segs: { Seg }, side: number, row: number }
local towers: { Tower } = {}
-- Per (side,row) frontier: the z where the next recycled tower goes.
local frontZ: { [string]: number } = {}

local FACE_COLOR = Color3.fromRGB(3, 5, 4)

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

function Backdrop.init()
	root = Instance.new("Folder")
	root.Name = "RoBallBackdrop"
	root.Parent = workspace
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
			local tint = Palette.dimAt(dist + ahead * 0.5, Art.CityValue / (1 + (tower.row - 1) * 0.35))
			layTower(tower, x, baseY, z, tint)
		end
	end
end

return Backdrop
