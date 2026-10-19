# RoBall3D

An infinite Roblox ball roller — roll to infinity, chase the high score.

Slope-styled endless runner inspired by Slope, Super Monkey Ball, and
Geometry Dash. A ball rolls forward on its own down a procedurally generated
track floating in a black void; you steer with real momentum physics, the
world narrows and speeds up at distance milestones, and one fall ends the run.

- **Seeded generation** — every map is a function of its seed; enter a seed to
  run the exact same map as someone else, or roll random
- **Pure physics steering** — Monkey Ball momentum, no lane snapping
- **Green wireframe on black** — Slope's signature look: wireframe ball, grid
  deck, red-edged obstacles, a wireframe city canyon drifting by
- **Music that accelerates** — the synthwave track's playback speed follows
  your ball speed
- **Global leaderboard** — personal best + top 20 runs, each tagged with its
  seed so great runs are replayable

## Status

**Playable MVP** — menu → seeded run → HUD → death → instant retry, live in
Studio playtests. Implemented: momentum steering + chase cam, seeded
procedural track (intro + 11 chunk types incl. Slope-style lethal red
obstacle chunks), tiered speed/difficulty ramp, risky-line gems,
server-authoritative scoring, personal best + global leaderboard (with
in-Studio fallback), green-family palette gradient, wireframe city-canyon
backdrop, wireframe ball + light/trail, bloom/atmosphere grade.

Not yet: a real music asset (`Config.Music.AssetId = 0` — the tempo-ramp
controller is wired and waits for it), moving obstacles, ball skins.

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
