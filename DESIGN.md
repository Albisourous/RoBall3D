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
  `BaseWidth` to match (~16 ball-diameters — the width ceiling never
  shrinks; only the floor ratchets with tiers).
- **Red = lethal, always.** Slope's one-color hazard language means zero
  ambiguity: players budget clearance the instant red is visible. We adopt it
  exactly: `LethalColor` is reserved for kill geometry and is *never*
  palette-shifted — edges, gems and scenery may hue-cycle, lethal red may not.
- **Obstacles are the mid-track threat; edges are the ambient one.** Slope's
  atlas: static blocks, walls with one opening, moving blocks, gaps,
  ramps, narrow lanes. MVP adds `BlockGate`/`BlockField`/`WallSlot`; moving
  blocks are post-MVP.
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
- **Bank pull** (`Config.Steering.BankPull`): a rolled deck pulls the ball
  toward its low edge — the under-ball surface normal carries the bank, so
  `sin(roll)·BankPull` biases the lateral velocity target whenever the ball
  is grounded. Idle drifts downhill; counter-steer still wins but pays the
  pull out of `MaxLateralSpeed`, and a downhill steer exceeds it (gravity
  assist). Airborne reads no surface — jumps stay clean. This is what makes
  Tilt/Sway a verb instead of scenery.
- **Slope tracking** (`Config.Landing.SlopeSmooth`): while grounded the
  drive vector projects onto the surface (`drive − (drive·n)n`, the probe
  normal eased so slice seams don't pop Y), and the projection's Y becomes
  the vertical velocity — the ball pushes itself down hills and rides over
  crests instead of launching (Monkey Ball feel). Fresh pad/orb kicks and
  real airtime keep physics Y — gravity still owns an actual fall.
- **Power meter** (`Config.Power`): one shared resource bar driving all
  three verbs — hold `W`/`↑` = ×`Mult` (1.5) boost, hold `S`/`↓` = ÷`Mult`
  brake, tap `Q`/`E` = dash (below). The ~1.2s charge drains while a held
  verb runs, refills on release (~10s to full — a deliberate pace, so
  gem lines matter), and emptying latches
  **every** verb out until ~35% refilled. Boost/brake both ease at 4×
  normal accel so the HUD tempo visibly jumps; the bar flares pink on
  boost, orange on brake. The gold `RechargeGate` notch in the strip is
  the universal **armed** marker — a meter past the notch means all
  three verbs are live, so "can I act?" is read off the bar, not felt
  out. Gem pickups refund meter by point value (`Power.GemPerPoint` —
  safe 3%, edge 4.5%, beam 7.5%, gap-arc 12% of the bar), so a risky
  line is a real recharge, not just score. Charge lives on the bottom-left
  meter bar (§12).
- **Dash** (`Config.Dash`): a lateral burst left/right — same steer-ease
  math drives lateral velocity toward `Speed` (64 s/s ≈ 2.4× max steer)
  at burst accel (~25ms to full — a snap, not a hard-slide) for
  `Time` (0.16s): a ~10-stud sidestep that
  clamps back into steer range on release. **Dash style** is a saved
  menu toggle (`Dash.Modes`, `RoBallDashMode` attr, persisted in the
  profile like a mixer gain): `keys` = tap `Q`/`E`, `tap` = a second
  press of the same `A`/`D` steer key inside `TapWindow` (0.28s) dashes
  that way. First tap still steers — the dash
  only reads on the repeat press. Steering is ignored mid-burst — the
  dodge is a commitment.
  Each dash spends a flat `Cost` (0.3 ≈ a third of the bar's sweep)
  of the **same** power meter boost/brake drain — offense, defense and
  dodge all bid on one resource, so a spent dodge is a boost you don't
  have. Dash arms on the **marker**, not its own threshold: the gold
  `RechargeGate` notch is the readiness read for every verb — below it
  a press is denied (the bar flickers dim), past it the dodge is live.
  `Cooldown` (0.35s) paces repeat bursts — the meter is the real
  limiter. A press that lands mid-burst or on cooldown doesn't die: it
  arms a `BufferWindow` (0.4s) buffer that auto-fires the moment the
  window is legal, so back-to-back pairs (`A·A` then `D·D`) chain at the
  earliest legal instant instead of being eaten. Airborne is legal physics: a bad Terrace bounce or ramp arc
  can be bought sideways at meter cost, and a dash can even carry a
  narrow cutout laterally — voids still kill (Y stays gravity's), so
  the skip is a gamble, not a cheat. The bar flashes white for the
  burst window; an accepted press plays a downward pitch-swept zip plus
  a light mix duck, a denied press a low blip that mirrors the flicker
  (AUDIO.md §6). No chunk ever *requires* a dash — it only widens the
  movement envelope, so every §8.1 solvability invariant still stands
  on steering alone.
- **Restart**: `R` in any mode = instant restart on the seed box's pick —
  `daily` by default, a typed seed, or a rolled random that gets mirrored
  back into the box on `RunStarted`, so a reload keeps the same map
  unless the menu says otherwise. Mid-run it tears the run
  down server-side without firing `RunEnded` and without saving the score —
  restarting to dodge a death never banks it.
- **No jump** in MVP.
- Keyboard only in MVP; touch later.

Ball: 3-stud `Ball`-shape Part, unanchored, `CustomPhysicalProperties`
(density 0.7, friction 0.6, elasticity 0, **elasticity weight 100** — the
ball's zero restitution dominates every contact). Elasticity alone still
bounces on fast landings — the solver's impact response pops the ball —
so once the lane probe sees deck within `Landing.ClampReach` the client
caps the approach at the deck's own descent rate (`Grade*fwdSpeed`)
plus `Landing.ImpactPad`: the ball lands flat, **never hops**, and a
bounce can't throw it into the next hole. Over a gap the probe finds
nothing — falls stay free. Server drives
`AssemblyLinearVelocity` each `Heartbeat`: `Vector3(lateral, naturalY, forward)`.
Y velocity is untouched — gravity handles falls, slopes, ramp arcs.

## 5. Camera

Chase cam: offset `(0, 13, 12)` studs behind/above the ball. The aim point is
not flat-ahead — it drops to the deck plane `LookAhead = 16` studs out
(`target.y -= Grade*16 + LookDrop`), so the camera pitches into the slope
(~28°) the way Slope does: ball low in frame, long readable runway ahead.
FOV eases `70 -> 88` with speed. Up to `LeanMax = 3°` of roll into the steer
direction for momentum readability. The horizon itself follows
`BankLean = 0.5` of the deck's bank — a banked chunk tilts the world, not
just the ribbon, while the deck stays visibly banked. No vertical bob
(keeps precision readable).
The position follows with an exp damp at `Camera.SmoothTime` (0.12s —
`alpha = 1 - e^-dt/τ`, frame-rate independent): deck-seam and landing bumps
filter out while the aim stays locked on the lead point, so a dash reads as
a brief elastic trail. Run starts snap rather than ease in from the menu.

## 6. Run structure & menu

- **Menu** (built in code, `StarterGui` from Luau — everything stays in git):
  "Shop floor" layout — the menu backdrop is **opaque** (the running
  world is NOT the background; a live scene behind the merch buries it).
  Three permanent zones: a left **GARAGE rail** (always open — the shop
  is zero clicks away, conversion needs the merch visible), a center
  **poster column** (title `ROBALL3D` over a hairline cyan→pink horizon
  rule, PLAY, dash, seed, track, best), and a right
  **LEADERBOARD rail** (always open — your rank is the ad for the rerun
  loop). The missions card is the only pop-up: a deck card over the
  bottom caption row (`dashHint` keymap).
  - **PLAY** — the only filled element on the screen (solid pink slab,
    cyan rim on hover); `ENTER`/`R` also start. Everything else is chrome.
  - **DASH button** — its own bordered gold chip directly under PLAY;
    cycles `keys / tap / both`, server-mirrored + saved (§4).
  - **SEED row** — directly under the dash button. The box defaults
    EMPTY with `daily` as the placeholder: blank = today's shared seed,
    any typed text is a seeded run (keywords like `daily`/feature seeds
    still resolve, §14). No daily/random mode swap — the empty state IS
    the daily mode, and it stays empty after a run so it keeps tracking
    today (a rolled seed is never mirrored into the box).
  - **TRACK row** — under the seed row; `‹ name ›` cycler picks the
    run's song (AUDIO.md §3).
  - **Missions card** — rides the bottom edge permanently (`◇` open /
    `✓` done quests + award tally, §14), fed by `setQuests`/
    `setAchievements` — no click to reveal it and no duplicate
    summary line under BEST.
  - **GARAGE rail** — tabbed `STYLE | PACKS | BANK | AUDIO`: equip
    cyclers, bundle passes, the gem bank, and the audio mixer (§18).
    The bank balance lives in the garage header — spendable gems sit
    next to every ◊ price. PACKS is a scrolling list — each row is an
    accordion whose body lists the bundle's actual contents
    (`bundle.items` → `SLOT · ITEM NAME`, tinted to each item's own
    color), one open at a time, so a purchase is never a guess. An open
    pack also takes over the PREVIEW window — the diorama dresses in
    the bundle's full 7-slot look so the set sells itself as a set;
    closing it (or cycling a STYLE row) hands the preview back to the
    browse set.
  - **PREVIEW window** — pinned to the bottom of the garage rail: a
    `ViewportFrame` playing a REAL-SCALE slice of the game (§18) — a
    straight Flat ribbon, the dressed ball rolling down-grade at the
    real opener speed, the live chase-cam transform, and world + sun
    from `Backdrop.diorama`. CosmeticFx rebuilds it from the *browsed*
    item on every slot — unowned merch previews before the buy
    (try-before-you-buy). The screen-filter cosmetic repaints inside
    the window as a Gui overlay.
  - **Leaderboard rail** — DAILY / TOP tabs (`name / score /
    seed`), DAILY left and selected by default to match the default run
    mode; the daily tab shows the shared seed + UTC reset countdown.
    A `◈ friends` toggle filters whichever board is
    open to your Roblox friends — rows keep their real rank numbers; the
    id set lazy-loads once per session via `GetFriendsAsync`. A `RECENT`
    strip pinned under the rows lists the newest
    `Config.Leaderboard.HistoryShown` runs of your own history
    (`pts · m · #seed`, newest first) — a tap prefills the seed box for
    a deterministic rerun of that map. The server keeps
    `Config.Leaderboard.HistoryCount` entries per profile (`history`,
    appended on every clean run end, also session-only until the first
    save) and mirrors them to the client as the `RoBallHistory`
    `s,d,z;…` CSV attribute
  - Audio console — an `AUDIO` garage page, four channel sliders stacked
    one per row (`MUSIC / GEMS / DASH / WIND`, 0–100%) riding the
    mixer taps in AUDIO.md §7, persisted via `profile.audio` →
    `RoBallVol_<ch>` attributes so a mix survives sessions. Defaults
    (`Config.Audio.Defaults`): all four at half — the
    sources are mixed hot; full-everything was deafening.
  - Personal best label
- **Run start**: `Config.Steering.SettleSeconds` (0.8s) "rolling…" settle,
  then control handed over.
- **Death**: pitch drop on music, death-cam orbit (§11), then the death
  screen lands as a **crash-log report card**: a `SIGNAL LOST` rail
  banner, a one-line verdict (`lost at N m — the VOID · inside FORK`),
  then a bordered mono readout panel — `RUN <seed>` header, hero `score`
  row, `best`, a `gems / banked` payout row, and the telemetry rows —
  with `[R]` or the `RETRY` button = instant
  restart on the seed box's pick (`daily` by default — the box keeps
  whatever seeded it, so retrying replays the same map).
  A gold `★ NEW BEST!` rides the score row when the run beat the
  stored record — the flag is computed server-side since attribute
  replication races make a client-side compare unreliable. The
  telemetry rows: `top` forward speed, `gates` lethal planes crossed,
  `boost` share of distance spent boosting, `air` share of run time
  airborne (the landing
  probe counts contact when the ball's underside is within
  `Landing.ContactPad` of lane ground), and `margin` the tightest
  near-miss of the run (`in-disc` when the closest call was inside a
  rotor's sweep). A dim trailer under the panel, `at the fall: PB +38 ·
  champion42 -142`, closes the report when echoes replayed — the last
  pace delta vs each ghost, signed by your lead, so the race result
  survives the run that ended it.
- **PB ghost**: on run start a translucent magenta `BEST n` gate floats on
  the deck at your record's end distance (`Score.PbMarkerMinDist` = 150m) —
  you race your own shadow. The label stays near-field only
  (`PbMarkerViewDist`, no AlwaysOnTop) so it isn't a constant screen
  occupant; crossing the line flashes a gold `★ NEW BEST` under the HUD
  score for `PbFlashSeconds`. Record `dist`/`seed` only overwrite on a true
  new record, so the gate always marks the real best, never a later run.
  The HUD score cluster lives top-right — Roblox's native menu overlays
  the top-left corner, and the center cone stays clear for the track
  read at speed. The score digit wears the speedo's chrome: gradient
  band, neon rim, cyan/pink VHS ghosts and a −4° outrun slant, thumping
  on the same audio-pulse quantum; the subline warms dim→pink toward the
  edge and the combo pip carries a cyan neon rim. While the PB echo replays (same-seed runs, §14) a
  `±N vs PB` line under the cluster shows the live meter delta against
  the ghost's position at the same elapsed time — cyan ahead, pink
  behind, hidden when no echo exists. Inside `Ghost.DuelRange` studs
  either way a `· DUEL` suffix joins the line — nose-to-nose reads as a
  race, not a number (the rival `±N vs <name>` line tags the same way).
- **Last-fall marker**: a dim red `LAST n` gate marks where the most
  recent clean run on this seed ended — the bloodstain for an R-rerun.
  Read from the `RoBallHistory` attribute (newest first), same 150m
  minimum and view-distance rules as BEST; suppressed within 8 studs of
  the PB gate so a last run that *was* the record doesn't double-mark.

## 7. Seed system

- Every run's map is a pure function of a seed: `Random.new(seed)` drives all
  generation choices. Same seed → same chunk sequence → same map.
- Default runs use `tick() % 2^31` randomized per run; the used seed is always
  displayed on the death screen and stored with the score so leaderboard rows
  are replayable/verifiable.
- Seed entry: numeric or text (hashed to int via a stable string hash).
- Feature seeds (debug-only): while `Config.Debug.Enabled` is on, a
  seed-box keyword matching a chunk type or label (`pressrow`,
  `TERRACES`, "press row") forces a run where every chunk is that
  feature — intro/debuts/pool weighting all bypassed, and the text still
  hashes to the seed so the same word replays the same layout. A
  `Debug.FeatureRunway`-long flat lead-in runs first so the element is
  visible on approach. Forced runs are flagged `run.debug` and earn
  nothing — no record, no board, no quests/streak, no ghost credential.
  **Flip `Debug.Enabled` off before release** so the keywords resolve to
  ordinary hashed seeds on live servers (sites: `ChunkDefs.matchFeature`,
  `GenCore.onlyType`, `Main.server` resolveSeed, `Debug.FeatureRunway`).

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
width is generous and stays reachable — the floor tightens with tiers
but the ceiling never shrinks; it is not a narrow ribbon).
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
| `Tilt` | Ribbon rolls around its long axis ±(8–20°→cap, steepens with distance via the §9 roll ramp) — bank pull drags the ball toward the low edge | Momentum management | 3+ |
| `FullTilt` | The whole chunk commits to one steep bank (26–34°→cap via the §9 roll ramp), cosine-eased in/out so the pull never snaps — bank pull is the entire hazard; edge gems ride the downhill rail you're being dragged toward | Sustained counter-lean | 6 |
| `LeftTilt` | FullTilt locked to a left bank — same sustained pull, fixed direction | Counter-lean left | 6 |
| `RightTilt` | FullTilt locked to a right bank | Counter-lean right | 6 |
| `Pinch` | Width collapses to 2–3 studs mid-chunk, reopens | Burst precision | 3+ |
| `SplitGap` | Center channel removed → two side ribbons; void-adjacent edges glow **lethal red** (void = kill geometry) so the split reads from the horizon | Route choice | 4+ |
| `Bowl` | Banked walls rise on both edges | Rest + dense gem canyon | 4+ |
| `RampGap` | Launch ramp, full-width void, landing strip + a gem-paying hoop at the flight apex | Speed check / spectacle | 5+ |
| `BlockGate` | Red blocks across the deck, one gap ≥ CorridorMin | Thread-the-gap | 2+ |
| `BlockField` | Scattered red blocks, density scales with tier | Weaving pressure | 3+ |
| `WallSlot` | Red wall spanning the deck, single opening | Commit-to-a-lane | 4+ |
| `Terrace` | Deck descends in soft lips — each tread is one whole cosine ease: flat at both seams, steepest mid-tread. No up-slopes, no lip edge, no foot-V — a flying ball only ever meets surfaces sloping away | Free ballistic spectacle | 2+ |
| `Swell` | Full-width ribbon undulating in y — rolling hills, up and down 3–6 times a chunk (amp 2–7); integer sine periods land the exit on the entry height, and `Swell.SlopeMax` keeps crests as air-popping hops, never walls | Kinesthetic rest | 2+ |
| `Sway` | Ribbon bank oscillates left-right — a slalom for the roll axis; integer sine periods land the exit level, `Sway.RateMax` caps deg/stud so the bank rolls like a wave, `AmpMax` steepens with the §9 roll ramp, and bank pull surfs the ball with each crest | Hold the line | 2+ |
| `SnakeField` | Edge-flush blocks alternating sides on a long chunk | Beat weave | 3+ |
| `Blackout` | Flat geometry, grid/center neon dims to rails+gems only — break sections only | Atmosphere | 3+ |
| `Chicane` | Wall rows with gaps pinned to alternating rails | S-steer combo | 4+ |
| `Fork` | Asymmetric split: thin gem-loaded rail / wide bare rail | Route choice | 4+ |
| `PadHop` | LaunchPad (cyan strip) kicks ball ballistic over a lethal strip | Computed arc | 4+ |
| `PadVoid` | LaunchPad launch across a void — pad supplies airtime, not speed | Early gap spectacle | 5+ |
| `DropGate` | Full-width wall whose gap threads ON a drop accent downbeat | Beat-slam set piece | 5+ |
| `Pacer` | Wall pair whose fixed gap slides L↔R on a beat-locked sine | Timing window | 6+ |
| `PressRow` | Open-air crushers: each ceiling press hangs in a neon gantry frame under open sky, slamming on a trapezoid wave; a ghost-red footprint marks each plate's kill zone on the deck and the plate's wireframe fills solid as it slams; one side lane stays permanently clear per row (flipping sides only when one beat-gap affords the crossing — otherwise the lane holds and widens), under-plate is the timed shortcut; the lane is rail-pinned, so the lead grows until a worst-case far-rail entry can afford the `2·halfW − gapW` transit — `canRun` declines decks where that runway would be degenerate | Vertical timing | 6+ |
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
- `Obstacle.hang` anchors a slab's top to `Config.Press.HangH` —
  PressRow's plates hang from their gantry frames under open sky; the
  red `PressZone` footprint marks each kill zone on the deck.
- `Obstacle.motion` (`slideX`/`spin`/`dropY` + periodSec/phase) —
  beat-locked movers; periods are whole-note counts of the heard tempo
  so the hazard cycle IS the music. `dropY` runs a trapezoid pulse —
  raised, fast slam, hold, rise — driven by `Config.Movers.Press*Frac`
  (shape shared via `MoveWave.pressPulse`), and `MoverController` fills
  the plate's outline surface toward `Press.SlamFill` as the pulse rises —
  the wireframe going solid IS the slam telegraph. Mover parts carry the
  whole
  waveform as `Mover*` attributes + a `RoBallMover` tag; the server's
  `StepHz` writes feed only its own hazard bookkeeping while the
  client's `MoverController` re-evaluates the wave every frame on the
  synced server clock (`MoverEpoch`) — smooth motion, and kills test
  exactly what the player sees.
- `ChunkSpec.pads` — LaunchPad strips (cyan, tagged `RoBallPad`,
  `KickY` attribute). The client applies the kick (it owns the ball's
  velocity): GD pads as terrain, not a jump button. Contact is
  `Touched` plus a per-frame sphere-vs-strip overlap test in
  `PadController` — a pad the ball visibly crosses always fires; the
  0.35-stud strip can't be tunneled or grazed past unseen. The trigger
  reaches `Pads.GrabH` above the strip top rather than testing literal
  surface contact — a "grounded" ball can ride up to
  `Landing.ContactPad` off the deck at speed (a seam pop takes ~0.2s to
  settle back down), enough to sail over a shallow band unseen. PadHop rolls
  the pad's lane offset inside ±width/5 capped at `Pads.MaxOffset`, so
  wide decks can't park the pad outside readable-steer range.
- `ChunkSpec.dim` (Blackout) dims grid/center neon to `Blackout.GridScale`
  — edges + gems stay lit.
- `ChunkSpec.hoop` — `RampGap` carries a faceted neon ring at the void's
  flight apex (`Hoop.Radius`/`Tube`, center `Hoop.ApexLift` above the
  launch plane). Threading it mid-air pays gems (§10).

### 8.4 Gem placement

Gems cluster on **risky lines** (this was the explicit choice): edge rails,
narrow beams, arcs over `RampGap` voids, and straight through the middle of
obstacle gaps (the corridor you're meant to thread — highest risk/reward).
Value scales with risk class:
safe `10` / edge `15` / beam `25` / gap-arc `40`. 0–3 clusters per chunk.

**Worth IS the shape** (`GemTypes.luau` + `Config.Gems.Kinds`): every value
tier renders its own Neon silhouette in a warm-family tint — hotter and
heavier reading = more points, so the payoff telegraphs at speed:

| Value | Name | Shapes (seeded pick) | Tint |
| ----: | ---- | ---- | ---- |
| 10 | chip | corner-balanced cube `diamond` / pearl `orb` | gold `255,212,64` |
| 15 | edge | upright `coin` / `orb` | amber `255,168,52` |
| 25 | beam | standing wedge `shard` / vertical `rod` | orange `255,132,50` |
| 40 | arc | fat `crown` diamond ×1.55 | white-hot `255,244,185` |

All shapes are engine primitives (Block/Ball/Cylinder/Wedge — `GemTypes.pose`
owns the silhouette + local rotation). The per-spot pick is a deterministic
hash of the emitted `(startZ, t)` — NOT the generator rng — so a seed
replays the same type mix every run (§6 purity: render-only, never feeds
scoring). Tints stay in the gold→white "currency" ramp, clear of
`LethalColor` red. The collected shape rides `RoBallGemShape` on the player
so client FX knows exactly what was picked up. (Two-pyramid octahedron via
`MeshType.Pyramid` was tried: that legacy mesh type renders nothing in the
current engine.)

**World restyle** (`gemStyle` on world items): a world cosmetic may restyle
every pickup at spawn — `world_sky` (APE BALL) sets `gemStyle = "ball"` and
TrackStreamer renders each gem as a banana-yellow capsule orb through
`GemTypes.ball` (tier lead-scale still sizes it, so worth keeps
telegraphing). The streamer stamps the live pickup's own `Color` into
`RoBallGemColor` alongside `RoBallGemShape`, so the client's pop ghost
matches styled pickups too. Authoritative value/scoring path untouched —
the style is render-only and set per run from the equipped world.

**Pickup juice** (`GemFx.luau`, client): the gem itself is `Destroy`ed
instantly server-side, so the flourish is client-local at the ball's
position when `RoBallGems` ticks up — a ghost of the collected gem pops
oversize in its real shape + tier tint and rises/fades while tumbling, a
sparkle burst scatters (built-in sparkles texture, always resolvable; the
equipped `gemFx` color), and a thin neon ring flashes outward across the
deck. All one-shots, gone in ~0.5s.

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

Debuts are generation-side only — `GenCore` stamps the spec so the
ramp can gate a type's hard variants on the showcase having run. No HUD
banner: the `NEW ▸ LABEL` flash was cut as screen clutter.

Ramp (spaced wide — features come late): Terrace 400m · SnakeField 800m ·
Blackout 900m · Chicane 1300m · Fork 1500m ·
PadHop 1700m · PadVoid 2100m · DropGate 2300m · PressRow 2600m · Pacer 2700m ·
Rotor 2900m · FullTilt 3000m · LeftTilt 3200m · RightTilt 3400m · OrbHop
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
must hand the next a level, open seam), the **no-up-step** invariant (the
deck never presents an upward-facing step — fine-sampled sections flag
any rise steeper than ~1.5 studs/stud; smooth rises like RampGap's ramp
and Swell's hills stay far below), and **lateral reachability** — the
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

### 8.7 Seed flavor (mutators)

Every seed rolls exactly one **flavor** from `Config.Mutators` on a
salted rng stream (`Random.new(seed + Salt)`) — separate from the gen
rng so the flavor pick can never shift the chunk roll sequence. The
flavor is a table of **weight multipliers** (`fams`/`types`) folded
into the songform pick (AUDIO.md §5.2), plus an optional **width
axis** (`width`) that scales the tier width window every chunk
target rolls from — the drift math, clamps, and `canRun` contracts
all run on the scaled window. It cannot
introduce a chunk `canRun` wouldn't already allow, cannot touch the
scripted intro, the debut ramp, contracts, or pacing, and `standard`
(¼ of seeds) is the plain mix. Fairness: same seed → same flavor →
same map, so the daily board stays a same-map race; off-daily the TOP
board already compares across seeds, and flavor is just one more axis
of seed identity. Flavors: STEADY (lethal-light breather runs),
PRESSURE (lethal-heavy), AIRSHOW (spectacle-heavy), WEAVE
(technical-heavy), GROUNDED (anti-airshow — spectacle ×0.35,
technical ×1.5: jump-free deck runs), ROTOR FIELD / PRESS GANG /
SNAKE PIT (one mover ×3.5 — soft bias: debut-gated movers only show
once the ramp lets them in), SQUEEZE / EXPANSE (width axis: the whole
map ~18% tighter / roomier). Flavors are
silent — no label rides the HUD, menu, or death card (cut as jargon
clutter); the bias is still seeded into the map itself.

## 9. Difficulty & speed

Tier table is in `Config.Tiers` (milestones → chunk pool + width window).
Speed itself is **one log curve**, not a tier column:

```
speed(d) = Speed.Start + Speed.LogGain * ln(1 + d / Speed.LogDist)
         = 34 + 49.3 * ln(1 + d / 625)
```

Fit through the old step milestones — ≈48@200m, 63@500m, 78@900m,
92@1400m, 105@2000m — then keeps rising slower than linear (~142@5km,
~174@10km, ~197@20km). Start `34` is a shade under the old `40` opener:
first-timer breathing room without a boring crawl. The ball eases
toward the curve at `Accel` = `6 studs/s²`.

Crossing a tier threshold:
- new chunk types join the RNG pool
- banked chunks steepen: `Config.Roll` ramps a `rollScale` multiplier
  over `RampDist` (6km) toward a per-seed ceiling in `[MaxLo, MaxHi]`
  (rolled on the salted mutator stream — each run's tilt ceiling differs,
  `Cap` = 42° absolute). Tilt's held bank and Sway's `AmpMax` both ride
  it, so deep runs bank hard enough that bank pull is a real threat
- the width floor tightens (34 → 10 min) — the ceiling NEVER does:
  `widthMax` is pinned at 50 on every tier, so the window itself is the
  difficulty and deep runs span razor-thin to full-width

Within a tier the deck width isn't monotonic: `Narrow` ratchets down
toward `widthMin`, `Flat` re-rolls the width anywhere in the window
(tiers 1–3 and back from tier 5 — it converges an over-wide deck down
into the window too), and from tier 5 `Widen` opens back toward
`widthMax` — so the deep game sawtooths between cramped precision
stretches and full-width reopened fields instead of parking in one
extreme.
`canRun` gates `Widen` to ≥4 studs of headroom under the tier ceiling,
and its edge-margin gems make the lateral reach (Q/E dash, §4) pay off
while the field is wide.

**Endless mode** — there is no speed cap. Past the last listed tier
(2000m), `Tiers.forDistance` extrapolates: the log curve keeps climbing
(unbounded but decelerating — ~142 s/s at 5km vs ~174 at 10km, so the
marginal squeeze shrinks the deeper you get) and the width floor eases
toward `EndlessWidthMinFloor` (12) — floored where a gate row + rim
margin still fits, since below ~12 studs lethal rows can't generate and
the run would paradoxically get easier. The ceiling stays pinned at 50
forever — variance itself is the late-game texture. The chunk pool
stays tier-6's;
**speed is still the difficulty driver** — collapsing reaction time plus
the tightening floor do the work, not new hazards or razor lanes.
`Config.Speed.Max` only normalizes presentation (FOV, music ramp, gem
beat spacing all saturate at it).

Hazards: **falling off the deck** and **touching `LethalColor` geometry** —
both instant death, per the Slope model (§2 REA). Moving hazards and
hanging plates land via `Obstacle.motion` and `Obstacle.hang` (§8.6).

## 10. Scoring

`score = floor(distance_m) + gem_points + near_miss_points`. Distance is
authoritative server-side (ball's traveled `-Z`). Gem values per 8.4. Death
seals the score.

**Near-miss trickle**: every lethal plane the ball crosses without dying pays
`Score.NearMiss.Points` (3) if the pass hugged the geometry — interpolated
crossing-x within `NearMiss.Range` (4 studs, ball-surface to face) of a static
block's edge, or anywhere inside a rotor's translucent sweep disc (the disc
already marks risk honestly). One award per obstacle; hanging slabs never
count (a lateral graze under a plate isn't a dodge) — except PressRow's
`dropY` plates, where the dodge is vertical: crossing the plane *inside the
plate's span* (the guaranteed lane sits outside it) while the plate is
≥`Press.ThreadMinDrop` into its travel pays `Press.ThreadBonus` — a free
pass under a raised plate pays nothing, and a crossing that kills can't
award. The server walks the streamer's ordered hazard-plane list with a
cursor — zero per-frame scans — and `plausible()` carries a loose
`ceil(dist/30) × 8 × Points` ceiling. The trickle pays silently into
score — no flash, particles, audio, or camera kick (the CLOSE ping /
chain ×N row / graze whoosh / FOV-kick layer was cut for noise).

**Hoop bonus**: the `RampGap` ring (§8.3) is a payout line, not just a
spectacle — crossing its plane inside the opening
(`dist(ball, ring center) ≤ r + ballR` at the interpolated crossing
point) pays `Hoop.Score` gem points and `Hoop.Bank` banked gems through
the same dual-purpose path as a pickup, so the `RoBallGems` bump gives
it the pickup flourish for free, while a `RoBallHoop` bump fires the
inhale-swept thread whoosh on the `wind` channel. Off-line or
over-the-top passes pay nothing — threading the ring is the ask.

## 11. Death

Ball leaves track → Y drops below kill plane (`trackY - Config.Death.KillDrop`,
15 studs) → run over
instantly. Ball touches `LethalColor` geometry → same outcome — but the
verdict belongs to the **client**, not the server. The ball's network owner
is the client, so server-side `Touched` judged an interpolated ghost of the
ball and killed dodges that never touched on screen (the "random death"
class of bug). Lethal blocks carry the `RoBallLethal` tag;
`FatalController` on the client fires `ReportFatal` when *its* simulation
touches one — `Touched` for ordinary contact plus a per-frame swept
`Spherecast` along the displacement so hitch-frames can't tunnel through a
block unseen. What the player sees hit them is what kills them. The server
keeps the backstops that can't false-fire on its lagged view: the kill
plane (self-consistent — it compares the same replicated position's y to
the deck at its own z), the stall watchdog, and external destruction. **Unstick hop** (client, first line): the heartbeat writes the
ball's full velocity vector every frame, so a visual freeze means physics is
canceling the forward push against a perpendicular face — a deck-slab or
wall-seam lip left where a section profile jogs. When the ball is grounded
(|vY| under `UnstickMaxY` — resting slope contact reads ~7) yet its real
forward velocity collapses below 15% of target for
`Config.Steering.UnstickTime`, the client pops one Y impulse
(`UnstickHop`, ~0.14s) to hop the lip. `UnstickCooldown` is the refractory so
a true pocket falls through to the watchdog instead of bouncing forever.
**Stall watchdog** (server, backstop): a ball whose position is frozen for
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
explicitly deferred; no replay playback either — watch-replay/rerun/
watch-champion were cut as death-card clutter (any new run's
`Ghost.stop()` still clears live echoes). The
card also **names the killer**: `FatalController` reports the lethal
part it simulated, the server reads the part's `ChunkType` stamp (set
at build from the spec) and carries the type on `RunEnded` — the stats
line ends `felled by NAME` (`Config.Features.Label`, pink). Falls read
`the VOID`, wedge-kills `wedged geometry`; an untrusted or missing part
leaves the line off. Backstop deaths (VOID/STALL/external) additionally
name the chunk containing the ball — `chunkTypeAt(z)` on the streamer —
rendered `— inside NAME`, so stuck-death reports carry the feature
that caused them.

## 12. Presentation

- **Skybox**: pure-black void (`Lighting.ClockTime = 0`), purple-leaning
  ambience and a magenta-purple haze.
- **Backdrop**: retro-futuristic city canyon — rows of near-black towers
  with `SelectionBox` neon outlines flanking the track, 1–3 stacked segments
  per tower, recycled per row for parallax, each tower tint-jittered along
  the vaporwave wheel so the skyline mixes cyan/magenta/violet. A giant
  **striped synthwave sun** (a solid Neon dome, orange crown → magenta
  base, dissolving into strips below the style's solid fraction with
  gaps widening downward) rides `SunDist`/`SunLift` ahead of the ball —
  pushed ~640 studs out so it hangs small on the horizon like a far
  sunset, not a looming wall. The **sun** cosmetic slot (§18) restyles
  the same strip stack via `Art.SunStyles` — colors, dome fraction,
  strip taper, radius scale (moons read smaller). Bases follow the deck's
  downhill grade so the canyon hugs the slope. **Backdrop is client-local**
  (`Backdrop.luau`): zero replication cost. The Atmosphere dims towers past
  ~600 studs; `CitySpan` stays inside the visible band.
  The **world** cosmetic slot (§18) swaps the flanks: **MIAMI NIGHTS**
  plants neon palm rows beside the track (dark violet trunk, cyan→magenta
  frond fan, bead coconuts; crowns rustle on a slow breeze sine);
  **NEON PEAKS**
  replaces the towers with a seeded wireframe ridge field — a displaced
  grid mesh of thin Neon edge parts over near-black tilted facet plates,
  plus a grade-pitched dark slab per tile so ranges occlude the void
  instead of reading translucent. Ridge height is a pure `math.noise`
  function of (side, column, world-lattice row), so independently
  recycled tiles meet in perfect seams and terrain generates fresh
  forever downhill; a lateral ramp keeps a flat valley at the road edge
  (innerX 55 clears the deck's worst lateral reach ~39) and a slow
  along-z envelope lets ranges arrive in passes without ever flattening
  away (`PeaksEnvFloor`). A summit-emphasis exponent (`PeaksPeakPow`)
  needles the crests into a serrated skyline over ~200-stud-tall ridge
  bands. Same client-local,
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
  Wave 2 added three more: **BOREALIS SKY** (`aurora`) hangs light
  curtains beside the lane as soft particles — the same one-emitter
  canopy technique as `polar` (giant `VelocityPerpendicular` streaks
  frozen mid-flight by `Drag`), but each fan is yawed so its sprite
  plane runs ALONG the track beside the deck, rays streaking forward
  and back past the ball over a green→cyan→violet gradient (color-law
  safe by construction, no red seam); **NEON REEF** (`reef`) fields dense thin
  neon strands rising out of the void beside the deck — bases sink below
  the plane, tips poke above it, like kelp on a wireframe reef;
  **METEOR SHOWER** (`meteor`) is the one animated sky — thin neon
  streaks on real velocities (wall-clock dt), respawning ahead once they
  fall below the deck or slip behind. **NORTHERN LIGHTS** (`polar`) is
  the overhead aurora done with soft particles, not part sheets — the
  classic one-emitter trick: giant `VelocityPerpendicular` streak
  sprites burst ~10k studs out of an emitter and `Drag` freezes them
  mid-flight, so what was a burst lands as a luminous canopy. Two
  `SpreadAngle (180,0)` fans stacked down-course sweep the whole upper
  semicircle across the lane; the emitter parts re-anchor ahead of the
  ball every frame (a slow yaw drift wanders the canopy planes) so it
  hangs over the track forever without recycling. Sprites fade in/out
  on a transparency curve and carry the green→white→cyan→pale-yellow
  aurora gradient — every hue inside the color-law window. A sparse
  star field scatters through the band so it reads as night sky, not a
  ceiling. **TOXIC WASTES** (`toxic`) is acid runoff come alive — lime
  Neon bubbles in a wide flanking field, each climbing `ToxicRiseSpan`
  on its own phase out of the dark below deck and popping back to base
  when the phase wraps, with a slow lateral sway so the columns never
  march in step; z recycles on the usual frontier. **SKY COURT** (`sky`,
  APE BALL) is the day-shift look: the client re-times `Lighting` to
  midday (`SkyClockTime` + day ambience/atmosphere — the only theme
  allowed to touch the sky, and it snapshots the server's night rig on
  first equip so any swap restores it verbatim), a green/cream
  checkerboard floor rides the descent `SkyFloorDrop` studs below the
  deck as solid SmoothPlastic tile rows recycled on a shared frontier,
  chunky four-lobe puff clouds drift beside the track on a lazy
  sine bob, re-entering ahead once they slip behind, and a **day-palm
  grove** lines the course — the same palm pool/frontier as MIAMI
  NIGHTS, re-dressed at lay time in the `SkyPalm*` palette (brown
  trunks, green fronds, banana beads, SmoothPlastic) so a theme swap
  migrates the shared grove's whole look in one recycle pass. All follow the same
  contract:
  lazy-built on first equip, client-local, non-collidable, parked below
  the void on theme swap, recycled on frontiers so they stream forever.
- **Ball**: near-black sphere + five `CylinderHandleAdornment` wireframe
  rings (3 cyan axial + 2 magenta diagonal) — a clean neon cage that rolls
  with the ball's spin. Slim magenta Trail. No PointLight — self-glow
  smears the wireframe under bloom. (`SelectionSphere` was tried first: its
  lat/long grid is too dense at 3 studs and renders as a blob.) Skins may
  carry `capsule`/`inhabitant` flags (§18 skin_capsule): `capsule` renders
  the shell transparent (`Art.CapsuleAlpha`), and `inhabitant = "monkey"`
  welds a toy monkey inside — seven Massless no-collide/no-query/no-touch
  primitive spheres from `BallDress.monkeySpec`, so it tumbles with the
  roll like an arcade capsule toy. Cosmetic only: the physics part is
  untouched, and `retint` adds/removes the rig on equip swaps.
- **Track**: purple-black deck (subtle `DeckTint` palette drift), neon edge
  rails + transverse grid strips + longitudinal center line, all tinted
  from `Palette` **per segment** — the neon flows continuously down the
  slope as a real gradient instead of stepping per chunk.
- **Gems**: four value tiers, each its own primitive silhouette + warm
  tint — diamond chips/pearl orbs (gold, 10), coins/orbs (amber, 15),
  shards/rods (orange, 25), the fat crown diamond (white-hot, 40). One part
  each, zero mesh cost; catalog in §8.4.
- **Obstacles**: near-black bodies with red `SelectionBox` edge outlines —
  Slope's black-with-red-edges read, same one-color lethal language. Red is
  never used for decoration anywhere else.
- **HUD**: four zones, nothing else — score cluster top-right, minimap +
  quest tracker right side under it, power meter bottom-left, BPM/speed
  digit bottom-right. One big pink score top-right (top-left sits under
  Roblox's native menu; the center cone stays clear for the track read at
  speed); distance/gems on a dim lavender subline, the combo pip under
  that, then the gold pass-moment flash and the `±N vs PB` pace line
  when a PB echo replays. Below the stack a narrow **look-ahead radar**
  (`Config.Radar`)
  strips the next `Range` studs down to red bars — top = far, bottom =
  at the ball, x = block offset vs the ball — re-read from the tagged
  `RoBallLethal` set every `ScanSeconds` so movers track for free;
  nearest `MaxBars` threats win the pooled frames.
  The echoes you race read on the same ruler: a cyan **PB tick** on the
  strip's left edge and a gold **rival tick** on the right pin each
  replay's distance-ahead (`dz = -pace`) — a ghost in front climbs the
  strip toward the top as it pulls away; behind-you clamps to the
  bottom edge like a minimap indicator; out-of-range pins the top.
  Under the strip the **threat name** labels the nearest bar's chunk
  type via `Features.Label` — the player learns each hazard's name on
  every encounter, not only at its debut.
  Flanking the track view a pair of pink **edge-warning chevrons**
  (`Config.EdgeWarn`) light when a short probe beside the ball finds no
  ground — over a cutout or one step from the rail; anything hit
  (deck, wall, face) counts as supported.
  A red **danger vignette** (`Config.Danger`) strokes the screen frame
  with intensity rising toward contact distance when a lethal part
  overlaps the ball's own line (`Danger.Lane`) inside `Danger.Near`
  studs — the forward brace warning the radar can't give; the chevrons
  stay lateral. Past `Danger.PingMin` a flattened sonar blip repeats on
  a cadence tightening `PingSlow→PingFast` with closeness (pitch lifted
  `PingLift` at contact) — the audible mirror of the frame closing in,
  on the `dash` mixer channel.
  Bottom-right is a single big **BPM number** — the
  heard tempo (`map.bpm × the player's live PlaybackSpeed`, which rides the
  semitone-snapped `TempoStepSt` curve), so the digit is accurate even
  mid-glide and steps in real intervals exactly when the music does. The digit's hue is still the speed meter: gradients cyan →
  violet → magenta across 0–100 s/s and snaps hot red + pulsing past it.
  It's dressed vaporwave: a chrome gradient band under the hue and twin
  cyan/pink VHS-fringe ghosts that spread and
  flare with the audio pulse — the digit thumps on the heard beat.
  The digit and its trace live in **one capsule** (the `BpmScope`
  module) — the same untilted pill footprint as the power meter
  mirrored on the opposite corner, so the two parallel pills bracket
  the lane as a matched set, with a `TEMPO` tag over the right one
  mirroring the meter's `POWER METER` tag. Inside, an **oscilloscope
  trace** takes the lead slot and draws the heard spectrum as a
  mirrored-envelope waveform: `Music.WavePoints` strips bucketed
  log-spaced off the same throttled `AudioAnalyzer` tap that feeds the
  thump (bass left, air right, cyan→pink ramp), attack-instant /
  decay-per-tick so a quiet passage flattens instead of snapping off.
  Bands are auto-gained against a decaying peak (`Music.WavePeakDecay`,
  floored at `WaveFloor`) so the trace breathes at any stem loudness,
  the HUD lifts them perceptually (`WaveGamma`), and the heard pulse
  swells the whole trace on the kick (`WaveBeatGain`/`WaveBeatFloor`)
  while the hairline and capsule rim flash with it — the module pumps
  on the music, not just the band energies.
  Bottom-left
  is a glanceable **power meter**: an untilted capsule holding one smooth
  chrome bar clipped to the eased charge — cyan→pink ramp with a
  white-hot leading edge, gloss sheen on top, dim shade under — with
  LED slot dividers laid over it so the retro texture survives while
  the fill slides continuously instead of stepping. A diamond bead
  rides the lit edge, `RechargeGate` shows as a gold notch in the
  sweep — the armed marker
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
  SIGNAL LOST). `F_DISPLAY` = Michroma — geometric retro-future caps for
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
  loop, per-bus stems, and a `SongMap.luau` beat/section chart
  that GenCore reads. Self-rendered = free stems, free beat maps, zero
  copyright surface.
- Shipped catalog: ten FlowMusic loops (`Config.Music.Tracklist`,
  per-track measured BPMs — `palm_screens` doubles as the menu bed).
  The earlier synthesized set (`vaporwave_loop`, `neon_descent`,
  `retro_wave`) is retired. `PlaybackSpeed` maps ball speed `0.5x ->
  1.35x` — a half-speed opener that rides the run's acceleration. Optional
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
  still gates what's allowed. Boost drift vs the nominal speed schedule is
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
  write thrift as the all-time board). The menu panel has TOP/DAILY
  tabs; the daily tab shows the seed + UTC reset countdown. Yesterday's
  stores are simply never read — no cleanup needed. After a daily-seeded
  death posts a session-best to the board, the server fetches the fresh
  rows and publishes `RoBallDailyRank` — the death card fills in
  `daily #n today` a beat later (0 when off the TopCount window; cleared
  on every run start so a non-daily death never shows a stale slot).
  A session-record `submitTop` publishes `RoBallTopRank` the same way —
  `all-time #n` on the card, reset with the daily line on run start.
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
  screen's `N quests done · ◊ +N banked` line. During a run a dim
  three-line **mission tracker** stacks under the minimap's threat name
  (right edge) showing the same quests live — `reach`/`score` read the
  run's own counters and `bank` adds the run's banked delta (snapshotted
  `RoBallBank` at run start) to the stored today-tally; a line goes `✓`
  gold once its number is in the bag (the flag itself still lands at
  run end), and the block hides entirely once nothing is left to chase.
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
  no scoring effect, dies with the run. Each echo also drags a short
  ribbon (`Config.Ghost.TrailLife`/`TrailGap`/`TrailFade`) between two
  y-offset attachments — the *line* each replay took reads through
  bends, not just the two balls' current distance.
- **Champion ghost**: the same credentialed upload also offers the run to
  `RoBall3D_GhostChamp_v1`, keyed `s<seed>` → a podium `{c, r}` — the
  seed's record holder plus the silver seat and their replays (v1 keys
  stored a bare champ `{n,s,u,f}`; reads migrate it to `{c = …}`).
  `crownChampion` merges inside `UpdateAsync` so simultaneous records
  can't tear (a tie keeps the earlier holder, a dethroned champion
  slides to silver, and one player never holds both seats).
  `GetGhost(seed)` returns `{s, f, c, r}` — your ghost plus both podium
  replays, each omitted when it's your own — and the client replays the
  champion as a gold echo carrying the record holder's name on a
  billboard. While it replays, a second pace line under `±N vs PB` shows
  `±N vs <name>` — the live gap to the seed's record, gold when you're
  ahead of it. Same cosmetic-only contract; `pace()` stays yours-vs-you.
  Catching a replay's interpolated position after trailing it by at
  least `Ghost.OvertakeArm` studs toasts `▸ PASSED PB` / `▸ PASSED
  <name>` once per ghost per run — a wire-to-wire lead never counts
  as a pass. The mirror fires `▸ LOST TO PB` / `▸ LOST TO <name>` when
  a replay you already passed pulls `OvertakeArm` studs back ahead —
  each direction change narrates, earned only after a PASSED, so a
  wire-to-wire trail stays quiet the same way. Every echo is named:
  the PB ball carries a `PB` billboard like the podium echoes carry
  their holders' names.
- **Crowd ghost**: on the daily seed (`seed == Daily.seed()`) the silver
  seat's replay also attaches as a labeled silver echo
  (`Ghost.CrowdColor`/`CrowdTransparency`) — airier than the rival, no
  pace line. Racing a field, not just the record; non-daily seeds skip
  it so a quiet seed doesn't stage a race that isn't there.
- **Crown toast**: when a credentialed ghost upload changes the podium
  (a before/after `loadPodium` read brackets `crownChampion`), the
  server fires `Crown` and the client toasts `♛ CROWN TAKEN from <name>`
  — or `♛ SEED CROWN CLAIMED` on an unclaimed seed. Improving your own
  crown doesn't re-announce.
- **Split-time sectors**: every `Config.Sectors.Length` studs a
  `SectorMark` ribbon paints across the deck
  (`Sectors.MarkW`/`MarkTrans`, per-rail on cutouts) — the pace pulse
  lives on the track itself; the HUD `SEC n · T.Ts` flash was cut as
  clutter.
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
                                   --   server spawn (the menu preview uses
                                   --   real parts — adornments don't render
                                   --   in a ViewportFrame)
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
                                   --   client-owned ball — Touched fast path
                                   --   + per-frame sphere-vs-strip overlap
                                   --   backstop so grazes/tunnels can't drop
                                   --   the launch (§8.6)
    OrbController.luau             -- JumpOrb taps: Space/touch within Radius
                                   --   re-kicks vY (§8.6, flag-off)
    FatalController.luau           -- client-authoritative lethal contact:
                                   --   Touched + swept spherecast ->
                                   --   ReportFatal remote (§11)
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
item is a pure visual in one of seven slots: `skin`, `world`, `trail`,
`gemFx`, `deathFx`, `sun`, `filter` — `world` swaps the entire
side-scenery theme (§12: city canyon ↔ NEON PEAKS ridge field ↔ MIAMI
NIGHTS palm grove), the first environment-tier DLC; `sun` restyles the
horizon disk the run chases (§12 `Art.SunStyles`), the second. `filter`
draws a retro screen overlay on a dedicated low-DisplayOrder ScreenGui —
lattice modes (PIXEL GLASS grid / SCANLINES·PHOSPHOR raster) plus wash
modes (GOLD HOUR·VERDANT VEIL·TOXIN·ABYSS·SNOWBLIND color grades and the
VIGNETTE dark-edge falloff) — while HUD text renders above it and stays
crisp. **Every bundle is a complete look**: exactly one item per slot,
twelve packs total — STARTER NEON (sunset set + palms), NEON PEAKS
(summit set + the flagship ridge world), SYNTHWAVE (prism + grid), MIDAS
(gold + meteor), VOID VIP (void + star well + eclipse), AURORA (borealis
+ aurora sky), POLARIS (phantom + polar sky + HALO RISE), TOXIC SLUDGE
(acid + toxic wastes), NEON REEF (lagoon + reef + NEAP TIDE), NULL (mono
set + the empty world), APE BALL (capsule set + the sky court world —
the rolling-party-ball homage: midday skybox, checkerboard floor,
cartoon clouds, day palms, a transparent capsule ball with a toy monkey
welded inside, and banana-orb pickups; all-original, no borrowed IP),
and seasonal SOLSTICE (frost set + POLAR CAP +
the shared NORTHERN LIGHTS sky). Retired pass ids stay sold-but-hidden in
`Cosmetics.LegacyBundles` — already-owned passes keep granting their
original contents forever.

**Catalog**: items live in `Cosmetics.luau` (ReplicatedStorage) — each is a
data record `{ slot, name, ...colors/params }`, so a new look is config,
not code. Items ship in **themed bundle gamepasses** (one pass = a
complete outfit, one item per slot — seven members each): passes are the
platform's permanent-unlock primitive and
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
The **COLOR LAB** extends it to player-picked hues: `Config.CustomHue`
bands sliders to `[Min, Max]` ≈ hue 20°–324° — the red seam is cut out
of the reachable space, and the server re-clamps so a hand-rolled client
can't mix a lethal look either.

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
slots picks the run's song — `RANDOM` keeps the seeded pick; a named
track sends a seed in its residue class so `SongMap.trackIdFor` lands on
it and the gen stamps that track's map (seed-box text / `daily` still
wins). The row browses `Config.Music.ActiveTracklist` — every uploaded
track, not just owned ones; songs aren't purchases, they're the level
picker.

**Garage (P2)**: arrows browse the WHOLE catalog, not just owned items —
owned items equip as they pass, unowned ones park showing their ◊price.
Name-click is the conversion funnel: a bundled item jumps to PACKS with
its bundle unfolded, scrolled into view, and the buy chip flared — the
open accordion still lists each member with its ◊price as the à-la-carte
escape hatch (unbundled singles keep the direct name-click buy). The BANK
page is the economy surface: a gold-sheened hero card carries the
balance huge behind a faceted gem icon (`today +◊N` / `day-N streak`
right-aligned for context), a `TOP-UP` caption heads three gem-pack
cards (icon + amount + price stack, SOON until product ids exist — the
vault tags `★ BEST`, most gems per R$), a paneled `TODAY'S FLOW` ledger
shows banked today / open-mission rewards left / the next daily run's
streak payout (repainted by `setQuests` + the streak attribute), then
the 2X BANK row wired like a bundle pass. The gem icon is drawn from
rotated frames (body + darker cut facet + vertex glint — `gemIcon`),
no image asset. The death screen reads `◊ +N BANKED` — the payout
visible on
every run end.

**Show surfaces**: private lanes hide other players, so the flex surfaces
are the run itself and the **garage preview window** — a `ViewportFrame`
diorama pinned to the bottom of the always-on garage rail (§6). CosmeticFx
rebuilds it on every browse change from the *browsed* item — not just the
equipped one — so cycling the catalog previews unowned merch before the
buy (try-before-you-buy). Everything sits at REAL game studs — no
shrink pass. The lane is a constant-profile straight Flat ribbon
emitted with TrackStreamer's own recipe: a pitched deck slab tinted by
`DeckTint`, neon edge rails + center line split into `GridEvery` pieces
so each samples `Palette.neonAt`/`dimAt` at its own z, transverse grid
on the same cadence — the shared deck primitives (`DeckColor`, `EdgeW`,
`EdgeH`, `GridH`, `CenterW`) live in `Config.Art` so menu and runtime
can't drift. The dressed ball (real `Ball.Diameter`, cage dims matching
the adornments it stands in for — rings are cylinder parts since
adornments don't render inside a ViewportFrame) rolls down-grade at
`Config.Speed.Start`, so the trail — BallDress's own attachment pair +
taper spec — streams exactly like a run; a ~150-stud loop ends at a
lethal-style wall (near-black `Obstacles.FaceColor` slab, `LethalColor`
neon edge frame — another stroke-swap for the SelectionBox outline): the
ball slams face-first, the browsed DEATH FX's REAL burst plays into the
WorldModel at the impact point (`DeathFx.previewBurst` — the same STYLES
the run uses, parented to the diorama instead of workspace), the cam
holds on the hit for ~0.85s, then the wrap respawns the ball with a
trail reset. The ribbon itself is a stroke-swap like the ring cage:
Trail objects can't draw inside a ViewportFrame, so thin Neon quads
bridge the ball's recent positions — a boost-trail composite: a bright
core strip that lerps white-hot at the ball and cools to the item's
color, a wider soft-glow layer under it, per-seg flicker, and ember
motes that peel off the wake, drift up, shrink and die. The ball weaves
±8 studs with a slight steer-lean so the
ribbon draws a visible S instead of a dead-straight line. The
ViewportFrame camera re-aims each frame with the live
chase-cam transform (`Camera.Offset` behind-above, `LookAhead`/
`LookDrop` aim) at the real speed-ramped FOV. The world is no sketch
either: `Backdrop.diorama(parent, theme, sun, anchor)` lays ONE static
window of the real theme into the diorama's Scene model — the same
make/lay functions, tunables, and seeded lattice `Backdrop.update` runs
live, frozen at the ball's start anchor instead of recycled behind it —
plus the real `makeSun` strip stack. SelectionBox tower outlines can't
draw in a ViewportFrame, so the diorama path traces laid tower segments
with neon edge parts — same `layTower` math, only the stroke primitive
swaps. A real `Gems.Size`/`FloatY` pickup sits on the lane ahead and
beat-pulses.
Animated flags (`fx = "rainbow" | "pulse" | "strobe" | "wave"` on skins —
strobe is a fast hue flicker, wave flows the run palette across the rings;
`"rainbow"`/`"palette"` on trails/gemfx) are evaluated in the client
render loop. The `world` slot rides the same plumbing: `RoBallEq_world`
lands on the client and `Backdrop.setTheme` re-seeds whichever scenery
system takes over — in the menu it shows up as the diorama's scene.
Every world theme anchors exactly one bundle (§18's complete-set rule):
`world_palms` → STARTER NEON, `world_grid` → SYNTHWAVE, `world_meteor` →
MIDAS, `world_void` → VOID VIP, `world_aurora` → AURORA, `world_peaks` →
NEON PEAKS (the flagship earns its own pass again — the retired
world-only `peaks` pass revives as a full 7-slot set and old buyers get
the whole outfit through the same pass key), `world_toxic` → TOXIC
SLUDGE (the `toxic` theme boils lime bubbles up out of the runoff below
deck — each sphere climbs on its own phase and pops back, a perpetual
simmer beside the lane), `world_reef` → NEON REEF, `world_empty` → NULL
(the `"empty"` theme draws no scenery at all — lane, sun, skybox; the
silence is the product), `world_sky` → APE BALL (the day-shift world —
SKY COURT re-times Lighting to midday, lays a green/cream checkerboard
below the deck, and drifts puff clouds beside the track), and
`world_polar` is shared —
POLARIS keeps it on the permanent shelf while SOLSTICE borrows it for
the winter window (`Cosmetics.bundleOf` resolves shared membership to
the non-seasonal pack, so the sky never inherits the seasonal gate).
Wave 2 also fills the acid/lagoon/ember/candy/chrome families, the
animated **CHROMA** (strobe) and **IRIS** (wave) prestige skins, and the
COLOR LAB singles — all inside color law; retired bundles' contents
folded into the new packs or back to à-la-carte, with `LegacyBundles`
preserving already-sold passes.

**COLOR LAB (custom hues)**: `skin_custom` / `trail_custom` /
`gemfx_custom` — prestige à-la-carte singles (the retired `colorlab`
pass still grants them via `LegacyBundles`) — items whose color params
are the strings `"customA"` / `"customB"` / `"customC"` instead of a fixed
Color3. They resolve through three replicated hue channels —
`RoBallHueA` (ring set A + accents), `RoBallHueB` (ring set B),
`RoBallHueC` (trail + gem pops) — read by `Cosmetics.huesOf` and resolved
in `Cosmetics.colorOf`, so `BallDress`, `GemFx`, and `DeathFx` paint them
like any other color. Owning ANY lab item (bundle or à-la-carte gem buy)
unlocks the garage's three sliders (`Cosmetics.labOwned`); a drag release
posts all three channels through the `SetHues` RemoteFunction, which
re-gates ownership and clamps `Config.CustomHue` server-side. Writes land
on `RoBallHue*` attributes → the preview diorama rebuilds, a live ball
retints mid-run, and the garage sliders re-seat. Persisted in
`profile.hues` like the mixer gains; the defaults are cyan/magenta/cyan.

The wave-2 drop widens every slot à-la-carte: five more skin families
(lagoon/acid/candy/ember/chrome), animated `strobe`/`wave` skins
(chroma, iris), matching trail/gemfx pairs (volt, peach, mint, ghost,
inferno), six death-fx styles, and three new world themes —
`world_aurora` (BOREALIS SKY), `world_reef` (NEON REEF), `world_meteor`
(METEOR SHOWER) at ◊800–900. `world_palms` (MIAMI NIGHTS) anchors the
STARTER NEON sunset set and `world_polar` (NORTHERN LIGHTS, ◊900)
anchors POLARIS (and rides SOLSTICE's winter window).

**COLOR LAB**: `skin_custom`/`trail_custom`/`gemfx_custom` take the
string params `customA`/`customB`/`customC`, resolved client-side through
the `RoBallHueA/B/C` attributes — a player-tinted set. `Config.CustomHue`
pre-sanitizes the picker's reachable band (hue 0.055–0.9) so no slider
position can mix a `LethalColor` red — the color law is enforced by
construction, not by auditing picks.

**Seasonal slot**: `Config.Monetization.Seasonal` holds one bundle id plus
a yearly UTC `[Start, End]` month/day window (wrap-around legal, e.g.
Dec 15 → Jan 8). Inside the window the pack sells like any other; outside
it the button reads `IN Nd` (days until opening) and the server refuses
both the bundle claim and à-la-carte gem buys of its member items.
Ownership already granted is permanent — scarcity gates acquisition, not
use. Currently **SOLSTICE**: the full frost set (skin/trail/gemfx +
AVALANCHE death + POLAR CAP sun + SNOWBLIND filter) plus the shared
NORTHERN LIGHTS sky. `Daily.seasonalStatus` is the shared
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
