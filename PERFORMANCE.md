# PERFORMANCE.md — RoBall3D efficiency audit & cleanup checklist

Read alongside DESIGN.md. This document is the standing checklist for
performance work: each item names the file, the pattern, why it costs,
and the fix shape. Check items off in commits; keep this file current
like DESIGN.md.

Budgets (targets, not laws):
- Client Heartbeat body < ~1 ms/frame typical; RenderStepped < ~1.5 ms.
- Server Heartbeat < ~4 ms total per player set, no single-chunk spikes
  over ~10 ms.
- No allocations in per-frame loops beyond value types (Vector3/CFrame/
  UDim2/Color3 are value types — tables and strings are not).
- Replicated property writes (server→client): movers ≤ 30 Hz, score
  attributes ≤ per-meter cadence.

---

## 1. Per-frame loops — client

- [ ] **Cache `tick()`/`os.clock()` once per frame.** `Main.client.luau`
  heartbeat calls `tick()` at lines ~948, ~954, ~1173 (and `tryDash`),
  and `Ui:setSpeedo` calls it ~5 more times. Hoist `local now = tick()`
  to the top of each loop body and pass it down.
- [ ] **`Tiers.forDistance` clones a table every frame.**
  `Main.client.luau:1014` calls it only for `.index`. `Tiers.luau:36-58`
  does `table.clone` + width-floor math per call. Add
  `Tiers.indexAt(dist)` (scan only, no clone) or cache the tier index in
  the run state and recompute only when `dist` crosses a tier boundary.
- [ ] **Radar rebuilds the whole lethal tag set at ~16 Hz.**
  `Main.client.luau:1079` calls `CollectionService:GetTagged("RoBallLethal")`
  every `Config.Radar.ScanSeconds` (0.06 s): allocates the full
  workspace-wide tagged array (all players' lanes) every scan, then
  iterates it. `FatalController.luau:27-66` already maintains an
  incremental `lethal`/`lethalList` set via `GetInstanceAddedSignal` +
  `listDirty` — lift that pattern into a shared tagged-set cache and let
  the radar filter it by the run's lane X (skips other players' lanes
  without paying the scan).
- [ ] **`FilterDescendantsInstances` allocates a table per frame.**
  `Main.client.luau:1128` builds `{ edgeLane }` every heartbeat. Assign
  only when `edgeLane` actually changes (bindBall / run start).
- [ ] **HUD cache allocates a string per frame.**
  `Main.client.luau:1210` `string.format("%d|%d|%d|%d", ...)` — compare
  the four numeric fields against cached numbers instead.
- [ ] **`Ui:setSpeedo` writes ~10 UI properties every heartbeat.**
  `Ui.luau:1828-1903`: 3× `.Text`, 3× `.TextSize` (pulse-driven, forces
  text relayout every frame), 2× `.Position`, 2× `.TextTransparency`,
  `.TextColor3`, stroke `.Color`. Gate writes on changed values;
  quantize `TextSize`/`spread` to whole pixels so sub-pixel pulse jitter
  stops dirtying layout.
- [ ] **Trivial per-frame writes:** `camera.CameraType = Scriptable`
  every RenderStepped (`Main.client.luau:1218`) — set once.
  `Ui:setEdgeWarn`/`setDanger` run every frame — early-out when the
  visibility state is unchanged.
- [ ] **`Music.sample()` calls `analyzer:GetSpectrum()` every render
  frame** (`MusicController.luau:638-656`) — allocates a spectrum table
  per frame plus a `pcall`. Sample on a ~30 Hz cadence clock and return
  the last value between ticks; the pulse envelope already smooths.
- [ ] **`BeatPulse` scans every tracked gem per render frame**
  (`BeatPulse.client.luau:54-61`): distance² check over the full
  `RoBallGem` set (all lanes, ~hundreds of parts). Keep a "near" subset
  refreshed on a cadence clock (reuse the radar's lane-scoped set), and
  only iterate that per frame.
- [ ] **`CosmeticFx` does `workspace:FindFirstChild(ballName)` per
  frame** (`CosmeticFx.luau:151`) while an animated skin is equipped —
  accept the already-bound `ball` from Main via a getter like the other
  controllers.
- [ ] **Backdrop is in good shape** (pooled parts, park-on-swap, lazy
  theme builds, client-local). Remaining nits: the sun's 16
  `.Size` writes/frame could quantize the pulse; `stepAurora` writes
  Position+Color on ~22 parts/frame — acceptable, leave unless the
  MicroProfiler says otherwise.

## 2. Per-frame loops — server

- [x] **`writeScore` runs every frame while the ball moves.** (fixed: gated on `run.lastFloorDist`)
  `Main.server.luau:816-820` → `writeScore` does 3 `SetAttribute` calls
  + a `leaderstats` write each call. The values only change once per
  whole meter — gate on `math.floor(d) ~= run.lastFloorDist` (and on
  gem/near-miss changes, which already call writeScore directly).
- [x] **Mover heartbeat replicates every frame.** (fixed: `Config.Movers.StepHz = 25` accumulated-dt + `CullBehind = 60`)
  `TrackStreamer.luau:926-941` writes `Position`/`CFrame` on every mover
  every Heartbeat — each write replicates to every client. Accumulate dt
  and step movers at 20–30 Hz (beat-locked motion still reads clean),
  and/or skip movers beyond a cull distance behind the ball. This is
  the largest steady-state replication cost in the game.
- [x] **`yAt` linear-scans `self.chunks` per frame per player** (fixed: monotonic z cursor)
  (`TrackStreamer.luau:945-957`). N is small (~15 chunks live), but z is
  monotonic — keep a cursor and only walk forward/back one chunk.
- [x] **`ensureAhead`/`cleanup` run every frame.** (fixed: `Config.Generation.ChunkBuildsPerFrame = 1` + spread run-start pre-build) The calls are cheap;
  the cost is `buildChunk`'s synchronous burst (~30–90 `Instance.new`,
  `spec.section` table allocs per call site, one `Touched` connection
  per gem). `streamer:ensureAhead(0)` at run start builds the whole
  400-stud window in one call — a real startup spike if several players
  start together. Add a build budget (≤1 chunk per heartbeat; the window
  catches up over the first seconds) while keeping the run-start
  pre-build either spread or deferred until first control unlock.

## 3. Instance churn / GC pressure

- [ ] **`Music.playOneShot` creates AudioPlayer + Wire per gem pickup**
  (`MusicController.luau:562-583`) plus a `task.delay(4)` cleanup. Pool
  ~6 reusable chime voices on `sfxFader` (recycle oldest when full).
- [ ] **`SfxController` spawns a `Sound` + `PitchShiftSoundEffect` per
  chime/dash/ping** and connects `Ended` per instance. Acceptable at
  current rates; if pooling chime voices, route the dash/ping voices
  through the same pool.
- [ ] **`GhostController.framesCsv` allocates a temp 4-element table per
  row** (`GhostController.luau:99`) — build each row with
  `string.format` into the output table directly.
- [ ] **`spec.section(t)` allocates a fresh Section table per call.**
  `TrackStreamer.buildChunk` already caches the `samples` array for
  slicing but re-calls `section()` ~3× per emitDeck, ~3× per grid strip,
  ~3× per sector mark (~50–100 allocs per chunk). Index the sampled
  array for emitDeck reuse or memoize `section()` per chunk build.
## 4. What's already right — do not regress

- `GenCore` is pure & seeded; never add `Instance.new`, `math.random`,
  or wall-clock reads inside it (leaderboard fairness).
- Backdrop/cosmetic FX are client-local, pooled, anchored, and
  `CanCollide/CanQuery/CanTouch/CastShadow = false` — keep that contract
  on every new decorative part.
- `FatalController`'s incremental tag set + dirty-list rebuild is the
  reference pattern for tag tracking — reuse it rather than
  `GetTagged` scans.
- Hazard/debut scans use monotonic cursors (`nmCursor`, `dbCursor`) —
  keep the z-descending invariants they rely on.
- Radar bars, power segments, board rows, landing ring, and the graze
  emitter are pooled — pool, don't create-per-event.
- All `InvokeServer` calls are `pcall`ed on the client; keep it.
- DataStore path already has retry/backoff, cooldown-cached leaderboards,
  probe deduplication (`probeInFlight`), and write-thrift (records only).
- Weak-keyed `fired` tables in Pad/Orb controllers — dead parts can't be
  pinned; preserve `__mode = "k"`.
- Server-side `Touched` is intentionally NOT used for lethal contact
  (client adjudication, §11) — don't "optimize" it back.
- Generation flags `GravityFlip`/`JumpOrbs` are off; their per-frame
  sweeps are already flag-gated — keep new feature work behind flags.

## 5. Diagnostics workflow (do before/after each cleanup commit)

1. Studio play mode → F9 DevConsole → **Script Performance**: sort by
   ms; the top entries should be `Main.client` heartbeat, `TrackStreamer`
   movers, `Main.server` heartbeat.
2. **MicroProfiler** (`Ctrl+Alt+F6` / pause `Ctrl+P` over a frame):
   - Look for `Heartbeat`/`RenderStepped` bars > budget, and spikes on
     chunk-build frames (`Instance.new` clusters under
     `TrackStreamer:buildChunk`).
   - `LuaHeap` in DevConsole memory tab: watch it over a 60 s run —
     steady sawtooth growth = per-frame table/string allocs.
   - `GraphicsParts`/`PhysicsParts` memory tags should plateau once the
     ahead-window is full and stay flat as chunks recycle.
   - `Network Receive`/`Replication`: mover throttling should visibly
     drop the replication send rate.
3. In-game probes (execute_luau during play): `#CollectionService:GetTagged("RoBallLethal")`,
   `#workspace.RoBallLanes.Lane0:GetDescendants()`, part counts per
   theme, `player:GetAttribute` churn.

## 6. Priority matrix

| Fix | Impact | Effort |
|---|---|---|
| Movers → 20–30 Hz + distance cull | High (replication) | Low |
| writeScore → per-meter gating | High (attrib replication) | Low |
| Radar → incremental lane-scoped tag set | High (allocs + scan) | Med |
| `Tiers.indexAt` (kill per-frame clone) | Med | Low |
| `Music.sample` → 30 Hz cadence | Med | Low |
| `setSpeedo` write gating + px quantize | Med (UI relayout) | Low |
| BeatPulse → near-gem subset | Med | Med |
| `playOneShot` voice pool | Med | Med |
| `ensureAhead` build budget (run-start spike) | Med (multiplayer) | Med |
| `FilterDescendantsInstances` / `tick()` / hudCache / CameraType / FindFirstChild | Low | Trivial |
| `section()` memoization, `framesCsv`, `yAt` cursor, gem Touched consolidation | Low | Med |
