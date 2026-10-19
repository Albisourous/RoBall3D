--!strict
-- TrackStreamer: turns pure ChunkSpecs (GenCore) into Instanced geometry for
-- one player's lane, keeps AheadDistance of track generated in front of the
-- ball, destroys chunks BehindDistance behind it. Owns the deck-height lookup
-- used by the kill plane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local GenCore = require(ReplicatedStorage.RoBall.GenCore)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local SEG_LEN = 5 -- studs per slice; smaller = smoother curves, more parts
local DECK_COLOR = Color3.fromRGB(28, 23, 46) -- readable dark violet, not pitch black
local EDGE_W = 0.6
local EDGE_H = 0.25
local GRID_H = 0.08

local TrackStreamer = {}
TrackStreamer.__index = TrackStreamer

export type ChunkRecord = {
	spec: ChunkDefs.ChunkSpec,
	holder: Folder,
	startZ: number,
	endZ: number,
}

export type Streamer = typeof(setmetatable({} :: any, TrackStreamer))

local lanesRoot = workspace:FindFirstChild("RoBallLanes") or Instance.new("Folder")
lanesRoot.Name = "RoBallLanes"
lanesRoot.Parent = workspace

function TrackStreamer.new(laneIndex: number, seed: number): Streamer
	local self = setmetatable({}, TrackStreamer)
	self.laneIndex = laneIndex
	self.laneX = laneIndex * Config.Generation.RowSpacing
	self.gen = GenCore.new(seed)
	self.seed = seed
	self.chunks = {} :: { ChunkRecord }
	self.folder = Instance.new("Folder")
	self.folder.Name = "Lane" .. laneIndex
	self.folder.Parent = lanesRoot
	-- Optional: set by Main. Fired when something touches lethal geometry.
	self.onFatalTouch = nil :: ((hit: BasePart) -> ())?
	-- Optional: set by Main. Fired when the ball touches a gem: (hit, value).
	self.onGem = nil :: ((hit: BasePart, value: number) -> ())?
	return self
end

local function makeSlicePart(
	parent: Instance,
	worldX: number,
	topY: number,
	zMid: number,
	width: number,
	pitch: number,
	roll: number,
	chunkType: string
): Part
	local p = Instance.new("Part")
	p.Name = "Deck"
	p.Anchored = true
	p.Size = Vector3.new(width, Config.Generation.TrackThickness, SEG_LEN + 0.2) -- slight overlap hides seams
	p.CFrame = CFrame.new(worldX, topY - Config.Generation.TrackThickness / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	p.Color = DECK_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p:SetAttribute("ChunkType", chunkType)
	p.Parent = parent
	return p
end

local function makeEdgeStrip(
	parent: Instance,
	worldX: number,
	topY: number,
	zMid: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
)
	local e = Instance.new("Part")
	e.Name = "Edge"
	e.Anchored = true
	e.CanCollide = false
	e.Size = Vector3.new(EDGE_W, EDGE_H, SEG_LEN + 0.2)
	e.CFrame = CFrame.new(worldX, topY + EDGE_H / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	e.Color = color
	e.Material = Enum.Material.Neon
	e:SetAttribute("ChunkType", chunkType)
	e.Parent = parent
end

-- Transverse neon grid strip across the deck top — floor readability + the
-- vaporwave grid signature (DESIGN.md §12).
local function makeGridStrip(
	parent: Instance,
	worldX: number,
	topY: number,
	zMid: number,
	width: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
)
	local g = Instance.new("Part")
	g.Name = "Grid"
	g.Anchored = true
	g.CanCollide = false
	g.CastShadow = false
	g.Size = Vector3.new(math.max(width - 1, 0.5), GRID_H, 0.5)
	g.CFrame = CFrame.new(worldX, topY + GRID_H / 2 + 0.02, zMid) * CFrame.Angles(pitch, 0, roll)
	g.Color = color
	g.Material = Enum.Material.Neon
	g:SetAttribute("ChunkType", chunkType)
	g.Parent = parent
end

local function makeWall(
	parent: Instance,
	worldX: number,
	topY: number,
	zMid: number,
	height: number,
	pitch: number,
	roll: number,
	chunkType: string
)
	local w = Instance.new("Part")
	w.Name = "Wall"
	w.Anchored = true
	w.Size = Vector3.new(1, height, SEG_LEN + 0.2)
	w.CFrame = CFrame.new(worldX, topY + height / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	w.Color = DECK_COLOR
	w.Material = Enum.Material.SmoothPlastic
	w:SetAttribute("ChunkType", chunkType)
	w.Parent = parent
end

-- Lethal blocks ride the deck: position/orient from section(t) so graded,
-- rolled and curved chunks all carry their hazards correctly.
local function makeBlock(parent: Instance, laneX: number, spec: ChunkDefs.ChunkSpec, ob: ChunkDefs.Obstacle)
	local mid = spec.section(ob.t)
	local dt = 0.02
	local tA = math.max(ob.t - dt, 0)
	local tB = math.min(ob.t + dt, 1)
	local sA = spec.section(tA)
	local sB = spec.section(tB)
	local pitch = math.atan((sB.y - sA.y) / math.max((tB - tA) * spec.length, 0.001))
	local roll = math.rad(mid.rollDeg)
	local b = Instance.new("Part")
	b.Name = "LethalBlock"
	b.Anchored = true
	b.Size = Vector3.new(ob.w, ob.h, ob.d)
	b.CFrame = CFrame.new(laneX + mid.centerX + ob.xOff, mid.y + ob.h / 2, spec.startZ - ob.t * spec.length)
		* CFrame.Angles(pitch, 0, roll)
	b.Color = Config.LethalColor
	b.Material = Enum.Material.Neon
	b:SetAttribute("ChunkType", spec.type)
	b.Parent = parent
	return b
end

-- Gems hover above the deck (or along the ramp arc). CanCollide stays off —
-- contact means collected, never an obstruction.
local function makeGem(parent: Instance, laneX: number, spec: ChunkDefs.ChunkSpec, g: ChunkDefs.GemSpot)
	local s = spec.section(g.t)
	local p = Instance.new("Part")
	p.Name = "Gem"
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.Size = Vector3.new(Config.Gems.Size, Config.Gems.Size, Config.Gems.Size)
	p.Position =
		Vector3.new(laneX + s.centerX + g.xOff, s.y + (g.yOff or Config.Gems.FloatY), spec.startZ - g.t * spec.length)
	p.Color = Config.Gems.Color
	p.Material = Enum.Material.Neon
	p:SetAttribute("GemValue", g.value)
	p:SetAttribute("ChunkType", spec.type)
	p.Parent = parent
	return p
end

function TrackStreamer:buildChunk(spec: ChunkDefs.ChunkSpec): ChunkRecord
	local holder = Instance.new("Folder")
	holder.Name = spec.type .. "@" .. tostring(spec.startZ)
	holder.Parent = self.folder

	-- Edges sample the distance-cycled palette: the world laps the vaporwave
	-- hue wheel as you roll deeper (DESIGN.md §8.5).
	local edgeColor = Palette.neonAt(-spec.startZ)
	local gridColor = Palette.dimAt(-spec.startZ, Config.Art.GridValue)

	local len = spec.length
	for zTop = spec.startZ, spec.startZ - len + 0.001, -SEG_LEN do
		local gridline = (spec.startZ - zTop) % Config.Art.GridEvery < SEG_LEN
		local t0 = (spec.startZ - zTop) / len
		local t1 = math.min(t0 + SEG_LEN / len, 1)
		local tMid = (t0 + t1) / 2
		local s0 = spec.section(t0)
		local s1 = spec.section(t1)
		local mid = spec.section(tMid)
		if mid.width > 0.5 then
			local zMid = zTop - (tMid - t0) * len
			local topY = (s0.y + s1.y) / 2
			local pitch = math.atan((s1.y - s0.y) / math.max((t1 - t0) * len, 0.001))
			local roll = math.rad(mid.rollDeg)
			local centerX = self.laneX + mid.centerX
			local width = mid.width

			if mid.cutout and mid.cutout > 1 then
				local rail = (width - mid.cutout) / 2
				local leftC = centerX - mid.cutout / 2 - rail / 2
				local rightC = centerX + mid.cutout / 2 + rail / 2
				makeSlicePart(holder, leftC, topY, zMid, rail, pitch, roll, spec.type)
				makeSlicePart(holder, rightC, topY, zMid, rail, pitch, roll, spec.type)
				makeEdgeStrip(holder, leftC - rail / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				makeEdgeStrip(holder, leftC + rail / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				makeEdgeStrip(holder, rightC - rail / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				makeEdgeStrip(holder, rightC + rail / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				if gridline then
					makeGridStrip(holder, leftC, topY, zMid, rail, pitch, roll, spec.type, gridColor)
					makeGridStrip(holder, rightC, topY, zMid, rail, pitch, roll, spec.type, gridColor)
				end
			else
				makeSlicePart(holder, centerX, topY, zMid, width, pitch, roll, spec.type)
				makeEdgeStrip(holder, centerX - width / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				makeEdgeStrip(holder, centerX + width / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type, edgeColor)
				if gridline then
					makeGridStrip(holder, centerX, topY, zMid, width, pitch, roll, spec.type, gridColor)
				end
			end

			if mid.wallH and mid.wallH > 0.1 then
				makeWall(holder, centerX - width / 2 + 0.5, topY, zMid, mid.wallH, pitch, roll, spec.type)
				makeWall(holder, centerX + width / 2 - 0.5, topY, zMid, mid.wallH, pitch, roll, spec.type)
			end
		end
	end

	if spec.obstacles then
		for _, ob in ipairs(spec.obstacles) do
			local block = makeBlock(holder, self.laneX, spec, ob)
			block.Touched:Connect(function(hit)
				if self.onFatalTouch then
					self.onFatalTouch(hit)
				end
			end)
		end
	end

	if spec.gems then
		for _, g in ipairs(spec.gems) do
			local gem = makeGem(holder, self.laneX, spec, g)
			local taken = false
			gem.Touched:Connect(function(hit)
				if taken then
					return
				end
				if self.onGem and self.onGem(hit, g.value) then
					taken = true
					gem:Destroy()
				end
			end)
		end
	end

	local record: ChunkRecord = {
		spec = spec,
		holder = holder,
		startZ = spec.startZ,
		endZ = spec.startZ - spec.length,
	}
	table.insert(self.chunks, record)
	return record
end

-- Keep generated track AheadDistance studs in front of the ball.
function TrackStreamer:ensureAhead(ballZ: number)
	local target = ballZ - Config.Generation.AheadDistance
	while self.gen.state.zEnd > target do
		self:buildChunk(self.gen:nextChunk())
	end
end

-- Destroy chunks fully behind the ball.
function TrackStreamer:cleanup(ballZ: number)
	local cutoff = ballZ + Config.Generation.BehindDistance
	local i = 1
	while i <= #self.chunks do
		local c = self.chunks[i]
		if c.endZ > cutoff then
			c.holder:Destroy()
			table.remove(self.chunks, i)
		else
			i += 1
		end
	end
end

-- Deck-top height at world z (for the kill plane). Exact via section fns.
function TrackStreamer:yAt(z: number): number
	for _, c in ipairs(self.chunks) do
		if z <= c.startZ and z > c.endZ then
			local t = (c.startZ - z) / c.spec.length
			return c.spec.section(t).y
		end
	end
	local last = self.chunks[#self.chunks]
	if last then
		return last.spec.section(1).y
	end
	return self.gen.state.y
end

function TrackStreamer:destroy()
	self.folder:Destroy()
end

return TrackStreamer
