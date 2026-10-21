# RoBall3D — Autonomous Improvement Loop

Paste this prompt into a Devin session (or keep it as standing orders). The agent
runs the loop below and does not stop until you say **stop**.

> Improve RoBall3D continuously. Work the backlog top-to-bottom, one feature per
> commit. Never break the core loop or the fairness guarantees. Verify every
> change the way the repo's AGENTS.md demands. When the backlog is empty,
> invent the next feature that increases replayability and add it to the list
> before building it.

## The loop

1. Pick the top unfinished item in **Backlog**. If it feels wrong for the game,
   reorder it and write a one-line note saying why.
2. **Design first**: if the change touches mechanics, presentation law, or
   contracts, update `DESIGN.md` in the same commit. Spec and code never drift.
3. Implement. All tunables go in `src/ReplicatedStorage/RoBall/Config.luau`.
   Cosmetics/content are data records in `Cosmetics.luau` — new looks are
   config, not code.
4. Gates, all required:
   `stylua --check src/ && selene src/ && rojo build -o build/RoBall3D.rbxl`
5. If generation, obstacles, physics, or contracts changed: run a `GenVerify`
   sweep (`sweepRange`, ≥8 seeds × 400 chunks). **0 violations required.**
6. Playtest through Studio MCP: start play → read console (ignore known Studio
   noise: DataStore API-off, UIBlox FoundationProvider, asset 203785492) →
   `screen_capture` the feature actually rendering → stop play.
7. Commit + push `origin/main`, author `Albisourous
   <43053302+Albisourous@users.noreply.github.com>`, no co-author trailers.
   One feature per commit.
8. Mark the item DONE in this file (date + commit hash). Pick the next item.
9. Repeat until told to stop. If blocked on something only a human can do
   (real DataStore/gamepass ids, art decisions), skip it, note it, keep going.

## Inviolable core — never regress these

- **Pure seeded generation**: no `math.random` in `GenCore`/`ChunkDefs`, no
  Instance creation inside generator modules. Determinism is a leaderboard
  feature.
- **Contract-honest chunks**: every builder honors `MinEntryWidth`, corridor
  ≥ `Obstacles.CorridorMin`, reach-honest leads/transitions. `GenVerify` is
  the judge — fix the generator, never weaken the audit.
- **Momentum steering**: `Config.Speed`/`Lateral` model — no speed caps that
  break endless acceleration, no steering assists that remove drift feel.
- **Beat-locked movers** on the music grid; no free-running hazard timers.
- **Camera**: position-damped chase, look-ahead slope read, FOV 70→88, ≤3° lean.
- **No per-frame Instance creation**; chunk-owned cleanup only.
- `workspace.StreamingEnabled` OFF, `Players.CharacterAutoLoads` OFF. Never set
  `FallenPartsDestroyHeight` from game scripts.
- **Cosmetics never touch gameplay**: hitboxes, speed, scoring, generation are
  identical for every player. Anything that helps a run (consumables,
  checkpoint buys) submits to the *assisted* board, never the clean one.
- **Leaderboard integrity**: clean and assisted boards never mix; banked gems
  are never score.

## Backlog — ranked by impact

`DONE` items keep their entry for history.

1. **Dual leaderboard** — ALL-TIME board (existing) + DAILY board: a seed
   derived from the UTC date so every player runs the same map that day;
   per-day OrderedDataStore + meta, tab UI, reset countdown, `daily` seed
   keyword in the seed box. *(done — see git log)*
2. **AURORA + PHANTOM packs** — two new bundle passes filling the unused
   green/teal and mono-violet palettes; à-la-carte gem prices included.
   *(done — see git log)*
3. **Daily streak** — consecutive-day runs on the daily seed shown on the
   daily tab + a small streak bonus of banked gems. Server tracks last
   daily-played day in the profile store. *(done — see git log)*
3b. **HUD placement** (user fix, unnumbered) — score top-left, PB gate
   label near-field only + NEW BEST flash on crossing. *(done — see git log)*
4. **Daily quests** — 3 seeded missions per day (e.g. "pass 5 Rotors",
   "bank 150 gems", "reach 2200m"), gem rewards, progress in the HUD menu.
   Reuse the `Daily` module's seed for quest selection. *(done — e74df54)*
5. **Weekly seed cup** — same machinery as the daily board keyed on ISO week;
   bigger gem payout, own tab. *(done — 15b7811: Sunday-week tag, W<n> store
   pair, third tab, +25 first-run bonus, lazy top-3 payout 200/100/50)*
5b. **Music canon + TRACK cycler** — FlowMusic batch (10 charts), menu bed,
   seeded-pool gating via ActiveTracklist. *(done — bcdf769, synced from the
   audio pipeline)*
6. **Achievements** — milestone badges (first 1k/2.5k/5k, 50 rotor passes,
   10k lifetime gems banked). Menu section + a toast on unlock. Server-tracked
   in the profile store.
7. **PB ghost** — race your best run: record position samples during a run
   (already-sequenced data), replay a translucent ball on the same seed.
   Must replay deterministically from the seed, not stored frames, to stay
   honest.
8. **New world themes** — `Backdrop.luau` supports `theme` strings; add
   `void` (starfield well) and `grid` (retro horizon) themes + world items,
   then a bundle. Verify with screenshots — do not blind-place geometry.
9. **Near-miss bonus** — close passes within N studs of lethal geometry add
   trickle score. Audit impact on `plausible()` anti-cheat cap first; it
   changes score math so it needs a DESIGN.md note.
10. **Run stats panel** — death screen adds: top speed reached, obstacles
    passed, distance under boost, closest-call. Cheap, big feel win.
11. **Death-cam** — on death, 1.5s orbit of the kill spot before the
    RUN OVER card. Presentation only.
12. **Friends board** — third leaderboard tab filtered to Roblox friends
    (GetFriendsAsync ids ∩ top-store meta). Only if the store count stays
    manageable.
13. **Music packs** — `SongMap_*.luau` stems pattern exists; add one more
    track as a bundleable. Needs real audio assets — flag as human-blocked
    if none available.
14. **Seasonal pack slot** — one time-limited bundle window (config dates) so
    the shop always has something rotating.

## Standing rules for new work

- New hazards go through `ChunkDefs` + `canRun` contracts + `GenVerify`
  blocker modeling — never stream hazards outside the spec layer.
- New config lands in `Config.luau` with a comment; no magic numbers.
- Every session ends with a clean tree, passing gates, and a push.
- If a change can't be verified in Studio (no API access), write it behind
  the existing graceful-degradation pattern (`ensureStores` nil-out) and say
  so in the commit message.
