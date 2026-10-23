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

## Items (126 total)

### SKIN — ringA/ringB cage + core + `gemShape` (20)

Every skin pins its pickups' silhouette for the run (§8.4) — the Gems
column is that shape. Worth still reads on tier scale + tint.

| Item | Look | Gems | Price | Bundle |
|---|---|---|---|---|
| CLASSIC NEON | cyan/magenta | diamond | free | — |
| MONO | white/silver | orb | free | — |
| SOLAR FLARE | orange/pink | shard | ◊300 | starter |
| 24K | gold/pale gold | coin | ◊750 | midas |
| PRISM | rainbow fx | diamond | ◊750 | synthwave |
| VOID EMPRESS | violet/pink pulse | crown | ◊900 | vip |
| AURORA | teal-green/sky | rod | ◊800 | aurora |
| PHANTOM | white/amethyst pulse | shard | ◊900 | polaris |
| FROSTBITE | frost/ice | shard | ◊800 | solstice (seasonal) |
| LAGOON | mint/blue | orb | ◊400 | reef |
| ACID BATH | lime/green | rod | ◊600 | acid |
| CANDY GLOSS | pink/white | orb | ◊400 | — |
| EMBER | orange/gold | rod | ◊400 | — |
| CHROME | silver/white | coin | ◊500 | — |
| CHROMA | strobe fx | crown | ◊1200 | — (prestige) |
| IRIS | wave fx | orb | ◊1100 | — (prestige) |
| COLOR LAB | your hues ×2 | diamond | ◊1500 | — (prestige) |
| NULL | pitch core/ghost rings | diamond | ◊800 | null |
| SUMMIT | sky-blue/white | shard | ◊800 | peaks |
| CAPSULE | 50/50 shell — red cap / clear bottom | orb | ◊800 | apeball |

### TRAIL — wake ribbon (19)

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
| BANANA WAKE | banana yellow | ◊450 | apeball |

### GEM FX — pickup flourish (18)

Same families/prices as trails: GOLD POP + COLD POP free; SUNSET→starter,
JACKPOT→midas, PRISM→synthwave, AMETHYST→vip, AURORA→aurora,
SPECTRE→polaris, FROST→solstice, NULL POP→null, PEAK POP→peaks,
BANANA POP→apeball (◊200–500, bundled); VOLT→acid, MINT→reef;
PEACH/GHOST/INFERNO (◊250–350, à-la-carte); LAB POP ◊1500 (prestige).

### DEATH FX — run-end burst (17)

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
| PARTY POP | pop | ◊550 | apeball |

### WORLD — side-scenery theme (12)

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
| SKY COURT | day sky + islets + goal arches + clouds | ◊900 | apeball |

### FLOOR — deck-surface restyle (14)

`deck` re-bases the slab tint; `deckB`+`deckCell` tile the deck into a
pure two-tone checker; `edge` pins rail color; `plain` drops the grid +
center line. All non-checker floors stay dark — the neon grid carries
the read and lethal red stays singular.

| Item | Look | Price | Bundle |
|---|---|---|---|
| NEON DECK | purple-black + palette drift (current look) | free | — |
| SLATE | cool grey | free | — |
| DUSK TILE | deep sunset plum | ◊250 | starter |
| GLACIER | deep alpine blue | ◊350 | peaks |
| WIRE DECK | synth-violet dark | ◊350 | synthwave |
| GILT | dark burnished gold | ◊350 | midas |
| VOID TILE | violet-black | ◊350 | vip |
| BOREALIS DECK | deep aurora teal | ◊350 | aurora |
| SPECTRAL | pale-violet dark | ◊350 | polaris |
| FROST TILE | deep ice | ◊350 | solstice (seasonal) |
| SLUDGE | dark lime | ◊300 | acid |
| TRENCH | deep sea blue | ◊350 | reef |
| BLACKOUT | pitch | ◊350 | null |
| CHECKER DECK | green/dark-green checker + dark-green rails, no grid | ◊450 | apeball |

### SUN — striped horizon disk (13)

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
| HIGH NOON | solid warm noon disk | ◊600 | apeball |

### FILTER — screen overlay (13)

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
| DAY GLOW | pale-sky grade | ◊500 | apeball |

---

## Bundle passes (12 + 1 perk)

Every pack is a complete outfit — exactly one item per STYLE slot, so
the preview can render the whole look and nothing in the box is filler.

| Pass | Contents | Suggested R$ |
|---|---|---|
| STARTER NEON | SOLAR FLARE · MIAMI NIGHTS · DUSK TILE floor · SUNSET trail · SUNSET POP · SUPERNOVA · PRISM RISE · SCANLINES | 49 |
| NEON PEAKS | SUMMIT · NEON PEAKS world · GLACIER floor · RIDGELINE · PEAK POP · LANDSLIDE · ALPINE SUN · THIN AIR | 149 |
| SYNTHWAVE | PRISM · GRID PLANE · WIRE DECK floor · PRISM trail · PRISM POP · ULTRAVIOLET · WIREFRAME SUN · PIXEL GLASS | 149 |
| MIDAS | 24K · METEOR SHOWER · GILT floor · BULLION · JACKPOT · COLLAPSE · 24K NOON · GOLD HOUR | 149 |
| VOID VIP | VOID EMPRESS · STAR WELL · VOID TILE floor · ULTRAVIOLET trail · AMETHYST · EVENT HORIZON · ECLIPSE · VIGNETTE | 199 |
| AURORA | AURORA · BOREALIS SKY · BOREALIS DECK floor · AURORA WAKE · AURORA POP · BOREALIS · PALE MOON · VERDANT VEIL | 149 |
| POLARIS | PHANTOM · NORTHERN LIGHTS · SPECTRAL floor · SPECTRE trail · SPECTRE POP · STATIC · HALO RISE · PHOSPHOR | 149 |
| TOXIC SLUDGE | ACID BATH · TOXIC WASTES · SLUDGE floor · VOLT trail · VOLT POP · MELTDOWN · ACID SUN · TOXIN | 149 |
| NEON REEF | LAGOON · NEON REEF world · TRENCH floor · MINT trail · MINT POP · GEYSER · NEAP TIDE · ABYSS | 199 |
| NULL | NULL · VOIDSPACE · BLACKOUT floor · DRIFT · NULL POP · FADE · DEAD SUN · SOOT | 149 |
| SOLSTICE | FROSTBITE · NORTHERN LIGHTS · FROST TILE floor · FROSTWAKE · FROST POP · AVALANCHE · POLAR CAP · SNOWBLIND (seasonal) | 149 |
| APE BALL | CAPSULE · SKY COURT world · CHECKER DECK floor · BANANA WAKE · (no trail — `trail_none` lands last) · BANANA POP · PARTY POP · HIGH NOON · DAY GLOW | 199 |
| 2X BANK | permanent 2× bank perk | 99 |

**APE BALL** is the rolling-party-ball homage — the whole world a
bright midday blue, the green/dark-green CHECKER
DECK tiling the lane itself, palm-topped islets floating in the blue,
cartoon clouds, a day-palm grove, a
50/50 glass capsule ball — translucent red top half, clear bottom
half, the split tumbling with the roll (a real CSG hemisphere welded to
the shell, APEBALL.md §2), no wake trail (`trail_none` closes the pack's equip so
the ball rolls clean — BANANA WAKE still grants, owners can re-equip),
and pickups restyled as banana-yellow orbs (the SKY COURT
world's `gemStyle`). All-original set in the genre's spirit —
no borrowed names, characters, art, or audio.

Retired passes — no longer sold, but `Cosmetics.LegacyBundles` keeps
every already-sold pass granting its original contents forever:
`phantom`, `deepspace`, `inferno`, `candy`, `colorlab`, `sunkissed`,
`miami`, `vhs`. Their items folded into the new packs or back to
à-la-carte gem buys. (The old world-only `peaks` pass came back as the
full NEON PEAKS set — same pass key, so early buyers keep their world
and get the whole outfit.)

## Release rollout — 2 packs/week

Passes unlock in weekly waves instead of all at once:
`Config.Monetization.Rollout.Weeks` lists two bundle ids per wave;
`Rollout.Start` is the UTC date wave 1 opens (set it to launch day) and
each wave opens `Start + (w-1)·7d` at 00:00 UTC — no republish needed.
`Daily.rolloutStatus(bundleId)` is the shared gate: **live** packs sell
normally, the **next** wave shows in the garage as `IN Nd` teasers
(buy disabled — the accordion + diorama preview still sell the look),
and **later** waves are hidden entirely — no row, member items filtered
out of slot browse, and the server refuses both bundle claims and
à-la-carte gem buys of their items (acquisition-gated, never use-gated:
owned packs stay usable). `Config.Debug.Enabled` lifts the whole
schedule for dev. SOLSTICE is exempt — it runs its own `Seasonal`
window. The canonical schedule and the designed-but-unshipped pack specs
live in **`DLC_ROADMAP.md`** — future-wave ids are already slotted in
`Weeks`, so shipping a designed pack is data work (items → Order →
bundle → sun/backdrop), not plumbing.

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
- **Bundle vs grind**: à-la-carte totals (◊3600–◊4400 per 8-item set)
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

1. Create the 12 passes + bank2x + 3 products on the Creator Dashboard
   at the prices above; drop ids into `Config.Monetization.Passes` /
   `.Products`.
2. Flip `Config.Monetization.FreeForTesting` off.
3. Rotate `Seasonal.Bundle` each quarter (new seasonal item wave =
   fresh SOLSTICE-class catalog entries).
