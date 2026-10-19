--!strict
-- RoBall3D client entry point — Phase 2: input -> velocity drive + chase cam
-- + tier-paced forward speed.
-- We drive the ball directly — the server gives us network ownership, so
-- velocity writes are lag-free (DESIGN.md §4). The ball is found by name in
-- Workspace; waiting for replication is more reliable than remote args.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ballName = player.Name .. "_Ball"
local lateralVel = 0
local fwdSpeed = Config.Speed.Start
local ball: BasePart? = nil

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
		fwdSpeed = Config.Speed.Start
	end
end
for _, c in ipairs(workspace:GetChildren()) do
	bindBall(c)
end
workspace.ChildAdded:Connect(bindBall)

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

RunService.Heartbeat:Connect(function(dt)
	local b = ball
	if not b then
		return
	end

	local steer = Config.Steering
	local intent = steerIntent()
	local targetLat = intent * steer.MaxLateralSpeed
	local accel = if intent == 0 then steer.IdleLateralDamping * steer.MaxLateralSpeed else steer.LateralAccel
	lateralVel += math.clamp(targetLat - lateralVel, -accel * dt, accel * dt)

	-- Tier-paced forward speed, eased (DESIGN.md §9)
	local dist = math.max(0, -b.Position.Z)
	local targetFwd = Tiers.speedAt(dist) * throttle()
	fwdSpeed += math.clamp(targetFwd - fwdSpeed, -Config.Speed.Accel * dt, Config.Speed.Accel * dt)

	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, v.Y, -fwdSpeed)
end)

RunService.RenderStepped:Connect(function()
	local b = ball
	if not b then
		return
	end

	local cam = Config.Camera
	local speedT = math.clamp((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT

	local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
	camera.CFrame = CFrame.lookAt(b.Position + cam.Offset, target)
end)

print("[RoBall3D] P2 client online — steering + tier speed + chase cam")
