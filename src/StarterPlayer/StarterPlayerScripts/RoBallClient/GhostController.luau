--!strict
-- GhostController (DESIGN.md §14): the PB echo. While a run is live it
-- samples ball position at Config.Ghost.SampleSeconds cadence; when the
-- run ends as a new best, Main.client ships the frames to the server
-- (which only accepts them against a one-shot record credential). On run
-- start it asks for the stored ghost and, when its seed matches, replays
-- the frames as a translucent ball — racing your own PB line.
--
-- Cosmetic only: the ghost part is CanCollide/CanQuery/CanTouch-off,
-- never joins physics, and dies with the run. Recording is flat-table
-- appends — no per-frame instance creation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

local GhostController = {}

type Frames = { number } -- flat t,x,y,z quads

local recT = 0 -- run-time clock for sampling
local recNext = 0 -- next sample time
local rec: Frames = {}
local recording = false

type Echo = { part: BasePart, frames: Frames, idx: number }

local echoes: { Echo } = {}
local pbEcho: Echo? = nil -- the echo pace() reads; nil without a PB replay
local rivalEcho: Echo? = nil -- the champion echo rivalPace() reads
local ghostT = 0 -- replay clock, shared by every echo on the run
local playing = false

function GhostController.beginRecord()
	recT = 0
	recNext = 0
	rec = {}
	recording = true
end

-- Called from the run heartbeat: sample position, advance the echo.
function GhostController.tick(dt: number, ballPos: Vector3)
	if recording then
		recT += dt
		if recT >= recNext and #rec < Config.Ghost.MaxSamples * 4 then
			recNext = recT + Config.Ghost.SampleSeconds
			table.insert(rec, recT)
			table.insert(rec, ballPos.X)
			table.insert(rec, ballPos.Y)
			table.insert(rec, ballPos.Z)
		end
	end
	if playing then
		ghostT += dt
		for _, echo in ipairs(echoes) do
			local frames = echo.frames
			-- Frames are time-ordered; walk the cursor to the current t.
			while echo.idx <= #frames and frames[echo.idx] < ghostT do
				echo.idx += 4
			end
			if echo.idx >= #frames then
				-- Past the record's end: the echo holds its last point (the
				-- run it died on) until the player passes it.
				local n = #frames
				echo.part.Position = Vector3.new(frames[n - 2], frames[n - 1], frames[n])
			else
				local t2, x2, y2, z2 =
					frames[echo.idx], frames[echo.idx + 1], frames[echo.idx + 2], frames[echo.idx + 3]
				if echo.idx > 1 then
					local t1, x1, y1, z1 =
						frames[echo.idx - 4], frames[echo.idx - 3], frames[echo.idx - 2], frames[echo.idx - 1]
					local span = math.max(t2 - t1, 1e-3)
					local a = math.clamp((ghostT - t1) / span, 0, 1)
					echo.part.Position = Vector3.new(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, z1 + (z2 - z1) * a)
				else
					echo.part.Position = Vector3.new(x2, y2, z2)
				end
			end
		end
	end
end

-- Compact wire format: t in hundredths, coords in tenths.
function GhostController.framesCsv(): string?
	local n = #rec / 4
	if n < Config.Ghost.MinFrames then
		return nil
	end
	-- Rows join on ";" — "t,x,y,z;t,x,y,z;...". Built straight into the
	-- row list (PERFORMANCE.md §3): no temp numbers array, no per-row
	-- {a,b,c,d} for concat — string concat tostrings like concat did.
	local rows = table.create(n)
	for i = 1, #rec, 4 do
		local t = math.floor(rec[i] * 100 + 0.5)
		local x = math.floor(rec[i + 1] * 10 + 0.5) / 10
		local y = math.floor(rec[i + 2] * 10 + 0.5) / 10
		local z = math.floor(rec[i + 3] * 10 + 0.5) / 10
		rows[(i + 3) / 4] = t .. "," .. x .. "," .. y .. "," .. z
	end
	return table.concat(rows, ";")
end

local function parseFrames(csv: string): Frames?
	local f: Frames = {}
	local n = 0
	local prevT = 0
	local gb = Config.Ghost
	for frame in string.gmatch(csv, "[^;]+") do
		for v in string.gmatch(frame, "[^,]+") do
			local num = tonumber(v)
			-- tonumber("1e999") -> inf, "nan"-shaped rows -> NaN — corrupt
			-- payloads must fail the whole parse, not one coordinate.
			if not num or num ~= num or math.abs(num) == math.huge then
				return nil
			end
			local pos = #f % 4 -- 0=t, 1=x, 2=y, 3=z
			num = num / (if pos == 0 then 100 else 1) -- t back to seconds
			-- Envelope + ordering (Config.Ghost.Frame*): t never goes
			-- backward (the replay cursor walks monotonically), and no
			-- legit frame sits outside the playable volume.
			if
				(pos == 0 and num < prevT)
				or (pos == 1 and math.abs(num) > gb.FrameMaxAbsX)
				or (pos == 2 and (num < gb.FrameMinY or num > gb.FrameMaxY))
				or (pos == 3 and (num < gb.FrameMinZ or num > gb.FrameMaxZ))
			then
				return nil
			end
			if pos == 0 then
				prevT = num
			end
			table.insert(f, num)
		end
		n += 1
	end
	if n < Config.Ghost.MinFrames or #f % 4 ~= 0 then
		return nil
	end
	return f
end

local function spawnEcho(f: Frames, name: string, color: Color3, transparency: number, label: string?): Echo
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(3, 3, 3)
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = transparency
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Name = name
	ball.Position = Vector3.new(f[2], f[3], f[4])
	-- Split trail (§14): a short ribbon between two y-offset attachments
	-- — it draws the echo's line through bends so the diverging route
	-- reads, not just the two points' distance.
	local gap = Config.Ghost.TrailGap
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, gap, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -gap, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.min(transparency + Config.Ghost.TrailFade, 1)),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = Config.Ghost.TrailLife
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Parent = ball
	if label then
		-- Diegetic announce: the champion's name rides its echo, no HUD space.
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(90, 14)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 300
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(1, 1)
		tl.Font = Enum.Font.Code
		tl.TextSize = 11
		tl.TextColor3 = color
		tl.TextStrokeTransparency = 0.4
		tl.Text = label
		tl.Parent = bb
		bb.Parent = ball
	end
	ball.Parent = workspace
	return { part = ball, frames = f, idx = 1 }
end

-- Attach the stored PB ghost: parse frames, spawn the echo. Returns false
-- on a malformed csv so the caller can just not replay.
function GhostController.attach(csv: string): boolean
	local f = parseFrames(csv)
	if not f then
		return false
	end
	pbEcho = spawnEcho(f, "PbGhost", Color3.fromRGB(0, 230, 255), Config.Ghost.Transparency, "PB")
	table.insert(echoes, pbEcho :: Echo)
	playing = true
	return true
end

-- Attach the seed champion's replay (§14): the rival line — gold echo
-- carrying the record holder's name. Shares the run clock with the PB
-- echo; pace() ignores it (that line is yours-vs-you).
function GhostController.attachRival(csv: string, name: string): boolean
	local f = parseFrames(csv)
	if not f then
		return false
	end
	rivalEcho = spawnEcho(f, "RivalGhost", Config.Ghost.RivalColor, Config.Ghost.RivalTransparency, name)
	table.insert(echoes, rivalEcho :: Echo)
	playing = true
	return true
end

-- Crowd ghost (§14): the daily seed's silver seat — a labeled silver
-- echo on the same shared clock. No pace line: presence, not another
-- HUD debt; stop() clears it with the rest.
function GhostController.attachCrowd(csv: string, name: string): boolean
	local f = parseFrames(csv)
	if not f then
		return false
	end
	table.insert(echoes, spawnEcho(f, "CrowdGhost", Config.Ghost.CrowdColor, Config.Ghost.CrowdTransparency, name))
	playing = true
	return true
end

function GhostController.stop()
	recording = false
	playing = false
	ghostT = 0
	for _, echo in ipairs(echoes) do
		echo.part:Destroy()
	end
	table.clear(echoes)
	pbEcho = nil
	rivalEcho = nil
end

-- Pace delta (§12): meters ahead of the PB echo at this instant —
-- positive when the live ball is further down-track than the ghost
-- (both roll -Z, so the lead is ghostZ - ballZ). nil when no echo is
-- replaying; the HUD hides the line then.
function GhostController.pace(ballPos: Vector3): number?
	if playing and pbEcho then
		return pbEcho.part.Position.Z - ballPos.Z
	end
	return nil
end

-- Rival pace (§14): same lead math vs the champion echo — the gap to
-- the seed's record. nil when no rival is replaying.
function GhostController.rivalPace(ballPos: Vector3): number?
	if playing and rivalEcho then
		return rivalEcho.part.Position.Z - ballPos.Z
	end
	return nil
end

return GhostController
