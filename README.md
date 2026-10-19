# RoBall3D

An infinite Roblox ball roller — roll to infinity, chase the high score.

Neo-vaporwave endless runner inspired by Ball Surfer 3D/Slope, Super Monkey
Ball, and Geometry Dash. A ball rolls forward on its own down a procedurally
generated track floating in space; you steer with real momentum physics, the
world narrows and speeds up at distance milestones, and one fall ends the run.

- **Seeded generation** — every map is a function of its seed; enter a seed to
  run the exact same map as someone else, or roll random
- **Pure physics steering** — Monkey Ball momentum, no lane snapping
- **Shifting vaporwave palette** — the world's neon hue slowly cycles as you
  travel, under a giant retro sun and wireframe mountains
- **Music that accelerates** — the synthwave track's playback speed follows
  your ball speed
- **Global leaderboard** — personal best + top 20 runs, each tagged with its
  seed so great runs are replayable

## Status

Pre-build. The full spec — controls, physics numbers, generator rules,
difficulty tiers, scoring, UI, architecture — lives in
[DESIGN.md](./DESIGN.md). Build phases P0–P7 are defined there.

## Dev setup

```bash
brew install rojo selene stylua   # toolchain
rojo serve                        # then connect with the Rojo Studio plugin
# or: rojo build -o RoBall3D.rbxl
```

See [AGENTS.md](./AGENTS.md) for the agent-assisted workflow (MCP playtests,
verification loop, conventions).
