# APEBALL.md — arcade-red ball + FLOOR slot

Design spec for the APE BALL deep-cut: a plain **arcade-red** core ball
under white/banana rings (the party-ball color homage), no trail in the
pack, and a new FLOOR cosmetic slot so every pack can restyle the deck
it rolls on.

Rules that still apply: tunables live in `Config`, items are data in
`Cosmetics.luau`, color law (nothing near `LethalColor` 255,32,48), the
diorama mirrors live behavior, and DESIGN.md/DLC.md get updated in the
same commit (§18, the Ball/Track art bullets, the catalog).

---

## 1. SMB REA findings (reference analysis)

Same method as DESIGN.md §2's Slope REA. Reference implementation:
**WebMonkeyBall** (`github.com/sndrec/WebMonkeyBall`, a TypeScript port
of the SMB decomp) — the ape-in-ball logic lives in
`src/physics.ts` (`updateBallApeBasis`, `updateApeBaseOrientation`,
`updateApeFromVelocity`, `updateApeSpinCompensation`,
`updateApeOrientation`, ~lines 340–610). Clone for reference:
`git clone --depth 1 https://github.com/sndrec/WebMonkeyBall /tmp/WebMonkeyBall`.

What the decomp actually does, in its own terms:

- **`apeQuat` is the rider's own orientation** — NOT a welded child of
  the ball's spin. Each frame the sim:
  1. computes the ball's per-frame rotation delta along its
     dominant axis (`unkA8` via `updateBallApeBasis` — quatFromDirs on
     the prev→current basis axis that changed most),
  2. applies only a **~65% damped share** of that tumble to the ape
     (`updateApeBaseOrientation` — so the rider shudders with hard spins
     but is not slaved to them),
  3. **re-uprights toward world +Y** incrementally (small
     quatFromAxisAngle nudges — ~5°-class s16 steps, i.e. soft tracking
     not a snap),
  4. **yaws the rider to face the horizontal velocity direction**
     (`updateApeFromVelocity`), blended in over a speed gate (blend 0
     below ~0.23 u/s, full by ~0.37 u/s at ball radius 0.5),
  5. adds yaw **spin compensation while airborne**
     (`updateApeSpinCompensation`).
- **Ball radius 0.5 u; the shell renders translucent ~half-alpha**; the
  GameCube HUD frame shows the rider seen from behind — it faces travel.
- **No wake trail**; **the checkered floor is the star** — the stage IS
  the checkerboard; gem pickups are bananas.

| SMB does | Read it produces | Our port |
|---|---|---|
| ~50% clear shell, red cap half | The arcade-red ball | `skin_capsule` — plain `rgb(235,45,55)` core under white/banana rings (the two-tone CSG shell was removed — see §2) |
| `apeQuat` rider machinery | (rider CUT — see §3) | — |
| No trail; checkered floor | Ball + floor carry the frame | Pack ships no trail; FLOOR slot + CHECKER DECK (below) |

## 2. The ball — plain arcade red

The original two-tone shell spec (half-clear Glass shell + a CSG red
hemisphere cap welded `Massless` at ball center, `CapSeq`-staled async
builds, Glass material/alpha branches in `dress`/`retint`, the diorama's
`vpCap` mirror) was **removed**: an extra welded part riding inside a
client-network-owned ball is one too many physics-adjacent moving pieces
for the homage's value. `skin_capsule` is now an ordinary color skin:

- `core = rgb(235, 45, 55)` — the SMB cap red as the whole ball color.
- `ringA = WHITE`, `ringB = BANANA`, `gemShape = "orb"`.
- `dress`/`retint` treat it identically to every other skin — always
  `Transparency = 0`, `SmoothPlastic`, no extra parts.
- `Config.Art.CapsuleAlpha/CapsuleRed/CapsuleRedAlpha`,
  `BallDress.buildCap`/`syncCap`, the `capsule` item flag, the
  `GeometryService` require, and the `CosmeticFx` `vpCap`/`vpBuildSeq`
  preview rig are all gone.

## 3. The rider — CUT

The original rider (upright toy monkey on an `AlignPosition` +
`AlignOrientation` constraint rig, server-driven yaw goal — a port of
the decomp's `updateApeOrientation`) shipped, worked, and was removed on
request: the primitive monkey didn't read through the shell. The two-
tone shell alone carries the homage now — simpler, and the split
tumbling with the ball is the arcade read anyway. All `Monkey*`/`Rider*`
tunables, `buildInhabitant`, `monkeySpec`, the `Inhabitant`/`RiderOri`
rig, and the Heartbeat goal driver are gone; `Cosmetics.Item` no longer
has an `inhabitant` field.

**Preview** (`CosmeticFx` diorama): nothing extra — the preview ball is
a plain SmoothPlastic sphere wearing the skin's `core` color, like every
other skin.

**Ghosts**: unaffected — echoes are plain neon spheres, never dressed.

## 4. No trail in the pack

- APE BALL bundle items get `trail_none` appended AFTER `trail_banana`:
  `equipBundle` equips in list order so the bundle lands on NONE, while
  `trail_banana` stays in the pack's grant list — pass holders keep it
  in inventory (no clawback — same rule as LegacyBundles).
- `trail_banana` stays in the catalog à-la-carte (◊450).

## 5. FLOOR slot — deck-surface restyle for every pack

New cosmetic slot `"floor"` ("FLOOR" in `Cosmetics.SlotName`, inserted
after `"world"` in `Cosmetics.Slots` — the garage builds one row per
slot automatically).

**Item params** (extend `Cosmetics.Item`):

| Field | Type | Effect |
|---|---|---|
| `deck` | `Color3` | Replaces `Config.Art.DeckColor` in `deckColorAt` — still lerped toward the palette by `DeckTint` unless `deckB` is set |
| `deckB` | `Color3?` | Checker partner color — splits deck slabs into `deckCell` tiles alternating `deck`/`deckB` (no palette lerp — checker stays pure) |
| `deckCell` | `number?` | Checker tile size in studs (~13 reads at speed) |
| `edge` | `Color3?` | Replaces the palette sample on edge rails (flat color per segment) |
| `plain` | `boolean?` | Suppresses transverse grid strips + center line |

**Server** (`TrackStreamer`, mirrors the `gemStyle` pattern):

- `self.deckItem` — the equipped floor `Item`, set by `Main.startRun`
  from `Cosmetics.item(eq.floor)` (same line that sets `gemStyle`).
- `deckColorAt(zMid)` uses `deckItem.deck` as the base when set.
- `emitDeck`: when `deckItem.deckB` + `deckCell`, every deck slab
  (including cutout rail regions) is sub-tiled —
  `ceil(span/deckCell) × ceil(width/deckCell)` parts alternating
  `deck`/`deckB` on `(row + col) % 2`. Flat items keep today's merged
  one-slab emission.
- `edge` overrides the `Palette.neonAt` sample on edge strips; `plain`
  skips the transverse grid + center-line strips.
- Mid-run floor equips stamp future chunks only (same as `gemStyle`).

**Client** (`CosmeticFx.makeLane`): reads `items.floor` — same recipe:
flat recolor or the same checker sub-tiling, `plain`/`edge` applied.
Checker tiles are laid at each row's own z on the pitched preview lane
(`deckTopAt(tileZ)` — the same pitch composition `emitDeck` uses), so
the board sits flush on the slope rather than stepping per row.

**Catalog** (14 items — every pack gets one):

| Item | Name | Look | Price | Bundle |
|---|---|---|---|---|
| floor_neon | NEON DECK | current purple-black + palette drift (default) | free | — |
| floor_slate | SLATE | cool grey deck | free | — |
| floor_dusk | DUSK TILE | deep sunset plum | ◊250 | starter |
| floor_glacier | GLACIER | deep alpine blue | ◊350 | peaks |
| floor_wire | WIRE DECK | synth-violet dark | ◊350 | synthwave |
| floor_gilt | GILT | dark burnished gold | ◊350 | midas |
| floor_void | VOID TILE | violet-black | ◊350 | vip |
| floor_boreal | BOREALIS DECK | deep aurora teal | ◊350 | aurora |
| floor_spectre | SPECTRAL | pale-violet dark | ◊350 | polaris |
| floor_frost | FROST TILE | deep ice | ◊350 | solstice |
| floor_sludge | SLUDGE | dark lime | ◊300 | acid |
| floor_trench | TRENCH | deep sea blue | ◊350 | reef |
| floor_blackout | BLACKOUT | pitch | ◊350 | null |
| floor_check | CHECKER DECK | `SkyFloorA`/`SkyFloorB` checker, cell 13, `plain`, dark-green `edge` | ◊450 | apeball |

Non-checker floors stay **dark** — the neon grid carries the read and
lethal red stays singular. `floor_check` is the licensed exception (the
homage). Add a `floor` row to `Cosmetics.Order` and
`Cosmetics.Defaults.floor = "floor_neon"`. Profile loads already merge
missing slots from defaults — no migration.

**APE BALL bundle** final item list:
`skin_capsule`, `world_sky`, `floor_check`, `trail_banana`,
`trail_none`, `gemfx_banana`, `deathfx_party`, `sun_noon`, `filter_day`.

`world_sky`'s SKY COURT backdrop (`Backdrop.luau` `"sky"` theme): the
whole world midday-arcade-blue, floating palm-topped islets, giant
gold/ivory **goal arches** straddling the lane that the ball threads
(the SMB finish-gate homage), puff clouds, and a day-palm grove.

All other bundles append their floor item (8 items each).

## 6. File map

| Workstream | Files |
|---|---|
| Deck | `Config.luau` (Art block), `TrackStreamer.luau` |
| Catalog | `Cosmetics.luau`, `BallDress.luau` |
| Client mirror | `CosmeticFx.luau` |
| Docs (integration pass) | `DESIGN.md` §18 + Ball/Track bullets, `DLC.md` items + APE BALL row |

## 7. Test plan

- `stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl`
- MCP playtest (debug seed `flat`, capsule + floor_check equipped):
  the ball is plain red under white/banana rings — no extra parts on it.
- Garage preview: same plain red diorama ball;
  `floor_check` lane renders as green/dark-green checker.
