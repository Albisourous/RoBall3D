--!strict
-- Persistence (DESIGN.md §14): personal best in a DataStore, global top runs
-- in an OrderedDataStore, plus a meta store so leaderboard rows can show the
-- seed the score was earned on. Everything degrades gracefully when Studio
-- API access is off — the run loop never depends on a save.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)

local SaveService = {}

local bestStore: DataStore? = nil
local topStore: OrderedDataStore? = nil
local metaStore: DataStore? = nil
local profileStore: DataStore? = nil

-- DataStores can throw in Studio without API access; probe once, then all
-- calls become cheap no-ops.
local enabled = RunService:IsStudio() == false
local probed = false

local function ensureStores(): boolean
	if probed then
		return enabled
	end
	probed = true
	local ok, err = pcall(function()
		bestStore = DataStoreService:GetDataStore(Config.Leaderboard.BestStore)
		topStore = DataStoreService:GetOrderedDataStore(Config.Leaderboard.TopRunsStore)
		metaStore = DataStoreService:GetDataStore(Config.Leaderboard.TopRunsStore .. "_Meta")
		profileStore = DataStoreService:GetDataStore(Config.Leaderboard.ProfileStore)
		-- A real read, not just handle creation — proves API access works.
		if bestStore then
			bestStore:GetAsync("__probe__")
		end
	end)
	enabled = ok
	if not ok then
		warn("[RoBall3D] DataStores unavailable (enable Studio API access for saves):", err)
	end
	return enabled
end

-- Personal best: {score, dist, seed}. Returns stored table or nil.
function SaveService.loadBest(userId: number): { score: number, dist: number, seed: number }?
	if not ensureStores() or not bestStore then
		return nil
	end
	local ok, data = pcall(function()
		return (bestStore :: DataStore):GetAsync("u" .. userId)
	end)
	if ok and typeof(data) == "table" then
		return data
	end
	return nil
end

function SaveService.saveBest(userId: number, best: { score: number, dist: number, seed: number })
	if not ensureStores() or not bestStore then
		return
	end
	pcall(function()
		(bestStore :: DataStore):UpdateAsync("u" .. userId, function(old)
			if typeof(old) == "table" and typeof(old.score) == "number" and old.score >= best.score then
				return nil -- stored best is better; keep it
			end
			return best
		end)
	end)
end

-- Cosmetic profile (§18): equipped item ids per slot only — pass ownership
-- is derived live from MarketplaceService, never stored.
function SaveService.loadProfile(userId: number): { equipped: { [string]: string } }?
	if not ensureStores() or not profileStore then
		return nil
	end
	local ok, data = pcall(function()
		return (profileStore :: DataStore):GetAsync("u" .. userId)
	end)
	if ok and typeof(data) == "table" then
		return data
	end
	return nil
end

function SaveService.saveProfile(userId: number, profile: { equipped: { [string]: string } })
	if not ensureStores() or not profileStore then
		return
	end
	pcall(function()
		(profileStore :: DataStore):SetAsync("u" .. userId, profile)
	end)
end

-- Submit to the global top board (score only) + meta row (seed for display).
function SaveService.submitTop(userId: number, score: number, seed: number)
	if not ensureStores() then
		return
	end
	if topStore then
		pcall(function()
			local key = "u" .. userId
			local old = (topStore :: OrderedDataStore):GetAsync(key)
			if typeof(old) ~= "number" or score > old then
				(topStore :: OrderedDataStore):SetAsync(key, score)
				if metaStore then
					-- Meta tracks the run that SET the top score — writing it
					-- unconditionally would pair a best with a later run's
					-- seed. `assisted` (§18): advantage items submit to a
					-- separate board so clean/assisted never mix.
					(metaStore :: DataStore):SetAsync(key, { seed = seed, score = score, assisted = false })
				end
			end
		end)
	end
end

-- Top rows for the menu: { {name, score, seed}, ... }. Name lookup per entry.
-- Returns nil when stores are unreachable — nil means OFFLINE (the client
-- shows "leaderboard offline"), while {} means a real but empty board.
function SaveService.getTop(count: number): { { name: string, score: number, seed: number } }?
	if not ensureStores() or not topStore then
		return nil
	end
	local ok, pages = pcall(function()
		return (topStore :: OrderedDataStore):GetSortedAsync(false, math.clamp(count, 1, 100))
	end)
	if not ok or not pages then
		return nil
	end
	-- Name + meta lookups yield; run all rows in parallel so a 20-entry
	-- board doesn't serialize ~40 datastore/name calls.
	local entries = pages:GetCurrentPage()
	local rows: { { name: string, score: number, seed: number }? } = table.create(#entries)
	local remaining = #entries
	for i, entry in ipairs(entries) do
		task.spawn(function()
			local userId = tonumber((entry.key :: string):sub(2)) or 0
			local name = "player" .. userId
			pcall(function()
				name = Players:GetNameFromUserIdAsync(userId)
			end)
			local seed = 0
			if metaStore then
				pcall(function()
					local meta = (metaStore :: DataStore):GetAsync("u" .. userId)
					if typeof(meta) == "table" and typeof(meta.seed) == "number" then
						seed = meta.seed
					end
				end)
			end
			rows[i] = { name = name, score = entry.value, seed = seed }
			remaining -= 1
		end)
	end
	while remaining > 0 do
		task.wait()
	end
	return rows :: { { name: string, score: number, seed: number } }
end

return SaveService
