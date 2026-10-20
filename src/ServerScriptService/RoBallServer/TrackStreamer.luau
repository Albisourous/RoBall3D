--!strict
-- TrackStreamer: turns pure ChunkSpecs (GenCore) into Instanced geometry for
-- one player's lane, keeps AheadDistance of track generated in front of the
-- ball, destroys chunks BehindDistance behind it. Owns the deck-height lookup
-- used by the kill plane.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	-- Beat-locked movers (§8.6): obstacle parts animated on Heartbeat.
	-- Entries die with their chunk's folder; cleanup() prunes dead rows.
	self.movers =
		{} :: { { part: BasePart, base: Vector3, kind: string, amp: number, periodSec: number, phase: number } }
	self.moverConn = nil :: RBXScriptConnection?
	self.moverT0 = 0
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
	-- Hanging slabs (TunnelSlot) anchor their top to the roof height
	-- instead of standing on the deck.
	local yBase = mid.y
	if ob.hang then
		yBase = mid.y + (mid.roofH or Config.Tunnel.RoofH) - ob.h
	end
	local b = Instance.new("Part")
	b.Name = "LethalBlock"
	b.Anchored = true
	b.Size = Vector3.new(ob.w, ob.h, ob.d)
	b.CFrame = CFrame.new(laneX + mid.centerX + ob.xOff, yBase + ob.h / 2, spec.startZ - ob.t * spec.length)
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

-- LaunchPad (§8.6): cyan neon strip lying on the deck; non-collide —
-- contact is the trigger, never a wall. The client's PadController reads
-- KickY off the attribute and applies it as the ball's vertical velocity
-- (the ball's network owner is the client, so the kick lands lag-free).
local function makePad(parent: Instance, laneX: number, spec: ChunkDefs.ChunkSpec, pad: ChunkDefs.Pad)
	local mid = spec.section(pad.t)
	local dt = 0.02
	local sA = spec.section(math.max(pad.t - dt, 0))
	local sB = spec.section(math.min(pad.t + dt, 1))
	local pitch = math.atan((sB.y - sA.y) / math.max((pad.t + dt - math.max(pad.t - dt, 0)) * spec.length, 0.001))
	local p = Instance.new("Part")
	p.Name = "LaunchPad"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = Vector3.new(pad.w, 0.35, pad.d)
	p.CFrame = CFrame.new(laneX + mid.centerX + pad.xOff, mid.y + 0.18, spec.startZ - pad.t * spec.length)
		* CFrame.Angles(pitch, 0, math.rad(mid.rollDeg))
	p.Color = Config.Pads.Color
	p.Material = Enum.Material.Neon
	p:SetAttribute("KickY", pad.kickY)
	p:SetAttribute("ChunkType", spec.type)
	CollectionService:AddTag(p, "RoBallPad")
	p.Parent = parent
	return p
end

-- TierGate arch (§8.6): non-collide neon posts + header + a distance
-- BillboardGui where the run crosses a tier boundary — GD progress-marker
-- feel and a readable "you leveled up" beat, zero gameplay effect.
local function makeTierGate(
	parent: Instance,
	laneX: number,
	spec: ChunkDefs.ChunkSpec,
	gate: { dist: number, t: number }
)
	local mid = spec.section(gate.t)
	local zMid = spec.startZ - gate.t * spec.length
	local cX = laneX + mid.centerX
	local w = math.max(mid.width, 8)
	local neon = Palette.neonAt(-zMid)
	local postH = 9
	for _, s in ipairs({ -1, 1 }) do
		local post = Instance.new("Part")
		post.Name = "GatePost"
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.CastShadow = false
		post.Size = Vector3.new(0.8, postH, 0.8)
		post.CFrame = CFrame.new(cX + s * (w / 2 - 0.6), mid.y + postH / 2, zMid)
		post.Color = neon
		post.Material = Enum.Material.Neon
		post.Parent = parent
	end
	local bar = Instance.new("Part")
	bar.Name = "GateBar"
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CastShadow = false
	bar.Size = Vector3.new(w - 0.4, 0.8, 0.8)
	bar.CFrame = CFrame.new(cX, mid.y + postH + 0.4, zMid)
	bar.Color = neon
	bar.Material = Enum.Material.Neon
	bar.Parent = parent
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 28)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop = false
	bb.Parent = bar
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.Code
	tl.TextSize = 20
	tl.TextColor3 = neon
	tl.Text = tostring(gate.dist) .. "m"
	tl.Parent = bb
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

	-- Blackout (§8.6): the chunk's transverse + center neon dims to a
	-- fraction of normal — edge rails and gems stay lit (they're the read).
	local gridScale = if spec.dim then Config.Blackout.GridScale else 1

	local function sameShape(a: ChunkDefs.Section, b: ChunkDefs.Section): boolean
		return math.abs(a.width - b.width) <= 0.06
			and math.abs(a.centerX - b.centerX) <= 0.06
			and math.abs(a.rollDeg - b.rollDeg) <= 0.06
			and math.abs((a.cutout or 0) - (b.cutout or 0)) <= 0.06
			and math.abs((a.cutoutOff or 0) - (b.cutoutOff or 0)) <= 0.06
			and math.abs((a.wallH or 0) - (b.wallH or 0)) <= 0.06
			and math.abs((a.roofH or 0) - (b.roofH or 0)) <= 0.06
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
			-- Split/fork rails: the void spans [off - cut/2, off + cut/2]
			-- around the deck center — cutoutOff shifts it for asymmetric
			-- risk/safe rails (Fork).
			local off = mid.cutoutOff or 0
			local cutL = centerX + off - mid.cutout / 2
			local cutR = centerX + off + mid.cutout / 2
			local lEdge = centerX - width / 2
			local rEdge = centerX + width / 2
			local railLW = cutL - lEdge
			local railRW = rEdge - cutR
			if railLW > 0.5 then
				makeSlicePart(holder, lEdge + railLW / 2, topY, zMid, railLW, span, pitch, roll, spec.type, deckColor)
			end
			if railRW > 0.5 then
				makeSlicePart(holder, cutR + railRW / 2, topY, zMid, railRW, span, pitch, roll, spec.type, deckColor)
			end
			eachStripSeg(span, zMid, topY, pitch, function(z0, y0, sub)
				local c = Palette.neonAt(-z0)
				if railLW > 0.5 then
					makeEdgeStrip(holder, lEdge + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
					makeEdgeStrip(holder, cutL - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				end
				if railRW > 0.5 then
					makeEdgeStrip(holder, cutR + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
					makeEdgeStrip(holder, rEdge - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
				end
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
					Palette.dimAt(-z0, Config.Art.GridValue * gridScale)
				)
			end)
		end

		if mid.wallH and mid.wallH > 0.1 then
			makeWall(holder, centerX - width / 2 + 0.5, topY, zMid, mid.wallH, span, pitch, roll, spec.type, deckColor)
			makeWall(holder, centerX + width / 2 - 0.5, topY, zMid, mid.wallH, span, pitch, roll, spec.type, deckColor)
		end

		-- TunnelSlot roof (§8.6): a dark ceiling ribbon with neon edge
		-- lines enclosing the deck. Non-collide — nothing can reach it.
		if mid.roofH and mid.roofH > 0.1 then
			local roofY = topY + mid.roofH
			makeSlicePart(holder, centerX, roofY, zMid, width, span, pitch, roll, spec.type, deckColor)
			local c = Palette.dimAt(-zMid, Config.Art.GridValue * gridScale)
			makeEdgeStrip(holder, centerX - width / 2 + EDGE_W / 2, roofY, zMid, span, pitch, roll, spec.type, c)
			makeEdgeStrip(holder, centerX + width / 2 - EDGE_W / 2, roofY, zMid, span, pitch, roll, spec.type, c)
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
			local stripColor = Palette.dimAt(-zMid, Config.Art.GridValue * gridScale)
			if mid.cutout and mid.cutout > 1 then
				local cutMid = mid.cutoutOff or 0
				local cutL = cutMid - mid.cutout / 2
				local cutR = cutMid + mid.cutout / 2
				local railLW = cutL + mid.width / 2 -- rail width = inner edge - (-w/2)
				local railRW = mid.width / 2 - cutR
				if railLW > 0.5 then
					makeGridStrip(
						holder,
						centerX - mid.width / 2 + railLW / 2,
						mid.y,
						zMid,
						railLW,
						pitch,
						roll,
						spec.type,
						stripColor
					)
				end
				if railRW > 0.5 then
					makeGridStrip(
						holder,
						centerX + cutR + railRW / 2,
						mid.y,
						zMid,
						railRW,
						pitch,
						roll,
						spec.type,
						stripColor
					)
				end
			else
				makeGridStrip(holder, centerX, mid.y, zMid, mid.width, pitch, roll, spec.type, stripColor)
			end
			-- TunnelSlot rib: a neon line across the ceiling sells the tube.
			if mid.roofH and mid.roofH > 1 then
				makeGridStrip(
					holder,
					centerX,
					mid.y + mid.roofH - 0.05,
					zMid,
					mid.width,
					pitch,
					roll,
					spec.type,
					stripColor
				)
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
			if ob.motion then
				table.insert(self.movers, {
					part = block,
					base = block.Position,
					kind = ob.motion.kind,
					amp = ob.motion.amp or 0,
					periodSec = ob.motion.periodSec,
					phase = ob.motion.phase,
				})
			end
		end
		self:startMovers()
	end

	if spec.pads then
		for _, pad in ipairs(spec.pads) do
			makePad(holder, self.laneX, spec, pad)
		end
	end

	if spec.tierGate then
		makeTierGate(holder, self.laneX, spec, spec.tierGate)
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
	local culled = false
	while i <= #self.chunks do
		local c = self.chunks[i]
		if c.endZ > cutoff then
			c.holder:Destroy()
			table.remove(self.chunks, i)
			culled = true
		else
			i += 1
		end
	end
	if culled then
		-- Mover parts died with their chunk folders — drop the dead rows so
		-- the list stays bounded.
		local j = 1
		while j <= #self.movers do
			if self.movers[j].part.Parent == nil then
				table.remove(self.movers, j)
			else
				j += 1
			end
		end
	end
end

-- Beat-locked movers (DESIGN.md §8.6): Pacer slabs slide laterally, Rotor
-- arms spin around their post. Periods are whole-note multiples of the
-- heard tempo — the hazard cycle IS the music. Server-side CFrame
-- animation on anchored parts replicates fine; Touched still kills.
function TrackStreamer:startMovers()
	if self.moverConn or #self.movers == 0 then
		return
	end
	self.moverT0 = os.clock()
	self.moverConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - self.moverT0
		for _, m in ipairs(self.movers) do
			if m.part.Parent then
				local ang = t / m.periodSec * math.pi * 2 + m.phase
				if m.kind == "slideX" then
					m.part.Position = m.base + Vector3.new(m.amp * math.sin(ang), 0, 0)
				else -- spin
					m.part.CFrame = CFrame.new(m.base) * CFrame.Angles(0, ang, 0)
				end
			end
		end
	end)
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
	if self.moverConn then
		self.moverConn:Disconnect()
		self.moverConn = nil
	end
	self.folder:Destroy()
end

return TrackStreamer
