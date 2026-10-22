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
local MoveWave = require(ReplicatedStorage.RoBall.MoveWave)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local SEG_LEN = 5 -- studs per slice; smaller = smoother curves, more parts
-- Deck primitives live in Config.Art — the garage preview's real-scale
-- mini-lane reads the same values (no drift between menu and runtime).
local DECK_COLOR = Config.Art.DeckColor
local EDGE_W = Config.Art.EdgeW
local EDGE_H = Config.Art.EdgeH
local GRID_H = Config.Art.GridH
local CENTER_W = Config.Art.CenterW

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
	-- Optional: set by Main. Fired when the ball touches a gem: (hit, value).
	self.onGem = nil :: ((hit: BasePart, value: number) -> ())?
	-- Beat-locked movers (§8.6): obstacle parts animated on Heartbeat.
	-- Entries die with their chunk's folder; cleanup() prunes dead rows.
	self.movers =
		{} :: { { part: BasePart, base: Vector3, kind: string, amp: number, periodSec: number, phase: number } }
	self.moverConn = nil :: RBXScriptConnection?
	-- Beat clock origin for this lane's movers — set at birth so stamped
	-- MoverEpoch attributes are valid from the first chunk build.
	self.moverT0 = os.clock()
	self.moverAcc = 0
	-- Ball's current z, fed by ensureAhead/cleanup — the mover step uses
	-- it to freeze hazards that fell CullBehind studs off-camera.
	self.ballZ = 0
	-- Deck-height cursor for yAt: queries walk deeper monotonically, so
	-- the containing chunk is found by advancing, never rescanning.
	self.yCursor = 1
	-- Near-miss records (§10): one row per lethal plane — {z, cx, halfW,
	-- spin} — appended in descending-z order so the run loop scans them
	-- with a bare cursor. spin entries key off the sweep-disc radius;
	-- press rows carry the live plate so the run loop can read how far
	-- into its drop the plate was at the crossing (§10 thread bonus).
	self.hazards = {} :: {
		{
			z: number,
			cx: number,
			halfW: number,
			spin: boolean,
			press: boolean?,
			part: BasePart?,
			baseY: number,
			amp: number,
		}
	}
	-- RampGap hoops (§10): {z, cx, cy, r} per hoop — same cursor shape
	-- as hazards; a crossing inside the ring opening pays the hoop bonus.
	self.gates = {} :: { { z: number, cx: number, cy: number, r: number } }
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
	-- Hanging slabs (press plates) anchor their top to the press hang
	-- height instead of standing on the deck.
	local yBase = mid.y
	if ob.hang then
		yBase = mid.y + Config.Press.HangH - ob.h
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
	-- Client-authoritative kills (§11): the ball's physics owner reports
	-- contact — server-side Touched judged an interpolated copy of the ball
	-- and killed dodges that never touched on screen.
	CollectionService:AddTag(b, "RoBallLethal")
	local outline = Instance.new("SelectionBox")
	outline.Adornee = b
	outline.Color3 = Config.LethalColor
	outline.LineThickness = Config.Obstacles.OutlineThickness
	outline.SurfaceTransparency = 1
	outline.Parent = b
	b.Parent = parent
	-- PressRow plate (§8.6 open crusher): the read kit that replaces the
	-- roof — a ghost-red deck footprint marking the kill zone, and a thin
	-- neon gantry (rim posts + crossbeam) showing what the plate hangs
	-- from. All scenery: non-collide, can't snag or wedge.
	if ob.motion and ob.motion.kind == "dropY" then
		local z = spec.startZ - ob.t * spec.length
		local zone = Instance.new("Part")
		zone.Name = "PressZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.CastShadow = false
		zone.Material = Enum.Material.Neon
		zone.Color = Config.LethalColor
		zone.Transparency = Config.Press.ZoneTrans
		zone.Size = Vector3.new(ob.w, 0.12, ob.d)
		zone.CFrame = CFrame.new(laneX + mid.centerX + ob.xOff, mid.y + 0.06, z) * CFrame.Angles(pitch, 0, roll)
		zone.Parent = parent

		local gw = Config.Press.GantryW
		local hangTop = mid.y + Config.Press.HangH
		local gantryColor = Palette.dimAt(-z, Config.Art.GridValue)
		for _, px in ipairs({ -mid.width / 2 + gw / 2, mid.width / 2 - gw / 2 }) do
			local post = Instance.new("Part")
			post.Name = "PressGantry"
			post.Anchored = true
			post.CanCollide = false
			post.CanQuery = false
			post.CanTouch = false
			post.CastShadow = false
			post.Material = Enum.Material.Neon
			post.Color = gantryColor
			post.Size = Vector3.new(gw, hangTop - mid.y, gw)
			post.CFrame = CFrame.new(laneX + mid.centerX + px, mid.y + (hangTop - mid.y) / 2, z)
				* CFrame.Angles(pitch, 0, roll)
			post.Parent = parent
		end
		local beam = Instance.new("Part")
		beam.Name = "PressGantry"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = gantryColor
		beam.Size = Vector3.new(mid.width, gw, gw)
		beam.CFrame = CFrame.new(laneX + mid.centerX, hangTop + gw / 2, z) * CFrame.Angles(pitch, 0, roll)
		beam.Parent = parent
		-- Slam telegraph: the plate's outline fills toward solid as the
		-- wave drops — MoverController drives SurfaceTransparency off the
		-- shared pulse each frame.
		outline.SurfaceColor3 = Config.LethalColor
	end
	-- Spin arms (Rotor): the moving hazard gets the loudest read — a neon
	-- blade, plus a translucent disc tinting exactly the swept zone so the
	-- always-clear rim lanes read from render distance.
	if ob.motion and ob.motion.kind == "spin" then
		b.Material = Enum.Material.Neon
		b.Color = Config.LethalColor
		local r = ob.w / 2
		local disc = Instance.new("Part")
		disc.Name = "RotorDisc"
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Shape = Enum.PartType.Cylinder
		disc.Transparency = Config.Movers.RotorDiscTrans
		disc.Material = Enum.Material.Neon
		disc.Color = Config.LethalColor
		disc.Size = Vector3.new(Config.Movers.RotorDiscH, r * 2, r * 2)
		-- Cylinder axis is local X: roll it up to deck-normal via the same
		-- pitch/roll basis the deck uses.
		disc.CFrame = CFrame.new(
			laneX + mid.centerX + ob.xOff,
			yBase + Config.Movers.RotorDiscH,
			spec.startZ - ob.t * spec.length
		) * CFrame.Angles(pitch, 0, roll) * CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = parent
	end
	-- `mid` rides along so the hazard record doesn't re-pay a section call.
	return b, mid
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

-- RampGap hoop (§8.6): a faceted neon ring floating at the void's flight
-- apex — the ball threads it mid-jump for the gem bonus (§10). Faceted
-- box segments match the angular wireframe palette (no torus primitive).
-- The record feeds streamer.gates: inside-the-ring pays Hoop.Score/.Bank.
local function makeHoop(
	parent: Instance,
	laneX: number,
	spec: ChunkDefs.ChunkSpec,
	hoop: { t: number }
): { z: number, cx: number, cy: number, r: number }
	local mid = spec.section(hoop.t)
	local zMid = spec.startZ - hoop.t * spec.length
	local cX = laneX + mid.centerX
	local cfg = Config.Hoop
	local r = cfg.Radius
	local centerY = mid.y + cfg.ApexLift
	local neon = Palette.neonAt(-zMid)
	local SEGS = 14
	local rMid = r + cfg.Tube * 0.5 -- ring centerline radius
	local segLen = (2 * math.pi * rMid / SEGS) * 1.25 -- ~25% overlap: no slivers
	for s = 0, SEGS - 1 do
		local a = s / SEGS * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "HoopRing"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Size = Vector3.new(segLen, cfg.Tube, cfg.Tube)
		seg.CFrame = CFrame.new(cX + rMid * math.cos(a), centerY + rMid * math.sin(a), zMid)
			* CFrame.Angles(0, 0, a + math.rad(90))
		seg.Color = neon
		seg.Material = Enum.Material.Neon
		seg.Parent = parent
	end
	return { z = zMid, cx = cX, cy = centerY, r = r }
end

-- JumpOrb (§8.6 stretch): a lime ring floating over the void. Non-collide —
-- the tap is proximity-based client-side (OrbController), never a wall.
local function makeOrb(parent: Instance, laneX: number, spec: ChunkDefs.ChunkSpec, orb: ChunkDefs.Orb)
	local mid = spec.section(orb.t)
	local o = Instance.new("Part")
	o.Name = "JumpOrb"
	o.Shape = Enum.PartType.Ball
	o.Anchored = true
	o.CanCollide = false
	o.CanQuery = false
	o.CastShadow = false
	o.Size = Vector3.new(2.4, 2.4, 2.4)
	o.CFrame = CFrame.new(laneX + mid.centerX + orb.xOff, mid.y + orb.yOff, spec.startZ - orb.t * spec.length)
	o.Color = Config.Orbs.Color
	o.Material = Enum.Material.Neon
	o:SetAttribute("KickY", orb.kickY)
	o:SetAttribute("Radius", orb.radius)
	o:SetAttribute("ChunkType", spec.type)
	CollectionService:AddTag(o, "RoBallOrb")
	o.Parent = parent
end

-- FlipRide (§8.6 stretch): a collide ceiling ribbon over the zone plus a
-- tagged invisible zone box the client's drive loop tests against.
local function emitFlipZone(
	holder: Instance,
	laneX: number,
	spec: ChunkDefs.ChunkSpec,
	flip: ChunkDefs.FlipZone,
	deckColorAt: (number) -> Color3
)
	local len = spec.length
	local t0, t1 = flip.t0, flip.t1
	local s0 = spec.section(t0)
	local s1 = spec.section(t1)
	local mid = spec.section((t0 + t1) / 2)
	local span = (t1 - t0) * len
	local zMid = spec.startZ - (t0 + t1) / 2 * len
	local topY = (s0.y + s1.y) / 2 + flip.clearH
	local pitch = math.atan((s1.y - s0.y) / span)
	local roll = math.rad(mid.rollDeg)
	local width = mid.width
	local centerX = laneX + mid.centerX

	-- The ceiling ribbon the ball rides. Real deck part — collide on.
	makeSlicePart(holder, centerX, topY, zMid, width, span, pitch, roll, spec.type, deckColorAt(zMid))
	local c = Palette.neonAt(-zMid)
	makeEdgeStrip(holder, centerX - width / 2 + EDGE_W / 2, topY, zMid, span, pitch, roll, spec.type, c)
	makeEdgeStrip(holder, centerX + width / 2 - EDGE_W / 2, topY, zMid, span, pitch, roll, spec.type, c)

	-- Portal frames at both ends: tall neon arches marking the flip.
	for _, t in ipairs({ t0, t1 }) do
		local s = spec.section(t)
		local z = spec.startZ - t * len
		local cX = laneX + s.centerX
		local postH = flip.clearH + 3
		for _, sx in ipairs({ -1, 1 }) do
			local post = Instance.new("Part")
			post.Name = "FlipPost"
			post.Anchored = true
			post.CanCollide = false
			post.CanQuery = false
			post.Size = Vector3.new(0.9, postH, 0.9)
			post.CFrame = CFrame.new(cX + sx * (s.width / 2 - 0.6), s.y + postH / 2, z)
			post.Color = c
			post.Material = Enum.Material.Neon
			post.Parent = holder
		end
		local bar = Instance.new("Part")
		bar.Name = "FlipBar"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.Size = Vector3.new(s.width - 0.4, 0.9, 0.9)
		bar.CFrame = CFrame.new(cX, s.y + postH + 0.45, z)
		bar.Color = c
		bar.Material = Enum.Material.Neon
		bar.Parent = holder
	end

	-- The zone box: axis-aligned, invisible, tagged — the client checks
	-- containment each frame instead of trusting Touched on a volume.
	local zone = Instance.new("Part")
	zone.Name = "FlipZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Size = Vector3.new(width + 6, flip.clearH + 8, span + 4)
	zone.CFrame = CFrame.new(centerX, topY - flip.clearH / 2, zMid)
	zone:SetAttribute("ChunkType", spec.type)
	CollectionService:AddTag(zone, "RoBallFlipZone")
	zone.Parent = holder
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

	-- spec.section(t) allocates a fresh Section per call (PERFORMANCE.md
	-- §3): emitDeck and the transverse marks re-queried ~3x per feature.
	-- Aligned t hits `samples` directly; anything else memoizes per build.
	local secCache: { [number]: ChunkDefs.Section } = {}
	local function secAt(t: number): ChunkDefs.Section
		local i = math.round(t * n)
		if i >= 0 and i <= n and math.abs(t - i / n) < 1e-6 then
			return samples[i + 1]
		end
		local s = secCache[t]
		if not s then
			s = spec.section(t)
			secCache[t] = s
		end
		return s
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
	end

	-- One straight deck box (or twin rails for a cutout) spanning tA..tB.
	-- Banked spans halve until their edge seam lip fits RollLipMax — each
	-- slab pivots about the centerline, so a roll change across it leaves a
	-- vertical step at the edges that would otherwise read as facets (and
	-- can catch the ball). Flat and held-bank spans merge upstream, so this
	-- split only fires inside roll transitions.
	local function emitDeck(tA: number, tB: number, depth: number?)
		local tM = (tA + tB) / 2
		local sA = secAt(tA)
		local sB = secAt(tB)
		local mid = secAt(tM)
		if mid.width <= 0.5 then
			return
		end
		local d = depth or 0
		if d < 6 then
			local lip = math.abs(math.tan(math.rad(sB.rollDeg)) - math.tan(math.rad(sA.rollDeg))) * mid.width / 2
			if lip > Config.Art.RollLipMax then
				emitDeck(tA, tM, d + 1)
				emitDeck(tM, tB, d + 1)
				return
			end
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
				-- Void-adjacent inner edges glow lethal red (DESIGN.md §3:
				-- red = kill geometry; the void IS kill geometry). The pair
				-- of red lines converging down the center is the split's
				-- tell long before the hole is under the ball.
				if railLW > 0.5 then
					makeEdgeStrip(holder, lEdge + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, c)
					makeEdgeStrip(holder, cutL - EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, Config.LethalColor)
				end
				if railRW > 0.5 then
					makeEdgeStrip(holder, cutR + EDGE_W / 2, y0, z0, sub, pitch, roll, spec.type, Config.LethalColor)
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
		local mid = secAt(t)
		if mid.width > 0.5 then
			local tA = math.max(t - 0.02, 0)
			local tB = math.min(t + 0.02, 1)
			local sA = secAt(tA)
			local sB = secAt(tB)
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
		end
	end

	-- Sector ribbons (§14): a brighter transverse mark at each
	-- Config.Sectors.Length boundary — the pace pulse the HUD counts is
	-- visible on the deck itself, on the same cadence as the SEC flashes.
	-- Cutout chunks paint per rail so no line floats over the void.
	local secL = Config.Sectors.Length
	local endZ = spec.startZ - spec.length
	for sec = math.max(1, math.ceil(-spec.startZ / secL)), math.ceil(-endZ / secL) - 1 do
		local z = -sec * secL
		local t = (spec.startZ - z) / spec.length
		local mid = secAt(t)
		if mid.width > 0.5 then
			local tA = math.max(t - 0.02, 0)
			local tB = math.min(t + 0.02, 1)
			local sA = secAt(tA)
			local sB = secAt(tB)
			local pitch = math.atan((sB.y - sA.y) / math.max((tB - tA) * len, 0.001))
			local roll = math.rad(mid.rollDeg)
			local cX = self.laneX + mid.centerX
			local markColor = Palette.neonAt(-z)
			local function mark(cx: number, w: number)
				local m = Instance.new("Part")
				m.Name = "SectorMark"
				m.Anchored = true
				m.CanCollide = false
				m.CanQuery = false
				m.CanTouch = false
				m.CastShadow = false
				m.Size = Vector3.new(math.max(w - 1, 0.5), GRID_H, Config.Sectors.MarkW)
				m.CFrame = CFrame.new(cx, mid.y + GRID_H / 2 + 0.03, z) * CFrame.Angles(pitch, 0, roll)
				m.Color = markColor
				m.Transparency = Config.Sectors.MarkTrans
				m.Material = Enum.Material.Neon
				m:SetAttribute("ChunkType", spec.type)
				m.Parent = holder
			end
			if mid.cutout and mid.cutout > 1 then
				local cutMid = mid.cutoutOff or 0
				local railLW = cutMid - mid.cutout / 2 + mid.width / 2
				local railRW = mid.width / 2 - (cutMid + mid.cutout / 2)
				if railLW > 0.5 then
					mark(cX - mid.width / 2 + railLW / 2, railLW)
				end
				if railRW > 0.5 then
					mark(cX + mid.width / 2 - railRW / 2, railRW)
				end
			else
				mark(cX, mid.width)
			end
		end
	end

	if spec.obstacles then
		-- This chunk's lethal planes, collected beside the build and merged
		-- in z-descending order — obstacle lists aren't guaranteed sorted.
		-- Hanging slabs are roof geometry: a lateral "near-miss" under them
		-- would be dishonest, so they earn no record — except dropY press
		-- plates, where the dodge is vertical and the crossing IS the
		-- thread (§10).
		local hzSeg = {}
		for _, ob in ipairs(spec.obstacles) do
			local block, mid = makeBlock(holder, self.laneX, spec, ob)
			local isPress = ob.hang and ob.motion ~= nil and ob.motion.kind == "dropY"
			if not ob.hang or isPress then
				table.insert(hzSeg, {
					z = spec.startZ - ob.t * spec.length,
					cx = self.laneX + mid.centerX + ob.xOff,
					halfW = ob.w / 2,
					spin = ob.motion ~= nil and ob.motion.kind == "spin",
					press = isPress or nil,
					part = if isPress then block else nil,
					baseY = if isPress then block.Position.Y else 0,
					amp = if isPress and ob.motion then ob.motion.amp or 0 else 0,
				})
			end
			if ob.motion then
				-- Client smooths the motion (§8.6): the part carries its
				-- whole waveform — kind/amp/period/phase plus the base
				-- position and this lane's beat-clock epoch on the shared
				-- server clock — so the client re-evaluates it every frame
				-- instead of seeing StepHz teleports.
				block:SetAttribute("MoverKind", ob.motion.kind)
				block:SetAttribute("MoverAmp", ob.motion.amp or 0)
				block:SetAttribute("MoverPeriod", ob.motion.periodSec)
				block:SetAttribute("MoverPhase", ob.motion.phase or 0)
				block:SetAttribute("MoverBase", block.Position)
				block:SetAttribute("MoverEpoch", workspace:GetServerTimeNow() - (os.clock() - self.moverT0))
				CollectionService:AddTag(block, "RoBallMover")
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
		table.sort(hzSeg, function(a, b)
			return a.z > b.z
		end)
		for _, h in ipairs(hzSeg) do
			table.insert(self.hazards, h)
		end
		self:startMovers()
	end

	if spec.pads then
		for _, pad in ipairs(spec.pads) do
			makePad(holder, self.laneX, spec, pad)
		end
	end

	if spec.orbs then
		for _, orb in ipairs(spec.orbs) do
			makeOrb(holder, self.laneX, spec, orb)
		end
	end

	if spec.flip then
		emitFlipZone(holder, self.laneX, spec, spec.flip, deckColorAt)
	end

	if spec.hoop then
		table.insert(self.gates, makeHoop(holder, self.laneX, spec, spec.hoop))
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

-- Keep generated track AheadDistance studs in front of the ball. The
-- per-frame call builds at most ChunkBuildsPerFrame chunks — the window
-- tops up a chunk at a time instead of bursting ~90 Instance.news in
-- one heartbeat when several chunks come due together.
function TrackStreamer:ensureAhead(ballZ: number, maxBuilds: number?)
	self.ballZ = ballZ
	local target = ballZ - Config.Generation.AheadDistance
	local budget = maxBuilds or Config.Generation.ChunkBuildsPerFrame
	while self.gen.state.zEnd > target and budget > 0 do
		self:buildChunk(self.gen:nextChunk())
		budget -= 1
	end
end

-- Destroy chunks fully behind the ball.
function TrackStreamer:cleanup(ballZ: number)
	self.ballZ = ballZ
	local cutoff = ballZ + Config.Generation.BehindDistance
	local i = 1
	local removed = 0
	while i <= #self.chunks do
		local c = self.chunks[i]
		if c.endZ > cutoff then
			c.holder:Destroy()
			table.remove(self.chunks, i)
			removed += 1
		else
			i += 1
		end
	end
	if removed > 0 then
		-- Culled rows came off the front — the yAt cursor's chunk index
		-- shifts by however many left.
		self.yCursor = math.max(1, self.yCursor - removed)
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
-- arms spin around their post, PressRow plates slam down on the count.
-- Periods are whole-note multiples of the heard tempo — the hazard cycle
-- IS the music. The server's StepHz positions feed its own hazard math;
-- clients re-evaluate the same wave per-frame (MoverController) so the
-- motion reads smooth, not stepped. Touched still kills.
function TrackStreamer:startMovers()
	if self.moverConn or #self.movers == 0 then
		return
	end
	local stepDt = 1 / Config.Movers.StepHz
	self.moverConn = RunService.Heartbeat:Connect(function(dt)
		-- Position writes replicate to every client — dt-accumulate down
		-- to StepHz (PERFORMANCE.md §2). The phase still reads the
		-- absolute beat clock, so the motion itself is unchanged, just
		-- written less often.
		self.moverAcc += dt
		if self.moverAcc < stepDt then
			return
		end
		self.moverAcc %= stepDt
		local t = os.clock() - self.moverT0
		local cullZ = self.ballZ + Config.Movers.CullBehind
		for _, m in ipairs(self.movers) do
			-- Movers CullBehind studs behind the ball are off-camera —
			-- freeze them until cleanup claims the chunk.
			if m.part.Parent and m.base.Z <= cullZ then
				local ang = t / m.periodSec * math.pi * 2 + m.phase
				if m.kind == "slideX" then
					m.part.Position = m.base + Vector3.new(m.amp * math.sin(ang), 0, 0)
				elseif m.kind == "dropY" then
					local x = (ang / (math.pi * 2)) % 1
					m.part.Position = m.base + Vector3.new(0, -m.amp * MoveWave.pressPulse(x), 0)
				else -- spin
					m.part.CFrame = CFrame.new(m.base) * CFrame.Angles(0, ang, 0)
				end
			end
		end
	end)
end

-- Which chunk owns world z — for death-cause attribution (§11): VOID and
-- STALL deaths name the feature that ate the run, not just the manner.
function TrackStreamer:chunkTypeAt(z: number): string?
	for _, c in ipairs(self.chunks) do
		if z <= c.startZ and z > c.endZ then
			return c.spec.type
		end
	end
	return nil
end

-- Deck-top height at world z (for the kill plane). Exact via section fns.
-- Queries during a run only move deeper (the ball rolls -Z), so a cursor
-- into the z-ordered chunk list walks forward instead of rescanning it
-- every frame; a probe behind the cursor (run-start PB/last markers)
-- rescans once and re-seats the cursor on the hit.
function TrackStreamer:yAt(z: number): number
	local i = self.yCursor
	while i < #self.chunks and z <= self.chunks[i + 1].startZ do
		i += 1
	end
	if i > 1 and z > self.chunks[i].startZ then
		i = 1
		while i < #self.chunks and z <= self.chunks[i + 1].startZ do
			i += 1
		end
	end
	self.yCursor = i
	local c = self.chunks[i]
	if c and z <= c.startZ and z > c.endZ then
		return c.spec.section((c.startZ - z) / c.spec.length).y
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
