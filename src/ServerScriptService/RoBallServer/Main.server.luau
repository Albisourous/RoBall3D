--!strict
-- RoBall3D server entry point — Phase 2: seeded generated track per player.
-- Run lifecycle (P2-lite): join -> fresh run on a random seed -> fall = die
-- -> teardown + new run on a new seed. P4 moves start/restart behind the menu
-- and adds entered-seed reuse (DESIGN.md §6-7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local TrackStreamer = require(script.Parent.TrackStreamer)

Players.CharacterAutoLoads = false

-- The world is fully generated; the template baseplate/spawn only get in the
-- way once the track starts descending.
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end
local spawn = workspace:FindFirstChild("SpawnLocation")
if spawn then
	spawn:Destroy()
end

local KILL_DROP = 15 -- studs below deck = dead (DESIGN.md §11)

type Run = {
	laneIndex: number,
	streamer: TrackStreamer.Streamer,
	ball: BasePart?,
}

local runs: { [Player]: Run } = {}
local nextLane = 0

local function randomSeed(): number
	return math.floor(tick() * 1000) % 2147483647 + math.random(1, 1000000)
end

local function spawnBall(player: Player, laneIndex: number, deckY: number): BasePart
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
	ball.Position = Vector3.new(x, deckY + d / 2 + 0.3, 2)
	ball.Parent = workspace
	ball:SetNetworkOwner(player)
	return ball
end

local startRun -- fwd: killRun restarts runs through this

-- Death is instant (DESIGN.md §11): fall below the deck OR touch lethal
-- geometry. Teardown, then a fresh seeded run after a short beat.
local function killRun(player: Player, run: Run)
	local laneIndex = run.laneIndex
	if run.ball then
		run.ball:Destroy()
	end
	run.streamer:destroy()
	runs[player] = nil
	task.delay(1.5, function()
		if player.Parent == Players then
			startRun(player, laneIndex)
		end
	end)
end

startRun = function(player: Player, laneIndex: number)
	local seed = randomSeed()
	local streamer = TrackStreamer.new(laneIndex, seed)
	local run: Run = { laneIndex = laneIndex, streamer = streamer, ball = nil }
	runs[player] = run

	streamer.onFatalTouch = function(hit)
		if run.ball and hit == run.ball then
			killRun(player, run)
		end
	end

	streamer:ensureAhead(0) -- build the full window before the ball drops
	run.ball = spawnBall(player, laneIndex, streamer:yAt(2))
	player:SetAttribute("RoBallSeed", seed)
end

local function onPlayerAdded(player: Player)
	local laneIndex = nextLane
	nextLane += 1
	print("[RoBall3D] onPlayerAdded", player.Name, "lane", laneIndex)
	startRun(player, laneIndex)
	print("[RoBall3D] run started, seed", player:GetAttribute("RoBallSeed"))
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Catch anyone who joined before the connection was made (playtest races).
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local run = runs[player]
	if run then
		if run.ball then
			run.ball:Destroy()
		end
		run.streamer:destroy()
		runs[player] = nil
	end
end)

RunService.Heartbeat:Connect(function()
	for player, run in pairs(runs) do
		local ball = run.ball
		if ball and ball.Parent then
			local z = ball.Position.Z
			run.streamer:ensureAhead(z)
			run.streamer:cleanup(z)

			if ball.Position.Y < run.streamer:yAt(z) - KILL_DROP then
				killRun(player, run)
			end
		end
	end
end)

print("[RoBall3D] P2 server online — seeded track generation + kill plane")
