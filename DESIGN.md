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
3. **Vaporwave in motion** — shifting gradient palette, retro sun, wireframe horizon.
4. **Readable chaos** — the track is random but *fair*; every death has a visible cause.

## 2. Reference analysis (what we stole and why)

| Game | Mechanic | What we take | What we don't |
|---|---|---|---|
| Ball Surfer 3D / Slope | Ball auto-rolls, speed ramps, steer-only, instant death, distance score, neon grid | Auto-forward + lateral steering, speed = difficulty, instant death, distance score | Yellow/black palette, deadly red blocks (post-MVP), power-ups |
| Super Monkey Ball | Momentum/tilt physics, narrow beams, bananas on risky lines | Physics-driven steering feel, thin/tilted paths, gems on risky lines | Tilt-the-world control, lives, stage structure |
| Geometry Dash | Music-synced intensity, milestone progression | Music tied to speed; tier-based progression feel | Jump/flight mechanics (post-MVP), fixed levels |

**Design consequences**

- Ball is **never directly positioned** — velocity is authoritative; falls/ramp
  launches emerge from physics. This is what makes it feel like Monkey Ball.
- Difficulty is a **distance function** (Slope-style), layered into **tiers**
  (GD-style progression beats) so runs feel like they have chapters.
- With no jump in MVP, gaps are handled two ways only: *route around* (partial
  gaps) or *ramp launch* (speed-gated ballistic arcs). Jump stays in the backlog.

## 3. Core loop

```
Menu (PLAY + optional seed) -> Run starts (scripted intro)
  -> roll, steer, collect gems, survive
  -> tiers escalate speed/track danger
  -> fall = instant death
  -> death screen (score, best, seed) -> one-key instant restart
```

Target session feel: first run ~30–60s, good runs 2–5min, deaths always
explainable.

## 4. Controls & ball physics

- **Steering**: `A`/`D` or `Left`/`Right` apply lateral acceleration
  (momentum — the ball keeps drifting when released, damped slightly when idle).
- **Throttle** (optional, `Speed.ThrottleEnabled`): `W` = +8% speed, `S` = -15%.
  Lets skilled players brake for tight sections at a small score-rate cost.
- **No jump** in MVP.
- Keyboard only in MVP; touch later.

Ball: 3-stud `Ball`-shape Part, unanchored, `CustomPhysicalProperties`
(density 0.7, friction 0.6, elasticity 0). Server drives
`AssemblyLinearVelocity` each `Heartbeat`: `Vector3(lateral, naturalY, forward)`.
Y velocity is untouched — gravity handles falls, slopes, ramp arcs.

## 5. Camera

Chase cam: offset `(0, 8, 14)` studs behind/above the ball, aimed `10` studs
ahead. FOV eases `70 -> 88` with speed. Slight lateral lean toward steering
input for readability. No vertical bob (keeps precision readable).

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
`Generation.Grade` studs per stud traveled (0.1 ≈ 5.7°), so the track visibly
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
30–90 studs long. The generator keeps `AheadDistance = 400` studs of track
alive ahead of the ball and destroys anything `BehindDistance = 250` studs
behind it. Each player's run lives in a private lane offset `600` studs apart
in `X` (invisible to others under fog).

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

`RampGap` rule: for gap length `L` and landing drop `d`, need entry speed
`v >= L / sqrt(2d/g)` (g = 196.2 studs/s²). Generator picks `L ≈ v * 0.45`,
`d = 4`, only at tiers where `speed >= 64`.

### 8.4 Gem placement

Gems cluster on **risky lines** (this was the explicit choice): edge rails,
narrow beams, arcs over `RampGap` voids. Value scales with risk class:
safe `10` / edge `15` / beam `25` / gap-arc `40`. 0–3 clusters per chunk,
3 gems per cluster, 3 studs apart. Gems are `Part` + `TouchInterest`-style
server touched handler → `Score += value`, pickup FX.

### 8.5 Palette gradient

The world samples a single hue from `Palette.HueStops`
(magenta → purple → blue → cyan), advanced by distance so the whole scene
slowly laps the vaporwave wheel (`CycleDistance = 400`m/lap). One
`Palette.CurrentColor(hue)` function feeds track edging, gem glow, sun stripes,
mountain wireframe — "generated by code, easily adjustable" per spec.

## 9. Difficulty & speed

Tier table is in `Config.Tiers`. Crossing a tier threshold:
- target speed steps up (40 → 106 by 2000m, cap 110), eased at `6 studs/s²`
- new chunk types join the RNG pool
- allowed width range tightens (24 → 4 min)

No deadly obstacles in MVP — **falling is the only killer**. The tier/chunk
system is designed so hazard types (deadly blocks, sweepers, moving walls) can
be added later as new chunk features without changing the generator contract.

## 10. Scoring

`score = floor(distance_m) + gem_points`. Distance is authoritative server-side
(ball's traveled `-Z`). Gem values per 8.4. Death seals the score.

## 11. Death

Ball leaves track → Y drops below kill plane (`trackY - 15`) → run over
instantly. Effects: music pitch slides to 0.6, camera pulls back, death screen.
No lives, no shields — they were explicitly deferred.

## 12. Presentation

- **Skybox**: near-black space + star points.
- **Backdrop**: giant striped retro sun sitting on the horizon ahead;
  procedural wireframe mountain silhouettes flanking the track (generated
  from thin `Part`s/`Beam`s, tinted by palette).
- **Ball**: dark sphere + neon wireframe grid texture (generated decal,
  uploaded via `upload_image`/`store_image` MCP tools) + PointLight + Trail.
  Option A from the design Q&A; revisit after seeing it live.
- **Track**: dark body, neon edge rails/stripes tinted from palette.
- **Post FX**: `BloomEffect`, subtle `ColorCorrection` saturation, `Atmosphere`
  density for depth haze.

## 13. Audio

One looped synthwave track (`Music.AssetId` TBD — needs a marketplace/uploaded
asset). `Sound.PlaybackSpeed` maps ball speed `0.9x -> 1.35x` so the music
literally accelerates with the run. Death slides pitch to floor, restart
restores. SFX backlog: gem pickup chirp, tier-up sting, wind noise w/ speed.

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
  ServerScriptService/RoBallServer/
    Main.server.luau               -- boot/wiring (exists)
    RunManager.luau                -- per-player run lifecycle, lanes, state
    TrackStreamer.luau             -- spec -> Instances, cleanup behind ball
    BallDriver.luau                -- heartbeat velocity control + kill plane
    ScoreService.luau              -- distance + gems, death, validation
    SaveService.luau               -- DataStore best + OrderedDataStore top
    Remotes.luau                   -- RemoteEvent/RemoteFunction registry
  StarterPlayer/StarterPlayerScripts/RoBallClient/
    Main.client.luau               -- boot (exists)
    InputController.luau           -- A/D/W/S -> lateral/throttle intent
    CameraController.luau          -- chase cam + FOV speed ramp
    MenuController.luau            -- title/seed/leaderboard/death screens
    HudController.luau             -- distance, score, tier flash
    MusicController.luau           -- tempo ramp + death slide
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

Jump/dash, deadly obstacles (red blocks, sweepers, moving walls), power-ups
(shield/magnet/slow-mo), mobile/touch controls, alternate biomes, ball skin
shop, parties/social. All have designed-for extension points (chunk features,
`datamodel` hooks) — nothing blocks them.
