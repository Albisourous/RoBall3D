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
-- refills past RechargeGate. No brake — momentum flow is the identity.
Config.Boost = {
	Mult = 1.3, -- forward speed multiplier while boosting
	Capacity = 2.5, -- seconds of boost on a full meter
	RegenPerSec = 0.2, -- meter fraction refilled per second while off-boost
	RechargeGate = 0.35, -- emptied meter must refill this far to boost again
}

-- Steering is force/momentum based (Super Monkey Ball feel), not snapping.
Config.Steering = {
	MaxLateralSpeed = 26, -- studs/s
	LateralAccel = 90, -- studs/s^2
	IdleLateralDamping = 6, -- extra damping when no steer key held (kills drift)
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
-- by forward speed. Deliberately slow: nothing below StartSpeed, and the
-- slopes are shallow so blur only becomes obvious deep into endless mode.
Config.Blur = {
	StartSpeed = 55, -- s/s before any blur appears (early game stays crisp)
	BlurPerSpeed = 0.07, -- Blur.Size gained per s/s over StartSpeed
	MaxBlur = 12, -- Blur.Size ceiling (engine max is 24; 12 is a heavy smear)
	DofFarPerSpeed = 0.004, -- DoF FarIntensity gained per s/s over StartSpeed
	DofFarMax = 0.45,
	DofFocusDistance = 300, -- studs — visible track stays sharp, horizon blurs
}

Config.Death = {
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
	IntroLength = 150, -- scripted safe intro before RNG chunks begin
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

-- Difficulty tiers. Crossing `dist` (meters) activates the tier: speed
-- target rises, new chunk types join the pool, width range tightens.
-- `chunkPool` entries must exist in ChunkDefs.
Config.Tiers = {
	{ dist = 0, speed = 40, chunkPool = { "Flat", "Slalom" }, widthMin = 40, widthMax = 50 },
	{
		dist = 200,
		speed = 52,
		chunkPool = { "Flat", "Slalom", "Narrow", "BlockGate" },
		widthMin = 34,
		widthMax = 48,
	},
	{
		dist = 500,
		speed = 64,
		chunkPool = { "Flat", "Slalom", "Narrow", "Tilt", "Pinch", "BlockGate", "BlockField" },
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
		},
		widthMin = 20,
		widthMax = 38,
	},
	{
		dist = 1400,
		speed = 92,
		chunkPool = { "Narrow", "Tilt", "Pinch", "SplitGap", "Bowl", "RampGap", "BlockField", "WallSlot" },
		widthMin = 14,
		widthMax = 32,
	},
	{
		dist = 2000,
		speed = 106,
		chunkPool = { "Narrow", "Tilt", "Pinch", "SplitGap", "Bowl", "RampGap", "BlockField", "WallSlot" },
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
	-- Reserved gold: collectible, never lethal, and reads as the "sunset"
	-- accent against the magenta/cyan world.
	Color = Color3.fromRGB(255, 212, 64),
}

Config.Score = {
	PointsPerMeter = 1,
}

Config.GemSfx = {
	-- Gem pickup chime (SfxController): rapid pickups climb a pentatonic
	-- ladder so cluster lines play little runs. rbxasset:// fallback is a
	-- built-in Roblox ping — always resolvable if the asset fails to load.
	AssetId = 125591495745947, -- gem_pickup (roball3d-audio, newest import)
	FallbackId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.5,
	ComboWindow = 0.9, -- seconds between pickups that still count as a run
	ComboScale = { 0, 2, 4, 7, 9, 12, 14, 16 }, -- A-minor pentatonic semitones
	PitchJitter = 0.03, -- +-3% so repeats never sound identical
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
}

Config.Music = {
	Track = "vaporwave_loop", -- SongMap id the runtime + generator key on
	AssetId = 139067975647102, -- full mix (roball3d-audio, newest import)
	-- Layered mode (AUDIO.md §4): when EVERY stem id is non-zero the
	-- MusicController plays one AudioPlayer per stem and fades layers by
	-- tier instead of playing the single mix. Zeros => single-track mode.
	-- (Stems render to roball3d-audio/stems/ — upload, paste ids here.)
	Stems = { pad = 0, bass = 0, drums = 0, lead = 0, arp = 0, air = 0 },
	Volume = 0.5,
	-- Native BPM of the track — gem clusters are placed on this beat grid
	-- (beat interval = 60 / (BaseBpm * heard PlaybackSpeed), so pickups land
	-- on musical subdivisions at any pace). Must equal SongMap.bpm —
	-- vaporwave_loop is 16 bars = 43.6s => 88 BPM.
	BaseBpm = 88,
	PlaybackSpeedMin = 0.9,
	PlaybackSpeedMax = 1.35,
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
	-- Beat-quantized stings (AUDIO.md §6) — 0 = not uploaded yet.
	Stings = { tierUp = 0, deathFall = 0, menuStart = 0 },
	-- Speed wind bed (AUDIO.md §7): looped noise faded/filtered by speed.
	WindAssetId = 0,
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
		Slalom = "technical",
		Narrow = "technical",
		Tilt = "technical",
		Pinch = "technical",
		SplitGap = "technical",
		BlockGate = "lethal",
		BlockField = "lethal",
		WallSlot = "lethal",
		RampGap = "spectacle",
	},
	-- Phrase quantization (AUDIO.md §5.2): single-feature set pieces
	-- (WallSlot wall, RampGap apex) shift their t so the feature lands on
	-- the next accentBeat downbeat when it falls inside the chunk.
	QuantizeSetPieces = true,
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
}

Config.Leaderboard = {
	TopRunsStore = "RoBall3D_TopRuns_v1", -- OrderedDataStore: userId -> best score
	BestStore = "RoBall3D_Best_v1", -- DataStore: personal best + last seed
	TopCount = 20,
	SaveRetryCount = 3,
}

return Config
