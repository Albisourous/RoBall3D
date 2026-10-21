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
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Ui = require(script.Parent.Ui)
local Backdrop = require(script.Parent.Backdrop)
local Music = require(script.Parent.MusicController)
local Sfx = require(script.Parent.SfxController)
local AudioMix = require(script.Parent.AudioMix)
local GemFx = require(script.Parent.GemFx)
local DeathFx = require(script.Parent.DeathFx)
local CosmeticFx = require(script.Parent.CosmeticFx)
local PadController = require(script.Parent.PadController)
local OrbController = require(script.Parent.OrbController)
local Ghost = require(script.Parent.GhostController)

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
local evSaveGhost = remotes:WaitForChild("SaveGhost") :: RemoteEvent
local fnGetGhost = remotes:WaitForChild("GetGhost") :: RemoteFunction
local fnGetLeaderboard = remotes:WaitForChild("GetLeaderboard") :: RemoteFunction
local fnEquipItem = remotes:WaitForChild("EquipItem") :: RemoteFunction
local fnBuyItem = remotes:WaitForChild("BuyItem") :: RemoteFunction
local fnBuyPack = remotes:WaitForChild("BuyPack") :: RemoteFunction
local fnBuyGems = remotes:WaitForChild("BuyGems") :: RemoteFunction

local ballName = player.Name .. "_Ball"
local ui = Ui.new()
ui.gateFrac = Config.Power.RechargeGate

local mode: "menu" | "running" | "dead" = "menu"
local ball: BasePart? = nil
local lateralVel = 0
local fwdSpeed = Config.Speed.Start
local currentSeed = 0
local controlAt = 0 -- steering unlocks after the "rolling…" settle
local lastBallPos = Vector3.new(0, Config.Generation.StartY, -30)
local powerCharge = 1 -- 0..1 power meter (DESIGN.md §4)
local powerSpent = false -- emptied latch until RechargeGate refills
local dashDir = 0 -- -1/+1 while a dash burst runs (DESIGN.md §4)
local dashUntil = 0
local lastDashAt = 0
local dashDeniedAt = 0 -- last broke/latched press — Ui flickers the bar dim
local bestDist = 0 -- RoBallBestDist: the PB gate's z; 0 = no marked record
local passedBest = false -- set when this run crosses it (one flash only)
local wasDashing = false
local camPos: Vector3? = nil -- damped camera position; nil = snap on next run frame

--============================ garage ==============================--
-- Shop state lives on player attributes (§18): RoBallEq_<slot> item ids,
-- the RoBallOwned CSV (bundle keys + gem-purchased item ids), and the
-- RoBallBank balance. The panel re-renders on every attribute change, so
-- server-side auto-equip and purchases land visibly.

local function equippedId(slot: string): string?
	local id = player:GetAttribute("RoBallEq_" .. slot)
	return if typeof(id) == "string" then id else nil
end

local function ownedSet(): { [string]: boolean }
	local set = {}
	local csv = player:GetAttribute("RoBallOwned")
	if typeof(csv) == "string" then
		for key in string.gmatch(csv, "[^,]+") do
			set[key] = true
		end
	end
	return set
end

local priceCache: { [string]: number } = {} -- pass prices by pass key
local productPrice: { [string]: number } = {} -- dev product prices by product key

-- Browse state (§18 P2): arrows scroll the WHOLE catalog per slot, not
-- just owned items — the garage is the shop shelf. Owned items equip as
-- you pass them; unowned ones park showing their ◊price, which the name
-- button buys on click.
local browseIdx: { [string]: number } = {}

local function syncBrowse(slot: string)
	local idx = table.find(Cosmetics.Order[slot], equippedId(slot))
	browseIdx[slot] = idx or 1
end

local function browseId(slot: string): string?
	local order = Cosmetics.Order[slot]
	return order[math.clamp(browseIdx[slot] or 1, 1, #order)]
end

for _, slot in ipairs(Cosmetics.Slots) do
	syncBrowse(slot)
end

local function slotRows(): { [string]: { text: string, afford: boolean } }
	local owned = ownedSet()
	local rows = {}
	for _, slot in ipairs(Cosmetics.Slots) do
		local id = browseId(slot)
		local item = Cosmetics.item(id)
		local text, afford = "—", false
		if item then
			-- Unowned + priced shows the ◊price (clickable); owned and
			-- pack-only records show a plain name.
			if not Cosmetics.owns(owned, id :: string) and item.gemPrice then
				text = item.name .. "  ◊" .. tostring(item.gemPrice)
				afford = true
			else
				text = item.name
			end
		end
		rows[slot] = { text = text, afford = afford }
	end
	return rows
end

local function packStates(): { [string]: { label: string, enabled: boolean } }
	local owned = ownedSet()
	local states = {}
	-- Bundle passes + the bank2x perk pass — same lifecycle, one table.
	local keys = { "bank2x" }
	for _, b in ipairs(Cosmetics.Bundles) do
		table.insert(keys, b.id)
	end
	for _, key in ipairs(keys) do
		local passId = Config.Monetization.Passes[key] or 0
		if owned[key] then
			states[key] = { label = "OWNED", enabled = false }
		elseif Config.Monetization.FreeForTesting then
			states[key] = { label = "FREE", enabled = true } -- temp: no paywall yet
		elseif passId == 0 then
			states[key] = { label = "SOON", enabled = false } -- pass not created yet
		else
			states[key] = {
				label = "R$" .. tostring(priceCache[key] or Config.Monetization.Price[key] or "?"),
				enabled = true,
			}
		end
	end
	return states
end

local function gemPackStates(): { [string]: { label: string, enabled: boolean } }
	local states = {}
	for _, key in ipairs(Config.Monetization.ProductOrder) do
		local productId = Config.Monetization.Products[key] or 0
		local gems = Config.Monetization.ProductGems[key] or 0
		if Config.Monetization.FreeForTesting then
			states[key] = { label = string.format("◊%d\nFREE", gems), enabled = true } -- temp: no paywall yet
		elseif productId == 0 then
			states[key] = { label = string.format("◊%d\nSOON", gems), enabled = false }
		else
			local price = productPrice[key] or Config.Monetization.ProductPrice[key] or "?"
			states[key] = { label = string.format("◊%d\nR$%s", gems, tostring(price)), enabled = true }
		end
	end
	return states
end

local function refreshGarage()
	ui:setGarage({
		slots = slotRows(),
		packs = packStates(),
		gemPacks = gemPackStates(),
		bank = player:GetAttribute("RoBallBank") or 0,
	})
end

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
		fwdSpeed = Config.Speed.Start
		powerCharge = 1
		powerSpent = false
		dashDir = 0
		dashUntil = 0
		lastDashAt = 0
		dashDeniedAt = 0
		wasDashing = false
		lastBallPos = ball.Position
		-- The settle starts when the ball EXISTS for the client, not when
		-- the event lands — replication order vs RunStarted isn't promised.
		controlAt = tick() + Config.Steering.SettleSeconds
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

-- TRACK cycler (AUDIO.md §3): item 1 = SEEDED — the run seed picks the
-- song; items 2+ = ActiveTracklist entries. A pick sends a seed in that
-- track's residue class so trackIdFor(seed) lands on it and the gen
-- charts the song the player hears. Explicit seed text / "daily" still
-- wins over the pick — the seed box is the stronger intent.
local trackItems = { "SEEDED" }
for _, id in ipairs(Config.Music.ActiveTracklist) do
	table.insert(trackItems, (id:gsub("_", " "):upper()))
end
local trackPickIdx = 1
ui.onTrackCycle = function(dir)
	trackPickIdx = ((trackPickIdx - 1 + dir) % #trackItems) + 1
	ui:setTrackRow(trackItems[trackPickIdx])
end
ui:setTrackRow(trackItems[trackPickIdx])

local function requestStart()
	local s = ui:seedText()
	if s == "" and trackPickIdx > 1 then
		local n = #Config.Music.ActiveTracklist
		s = tostring(trackPickIdx - 2 + n * math.random(0, 9999))
	end
	evStart:FireServer(s)
end
ui.onPlay = requestStart
ui.onRetry = requestStart

-- Equip arrows: browse the WHOLE slot order, wrap around. Owned items
-- equip as they come into view (server re-validates — this is only a
-- suggestion); unowned ones just display their price until clicked.
ui.onEquipCycle = function(slot, dir)
	local order = Cosmetics.Order[slot]
	local i = browseIdx[slot] or 1
	browseIdx[slot] = ((i - 1 + dir) % #order) + 1
	local id = order[browseIdx[slot]]
	if Cosmetics.owns(ownedSet(), id) and equippedId(slot) ~= id then
		pcall(function()
			fnEquipItem:InvokeServer(id)
		end)
	end
	refreshGarage()
end

-- Click a priced item name: buy it with banked gems (§18 P2). The server
-- owns the answer — success auto-equips and lands via attribute refresh.
ui.onItemSlot = function(slot)
	local id = browseId(slot)
	local item = Cosmetics.item(id)
	if not id or not item or item.gemPrice == nil then
		return
	end
	if Cosmetics.owns(ownedSet(), id) then
		return
	end
	pcall(function()
		fnBuyItem:InvokeServer(id)
	end)
end

ui.onBuy = function(bundleId)
	-- FreeForTesting (§18, temp): the server claims the pass straight into
	-- the ownership set — same equip/save pipeline as a real purchase.
	if Config.Monetization.FreeForTesting then
		pcall(function()
			fnBuyPack:InvokeServer(bundleId)
		end)
		return
	end
	local passId = Config.Monetization.Passes[bundleId] or 0
	if passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end
end

-- Gem packs are dev products (§18 P2): prompt, and the server's
-- ProcessReceipt grants the gems. FreeForTesting skips the prompt.
ui.onGemPack = function(key)
	if Config.Monetization.FreeForTesting then
		pcall(function()
			fnBuyGems:InvokeServer(key)
		end)
		return
	end
	local productId = Config.Monetization.Products[key] or 0
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	end
end

-- Leaderboard rows: fetched on boot and refreshed every time the menu
-- shows — otherwise a score saved this session stays invisible until
-- rejoin. RemoteFunction yields, so it runs off the render thread.
-- `board` is "top" (all-time) or "daily" (today's shared-seed board, §14).
local boardFetchSeq = 0
local function refreshBoard(board: string?)
	-- Only the latest fetch may paint — a slow all-time response must not
	-- land after the player has already flipped to DAILY.
	boardFetchSeq += 1
	local seq = boardFetchSeq
	task.spawn(function()
		-- Unprotected InvokeServer can throw (server error/shutdown) — an
		-- error reads as offline rather than leaving the board on "loading…".
		local ok, rows = pcall(function()
			return fnGetLeaderboard:InvokeServer(board or "top")
		end)
		if seq == boardFetchSeq then
			ui:setLeaderboard(if ok then rows else nil)
		end
	end)
end

-- Tab switch on the board panel: re-fetch under the new board key.
ui.onBoardTab = function(board)
	refreshBoard(board)
end

-- Friends filter (§14): the board rows already carry userId — the client
-- just needs its own friend set, loaded lazily on first toggle and cached
-- for the session (friends' board positions are session-stale anyway).
-- Roblox caps the page walk at ~200 ids; GetFriendsAsync failing or a
-- Studio environment without it degrades to the unavailable state.
local friendIds: { [number]: boolean }? = nil
local friendLoading = false
ui.onFriendsReady = function()
	if friendIds or friendLoading then
		return
	end
	friendLoading = true
	task.spawn(function()
		local ok, pages = pcall(function()
			return Players:GetFriendsAsync(player.UserId)
		end)
		local set: { [number]: boolean } = {}
		if ok and pages then
			local cap = 200
			while cap > 0 do
				for _, f in ipairs(pages:GetCurrentPage()) do
					set[f.Id] = true
					cap -= 1
				end
				if pages.IsFinished then
					break
				end
				local okNext = pcall(function()
					pages:AdvanceToNextPageAsync()
				end)
				if not okNext then
					break
				end
			end
			ui.friendSet = set
		else
			ui.friendsErr = true
		end
		friendLoading = false
		ui:drawBoard()
	end)
end

-- Death screen -> menu: the garage lives on the menu (§18), so this is
-- also how players reach the shop between runs.
ui.onMenu = function()
	mode = "menu"
	CosmeticFx.onMode("menu")
	ui:showMenu(player:GetAttribute("RoBallBest") or 0)
	Music.onMenu()
	refreshGarage()
	refreshBoard(ui.boardMode)
end

-- The saved best loads async after join; the boot-time showMenu reads the
-- attribute before it lands, so push late arrivals onto the menu label.
player:GetAttributeChangedSignal("RoBallBest"):Connect(function()
	if mode == "menu" then
		ui:setBest(player:GetAttribute("RoBallBest") or 0)
	end
end)

-- Daily quests (§14): server pushes "1,0,0,<bankedToday>" CSV on every
-- run end; the menu lines track it live.
local function refreshQuests()
	ui:setQuests(player:GetAttribute("RoBallQuests") or "")
end
player:GetAttributeChangedSignal("RoBallQuests"):Connect(refreshQuests)
refreshQuests()

-- Achievements (§14): RoBallAch = full unlock set -> menu tally;
-- RoBallAchNew = only ids unlocked by the latest eval -> the toast batch.
-- Keeping them separate means a restored profile never re-fires ribbons.
local achById = {}
for _, a in ipairs(Config.Monetization.Achievements) do
	achById[a.id] = a
end
local function refreshAchievements()
	local count = 0
	for _ in string.gmatch(player:GetAttribute("RoBallAch") or "", "[^,]+") do
		count += 1
	end
	ui:setAchievements(count)
end
player:GetAttributeChangedSignal("RoBallAch"):Connect(refreshAchievements)
player:GetAttributeChangedSignal("RoBallAchNew"):Connect(function()
	local names = {}
	local total = 0
	for id in string.gmatch(player:GetAttribute("RoBallAchNew") or "", "[^,]+") do
		local a = achById[id]
		if a then
			table.insert(names, a.name)
			total += a.reward
		end
	end
	if #names > 0 then
		ui:toast(string.format("◈ %s  ·  ◊ +%d", table.concat(names, " + "), total))
	end
end)
refreshAchievements()

-- Gem combo pip: RoBallGems ticks up per pickup; a pickup inside
-- ComboWindow of the last extends the streak — the same window
-- SfxController's pitch ladder uses, so the "xN" matches the chime run.
local combo = 0
local lastPickupAt = 0
local lastGemPts = 0
-- Run-stats card (death screen): the client owns the drive-channel truth —
-- boost/dash are local input state the server never sees. Display-only,
-- never part of the score.
local statMaxFwd = 0
local statBoostDist = 0
local statDashes = 0
local statPrevZ = 0
-- Death-cam (§11): each death bumps the sequence so a pending card lands
-- only if no restart/menu happened mid-orbit.
local deathSeq = 0
local deathT0 = 0
player:GetAttributeChangedSignal("RoBallGems"):Connect(function()
	local n = player:GetAttribute("RoBallGems") or 0
	if n > lastGemPts then
		combo = if tick() - lastPickupAt <= Config.GemSfx.ComboWindow then combo + 1 else 1
		lastPickupAt = tick()
		ui:setCombo(combo)
		local seen = combo
		task.delay(Config.GemSfx.ComboWindow, function()
			if combo == seen and tick() - lastPickupAt >= Config.GemSfx.ComboWindow - 1e-3 then
				combo = 0
				ui:setCombo(0)
			end
		end)
	end
	lastGemPts = n
end)

-- Near-miss ping (§10): the server's count attribute is the signal — each
-- increment flashes CLOSE +N under the score. No reset needed: the count
-- is per-run and the flash is momentary.
player:GetAttributeChangedSignal("RoBallNearMiss"):Connect(function()
	if mode == "running" then
		ui:flashMiss(Config.Score.NearMiss.Points)
	end
end)

evRunStarted.OnClientEvent:Connect(function(seed: number)
	mode = "running"
	currentSeed = seed
	combo = 0
	lastGemPts = 0
	passedBest = false
	statMaxFwd = 0
	statBoostDist = 0
	statDashes = 0
	statPrevZ = 2
	-- The attribute is set server-side just before this event fires, but
	-- replication order isn't promised — read it lazily per frame instead.
	bestDist = 0
	ui:setCombo(0)
	camPos = nil -- snap the damped cam onto the new lane, don't ease from the menu orbit
	CosmeticFx.onMode("running")
	ui:showHud()
	Music.onStart(seed)
	-- PB echo (§14): start recording this run's frames, and fetch the
	-- stored ghost — it replays only when its seed matches this run's.
	-- stop() first clears any echo still alive from a mid-run restart.
	Ghost.stop()
	Ghost.beginRecord()
	task.spawn(function()
		local g = fnGetGhost:InvokeServer()
		if mode == "running" and g and g.s == seed then
			Ghost.attach(g.f)
		end
	end)
end)

evRunEnded.OnClientEvent:Connect(
	function(
		score: number,
		dist: number,
		gems: number,
		best: number,
		seed: number,
		newBest: boolean?,
		banked: number?,
		streak: number?,
		streakBonus: number?,
		questBonus: number?,
		questHits: number?,
		weeklyBonus: number?,
		hzPassed: number?,
		closestCall: number?
	)
		mode = "dead"
		deathSeq += 1
		deathT0 = os.clock()
		combo = 0
		ui:setCombo(0)
		CosmeticFx.onMode("dead")
		DeathFx.burst(lastBallPos)
		-- Ghost echo (§14): this run's frames become the stored ghost only
		-- when the run is the new PB — the server holds a one-shot
		-- credential from that same kill, so the echo can't be forged to
		-- a run that never set a record.
		local ghostCsv = Ghost.framesCsv()
		Ghost.stop()
		if newBest and ghostCsv then
			evSaveGhost:FireServer(seed, ghostCsv, score)
		end
		-- newBest is computed server-side: attribute replication races make a
		-- client-side "score > stored best" comparison unreliable.
		-- The card waits out the death-cam orbit (§11); R mid-orbit skips it
		-- via requestStart — the seq guard drops the stale delayed show.
		local seq = deathSeq
		task.delay(Config.Camera.DeathOrbitSec, function()
			if mode == "dead" and deathSeq == seq then
				ui:showDeath(
					score,
					dist,
					gems,
					best,
					seed,
					newBest,
					banked,
					streak,
					streakBonus,
					questBonus,
					questHits,
					weeklyBonus,
					{
						top = statMaxFwd,
						boost = statBoostDist,
						dashes = statDashes,
						hazards = hzPassed,
						closest = closestCall,
					}
				)
			end
		end)
		Music.onDeath()
	end
)

-- Dash (§4): Q/E spend a flat Cost slice of the power meter for a
-- ~12-stud sidestep. The gold RechargeGate notch is the readiness read:
-- a meter past the marker = all verbs armed (the latch can't outlive
-- it); a denied press just flickers the bar dim.
local function tryDash(dir: number): string
	local now = tick()
	if mode ~= "running" or now < controlAt then
		return "not-running"
	end
	if now < dashUntil or now - lastDashAt < Config.Dash.Cooldown then
		return "cooldown"
	end
	if powerCharge < math.max(Config.Power.RechargeGate, Config.Dash.Cost) then
		dashDeniedAt = now
		Sfx.dashDenied()
		return "denied"
	end
	powerCharge = math.max(0, powerCharge - Config.Dash.Cost)
	statDashes += 1
	dashDir = dir
	dashUntil = now + Config.Dash.Time
	lastDashAt = now
	Sfx.dash(dir)
	return "fired"
end

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
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		tryDash(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		tryDash(1)
	end
end)

--============================== drive ===============================--

local hudCache = ""

RunService.Heartbeat:Connect(function(dt)
	local b = ball
	if mode ~= "running" or not b then
		return
	end

	-- FlipRide (§8.6 stretch, flag-off): inside a RoBallFlipZone box the
	-- ball rides the ceiling ribbon — vY holds +Lift, steering mirrors.
	-- Zones only exist when Features.GravityFlip is on, so the tagged
	-- sweep is a no-op in the default game.
	local inFlip = false
	if Config.Features.GravityFlip then
		local bp = b.Position
		for _, zone in ipairs(CollectionService:GetTagged("RoBallFlipZone")) do
			if zone:IsA("BasePart") then
				local lp = zone.CFrame:PointToObjectSpace(bp)
				local hs = zone.Size / 2
				if math.abs(lp.X) <= hs.X and math.abs(lp.Y) <= hs.Y and math.abs(lp.Z) <= hs.Z then
					inFlip = true
					break
				end
			end
		end
	end

	local steer = Config.Steering
	local intent = if tick() >= controlAt then steerIntent() * (if inFlip then -1 else 1) else 0
	-- Dash (§4): the burst drives the SAME lateral-ease math as steering
	-- — the target pins to dash Speed and the accel is ~13x, so the dart
	-- eases in over ~50ms instead of hard-sliding. Steering input is
	-- ignored for the window; on expiry the velocity clamps back into
	-- steer range so residual drift is normal steering, not a free slide.
	local dashing = tick() < dashUntil
	local targetLat = intent * steer.MaxLateralSpeed
	local accel = if intent == 0 then steer.IdleLateralDamping * steer.MaxLateralSpeed else steer.LateralAccel
	if dashing then
		targetLat = dashDir * (if inFlip then -1 else 1) * Config.Dash.Speed
		accel = Config.Dash.Accel
	end
	lateralVel += math.clamp(targetLat - lateralVel, -accel * dt, accel * dt)
	if wasDashing and not dashing then
		lateralVel = math.clamp(lateralVel, -steer.MaxLateralSpeed, steer.MaxLateralSpeed)
	end
	wasDashing = dashing

	-- Tier-paced forward speed, eased (DESIGN.md §9). Hold W to boost, S to
	-- brake — same power meter, same Mult, opposite direction; it only
	-- refills once released, and an emptied meter latches out past
	-- RechargeGate.
	local dist = math.max(0, -b.Position.Z)
	-- PB gate (§11): crossing the record distance earns one gold flash.
	-- bestDist self-heals on the first frames while the attribute lands.
	if bestDist == 0 then
		bestDist = player:GetAttribute("RoBallBestDist") or 0
	end
	if not passedBest and bestDist > 0 and dist >= bestDist then
		passedBest = true
		ui:flashBest()
	end
	local wantBoost = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local wantBrake = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
	local boosting = wantBoost and not powerSpent
	local braking = wantBrake and not boosting and not powerSpent
	if boosting or braking then
		powerCharge = math.max(0, powerCharge - dt / Config.Power.Capacity)
		if powerCharge == 0 then
			powerSpent = true
			boosting = false
			braking = false
		end
	elseif not wantBoost and not wantBrake then
		powerCharge = math.min(1, powerCharge + Config.Power.RegenPerSec * dt)
		if powerSpent and powerCharge >= Config.Power.RechargeGate then
			powerSpent = false
		end
	end
	local targetFwd = Tiers.speedAt(dist) * (boosting and Config.Power.Mult or 1) / (braking and Config.Power.Mult or 1)
	-- Both directions ease faster so the HUD tempo visibly jumps — the
	-- boost/brake has to FEEL like a kick, not a suggestion.
	local fwdAccel = Config.Speed.Accel * ((boosting or braking) and Config.Power.AccelMult or 1)
	fwdSpeed += math.clamp(targetFwd - fwdSpeed, -fwdAccel * dt, fwdAccel * dt)
	-- Run-stats card: top speed + meters traveled while the boost verb
	-- was actually draining the meter. prevZ tracks the same -Z dist.
	statMaxFwd = math.max(statMaxFwd, fwdSpeed)
	if boosting then
		statBoostDist += math.max(0, statPrevZ - b.Position.Z)
	end
	statPrevZ = b.Position.Z
	-- norm lands before the speedo so Music.bpm() reads this frame's
	-- tempo, not last frame's.
	Music.setSpeedNorm((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start))
	ui:setSpeedo(fwdSpeed, Music.bpm(), powerCharge, boosting, powerSpent, braking, dashing, dashDeniedAt)
	Music.setTier(Tiers.forDistance(dist).index) -- layer mix + sting on tier-ups
	Ghost.tick(dt, b.Position) -- record this run + advance the PB echo

	local v = b.AssemblyLinearVelocity
	-- Inside a flip zone vY is pinned to +Lift so gravity can't pull the
	-- ball off the ceiling; at the zone edge the pin drops and gravity
	-- takes over — the ball falls ClearH back to the deck.
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, if inFlip then Config.Flip.Lift else v.Y, -fwdSpeed)
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

RunService.RenderStepped:Connect(function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	local cam = Config.Camera
	local pulse = Music.sample()
	Backdrop.setPulse(pulse) -- analyzer energy -> sun breathing (AUDIO.md §8)
	ui:setPulse(pulse) -- same energy -> speedo thump / chromatic spread

	local b = ball
	if b then
		local speedT = math.clamp((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)
		camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT
		-- Blur meter: power curve — clear through the 0-100 game, smear
		-- climbs hard into endless mode, capped at MaxBlur.
		local bl = Config.Blur
		local curve = math.clamp((fwdSpeed - bl.StartSpeed) / (bl.CurveTop - bl.StartSpeed), 0, 1) ^ bl.Exponent;
		(speedBlur :: BlurEffect).Size = curve * bl.MaxBlur
		if dof then
			dof.FarIntensity = curve * bl.DofFarMax
		end
		-- Aim at the deck plane LookAhead studs out: the drop = grade*ahead,
		-- so the camera pitches into the slope and shows more track (the
		-- Slope downhill read). Roll leans a few degrees into the steer.
		local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
		target -= Vector3.new(0, Config.Generation.Grade * cam.LookAhead + cam.LookDrop, 0)
		local lean = -math.clamp(lateralVel / Config.Steering.MaxLateralSpeed, -1, 1) * math.rad(cam.LeanMax)
		-- Position eases with an exp damp (alpha = 1 - e^-dt/τ — frame-rate
		-- independent): deck-seam and landing bumps filter out at SmoothTime
		-- while the aim stays locked on the lead point, so dashes read as a
		-- brief elastic trail, never as swim.
		local desired = b.Position + cam.Offset
		camPos = if camPos then camPos + (desired - camPos) * (1 - math.exp(-dt / cam.SmoothTime)) else desired
		camera.CFrame = CFrame.lookAt(camPos :: Vector3, target) * CFrame.Angles(0, 0, lean)
		Backdrop.update(b.Position)
	elseif mode == "dead" then
		-- Death-cam (§11): an ease-out orbit of the kill spot — yaw sweeps
		-- DeathOrbitArc while the radius pulls back toward DeathOrbitPull.
		-- FOV settles back to FovMin so the card lands on a calm frame.
		local k = math.clamp((os.clock() - deathT0) / cam.DeathOrbitSec, 0, 1)
		local ease = 1 - (1 - k) ^ 2
		local yaw = ease * cam.DeathOrbitArc
		local off = cam.Offset * (1 + (cam.DeathOrbitPull - 1) * ease)
		local rx = off.Z * math.sin(yaw)
		local rz = off.Z * math.cos(yaw)
		camera.FieldOfView = cam.FovMin + (camera.FieldOfView - cam.FovMin) * (1 - ease)
		camera.CFrame = CFrame.lookAt(lastBallPos + Vector3.new(rx, off.Y, rz), lastBallPos)
		Backdrop.update(lastBallPos)
	else
		-- Menu vista: slow orbit toward the track start
		local t = tick() * 0.12
		local p = Vector3.new(math.sin(t) * 55, 40, 30 + math.cos(t) * 25)
		camera.CFrame = CFrame.lookAt(p, Vector3.new(0, Config.Generation.StartY - 15, -120))
		Backdrop.update(Vector3.new(0, Config.Generation.StartY, -60))
	end
end)

-- Garage refresh on state changes: equipped ids resync browsing + preview;
-- ownership and bank changes re-render prices and buttons.
player:GetAttributeChangedSignal("RoBallOwned"):Connect(refreshGarage)
player:GetAttributeChangedSignal("RoBallBank"):Connect(refreshGarage)
for _, slot in ipairs(Cosmetics.Slots) do
	player:GetAttributeChangedSignal("RoBallEq_" .. slot):Connect(function()
		syncBrowse(slot)
		refreshGarage()
		CosmeticFx.refresh()
	end)
end

Backdrop.init()
Music.init()
AudioMix.init()
Sfx.init()
GemFx.init()
CosmeticFx.init()
PadController.init(function()
	return ball
end)
OrbController.init(function()
	return ball
end, Config.Features.JumpOrbs == true)
CosmeticFx.onMode("menu")
ui:showMenu(player:GetAttribute("RoBallBest") or 0)
refreshGarage()
refreshBoard()
task.spawn(function()
	-- Real prices beat the Config fallback display (§18): GetProductInfo
	-- returns what the dashboard pass/product actually costs.
	for _, b in ipairs(Cosmetics.Bundles) do
		local passId = Config.Monetization.Passes[b.id] or 0
		if passId > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
			end)
			if ok and info and info.PriceInRobux then
				priceCache[b.id] = info.PriceInRobux
			end
		end
	end
	local perkId = Config.Monetization.Passes.bank2x or 0
	if perkId > 0 then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(perkId, Enum.InfoType.GamePass)
		end)
		if ok and info and info.PriceInRobux then
			priceCache.bank2x = info.PriceInRobux
		end
	end
	for _, key in ipairs(Config.Monetization.ProductOrder) do
		local productId = Config.Monetization.Products[key] or 0
		if productId > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				productPrice[key] = info.PriceInRobux
			end
		end
	end
	refreshGarage()
end)
print("[RoBall3D] P4 client online — menu/HUD/death + steering + chase cam")
