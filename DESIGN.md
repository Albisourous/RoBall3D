# RoBall3D — Design Document

> An infinite neon ball roller. Roll forever. Don't fall. Top the leaderboard.

Status: **pre-build spec — all decisions below are final for MVP unless marked TBD.**
Every tunable number lives in `src/ReplicatedStorage/RoBall/Config.luau`.

---

## 1. Concept

RoBall3D is an endless-runner for Roblox: a ball rolls forward on its own down a
procedurally generated neo-vaporwave track floating in space. The player steers
with momentum physics, the track narrows/breaks/speeds up at distance
milestones, and a single fall ends the run. Score = distance + gems. A global
leaderboard is the replay hook; a seed system lets players run identical maps.

**Pillars**

1. **One-more-run tension** — instant restarts, score always climbing, "I almost had it."
2. **Honest physics** — Monkey Ball momentum, no assists, deaths always feel earned.
3. **Neon wireframe in motion** — Slope's downhill-read signature re-skinned
   vaporwave: wireframe ball, grid deck, red-edged hazards, a neon city
   canyon and a striped synthwave sun for a horizon.
4. **Readable chaos** — the track is random but *fair*; every death has a visible cause.

## 2. Reference analysis (what we stole and why)

| Game | Mechanic | What we take | What we don't |
|---|---|---|---|
| **Slope** (primary ref) | Wide downhill slope face; L/R momentum steering only; continuous speed ramp; **lethal red obstacles** as the mid-track threat; instant death + sub-2s restart; pure distance score; **green wireframe-on-black look** | Downhill grade, wide deck, speed-as-difficulty ramp, one-color lethal language, edges + obstacles as dual hazards, instant restart, **wireframe art direction (re-skinned vaporwave: magenta/cyan/violet on purple-black, red stays lethal)** | Cloned layouts, Unity build, F2P wrapper junk |
| Ball Surfer 3D | Neon ball identity, steer-only, distance chase | Neon-first identity, momentum steering feel | Exact visual clones |
| Super Monkey Ball | Momentum/tilt physics, narrow beams, bananas on risky lines | Physics-driven steering feel, tilted paths, gems on risky lines | Tilt-the-world control, lives, stage structure |
| Geometry Dash | Music-synced intensity, milestone progression | Music tied to speed; tier-based progression feel | Jump/flight mechanics (post-MVP), fixed levels |

### Slope REA findings (slope-unblock.github.io atlas + playstudy)

- **The track is a wide slope face, not a ribbon.** Generous width is core to
  the feel — most deaths come from obstacles, not edges. We widened
  `BaseWidth` to match (~16 ball-diameters early, narrowing per tier).
- **Red = lethal, always.** Slope's one-color hazard language means zero
  ambiguity: players budget clearance the instant red is visible. We adopt it
  exactly: `LethalColor` is reserved for kill geometry and is *never*
  palette-shifted — edges, gems and scenery may hue-cycle, lethal red may not.
- **Obstacles are the mid-track threat; edges are the ambient one.** Slope's
  atlas: static blocks, walls with one opening, moving blocks, tunnels, gaps,
  ramps, narrow lanes. MVP adds `BlockGate`/`BlockField`/`WallSlot`; moving
  blocks and tunnels are post-MVP.
- **Speed is continuous**, not stepped — pressure comes from reaction windows
  shrinking. Our eased tier targets approximate the same curve; keep `Accel`
  smooth so no "step" is felt.
- **Exit-line fairness rule**: "a dodge that aims the ball at an edge is a
  partial failure." Generator invariant: every obstacle cluster leaves ≥1
  corridor ≥ `Obstacles.CorridorMin`, and lethal-feature spacing scales with
  tier speed (`speed * Obstacles.ReactionTime`) so every sequence stays
  solvable.
- **Momentum steering + no brake** — lateral velocity persists after release;
  skill = early small inputs, not late holds. Our damped-momentum model
  already matches; the metered W boost is a deliberate divergence for
  skill expression at a risk cost (no brake — momentum flow is identity).
- **Restart must feel free.** Crash → new run in ~1.5s is the addiction loop.
  The pre-menu auto-restart already implements this.
- **The look is neon wireframe on pure black — vaporwave-skinned.** Dark ball
  + cyan/magenta wireframe rings; purple-black deck with neon transverse +
  longitudinal grid lines; lethal blocks are black bodies with red edge
  outlines; the horizon is a canyon of palette-outlined dark towers under a
  giant striped synthwave sun; one big pink score up in the top-left.

**Design consequences**

- Ball is **never directly positioned** — velocity is authoritative; falls/ramp
  launches emerge from physics. This is what makes it feel like Monkey Ball.
- Difficulty is a **distance function** (Slope-style), layered into **tiers**
  (GD-style progression beats) so runs feel like they have chapters.
- **Two hazard classes**: falling off the edge, and touching `LethalColor`
  geometry. Both are instant death; both must always read as the player's
  fault (readable chaos pillar).
- With no jump in MVP, gaps are handled two ways only: *route around* (partial
  gaps) or *ramp launch* (speed-gated ballistic arcs). Jump stays in the backlog.

## 3. Core loop

```
Menu (PLAY + optional seed) -> Run starts (scripted intro)
  -> roll, steer, collect gems, survive
  -> tiers escalate speed/track danger
  -> fall = instant death
  -> death screen (score, best, seed) -> one-key instant restart
     (`R` also restarts mid-run — abandons the run with no save)
```

Target session feel: first run ~30–60s, good runs 2–5min, deaths always
explainable.

## 4. Controls & ball physics

- **Steering**: `A`/`D` or `Left`/`Right` apply lateral acceleration
  (momentum — the ball keeps drifting when released, damped slightly when idle).
- **Power meter** (`Config.Power`): one shared resource bar driving all
  three verbs — hold `W`/`↑` = ×`Mult` (1.5) boost, hold `S`/`↓` = ÷`Mult`
  brake, tap `Q`/`E` = dash (below). The ~1.2s charge drains while a held
  verb runs, refills on release (~4.4s to full), and emptying latches
  **every** verb out until ~35% refilled. Boost/brake both ease at 4×
  normal accel so the HUD tempo visibly jumps; the bar flares pink on
  boost, orange on brake. The gold `RechargeGate` notch in the strip is
  the universal **armed** marker — a meter past the notch means all
  three verbs are live, so "can I act?" is read off the bar, not felt
  out. Charge lives on the bottom-left meter bar (§12).
- **Dash** (`Config.Dash`): tap `Q`/`E` = lateral burst left/right —
  the same steer-ease math drives lateral velocity toward `Speed`
  (60 s/s ≈ 2.3× max steer) at burst accel (~50ms to full, so the
  dart eases in like steering does — no robotic hard-slide) for `Time`
  (0.2s): a ~12-stud sidestep that clamps back into steer range on
  release. Steering is ignored mid-burst — the dodge is a commitment.
  Each dash spends a flat `Cost` (0.3 ≈ 4 of the bar's 14 LED cells)
  of the **same** power meter boost/brake drain — offense, defense and
  dodge all bid on one resource, so a spent dodge is a boost you don't
  have. Dash arms on the **marker**, not its own threshold: the gold
  `RechargeGate` notch is the readiness read for every verb — below it
  a press is denied (the bar flickers dim), past it the dodge is live.
  `Cooldown` (0.45s) paces repeat bursts — the meter is the real
  limiter. Airborne is legal physics: a bad Terrace bounce or ramp arc
  can be bought sideways at meter cost, and a dash can even carry a
  narrow cutout laterally — voids still kill (Y stays gravity's), so
  the skip is a gamble, not a cheat. The bar flashes white for the
  burst window; an accepted press plays a downward pitch-swept zip plus
  a light mix duck, a denied press a low blip that mirrors the flicker
  (AUDIO.md §6). No chunk ever *requires* a dash — it only widens the
  movement envelope, so every §8.1 solvability invariant still stands
  on steering alone.
- **Restart**: `R` in any mode = instant re-roll. Mid-run it tears the run
  down server-side without firing `RunEnded` and without saving the score —
  restarting to dodge a death never banks it. Blank seed → fresh random.
- **No jump** in MVP.
- Keyboard only in MVP; touch later.

Ball: 3-stud `Ball`-shape Part, unanchored, `CustomPhysicalProperties`
(density 0.7, friction 0.6, elasticity 0, **elasticity weight 100** — the
ball's zero restitution dominates every contact, so high pad-arc landings
come down dead: no rebound hop). Server drives
`AssemblyLinearVelocity` each `Heartbeat`: `Vector3(lateral, naturalY, forward)`.
Y velocity is untouched — gravity handles falls, slopes, ramp arcs.

## 5. Camera

Chase cam: offset `(0, 13, 12)` studs behind/above the ball. The aim point is
not flat-ahead — it drops to the deck plane `LookAhead = 16` studs out
(`target.y -= Grade*16 + LookDrop`), so the camera pitches into the slope
(~28°) the way Slope does: ball low in frame, long readable runway ahead.
FOV eases `70 -> 88` with speed. Up to `LeanMax = 3°` of roll into the steer
direction for momentum readability. No vertical bob (keeps precision readable).
The position follows with an exp damp at `Camera.SmoothTime` (0.12s —
`alpha = 1 - e^-dt/τ`, frame-rate independent): deck-seam and landing bumps
filter out while the aim stays locked on the lead point, so a dash reads as
a brief elastic trail. Run starts snap rather than ease in from the menu.

## 6. Run structure & menu

- **Menu** (built in code, `StarterGui` from Luau — everything stays in git):
  - Title `ROBALL3D`, vaporwave-styled
  - **PLAY** button — starts a run on a random seed
  - Seed `TextBox` — paste/type a seed for an identical map, `daily` for
    today's shared UTC seed, `weekly` for the cup (§14)
  - Leaderboard panel — TOP / DAILY / WEEKLY tabs (`name / score / seed`);
    daily shows the shared seed + time to reset, weekly shows the cup
    seed + days to reset. A `◈ friends` toggle filters whichever board is
    open to your Roblox friends — rows keep their real rank numbers; the
    id set lazy-loads once per session via `GetFriendsAsync`
  - Audio console — a collapsed `audio ▸` toggle under the controls hint
    unfolds five channel sliders in three paired rows (`MUSIC + GEMS /
    DASH + WIND / CUES`, 0–100%) riding the mixer taps in AUDIO.md §7,
    persisted via `profile.audio` → `RoBallVol_<ch>` attributes so a mix
    survives sessions
  - Personal best label
- **Run start**: `Config.Steering.SettleSeconds` (0.8s) "rolling…" settle,
  then control handed over.
- **Death**: pitch drop on music, death-cam orbit (§11), then the death
  screen shows
  `SCORE / DISTANCE / BEST / SEED`, `[R]` or button = instant restart (new
  random seed unless one was entered — same seed if entered manually).
  A gold `★ NEW BEST!` line appears under the title when the run beat the
  stored record — the flag is computed server-side since attribute
  replication races make a client-side compare unreliable. A dim stats
  line closes the card: `top N s/s · M gates · P% boost · margin X` —
  top forward speed, lethal planes crossed, share of distance spent
  boosting (client-tracked, display-only), and the tightest near-miss
  margin of the run (`in-disc` when the closest call was inside a rotor's
  sweep).
- **PB ghost**: on run start a translucent magenta `BEST n` gate floats on
  the deck at your record's end distance (`Score.PbMarkerMinDist` = 150m) —
  you race your own shadow. The label stays near-field only
  (`PbMarkerViewDist`, no AlwaysOnTop) so it isn't a constant screen
  occupant; crossing the line flashes a gold `★ NEW BEST` under the HUD
  score for `PbFlashSeconds`. Record `dist`/`seed` only overwrite on a true
  new record, so the gate always marks the real best, never a later run.
  The HUD score cluster lives top-left — the center cone stays clear for
  the track read at speed.

## 7. Seed system

- Every run's map is a pure function of a seed: `Random.new(seed)` drives all
  generation choices. Same seed → same chunk sequence → same map.
- Default runs use `tick() % 2^31` randomized per run; the used seed is always
  displayed on the death screen and stored with the score so leaderboard rows
  are replayable/verifiable.
- Seed entry: numeric or text (hashed to int via a stable string hash).

## 8. World generation

### 8.1 Model

Runs travel toward `-Z` and **always downhill**: every chunk's deck drops by
`Generation.Grade` studs per stud traveled (0.16 ≈ 9°), so the track visibly
descends and the auto-roll reads as rolling downhill (the Slope cue). Deck
heights accumulate, so chunk `y` values drift down over a run; the kill plane
always follows the local deck height via `yAt(z)`.

**Closure contract**: section functions are evaluated lazily (at build time,
and again later by `yAt`), after the generator state has advanced — so
`nextChunk` hands every builder a frozen snapshot of the entry state
(`centerX/width/y/zEnd`). Sections must never read the live `self.state`
table; that bug once made geometry shift per-chunk and `yAt` return the
generation frontier, spawning the ball under the world.

Track = ordered sequence of **chunks**, each
30–90 studs long, forming a **wide descending slope face** (Slope model —
width is generous early and narrows with tiers; it is not a narrow ribbon).
The generator keeps `AheadDistance = 400` studs of track
alive ahead of the ball and destroys anything `BehindDistance = 250` studs
behind it. Each player's run lives in a private lane offset `600` studs apart
in `X` (invisible to others under fog).

**Build cost**: the streamer samples each chunk at `SEG_LEN` intervals but
emits the *fewest boxes that describe it* — consecutive intervals with
constant profile (width/centerX/roll/cutout/wallH) and constant deck slope
merge into one long part. Straight chunks (Flat, intro, obstacle rows) build
as ~4 parts; curved chunks keep fine slices. Transverse grid strips emit on
their own `GridEvery` cadence, independent of slicing.

Two hazard classes live on the deck (REA §2): **edges** (ambient threat) and
**lethal obstacles** (mid-track threat — parts colored `Config.LethalColor`,
always reserved hot-red). Obstacle chunks emit block/wall specs alongside
deck geometry; touching one is instant death, same as falling.

Each chunk produces an **end state** `{ width, centerX, height, exitSpeedReq }`.
The next chunk's entry must match it — the generator enforces constraints so
every sequence is *completable*:

- `endWidth` of chunk N ≥ `minEntryWidth` of chunk N+1
- Height deltas ≤ gentle slope limits (max ~12°) unless a `RampGap` boundary
- `RampGap` chunks only emit when current tier speed ≥ their required entry
  speed (computed from gap length — see 8.3)

### 8.2 Scripted intro

The first 170 studs are hand-authored, not RNG (`GenCore.intro`):

`Flat(35, 48) -> Flat(35, 48->44, gems) -> Slalom(45, amp 8, 0.6 periods) -> Narrow(55, ->32)`

Players learn: it rolls on its own, steering drifts, gems exist, track can
narrow. Then the seeded generator takes over.

### 8.3 Chunk types (MVP)

| Chunk | Shape | Role | Tier |
|---|---|---|---|
| `Flat` | Full-width ribbon | Breather, gem lines | 1+ |
| `Slalom` | Ribbon, centerline sways via sine | Steering warmup | 1+ |
| `Narrow` | Width lerps down over the chunk | Precision | 2+ |
| `Widen` | Deck opens to the tier window's upper half in ~35%, then holds; twin edge-margin gem lines | Relief + lateral reach (dash's job) | 5+ |
| `Tilt` | Ribbon rolls around its long axis ±(8–20°) | Momentum management | 3+ |
| `Pinch` | Width collapses to 2–3 studs mid-chunk, reopens | Burst precision | 3+ |
| `SplitGap` | Center channel removed → two side ribbons; void-adjacent edges glow **lethal red** (void = kill geometry) so the split reads from the horizon | Route choice | 4+ |
| `Bowl` | Banked walls rise on both edges | Rest + dense gem canyon | 4+ |
| `RampGap` | Launch ramp, full-width void, landing strip | Speed check / spectacle | 5+ |
| `BlockGate` | Red blocks across the deck, one gap ≥ CorridorMin | Thread-the-gap | 2+ |
| `BlockField` | Scattered red blocks, density scales with tier | Weaving pressure | 3+ |
| `WallSlot` | Red wall spanning the deck, single opening | Commit-to-a-lane | 4+ |
| `Terrace` | Deck descends in lips; gravity pops the ball off each edge | Free ballistic spectacle | 2+ |
| `SnakeField` | Edge-flush blocks alternating sides on a long chunk | Beat weave | 3+ |
| `Blackout` | Flat geometry, grid/center neon dims to rails+gems only — break sections only | Atmosphere | 3+ |
| `Chicane` | Wall rows with gaps pinned to alternating rails | S-steer combo | 4+ |
| `Fork` | Asymmetric split: thin gem-loaded rail / wide bare rail | Route choice | 4+ |
| `PadHop` | LaunchPad (cyan strip) kicks ball ballistic over a lethal strip | Computed arc | 4+ |
| `PadVoid` | LaunchPad launch across a void — pad supplies airtime, not speed | Early gap spectacle | 5+ |
| `TunnelSlot` | Roof ribbon + hanging slabs leaving one corridor + decor teeth | Enclosed corridor | 5+ |
| `DropGate` | Full-width wall whose gap threads ON a drop accent downbeat | Beat-slam set piece | 5+ |
| `Pacer` | Wall pair whose fixed gap slides L↔R on a beat-locked sine | Timing window | 6+ |
| `Rotor` | Near-center post + neon spinning blade; swept disc can't reach either rim — both rails are always-clear lanes, and a translucent danger disc tints the swept zone | Timing + bait gems | 6+ |

**Obstacle rules (REA exit-line fairness)**
- Every row of lethal geometry must leave ≥1 clear corridor ≥
  `Obstacles.CorridorMin` studs wide relative to deck width.
- Successive obstacle rows inside a chunk are spaced ≥
  `tier.speed * Obstacles.ReactionTime` studs so the player always has time to
  read the next row.
- Obstacles ride the deck surface (`section(t).y` + half height) and roll with
  `rollDeg` so Tilted obstacle chunks stay glued to the slope.
- `LethalColor` parts are `CanCollide = true` (they read as solid) and carry a
  server `Touched` kill — the ball never survives contact.

`RampGap` rule: for gap length `L` and landing drop `d`, need entry speed
`v >= L / sqrt(2d/g)` (g = 196.2 studs/s²). Generator picks `L ≈ v * 0.45`,
`d = 4`, only at tiers where `speed >= 64`.

**Feature chunks (§8.6) extend the contract**
- `Section.cutoutOff` shifts a cutout's center off the deck axis (Fork).
- `Section.roofH` emits a dark ceiling ribbon + neon ribs (TunnelSlot).
- `Obstacle.hang` anchors a slab's top to `roofH` — hanging gate columns.
- `Obstacle.motion` (`slideX`/`spin` + periodSec/phase) — beat-locked
  movers; periods are whole-note counts of the heard tempo so the hazard
  cycle IS the music.
- `ChunkSpec.pads` — LaunchPad strips (cyan, tagged `RoBallPad`,
  `KickY` attribute). The client applies the kick (it owns the ball's
  velocity): GD pads as terrain, not a jump button.
- `ChunkSpec.dim` (Blackout) dims grid/center neon to `Blackout.GridScale`
  — edges + gems stay lit.
- `ChunkSpec.tierGate` — a chunk straddling a tier boundary carries a
  non-collide neon portal bridge: two frames joined by top rails (no
  distance label — the HUD already owns numbers).

### 8.4 Gem placement

Gems cluster on **risky lines** (this was the explicit choice): edge rails,
narrow beams, arcs over `RampGap` voids, and straight through the middle of
obstacle gaps (the corridor you're meant to thread — highest risk/reward).
Value scales with risk class:
safe `10` / edge `15` / beam `25` / gap-arc `40`. 0–3 clusters per chunk.
Gems are a single Neon `Part` — a cube balanced on a corner (35.26° pitch
+ 45° yaw), giving a hexagonal diamond silhouette — with a server touched
handler → `Score += value`. (Two-pyramid octahedron via
`MeshType.Pyramid` was tried: that legacy mesh type renders nothing in the
current engine.)

**Pickup juice** (`GemFx.luau`, client): the gem itself is `Destroy`ed
instantly server-side, so the flourish is client-local at the ball's
position when `RoBallGems` ticks up — a ghost diamond pops oversize and
rises/fades while tumbling, a gold sparkle burst scatters (built-in
sparkles texture, always resolvable), and a thin neon ring flashes
outward across the deck. All one-shots, gone in ~0.5s.

**Rhythmic clusters** (`gemRhythmLine`): gem spacing rides the music's beat
grid. Cluster sizes are note groupings — 8 = sixteenths, 4 = eighths,
2 = quarters, 1 = accent (`Gems.ClusterSizes/ClusterWeights`) — and
`beatSpacing` sets stud spacing to `speed × beatInterval / subdivision`,
where the heard BPM is `Music.BaseBpm × PlaybackSpeed`. Since PlaybackSpeed
ramps with the same speed curve the ball uses, the pickup interval stays a
constant note value at any pace. `rollRhythm` picks the largest cluster that
fits the chunk span (retrying one subdivision denser before dropping size).

### 8.5 Palette gradient

The world samples a single hue from `Palette.HueStops` — a **vaporwave**
wheel (magenta → violet → blue → cyan), advanced by distance so the scene
slowly laps the synthwave band (`CycleDistance = 800`m/lap). Red is excluded
from the wheel entirely — it stays the reserved lethal color.

Sampling is **continuous, not per-chunk**: longitudinal neon (edge rails,
center line) is emitted in `GridEvery`-length pieces that each sample the
palette at their own distance, transverse grid strips sample at their own
z, and the purple-black deck lerps `DeckTint` toward the palette — so the
whole course *flows* through the gradient rather than banding chunk by
chunk. `Palette.neonAt/dimAt` feed track edging, grid lines, tower
outlines and the trail — "generated by code, easily adjustable" per spec.
`LethalColor` and the gold `Gems.Color` are reserved and never sampled
from the wheel.

### 8.6 Feature ramp — teach, then test (GD model)

New mechanics are introduced one at a time, GD-style: each feature type
has a debut distance in `Config.Features.Debut`. The **first** spawn of a
type at/after its milestone is a scripted **gentle showcase** — widest
corridor, slowest mover cycle, full breadcrumb gem line — then the type
joins the seeded pool at full difficulty. A type stays out of the pool
until its debut has run (`GenCore.debuted`), so players always meet the
easy form first. Debuts are deterministic like everything else — same
seed, same ramp.

Ramp (spaced wide — features come late): Terrace 400m · SnakeField 800m ·
Blackout 900m · Chicane 1300m · Fork 1500m · PadHop 1700m · PadVoid 2100m
· TunnelSlot 2200m · DropGate 2300m · Pacer 2700m · Rotor 2900m · OrbHop
3300m\* · FlipRide 3500m\* (\*flag-off stretches). Early
game (0–800m) is core verbs only: steer, narrow, dodge, gems, Terrace.

**Fairness invariants** — every feature must satisfy:

1. Every lethal row leaves ≥ `Obstacles.CorridorMin` of continuous deck —
   including movers: the Pacer's gap is constant-width (slabs overhang the
   rim and slide together); the Rotor's near-center post sweeps a disc
   bounded `CorridorMin` short of BOTH rims — two always-clear lanes, and
   the worst entry owes only ~halfW of transit. And no chunk may squeeze
   the deck under `Generation.MinWidth` (4 studs) — Pinch and SplitGap
   rails floor there.
2. Read distance ≥ `speed × ReactionTime` before any commitment. A chain
   of ONE repeated pattern (Chicane/SnakeField) may use a ×0.75/×0.5
   window — the read is learned from the first row. Chained chunks size
   their *length* around the spacing instead of cramming rows into 90
   studs — this is why feature chunks may exceed ChunkMaxLength.
3. Ballistics are guaranteed by construction **across the survivable
   entry-speed range**, not just at nominal tier speed: `PadVoid` gap ≤
   `v × tAir × VoidAirFrac` with VoidAirFrac sized below the 0.67×
   full-brake floor, so a braked crossing still lands. `PadHop` holds
   y ≥ H for a window wSec centered on the apex; the strip is placed
   inside the *intersection* of those windows for every u in
   `[SlowCrossFrac, Power.Mult]×speed` — braked entries cross late in
   the arc, boosted entries early on the rising limb, and both clear.
   Miss the pad → death is earned.
4. Context gating (`ChunkDefs.canRun`): DropGate only on accent downbeats
   at energy ≥ 0.8; Blackout only in `break` sections; movers/rails only
   above honest width floors. Ineligible types never roll. Entry width is
   declared per type in `ChunkDefs.MinEntryWidth` (wide enough for the
   *debut* variant too) — below it the builder would emit a silently-empty
   obstacle chunk or squeeze under `MinWidth`; both are generator bugs the
   pool routes around. `gateRow` clamps its corridor draw into the feasible
   range rather than returning an empty row.
5. **Lateral-authority honesty** (`ChunkDefs.latTravel`/`latReach`):
   transitions are sized so the closing edge never outruns the steering
   from ANY entry position the previous chunk could force. Both helpers
   use the *slowest survivable* entry (`SlowCrossFrac`× tier speed × 0.85
   authority) — a line transit-able while braking is transit-able at any
   entry. `Flat`/`Narrow`/`Blackout` grow their length with the width
   drift; `Pinch` is sized against its peak collapse rate; `SplitGap`/
   `Fork` fade the void mouth over `latTravel(cut/2 + r + margin)` studs
   (a center entry must reach a rail before the floor is gone); `gateRow`
   and `DropGate` draw the slot inside `latReach(lead)` of the far edge;
   `Chicane` bounds its alternating amplitude by the entry→row-1 and
   row→row transits; `Rotor` grows its lead until a mid-deck entry can
   reach the nearer always-clear rim lane — and `canRun` declines it when
   that lead would exceed `2 × ChunkMaxLength` (a degenerate runway on
   wide/fast decks). Empty chunks are still refused over silently-empty.
6. Gem lines breadcrumb the intended line through every hard chunk —
   SnakeField's zig line, Fork's risk rail, gate gaps, pad arcs.

**GenVerify** (`ReplicatedStorage/RoBall/GenVerify.luau`) is the proof:
a pure-Luau sweep walking GenCore for N seeds asserting all of the above
plus entry continuity and debut ordering. Two further audits: the
**flat-exit seam** (roll/cutout/wall/roof are chunk-internal — every chunk
must hand the next a level, open seam) and **lateral reachability** — the
set of lane-local x positions a ball can still occupy is propagated through
each chunk's valid ribbon band (minus ball radius, split by cutouts,
shrunk around static lethal blockers over their depth, voids expand-only)
at `MaxLateralSpeed` of travel per stud — modelled at `SlowCrossFrac`× tier
speed, the most permissive budget, so an empty set means no survivable
line exists at ANY entry: a generator bug, not player error. Studio-only
(`Config.Debug.VerifySeeds`), run by `GenVerifyRunner.server.luau`.

**Stretch pillars (flag-off, built)**: `Config.Features.JumpOrbs` /
`GravityFlip` gate GD's tap-orbs and gravity portals. Both are fully
implemented but ship disabled — they change core controls (jump input) and
physics (ceiling riding inverts the heartbeat's downhill model). Debuts:
OrbHop 3300m · FlipRide 3500m.

- **OrbHop** — pad → void with a lime `RoBallOrb` sphere mid-flight →
  landing. The pad kick places the arc apex on the orb; the void is sized
  so arc-1 lands INSIDE the gap (orb-or-die). `OrbController` (client):
  Space/touch-tap while within `Orbs.Radius` re-kicks `vY` to `KickY`
  once per orb. Fairness: the builder solves a quadratic for the
  grade-aware arc-1 landing point and sets the lip 6 studs past it; the
  audit asserts orb reachability, arc-2 reach, and arc-1 insufficiency.
- **FlipRide** — portal-framed zone (`FlipPost`/`FlipBar` neon arches)
  bracketing a collide ceiling ribbon `Flip.ClearH` above the deck. Inside
  the tagged `RoBallFlipZone` box the client pins `vY = +Flip.Lift`
  (ball presses the ceiling underside) and mirrors steering; at the zone
  edge the pin drops, gravity resumes, and the ball falls ClearH back.
  No obstacles inside — the ride itself is the read. Gems line the
  ceiling run.

## 9. Difficulty & speed

Tier table is in `Config.Tiers`. Crossing a tier threshold:
- target speed steps up (40 → 106 by 2000m), eased at `6 studs/s²`
- new chunk types join the RNG pool
- allowed width range tightens (24 → 4 min)

Within a tier the deck width isn't monotonic: `Narrow` ratchets down
toward `widthMin`, `Flat` re-rolls the width anywhere in the window
(tiers 1–3 and back from tier 5 — it converges an over-wide deck down
into the window too), and from tier 5 `Widen` opens back toward
`widthMax` — so the deep game sawtooths between cramped precision
stretches and reopened fields instead of parking in one extreme.
`canRun` gates `Widen` to ≥4 studs of headroom under the tier ceiling,
and its edge-margin gems make the lateral reach (Q/E dash, §4) pay off
while the field is wide.

**Endless mode** — there is no speed cap. Past the last listed tier
(2000m), `Tiers.forDistance` extrapolates: speed rises by
`Speed.EndlessRamp` per meter (+12 s/s per km — ~142 s/s at 5km, ~200 at
10km) and the width window eases toward `EndlessWidth*Floor` (12/18) —
floored where a gate row + rim margin still fits, since below ~12 studs
lethal rows can't generate and the run would paradoxically get easier.
The chunk pool stays tier-6's; **speed is the difficulty driver** —
collapsing reaction time does the work, not new hazards or razor lanes.
`Config.Speed.Max` only normalizes presentation (FOV, music ramp, gem
beat spacing all saturate at it).

Hazards: **falling off the deck** and **touching `LethalColor` geometry** —
both instant death, per the Slope model (§2 REA). Moving hazards and
tunnels landed via `Obstacle.motion` and `Section.roofH` (§8.6).

## 10. Scoring

`score = floor(distance_m) + gem_points + near_miss_points`. Distance is
authoritative server-side (ball's traveled `-Z`). Gem values per 8.4. Death
seals the score.

**Near-miss trickle**: every lethal plane the ball crosses without dying pays
`Score.NearMiss.Points` (3) if the pass hugged the geometry — interpolated
crossing-x within `NearMiss.Range` (4 studs, ball-surface to face) of a static
block's edge, or anywhere inside a rotor's translucent sweep disc (the disc
already marks risk honestly). One award per obstacle; hanging roof slabs never
count (a lateral graze under a ceiling isn't a dodge). The server walks the
streamer's ordered hazard-plane list with a cursor — zero per-frame scans —
and `plausible()` carries a loose `ceil(dist/30) × 8 × Points` ceiling. Each
award bumps `RoBallNearMiss`; the HUD flashes a short cyan `CLOSE +N`.

## 11. Death

Ball leaves track → Y drops below kill plane (`trackY - Config.Death.KillDrop`,
15 studs) → run over
instantly. Ball touches `LethalColor` geometry → same outcome server-side via
`Touched`. **Stall watchdog**: ball velocity is client-forced every frame, so
a live ball can never sit still — a ball whose position is frozen for
`Config.Death.StallSeconds` (past `StallGraceDist`) is wedged in geometry and
killed like any other death, converting what would be a silent hang into a
normal run-over + instant retry. **External destruction** (e.g.
`FallenPartsDestroyHeight` — canonical value is
`Config.Generation.FallenDestroyY`, **applied via `default.project.json`**
(the property requires plugin capability — a runtime assignment from a game
script crashes the script). The default -500 ate the ball around 3.4km in)
also seals the run:
if `run.ball` loses its Parent, the heartbeat treats it as a death rather
than leaving a ghost run. Effects: music pitch slides to 0.6, then the
**death-cam**: a `Camera.DeathOrbitSec` (1.5s) ease-out orbit of the kill
spot — yaw sweeps `DeathOrbitArc` (~31°) while the radius pulls back
toward `DeathOrbitPull`× and FOV settles to FovMin — *then* the death
card lands. R mid-orbit skips straight to restart; a stale delayed card
is dropped by the death-sequence guard. No lives, no shields — they were
explicitly deferred.

## 12. Presentation

- **Skybox**: pure-black void (`Lighting.ClockTime = 0`), purple-leaning
  ambience and a magenta-purple haze.
- **Backdrop**: retro-futuristic city canyon — rows of near-black towers
  with `SelectionBox` neon outlines flanking the track, 1–3 stacked segments
  per tower, recycled per row for parallax, each tower tint-jittered along
  the vaporwave wheel so the skyline mixes cyan/magenta/violet. A giant
  **striped synthwave sun** (stacked Neon strips, orange crown → magenta
  base, gaps widening downward) rides at a fixed distance + lift ahead of
  the ball so it always hangs in the upper frame like a sunset at the end
  of the slope. Bases follow the deck's
  downhill grade so the canyon hugs the slope. **Backdrop is client-local**
  (`Backdrop.luau`): zero replication cost. The Atmosphere dims towers past
  ~600 studs; `CitySpan` stays inside the visible band.
  The **world** cosmetic slot (§18) swaps the flanks: **NEON PEAKS**
  replaces the towers with a seeded wireframe ridge field — a displaced
  grid mesh of thin Neon edge parts over near-black tilted facet plates,
  plus a grade-pitched dark slab per tile so ranges occlude the void
  instead of reading translucent. Ridge height is a pure `math.noise`
  function of (side, column, world-lattice row), so independently
  recycled tiles meet in perfect seams and terrain generates fresh
  forever downhill; a lateral ramp keeps a flat valley at the road edge
  (innerX 55 clears the deck's worst lateral reach ~39) and a slow
  along-z envelope lets ranges arrive in passes. Same client-local,
  palette-driven rules — edges sample `Palette.dimAt` per stroke with an
  outer-column dim for depth. Two more worlds round out the slot:
  **STAR WELL** (`void`) replaces the flanks with a shell of neon motes
  ringing the descent axis — azimuth and shell radius are fixed per
  mote, only z recycles forward, and half the shell sits below the deck
  plane so the drop reads as a fall through open space; **GRID PLANE**
  (`grid`) is the retro wireframe floor riding the descent `GridDrop`
  studs below the deck — cross wires recycle on a frontier like the
  tower rows, longitudinal rays stride by their own window length, and
  both pitch to the grade so the floor stays parallel to the slope.
- **Ball**: near-black sphere + five `CylinderHandleAdornment` wireframe
  rings (3 cyan axial + 2 magenta diagonal) — a clean neon cage that rolls
  with the ball's spin. Slim magenta Trail. No PointLight — self-glow
  smears the wireframe under bloom. (`SelectionSphere` was tried first: its
  lat/long grid is too dense at 3 studs and renders as a blob.)
- **Track**: purple-black deck (subtle `DeckTint` palette drift), neon edge
  rails + transverse grid strips + longitudinal center line, all tinted
  from `Palette` **per segment** — the neon flows continuously down the
  slope as a real gradient instead of stepping per chunk.
- **Gems**: gold corner-balanced cubes — a hexagonal diamond silhouette
  that reads as a collectible at speed (one part each, zero mesh cost).
- **Obstacles**: near-black bodies with red `SelectionBox` edge outlines —
  Slope's black-with-red-edges read, same one-color lethal language. Red is
  never used for decoration anywhere else.
- **HUD**: one big pink score top-left (the center cone stays clear for
  the track read at speed); distance/gems on a dim lavender subline, the
  combo pip under that, and the gold pass-moment flash below.
  Bottom-right is a single big **BPM number** — the
  heard tempo (`map.bpm × PlaybackSpeed`, snapped to `TempoStepSt`
  semitones), so the digit steps in real intervals exactly when the music
  does. The digit's hue is still the speed meter: gradients cyan →
  violet → magenta across 0–100 s/s and snaps hot red + pulsing past it.
  It's dressed vaporwave: a chrome gradient band under the hue, a −6°
  outrun slant, and twin cyan/pink VHS-fringe ghosts that spread and
  flare with the audio pulse — the digit thumps on the heard beat.
  Bottom-left
  is a glanceable **power meter**: a tilted capsule of LED segments ramping
  cyan→magenta like a VU meter, diamond bead riding the lit edge,
  `RechargeGate` shown as a gold notch between cells — the armed marker
  for boost, brake AND dash (§4) — with the lock zone
  tinted warm, pink flare while boosting, hot orange
  while braking, white flash for a dash burst, a dim flicker on a
  denied press (same power meter — §4), blink while latched out —
  and a gold ping the moment charge crosses the gate upward, so W coming
  back is felt, not watched. Under the subline a small `xN` **combo pip**
  tracks gem streaks (same `GemSfx.ComboWindow` the chime ladder uses, so
  the count always matches the pitch climb). Gem pickups also float a
  `+N` points popup with the ghost-diamond burst — the pickup's exact
  value read off the cumulative `RoBallGems` delta. Dial pods were tried
  and rejected — minimal chrome keeps eyes on track.
- **Type**: three voices, one job each (`Ui.luau` font constants).
  `F_HERO` = Garamond in letterspaced caps — the Floral Shoppe
  "A E S T H E T I C" serif, reserved for hero titles (menu name,
  RUN OVER). `F_DISPLAY` = Michroma — geometric retro-future caps for
  chrome headers and action buttons (TOP RUNS, GARAGE, PACKS/BANK,
  PLAY/RETRY). `F_DATA` = Code — the machine voice for every number,
  tag and readout (score, BPM digit, rows, seed, popups; the server
  PB gate and GemFx `+N` use it inline).
- **Post FX**: `applyEnvironment` owns Lighting outright — it destroys every
  pre-existing `BloomEffect`/`Atmosphere`/`SunRaysEffect`/`ColorCorrectionEffect`
  (the place file carried a stale authored kit that double-stacked ours) and
  creates exactly one set: a restrained `BloomEffect` named **`WorldBloom`**
  (Intensity 0.35, Size 10, Threshold
  1.5 — only true Neon emissive pixels bloom; earlier 1.15/30/0.8 smeared
  the whole frame into blur, and 0.55/16/1.3 still glowed too hot), subtle `ColorCorrection`, `Atmosphere` density
  0.25 for depth haze. Backdrop's audio pulse binds `WorldBloom` by name
  (`WaitForChild`), never a stale authored bloom. **Speed blur** is a meter, not a constant: a
  `BlurEffect` + the `DepthOfField`'s far intensity ramp off `fwdSpeed` —
  a power curve (`MaxBlur * t^Exponent`, t normalized `StartSpeed`→`CurveTop`,
  StartSpeed 100) so sub-100 stays perfectly clear and the smear climbs
  exponentially past it, capped at MaxBlur — crystal at
  tier pace, smearing only deep into endless mode. The place-file DoF used
  to sit at a near focus (track permanently soft); the client retunes it to
  `DofFocusDistance` so only the horizon blurs.

## 13. Audio

Full spec: `AUDIO.md`. Binding decisions:

- Music is a **generation input**, not background. The renderer
  (`roball3d-audio/generate_audio.py`) owns the soundtrack: it emits the
  loop, per-bus stems, stingers, and a `SongMap.luau` beat/section chart
  that GenCore reads. Self-rendered = free stems, free beat maps, zero
  copyright surface.
- Shipped catalog: ten FlowMusic loops (`Config.Music.Tracklist`,
  per-track measured BPMs — `palm_screens` doubles as the menu bed).
  The earlier synthesized set (`vaporwave_loop`, `neon_descent`,
  `retro_wave`) is retired. `PlaybackSpeed` maps ball speed `0.9x ->
  1.35x`, so the heard tempo rides the run's acceleration. Optional
  `AudioPitchShifter` (`Music.PitchCompensation`) softens the squeak
  while tempo keeps climbing.
- Runtime migrates `Sound` → the audio-graph API: one
  `AudioPlayer` + fader per stem (equal-length streams stay
  sample-locked; a watchdog resyncs on `Looped`), `AudioFilter`
  tape-stop on death/menu, `AudioAnalyzer` tap feeding decorative
  audio-reactive visuals — never tinting toward `LethalColor`.
- **Songform sync**: bar position is a pure function of distance
  (`beats/m = BaseBpm·ps(v)/(60·v)`), so GenCore weights chunk families
  by the section energy under the ball — drops roll lethal/spectacle,
  breaks roll breathers. Selection bias only; every §8.1 legality rule
  still gates what's allowed. Tier-up stings and set-pieces quantize to
  phrase downbeats. Boost drift vs the nominal speed schedule is
  bounded and accepted.
- Gems stay on the heard beat grid (§8.4); `Music.BaseBpm` must equal
  `SongMap.bpm` or everything drifts. The pickup chime keeps the
  pentatonic ladder (`SfxController` + `GemSfx`, `gem_pickup` asset).
- Once a track canon exists, the seed picks the track: same seed → same
  track + map + musical pacing — leaderboard rows become replayable
  "levels", GD-style.

## 14. Persistence & leaderboard

- `RoBall3D_Best_v1` (DataStore): personal best `{score, dist, seed}`.
- `RoBall3D_Profile_v1` (DataStore): equipped cosmetic ids per slot + gem
  bank balance + gem-purchased item ids (§18).
- `RoBall3D_TopRuns_v1` (OrderedDataStore): global top scores, shown in menu.
  A `_Meta` store beside it holds `{seed, score, assisted}` per user, written
  only when a run beats the stored top — the board row's seed is always the
  seed that earned that score. The menu panel sizes its rows from
  `Config.Leaderboard.TopCount` and refetches on every menu entry (boot +
  death → menu) so a just-saved score is immediately visible.
- **Daily board**: `RoBall3D_Daily_v1_YYYYMMDD` (+ `_Meta`) — a per-day
  OrderedDataStore pair. The daily seed is `djb2("daily:" .. YYYYMMDD)` over
  the UTC date (`Daily.luau`): every player who runs it gets the identical
  map that day, so the board is a same-seed race. Typing `daily`/`today` in
  the seed box resolves to it; a run whose seed equals today's seed submits
  to the day's board on death (same keep-max `UpdateAsync` + session-best
  write thrift as the all-time board). The menu panel gains TOP/DAILY/
  WEEKLY tabs; the daily tab shows the seed + UTC reset countdown. Yesterday's
  stores are simply never read — no cleanup needed.
- **Daily streak**: finishing a daily-seeded run counts the UTC day —
  same day again is a no-op, yesterday continues the streak, a gap resets
  to 1. Each counted day pays `min(streak, DailyStreakCap) *
  DailyStreakBonus` banked gems (never score). The profile store carries
  `dailyDay`/`dailyStreak`; runs that end before the profile lands queue
  on `pendingDaily` so a slow load can't clobber the stored streak. The
  death screen shows the payoff line and the daily tab shows the streak.
- **Daily quests**: three missions seeded by the day's seed
  (`Daily.quests()` — pure, same list on client and server): one target
  drawn per pool (`Config.Monetization.Quests` — reach/score in one run,
  gems banked across the day). Any clean run's end evaluates them;
  rewards pay banked gems via `awardGems`, never score. Progress persists
  in the profile (`questDay`/`questDone`/`questBanked`) and restores only
  when the stored tag IS today — yesterday's missions die with the day.
  The client reads the `RoBallQuests` CSV attribute
  (`done flags + bankedToday`) to draw the menu lines and the death
  screen's `N quests done · ◊ +N banked` line.
- **Weekly cup**: `RoBall3D_Weekly_v1_W<n>` (+ `_Meta`) — the same per-week
  OrderedDataStore pair, keyed on Sunday-start week index
  (`floor((daysSinceEpoch + 4) / 7)` — pure arithmetic, no strftime gamble).
  The cup seed is `djb2("weekly:" .. W<n>)`; typing `weekly`/`week`/`cup`
  resolves to it. A third board tab shows the cup seed + reset countdown.
  Economy: the first weekly-seeded run of a week pays `WeeklyRunBonus`
  banked gems, and at the same moment lazily reads LAST week's final board
  once — a top-3 finish pays `WeeklyTopGems[rank]` (200/100/50). Both
  writes gate on profile `weeklyTag` so they fire exactly once per week.
- **Achievements**: `Config.Monetization.Achievements` — milestone badges
  evaluated server-side at every clean run end (`ShopService.onRunEnd`,
  after streak + quest eval so those counts are fresh). Kinds:
  `runs`/`runDist` (this run / lifetime), `lifetimeGems` (play-earned gems
  — `awardGems` credits the counter; purchases through `grantGems` don't),
  `streak` (daily streak), `questsAll` (all day missions done). Rewards
  pay banked gems — never score. Profile carries the `achievements` id
  list plus `statsGems`/`statsRuns`/`statsBestDist` counters; unlocks are
  permanent and idempotent (a re-eval on a done id is a no-op). Mirroring:
  `RoBallAch` = full sorted id CSV for the menu tally (`awards n/N`),
  `RoBallAchNew` = only the just-unlocked batch — the client toasts
  `◈ NAME · ◊ +N` off that attribute and clears, so a restored profile
  never re-fires ribbons.
- **PB ghost**: your record run leaves a replayable echo. The client
  samples ball position every `Config.Ghost.SampleSeconds` during a run
  (flat table — no per-frame instancing); when the run ends as a new
  session PB, the server arms a one-shot `ghostAuth` credential and the
  client submits the frames through `SaveGhost`. The server accepts only
  frames whose seed/score match the credential — the echo provably IS
  the PB run — after a format check (frame cap, monotone -Z, sane
  bounds). Stored per-userId in `RoBall3D_Ghost_v1` as
  `{s = seed, f = csv}`. On run start the client fetches it via
  `GetGhost` and replays only when `ghost.seed == run.seed` — the echo
  always traces the identical lane, which is what makes it honest.
  Playback is a translucent neon ball lerping between time-stamped
  frames; it's cosmetic — CanCollide/Query/Touch all off, no physics,
  no scoring effect, dies with the run.
- Server-side validation lite: reject submitted scores above
  `maxSpeed * elapsed * 1.15` + gem cap sanity.
- Production guards: top-board submission is a single atomic `UpdateAsync`
  max (no cross-server Get/Set race) and only fires on session records;
  all writes retry `SaveRetryCount` times with backoff. Menu fetches share
  a `CacheSeconds` server-side cache — invalidated the moment a new record
  lands, so a just-saved record is still immediately visible — behind a
  per-player `FetchCooldown` that serves stale rows to repeat pulls. A
  `leaderstats` folder mirrors live Score/Best onto the native playerlist,
  and a failed DataStore probe re-tries lazily rather than latching the
  server offline.
- Personal-best save happens on kill and on `BindToClose` flush — a
  `PlayerRemoving` task-spawned save alone can lose the race on server close.
- Studio playtests need "Enable Studio API Access" ON for DataStore writes —
  noted for setup. When stores are unreachable the menu panel shows
  `leaderboard offline` (nil rows) — an *empty* board says
  `no saved runs yet`, a distinct state, not an error masquerade.

## 15. Architecture

```
src/
  ReplicatedStorage/RoBall/        -- shared, pure modules
    Config.luau                    -- all tunables (exists)
    Palette.luau                   -- distance -> vaporwave gradient
    ChunkDefs.luau                 -- chunk type table: weights, width rules,
                                   --   entry/exit constraints, builders
    GenCore.luau                   -- pure generator: (rng, state) -> chunk spec
                                   --   + debut state machine (§8.6)
    GenVerify.luau                 -- solvability audit sweep (§8.6)
    SongMap.luau                   -- generated beat/section chart (renderer
                                   --   output, required by GenCore + client)
    Cosmetics.luau                 -- cosmetic catalog: items, slots, bundles (§18)
    BallDress.luau                 -- shared ball dresser (rings + trail) for
                                   --   server spawn and the client menu preview
  ServerScriptService/RoBallServer/
    Main.server.luau               -- boot/wiring (exists): run lifecycle folded
                                   --   in (remotes, spawn, kill, heartbeat,
                                   --   seed parse/hash)
    TrackStreamer.luau             -- spec -> Instances, cleanup behind ball,
                                   --   mover heartbeat (§8.6)
    GenVerifyRunner.server.luau    -- Studio-only audit sweep runner (§8.6)
    SaveService.luau               -- DataStore best/profile + OrderedDataStore top
    ShopService.luau               -- pass ownership, equip validate+save,
                                   --   purchase-finished auto-equip, gem bank,
                                   --   per-item buys, ProcessReceipt (§18)
  StarterPlayer/StarterPlayerScripts/RoBallClient/
    Main.client.luau               -- boot, state machine, drive, chase cam
    Ui.luau                        -- menu + HUD + death screen + garage, all in code
    Backdrop.luau                  -- synthwave sun + swappable side scenery
                                   --   (city canyon | NEON PEAKS, client-local)
    MusicController.luau           -- stem graph, tempo ramp, beat clock (AUDIO.md)
    SfxController.luau             -- gem pickup chime, pentatonic combo runs
    GemFx.luau                     -- pickup juice: pop diamond + sparkles + ring
    DeathFx.luau                   -- death burst variants at last ball pos (§18)
    CosmeticFx.luau                -- menu preview ball + animated skin/trail fx
                                   --   (rainbow/pulse), all client-local
    PadController.luau             -- LaunchPad kicks: applies KickY to the
                                   --   client-owned ball on pad touch (§8.6)
    OrbController.luau             -- JumpOrb taps: Space/touch within Radius
                                   --   re-kicks vY (§8.6, flag-off)
```

Generation runs **server-side** (authoritative + leaderboard integrity);
`GenCore` is pure and unit-testable on either side.

## 16. MVP build phases

| Phase | Deliverable | Done when |
|---|---|---|
| P0 | Rojo scaffold, git, docs | `rojo build` produces a place |
| P1 | Ball + input + camera | Ball rolls at fixed speed, steers, falls, respawns |
| P2 | Generator core | Intro + Flat/Slalom/Narrow stream infinitely, seeded |
| P3 | Tiers + gems + scoring | Speed tiers apply, risky gems score, death seals run |
| P4 | Menu + HUD + restart | PLAY/seed/leaderboard UI, instant restart loop |
| P5 | Persistence | Personal best + global board save/load in Studio test |
| P6 | Art pass | Palette gradient, backdrop, ball skin, bloom, music ramp |
| P7 | MCP playtest polish | Screenshot/verify loop, tune Config numbers |

## 17. Explicitly out of scope (backlog)

Power-ups (shield/magnet/slow-mo — if sold, runs must submit to the
assisted board, §18), mobile/touch controls, alternate biomes, music packs,
parties/social. (Tap-orbs and gravity-flip rides are now implemented behind
`Config.Features.JumpOrbs`/`GravityFlip`, default-off — §8.6.)
All have designed-for extension points (chunk features, `datamodel` hooks)
— nothing blocks them.

## 18. Monetization

**Phase 1 = cosmetics only.** The leaderboard is the replay hook, so v1
sells looks, never power. Death stays final — revives were considered and
explicitly rejected (a paid continue is just buying board position). Every
item is a pure visual in one of five slots: `skin`, `trail`, `gemFx`,
`deathFx`, `world` — `world` swaps the entire side-scenery theme (§12:
city canyon ↔ NEON PEAKS ridge field), the first environment-tier DLC.

**Catalog**: items live in `Cosmetics.luau` (ReplicatedStorage) — each is a
data record `{ slot, name, ...colors/params }`, so a new look is config,
not code. Items ship in **themed bundle gamepasses** (one pass = a matched
set across slots): passes are the platform's permanent-unlock primitive and
keep the dashboard surface small. Pass ids live in
`Config.Monetization.Passes`; `0` means the pass isn't created on the
Creator Dashboard yet — the shop shows SOON and everything else still works
(same stub pattern as `Music.Stems`). `Config.Monetization.FreeForTesting`
(temp, pre-paywall) makes every pack/product grant instantly on click
through the same ownership/equip/save pipeline — the shop shows FREE
instead of SOON.

**Color law**: cosmetics must never sample or resemble `LethalColor`
(255,32,48, hue ~356°). The allowed space is the vaporwave family
(magenta → violet → blue → cyan), gold, orange sun-tones, and mono. This is
the same rule the world palette already enforces; the shop obeys it too.

**Persistence**: `RoBall3D_Profile_v1` stores `equipped` ids, the `bank`
balance, and `items` (ids bought with gems). Bundle ownership is derived
live from `UserOwnsGamePassAsync` so passes are the single source of truth
for their items and nothing can desync — gem purchases have no platform
record, so the profile's `items` array is theirs. The server caches
ownership per session and mirrors state onto player attributes
(`RoBallEq_skin` / `_trail` / `_gemFx` / `_deathFx` / `_world`, a
`RoBallOwned` CSV of
bundle keys + purchased item ids, and `RoBallBank`), so client FX, the
garage, and the menu preview read state without a fetch remote.

**Buying**: client calls `PromptGamePassPurchase`; the server's
`PromptGamePassPurchaseFinished` handler refreshes ownership attributes and
auto-equips the bundle's items so a purchase is felt immediately. The
`EquipItem` RemoteFunction re-validates slot + ownership server-side before
saving — client UI is only a suggestion.

**Gem bank (P2)**: every pickup is dual-purpose — score points AND banked
currency, credited live at `Config.Monetization.BankPerGem` (1) per gem.
The 2X BANK pass (`Passes.bank2x`) doubles the credit. Banked currency is
**never score**: it lives on `RoBallBank`, nowhere near the leaderboard
path. Credits persist at boundaries — run end (kill + fast-restart),
purchases, leaving, `BindToClose` — so a crash loses at most the in-flight
run's gems.

**Spending**: every non-free item carries `gemPrice` — the grind path.
Bundles stay the priced shortcut: à-la-carte totals (700–2500 gems) sit
well above their pass price (R$49–199), so paying feels like a deal and
grinding feels fair. `BuyItem` re-validates everything server-side
(catalog record, ownership, balance), deducts, records the item id, and
auto-equips — same post-purchase delight rule as bundle passes. Gem packs
are dev products (`Config.Monetization.Products`): `ProcessReceipt` waits
for the profile, grants `ProductGems`, and saves immediately before
returning `PurchaseGranted`; unknown ids or an unready profile return
`NotProcessedYet` so Roblox retries instead of eating a payment.

**TRACK row (music packs, early P3)**: a sixth cycler under the equip
slots picks the run's song — `SEEDED` keeps the seeded pick; a named
track sends a seed in its residue class so `SongMap.trackIdFor` lands on
it and the gen stamps that track's map (seed-box text / `daily` still
wins). The row browses `Config.Music.ActiveTracklist` — every uploaded
track, not just owned ones; songs aren't purchases, they're the level
picker.

**Garage (P2)**: arrows browse the WHOLE catalog, not just owned items —
owned items equip as they pass, unowned ones park showing their ◊price and
buy on name-click. The BANK block shows the balance, three gem-pack
buttons (SOON until product ids exist), and the 2X BANK row wired like a
bundle pass. The death screen reads `◊ +N BANKED` — the payout visible on
every run end.

**Show surfaces**: private lanes hide other players, so the flex surfaces
are the run itself and the **menu preview ball** — a client-local dressed
ball parked in the menu vista that rebuilds on every equip change
(`BallDress` is shared so server spawn and preview draw the same way).
Animated flags (`fx = "rainbow" | "pulse"` on skins, `"rainbow"` on
trails/gemfx) are evaluated in the client render loop. The `world` slot
rides the same plumbing: `RoBallEq_world` lands on the client and
`Backdrop.setTheme` re-seeds whichever scenery system takes over — the
NEON PEAKS vista is visible in the menu the moment the pass equips.
`world_peaks` sells as its own bundle pass (`Passes.peaks`) or à-la-carte
for ◊800 — the flagship grind target. **DEEP SPACE** (`Passes.deepspace`)
packs both new world themes — `world_void` (STAR WELL) and `world_grid`
(GRID PLANE), each also ◊800 à-la-carte. Later sets fill the palette
families the launch bundles left open: **AURORA** (green-polar: teal-green
rings, borealis nova) and **PHANTOM** (ghost-mono: white/amethyst rings,
static shatter). All stay inside color law — nothing near `LethalColor`.

**Seasonal slot**: `Config.Monetization.Seasonal` holds one bundle id plus
a yearly UTC `[Start, End]` month/day window (wrap-around legal, e.g.
Dec 15 → Jan 8). Inside the window the pack sells like any other; outside
it the button reads `IN Nd` (days until opening) and the server refuses
both the bundle claim and à-la-carte gem buys of its member items.
Ownership already granted is permanent — scarcity gates acquisition, not
use. Currently **SOLSTICE**: frost skin/trail/gemfx + AVALANCHE death
(shatter style in the ice palette). `Daily.seasonalStatus` is the shared
UTC math so client display and server enforcement agree.

**Score integrity contract**: the leaderboard meta row carries
`assisted = false` today. Any future advantage item (bounded power-ups sit
in the §17 backlog) must set it and submit to a separate `*_Assisted`
OrderedDataStore — clean and assisted boards never mix.

**Phases**:
- **P1**: cosmetic catalog + bundle passes + garage UI + profile store.
  2 free alternates per slot so the equip system is live for everyone.
- **P2 (this)**: gem bank (dual-purpose pickups — banked currency is never
  score), gem-pack dev products, per-item `gemPrice`s, the "2x bank" pass,
  browse-the-catalog garage.
- **P3 (backlog)**: themed monthly bundles, music packs (renderer mints
  tracks for free). The seed-of-the-day board landed ahead of schedule —
  see §14's daily board.
- **Never**: energy systems, timers, pay-to-restart, fake urgency, paid
  random items without PolicyService + disclosed odds.
