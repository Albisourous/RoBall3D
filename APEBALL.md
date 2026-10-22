# APEBALL.md — capsule rider + FLOOR slot

Design spec for the APE BALL deep-cut: a true party-ball capsule (50/50
clear shell, a monkey that *rides* like the genre's instead of tumbling
like a capsule toy), no trail in the pack, and a new FLOOR cosmetic slot
so every pack can restyle the deck it rolls on.

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
| `apeQuat` counter-rotates vs ball spin, upright-stabilized | The signature "ball spins around the rider" | Constraint rider rig: `AlignPosition` to ball center + `AlignOrientation` driven to a world-space goal (below) — the engine's solver IS the incremental stabilizer |
| ~65% tumble inheritance (`unkA8`) | Rider shudders with hard spins, stays legible | `RiderTumble` fraction of `AssemblyAngularVelocity` folded into the goal |
| Yaw → horizontal velocity, speed-gated blend | Monkey faces where it's going | `goalYaw = atan2(vx, vz)`, gated below `RiderYawVelLo`, fully tracked by `RiderYawVelHi` |
| In-air spin compensation | Airtime reads loose/alive | Same goal path handles air — world-space goal never cares about contact |
| ~50% clear shell, warm tint | Glass-bubble toy | `CapsuleAlpha 0.5` + `Enum.Material.Glass` |
| No trail; checkered floor | Ball + floor carry the frame | Pack ships no trail; FLOOR slot + CHECKER DECK (below) |

## 2. Capsule shell — "clear 50/50"

- `Config.Art.CapsuleAlpha = 0.5` — exactly half-tinted, half-clear.
- `BallDress.dress`/`retint`: when `skin.capsule`, the ball part wears
  `Enum.Material.Glass` (specular shell read) instead of SmoothPlastic;
  non-capsule skins restore SmoothPlastic. `retint` must restore the
  material too — an equip swap off capsule leaves no glass behind.
- Keep `skin_capsule.core` (255,138,36): through the half-alpha glass it
  reads as the warm-tinted bubble from the key art.
- Ring cage stays (it's our art direction, not the ref's) — but ring
  parts must not hide the monkey: already 0.14-study wireframe rings,
  fine.

## 3. The rider — upright, leaning, bouncy ("acts like Monkey Ball")

**Rig** (`BallDress.buildInhabitant` rework — same function, new guts):

- A hidden `Root` part inside the shell: small block, `Transparency 1`,
  `Massless`, CanCollide/CanQuery/CanTouch off, `CastShadow` off. NOT
  welded to the ball — its own assembly.
- Monkey bits weld to `Root` (WeldConstraint), same `monkeySpec`
  primitive-sphere recipe.
- `Attachment "Ride"` at ball center (child of ball) + `Attachment` on
  `Root` at its center.
- `AlignPosition` **TwoAttachment** (root att → ball att) holds the rider
  centered — `Responsiveness` < 200 gives the suspension bob; reaction
  force on the ball is ~0 (massless assembly).
- `AlignOrientation` **OneAttachment** on the root attachment; `CFrame`
  is the world-upright goal, rewritten per frame by the lean driver.

**Rider goal driver** (server, `Main.server.luau` Heartbeat — the ball's
network owner is the client, but the server reads
`ball.AssemblyLinearVelocity`/`AssemblyAngularVelocity` fine and
constraint-property writes replicate to whichever machine simulates the
rig). Port of `updateApeOrientation` (physics.ts ~571):

- For each `run.ball` carrying `Inhabitant`: find the rig's
  `AlignOrientation` (name it `RiderOri` — one named lookup, no tag
  bookkeeping) and compose the goal:

  ```lua
  -- yaw: face the horizontal velocity (updateApeFromVelocity) — blended
  -- in over the speed gate, last yaw held when nearly stopped.
  local v = ball.AssemblyLinearVelocity
  local hs = math.sqrt(v.X * v.X + v.Z * v.Z)
  if hs > Art.RiderYawVelLo then
      local target = math.atan2(v.X, v.Z) -- +Z face (muzzle/eyes) onto vel dir
      local blend = math.clamp((hs - Art.RiderYawVelLo) / (Art.RiderYawVelHi - Art.RiderYawVelLo), 0, 1)
      -- shortest-arc blend from lastYaw to target (s16-wrapped delta in the decomp)
      local d = (target - lastYaw + math.pi) % (2 * math.pi) - math.pi
      lastYaw += d * blend
  end
  -- tumble: RiderTumble share of the ball's per-frame angular delta
  -- (the decomp's 0.65-scaled unkA8) — the shudder without the slave.
  local w = ball.AssemblyAngularVelocity
  local wn = w.Magnitude
  local goal = CFrame.Angles(0, lastYaw, 0)
  if wn > 1e-3 then
      goal = CFrame.fromAxisAngle(w.Unit, wn * dt * Art.RiderTumble) * goal
  end
  ori.CFrame = goal
  ```

  `lastYaw` is state per run (`run.riderYaw`, init `math.pi` — facing
  -Z/travel at spawn, matching SMB's `getInitApeYaw`).
- One property write per capsule ball per frame; zero cost for
  non-capsule runs (gate on `ball:FindFirstChild("Inhabitant")`). The
  `AlignOrientation` soft `Responsiveness` plays the role of SMB's
  incremental uprighting — no manual upright nudge needed.

**Rider scale/visibility**: bump `monkeySpec` ~35% larger overall, add a
tail bit (small fur sphere low/back — SMB tails read when the rider
faces -Z), brighten `MonkeyFur`/`MonkeyFace` slightly — it must read
through a 0.5 shell at chase-cam distance.

**Tunables** (all in `Config.Art`, all commented): `CapsuleAlpha`,
`RiderTumble` (~0.35 — share of ball angular delta inherited),
`RiderYawVelLo`/`RiderYawVelHi` (~4/16 studs/s — SMB's gate rescaled:
their 0.23/0.37 u/s at radius 0.5 ≈ this ratio), `RiderResponsiveness`
(~40), rider `MaxForce`/`MaxTorque` caps, `MonkeyScale` (1.35). (The
earlier `RiderLeanMax`/`RiderLeanVel`/`RiderPitchMax` synthetic-lean
fields are SUPERSEDED — SMB leans come free from yaw-tracking + tumble.)

**Preview** (`CosmeticFx` diorama): `vpMonkey` bits currently pin to the
roll CFrame `bc` (tumble). Change the basis to
`CFrame.new(bc.Position) * CFrame.Angles(0, yaw, 0)` where yaw tracks the
diorama's own horizontal velocity (finite-difference the ball's x/z each
frame — the preview moves -Z with a weave, so the monkey visibly turns
into the S-curves and onto the gem line, same as live). Dead-hold and
respawn transparency paths stay as they are.

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

All other bundles append their floor item (8 items each).

## 6. File map

| Workstream | Files |
|---|---|
| Rider rig + deck | `Config.luau` (Art block), `BallDress.luau`, `TrackStreamer.luau`, `Main.server.luau` |
| Catalog | `Cosmetics.luau` |
| Client mirror | `CosmeticFx.luau` |
| Docs (integration pass) | `DESIGN.md` §18 + Ball/Track bullets, `DLC.md` items + APE BALL row |

## 7. Test plan

- `stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl`
- MCP playtest (debug seed `flat`, capsule + floor_check equipped):
  two screenshots a beat apart show the shell/rings rotated while the
  monkey is still upright and camera-facing; steer → visible lean.
- Garage preview: monkey upright mid-roll, leans onto the gem line;
  `floor_check` lane renders as green/cream checker.
- Equip another skin mid-run: glass/monkey removed cleanly (retint).
