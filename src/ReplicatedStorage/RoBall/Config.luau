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
	BaseWidth = 24, -- widest ribbon
	MinWidth = 4, -- narrowest allowed ribbon
	TrackThickness = 1, -- studs
	StartY = 50, -- deck height runs start at
	RowSpacing = 600, -- per-player run lanes are this far apart in X
}

-- Difficulty tiers. Crossing `dist` (meters) activates the tier: speed
-- target rises, new chunk types join the pool, width range tightens.
-- `chunkPool` entries must exist in ChunkDefs.
Config.Tiers = {
	{ dist = 0, speed = 40, chunkPool = { "Flat", "Slalom" }, widthMin = 20, widthMax = 26 },
	{ dist = 200, speed = 52, chunkPool = { "Flat", "Slalom", "Narrow" }, widthMin = 14, widthMax = 24 },
	{
		dist = 500,
		speed = 64,
		chunkPool = { "Flat", "Slalom", "Narrow", "Tilt", "Pinch" },
		widthMin = 10,
		widthMax = 22,
	},
	{
		dist = 900,
		speed = 78,
		chunkPool = { "Flat", "Slalom", "Narrow", "Tilt", "Pinch", "SplitGap", "Bowl" },
		widthMin = 8,
		widthMax = 20,
	},
	{
		dist = 1400,
		speed = 92,
		chunkPool = { "Narrow", "Tilt", "Pinch", "SplitGap", "Bowl", "RampGap" },
		widthMin = 6,
		widthMax = 16,
	},
	{
		dist = 2000,
		speed = 106,
		chunkPool = { "Narrow", "Tilt", "Pinch", "SplitGap", "Bowl", "RampGap" },
		widthMin = 4,
		widthMax = 12,
	},
}

Config.Gems = {
	-- Gems sit on risky lines: near edges, on beams, over gaps.
	-- Value scales with how dangerous the placement is.
	ValueSafe = 10,
	ValueEdge = 15,
	ValueBeam = 25,
	ValueGapArc = 40,
	ClustersPerChunkMin = 0,
	ClustersPerChunkMax = 3,
	ClusterSize = 3, -- gems per line cluster
	Spacing = 3, -- studs between gems in a cluster
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
