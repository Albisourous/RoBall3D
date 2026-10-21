--!strict
-- Cosmetics catalog (DESIGN.md §18): every purchasable look is a data
-- record here — a new skin/trail/fx is config, not code. Items group into
-- themed bundle gamepasses; pass ids live in Config.Monetization.Passes
-- (0 = not created yet -> shop shows SOON). Every non-free item also
-- carries gemPrice — the grind path: banked gems buy items one at a time
-- while bundle passes remain the priced shortcut (à-la-carte totals sit
-- well above the pass, so the bundle stays the deal).
--
-- COLOR LAW: nothing here may approach LethalColor (255,32,48). Vaporwave
-- family + gold + sun-orange + mono only — red stays lethal.

local Palette = require(script.Parent.Palette)

local Cosmetics = {}

export type Slot = "skin" | "trail" | "gemFx" | "deathFx" | "world"

Cosmetics.Slots = { "skin", "trail", "gemFx", "deathFx", "world" } :: { Slot }
Cosmetics.SlotName = {
	skin = "SKIN",
	trail = "TRAIL",
	gemFx = "GEM FX",
	deathFx = "DEATH FX",
	world = "WORLD",
} :: { [Slot]: string }

-- Per-slot params:
--   skin:    ringA/ringB ring colors, core ball face, fx "rainbow"|"pulse"
--            (client-animated in the render loop — CosmeticFx)
--   trail:   color = Color3 | "palette" (samples the run wheel) | "rainbow"
--   gemFx:   color = Color3 | "rainbow" (per-burst hue cycle)
--   deathFx: style "pop"|"shatter"|"nova"|"implode", colorA/colorB accents
--   world:   theme "city"|"peaks" — picks the side scenery Backdrop draws
export type Item = {
	slot: Slot,
	name: string,
	free: boolean?,
	gemPrice: number?, -- banked-gem price (§18 P2); nil = pass-only record
	ringA: Color3?,
	ringB: Color3?,
	core: Color3?,
	fx: string?,
	color: (Color3 | string)?,
	style: string?,
	colorA: Color3?,
	colorB: Color3?,
	theme: string?,
}

local CYAN = Color3.fromRGB(0, 230, 255)
local MAGENTA = Color3.fromRGB(255, 64, 190)
local PINK = Color3.fromRGB(255, 46, 160)
local GOLD = Color3.fromRGB(255, 212, 64)
local PALE_GOLD = Color3.fromRGB(255, 240, 170)
local ORANGE = Color3.fromRGB(255, 176, 64)
local SUNSET = Color3.fromRGB(255, 140, 60)
local VIOLET = Color3.fromRGB(175, 80, 255)
local UV = Color3.fromRGB(180, 90, 255)
local AMETHYST = Color3.fromRGB(190, 120, 255)
local WHITE = Color3.fromRGB(245, 238, 255)
local SILVER = Color3.fromRGB(140, 150, 190)
local AURORA_G = Color3.fromRGB(80, 255, 170) -- teal-green (the unused family)
local AURORA_B = Color3.fromRGB(80, 180, 255)
local PALE_VIOLET = Color3.fromRGB(210, 200, 255)

Cosmetics.Items = {
	--==== SKIN — 3 axial rings (ringA) + 2 diagonals (ringB), core = ball face
	skin_classic = {
		slot = "skin",
		name = "CLASSIC NEON",
		free = true,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
	},
	skin_mono = {
		slot = "skin",
		name = "MONO",
		free = true,
		ringA = WHITE,
		ringB = SILVER,
		core = Color3.fromRGB(8, 8, 12),
	},
	skin_solar = {
		slot = "skin",
		name = "SOLAR FLARE",
		gemPrice = 300,
		ringA = ORANGE,
		ringB = PINK,
		core = Color3.fromRGB(24, 8, 4),
	},
	skin_midas = {
		slot = "skin",
		name = "24K",
		gemPrice = 750,
		ringA = GOLD,
		ringB = PALE_GOLD,
		core = Color3.fromRGB(26, 16, 4),
	},
	skin_prism = {
		slot = "skin",
		name = "PRISM",
		gemPrice = 750,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
		fx = "rainbow",
	},
	skin_void = {
		slot = "skin",
		name = "VOID EMPRESS",
		gemPrice = 900,
		ringA = VIOLET,
		ringB = PINK,
		core = Color3.fromRGB(2, 0, 6),
		fx = "pulse",
	},
	skin_aurora = {
		slot = "skin",
		name = "AURORA",
		gemPrice = 800,
		ringA = AURORA_G,
		ringB = AURORA_B,
		core = Color3.fromRGB(4, 14, 10),
	},
	skin_phantom = {
		slot = "skin",
		name = "PHANTOM",
		gemPrice = 900,
		ringA = WHITE,
		ringB = AMETHYST,
		core = Color3.fromRGB(6, 4, 12),
		fx = "pulse",
	},

	--==== TRAIL — slim wake ribbon behind the ball
	trail_magenta = { slot = "trail", name = "PALETTE WAKE", free = true, color = "palette" },
	trail_ion = { slot = "trail", name = "ION", free = true, color = CYAN },
	trail_sunset = { slot = "trail", name = "SUNSET", gemPrice = 200, color = SUNSET },
	trail_bullion = { slot = "trail", name = "BULLION", gemPrice = 400, color = GOLD },
	trail_prism = { slot = "trail", name = "PRISM", gemPrice = 400, color = "rainbow" },
	trail_uv = { slot = "trail", name = "ULTRAVIOLET", gemPrice = 500, color = UV },
	trail_aurora = { slot = "trail", name = "AURORA WAKE", gemPrice = 450, color = AURORA_G },
	trail_spectre = { slot = "trail", name = "SPECTRE", gemPrice = 500, color = PALE_VIOLET },

	--==== GEM FX — the pickup flourish (pop diamond + sparkles + ring)
	gemfx_gold = { slot = "gemFx", name = "GOLD POP", free = true, color = GOLD },
	gemfx_cold = { slot = "gemFx", name = "COLD POP", free = true, color = CYAN },
	gemfx_sunset = { slot = "gemFx", name = "SUNSET POP", gemPrice = 200, color = SUNSET },
	gemfx_jackpot = { slot = "gemFx", name = "JACKPOT", gemPrice = 400, color = PALE_GOLD },
	gemfx_prism = { slot = "gemFx", name = "PRISM POP", gemPrice = 400, color = "rainbow" },
	gemfx_amethyst = { slot = "gemFx", name = "AMETHYST", gemPrice = 500, color = AMETHYST },
	gemfx_aurora = { slot = "gemFx", name = "AURORA POP", gemPrice = 450, color = AURORA_G },
	gemfx_spectre = { slot = "gemFx", name = "SPECTRE POP", gemPrice = 500, color = PALE_VIOLET },

	--==== DEATH FX — burst at the last ball position on run end
	deathfx_shatter = {
		slot = "deathFx",
		name = "SHATTER",
		free = true,
		style = "shatter",
		colorA = CYAN,
		colorB = MAGENTA,
	},
	deathfx_pop = {
		slot = "deathFx",
		name = "WHITEOUT",
		free = true,
		style = "pop",
		colorA = WHITE,
		colorB = CYAN,
	},
	deathfx_nova = {
		slot = "deathFx",
		name = "SUPERNOVA",
		gemPrice = 500,
		style = "nova",
		colorA = PINK,
		colorB = ORANGE,
	},
	deathfx_implode = {
		slot = "deathFx",
		name = "COLLAPSE",
		gemPrice = 500,
		style = "implode",
		colorA = GOLD,
		colorB = PALE_GOLD,
	},
	deathfx_horizon = {
		slot = "deathFx",
		name = "EVENT HORIZON",
		gemPrice = 600,
		style = "implode",
		colorA = VIOLET,
		colorB = PINK,
	},
	deathfx_borealis = {
		slot = "deathFx",
		name = "BOREALIS",
		gemPrice = 600,
		style = "nova",
		colorA = AURORA_G,
		colorB = AURORA_B,
	},
	deathfx_static = {
		slot = "deathFx",
		name = "STATIC",
		gemPrice = 650,
		style = "shatter",
		colorA = WHITE,
		colorB = AMETHYST,
	},

	--==== WORLD — the whole side-scenery theme (Backdrop.luau renders it)
	world_city = { slot = "world", name = "NEON CITY", free = true, theme = "city" },
	world_peaks = { slot = "world", name = "NEON PEAKS", gemPrice = 800, theme = "peaks" },
	world_void = { slot = "world", name = "STAR WELL", gemPrice = 800, theme = "void" },
	world_grid = { slot = "world", name = "GRID PLANE", gemPrice = 800, theme = "grid" },
} :: { [string]: Item }

-- Equip-cycle order in the garage (matches the table above).
Cosmetics.Order = {
	skin = {
		"skin_classic",
		"skin_mono",
		"skin_solar",
		"skin_midas",
		"skin_prism",
		"skin_void",
		"skin_aurora",
		"skin_phantom",
	},
	trail = {
		"trail_magenta",
		"trail_ion",
		"trail_sunset",
		"trail_bullion",
		"trail_prism",
		"trail_uv",
		"trail_aurora",
		"trail_spectre",
	},
	gemFx = {
		"gemfx_gold",
		"gemfx_cold",
		"gemfx_sunset",
		"gemfx_jackpot",
		"gemfx_prism",
		"gemfx_amethyst",
		"gemfx_aurora",
		"gemfx_spectre",
	},
	deathFx = {
		"deathfx_shatter",
		"deathfx_pop",
		"deathfx_nova",
		"deathfx_implode",
		"deathfx_horizon",
		"deathfx_borealis",
		"deathfx_static",
	},
	world = { "world_city", "world_peaks", "world_void", "world_grid" },
} :: { [string]: { string } }

Cosmetics.Defaults = {
	skin = "skin_classic",
	trail = "trail_magenta",
	gemFx = "gemfx_gold",
	deathFx = "deathfx_shatter",
	world = "world_city",
} :: { [string]: string }

-- Themed bundle gamepasses (§18): one pass = a matched set across slots.
-- `id` is the pass key into Config.Monetization.Passes / .Price.
Cosmetics.Bundles = {
	{
		id = "starter",
		name = "STARTER NEON",
		desc = "solar skin · sunset trail + pop",
		items = { "skin_solar", "trail_sunset", "gemfx_sunset" },
	},
	{
		id = "synthwave",
		name = "SYNTHWAVE",
		desc = "prism set · supernova death",
		items = { "skin_prism", "trail_prism", "gemfx_prism", "deathfx_nova" },
	},
	{
		id = "midas",
		name = "MIDAS",
		desc = "24k set · collapse death",
		items = { "skin_midas", "trail_bullion", "gemfx_jackpot", "deathfx_implode" },
	},
	{
		id = "vip",
		name = "VOID VIP",
		desc = "void set · event horizon",
		items = { "skin_void", "trail_uv", "gemfx_amethyst", "deathfx_horizon" },
	},
	{
		id = "peaks",
		name = "NEON PEAKS",
		desc = "wireframe ridge world",
		items = { "world_peaks" },
	},
	{
		id = "aurora",
		name = "AURORA",
		desc = "green-polar set · borealis death",
		items = { "skin_aurora", "trail_aurora", "gemfx_aurora", "deathfx_borealis" },
	},
	{
		id = "phantom",
		name = "PHANTOM",
		desc = "ghost-mono set · static death",
		items = { "skin_phantom", "trail_spectre", "gemfx_spectre", "deathfx_static" },
	},
	{
		id = "deepspace",
		name = "DEEP SPACE",
		desc = "star well + grid plane worlds",
		items = { "world_void", "world_grid" },
	},
}

-- itemId -> bundle id, built once at require time.
local bundleIndex: { [string]: string } = {}
for _, b in ipairs(Cosmetics.Bundles) do
	for _, id in ipairs(b.items) do
		bundleIndex[id] = b.id
	end
end

function Cosmetics.item(id: string?): Item?
	return if id then Cosmetics.Items[id] else nil
end

function Cosmetics.defaults(): { [string]: string }
	return {
		skin = Cosmetics.Defaults.skin,
		trail = Cosmetics.Defaults.trail,
		gemFx = Cosmetics.Defaults.gemFx,
		deathFx = Cosmetics.Defaults.deathFx,
		world = Cosmetics.Defaults.world,
	}
end

function Cosmetics.bundleOf(itemId: string): string?
	return bundleIndex[itemId]
end

-- Does `owned` cover this item? The set mixes bundle keys (pass ownership)
-- with item ids (gem purchases, §18 P2) — they can't collide. Free items
-- always pass.
function Cosmetics.owns(owned: { [string]: boolean }, itemId: string): boolean
	local item = Cosmetics.Items[itemId]
	if not item then
		return false
	end
	if item.free or owned[itemId] then
		return true
	end
	local b = bundleIndex[itemId]
	return b ~= nil and owned[b] == true
end

-- Resolve a color param to a Color3: Color3 passthrough, "palette" samples
-- the run wheel at 0 (the magenta the default trail uses), "rainbow" is a
-- slow time-cycled hue. Anything else falls back.
function Cosmetics.colorOf(param: any, fallback: Color3?): Color3
	if typeof(param) == "Color3" then
		return param
	end
	if param == "rainbow" then
		return Color3.fromHSV((tick() * 0.3) % 1, 0.9, 1)
	end
	if param == "palette" or fallback == nil then
		return Palette.neonAt(0)
	end
	return fallback
end

return Cosmetics
