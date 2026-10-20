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
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local BallDress = require(ReplicatedStorage.RoBall.BallDress)
local TrackStreamer = require(script.Parent.TrackStreamer)
local SaveService = require(script.Parent.SaveService)
local ShopService = require(script.Parent.ShopService)

Players.CharacterAutoLoads = false

-- Night-sky + post FX (DESIGN.md §12): deep-purple void, restrained neon
-- bloom (only true Neon parts glow — no full-screen smear), magenta haze
-- so the vaporwave city fades into the distance.
local function applyEnvironment()
	Lighting.ClockTime = 0 -- night: dark skybox + stars
	Lighting.GeographicLatitude = 0
	Lighting.Ambient = Color3.fromRGB(30, 18, 42)
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 12, 32)

	-- The place file carries a stale authored post-FX kit (extra Bloom,
	-- Atmosphere, SunRays, ColorCorrection at defaults) that stacks on top of
	-- ours and doubles the glow/haze. Own Lighting outright: destroy every
	-- existing effect of the classes we manage, then create exactly ours.
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("Atmosphere") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") then
			e:Destroy()
		end
	end

	-- Restrained bloom: Threshold above 1 means only emissive Neon pixels
	-- bloom; low intensity/size keeps edges crisp instead of blurry. Named so
	-- Backdrop can bind this exact effect instead of a stale authored one.
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "WorldBloom"
	bloom.Intensity = 0.35
	bloom.Size = 10
	bloom.Threshold = 1.5
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
local fnEquipItem = Instance.new("RemoteFunction")
fnEquipItem.Name = "EquipItem"
fnEquipItem.Parent = remotes
local fnBuyItem = Instance.new("RemoteFunction")
fnBuyItem.Name = "BuyItem"
fnBuyItem.Parent = remotes
remotes.Parent = ReplicatedStorage

local KILL_DROP = 15 -- studs below deck = dead (DESIGN.md §11)

type Run = {
	laneIndex: number,
	streamer: TrackStreamer.Streamer,
	ball: BasePart?,
	seed: number,
	dist: number, -- studs traveled (-Z), drives score
	gemPts: number, -- gem pickups this run
	banked: number, -- gems credited to the bank this run (§18 P2 — never score)
	t0: number, -- os.clock() at start; feeds the plausibility cap
	lastPos: Vector3?, -- previous-frame ball position (stall watchdog)
	stillT: number, -- seconds the ball has been frozen in place
}

local runs: { [Player]: Run } = {}
local laneOf: { [Player]: number } = {}
local seedPref: { [Player]: string } = {}
local bestOf: { [Player]: { score: number, dist: number, seed: number } } = {}
local lbCooldown: { [Player]: number } = {}
local statsOf: { [Player]: { best: IntValue, score: IntValue } } = {}
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
	ball.Material = Enum.Material.SmoothPlastic
	ball.Position = Vector3.new(x, deckY + d / 2 + 0.3, 2)

	-- Vaporwave ball (§18): skin item picks the cage/core colors — the same
	-- BallDress code the client's menu preview uses, so WYSIWYG.
	local eq = ShopService.equipped(player)
	BallDress.dress(ball, Cosmetics.item(eq.skin), Cosmetics.item(eq.trail))

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
	local ls = statsOf[player]
	if ls then
		ls.score.Value = score
	end
end

-- Lite plausibility check (DESIGN.md §14): dist can't exceed the distance
-- reachable by holding W for the whole run under the real eased speed curve
-- (uncapped past the last tier), and gems can't exceed ~cluster cap per chunk.
local function maxPossibleDist(elapsed: number): number
	local d, fwd, t, step = 0, Config.Speed.Start, 0, 0.25
	while t < elapsed do
		local target = Tiers.speedAt(d) * Config.Boost.Mult
		fwd += math.clamp(target - fwd, -Config.Speed.Accel * step, Config.Speed.Accel * step)
		d += fwd * step
		t += step
	end
	return d * 1.15
end

local function plausible(run: Run, score: number): boolean
	local elapsed = math.max(os.clock() - run.t0, 1)
	local maxDist = maxPossibleDist(elapsed)
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
	local oldBest = player:GetAttribute("RoBallBest") or 0
	local best = math.max(oldBest, score)
	if run.ball then
		run.ball:Destroy()
	end
	run.streamer:destroy()
	runs[player] = nil
	ShopService.flush(player) -- bank checkpoint: persist the run's credits (§18)
	player:SetAttribute("RoBallBest", best)
	player:SetAttribute("RoBallLastScore", score)
	local ls = statsOf[player]
	if ls then
		ls.best.Value = best
		ls.score.Value = score
	end
	-- newBest rides the event: attribute replication order vs the remote
	-- isn't guaranteed, so the client can't derive this reliably.
	evRunEnded:FireClient(player, score, dist, run.gemPts, best, run.seed, score > oldBest, run.banked)

	if plausible(run, score) then
		-- Only overwrite the record when this run IS the record — storing
		-- `dist`/`seed` from a later, worse run would misplace the PB
		-- marker and tag the saved best with the wrong seed.
		local prev = bestOf[player]
		local isRecord = not prev or score > (prev.score or 0)
		if isRecord then
			bestOf[player] = { score = score, dist = dist, seed = run.seed }
		end
		task.spawn(function()
			SaveService.saveBest(player.UserId, bestOf[player])
			-- The top board only moves on session records — skipping
			-- non-record deaths halves write traffic for free.
			if isRecord then
				SaveService.submitTop(player.UserId, score, run.seed)
			end
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
		banked = 0,
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
			-- Dual-purpose (§18 P2): the pickup is score AND banked currency —
			-- credited live so a quit mid-run keeps what it earned.
			run.banked += ShopService.awardGems(player, Config.Monetization.BankPerGem)
			return true -- consumed: despawn the gem
		end
		return false
	end

	streamer:ensureAhead(0) -- build the full window before the ball drops

	-- PB ghost (DESIGN.md §11): a translucent "BEST n" gate floats at your
	-- record's end distance — you race your own shadow. Parented to the
	-- lane folder so it dies with the run.
	local pb = bestOf[player]
	if pb and pb.dist >= Config.Score.PbMarkerMinDist then
		local z = -pb.dist
		local gate = Instance.new("Part")
		gate.Name = "PbMarker"
		gate.Anchored = true
		gate.CanCollide = false
		gate.CanQuery = false
		gate.CastShadow = false
		gate.Transparency = 0.45
		gate.Material = Enum.Material.Neon
		gate.Color = Color3.fromRGB(255, 64, 190)
		gate.Size = Vector3.new(math.max(4, Tiers.forDistance(pb.dist).widthMin), 0.4, 0.4)
		gate.CFrame = CFrame.new(laneIndex * Config.Generation.RowSpacing, streamer:yAt(z) + 0.3, z)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 24)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = true
		bb.Parent = gate
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(1, 1)
		tl.Font = Enum.Font.Code
		tl.TextSize = 14
		tl.TextColor3 = Color3.fromRGB(255, 64, 190)
		tl.Text = "BEST " .. tostring(math.floor(pb.score))
		tl.Parent = bb
		gate.Parent = streamer.folder
	end

	run.ball = spawnBall(player, laneIndex, streamer:yAt(2))
	player:SetAttribute("RoBallSeed", seed)
	player:SetAttribute("RoBallScore", 0)
	player:SetAttribute("RoBallDist", 0)
	player:SetAttribute("RoBallGems", 0)
	local ls = statsOf[player]
	if ls then
		ls.score.Value = 0
	end
	evRunStarted:FireClient(player, seed)
	print("[RoBall3D] run started for", player.Name, "seed", seed)
end

evRequestStart.OnServerEvent:Connect(function(player, seedText)
	seedPref[player] = typeof(seedText) == "string" and string.sub(seedText, 1, 64) or ""
	local run = runs[player]
	if run then
		-- Fast restart (R mid-run): tear down without the death flow — no
		-- RunEnded event and no score save, so rage-restarting to dodge a
		-- crash can't bank the run. Banked gems still flush: they credited
		-- live on pickup and are never score (§18).
		if run.ball then
			run.ball:Destroy()
		end
		run.streamer:destroy()
		runs[player] = nil
		ShopService.flush(player)
	end
	startRun(player)
end)

-- Live re-dress (§18): an equip landing while a ball exists — mid-run or
-- the async profile load racing a fast first spawn — repaints it. Rings
-- carry RingGroup tags so retint never guesses child order.
local function retintEquipped(player: Player)
	local run = runs[player]
	if run and run.ball then
		local eq = ShopService.equipped(player)
		BallDress.retint(run.ball, Cosmetics.item(eq.skin), Cosmetics.item(eq.trail))
	end
end

local function onPlayerAdded(player: Player)
	if not laneOf[player] then
		laneOf[player] = nextLane
		nextLane += 1
	end
	player:GetAttributeChangedSignal("RoBallEq_skin"):Connect(function()
		retintEquipped(player)
	end)
	player:GetAttributeChangedSignal("RoBallEq_trail"):Connect(function()
		retintEquipped(player)
	end)
	ShopService.onPlayerAdded(player)
	-- Native playerlist stats: Roblox's built-in leaderboard only reads a
	-- `leaderstats` folder. Attributes stay the source of truth — these two
	-- IntValues just mirror them so the playerlist shows live Score + Best.
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local lsBest = Instance.new("IntValue")
	lsBest.Name = "Best"
	lsBest.Parent = ls
	local lsScore = Instance.new("IntValue")
	lsScore.Name = "Score"
	lsScore.Parent = ls
	ls.Parent = player
	statsOf[player] = { best = lsBest, score = lsScore }
	-- Load persisted best (async — the menu reads the attribute whenever it
	-- lands; P5 store may be unreachable in Studio, which is fine). Merge,
	-- don't replace: a record set before the load lands must survive it.
	task.spawn(function()
		local saved = SaveService.loadBest(player.UserId)
		if saved then
			local cur = bestOf[player]
			if not cur or saved.score > cur.score then
				bestOf[player] = saved
			end
			local best = math.max(saved.score, player:GetAttribute("RoBallBest") or 0)
			player:SetAttribute("RoBallBest", best)
			lsBest.Value = best
		end
	end)
	player:SetAttribute("RoBallBest", player:GetAttribute("RoBallBest") or 0)
	print("[RoBall3D] joined", player.Name, "lane", laneOf[player])
end

fnGetLeaderboard.OnServerInvoke = function(player)
	-- Per-player cooldown: repeat pulls inside the window serve the cached
	-- board (staleOnly) instead of forcing a fresh DataStore fetch.
	local now = os.clock()
	if now - (lbCooldown[player] or -math.huge) < Config.Leaderboard.FetchCooldown then
		return SaveService.getTop(Config.Leaderboard.TopCount, true)
	end
	lbCooldown[player] = now
	return SaveService.getTop(Config.Leaderboard.TopCount)
end

fnEquipItem.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false
	end
	return ShopService.equip(player, itemId)
end

fnBuyItem.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false, "bad arg"
	end
	return ShopService.buyItem(player, itemId)
end

ShopService.init()

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
	lbCooldown[player] = nil
	statsOf[player] = nil
end)

-- Shutdown flush: PlayerRemoving's task.spawn'd saveBest can lose the race
-- on server close — BindToClose yields are awaited (up to the ~30s grace),
-- so pending bests actually land. Dirty banks flush on the same pass.
game:BindToClose(function()
	for player, saved in pairs(bestOf) do
		SaveService.saveBest(player.UserId, saved)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		ShopService.flush(player)
	end
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
