# TRACKER — autonomous improvement log

Running log of every change from the continuous-improvement pass. One row
per commit so any entry can be reviewed or reverted in isolation. Verify
gate for every row: `stylua --check src/ && selene src/ && rojo build -o
build/RoBall3D.rbxl`, plus a Studio playtest when the change is behavioral.

| # | Change | Type | Files | Commit | Verification | Notes |
|---|--------|------|-------|--------|--------------|-------|
| 1 | Audit: dead config (UiTick/MenuSpec), connect-stacking, PlayerRemoving cleanup, bindBall hot path | audit | — | — | grep sweep | All clean — parallel session swept Config; 24 client connects all one-time; all per-player tables cleared on leave |
| 2 | RequestStart throttle — PLAY/R spam rebuilt the whole streamer per click | robustness | Config.luau, Main.server.luau | `d26d790` | gates clean | `Config.Generation.StartCooldown = 0.35`; cleared in PlayerRemoving |
| 3 | GradeFloor — linear descent crossed FallenPartsDestroyHeight at ~313km, engine-destroying deck+ball mid-run (caught live: death at 312,804m "the track") | bugfix | Config.luau, ChunkDefs.luau, GenCore.luau, GenVerify.luau, Backdrop.luau, DESIGN.md | pending | gates + inline sim (finalY=minY=-46000, 4000-stud margin) | Shared `gradeDrop(y0,u)`: full grade → level past -46000; OrbHop landing re-solves flat when arc crosses the floor; backdrop deck estimates clamped |
