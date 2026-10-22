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
local Daily = require(ReplicatedStorage.RoBall.Daily)
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
local MoverController = require(script.Parent.MoverController)
local FatalController = require(script.Parent.FatalController)
local Ghost = require(script.Parent.GhostController)
local ScreenFilter = require(script.Parent.ScreenFilter)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable -- set once (PERFORMANCE.md §1), not re-asserted per frame
local Lighting = game:GetService("Lighting")

-- No gameplay blur/DoF (§12): the place file ships a DepthOfField at a
-- near focus that softens the whole track — destroy it on boot. Any
-- stale SpeedBlur a previous version created gets removed the same way.
for _, name in ipairs({ "SpeedBlur" }) do
	local fx = Lighting:FindFirstChild(name)
	if fx then
		fx:Destroy()
	end
end
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof:Destroy()
end

local remotes = ReplicatedStorage:WaitForChild("RoBallRemotes")
local evStart = remotes:WaitForChild("RequestStart") :: RemoteEvent
local evRunStarted = remotes:WaitForChild("RunStarted") :: RemoteEvent
local evRunEnded = remotes:WaitForChild("RunEnded") :: RemoteEvent
local evReportFatal = remotes:WaitForChild("ReportFatal") :: RemoteEvent
local evSaveGhost = remotes:WaitForChild("SaveGhost") :: RemoteEvent
local fnGetGhost = remotes:WaitForChild("GetGhost") :: RemoteFunction
local evCrown = remotes:WaitForChild("Crown") :: RemoteEvent
local fnGetLeaderboard = remotes:WaitForChild("GetLeaderboard") :: RemoteFunction
local fnEquipItem = remotes:WaitForChild("EquipItem") :: RemoteFunction
local fnBuyItem = remotes:WaitForChild("BuyItem") :: RemoteFunction
local fnBuyPack = remotes:WaitForChild("BuyPack") :: RemoteFunction
local fnBuyGems = remotes:WaitForChild("BuyGems") :: RemoteFunction
local fnSetHues = remotes:WaitForChild("SetHues") :: RemoteFunction
local fnSetDashMode = remotes:WaitForChild("SetDashMode") :: RemoteFunction

local ballName = player.Name .. "_Ball"
local ui = Ui.new()
ui.gateFrac = Config.Power.RechargeGate

local mode: "menu" | "running" | "dead" = "menu"
local ball: BasePart? = nil
local lateralVel = 0
local fwdSpeed = Config.Speed.Start
local bankRollRad = 0 -- grounded deck's bank angle (rad) — horizon lean + pull
local surfNormal = Vector3.yAxis -- eased ground normal — slope tracking
local bankLeanCur = 0 -- eased bank lean actually applied to the camera
local currentSeed: number? = nil
local controlAt = 0 -- steering unlocks after the "rolling…" settle
local lastBallPos = Vector3.new(0, Config.Generation.StartY, -30)
local powerCharge = 1 -- 0..1 power meter (DESIGN.md §4)
local powerSpent = false -- emptied latch until RechargeGate refills
local dashDir = 0 -- -1/+1 while a dash burst runs (DESIGN.md §4)
local dashUntil = 0
local lastDashAt = 0
-- "tap" dash style (§4): last press time per steer direction — a second
-- tap inside Dash.TapWindow dashes instead of just steering.
local lastTapAt = { [-1] = 0, [1] = 0 }
local dashBuffered: { dir: number, at: number }? = nil -- press during burst/cooldown arms a fire-on-unlock dash
local dashDeniedAt = 0 -- last broke/latched press — Ui flickers the bar dim
local bestDist = 0 -- RoBallBestDist: the PB gate's z; 0 = no marked record
local passedBest = false -- set when this run crosses it (one flash only)
local wasDashing = false
local stuckT = 0 -- sustained wedge time (§11 unstick hop)
local unstickUntil = 0 -- hop impulse window
local unstickAfter = 0 -- refractory before another hop may fire
local camPos: Vector3? = nil -- damped camera position; nil = snap on next run frame
local edgeParams = RaycastParams.new()
edgeParams.FilterType = Enum.RaycastFilterType.Include
-- Persistent filter table (PERFORMANCE.md §1): FilterDescendantsInstances
-- takes the table by reference, so reassigning a fresh { edgeLane } every
-- frame was a pure allocation — only re-seats when the lane actually
-- changes (bindBall, once per run).
local edgeFilter: { Instance } = {}
local EDGE_DOWN = Vector3.new(0, -1, 0)
local lanesFolder = workspace:FindFirstChild("RoBallLanes")
local edgeLane: Instance? = nil -- this run's lane folder, set in bindBall
local dangerDz: number? = nil -- nearest corridor threat ahead, set by the radar scan
local nextPingAt = 0 -- sonar cadence clock; 0 re-arms on zone entry
local threatCache: string? = nil -- threat label currently on the radar

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

local function slotRows(): {
	[string]: { text: string, afford: boolean, owned: boolean, equipped: boolean, color: Color3? },
}
	local owned = ownedSet()
	local rows = {}
	for _, slot in ipairs(Cosmetics.Slots) do
		local id = browseId(slot)
		local item = Cosmetics.item(id)
		local text, afford, own = "—", false, false
		local color: Color3? = nil
		if item then
			own = Cosmetics.owns(owned, id :: string)
			-- Unowned + priced shows the ◊price (clickable); owned and
			-- pack-only records show a plain name.
			if not own and item.gemPrice then
				text = item.name .. "  ◊" .. tostring(item.gemPrice)
				afford = true
			else
				text = item.name
			end
			-- Row chip wears the item's own swatch — pack contents resolve
			-- the same precedence. String colors ("rainbow"/"customC"/
			-- "palette") stay chipless; the preview sells those.
			local c = item.color or item.ringA or item.colorA or item.deck
			if typeof(c) == "Color3" then
				color = c
			end
		end
		rows[slot] = {
			text = text,
			afford = afford,
			owned = own,
			equipped = id ~= nil and id == equippedId(slot),
			color = color,
		}
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
		-- Seasonal slot (§18): outside the yearly window the pack shows a
		-- countdown instead of a price — the server refuses the buy too.
		local offSeason = false
		if key == Config.Monetization.Seasonal.Bundle and not owned[key] then
			local live, days = Daily.seasonalStatus()
			offSeason = not live
			if offSeason then
				states[key] = { label = string.format("IN %dD", days), enabled = false }
			end
		end
		if not offSeason then
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

-- Preview push (§18): the garage's ViewportFrame diorama dresses the
-- BROWSED items — cycling a slot previews unowned merch before the buy,
-- which is the conversion lever. An open PACK overrides the browse set
-- entirely: tapping a pack's header dresses the whole diorama in that
-- bundle's 7-slot look (world, sun, skin, trail, fx, filter) — the set
-- sells itself as a set. Filter rides along as a Gui overlay.
local packPreviewId: string? = nil
local function previewPush()
	local items: { [string]: any } = {}
	if packPreviewId then
		for _, b in ipairs(Cosmetics.Bundles) do
			if b.id == packPreviewId then
				for _, iid in ipairs(b.items) do
					local it = Cosmetics.item(iid)
					if it then
						items[it.slot] = it
					end
				end
				break
			end
		end
	else
		for _, slot in ipairs(Cosmetics.Slots) do
			items[slot] = Cosmetics.item(browseId(slot))
		end
	end
	CosmeticFx.preview(items)
	ui:setPreviewFilter(items.filter)
end

-- Diorama pushes collapse to at most one rebuild per frame (PERFORMANCE):
-- preview() is a full ~200-part scene rebuild and attribute bursts — the
-- profile landing its ~12 attr pushes, an equip-bundle write, hue saves —
-- fire refreshGarage once per attr. Boot was rebuilding the diorama a
-- dozen times in the first seconds; one deferred pass instead. While the
-- menu's hidden (mid-run) pushes skip entirely — ui.onMenu's refresh
-- rebuilds once on reopen.
local previewGen = 0
local function queuePreview()
	previewGen += 1
	local gen = previewGen
	-- Trailing 0.12s debounce: attribute pushes replicate over a few
	-- frames, so each new write re-arms the timer and a whole burst —
	-- the profile landing its ~12 attrs, an equip-bundle write — lands
	-- exactly one rebuild. Browsing/equips still feel instant.
	task.delay(0.12, function()
		if gen == previewGen and ui.menu.Visible then
			previewPush()
		end
	end)
end

local function refreshGarage()
	local owned = ownedSet()
	ui:setGarage({
		slots = slotRows(),
		packs = packStates(),
		gemPacks = gemPackStates(),
		bank = player:GetAttribute("RoBallBank") or 0,
		-- COLOR LAB (§18): owning ANY lab item unlocks the sliders; hues
		-- mirror the RoBallHue* attributes the server pushes.
		lab = {
			visible = Cosmetics.labOwned(owned),
			hues = {
				a = player:GetAttribute(Cosmetics.HueAttr.a) :: number?,
				b = player:GetAttribute(Cosmetics.HueAttr.b) :: number?,
				c = player:GetAttribute(Cosmetics.HueAttr.c) :: number?,
			},
		},
	})
	queuePreview()
end

local function bindBall(b: Instance)
	if b.Name == ballName and b:IsA("BasePart") then
		ball = b :: BasePart
		lateralVel = 0
		fwdSpeed = Config.Speed.Start
		bankRollRad = 0
		surfNormal = Vector3.yAxis
		bankLeanCur = 0
		powerCharge = 1
		powerSpent = false
		dashDir = 0
		dashUntil = 0
		lastDashAt = 0
		lastTapAt[-1] = 0
		lastTapAt[1] = 0
		dashBuffered = nil
		dashDeniedAt = 0
		wasDashing = false
		stuckT = 0
		unstickUntil = 0
		unstickAfter = 0
		lastBallPos = ball.Position
		-- The settle starts when the ball EXISTS for the client, not when
		-- the event lands — replication order vs RunStarted isn't promised.
		controlAt = tick() + Config.Steering.SettleSeconds
		-- Edge probes only count the ball's own lane as ground (§12).
		edgeLane = lanesFolder
			and lanesFolder:FindFirstChild("Lane" .. math.round(ball.Position.X / Config.Generation.RowSpacing))
		edgeFilter[1] = edgeLane :: Instance
		edgeParams.FilterDescendantsInstances = edgeFilter
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

-- TRACK cycler (AUDIO.md §3): item 1 = RANDOM — the run seed picks the
-- song; items 2+ = ActiveTracklist entries. A pick sends a seed in that
-- track's residue class so trackIdFor(seed) lands on it and the gen
-- charts the song the player hears. Explicit seed text / "daily" still
-- wins over the pick — the seed box is the stronger intent.
local trackItems = { "RANDOM" }
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
	-- Empty box = "daily": the seed row's placeholder is the default —
	-- no mode swap (§6). Any typed text goes through as the seed.
	local s = ui:seedText()
	if s == "" then
		s = "daily"
	end
	evStart:FireServer(s)
end
ui.onPlay = requestStart
ui.onRetry = requestStart

-- Equip arrows: browse the WHOLE slot order, wrap around. Owned items
-- equip as they come into view (server re-validates — this is only a
-- suggestion); unowned ones just display their price until clicked.
-- Pack accordion notify (§18): an open pack's contents take over the
-- preview diorama; closing hands it back to the browse set. The locked-
-- item funnel lands here too — focusPack opens the row, the set renders.
ui.onPackOpen = function(id)
	packPreviewId = id
	queuePreview()
end

ui.onEquipCycle = function(slot, dir)
	packPreviewId = nil -- browsing a slot reclaims the preview
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

-- RANDOM chip (§18): slot-machines the whole browse set — two throwaway
-- rolls then the settle, so the preview reads as a spin, not a pop. A
-- roll never re-lands on the current pick; the commit roll equips owned
-- picks through the same server path as cycling, unowned ones stay
-- window-shopping.
ui.onRandomize = function()
	packPreviewId = nil
	local owned = ownedSet()
	local function roll(commit: boolean)
		for _, slot in ipairs(Cosmetics.Slots) do
			local order = Cosmetics.Order[slot]
			if #order > 1 then
				local i = browseIdx[slot] or 1
				local r = math.random(#order - 1)
				if r >= i then
					r += 1
				end
				browseIdx[slot] = r
				local id = order[r]
				if commit and Cosmetics.owns(owned, id) and equippedId(slot) ~= id then
					pcall(function()
						fnEquipItem:InvokeServer(id)
					end)
				end
			end
		end
		refreshGarage()
	end
	roll(false)
	task.delay(0.09, function()
		roll(false)
	end)
	task.delay(0.18, function()
		roll(true)
	end)
end

-- Dash style (§4): the menu toggle cycles Config.Dash.Modes; the server
-- mirrors RoBallDashMode back and the attribute drives the input map.
local function dashMode(): string
	local m = player:GetAttribute("RoBallDashMode")
	return if typeof(m) == "string" and table.find(Config.Dash.Modes, m) then m else Config.Dash.Modes[1]
end
ui.onDashMode = function()
	local modes = Config.Dash.Modes
	local i = table.find(modes, dashMode()) or 1
	pcall(function()
		fnSetDashMode:InvokeServer(modes[(i % #modes) + 1])
	end)
end
local function syncDashModeUi()
	ui:setDashMode(dashMode())
end
player:GetAttributeChangedSignal("RoBallDashMode"):Connect(syncDashModeUi)
syncDashModeUi()

-- Click a locked item name (§18): a bundled item jumps to its PACK —
-- the bundle pitch + contents accordion is the conversion surface, and
-- the open pack still offers the single's ◊price à-la-carte. Unbundled
-- priced items keep the direct gem buy; the server owns the answer.
ui.onItemSlot = function(slot)
	local id = browseId(slot)
	local item = Cosmetics.item(id)
	if not id or not item or Cosmetics.owns(ownedSet(), id) then
		return
	end
	local bundleId = Cosmetics.bundleOf(id)
	if bundleId then
		ui:focusPack(bundleId)
		return
	end
	if item.gemPrice == nil then
		return
	end
	pcall(function()
		fnBuyItem:InvokeServer(id)
	end)
end

-- "Buy just this" inside an open pack's contents list — the à-la-carte
-- gem path for a single, same server-side validation as the name click.
ui.onBuyItem = function(itemId)
	local item = Cosmetics.item(itemId)
	if not item or item.gemPrice == nil or Cosmetics.owns(ownedSet(), itemId) then
		return
	end
	pcall(function()
		fnBuyItem:InvokeServer(itemId)
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

-- COLOR LAB (§18): a slider release posts the three hue channels; the
-- server gates ownership + clamps the band, attributes echo back and
-- re-render the lab + preview + live ball.
ui.onHues = function(h)
	pcall(function()
		fnSetHues:InvokeServer(h)
	end)
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

-- Recent runs (§14): server pushes "s,d,z;s,d,z" after every clean run
-- end and once the profile lands; the board strip renders the newest
-- five and a tap prefills the seed box for that map.
local function refreshHistory()
	local rows = {}
	for entry in string.gmatch(player:GetAttribute("RoBallHistory") or "", "[^;]+") do
		local s, d, z = string.match(entry, "(%d+),(%d+),(%d+)")
		if s then
			table.insert(rows, { s = tonumber(s), d = tonumber(d), z = tonumber(z) })
		end
	end
	ui:setHistory(rows)
end
player:GetAttributeChangedSignal("RoBallHistory"):Connect(refreshHistory)
refreshHistory()
ui.onHistoryPick = function(seed)
	ui:setSeedText(tostring(seed))
end

-- Daily rank (§14): the server publishes RoBallDailyRank a beat after
-- the death card — the listener slots it into the card that's already up.
player:GetAttributeChangedSignal("RoBallDailyRank"):Connect(function()
	ui:setDailyRank(player:GetAttribute("RoBallDailyRank") :: number?)
end)
-- All-time rank (§14): same late-arriving attr after a record submitTop.
player:GetAttributeChangedSignal("RoBallTopRank"):Connect(function()
	ui:setTopRank(player:GetAttribute("RoBallTopRank") :: number?)
end)

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
local statGroundT = 0 -- seconds with the lane probe finding contact
local statAirT = 0 -- airborne share shows on the death card (§11)
local statDashes = 0
local statPrevZ = 0
-- Pace delta (§12): last whole-meter delta shown; nil when no ghost
-- echoes (different seed / no PB yet) so the HUD line stays hidden.
local paceCache: number? = nil
-- Rival pace (§14): same deal vs the champion echo; name rides the line.
local rivalPaceCache: number? = nil
local overtakePb: boolean? = nil -- armed after trailing the PB echo (§14)
local overtakeRival: boolean? = nil -- same vs the champion echo
local rivalName: string? = nil
-- Hazard radar (§12): scan clock for the look-ahead strip. `radarScan`
-- is the bar list handed to Ui and `radarPool` recycles its row tables —
-- both persist so the ~16 Hz scan allocates nothing (PERFORMANCE.md §1).
local radarT = 0
local radarScan: { { dx: number, dz: number, w: number } } = {}
local radarPool: { { dx: number, dz: number, w: number } } = {}
-- Death-cam (§11): each death bumps the sequence so a pending card lands
-- only if no restart/menu happened mid-orbit.
local deathSeq = 0
local deathT0 = 0
player:GetAttributeChangedSignal("RoBallGems"):Connect(function()
	local n = player:GetAttribute("RoBallGems") or 0
	if n > lastGemPts then
		-- Gem income (§4/§10): each pickup refunds meter by its point
		-- value — a risky line is a recharge, not just score.
		powerCharge = math.min(1, powerCharge + (n - lastGemPts) * Config.Power.GemPerPoint)
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

evRunStarted.OnClientEvent:Connect(function(seed: number)
	mode = "running"
	currentSeed = seed
	-- Blank box stays blank: empty means "daily" — writing the resolved
	-- number back would freeze it to a stale day. A typed seed already
	-- persists in the box, so R restarts the same map either way.
	combo = 0
	lastGemPts = 0
	passedBest = false
	statMaxFwd = 0
	statBoostDist = 0
	statGroundT = 0
	statAirT = 0
	statDashes = 0
	statPrevZ = 2
	paceCache = nil :: number? -- pace line re-renders on whole-meter change
	ui:setPace(nil)
	rivalPaceCache = nil :: number?
	overtakePb = nil :: boolean?
	overtakeRival = nil :: boolean?
	rivalName = nil :: string?
	ui:setRivalPace(nil, nil)
	-- Live mission tracker (§14): snapshot the bank so the bank quest can
	-- add this run's pickups to the stored today-tally.
	ui:missionArm(player:GetAttribute("RoBallBank") or 0)
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
		local g = fnGetGhost:InvokeServer(seed)
		if mode ~= "running" or not g then
			return
		end
		if g.s == seed then
			Ghost.attach(g.f)
		end
		-- Champion ghost (§14): the seed's record holder replays as a
		-- labeled gold echo — racing the top line, not just your own.
		local champ = g.c
		if champ and champ.f and Ghost.attachRival(champ.f, champ.n) then
			rivalName = champ.n
		end
		-- Crowd ghost (§14): on the daily seed the silver seat replays as
		-- a labeled silver echo — you're racing a field, not just a champ.
		local runner = g.r
		if runner and runner.f and seed == Daily.seed() then
			Ghost.attachCrowd(runner.f, runner.n)
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
		hzPassed: number?,
		closestCall: number?,
		cause: string?,
		causeLoc: string?
	)
		mode = "dead"
		deathSeq += 1
		deathT0 = os.clock()
		combo = 0
		ui:setCombo(0)
		ui:setEdgeWarn(false, false)
		ui:setDanger(0)
		dangerDz = nil
		nextPingAt = 0
		threatCache = nil :: string?
		ui:setThreat("")
		ui:setRadarGhosts(nil, nil)
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
			if mode ~= "dead" or deathSeq ~= seq then
				return
			end
			ui:showDeath(score, dist, gems, best, seed, newBest, banked, streak, streakBonus, questBonus, questHits, {
				top = statMaxFwd,
				boost = statBoostDist,
				dashes = statDashes,
				hazards = hzPassed,
				closest = closestCall,
				cause = cause,
				causeLoc = causeLoc,
				air = statAirT / math.max(statAirT + statGroundT, 0.01),
				pbDelta = paceCache,
				rivalDelta = rivalPaceCache,
				rivalName = rivalName,
			})
		end)
		Music.onDeath()
	end
)

-- Crown toast (§14): the server fires this when a PB upload dethrones
-- the seed champion — the gold echo you were racing now wears your
-- name. Empty name = the seed had no prior champion.
evCrown.OnClientEvent:Connect(function(name: string)
	if name ~= "" then
		ui:toast(string.format("♛ CROWN TAKEN from %s", name))
	else
		ui:toast("♛ SEED CROWN CLAIMED")
	end
end)

-- Dash (§4): Q/E spend a flat Cost slice of the power meter for a
-- ~8-stud sidestep. The gold RechargeGate notch is the readiness read:
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

-- Buffering (§4): a press that lands mid-burst or inside Cooldown would
-- otherwise die silently — arm it instead, and the drive loop fires it
-- the moment the window is legal. Back-to-back pairs chain.
local function queueDash(dir: number)
	if tryDash(dir) == "cooldown" then
		dashBuffered = { dir = dir, at = tick() }
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	-- R restarts in ANY mode — mid-run it abandons the run and re-rolls
	-- instantly (the Slope rage-restart). It starts on the seed box's
	-- pick — "daily" by default, a typed seed, or a rolled random that's
	-- been mirrored back into the box — so a reload keeps the same map
	-- unless the menu says otherwise. Enter starts from the menu.
	if input.KeyCode == Enum.KeyCode.R or (input.KeyCode == Enum.KeyCode.Return and mode == "menu") then
		requestStart()
		return
	end
	-- Dash input map (§4): "keys" fires Q/E; "tap" fires on a second
	-- press of the same steer key inside TapWindow.
	local dm = dashMode()
	if dm == "keys" and input.KeyCode == Enum.KeyCode.Q then
		queueDash(-1)
	elseif dm == "keys" and input.KeyCode == Enum.KeyCode.E then
		queueDash(1)
	elseif dm == "tap" then
		local dir = if input.KeyCode == Enum.KeyCode.A then -1 elseif input.KeyCode == Enum.KeyCode.D then 1 else 0
		if dir ~= 0 then
			local now = tick()
			if now - lastTapAt[dir] <= Config.Dash.TapWindow then
				lastTapAt[dir] = 0
				queueDash(dir)
			else
				lastTapAt[dir] = now
			end
		end
	end
end)

--============================== drive ===============================--

-- HUD fields compared numerically (PERFORMANCE.md §1): the change key
-- was a string.format every heartbeat — four cached numbers instead.
local hudS, hudD, hudG, hudV, hudB = -1, -1, -1, -1, -1

RunService.Heartbeat:Connect(function(dt)
	local b = ball
	if mode ~= "running" or not b then
		return
	end
	-- One clock read per frame (PERFORMANCE.md §1): controlAt, the dash
	-- window, the danger ping and unstick timers all key off the same now.
	local now = tick()

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
	-- Bank pull (§4): a rolled deck drags the ball toward its low edge —
	-- the lane probe's surface normal carries the bank (normal.X =
	-- -sin(rollDeg); a +roll deck dips -X), so the pull is proportional
	-- to Normal.X — always toward the downhill rail. It rides the same
	-- velocity-ease as steering: idle drifts downhill, counter-steer
	-- still wins but pays the pull out of MaxLateralSpeed. Airborne reads
	-- no surface — pull stays zero.
	local bp = b.Position
	-- Uncapped-tail guard (§9): past ~1k studs/s the ball can out-step the
	-- solver through the 1-stud deck — last frame's center was above the
	-- surface, this frame's is below it. Sweep the traveled segment
	-- against the lane; a crossed floor face re-seats the ball on top
	-- (the approach cap then re-grounds vY). Falls through real gaps hit
	-- nothing and stay free.
	local sweep = bp - lastBallPos
	if sweep.Magnitude > 0.01 then
		local hit = workspace:Raycast(lastBallPos, sweep, edgeParams)
		if hit and hit.Normal:Dot(Vector3.yAxis) > 0.5 then
			b.CFrame = CFrame.new(hit.Position + hit.Normal * (Config.Ball.Diameter / 2))
			bp = b.Position
		end
	end
	local drop = workspace:Raycast(bp, EDGE_DOWN * Config.Landing.MaxDrop, edgeParams)
	local grounded = drop ~= nil
		and bp.Y - (drop :: RaycastResult).Position.Y <= Config.Ball.Diameter / 2 + Config.Landing.ContactPad
	-- Eased surface normal for everything that reads the deck: raw probe
	-- normals pop at slice seams and slope inflections — banking, pull and
	-- the Y projection all ride this relaxed read instead.
	local wantN = if grounded and drop then drop.Normal else Vector3.yAxis
	surfNormal = (surfNormal + (wantN - surfNormal) * (1 - math.exp(-dt / Config.Landing.SlopeSmooth))).Unit
	local bankPull = 0
	bankRollRad = 0
	if grounded and drop then
		bankPull = surfNormal.X * steer.BankPull
		-- Deck roll for the camera: normal.X = -sin(roll) on a banked
		-- surface — same read the pull uses, kept as an angle for the
		-- horizon lean.
		bankRollRad = -math.asin(math.clamp(surfNormal.X, -1, 1))
	end
	local intent = if now >= controlAt then steerIntent() * (if inFlip then -1 else 1) else 0
	-- Dash (§4): the burst drives the SAME lateral-ease math as steering
	-- — the target pins to dash Speed and the accel is ~13x, so the dart
	-- eases in over ~50ms instead of hard-sliding. Steering input is
	-- ignored for the window; on expiry the velocity clamps back into
	-- steer range so residual drift is normal steering, not a free slide.
	-- Consume a buffered dash once the burst window is legal again —
	-- stale presses expire after BufferWindow so a dropped dodge doesn't
	-- surprise-fire later. "denied"/"fired" clear it in one shot.
	if
		dashBuffered and (now - dashBuffered.at > Config.Dash.BufferWindow or tryDash(dashBuffered.dir) ~= "cooldown")
	then
		dashBuffered = nil
	end
	local dashing = now < dashUntil
	local targetLat = intent * steer.MaxLateralSpeed + bankPull
	local accel = if intent == 0 then steer.IdleLateralDamping * steer.MaxLateralSpeed else steer.LateralAccel
	if dashing then
		targetLat = dashDir * (if inFlip then -1 else 1) * Config.Dash.Speed + bankPull
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
	Music.setTier(Tiers.indexAt(dist)) -- layer mix on tier-ups
	Ghost.tick(dt, b.Position) -- record this run + advance the PB echo
	-- Pace delta (§12): live "±N vs PB" — ghost position IS the PB's
	-- position at this elapsed time on this same map.
	local pace = Ghost.pace(b.Position)
	local paceR = pace and math.floor(pace + 0.5) or nil
	if paceR ~= paceCache then
		paceCache = paceR
		ui:setPace(paceR)
	end
	local rpace = Ghost.rivalPace(b.Position)
	local rpaceR = rpace and math.floor(rpace + 0.5) or nil
	if rpaceR ~= rivalPaceCache then
		rivalPaceCache = rpaceR
		ui:setRivalPace(rpaceR, rivalName)
	end
	-- Overtake toast (§14): catching a replay's interpolated position is a
	-- pass, once per ghost per run — armed only after actually trailing it
	-- by OvertakeArm studs, so leading wire-to-wire stays quiet.
	if pace then
		if pace <= -Config.Ghost.OvertakeArm then
			if overtakePb == false then
				-- Mirror (§14): the ghost re-passes you — earned only
				-- after a PASSED toast, so leading wire-to-wire stays
				-- quiet the same way.
				ui:toast("▸ LOST TO PB")
			end
			overtakePb = true
		elseif overtakePb and pace >= 0 then
			overtakePb = false -- consumed; LOST TO is now possible
			ui:toast("▸ PASSED PB")
		end
	end
	if rpace then
		if rpace <= -Config.Ghost.OvertakeArm then
			if overtakeRival == false then
				ui:toast("▸ LOST TO " .. (rivalName or "CHAMP"))
			end
			overtakeRival = true
		elseif overtakeRival and rpace >= 0 then
			overtakeRival = false
			ui:toast("▸ PASSED " .. (rivalName or "CHAMP"))
		end
	end
	-- Hazard radar (§12): re-read the tagged lethal set at ScanSeconds —
	-- movers/spinners track for free. Ball-relative: dz ahead, dx off
	-- center; other lanes fall outside HalfWidth naturally. Nearest
	-- MaxBars win the pool.
	radarT += dt
	if radarT >= Config.Radar.ScanSeconds then
		radarT = 0
		local R = Config.Radar
		local scan = radarScan
		-- FatalController already tracks RoBallLethal incrementally — the
		-- radar reads its set and lane-filters on dx instead of re-paying a
		-- workspace-wide GetTagged (PERFORMANCE.md §1).
		local nearest: Instance? = nil
		for _, p in ipairs(FatalController.lethalParts()) do
			local dz = b.Position.Z - p.Position.Z
			local dx = p.Position.X - b.Position.X
			if dz > -2 and dz < R.Range and math.abs(dx) - p.Size.X / 2 < R.HalfWidth then
				local e = table.remove(radarPool) or { dx = 0, dz = 0, w = 0 }
				e.dx = dx
				e.dz = math.max(dz, 0)
				e.w = p.Size.X
				table.insert(scan, e)
				if not nearest or dz < (b.Position.Z - (nearest :: BasePart).Position.Z) then
					nearest = p
				end
			end
		end
		-- Danger vignette (§12): nearest threat overlapping the ball's line
		-- feeds the heartbeat's frame-stroke intensity.
		dangerDz = nil :: number?
		for _, e in ipairs(scan) do
			if math.abs(e.dx) - e.w / 2 < Config.Danger.Lane and (not dangerDz or e.dz < dangerDz) then
				dangerDz = e.dz
			end
		end
		table.sort(scan, function(a, c)
			return a.dz < c.dz
		end)
		while #scan > R.MaxBars do
			table.insert(radarPool, table.remove(scan))
		end
		ui:setRadar(scan)
		-- Rows live beyond the call only inside Ui's same-frame read —
		-- recycle them for the next scan.
		while #scan > 0 do
			table.insert(radarPool, table.remove(scan))
		end
		-- Ghost ticks (§14): the echoes you race on the threat ruler —
		-- dz ahead = -pace; behind-you clamps to the bottom edge.
		ui:setRadarGhosts(
			pace and math.clamp(-pace, 0, R.Range) or nil,
			rpace and math.clamp(-rpace, 0, R.Range) or nil
		)
		-- Threat name (§12): the nearest bar's chunk label, cached so the
		-- line doesn't thrash as distances jitter between scans.
		local ct = nearest and (nearest :: BasePart):GetAttribute("ChunkType")
		local threat = if type(ct) == "string" then (Config.Features.Label[ct] or string.upper(ct)) else ""
		if threat ~= threatCache then
			threatCache = threat
			ui:setThreat(threat)
		end
	end

	-- Deck-edge warning (§12): two short probes beside the ball — a side
	-- with nothing under it reads as a chevron. Only the ball's own lane
	-- folder counts as support (backdrop towers and ghost echoes can't
	-- fake ground); blocks and walls inside it support honestly.
	local E = Config.EdgeWarn
	local lp = workspace:Raycast(bp + Vector3.new(-E.ProbeSide, 0, 0), EDGE_DOWN * E.ProbeDown, edgeParams)
	local rp = workspace:Raycast(bp + Vector3.new(E.ProbeSide, 0, 0), EDGE_DOWN * E.ProbeDown, edgeParams)
	ui:setEdgeWarn(lp == nil, rp == nil)

	-- Airtime stat (§11): the same lane probe that drives bank pull
	-- decides grounded vs airborne — the death card turns it into "air
	-- N%" of run time.
	if grounded then
		statGroundT += dt
	else
		statAirT += dt
	end

	-- Danger vignette + sonar (§12): intensity rises toward contact
	-- distance — steady ramp, no pulse: speed already thins the time it
	-- reads. Past PingMin a blip repeats on a cadence that tightens with
	-- closeness — the audible mirror of the frame closing in.
	local dd = dangerDz
	local dInt = dd and math.clamp(1 - dd / Config.Danger.Near, 0, 1) or 0
	ui:setDanger(dInt)
	local dn = Config.Danger
	if dInt >= dn.PingMin and now >= nextPingAt then
		Sfx.dangerPing(dInt)
		nextPingAt = now + dn.PingSlow + (dn.PingFast - dn.PingSlow) * (dInt - dn.PingMin) / (1 - dn.PingMin)
	elseif dInt < dn.PingMin then
		nextPingAt = 0 -- re-arm instantly on the next entry
	end

	local v = b.AssemblyLinearVelocity
	-- Unstick hop (§11): the -Z write below means a freeze is physics
	-- canceling intent — real v.Z collapses while Y stays quiet (grounded).
	-- Sustain that past UnstickTime → one Y impulse pops the seam lip.
	if not inFlip and math.abs(v.Y) < steer.UnstickMaxY and -v.Z < fwdSpeed * 0.15 then
		stuckT += dt
	else
		stuckT = 0
	end
	if stuckT >= steer.UnstickTime and now >= unstickAfter then
		stuckT = 0
		unstickAfter = now + steer.UnstickCooldown
		unstickUntil = now + 0.14
	end
	-- The kick stamp reads physics v.Y, not the overridden vY below — an
	-- unstick window that fires the same frame as a pad must not swallow
	-- the launch (the pad's KickY is inviolable, §8.6).
	local kickAt = b:GetAttribute("KickAt") or 0
	local kicked = v.Y > 0 and now - kickAt <= Config.Landing.KickGrace
	local vY = if inFlip then Config.Flip.Lift elseif now < unstickUntil and not kicked then steer.UnstickHop else v.Y
	-- Inside a flip zone vY is pinned to +Lift so gravity can't pull the
	-- ball off the ceiling; at the zone edge the pin drops and gravity
	-- takes over — the ball falls ClearH back to the deck.
	-- Slope tracking (§4): while grounded, the drive vector projects onto
	-- the eased surface — drive - (drive·n)n is the plane projection (same
	-- as n×(drive×n)); its Y becomes the vertical target, so the ball
	-- pushes itself down hills and carries over crests instead of
	-- launching (Monkey Ball feel). Fresh pad/orb kicks and genuine
	-- airtime keep physics Y — gravity owns a real fall.
	if not inFlip and now >= unstickUntil and grounded and not kicked then
		local drive = Vector3.new(lateralVel, 0, -fwdSpeed)
		local surfY = (drive - surfNormal * drive:Dot(surfNormal)).Y
		-- Ease toward the surface speed while contact persists
		-- (SlopeVelSmooth τ) — but a real fall outrunning the ground
		-- snaps straight to surfY instead of easing through the deck.
		if vY < surfY - Config.Landing.ImpactPad then
			vY = surfY
		else
			vY += (surfY - vY) * (1 - math.exp(-dt / Config.Landing.SlopeVelSmooth))
		end
	-- Zero-bounce landing (§11): arriving harder than the deck's own
	-- descent pops the ball back up even at elasticity 0 — the solver's
	-- impact response is the bounce. Stage one: the lane probe looks
	-- ClampReach + one physics step ahead and caps the approach at
	-- slope-following speed + ImpactPad — a deep fall can't outrun the
	-- frame. Stage two: any positive vY still standing at contact is a
	-- solver pop, squashed flat — unless a pad/orb kick stamped KickAt
	-- inside the grace window. Over a gap the probe finds nothing:
	-- falls stay free.
	elseif not inFlip and now >= unstickUntil and drop then
		local gap = bp.Y - Config.Ball.Diameter / 2 - drop.Position.Y
		if gap <= Config.Landing.ClampReach + math.max(0, -vY) * dt then
			vY = math.max(vY, -fwdSpeed * Config.Generation.Grade - Config.Landing.ImpactPad)
		end
		if gap <= Config.Landing.ContactPad and vY > 0 and not kicked then
			vY = 0
		end
	end
	b.AssemblyLinearVelocity = Vector3.new(lateralVel, vY, -fwdSpeed)
	lastBallPos = b.Position

	-- HUD: attributes arrive from the server; only rebuild on visible change
	local score = player:GetAttribute("RoBallScore") or 0
	local d = player:GetAttribute("RoBallDist") or 0
	local gems = player:GetAttribute("RoBallGems") or 0
	local bank = player:GetAttribute("RoBallBank") or 0
	local shown = math.floor(fwdSpeed + 0.5)
	if score ~= hudS or d ~= hudD or gems ~= hudG or shown ~= hudV or bank ~= hudB then
		hudS, hudD, hudG, hudV, hudB = score, d, gems, shown, bank
		ui:setHud(score, d, gems, shown, currentSeed or 0)
		ui:setMissionTrack(score, d, bank)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local cam = Config.Camera
	local pulse = Music.sample()
	Backdrop.setPulse(pulse) -- analyzer energy -> sun breathing (AUDIO.md §8)
	ui:setPulse(pulse) -- same energy -> speedo thump / chromatic spread
	ui:setWave(Music.spectrum()) -- spectrum buckets -> BPM scope trace (§12)

	local b = ball
	if b then
		local speedT = math.clamp((fwdSpeed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)
		camera.FieldOfView = cam.FovMin + (cam.FovMax - cam.FovMin) * speedT
		-- Aim at the deck plane LookAhead studs out: the drop = grade*ahead,
		-- so the camera pitches into the slope and shows more track (the
		-- Slope downhill read). Roll leans a few degrees into the steer.
		local target = b.Position + Config.Generation.TravelAxis * cam.LookAhead
		target -= Vector3.new(0, Config.Generation.Grade * cam.LookAhead + cam.LookDrop, 0)
		local lean = -math.clamp(lateralVel / Config.Steering.MaxLateralSpeed, -1, 1) * math.rad(cam.LeanMax)
		-- Horizon lean: the camera follows BankLean of the deck's roll so a
		-- banked chunk tilts the WORLD, not just the ribbon — eased so deck
		-- seams and landings lean rather than snap.
		bankLeanCur += (-bankRollRad * cam.BankLean - bankLeanCur) * (1 - math.exp(-dt / cam.SmoothTime))
		lean += bankLeanCur
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
	elseif mode == "menu" then
		-- Menu vista: slow orbit toward the track start
		local t = tick() * 0.12
		local p = Vector3.new(math.sin(t) * 55, 40, 30 + math.cos(t) * 25)
		camera.CFrame = CFrame.lookAt(p, Vector3.new(0, Config.Generation.StartY - 15, -120))
		Backdrop.update(Vector3.new(0, Config.Generation.StartY, -60))
	else
		-- Transitional frames: ball gone but RunEnded hasn't flipped mode
		-- yet — hold the anchor on the last ball spot so the backdrop
		-- never sees a phantom teleport to the vista and re-seeds.
		Backdrop.update(lastBallPos)
	end
end)

-- Garage refresh on state changes: equipped ids resync browsing + preview;
-- ownership and bank changes re-render prices and buttons.
player:GetAttributeChangedSignal("RoBallOwned"):Connect(refreshGarage)
player:GetAttributeChangedSignal("RoBallBank"):Connect(refreshGarage)
-- COLOR LAB: hue writes land on attributes — re-seat the sliders.
for _, attr in pairs(Cosmetics.HueAttr) do
	player:GetAttributeChangedSignal(attr):Connect(refreshGarage)
end
for _, slot in ipairs(Cosmetics.Slots) do
	player:GetAttributeChangedSignal("RoBallEq_" .. slot):Connect(function()
		syncBrowse(slot)
		refreshGarage()
		CosmeticFx.refresh()
	end)
end

Backdrop.init()
ScreenFilter.init()
Music.init()
AudioMix.init()
Sfx.init()
GemFx.init()
CosmeticFx.init(function()
	return ball
end)
CosmeticFx.mountViewport(ui.previewView)
PadController.init(function()
	return ball
end)
OrbController.init(function()
	return ball
end, Config.Features.JumpOrbs == true)
-- Beat-locked movers re-evaluate their waveform locally every frame
-- (§8.6): server steps at StepHz for its own bookkeeping — replicated
-- writes alone would read as teleports.
MoverController.init(function()
	return ball
end)
-- Lethal hits are reported where they're simulated (§11): this client owns
-- the ball, so its contact is the truth the player sees. Report once; the
-- server seals the run and answers with the normal RunEnded flow.
FatalController.init(function()
	return ball
end, function()
	return mode == "running"
end, function(killerPart: BasePart?)
	evReportFatal:FireServer(killerPart)
end)
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
