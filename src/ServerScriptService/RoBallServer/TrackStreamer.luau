--!strict
-- TrackStreamer: turns pure ChunkSpecs (GenCore) into Instanced geometry for
-- one player's lane, keeps AheadDistance of track generated in front of the
-- ball, destroys chunks BehindDistance behind it. Owns the deck-height lookup
-- used by the kill plane.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local GenCore = require(ReplicatedStorage.RoBall.GenCore)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local SEG_LEN = 5 -- studs per slice; smaller = smoother curves, more parts
local DECK_COLOR = Color3.fromRGB(10, 6, 16) -- purple-black deck; the neon grid carries the read
local EDGE_W = 0.6
local EDGE_H = 0.25
local GRID_H = 0.08
local CENTER_W = 0.35 -- longitudinal grid line down the deck middle

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
	span: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
): Part
	local p = Instance.new("Part")
	p.Name = "Deck"
	p.Anchored = true
	p.Size = Vector3.new(width, Config.Generation.TrackThickness, span + 0.2) -- slight overlap hides seams
	p.CFrame = CFrame.new(worldX, topY - Config.Generation.TrackThickness / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	p.Color = color
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
	span: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
)
	local e = Instance.new("Part")
	e.Name = "Edge"
	e.Anchored = true
	e.CanCollide = false
	e.Size = Vector3.new(EDGE_W, EDGE_H, span + 0.2)
	e.CFrame = CFrame.new(worldX, topY + EDGE_H / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	e.Color = color
	e.Material = Enum.Material.Neon
	e:SetAttribute("ChunkType", chunkType)
	e.Parent = parent
end

-- Longitudinal neon line down the deck center — pairs with the transverse
-- grid strips to sell the full wireframe floor (DESIGN.md §12).
local function makeCenterStrip(
	parent: Instance,
	worldX: number,
	topY: number,
	zMid: number,
	segLen: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
)
	local c = Instance.new("Part")
	c.Name = "GridC"
	c.Anchored = true
	c.CanCollide = false
	c.CastShadow = false
	c.Size = Vector3.new(CENTER_W, GRID_H, segLen + 0.15)
	c.CFrame = CFrame.new(worldX, topY + GRID_H / 2 + 0.02, zMid) * CFrame.Angles(pitch, 0, roll)
	c.Color = color
	c.Material = Enum.Material.Neon
	c:SetAttribute("ChunkType", chunkType)
	c.Parent = parent
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
	span: number,
	pitch: number,
	roll: number,
	chunkType: string,
	color: Color3
)
	local w = Instance.new("Part")
	w.Name = "Wall"
	w.Anchored = true
	w.Size = Vector3.new(1, height, span + 0.2)
	w.CFrame = CFrame.new(worldX, topY + height / 2, zMid) * CFrame.Angles(pitch, 0, roll)
	w.Color = color
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
	-- Slope look: black body, red edge outline — the same one-color lethal
	-- language, but wireframe instead of solid fill.
	b.Color = Config.Obstacles.FaceColor
	b.Material = Enum.Material.SmoothPlastic
	b:SetAttribute("ChunkType", spec.type)
	local outline = Instance.new("SelectionBox")
	outline.Adornee = b
	outline.Color3 = Config.LethalColor
	outline.LineThickness = Config.Obstacles.OutlineThickness
	outline.SurfaceTransparency = 1
	outline.Parent = b
	b.Parent = parent
	return b
end

-- Gems hover above the deck (or along the ramp arc). Shape: a cube balanced
-- on a corner — 35.26° pitch + 45° yaw puts a vertex straight up, giving a
-- hexagonal diamond silhouette that reads as a gem at speed. (A two-pyramid
-- octahedron via SpecialMesh was tried: MeshType.Pyramid renders nothing in
-- the current engine.) CanCollide stays off — contact means collected,
-- never an obstruction.
local function makeGem(parent: Instance, laneX: number, spec: ChunkDefs.ChunkSpec, g: ChunkDefs.GemSpot): Part
	local s = spec.section(g.t)
	local p = Instance.new("Part")
	p.Name = "Gem"
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = Vector3.new(Config.Gems.Size, Config.Gems.Size, Config.Gems.Size)
	p.CFrame = CFrame.new(
		laneX + s.centerX + g.xOff,
		s.y + (g.yOff or Config.Gems.FloatY),
		spec.startZ - g.t * spec.length
	) * CFrame.Angles(math.rad(35.264), math.rad(45), 0)
	p.Color = Config.Gems.Color
	p.Material = Enum.Material.Neon
	p:SetAttribute("GemValue", g.value)
	p:SetAttribute("ChunkType", spec.type)
	CollectionService:AddTag(p, "RoBallGem") -- client BeatPulse subscribes
	p.Parent = parent
	return p
end

function TrackStreamer:buildChunk(spec: ChunkDefs.ChunkSpec): ChunkRecord
	local holder = Instance.new("Folder")
	holder.Name = spec.type .. "@" .. tostring(spec.startZ)
	holder.Parent = self.folder

	-- Neon accents sample the distance-cycled palette PER SEGMENT, not once
	-- per chunk: edge rails and the center line are split into <=GridEvery
	-- pieces and grid strips sample at their own z, so color flows
	-- continuously down the course like a real vaporwave gradient instead
	-- of banding per chunk (DESIGN.md §8.5). The deck gets a subtle palette
	-- tint so the floor itself drifts with the gradient.
	local len = spec.length
	local n = math.max(1, math.round(len / SEG_LEN))

	-- One deck box can't gradient, but tinting it toward the palette (dark,
	-- DeckTint-weighted) lets the floor drift with the flow.
	local function deckColorAt(zMid: number): Color3
		return DECK_COLOR:Lerp(Palette.neonAt(-zMid), Config.Art.DeckTint)
	end

	-- Runs a longitudinal strip (edge rail / center line) in <=GridEvery
	-- pieces along a run; each piece samples the palette at its own z.
	-- topY(z) follows the deck box's pitch so pieces sit flush.
	local function eachStripSeg(
		span: number,
		zMid: number,
		topY: number,
		pitch: number,
		fn: (number, number, number) -> ()
	)
		local nSeg = math.max(1, math.ceil(span / Config.Art.GridEvery))
		local sub = span / nSeg
		for i = 0, nSeg - 1 do
			local z0 = zMid + span / 2 - (i + 0.5) * sub
			local y0 = topY - math.tan(pitch) * (z0 - zMid)
			fn(z0, y0, sub)
		end
	end

	-- Sample the section once, then emit the fewest boxes that describe it:
	-- consecutive intervals whose profile (width/centerX/roll/cutout/wallH)
	-- and deck slope stay constant merge into a single long part. Straight
	-- chunks (Flat, intro, obstacle rows) collapse to ~4 parts; curved ones
	-- (Slalom, Tilt, Pinch) keep fine SEG_LEN slices.
	local samples = table.create(n + 1)
	for i = 0, n do
		samples[i + 1] = spec.section(i / n)
	end

	local function sameShape(a: ChunkDefs.Section, b: ChunkDefs.Section): boolean
		return math.abs(a.width - b.width) <= 0.06
			and math.abs(a.centerX - b.centerX) <= 0.06
			and math.abs(a.rollDeg - b.rollDeg) <= 0.06
			and math.abs((a.cutout or 0) - (b.cutout or 0)) <= 0.06
			and math.abs((a.wallH or 0) - (b.wallH or 0)) <= 0.06
	end

	-- One straight deck box (or twin rails for a cutout) spanning tA..tB.
	local function emitDeck(tA: number, tB: number)
		local tM = (tA + tB) / 2
		local sA = spec.section(tA)
		local sB = spec.section(tB)
		local mid = spec.section(tM)
		if mid.width <= 0.5 then
			return
		end
		local span = (tB - tA) * len
		local zMid = spec.startZ - tM * len
		local topY = (sA.y + sB.y) / 2
		local pitch = math.atan((sB.y - sA.y) / span)
		local roll = math.rad(mid.rollDeg)
		local centerX = self.laneX + mid.centerX
		local width = mid.width
		local deckColor = deckColorAt(zMid)

		if mid.cutout and mid.cutout > 1 then
			local rail = (width - mid.cutout) / 2
			local leftC = centerX - mid.cutout / 2 - rail / 2
			local rightC = centerX + mid.cutout / 2 + rail / 2
			makeSlicePart(holder, leftC, topY, zMid, rail, span, pitch, roll, spec.type, deckColor)
			makeSlicePart(holder, rightC, topY, zMid, rail, span, pitch, roll, spec.type, deckColor)
			eachStripSeg(span, zMid, topY, pitch, function(z0, y0, sub)
				local c = Palette.neonAt(-z0)
				makeEdgeStrip(holder, leftC - rail / 2 + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				makeEdgeStrip(holder, leftC + rail / 2 - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				makeEdgeStrip(holder, rightC - rail / 2 + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				makeEdgeStrip(holder, rightC + rail / 2 - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
			end)
		else
			makeSlicePart(holder, centerX, topY, zMid, width, span, pitch, roll, spec.type, deckColor)
			eachStripSeg(span, zMid, topY, pitch, function(z0, y0, sub)
				local c = Palette.neonAt(-z0)
				makeEdgeStrip(holder, centerX - width / 2 + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				makeEdgeStrip(holder, centerX + width / 2 - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				makeCenterStrip(
					holder,
					centerX,
					y0,
					z0,
					sub,
					pitch,
					roll,
					spec.type,
					Palette.dimAt(-z0, Config.Art.GridValue)
				)
			end)
		end

		if mid.wallH and mid.wallH > 0.1 then
			makeWall(holder, centerX - width / 2 + 0.5, topY, zMid, mid.wallH, span, pitch, roll, spec.type, deckColor)
			makeWall(holder, centerX + width / 2 - 0.5, topY, zMid, mid.wallH, span, pitch, roll, spec.type, deckColor)
		end
	end

	local k = 1
	while k <= n do
		local s0 = samples[k]
		local yStep = samples[k + 1].y - s0.y -- deck drop across this interval
		local runEnd = k
		while
			runEnd < n
			and sameShape(samples[runEnd + 1], s0)
			and math.abs(samples[runEnd + 2].y - samples[runEnd + 1].y - yStep) <= 0.1
		do
			runEnd += 1
		end
		emitDeck((k - 1) / n, runEnd / n)
		k = runEnd + 1
	end

	-- Transverse grid strips on a fixed GridEvery cadence, independent of how
	-- the deck was sliced above.
	for off = Config.Art.GridEvery, len - 0.01, Config.Art.GridEvery do
		local t = off / len
		local mid = spec.section(t)
		if mid.width > 0.5 then
			local tA = math.max(t - 0.02, 0)
			local tB = math.min(t + 0.02, 1)
			local sA = spec.section(tA)
			local sB = spec.section(tB)
			local pitch = math.atan((sB.y - sA.y) / math.max((tB - tA) * len, 0.001))
			local roll = math.rad(mid.rollDeg)
			local centerX = self.laneX + mid.centerX
			local zMid = spec.startZ - off
			local stripColor = Palette.dimAt(-zMid, Config.Art.GridValue)
			if mid.cutout and mid.cutout > 1 then
				local rail = (mid.width - mid.cutout) / 2
				makeGridStrip(
					holder,
					centerX - mid.cutout / 2 - rail / 2,
					mid.y,
					zMid,
					rail,
					pitch,
					roll,
					spec.type,
					stripColor
				)
				makeGridStrip(
					holder,
					centerX + mid.cutout / 2 + rail / 2,
					mid.y,
					zMid,
					rail,
					pitch,
					roll,
					spec.type,
					stripColor
				)
			else
				makeGridStrip(holder, centerX, mid.y, zMid, mid.width, pitch, roll, spec.type, stripColor)
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
