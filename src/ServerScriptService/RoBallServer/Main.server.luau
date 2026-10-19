--!strict
-- RoBall3D server entry point — Phase 1: ball spawn + test track + kill plane.
-- Run generation arrives in Phase 2 (see DESIGN.md §8).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)

Players.CharacterAutoLoads = false

-- Remotes are created at runtime so both sides WaitForChild them.
local remotes = Instance.new("Folder")
remotes.Name = "RoBallRemotes"
local ballAssigned = Instance.new("RemoteEvent")
ballAssigned.Name = "BallAssigned"
ballAssigned.Parent = remotes
remotes.Parent = ReplicatedStorage

-- P1 scaffold: a flat ribbon per player lane so we can tune steering feel
-- before the real generator lands. P2 replaces this.
local TRACK_Y = 50
local TRACK_LENGTH = 600
local KILL_Y = TRACK_Y - 20

local nextLane = 0

local function buildLaneTrack(laneIndex: number)
	local x = laneIndex * Config.Generation.RowSpacing
	local track = Instance.new("Part")
	track.Name = "Lane" .. laneIndex .. "_TestTrack"
	track.Anchored = true
	track.Size = Vector3.new(Config.Generation.BaseWidth, Config.Generation.TrackThickness, TRACK_LENGTH)
	track.Position = Vector3.new(x, TRACK_Y, -TRACK_LENGTH / 2)
	track.Color = Color3.fromRGB(15, 15, 20)
	track.Material = Enum.Material.SmoothPlastic
	track.Parent = workspace
	return track
end

local function spawnBall(player: Player, laneIndex: number)
	local x = laneIndex * Config.Generation.RowSpacing
	local d = Config.Ball.Diameter
	local ball = Instance.new("Part")
	ball.Name = player.Name .. "_Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(d, d, d)
	ball.CustomPhysicalProperties =
		PhysicalProperties.new(Config.Ball.Density, Config.Ball.Friction, Config.Ball.Elasticity, 1, 1)
	ball.Color = Color3.fromRGB(255, 45, 120) -- placeholder until P6 skin pass
	ball.Material = Enum.Material.Neon
	ball.Position = Vector3.new(x, TRACK_Y + Config.Generation.TrackThickness / 2 + d / 2 + 0.5, 0)
	ball.Parent = workspace
	ball:SetNetworkOwner(player)
	return ball
end

local balls: { [Player]: BasePart } = {}

Players.PlayerAdded:Connect(function(player)
	local laneIndex = nextLane
	nextLane += 1
	buildLaneTrack(laneIndex)

	local ball = spawnBall(player, laneIndex)
	balls[player] = ball
	ballAssigned:FireClient(player, ball)
end)

Players.PlayerRemoving:Connect(function(player)
	local ball = balls[player]
	if ball then
		ball:Destroy()
	end
	balls[player] = nil
end)

-- Kill plane + respawn (real death flow lands in P4).
RunService.Heartbeat:Connect(function()
	for player, ball in pairs(balls) do
		if ball.Position.Y < KILL_Y then
			local laneIndex = math.round(ball.Position.X / Config.Generation.RowSpacing)
			balls[player] = nil
			ball:Destroy()
			task.delay(1.5, function()
				if player.Parent == Players then
					local newBall = spawnBall(player, laneIndex)
					balls[player] = newBall
					ballAssigned:FireClient(player, newBall)
				end
			end)
		end
	end
end)

print("[RoBall3D] P1 server online — ball spawn + test track + kill plane")
