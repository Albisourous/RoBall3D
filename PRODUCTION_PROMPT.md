# RoBall3D — Production Release Gate

Paste this prompt into a Devin session for the launch pass. It is the audit
+ checklist for the release build — everything that must be true before the
place publishes to the live universe (10771950941 / placeId 129613959669994).

> Get RoBall3D production-ready. Work the release checklist below
> top-to-bottom. Nothing publishes until every blocking box is ticked or
> consciously waived with a written reason. Verify the way AGENTS.md
> demands: `stylua --check src/ && selene src/ &&
> rojo build -o build/RoBall3D.rbxl`, then a Studio MCP playtest with a
> clean console and a screenshot proving the feature/setting live.

## 1. Release flags — flip BEFORE publish

| Flag | Dev state | Release state | Status |
|---|---|---|---|
| `Config.Debug.Enabled` | `true` — feature-seed keywords resolve ("swell", "pressrow", …) and force single-chunk tracks for debugging | **`false`** — keywords become plain hashed seeds | ☐ flip before publish |
| `Config.Debug.VerifySeeds` | `0` — `GenVerifyRunner` inert in Studio | keep `0` in prod (sweep manually, see §4) | ☐ confirm |
| `Config.Monetization.FreeForTesting` | ~~`true`~~ | **`false`** — real Marketplace prompts | ☑ done |
| `Config.Power.Capacity` / `Dash.Cost` | was 10× test values (12 / 0.03) | `1.2` / `0.3` | ☑ done |

Debug runs already cannot touch production state: `run.debug` makes
`killRun` skip records, boards, quests, streaks, and session-best. Flipping
`Debug.Enabled` off is still required — it removes the keyword surface
entirely.

## 2. Monetization — Creator Dashboard work (human-blocked today)

- [ ] Create the 11 gamepasses + `bank2x` pass listed in `DLC.md`.
- [ ] Create the 3 developer products (gem packs) listed in `DLC.md`.
- [ ] Paste real ids into `Config.Monetization.Passes` / `.Products`
      (everything is `0` → shop shows SOON until then — safe, not broken).
- [ ] Publish to a test place, buy each pass + product once, confirm
      `ProcessReceipt` grants and the pass-check path equips cosmetics.
- [ ] Confirm cosmetics stay cosmetic — no hitbox/speed/score changes.

## 3. Data & boards — needs a published test place with API access

- [ ] Profile save/load round-trips (best, gems, cosmetics, history, audio).
- [ ] All-time OrderedDataStore writes and reads ranks correctly.
- [ ] Daily board: UTC-day seed matches for all players; daily streak
      increments on consecutive days.
- [ ] Ghost saves (`SaveGhost`) round-trip; champion ghost CAS works.
- [ ] Studio-degraded paths (DataStores unavailable) stay graceful —
      already verified, re-verify after publish.

## 4. Generation & fairness

- [x] `GenVerify` sweep — 24 seeds × 600 chunks, **0 violations**
      (PadHop pad-position drift found + fixed: the builder sampled tier
      speed at `padT × initial length` while the pad rides `padT` of the
      *grown* chunk — sub-stud under the old log tail, ~4 studs under the
      linear tail. Re-sweep after any ChunkDefs/Tiers touch).
- [ ] Purity check: no `math.random`, no Instance creation in
      `GenCore`/`ChunkDefs` — grep before tagging the build.
- [ ] `StreamingEnabled` off, `CharacterAutoLoads` off,
      `FallenPartsDestroyHeight` stays declarative in
      `default.project.json` (-50000), never set from a script.

## 5. Audio & assets

- [ ] Every `TrackAssets` entry loads — `AssetId = 0` tracks are dropped
      from `ActiveTracklist` by the watchdog; sweep the list.
- [ ] `rbxassetid://203785492` fails to load at startup ("asset type does
      not match") — **confirmed external**: not in `src/`, not in the
      Edit tree (broad ContentId-property sweep), not in either play
      datamodel. It's Zyleak's 2015 "Pop Close Sound" requested with the
      wrong expected type at Studio session/rojo-push transitions — a
      stale reference inside a Studio built-in/plugin asset. Harmless;
      nothing game code can do. Verify in a real client.
- [ ] Menu/stem assets all load; the `Music.Wave*` scope trace
      (BPM HUD) stays ≤ 30 Hz analyzer reads — no extra taps.
- [ ] SFX ids (gem pickup, dash, UI) all resolve.

## 6. Presentation & UX

- [ ] Device simulator pass: phone portrait/landscape + tablet — check
      BPM digit + waveform vs. seed corner text, power meter, radar,
      and the native Roblox chrome for overlap.
- [ ] HUD clutter law holds: score top-right, radar right, meter
      bottom-left, BPM+wave bottom-right — nothing else perma-on-screen.
- [ ] Menu → run → death → retry and menu → run → death → rerun-seed
      flows clean; death cam settles; RECENT strip clicks fill the seed box.

## 7. Launch steps (in order)

1. `Config.Debug.Enabled = false`, commit, push.
2. All monetization ids in place; `FreeForTesting` already `false`.
3. `stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl`.
4. GenVerify sweep — 0 violations.
5. Studio MCP playtest: clean console (DataStore-off and the 203785492
   noise are known), screenshot of menu + live run + death card.
6. Publish the place. Smoke-test the live universe: real run, board
   entry, one purchase.
7. Flip `Config.Debug.Enabled = true` back on `main` AFTER publish if
   ongoing dev continues — keep the release build clean.

## Already verified this pass

- `stylua`/`selene`/`rojo build`: 0 errors/warnings — build produced.
- Live playtest: run starts, score/quests/gems HUD live, power meter
  reads the reverted economy, BPM digit + auto-gained scope waveform
  render and animate, console clean.
- `swell` debug-seed forced an all-Swell track under
  `Config.Debug.Enabled = true`; `run.debug` blocks all persistence.
