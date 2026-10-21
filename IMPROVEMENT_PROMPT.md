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
    verified live 72→78→73 — later removed with the near-miss FX layer)*
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
    two-plane pair — later removed: all near-miss FX (CLOSE flash, chain
    row, graze whoosh, sparks, FOV kick) cut for noise; grazes pay flat
    `Points` silently)*
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
28b. **Death replay** *(done — b58a7b0; **removed** — the parked dim
    echo on the death card read as a stray ball; V's `watch replay`
    still re-runs the full recording on demand)*
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
34. **Daily rank on the death card** *(done — c54f9ab: a daily-seeded
    session-best submits, then `dailyRank` re-reads the fresh board and
    publishes `RoBallDailyRank`; the card fills in `daily #n today`
    late. Cleared on run start. Verified live: attr → `daily #3 today`)*
34. **Menu cleanup pass** *(done — 16354d3: leaderboard TOP|DAILY tabs
    re-centered for the two-board layout (was 3-tab geometry), the
    `audio ▸` toggle left the hero column for a fourth garage page
    `STYLE|PACKS|BANK|AUDIO` with five stacked sliders, and today's
    quests moved off bare text lines into a `MISSIONS` card matching
    RUN SETUP's bordered chrome. Verified live: chips centered,
    DAILY lit on `daily`, audio page holds 5 sliders)*
35. **Press-thread bonus** *(done — b22e35e: `dropY` press plates join the
    ordered hazard list carrying the live plate + baseY/amp; a crossing
    inside the plate's span while `drop >= Press.ThreadMinDrop` pays
    `Press.ThreadBonus` on its own `RoBallThread` counter and flashes
    `THREAD +N` (flash/kick later removed with the near-miss FX layer —
    the bonus still pays silently).
    Corridor crossings and raised-plate passes pay nil; a paid thread
    suppresses the graze-chain block — no double award. Verified live:
    record fields match spec (z=-2691, cx, halfW, amp), drop tracks the
    plate 0..1, attr → `THREAD +6` flash screenshotted)*
36. **Debut banner** *(done — 24619d8: `GenCore` stamps `spec.debut` on
    the gentle showcase, the streamer queues `{startZ, type}` per chunk,
    and the server fires `Debut` as the ball crosses in — gold
    `NEW ▸ LABEL` HUD line (`Config.Features.Label`/`BannerSeconds`)
    names each mechanic once per type per run. Presentation only.
    Verified live: 10 records milestone-correct in z-desc order, cursor
    fired Terrace at -426 and Chicane at -1294 — `NEW ▸ CHICANE`
    screenshotted mid-run beside `SEC 5`)*
37. **Death cause on the card** *(done — d7c6850: `FatalController`
    reports the lethal part it simulated (touch or spherecast), the
    server validates the `RoBallLethal` tag and reads its `ChunkType`
    stamp, `RunEnded` carries the cause, and the stats line ends
    `felled by NAME` in pink via `Features.Label` (map grew to cover
    the pool types). Falls read `the VOID`, wedges `wedged geometry`,
    untrusted parts leave it off. Verified live: `felled by BLOCK
    GATE` screenshotted on the card)*
38. **Deck-edge warning chevrons** *(done — a0da177: two heartbeat
    probes `ProbeSide` studs beside the ball cast `ProbeDown` into the
    ball's own lane folder only (backdrop towers and ghost echoes can't
    fake ground; blocks/walls inside it support honestly). A side with
    nothing under it lights a pink `◄`/`►` chevron at the screen edge —
    over a cutout or one step from the rail; pad arcs stay quiet since
    the deck is still in reach. Client-only, hidden on run end.
    Verified live: right-rail pin → `EdgeL=false EdgeR=true`, airborne
    mid-deck +10 → both false, high over void → both true (honest
    nothing-below); both chevrons screenshotted mid-run)*
39. **Landing shadow** *(done — b933b6c; **removed** — the cyan disc
    read as clutter under the ball; the down-probe survives only as the
    airtime stat's grounded check)*
40. **Ghost overtake toast** *(done — c4d6b3d: after trailing a replay's
    interpolated position by ≥ `Ghost.OvertakeArm` studs, crossing back
    to even toasts `▸ PASSED PB` / `▸ PASSED <name>` once per ghost per
    run through the shared `achToast` channel — a wire-to-wire lead
    never counts as a pass. Verified live: stub ghost parked at -40
    armed at pace −8 and toasted on the catch; `PASSED champion42`
    screenshotted beside `+160 vs champion42`)*
41. **Danger vignette** *(done — 16d30f9: the radar scan's nearest
    `RoBallLethal` overlapping the ball's line (`Danger.Lane`) inside
    `Danger.Near` studs drives a full-screen `UIStroke` frame —
    intensity `1 − dz/Near` up to `MaxAlpha`, cleared on run end. The
    forward brace warning the lateral chevrons can't give. Verified
    live: natural approach ramped stroke 0.96→0.53 before the fatal
    gate; parked 30 studs out held `vis=true T=0.76` = 0.4·MaxAlpha
    exactly; card clears it. Live screenshot not captured — runs kept
    dying inside the warning window)*
42. **Threat name on radar** *(done — b4ed601: the scan tracks the
    nearest `RoBallLethal` part, reads its replicated `ChunkType`, and
    shows the `Features.Label` name under the radar strip, cached so
    the line doesn't thrash; cleared on run end. Verified live:
    `BLOCK GATE` tracked the approach z=-113→-315 and rendered under
    the radar — screenshotted mid-run)*

43. **All-time rank on death card** *(done — d3f48e3: symmetric with
    the daily line — a session-record `submitTop` triggers
    `SaveService.topRank` (fresh `getTop` read since the write drops the
    cache) and publishes `RoBallTopRank`; the client listener fills
    `all-time #n` on the card, hidden when nil/0 or outside
    `TopCount`, cleared on every run start. Verified live: attr → card
    path rendered `all-time #7` under the seed line — screenshotted on a
    real death card)*

44. **Chain meter** *(done — 946719f: from chain two a `chain ×N` row
    holds under the miss flash with a thin bar draining across
    `ChainWindow` — every bump re-arms the drain, an empty bar is the
    dropped chain (next graze reads ×1, mirroring the server reset).
    Hidden on run start/end. Verified live: attr bump mid-run rendered
    `CLOSE +12 ×4` + `chain ×4` + drain bar — screenshotted)*

45. **Duel indicator** *(done — 0dedbf8: a pace line inside
    `Ghost.DuelRange` studs (8, either direction) earns the `· DUEL`
    suffix on both `±N vs PB` and `±N vs <name>`; client derives it from
    the same delta that renders the line, no extra plumbing. Verified
    live: stub champ at ~44 s/s showed `· DUEL` exactly inside ±8
    (-4,-7,-7,-4,-1,+5) and dropped it at 9+ on both edges — console
    boundary readings plus mid-run screenshots. Same commit moves the
    chain meter to the free left column under the sector line — its
    first slot overlapped `paceText`)*

46. **Proximity ping** *(done — 226a5a9: a flattened sonar blip on the
    `dash` mixer channel while the danger vignette is live — interval
    tightens `PingSlow→PingFast` and pitch lifts `PingLift` as the
    corridor threat closes; the audible mirror of the closing frame.
    Verified live: natural run fired a real `DangerPing` at t=6.7 on
    approach (0.6s before contact); direct calls spawned voices with
    exact octave math 0.59/0.68 = `0.5×(1+0.35×I)`)*

47. **Graze spark** *(done — fb8657a: a pooled `GrazeSpark` emitter
    rides the ball (bound per run, cleared on removal); near-miss and
    press-thread bumps `Emit(8)` icy shards — the dodge reads physically
    at the moment of risk, not only as HUD text. Verified live: emitter
    confirmed on the ball and the attr→Emit path ran clean mid-run; the
    0.45s burst is too brief to capture via tool round-trips)*

48. **Graze whoosh** *(done — 8a58109: the bell inhale-swept
    `WhooshStartOct→WhooshEndOct` (0.4→1.15) on the `wind` mixer channel
    — air rushing past the face, mirror of the dash's falling zip; fires
    with the spark on near-miss and thread bumps. Verified live:
    `GrazeWhoosh` voice spawned on the attr bump with oct0=0.40,
    vol=0.32 — exact config math)*

49. **LOST TO mirror + PB tag** *(done — dfec54e: falling back past
    `OvertakeArm` after an earned PASSED toasts `▸ LOST TO PB` /
    `▸ LOST TO <name>` — each direction change narrates, a wire-to-wire
    trail stays quiet like a wire-to-wire lead. The PB echo also carries
    a `PB` billboard now — every ghost is named. Verified live: stub
    champ parked at -60 then diving gave PASSED at t=1.85, LOST TO at
    t=2.38; the mistimed first stub dove before the catch and correctly
    fired neither)*

50. **Air share on the death card** *(done — 147e13e: the stats line
    gains `air A%` — share of run time the lane probe found no contact
    (`Landing.ContactPad` under the ball's underside). Reuses the
    landing-shadow raycast; display-only like the rest of the line.
    Verified live: pinned +30 for 4s of a 4.5s run → `air 95% · felled
    by the VOID`; natural grounded runs → `air 0%`)*

51. **Ghost margins on the death card** *(done — 137cac4: a dim trailer
    under the stats line — `at the fall: PB +38 · champion42 -142` —
    the last pace deltas vs each echo, signed by your lead, so the race
    result survives the run that ended it. Verified live: parked stub
    echoes at -60/-140 gave exactly `PB +269 · champion42 +189` at a
    -329 fall and `PB +957 · champion42 +877` at -1017)*

52. **Last-fall marker** *(done — 73ab192: a dim red `LAST n` gate on
    the deck where the most recent clean run on this seed ended — the
    bloodstain for an R-rerun, read from `RoBallHistory` (newest
    first). Same 150m minimum + view-distance rules as BEST, suppressed
    within 8 studs of the PB gate. Verified live: history `900,300,777`
    spawned the marker at exactly z=-300 labeled `LAST 900` at 0.6
    transparency (off-seed entries ignored); an 80m fall spawned none)*

53. **Watch replay** *(done — bd1bd61: `watch replay` / V on the death
    card re-runs the just-ended run's ENTIRE recording down the
    still-standing track — `Ghost.replayFull()` rebases frames to t=0,
    the chase cam follows the echo with the live run's framing, V or
    playback's end re-shows the same card from the stored arg tuple, R
    skips to retry, `Ghost.stop()` on the next run clears the echo.
    `Ghost.canReplay` hides the button on stub runs. Verified: the
    button renders on the live card (Studio click/keyboard injection is
    capability-blocked, so the full record→rebase→spawn→travel→park
    path was driven through the real module API — `dur=7.8` for 40×0.2s
    frames, echo at frame 1's `z=-6, x=2.4`, parked at the final frame's
    `z=-240`)*

54. **Radar ghost ticks** *(done — c5d0f45: a cyan PB tick on the
    radar's left edge and a gold rival tick on the right pin each
    echo's distance-ahead (`dz = -pace`) on the same ruler the threat
    bars use — a ghost in front climbs the strip as it pulls away;
    behind-you clamps to the bottom edge, out-of-range pins the top.
    Gates green; live visual check still owed — Studio was closed at
    commit time)*

## Standing rules for new work

- New hazards go through `ChunkDefs` + `canRun` contracts + `GenVerify`
  blocker modeling — never stream hazards outside the spec layer.
- New config lands in `Config.luau` with a comment; no magic numbers.
- Every session ends with a clean tree, passing gates, and a push.
- If a change can't be verified in Studio (no API access), write it behind
  the existing graceful-degradation pattern (`ensureStores` nil-out) and say
  so in the commit message.
