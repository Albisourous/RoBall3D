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

## Items (105 total)

### SKIN — ringA/ringB cage + core (19)

| Item | Look | Price | Bundle |
|---|---|---|---|
| CLASSIC NEON | cyan/magenta | free | — |
| MONO | white/silver | free | — |
| SOLAR FLARE | orange/pink | ◊300 | starter |
| 24K | gold/pale gold | ◊750 | midas |
| PRISM | rainbow fx | ◊750 | synthwave |
| VOID EMPRESS | violet/pink pulse | ◊900 | vip |
| AURORA | teal-green/sky | ◊800 | aurora |
| PHANTOM | white/amethyst pulse | ◊900 | polaris |
| FROSTBITE | frost/ice | ◊800 | solstice (seasonal) |
| LAGOON | mint/blue | ◊400 | reef |
| ACID BATH | lime/green | ◊600 | acid |
| CANDY GLOSS | pink/white | ◊400 | — |
| EMBER | orange/gold | ◊400 | — |
| CHROME | silver/white | ◊500 | — |
| CHROMA | strobe fx | ◊1200 | — (prestige) |
| IRIS | wave fx | ◊1100 | — (prestige) |
| COLOR LAB | your hues ×2 | ◊1500 | — (prestige) |
| NULL | pitch core/ghost rings | ◊800 | null |
| SUMMIT | sky-blue/white | ◊800 | peaks |

### TRAIL — wake ribbon (18)

| Item | Look | Price | Bundle |
|---|---|---|---|
| NONE | no trail | free | — |
| PALETTE WAKE | run-wheel hue | free | — |
| ION | cyan | free | — |
| SUNSET | sun-orange | ◊200 | starter |
| BULLION | gold | ◊400 | midas |
| PRISM | rainbow | ◊400 | synthwave |
| ULTRAVIOLET | uv | ◊500 | vip |
| AURORA WAKE | teal-green | ◊450 | aurora |
| SPECTRE | pale violet | ◊500 | polaris |
| FROSTWAKE | ice | ◊450 | solstice (seasonal) |
| VOLT | lime | ◊300 | acid |
| PEACH | peach | ◊250 | — |
| MINT | mint | ◊300 | reef |
| GHOST | white | ◊350 | — |
| INFERNO | orange | ◊300 | — |
| LAB WAKE | your accent hue | ◊1500 | — (prestige) |
| DRIFT | pale grey | ◊450 | null |
| RIDGELINE | sky blue | ◊450 | peaks |

### GEM FX — pickup flourish (17)

Same families/prices as trails: GOLD POP + COLD POP free; SUNSET→starter,
JACKPOT→midas, PRISM→synthwave, AMETHYST→vip, AURORA→aurora,
SPECTRE→polaris, FROST→solstice, NULL POP→null, PEAK POP→peaks
(◊200–500, bundled); VOLT→acid, MINT→reef; PEACH/GHOST/INFERNO
(◊250–350, à-la-carte); LAB POP ◊1500 (prestige).

### DEATH FX — run-end burst (16)

| Item | Style | Price | Bundle |
|---|---|---|---|
| SHATTER | shards out | free | — |
| WHITEOUT | pop | free | — |
| SUPERNOVA | nova | ◊500 | starter |
| COLLAPSE | implode | ◊500 | midas |
| EVENT HORIZON | implode | ◊600 | vip |
| BOREALIS | nova | ◊600 | aurora |
| STATIC | shatter | ◊650 | polaris |
| AVALANCHE | shatter | ◊600 | solstice (seasonal) |
| GEYSER | geyser | ◊550 | reef |
| MELTDOWN | geyser | ◊600 | acid |
| CORONA | corona | ◊650 | — |
| ULTRAVIOLET | corona | ◊650 | synthwave |
| PINK SLIP | pop | ◊500 | — |
| LIMEWIRE | shatter | ◊550 | — |
| FADE | pop | ◊550 | null |
| LANDSLIDE | shatter | ◊550 | peaks |

### WORLD — side-scenery theme (11)

| Item | Look | Price | Bundle |
|---|---|---|---|
| NEON CITY | tower canyon | free | — |
| NEON PEAKS | wireframe ridges | ◊800 | peaks |
| STAR WELL | mote shell | ◊800 | vip |
| GRID PLANE | wireframe floor | ◊800 | synthwave |
| BOREALIS SKY | aurora curtains | ◊900 | aurora |
| NEON REEF | strand field | ◊800 | reef |
| METEOR SHOWER | animated streaks | ◊900 | midas |
| MIAMI NIGHTS | neon palm grove | ◊800 | starter |
| NORTHERN LIGHTS | particle-canopy aurora + stars | ◊900 | polaris + solstice |
| VOIDSPACE | empty — lane + sun only | ◊900 | null |
| TOXIC WASTES | rising acid bubbles | ◊800 | acid |

### SUN — striped horizon disk (12)

| Item | Look | Price | Bundle |
|---|---|---|---|
| SYNTH SUN | orange→pink strips | free | — |
| PALE MOON | pale solid disk | ◊400 | aurora |
| ACID SUN | lime→green strips | ◊500 | acid |
| PRISM RISE | cyan→magenta strips | ◊600 | starter |
| WIREFRAME SUN | sparse wire grid | ◊700 | synthwave |
| 24K NOON | solid gold disk | ◊750 | midas |
| ECLIPSE | violet corona | ◊800 | vip |
| POLAR CAP | frost→ice blue | ◊600 | solstice (seasonal) |
| HALO RISE | thin spectral ring | ◊600 | polaris |
| NEAP TIDE | cyan→deep blue | ◊600 | reef |
| DEAD SUN | sparse ghost strips | ◊600 | null |
| ALPINE SUN | cyan→violet strips | ◊600 | peaks |

### FILTER — screen overlay (12)

| Item | Look | Price | Bundle |
|---|---|---|---|
| CLEAN | no overlay | free | — |
| SCANLINES | CRT raster bars | ◊450 | starter |
| PHOSPHOR | fine dense raster | ◊450 | polaris |
| PIXEL GLASS | LCD lattice | ◊600 | synthwave |
| VIGNETTE | dark edge falloff | ◊550 | vip |
| GOLD HOUR | warm gold grade | ◊500 | midas |
| VERDANT VEIL | aurora-green grade | ◊500 | aurora |
| TOXIN | lime grade | ◊500 | acid |
| ABYSS | deep-ice grade | ◊550 | reef |
| SNOWBLIND | frost grade | ◊550 | solstice (seasonal) |
| SOOT | grey desat grade | ◊500 | null |
| THIN AIR | pale blue grade | ◊500 | peaks |

---

## Bundle passes (11 + 1 perk)

Every pack is a complete outfit — exactly one item per STYLE slot, so
the preview can render the whole look and nothing in the box is filler.

| Pass | Contents | Suggested R$ |
|---|---|---|
| STARTER NEON | SOLAR FLARE · MIAMI NIGHTS · SUNSET trail · SUNSET POP · SUPERNOVA · PRISM RISE · SCANLINES | 49 |
| NEON PEAKS | SUMMIT · NEON PEAKS world · RIDGELINE · PEAK POP · LANDSLIDE · ALPINE SUN · THIN AIR | 149 |
| SYNTHWAVE | PRISM · GRID PLANE · PRISM trail · PRISM POP · ULTRAVIOLET · WIREFRAME SUN · PIXEL GLASS | 149 |
| MIDAS | 24K · METEOR SHOWER · BULLION · JACKPOT · COLLAPSE · 24K NOON · GOLD HOUR | 149 |
| VOID VIP | VOID EMPRESS · STAR WELL · ULTRAVIOLET trail · AMETHYST · EVENT HORIZON · ECLIPSE · VIGNETTE | 199 |
| AURORA | AURORA · BOREALIS SKY · AURORA WAKE · AURORA POP · BOREALIS · PALE MOON · VERDANT VEIL | 149 |
| POLARIS | PHANTOM · NORTHERN LIGHTS · SPECTRE trail · SPECTRE POP · STATIC · HALO RISE · PHOSPHOR | 149 |
| TOXIC SLUDGE | ACID BATH · TOXIC WASTES · VOLT trail · VOLT POP · MELTDOWN · ACID SUN · TOXIN | 149 |
| NEON REEF | LAGOON · NEON REEF world · MINT trail · MINT POP · GEYSER · NEAP TIDE · ABYSS | 199 |
| NULL | NULL · VOIDSPACE · DRIFT · NULL POP · FADE · DEAD SUN · SOOT | 149 |
| SOLSTICE | FROSTBITE · NORTHERN LIGHTS · FROSTWAKE · FROST POP · AVALANCHE · POLAR CAP · SNOWBLIND (seasonal) | 149 |
| 2X BANK | permanent 2× bank perk | 99 |

Retired passes — no longer sold, but `Cosmetics.LegacyBundles` keeps
every already-sold pass granting its original contents forever:
`phantom`, `deepspace`, `inferno`, `candy`, `colorlab`, `sunkissed`,
`miami`, `vhs`. Their items folded into the new packs or back to
à-la-carte gem buys. (The old world-only `peaks` pass came back as the
full NEON PEAKS set — same pass key, so early buyers keep their world
and get the whole outfit.)

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
- **Bundle vs grind**: à-la-carte totals (◊3300–◊4000 per 7-item set)
  always sit well above the pass price, so the bundle reads as the deal
  and the grind reads as fair. World items are the premium à-la-carte
  tier (◊800–900).
- **Complete sets only**: every pass carries exactly one item per STYLE
  slot — a head-to-toe outfit the garage preview can render whole when
  the pack is tapped. Partial sets don't sell because a pack that
  "includes a world you don't want" reads as filler; one-of-each never
  does. NORTHERN LIGHTS is the one shared member (POLARIS shelf +
  SOLSTICE window) — `bundleOf` resolves shared items to the
  non-seasonal pack so the sky stays buyable year-round.
- **Prestige singles**: CHROMA/IRIS/COLOR LAB singles (◊1100–1500) stay
  OUT of value bundles — the gem sink for grinders. The lab items moved
  à-la-carte when packs went full-set; the retired `colorlab` pass still
  grants all three via `LegacyBundles`.
- **Worlds drive passes**: every world theme anchors exactly one pack so
  the most visible flex (whole-sky swap) monetizes as DLC, with à-la-carte
  gems as the patient path.
- **Seasonal**: one rotating gated bundle (SOLSTICE) — scarcity on
  acquisition, permanent on ownership. Rotate the slot quarterly.

## Live-ops checklist

1. Create the 11 passes + bank2x + 3 products on the Creator Dashboard
   at the prices above; drop ids into `Config.Monetization.Passes` /
   `.Products`.
2. Flip `Config.Monetization.FreeForTesting` off.
3. Rotate `Seasonal.Bundle` each quarter (new seasonal item wave =
   fresh SOLSTICE-class catalog entries).
