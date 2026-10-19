--!strict
-- RoBall3D server entry point — Phase 4: menu-driven run lifecycle.
-- Joins no longer auto-start: the client shows the menu, fires RequestStart
-- (optionally with a seed), and the server owns the run. Death fires RunEnded
-- and waits for the next request — an entered seed is reused on retry
-- (DESIGN.md §6-7); blank seed = fresh random each run.

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

-- Remotes are created here so the tree stays in git (AGENTS.md). Parent the
-- folder last so a client's WaitForChild can't see a half-built set.
local remotes = Instance.new("Folder")
remotes.Name = "RoBallRemotes"
local evRequestStart = Instance.new("RemoteEvent")
evRequestStart.Name = "RequestStart"
evRequestStart.Parent = remotes
local evRunStarted = Instance.new("RemoteEvent")
evRunStarted.Name = "RunStarted"
evRunStarted.Parent = remotes
local evRunEnded = Instance.new("RemoteEvent")
evRunEnded.Name = "RunEnded"
evRunEnded.Parent = remotes
remotes.Parent = ReplicatedStorage

local KILL_DROP = 15 -- studs below deck = dead (DESIGN.md §11)

type Run = {
	laneIndex: number,
	streamer: TrackStreamer.Streamer,
	ball: BasePart?,
	seed: number,
	dist: number, -- studs traveled (-Z), drives score
	gemPts: number, -- gem pickups this run
}

local runs: { [Player]: Run } = {}
local laneOf: { [Player]: number } = {}
local seedPref: { [Player]: string } = {}
local nextLane = 0

local function randomSeed(): number
	return math.floor(tick() * 1000) % 2147483647 + math.random(1, 1000000)
end

-- Stable string hash (djb2) so text seeds map to the same map every run.
local function hashSeed(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function resolveSeed(player: Player): number
	local s = seedPref[player]
	if s and #s > 0 then
		local n = tonumber(s)
		if n then
			return math.floor(math.abs(n)) % 2147483647
		end
		return hashSeed(s)
	end
	return randomSeed()
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

local function writeScore(player: Player, run: Run)
	-- Score = whole meters + gem points (DESIGN.md §10). Attributes drive the
	-- HUD and later feed the leaderboard save (P5).
	local score = math.floor(run.dist) + run.gemPts
	player:SetAttribute("RoBallScore", score)
	player:SetAttribute("RoBallDist", math.floor(run.dist))
	player:SetAttribute("RoBallGems", run.gemPts)
end

-- Death is instant (DESIGN.md §11): fall below the deck OR touch lethal
-- geometry. Seal the score, report to the client, wait for the next request.
local function killRun(player: Player, run: Run)
	local score = math.floor(run.dist) + run.gemPts
	local best = math.max(player:GetAttribute("RoBallBest") or 0, score)
	if run.ball then
		run.ball:Destroy()
	end
	run.streamer:destroy()
	runs[player] = nil
	player:SetAttribute("RoBallBest", best)
	player:SetAttribute("RoBallLastScore", score)
	evRunEnded:FireClient(player, score, math.floor(run.dist), run.gemPts, best, run.seed)
end

local function startRun(player: Player)
	local laneIndex = laneOf[player] or 0
	local seed = resolveSeed(player)
	local streamer = TrackStreamer.new(laneIndex, seed)
	local run: Run = { laneIndex = laneIndex, streamer = streamer, ball = nil, seed = seed, dist = 0, gemPts = 0 }
	runs[player] = run

	streamer.onFatalTouch = function(hit)
		if run.ball and hit == run.ball then
			killRun(player, run)
		end
	end
	streamer.onGem = function(hit, value)
		if run.ball and hit == run.ball then
			run.gemPts += value
			writeScore(player, run)
			return true -- consumed: despawn the gem
		end
		return false
	end

	streamer:ensureAhead(0) -- build the full window before the ball drops
	run.ball = spawnBall(player, laneIndex, streamer:yAt(2))
	player:SetAttribute("RoBallSeed", seed)
	player:SetAttribute("RoBallScore", 0)
	player:SetAttribute("RoBallDist", 0)
	player:SetAttribute("RoBallGems", 0)
	evRunStarted:FireClient(player, seed)
	print("[RoBall3D] run started for", player.Name, "seed", seed)
end

evRequestStart.OnServerEvent:Connect(function(player, seedText)
	if runs[player] then
		return -- already running; ignore double-clicks/key spam
	end
	seedPref[player] = typeof(seedText) == "string" and seedText or ""
	startRun(player)
end)

local function onPlayerAdded(player: Player)
	if not laneOf[player] then
		laneOf[player] = nextLane
		nextLane += 1
	end
	player:SetAttribute("RoBallBest", player:GetAttribute("RoBallBest") or 0)
	print("[RoBall3D] joined", player.Name, "lane", laneOf[player])
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
	laneOf[player] = nil
	seedPref[player] = nil
end)

RunService.Heartbeat:Connect(function()
	for player, run in pairs(runs) do
		local ball = run.ball
		if ball and ball.Parent then
			local z = ball.Position.Z
			run.streamer:ensureAhead(z)
			run.streamer:cleanup(z)

			-- Distance is authoritative server-side: spawn z=2, travel is -Z.
			local d = 2 - z
			if d > run.dist then
				run.dist = d
				writeScore(player, run)
			end

			if ball.Position.Y < run.streamer:yAt(z) - KILL_DROP then
				killRun(player, run)
			end
		end
	end
end)

print("[RoBall3D] P4 server online — menu-driven runs, seeded gen, scoring")
