--!strict
-- ShopService (DESIGN.md §18): ownership + equip state for cosmetics.
-- Gamepasses are the source of truth for ownership (queried live, cached
-- per session — never stored); the profile DataStore only persists which
-- item ids are equipped. State mirrors onto player attributes so the
-- client garage/FX read it without a fetch remote:
--   RoBallEq_<slot>  -> equipped item id ("skin"/"trail"/"gemFx"/"deathFx")
--   RoBallOwned      -> CSV of owned bundle keys
-- Studio: pass ids are 0 until created on the dashboard, so nothing is
-- ownable and free items still equip — the system degrades cleanly.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local SaveService = require(script.Parent.SaveService)

local ShopService = {}

local owned: { [Player]: { [string]: boolean } } = {} -- bundle key -> true
local equipped: { [Player]: { [string]: string } } = {} -- slot -> itemId

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
	local b = Cosmetics.bundleOf(itemId)
	return b ~= nil and ShopService.ownsPass(player, b)
end

function ShopService.equipped(player: Player): { [string]: string }
	return equipped[player] or Cosmetics.defaults()
end

-- Mirror state onto attributes: per-slot equipped ids + owned bundle CSV.
local function pushAttrs(player: Player)
	local eq = ShopService.equipped(player)
	for _, slot in ipairs(Cosmetics.Slots) do
		player:SetAttribute("RoBallEq_" .. slot, eq[slot])
	end
	local list = {}
	for key in pairs(owned[player] or {}) do
		table.insert(list, key)
	end
	table.sort(list)
	player:SetAttribute("RoBallOwned", table.concat(list, ","))
end

local function saveProfile(player: Player)
	local eq = equipped[player]
	if eq then
		task.spawn(function()
			SaveService.saveProfile(player.UserId, { equipped = eq })
		end)
	end
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
-- look lands immediately, no manual trip to the garage required.
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
	saveProfile(player)
	return true
end

function ShopService.onPlayerAdded(player: Player)
	owned[player] = {}
	equipped[player] = Cosmetics.defaults()
	task.spawn(function()
		local eq = equipped[player]
		local prof = SaveService.loadProfile(player.UserId)
		if prof and typeof(prof.equipped) == "table" then
			for slot, id in pairs(prof.equipped) do
				local item = Cosmetics.Items[id]
				-- Only fill slots still at default: a purchase that landed
				-- during the async load must not be clobbered.
				if item and item.slot == slot and eq[slot] == Cosmetics.Defaults[slot] then
					eq[slot] = id
				end
			end
		end
		queryPasses(player)
		-- Strip equipped items the player can't own (e.g. refunded pass).
		for slot, id in pairs(eq) do
			if not ShopService.ownsItem(player, id) then
				eq[slot] = Cosmetics.Defaults[slot]
			end
		end
		pushAttrs(player)
	end)
end

function ShopService.onPlayerRemoving(player: Player)
	saveProfile(player)
	owned[player] = nil
	equipped[player] = nil
end

function ShopService.init()
	-- Purchase completed: mark the bundle owned, auto-equip its items, save.
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
				saveProfile(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ShopService.onPlayerRemoving(player)
	end)
end

return ShopService
