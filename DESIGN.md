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
  already matches; our optional W/S throttle is a deliberate divergence for
  skill expression at a score-rate cost.
- **Restart must feel free.** Crash → new run in ~1.5s is the addiction loop.
  The pre-menu auto-restart already implements this.
- **The look is neon wireframe on pure black — vaporwave-skinned.** Dark ball
  + cyan/magenta wireframe rings; purple-black deck with neon transverse +
  longitudinal grid lines; lethal blocks are black bodies with red edge
  outlines; the horizon is a canyon of palette-outlined dark towers under a
  giant striped synthwave sun; one big pink score centered at the top.

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
- **Throttle** (optional, `Speed.ThrottleEnabled`): `W` = +8% speed, `S` = -15%.
  Lets skilled players brake for tight sections at a small score-rate cost.
- **Restart**: `R` in any mode = instant re-roll. Mid-run it tears the run
  down server-side without firing `RunEnded` and without saving the score —
  restarting to dodge a death never banks it. Blank seed → fresh random.
- **No jump** in MVP.
- Keyboard only in MVP; touch later.

Ball: 3-stud `Ball`-shape Part, unanchored, `CustomPhysicalProperties`
(density 0.7, friction 0.6, elasticity 0). Server drives
`AssemblyLinearVelocity` each `Heartbeat`: `Vector3(lateral, naturalY, forward)`.
Y velocity is untouched — gravity handles falls, slopes, ramp arcs.

## 5. Camera

Chase cam: offset `(0, 12, 12)` studs behind/above the ball. The aim point is
not flat-ahead — it drops to the deck plane `LookAhead = 16` studs out
(`target.y -= Grade*16 + LookDrop`), so the camera pitches into the slope
(~28°) the way Slope does: ball low in frame, long readable runway ahead.
FOV eases `70 -> 88` with speed. Up to `LeanMax = 3°` of roll into the steer
direction for momentum readability. No vertical bob (keeps precision readable).

## 6. Run structure & menu

- **Menu** (built in code, `StarterGui` from Luau — everything stays in git):
  - Title `ROBALL3D`, vaporwave-styled
  - **PLAY** button — starts a run on a random seed
  - Seed `TextBox` — paste/type a seed for an identical map (for challenges)
  - Leaderboard panel — global top 20 (`name / score / seed`)
  - Personal best label
- **Run start**: 0.8s "rolling…" settle, then control handed over.
- **Death**: pitch drop on music, camera pulls back, death screen shows
  `SCORE / DISTANCE / BEST / SEED`, `[R]` or button = instant restart (new
  random seed unless one was entered — same seed if entered manually).

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

The first `IntroLength = 150` studs are hand-authored, not RNG:

`Flat(30, wide) -> Flat(30, gems center) -> Slalom(40, gentle) -> Narrow(50, 24->16)`

Players learn: it rolls on its own, steering drifts, gems exist, track can
narrow. Then the seeded generator takes over.

### 8.3 Chunk types (MVP)

| Chunk | Shape | Role | Tier |
|---|---|---|---|
| `Flat` | Full-width ribbon | Breather, gem lines | 1+ |
| `Slalom` | Ribbon, centerline sways via sine | Steering warmup | 1+ |
| `Narrow` | Width lerps down over the chunk | Precision | 2+ |
| `Tilt` | Ribbon rolls around its long axis ±(8–20°) | Momentum management | 3+ |
| `Pinch` | Width collapses to 2–3 studs mid-chunk, reopens | Burst precision | 3+ |
| `SplitGap` | Center channel removed → two side ribbons | Route choice | 4+ |
| `Bowl` | Banked walls rise on both edges | Rest + dense gem canyon | 4+ |
| `RampGap` | Launch ramp, full-width void, landing strip | Speed check / spectacle | 5+ |
| `BlockGate` | Red blocks across the deck, one gap ≥ CorridorMin | Thread-the-gap | 2+ |
| `BlockField` | Scattered red blocks, density scales with tier | Weaving pressure | 3+ |
| `WallSlot` | Red wall spanning the deck, single opening | Commit-to-a-lane | 4+ |

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

## 9. Difficulty & speed

Tier table is in `Config.Tiers`. Crossing a tier threshold:
- target speed steps up (40 → 106 by 2000m, cap 110), eased at `6 studs/s²`
- new chunk types join the RNG pool
- allowed width range tightens (24 → 4 min)

Hazards: **falling off the deck** and **touching `LethalColor` geometry** —
both instant death, per the Slope model (§2 REA). Moving obstacles, tunnels
and sweepers remain post-MVP; they slot in as new chunk types without
changing the generator contract.

## 10. Scoring

`score = floor(distance_m) + gem_points`. Distance is authoritative server-side
(ball's traveled `-Z`). Gem values per 8.4. Death seals the score.

## 11. Death

Ball leaves track → Y drops below kill plane (`trackY - 15`) → run over
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
than leaving a ghost run. Effects: music pitch slides to 0.6, camera
pulls back, death screen. No lives, no shields — they were explicitly
deferred.

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
- **HUD**: one big pink score centered at the top; distance/speed/seed on a
  dim lavender subline.
- **Post FX**: restrained `BloomEffect` (Intensity 0.55, Size 16, Threshold
  1.3 — only true Neon emissive pixels bloom; earlier 1.15/30/0.8 smeared
  the whole frame into blur), subtle `ColorCorrection`, `Atmosphere` density
  0.25 for depth haze.

## 13. Audio

Full spec: `AUDIO.md`. Binding decisions:

- Music is a **generation input**, not background. The renderer
  (`roball3d-audio/generate_audio.py`) owns the soundtrack: it emits the
  loop, per-bus stems, stingers, and a `SongMap.luau` beat/section chart
  that GenCore reads. Self-rendered = free stems, free beat maps, zero
  copyright surface.
- Shipped loop: `vaporwave_loop` (16 bars ≈ 43.6s, **88 BPM**, A minor —
  `Music.AssetId`). `PlaybackSpeed` maps ball speed `0.9x -> 1.35x`, so
  the heard tempo runs ~79 → ~119 BPM as the run accelerates. Optional
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
  phrase downbeats. Throttle drift vs the nominal speed schedule is
  bounded and accepted.
- Gems stay on the heard beat grid (§8.4); `Music.BaseBpm` must equal
  `SongMap.bpm` or everything drifts. The pickup chime keeps the
  pentatonic ladder (`SfxController` + `GemSfx`, `gem_pickup` asset).
- Once a track canon exists, the seed picks the track: same seed → same
  track + map + musical pacing — leaderboard rows become replayable
  "levels", GD-style.

## 14. Persistence & leaderboard

- `RoBall3D_Best_v1` (DataStore): personal best `{score, dist, seed}`.
- `RoBall3D_TopRuns_v1` (OrderedDataStore): global top scores, shown in menu.
- Server-side validation lite: reject submitted scores above
  `maxSpeed * elapsed * 1.1` + gem cap sanity.
- Studio playtests need "Enable Studio API Access" ON for DataStore writes —
  noted for setup.

## 15. Architecture

```
src/
  ReplicatedStorage/RoBall/        -- shared, pure modules
    Config.luau                    -- all tunables (exists)
    Palette.luau                   -- distance -> vaporwave gradient
    Seeds.luau                     -- seed parse/hash
    ChunkDefs.luau                 -- chunk type table: weights, width rules,
                                   --   entry/exit constraints, builders
    GenCore.luau                   -- pure generator: (rng, state) -> chunk spec
    SongMap.luau                   -- generated beat/section chart (renderer
                                   --   output, required by GenCore + client)
  ServerScriptService/RoBallServer/
    Main.server.luau               -- boot/wiring (exists)
    RunManager.luau                -- per-player run lifecycle, lanes, state
    TrackStreamer.luau             -- spec -> Instances, cleanup behind ball
    BallDriver.luau                -- heartbeat velocity control + kill plane
    ScoreService.luau              -- distance + gems, death, validation
    SaveService.luau               -- DataStore best + OrderedDataStore top
    Remotes.luau                   -- RemoteEvent/RemoteFunction registry
  StarterPlayer/StarterPlayerScripts/RoBallClient/
    Main.client.luau               -- boot, state machine, drive, chase cam
    Ui.luau                        -- menu + HUD + death screen, all in code
    Backdrop.luau                  -- synthwave sun + neon city canyon (client-local)
    MusicController.luau           -- stem graph, tempo ramp, beat clock (AUDIO.md)
    SfxController.luau             -- gem pickup chime, pentatonic combo runs
    GemFx.luau                     -- pickup juice: pop diamond + sparkles + ring
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

Jump/dash, moving obstacles (sweepers/moving walls), tunnels, power-ups
(shield/magnet/slow-mo), mobile/touch controls, alternate biomes, ball skin
shop, parties/social. All have designed-for extension points (chunk features,
`datamodel` hooks) — nothing blocks them. (Static lethal blocks landed in the
Slope map pass; motion variants ride the same `ChunkSpec.obstacles` path.)
