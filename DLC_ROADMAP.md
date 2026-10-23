# DLC Roadmap — release schedule & pipeline

The canonical tracking doc for DLC logic. `DLC.md` stays the *catalog*
(what exists, prices, contents); this file tracks *when packs go live*,
*what's being designed*, and *how a pack ships*. Keep both honest in the
same commit — spec and code never drift (AGENTS.md rule 1).

---

## 1. Rollout mechanics (implemented)

Two packs per week, staggered forever. `Config.Monetization.Rollout`:

- `Start = { 2026, 10, 26 }` — UTC date wave 1 opens (**set to launch
  day**). Week `w` unlocks at `Start + (w-1)·7d`, 00:00 UTC. Changing the
  schedule is a data edit, not a republish — waves self-open.
- `Weeks = { { idA, idB }, ... }` — two bundle ids per wave.
- `Daily.rolloutStatus(bundleId, t?)` → `"live" | "next" | "later"` +
  days — the ONE shared gate, pure UTC math like `seasonalStatus`, so
  client display and server enforcement can never disagree.

| status | garage row | member items | server |
|---|---|---|---|
| `live` | normal price flow | browsable, buyable | sells |
| `next` | visible, `IN Nd` teaser, buy disabled | browsable (hype); clicks funnel to the pack row | refuses claim + à-la-carte |
| `later` | **hidden** — no row at all | filtered out of slot browse entirely | refuses claim + à-la-carte |

- `Config.Debug.Enabled = true` → every wave live (dev sees the full
  schedule). `FreeForTesting` still controls the purchase path on top.
- Unscheduled bundles are always-live — **SOLSTICE is deliberately not
  in any wave**; its `Seasonal` yearly window gates it instead.
- Owned unreleased packs (only possible via debug claims) stay visible
  and usable — the gate blocks acquisition, never use.
- Item-side membership is a list, not a scalar:
  `Cosmetics.bestRollout(itemId)` returns `live` if ANY containing pack
  is live — so shared members (e.g. `world_polar` in `polaris` +
  `solstice`) can't hide behind whichever bundle `bundleOf` lists first,
  and a closed seasonal window doesn't count as a live path.
- Platform caveat: once a real gamepass id exists, a player could buy it
  through the Roblox website regardless of in-game visibility. Harmless
  (ownership is derived from `UserOwnsGamePassAsync`), but don't create
  dashboard ids until the wave approaches — see checklist step 8.

## 2. Release schedule (canonical — mirrors `Rollout.Weeks`)

Drops land Mondays 00:00 UTC. Order alternates price tiers and mood
(dark↔bright, neon↔organic) so every wave reads as variety, not residue.

| Wave | Opens (UTC) | Pack A | Pack B | Status |
|---|---|---|---|---|
| W1 | 2026-10-26 | STARTER NEON `starter` ◊149→R$49 | SYNTHWAVE `synthwave` R$149 | shipped |
| W2 | 2026-11-02 | MIDAS `midas` R$149 | NEON PEAKS `peaks` R$149 | shipped |
| W3 | 2026-11-09 | AURORA `aurora` R$149 | NEON REEF `reef` R$199 | shipped |
| W4 | 2026-11-16 | VOID VIP `vip` R$199 | NULL `null` R$149 | shipped |
| W5 | 2026-11-23 | POLARIS `polaris` R$149 | APE BALL `apeball` R$199 | shipped |
| W6 | 2026-11-30 | MAINFRAME `mainframe` R$149 | FESTIVAL `festival` R$149 | **built** |
| W7 | 2026-12-07 | HYPNOTUBE `hypnotube` R$149 | CATHEDRAL `cathedral` R$199 | **designed** (§3) |
| W8 | 2026-12-14 | PAPERCRAFT `papercraft` R$149 | MYCELIUM `mycelium` R$149 | **designed** (§3) |
| W9 | 2026-12-21 | INKWELL `inkwell` R$149 | HYPERDRIVE `hyperdrive` R$199 | **designed** (§3) |
| W10 | 2026-12-28 | MERCURY `mercury` R$199 | KALEIDO `kaleido` R$199 | **designed** (§3) |
| — | Dec 15–Jan 8 | SOLSTICE `solstice` R$149 | (seasonal window, not a wave) | shipped |

- W1 is the launch wave — if launch wants more shelf depth, promote W2
  into W1 (edit `Weeks`; keep ≤2/wave after that).
- After W10: extend `Weeks` with the next pair (new designs below run
  out). Keep the seasonal slot rotating quarterly per DLC.md.
- **Wave log** — when a wave opens, append the flip here:
  `| W6 | 2026-11-30 | live | commit … |`.

## 3. Designed packs (animation-style wave — spec only, NOT in code)

Inspiration: shader/procedural animation styles (aurora gradient, matrix
rain, starfield warp, chrome metal, fireworks, wireframe terrain, origami
fold, water ripples, infinite tunnel, stained glass, ink in water,
kaleidoscope, spirograph, voronoi cells, smoke sim, boids, reaction
diffusion, slime mold). Aurora/wireframe/city/water are already shipped
themes — these ten fill **new** visual territory. Every pack keeps the
complete-look rule: one item per slot, all inside color law (nothing
near `LethalColor` 255,32,48). "New code" column = what a designer must
build beyond data records.

### W6 — MAINFRAME `mainframe` (matrix rain) — R$149
Green phosphor terminal world — dense falling code-rain.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_mainframe` | ringA `(80,255,120)` phosphor, ringB `(190,255,220)`, core `(10,26,14)`; `fx="pulse"`; `gemShape="rod"` |
| world | `world_matrix` | `theme="matrix"` — falling neon-green bar columns w/ bright heads, recycled on frontier (meteor-streak recycle, vertical axis) + dim far field |
| floor | `floor_matrix` | `deck=(8,14,10)`, `edge=(80,255,120)` |
| trail | `trail_stream` | `color=(80,255,120)` |
| gemFx | `gemfx_decrypt` | `color=(140,255,180)` |
| deathFx | `deathfx_segfault` | `style="shatter"`, A `(80,255,120)` / B `(190,255,220)` |
| sun | `sun_cursor` | `sun="cursor"` — TERMINAL SUN: solid pale-green block `(190,255,220)/(60,200,110)`, solid .85 |
| filter | `filter_terminal` | `filter="scan"`, `pitch=6`, `bar=1`, `alpha=.28` |

New code: Backdrop theme `matrix`, `SunStyles.cursor`.

### W6 — FESTIVAL `festival` (fireworks) — R$149
Night-fair world — real ParticleEmitter firework bursts + lantern rows.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_pyro` | ringA `(255,176,64)` ember, ringB `(90,110,200)` dusk, core `(24,18,30)`; `gemShape="orb"` (shells) |
| world | `world_fireworks` | `theme="fireworks"` — periodic emitter bursts at random azimuth/elevation beside the lane + smoke wisps + sagging lantern strings (palm-row recycle cadence) |
| floor | `floor_street` | `deck=(14,14,22)`, `edge=(255,190,90)` |
| trail | `trail_sparkler` | `color=(255,226,140)` hot gold |
| gemFx | `gemfx_burst` | `color=(255,176,64)` |
| deathFx | `deathfx_finale` | `style="nova"`, A `(255,176,64)` / B `(255,212,64)` |
| sun | `sun_lantern` | `sun="lantern"` — warm disk `(255,200,140)/(200,120,80)`, solid .85 |
| filter | `filter_duskhaze` | `filter="tint"`, `tint=(120,100,180)`, `alpha=.12` |

New code: Backdrop theme `fireworks` (canonical ParticleEmitter bursts),
`SunStyles.lantern`.

### W7 — HYPNOTUBE `hypnotube` (infinite tunnel) — R$149
Endless hoop tunnel — the cheapest new world: it reuses the SKY COURT
goal-arch recycling machinery.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_spiral` | ringA `(0,230,255)`, ringB `(175,80,255)`, core `(18,14,40)`; `fx="wave"`; `gemShape="coin"` (hoops) |
| world | `world_tunnel` | `theme="tunnel"` — dense concentric neon hoops threaded down the course, hue-walking down the chain, recycled ahead like `sky`'s arches |
| floor | `floor_tube` | `deck=(10,10,24)`, `edge=(0,230,255)` |
| trail | `trail_vortex` | `color=(175,80,255)` |
| gemFx | `gemfx_hoop` | `color=(140,140,255)` |
| deathFx | `deathfx_unwind` | `style="corona"`, A `(0,230,255)` / B `(175,80,255)` |
| sun | `sun_aperture` | `sun="aperture"` — thin ring `(0,230,255)/(255,64,190)`, solid .18, gap .25 |
| filter | `filter_hypnosis` | `filter="tint"`, `tint=(60,50,120)`, `alpha=.14` |

New code: Backdrop theme `tunnel` (arch-recycle reuse), `SunStyles.aperture`.

### W7 — CATHEDRAL `cathedral` (stained glass) — R$199
Rose-window sun + jewel-pane world — the wave's premium slot.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_leaded` | ringA `(255,212,64)` gold-lead, ringB `(255,64,190)` jewel, core `(240,230,210)` ivory; `gemShape="shard"` |
| world | `world_glass` | `theme="glass"` — tall jewel-tone pane columns + pointed-arch silhouettes floating beside the track, translucent colored light shafts |
| floor | `floor_nave` | `deckB` checker `(40,44,64)/(26,28,44)`, `deckCell=12`, `edge=(255,212,64)` |
| trail | `trail_censer` | `color=(255,190,90)` amber |
| gemFx | `gemfx_glint` | `color=(255,212,64)` |
| deathFx | `deathfx_rosefall` | `style="shatter"`, A `(255,64,190)` / B `(255,212,64)` |
| sun | `sun_rose` | `sun="rose"` — ROSE WINDOW `(255,190,90)/(200,60,160)`, solid .5 |
| filter | `filter_sanctuary` | `filter="tint"`, `tint=(255,210,140)`, `alpha=.10` |

New code: Backdrop theme `glass`, `SunStyles.rose`.

### W8 — PAPERCRAFT `papercraft` (origami fold) — R$149
Flat-shaded paper world — cranes, faceted islets, warm matte grade.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_fold` | ringA `(255,244,228)` paper, ringB `(255,150,120)` clay, core `(235,225,205)`; `gemShape="shard"` (folded facets) |
| world | `world_paper` | `theme="paper"` — floating origami cranes + faceted pastel wedge islets drifting beside the lane, occasional paper-plane flyby |
| floor | `floor_kraft` | `deck=(46,34,28)` dark kraft, `edge=(255,244,228)` |
| trail | `trail_crease` | `color=(255,240,220)` |
| gemFx | `gemfx_paper` | `color=(255,180,150)` |
| deathFx | `deathfx_unfold` | `style="shatter"`, A `(255,244,228)` / B `(255,150,120)` |
| sun | `sun_paper` | `sun="paper"` — flat warm-white disk `(255,244,228)/(220,190,160)`, solid .9 |
| filter | `filter_matte` | `filter="tint"`, `tint=(240,220,190)`, `alpha=.10` |

New code: Backdrop theme `paper`, `SunStyles.paper`.

### W8 — MYCELIUM `mycelium` (slime mold) — R$149
Physarum network world — glowing tendrils creeping along the verge.
(Amber/moss family — distinct from TOXIC SLUDGE's lime.)

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_spore` | ringA `(255,190,60)` honey, ringB `(120,200,90)` moss, core `(16,20,12)`; `fx="pulse"`; `gemShape="orb"` (spore sacs) |
| world | `world_slime` | `theme="slime"` — glowing node beads + thin tendril beams linking them along both verges, light pulses traveling the links (reef-strand lazy pool + beam primitives), spore-mote drift |
| floor | `floor_humus` | `deck=(22,30,18)`, `edge=(255,190,60)` |
| trail | `trail_hypha` | `color=(255,200,80)` |
| gemFx | `gemfx_spore` | `color=(200,220,120)` |
| deathFx | `deathfx_sporulate` | `style="geyser"`, A `(255,190,60)` / B `(120,200,90)` — spores erupt up |
| sun | `sun_ferment` | `sun="ferment"` — amber disk `(255,200,80)/(140,100,40)`, solid .7 |
| filter | `filter_petri` | `filter="tint"`, `tint=(150,140,70)`, `alpha=.12` |

New code: Backdrop theme `slime`, `SunStyles.ferment`.

### W9 — INKWELL `inkwell` (ink in water) — R$149
Deep-indigo fluid world — slow ink blooms in dark water-light.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_sumi` | ringA `(70,80,200)` indigo, ringB `(220,225,240)` ink-white, core `(14,16,36)`; `fx="wave"`; `gemShape="orb"` (drops) |
| world | `world_ink` | `theme="ink"` — large soft translucent spheres/particles expanding + fading beside the lane (grow-shrink lifecycle), darker drop columns falling past |
| floor | `floor_inkwash` | `deck=(16,18,34)`, `edge=(200,205,230)` |
| trail | `trail_ink` | `color=(80,70,160)` |
| gemFx | `gemfx_bleed` | `color=(110,100,220)` |
| deathFx | `deathfx_bloom` | `style="implode"`, A `(70,80,200)` / B `(220,225,240)` — collapses then blooms |
| sun | `sun_inkmoon` | `sun="inkmoon"` — pale lavender-grey `(220,220,240)/(120,120,160)`, solid .9 |
| filter | `filter_sumi` | `filter="tint"`, `tint=(60,60,90)`, `alpha=.14` |

New code: Backdrop theme `ink`, `SunStyles.inkmoon`.

### W9 — HYPERDRIVE `hyperdrive` (starfield warp) — R$199
Radial star-streak tunnel — motes *with velocity*, distinct from STAR
WELL's static shell.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_lightyear` | ringA `(245,248,255)` white-hot, ringB `(0,230,255)`, core `(10,14,34)`; `fx="strobe"`; `gemShape="rod"` (streaks) |
| world | `world_warp` | `theme="warp"` — thin long streak parts streaming outward from the descent axis around the lane; density ramps with speed tier |
| floor | `floor_darkmatter` | `deck=(10,12,26)`, `edge=(160,240,255)` |
| trail | `trail_warpline` | `color=(160,240,255)` |
| gemFx | `gemfx_starburst` | `color=(220,245,255)` |
| deathFx | `deathfx_signal` | `style="nova"`, A `(245,248,255)` / B `(0,230,255)` — SIGNAL LOST |
| sun | `sun_warpcore` | `sun="warpcore"` — white-hot disk `(245,248,255)/(120,200,255)`, solid .8 |
| filter | `filter_lightspeed` | `filter="tint"`, `tint=(140,220,255)`, `alpha=.10` |

New code: Backdrop theme `warp`, `SunStyles.warpcore`.

### W10 — MERCURY `mercury` (chrome metal) — R$199
Liquid-metal world — chrome dunes and mirror pools. À-la-carte CHROME
skin stays a single; this pack's own look is mirror-finish.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_mercury` | ringA `(220,230,240)` bright silver, ringB `(140,150,190)` slate, core `(200,210,225)`; `fx="wave"`; `gemShape="orb"` (droplets) |
| world | `world_chrome` | `theme="chrome"` — slow undulating low-poly mounds + mirror pools flanking the lane, cool white rim glints |
| floor | `floor_chromedeck` | `deck=(24,26,34)` gunmetal, `edge=(200,210,225)` |
| trail | `trail_quicksilver` | `color=(190,200,220)` |
| gemFx | `gemfx_chrome` | `color=(220,230,240)` |
| deathFx | `deathfx_liquidate` | `style="implode"`, A `(220,230,240)` / B `(140,150,190)` |
| sun | `sun_platinum` | `sun="platinum"` — solid silver disk `(235,240,250)/(150,160,180)`, solid .92 |
| filter | `filter_polish` | `filter="tint"`, `tint=(140,150,175)`, `alpha=.10` |

New code: Backdrop theme `chrome`, `SunStyles.platinum`.

### W10 — KALEIDO `kaleido` (kaleidoscope) — R$199
Mirrored mandala world — the schedule's prestige anchor and heaviest
build; a real rotating wedge-array around the descent axis.

| Slot | Item id | Spec |
|---|---|---|
| skin | `skin_kaleido` | ringA `(255,64,190)`, ringB `(0,230,255)`, core `(30,20,50)`; `fx="rainbow"`; `gemShape="diamond"` |
| world | `world_kaleido` | `theme="kaleido"` — mirrored wedge mandala segments rotating slowly around the descent axis (prestige — budget the renderer) |
| floor | `floor_shard` | `deck=(20,14,36)`, `edge=(255,64,190)` |
| trail | `trail_tumble` | `color="rainbow"` |
| gemFx | `gemfx_facet` | `color="rainbow"` |
| deathFx | `deathfx_prismbreak` | `style="shatter"`, A `(255,64,190)` / B `(0,230,255)` |
| sun | `sun_mandala` | `sun="mandala"` — `(255,64,190)/(0,230,255)`, solid .4, gap .3 |
| filter | `filter_prismatic` | `filter="tint"`, `tint=(160,80,200)`, `alpha=.10` |

New code: Backdrop theme `kaleido` (the one heavy lift), `SunStyles.mandala`.

### Folded-in styles (not standalone packs)

- **aurora gradient** → shipped (AURORA world/filter).
- **wireframe terrain / isometric city** → shipped (NEON PEAKS / NEON CITY).
- **water ripples** → shipped-adjacent (NEON REEF); reserve for a future
  gemFx "RIPPLE" ring burst.
- **low poly 3D** → technique inside PAPERCRAFT + SKY COURT islets.
- **smoke simulation** → wisp accents inside FESTIVAL's fireworks world.
- **reaction diffusion / voronoi cells** → motif seeds for MYCELIUM
  floor/coral patterns; a voronoi-crack floor needs a texture path —
  park until a `deckTex` param exists.
- **spirograph** → HYPNOTUBE's `aperture` ring-sun + hoop accents.
- **boids flocking** → held as a future world (`theme="flock"`, pooled
  wedge steering) — cut from this wave to keep each new theme shippable
  in one pass; first candidate if a W11 opens.

## 4. Ship-a-pack checklist (one commit per wave)

1. Item records into `Cosmetics.Items` (8 slots, ids per §3) + append to
   `Cosmetics.Order` in the right slot lists.
2. `Config.Art.SunStyles.<key>` entry for the pack's sun.
3. Backdrop: `Theme` union + `THEMES` map + `build`/`update` branches for
   the new world theme (lazy-build contract — pooled parts only).
4. `Cosmetics.Bundles += { id, name, desc, items }` — 8 members.
5. `Config.Monetization.Passes[id] = 0` + `Price[id]` (already listed in
   `Rollout.Weeks` — verify the wave index, don't re-slot).
6. `gemPrice` on every member (worlds ◊800–900, suns ◊400–800, rest
   ◊200–600) — à-la-carte total must stay well above pass price.
7. Gates: `stylua --check src/ && selene src/ && rojo build`, MCP
   playtest, screenshot the garage row + diorama preview.
8. On wave week: create the gamepass on the Creator Dashboard, drop the
   real id into `Passes`, publish. Create ids only as waves approach —
   dashboard purchases bypass in-game visibility.
9. Log it in §2's wave log + TRACKER.md.

## 5. Debug/dev behavior

- `Config.Debug.Enabled = true` → `rolloutStatus` returns `"live"` for
  every wave: all rows visible, all claims allowed. Studio dev always
  sees the full catalog — the schedule only bites with Debug off.
- `FreeForTesting = true` → released packs claim FREE instantly;
  unreleased waves still refuse unless Debug is also on (dev combo =
  everything free AND visible).
- To rehearse a wave flip without touching `Start`: Studio console →
  `Daily.rolloutStatus("mainframe", os.time() + 7*86400)`.
