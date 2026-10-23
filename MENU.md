# MENU.md — menu feel: the osu! lessons

> The layout is settled — §6's shop floor (opaque backdrop, garage rail
> left, poster column, leaderboard rail right, diorama window) is ours
> and stays. This doc is the **feel** spec: what osu!'s menu does that
> makes it an instrument instead of a form, which mechanisms port onto
> our chrome, and which we deliberately leave behind.
>
> Reference: osu! (stable client's cookie + carousel; lazer's redesign
> kept the physics and dropped the pie menu — the lessons are the same
> either way). Same method as DESIGN.md §2's Slope REA.

---

## 1. What osu!'s menu does, precisely (REA)

Stripped to mechanisms, the osu! menu is seven things:

1. **The song never stops.** Menu music is the selected beatmap's own
   audio, running continuously — song select *auditions* the actual
   track, and pressing play doesn't restart the stream, it commits to
   it. The room always has a pulse because the song you might play is
   already on.
2. **The picker is a physical object.** The beatmap carousel is a
   curved stack of panels you grab, fling, and let settle — inertia,
   snap-to-item, tilt at the edges, real velocity. F2's random is a
   slot-machine spin through the same physics, not a jump. Choosing is
   *play*, pre-play.
3. **Chrome breathes on the beat.** The cookie thumps to the song,
   panels settle with spring overshoot — and that's the whole voice:
   the menu is deliberately silent of SFX (§5). All the rhythm comes
   from the music itself.
4. **Selection re-skins the room.** The picked beatmap's art fades in
   behind everything, dimmed — the pick owns the frame before it owns
   the level. The choice is ambient.
5. **One hero, everything else chrome.** The cookie is the only filled
   element on the main menu; on song select the carousel is the hero.
   Every screen has exactly one loud surface.
6. **Density around the pick.** BPM, length, mapper, star rating, your
   PB, the boards — all live on the picker screen, so choosing is
   informed and a pick feels earned.
7. **Results land as a stamp; retry is free.** The grade slams in with
   weight, the breakdown sits under it, retry is one key — the same
   "crash → report → go" addiction loop the Slope REA found.

| osu! does | Read it produces | Our port |
|---|---|---|
| Beatmap audio plays in menus; play commits the same stream | The picker auditions — the start is a lift, not a cut | `Music.preview(id)` — the TRACK row swaps the muffled menu bed to the browsed song; PLAY opens the filter on it (§3) |
| Carousel with inertia, snap, tilt | The picker is a toy; browsing is fun itself | A 1-DOF spring on the TRACK row and STYLE cyclers — every cycle overshoots and settles; wheel/drag feeds velocity (§4) |
| All chrome thumps on the beat | The menu is a rhythm instrument | `Music.sample()` already lands on `self.pulse` every frame — spend it on PLAY + the horizon rule while the menu is up (§2) |
| Menu hitsounds quantized to the grid | — cut: reads as noise under a quiet bed | Divergence kept: the menu is deliberately SFX-free — bed + audition only (§5); grid-snapping stays a gameplay instrument |
| Picked map's art owns the frame | The choice is ambient before it's played | Divergence kept: the opaque shop floor stands — the pick re-skins the room through the diorama + accent tint, not a live backdrop (§6) |
| Grade stamp + one-key retry | The report card has weight; the loop is free | Score hero + `★ NEW BEST` stamp in on a Back ease with a duck punch; retry stays `R` (§7) |
| Menu visualizer / idle motion | Idle is never dead | ~~`Music.spectrum()` scope strip under the horizon rule~~ — CUT; §2 pulse carries idle motion alone (§8) |

## 2. Beat-thumped chrome — PLAY breathes

`Main.client`'s RenderStepped already pushes `Music.sample()` into
`ui:setPulse` every frame — in menu mode it's stored on `self.pulse` and
nobody spends it. The port is a menu-side consumer with `setWave`'s own
discipline: quantize the envelope, write only on change, menu-only.

```luau
-- Ui.luau — called from Main's RenderStepped alongside setPulse.
-- The poster thumps on the menu bed: PLAY swells a few percent and the
-- horizon rule's mid keypoint dips — the menu's only filled element is
-- the one that breathes (the cookie rule).
function Ui:pulseMenu()
	if not self.menu.Visible then
		return
	end
	local e8 = math.floor((self.pulse or 0) * 8 + 0.5) / 8
	if e8 == self._menuEnv then
		return
	end
	self._menuEnv = e8
	self.playScale.Scale = 1 + Config.Menu.ChromePulse * e8
	self.ruleGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3 * e8),
		NumberSequenceKeypoint.new(1, 1),
	})
end
```

`playScale` is a `UIScale` child of the PLAY slab; `ruleGrad` is the
existing horizon-rule gradient. Keep the swell tiny
(`Config.Menu.ChromePulse ≈ 0.04`) — it should read as the room
breathing, not a bounce.

## 3. The audition is the pick — TRACK row plays the song

Today's gap: the menu bed is parked on `menuTrackId()` regardless of the
TRACK cycler, and `onStart` re-picks by seed — so the song you hear in
the menu is never the song you're choosing. osu's rule is the song you
audition is the song you play.

The plumbing is almost free: `selectTrack` already early-returns on a
same-id swap, and the splice dip already masks track changes. Add one
public seam in `MusicController`:

```luau
-- MENU.md §3: menu audition — swap the muffled bed to the browsed
-- track. Menu-only; the filter/volumes stay parked at menu values, so
-- PLAY's filter-open is a lift on the same stream, not a cut.
function Music.preview(id: string?)
	selectTrack(id or m.menuTrackId()) -- nil/RANDOM re-parks the bed
end
```

Then in `Main.client`'s `onTrackCycle` handler: a named track calls
`Music.preview(trackId)`; `RANDOM` calls `Music.preview(nil)`. `onStart`
needs no change — `selectTrack(trackIdFor(seed, ...))` early-returns
when the seed lands on the auditioned track and `TimePosition` snaps to
the seeded `startBeat` regardless, so a matching pick costs zero rebuild
and PLAY just opens the lowpass. When the seed lands elsewhere, the
existing splice path handles it — honest behavior either way.

## 4. The picker has weight — spring cyclers

The cheap port (no new layout): every menu cycler runs through a
one-DOF spring. The arrow moves the *target*; the spring supplies the
overshoot — the `‹ name ›` label's x-offset and a slight scale dip are
all you need for the read.

```luau
-- One-DOF spring (MENU.md §4): pos/vel integrate toward target each
-- frame; a cycle moves the target, drag/wheel adds vel directly.
local function spring(pos: number, vel: number, target: number, dt: number): (number, number)
	local c = Config.Menu
	vel += (c.SpringStiff * (target - pos) - c.SpringDamp * vel) * dt
	return pos + vel * dt, vel
end
```

Wire it in the menu's frame tick (the same connection §2's `pulseMenu`
rides): each cycler keeps `{pos, vel, target}`; on `onTrackCycle(dir)`
set `target += dir` and let the spring overshoot ~`JacketPx` before
settling. MouseWheel over the row adds `vel` — flingable, like the
carousel.

The fuller port shipped: three procedural **track jackets**
(prev/current/next cards) riding the strip. No image assets (the
`gemIcon` rule) — each jacket is its SongMap drawn small: a
`TrackAccents` gradient face + one bar per `sections[i]` whose height
is `energy` and whose tint marks `kind` — the track's cover *is* its
intensity curve, the same read osu's star graph gives. Side cards sit
dimmed at `Jacket.SideDim`; the current card wears an accentA stroke
and a name plate. RANDOM draws a `?` card. A stat caption under the
strip reads `BPM · s · SECTIONS` ("the seed picks the song" for
RANDOM), and one wheel notch cycles one card.

```luau
-- Jacket face (MENU.md §4): SongMap.sections -> a strip of energy bars.
-- kind -> tint: intro/break = dim, build = cyan, drop = pink. The card
-- previews the run's shape the way a beatmap card previews its peaks.
local function jacketBars(parent: Instance, map: SongMap.Map)
	for i, sec in ipairs(map.sections) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.fromScale((i - 0.5) / #map.sections, 1)
		bar.Size = UDim2.new(0.7 / #map.sections, 0, 0.25 + 0.75 * sec.energy, 0)
		bar.BackgroundColor3 = if sec.kind == "drop" then C_PINK
			elseif sec.kind == "build" then C_CYAN
			else C_DIM
		bar.BorderSizePixel = 0
		bar.Parent = parent
	end
end
```

Bonus density (REA #6): under the jacket, `map.bpm` · `loopSeconds` ·
section count — the picker's stat line, one caption row.

## 5. Menu silence — the bed is the only voice

The menu plays NO sound effects: no hover tick, no click kick, nothing.
osu!'s percussion-menu was tried here (grid-snapped `Sfx.uiTick` —
first a hover hat + click kick, then click-only) and the verdict was
that under a quiet bed every chrome noise reads as *noise*, not
rhythm. The song is the menu's whole sound identity: the parked bed,
and the §3 audition swap when you browse TRACK. `Music.nextGridDelay`
stays — but as a gameplay instrument (the gem chime), not a UI one.

## 6. The room wears the pick — accents, not backdrops

Honest divergence, kept deliberately: osu! fades the picked map's art
behind the whole screen; §6's shop floor is opaque because a live scene
behind the merch buries it (and nothing live exists behind our menu —
`StreamingEnabled` is off, the lane is private). The read to steal is
*ambient identity*, not the mechanism: the pick should tint the room.

- The diorama window already does the heavy lift — browsing `world_*`
  re-seeds the preview's Backdrop scene. That's our "beatmap background,"
  framed on purpose.
- The cheap complement shipped: the poster's accent endpoints (horizon
  rule gradient ~0.65, BEST label ~0.5 toward accentA) lerp toward the
  picked track's two accent colors — `Config.Music.TrackAccents[id]`,
  a hand-tuned pair per track kept a clear step off `LethalColor`
  (SongMap files are generated, so accents live in Config, not on the
  map). RANDOM returns the brand cyan/pink.
- `Music.preview` (§3) is the audio half of the same read — the room
  sounds like the pick too.

## 7. The stamp — results land with weight

The crash-log card is right and stays; what's missing is the *landing*.
Osu's grade slams in — our equivalent is the hero score row + `★ NEW
BEST`, no letter grade (distance purity is §10's law; a rank letter
would invite comparison against the leaderboard's own authority).

```luau
-- Ui.showDeath tail (MENU.md §7): stamp the hero row — scale in past
-- 100% and settle with Back ease, while a duck makes it land ON the
-- tape-stop's floor. Same trick for the ★ NEW BEST tag when armed.
local stamp = TweenInfo.new(Config.Menu.StampSec, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
heroScale.Scale = 1.35
TweenService:Create(heroScale, stamp, { Scale = 1 }):Play()
Music.duck(0.3, 0.5)
```

## 8. Idle is never dead — menu scope strip [CUT]

Cut after shipping — the strip cluttered the poster; keep §2's pulse
only. Spec kept for reference if it ever returns.

`Music.spectrum()` hands out the WavePoints buffer every frame for free;
the HUD scope already paints it. The menu port is a second, thinner
scope under the horizon rule — reusing `setWave`'s exact discipline
(2px-quantized heights, per-seg cache, only repaint changed segs), so a
still menu costs nothing:

```luau
-- Ui.setWave already does this for the HUD scope; a menu strip is the
-- same loop over a second seg set, gated on self.menu.Visible. Share
-- the cache/env pattern — don't fork the logic, parameterize the segs.
```

Gate it on menu visibility and it's the poster's heartbeat monitor —
pairs with §2 so the chrome thumps (pulse) while the strip traces
(spectrum), exactly like osu!'s visualizer under the cookie.

## 9. Already osu!-shaped / deliberately skipped

**Already aligned** (the REA validates choices we shipped):

- **One filled hero** — PLAY is the only solid element on the screen;
  the cookie rule, before we'd read it.
- **R = instant retry** — osu's quick-retry loop; ours is even faster.
- **The garage RANDOM chip** — a slot-machine spin through owned items
  is F2's random-theater, already ported.
- **RECENT strip** — osu!'s recent-plays panel, already on the board rail.
- **Missions card always visible** — picker-screen info density (REA #6).

**Deliberately skipped**:

- **Pie/radial menu** — hides the garage rail behind a click; breaks
  the zero-clicks-to-merch conversion rule.
- **Blurred live-scene backdrop** — the opaque shop floor is a settled
  decision; §6 ports the *ambient identity* read instead.
- **Fuzzy search / grouping tabs** — ten tracks don't need a search box.
- **Letter grades on results** — competes with the leaderboard's
  authority; distance is the only score.
- **Chat panels / lobby chrome** — Roblox owns social; not our surface.

**Shipped since**: cursor parallax (`Config.Menu.ParallaxPx = 6`) —
the poster column drifts ±6px toward the cursor and the rails
counter-drift at half strength, quantized to whole px and gated on
`MouseEnabled` so touch never pays for it.

## 10. Tunables

```luau
-- Config.luau — new block. All menu-feel constants live here.
Config.Menu = {
	ChromePulse = 0.04, -- §2 poster swell per pulse unit
	SpringStiff = 170, -- §4 cycler spring stiffness
	SpringDamp = 22, -- §4 damping (~critically damped, small overshoot)
	SpringDtMax = 1 / 20, -- §4 frame dt cap — a hitch must not slingshot
	JacketPx = 40, -- §4 cycler overshoot amplitude in px
	Jacket = { W = 104, H = 58, Gap = 14, SideDim = 0.5 }, -- §4 cards
	-- §5: no UiTick block — the menu is deliberately SFX-free.
	StampSec = 0.25, -- §7 death-hero stamp duration
	StampKick = 1.35, -- §7 the hero slams in past 100%, then settles
	StampDuck = 0.3, -- §7 duck depth when the card lands
	StampDuckRelease = 0.5,
	-- §8 cut: no MenuSpec* — §2's pulse carries idle motion alone.
	ParallaxPx = 6, -- §9 poster drift toward cursor; 0 = off
}
```

Plus `Config.Music.TrackAccents[id] = { accentA, accentB }` per track
(§6) — the jacket face + poster accents' source pair.

**Status**: §3 audition, §2 chrome pulse, §4 springs + jackets + stat
line + wheel, §6 accents, §7 stamp, §9 parallax — shipped. §5
hitsounds and the §8 scope strip were built then deliberately cut
(menu silence reads better under the quiet bed).
