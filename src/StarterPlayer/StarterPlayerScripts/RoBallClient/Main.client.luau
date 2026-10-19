--!strict
-- RoBall3D client entry point — Phase 4: menu -> run -> death -> retry.
-- Ball drive + chase cam only run while `mode == "running"`. Runs start on
-- server command (RequestStart -> RunStarted); death arrives via RunEnded.
-- The ball is found by name in Workspace; waiting for replication is more
-- reliable than remote args (AGENTS.md gotcha).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild("RoBallRemotes")
local evStart = remotes:WaitForChild("RequestStart") :: RemoteEvent
local evRunStarted = remotes:WaitForChild("RunStarted") :: RemoteEvent
local evRunEnded = remotes:WaitForChild("RunEnded") :: RemoteEvent
local fnGetLeaderboard = remotes:WaitForChild("GetLeaderboard") :: RemoteFunction

local ballName = player.Name .. "_Ball"
local ui = Ui.new()

local mode: "menu" | "running" | "dead" = "menu"
local ball: BasePart? = nil
local lateralVel = 0
local fwdSpeed = Config.Speed.Start
local currentSeed = 0
local controlAt = 0 -- steering unlocks after the "rolling…" settle
local lastBallPos = Vector3.new(0, Config.Generation.StartY, -30)

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
		fwdSpeed = Config.Speed.Start
		lastBallPos = ball.Position
	end
end
for _, c in ipairs(workspace:GetChildren()) do
	bindBall(c)
end
workspace.ChildAdded:Connect(bindBall)
workspace.ChildRemoved:Connect(function(c)
	if c == ball then
		ball = nil -- destroyed part isn't nil; clear so we stop driving it
	end
end)

local function steerIntent(): number
	local intent = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		intent -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		intent += 1
	end
	return intent
end

local function throttle(): number
	if not Config.Speed.ThrottleEnabled then
		return 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		return Config.Speed.ThrottleUp
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		return Config.Speed.ThrottleDown
	end
	return 1
end

--============================== wiring ==============================--

local function requestStart()
	evStart:FireServer(ui:seedText())
end
ui.onPlay = requestStart
ui.onRetry = requestStart

evRunStarted.OnClientEvent:Connect(function(seed: number)
	mode = "running"
	currentSeed = seed
	controlAt = tick() + 0.8 -- DESIGN.md §6: "rolling…" settle before control
	ui:showHud()
end)

evRunEnded.OnClientEvent:Connect(function(score: number, dist: number, gems: number, best: number, seed: number)
	mode = "dead"
	ui:showDeath(score, dist, gems, best, seed)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local wantsRetry = input.KeyCode == Enum.KeyCode.R and mode == "dead"
	local wantsPlay = input.KeyCode == Enum.KeyCode.Return and mode == "menu"
	if wantsRetry or wantsPlay then
		requestStart()
	end
end)

--============================== drive ===============================--

local hudCache = ""

RunService.Heartbeat:Connect(function(dt)
	local b = ball
	if mode ~= "running" or not b then
		return
	end

	local steer = Config.Steering
	local intent = if tick() >= controlAt then steerIntent() else 0
	local targetLat = intent * steer.MaxLateralSpeed
	local accel = if intent == 0 then steer.IdleLateralDamping * steer.MaxLateralSpeed else steer.LateralAccel
	lateralVel += math.clamp(targetLat - lateralVel, -accel * dt, accel * dt)

	-- Tier-paced forward speed, eased (DESIGN.md §9)
	local dist = math.max(0, -b.Position.Z)
	local targetFwd = Tiers.speedAt(dist) * throttle()
	fwdSpeed += math.clamp(targetFwd - fwdSpeed, -Config.Speed.Accel * dt, Config.Speed.Accel * dt)

	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, v.Y, -fwdSpeed)
	lastBallPos = b.Position

	-- HUD: attributes arrive from the server; only rebuild on visible change
	local score = player:GetAttribute("RoBallScore") or 0
	local d = player:GetAttribute("RoBallDist") or 0
	local gems = player:GetAttribute("RoBallGems") or 0
	local key = string.format("%d|%d|%d|%d", score, d, gems, fwdSpeed)
	if key ~= hudCache then
		hudCache = key
		ui:setHud(score, d, gems, math.floor(fwdSpeed + 0.5), currentSeed)
	end
end)

RunService.RenderStepped:Connect(function()
	camera.CameraType = Enum.CameraType.Scriptable
	local cam = Config.Camera

	local b = ball
	if b then
		local speedT = math.clamp((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)
		camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT
		local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
		camera.CFrame = CFrame.lookAt(b.Position + cam.Offset, target)
	elseif mode == "dead" then
		-- Camera pulls back from the last known ball position (DESIGN.md §11)
		camera.CFrame =
			CFrame.lookAt(lastBallPos + cam.Offset * 1.6, lastBallPos + Config.Generation.TravelAxis * cam.LookAhead)
	else
		-- Menu vista: slow orbit toward the track start
		local t = tick() * 0.12
		local p = Vector3.new(math.sin(t) * 55, 40, 30 + math.cos(t) * 25)
		camera.CFrame = CFrame.lookAt(p, Vector3.new(0, Config.Generation.StartY - 15, -120))
	end
end)

ui:showMenu(player:GetAttribute("RoBallBest") or 0)
task.spawn(function()
	local rows = fnGetLeaderboard:InvokeServer()
	ui:setLeaderboard(rows)
end)
print("[RoBall3D] P4 client online — menu/HUD/death + steering + chase cam")
