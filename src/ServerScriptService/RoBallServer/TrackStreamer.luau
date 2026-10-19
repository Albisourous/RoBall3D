--!strict
-- TrackStreamer: turns pure ChunkSpecs (GenCore) into Instanced geometry for
-- one player's lane, keeps AheadDistance of track generated in front of the
-- ball, destroys chunks BehindDistance behind it. Owns the deck-height lookup
-- used by the kill plane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local GenCore = require(ReplicatedStorage.RoBall.GenCore)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)

local SEG_LEN = 5 -- studs per slice; smaller = smoother curves, more parts
local DECK_COLOR = Color3.fromRGB(15, 15, 20)
local EDGE_COLOR = Color3.fromRGB(255, 45, 120) -- placeholder; P6 palette drive
local EDGE_W = 0.6
local EDGE_H = 0.25

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
	chunkType: string
)
	local e = Instance.new("Part")
	e.Name = "Edge"
	e.Anchored = true
	e.CanCollide = false
	e.Size = Vector3.new(EDGE_W, EDGE_H, SEG_LEN + 0.2)
	e.CFrame = CFrame.new(worldX, topY + EDGE_H / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	e.Color = EDGE_COLOR
	e.Material = Enum.Material.Neon
	e:SetAttribute("ChunkType", chunkType)
	e.Parent = parent
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

function TrackStreamer:buildChunk(spec: ChunkDefs.ChunkSpec): ChunkRecord
	local holder = Instance.new("Folder")
	holder.Name = spec.type .. "@" .. tostring(spec.startZ)
	holder.Parent = self.folder

	local len = spec.length
	for zTop = spec.startZ, spec.startZ - len + 0.001, -SEG_LEN do
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
				makeEdgeStrip(holder, leftC - rail / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
				makeEdgeStrip(holder, leftC + rail / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
				makeEdgeStrip(holder, rightC - rail / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
				makeEdgeStrip(holder, rightC + rail / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
			else
				makeSlicePart(holder, centerX, topY, zMid, width, pitch, roll, spec.type)
				makeEdgeStrip(holder, centerX - width / 2 + EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
				makeEdgeStrip(holder, centerX + width / 2 - EDGE_W / 2, topY, zMid, pitch, roll, spec.type)
			end

			if mid.wallH and mid.wallH > 0.1 then
				makeWall(holder, centerX - width / 2 + 0.5, topY, zMid, mid.wallH, pitch, roll, spec.type)
				makeWall(holder, centerX + width / 2 - 0.5, topY, zMid, mid.wallH, pitch, roll, spec.type)
			end
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
