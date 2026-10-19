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
	Offset = Vector3.new(0, 8, 14), -- behind + above the ball
	LookAhead = 10, -- studs ahead of the ball the camera aims at
	FovMin = 70,
	FovMax = 88, -- FOV widens with speed for sense of velocity
	SmoothTime = 0.12,
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
	Grade = 0.1, -- studs of drop per stud traveled — constant downhill (~5.7deg)
	RowSpacing = 600, -- per-player run lanes are this far apart in X
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
	ClusterSize = 3, -- gems per line cluster
	Spacing = 3, -- studs between gems in a cluster
	FloatY = 1.6, -- default hover height above the deck
	Size = 0.9, -- studs
	Color = Color3.fromRGB(0, 255, 240), -- reserved cyan: collectible, never lethal
}

Config.Score = {
	PointsPerMeter = 1,
}

Config.Music = {
	-- Single synthwave loop; PlaybackSpeed ramps with ball speed.
	AssetId = 0, -- TODO: pick/upload a synthwave track and set the asset id
	Volume = 0.5,
	PlaybackSpeedMin = 0.9,
	PlaybackSpeedMax = 1.35,
	DeathPitchFloor = 0.6, -- pitch slides to this on death
}

Config.Palette = {
	-- Vaporwave hue wheel, cycled by distance. Neon elements sample this.
	HueStops = { 320, 275, 230, 190, 320 }, -- magenta -> purple -> blue -> cyan -> magenta
	CycleDistance = 400, -- meters per full hue lap
	Saturation = 0.85,
	NeonValue = 1.0,
}

Config.Leaderboard = {
	TopRunsStore = "RoBall3D_TopRuns_v1", -- OrderedDataStore: userId -> best score
	BestStore = "RoBall3D_Best_v1", -- DataStore: personal best + last seed
	TopCount = 20,
	SaveRetryCount = 3,
}

return Config
