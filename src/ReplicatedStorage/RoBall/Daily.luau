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

return Daily
