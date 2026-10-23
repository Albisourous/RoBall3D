--!strict
-- ShopService (DESIGN.md §18): ownership + equip state for cosmetics plus
-- the Phase-2 gem bank. Passes are the source of truth for bundle ownership
-- (queried live, cached per session — never stored); the profile DataStore
-- persists equipped ids, the bank balance, and item ids bought with gems
-- (gem purchases have no platform record, so `items` IS their receipt).
-- State mirrors onto player attributes so the client garage/FX read it
-- without a fetch remote:
--   RoBallEq_<slot>  -> equipped item id ("skin"/"trail"/"gemFx"/"deathFx")
--   RoBallOwned      -> CSV of owned bundle keys + purchased item ids
--   RoBallBank       -> banked gem balance (banked currency is never score)
--   RoBallHue_<A|B|C>-> COLOR LAB custom hues 0..1 (§18; band-clamped)
--   RoBallVol_<ch>   -> mixer channel gain 0..1 (AUDIO.md §7)
-- Studio: pass/product ids are 0 until created on the dashboard, so nothing
-- robux-priced exists and free items still equip — the system degrades
-- cleanly. DataStores off in Studio = volatile session bank, still playable.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Daily = require(ReplicatedStorage.RoBall.Daily)
local SaveService = require(script.Parent.SaveService)

local ShopService = {}

local owned: { [Player]: { [string]: boolean } } = {} -- bundle/perk pass key -> true
local items: { [Player]: { [string]: boolean } } = {} -- gem-purchased itemId -> true
local equipped: { [Player]: { [string]: string } } = {} -- slot -> itemId
local bank: { [Player]: number } = {}
local profileReady: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {} -- bank/items changed since last save
local dailyDay: { [Player]: string } = {} -- last counted daily-run day tag (§14)
local dailyStreak: { [Player]: number } = {}
local pendingDaily: { [Player]: boolean } = {} -- daily run ended before the profile landed
local questDayTag: { [Player]: string } = {} -- day the quest slots belong to (§14)
local questDone: { [Player]: { [string]: boolean } } = {} -- quest id -> true (today)
local questBanked: { [Player]: number } = {} -- gems banked toward today's bank quest
local achDone: { [Player]: { [string]: boolean } } = {} -- achievement id -> true (§14)
local achNew: { [Player]: { string } } = {} -- ids unlocked by the latest eval (one-push toast batch)
local statsGems: { [Player]: number } = {} -- lifetime gems banked through play
local statsRuns: { [Player]: number } = {} -- lifetime clean runs finished
local statsBestDist: { [Player]: number } = {} -- lifetime best single-run distance
-- Recent runs (§14): { s=score, d=dist, z=seed }, newest first. Session
-- state persists via profile.history on save; mirrored to the client as
-- the RoBallHistory CSV attr so the menu strip can render + replay seeds.
local history: { [Player]: { { s: number, d: number, z: number } } } = {}
-- Menu mixer (AUDIO.md §7): per-channel gains mirrored as
-- RoBallVol_<ch> attributes; missing entries mean 1 (full).
local audioVol: { [Player]: { [string]: number } } = {}
-- COLOR LAB (§18): custom hue channels a/b/c (0..1, band-clamped by
-- Config.CustomHue). Mirrored as RoBallHue* attributes; persisted in
-- profile.hues like the mixer gains.
local customHues: { [Player]: { a: number, b: number, c: number } } = {}
-- Dash style (§4): "keys"|"tap" — a control pref mirrored as the
-- RoBallDashMode attribute; persists in profile.dashMode like the mixer.
local dashModes: { [Player]: string } = {}
-- Dev-product receipts (§18 P2): PurchaseId -> true. Persisted in
-- profile.receipts so redelivery on ANY server finds the mark — session
-- memory alone can't dedup a retry that lands after a crash or hop.
local receipts: { [Player]: { [string]: boolean } } = {}
-- Save coalescing: a burst of saveNow calls collapses into one in-flight
-- write plus at most one trailing write of the LATEST snapshot — remote
-- spam can't stack a write per invoke and drain the DataStore budget.
local saveFlying: { [Player]: boolean } = {}
local saveAgain: { [Player]: boolean } = {}
local pendingSnap: { [Player]: SaveService.Profile } = {}

local function defaultHues(): { a: number, b: number, c: number }
	local d = Config.CustomHue.Defaults
	return { a = d.a, b = d.b, c = d.c }
end

function ShopService.hues(player: Player): { a: number, b: number, c: number }
	return customHues[player] or defaultHues()
end

function ShopService.ownsPass(player: Player, key: string): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

function ShopService.ownsItem(player: Player, itemId: string): boolean
	-- Cosmetics.owns is the single oracle: free + gem ids + live bundles +
	-- retired LegacyBundles (§18 — a sunset pass keeps granting its items).
	-- Merge the two session tables into the mixed key/item-id set it wants.
	local set = owned[player] or {}
	if items[player] then
		set = table.clone(set)
		for id in pairs(items[player]) do
			set[id] = true
		end
	end
	return Cosmetics.owns(set, itemId)
end

function ShopService.equipped(player: Player): { [string]: string }
	return equipped[player] or Cosmetics.defaults()
end

function ShopService.bank(player: Player): number
	return bank[player] or 0
end

function ShopService.isReady(player: Player): boolean
	return profileReady[player] == true
end

-- Mirror state onto attributes: per-slot equipped ids, owned CSV (pass keys
-- + item ids — disjoint namespaces), bank balance.
local function pushAttrs(player: Player)
	local eq = ShopService.equipped(player)
	for _, slot in ipairs(Cosmetics.Slots) do
		player:SetAttribute("RoBallEq_" .. slot, eq[slot])
	end
	local list = {}
	for key in pairs(owned[player] or {}) do
		table.insert(list, key)
	end
	for id in pairs(items[player] or {}) do
		table.insert(list, id)
	end
	table.sort(list)
	player:SetAttribute("RoBallOwned", table.concat(list, ","))
	player:SetAttribute("RoBallBank", bank[player] or 0)
	player:SetAttribute("RoBallDailyStreak", dailyStreak[player] or 0)
	-- Daily quests (§14): "done flag per quest, banked today" CSV — the
	-- client recomputes the quest list from Daily.quests() itself.
	local flags = {}
	for i, q in ipairs(Daily.quests()) do
		flags[i] = ((questDone[player] or {})[q.id] and questDayTag[player] == Daily.dayTag()) and "1" or "0"
	end
	table.insert(flags, tostring(questBanked[player] or 0))
	player:SetAttribute("RoBallQuests", table.concat(flags, ","))
	-- Achievements (§14): RoBallAch = the full sorted unlock set for the
	-- menu tally; RoBallAchNew = only ids unlocked by the latest eval —
	-- the client toasts that batch, so a restored profile never re-fires.
	local ach = {}
	for id in pairs(achDone[player] or {}) do
		table.insert(ach, id)
	end
	table.sort(ach)
	player:SetAttribute("RoBallAch", table.concat(ach, ","))
	player:SetAttribute("RoBallAchNew", table.concat(achNew[player] or {}, ","))
	achNew[player] = {}
	-- Recent runs (§14): "s,d,z;s,d,z" — seeds survive for click-to-replay.
	local hist = {}
	for _, r in ipairs(history[player] or {}) do
		table.insert(hist, string.format("%d,%d,%d", r.s, r.d, r.z))
	end
	player:SetAttribute("RoBallHistory", table.concat(hist, ";"))
	-- Mixer (AUDIO.md §7): RoBallVol_<ch> per channel, falling back to
	-- Config.Audio.Defaults (music 1, SFX half) for unsaved channels.
	for _, ch in ipairs(Config.Audio.Channels) do
		player:SetAttribute(
			Config.Audio.AttrPrefix .. ch,
			(audioVol[player] or {})[ch] or Config.Audio.Defaults[ch] or 1
		)
	end
	-- COLOR LAB (§18): RoBallHue* per channel — always pushed so the
	-- client preview + dress paths never see a missing attr.
	local h = customHues[player] or defaultHues()
	for k, attr in pairs(Cosmetics.HueAttr) do
		player:SetAttribute(attr, (h :: any)[k])
	end
	player:SetAttribute("RoBallDashMode", dashModes[player] or Config.Dash.Modes[1])
end

local function itemArray(player: Player): { string }
	local list = {}
	for id in pairs(items[player] or {}) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

-- Snapshot everything NOW: the write serializes later, and a live table
-- reference would write whatever state exists at that moment. Captured
-- before the flying check so a leave-flush queued while PlayerRemoving
-- clears session tables still writes real state, not nils.
local function snapshotProfile(player: Player): SaveService.Profile
	local questDoneSnapshot = {}
	for id in pairs(questDone[player] or {}) do
		table.insert(questDoneSnapshot, id)
	end
	local achSnapshot = {}
	for id in pairs(achDone[player] or {}) do
		table.insert(achSnapshot, id)
	end
	local histSnapshot = {}
	for _, r in ipairs(history[player] or {}) do
		table.insert(histSnapshot, { s = r.s, d = r.d, z = r.z })
	end
	return {
		equipped = table.clone(equipped[player] or {}),
		bank = bank[player] or 0,
		items = itemArray(player),
		dailyDay = dailyDay[player] or "",
		dailyStreak = dailyStreak[player] or 0,
		questDay = questDayTag[player] or "",
		questDone = questDoneSnapshot,
		questBanked = questBanked[player] or 0,
		achievements = achSnapshot,
		statsGems = statsGems[player] or 0,
		statsRuns = statsRuns[player] or 0,
		statsBestDist = statsBestDist[player] or 0,
		audio = table.clone(audioVol[player] or {}),
		hues = table.clone(customHues[player] or defaultHues()),
		dashMode = dashModes[player] or Config.Dash.Modes[1],
		history = histSnapshot,
		receipts = table.clone(receipts[player] or {}),
	}
end

local function saveNow(player: Player)
	local eq = equipped[player]
	if not eq or not profileReady[player] then
		return -- pre-load writes would snapshot defaults over the stored profile
	end
	dirty[player] = false
	pendingSnap[player] = snapshotProfile(player)
	if saveFlying[player] then
		saveAgain[player] = true -- collapse this burst into the trailing write
		return
	end
	saveFlying[player] = true
	task.spawn(function()
		repeat
			saveAgain[player] = false
			local snap = pendingSnap[player]
			pendingSnap[player] = nil
			if snap then
				SaveService.saveProfile(player.UserId, snap)
			end
		until not saveAgain[player]
		saveFlying[player] = nil
	end)
end

-- Awaited write (receipt path): the caller must KNOW the save landed
-- before it answers — a spawned coalesced write can't give that. Same
-- snapshot, same retry, synchronous so ProcessReceipt can refuse the ack
-- when the store is down.
local function saveNowSync(player: Player): boolean
	if not profileReady[player] or equipped[player] == nil then
		return false
	end
	dirty[player] = false
	return SaveService.saveProfileSync(player.UserId, snapshotProfile(player))
end

-- Checkpoint write (§18 P2): bank credits live per pickup but only persists
-- on boundaries — run end, purchases, leaving, shutdown. A crash loses at
-- most the in-flight run's gems.
function ShopService.flush(player: Player)
	if dirty[player] then
		saveNow(player)
	end
end

-- Gem pickup credit (§18 P2): every collected gem banks BankPerGem, doubled
-- by the 2X BANK pass. Returns the credited amount so the run can total it
-- for the death screen. Banked currency is never score.
function ShopService.awardGems(player: Player, n: number): number
	local mult = ShopService.ownsPass(player, "bank2x") and Config.Monetization.BankDoubleMult or 1
	local credited = n * mult
	bank[player] = (bank[player] or 0) + credited
	-- Lifetime stat for achievements (§14): play-earned gems only —
	-- purchases route through grantGems and don't count toward VAULT.
	statsGems[player] = (statsGems[player] or 0) + credited
	dirty[player] = true
	player:SetAttribute("RoBallBank", bank[player])
	return credited
end

-- Daily streak (§14): finishing a daily-seeded run counts the day. Same
-- day again -> no-op; yesterday -> streak+1; a gap -> back to 1. Each
-- counted day pays min(streak, cap) * DailyStreakBonus banked gems (never
-- score). Runs ending before the profile lands queue on pendingDaily so
-- the stored streak can't be clobbered by an unloaded profile.
function ShopService.recordDailyRun(player: Player): (number, number)
	if not profileReady[player] then
		pendingDaily[player] = true
		return dailyStreak[player] or 0, 0
	end
	local today = Daily.dayTag()
	if dailyDay[player] == today then
		return dailyStreak[player] or 0, 0
	end
	local streak = if dailyDay[player] == Daily.dayTag(os.time() - 86400) then (dailyStreak[player] or 0) + 1 else 1
	dailyDay[player] = today
	dailyStreak[player] = streak
	player:SetAttribute("RoBallDailyStreak", streak)
	local bonus = math.min(streak, Config.Monetization.DailyStreakCap) * Config.Monetization.DailyStreakBonus
	if bonus > 0 then
		ShopService.awardGems(player, bonus)
	end
	saveNow(player)
	return streak, bonus
end

-- Daily quests (§14): evaluate today's three missions at run end.
-- `bankedDelta` = gems this run banked (pickups + streak bonus); the bank
-- quest tracks today's total. Rewards pay banked gems — never score.
-- Returns (bonusGems, completedCount).
function ShopService.onRunEnd(
	player: Player,
	dist: number,
	score: number,
	bankedDelta: number,
	seed: number?
): (number, number)
	-- Recent runs (§14): recorded even when the profile hasn't landed —
	-- it's session state first, persisted on the next saveNow. The attr
	-- writes here since the ready-gate below skips pushAttrs for unready.
	local h = history[player]
	if h and seed then
		table.insert(h, 1, { s = score, d = dist, z = seed })
		while #h > Config.Leaderboard.HistoryCount do
			table.remove(h)
		end
		local csv = {}
		for _, r in ipairs(h) do
			table.insert(csv, string.format("%d,%d,%d", r.s, r.d, r.z))
		end
		player:SetAttribute("RoBallHistory", table.concat(csv, ";"))
		dirty[player] = true
	end
	if not profileReady[player] then
		return 0, 0
	end
	local today = Daily.dayTag()
	if questDayTag[player] ~= today then
		questDayTag[player] = today
		questDone[player] = {}
		questBanked[player] = 0
	end
	questBanked[player] = (questBanked[player] or 0) + bankedDelta
	local bonus = 0
	local hits = 0
	for _, q in ipairs(Daily.quests()) do
		if not questDone[player][q.id] then
			local done = (q.kind == "reach" and dist >= q.target)
				or (q.kind == "score" and score >= q.target)
				or (q.kind == "bank" and (questBanked[player] or 0) >= q.target)
			if done then
				questDone[player][q.id] = true
				bonus += q.reward
				hits += 1
			end
		end
	end
	-- Achievements (§14): clean runs only — the caller gates this. Stats
	-- move first so same-run thresholds (1k dist + 100 lifetime gems)
	-- can both clear on one ending.
	statsRuns[player] = (statsRuns[player] or 0) + 1
	statsBestDist[player] = math.max(statsBestDist[player] or 0, dist)
	local allQuests = 0
	for _, q in ipairs(Daily.quests()) do
		if questDone[player][q.id] then
			allQuests += 1
		end
	end
	local achBonus = 0
	local achHits = 0
	if not achNew[player] then
		achNew[player] = {}
	end
	for _, a in ipairs(Config.Monetization.Achievements) do
		if not achDone[player][a.id] then
			local ok = (a.kind == "runs" and statsRuns[player] >= a.target)
				or (a.kind == "runDist" and dist >= a.target)
				or (a.kind == "lifetimeGems" and (statsGems[player] or 0) >= a.target)
				or (a.kind == "streak" and (dailyStreak[player] or 0) >= a.target)
				or (a.kind == "questsAll" and allQuests >= a.target)
			if ok then
				achDone[player][a.id] = true
				table.insert(achNew[player], a.id)
				achBonus += a.reward
				achHits += 1
			end
		end
	end
	bonus += achBonus
	pushAttrs(player)
	if bonus > 0 then
		ShopService.awardGems(player, bonus)
	end
	saveNow(player)
	return bonus, hits
end

-- Dev-product grant (ProcessReceipt): credits gems and saves IMMEDIATELY —
-- once we tell Roblox PurchaseGranted the money is spent, so the bank must
-- land in the same breath, not at the next checkpoint.
function ShopService.grantGems(player: Player, n: number): number
	bank[player] = (bank[player] or 0) + n
	player:SetAttribute("RoBallBank", bank[player])
	saveNow(player)
	return bank[player]
end

-- Seasonal slot (§18): the gated bundle can't be claimed outside its
-- yearly window; member items refuse à-la-carte gem buys too. Ownership
-- already granted is untouched — the gate only blocks NEW acquisitions.
-- Dev flags (Debug.Enabled / FreeForTesting) lift the window — every
-- pack must be claimable when the shop runs free for testing, matching
-- the rollout gate's Debug exemption.
local function seasonalLive(): boolean
	return Config.Debug.Enabled or Config.Monetization.FreeForTesting or (Daily.seasonalStatus())
end

-- Per-item gem purchase (§18 P2): the grind path. Server re-validates
-- everything — catalog record, price, ownership, balance — then deducts,
-- records the item id, auto-equips (same delight rule as bundle passes),
-- and saves: a spend is a boundary, never left dirty.
function ShopService.buyItem(player: Player, itemId: string): (boolean, string)
	if not profileReady[player] then
		return false, "loading"
	end
	local item = Cosmetics.Items[itemId]
	if not item or item.free or item.gemPrice == nil then
		return false, "not for sale"
	end
	if Cosmetics.bundleOf(itemId) == Config.Monetization.Seasonal.Bundle and not seasonalLive() then
		return false, "offseason"
	end
	-- Weekly drop gate (§18): member items of an unreleased wave refuse
	-- à-la-carte gem buys until their pack hits the teaser→live boundary —
	-- same acquisition-only gate as the seasonal window. bestRollout covers
	-- shared members: an item is live if ANY pack containing it is.
	if Cosmetics.bestRollout(itemId) ~= "live" then
		return false, "unreleased"
	end
	if ShopService.ownsItem(player, itemId) then
		return false, "owned"
	end
	local price = item.gemPrice :: number
	if (bank[player] or 0) < price then
		return false, "bank"
	end
	bank[player] = (bank[player] or 0) - price
	if not items[player] then
		items[player] = {}
	end
	items[player][itemId] = true
	if not equipped[player] then
		equipped[player] = Cosmetics.defaults()
	end
	equipped[player][item.slot] = itemId
	pushAttrs(player)
	saveNow(player)
	return true, "ok"
end

-- Query every configured pass for this player (id 0 = not created yet).
local function queryPasses(player: Player)
	local set = {}
	for key, id in pairs(Config.Monetization.Passes) do
		if id > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and has then
				set[key] = true
			end
		end
	end
	owned[player] = set
end

-- Equip every item a bundle grants — post-purchase delight (§18): the
-- look lands immediately, no manual trip to the garage required. Perk
-- passes (bank2x) own no items, so this is a clean no-op for them.
local function equipBundle(player: Player, bundleId: string)
	for _, b in ipairs(Cosmetics.Bundles) do
		if b.id == bundleId then
			for _, itemId in ipairs(b.items) do
				local item = Cosmetics.Items[itemId]
				if item then
					equipped[player][item.slot] = itemId
				end
			end
		end
	end
end

-- Mixer write (AUDIO.md §7): a slider release lands here. Cosmetic
-- state — no gameplay effect — so it follows the equip/save path.
function ShopService.setAudio(player: Player, ch: string, v: number): boolean
	if not table.find(Config.Audio.Channels, ch) then
		return false
	end
	v = math.clamp(v, 0, 1)
	if not audioVol[player] then
		audioVol[player] = {}
	end
	audioVol[player][ch] = v
	pushAttrs(player)
	saveNow(player)
	return true
end

-- Dash style (§4): the menu toggle lands here via SetDashMode — a control
-- pref, mirrored as RoBallDashMode + saved like a mixer gain.
function ShopService.dashMode(player: Player): string
	return dashModes[player] or Config.Dash.Modes[1]
end

function ShopService.setDashMode(player: Player, m: string): boolean
	if not table.find(Config.Dash.Modes, m) then
		return false
	end
	dashModes[player] = m
	pushAttrs(player)
	saveNow(player)
	return true
end

-- COLOR LAB write (§18): slider releases land here via SetHues. Gate: the
-- player must own at least one lab item (bundle grants all three; a
-- gem-bought single unlocks the lab too — friendlier and harmless).
-- Values clamp into the legal band server-side, so the red seam can never
-- be mixed even by a hand-rolled client. Saves immediately like an equip.
function ShopService.setHues(player: Player, h: any): boolean
	local allowed = false
	for _, id in ipairs(Cosmetics.LabItems) do
		if ShopService.ownsItem(player, id) then
			allowed = true
			break
		end
	end
	if not allowed then
		return false
	end
	local H = Config.CustomHue
	local cur = customHues[player] or defaultHues()
	if typeof(h) == "table" then
		for _, k in ipairs({ "a", "b", "c" }) do
			local v = (h :: any)[k]
			if typeof(v) == "number" and v == v then
				(cur :: any)[k] = math.clamp(v, H.Min, H.Max)
			end
		end
	end
	customHues[player] = cur
	pushAttrs(player)
	saveNow(player)
	return true
end

function ShopService.equip(player: Player, itemId: string): boolean
	local item = Cosmetics.Items[itemId]
	if not item or not ShopService.ownsItem(player, itemId) then
		return false
	end
	if not equipped[player] then
		equipped[player] = Cosmetics.defaults()
	end
	equipped[player][item.slot] = itemId
	pushAttrs(player)
	saveNow(player)
	return true
end

-- Free-for-testing grants (Config.Monetization.FreeForTesting — §18): the
-- pre-paywall path. A garage click "buys" instantly — no prompt, no
-- dashboard id — but lands through the same ownership/equip/save pipeline
-- as a real purchase. Dead ends once the flag is off.
local claimable: { [string]: boolean } = {}
for _, b in ipairs(Cosmetics.Bundles) do
	claimable[b.id] = true
end
claimable["bank2x"] = true -- perk pass owns no items

function ShopService.claimPass(player: Player, key: string): (boolean, string)
	if not Config.Monetization.FreeForTesting then
		return false, "unavailable"
	end
	if not profileReady[player] then
		return false, "loading" -- same gate as buyItem: a pre-load claim would
		-- be wiped when queryPasses rebuilds owned[] at profile land
	end
	-- Retired pass ids stay in Passes for ownership lookup but aren't
	-- sellable — a hand-rolled client must not claim sunset contents.
	if not claimable[key] then
		return false, "unknown pass"
	end
	if key == Config.Monetization.Seasonal.Bundle and not seasonalLive() then
		return false, "offseason"
	end
	-- Weekly drop gate (§18): unreleased waves refuse claims even in
	-- FreeForTesting; Config.Debug.Enabled lifts the gate for dev.
	if Daily.rolloutStatus(key) ~= "live" then
		return false, "unreleased"
	end
	if ShopService.ownsPass(player, key) then
		return false, "owned"
	end
	if not owned[player] then
		owned[player] = {}
	end
	if not equipped[player] then
		equipped[player] = Cosmetics.defaults()
	end
	owned[player][key] = true
	equipBundle(player, key)
	pushAttrs(player)
	saveNow(player)
	return true, "ok"
end

function ShopService.claimGemPack(player: Player, key: string): (boolean, string)
	if not Config.Monetization.FreeForTesting then
		return false, "unavailable"
	end
	if not profileReady[player] then
		return false, "loading"
	end
	local gems = Config.Monetization.ProductGems[key]
	if gems == nil then
		return false, "unknown pack"
	end
	ShopService.grantGems(player, gems)
	return true, "ok"
end

function ShopService.onPlayerAdded(player: Player)
	owned[player] = {}
	items[player] = {}
	equipped[player] = Cosmetics.defaults()
	bank[player] = 0
	dailyDay[player] = ""
	dailyStreak[player] = 0
	pendingDaily[player] = false
	questDayTag[player] = ""
	questDone[player] = {}
	questBanked[player] = 0
	achDone[player] = {}
	achNew[player] = {}
	statsGems[player] = 0
	statsRuns[player] = 0
	statsBestDist[player] = 0
	audioVol[player] = {}
	customHues[player] = defaultHues()
	history[player] = {}
	receipts[player] = {}
	profileReady[player] = false
	task.spawn(function()
		local eq = equipped[player]
		local prof = SaveService.loadProfile(player.UserId)
		if equipped[player] == nil or bank[player] == nil or items[player] == nil then
			return -- player left during the async load
		end
		if prof then
			if typeof(prof.equipped) == "table" then
				for slot, id in pairs(prof.equipped) do
					local item = Cosmetics.Items[id]
					-- Only fill slots still at default: a purchase that landed
					-- during the async load must not be clobbered.
					if item and item.slot == slot and eq[slot] == Cosmetics.Defaults[slot] then
						eq[slot] = id
					end
				end
			end
			-- += (not =): gems banked by an early run before the profile
			-- landed are this session's delta on top of the stored baseline.
			if typeof(prof.bank) == "number" then
				bank[player] += prof.bank
			end
			if typeof(prof.items) == "table" then
				for _, id in ipairs(prof.items) do
					if Cosmetics.Items[id] then
						items[player][id] = true
					end
				end
			end
			if typeof(prof.dailyDay) == "string" then
				dailyDay[player] = prof.dailyDay
			end
			if typeof(prof.dailyStreak) == "number" then
				dailyStreak[player] = prof.dailyStreak
			end
			-- Quest slots only restore if the stored day IS today — a stale
			-- tag means yesterday's missions expired with the day.
			if prof.questDay == Daily.dayTag() then
				questDayTag[player] = prof.questDay
				if typeof(prof.questDone) == "table" then
					for _, id in ipairs(prof.questDone) do
						questDone[player][id] = true
					end
				end
				if typeof(prof.questBanked) == "number" then
					questBanked[player] = prof.questBanked
				end
			end
			-- Recent runs restore unconditionally — display data, replay
			-- seeds. Entries are validated shape-only (numbers in place).
			if typeof(prof.history) == "table" then
				for _, r in ipairs(prof.history) do
					if
						typeof(r) == "table"
						and typeof(r.s) == "number"
						and typeof(r.d) == "number"
						and typeof(r.z) == "number"
					then
						table.insert(history[player], { s = r.s, d = r.d, z = r.z })
					end
				end
			end
			-- Mixer gains restore unconditionally; unknown channels die here.
			if typeof(prof.audio) == "table" then
				for ch, v in pairs(prof.audio) do
					if table.find(Config.Audio.Channels, ch) and typeof(v) == "number" then
						audioVol[player][ch] = math.clamp(v, 0, 1)
					end
				end
			end
			-- COLOR LAB hues (§18): restore band-clamped channels only —
			-- a hand-edited profile still can't smuggle lethal red in.
			if typeof(prof.hues) == "table" then
				local H = Config.CustomHue
				local cur = customHues[player] or defaultHues()
				for _, k in ipairs({ "a", "b", "c" }) do
					local v = (prof.hues :: any)[k]
					if typeof(v) == "number" then
						(cur :: any)[k] = math.clamp(v, H.Min, H.Max)
					end
				end
				customHues[player] = cur
			end
			-- Dash style (§4): control pref, whitelisted ids only.
			if typeof(prof.dashMode) == "string" and table.find(Config.Dash.Modes, prof.dashMode) then
				dashModes[player] = prof.dashMode
			end
			-- Achievements restore unconditionally — unlocks are permanent,
			-- stats are lifetime counters. Unknown ids are ignored.
			if typeof(prof.achievements) == "table" then
				for _, id in ipairs(prof.achievements) do
					achDone[player][id] = true
				end
			end
			statsGems[player] =
				math.max(statsGems[player], if typeof(prof.statsGems) == "number" then prof.statsGems else 0)
			statsRuns[player] =
				math.max(statsRuns[player], if typeof(prof.statsRuns) == "number" then prof.statsRuns else 0)
			statsBestDist[player] = math.max(
				statsBestDist[player],
				if typeof(prof.statsBestDist) == "number" then prof.statsBestDist else 0
			)
			-- Paid-purchase marks restore unconditionally — a redelivered
			-- receipt must find its mark wherever the profile last saved it.
			if typeof(prof.receipts) == "table" then
				for pid in pairs(prof.receipts) do
					receipts[player][pid :: string] = true
				end
			end
		end
		queryPasses(player)
		if equipped[player] == nil then
			return -- gone mid-load: nothing left to mirror
		end
		-- Strip equipped items the player can't own (e.g. refunded pass).
		for slot, id in pairs(eq) do
			if not ShopService.ownsItem(player, id) then
				eq[slot] = Cosmetics.Defaults[slot]
			end
		end
		profileReady[player] = true
		pushAttrs(player)
		-- A daily run that finished during the async load counts now — the
		-- stored streak is live, so the day can't be lost or clobbered.
		if pendingDaily[player] then
			pendingDaily[player] = nil
			ShopService.recordDailyRun(player)
		end
	end)
end

function ShopService.onPlayerRemoving(player: Player)
	saveNow(player)
	owned[player] = nil
	items[player] = nil
	equipped[player] = nil
	bank[player] = nil
	profileReady[player] = nil
	dirty[player] = nil
	dailyDay[player] = nil
	dailyStreak[player] = nil
	pendingDaily[player] = nil
	questDayTag[player] = nil
	questDone[player] = nil
	questBanked[player] = nil
	achDone[player] = nil
	achNew[player] = nil
	statsGems[player] = nil
	statsRuns[player] = nil
	statsBestDist[player] = nil
	audioVol[player] = nil
	customHues[player] = nil
	dashModes[player] = nil
	history[player] = nil
	receipts[player] = nil
	-- saveFlying/saveAgain/pendingSnap intentionally NOT cleared: a queued
	-- leave-flush must still drain its captured snapshot after teardown.
end

function ShopService.init()
	-- Pass purchase completed: mark the key owned, auto-equip its items
	-- (bundles) or just bank the perk (bank2x), save.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for key, id in pairs(Config.Monetization.Passes) do
			if id == gamePassId and id > 0 then
				if not owned[player] then
					owned[player] = {}
				end
				if not equipped[player] then
					equipped[player] = Cosmetics.defaults()
				end
				owned[player][key] = true
				equipBundle(player, key)
				pushAttrs(player)
				saveNow(player)
			end
		end
	end)

	-- Dev-product receipts (§18 P2 gem packs): the ONLY ProcessReceipt
	-- handler in the game — it must answer every product id the client can
	-- prompt. Unknown/unfinished work returns NotProcessedYet so Roblox
	-- retries instead of silently eating a purchase.
	--
	-- Grant -> persist -> ACK: PurchaseGranted spends the money and stops
	-- redelivery, so the profile write must have landed before we return
	-- it. The PurchaseId mark lives in profile.receipts and is set BEFORE
	-- the credit so every racing snapshot carries it — dedup survives a
	-- crash or a server hop that pure session memory would lose.
	local seenReceipts = {}
	MarketplaceService.ProcessReceipt = function(receipt)
		local productKey = nil
		for key, id in pairs(Config.Monetization.Products) do
			if id > 0 and id == receipt.ProductId then
				productKey = key
			end
		end
		if not productKey then
			warn("[RoBall3D] receipt for unconfigured product", receipt.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- grant lands on rejoin
		end
		-- Wait for the profile: granting before it loads would be clobbered
		-- by the stored baseline overwriting the credit.
		local deadline = os.clock() + 10
		while not profileReady[player] and player.Parent ~= nil and os.clock() < deadline do
			task.wait(0.25)
		end
		if not profileReady[player] or player.Parent == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local granted = Config.Monetization.ProductGems[productKey] or 0
		if not seenReceipts[receipt.PurchaseId] and not (receipts[player] or {})[receipt.PurchaseId] then
			if not receipts[player] then
				receipts[player] = {}
			end
			receipts[player][receipt.PurchaseId] = true
			seenReceipts[receipt.PurchaseId] = true
			bank[player] = (bank[player] or 0) + granted
			player:SetAttribute("RoBallBank", bank[player])
			print("[RoBall3D] gem pack", productKey, "+", granted, "->", player.Name)
		end
		-- The credit is live in-session either way; the ack only means
		-- "the write landed". Session-marked retries still re-drive the
		-- durable write so a redelivery can't be acked on memory alone.
		if saveNowSync(player) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Players.PlayerRemoving:Connect(function(player)
		ShopService.onPlayerRemoving(player)
	end)
end

return ShopService
