--!strict
-- RoBall3D client entry point — Phase 1: input -> velocity drive + chase cam.
-- We drive the ball directly — the server gives us network ownership, so
-- velocity writes are lag-free (DESIGN.md §4). The ball is found by name in
-- Workspace; Waiting for replication is more reliable than remote args.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.RoBall.Config)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ballName = player.Name .. "_Ball"
local lateralVel = 0
local ball: BasePart? = nil

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
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
	local targetLat = steerIntent() * steer.MaxLateralSpeed
	local accel = if steerIntent() == 0 then steer.IdleLateralDamping * steer.MaxLateralSpeed else steer.LateralAccel
	lateralVel += math.clamp(targetLat - lateralVel, -accel * dt, accel * dt)

	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, v.Y, -Config.Speed.Start * throttle())
end)

RunService.RenderStepped:Connect(function()
	local b = ball
	if not b then
		return
	end

	local cam = Config.Camera
	local forwardSpeed = math.abs(b.AssemblyLinearVelocity.Z)
	local speedT = math.clamp((forwardSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT

	local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
	camera.CFrame = CFrame.lookAt(b.Position + cam.Offset, target)
end)

print("[RoBall3D] P1 client online — input + chase cam ready")
