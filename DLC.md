# DLC Catalog & Monetization Plan

Cosmetics-only, always. The leaderboard is the replay hook — nothing here
sells power, revives, or score. Every item is a data record in
`Cosmetics.luau`; bundles are game passes (`Config.Monetization.Passes`,
`0` = SOON until created on the Creator Dashboard). Each non-free item
also has a `gemPrice` — the grind path through the banked-gem economy.

**Color law**: nothing may approach `LethalColor` (255,32,48). Player-
picked hues are band-clamped to hue ~20°–340° (`Config.CustomHue`) —
the red seam is cut out of the reachable space on both ends.

---

## Items (81 total)

### SKIN — ringA/ringB cage + core (17)

| Item | Look | Price | Bundle |
|---|---|---|---|
| CLASSIC NEON | cyan/magenta | free | — |
| MONO | white/silver | free | — |
| SOLAR FLARE | orange/pink | ◊300 | starter |
| 24K | gold/pale gold | ◊750 | midas |
| PRISM | rainbow fx | ◊750 | synthwave |
| VOID EMPRESS | violet/pink pulse | ◊900 | vip |
| AURORA | teal-green/sky | ◊800 | aurora |
| PHANTOM | white/amethyst pulse | ◊900 | phantom |
| FROSTBITE | frost/ice | ◊800 | solstice (seasonal) |
| LAGOON | mint/blue | ◊400 | reef |
| ACID BATH | lime/green | ◊600 | acid |
| CANDY GLOSS | pink/white | ◊400 | candy |
| EMBER | orange/gold | ◊400 | inferno |
| CHROME | silver/white | ◊500 | — |
| CHROMA | strobe fx | ◊1200 | — (prestige) |
| IRIS | wave fx | ◊1100 | — (prestige) |
| COLOR LAB | your hues ×2 | ◊1500 | colorlab |

### TRAIL — wake ribbon (15)

| Item | Look | Price | Bundle |
|---|---|---|---|
| PALETTE WAKE | run-wheel hue | free | — |
| ION | cyan | free | — |
| SUNSET | sun-orange | ◊200 | starter |
| BULLION | gold | ◊400 | midas |
| PRISM | rainbow | ◊400 | synthwave |
| ULTRAVIOLET | uv | ◊500 | vip |
| AURORA WAKE | teal-green | ◊450 | aurora |
| SPECTRE | pale violet | ◊500 | phantom |
| FROSTWAKE | ice | ◊450 | solstice (seasonal) |
| VOLT | lime | ◊300 | acid |
| PEACH | peach | ◊250 | candy |
| MINT | mint | ◊300 | reef |
| GHOST | white | ◊350 | — |
| INFERNO | orange | ◊300 | inferno |
| LAB WAKE | your accent hue | ◊1500 | colorlab |

### GEM FX — pickup flourish (15)

Same families/prices as trails: GOLD POP + COLD POP free; SUNSET/JACKPOT/
PRISM/AMETHYST/AURORA/SPECTRE/FROST (◊200–500, bundled); VOLT/PEACH/MINT/
GHOST/INFERNO (◊250–350); LAB POP ◊1500 (colorlab).

### DEATH FX — run-end burst (14)

| Item | Style | Price | Bundle |
|---|---|---|---|
| SHATTER | shards out | free | — |
| WHITEOUT | pop | free | — |
| SUPERNOVA | nova | ◊500 | synthwave |
| COLLAPSE | implode | ◊500 | midas |
| EVENT HORIZON | implode | ◊600 | vip |
| BOREALIS | nova | ◊600 | aurora |
| STATIC | shatter | ◊650 | phantom |
| AVALANCHE | shatter | ◊600 | solstice (seasonal) |
| GEYSER | geyser | ◊550 | — |
| MELTDOWN | geyser | ◊600 | acid |
| CORONA | corona | ◊650 | inferno |
| ULTRAVIOLET | corona | ◊650 | — |
| PINK SLIP | pop | ◊500 | candy |
| LIMEWIRE | shatter | ◊550 | — |

### WORLD — side-scenery theme (9)

| Item | Look | Price | Bundle |
|---|---|---|---|
| NEON CITY | tower canyon | free | — |
| NEON PEAKS | wireframe ridges | ◊800 | peaks |
| STAR WELL | mote shell | ◊800 | deepspace |
| GRID PLANE | wireframe floor | ◊800 | deepspace |
| BOREALIS SKY | aurora curtains | ◊900 | aurora |
| NEON REEF | strand field | ◊800 | reef |
| METEOR SHOWER | animated streaks | ◊900 | deepspace |
| MIAMI NIGHTS | neon palm grove | ◊800 | miami |
| NORTHERN LIGHTS | particle-canopy aurora + stars | ◊900 | polaris |

---

## Bundle passes (18 + 1 perk)

| Pass | Contents | Suggested R$ |
|---|---|---|
| STARTER NEON | solar + sunset trail + pop | 49 |
| SYNTHWAVE | prism set + supernova | 149 |
| MIDAS | gold set + collapse | 149 |
| VOID VIP | void set + event horizon | 199 |
| NEON PEAKS | peaks world | 149 |
| AURORA | aurora set + borealis + BOREALIS SKY | 149 |
| PHANTOM | phantom set + static | 199 |
| DEEP SPACE | 3 worlds: star well, grid, meteor | 149 |
| SOLSTICE | frost set + avalanche (seasonal) | 149 |
| TOXIC SLUDGE | acid set + meltdown | 149 |
| NEON REEF | lagoon set + reef world | 199 |
| INFERNO | ember set + corona | 149 |
| CANDY GLOSS | candy set + pink slip | 149 |
| COLOR LAB | custom-hue skin+trail+pop + sliders | 249 |
| SUNKISSED | eclipse + 24k noon + wireframe suns | 149 |
| MIAMI NIGHTS | palm-grove world + prism sun | 149 |
| VHS DECK | pixel glass + scanline filters | 99 |
| POLARIS | northern-lights world + pale moon | 149 |
| 2X BANK | permanent 2× bank perk | 99 |

## Gem packs (dev products)

| Pack | Grant | R$ |
|---|---|---|
| pouch | ◊300 | 49 |
| cache | ◊800 | 99 |
| vault | ◊2000 | 199 |

---

## Pricing logic (why the numbers look like this)

- **Anchors**: R$49 entry / R$149 standard / R$199 premium / R$249
  feature unlock — a 4-rung ladder players read instantly. Every new
  pass lands on a rung; nothing prices off-ladder.
- **Bundle vs grind**: à-la-carte totals (◊700–◊2500) always sit well
  above the pass price, so the bundle reads as the deal and the grind
  reads as fair. World items are the premium à-la-carte tier (◊800–900).
- **Prestige singles**: CHROMA/IRIS/COLOR LAB singles (◊1100–1500) stay
  OUT of value bundles or price above them — the gem sink for grinders
  and the reason the colorlab pass is a shortcut, not the only door.
- **COLOR LAB at 249**: it's a feature unlock (infinite colors), not a
  fixed look — the top rung, under R$299 so it still feels cosmetic-tier.
- **Worlds drive passes**: every world theme is bundled into a pass so
  the most visible flex (whole-sky swap) monetizes as DLC, with à-la-carte
  gems as the patient path.
- **Seasonal**: one rotating gated bundle (SOLSTICE) — scarcity on
  acquisition, permanent on ownership. Rotate the slot quarterly.

## Live-ops checklist

1. Create the 18 passes + bank2x + 3 products on the Creator Dashboard
   at the prices above; drop ids into `Config.Monetization.Passes` /
   `.Products`.
2. Flip `Config.Monetization.FreeForTesting` off.
3. Rotate `Seasonal.Bundle` each quarter (new seasonal item wave =
   fresh SOLSTICE-class catalog entries).
