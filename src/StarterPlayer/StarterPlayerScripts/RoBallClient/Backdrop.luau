--!strict
-- Backdrop (DESIGN.md §12): giant striped retro sun parked on the horizon
-- ahead + wireframe mountain silhouettes flanking the track. All parts are
-- client-local — zero replication cost, and they read as parallax scenery
-- because they sit in world space while the ball flies past.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local Art = Config.Art
local rng = Random.new()

local Backdrop = {}

local root: Folder
local sun: Model
local sunStripes: { BasePart }

type Peak = { barL: Part, barR: Part, side: number, row: number }
local peaks: { Peak } = {}
-- Per (side,row) frontier: the z where the next recycled peak goes.
local frontZ: { [string]: number } = {}

-- Sun stripe layout (top -> bottom): {centerY frac, thickness frac} of R.
-- Gaps widen toward the bottom — the classic synthwave sun silhouette.
local STRIPES = {
	{ 0.80, 0.20 },
	{ 0.56, 0.15 },
	{ 0.36, 0.12 },
	{ 0.19, 0.10 },
	{ 0.05, 0.08 },
	{ -0.07, 0.065 },
	{ -0.18, 0.05 },
	{ -0.27, 0.04 },
	{ -0.34, 0.03 },
}

local function bar(parent: Instance, cframe: CFrame, length: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = Vector3.new(Art.BarThickness, length, Art.BarThickness)
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Parent = parent
	return p
end

-- A peak is two slanted neon bars forming /\ . `lay` positions+shapes the
-- bars for a given location/footprint so peaks can be re-randomized on reuse.
local function layPeak(peak: Peak, x: number, baseY: number, z: number, w: number, h: number, color: Color3)
	local half = w / 2
	local slope = math.sqrt(half * half + h * h)
	local ang = math.atan2(h, half)
	local midY = baseY + h / 2
	-- barL: bottom-left -> apex. barR: apex -> bottom-right. Rotation about Z.
	-- barL leans "/" (bottom-left -> apex): +Y tilted toward +X.
	-- barR leans "\" (apex -> bottom-right): +Y tilted toward -X.
	peak.barL.CFrame = CFrame.new(x - half / 2, midY, z) * CFrame.Angles(0, 0, -ang)
	peak.barR.CFrame = CFrame.new(x + half / 2, midY, z) * CFrame.Angles(0, 0, ang)
	peak.barL.Size = Vector3.new(Art.BarThickness, slope, Art.BarThickness)
	peak.barR.Size = Vector3.new(Art.BarThickness, slope, Art.BarThickness)
	peak.barL.Color = color
	peak.barR.Color = color
end

local function makePeak(side: number, row: number, x: number, baseY: number, z: number): Peak
	local model = Instance.new("Model")
	model.Name = "Peak"
	model.Parent = root
	local dummy = CFrame.new(0, -10000, 0)
	local p: Peak = {
		barL = bar(model, dummy, 1, Color3.new()),
		barR = bar(model, dummy, 1, Color3.new()),
		side = side,
		row = row,
	}
	layPeak(p, x, baseY, z, 100, 80, Color3.new())
	return p
end

local function initSun()
	sun = Instance.new("Model")
	sun.Name = "RetroSun"
	sunStripes = {}
	local R = Art.SunRadius
	for i, band in ipairs(STRIPES) do
		local yc, th = band[1], band[2]
		local halfChord = math.sqrt(math.max(R * R - (yc * R) ^ 2, 0))
		local p = Instance.new("Part")
		p.Name = "Stripe" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Size = Vector3.new(halfChord * 2, th * R, Art.SunDepth)
		p.Position = Vector3.new(0, yc * R, 0) -- model-local; PivotTo moves all
		p.Material = Enum.Material.Neon
		p.Parent = sun
		sunStripes[i] = p
	end
	sun.PrimaryPart = sunStripes[5] -- yc≈0: pivot lands the disc center on target
	sun.Parent = root
end

-- Gold (top) -> magenta (bottom) gradient, tinted toward the live palette hue.
local function paintSun(anchorDist: number)
	local tint = Palette.neonAt(anchorDist)
	local n = #sunStripes
	for i, stripe in ipairs(sunStripes) do
		local t = (i - 1) / math.max(n - 1, 1)
		local base = Color3.fromRGB(255, 190, 70):Lerp(Color3.fromRGB(255, 45, 140), t)
		stripe.Color = base:Lerp(tint, 0.2)
	end
end

function Backdrop.init()
	root = Instance.new("Folder")
	root.Name = "RoBallBackdrop"
	root.Parent = workspace
	initSun()
	-- Peaks are created parked and laid out on the first update, when the
	-- ball's lane X is known (lanes sit at laneIndex * RowSpacing). Parked
	-- z is deep behind the anchor so every peak recycles on frame one.
	for side = -1, 1, 2 do
		for row = 1, Art.MountainRows do
			for _ = 1, math.floor(Art.MountainSpan / Art.MountainSpacing) do
				table.insert(peaks, makePeak(side, row, 0, -10000, 1e6))
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
			for row = 1, Art.MountainRows do
				frontZ[side .. ":" .. row] = anchor.Z + Art.MountainSpacing
			end
		end
	end

	-- Sun: locked ahead of the ball, sunk below the deck so it reads as a
	-- horizon. Slight x drift keeps it feeling placed, not glued.
	sun:PivotTo(CFrame.new(anchor.X * 0.25, anchor.Y - Art.SunDrop, anchor.Z - Art.SunDistance))
	paintSun(dist)

	-- Mountains: recycle any peak that fell behind the anchor to the front of
	-- its row, re-randomized. Static world-z between recycles = real parallax.
	local tint = Palette.dimAt(dist, Art.MountainValue)
	for _, peak in ipairs(peaks) do
		if peak.barL.Position.Z > anchor.Z + 80 then
			local key = peak.side .. ":" .. peak.row
			local z = frontZ[key] - Art.MountainSpacing
			frontZ[key] = z
			local x = anchor.X
				+ peak.side * (Art.MountainMinX + (peak.row - 1) * Art.MountainRowDX + rng:NextNumber(0, 70))
			local w = rng:NextNumber(Art.MountainMinW, Art.MountainMaxW)
			local h = rng:NextNumber(Art.MountainMinH, Art.MountainMaxH)
			layPeak(peak, x, anchor.Y - 70, z, w, h, tint)
		end
	end
end

return Backdrop
