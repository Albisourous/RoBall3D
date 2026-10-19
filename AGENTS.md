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
4. **Generation must stay pure & seeded.** `GenCore` takes `Random` and emits
   chunk specs — no `math.random`, no Instance creation inside it. Determinism
   is a leaderboard feature.
5. Keep chunk builders constraint-honest: every chunk declares its entry
   width/speed requirements and its exit state (DESIGN.md §8.1).

## Verify before done

```bash
stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl
```

Then an MCP playtest: start play, read console output for errors, capture a
screenshot of the result.

## Repo & deploy

- Push to `origin/main`. Commits: `Albisourous
  <43053302+Albisourous@users.noreply.github.com>`, no co-author trailers.
- `.rbxl`/`.rbxlx` binaries are gitignored — source of truth is `src/`.
- Live experience: universe `10771950941`, root place `RoBall3D`
  (placeId `129613959669994`). Open it in Studio via
  `roblox-studio:1+launchmode:edit+task:EditPlace+placeId:129613959669994`.
  Publish goes there via File → Publish.
- Dev sync: `rojo serve` + Rojo Studio plugin (installed at
  `~/Documents/Roblox/Plugins/RojoManagedPlugin.rbxm`, click its Connect
  button once per session).
