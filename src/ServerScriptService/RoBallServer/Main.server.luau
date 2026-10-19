--!strict
-- RoBall3D server entry point — Phase 4: menu-driven run lifecycle.
-- Joins no longer auto-start: the client shows the menu, fires RequestStart
-- (optionally with a seed), and the server owns the run. Death fires RunEnded
-- and waits for the next request — an entered seed is reused on retry
-- (DESIGN.md §6-7); blank seed = fresh random each run.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Palette = require(ReplicatedStorage.RoBall.Palette)
local TrackStreamer = require(script.Parent.TrackStreamer)
local SaveService = require(script.Parent.SaveService)

Players.CharacterAutoLoads = false

-- Night-sky + post FX (DESIGN.md §12): deep-purple void, restrained neon
-- bloom (only true Neon parts glow — no full-screen smear), magenta haze
-- so the vaporwave city fades into the distance.
local function applyEnvironment()
	Lighting.ClockTime = 0 -- night: dark skybox + stars
	Lighting.GeographicLatitude = 0
	Lighting.Ambient = Color3.fromRGB(30, 18, 42)
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 12, 32)

	-- Restrained bloom: Threshold above 1 means only emissive Neon pixels
	-- bloom; low intensity/size keeps edges crisp instead of blurry.
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 16
	bloom.Threshold = 1.3
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.08
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 238, 252)
	cc.Parent = Lighting

	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.25 -- light haze: distant towers dim, not vanish
	atmo.Offset = 0 -- keep the haze floor at y=0 so descending track stays clear
	atmo.Color = Color3.fromRGB(48, 22, 68)
	atmo.Decay = Color3.fromRGB(26, 10, 44)
	atmo.Glare = 0
	atmo.Haze = 1.5
	atmo.Parent = Lighting
end
applyEnvironment()

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
local fnGetLeaderboard = Instance.new("RemoteFunction")
fnGetLeaderboard.Name = "GetLeaderboard"
fnGetLeaderboard.Parent = remotes
remotes.Parent = ReplicatedStorage

local KILL_DROP = 15 -- studs below deck = dead (DESIGN.md §11)

type Run = {
	laneIndex: number,
	streamer: TrackStreamer.Streamer,
	ball: BasePart?,
	seed: number,
	dist: number, -- studs traveled (-Z), drives score
	gemPts: number, -- gem pickups this run
	t0: number, -- os.clock() at start; feeds the plausibility cap
	lastPos: Vector3?, -- previous-frame ball position (stall watchdog)
	stillT: number, -- seconds the ball has been frozen in place
}

local runs: { [Player]: Run } = {}
local laneOf: { [Player]: number } = {}
local seedPref: { [Player]: string } = {}
local bestOf: { [Player]: { score: number, dist: number, seed: number } } = {}
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
	-- Slope look: near-black core + engine-rendered wireframe sphere. The
	-- adornment does the neon; the part underneath just needs to be dark.
	ball.Color = Color3.fromRGB(4, 8, 6)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Position = Vector3.new(x, deckY + d / 2 + 0.3, 2)

	-- Vaporwave ball: five engine-rendered wireframe rings (3 cyan axial +
	-- 2 magenta diagonal). They ride the adornee's CFrame, so the cage
	-- visibly rolls with the ball.
	for _, rot in ipairs({
		{ rot = CFrame.Angles(0, 0, 0), color = Config.Art.RingA },
		{ rot = CFrame.Angles(math.rad(90), 0, 0), color = Config.Art.RingA },
		{ rot = CFrame.Angles(0, 0, math.rad(90)), color = Config.Art.RingA },
		{ rot = CFrame.Angles(math.rad(45), 0, math.rad(90)), color = Config.Art.RingB },
		{ rot = CFrame.Angles(math.rad(-45), 0, math.rad(90)), color = Config.Art.RingB },
	}) do
		local ring = Instance.new("CylinderHandleAdornment")
		ring.Adornee = ball
		ring.CFrame = rot.rot
		ring.Radius = d / 2 + 0.08
		ring.Height = 0.14
		ring.Color3 = rot.color
		ring.Parent = ball
	end

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, d * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -d * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = Config.Art.TrailLifetime
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Palette.neonAt(0))
	trail.Transparency = NumberSequence.new(0.5, 1)
	trail.WidthScale = NumberSequence.new(0.35, 0.05)
	trail.Parent = ball

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

-- Lite plausibility check (DESIGN.md §14): dist can't exceed max achievable
-- speed * elapsed * margin, and gems can't exceed ~cluster cap per chunk.
local function plausible(run: Run, score: number): boolean
	local elapsed = math.max(os.clock() - run.t0, 1)
	local maxDist = Config.Speed.Max * Config.Speed.ThrottleUp * elapsed * 1.15
	local gemCap = math.ceil(run.dist / 30)
		* Config.Gems.ClustersPerChunkMax
		* Config.Gems.ClusterSizes[1]
		* Config.Gems.ValueGapArc
	return score <= maxDist + math.max(gemCap, 100)
end

-- Death is instant (DESIGN.md §11): fall below the deck OR touch lethal
-- geometry. Seal the score, report to the client, wait for the next request.
local function killRun(player: Player, run: Run)
	local score = math.floor(run.dist) + run.gemPts
	local dist = math.floor(run.dist)
	local best = math.max(player:GetAttribute("RoBallBest") or 0, score)
	if run.ball then
		run.ball:Destroy()
	end
	run.streamer:destroy()
	runs[player] = nil
	player:SetAttribute("RoBallBest", best)
	player:SetAttribute("RoBallLastScore", score)
	evRunEnded:FireClient(player, score, dist, run.gemPts, best, run.seed)

	if plausible(run, score) then
		bestOf[player] = { score = best, dist = dist, seed = run.seed }
		task.spawn(function()
			SaveService.saveBest(player.UserId, bestOf[player])
			SaveService.submitTop(player.UserId, score, run.seed)
		end)
	else
		warn("[RoBall3D] implausible score rejected:", player.Name, score)
	end
end

local function startRun(player: Player)
	local laneIndex = laneOf[player] or 0
	local seed = resolveSeed(player)
	local streamer = TrackStreamer.new(laneIndex, seed)
	local run: Run = {
		laneIndex = laneIndex,
		streamer = streamer,
		ball = nil,
		seed = seed,
		dist = 0,
		gemPts = 0,
		t0 = os.clock(),
		lastPos = nil,
		stillT = 0,
	}
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
	seedPref[player] = typeof(seedText) == "string" and seedText or ""
	local run = runs[player]
	if run then
		-- Fast restart (R mid-run): tear down without the death flow — no
		-- RunEnded event and no score save, so rage-restarting to dodge a
		-- crash can't bank the run.
		if run.ball then
			run.ball:Destroy()
		end
		run.streamer:destroy()
		runs[player] = nil
	end
	startRun(player)
end)

local function onPlayerAdded(player: Player)
	if not laneOf[player] then
		laneOf[player] = nextLane
		nextLane += 1
	end
	-- Load persisted best (async — the menu reads the attribute whenever it
	-- lands; P5 store may be unreachable in Studio, which is fine).
	task.spawn(function()
		local saved = SaveService.loadBest(player.UserId)
		if saved then
			bestOf[player] = saved
			player:SetAttribute("RoBallBest", math.max(saved.score, player:GetAttribute("RoBallBest") or 0))
		end
	end)
	player:SetAttribute("RoBallBest", player:GetAttribute("RoBallBest") or 0)
	print("[RoBall3D] joined", player.Name, "lane", laneOf[player])
end

fnGetLeaderboard.OnServerInvoke = function(_player)
	return SaveService.getTop(Config.Leaderboard.TopCount)
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
	local saved = bestOf[player]
	if saved then
		task.spawn(function()
			SaveService.saveBest(player.UserId, saved)
		end)
	end
	laneOf[player] = nil
	seedPref[player] = nil
	bestOf[player] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	for player, run in pairs(runs) do
		local ball = run.ball
		if ball and not ball.Parent then
			-- Ball destroyed by something outside killRun (kill floor,
			-- cleanup race, admin) — seal the run so the HUD can't hang
			-- on a ghost run forever.
			killRun(player, run)
		elseif ball then
			local z = ball.Position.Z
			run.streamer:ensureAhead(z)
			run.streamer:cleanup(z)

			-- Distance is authoritative server-side: spawn z=2, travel is -Z.
			local d = 2 - z
			if d > run.dist then
				run.dist = d
				writeScore(player, run)
			end

			-- Stall watchdog: the client force-sets ball velocity every frame,
			-- so a live ball can never sit still — a frozen position means it
			-- wedged into geometry and would otherwise hang the run forever
			-- (the "score stops counting" freeze). dt clamp keeps an editor
			-- hitch from counting against a healthy run.
			local pos = ball.Position
			if run.lastPos and (pos - run.lastPos).Magnitude < 0.05 then
				run.stillT += math.min(dt, 0.25)
				if run.stillT > Config.Death.StallSeconds and run.dist > Config.Death.StallGraceDist then
					killRun(player, run)
					continue
				end
			else
				run.stillT = 0
			end
			run.lastPos = pos

			if ball.Position.Y < run.streamer:yAt(z) - KILL_DROP then
				killRun(player, run)
			end
		end
	end
end)

print("[RoBall3D] P4 server online — menu-driven runs, seeded gen, scoring")
