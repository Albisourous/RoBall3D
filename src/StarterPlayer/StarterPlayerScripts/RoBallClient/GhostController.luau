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

local part: BasePart? = nil
local frames: Frames = {}
local ghostT = 0 -- replay clock
local idx = 1 -- next frame index to pass (1-based into quads)
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
	if playing and part then
		ghostT += dt
		-- Frames are time-ordered; walk the cursor to the current t.
		while idx <= #frames and frames[idx] < ghostT do
			idx += 4
		end
		if idx >= #frames then
			-- Past the record's end: the echo holds its last point (the
			-- run it died on) until the player passes it.
			local n = #frames
			part.Position = Vector3.new(frames[n - 2], frames[n - 1], frames[n])
			return
		end
		local t2, x2, y2, z2 = frames[idx], frames[idx + 1], frames[idx + 2], frames[idx + 3]
		if idx > 1 then
			local t1, x1, y1, z1 = frames[idx - 4], frames[idx - 3], frames[idx - 2], frames[idx - 1]
			local span = math.max(t2 - t1, 1e-3)
			local a = math.clamp((ghostT - t1) / span, 0, 1)
			part.Position = Vector3.new(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, z1 + (z2 - z1) * a)
		else
			part.Position = Vector3.new(x2, y2, z2)
		end
	end
end

-- Compact wire format: t in hundredths, coords in tenths.
function GhostController.framesCsv(): string?
	local n = #rec / 4
	if n < Config.Ghost.MinFrames then
		return nil
	end
	local out = table.create(#rec)
	for i = 1, #rec, 4 do
		out[i] = math.floor(rec[i] * 100 + 0.5)
		out[i + 1] = math.floor(rec[i + 1] * 10 + 0.5) / 10
		out[i + 2] = math.floor(rec[i + 2] * 10 + 0.5) / 10
		out[i + 3] = math.floor(rec[i + 3] * 10 + 0.5) / 10
	end
	-- Rows join on ";" — "t,x,y,z;t,x,y,z;..."
	local rows = table.create(n)
	for i = 0, n - 1 do
		rows[i + 1] = table.concat({ out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3], out[i * 4 + 4] }, ",")
	end
	return table.concat(rows, ";")
end

-- Attach the stored ghost: parse frames, spawn the echo. Returns false
-- on a malformed csv so the caller can just not replay.
function GhostController.attach(csv: string): boolean
	local f: Frames = {}
	local n = 0
	for frame in string.gmatch(csv, "[^;]+") do
		for v in string.gmatch(frame, "[^,]+") do
			local num = tonumber(v)
			if not num then
				return false
			end
			table.insert(f, num / (if #f % 4 == 0 then 100 else 1)) -- t back to seconds
		end
		n += 1
	end
	if n < Config.Ghost.MinFrames or #f % 4 ~= 0 then
		return false
	end
	frames = f
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(3, 3, 3)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(0, 230, 255)
	ball.Transparency = Config.Ghost.Transparency
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Name = "PbGhost"
	ball.Position = Vector3.new(frames[2], frames[3], frames[4])
	ball.Parent = workspace
	part = ball
	ghostT = 0
	idx = 1
	playing = true
	return true
end

function GhostController.stop()
	recording = false
	playing = false
	if part then
		part:Destroy()
		part = nil
	end
end

-- Pace delta (§12): meters ahead of the PB echo at this instant —
-- positive when the live ball is further down-track than the ghost
-- (both roll -Z, so the lead is ghostZ - ballZ). nil when no echo is
-- replaying; the HUD hides the line then.
function GhostController.pace(ballPos: Vector3): number?
	if playing and part then
		return part.Position.Z - ballPos.Z
	end
	return nil
end

return GhostController
