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
local Daily = require(ReplicatedStorage.RoBall.Daily)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)

local SaveService = {}

local bestStore: DataStore? = nil
local topStore: OrderedDataStore? = nil
local metaStore: DataStore? = nil
local profileStore: DataStore? = nil
local ghostStore: DataStore? = nil -- PB-run replay frames, per userId (§14)
local champStore: DataStore? = nil -- seed record holder's replay, per seed (§14)

-- Per-day daily-board handles, memoized — a new day tag just means a new
-- OrderedDataStore name; yesterday's store is simply never read again.
local dailyStores: { [string]: OrderedDataStore } = {}
local dailyMetaStores: { [string]: DataStore } = {}

-- DataStores can throw without API access; probe once with a real read. On
-- failure, re-probe after a cooldown — a boot-time backend hiccup shouldn't
-- kill saves for the server's whole lifetime.
local probed = false
local enabled = false
local nextProbeAt = 0
local probeInFlight = false
local REPROBE_SECONDS = 60

local function ensureStores(): boolean
	if probed and (enabled or os.clock() < nextProbeAt) then
		return enabled
	end
	if probeInFlight then
		-- A probe yields on GetAsync; callers arriving mid-flight would stack
		-- parallel probes and all wedge on a hung backend. Wait briefly, then
		-- treat the shared result as authoritative either way.
		local deadline = os.clock() + 10
		while probeInFlight and os.clock() < deadline do
			task.wait(0.1)
		end
		return enabled
	end
	probeInFlight = true
	probed = true
	local ok, err = pcall(function()
		bestStore = DataStoreService:GetDataStore(Config.Leaderboard.BestStore)
		topStore = DataStoreService:GetOrderedDataStore(Config.Leaderboard.TopRunsStore)
		metaStore = DataStoreService:GetDataStore(Config.Leaderboard.TopRunsStore .. "_Meta")
		profileStore = DataStoreService:GetDataStore(Config.Leaderboard.ProfileStore)
		ghostStore = DataStoreService:GetDataStore(Config.Ghost.Store)
		champStore = DataStoreService:GetDataStore(Config.Ghost.ChampStore)
		-- A real read, not just handle creation — proves API access works.
		if bestStore then
			bestStore:GetAsync("__probe__")
		end
	end)
	enabled = ok
	probeInFlight = false
	if not ok then
		nextProbeAt = os.clock() + REPROBE_SECONDS
		warn("[RoBall3D] DataStores unavailable (enable Studio API access for saves):", err)
	end
	return enabled
end

-- Transient backend errors are common enough that a one-shot pcall loses real
-- saves. Exponential backoff (1s, 2s, 4s, capped); UpdateAsync's internal CAS
-- retry is separate from this.
local function retry(label: string, fn: () -> ()): boolean
	local tries = math.max(1, Config.Leaderboard.SaveRetryCount)
	for i = 1, tries do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		if i < tries then
			task.wait(math.min(2 ^ (i - 1), 8))
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
	-- Daily streak (§14): last UTC day-tag a daily-seeded run counted, and
	-- the consecutive-day total. Updated only by ShopService.recordDailyRun.
	dailyDay: string?,
	dailyStreak: number?,
	-- Daily quests (§14): the day-tag the quest slots belong to, the done
	-- set (quest ids), and gems banked toward today's bank-quest.
	questDay: string?,
	questDone: { string }?,
	questBanked: number?,
	-- Achievements (§14): unlocked ids + the lifetime stats they check
	-- against. stats are append-only counters; unlocks never roll back.
	achievements: { string }?,
	statsGems: number?,
	statsRuns: number?,
	statsBestDist: number?,
	-- Audio mixer (AUDIO.md §7): per-channel gains 0..1 keyed by
	-- Config.Audio.Channels — the menu AUDIO panel's saved state.
	audio: { [string]: number }?,
	-- COLOR LAB (§18): custom hue channels a/b/c (0..1, band-clamped) for
	-- the customA/B/C cosmetic params. Pure vanity — never gameplay.
	hues: { a: number, b: number, c: number }?,
	-- Dash style (§4): "keys"|"tap" — which input mapping dashes.
	-- A control pref, never gameplay-affecting.
	dashMode: string?,
	-- Recent runs (§14): newest-first { s=score, d=dist, z=seed } entries,
	-- capped at Config.Leaderboard.HistoryCount. Display + replay data.
	history: { { s: number, d: number, z: number } }?,
	-- Dev-product receipts (§18 P2): PurchaseId -> true — durable dedup so
	-- a redelivered receipt on any server can find its mark. Marks are set
	-- before the credit applies, so every snapshot carries them.
	receipts: { [string]: boolean }?,
}

function SaveService.loadProfile(userId: number): Profile?
	if not ensureStores() or not profileStore then
		return nil
	end
	local ok, data = pcall(function()
		-- The profile is the authoritative economy record — a same-server
		-- instant rejoin must not read the ~4s GetAsync cache and then
		-- write a stale baseline over the save that just landed.
		local opts = Instance.new("DataStoreGetOptions")
		opts.UseCache = false
		return (profileStore :: DataStore):GetAsync("u" .. userId, opts)
	end)
	if ok and typeof(data) == "table" then
		return data
	end
	return nil
end

-- Field-merge rules for the profile write (hop-safe): ownership and unlock
-- sets union so concurrent sessions can't lose grants, lifetime counters
-- keep-max, day-tagged streak/quest state goes to the newer tag, and pref
-- fields take the newest writer. `bank` is a spendable balance — not a
-- monotone counter — so it can't merge: the newest snapshot wins it, and
-- the paid-gem path closes its own race by acking only after the write
-- lands (ProcessReceipt → saveNowSync). Every rule is idempotent —
-- UpdateAsync may re-run the transform on CAS contention.
local function mergeProfiles(stored: any, new: Profile): Profile
	local s: { [string]: any } = if typeof(stored) == "table" then stored else {}
	local out: { [string]: any } = {}

	out.equipped = if new.equipped ~= nil then new.equipped else s.equipped
	out.audio = if new.audio ~= nil then new.audio else s.audio
	out.hues = if new.hues ~= nil then new.hues else s.hues
	out.dashMode = if new.dashMode ~= nil then new.dashMode else s.dashMode
	out.bank = if new.bank ~= nil then new.bank else s.bank

	-- Two shapes: receipts is a {PurchaseId -> true} map (keys matter);
	-- items/achievements/questDone are id arrays (values matter).
	local function unionMap(a: any, b: any): { [string]: boolean }
		local set: { [string]: boolean } = {}
		for k in pairs(if typeof(a) == "table" then a else {}) do
			set[k] = true
		end
		for k in pairs(if typeof(b) == "table" then b else {}) do
			set[k] = true
		end
		return set
	end
	local function unionList(a: any, b: any): { string }
		local set: { [string]: boolean } = {}
		for _, v in pairs(if typeof(a) == "table" then a else {}) do
			set[v] = true
		end
		for _, v in pairs(if typeof(b) == "table" then b else {}) do
			set[v] = true
		end
		local list = {}
		for k in pairs(set) do
			table.insert(list, k)
		end
		table.sort(list)
		return list
	end

	out.items = unionList(s.items, new.items)
	out.achievements = unionList(s.achievements, new.achievements)
	out.receipts = unionMap(s.receipts, new.receipts)

	out.statsGems = math.max(if typeof(s.statsGems) == "number" then s.statsGems else 0, new.statsGems or 0)
	out.statsRuns = math.max(if typeof(s.statsRuns) == "number" then s.statsRuns else 0, new.statsRuns or 0)
	out.statsBestDist =
		math.max(if typeof(s.statsBestDist) == "number" then s.statsBestDist else 0, new.statsBestDist or 0)

	-- Day tags are %Y%m%d — fixed-width, so string compare orders them.
	local sDay = if typeof(s.dailyDay) == "string" then s.dailyDay else ""
	local nDay = new.dailyDay or ""
	if nDay >= sDay then
		out.dailyDay = nDay
		out.dailyStreak = math.max(
			if nDay == sDay and typeof(s.dailyStreak) == "number" then s.dailyStreak else 0,
			new.dailyStreak or 0
		)
	else
		out.dailyDay = sDay
		out.dailyStreak = if typeof(s.dailyStreak) == "number" then s.dailyStreak else 0
	end

	local sQDay = if typeof(s.questDay) == "string" then s.questDay else ""
	local nQDay = new.questDay or ""
	if nQDay > sQDay then
		out.questDay = nQDay
		out.questDone = new.questDone or {}
		out.questBanked = new.questBanked or 0
	elseif nQDay == sQDay then
		out.questDay = nQDay
		out.questDone = unionList(s.questDone, new.questDone)
		out.questBanked = math.max(if typeof(s.questBanked) == "number" then s.questBanked else 0, new.questBanked or 0)
	else
		out.questDay = sQDay
		out.questDone = if typeof(s.questDone) == "table" then s.questDone else {}
		out.questBanked = if typeof(s.questBanked) == "number" then s.questBanked else 0
	end

	-- History: union by (s,d,z), newest-session entries first, capped.
	local seen: { [string]: boolean } = {}
	local hist = {}
	local function pushRows(rows: any, clone: boolean)
		for _, r in ipairs(if typeof(rows) == "table" then rows else {}) do
			if
				typeof(r) == "table"
				and typeof(r.s) == "number"
				and typeof(r.d) == "number"
				and typeof(r.z) == "number"
			then
				local k = string.format("%d,%d,%d", r.s, r.d, r.z)
				if not seen[k] then
					seen[k] = true
					table.insert(hist, if clone then { s = r.s, d = r.d, z = r.z } else r)
				end
			end
		end
	end
	pushRows(new.history, false)
	pushRows(s.history, true)
	while #hist > Config.Leaderboard.HistoryCount do
		table.remove(hist)
	end
	out.history = hist

	return out :: Profile
end

function SaveService.saveProfile(userId: number, profile: Profile)
	SaveService.saveProfileSync(userId, profile)
end

-- The awaited variant: callers that must know the write landed before
-- answering (dev-product receipts) use this instead of fire-and-forget.
function SaveService.saveProfileSync(userId: number, profile: Profile): boolean
	if not ensureStores() or not profileStore then
		return false
	end
	return retry("saveProfile", function()
		(profileStore :: DataStore):UpdateAsync("u" .. userId, function(old)
			return mergeProfiles(old, profile)
		end)
	end)
end

-- PB ghost (§14): the record run's position frames — {s = seed, f = csv}
-- where the csv is "t,x,y,z;t,x,y,z;..." in hundredths/tenths. One ghost
-- per player (the PB's), overwritten only when the PB falls. Cosmetic
-- data: a corrupt load just means no echo, never a run dependency.
function SaveService.loadGhost(userId: number): { s: number, f: string }?
	if not ensureStores() or not ghostStore then
		return nil
	end
	local value = nil
	retry("loadGhost", function()
		value = (ghostStore :: DataStore):GetAsync("u" .. userId)
	end)
	if typeof(value) == "table" and typeof(value.s) == "number" and typeof(value.f) == "string" then
		return value
	end
	return nil
end

function SaveService.saveGhost(userId: number, seed: number, csv: string)
	if not ensureStores() or not ghostStore then
		return
	end
	retry("saveGhost", function()
		(ghostStore :: DataStore):SetAsync("u" .. userId, { s = seed, f = csv })
	end)
end

-- Champion ghost (§14): the best run on a seed, keyed "s<seed>" — any
-- player who starts that seed gets the record holder's replay as a rival
-- echo. The stored value is a podium `{c, r}` — the seed's #2 replay
-- rides the daily run as a silver crowd echo (§14). crownChampion
-- merges inside UpdateAsync so near-simultaneous records can't tear; a
-- tie keeps the earlier holder (first to the score holds the seat), and
-- a player never occupies both seats at once.
export type Champ = { n: string, s: number, u: number, f: string }
export type Podium = { c: Champ?, r: Champ? }

-- v1 rows were a bare Champ `{n,s,u,f}` — read through this so old keys
-- still load, and writes always land the podium shape.
local function asPodium(raw: any): Podium?
	if raw == nil then
		return nil
	end
	if raw.n ~= nil then
		return { c = raw :: Champ }
	end
	return raw :: Podium
end

function SaveService.loadPodium(seed: number): Podium?
	if not ensureStores() or not champStore then
		return nil
	end
	local value: Podium? = nil
	retry("loadPodium", function()
		value = asPodium((champStore :: DataStore):GetAsync("s" .. seed))
	end)
	return value
end

function SaveService.crownChampion(seed: number, userId: number, name: string, score: number, csv: string)
	if not ensureStores() or not champStore then
		return
	end
	retry("crownChampion", function()
		(champStore :: DataStore):UpdateAsync("s" .. seed, function(raw: any)
			local old = asPodium(raw)
			local c = old and old.c
			local r = old and old.r
			local shot: Champ = { n = name, s = score, u = userId, f = csv }
			if c and c.u == userId then
				if c.s >= score then
					return nil -- own crown stands; UpdateAsync treats nil as "no write"
				end
				return { c = shot, r = r }
			end
			if r and r.u == userId then
				if c == nil or score > c.s then
					return { c = shot, r = c } -- silver seat takes the crown
				end
				if r.s >= score then
					return nil
				end
				return { c = c, r = shot }
			end
			if c == nil or score > c.s then
				return { c = shot, r = c } -- dethroned champion slides to silver
			end
			if r == nil or score > r.s then
				return { c = c, r = shot }
			end
			return nil
		end)
	end)
end

type TopRow = { name: string, score: number, seed: number, userId: number? }
local topCache: { rows: { TopRow }, count: number, at: number }? = nil
local dailyCache: { tag: string, rows: { TopRow }, count: number, at: number }? = nil
local fetchBusy = false
local dailyFetchBusy = false
local nameCache: { [number]: string } = {}

-- Daily-board handles for a day tag, created lazily and cached — handles are
-- cheap and the tag rolls at UTC midnight on its own.
local function dailyStore(tag: string): (OrderedDataStore?, DataStore?)
	if not ensureStores() then
		return nil, nil
	end
	local store = dailyStores[tag]
	local meta = dailyMetaStores[tag]
	if not store or not meta then
		local ok = pcall(function()
			store = DataStoreService:GetOrderedDataStore(Config.Leaderboard.DailyStorePrefix .. tag)
			meta = DataStoreService:GetDataStore(Config.Leaderboard.DailyStorePrefix .. tag .. "_Meta")
		end)
		if not ok or not store or not meta then
			return nil, nil
		end
		dailyStores[tag] = store
		dailyMetaStores[tag] = meta
	end
	return store, meta
end

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
			(metaStore :: DataStore):SetAsync("u" .. userId, {
				seed = seed,
				score = score,
				trackId = SongMap.trackIdFor(seed, Config.Music.ActiveTracklist),
				assisted = false,
			})
		end)
	end
end

-- Name + meta lookups yield; run all rows in parallel so a 20-entry
-- board doesn't serialize ~40 datastore/name calls. The join has a hard
-- deadline: one hung lookup must not stall the RemoteFunction forever.
local function rowsFromPages(entries: { { key: string, value: any } }, meta: DataStore?): { TopRow }
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
			if meta then
				pcall(function()
					local m = (meta :: DataStore):GetAsync("u" .. userId)
					if typeof(m) == "table" and typeof(m.seed) == "number" then
						seed = m.seed
					end
				end)
			end
			-- userId rides along for the menu's friends filter — the
			-- leaderboard UI otherwise shows name/score/seed.
			rows[i] = { name = name, score = entry.value, seed = seed, userId = userId }
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
	return rows :: { TopRow }
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
	local done = rowsFromPages((pages :: DataStorePages):GetCurrentPage(), metaStore)
	topCache = { rows = done, count = count, at = os.clock() }
	return done
end

-- Daily board (§14): submitTop equivalent against today's store. Same
-- keep-max UpdateAsync shape; Main only calls it when the run's seed is
-- today's daily seed.
function SaveService.submitDaily(userId: number, score: number)
	local tag = Daily.dayTag()
	local store, meta = dailyStore(tag)
	if not store then
		return
	end
	local won = false
	local ok = retry("submitDaily", function()
		(store :: OrderedDataStore):UpdateAsync("u" .. userId, function(old)
			won = typeof(old) ~= "number" or score > old
			return if won then score else nil
		end)
	end)
	if not ok or not won then
		return
	end
	dailyCache = nil
	if meta then
		local seed = Daily.seed()
		retry("submitDaily meta", function()
			(meta :: DataStore):SetAsync("u" .. userId, {
				seed = seed,
				score = score,
				trackId = SongMap.trackIdFor(seed, Config.Music.ActiveTracklist),
			})
		end)
	end
end

-- The player's 1-based slot on the all-time board, nil when off-board or
-- the stores are down. Called right after submitTop — a real write drops
-- topCache so this read is fresh.
function SaveService.topRank(userId: number): number?
	local rows = SaveService.getTop(Config.Leaderboard.TopCount)
	if not rows then
		return nil
	end
	for i, row in ipairs(rows) do
		if row.userId == userId then
			return i
		end
	end
	return nil
end

-- The player's 1-based slot on today's board, nil when off-board or the
-- stores are down. Called right after submitDaily — a real write drops
-- dailyCache so this read is fresh, and the rank is only meaningful
-- inside the TopCount window the menu shows anyway.
function SaveService.dailyRank(userId: number): number?
	local rows = SaveService.getDailyTop(Config.Leaderboard.TopCount)
	if not rows then
		return nil
	end
	for i, row in ipairs(rows) do
		if row.userId == userId then
			return i
		end
	end
	return nil
end

-- Today's daily rows. `staleOnly`/fetchBusy mirror getTop; the cache keys on
-- the day tag so a post-midnight fetch can't serve yesterday's board.
function SaveService.getDailyTop(count: number, staleOnly: boolean?): { TopRow }?
	local tag = Daily.dayTag()
	local store, meta = dailyStore(tag)
	if not store then
		return nil
	end
	count = math.clamp(count, 1, 100)
	local cache = dailyCache
	if
		cache
		and cache.tag == tag
		and count <= cache.count
		and (staleOnly or os.clock() - cache.at < Config.Leaderboard.CacheSeconds)
	then
		local rows: { TopRow } = {}
		for i = 1, math.min(count, #cache.rows) do
			rows[i] = cache.rows[i]
		end
		return rows
	end
	if staleOnly or dailyFetchBusy then
		return nil
	end
	dailyFetchBusy = true
	local pages: DataStorePages? = nil
	retry("getDailyTop", function()
		pages = (store :: OrderedDataStore):GetSortedAsync(false, count)
	end)
	dailyFetchBusy = false
	if not pages then
		return nil
	end
	local done = rowsFromPages((pages :: DataStorePages):GetCurrentPage(), meta)
	dailyCache = { tag = tag, rows = done, count = count, at = os.clock() }
	return done
end

return SaveService
