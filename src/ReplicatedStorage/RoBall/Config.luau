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
	Max = 110,
	-- Optional throttle: W speeds up slightly, S brakes. Gives players a
	-- way to "play it safe" at a score cost. Toggleable.
	ThrottleEnabled = true,
	ThrottleUp = 1.08,
	ThrottleDown = 0.85,
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

Config.Music = {
	-- Single synthwave loop; PlaybackSpeed ramps with ball speed.
	AssetId = 139067975647102, -- vaporwave_loop (roball3d-audio, newest import)
	Volume = 0.5,
	-- Native BPM of the track — gem clusters are placed on this beat grid
	-- (beat interval = 60 / (BaseBpm * heard PlaybackSpeed), so pickups land
	-- on musical subdivisions at any pace). vaporwave_loop is 16 bars =
	-- 43.6s => 88 BPM (the generate_audio.py tape-slow lands it at 88, not
	-- the script's stated 128 target — measure TimeLength, don't guess).
	BaseBpm = 88,
	PlaybackSpeedMin = 0.9,
	PlaybackSpeedMax = 1.35,
	DeathPitchFloor = 0.6, -- pitch slides to this on death
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
