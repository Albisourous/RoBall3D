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
   bigger gem payout, own tab. *(done — 15b7811; **later removed** — the cup
   board, seed keywords, run bonus, and podium payouts were cut when the
   menu dropped to DAILY|RANDOM only)*
5b. **Music canon + TRACK cycler** — FlowMusic batch (10 charts), menu bed,
   seeded-pool gating via ActiveTracklist. *(done — bcdf769, synced from the
   audio pipeline)*
6. **Achievements** — milestone badges (first 1k/2.5k/5k, 50 rotor passes,
   10k lifetime gems banked). Menu section + a toast on unlock. Server-tracked
   in the profile store. *(done — 3a47c5d: 8 badges / 5 kinds, RoBallAch
   tally + RoBallAchNew toast batch)*
7. **PB ghost** — race your best run: record position samples during a run
   (already-sequenced data), replay a translucent ball on the same seed.
   Must replay deterministically from the seed, not stored frames, to stay
   honest. *(done: GhostController + SaveGhost one-shot credential; the
   echo only ever replays the PB run on its own seed)*
8. **New world themes** — `Backdrop.luau` supports `theme` strings; add
   `void` (starfield well) and `grid` (retro horizon) themes + world items,
   then a bundle. Verify with screenshots — do not blind-place geometry.
   *(done — b0032d7: 150 star motes + 21w/14r grid plane, both screenshot-
   verified live; DEEP SPACE bundle carries both)*
9. **Near-miss bonus** — close passes within N studs of lethal geometry add
   trickle score. Audit impact on `plausible()` anti-cheat cap first; it
   changes score math so it needs a DESIGN.md note.
   *(done — 7b92eae: ordered hazard-plane records in the streamer, cursor
   scan at crossing-x, static-face/rotor-disc rules, cap headroom, CLOSE +3
   HUD flash; verified 3 natural awards live. The commit also carries the
   audio pipeline's menu AUDIO mixer — AudioMix + SetAudio remote +
   RoBallVol_ attrs + profile.audio — complete and verified wiring.)*
10. **Run stats panel** — death screen adds: top speed reached, obstacles
    passed, distance under boost, closest-call. Cheap, big feel win.
    *(done — 3c8c3c3: `top N s/s · M gates · P% boost · margin X` line;
    server sends hazards+closest on RunEnded, client owns top/boost/dash)*
11. **Death-cam** — on death, 1.5s orbit of the kill spot before the
    RUN OVER card. Presentation only.
    *(done — 1a569df: ease-out yaw arc + pull-back + FOV settle, card
    delayed via deathSeq guard, R skips; verified live)*
12. **Friends board** — third leaderboard tab filtered to Roblox friends
    (GetFriendsAsync ids ∩ top-store meta). Only if the store count stays
    manageable.
    *(done — 028bccc: client-side `◈ friends` filter chip riding all three tabs;
    lazy `GetFriendsAsync` set (no 4th store), real ranks preserved,
    offline/empty/err states verified live vs running module)*
13. **Music packs** — `SongMap_*.luau` stems pattern exists; add one more
    track as a bundleable. Needs real audio assets — flag as human-blocked
    if none available.
    *(blocked — all 13 cataloged tracks already wired to real uploads;
    a new bundle needs a human-provided master/stem upload)*
14. **Seasonal pack slot** — one time-limited bundle window (config dates) so
    the shop always has something rotating.
    *(done — 125d20c: `Config.Monetization.Seasonal` yearly UTC window +
    SOLSTICE frost set; `Daily.seasonalStatus` shared math, `IN Nd`
    countdown button, server refuses bundle + member items off-window;
    verified live incl. boundary dates)*
15. **Same-seed rerun** — death screen gets a RERUN chip next to RETRY that
    restarts on the run's exact seed: the deterministic rematch button.
    *(done — `rerun #N` ghost button + T key while dead fires the run's
    numeric seed; verified live, card chip matches dead run's seed)*
16. **Recent-runs strip** — profile-persisted last-N runs (score/dist/seed)
    on the menu; click a row to prefill the seed box. Deterministic
    replay of your own past maps.
    *(done — 796afeb: RECENT strip under the leaderboard rows, newest
    five, `pts · m · #seed`, click fills the seed box; history rides
    profile.history + RoBallHistory attr, verified live 2-deep)*
17. **Log speed curve** *(done — 7581359: Speed.Start/LogGain/LogDist
    `34 + 49.3·ln(1+d/625)` replaces tier speed steps + EndlessRamp;
    width-shrink still drives the endless tail)*
18. **Client-authoritative kills** *(done — dbf099f: FatalController tags
    RoBallLethal parts, Touched + swept Spherecast on the ball's owner,
    ReportFatal latch; server keeps fall/stall backstops. Kills the
    "random death" class from server-interpolated ball copies)*
19. **Menu RunSetup** *(done — 11fd79d: DAILY/RANDOM chips + type-a-
    seed box in one setup card; PLAY is the single solid slab; weekly cut
    later — daily is the default)*
20. **Pace delta** *(done — 245b5b8: `±N vs PB` HUD line off the echo
    part's interpolated position; cyan/pink, hidden without a ghost;
    verified live via stubbed GetGhost)*
21. **Near-miss FOV pulse** *(done — adc8d41: graze attr kicks
    `Config.Camera.MissFovKick` degrees, decays at MissFovDecay/s;
    verified live 72→78→73)*
22. **Look-ahead radar** *(done — f12b3f0: `Config.Radar` strip beside
    the top-right HUD maps tagged `RoBallLethal` blocks into pooled red
    bars, top=far/bottom=ball/x=lateral; heartbeat re-scans at
    ScanSeconds so movers track; verified live incl. death-card hide.
    Same commit named the menu controls MCP playtests click by path)*
23. **Champion ghost** *(done — 2714395: per-seed record holder's replay
    in `RoBall3D_GhostChamp_v1`, UpdateAsync compare-and-set crown on
    the credentialed SaveGhost path; `GetGhost(seed)` returns own+champ,
    gold `RivalGhost` with name billboard shares the run clock; pace
    stays PB-only; verified live via stubbed GetGhost)*
24. **Near-miss chains** *(done — c2c3f75: grazes inside `ChainWindow` 6s
    multiply the award `Points × min(chain, ChainMax=4)`; `RoBallNmAward`/
    `RoBallNmChain` attrs feed a `CLOSE +N ×M` flash; plausible() cap
    gained the ChainMax factor. Verified live: chain=2 award=6 on a
    two-plane pair)*
25. **Rival pace line** *(done — 7b65cd0: `Ghost.rivalPace()` reads the
    champion echo's lead separately; gold `±N vs <name>` line under the
    cyan PB line, pink when behind; radar shifted to y174. PaceText/
    RivalText named for MCP probes. Verified live via stubbed GetGhost)*
26. **Split-time sectors** *(done — 2683a6b: `Config.Sectors` boundary
    every 250m fires `SEC n · T.Ts` plus a `±S.Ss` RichText segment per
    live replay; `Ghost.sectorSplit` interpolates the replay's crossing
    time, positive = ahead, segment omitted past replay end. Verified
    live via stubbed ghosts: SEC1 PB/champ -0.2s mid-run)*
27. **Hazard variety: low ceiling** — a `HeadBlock` spec that sweeps the
    lane at ball-height+; crossing under it demands a hop *not* taken.
    *(superseded by PressRow — the slam plate IS the ceiling hazard)*
27b. **PressRow** *(done — 5eee397: low roof + hanging plates on a new
    `dropY` mover — trapezoid pulse beat-locked to tempo; one permanent
    side lane per row (zigzags only when a beat-gap affords the lateral
    crossing via `latReach`, else the lane widens or holds), under-plate
    is the timed shortcut. Debut 2600m, tier 6+ pool. GenVerify treats
    motioned hang plates as blockers — teeth stay decorative only when
    motionless — and dropY audits the reach band since the plate's
    x-span never moves. 8 seeds × 70 chunks: 0 violations; press travel
    verified 0 … −3.2 live)*
28. **Ghost split trails** *(done — 7c7f019: each echo draws a Trail
    between two y-offset attachments; Config.Ghost.TrailLife/TrailGap/
    TrailFade. Verified live — ribbons on both echoes)*
28b. **Death replay** *(done — b58a7b0: `Ghost.replayTail` re-baselines
    the run's last DeathOrbitSec as a dim echo through the death-cam;
    the fatal approach is visible before the card. Verified live)*
29. **Crowd ghost on daily runs** *(done — b755f11: the champ store is
    now a podium `{c, r}` merged atomically in UpdateAsync (v1 bare-Champ
    keys migrate on read); `GetGhost` returns `r` too, and on the daily
    seed the client replays it as a labeled silver echo — verified live:
    silver77 on daily, absent off-daily)*
30. **Weekly cup removed** *(external — the cup board, seed keywords,
    run bonus, and podium payouts were cut when the menu went
    DAILY|RANDOM; see item 5's note)*
31. **Wave-2 cosmetics + COLOR LAB** *(external — five skin families,
    animated strobe/wave skins, matching trail/gemfx pairs, six death-fx
    styles, aurora/reef/meteor world themes, `customA/B/C` hue params on
    the LAB items resolved through RoBallHue* attrs; hue band
    pre-sanitized off LethalColor)*
32. **Sector deck ribbons** *(done — d65c1af: `TrackStreamer` paints a
    neon `SectorMark` across the deck at each `Sectors.Length` boundary,
    per-rail on cutouts — the pace pulse the HUD counts is visible on the
    track itself. Verified live: marks at z=-250/-500, full width,
    non-collidable)*
33. **Crown toast** *(done — e31c852: the ghost upload brackets
    `crownChampion` with `loadPodium` reads; a dethroning fires `Crown`
    and the client toasts `♛ CROWN TAKEN from <name>` / `CLAIMED`.
    Verified live: remote → listener → `RoBallGui` toast text)*

## Standing rules for new work

- New hazards go through `ChunkDefs` + `canRun` contracts + `GenVerify`
  blocker modeling — never stream hazards outside the spec layer.
- New config lands in `Config.luau` with a comment; no magic numbers.
- Every session ends with a clean tree, passing gates, and a push.
- If a change can't be verified in Studio (no API access), write it behind
  the existing graceful-degradation pattern (`ensureStores` nil-out) and say
  so in the commit message.
