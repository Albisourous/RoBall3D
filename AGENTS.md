# AGENTS.md — working on RoBall3D

## What this is

Endless ball roller for Roblox. **Read `DESIGN.md` before writing any code** —
it is the single source of truth for mechanics, numbers, and structure. All
tunables live in `src/ReplicatedStorage/RoBall/Config.luau`; change them there,
never inline magic numbers in gameplay code.

## Toolchain

- **Rojo 7.x** — file-sync: `src/` maps into the DataModel via
  `default.project.json`. `rojo serve` + Studio plugin, or
  `rojo build -o build/RoBall3D.rbxl`.
- **Luau** — `--!strict` at the top of every module. Style: stylua
  (`stylua.toml`), lint: selene (`selene.toml`, roblox std).
- **Studio MCP** — Devin is connected to the built-in Studio MCP server
  (`Roblox_Studio`, stdio at
  `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`). Studio must have
  Assistant → Manage MCP Servers → "Enable Studio as MCP server" ON.

## Workflow rules

1. **Design first.** If a change contradicts DESIGN.md, update DESIGN.md in the
   same commit — never let code and spec drift.
2. **Logic via MCP, eyes via screenshots.** Agents write scripts/properties
   through `execute_luau`/`multi_edit`. Use `screen_capture` (with
   `capture_id`, `camera_position`, `look_at_position`) to verify anything
   visual — do not blind-place decorative geometry.
3. **Playtest loop**: `start_stop_play` → `get_console_output` → assert via
   `execute_luau` (Server datamodel during play) → `start_stop_play` to stop.
   "Edit" datamodel calls are rejected while playing.
4. **`studio_id` rotates** on every play/stop transition — re-run
   `list_roblox_studios` if a call says the instance isn't connected.
5. **`workspace.StreamingEnabled` is OFF** (set in Edit mode). With
   `CharacterAutoLoads = false` there is no character, so streaming never
   delivers parts to the client — and RemoteEvent args that reference
   unreplicated instances arrive as nil. Client code finds its ball by name in
   Workspace (`<player>_Ball`) instead of trusting remote args.
6. **Generation must stay pure & seeded.** `GenCore` takes `Random` and emits
   chunk specs — no `math.random`, no Instance creation inside it. Determinism
   is a leaderboard feature.
7. Keep chunk builders constraint-honest: every chunk declares its entry
   width/speed requirements and its exit state (DESIGN.md §8.1).
8. **Never set `workspace.FallenPartsDestroyHeight` from a game script** —
   it requires plugin capability and crashes the script at startup (remotes
   never replicate → client hangs). The canonical value is
   `Config.Generation.FallenDestroyY` (-50000), applied declaratively via
   `default.project.json`. Context: the default -500 silently destroys the
   ball ~3.4km into a run.

## Verify before done

```bash
stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl
```

Then an MCP playtest: start play, read console output for errors, capture a
screenshot of the result.

## Testing a specific feature (debug-seed)

To test one chunk type in isolation, type its name in the seed box and
press PLAY — `pressrow`, `PRESS ROW`, `TERRACES`, `swell`, `fulltilt`,
`left tilt`, any builder name or its HUD label, case/space-insensitive.
`ChunkDefs.matchFeature` resolves the text; `GenCore.onlyType` then emits
a `Config.Debug.FeatureRunway`-stud flat runway followed by only that
chunk. The keyword still hashes to a seed, so the same word replays the
exact same layout — reproducible repro cases. Forcing bypasses `canRun`
on purpose (flag-off features like `OrbHop`/`FlipRide` spawn too).

From the MCP client datamodel you can also fire it directly:
`remotes.RequestStart:FireServer("swell")`.

Marked `TODO(debug-seed)` at all four sites for later removal:
`ChunkDefs.matchFeature`, `GenCore` (field + `nextChunk` bypass),
`Main.server` (`resolveSeed`/`startRun`), `DESIGN.md` §7.

## Repo & deploy

- Push to `origin/main`. Commits: `Albisourous
  <43053302+Albisourous@users.noreply.github.com>`, no co-author trailers.
- `.rbxl`/`.rbxlx` binaries and `graphify-out/` are gitignored — source of
  truth is `src/`. `graphify-out/` holds a knowledge graph of the repo
  (`graph.json`, `GRAPH_REPORT.md`, `graph.html`) — query it for architecture
  questions before re-reading everything.
- Live experience: universe `10771950941`, root place `RoBall3D`
  (placeId `129613959669994`). Open it in Studio via
  `roblox-studio:1+launchmode:edit+task:EditPlace+placeId:129613959669994`.
  Publish goes there via File → Publish.
- Dev sync: `rojo serve` + Rojo Studio plugin (installed at
  `~/Documents/Roblox/Plugins/RojoManagedPlugin.rbxm`, click its Connect
  button once per session).
