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
local Daily = require(script.Parent.Daily)
local Palette = require(script.Parent.Palette)

local Cosmetics = {}

export type Slot = "skin" | "trail" | "gemFx" | "deathFx" | "world" | "floor" | "sun" | "filter"

Cosmetics.Slots = { "skin", "world", "floor", "trail", "gemFx", "deathFx", "sun", "filter" } :: { Slot }
Cosmetics.SlotName = {
	skin = "SKIN",
	trail = "TRAIL",
	gemFx = "GEM FX",
	deathFx = "DEATH FX",
	world = "WORLD",
	floor = "FLOOR",
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
--            "matrix"|"palms"|"polar" — picks the scenery Backdrop draws
--   floor:   deck = slab base color (still DeckTint-lerped toward the
--            palette unless deckB is set); deckB + deckCell = checker
--            partner color + tile size in studs (no palette lerp);
--            edge = flat edge-rail color; plain = suppress the transverse
--            grid strips + center line
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
	deck: Color3?,
	deckB: Color3?,
	deckCell: number?,
	edge: Color3?,
	plain: boolean?,
	capsule: boolean?,
	gemStyle: string?,
	gemShape: string?,
	none: boolean?,
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
local PHOSPHOR = Color3.fromRGB(80, 255, 120) -- mainframe terminal green
local PHOSPHOR_HI = Color3.fromRGB(190, 255, 220) -- phosphor near-white
local PHOSPHOR_MID = Color3.fromRGB(140, 255, 180) -- phosphor mid
local DUSK = Color3.fromRGB(90, 110, 200) -- festival night-blue
local SPARK = Color3.fromRGB(255, 226, 140) -- sparkler gold
local AMBER = Color3.fromRGB(255, 190, 90) -- cathedral warm glass
local IVORY = Color3.fromRGB(240, 230, 210) -- cathedral lead-work
local HOOP = Color3.fromRGB(140, 140, 255) -- hypnotube mid-spectrum
local PAPER = Color3.fromRGB(255, 244, 228) -- papercraft stock
local CLAY = Color3.fromRGB(255, 150, 120) -- papercraft accent
local HONEY = Color3.fromRGB(255, 190, 60) -- mycelium amber
local MOSS = Color3.fromRGB(120, 200, 90) -- mycelium green
local INDIGO = Color3.fromRGB(70, 80, 200) -- inkwell sumi
local INKW = Color3.fromRGB(220, 225, 240) -- ink-white
local HOTW = Color3.fromRGB(245, 248, 255) -- hyperdrive white-hot

Cosmetics.Items = {
	--==== SKIN — 3 axial rings (ringA) + 2 diagonals (ringB), core = ball
	-- face. `gemShape` pins the run's pickup silhouette (§8.4): every gem
	-- under one skin shares the shape — worth still telegraphs on tier
	-- scale + warm tint. Names come from GemTypes.pose's vocabulary:
	-- "diamond"/"crown" (corner cube), "orb", "coin", "shard", "rod".
	skin_classic = {
		slot = "skin",
		name = "CLASSIC NEON",
		free = true,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
		gemShape = "diamond",
	},
	skin_mono = {
		slot = "skin",
		name = "MONO",
		free = true,
		ringA = WHITE,
		ringB = SILVER,
		core = Color3.fromRGB(8, 8, 12),
		gemShape = "orb", -- the pearl
	},
	skin_solar = {
		slot = "skin",
		name = "SOLAR FLARE",
		gemPrice = 300,
		ringA = ORANGE,
		ringB = PINK,
		core = Color3.fromRGB(24, 8, 4),
		gemShape = "shard", -- flare spikes
	},
	skin_midas = {
		slot = "skin",
		name = "24K",
		gemPrice = 750,
		ringA = GOLD,
		ringB = PALE_GOLD,
		core = Color3.fromRGB(26, 16, 4),
		gemShape = "coin", -- bullion tokens
	},
	skin_prism = {
		slot = "skin",
		name = "PRISM",
		gemPrice = 750,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
		fx = "rainbow",
		gemShape = "diamond", -- faceted
	},
	skin_void = {
		slot = "skin",
		name = "VOID EMPRESS",
		gemPrice = 900,
		ringA = VIOLET,
		ringB = PINK,
		core = Color3.fromRGB(2, 0, 6),
		fx = "pulse",
		gemShape = "crown", -- the empress wears it
	},
	skin_aurora = {
		slot = "skin",
		name = "AURORA",
		gemPrice = 800,
		ringA = AURORA_G,
		ringB = AURORA_B,
		core = Color3.fromRGB(4, 14, 10),
		gemShape = "rod", -- light pillars
	},
	skin_phantom = {
		slot = "skin",
		name = "PHANTOM",
		gemPrice = 900,
		ringA = WHITE,
		ringB = AMETHYST,
		core = Color3.fromRGB(6, 4, 12),
		fx = "pulse",
		gemShape = "shard", -- spectral spike
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
		gemShape = "shard", -- ice crystal
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
		gemShape = "orb", -- lagoon pearl
	},
	skin_acid = {
		slot = "skin",
		name = "ACID BATH",
		gemPrice = 600,
		ringA = LIME,
		ringB = AURORA_G,
		core = Color3.fromRGB(10, 16, 2),
		gemShape = "rod", -- glow-stick
	},
	skin_candy = {
		slot = "skin",
		name = "CANDY GLOSS",
		gemPrice = 400,
		ringA = PINK,
		ringB = WHITE,
		core = Color3.fromRGB(18, 4, 10),
		gemShape = "orb", -- gumball
	},
	skin_ember = {
		slot = "skin",
		name = "EMBER",
		gemPrice = 400,
		ringA = ORANGE,
		ringB = GOLD,
		core = Color3.fromRGB(20, 8, 2),
		gemShape = "rod", -- a coal poker
	},
	skin_chrome = {
		slot = "skin",
		name = "CHROME",
		gemPrice = 500,
		ringA = SILVER,
		ringB = WHITE,
		core = Color3.fromRGB(10, 10, 14),
		gemShape = "coin", -- casino chip
	},
	skin_chroma = {
		slot = "skin",
		name = "CHROMA",
		gemPrice = 1200,
		ringA = CYAN,
		ringB = MAGENTA,
		core = Color3.fromRGB(4, 8, 6),
		fx = "strobe",
		gemShape = "crown", -- jackpot silhouette
	},
	skin_iris = {
		slot = "skin",
		name = "IRIS",
		gemPrice = 1100,
		ringA = VIOLET,
		ringB = AURORA_B,
		core = Color3.fromRGB(4, 6, 12),
		fx = "wave",
		gemShape = "orb", -- the eye
	},
	skin_custom = {
		slot = "skin",
		name = "COLOR LAB",
		gemPrice = 1500,
		ringA = "customA",
		ringB = "customB",
		core = Color3.fromRGB(8, 6, 12),
		gemShape = "diamond",
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
		gemShape = "diamond", -- bare crystal, nothing else
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
		gemShape = "shard", -- mountain crystal
	},
	--==== APE BALL pack — the arcade-toy set for the sky court world:
	-- a glossy two-tone capsule ball: half-clear Glass shell under a
	-- translucent red hemisphere cap, the split tumbling with the roll
	-- (BallDress.buildCap CSG hemisphere, APEBALL.md §2).
	skin_mainframe = {
		slot = "skin",
		name = "MAINFRAME",
		gemPrice = 800,
		ringA = PHOSPHOR,
		ringB = PHOSPHOR_HI,
		core = Color3.fromRGB(10, 26, 14),
		fx = "pulse",
		gemShape = "rod", -- code-rain bars
	},
	skin_pyro = {
		slot = "skin",
		name = "PYRO",
		gemPrice = 800,
		ringA = ORANGE,
		ringB = DUSK,
		core = Color3.fromRGB(24, 18, 30),
		gemShape = "orb", -- festival shells
	},
	skin_spiral = {
		slot = "skin",
		name = "SPIRAL",
		gemPrice = 800,
		ringA = CYAN,
		ringB = VIOLET,
		core = Color3.fromRGB(18, 14, 40),
		fx = "wave",
		gemShape = "coin", -- hypnotube hoops
	},
	skin_leaded = {
		slot = "skin",
		name = "LEADED",
		gemPrice = 800,
		ringA = GOLD,
		ringB = MAGENTA,
		core = IVORY,
		gemShape = "shard", -- stained-glass panes
	},
	skin_fold = {
		slot = "skin",
		name = "FOLD",
		gemPrice = 800,
		ringA = PAPER,
		ringB = CLAY,
		core = Color3.fromRGB(235, 225, 205),
		gemShape = "shard", -- folded facets
	},
	skin_spore = {
		slot = "skin",
		name = "SPORE",
		gemPrice = 800,
		ringA = HONEY,
		ringB = MOSS,
		core = Color3.fromRGB(16, 20, 12),
		fx = "pulse",
		gemShape = "orb", -- spore sacs
	},
	skin_sumi = {
		slot = "skin",
		name = "SUMI",
		gemPrice = 800,
		ringA = INDIGO,
		ringB = INKW,
		core = Color3.fromRGB(14, 16, 36),
		fx = "wave",
		gemShape = "orb", -- ink drops
	},
	skin_lightyear = {
		slot = "skin",
		name = "LIGHTYEAR",
		gemPrice = 900,
		ringA = HOTW,
		ringB = CYAN,
		core = Color3.fromRGB(10, 14, 34),
		fx = "strobe",
		gemShape = "rod", -- star streaks
	},
	skin_capsule = {
		slot = "skin",
		name = "CAPSULE",
		gemPrice = 800,
		ringA = WHITE,
		ringB = BANANA,
		core = Color3.new(1, 1, 1), -- neutral: the clear half stays truly clear
		capsule = true, -- clear shell at Config.Art.CapsuleAlpha + red ShellCap
		gemShape = "orb", -- ball pickups, on any world
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
	trail_stream = { slot = "trail", name = "DATASTREAM", gemPrice = 450, color = PHOSPHOR },
	trail_sparkler = { slot = "trail", name = "SPARKLER", gemPrice = 450, color = SPARK },
	trail_vortex = { slot = "trail", name = "VORTEX", gemPrice = 450, color = VIOLET },
	trail_censer = { slot = "trail", name = "CENSER", gemPrice = 450, color = AMBER },
	trail_crease = { slot = "trail", name = "CREASE", gemPrice = 450, color = Color3.fromRGB(255, 240, 220) },
	trail_hypha = { slot = "trail", name = "HYPHA", gemPrice = 450, color = Color3.fromRGB(255, 200, 80) },
	trail_ink = { slot = "trail", name = "INK TRAIL", gemPrice = 450, color = Color3.fromRGB(80, 70, 160) },
	trail_warpline = { slot = "trail", name = "WARP LINE", gemPrice = 500, color = Color3.fromRGB(160, 240, 255) },

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
	gemfx_decrypt = { slot = "gemFx", name = "DECRYPT", gemPrice = 400, color = PHOSPHOR_MID },
	gemfx_burst = { slot = "gemFx", name = "SKY BURST", gemPrice = 400, color = ORANGE },
	gemfx_hoop = { slot = "gemFx", name = "HOOP", gemPrice = 400, color = HOOP },
	gemfx_glint = { slot = "gemFx", name = "GLINT", gemPrice = 400, color = GOLD },
	gemfx_paper = { slot = "gemFx", name = "PAPER CUT", gemPrice = 400, color = Color3.fromRGB(255, 180, 150) },
	gemfx_spore = { slot = "gemFx", name = "SPORE BURST", gemPrice = 400, color = Color3.fromRGB(200, 220, 120) },
	gemfx_bleed = { slot = "gemFx", name = "BLEED", gemPrice = 400, color = Color3.fromRGB(110, 100, 220) },
	gemfx_starburst = { slot = "gemFx", name = "STARBURST", gemPrice = 450, color = Color3.fromRGB(220, 245, 255) },

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
	deathfx_segfault = {
		slot = "deathFx",
		name = "SEGFAULT",
		gemPrice = 550,
		style = "shatter",
		colorA = PHOSPHOR,
		colorB = PHOSPHOR_HI,
	},
	deathfx_finale = {
		slot = "deathFx",
		name = "FINALE",
		gemPrice = 600,
		style = "nova",
		colorA = ORANGE,
		colorB = GOLD,
	},
	deathfx_unwind = {
		slot = "deathFx",
		name = "UNWIND",
		gemPrice = 550,
		style = "corona",
		colorA = CYAN,
		colorB = VIOLET,
	},
	deathfx_rosefall = {
		slot = "deathFx",
		name = "ROSEFALL",
		gemPrice = 600,
		style = "shatter",
		colorA = MAGENTA,
		colorB = GOLD,
	},
	deathfx_unfold = {
		slot = "deathFx",
		name = "UNFOLD",
		gemPrice = 550,
		style = "shatter",
		colorA = PAPER,
		colorB = CLAY,
	},
	deathfx_sporulate = {
		slot = "deathFx",
		name = "SPORULATE",
		gemPrice = 550,
		style = "geyser",
		colorA = HONEY,
		colorB = MOSS,
	},
	deathfx_bloom = {
		slot = "deathFx",
		name = "BLOOM",
		gemPrice = 550,
		style = "implode", -- collapses then blooms
		colorA = INDIGO,
		colorB = INKW,
	},
	deathfx_signal = {
		slot = "deathFx",
		name = "SIGNAL LOST",
		gemPrice = 600,
		style = "nova",
		colorA = HOTW,
		colorB = CYAN,
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
	-- gemStyle "ball" restyles every pickup as a banana-yellow capsule orb
	-- (TrackStreamer stamps it server-side; §8.4).
	world_sky = { slot = "world", name = "SKY COURT", gemPrice = 900, theme = "sky", gemStyle = "ball" },
	world_matrix = { slot = "world", name = "MAINFRAME", gemPrice = 900, theme = "matrix" },
	world_fireworks = { slot = "world", name = "FESTIVAL", gemPrice = 900, theme = "fireworks" },
	world_tunnel = { slot = "world", name = "HYPNOTUBE", gemPrice = 900, theme = "tunnel" },
	world_glass = { slot = "world", name = "CATHEDRAL", gemPrice = 900, theme = "glass" },
	world_paper = { slot = "world", name = "PAPERCRAFT", gemPrice = 800, theme = "paper" },
	world_slime = { slot = "world", name = "MYCELIUM", gemPrice = 800, theme = "slime" },
	world_ink = { slot = "world", name = "INKWELL", gemPrice = 800, theme = "ink" },
	world_warp = { slot = "world", name = "HYPERDRIVE", gemPrice = 900, theme = "warp" },

	--==== FLOOR — the deck slab itself (TrackStreamer/CosmeticFx restyle
	-- it). `deck` is the lane base color, still lerped toward the run
	-- palette by DeckTint; `deckB` + `deckCell` switch to a two-color
	-- checkerboard that skips the drift. Every flat recolor stays DARK in
	-- its pack family — the neon grid carries the read and lethal red
	-- stays singular (CHECKER DECK is the licensed exception, the ape-ball
	-- homage). NEON DECK = no fields, the current look.
	floor_neon = { slot = "floor", name = "NEON DECK", free = true },
	floor_slate = { slot = "floor", name = "SLATE", free = true, deck = Color3.fromRGB(17, 18, 24) },
	floor_dusk = { slot = "floor", name = "DUSK TILE", gemPrice = 250, deck = Color3.fromRGB(28, 10, 22) },
	floor_glacier = { slot = "floor", name = "GLACIER", gemPrice = 350, deck = Color3.fromRGB(6, 12, 22) },
	floor_wire = { slot = "floor", name = "WIRE DECK", gemPrice = 350, deck = Color3.fromRGB(12, 6, 22) },
	floor_gilt = { slot = "floor", name = "GILT", gemPrice = 350, deck = Color3.fromRGB(26, 18, 5) },
	floor_void = { slot = "floor", name = "VOID TILE", gemPrice = 350, deck = Color3.fromRGB(6, 2, 14) },
	floor_boreal = { slot = "floor", name = "BOREALIS DECK", gemPrice = 350, deck = Color3.fromRGB(4, 16, 12) },
	floor_spectre = { slot = "floor", name = "SPECTRAL", gemPrice = 350, deck = Color3.fromRGB(14, 12, 24) },
	floor_frost = { slot = "floor", name = "FROST TILE", gemPrice = 350, deck = Color3.fromRGB(6, 14, 22) },
	floor_sludge = { slot = "floor", name = "SLUDGE", gemPrice = 300, deck = Color3.fromRGB(12, 18, 3) },
	floor_trench = { slot = "floor", name = "TRENCH", gemPrice = 350, deck = Color3.fromRGB(3, 10, 18) },
	floor_blackout = { slot = "floor", name = "BLACKOUT", gemPrice = 350, deck = Color3.fromRGB(2, 2, 5) },
	floor_check = {
		slot = "floor",
		name = "CHECKER DECK",
		gemPrice = 450,
		deck = Config.Art.SkyFloorA,
		deckB = Config.Art.SkyFloorB,
		deckCell = 13, -- studs per tile; ~13 reads at speed
		edge = Color3.fromRGB(28, 110, 50), -- grass-green rails, far from lethal
		plain = true, -- the checker IS the pattern — no grid strips/center line
	},
	floor_matrix = {
		slot = "floor",
		name = "CIRCUIT DECK",
		gemPrice = 350,
		deck = Color3.fromRGB(8, 14, 10),
		edge = PHOSPHOR,
	},
	floor_street = {
		slot = "floor",
		name = "FAIRGROUND",
		gemPrice = 350,
		deck = Color3.fromRGB(14, 14, 22),
		edge = AMBER,
	},
	floor_tube = {
		slot = "floor",
		name = "TUBE",
		gemPrice = 350,
		deck = Color3.fromRGB(10, 10, 24),
		edge = CYAN,
	},
	floor_nave = {
		slot = "floor",
		name = "NAVE",
		gemPrice = 350,
		deckB = Color3.fromRGB(40, 44, 64),
		deck = Color3.fromRGB(26, 28, 44),
		deckCell = 12,
		edge = GOLD,
	},
	floor_kraft = {
		slot = "floor",
		name = "KRAFT",
		gemPrice = 350,
		deck = Color3.fromRGB(46, 34, 28),
		edge = PAPER,
	},
	floor_humus = {
		slot = "floor",
		name = "HUMUS",
		gemPrice = 350,
		deck = Color3.fromRGB(22, 30, 18),
		edge = HONEY,
	},
	floor_inkwash = {
		slot = "floor",
		name = "INK WASH",
		gemPrice = 350,
		deck = Color3.fromRGB(16, 18, 34),
		edge = Color3.fromRGB(200, 205, 230),
	},
	floor_darkmatter = {
		slot = "floor",
		name = "DARK MATTER",
		gemPrice = 350,
		deck = Color3.fromRGB(10, 12, 26),
		edge = Color3.fromRGB(160, 240, 255),
	},

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
	sun_cursor = { slot = "sun", name = "TERMINAL SUN", gemPrice = 600, sun = "cursor" },
	sun_lantern = { slot = "sun", name = "LANTERN MOON", gemPrice = 600, sun = "lantern" },
	sun_aperture = { slot = "sun", name = "APERTURE", gemPrice = 600, sun = "aperture" },
	sun_rose = { slot = "sun", name = "ROSE WINDOW", gemPrice = 700, sun = "rose" },
	sun_paper = { slot = "sun", name = "PAPER SUN", gemPrice = 600, sun = "paper" },
	sun_ferment = { slot = "sun", name = "FERMENT", gemPrice = 600, sun = "ferment" },
	sun_inkmoon = { slot = "sun", name = "INK MOON", gemPrice = 600, sun = "inkmoon" },
	sun_warpcore = { slot = "sun", name = "WARP CORE", gemPrice = 700, sun = "warpcore" },

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
	filter_terminal = {
		slot = "filter",
		name = "TERMINAL",
		gemPrice = 500,
		filter = "scan",
		pitch = 6,
		bar = 1,
		alpha = 0.28,
	},
	filter_duskhaze = {
		slot = "filter",
		name = "DUSK HAZE",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(120, 100, 180),
		alpha = 0.12,
	},
	filter_hypnosis = {
		slot = "filter",
		name = "HYPNOSIS",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(60, 50, 120),
		alpha = 0.14,
	},
	filter_sanctuary = {
		slot = "filter",
		name = "SANCTUARY",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(255, 210, 140),
		alpha = 0.10,
	},
	filter_matte = {
		slot = "filter",
		name = "MATTE",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(240, 220, 190),
		alpha = 0.10,
	},
	filter_petri = {
		slot = "filter",
		name = "PETRI",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(150, 140, 70),
		alpha = 0.12,
	},
	filter_sumi = {
		slot = "filter",
		name = "SUMI",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(60, 60, 90),
		alpha = 0.14,
	},
	filter_lightspeed = {
		slot = "filter",
		name = "LIGHTSPEED",
		gemPrice = 500,
		filter = "tint",
		tint = Color3.fromRGB(140, 220, 255),
		alpha = 0.10,
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
		"skin_mainframe",
		"skin_pyro",
		"skin_spiral",
		"skin_leaded",
		"skin_fold",
		"skin_spore",
		"skin_sumi",
		"skin_lightyear",
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
		"trail_stream",
		"trail_sparkler",
		"trail_vortex",
		"trail_censer",
		"trail_crease",
		"trail_hypha",
		"trail_ink",
		"trail_warpline",
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
		"gemfx_decrypt",
		"gemfx_burst",
		"gemfx_hoop",
		"gemfx_glint",
		"gemfx_paper",
		"gemfx_spore",
		"gemfx_bleed",
		"gemfx_starburst",
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
		"deathfx_segfault",
		"deathfx_finale",
		"deathfx_unwind",
		"deathfx_rosefall",
		"deathfx_unfold",
		"deathfx_sporulate",
		"deathfx_bloom",
		"deathfx_signal",
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
		"world_matrix",
		"world_fireworks",
		"world_tunnel",
		"world_glass",
		"world_paper",
		"world_slime",
		"world_ink",
		"world_warp",
	},
	floor = {
		"floor_neon",
		"floor_slate",
		"floor_dusk",
		"floor_glacier",
		"floor_wire",
		"floor_gilt",
		"floor_void",
		"floor_boreal",
		"floor_spectre",
		"floor_frost",
		"floor_sludge",
		"floor_trench",
		"floor_blackout",
		"floor_check",
		"floor_matrix",
		"floor_street",
		"floor_tube",
		"floor_nave",
		"floor_kraft",
		"floor_humus",
		"floor_inkwash",
		"floor_darkmatter",
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
		"sun_cursor",
		"sun_lantern",
		"sun_aperture",
		"sun_rose",
		"sun_paper",
		"sun_ferment",
		"sun_inkmoon",
		"sun_warpcore",
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
		"filter_terminal",
		"filter_duskhaze",
		"filter_hypnosis",
		"filter_sanctuary",
		"filter_matte",
		"filter_petri",
		"filter_sumi",
		"filter_lightspeed",
	},
} :: { [string]: { string } }

Cosmetics.Defaults = {
	skin = "skin_classic",
	trail = "trail_none",
	gemFx = "gemfx_gold",
	deathFx = "deathfx_shatter",
	world = "world_city",
	floor = "floor_neon",
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
			"floor_dusk",
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
			"floor_glacier",
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
			"floor_wire",
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
			"floor_gilt",
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
			"floor_void",
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
			"floor_boreal",
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
			"floor_spectre",
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
			"floor_sludge",
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
			"floor_trench",
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
			"floor_blackout",
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
			"floor_frost",
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
			"floor_check",
			"trail_banana",
			-- equipBundle equips in list order, so NONE lands last: the pack
			-- ships trail-less like the homage, while trail_banana stays in
			-- the grant list (pass holders keep the wake à-la-carte).
			"trail_none",
			"gemfx_banana",
			"deathfx_party",
			"sun_noon",
			"filter_day",
		},
	},
	{
		-- W6-A (DLC_ROADMAP.md §3): green-phosphor terminal set — code-rain
		-- world, caret sun, raster filter.
		id = "mainframe",
		name = "MAINFRAME",
		desc = "full phosphor set · code-rain world",
		items = {
			"skin_mainframe",
			"world_matrix",
			"floor_matrix",
			"trail_stream",
			"gemfx_decrypt",
			"deathfx_segfault",
			"sun_cursor",
			"filter_terminal",
		},
	},
	{
		-- W6-B (DLC_ROADMAP.md §3): night-fair set — firework world,
		-- lantern moon, dusk haze.
		id = "festival",
		name = "FESTIVAL",
		desc = "full pyro set · fireworks world",
		items = {
			"skin_pyro",
			"world_fireworks",
			"floor_street",
			"trail_sparkler",
			"gemfx_burst",
			"deathfx_finale",
			"sun_lantern",
			"filter_duskhaze",
		},
	},
	{
		-- W7-A (DLC_ROADMAP.md §3): infinite tunnel — hue-walking hoops,
		-- aperture ring sun.
		id = "hypnotube",
		name = "HYPNOTUBE",
		desc = "full spiral set · tunnel world",
		items = {
			"skin_spiral",
			"world_tunnel",
			"floor_tube",
			"trail_vortex",
			"gemfx_hoop",
			"deathfx_unwind",
			"sun_aperture",
			"filter_hypnosis",
		},
	},
	{
		-- W7-B (DLC_ROADMAP.md §3): stained glass — pane world, rose
		-- window sun, the wave's premium slot.
		id = "cathedral",
		name = "CATHEDRAL",
		desc = "full stained-glass set · pane world",
		items = {
			"skin_leaded",
			"world_glass",
			"floor_nave",
			"trail_censer",
			"gemfx_glint",
			"deathfx_rosefall",
			"sun_rose",
			"filter_sanctuary",
		},
	},
	{
		-- W8-A (DLC_ROADMAP.md §3): origami — paper world, matte sun.
		id = "papercraft",
		name = "PAPERCRAFT",
		desc = "full fold set · paper world",
		items = {
			"skin_fold",
			"world_paper",
			"floor_kraft",
			"trail_crease",
			"gemfx_paper",
			"deathfx_unfold",
			"sun_paper",
			"filter_matte",
		},
	},
	{
		-- W8-B (DLC_ROADMAP.md §3): physarum — slime-network world,
		-- amber ferment sun.
		id = "mycelium",
		name = "MYCELIUM",
		desc = "full spore set · slime world",
		items = {
			"skin_spore",
			"world_slime",
			"floor_humus",
			"trail_hypha",
			"gemfx_spore",
			"deathfx_sporulate",
			"sun_ferment",
			"filter_petri",
		},
	},
	{
		-- W9-A (DLC_ROADMAP.md §3): ink in water — blooming ink world.
		id = "inkwell",
		name = "INKWELL",
		desc = "full sumi set · ink world",
		items = {
			"skin_sumi",
			"world_ink",
			"floor_inkwash",
			"trail_ink",
			"gemfx_bleed",
			"deathfx_bloom",
			"sun_inkmoon",
			"filter_sumi",
		},
	},
	{
		-- W9-B (DLC_ROADMAP.md §3): starfield warp — the premium slot's
		-- speed-reactive streak tunnel.
		id = "hyperdrive",
		name = "HYPERDRIVE",
		desc = "full warp set · streak world",
		items = {
			"skin_lightyear",
			"world_warp",
			"floor_darkmatter",
			"trail_warpline",
			"gemfx_starburst",
			"deathfx_signal",
			"sun_warpcore",
			"filter_lightspeed",
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
		floor = Cosmetics.Defaults.floor,
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

-- Weekly drop gate, item-side (§18): membership is a LIST (world_polar sits
-- in two packs), so a shared member's release can't hang on which bundle
-- bundleOf happens to return first — the item is "live" if ANY pack
-- containing it is live, "next" if one is in teaser range, else "later".
-- A closed seasonal pack is NOT a live acquisition path: off-season
-- solstice can't leak world_polar into the shop early.
function Cosmetics.bestRollout(itemId: string): Daily.RolloutStatus
	local list = bundleIndex[itemId]
	if not list then
		return "live"
	end
	local seasonal = Config.Monetization.Seasonal.Bundle
	local seasonalOpen = Daily.seasonalStatus()
	local seenNext = false
	for _, bid in ipairs(list) do
		if bid ~= seasonal or seasonalOpen then
			local s = Daily.rolloutStatus(bid)
			if s == "live" then
				return "live"
			elseif s == "next" then
				seenNext = true
			end
		end
	end
	return if seenNext then "next" else "later"
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
		return Color3.fromHSV((time() * 0.3) % 1, 0.9, 1)
	end
	if param == "palette" or fallback == nil then
		return Palette.neonAt(0)
	end
	return fallback
end

return Cosmetics
