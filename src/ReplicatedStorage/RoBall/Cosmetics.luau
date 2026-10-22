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

local Config = require(script.Parent.Config)
local Palette = require(script.Parent.Palette)

local Cosmetics = {}

export type Slot = "skin" | "trail" | "gemFx" | "deathFx" | "world" | "sun" | "filter"

Cosmetics.Slots = { "skin", "world", "trail", "gemFx", "deathFx", "sun", "filter" } :: { Slot }
Cosmetics.SlotName = {
	skin = "SKIN",
	trail = "TRAIL",
	gemFx = "GEM FX",
	deathFx = "DEATH FX",
	world = "WORLD",
	sun = "SUN",
	filter = "FILTER",
} :: { [Slot]: string }

-- Per-slot params:
--   skin:    ringA/ringB ring colors, core ball face, fx
--            "rainbow"|"pulse"|"strobe"|"wave" (client-animated in the
--            render loop — CosmeticFx)
--   trail:   color = Color3 | "palette" (samples the run wheel) | "rainbow"
--   gemFx:   color = Color3 | "rainbow" (per-burst hue cycle)
--   deathFx: style "pop"|"shatter"|"nova"|"implode"|"geyser"|"corona",
--            colorA/colorB accents
--   world:   theme "city"|"peaks"|"void"|"grid"|"aurora"|"reef"|"meteor"|
--            "palms"|"polar" — picks the scenery Backdrop draws
--   sun:     sun = a key into Config.Art.SunStyles — restyles the striped
--            horizon disk Backdrop parks down the slope
--   filter:  filter = "off"|"scan"|"pixel"|"tint"|"vignette" — a screen
--            overlay the ScreenFilter module draws UNDER the HUD text
--            layer; tint/alpha recolor the wash, pitch/bar/alpha override
--            the lattice recipe for scan/pixel variants
-- Any color param may instead be the string "customA"/"customB"/"customC"
-- (COLOR LAB §18): it resolves through that RoBallHue* channel — ringA→A,
-- ringB→B, trail/gemFx→C.
export type Item = {
	slot: Slot,
	name: string,
	free: boolean?,
	gemPrice: number?, -- banked-gem price (§18 P2); nil = pass-only record
	ringA: (Color3 | string)?,
	ringB: (Color3 | string)?,
	core: Color3?,
	fx: string?,
	color: (Color3 | string)?,
	style: string?,
	colorA: Color3?,
	colorB: Color3?,
	theme: string?,
	sun: string?,
	filter: string?,
	tint: Color3?,
	alpha: number?,
	pitch: number?,
	bar: number?,
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
local ICE = Color3.fromRGB(150, 222, 255) -- solstice seasonal family
local FROST = Color3.fromRGB(228, 246, 255)
local DEEP_ICE = Color3.fromRGB(70, 150, 255)
local LIME = Color3.fromRGB(170, 255, 60) -- toxic/acid family
local MINT = Color3.fromRGB(140, 255, 220)
local PEACH = Color3.fromRGB(255, 196, 140)
local BANANA = Color3.fromRGB(255, 226, 92) -- ape-ball toy family

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
	--==== SOLSTICE — seasonal window slot (§18; Config.Monetization.Seasonal
	-- gates the bundle and à-la-carte buys of these ids)
	skin_frost = {
		slot = "skin",
		name = "FROSTBITE",
		gemPrice = 800,
		ringA = FROST,
		ringB = DEEP_ICE,
		core = Color3.fromRGB(4, 8, 16),
	},
	--==== wave-2 families (§18): acid / lagoon / ember / candy / chrome,
	-- the animated strobe+wave skins, and the COLOR LAB custom-hue skin.
	skin_lagoon = {
		slot = "skin",
		name = "LAGOON",
		gemPrice = 400,
		ringA = MINT,
		ringB = AURORA_B,
		core = Color3.fromRGB(3, 12, 10),
	},
	skin_acid = {
		slot = "skin",
		name = "ACID BATH",
		gemPrice = 600,
		ringA = LIME,
		ringB = AURORA_G,
		core = Color3.fromRGB(10, 16, 2),
	},
	skin_candy = {
		slot = "skin",
		name = "CANDY GLOSS",
		gemPrice = 400,
		ringA = PINK,
		ringB = WHITE,
		core = Color3.fromRGB(18, 4, 10),
	},
	skin_ember = {
		slot = "skin",
		name = "EMBER",
		gemPrice = 400,
		ringA = ORANGE,
		ringB = GOLD,
		core = Color3.fromRGB(20, 8, 2),
	},
	skin_chrome = {
		slot = "skin",
		name = "CHROME",
		gemPrice = 500,
		ringA = SILVER,
		ringB = WHITE,
		core = Color3.fromRGB(10, 10, 14),
	},
	skin_chroma = {
		slot = "skin",
		name = "CHROMA",
		gemPrice = 1200,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
		fx = "strobe",
	},
	skin_iris = {
		slot = "skin",
		name = "IRIS",
		gemPrice = 1100,
		ringA = VIOLET,
		ringB = AURORA_B,
		core = Color3.fromRGB(4, 6, 12),
		fx = "wave",
	},
	skin_custom = {
		slot = "skin",
		name = "COLOR LAB",
		gemPrice = 1500,
		ringA = "customA",
		ringB = "customB",
		core = Color3.fromRGB(8, 6, 12),
	},
	--==== NULL pack — the stark set for the empty world: a pitch ball,
	-- ghost-pale rings, nothing chasing you but the sun.
	skin_null = {
		slot = "skin",
		name = "NULL",
		gemPrice = 800,
		ringA = WHITE,
		ringB = Color3.fromRGB(46, 48, 68),
		core = Color3.fromRGB(1, 1, 3),
	},
	--==== NEON PEAKS pack — the flagship world as its own complete look:
	-- a glacial summit set over the wireframe ridge field.
	skin_summit = {
		slot = "skin",
		name = "SUMMIT",
		gemPrice = 800,
		ringA = AURORA_B,
		ringB = WHITE,
		core = Color3.fromRGB(4, 8, 18),
	},
	--==== APE BALL pack — the arcade-toy set for the sky court world:
	-- a glossy capsule ball — warm plastic face under clean white rings.
	skin_capsule = {
		slot = "skin",
		name = "CAPSULE",
		gemPrice = 800,
		ringA = WHITE,
		ringB = BANANA,
		core = Color3.fromRGB(255, 138, 36),
	},

	--==== TRAIL — slim wake ribbon behind the ball
	trail_none = { slot = "trail", name = "NONE", free = true, none = true },
	trail_magenta = { slot = "trail", name = "PALETTE WAKE", free = true, color = "palette" },
	trail_ion = { slot = "trail", name = "ION", free = true, color = CYAN },
	trail_sunset = { slot = "trail", name = "SUNSET", gemPrice = 200, color = SUNSET },
	trail_bullion = { slot = "trail", name = "BULLION", gemPrice = 400, color = GOLD },
	trail_prism = { slot = "trail", name = "PRISM", gemPrice = 400, color = "rainbow" },
	trail_uv = { slot = "trail", name = "ULTRAVIOLET", gemPrice = 500, color = UV },
	trail_aurora = { slot = "trail", name = "AURORA WAKE", gemPrice = 450, color = AURORA_G },
	trail_spectre = { slot = "trail", name = "SPECTRE", gemPrice = 500, color = PALE_VIOLET },
	trail_frost = { slot = "trail", name = "FROSTWAKE", gemPrice = 450, color = ICE },
	trail_volt = { slot = "trail", name = "VOLT", gemPrice = 300, color = LIME },
	trail_peach = { slot = "trail", name = "PEACH", gemPrice = 250, color = PEACH },
	trail_mint = { slot = "trail", name = "MINT", gemPrice = 300, color = MINT },
	trail_ghost = { slot = "trail", name = "GHOST", gemPrice = 350, color = WHITE },
	trail_inferno = { slot = "trail", name = "INFERNO", gemPrice = 300, color = ORANGE },
	trail_custom = { slot = "trail", name = "LAB WAKE", gemPrice = 1500, color = "customC" },
	trail_null = { slot = "trail", name = "DRIFT", gemPrice = 450, color = SILVER },
	trail_ridgeline = { slot = "trail", name = "RIDGELINE", gemPrice = 450, color = AURORA_B },
	trail_banana = { slot = "trail", name = "BANANA WAKE", gemPrice = 450, color = BANANA },

	--==== GEM FX — the pickup flourish (pop diamond + sparkles + ring)
	gemfx_gold = { slot = "gemFx", name = "GOLD POP", free = true, color = GOLD },
	gemfx_cold = { slot = "gemFx", name = "COLD POP", free = true, color = CYAN },
	gemfx_sunset = { slot = "gemFx", name = "SUNSET POP", gemPrice = 200, color = SUNSET },
	gemfx_jackpot = { slot = "gemFx", name = "JACKPOT", gemPrice = 400, color = PALE_GOLD },
	gemfx_prism = { slot = "gemFx", name = "PRISM POP", gemPrice = 400, color = "rainbow" },
	gemfx_amethyst = { slot = "gemFx", name = "AMETHYST", gemPrice = 500, color = AMETHYST },
	gemfx_aurora = { slot = "gemFx", name = "AURORA POP", gemPrice = 450, color = AURORA_G },
	gemfx_spectre = { slot = "gemFx", name = "SPECTRE POP", gemPrice = 500, color = PALE_VIOLET },
	gemfx_frost = { slot = "gemFx", name = "FROST POP", gemPrice = 450, color = ICE },
	gemfx_volt = { slot = "gemFx", name = "VOLT POP", gemPrice = 300, color = LIME },
	gemfx_peach = { slot = "gemFx", name = "PEACH POP", gemPrice = 250, color = PEACH },
	gemfx_mint = { slot = "gemFx", name = "MINT POP", gemPrice = 300, color = MINT },
	gemfx_ghost = { slot = "gemFx", name = "GHOST POP", gemPrice = 350, color = WHITE },
	gemfx_inferno = { slot = "gemFx", name = "INFERNO POP", gemPrice = 300, color = ORANGE },
	gemfx_custom = { slot = "gemFx", name = "LAB POP", gemPrice = 1500, color = "customC" },
	gemfx_null = { slot = "gemFx", name = "NULL POP", gemPrice = 400, color = SILVER },
	gemfx_peak = { slot = "gemFx", name = "PEAK POP", gemPrice = 400, color = AURORA_B },
	gemfx_banana = { slot = "gemFx", name = "BANANA POP", gemPrice = 400, color = BANANA },

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
	deathfx_avalanche = {
		slot = "deathFx",
		name = "AVALANCHE",
		gemPrice = 600,
		style = "shatter",
		colorA = FROST,
		colorB = DEEP_ICE,
	},
	deathfx_geyser = {
		slot = "deathFx",
		name = "GEYSER",
		gemPrice = 550,
		style = "geyser",
		colorA = AURORA_B,
		colorB = CYAN,
	},
	deathfx_meltdown = {
		slot = "deathFx",
		name = "MELTDOWN",
		gemPrice = 600,
		style = "geyser",
		colorA = LIME,
		colorB = AURORA_G,
	},
	deathfx_corona = {
		slot = "deathFx",
		name = "CORONA",
		gemPrice = 650,
		style = "corona",
		colorA = GOLD,
		colorB = WHITE,
	},
	deathfx_violet = {
		slot = "deathFx",
		name = "ULTRAVIOLET",
		gemPrice = 650,
		style = "corona",
		colorA = UV,
		colorB = VIOLET,
	},
	deathfx_pinkslip = {
		slot = "deathFx",
		name = "PINK SLIP",
		gemPrice = 500,
		style = "pop",
		colorA = PINK,
		colorB = WHITE,
	},
	deathfx_limewire = {
		slot = "deathFx",
		name = "LIMEWIRE",
		gemPrice = 550,
		style = "shatter",
		colorA = LIME,
		colorB = MINT,
	},
	deathfx_null = {
		slot = "deathFx",
		name = "FADE",
		gemPrice = 550,
		style = "pop",
		colorA = WHITE,
		colorB = SILVER,
	},
	deathfx_landslide = {
		slot = "deathFx",
		name = "LANDSLIDE",
		gemPrice = 550,
		style = "shatter",
		colorA = AURORA_B,
		colorB = WHITE,
	},
	deathfx_party = {
		slot = "deathFx",
		name = "PARTY POP",
		gemPrice = 550,
		style = "pop",
		colorA = BANANA,
		colorB = WHITE,
	},

	--==== WORLD — the whole side-scenery theme (Backdrop.luau renders it)
	world_city = { slot = "world", name = "NEON CITY", free = true, theme = "city" },
	world_peaks = { slot = "world", name = "NEON PEAKS", gemPrice = 800, theme = "peaks" },
	world_void = { slot = "world", name = "STAR WELL", gemPrice = 800, theme = "void" },
	world_grid = { slot = "world", name = "GRID PLANE", gemPrice = 800, theme = "grid" },
	world_aurora = { slot = "world", name = "BOREALIS SKY", gemPrice = 900, theme = "aurora" },
	world_reef = { slot = "world", name = "NEON REEF", gemPrice = 800, theme = "reef" },
	world_meteor = { slot = "world", name = "METEOR SHOWER", gemPrice = 900, theme = "meteor" },
	world_palms = { slot = "world", name = "MIAMI NIGHTS", gemPrice = 800, theme = "palms" },
	world_polar = { slot = "world", name = "NORTHERN LIGHTS", gemPrice = 900, theme = "polar" },
	world_empty = { slot = "world", name = "VOIDSPACE", gemPrice = 900, theme = "empty" },
	world_toxic = { slot = "world", name = "TOXIC WASTES", gemPrice = 800, theme = "toxic" },
	world_sky = { slot = "world", name = "SKY COURT", gemPrice = 900, theme = "sky" },

	--==== SUN — the horizon disk the run chases (Backdrop.luau renders it
	-- from Config.Art.SunStyles; "grid" thins the strips to a wireframe
	-- read, "moon"/"eclipse" pack them into a solid body)
	sun_classic = { slot = "sun", name = "SYNTH SUN", free = true, sun = "classic" },
	sun_moon = { slot = "sun", name = "PALE MOON", gemPrice = 400, sun = "moon" },
	sun_acid = { slot = "sun", name = "ACID SUN", gemPrice = 500, sun = "acid" },
	sun_prism = { slot = "sun", name = "PRISM RISE", gemPrice = 600, sun = "prism" },
	sun_grid = { slot = "sun", name = "WIREFRAME SUN", gemPrice = 700, sun = "grid" },
	sun_midas = { slot = "sun", name = "24K NOON", gemPrice = 750, sun = "midas" },
	sun_eclipse = { slot = "sun", name = "ECLIPSE", gemPrice = 800, sun = "eclipse" },
	sun_frost = { slot = "sun", name = "POLAR CAP", gemPrice = 600, sun = "frost" },
	sun_halo = { slot = "sun", name = "HALO RISE", gemPrice = 600, sun = "halo" },
	sun_tide = { slot = "sun", name = "NEAP TIDE", gemPrice = 600, sun = "tide" },
	sun_null = { slot = "sun", name = "DEAD SUN", gemPrice = 600, sun = "null" },
	sun_alpine = { slot = "sun", name = "ALPINE SUN", gemPrice = 600, sun = "alpine" },
	sun_noon = { slot = "sun", name = "HIGH NOON", gemPrice = 600, sun = "noon" },

	--==== FILTER — a screen overlay over the 3D view (ScreenFilter.luau
	-- renders it under the HUD so text stays readable). One per bundle:
	-- every pack carries a full 7-slot look, so the filter families span
	-- the lattice modes (scan/pixel) plus the wash modes (tint/vignette).
	filter_off = { slot = "filter", name = "CLEAN", free = true, filter = "off" },
	filter_scan = { slot = "filter", name = "SCANLINES", gemPrice = 450, filter = "scan" },
	filter_phosphor = {
		slot = "filter",
		name = "PHOSPHOR",
		gemPrice = 450,
		filter = "scan",
		pitch = 4,
		bar = 1,
		alpha = 0.35,
	},
	filter_pixel = { slot = "filter", name = "PIXEL GLASS", gemPrice = 600, filter = "pixel" },
	filter_vignette = { slot = "filter", name = "VIGNETTE", gemPrice = 550, filter = "vignette" },
	filter_gild = { slot = "filter", name = "GOLD HOUR", gemPrice = 500, filter = "tint", tint = GOLD },
	filter_verdant = {
		slot = "filter",
		name = "VERDANT VEIL",
		gemPrice = 500,
		filter = "tint",
		tint = AURORA_G,
	},
	filter_toxin = { slot = "filter", name = "TOXIN", gemPrice = 500, filter = "tint", tint = LIME },
	filter_abyss = { slot = "filter", name = "ABYSS", gemPrice = 550, filter = "tint", tint = DEEP_ICE },
	filter_snowblind = {
		slot = "filter",
		name = "SNOWBLIND",
		gemPrice = 550,
		filter = "tint",
		tint = FROST,
		alpha = 0.16,
	},
	filter_soot = {
		slot = "filter",
		name = "SOOT",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(110, 110, 140),
	},
	filter_thinair = {
		slot = "filter",
		name = "THIN AIR",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(140, 190, 255),
	},
	filter_day = {
		slot = "filter",
		name = "DAY GLOW",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(150, 200, 255),
	},
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
		"skin_frost",
		"skin_lagoon",
		"skin_acid",
		"skin_candy",
		"skin_ember",
		"skin_chrome",
		"skin_chroma",
		"skin_iris",
		"skin_custom",
		"skin_null",
		"skin_summit",
		"skin_capsule",
	},
	trail = {
		"trail_none",
		"trail_magenta",
		"trail_ion",
		"trail_sunset",
		"trail_bullion",
		"trail_prism",
		"trail_uv",
		"trail_aurora",
		"trail_spectre",
		"trail_frost",
		"trail_volt",
		"trail_peach",
		"trail_mint",
		"trail_ghost",
		"trail_inferno",
		"trail_custom",
		"trail_null",
		"trail_ridgeline",
		"trail_banana",
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
		"gemfx_frost",
		"gemfx_volt",
		"gemfx_peach",
		"gemfx_mint",
		"gemfx_ghost",
		"gemfx_inferno",
		"gemfx_custom",
		"gemfx_null",
		"gemfx_peak",
		"gemfx_banana",
	},
	deathFx = {
		"deathfx_shatter",
		"deathfx_pop",
		"deathfx_nova",
		"deathfx_implode",
		"deathfx_horizon",
		"deathfx_borealis",
		"deathfx_static",
		"deathfx_avalanche",
		"deathfx_geyser",
		"deathfx_meltdown",
		"deathfx_corona",
		"deathfx_violet",
		"deathfx_pinkslip",
		"deathfx_limewire",
		"deathfx_null",
		"deathfx_landslide",
		"deathfx_party",
	},
	world = {
		"world_city",
		"world_peaks",
		"world_void",
		"world_grid",
		"world_aurora",
		"world_reef",
		"world_meteor",
		"world_palms",
		"world_polar",
		"world_empty",
		"world_toxic",
		"world_sky",
	},
	sun = {
		"sun_classic",
		"sun_moon",
		"sun_acid",
		"sun_prism",
		"sun_grid",
		"sun_midas",
		"sun_eclipse",
		"sun_frost",
		"sun_halo",
		"sun_tide",
		"sun_null",
		"sun_alpine",
		"sun_noon",
	},
	filter = {
		"filter_off",
		"filter_scan",
		"filter_phosphor",
		"filter_pixel",
		"filter_vignette",
		"filter_gild",
		"filter_verdant",
		"filter_toxin",
		"filter_abyss",
		"filter_snowblind",
		"filter_soot",
		"filter_thinair",
		"filter_day",
	},
} :: { [string]: { string } }

Cosmetics.Defaults = {
	skin = "skin_classic",
	trail = "trail_none",
	gemFx = "gemfx_gold",
	deathFx = "deathfx_shatter",
	world = "world_city",
	sun = "sun_classic",
	filter = "filter_off",
} :: { [string]: string }

-- Themed bundle gamepasses (§18): one pass = a COMPLETE look — exactly
-- one item per STYLE slot, so a pack is a head-to-toe outfit the preview
-- can render whole. `id` is the pass key into Config.Monetization.Passes
-- / .Price. world_polar sits in two packs on purpose (POLARIS is the
-- permanent shelf item; SOLSTICE borrows it for the winter window) —
-- bundleOf resolves shared items to the non-seasonal bundle.
Cosmetics.Bundles = {
	{
		id = "starter",
		name = "STARTER NEON",
		desc = "full sunset set · palms world",
		items = {
			"skin_solar",
			"world_palms",
			"trail_sunset",
			"gemfx_sunset",
			"deathfx_nova",
			"sun_prism",
			"filter_scan",
		},
	},
	{
		-- The flagship world sold solo once — now it anchors its own
		-- complete look. Anyone holding the retired world-only `peaks`
		-- pass owns the whole set through the same pass key.
		id = "peaks",
		name = "NEON PEAKS",
		desc = "full summit set · ridge world",
		items = {
			"skin_summit",
			"world_peaks",
			"trail_ridgeline",
			"gemfx_peak",
			"deathfx_landslide",
			"sun_alpine",
			"filter_thinair",
		},
	},
	{
		id = "synthwave",
		name = "SYNTHWAVE",
		desc = "full prism set · grid world",
		items = {
			"skin_prism",
			"world_grid",
			"trail_prism",
			"gemfx_prism",
			"deathfx_violet",
			"sun_grid",
			"filter_pixel",
		},
	},
	{
		id = "midas",
		name = "MIDAS",
		desc = "full 24k set · meteor world",
		items = {
			"skin_midas",
			"world_meteor",
			"trail_bullion",
			"gemfx_jackpot",
			"deathfx_implode",
			"sun_midas",
			"filter_gild",
		},
	},
	{
		id = "vip",
		name = "VOID VIP",
		desc = "full void set · star-well world",
		items = {
			"skin_void",
			"world_void",
			"trail_uv",
			"gemfx_amethyst",
			"deathfx_horizon",
			"sun_eclipse",
			"filter_vignette",
		},
	},
	{
		id = "aurora",
		name = "AURORA",
		desc = "full borealis set · aurora sky",
		items = {
			"skin_aurora",
			"world_aurora",
			"trail_aurora",
			"gemfx_aurora",
			"deathfx_borealis",
			"sun_moon",
			"filter_verdant",
		},
	},
	{
		id = "polaris",
		name = "POLARIS",
		desc = "full phantom set · polar sky",
		items = {
			"skin_phantom",
			"world_polar",
			"trail_spectre",
			"gemfx_spectre",
			"deathfx_static",
			"sun_halo",
			"filter_phosphor",
		},
	},
	{
		id = "acid",
		name = "TOXIC SLUDGE",
		desc = "full acid set · toxic wastes",
		items = {
			"skin_acid",
			"world_toxic",
			"trail_volt",
			"gemfx_volt",
			"deathfx_meltdown",
			"sun_acid",
			"filter_toxin",
		},
	},
	{
		id = "reef",
		name = "NEON REEF",
		desc = "full lagoon set · reef world",
		items = {
			"skin_lagoon",
			"world_reef",
			"trail_mint",
			"gemfx_mint",
			"deathfx_geyser",
			"sun_tide",
			"filter_abyss",
		},
	},
	{
		-- The anti-pack: a stripped-down set for the empty world — pitch
		-- ball, ghost rings, soot filter, dead sun. The scenery itself is
		-- the product: nothing but the lane and the horizon.
		id = "null",
		name = "NULL",
		desc = "full null set · empty world",
		items = {
			"skin_null",
			"world_empty",
			"trail_null",
			"gemfx_null",
			"deathfx_null",
			"sun_null",
			"filter_soot",
		},
	},
	{
		-- Seasonal slot (§18): Config.Monetization.Seasonal holds the UTC
		-- window; Ui derives this row's desc from it at build time. Borrows
		-- world_polar — the northern-lights sky IS the winter look.
		id = "solstice",
		name = "SOLSTICE",
		desc = "full frost set · polar sky",
		items = {
			"skin_frost",
			"world_polar",
			"trail_frost",
			"gemfx_frost",
			"deathfx_avalanche",
			"sun_frost",
			"filter_snowblind",
		},
	},
	{
		-- The arcade homage: a glossy toy look for the bright sky court —
		-- capsule ball, banana wake, checker floor, noon sun. An original
		-- set in the rolling-party-ball spirit; no borrowed IP or assets.
		id = "apeball",
		name = "APE BALL",
		desc = "full capsule set · sky court world",
		items = {
			"skin_capsule",
			"world_sky",
			"trail_banana",
			"gemfx_banana",
			"deathfx_party",
			"sun_noon",
			"filter_day",
		},
	},
}

-- itemId -> {bundle ids}, built once at require time. Membership can
-- overlap (see world_polar) so the index is a list, not a scalar.
local bundleIndex: { [string]: { string } } = {}
for _, b in ipairs(Cosmetics.Bundles) do
	for _, id in ipairs(b.items) do
		local list = bundleIndex[id]
		if list == nil then
			list = {}
			bundleIndex[id] = list
		end
		table.insert(list, b.id)
	end
end

-- Retired bundle ids (§18): passes sunset in the catalog but already-SOLD
-- passes keep granting their original contents forever — owns() consults
-- this map so a deleted pack never claws back what someone bought.
Cosmetics.LegacyBundles = {
	phantom = { "skin_phantom", "trail_spectre", "gemfx_spectre", "deathfx_static" },
	deepspace = { "world_void", "world_grid", "world_meteor" },
	inferno = { "skin_ember", "trail_inferno", "gemfx_inferno", "deathfx_corona" },
	candy = { "skin_candy", "trail_peach", "gemfx_peach", "deathfx_pinkslip" },
	colorlab = { "skin_custom", "trail_custom", "gemfx_custom" },
	sunkissed = { "sun_eclipse", "sun_midas", "sun_grid" },
	miami = { "world_palms", "sun_prism" },
	vhs = { "filter_pixel", "filter_scan" },
}
local legacyIndex: { [string]: { string } } = {}
for bid, items in pairs(Cosmetics.LegacyBundles) do
	for _, id in ipairs(items) do
		local list = legacyIndex[id]
		if list == nil then
			list = {}
			legacyIndex[id] = list
		end
		table.insert(list, bid)
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
		sun = Cosmetics.Defaults.sun,
		filter = Cosmetics.Defaults.filter,
	}
end

-- itemId -> the bundle the shop should route to. Shared memberships
-- resolve to the NON-seasonal pack (the always-on shelf item) so a
-- borrowed item like world_polar never inherits the seasonal gate —
-- the locked-item funnel and the off-season à-la-carte check both
-- read this.
function Cosmetics.bundleOf(itemId: string): string?
	local list = bundleIndex[itemId]
	if not list then
		return nil
	end
	local seasonal = Config.Monetization.Seasonal.Bundle
	for _, id in ipairs(list) do
		if id ~= seasonal then
			return id
		end
	end
	return list[1]
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
	for _, b in ipairs(bundleIndex[itemId] or {}) do
		if owned[b] then
			return true
		end
	end
	for _, b in ipairs(legacyIndex[itemId] or {}) do
		if owned[b] then
			return true
		end
	end
	return false
end

-- Resolve a color param to a Color3: Color3 passthrough, "palette" samples
-- the run wheel at 0 (the magenta the default trail uses), "rainbow" is a
-- slow time-cycled hue, and "customA"/"customB"/"customC" read the COLOR
-- LAB channel colors out of `hues` (see huesOf). Anything else falls back.
export type Hues = { a: Color3?, b: Color3?, c: Color3? }

Cosmetics.HueAttr = { a = "RoBallHueA", b = "RoBallHueB", c = "RoBallHueC" }
local hueChannel: { [string]: string } = { customA = "a", customB = "b", customC = "c" }

-- Resolved COLOR LAB channel colors for a player: RoBallHue* attributes
-- clamped into the legal band (Config.CustomHue — the red seam is cut).
-- Missing attrs (pre-profile) fall back to the configured defaults.
function Cosmetics.huesOf(player: Player): Hues
	local H = Config.CustomHue
	local function ch(k: string): Color3
		local v = player:GetAttribute(Cosmetics.HueAttr[k])
		local h = if typeof(v) == "number" then v else (H.Defaults :: any)[k]
		return Color3.fromHSV(math.clamp(h, H.Min, H.Max), H.Sat, H.Value)
	end
	return { a = ch("a"), b = ch("b"), c = ch("c") }
end

-- COLOR LAB gate (§18): the hue sliders unlock when the player owns ANY
-- lab item — the colorlab bundle grants all three, à-la-carte singles
-- (gem purchases) count too.
Cosmetics.LabItems = { "skin_custom", "trail_custom", "gemfx_custom" }
function Cosmetics.labOwned(owned: { [string]: boolean }): boolean
	for _, id in ipairs(Cosmetics.LabItems) do
		if Cosmetics.owns(owned, id) then
			return true
		end
	end
	return false
end

function Cosmetics.colorOf(param: any, fallback: Color3?, hues: Hues?): Color3
	if typeof(param) == "Color3" then
		return param
	end
	if type(param) == "string" then
		local ch = hueChannel[param]
		if ch then
			return (hues and hues[ch]) or fallback or Palette.neonAt(0)
		end
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
