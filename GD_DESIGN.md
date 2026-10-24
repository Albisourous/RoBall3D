# GD_DESIGN.md — Geometry Dash lessons, lifted into RoBall3D

What Geometry Dash does that we want, what we already do, what's shipped,
and what's deliberately skipped. DESIGN.md stays the source of truth for
numbers and mechanics — this file tracks the *inspiration ledger*.

## 1. What GD actually does (the audit)

- **The level is the song.** Every obstacle, portal, and deco pulse lands
  on the heard grid; structure is the music's structure (builds tighten,
  drops open, breaks dim). Nothing exists off-beat.
- **Inputs stay dead simple.** One button. All depth comes from what the
  level does to you — pads kick, orbs re-kick on a tap, portals change
  gravity/speed/mode. The level supplies verbs; the player supplies timing.
- **Every kill has a visible cause.** Spikes, saws, walls — nothing kills
  from off-screen and nothing kills silently. The crash *is* the feedback.
- **Coins are the risk read.** Optional pickups sit exactly where the safe
  line isn't — a coin under a saw is the level asking a question.
- **Portals are instant state changes.** Gravity flip, speed change, mode
  swap — one frame, no ramp. The portal frame reads as the threshold.
- **Dash orbs hold a line.** Hold inside the orb and it drags you along
  its arrow — steering becomes "trust the line while it lasts."
- **Difficulty is a ladder, not a wall.** Easy → Demon tiers; a level
  teaches its tricks gently before it combines them.
- **Deco is reactive.** Blocks glow on downbeats, saw blades are beat-cut,
  backgrounds pulse — the room wears the song even where nothing kills you.
- **Practice mode drops checkpoints.** Death resets to the last checkpoint
  instead of the start — learning a level is cheap.
- **Instant restart.** R and you're back in — no menu, no fade, no cost.

## 2. What we already have

| GD mechanic | RoBall3D equivalent |
|---|---|
| Level = song structure | `SongMap` sections drive `GenCore` — builds/drops/breaks stamp chunk energy + pacing |
| Beat-locked hazards | `Pacer`/`Rotor`/`PressRow` movers on whole-note periods |
| Instant restart | `R` reseeds and respawns mid-run, no menu stop |
| Visible-cause kills | server-sealed deaths + `lost at Nm — <feature>` verdict + danger vignette/ping |
| Coins on risky lines | gems graded `ValueSafe→ValueGapArc` by placement danger |
| Jump pads | `LaunchPad` strips — terrain trigger, no jump button |
| Gravity portals | `FlipRide` — designed, flag-off (`Features.GravityFlip`) |
| Jump orbs | `OrbHop` — designed, flag-off (`Features.JumpOrbs`) |
| Reactive deco | `BeatPulse` gems/edge pulse + `Blackout` break darkness + analyzer-driven skyline |
| Daily challenge | `Daily` seeded shared board + streak |

## 3. Shipped from this pass

| Feature | What it lifts | Where |
|---|---|---|
| `HalfPipe` | Pipe surfing — alternating steep banks inside edge walls; gems ride both faces | `Config.HalfPipe`, `ChunkDefs.HalfPipe` |
| `HoopRun` | Portal threading translated to aim-don't-dodge — standing rings, thread = bonus, miss = free | `Config.HoopRun`, `ChunkDefs.HoopRun`, `spec.hoops` |
| `MagnetLane` | Dash-orb hold-the-line as terrain — violet rail bends steering toward its line; `Magnet.Cap < MaxLateralSpeed` means it gathers, never grabs | `Config.Magnet`, `ChunkDefs.MagnetLane`, `MagnetController` |

## 4. Next candidates (tracked, not shipped)

- **Practice checkpoint** — GD's practice mode; ours is endless+seeded, so
  the shape is "rerun the seed" — the RECENT strip already does it. A real
  checkpoint would mean mid-run respawn: big machinery for an endless game.
- **Speed portal** — GD's instant fast-forward. Our drive loop pins
  `-fwdSpeed` every frame to the tier schedule; a kick gets overwritten.
  Honest version = boost already exists on the power meter.
- **Mode portals (ship/wave)** — a real second control scheme. Biggest
  lift on the list; revisit only if runs plateau.
- **Jump orbs / gravity flips** — built, flag-off. Flip when they get a
  tuning pass; the chunks already emit and `canRun` gates them.
- **Demon-tier milestone labels** — difficulty naming on seed tiers;
  cosmetics copy, not mechanics.

## 5. Deliberately skipped

- **Chime/audio pickups** — GD plays nothing on coin collect; ours was a
  pentatonic ladder over the track — removed (it fought the music).
- **Jump button** — GD's one-button scheme maps to steer+dash; pads supply
  airtime so no jump verb is needed.
- **Ship mode's gravity** — ball physics is the identity; a second gravity
  model is a different game.
