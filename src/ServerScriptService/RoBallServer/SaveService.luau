--!strict
-- Persistence (DESIGN.md §14): personal best in a DataStore, global top runs
-- in an OrderedDataStore, plus a meta store so leaderboard rows can show the
-- seed the score was earned on. Everything degrades gracefully when Studio
-- API access is off — the run loop never depends on a save.
--
-- Production guards: writes retry with backoff (SaveRetryCount), the
-- top-board read is cached server-side (CacheSeconds) so menu spam can't
-- drain the DataStore budget, and a failed boot probe re-tries lazily rather
-- than latching the server offline for its whole lifetime.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

local SaveService = {}

local bestStore: DataStore? = nil
local topStore: OrderedDataStore? = nil
local metaStore: DataStore? = nil
local profileStore: DataStore? = nil

-- DataStores can throw without API access; probe once with a real read. On
-- failure, re-probe after a cooldown — a boot-time backend hiccup shouldn't
-- kill saves for the server's whole lifetime.
local probed = false
local enabled = false
local nextProbeAt = 0
local REPROBE_SECONDS = 60

local function ensureStores(): boolean
	if probed and (enabled or os.clock() < nextProbeAt) then
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
		nextProbeAt = os.clock() + REPROBE_SECONDS
		warn("[RoBall3D] DataStores unavailable (enable Studio API access for saves):", err)
	end
	return enabled
end

-- Transient backend errors are common enough that a one-shot pcall loses real
-- saves. Linear backoff (1s, 2s, ...); UpdateAsync's internal CAS retry is
-- separate from this.
local function retry(label: string, fn: () -> ()): boolean
	local tries = math.max(1, Config.Leaderboard.SaveRetryCount)
	for i = 1, tries do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		if i < tries then
			task.wait(i)
		else
			warn(("[RoBall3D] %s failed after %d tries: %s"):format(label, tries, tostring(err)))
		end
	end
	return false
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
	retry("saveBest", function()
		(bestStore :: DataStore):UpdateAsync("u" .. userId, function(old)
			if typeof(old) == "table" and typeof(old.score) == "number" and old.score >= best.score then
				return nil -- stored best is better; keep it
			end
			return best
		end)
	end)
end

-- Cosmetic profile (§18): equipped item ids per slot + the gem bank +
-- item ids bought with gems. Pass ownership is derived live from
-- MarketplaceService, never stored; gem purchases have no platform record
-- so `items` is their source of truth.
export type Profile = {
	equipped: { [string]: string }?,
	bank: number?,
	items: { string }?,
}

function SaveService.loadProfile(userId: number): Profile?
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

function SaveService.saveProfile(userId: number, profile: Profile)
	if not ensureStores() or not profileStore then
		return
	end
	retry("saveProfile", function()
		(profileStore :: DataStore):SetAsync("u" .. userId, profile)
	end)
end

type TopRow = { name: string, score: number, seed: number }
local topCache: { rows: { TopRow }, count: number, at: number }? = nil
local fetchBusy = false
local nameCache: { [number]: string } = {}

-- Submit to the global top board (score only) + meta row (seed for display).
-- UpdateAsync folds read+compare+write into one atomic call — no Get/Set race
-- across servers. `won` flags whether THIS score actually raised the board,
-- so the meta seed always pairs with the run that earned it (§14). A real
-- write also drops the cached board so the next menu fetch shows it.
function SaveService.submitTop(userId: number, score: number, seed: number)
	if not ensureStores() or not topStore then
		return
	end
	local won = false
	local ok = retry("submitTop", function()
		(topStore :: OrderedDataStore):UpdateAsync("u" .. userId, function(old)
			won = typeof(old) ~= "number" or score > old
			return if won then score else nil
		end)
	end)
	if not ok or not won then
		return
	end
	topCache = nil
	if metaStore then
		retry("submitTop meta", function()
			-- Meta tracks the run that SET the top score — writing it
			-- unconditionally would pair a best with a later run's
			-- seed. `assisted` (§18): advantage items submit to a
			-- separate board so clean/assisted never mix.
			(metaStore :: DataStore):SetAsync("u" .. userId, { seed = seed, score = score, assisted = false })
		end)
	end
end

-- Top rows for the menu: { {name, score, seed}, ... }. Name lookup per entry.
-- Returns nil when stores are unreachable — nil means OFFLINE (the client
-- shows "leaderboard offline"), while {} means a real but empty board.
-- `staleOnly` serves the cache regardless of age — the per-player invoke
-- cooldown uses it so a spammed RemoteFunction can't force fresh fetches.
function SaveService.getTop(count: number, staleOnly: boolean?): { TopRow }?
	if not ensureStores() or not topStore then
		return nil
	end
	count = math.clamp(count, 1, 100)
	local cache = topCache
	if cache and count <= cache.count and (staleOnly or os.clock() - cache.at < Config.Leaderboard.CacheSeconds) then
		local rows: { TopRow } = {}
		for i = 1, math.min(count, #cache.rows) do
			rows[i] = cache.rows[i]
		end
		return rows
	end
	if staleOnly or fetchBusy then
		return nil -- throttled caller, or a fetch is already in flight
	end
	fetchBusy = true
	local pages: DataStorePages? = nil
	retry("getTop", function()
		pages = (topStore :: OrderedDataStore):GetSortedAsync(false, count)
	end)
	fetchBusy = false
	if not pages then
		return nil
	end
	-- Name + meta lookups yield; run all rows in parallel so a 20-entry
	-- board doesn't serialize ~40 datastore/name calls. The join has a hard
	-- deadline: one hung lookup must not stall the RemoteFunction forever.
	local entries = (pages :: DataStorePages):GetCurrentPage()
	local rows: { TopRow? } = table.create(#entries)
	local remaining = #entries
	for i, entry in ipairs(entries) do
		task.spawn(function()
			local userId = tonumber((entry.key :: string):sub(2)) or 0
			local name = "player" .. userId
			if nameCache[userId] then
				name = nameCache[userId]
			else
				pcall(function()
					local fetched = Players:GetNameFromUserIdAsync(userId)
					name = fetched
					nameCache[userId] = fetched
				end)
			end
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
	local deadline = os.clock() + 8
	while remaining > 0 and os.clock() < deadline do
		task.wait()
	end
	for i, entry in ipairs(entries) do
		if rows[i] == nil then
			local userId = tonumber((entry.key :: string):sub(2)) or 0
			rows[i] = { name = "player" .. userId, score = entry.value, seed = 0 }
		end
	end
	local done = rows :: { TopRow }
	topCache = { rows = done, count = count, at = os.clock() }
	return done
end

return SaveService
