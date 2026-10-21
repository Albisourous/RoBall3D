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
-- Studio: pass/product ids are 0 until created on the dashboard, so nothing
-- robux-priced exists and free items still equip — the system degrades
-- cleanly. DataStores off in Studio = volatile session bank, still playable.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local SaveService = require(script.Parent.SaveService)

local ShopService = {}

local owned: { [Player]: { [string]: boolean } } = {} -- bundle/perk pass key -> true
local items: { [Player]: { [string]: boolean } } = {} -- gem-purchased itemId -> true
local equipped: { [Player]: { [string]: string } } = {} -- slot -> itemId
local bank: { [Player]: number } = {}
local profileReady: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {} -- bank/items changed since last save

function ShopService.ownsPass(player: Player, key: string): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

function ShopService.ownsItem(player: Player, itemId: string): boolean
	local item = Cosmetics.Items[itemId]
	if not item then
		return false
	end
	if item.free then
		return true
	end
	if items[player] and items[player][itemId] then
		return true
	end
	local b = Cosmetics.bundleOf(itemId)
	return b ~= nil and ShopService.ownsPass(player, b)
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
end

local function itemArray(player: Player): { string }
	local list = {}
	for id in pairs(items[player] or {}) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

local function saveNow(player: Player)
	local eq = equipped[player]
	if not eq then
		return
	end
	dirty[player] = false
	-- Snapshot everything: the spawned save serializes later, and a live
	-- table reference would write whatever state exists at that moment.
	local eqSnapshot = table.clone(eq)
	local bankSnapshot = bank[player] or 0
	local itemsSnapshot = itemArray(player)
	task.spawn(function()
		SaveService.saveProfile(player.UserId, {
			equipped = eqSnapshot,
			bank = bankSnapshot,
			items = itemsSnapshot,
		})
	end)
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
	dirty[player] = true
	player:SetAttribute("RoBallBank", bank[player])
	return credited
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
function ShopService.claimPass(player: Player, key: string): (boolean, string)
	if not Config.Monetization.FreeForTesting then
		return false, "unavailable"
	end
	if Config.Monetization.Passes[key] == nil then
		return false, "unknown pass"
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
		while not profileReady[player] and os.clock() < deadline do
			task.wait(0.25)
		end
		if not profileReady[player] then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local granted = Config.Monetization.ProductGems[productKey] or 0
		ShopService.grantGems(player, granted)
		print("[RoBall3D] gem pack", productKey, "+", granted, "->", player.Name)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	Players.PlayerRemoving:Connect(function(player)
		ShopService.onPlayerRemoving(player)
	end)
end

return ShopService
