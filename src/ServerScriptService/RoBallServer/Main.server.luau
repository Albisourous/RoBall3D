--!strict
-- RoBall3D server entry point — Phase 4: menu-driven run lifecycle.
-- Joins no longer auto-start: the client shows the menu, fires RequestStart
-- (optionally with a seed), and the server owns the run. Death fires RunEnded
-- and waits for the next request — an entered seed is reused on retry
-- (DESIGN.md §6-7); blank seed = fresh random each run.

local CollectionService = game:GetService("CollectionService")
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
local Daily = require(ReplicatedStorage.RoBall.Daily)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)
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
local fnSetAudio = Instance.new("RemoteFunction")
fnSetAudio.Name = "SetAudio"
fnSetAudio.Parent = remotes
local fnBuyItem = Instance.new("RemoteFunction")
fnBuyItem.Name = "BuyItem"
fnBuyItem.Parent = remotes
local fnBuyPack = Instance.new("RemoteFunction")
fnBuyPack.Name = "BuyPack"
fnBuyPack.Parent = remotes
local fnBuyGems = Instance.new("RemoteFunction")
fnBuyGems.Name = "BuyGems"
fnBuyGems.Parent = remotes
local fnSetHues = Instance.new("RemoteFunction")
fnSetHues.Name = "SetHues"
fnSetHues.Parent = remotes
local evReportFatal = Instance.new("RemoteEvent")
evReportFatal.Name = "ReportFatal"
evReportFatal.Parent = remotes
local evSaveGhost = Instance.new("RemoteEvent")
evSaveGhost.Name = "SaveGhost"
evSaveGhost.Parent = remotes
local fnGetGhost = Instance.new("RemoteFunction")
fnGetGhost.Name = "GetGhost"
fnGetGhost.Parent = remotes
local evCrown = Instance.new("RemoteEvent")
evCrown.Name = "Crown"
evCrown.Parent = remotes
local fnSetDashMode = Instance.new("RemoteFunction")
fnSetDashMode.Name = "SetDashMode"
fnSetDashMode.Parent = remotes
remotes.Parent = ReplicatedStorage

type Run = {
	laneIndex: number,
	streamer: TrackStreamer.Streamer,
	ball: BasePart?,
	seed: number,
	dist: number, -- studs traveled (-Z), drives score
	gemPts: number, -- gem pickups this run
	nmPts: number, -- near-miss bonus points this run (§10)
	nmCursor: number, -- scan cursor into streamer.hazards
	gateCursor: number, -- scan cursor into streamer.gates (§10 hoop bonus)
	hoopThreads: number, -- clean ring threads this run — drives the whoosh attribute
	hzPassed: number, -- lethal planes crossed alive (death-screen stat)
	closest: number, -- tightest crossing gap seen, studs (inf = never close)
	banked: number, -- gems credited to the bank this run (§18 P2 — never score)
	debug: boolean, -- feature-forced track (§7): ineligible for all scoring
	t0: number, -- os.clock() at start; feeds the plausibility cap
	lastFloorDist: number, -- last whole meter written to score attributes
	lastPos: Vector3?, -- previous-frame ball position (stall watchdog)
	stillT: number, -- seconds the ball has been frozen in place
	riderYaw: number, -- capsule rider heading (§3): persists so the yaw gate holds last heading
	riderAcc: number, -- RiderHz accumulator for throttled goal writes
	riderOri: AlignOrientation?, -- cached RiderOri constraint (recursive find once)
}

local runs: { [Player]: Run } = {}
local laneOf: { [Player]: number } = {}
local seedPref: { [Player]: string } = {}
local bestOf: { [Player]: { score: number, dist: number, seed: number } } = {}
-- Session-known daily best (§14): same write-thrift as the all-time board —
-- only a new session record writes. The store's keep-max UpdateAsync stays
-- correct even if a previous session set a higher score.
local dailyBestOf: { [Player]: number } = {}
-- PB ghost (§14): when a clean run sets the session record, it earns a
-- one-shot credential — the client may then submit that run's position
-- frames as the new ghost echo. Consumed on use, never persisted.
local ghostAuth: { [Player]: { seed: number, score: number } } = {}
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

local function resolveSeed(player: Player): (number, string?)
	local s = seedPref[player]
	if s and #s > 0 then
		-- "daily"/"today" → the shared UTC-day seed (DESIGN.md §14): every
		-- player who runs it today gets the identical map.
		if Daily.isKeyword(s) then
			return Daily.seed(), nil
		end
		-- Feature seeds (§7, Config.Debug.Enabled): a feature keyword
		-- ("pressrow", "TERRACES") forces a track of only that chunk type —
		-- the text still hashes to the seed, so the same word replays the
		-- same layout. Forced runs carry run.debug and never submit scores;
		-- with the flag off the keyword is just a normal hashed seed.
		local only = Config.Debug.Enabled and ChunkDefs.matchFeature(s) or nil
		if only then
			return hashSeed(s), only
		end
		local n = tonumber(s)
		if n then
			return math.floor(math.abs(n)) % 2147483647, nil
		end
		return hashSeed(s), nil
	end
	return randomSeed(), nil
end

local function spawnBall(player: Player, laneIndex: number, deckY: number): BasePart
	local x = laneIndex * Config.Generation.RowSpacing
	local d = Config.Ball.Diameter
	local ball = Instance.new("Part")
	ball.Name = player.Name .. "_Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(d, d, d)
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		Config.Ball.Density,
		Config.Ball.Friction,
		Config.Ball.Elasticity,
		1,
		Config.Ball.ElasticityWeight
	)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Position = Vector3.new(x, deckY + d / 2 + 0.3, 2)

	-- Vaporwave ball (§18): skin item picks the cage/core colors — the same
	-- BallDress code the client's menu preview uses, so WYSIWYG.
	local eq = ShopService.equipped(player)
	BallDress.dress(ball, Cosmetics.item(eq.skin), Cosmetics.item(eq.trail), nil, Cosmetics.huesOf(player))

	ball.Parent = workspace
	ball:SetNetworkOwner(player)
	return ball
end

local function writeScore(player: Player, run: Run)
	-- Score = whole meters + gem points (DESIGN.md §10). Attributes drive the
	-- HUD and later feed the leaderboard save (P5).
	local score = math.floor(run.dist) + run.gemPts + run.nmPts
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
		local target = Tiers.speedAt(d) * Config.Power.Mult
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
	-- Near-miss headroom: ~8 lethal planes per 30-stud chunk slice is
	-- already impossible (rows are ReactionTime-spaced), so this stays a
	-- loose ceiling, not a knob cheaters could reach.
	local nearCap = math.ceil(run.dist / 30) * 8 * Config.Score.NearMiss.Points
	return score <= maxDist + math.max(gemCap, 100) + nearCap
end

-- Death is instant (DESIGN.md §11): fall below the deck OR touch lethal
-- geometry. Seal the score, report to the client, wait for the next request.
local function killRun(player: Player, run: Run, cause: string?, causeLoc: string?)
	local score = math.floor(run.dist) + run.gemPts + run.nmPts
	local dist = math.floor(run.dist)
	local oldBest = player:GetAttribute("RoBallBest") or 0
	-- A run only counts when it's real: debug-seed forced tracks (§7,
	-- run.debug) and implausible scores earn nothing — no record, no
	-- board, no quests, no streak. The session best/leaderstats reads stay
	-- honest too: a fake run can't inflate them even transiently.
	local cleanRun = not run.debug and plausible(run, score)
	local best = if cleanRun then math.max(oldBest, score) else oldBest
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
	-- Daily streak counts BEFORE the event so the death screen can show it;
	-- implausible runs don't count the day (a cheaty run earns nothing).
	-- Quests evaluate on every clean run — they're day missions, not tied
	-- to the daily seed.
	local streak, streakBonus = 0, 0
	if cleanRun and run.seed == Daily.seed() then
		streak, streakBonus = ShopService.recordDailyRun(player)
	end
	local questBonus, questHits = 0, 0
	if cleanRun then
		questBonus, questHits = ShopService.onRunEnd(player, dist, score, run.banked + streakBonus, run.seed)
	end
	-- newBest rides the event: attribute replication order vs the remote
	-- isn't guaranteed, so the client can't derive this reliably.
	evRunEnded:FireClient(
		player,
		score,
		dist,
		run.gemPts,
		best,
		run.seed,
		cleanRun and score > oldBest,
		run.banked,
		streak,
		streakBonus,
		questBonus,
		questHits,
		run.hzPassed,
		if run.closest < math.huge then run.closest else nil,
		cause,
		causeLoc
	)

	if cleanRun then
		-- Only overwrite the record when this run IS the record — storing
		-- `dist`/`seed` from a later, worse run would misplace the PB
		-- marker and tag the saved best with the wrong seed.
		local prev = bestOf[player]
		local isRecord = not prev or score > (prev.score or 0)
		if isRecord then
			bestOf[player] = { score = score, dist = dist, seed = run.seed }
			-- Ghost credential (§14): the client may claim it with this
			-- run's recorded frames — the echo always IS the PB run.
			ghostAuth[player] = { seed = run.seed, score = score }
		end
		task.spawn(function()
			SaveService.saveBest(player.UserId, bestOf[player])
			-- The top board only moves on session records — skipping
			-- non-record deaths halves write traffic for free.
			if isRecord then
				SaveService.submitTop(player.UserId, score, run.seed)
				-- All-time rank (§14): the board slot lands a beat after
				-- the death card — the attr listener fills it in late.
				local topRank = SaveService.topRank(player.UserId)
				if topRank then
					player:SetAttribute("RoBallTopRank", topRank)
				end
			end
		end)
		-- Daily board (§14): a run on today's seed competes on today's store.
		-- Session-best thrift mirrors the all-time write policy. (The streak
		-- side already ran above, before RunEnded fired.)
		if run.seed == Daily.seed() and score > (dailyBestOf[player] or 0) then
			dailyBestOf[player] = score
			task.spawn(function()
				SaveService.submitDaily(player.UserId, score)
				-- Daily rank (§14): the board slot lands a beat after the
				-- death card — the attr listener fills it in late.
				local rank = SaveService.dailyRank(player.UserId)
				if rank then
					player:SetAttribute("RoBallDailyRank", rank)
				end
			end)
		end
	elseif not run.debug then
		warn("[RoBall3D] implausible score rejected:", player.Name, score)
	end
end

-- Forward-declared: startRun's pre-build task calls into launch once the
-- ahead window stands (defined below).
local launch: (player: Player, run: Run, streamer: TrackStreamer.Streamer, seed: number) -> ()

local function startRun(player: Player)
	local laneIndex = laneOf[player] or 0
	local seed, onlyFeature = resolveSeed(player)
	local streamer = TrackStreamer.new(laneIndex, seed)
	-- Feature-forced test runs (§7, Config.Debug.Enabled): see
	-- ChunkDefs.matchFeature.
	streamer.gen.onlyType = onlyFeature
	if onlyFeature then
		print(string.format("[RoBall3D] debug-seed: every chunk is %s for %s", onlyFeature, player.Name))
	end
	-- Pickup restyle (§18): the equipped world item may restyle gems —
	-- world_sky's "ball" style renders every pickup as a capsule orb.
	local eq = ShopService.equipped(player)
	local worldItem = Cosmetics.item(eq.world)
	streamer.gemStyle = worldItem and worldItem.gemStyle
	-- FLOOR slot (APEBALL.md §5): the equipped floor item restyles deck
	-- slabs/rails — a mid-run swap stamps future chunks only.
	streamer.deckItem = Cosmetics.item(eq.floor)
	-- Gem silhouette (§8.4): the equipped skin pins one pickup shape for
	-- the run — worth still telegraphs on tier scale + tint. Read per
	-- chunk build like deckItem, so the shape is never re-rolled mid-run.
	streamer.gemShape = (Cosmetics.item(eq.skin) or {}).gemShape
	local run: Run = {
		laneIndex = laneIndex,
		streamer = streamer,
		ball = nil,
		seed = seed,
		dist = 0,
		gemPts = 0,
		nmPts = 0,
		nmCursor = 1,
		gateCursor = 1,
		hoopThreads = 0,
		hzPassed = 0,
		closest = math.huge,
		banked = 0,
		debug = onlyFeature ~= nil,
		t0 = os.clock(),
		lastFloorDist = 0,
		lastPos = nil,
		stillT = 0,
		riderYaw = math.pi, -- facing -Z/travel at spawn, matching SMB's getInitApeYaw
		riderAcc = 0,
		riderOri = nil,
	}
	runs[player] = run
	-- A stale daily rank can't leak onto a non-daily run's death card.
	player:SetAttribute("RoBallDailyRank", 0)
	player:SetAttribute("RoBallTopRank", 0)

	streamer.onGem = function(hit, value, shape, tint)
		if run.ball and hit == run.ball then
			-- Stamped BEFORE the RoBallGems bump so the client's pop ghost
			-- reads the collected gem's shape + tint in the same attr flush.
			player:SetAttribute("RoBallGemShape", shape)
			player:SetAttribute("RoBallGemColor", tint)
			run.gemPts += value
			writeScore(player, run)
			-- Dual-purpose (§18 P2): the pickup is score AND banked currency —
			-- credited live so a quit mid-run keeps what it earned.
			run.banked += ShopService.awardGems(player, Config.Monetization.BankPerGem)
			return true -- consumed: despawn the gem
		end
		return false
	end

	-- Build the ahead window one chunk per frame instead of bursting the
	-- whole 400 studs inside startRun (PERFORMANCE.md §2): ~10 chunks of
	-- Instance.news in one call was a run-start spike that stacks when
	-- several players press PLAY together. The 0.8s client settle covers
	-- the catch-up; markers and the ball wait for the full window so
	-- their yAt reads stay honest. A restart/leave mid-build orphans the
	-- task — it sees runs[player] has moved on and exits.
	task.spawn(function()
		while streamer.gen.state.zEnd > -Config.Generation.AheadDistance do
			if runs[player] ~= run then
				return
			end
			streamer:ensureAhead(0)
			task.wait()
		end
		if runs[player] ~= run then
			return
		end
		launch(player, run, streamer, seed)
	end)
end

-- The run goes live once the ahead window stands: distance gates, then
-- the ball + RunStarted. Extracted from startRun so the pre-build can
-- spread across frames (see the task above).
function launch(player: Player, run: Run, streamer: TrackStreamer.Streamer, seed: number)
	local laneIndex = run.laneIndex
	-- PB ghost (DESIGN.md §11): a translucent "BEST n" gate floats at your
	-- record's end distance — you race your own shadow. Parented to the
	-- lane folder so it dies with the run. The label only renders in the
	-- last approach window (MaxDistance) so it isn't a constant screen
	-- occupant; the client flashes NEW BEST at the crossing instead.
	local pb = bestOf[player]
	local pbDist = if pb and pb.dist >= Config.Score.PbMarkerMinDist then pb.dist else 0
	player:SetAttribute("RoBallBestDist", pbDist)
	if pb and pbDist > 0 then
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
		bb.MaxDistance = Config.Score.PbMarkerViewDist
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

	-- Last-fall marker (DESIGN.md §11): the bloodstain — a dim gate where
	-- the most recent run on this seed ended, from the RoBallHistory
	-- attr (newest first). Skipped beside the PB gate — BEST already
	-- marks that spot; same min-distance rule keeps stub deaths unmarked.
	local lastD, lastS = 0, 0
	local hist = player:GetAttribute("RoBallHistory")
	if typeof(hist) == "string" then
		for entry in string.gmatch(hist, "[^;]+") do
			local s, d, z = string.match(entry, "([^,]+),([^,]+),([^,]+)")
			if tonumber(z) == seed then
				lastD, lastS = tonumber(d) or 0, tonumber(s) or 0
				break
			end
		end
	end
	if lastD >= Config.Score.PbMarkerMinDist and math.abs(lastD - pbDist) >= 8 then
		local z = -lastD
		local gate = Instance.new("Part")
		gate.Name = "LastMarker"
		gate.Anchored = true
		gate.CanCollide = false
		gate.CanQuery = false
		gate.CastShadow = false
		gate.Transparency = 0.6
		gate.Material = Enum.Material.Neon
		gate.Color = Color3.fromRGB(150, 45, 62)
		gate.Size = Vector3.new(math.max(4, Tiers.forDistance(lastD).widthMin), 0.4, 0.4)
		gate.CFrame = CFrame.new(laneIndex * Config.Generation.RowSpacing, streamer:yAt(z) + 0.3, z)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 24)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
		bb.MaxDistance = Config.Score.PbMarkerViewDist
		bb.Parent = gate
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(1, 1)
		tl.Font = Enum.Font.Code
		tl.TextSize = 14
		tl.TextColor3 = Color3.fromRGB(150, 45, 62)
		tl.Text = "LAST " .. tostring(math.floor(lastS))
		tl.Parent = bb
		gate.Parent = streamer.folder
	end

	run.ball = spawnBall(player, laneIndex, streamer:yAt(2))
	player:SetAttribute("RoBallSeed", seed)
	player:SetAttribute("RoBallScore", 0)
	player:SetAttribute("RoBallDist", 0)
	player:SetAttribute("RoBallGems", 0)
	player:SetAttribute("RoBallHoop", 0)
	local ls = statsOf[player]
	if ls then
		ls.score.Value = 0
	end
	evRunStarted:FireClient(player, seed)
	print("[RoBall3D] run started for", player.Name, "seed", seed)
end

-- Lethal contact is client-adjudicated (§11): the ball's network owner is
-- the client, so server-side Touched judged an interpolated ghost of the
-- ball — dodges that visibly cleared a block still registered hits (the
-- "random death" report). The client reports the contact it simulated;
-- falls, stalls and external destruction stay server-checked in the
-- heartbeat below — they're unambiguous on the server's view.
evReportFatal.OnServerEvent:Connect(function(player, killerPart: Instance?)
	local run = runs[player]
	if run then
		-- Death cause (§11): the reported part carries ChunkType from the
		-- spec that built it — the card names the mechanic that killed
		-- the run. Untrusted arg: only a real lethal tag earns a label.
		local cause: string? = nil
		if
			typeof(killerPart) == "Instance"
			and killerPart:IsA("BasePart")
			and CollectionService:HasTag(killerPart, "RoBallLethal")
		then
			cause = killerPart:GetAttribute("ChunkType") :: string?
		end
		killRun(player, run, cause)
	end
end)

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
		BallDress.retint(run.ball, Cosmetics.item(eq.skin), Cosmetics.item(eq.trail), Cosmetics.huesOf(player))
	end
end

local joinedOnce: { [Player]: boolean } = {} -- PlayerAdded + catch-up loop can both fire

local function onPlayerAdded(player: Player)
	if joinedOnce[player] then
		return
	end
	joinedOnce[player] = true
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
	-- COLOR LAB (§18): a hue write mid-run repaints the live ball too.
	for _, attr in pairs(Cosmetics.HueAttr) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			retintEquipped(player)
		end)
	end
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

fnGetLeaderboard.OnServerInvoke = function(player, board)
	-- board: "top" (all-time) or "daily" (today's shared seed). Per-player
	-- cooldown: repeat pulls inside the window serve the cached board
	-- (staleOnly) instead of forcing a fresh DataStore fetch.
	local now = os.clock()
	local cool = now - (lbCooldown[player] or -math.huge) < Config.Leaderboard.FetchCooldown
	if not cool then
		lbCooldown[player] = now
	end
	if board == "daily" then
		return SaveService.getDailyTop(Config.Leaderboard.TopCount, cool)
	end
	return SaveService.getTop(Config.Leaderboard.TopCount, cool)
end

fnEquipItem.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false
	end
	return ShopService.equip(player, itemId)
end

-- Mixer writes (AUDIO.md §7): pure preference state — validate the
-- channel + range, then store/mirror like an equip.
fnSetAudio.OnServerInvoke = function(player, ch, v)
	if typeof(ch) ~= "string" or typeof(v) ~= "number" or v ~= v then
		return false
	end
	return ShopService.setAudio(player, ch, v)
end

-- Dash style (§4): "keys"|"tap" — a control pref, mirrored +
-- saved like a mixer gain.
fnSetDashMode.OnServerInvoke = function(player, m)
	if typeof(m) ~= "string" then
		return false
	end
	return ShopService.setDashMode(player, m)
end

fnBuyItem.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false, "bad arg"
	end
	return ShopService.buyItem(player, itemId)
end

fnBuyPack.OnServerInvoke = function(player, key)
	if typeof(key) ~= "string" then
		return false, "bad arg"
	end
	return ShopService.claimPass(player, key)
end

fnBuyGems.OnServerInvoke = function(player, key)
	if typeof(key) ~= "string" then
		return false, "bad arg"
	end
	return ShopService.claimGemPack(player, key)
end

-- COLOR LAB (§18): hue slider releases — the server gates ownership and
-- clamps the band; the client only suggests.
fnSetHues.OnServerInvoke = function(player, h)
	if typeof(h) ~= "table" then
		return false
	end
	return ShopService.setHues(player, h)
end

-- PB ghost (§14): the client claims the one-shot credential its record
-- run earned by submitting that run's position frames. Validation: the
-- seed/score must match the credential, the csv must parse as
-- "t,x,y,z;..." with sane bounds — frames are cosmetic (self-scoped
-- echo) but an unbounded payload still isn't allowed through.
local function ghostCsvOk(csv: string): boolean
	local g = Config.Ghost
	if #csv == 0 or #csv > g.MaxSamples * 32 then
		return false
	end
	local n = 0
	local lastZ = math.huge -- frames run toward -Z: each z must be < last
	for frame in string.gmatch(csv, "[^;]+") do
		local t, x, y, z = frame:match("^([%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
		local tn, xn, yn, zn = tonumber(t), tonumber(x), tonumber(y), tonumber(z)
		if not tn or not xn or not yn or not zn then
			return false
		end
		if math.abs(xn) > 100 or zn > lastZ or tn > 86400 then
			return false
		end
		lastZ = zn
		n += 1
	end
	return n >= g.MinFrames and n <= g.MaxSamples
end

evSaveGhost.OnServerEvent:Connect(function(player, seed, csv, score)
	local auth = ghostAuth[player]
	if not auth or typeof(seed) ~= "number" or typeof(score) ~= "number" or typeof(csv) ~= "string" then
		return
	end
	ghostAuth[player] = nil -- one-shot: consume it either way
	if seed ~= auth.seed or score ~= auth.score or not ghostCsvOk(csv) then
		return
	end
	task.spawn(function()
		SaveService.saveGhost(player.UserId, seed, csv)
		-- Champion shot (§14): the run already earned the PB credential, so
		-- if it also tops this seed's stored record its frames become the
		-- rival echo everyone on the seed races. A before/after podium
		-- read tells us whether the shot dethroned somebody — toast the
		-- takeover so the crown story closes the loop.
		local before = SaveService.loadPodium(seed)
		local oldChamp = before and before.c
		SaveService.crownChampion(seed, player.UserId, player.Name, score, csv)
		local after = SaveService.loadPodium(seed)
		local newChamp = after and after.c
		if newChamp and newChamp.u == player.UserId and (oldChamp == nil or oldChamp.u ~= player.UserId) then
			evCrown:FireClient(player, oldChamp and oldChamp.n or "")
		end
	end)
end)

-- The echoes for the run about to start: own stored ghost (only when its
-- seed matches) plus the seed champion's replay — the rival line. The
-- champion is omitted when it's the requester's own record so nobody
-- races a second copy of their best.
fnGetGhost.OnServerInvoke = function(player, seed)
	local own = SaveService.loadGhost(player.UserId)
	local out: { s: number?, f: string?, c: SaveService.Champ?, r: SaveService.Champ? } = {}
	if own then
		out.s = own.s
		out.f = own.f
	end
	if typeof(seed) == "number" then
		local podium = SaveService.loadPodium(seed)
		local champ = podium and podium.c
		local runner = podium and podium.r
		if champ and champ.u ~= player.UserId then
			out.c = champ
		end
		-- Crowd ghost (§14): the seed's silver seat — the client only
		-- replays it on the daily seed, where a field exists to race.
		if runner and runner.u ~= player.UserId and (champ == nil or runner.u ~= champ.u) then
			out.r = runner
		end
	end
	return out
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
	dailyBestOf[player] = nil
	ghostAuth[player] = nil
	joinedOnce[player] = nil
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
			killRun(player, run, nil, run.streamer:chunkTypeAt(ball.Position.Z))
		elseif ball then
			local z = ball.Position.Z
			run.streamer:ensureAhead(z)
			run.streamer:cleanup(z)

			-- Distance is authoritative server-side: spawn z=2, travel is -Z.
			-- writeScore only when the whole meter ticks over — the
			-- attributes (and leaderstats) only change per meter anyway,
			-- so per-frame writes were pure replication churn
			-- (PERFORMANCE.md §2). Gem/near-miss bumps write directly.
			local d = 2 - z
			if d > run.dist then
				run.dist = d
				local m = math.floor(d)
				if m ~= run.lastFloorDist then
					run.lastFloorDist = m
					writeScore(player, run)
				end
			end

			-- Capsule rider goal (APEBALL.md §3 — port of the SMB decomp's
			-- updateApeOrientation, WebMonkeyBall physics.ts ~571): the
			-- Inhabitant rig's "RiderOri" AlignOrientation gets a fresh
			-- world-space goal each RiderHz tick — yaw blends onto the
			-- horizontal velocity heading through the Lo→Hi speed gate (the
			-- last heading holds when nearly stopped), then a RiderTumble
			-- share of the ball's angular delta gives the shudder without
			-- slaving the rider to the roll. The constraint's soft
			-- Responsiveness plays the decomp's incremental uprighting —
			-- no manual upright nudge needed, and 30 Hz goals are
			-- indistinguishable under that damping while halving the
			-- replicated write rate. The AlignOrientation is cached on
			-- first find (was a recursive search per frame).
			local inhab = ball:FindFirstChild("Inhabitant")
			if inhab then
				local ori = run.riderOri
				if not (ori and ori.Parent) then
					local found = inhab:FindFirstChild("RiderOri", true)
					ori = if found and found:IsA("AlignOrientation") then found else nil
					run.riderOri = ori
				end
				if ori then
					run.riderAcc += dt
					if run.riderAcc >= 1 / Config.Art.RiderHz then
						local rdt = run.riderAcc
						run.riderAcc = 0
						local v = ball.AssemblyLinearVelocity
						local hs = math.sqrt(v.X * v.X + v.Z * v.Z)
						if hs > Config.Art.RiderYawVelLo then
							local target = math.atan2(v.X, v.Z) -- +Z face (muzzle/eyes) onto vel dir
							local blend = math.clamp(
								(hs - Config.Art.RiderYawVelLo) / (Config.Art.RiderYawVelHi - Config.Art.RiderYawVelLo),
								0,
								1
							)
							-- Shortest-arc blend toward the heading — the
							-- decomp's s16-wrapped delta.
							local dYaw = (target - run.riderYaw + math.pi) % (2 * math.pi) - math.pi
							run.riderYaw += dYaw * blend
						end
						local w = ball.AssemblyAngularVelocity
						local wn = w.Magnitude
						local goal = CFrame.Angles(0, run.riderYaw, 0)
						if wn > 1e-3 then
							goal = CFrame.fromAxisAngle(w.Unit, wn * rdt * Config.Art.RiderTumble) * goal
						end
						ori.CFrame = goal
					end
				end
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
					killRun(player, run, "STALL", run.streamer:chunkTypeAt(pos.Z))
					continue
				end
			else
				run.stillT = 0
			end

			-- Near-miss trickle (§10): each lethal plane the ball crosses
			-- without dying pays a small bonus if the pass hugged the face
			-- — or sat inside a rotor's marked sweep disc. Evaluated once
			-- per plane from the interpolated crossing x; a crossing that
			-- also killed can't double-award (killRun already sealed the
			-- run and removed it from `runs`).
			local nm = Config.Score.NearMiss
			local ballR = Config.Ball.Diameter / 2
			while true do
				local h = run.streamer.hazards[run.nmCursor]
				if not h or pos.Z >= h.z then
					break
				end
				run.nmCursor += 1
				run.hzPassed += 1
				local px = run.lastPos and run.lastPos.X or pos.X
				local pz = run.lastPos and run.lastPos.Z or pos.Z
				local t = math.clamp((pz - h.z) / math.max(pz - pos.Z, 0.001), 0, 1)
				local bx = px + (pos.X - px) * t
				local close
				if h.spin then
					-- Disc-edge distance; negative = inside the sweep zone.
					local gap = math.abs(bx - h.cx) - h.halfW
					close = gap <= nm.Range
					run.closest = math.min(run.closest, gap)
				elseif h.press then
					-- Press thread (§10): the ball crossed inside the
					-- plate's span — the guaranteed lane sits outside it,
					-- so this only counts the timed under-route — while
					-- the plate was dropped into it. A crossing that killed
					-- never reaches here; a free pass (plate raised) pays nil.
					local part = h.part
					local drop = 0
					if part then
						drop = (h.baseY - part.Position.Y) / math.max(h.amp, 0.001)
					end
					close = math.abs(bx - h.cx) <= h.halfW and drop >= Config.Press.ThreadMinDrop
					if close then
						run.nmPts += Config.Press.ThreadBonus
						writeScore(player, run)
						close = false -- paid as a thread; skips the graze block
					end
				else
					local gap = math.abs(bx - h.cx) - h.halfW - ballR
					close = gap <= nm.Range
					run.closest = math.min(run.closest, gap)
				end
				if close then
					run.nmPts += nm.Points
					writeScore(player, run)
				end
			end

			-- RampGap hoops (§10): crossing a hoop's plane inside the ring
			-- opening pays flat gems — the same cursor walk + interpolated
			-- crossing as hazards; outside the circle or over the top pays nil.
			local gt = Config.Hoop
			while true do
				local g = run.streamer.gates[run.gateCursor]
				if not g or pos.Z >= g.z then
					break
				end
				run.gateCursor += 1
				local px = run.lastPos and run.lastPos.X or pos.X
				local py = run.lastPos and run.lastPos.Y or pos.Y
				local pz = run.lastPos and run.lastPos.Z or pos.Z
				local t = math.clamp((pz - g.z) / math.max(pz - pos.Z, 0.001), 0, 1)
				local dx = px + (pos.X - px) * t - g.cx
				local dy = py + (pos.Y - py) * t - g.cy
				if dx * dx + dy * dy <= (g.r + ballR) * (g.r + ballR) then
					run.gemPts += gt.Score
					-- Same dual-purpose path as a pickup: score + banked
					-- currency (§18 P2), and the RoBallGems bump gives the
					-- client its pickup flourish for free. RoBallHoop fires
					-- the thread whoosh (§10).
					run.banked += ShopService.awardGems(player, gt.Bank)
					run.hoopThreads += 1
					player:SetAttribute("RoBallHoop", run.hoopThreads)
					writeScore(player, run)
				end
			end

			run.lastPos = pos

			if ball.Position.Y < run.streamer:yAt(z) - Config.Death.KillDrop then
				killRun(player, run, "VOID", run.streamer:chunkTypeAt(z))
			end
		end
	end
end)

print("[RoBall3D] P4 server online — menu-driven runs, seeded gen, scoring")
