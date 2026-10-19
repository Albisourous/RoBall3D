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
local Backdrop = require(script.Parent.Backdrop)
local Music = require(script.Parent.MusicController)
local Sfx = require(script.Parent.SfxController)
local GemFx = require(script.Parent.GemFx)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Lighting = game:GetService("Lighting")

-- Speed-blur meter (DESIGN.md §12): BlurEffect for the screen smear +
-- the place's DepthOfField retuned so only the horizon goes soft, both
-- ramping off fwdSpeed in the render loop. The DoF ships in the place
-- file with a near focus that blurred the whole track — we take it over.
local speedBlur = Lighting:FindFirstChild("SpeedBlur") :: BlurEffect?
if not speedBlur then
	speedBlur = Instance.new("BlurEffect")
	speedBlur.Name = "SpeedBlur"
	speedBlur.Size = 0
	speedBlur.Parent = Lighting
end
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof.FocusDistance = Config.Blur.DofFocusDistance
	dof.InFocusRadius = Config.Blur.DofFocusDistance * 0.6
	dof.NearIntensity = 0
end

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
local boostCharge = 1 -- 0..1 boost meter (DESIGN.md §6)
local boostSpent = false -- emptied latch until RechargeGate refills

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
		fwdSpeed = Config.Speed.Start
		boostCharge = 1
		boostSpent = false
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
	Music.onStart()
end)

evRunEnded.OnClientEvent:Connect(function(score: number, dist: number, gems: number, best: number, seed: number)
	mode = "dead"
	ui:showDeath(score, dist, gems, best, seed)
	Music.onDeath()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	-- R restarts in ANY mode — mid-run it abandons the run and re-rolls
	-- instantly (the Slope rage-restart); Enter starts from the menu.
	local wantsRestart = input.KeyCode == Enum.KeyCode.R
	local wantsPlay = input.KeyCode == Enum.KeyCode.Return and mode == "menu"
	if wantsRestart or wantsPlay then
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

	-- Tier-paced forward speed, eased (DESIGN.md §9). Hold W to boost while
	-- the meter drains; it only refills once released, and an emptied meter
	-- latches out until it recharges past RechargeGate.
	local dist = math.max(0, -b.Position.Z)
	local wantBoost = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local boosting = wantBoost and not boostSpent
	if boosting then
		boostCharge = math.max(0, boostCharge - dt / Config.Boost.Capacity)
		if boostCharge == 0 then
			boostSpent = true
			boosting = false
		end
	elseif not wantBoost then
		boostCharge = math.min(1, boostCharge + Config.Boost.RegenPerSec * dt)
		if boostSpent and boostCharge >= Config.Boost.RechargeGate then
			boostSpent = false
		end
	end
	local targetFwd = Tiers.speedAt(dist) * (boosting and Config.Boost.Mult or 1)
	-- Boosting eases faster so the HUD s/s readout visibly jumps — the
	-- boost has to FEEL like a kick, not a suggestion.
	local fwdAccel = Config.Speed.Accel * (boosting and Config.Boost.AccelMult or 1)
	fwdSpeed += math.clamp(targetFwd - fwdSpeed, -fwdAccel * dt, fwdAccel * dt)
	ui:setBoost(boostCharge, boosting)
	Music.setTier(Tiers.forDistance(dist).index) -- layer mix + sting on tier-ups

	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, v.Y, -fwdSpeed)
	lastBallPos = b.Position
	Music.setSpeedNorm((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start))

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
	Backdrop.setPulse(Music.sample()) -- analyzer energy -> sun breathing (AUDIO.md §8)

	local b = ball
	if b then
		local speedT = math.clamp((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)
		camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT
		-- Blur meter: slow smear that keeps deepening past the old cap —
		-- the gradient ride is visual speed, not a penalty.
		local over = math.max(0, fwdSpeed - Config.Blur.StartSpeed);
		(speedBlur :: BlurEffect).Size = math.min(Config.Blur.MaxBlur, over * Config.Blur.BlurPerSpeed)
		if dof then
			dof.FarIntensity = math.min(Config.Blur.DofFarMax, over * Config.Blur.DofFarPerSpeed)
		end
		-- Aim at the deck plane LookAhead studs out: the drop = grade*ahead,
		-- so the camera pitches into the slope and shows more track (the
		-- Slope downhill read). Roll leans a few degrees into the steer.
		local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
		target -= Vector3.new(0, Config.Generation.Grade * cam.LookAhead + cam.LookDrop, 0)
		local lean = -math.clamp(lateralVel / Config.Steering.MaxLateralSpeed, -1, 1) * math.rad(cam.LeanMax)
		camera.CFrame = CFrame.lookAt(b.Position + cam.Offset, target) * CFrame.Angles(0, 0, lean)
		Backdrop.update(b.Position)
	elseif mode == "dead" then
		-- Camera pulls back from the last known ball position (DESIGN.md §11)
		local target = lastBallPos + Config.Generation.TravelAxis * cam.LookAhead
		target -= Vector3.new(0, Config.Generation.Grade * cam.LookAhead + cam.LookDrop, 0)
		camera.CFrame = CFrame.lookAt(lastBallPos + cam.Offset * 1.6, target)
		Backdrop.update(lastBallPos)
	else
		-- Menu vista: slow orbit toward the track start
		local t = tick() * 0.12
		local p = Vector3.new(math.sin(t) * 55, 40, 30 + math.cos(t) * 25)
		camera.CFrame = CFrame.lookAt(p, Vector3.new(0, Config.Generation.StartY - 15, -120))
		Backdrop.update(Vector3.new(0, Config.Generation.StartY, -60))
	end
end)

Backdrop.init()
Music.init()
Sfx.init()
GemFx.init()
ui:showMenu(player:GetAttribute("RoBallBest") or 0)
task.spawn(function()
	local rows = fnGetLeaderboard:InvokeServer()
	ui:setLeaderboard(rows)
end)
print("[RoBall3D] P4 client online — menu/HUD/death + steering + chase cam")
