--!strict
-- RoBall3D master tuning table.
-- Every gameplay-feel number lives here. See DESIGN.md for the rationale
-- behind each value. Change a number here, playtest, iterate.

local Config = {}

Config.Ball = {
	Diameter = 3, -- studs
	Density = 0.7,
	Friction = 0.6,
	Elasticity = 0, -- we drive velocity directly; bounce comes from physics, not material
	-- Restitution is WEIGHTED between both contacting parts: without max
	-- weight the deck's default material (~0.5 elasticity) keeps landings
	-- springy. 100/101 ≈ zero — high pad arcs land dead, no rebound hop.
	ElasticityWeight = 100,
}

-- Forward speed is tier-driven: the generator moves the target up at each
-- milestone and the ball eases toward it at Accel.
Config.Speed = {
	Start = 40, -- studs/s
	Accel = 6, -- studs/s^2 ease toward tier target
	-- Reference speed for 0..1 normalization (FOV, music ramp, gem beat
	-- spacing) — those saturate at Max. Actual speed is UNCAPPED: past the
	-- last tier, Tiers.speedAt grows by EndlessRamp per meter forever.
	Max = 110,
	EndlessRamp = 0.012, -- studs/s gained per meter past the last tier (+12/km)
	-- Track keeps narrowing gently: widthMin/widthMax shrink by this per
	-- meter past the last tier, floored so lethal rows can always spawn —
	-- below ~12 studs gateRow/BlockField have no room and the run would go
	-- obstacle-free = EASIER. Speed is the difficulty driver, not width.
	EndlessWidthShrink = 0.002, -- studs per meter
	EndlessWidthMinFloor = 12, -- min gap (7) + rim margin (~5) fits a block row
	EndlessWidthMaxFloor = 18,
}

-- Boost (DESIGN.md §6): hold W/Up to push speed by Mult while a meter
-- drains; release to recharge. Emptying latches it out until the meter
-- refills past RechargeGate. Short meter = pick your moment. No brake —
-- momentum flow is the identity.
Config.Boost = {
	Mult = 1.5, -- forward speed multiplier while boosting — a real kick
	AccelMult = 4, -- ease rate x Accel while boosting: the BPM HUD visibly JUMPS
	Capacity = 1.2, -- seconds of boost on a full meter — spend it deliberately
	RegenPerSec = 0.225, -- meter fraction refilled per second off (~4.4s to full)
	RechargeGate = 0.35, -- emptied meter must refill this far to boost again
}

-- Dash (DESIGN.md §4): tap Q/E for a lateral burst — a flat slice of the
-- SAME meter boost/brake drain (offense/defense/dodge bid on one
-- resource). Discrete spend, not a held drain — but a burnt meter still
-- locks it, same latch as the held verbs.
Config.Dash = {
	Speed = 60, -- studs/s lateral target during the burst (~2.3x max steer)
	Time = 0.2, -- burst window — ~12 studs of sidestep before hand-back
	Accel = 1200, -- burst ease rate: reaches Speed in ~50ms, eases in like steering
	Cost = 0.3, -- meter fraction per dash (~4 LED cells, 3 dashes per full bar)
	Cooldown = 0.45, -- seconds between dashes (the meter is the real limiter)
}

-- Steering is force/momentum based (Super Monkey Ball feel), not snapping.
Config.Steering = {
	MaxLateralSpeed = 26, -- studs/s
	LateralAccel = 90, -- studs/s^2
	IdleLateralDamping = 6, -- extra damping when no steer key held (kills drift)
	SettleSeconds = 0.8, -- "rolling…" settle: steering locked this long after RunStarted (§6)
}

Config.Camera = {
	Offset = Vector3.new(0, 13, 12), -- behind + above; high + pitched = Slope's downhill read
	LookAhead = 16, -- studs ahead of the ball the camera aims at
	-- Aim drops with the track: target sits on the deck plane LookAhead
	-- studs out, so the camera pitches into the slope, not at the horizon.
	LookDrop = 1.5, -- extra studs below the deck plane (keeps track in frame)
	LeanMax = 3, -- degrees of camera roll toward the steer direction
	FovMin = 70,
	FovMax = 88, -- FOV widens with speed for sense of velocity
	SmoothTime = 0.12,
}

-- Speed blur (DESIGN.md §12): the world smears as the ball gets faster —
-- a BlurEffect plus the DepthOfField's far-field intensity, both driven
-- by forward speed. Power curve, not linear: Size = MaxBlur * t^Exponent
-- where t = (speed - StartSpeed)/(CurveTop - StartSpeed) clamped 0..1.
-- Exponent > 1 keeps everything under 100 s/s perfectly clear — blur is
-- strictly an endless-mode effect — then climbs hard: ~1.7 at 150, ~8 at
-- 200 — the deep-run wall reads as the world literally smearing.
Config.Blur = {
	StartSpeed = 100, -- s/s before any blur appears (0–100 stays razor sharp)
	CurveTop = 220, -- s/s where the curve saturates at MaxBlur
	Exponent = 2.2, -- >1 = progressively steeper
	MaxBlur = 12, -- Blur.Size ceiling (engine max is 24; 12 is a heavy smear)
	DofFarMax = 0.45,
	DofFocusDistance = 300, -- studs — visible track stays sharp, horizon blurs
}

Config.Death = {
	-- Kill plane (DESIGN.md §11): falling this far below the local deck
	-- height (yAt) is death — the plane descends with the track.
	KillDrop = 15, -- studs below deck = dead
	-- Stall watchdog (DESIGN.md §11): ball velocity is client-driven every
	-- frame, so a ball whose position stops changing is wedged in geometry —
	-- a dead run, not a live one. Killing it turns a silent freeze into a
	-- normal RUN OVER the player can instantly retry from.
	StallSeconds = 1.2, -- position frozen this long = dead
	StallGraceDist = 10, -- meters of travel before the watchdog arms (spawn settle)
}

Config.Generation = {
	TravelAxis = Vector3.new(0, 0, -1), -- runs go toward -Z
	ChunkMinLength = 30, -- studs
	ChunkMaxLength = 90,
	AheadDistance = 400, -- keep this much track generated ahead of the ball
	BehindDistance = 250, -- destroy chunks further than this behind the ball
	BaseWidth = 48, -- widest deck — Slope-style broad slope face (~16 ball widths)
	MinWidth = 4, -- narrowest allowed ribbon
	TrackThickness = 1, -- studs
	StartY = 50, -- deck height runs start at
	Grade = 0.16, -- studs of drop per stud traveled — constant downhill (~9deg)
	RowSpacing = 600, -- per-player run lanes are this far apart in X
	-- Deck crosses y=-500 around ~3.4km in (50 - Grade*dist); Roblox's default
	-- FallenPartsDestroyHeight is -500 and silently Destroy()s any unanchored
	-- part below it — the ball — leaving the run hung with a frozen HUD.
	-- -50k (engine minimum) buys ~310km of track before the void wins.
	FallenDestroyY = -50000,
}

-- Lethal geometry (DESIGN.md §2 REA): one reserved color, NEVER palette-shifted.
Config.LethalColor = Color3.fromRGB(255, 32, 48)

Config.Obstacles = {
	CorridorMin = 7, -- every lethal row must leave a gap at least this wide
	ReactionTime = 0.9, -- seconds between lethal rows at current tier speed
	BlockHeight = 6,
	BlockDepth = 4,
	WallHeight = 9, -- WallSlot slab height
	WallDepth = 2.5,
	-- Slope look: lethal blocks are near-black solids with a hot red edge
	-- outline (SelectionBox), not solid red fill.
	FaceColor = Color3.fromRGB(30, 4, 8),
	OutlineThickness = 0.09,
}

-- Feature ramp (DESIGN.md §8.6): new map mechanics debut one at a time.
-- The FIRST spawn of each type at/after its distance is a scripted gentle
-- variant (wide corridor, slow cycle, breadcrumb gems) that teaches the
-- read; afterwards the type joins the seeded pool at full difficulty.
-- A type only debuts inside a tier that lists it in chunkPool.
Config.Features = {
	Debut = {
		Terrace = 400,
		SnakeField = 800,
		Blackout = 900,
		Chicane = 1300,
		Fork = 1500,
		PadHop = 1700,
		PadVoid = 2100,
		TunnelSlot = 2200,
		DropGate = 2300,
		Pacer = 2700,
		Rotor = 2900,
		OrbHop = 3300, -- flag: Features.JumpOrbs
		FlipRide = 3500, -- flag: Features.GravityFlip
	},
	-- Explicit order — deterministic generation can't iterate a dict.
	DebutOrder = {
		"Terrace",
		"SnakeField",
		"Blackout",
		"Chicane",
		"Fork",
		"PadHop",
		"PadVoid",
		"TunnelSlot",
		"DropGate",
		"Pacer",
		"Rotor",
		"OrbHop",
		"FlipRide",
	},
	-- Stretch pillars (DESIGN.md §8.6): GD gravity flips and tap-jump orbs
	-- are designed but flag-off — they change core physics/controls.
	GravityFlip = false,
	JumpOrbs = false,
}

Config.Pads = {
	-- LaunchPad (DESIGN.md §8.3): cyan neon strip on the deck; touching it
	-- applies a one-shot vertical kick client-side — GD pads as terrain,
	-- not a jump button. The generator computes kickY so the arc always
	-- clears the hazard at the current tier speed.
	Width = 6, -- studs across
	DebutWidth = 11, -- debut pad is nearly unmissable
	Length = 4, -- studs along travel
	StripH = 2.5, -- lethal strip height the PadHop arc must clear
	StripMin = 5,
	StripMax = 10,
	ArcMargin = 1.6, -- studs of clearance above the strip the arc must keep
	-- Entry-speed honesty: pad chunks must be clearable at the SLOWEST
	-- survivable entry, not the nominal tier speed. Full-brake sets the
	-- sustained floor at 1/Boost.Mult ≈ 0.67x nominal — size a notch below
	-- it so a braked (or mid-flight braking) ball never meets an
	-- impossible arc. PadHop's upper bound is Boost.Mult itself.
	SlowCrossFrac = 0.55, -- PadHop's strip clearance covers entries down to this fraction of tier speed
	VoidAirFrac = 0.55, -- PadVoid gap = this fraction of pad airtime * speed (< brake floor)
	Color = Color3.fromRGB(0, 230, 255),
}

Config.Movers = {
	-- Beat-locked hazards (DESIGN.md §8.3): periods are whole-note values
	-- of the heard tempo, so the movement cycle IS the music — GD's
	-- "the level dances", deterministic under the seed's beat clock.
	PacerBeats = 8, -- slide cycle length in beats (debut runs it double)
	PacerRimMargin = 2, -- sliding gap never closes nearer than this to a rim
	RotorBeats = 6, -- full sweep period in beats (debut runs it 1.5x)
	RotorArmFrac = 1.15, -- arm half-length vs half deck width (pre-clamp)
	RotorPostFrac = 0.4, -- post sits this fraction of halfW toward one edge
	RotorArmH = 1.4, -- arm bar height — sweeps the ball's lower half
	RotorPostH = 5,
}

Config.Tunnel = {
	RoofH = 8, -- studs of headroom inside TunnelSlot
	ToothMin = 2, -- decorative ceiling teeth…
	ToothMax = 3.5, -- …bottom stays >4.5 above deck: lethal, unreachable
}

Config.Blackout = {
	-- Break-section darkness: grid/center neon dims to this fraction while
	-- edge rails and gems stay lit — the track goes lights-out, not blind.
	GridScale = 0.12,
}

Config.Orbs = {
	-- JumpOrbs stretch (DESIGN.md §8.6, flag-off): lime rings floating over
	-- voids. A jump input while inside Radius re-kicks vY — the tap extends
	-- the pad arc across gaps the pad alone can't clear (orb-or-die).
	Radius = 6, -- tap window (studs)
	Color = Color3.fromRGB(80, 255, 120),
	KickH = 5, -- studs of apex the orb re-kick buys back
}

Config.Flip = {
	-- GravityFlip stretch (DESIGN.md §8.6, flag-off): portal-framed zones
	-- where the client holds vY=+Lift, pressing the ball to a ceiling
	-- ribbon; steering mirrors, gravity resumes at the zone's end.
	ClearH = 11, -- ceiling ride height above the deck
	Lift = 55, -- held vY while flipped (studs/s up)
}

-- Difficulty tiers. Crossing `dist` (meters) activates the tier: speed
-- target rises, new chunk types join the pool, width range tightens.
-- `chunkPool` entries must exist in ChunkDefs.
Config.Tiers = {
	{ dist = 0, speed = 40, chunkPool = { "Flat", "Slalom" }, widthMin = 40, widthMax = 50 },
	{
		dist = 200,
		speed = 52,
		chunkPool = { "Flat", "Slalom", "Narrow", "BlockGate", "Terrace" },
		widthMin = 34,
		widthMax = 48,
	},
	{
		dist = 500,
		speed = 64,
		chunkPool = {
			"Flat",
			"Slalom",
			"Narrow",
			"Tilt",
			"Pinch",
			"BlockGate",
			"BlockField",
			"Terrace",
			"SnakeField",
			"Blackout",
		},
		widthMin = 26,
		widthMax = 44,
	},
	{
		dist = 900,
		speed = 78,
		chunkPool = {
			"Flat",
			"Slalom",
			"Narrow",
			"Tilt",
			"Pinch",
			"SplitGap",
			"Bowl",
			"BlockGate",
			"BlockField",
			"WallSlot",
			"Terrace",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
		},
		widthMin = 20,
		widthMax = 38,
	},
	{
		dist = 1400,
		speed = 92,
		chunkPool = {
			"Narrow",
			"Tilt",
			"Pinch",
			"SplitGap",
			"Bowl",
			"RampGap",
			"BlockField",
			"WallSlot",
			"Terrace",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
			"PadVoid",
			"TunnelSlot",
			"DropGate",
		},
		widthMin = 14,
		widthMax = 32,
	},
	{
		dist = 2000,
		speed = 106,
		chunkPool = {
			"Narrow",
			"Tilt",
			"Pinch",
			"SplitGap",
			"Bowl",
			"RampGap",
			"BlockField",
			"WallSlot",
			"Terrace",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
			"PadVoid",
			"TunnelSlot",
			"DropGate",
			"Pacer",
			"Rotor",
			-- Flag-off stretches (§8.6): canRun drops them unless the
			-- Features flags are on, so they sit inert in the pool.
			"OrbHop",
			"FlipRide",
		},
		widthMin = 10,
		widthMax = 26,
	},
}

Config.Gems = {
	-- Gems sit on risky lines: near edges, on beams, over gaps, through
	-- obstacle corridors. Value scales with how dangerous the placement is.
	ValueSafe = 10,
	ValueEdge = 15,
	ValueBeam = 25,
	ValueGapArc = 40,
	ClustersPerChunkMin = 0,
	ClustersPerChunkMax = 3,
	-- Rhythmic clusters: pickups land on heard-beat subdivisions. Cluster
	-- sizes are note groupings — 8 = sixteenths, 4 = eighths, 2 = quarters,
	-- 1 = accent — and spacing scales with ball speed so the pickup
	-- INTERVAL is a constant note value no matter the pace (the music's
	-- PlaybackSpeed ramps with the same speed curve). See ChunkDefs'
	-- beatSpacing/rollRhythm/gemRhythmLine.
	ClusterSizes = { 8, 4, 2, 1 },
	ClusterWeights = { 1.5, 4, 3, 2 }, -- big runs are treats, pairs are bread
	FloatY = 1.6, -- default hover height above the deck
	Size = 1.0, -- studs (cube side; corner-balanced so the diamond reads ~1.7 tall)
	-- Beat pulse (AUDIO.md §8): gems swell by this fraction on every beat,
	-- decaying over the beat; downbeats hit ~30% harder (BeatPulse client).
	BeatPulse = 0.22,
	BeatPulseRadius = 140, -- studs from camera — farther gems skip the pulse
	-- Reserved gold: collectible, never lethal, and reads as the "sunset"
	-- accent against the magenta/cyan world.
	Color = Color3.fromRGB(255, 212, 64),
}

Config.Score = {
	PointsPerMeter = 1,
	-- PB ghost (DESIGN.md §11): a translucent "BEST n" gate floats on the
	-- deck at your record's end distance — you race your own shadow.
	PbMarkerMinDist = 150, -- meters — don't bother marking stub runs
}

Config.GemSfx = {
	-- Gem pickup chime (SfxController): rapid pickups climb a pentatonic
	-- ladder so cluster lines play little runs. rbxasset:// fallback is a
	-- built-in Roblox ping — always resolvable if the asset fails to load.
	-- Numeric id for production OR an rbxasset:// ContentId URI resolving
	-- Studio's bundled content dir for local dev (the vaporwave-bell render).
	AssetId = 88208694516408, -- uploaded rb3_gem_pickup (vaporwave bell cascade)
	FallbackId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.25, -- half of the original — the chime was drowning the mix
	ComboWindow = 0.9, -- seconds between pickups that still count as a run
	ComboScale = { 0, 2, 4, 7, 9, 12, 14, 16 }, -- A-minor pentatonic semitones
	PitchJitter = 0.03, -- +-3% so repeats never sound identical
	-- Ear candy (AUDIO.md §6): a combo isn't a flat ladder climb — pickups
	-- climb the section's chord-tone scale, WRAPPING into the next octave
	-- rather than stalling on the top rung, and every CadenceEvery-th pickup
	-- resolves to the root one octave up, so a run of gems plays an
	-- arpeggio that lands on its octave — a little phrase, not a siren.
	-- Past two octaves the phrase folds back down (keeps pitches sweet).
	CadenceEvery = 4,
	MaxOctaves = 2,
	-- Harmony gloss: from the 2nd pickup of a combo on, a quiet perfect
	-- fifth rides under the melody note — consonant against any chord tone
	-- and instantly thicker. Shares the melody's jitter so it stays in tune.
	HarmonySemi = 7,
	HarmonyVolume = 0.35,
	-- Combos swell slightly louder as they run — a run of pickups should
	-- feel like it's BUILDING, capped so it never overpowers the mix.
	ComboVolGain = 0.04,
	ComboVolCap = 1.35,
	-- Grid-snap + sidechain (AUDIO.md §6): chimes nudge onto the next
	-- QuantizeSubdiv-of-a-beat (8 = 32nd note) so pickup phrases land dead
	-- on the tempo, never more than QuantizeCap seconds late. DuckDepth
	-- knocks the whole bus down and it blooms back over DuckRelease —
	-- the chime punches the track instead of stacking on it.
	QuantizeSubdiv = 8,
	QuantizeCap = 0.09,
	DuckDepth = 0.16,
	DuckRelease = 0.24,
}

Config.GemFx = {
	-- Pickup flourish (GemFx.luau): ghost diamond pop + sparkle burst + ring
	-- flash, client-local. All gold — reuses Gems.Color.
	SparkleCount = 14,
	SparkleSpeed = 16, -- studs/s outward
	SparkleLife = 0.5, -- max particle seconds
	PopRise = 4, -- studs the ghost gem climbs
	PopScale = 1.6, -- overshoot multiplier before it fades
	PopSpin = 170, -- degrees of tumble while rising
	PopTime = 0.42,
	RingSize = 8, -- final ring diameter in studs
	RingTime = 0.32,
	-- "+N" score float that rises off the pickup
	PopupRise = 3, -- studs the popup climbs
	PopupTime = 0.7,
	PopupSize = 15, -- text px
}

Config.Music = {
	-- Seeded track rotation (AUDIO.md §3): each run picks
	-- SongMap.trackIdFor(seed, Tracklist); GenCore and MusicController share
	-- the pick so stamped sections match the heard track. Per-track charts
	-- live in SongMap_<id>.luau.
	Tracklist = { "vaporwave_loop", "neon_descent", "retro_wave" },
	-- Per-track assets. AssetId = the full mix; numeric rbxassetid for
	-- production or an rbxasset:// ContentId URI resolving to Studio's
	-- bundled content dir for local dev. Stems: when EVERY entry resolves,
	-- the MusicController plays one AudioPlayer per stem and fades layers by
	-- tier (Layers); any stem failing to load drops the whole set back to
	-- that track's AssetId (watchdog). Upload roball3d-audio/tracks/<id>/
	-- oggs and paste numeric ids for production.
	TrackAssets = {
		vaporwave_loop = {
			AssetId = 136262831381200, -- uploaded rb3_vaporwave_loop master mix
			Stems = {
				pad = 118520566152626,
				bass = 102804260133040,
				drums = 132587284358057,
				lead = 132021034108931,
				arp = 101051387972789,
				air = 111219469183234,
			},
		},
		neon_descent = {
			AssetId = 127402293202751,
			Stems = {
				pad = 78035449894734,
				bass = 91799845866937,
				drums = 107672990378953,
				lead = 96130309464152,
				arp = 140482450562711,
				air = 91780468186207,
			},
		},
		retro_wave = {
			AssetId = 75972822769617,
			Stems = {
				pad = 135018068369330,
				bass = 73515253694480,
				drums = 81406148991075,
				lead = 106969072375083,
				arp = 93498334151618,
				air = 111078014754337,
			},
		},
	},
	Volume = 0.5,
	-- Default track tempo — the fallback beat grid for code paths without a
	-- run map (beat interval = 60 / (bpm * heard PlaybackSpeed)). Must equal
	-- the default track's SongMap.bpm — vaporwave_loop is 16 bars = 43.6s
	-- => 88 BPM. Per-run lookups use the run map's own bpm (neon_descent
	-- is 100 BPM), this is only the non-run default.
	BaseBpm = 88,
	PlaybackSpeedMin = 0.9,
	PlaybackSpeedMax = 1.35,
	-- Speed IS the tempo (AUDIO.md §4): heard BPM = map.bpm * PlaybackSpeed
	-- and norm rides ball speed, so the song literally accelerates with the
	-- ball. Past norm 1 (endless speed is uncapped) tempo keeps climbing at
	-- this rate per unit of over-norm, floored at PlaybackSpeedCeil.
	PlaybackSpeedEndless = 0.12,
	PlaybackSpeedCeil = 1.6,
	-- TempoStepSt snaps the heard tempo to N-semitone steps — speed-ups
	-- land on real pitch intervals (a GD-style key lift, not tape warble)
	-- and each step glides in over TempoStepGlide seconds. 0 = continuous.
	TempoStepSt = 1,
	TempoStepGlide = 0.3,
	DeathPitchFloor = 0.6, -- pitch slides to this on death
	-- AudioPitchShifter compensation (AUDIO.md §4): Pitch = ps^-k.
	-- 0 = full chipmunk ramp (pitch+tempo coupled), 1 = pitch-locked while
	-- tempo climbs. 0.5 halves the squeak, keeps the urgency.
	PitchCompensation = 0.5,
	-- Layer fades ride the beat grid: a tier's mix change completes over
	-- this many bars, landing on bar lines not mid-phrase.
	FadeBars = 2,
	SyncDriftMs = 40, -- stem watchdog: snap followers beyond this drift
	-- Tier layer mix (AUDIO.md §5.1): fader target per stem per tier index.
	Layers = {
		pad = { 1, 1, 1, 1, 1, 1 },
		air = { 1, 1, 1, 1, 1, 1 },
		bass = { 0.7, 1, 1, 1, 1, 1 },
		drums = { 0, 0.6, 0.85, 1, 1, 1 },
		arp = { 0, 0, 0.6, 1, 1, 1 },
		lead = { 0, 0, 0, 0.7, 1, 1 },
	},
	-- Scene scoring (AUDIO.md §7): menu runs the same track muffled under a
	-- lowpass; death sweeps it shut with the pitch slide.
	MenuCutoffHz = 1800,
	MenuVolume = 0.35,
	OpenCutoffHz = 18000,
	DeathCutoffHz = 700,
	FilterSweepTime = 0.5,
	-- Beat-quantized stings (AUDIO.md §6) — same id-or-URI rule as Stems;
	-- these dev paths resolve in Studio, upload for production.
	Stings = {
		tierUp = 94736885697655,
		deathFall = 88260413971234,
		menuStart = 135814836741193,
	},
	-- Speed wind bed (AUDIO.md §7): looped noise faded/filtered by speed.
	WindAssetId = 89232863140759,
	WindVolume = 0.4,
	WindCutMin = 500,
	WindCutMax = 4200,
}

-- Songform sync (AUDIO.md §5.2): the generator weights chunk families by
-- the music section under the ball. Selection bias ONLY — every legality
-- rule in DESIGN.md §8.1 still gates what may spawn.
Config.MusicSync = {
	Enabled = true,
	-- Chunk family -> weight lerp across section energy (lo = break feel,
	-- hi = drop feel). e=0 favors breathers, e=1 favors lethal/spectacle.
	Families = {
		breather = { lo = 1.6, hi = 0.3 },
		technical = { lo = 0.7, hi = 1.3 },
		lethal = { lo = 0.3, hi = 2.0 },
		spectacle = { lo = 0.6, hi = 2.5 },
	},
	ChunkFamily = {
		Flat = "breather",
		Bowl = "breather",
		Blackout = "breather",
		Terrace = "technical",
		Slalom = "technical",
		Narrow = "technical",
		Tilt = "technical",
		Pinch = "technical",
		SplitGap = "technical",
		Fork = "technical",
		BlockGate = "lethal",
		BlockField = "lethal",
		WallSlot = "lethal",
		SnakeField = "lethal",
		Chicane = "lethal",
		TunnelSlot = "lethal",
		DropGate = "lethal",
		Pacer = "lethal",
		RampGap = "spectacle",
		PadHop = "spectacle",
		PadVoid = "spectacle",
		Rotor = "spectacle",
	},
	-- Phrase quantization (AUDIO.md §5.2): single-feature set pieces
	-- (WallSlot wall, RampGap apex) shift their t so the feature lands on
	-- the next accentBeat downbeat when it falls inside the chunk.
	QuantizeSetPieces = true,
	-- Seeded start (AUDIO.md §6): each run opens the track on a seed-picked
	-- accentBeat instead of always bar 0; GenCore's beat clock starts there
	-- so stamped sections match the heard audio.
	SeededStartOffset = true,
	-- Drop sections may roll one subdivision denser; breaks cap at
	-- quarter-note clusters (ChunkDefs.rollRhythm).
	DropDenseGems = true,
}

Config.Palette = {
	-- Vaporwave hue wheel, cycled by distance. Neon elements sample this.
	-- The wheel laps magenta -> violet -> blue -> cyan -> magenta — always
	-- the synthwave family, never red (red is reserved for lethal geometry).
	HueStops = { 315, 275, 225, 185, 315 }, -- magenta -> violet -> blue -> cyan -> magenta
	CycleDistance = 800, -- meters per full hue lap — slow drift, real vaporwave flow
	Saturation = 0.95,
	NeonValue = 1.0,
}

-- Presentation (DESIGN.md §12). All decorative — zero gameplay effect.
Config.Art = {
	-- Retro-futuristic city canyon (vaporwave look): rows of dark towers
	-- outlined in palette neon, flanking the track on both sides, recycled
	-- for parallax.
	CityRows = 2, -- depth layers per side
	CityMinX = 55, -- innermost lateral offset from lane center
	CityRowDX = 100, -- extra offset per row
	CitySpacing = 125, -- z spacing between towers in a row
	CitySpan = 1000, -- z window; towers leaving the tail wrap forward
	CityMinH = 40,
	CityMaxH = 220,
	CityMinW = 26,
	CityMaxW = 70,
	CityMinD = 30,
	CityMaxD = 90,
	CitySegsMax = 3, -- stacked block segments per tower (1..SegsMax)
	CityValue = 0.7, -- palette value scale for tower outlines
	CityFaceValue = 0.10, -- near-black face fill
	LineThickness = 0.12, -- SelectionBox edge thickness
	-- NEON PEAKS world theme (§18): seeded wireframe ridge field replacing
	-- the towers — a displaced grid mesh, neon edges over near-black
	-- facets, rising straight out of the void beside the deck. Heights are
	-- a pure function of (world-z lattice row, column) so recycled tiles
	-- meet in perfect seams; the strip hugs the deck's downhill grade.
	PeaksInnerX = 55, -- lateral offset of the ridge's inner skirt (deck
	-- edge max ~39 = half-width 25 + slalom 14 — always clear)
	PeaksCols = 7, -- grid quads across the strip per side
	PeaksCellX = 26, -- studs per column
	PeaksRows = 10, -- grid quads along z per tile
	PeaksCellZ = 70, -- studs per row
	PeaksTiles = 2, -- tiles per side covering the visible window
	PeaksMaxH = 170, -- ridge amplitude at the outermost column
	PeaksRampPow = 0.85, -- lateral ramp exponent (0 at road edge = valley)
	PeaksFreqX = 0.16, -- ridged-noise frequency per column step
	PeaksFreqZ = 0.055, -- ridged-noise frequency per lattice row
	PeaksEnvF = 0.012, -- range-swell frequency per lattice row (passes)
	PeaksSeed = 71, -- math.noise seed — terrain identity is world-fixed
	PeaksSkirt = 9, -- ridge base sinks this far below the deck plane
	PeaksLine = 0.45, -- wireframe edge thickness (Neon parts)
	PeaksValue = 0.85, -- palette value scale for edges
	PeaksFaceTint = 0.09, -- facet drift toward palette (DeckTint cousin)
	-- Synthwave sun: a striped neon disk parked far down the slope, riding
	-- the descent so it always hangs on the horizon. Built from horizontal
	-- strips (orange -> magenta) with gaps that widen toward the bottom.
	SunDist = 380, -- studs ahead; close enough that atmosphere doesn't fade it
	SunRadius = 90,
	SunLift = 58, -- studs above the ball — puts ~2/3 of the disk in the
	-- frame's upper band against the camera's downward pitch
	SunStrips = 11,
	SunDepth = 3, -- strip thickness along z
	SunTopColor = Color3.fromRGB(255, 176, 64), -- hot orange crown
	SunBottomColor = Color3.fromRGB(255, 46, 160), -- magenta base
	SunMinStripH = 0.5, -- thinnest strips at the bottom (classic fade)
	SunMaxStripH = 3.2, -- tallest strips near the top
	-- Ball wireframe: axial rings cyan, diagonals magenta.
	RingA = Color3.fromRGB(0, 230, 255),
	RingB = Color3.fromRGB(255, 64, 190),
	-- Ball dressing: fading trail (no point light — glow smears the
	-- wireframe under bloom).
	TrailLifetime = 0.4,
	-- Floor readability: neon grid lines across the deck every GridEvery
	-- studs — sells the wireframe grid floor AND improves depth perception.
	-- Longitudinal neon (edge rails, center line) is also emitted in
	-- GridEvery-length pieces so each piece samples the palette at its own
	-- distance — the color flows continuously instead of banding per chunk.
	GridEvery = 10,
	GridValue = 0.5, -- palette value scale for grid lines (dimmer than edges)
	-- Deck tint: how far the purple-black floor leans toward the palette at
	-- each point (0 = static black, 1 = full neon). Subtle — keeps the deck
	-- dark while letting it drift with the gradient.
	DeckTint = 0.14,
	-- Audio-reactive bloom (AUDIO.md §8): Lighting bloom rides the
	-- analyzer pulse — kicks punch the whole frame a little brighter.
	-- BloomBase is only the fallback when the place has no BloomEffect.
	BloomBase = 0.45,
	BloomPulseGain = 0.2, -- kicks nudge the frame, they don't blow it out
}

Config.Leaderboard = {
	TopRunsStore = "RoBall3D_TopRuns_v1", -- OrderedDataStore: userId -> best score
	BestStore = "RoBall3D_Best_v1", -- DataStore: personal best + last seed
	ProfileStore = "RoBall3D_Profile_v1", -- DataStore: equipped cosmetic ids (§18)
	TopCount = 20,
	SaveRetryCount = 3,
	CacheSeconds = 45, -- server-side top-board cache: menu fetches share it
	FetchCooldown = 8, -- per-player GetLeaderboard throttle -> cached rows
}

-- Monetization (DESIGN.md §18). Bundle gamepasses grant themed item sets
-- from Cosmetics.luau; the gem bank is the grind path — pickups credit
-- BankPerGem each (2x pass doubles it) and spend on per-item gemPrice
-- records in the catalog. Banked currency is NEVER score: the leaderboard
-- stays clean, the shop stays funded. Pass/product ids are created on the
-- Creator Dashboard — 0 = not created yet; the garage shows SOON and
-- everything else still works (same stub pattern as Music.Stems). Price
-- fields are display fallbacks; the shop prefers live GetProductInfo
-- PriceInRobux when the pass/product exists.
Config.Monetization = {
	-- TEMP test mode: every pack/product grants instantly on click — no
	-- dashboard ids, no purchase prompts, and OWNED/bank behave exactly
	-- like the real grants. Flip false (or remove) when real ids land.
	FreeForTesting = true,
	Passes = {
		starter = 0, -- STARTER NEON — solar skin + sunset trail + sunset pop (~49)
		synthwave = 0, -- SYNTHWAVE — full prism set, rainbow fx (~149)
		midas = 0, -- MIDAS — full gold set (~149)
		vip = 0, -- VOID VIP — violet set + pulse skin (~199)
		bank2x = 0, -- 2X BANK — every pickup banks double, forever (~99)
		peaks = 0, -- NEON PEAKS — wireframe ridge world theme (~149)
	},
	Price = { starter = 49, synthwave = 149, midas = 149, vip = 199, bank2x = 99, peaks = 149 },
	-- Gem bank (§18 P2): each pickup banks this many gems, credited live.
	BankPerGem = 1,
	BankDoubleMult = 2, -- bank2x pass multiplier
	-- Gem pack dev products: id 0 = not created yet -> SOON. ProductGems is
	-- the grant the server applies in ProcessReceipt; ProductPrice is only
	-- the fallback label until GetProductInfo answers.
	Products = {
		pouch = 0, -- ◊300 top-up (~49)
		cache = 0, -- ◊800 mid pack (~99)
		vault = 0, -- ◊2000 whale pack (~199)
	},
	ProductGems = { pouch = 300, cache = 800, vault = 2000 },
	ProductPrice = { pouch = 49, cache = 99, vault = 199 },
	ProductOrder = { "pouch", "cache", "vault" }, -- garage button order
}

Config.Debug = {
	-- GenVerify solvability sweep (DESIGN.md §8.6): Studio-only audit that
	-- walks seeds asserting corridor/reaction/ballistic invariants on every
	-- generated chunk. 0 seeds = off (production playtests stay clean).
	VerifySeeds = 0,
	VerifyChunks = 600,
}

return Config
