# RoBall3D — Audio & Music Design

> The run is a song. Geometry Dash authors a fixed level to a fixed track;
> we generate the level *from* the track. This document is the full music
> spec — DESIGN.md §13 holds the summary and the binding tunables live in
> `Config.luau`.

Status: **spec — phases A1+ are forward work; the shipped game currently runs
the "MVP baseline" described in §2.** Reference: Geometry Dash (editor sync
model, section-driven intensity), F-777/MDK/Waterflame track canon, and the
Roblox adaptive-audio stack.

---

## 1. What Geometry Dash does, precisely (REA)

Stripped to mechanisms, GD's music design is five things:

1. **The song is the level's timeline.** The editor renders "music
   guidelines" (designer taps Record and clicks on the beat; the lines become
   permanent ruler marks) and a "music line" that tracks the player's X
   position against playback. Designers place clicks, portals and hazards
   *on* those lines — a jump lands on a snare, a mode swap lands on the drop.
2. **Intensity follows song structure.** Hard sections sit on drops,
   breathers on breakdowns, builds on risers. Players literally learn the
   level as a song — "when the second drop hits, it's the wave part."
3. **One track per level = one identity.** Stereo Madness *is* the first
   level. The Newgrounds/NCS pipeline made the soundtrack a canon — the
   songs are why people remember the levels.
4. **Death re-hears the song.** Restarting replays the section — the
   drill-it-into-your-head loop is an addiction mechanic, not an accident.
   (GD's "Don't Reset" song option is the deliberate exception.)
5. **Prior art for generation**: tools like GDForge already auto-build GD
   levels from audio analysis (onset peaks → orb placement). Procedural
   level-from-music is proven; we're doing it first-class instead of as an
   importer.

**The inversion we own**: GD hand-places objects to a song's beat grid. Our
generator *is* the level designer, so the beat grid becomes a generation
constraint — the song's structure participates in `nextChunk()` alongside
tier and width rules. Nobody else gets this for free because nobody else's
level builder can read the song.

## 2. Where we are (MVP baseline)

- One looped synthwave track (`vaporwave_loop`, 16 bars ≈ 43.6s at
  **88 BPM**, A minor — rendered by `roball3d-audio/generate_audio.py`,
  "NEON CASCADE": intro → saw hook → octave-jump break → riser → drop,
  claps, 16th hats, sidechain pump).
- `MusicController` drives `Sound.PlaybackSpeed` `0.9 → 1.35` with ball
  speed (`speedNorm`). **Heard BPM is therefore `BaseBpm × PlaybackSpeed`:
  ~79 BPM cruising to ~119 BPM flat-out** — the track morphs chillwave →
  EDM as the run accelerates. This is already the GD "speed = energy"
  signature; keep it.
- Gem clusters already land on the heard beat grid (`beatSpacing`,
  `rollRhythm`, `gemRhythmLine` — cluster sizes are note groupings:
  8 = 16ths, 4 = 8ths, 2 = quarters, 1 = accent). Pickups chime up an
  A-minor pentatonic ladder per combo (`SfxController`).
- Death slides pitch to `DeathPitchFloor = 0.6`.

Everything below builds on this — nothing here is thrown away.

## 3. Soundtrack strategy: keep the synth pipeline

**Decision: we render our own tracks.** `generate_audio.py` is already a
GD-literate arranger (it knows what a riser, a half-time break and a
16th-hat drop *are*). Keeping it gives us what licensed music never can:

- **Free stems** — the mix is already routed through buses (pad, bass,
  kick, rim/clap, hat, lead, arp, vinyl, reverb send). Writing each bus to
  its own file is an afternoon of work.
- **Free beat maps** — the renderer *knows* where every beat, phrase and
  section boundary is because it placed them. It emits that as data; no
  beat-detection guessing.
- **Zero copyright surface** — self-authored output, no Newgrounds/NCS
  licensing, no asset-Id roulette.
- **Infinite iteration** — new track = new seed/arrangement constants.

Licensed tracks stay possible later (the runtime won't care whether a loop
came from our renderer or an import), but they can never feed the
generator a beat map. Pipeline first.

### 3.1 Pipeline v2 — what `generate_audio.py` emits next

Per track, alongside `track.ogg` (the full mix, for menu/fallback):

| Output | What | Why |
|---|---|---|
| `stems/{pad,bass,drums,lead,arp,air}.ogg` | Each bus rendered solo, **same sample count** `N_OUT` | Vertical mixing: fade layers by tier. Identical lengths = sample-locked sync. |
| `SongMap_<id>.luau` | Generated module per track: `{ id, bpm, beatsPerBar, loopBeats, sections, accentBeats, scale ladders }` | The generator's chart. Checked into `src/` — pure data, no audio parse at runtime. |
| `stings/{tier_up,death_fall,menu_start}.ogg` | One-shots rendered in-key | Beat-quantized stingers (§6). |

`SongMap.luau` is a hand-written registry: it re-exports the default
track's map (so `SongMap.sectionAtBeat(...)` keeps working) and adds
`forTrack(id)` / `trackIdFor(seed, Tracklist)` — the seeded pick GenCore
and MusicController share. Per-track chart sketch:

```luau
return {
    id = "vaporwave_loop",
    bpm = 88,            -- BaseBpm: matches the rendered grid
    beatsPerBar = 4,
    loopBeats = 64,      -- 16 bars
    -- sections come straight from the renderer's DRUM/BREAK/DROP constants
    sections = {
        { first = 0,  last = 7,  kind = "intro",  energy = 0.20 },
        { first = 8,  last = 27, kind = "groove", energy = 0.55 },
        { first = 28, last = 31, kind = "build",  energy = 0.70 },
        { first = 32, last = 47, kind = "break",  energy = 0.35 },
        { first = 48, last = 63, kind = "drop",   energy = 1.00 },
    },
    accentBeats = { 0, 16, 32, 48 }, -- phrase downbeats (build/drop entries)
}
```

### 3.2 Track canon — implemented

`Config.Music.Tracklist = { "vaporwave_loop", "neon_descent", "retro_wave" }`
— the run's seed picks the track via `SongMap.trackIdFor`: **same seed →
same track + same map + same musical pacing** — the leaderboard row becomes
a replayable "level" exactly like a GD ID. All three tracks carry full stem
sets (`TrackAssets[id].Stems`) so tier-layering works on any; the seed also
rotates the opening accent (§6). `retro_wave` is the outrun-flavored entry
(100 BPM, Am9 → Gadd9 → Fmaj7 → Em9 arc landing Gadd9 → E7b9 in the drop,
tape-dragged master) modeled on the Envato "Retro Wave" reference. Grow the
canon by adding a `TRACKS` spec in `generate_audio.py`, rendering, and
appending the id + `TrackAssets` entry. `SaveService` records `trackId`
next to the seed.

## 4. Runtime: migrate to the audio graph

The modern Roblox audio stack (`AudioPlayer` + `Wire` graphs — `Sound`/
`SoundGroup`/`SoundEffect` are now the discouraged path) is the enabler for
everything below:

```
AudioPlayer[stem] ──► AudioFader[stem] ─┐
AudioPlayer[stem] ──► AudioFader[stem] ─┤   (players stay sample-locked:
...  4–6 stems ──►  ...               ──┤    same length, Play() same frame)
                                        ▼
                              AudioChannelMixer? / straight wiring ──► AudioPitchShifter ──► AudioDeviceOutput
                                        │                                    ▲
                                        └──► AudioAnalyzer (client-only:     └─ Pitch = ps^(−k)
                                             RmsLevel/PeakLevel/GetSpectrum)      optional pitch-lock
```

Concrete nodes (all client-local, parented under a client-owned container,
e.g. a `RoBallAudio` Folder in `PlayerGui`):

- **`AudioPlayer` per stem** — `Asset = rbxassetid://<stem id>`,
  `Looping = true`, `AutoLoad = true`, `PlaybackSpeed` driven identically on
  every stem (the speed ramp survives migration — `PlaybackSpeed` exists on
  `AudioPlayer`). `Play(atTime)` supports scheduled starts if we want
  sample-tight stem entry.
  Entries also accept full ContentId URIs: `rbxasset://roball3d/*.ogg`
  resolves from Studio's bundled `content/` dir for local dev before the
  oggs are uploaded — a readiness watchdog drops back to the single mix if
  any stem never becomes ready (e.g. dev paths on a published client).
- **`AudioFader` per stem** — tier layer mix (§5), ramps over beats, not
  seconds.
- **`AudioPitchShifter` (optional)** — `Pitch = ps^(−PitchCompensation)`.
  `PitchCompensation = 0` keeps the current coupled chipmunk ramp;
  `1` locks pitch while tempo still climbs. **Default 0.5**: half the
  squeak, all the urgency. Tunable in `Config.Music`.
- **Stepped tempo, not warble** — speed IS the tempo: `ps(norm)` ramps
  `PlaybackSpeedMin→Max` over `Speed.Start→Max`, then keeps climbing at
  `PlaybackSpeedEndless` per over-norm past it (speed is uncapped, so the
  tempo lifts forever) up to `PlaybackSpeedCeil`. `TempoStepSt` snaps the
  result to semitone steps — the song modulates up a real interval each
  time the ball crosses a threshold (a key-lift, GD-style) — gliding in
  over `TempoStepGlide` s. `MusicGrid.playbackSpeedForNorm` is the single
  mapping both the live players and the generator's beat predictions use,
  so gem spacing/section timing stay on the heard grid at any speed.
- **`AudioFilter` lowpass on the bus** — the "underwater/tape" pass for
  menu + death (§7).
- **`AudioAnalyzer` tap on the bus** — `SpectrumEnabled`, bands → visuals
  (§8). Client-only by design (server reads zero); visuals are decorative,
  so that's fine.
- **SFX players** — one `AudioPlayer` per stinger; a shared SFX asset with
  `PlaybackRegion` slices is an option if we pack multiple stingers in one
  file (GD's SFX-library trick).

**Stem drift watchdog**: players that start together on equal-length
streams should hold sync, but we verify — on the lead stem's `Looped`
event, compare each stem's `TimePosition` to the lead's; if drift > 40ms,
snap `TimePosition` to the lead (or re-`Play` at the next downbeat).
Cheap insurance, runs once per lap.

**The beat clock**: composition position is a pure function of
`leadPlayer.TimePosition` — `beatPos = TimePosition × bpm / 60` (asset
time; `PlaybackSpeed` only changes how fast we traverse it). Section
lookup = `SongMap.sections` containing `beatPos % loopBeats`.

## 5. Songform-synced generation (the centerpiece)

Two layered sync models, both deterministic:

### 5.1 Tier-synced layers (vertical mix — the endless-runner half)

Stems fade in with `speedNorm`/tier, faders ramped over `FadeBars = 2`
bars (fades land on bar lines, not mid-phrase):

| Stem | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|
| pad + air | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 |
| bass | 0.7 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 |
| drums | 0 | 0.6 | 0.85 | 1.0 | 1.0 | 1.0 |
| arp | 0 | 0 | 0.6 | 1.0 | 1.0 | 1.0 |
| lead | 0 | 0 | 0 | 0.7 | 1.0 | 1.0 |

(`Config.Music.Layers` — tunable; table above is the starting point, not
the final mix.)

### 5.2 Songform chunks (the GD half)

**Musical position is a pure function of distance.** Heard BPM =
`BaseBpm × ps(v)` and the ball covers `v` studs/s, so beats advance per
meter at `BaseBpm × ps(v) / (60 × v)`. With the shipped numbers:

| Ball speed | Heard BPM | Studs per bar | Studs per 16-bar lap |
|---|---|---|---|
| 40 (T1) | 79 | ~121 | ~1,940 |
| 64 (T3) | 95 | ~166 | ~2,650 |
| 106 (T6) | 119 | ~218 | ~3,490 |

**Lap 1 spans ~1.9–2km — almost exactly the tier arc to Tier 5.** The
loop's own drop (bars 12–15, last quarter of the lap ≈ ~1.5–1.9km) lands
right where `RampGap` unlocks. The song's climax and the track's
difficulty cliff coincide *for free* — we keep and sharpen that.

`GenCore` gains a musical clock:

- `barPosAt(dist)` — numeric integral of `beatsPerMeter(v)` over the
  nominal speed schedule (piecewise by tier + the `Accel` ease), computed
  in ~10-stud steps. Pure, seeded, unit-testable — same purity contract as
  the rest of GenCore (no wall clock, no `math.random`).
- `sectionAt(dist)` — bar position mod `loopBeats` → SongMap section →
  `kind` + `energy`.

Chunk selection gets an **energy bias** (selection only — every legality
rule in §8.1/`Obstacles` is untouched: `CorridorMin`, `ReactionTime`
spacing and width contracts still gate what's *allowed*; energy only
reweights among legal picks):

| Chunk family | Members | Weight vs section energy `e` |
|---|---|---|
| breather | Flat, Bowl | `× lerp(1.6, 0.3, e)` |
| technical | Slalom, Narrow, Tilt, Pinch, SplitGap | `× lerp(0.7, 1.3, e)` |
| lethal | BlockGate, BlockField, WallSlot | `× lerp(0.3, 2.0, e)` |
| spectacle | RampGap | `× (e > 0.85 ? 2.5 : 1)` — drops want launches |

So a `break` section genuinely rolls breathers, a `drop` rolls lethal
clusters, a `build` ramps technical chunks — every lap has the GD
intro→build→drop→break arc *inside* the tier escalation.

**Phrase-quantized set pieces** (refinement, A4): when a lethal chunk or
`RampGap` wins the roll, nudge its start so its feature lands on the next
section boundary/`accentBeats` downbeat (generator knows studs-per-beat at
that distance — shift the chunk start ≤ half a chunk). The drop *hits*
when you thread the wall — that's the GD editor's guideline-tap, done by
the generator.

**Gems**: `rollRhythm` consults section energy — drops may roll one step
denser (32nd-note runs at top speed), breaks cap at quarters. Clusters
stay on the same beat grid as today.

**Honest limit — throttle drift.** The prediction uses the *nominal* speed
schedule; a player holding W/S drifts the heard position vs the predicted
one (bounded — chunks are already placed, so worst case a drop lands a
beat late, not wrong). Acceptable; the grid re-converges every lap.
Documented, not solved.

## 6. Beat-quantized events

Anything that *sounds* musical lands on the grid:

- **Tier-up sting** — `stings/tier_up`: triggered when a tier boundary
  crosses; the player computes `delay = (nextAccentBeat − beatPos) /
  heardRate` and plays it then — the sting arrives *on* the downbeat, GD
  trigger-style.
- **Restart** — track restarts per run (GD default: rehear the intro, own
  the first ten seconds). `Music.SeedStartOffset` (bool, default off): if
  on, the start offset rotates to a seeded `accentBeat` so repeat seeds
  don't always open on bar 0 — deterministic, still "same seed = same
  level."
- **Gem chime** — pickups are physically on the grid already (their
  spacing *is* the beat), so chimes are self-quantizing. The combo ladder
  is section-aware: `SongMap.sections[].scale` is the union of live chord
  tones under the ball right now (E7b9's b9 spice shows up in drop
  pickups, Am9's 9th in intro), generated from the score's chord chart —
  falling back to `Config.GemSfx.ComboScale` when the clock isn't running.
  The ladder is a *phrase*, not a siren: it wraps into the next octave
  instead of stalling on the top rung, every `CadenceEvery`-th pickup
  resolves UP to the root's next octave (the run lands on its octave like
  a cadence), and past `MaxOctaves` it folds back down so pitches stay
  sweet. From the second pickup of a combo, a quiet perfect fifth rides
  under the melody at `HarmonyVolume` — consonant against any chord tone —
  and combo volume swells by `ComboVolGain` (capped). Same jitter on both
  voices so the dyad stays in tune.

## 7. Scene scoring — menu, death, wind

- **Menu**: same track at `PlaybackSpeedMin` through a half-closed
  `AudioFilter` lowpass (~2kHz) — the muffled-diner version of the game
  song. Opening PLAY opens the filter on the count-in.
- **Death (upgrade of the shipped slide)**: tape-stop — tween
  `PlaybackSpeed → DeathPitchFloor` **and** sweep the bus lowpass
  18kHz → 700Hz over the same 0.5s, then hold under the death screen.
  Restart resets both instantly (instant restart stays sacred — no fade-in
  tax).
- **Wind** — looped noise `AudioPlayer` through its own fader +
  `AudioFilter`; volume `∝ speedNorm²`, cutoff `2k → 8kHz` with speed.
  The speed you hear is wind + tempo — two channels of the same signal.

## 8. Audio-reactive visuals (analyzer)

`AudioAnalyzer` on the mix bus → client-side pulses that never touch
readability ("readable chaos" is a pillar — pulses are ±10% value, never
hue, never near `LethalColor`):

- **Bass band** → synthwave sun strip scale pulse + grid-strip brightness
  thump (the deck breathes on the kick).
- **Beat clock** → gems swell on every beat (`BeatPulse.client`), sharp
  attack + beat-long decay, downbeats ~30% harder — the GD world-pulse
  read, driven by the same clock the pickups are placed on.
- **Mid band** → palette neon `Saturation`/`NeonValue` nudge; bloom
  `Intensity` +0.05 max.
- **RmsLevel** → HUD score pop on downbeats only (4-beat gate — not every
  kick, that would strobing).

`Config.Art.AudioReactive` master switch + per-band gains; all decorative,
off = nothing lost.

## 9. Config sketch (all tunables, per repo law)

```luau
Config.Music = {
    Track = "vaporwave_loop",     -- SongMap id; seed can pick from a canon
    Volume = 0.5,
    BaseBpm = 88,                 -- must equal SongMap.bpm — grid truth
    PlaybackSpeedMin = 0.9,
    PlaybackSpeedMax = 1.35,
    PitchCompensation = 0.5,      -- 0 = full chipmunk ramp, 1 = pitch-locked
    DeathPitchFloor = 0.6,
    Layers = { pad = {...}, bass = {...}, drums = {...}, ... }, -- §5.1
    FadeBars = 2,                 -- layer fades complete over this many bars
    SeedStartOffset = false,      -- rotate start bar by seed
    SyncDriftMs = 40,             -- stem watchdog threshold
}

Config.MusicSync = {
    Enabled = true,
    -- §5.2 family weight tables + energy threshold for spectacle
    -- (numbers live here; formulas live in GenCore)
}
```

## 10. Build phases

| Phase | Deliverable | Done when |
|---|---|---|
| A1 | Pipeline v2: stems + `SongMap.luau` + stings | `SongMap` required from `src/`; stems uploaded, same length verified |
| A2 | Beat clock + songform chunks | `barPosAt` unit-verified vs config numbers; chunk histograms shift by section energy with seed fixed |
| A3 | Audio-graph migration | stems sample-locked under load; layer faders follow tiers; drift watchdog passes a 3-lap soak |
| A4 | Phrase quantization + section-aware gems | lethal features land on downbeats in log; drop sections roll denser clusters |
| A5 | Scene scoring + analyzer visuals + track 2 | death tape-stop feels right; sun pulses to bass; seeded track pick recorded on leaderboard rows |

A1–A2 are pure and fully testable outside Studio (SongMap is data;
`barPosAt` is math). A3+ needs Studio playtests via the MCP loop.

## 11. Explicit limits & non-goals

- **No runtime audio analysis for gameplay.** `AudioAnalyzer` is
  client-only and decorative; the generator runs on SongMap data it can
  compute deterministically. (GDForge-style onset detection is how you'd
  import *external* songs later — backlog, not spec.)
- **No beat-detection on uploaded tracks.** If a licensed track ever ships,
  its SongMap is hand-authored, same schema.
- **Pulses never tint toward red.** Lethal stays lethal.
- **Instant restart never waits on audio.** All transitions are ≤ a beat.
- **Throttle desyncs the chunk grid slightly** (§5.2). Accepted.
- Server does zero audio work — analyzer, faders, players all client-side;
  the server's only audio fact is the seed→track pick it records.
