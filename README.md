# RoBall3D

An infinite Roblox ball roller — roll to infinity, chase the high score.

Slope-styled endless runner inspired by Slope, Super Monkey Ball, and
Geometry Dash. A ball rolls forward on its own down a procedurally generated
track floating in a black void; you steer with real momentum physics, the
world narrows and speeds up at distance milestones, and one fall ends the run.

- **Seeded generation** — every map is a function of its seed; enter a seed to
  run the exact same map as someone else, or roll random
- **Pure physics steering** — Monkey Ball momentum, no lane snapping
- **Instant restart** — `R` re-rolls the run at any time; death screen or
  mid-flight, it just resets
- **Rhythm gems** — gold diamond pickups land on the music's beat grid;
  rapid pickups climb a pentatonic chime ladder
- **Vaporwave wireframe** — Slope's downhill read re-skinned: neon-cage ball,
  flowing magenta/violet/cyan gradient deck, red-edged lethal obstacles, a
  neon city canyon and a striped synthwave sun at the horizon
- **Music that accelerates** — the synthwave track's playback speed follows
  your ball speed
- **Global leaderboard** — personal best + top 20 runs, each tagged with its
  seed so great runs are replayable

Controls: `A`/`D` or `←`/`→` steer (momentum, no brake), `W`/`S` throttle,
`R` restart.

## Status

**Playable MVP** — menu → seeded run → HUD → death → instant retry, live in
Studio playtests. Implemented: momentum steering + chase cam, seeded
procedural track (intro + 11 chunk types incl. Slope-style lethal red
obstacle chunks), tiered speed/difficulty ramp, beat-synced rhythmic gem
clusters on risky lines (corner-cube diamonds), pentatonic pickup chime,
server-authoritative scoring, personal best + global leaderboard (with
in-Studio fallback), continuous vaporwave palette gradient, neon city-canyon
backdrop with a striped sun, wireframe-cage ball + trail, restrained
bloom/atmosphere grade, `R` restart in any mode, stall watchdog +
deep-run kill-floor fix.

Not yet: moving obstacles, ball skins.

The full spec — controls, physics numbers, generator rules, difficulty
tiers, scoring, UI, architecture — lives in [DESIGN.md](./DESIGN.md).

## Dev setup

```bash
brew install rojo selene stylua   # toolchain
rojo serve                        # then connect with the Rojo Studio plugin
# or: rojo build -o RoBall3D.rbxl
```

See [AGENTS.md](./AGENTS.md) for the agent-assisted workflow (MCP playtests,
verification loop, conventions).
