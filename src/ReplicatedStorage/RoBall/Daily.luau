--!strict
-- Daily seed board (DESIGN.md §14): one seed per UTC day — every player who
-- types "daily" (or accepts the day's seed) runs the identical map, so the
-- daily board is a fair same-map race. Pure module: no Instances, no stores,
-- same answer on every server and client.

local Daily = {}

local DAY_SECONDS = 86400

-- YYYYMMDD tag: store-name suffix, cache key, and the rollover boundary.
function Daily.dayTag(t: number?): string
	return os.date("!%Y%m%d", t or os.time())
end

-- Seconds until next UTC midnight — the board's reset timer.
function Daily.resetIn(t: number?): number
	return DAY_SECONDS - ((t or os.time()) % DAY_SECONDS)
end

-- Same djb2 as Main.server's text-seed hash: the daily seed must equal what
-- resolveSeed produces for the text, so the canonical text is "daily:<tag>".
local function hashSeed(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

function Daily.seed(t: number?): number
	return hashSeed("daily:" .. Daily.dayTag(t))
end

-- Seed strings that resolve to today's seed (server resolveSeed consumes).
function Daily.isKeyword(s: string): boolean
	local l = string.lower(s)
	return l == "daily" or l == "today"
end

-- Weekly cup (§14): same one-seed-per-window trick keyed on Sunday-start
-- weeks. Pure arithmetic, no strftime %U gamble: epoch 1970-01-01 was a
-- Thursday, so `days + 4` shifted by 4 aligns week boundaries to Sundays.
function Daily.weekTag(t: number?): string
	local days = math.floor((t or os.time()) / DAY_SECONDS)
	return "W" .. math.floor((days + 4) / 7)
end

-- Previous week's tag — the lazy top-3 payout reads that board.
function Daily.prevWeekTag(t: number?): string
	local days = math.floor((t or os.time()) / DAY_SECONDS)
	return "W" .. (math.floor((days + 4) / 7) - 1)
end

-- Seconds until next Sunday 00:00 UTC — the cup's reset timer.
function Daily.weekResetIn(t: number?): number
	local now = t or os.time()
	local nextStart = (math.floor((math.floor(now / DAY_SECONDS) + 4) / 7) + 1) * 7 - 4
	return nextStart * DAY_SECONDS - now
end

function Daily.weekSeed(t: number?): number
	return hashSeed("weekly:" .. Daily.weekTag(t))
end

-- Seed strings that resolve to this week's cup seed.
function Daily.isWeekKeyword(s: string): boolean
	local l = string.lower(s)
	return l == "weekly" or l == "week" or l == "cup"
end

-- Seasonal shop slot (§18): a yearly UTC window [Start, End] both days
-- inclusive — Dec 15 → Jan 8 wraps the year boundary. Returns
-- (live, days): live → days left in the window; else → days until the
-- next opening. Pure math — os.time/os.date are UTC in Luau.
local function mdStamp(year: number, md: { number }): number
	return os.time({ year = year, month = md[1], day = md[2], hour = 0 })
end

function Daily.seasonalStatus(t: number?): (boolean, number)
	local Config = require(script.Parent.Config)
	local S = Config.Monetization.Seasonal
	local now = t or os.time()
	local y = tonumber(os.date("!%Y", now)) :: number
	local wraps = mdStamp(2000, S.End) <= mdStamp(2000, S.Start)
	local nearest = math.huge
	-- The candidate windows that can contain `now` start this year or
	-- last; +1 year covers the "next opening" answer for the countdown.
	for sy = y - 1, y + 1 do
		local s = mdStamp(sy, S.Start)
		local e = mdStamp(if wraps then sy + 1 else sy, S.End) + DAY_SECONDS
		if now >= s and now < e then
			return true, math.ceil((e - now) / DAY_SECONDS)
		end
		if now < s then
			nearest = math.min(nearest, s - now)
		end
	end
	return false, math.ceil(nearest / DAY_SECONDS)
end

-- Daily quests (§14): three seeded missions per UTC day. The day's seed
-- picks one target per pool — every player gets the same quests, so the
-- list is pure and identical on client and server (menu lines are drawn
-- client-side, progress arrives via the RoBallQuests attribute).
export type Quest = { id: string, kind: string, target: number, reward: number, text: string }

function Daily.quests(t: number?): { Quest }
	local Config = require(script.Parent.Config)
	local rng = Random.new(Daily.seed(t))
	local pools = Config.Monetization.Quests
	local r = pools.ReachTargets[rng:NextInteger(1, #pools.ReachTargets)]
	local s = pools.ScoreTargets[rng:NextInteger(1, #pools.ScoreTargets)]
	local b = pools.BankTargets[rng:NextInteger(1, #pools.BankTargets)]
	return {
		{
			id = "reach",
			kind = "reach",
			target = r,
			reward = pools.Rewards.reach,
			text = string.format("reach %dm in one run", r),
		},
		{
			id = "score",
			kind = "score",
			target = s,
			reward = pools.Rewards.score,
			text = string.format("score %d in one run", s),
		},
		{
			id = "bank",
			kind = "bank",
			target = b,
			reward = pools.Rewards.bank,
			text = string.format("bank %d gems today", b),
		},
	}
end

return Daily
