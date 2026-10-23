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

-- Forward speed is a logarithmic curve (DESIGN.md §9): the whole ramp is
--   speed(d) = Start + LogGain * ln(1 + d / LogDist)              d <= LinearKnee
--            = curve(LinearKnee) + TailGain * (d - LinearKnee)   d >  LinearKnee
-- fit through the old tier milestones (~63@500m, 78@900m, 92@1400m,
-- 105@2000m), so early game is gentler — then a LINEAR endless tail:
-- the log flattens to a felt ceiling in deep runs, the tail doesn't.
-- There is no speed cap: every kilometer past the knee adds ~TailGain*1000
-- studs/s. TrackStreamer keeps AheadSeconds of boosted-pace track built
-- and the client's swept-floor catch re-seats solver tunneling, so the
-- run survives the tail instead of falling into ungenerated void.
Config.Speed = {
	Start = 34, -- studs/s — a shade under the old 40 opener: learnable, not boring
	Accel = 6, -- studs/s^2 ease toward the curve target
	LogGain = 49.3, -- curve slope (studs/s per log unit)
	LogDist = 625, -- characteristic distance, meters — d/D inside ln(1+x)
	LinearKnee = 2000, -- meters where the log curve hands off to the linear tail
	TailGain = 0.03, -- studs/s gained per meter past the knee (+30/km)
	-- Reference speed for 0..1 normalization (FOV, music ramp, gem beat
	-- spacing) — those saturate at Max. Actual speed is UNCAPPED: the log
	-- curve keeps growing (slowly) forever.
	Max = 110,
	-- Past the last tier the width FLOOR keeps tightening by this per
	-- meter, floored so lethal rows can always spawn — below ~12 studs
	-- gateRow/BlockField have no room and the run would go obstacle-free
	-- = EASIER. widthMax never shrinks: the deck can always reopen to
	-- full width, so late game variance is the whole [floor, 50] window.
	EndlessWidthShrink = 0.002, -- studs per meter
	EndlessWidthMinFloor = 12, -- min gap (7) + rim margin (~5) fits a block row
}

-- Power meter (DESIGN.md §4): one resource bar for all three verbs —
-- W/Up boost (×Mult speed), S/Down brake (÷Mult), Q/E dash (flat slice
-- per burst). Held verbs drain it; release to recharge; emptying latches
-- ALL verbs out until the meter refills past RechargeGate — the gold
-- notch on the bar is the universal "armed" read.
Config.Power = {
	Mult = 1.5, -- forward speed multiplier while boosting — a real kick
	AccelMult = 4, -- ease rate x Accel while boosting: the BPM HUD visibly JUMPS
	Capacity = 1.2, -- seconds a full meter drains under a held verb
	RegenPerSec = 0.1, -- meter fraction refilled per second off (~10s to full)
	RechargeGate = 0.35, -- emptied meter must refill this far to act again — the marker
	-- Gem income (§10): pickups refund meter by point value — riskier
	-- lines recharge faster. Per point: safe 10→3%, edge 15→4.5%, beam
	-- 25→7.5%, gap-arc/hoop 40/25→12%/7.5%. ~330 pts fills a bar alone —
	-- with the slower regen, gem lines ARE the recharge path.
	GemPerPoint = 0.003,
}

-- Dash (DESIGN.md §4): tap Q/E for a lateral burst — a flat slice of the
-- power meter (offense/defense/dodge bid on one resource). Discrete
-- spend, not a held drain, but it still needs a meter past the marker.
Config.Dash = {
	Speed = 64, -- studs/s lateral target during the burst (~2.4x max steer)
	Time = 0.16, -- burst window — ~10 studs of sidestep before hand-back
	Accel = 2400, -- burst ease rate: reaches Speed in ~25ms, snaps in fast
	Cost = 0.3, -- flat meter slice per burst (~4 of the bar's 14 LED cells)
	Cooldown = 0.35, -- seconds between dashes (the meter is the real limiter)
	BufferWindow = 0.4, -- a press mid-burst/on cooldown stays armed this long — chains snap
	-- Dash style (§4): a saved menu toggle picks the input mapping —
	-- "keys" (Q/E) or "tap" (double-tap the steer key).
	-- Mirrored as RoBallDashMode; persisted in the profile like a mixer gain.
	Modes = { "keys", "tap" },
	TapWindow = 0.28, -- seconds between steer-key taps that read as a dash
	ModeLabel = { keys = "‹ Q / E KEYS ›", tap = "‹ DOUBLE-TAP A / D ›" },
	ModeHint = { keys = "Q/E dash", tap = "A·A / D·D dash" },
}

-- Steering is force/momentum based (Super Monkey Ball feel), not snapping.
Config.Steering = {
	MaxLateralSpeed = 26, -- studs/s
	LateralAccel = 90, -- studs/s^2
	IdleLateralDamping = 6, -- extra damping when no steer key held (kills drift)
	BankPull = 45, -- downhill drift speed at sin(bank)=1 — a banked deck
	-- shoves the ball toward its low edge (Sway/Tilt); counter-steer wins
	-- on moderate banks but pays most of MaxLateralSpeed, and ~42° caps
	-- nearly out-pull steering — hold uphill or slide off
	SettleSeconds = 0.8, -- "rolling…" settle: steering locked this long after RunStarted (§6)
	-- Unstick hop (§11): grounded + real forward speed under 15% of target
	-- for UnstickTime = wedged on a seam lip — pop one Y impulse to clear it.
	UnstickTime = 0.35, -- seconds of wedge before the hop fires
	UnstickHop = 11, -- Y impulse studs/s, held ~0.14s
	UnstickCooldown = 1.0, -- refractory; true pockets fall to StallSeconds
	UnstickMaxY = 15, -- |vY| under this = grounded; resting slope reads ~7
}

-- Touch + gamepad inputs (§4): the keyboard map stays canonical — these
-- map onto the same steer/boost/brake/dash intents, never new physics.
Config.Controls = {
	PadDeadzone = 0.18, -- gamepad thumbstick |x| under this reads 0
	PadTravelPx = 90, -- touch drag distance for full-lock steer
	PadTapPx = 14, -- release under this travel counts as a tap (dash pair)
	ZoneW = 0.44, -- touch steer zone: left screen fraction, bottom-anchored
	ZoneH = 0.62, -- …and height fraction from the bottom edge up
	-- Gamepad rumble (§4): Large = the low thump, Small = the zip. Every
	-- entry is {large, small, seconds}; 0/0 entries still pulse Small so
	-- a denied tap reads in the hand, not just the ear.
	Rumble = {
		Enabled = true,
		Dash = { 0.15, 0.45, 0.14 }, -- burst fires — a high zing, not a thud
		Denied = { 0, 0.12, 0.10 }, -- latched-out tap — a faint click
		Death = { 0.95, 0.8, 0.5 }, -- the wreck — the only big shake
	},
}

Config.Camera = {
	Offset = Vector3.new(0, 13, 12), -- behind + above; high + pitched = Slope's downhill read
	LookAhead = 16, -- studs ahead of the ball the camera aims at
	-- Aim drops with the track: target sits on the deck plane LookAhead
	-- studs out, so the camera pitches into the slope, not at the horizon.
	LookDrop = 1.5, -- extra studs below the deck plane (keeps track in frame)
	LeanMax = 3, -- degrees of camera roll toward the steer direction
	BankLean = 0.5, -- fraction of the deck's bank the horizon follows —
	-- the tilt read: on a 20° bank the world leans 10°, deck stays visibly
	-- banked (Monkey Ball feel); 1.0 would make deck read flat
	FovMin = 70,
	FovMax = 88, -- FOV widens with speed for sense of velocity
	SmoothTime = 0.12,
	-- Death-cam (§11): on a kill the camera orbits the wreck for
	-- DeathOrbitSec — an ease-out yaw sweep of DeathOrbitArc pulling back
	-- ×Pull — then the RUN OVER card lands. R during the orbit skips it.
	DeathOrbitSec = 1.5,
	DeathOrbitArc = 0.55, -- radians of yaw sweep (~31°)
	DeathOrbitPull = 1.6, -- offset multiplier at the end of the sweep
}

-- Look-ahead radar (DESIGN.md §12): a vertical strip beside the HUD —
-- top = Range studs out, bottom = at the ball; bars are RoBallLethal
-- blocks projected ball-relative (center line = you). Presentation
-- only: the client re-reads tagged parts every ScanSeconds, so movers
-- and spinners track for free and nothing allocates per frame.
Config.Radar = {
	Range = 240, -- studs ahead shown
	HalfWidth = 26, -- studs either side of the ball mapped to the strip edges
	ScanSeconds = 0.06, -- ~16Hz refresh
	MaxBars = 18, -- pooled bar frames; nearest threats win the pool
	Width = 52, -- strip px
	Height = 150, -- strip px
	BarH = 3, -- bar px
}

-- Deck-edge warning (§12): client raycasts beside the ball warn when the
-- far side hangs off the deck — over a cutout or one step from the rail.
-- A hit on anything (deck, wall, block face) counts as supported.
Config.EdgeWarn = {
	ProbeSide = 2.2, -- lateral studs from ball center — past the ball's edge
	ProbeDown = 30, -- reach: pad arcs must still see the deck below
	Px = 42, -- chevron inset from the side screen edge
	Y = 0.62, -- screen-height fraction of the chevrons
}

-- Ground probe (§11): a lane-only raycast straight down from the ball.
-- The ball's underside within ContactPad of the hit counts as contact —
-- the death card's "air N%" stat is 1 minus the grounded share of run
-- time.
Config.Landing = {
	MaxDrop = 40, -- studs below the ball the probe can still find ground
	ContactPad = 0.7,
	-- Zero-bounce landing: a fast fall arrives past the solver's quiet-
	-- contact range and the impact pops the ball back up — a bounce
	-- that throws the player into the next hole. Two stages: the
	-- approach cap engages when ground is inside ClampReach + one step
	-- of lookahead, holding impact at slope-follow + ImpactPad; then any
	-- solver-pop that still lands positive vY at ContactPad is squashed
	-- flat. Pad/orb kicks stamp KickAt and ride a grace window through
	-- the squash. Over a gap the probe finds nothing: falls stay free.
	ClampReach = 1.8, -- studs under the ball where the cap engages
	ImpactPad = 10, -- studs/s of true impact allowed over slope-following
	KickGrace = 0.25, -- seconds a pad/orb kick is exempt from the squash
	-- Slope tracking (§4): grounded Y follows the surface — the drive
	-- vector is projected onto the probe's plane so the ball pushes
	-- itself down hills instead of launching off crests (Monkey Ball
	-- feel). SlopeSmooth eases the read normal (seconds, τ) so slice
	-- seams don't pop the input; SlopeVelSmooth eases the resulting vY
	-- while contact persists so inflection points don't pop the output —
	-- a real touchdown still snaps (residual fall has to die instantly).
	-- Airborne balls ignore both and fall free.
	SlopeSmooth = 0.05,
	SlopeVelSmooth = 0.09,
}

-- Danger vignette (§12): a red screen-frame stroke that tightens as the
-- nearest corridor-overlapping lethal threat closes — the peripheral
-- brace warning the radar strip can't give.
Config.Danger = {
	Near = 50, -- studs ahead where the vignette starts
	Lane = 4, -- half-width of "overlaps my line" in studs
	MaxAlpha = 0.6, -- stroke opacity at contact distance
	Stroke = 10, -- frame thickness px
	-- Proximity ping (§12): a flattened sonar blip while the vignette is
	-- live — interval tightens Slow→Fast as the threat closes, pitch lifts
	-- PingLift octaves at contact. Audible brace, not a pickup sound.
	PingMin = 0.35, -- intensity floor before the sonar speaks
	PingSlow = 1.0, -- seconds between pings at the floor
	PingFast = 0.22, -- seconds between pings at contact distance
	PingOctave = 0.5, -- base pitch (gem bell down an octave)
	PingLift = 0.35, -- extra pitch rise at full intensity
	PingVol = 0.3,
}

-- Split-time sectors (§14): every Length studs down-track a SectorMark
-- ribbon paints across the deck — the pace pulse is on the track
-- itself, no HUD line.
Config.Sectors = {
	Length = 250, -- studs per boundary
	MarkW = 1.4, -- deck ribbon z-thickness at each boundary
	MarkTrans = 0.25, -- brighter than grid lines, under the edge neon
}

-- No gameplay blur (DESIGN.md §12): the world stays razor sharp at any
-- speed — post FX is restrained bloom + color correction + atmosphere.

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

-- Deck descent is NOT linear forever: deckY drops Grade studs per stud
-- traveled until GradeFloor, then runs level. The floor exists because
-- FallenPartsDestroyHeight clamps at -50000 and a linear grade crosses it
-- ~313km in — the engine destroys deck and ball mid-run. Every consumer
-- (chunk builders, arc solves, the verifier, the client backdrop) calls
-- this one function so they can never disagree about deck height.
local function gradeDrop(y0: number, u: number): number
	return math.min(Config.Generation.Grade * math.max(u, 0), math.max(0, y0 - Config.Generation.GradeFloor))
end

Config.Generation = {
	TravelAxis = Vector3.new(0, 0, -1), -- runs go toward -Z
	ChunkMinLength = 30, -- studs
	ChunkMaxLength = 90,
	AheadDistance = 400, -- keep this much track generated ahead of the ball
	-- Uncapped-tail safety (§9): at extreme speed a fixed stud window
	-- shrinks to sub-second margin — the window grows to AheadSeconds of
	-- boosted-pace travel so a build hitch can't strand the ball in
	-- ungenerated void.
	AheadSeconds = 2,
	BehindDistance = 250, -- destroy chunks further than this behind the ball
	-- Instance.new bursts are the cost, not generation: a chunk is
	-- ~30-90 parts. One per frame tops up the window invisibly; the
	-- run-start pre-build spreads over the settle instead of spiking
	-- one heartbeat with ~10 chunks (worse when several runs start
	-- together).
	ChunkBuildsPerFrame = 1,
	-- Per-player RequestStart throttle: a start/restart rebuilds the
	-- whole streamer — spam (double-click PLAY, R mashing) would churn
	-- chunk builds for nothing. 0.35s sits below real retry cadence.
	StartCooldown = 0.35,
	BaseWidth = 48, -- widest deck — Slope-style broad slope face (~16 ball widths)
	MinWidth = 4, -- narrowest allowed ribbon
	TrackThickness = 1, -- studs
	StartY = 50, -- deck height runs start at
	Grade = 0.16, -- studs of drop per stud traveled — constant downhill (~9deg)
	-- Deck descent bottoms out here, ~4k studs above FallenDestroyY — past
	-- ~287km the track runs level instead of riding the grade into the
	-- engine kill plane. Deepest scenery hangs ~250 studs below deck.
	GradeFloor = -46000,
	gradeDrop = gradeDrop,
	RowSpacing = 600, -- per-player run lanes are this far apart in X
	-- Deck crosses y=-500 around ~3.4km in (50 - Grade*dist); Roblox's default
	-- FallenPartsDestroyHeight is -500 and silently Destroy()s any unanchored
	-- part below it — the ball — leaving the run hung with a frozen HUD.
	-- -50k is the engine minimum; GradeFloor keeps the deck above it forever.
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
		DropGate = 2300,
		PressRow = 2600,
		Pacer = 2700,
		Rotor = 2900,
		FullTilt = 3000,
		LeftTilt = 3200,
		RightTilt = 3400,
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
		"DropGate",
		"PressRow",
		"Pacer",
		"Rotor",
		"FullTilt",
		"LeftTilt",
		"RightTilt",
		"OrbHop",
		"FlipRide",
	},
	-- Stretch pillars (DESIGN.md §8.6): GD gravity flips and tap-jump orbs
	-- are designed but flag-off — they change core physics/controls.
	GravityFlip = false,
	JumpOrbs = false,
	-- Type → HUD display name: the debut banner (§8.6) and the death
	-- card's "felled by" line both resolve through this map. Missing
	-- names fall back to the uppercased type.
	Label = {
		Flat = "FLAT",
		Slalom = "SLALOM",
		Narrow = "NARROW",
		Widen = "WIDEN",
		Tilt = "TILT",
		Pinch = "PINCH",
		SplitGap = "SPLIT GAP",
		Bowl = "BOWL",
		RampGap = "RAMP GAP",
		BlockGate = "BLOCK GATE",
		BlockField = "BLOCK FIELD",
		WallSlot = "WALL SLOT",
		Terrace = "TERRACES",
		Swell = "SWELL",
		Sway = "SWAY",
		SnakeField = "SNAKE FIELD",
		Blackout = "BLACKOUT",
		Chicane = "CHICANE",
		Fork = "FORK",
		FullTilt = "FULL TILT",
		LeftTilt = "LEFT TILT",
		RightTilt = "RIGHT TILT",
		PadHop = "PAD HOP",
		PadVoid = "PAD VOID",
		DropGate = "DROP GATE",
		PressRow = "PRESS ROW",
		Pacer = "PACERS",
		Rotor = "ROTOR",
		OrbHop = "ORB HOP",
		FlipRide = "FLIP RIDE",
	},
}

Config.Pads = {
	-- LaunchPad (DESIGN.md §8.3): cyan neon strip on the deck; touching it
	-- applies a one-shot vertical kick client-side — GD pads as terrain,
	-- not a jump button. The generator computes kickY so the arc always
	-- clears the hazard at the current tier speed.
	Width = 6, -- studs across
	DebutWidth = 11, -- debut pad is nearly unmissable
	Length = 4, -- studs along travel
	-- PadHop rolls padX inside ±width/5 but capped here: on max-width
	-- decks an uncapped roll parks the pad ~10 studs off the run line —
	-- readable-steer range at speed, not a hidden coin flip. The strip
	-- is still the punish for ignoring the pad.
	MaxOffset = 7,
	-- The strip is a TRIGGER, not a ledge: a ball crossing its footprint
	-- kicks from this far above the strip top. Must exceed Landing's
	-- ContactPad — a "grounded" ball can float that far over the deck at
	-- speed, and a grab band below it reads as the pad not working.
	GrabH = 1.5,
	StripH = 2.5, -- lethal strip height the PadHop arc must clear
	StripMin = 5,
	StripMax = 10,
	ArcMargin = 1.6, -- studs of clearance above the strip the arc must keep
	-- Entry-speed honesty: pad chunks must be clearable at the SLOWEST
	-- survivable entry, not the nominal tier speed. Full-brake sets the
	-- sustained floor at 1/Power.Mult ≈ 0.67x nominal — size a notch below
	-- it so a braked (or mid-flight braking) ball never meets an
	-- impossible arc. PadHop's upper bound is Power.Mult itself.
	SlowCrossFrac = 0.55, -- PadHop's strip clearance covers entries down to this fraction of tier speed
	VoidAirFrac = 0.55, -- PadVoid gap = this fraction of pad airtime * speed (< brake floor)
	Color = Color3.fromRGB(0, 230, 255),
}

-- RampGap hoop (§8.6): a neon ring floating at the void's flight apex —
-- non-collide; threading it mid-air pays a flat gem bonus (§10).
Config.Hoop = {
	Radius = 5, -- opening radius — reads as a target at jump speed
	Tube = 1.1, -- ring tube thickness (studs)
	ApexLift = 3.5, -- ring center above the void's launch plane
	Score = 25, -- gem points for a clean thread (beam-tier value)
	Bank = 3, -- banked gems paid through ShopService.awardGems
	-- Whoosh (§10): the bell inhale-swept up through the pass — air
	-- rushing through the opening; rides the `gems` mixer channel.
	WhooshVol = 0.38,
	WhooshStartOct = 0.45, -- starts flattened…
	WhooshEndOct = 1.3, -- …lifts through the thread — triumphant, not a zip
	WhooshTime = 0.26, -- sweep seconds
}

Config.Movers = {
	-- Beat-locked hazards (DESIGN.md §8.3): periods are whole-note values
	-- of the heard tempo, so the movement cycle IS the music — GD's
	-- "the level dances", deterministic under the seed's beat clock.
	PacerBeats = 8, -- slide cycle length in beats (debut runs it double)
	PacerRimMargin = 2, -- sliding gap never closes nearer than this to a rim
	RotorBeats = 6, -- full sweep period in beats (debut runs it 1.5x)
	RotorArmFrac = 1.15, -- arm half-length vs half deck width (pre-clamp)
	RotorPostJitter = 0.12, -- post wanders this fraction of halfW off center
	RotorArmH = 3.2, -- arm bar height — a blade you can't miss, not a curb
	RotorPostH = 5,
	RotorDiscH = 0.12, -- translucent danger-disc slab height under the sweep
	RotorDiscTrans = 0.8, -- ghost tint marking the swept zone's edge
	PressBeats = 4, -- slam cycle length in beats (debut runs it 1.5x)
	PressDownFrac = 0.12, -- cycle share spent slamming down
	PressHoldFrac = 0.2, -- cycle share held on the deck (lethal window)
	-- shorter hold = longer raised window = more time under
	PressUpFrac = 0.22, -- cycle share rising back
	-- Replication thrift (PERFORMANCE.md §2): every Position/CFrame write
	-- goes to every client — stepping movers at frame rate was the
	-- game's largest steady-state send cost. The phase math still reads
	-- the absolute beat clock, so motion is identical, just written
	-- less often; movers this far behind the ball are off-camera and
	-- freeze until cleanup claims them.
	StepHz = 25,
	CullBehind = 60, -- studs behind the ball where movers stop updating
}

-- PressRow (DESIGN.md §8.6): a low roof over the deck and ceiling
-- presses that slam on the beat — the threat comes DOWN, not across.
-- Each press row leaves one permanent side lane; under the plate is a
-- timed shortcut, not the guaranteed line.
Config.Press = {
	HangH = 8, -- gantry hang height — press plates' tops anchor here
	LiftClear = 5.5, -- raised bottom edge: 2.5 studs over the ball —
	-- the under-route must read as a real gap, not a skim
	SlamGap = 0.4, -- slammed bottom edge — always a touch
	MinSpan = 8, -- narrowest press plate that still reads as a press
	LaneMul = 1.45, -- safe-lane width × CorridorMin — a far-rail entry owes
	-- (2·halfW − lane) of lateral transit; wider lane = beatable dash
	DebutLaneMul = 1.8, -- same, on the debut showcase
	ZoneTrans = 0.75, -- ghost red deck slab marking each plate's lethal footprint
	SlamFill = 0.35, -- plate outline surface transparency when fully slammed
	-- (raised = pure wireframe; filling in IS the slam telegraph)
	GantryW = 0.55, -- rim post/crossbeam thickness of each press's frame
	-- Thread bonus (§10): crossing under the plate inside its span while
	-- it's dropped into the under-route — a timed dodge, not a lane take.
	ThreadBonus = 6,
	ThreadMinDrop = 0.2, -- plate must be ≥20% into its travel to count
}

Config.Blackout = {
	-- Break-section darkness: grid/center neon dims to this fraction while
	-- edge rails and gems stay lit — the track goes lights-out, not blind.
	GridScale = 0.12,
}

Config.Swell = {
	-- Deck-shape rest chunk (DESIGN.md §8.3): full-width ribbon undulating
	-- in y — a pump line of rolling hills. Integer periods land the exit
	-- back on the entry height so the seam stays clean.
	LenMin = 160,
	LenMax = 260,
	PeriodsMin = 3,
	PeriodsMax = 6,
	AmpMin = 2.0,
	AmpMax = 7.0,
	SlopeMax = 0.36, -- peak added slope; past this a crest launches hard, not pops
}

-- Roll ramp (DESIGN.md §9): banked chunks (Tilt, Sway) grow steeper with
-- distance — rollScale = 1 + min(dist/RampDist, 1) * (seededMax - 1).
-- The per-seed max multiplier is rolled inside [MaxLo, MaxHi] on the
-- mutator stream, so each run's tilt ceiling differs. Cap is the absolute
-- sanity bound — BankPull at ~42° is ~20 s/s vs 26 max steer: survivable
-- with counter-steer, no longer ignorable.
Config.Roll = {
	RampDist = 6000, -- meters of run to reach full tilt scale
	MaxLo = 1.4, -- per-seed max-multiplier range
	MaxHi = 2.4,
	Cap = 42, -- absolute bank cap, degrees
}

Config.Tilt = {
	-- Tilt (DESIGN.md §8.3): bank the ribbon, hold, return level.
	LenMin = 70,
	LenMax = 110,
}

Config.FullTilt = {
	-- FullTilt (DESIGN.md §8.3): the whole chunk commits to one steep
	-- bank — no Sway oscillation, no mild Tilt hold. Bank pull shoves
	-- toward the low edge the entire length; holding the uphill line IS
	-- the challenge. DegMax rides the §9 roll ramp.
	LenMin = 90,
	LenMax = 140,
	DegMin = 26, -- base bank, degrees
	DegMax = 34, -- × rollScale, clamped to Roll.Cap
	RampFrac = 0.3, -- fraction of chunk the bank eases in/out over
}

Config.Sway = {
	-- Deck-shape chunk (DESIGN.md §8.3): the ribbon's bank oscillates
	-- left-right. Integer periods land the exit level; RateMax caps the
	-- peak deg/stud so the bank rolls like a wave, not a whip.
	LenMin = 90,
	LenMax = 150,
	PeriodsMin = 1,
	PeriodsMax = 2,
	AmpMin = 7,
	AmpMax = 14,
	RateMax = 0.7,
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
-- target rises, new chunk types join the pool, the width floor tightens.
-- widthMax is pinned at 50 forever — the ceiling never shrinks, so deep
-- runs sawtooth across the WHOLE floor-to-full-width window instead of
-- camping narrow. `chunkPool` entries must exist in ChunkDefs.
Config.Tiers = {
	{ dist = 0, chunkPool = { "Flat", "Slalom" }, widthMin = 40, widthMax = 50 },
	{
		dist = 200,
		chunkPool = { "Flat", "Slalom", "Narrow", "BlockGate", "Terrace", "Swell", "Sway" },
		widthMin = 34,
		widthMax = 50,
	},
	{
		dist = 500,
		chunkPool = {
			"Flat",
			"Slalom",
			"Narrow",
			"Tilt",
			"Pinch",
			"BlockGate",
			"BlockField",
			"Terrace",
			"Swell",
			"Sway",
			"SnakeField",
			"Blackout",
		},
		widthMin = 26,
		widthMax = 50,
	},
	{
		dist = 900,
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
			"Swell",
			"Sway",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
		},
		widthMin = 20,
		widthMax = 50,
	},
	{
		dist = 1400,
		chunkPool = {
			"Flat",
			"Narrow",
			"Widen",
			"Tilt",
			"FullTilt",
			"LeftTilt",
			"RightTilt",
			"Pinch",
			"SplitGap",
			"Bowl",
			"RampGap",
			"BlockField",
			"WallSlot",
			"Terrace",
			"Swell",
			"Sway",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
			"PadVoid",
			"DropGate",
		},
		widthMin = 14,
		widthMax = 50,
	},
	{
		dist = 2000,
		chunkPool = {
			"Flat",
			"Narrow",
			"Widen",
			"Tilt",
			"FullTilt",
			"LeftTilt",
			"RightTilt",
			"Pinch",
			"SplitGap",
			"Bowl",
			"RampGap",
			"BlockField",
			"WallSlot",
			"Terrace",
			"Swell",
			"Sway",
			"SnakeField",
			"Blackout",
			"Chicane",
			"Fork",
			"PadHop",
			"PadVoid",
			"DropGate",
			"PressRow",
			"Pacer",
			"Rotor",
			-- Flag-off stretches (§8.6): canRun drops them unless the
			-- Features flags are on, so they sit inert in the pool.
			"OrbHop",
			"FlipRide",
		},
		widthMin = 10,
		widthMax = 50,
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
	-- Near-set rebuild cadence (PERFORMANCE.md §1): iterating every tagged
	-- gem per render frame was the script's widest scan — this keeps a
	-- camera-near subset and only refreshes it a few times a second.
	BeatPulseScanSeconds = 0.25,
	-- Reserved gold: collectible, never lethal, and reads as the "sunset"
	-- accent against the magenta/cyan world.
	Color = Color3.fromRGB(255, 212, 64),
	-- Gem types (§8.4): worth IS the type — each value tier carries its own
	-- warm-family tint + shape list, hotter/heavier reading = more points,
	-- so pickups telegraph their payoff at speed. `shapes` lists the
	-- silhouettes a tier can render; the streamer picks per spot by a
	-- deterministic (startZ, t) hash in GemTypes.pick — a pure function of
	-- the emitted spec, so a seed replays the exact same mix (no rng spent,
	-- §6 purity intact). Tints stay in the gold→white "currency" ramp:
	-- collectible warmth, never near LethalColor red. Keys mirror the
	-- Value* entries above — retune a value, move its tier key too.
	Kinds = {
		-- safe 10 — small common pickups: the corner diamond or a pearl orb
		[10] = {
			color = Color3.fromRGB(255, 212, 64),
			shapes = {
				{ shape = "diamond", size = 1.0 },
				{ shape = "orb", size = 0.95 },
			},
		},
		-- edge 15 — amber: upright coins + orbs hugging the rails
		[15] = {
			color = Color3.fromRGB(255, 168, 52),
			shapes = {
				{ shape = "coin", size = 1.05 },
				{ shape = "orb", size = 0.95 },
			},
		},
		-- beam 25 — orange: shards and rods on the risky lines
		[25] = {
			color = Color3.fromRGB(255, 132, 50),
			shapes = {
				{ shape = "shard", size = 1.25 },
				{ shape = "rod", size = 1.25 },
			},
		},
		-- gap-arc 40 — the jackpot crown: always the fat white-hot diamond
		[40] = {
			color = Color3.fromRGB(255, 244, 185),
			shapes = {
				{ shape = "crown", size = 1.55 },
			},
		},
	},
	-- "ball" pickup style (§18 world_sky / APE BALL): the world item's
	-- gemStyle restyles every pickup as a banana-yellow capsule orb —
	-- tier scale still sizes it so worth reads at speed.
	BallStyleColor = Color3.fromRGB(255, 226, 92),
}

Config.Score = {
	PointsPerMeter = 1,
	-- PB ghost (DESIGN.md §11): a translucent "BEST n" gate floats on the
	-- deck at your record's end distance — you race your own shadow.
	PbMarkerMinDist = 150, -- meters — don't bother marking stub runs
	-- The gate's "BEST n" label only renders inside this range — a quiet
	-- approach cue, not a constant screen occupant.
	PbMarkerViewDist = 140,
	-- Crossing the line flashes "★ NEW BEST" under the HUD score.
	PbFlashSeconds = 3,
	TierFlashSec = 1.6, -- tier-up callout under the score — cue for the speed/hazard step
	-- Near-miss trickle (§10): crossing a hazard's plane within Range
	-- studs of its lethal face — or anywhere inside a rotor's marked
	-- sweep disc — without dying pays Points of score. Per-obstacle,
	-- once each; small on purpose, it's seasoning not a farm.
	NearMiss = {
		Range = 4,
		Points = 3,
	},
}

-- PB ghost replay (DESIGN.md §14): your record run leaves a translucent
-- echo on its seed — record at SampleSeconds cadence while running, save
-- the frames only when the run ends as a new personal best, replay them
-- on the same seed. Cosmetic only: the ghost never touches physics,
-- scoring, or generation.
Config.Ghost = {
	Store = "RoBall3D_Ghost_v1", -- datastore key, per-userId
	ChampStore = "RoBall3D_GhostChamp_v1", -- per-seed record holder replay
	SampleSeconds = 0.2, -- client records one frame per N seconds of run
	MaxSamples = 600, -- 2 minutes of run — hard payload cap, server-enforced
	MinFrames = 25, -- runs under ~5s aren't worth a ghost
	Transparency = 0.55, -- the echo ball's translucency
	RivalColor = Color3.fromRGB(255, 196, 56), -- champion echo: gold vs own cyan
	RivalTransparency = 0.35, -- reads "ahead of you" vs the airier PB echo
	CrowdColor = Color3.fromRGB(196, 204, 220), -- crowd echo: silver seat on daily seeds
	CrowdTransparency = 0.62, -- presence, not pace — airier than the rival
	-- Split trails (§14): each echo drags a short ribbon so the diverging
	-- lines read in peripheral vision, not just the two balls. Lifetime is
	-- seconds of path; the alpha ramp starts at the echo's translucency.
	TrailLife = 1.1,
	TrailGap = 1.1, -- attachment half-span (studs) — ribbon thickness
	TrailFade = 0.35, -- extra transparency added over the echo's own
	OvertakeArm = 2, -- studs behind a replay before catching it counts as a pass
	-- Duel tag (§14): a pace line within this many studs either way earns
	-- the "· DUEL" suffix — close-race tension the number alone misses.
	DuelRange = 8,
}

Config.GemSfx = {
	-- Gem pickup chime (SfxController): rapid pickups climb a pentatonic
	-- ladder so cluster lines play little runs. rbxasset:// fallback is a
	-- built-in Roblox ping — always resolvable if the asset fails to load.
	-- Numeric id for production OR an rbxasset:// ContentId URI resolving
	-- Studio's bundled content dir for local dev (the vaporwave-bell render).
	AssetId = 87429654015431, -- uploaded "Gem Pickup SFX" (FlowMusic render)
	FallbackId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.18, -- baseline sits under the mix; the menu mixer's GEMS slider rides on top
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

Config.DashSfx = {
	-- Q/E dash voice (SfxController, AUDIO.md §6): OFF-grid on purpose —
	-- quantizing a panic input would cost the dodge. The same uploaded
	-- bell plays through a PitchShiftSoundEffect swept down over the
	-- burst: duration stays fixed, the read is a falling zip, not a chime.
	AssetId = 88208694516408, -- reuses the uploaded rb3_gem_pickup bell
	FallbackId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.3,
	StartOctave = 1.0, -- PitchShift octaves at press time
	EndOctave = 0.55, -- swept target — most of the fall lands in-burst
	SweepTime = 0.17, -- seconds for the octave to ease down (EasingStyle.Quad)
	DirTilt = 0.06, -- E starts this fraction brighter than Q — direction signature
	-- Denied press: flat low blip, hard-stopped so it never rings out.
	DenyOctave = 0.45,
	DenyVolume = 0.14,
	DenyTime = 0.09,
	-- Light sidechain punch on a fired dash (same duck() the chime uses).
	DuckDepth = 0.18,
	DuckRelease = 0.28,
}

Config.Audio = {
	-- Menu mixer (AUDIO.md §7): the AUDIO panel's slider channels. Keys
	-- are the attribute/profile/remote namespace (RoBallVol_<ch>); the
	-- panel labels are player-facing. All sliders are attenuation-only
	-- (0..1) — the mix is tuned at the sources. Defaults sit at half —
	-- the sources are mixed hot, full-everything was deafening, and a
	-- mid default leaves headroom both directions.
	Channels = { "music", "gems", "dash" },
	Defaults = { music = 0.5, gems = 0.5, dash = 0.5 },
	Labels = { music = "MUSIC", gems = "GEMS", dash = "DASH" },
	RemoteName = "SetAudio", -- RemoteFunction: SetAudio(ch, 0..1) -> bool
	AttrPrefix = "RoBallVol_", -- per-channel attribute mirror
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
	-- SongMap.trackIdFor(seed, ActiveTracklist); GenCore and MusicController
	-- share the pick so stamped sections match the heard track. Per-track
	-- charts live in SongMap_<id>.luau. Tracklist is the FULL catalog —
	-- ActiveTracklist (built below) drops ids whose AssetId isn't wired
	-- yet, so unuploaded tracks can't be seeded. The garage TRACK cycler
	-- picks from the same list; picking a track just sends a seed in its
	-- residue class so the gen charts the song the player hears.
	Tracklist = {
		-- FlowMusic catalog (roball3d-audio/flowmusic/, IMPORT_REPORT.md)
		"midnight_overdrive", -- 109.72 bpm
		"void_runner", -- 136.06
		"tape_drift", -- 126.12
		"smoothride", -- 126.12
		"retro_wave_sunset", -- 109.72
		"neon_nostalgia", -- 82.56
		"oldtimes", -- 82.56
		"underwater", -- 93.25
		"velvet_loader", -- 172.27 (double-time read of a ~129 pulse)
		"palm_screens", -- 105.38 — also the menu bed
	},
	-- Menu music: plays instead of the seeded pick while parked (still
	-- under the menu lowpass). Falls back to Tracklist[1] when unset or
	-- the asset isn't uploaded yet.
	MenuTrack = "palm_screens",
	-- MENU.md §6: the poster's accent endpoints (horizon rule gradient,
	-- BEST label tint) re-skin to the browsed track — one {A, B} pair per
	-- Tracklist id, tuned to each track's identity. Palette law holds:
	-- neon/warm endpoints, every pair a clear step off LethalColor red.
	TrackAccents = {
		midnight_overdrive = { Color3.fromRGB(175, 80, 255), Color3.fromRGB(0, 230, 255) }, -- violet/cyan
		void_runner = { Color3.fromRGB(110, 90, 255), Color3.fromRGB(228, 246, 255) }, -- indigo/starlight
		tape_drift = { Color3.fromRGB(255, 168, 52), Color3.fromRGB(255, 90, 170) }, -- amber/dusty pink
		smoothride = { Color3.fromRGB(0, 230, 210), Color3.fromRGB(120, 190, 255) }, -- aqua/sky
		retro_wave_sunset = { Color3.fromRGB(255, 176, 64), Color3.fromRGB(255, 46, 160) }, -- classic sun: orange/pink
		neon_nostalgia = { Color3.fromRGB(255, 46, 190), Color3.fromRGB(0, 230, 255) }, -- magenta/cyan
		oldtimes = { Color3.fromRGB(240, 200, 140), Color3.fromRGB(170, 130, 220) }, -- cream/faded violet
		underwater = { Color3.fromRGB(60, 140, 255), Color3.fromRGB(0, 230, 255) }, -- deep blue/cyan
		velvet_loader = { Color3.fromRGB(255, 64, 190), Color3.fromRGB(150, 70, 255) }, -- hot pink/violet
		palm_screens = { Color3.fromRGB(0, 230, 255), Color3.fromRGB(90, 255, 160) }, -- cyan/palm mint
	},
	-- Per-track assets. AssetId = the full mix; numeric rbxassetid for
	-- production or an rbxasset:// ContentId URI resolving to Studio's
	-- bundled content dir for local dev. Stems: when EVERY entry resolves,
	-- the MusicController plays one AudioPlayer per stem and fades layers by
	-- tier (Layers); any stem failing to load drops the whole set back to
	-- that track's AssetId (watchdog). Upload roball3d-audio/tracks/<id>/
	-- oggs and paste numeric ids for production.
	TrackAssets = {
		-- FlowMusic catalog — master mix only (no stems, plays the AssetId
		-- player directly). AssetId = 0 keeps the id out of ActiveTracklist
		-- until the ogg is uploaded and the id pasted here.
		midnight_overdrive = { AssetId = 96854802386980 }, -- "MIDNIGHT OVERDRIVE"
		void_runner = { AssetId = 117637051419784 }, -- "VOID RUNNER"
		tape_drift = { AssetId = 96839771028670 }, -- "Tape Drift"
		smoothride = { AssetId = 136320984653411 }, -- "smoothride"
		retro_wave_sunset = { AssetId = 121485175631351 }, -- "retro wave sunset"
		neon_nostalgia = { AssetId = 103995967173138 }, -- "Neon Nostalgia"
		oldtimes = { AssetId = 106814879270965 }, -- "OldTimes"
		underwater = { AssetId = 114136064521412 }, -- "UnderWater"
		velvet_loader = { AssetId = 100333018795935 }, -- "VELVET LOADER"
		palm_screens = { AssetId = 107610795649189 }, -- "PALM SCREENS"
	},
	Volume = 0.5,
	-- Reference grid tempo — the beat grid EVERY run generates against
	-- (beat interval = 60 / (bpm * heard PlaybackSpeed)). Must equal the
	-- MenuTrack map's SongMap.bpm — palm_screens is 105.38. The seeded
	-- track pick only chooses the heard audio; keeping generation on this
	-- one tempo is what makes gem spacing, mover periods, and section
	-- energy identical across songs (AUDIO.md §5.2 fairness contract).
	BaseBpm = 105.38,
	-- Runs open at HALF speed: 0.5 snaps to exactly −12 semitones — a clean
	-- octave-down "chopped & screwed" opener that lifts to full tilt as the
	-- ball accelerates (AUDIO.md §4). Fairness holds: the same curve applies
	-- to every song, and generation never reads the track's own bpm.
	PlaybackSpeedMin = 0.5,
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
	DeathPitchFloor = 0.4, -- pitch slides to this on death; must sit BELOW
	-- PlaybackSpeedMin or an instant-death tape-stop slides UP in tempo
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
	-- Analyzer cadence (PERFORMANCE.md §1): GetSpectrum allocates a table
	-- per call — re-read at this rate and keep the pulse envelope's decay
	-- running per frame between reads, so visuals stay continuous.
	AnalyzerHz = 30,
	-- HUD waveform (§12): the BPM cluster's scope trace buckets the
	-- throttled spectrum into this many strips — log-spaced bins, bass on
	-- the left, air on the right. Attack is instant, release decays per
	-- tick so a quiet passage flattens instead of snapping off.
	WavePoints = 26,
	-- Auto-gain: raw spectrum magnitudes ride the stem loudness (~1e-3
	-- scale), so bands normalize against a decaying peak — the trace
	-- breathes at any mix volume instead of clipping loud or flatlining
	-- quiet. WaveFloor keeps dead air a true flatline rather than
	-- noise-pumping the floor to full height.
	WavePeakDecay = 0.985,
	WaveFloor = 0.03,
	-- Log-lift strength for band normalization (§12): quiet band means
	-- sit ~10x under the hot band, so a linear gain buries mids/air —
	-- v = log(1 + raw*K) / log(1 + peak*K). Higher K = quiet bands rise
	-- harder; K = 0 is linear.
	WaveCurveK = 1000,
	-- Band release per analyzer tick — lower drops peaks faster so the
	-- trace reads jumpy, not syrupy.
	WaveDecay = 0.68,
	-- Perceptual lift applied in the HUD (v^WaveGamma): raises quiet
	-- bands so mids/air register without flattening the bass crests.
	WaveGamma = 0.55,
	-- Beat envelope (§12): Music.sample() returns the heard level
	-- normalized against its own decaying peak (kicks hit ~1, lulls drop
	-- toward 0 on any mix), and that envelope swells the whole trace —
	-- amp = floor + (1-floor) x min(1, pulse x gain). The baseline
	-- hairline and capsule rim flash on the same envelope.
	WaveBeatGain = 2.5,
	WaveBeatFloor = 0.3,
	-- Gem-chime voice pool (PERFORMANCE.md §3): playOneShot used to build
	-- an AudioPlayer + Wire per pickup; this many pooled voices cover
	-- even dense cluster runs, recycling the oldest when saturated.
	ChimeVoices = 6,
}

-- The seeded/garage pool: Tracklist order, minus ids that can't play —
-- a track with no master AND no complete stem set can't be seeded or
-- picked. GenCore and MusicController both consume THIS list so
-- the gen's stamped SongMap always matches the heard audio.
local function trackPlayable(ta): boolean
	if not ta then
		return false
	end
	if ta.AssetId ~= 0 then
		return true
	end
	if type(ta.Stems) ~= "table" then
		return false
	end
	for _, name in ipairs({ "pad", "bass", "drums", "lead", "arp", "air" }) do
		local id = ta.Stems[name]
		if id == nil or id == 0 or id == "" then
			return false
		end
	end
	return true
end
Config.Music.ActiveTracklist = {}
for _, id in ipairs(Config.Music.Tracklist) do
	if trackPlayable(Config.Music.TrackAssets[id]) then
		table.insert(Config.Music.ActiveTracklist, id)
	end
end

-- The menu bed, when its asset exists — else the seeded default.
function Config.Music.menuTrackId(): string
	local ta = Config.Music.TrackAssets[Config.Music.MenuTrack]
	if trackPlayable(ta) then
		return Config.Music.MenuTrack
	end
	return Config.Music.ActiveTracklist[1]
end

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
		Swell = "breather",
		Sway = "technical",
		Slalom = "technical",
		Narrow = "technical",
		Widen = "technical",
		Tilt = "technical",
		FullTilt = "technical",
		LeftTilt = "technical",
		RightTilt = "technical",
		Pinch = "technical",
		SplitGap = "technical",
		Fork = "technical",
		BlockGate = "lethal",
		BlockField = "lethal",
		WallSlot = "lethal",
		SnakeField = "lethal",
		Chicane = "lethal",
		DropGate = "lethal",
		PressRow = "lethal",
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

-- Seed flavor (DESIGN.md §8.7): each seed rolls one mutator on a salted
-- rng stream and GenCore multiplies it into the songform pick weights —
-- selection bias ONLY. Legality rules, contracts, the intro, and debut
-- milestones are untouched, so a flavor can never make an unfair map.
Config.Mutators = {
	-- Random.new(seed + Salt): a stream separate from the gen rng so the
	-- flavor pick can't shift the chunk roll sequence.
	Salt = 7919,
	-- standard sits in the order three times — ~1 in 4 seeds runs the
	-- plain mix.
	Order = {
		"standard",
		"standard",
		"standard",
		"steady",
		"pressure",
		"airshow",
		"weave",
		"rotorfield",
		"pressgang",
		"grounded",
		"snakepit",
		"squeeze",
		"expanse",
	},
	List = {
		standard = {},
		steady = { label = "STEADY", fams = { lethal = 0.5, breather = 1.8 } },
		pressure = { label = "PRESSURE", fams = { lethal = 2.1, breather = 0.4 } },
		airshow = { label = "AIRSHOW", fams = { spectacle = 2.1, technical = 0.6 } },
		weave = { label = "WEAVE", fams = { technical = 2.0, lethal = 0.6 } },
		rotorfield = { label = "ROTOR FIELD", fams = { spectacle = 1.3 }, types = { Rotor = 3.5 } },
		pressgang = { label = "PRESS GANG", types = { PressRow = 3.5 } },
		grounded = { label = "GROUNDED", fams = { spectacle = 0.35, technical = 1.5 } },
		snakepit = { label = "SNAKE PIT", types = { SnakeField = 3.5 } },
		squeeze = { label = "SQUEEZE", width = 0.82 },
		expanse = { label = "EXPANSE", width = 1.18 },
	},
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
	CityFadeIn = 0.7, -- seconds a recycled tower's outline ramps in
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
	PeaksMaxH = 700, -- ridge amplitude at the outermost column
	PeaksPeakPow = 2.2, -- summit-emphasis exponent on the crest signal —
	-- crest^p sinks the rolling mid-field into valleys while crests keep
	-- their needle, so the silhouette reads as separate sharp peaks
	PeaksRampPow = 0.5, -- lateral ramp exponent (0 at road edge = valley)
	PeaksFreqX = 0.28, -- ridged-noise frequency per column step — higher
	-- samples more crests per column span = serrated skyline
	PeaksFreqZ = 0.09, -- ridged-noise frequency per lattice row
	PeaksEnvF = 0.012, -- range-swell frequency per lattice row (passes)
	PeaksEnvFloor = 0.3, -- envelope never flattens past this share of
	-- full height — passes dip, the mountain band never vanishes
	PeaksSeed = 71, -- math.noise seed — terrain identity is world-fixed
	PeaksSkirt = 9, -- ridge base sinks this far below the deck plane
	PeaksLine = 0.45, -- wireframe edge thickness (Neon parts)
	PeaksValue = 0.85, -- palette value scale for edges
	PeaksFaceTint = 0.09, -- facet drift toward palette (DeckTint cousin)
	-- Starfield well (§18 world "void"): a shell of neon motes ringing the
	-- descent axis — half the shell sits below the deck plane, so the drop
	-- reads as a fall through open space. Motes recycle like towers.
	VoidStars = 150, -- motes on the shell
	VoidRadius = 480, -- shell radius out from the lane
	VoidZSpan = 900, -- z window the motes cover around the ball
	VoidSize = 1.4, -- base mote diameter (jittered ±)
	VoidValue = 0.9, -- palette value for mote neon
	-- TOXIC WASTES (§18 world "toxic"): acid bubbles boiling up beside
	-- the lane — lime spheres climb out of the runoff below deck, pop
	-- back to base when their phase wraps, and recycle forward on the
	-- usual z frontier like the star motes.
	ToxicCount = 120, -- bubbles in the field
	ToxicSideMin = 30, -- lateral distance from lane center (clears the deck)
	ToxicSideJitter = 260, -- extra lateral spread
	ToxicZSpan = 650, -- z window the field covers behind the frontier
	ToxicDepthMin = 4, -- spawn depth below the local deck plane
	ToxicDepthMax = 44,
	ToxicRiseMin = 5, -- climb speed, studs/s
	ToxicRiseMax = 15,
	ToxicRiseSpan = 50, -- height of one climb before the pop resets
	ToxicSizeMin = 0.6,
	ToxicSizeMax = 4.2,
	ToxicAlpha = 0.2, -- base transparency (jittered up per bubble)
	-- Retro grid floor (§18 world "grid"): a wireframe plane riding the
	-- descent GridFloorDrop studs below the deck — cross wires +
	-- longitudinal rays, recycling forward like the tower rows.
	GridFloorDrop = 70,
	GridFloorHalfX = 320, -- floor half-width
	GridFloorCellZ = 55, -- cross-wire spacing along z
	GridFloorRows = 22, -- cross wires covering the window
	GridFloorCols = 14, -- longitudinal rays
	GridFloorLine = 0.4, -- wire thickness
	GridFloorValue = 0.75, -- palette value for the floor neon
	-- BOREALIS SKY (§18 world "aurora"): light curtains flanking the
	-- lane — the same soft-particle technique as NORTHERN LIGHTS (giant
	-- VelocityPerpendicular streak sprites burst ~10k studs and frozen
	-- mid-flight by Drag), but each emitter fan is yawed so its sprite
	-- plane runs ALONG the track beside the deck (polar's fans span the
	-- sky overhead). Emitter parts re-anchor ahead of the ball every
	-- frame — the curtains stream forever without recycling.
	AuroraFanSides = 2, -- emitter fans per side, stacked down-course
	AuroraFanX = 460, -- lateral offset beside the lane — far enough that the
	-- curtains hang in the distance instead of walling the camera in
	AuroraFanXJitter = 140, -- seeded lateral spread across the fans
	AuroraFanY = 170, -- emitter height above the ball — high enough for the
	-- rays to arch into the chase cam's sky band instead of hugging the deck
	AuroraFanZ = 420, -- first fan's distance ahead
	AuroraFanZGap = 520, -- extra distance per stacked fan
	AuroraTexture = "rbxassetid://110170832236629", -- soft streak sprite
	AuroraRate = 140, -- particles/s per fan
	AuroraSpeed = 10000, -- burst studs — drag then freezes them mid-flight
	AuroraDrag = 9,
	AuroraSize = 420, -- sprite studs
	AuroraSquash = 2, -- velocity stretch — silky streaks, not blobs
	AuroraLifeMin = 2,
	AuroraLifeMax = 4,
	AuroraEmission = 0.85, -- LightEmission — self-glow through the night
	-- NORTHERN LIGHTS (§18 world "polar"): the aurora is a soft-particle
	-- canopy, not part sheets — giant VelocityPerpendicular streak
	-- sprites flung on a 10,000-stud burst and frozen mid-flight by Drag
	-- (the classic one-emitter aurora trick). SpreadAngle (180,0) fans
	-- the burst across the upper semicircle; emitter parts re-anchor
	-- ahead of the ball every frame so the canopy hangs over the track
	-- forever. A sparse star field rides the night band with it.
	PolarFans = 2, -- emitter fans stacked down-course (depth layers)
	PolarFanZ = 50, -- first fan's distance ahead of the ball — near the
	-- vanishing point, so the rays fan across the whole sky
	PolarFanZGap = 140, -- extra distance per stacked fan
	PolarFanY = -10, -- emitter drop below the ball — the fan sweeps overhead
	PolarFanYaw = 0.35, -- seeded yaw off the lane axis (rad), plus a slow
	-- live drift so the canopy planes wander
	PolarTexture = "rbxassetid://110170832236629", -- soft streak sprite
	PolarRate = 200, -- particles/s per fan
	PolarSpeed = 10000, -- burst studs — drag then freezes them mid-flight
	PolarDrag = 9, -- the freeze that turns a burst into a canopy
	PolarSize = 650, -- sprite studs — the scale is what makes it sky-like
	PolarSquash = 2, -- velocity stretch — silky streaks, not blobs
	PolarLifeMin = 2, -- lifetime s — sprites respawn as the canopy churns
	PolarLifeMax = 4,
	PolarEmission = 0.9, -- LightEmission — self-glow through the night
	PolarStars = 45, -- star motes scattered through the night band
	PolarStarAltMin = 10, -- star heights above the ball (ball-relative,
	PolarStarAltMax = 280, -- same sky-anchoring as the veils)
	PolarStarX = 320, -- star lateral scatter half-width
	PolarStarZSpan = 1100, -- z window the field covers
	-- Neon reed field (§18 world "reef"): dense thin neon strands rising
	-- out of the void beside the deck — kelp on a wireframe reef. Static
	-- parts recycled on a frontier like the towers.
	ReefCount = 40, -- strands per side
	ReefSpacing = 34, -- z spacing per strand
	ReefMinX = 42, -- inner reach (deck max ~39 — hugs the edge)
	ReefMaxX = 150,
	ReefMinH = 14, -- strand heights; bases sit below the deck
	ReefMaxH = 80,
	ReefW = 0.55, -- strand thickness
	ReefSink = 26, -- deepest a strand's center may sit below the deck
	ReefFloat = 14, -- highest it may float above
	ReefValue = 0.9,
	-- Meteor shower (§18 world "meteor"): thin neon streaks slanting down
	-- through the sky on real velocities — the one animated sky.
	MeteorCount = 16,
	MeteorSpan = 1100, -- z window ahead of the ball they spawn inside
	MeteorMinX = 60, -- lateral spawn band around the lane
	MeteorMaxX = 320,
	MeteorAltMin = 60, -- spawn height above the deck plane
	MeteorAltMax = 260,
	MeteorSpeedMin = 150, -- studs/s along the streak direction
	MeteorSpeedMax = 300,
	MeteorLenMin = 11, -- streak tail length
	MeteorLenMax = 26,
	MeteorDrop = 160, -- respawn once this far below the deck plane
	MeteorValue = 1.0,
	MeteorWhite = 0.45, -- fraction painted pure white (hot heads)
	-- PALMS (§18 "palms" world): neon palm rows replace the tower canyon —
	-- a trunk, a fan of thin drooping fronds, two bead coconuts. Fronds
	-- rustle a few degrees on wall-clock sine; bases sit just under the
	-- deck grade so the grove reads planted beside the track.
	PalmRows = 2,
	PalmMinX = 54, -- nearest trunk distance from lane center
	PalmRowDX = 46,
	PalmSpacing = 40,
	PalmSpan = 460,
	PalmTrunkMin = 22,
	PalmTrunkMax = 36,
	PalmFronds = 6,
	PalmFrondLen = 12,
	PalmDroopMin = 0.9, -- rad: frond pitch below horizontal
	PalmDroopMax = 1.35,
	PalmSwayDeg = 3.5, -- crown rustle amplitude
	PalmSwayRate = 1.1, -- rad/s breeze
	PalmValue = 0.9, -- neon brightness for fronds
	-- SKY COURT (§18 "sky" world, APE BALL pack): the day-shift look —
	-- the client re-times Lighting to midday so the whole sky goes
	-- arcade blue with a real sun, palm-topped islets float past in the
	-- blue, and chunky cartoon clouds hang beside the track.
	SkyClockTime = 14.2,
	SkyAmbient = Color3.fromRGB(120, 132, 160),
	SkyOutdoorAmbient = Color3.fromRGB(170, 180, 205),
	SkyAtmoColor = Color3.fromRGB(150, 195, 245),
	SkyAtmoDecay = Color3.fromRGB(115, 160, 215),
	SkyAtmoHaze = 2.5,
	SkyFloorA = Color3.fromRGB(158, 206, 80), -- arcade grass, light tile (floor_check deck)
	SkyFloorB = Color3.fromRGB(50, 130, 54), -- arcade grass, dark tile (floor_check deck)
	-- Floating islets in the open blue (SMB's islands-in-the-sky read):
	-- grass-domed motes with a lone palm recycle past like the cloud
	-- field, hung at SkyIsleDrop below deck grade.
	SkyIsleDrop = 230, -- islet altitude below deck grade
	SkyIslands = 6, -- grass-domed islets adrift in the sky
	SkyIslandMinX = 260, -- closest drift from lane center
	SkyIslandDX = 380, -- lateral spread beyond MinX
	SkyIslandZMin = 350, -- nearest re-entry ahead of the ball
	SkyIslandZSpan = 1600, -- re-entry window beyond ZMin
	SkyIslandBack = 150, -- recycle once this far behind the anchor
	SkyIslandMinR = 34, -- dome radius band
	SkyIslandMaxR = 92,
	SkyIslandTop = Color3.fromRGB(66, 152, 62),
	SkyIslandSide = Color3.fromRGB(202, 166, 108), -- sandy cliff mass under the dome
	-- Goal arches (SMB's finish-gate homage): a giant two-tone ring the
	-- lane threads — center lifted just over the deck so the ball rolls
	-- through the hole while the lower arc swings under the lane into
	-- the open blue. Gold/ivory stripes stay clear of LethalColor red.
	SkyGates = 3, -- arches live in the window at once
	SkyGateZMin = 700, -- nearest re-entry ahead of the ball
	SkyGateZSpan = 1800, -- re-entry window beyond ZMin
	SkyGateBack = 140, -- recycle once this far behind the anchor
	SkyGateR = 34, -- ring radius — opens ~31 wide at deck height on a 44 lane
	SkyGateLift = 14, -- ring center above deck grade
	SkyGateSegs = 24, -- arc segments per ring
	SkyGateThick = 1.7, -- segment thickness studs
	SkyGateA = Color3.fromRGB(255, 196, 56), -- goal-gold stripe
	SkyGateB = Color3.fromRGB(250, 250, 245), -- ivory stripe
	SkyClouds = 14, -- drifting puffs in flight
	SkyCloudMinX = 46, -- closest drift from lane center
	SkyCloudDX = 110, -- lateral spread beyond MinX
	SkyCloudAltMin = -35, -- lowest drift below deck grade
	SkyCloudAltMax = 90, -- highest drift above
	SkyCloudSpan = 500, -- z window a recycled cloud re-enters inside
	SkyCloudBob = 0.5, -- rad/s lazy bob
	SkyCloudBobAmp = 2.5, -- studs
	SkyCloudColor = Color3.fromRGB(255, 255, 255),
	-- SKY COURT palms: the same grove machinery as MIAMI NIGHTS, dressed
	-- in a day palette — brown trunks, green fronds, banana-yellow beads.
	SkyPalmTrunk = Color3.fromRGB(146, 96, 52),
	SkyPalmFrondA = Color3.fromRGB(58, 168, 76),
	SkyPalmFrondB = Color3.fromRGB(28, 122, 56),
	SkyPalmShade = Color3.fromRGB(20, 84, 40), -- outer-row dim target
	SkyPalmBead = Color3.fromRGB(255, 226, 92), -- banana-yellow coconuts
	-- CAPSULE skin (§18 ape, APEBALL.md §2-3): a glossy half-clear shell
	-- with a toy monkey RIDING inside on a constraint rig — it stays
	-- upright and yaws into travel like the arcade ape instead of
	-- tumbling with the roll. Generic primitive monkey: no borrowed
	-- character.
	CapsuleAlpha = 0.5,
	RiderTumble = 0.004, -- lean-back per rad/s of ball spin (SMB's bounded in-air counter-tilt, NOT a spin share)
	RiderTumbleMax = 0.18, -- rad cap on that lean — full speed stays a ~10° brace, never a somersault
	RiderYawVelLo = 4, -- studs/s: yaw blends onto the velocity heading above this (SMB's 0.23 u/s gate rescaled)
	RiderYawVelHi = 16, -- studs/s: fully velocity-facing by here (SMB's 0.37 u/s)
	RiderResponsiveness = 40, -- Align stiffness — <200 leaves suspension bob, plays SMB's soft uprighting
	RiderMaxForce = 1e5, -- AlignPosition cap: the rig must hold dead-center at any speed
	RiderMaxTorque = 1e4, -- AlignOrientation cap: soft tracking, never a snap
	RiderHz = 30, -- goal-write cadence: the damped constraint hides anything faster; halves replication
	MonkeyScale = 1.35, -- overall monkey size multiplier — reads through the 0.5 shell
	MonkeyFur = Color3.fromRGB(170, 110, 64),
	MonkeyFace = Color3.fromRGB(248, 214, 170),
	MonkeyEye = Color3.fromRGB(48, 30, 24),
	-- PIXEL GLASS / SCANLINES (§18 "filter" slot): an LCD-style lattice
	-- over the 3D view — gridlines at PixelPitch read as chunky pixels.
	-- The overlay sits on a lower DisplayOrder than the HUD so every
	-- line of text stays crisp (the filter never touches readability).
	PixelPitch = 6, -- px per pixel cell
	PixelBar = 1, -- gridline thickness in px
	PixelAlpha = 0.5, -- gridline opacity
	PixelColor = Color3.fromRGB(6, 2, 12),
	-- Synthwave sun: a neon disk parked far down the slope, riding the
	-- descent so it hangs on the horizon. The crown is a solid dome
	-- (orange -> magenta), the bottom `solid`->1 dissolves into the
	-- classic horizontal strips with gaps widening downward.
	SunDist = 480, -- studs ahead — pushed back so the disk reads distant,
	-- not looming, but stays inside the atmosphere's ~600-stud fade wall
	SunRadius = 72,
	SunLift = 16, -- studs above the ball — disk rides low against the
	-- camera's downward pitch so most of it stays in frame
	SunStrips = 16,
	SunDepth = 3, -- strip thickness along z
	-- Sun skins (§18 "sun" slot): each style restyles the strip stack —
	-- crown/base colors, the solid-dome fraction, the thinnest strip,
	-- and a radius multiplier (moons read smaller than suns).
	SunStyles = {
		classic = {
			top = Color3.fromRGB(255, 176, 64),
			bottom = Color3.fromRGB(255, 46, 160),
			solid = 0.55,
			gap = 0.5,
			scale = 1,
		},
		moon = {
			top = Color3.fromRGB(245, 238, 255),
			bottom = Color3.fromRGB(140, 150, 190),
			solid = 0.95,
			gap = 0.4,
			scale = 0.72,
		},
		acid = {
			top = Color3.fromRGB(170, 255, 60),
			bottom = Color3.fromRGB(80, 255, 170),
			solid = 0.55,
			gap = 0.5,
			scale = 1,
		},
		frost = {
			top = Color3.fromRGB(228, 246, 255),
			bottom = Color3.fromRGB(70, 150, 255),
			solid = 0.7,
			gap = 0.45,
			scale = 0.85,
		},
		prism = {
			top = Color3.fromRGB(0, 230, 255),
			bottom = Color3.fromRGB(255, 64, 190),
			solid = 0.55,
			gap = 0.5,
			scale = 1,
		},
		grid = {
			top = Color3.fromRGB(0, 230, 255),
			bottom = Color3.fromRGB(175, 80, 255),
			solid = 0.1,
			gap = 0.25,
			scale = 1,
		},
		midas = {
			top = Color3.fromRGB(255, 240, 170),
			bottom = Color3.fromRGB(255, 212, 64),
			solid = 0.9,
			gap = 0.4,
			scale = 0.95,
		},
		eclipse = {
			top = Color3.fromRGB(210, 200, 255),
			bottom = Color3.fromRGB(20, 8, 34),
			solid = 1,
			gap = 0.5,
			scale = 0.9,
		},
		halo = {
			-- POLARIS pack: a thin spectral ring — barely a disk, mostly
			-- outline, like the polar sun that never quite rises.
			top = Color3.fromRGB(245, 238, 255),
			bottom = Color3.fromRGB(190, 120, 255),
			solid = 0.15,
			gap = 0.25,
			scale = 0.9,
		},
		tide = {
			-- NEON REEF pack: lagoon cyan sinking into deep-water blue.
			top = Color3.fromRGB(0, 230, 255),
			bottom = Color3.fromRGB(70, 150, 255),
			solid = 0.6,
			gap = 0.45,
			scale = 0.9,
		},
		null = {
			-- NULL pack: a dying sun — sparse ghost-grey strips, barely
			-- holding together against the empty sky.
			top = Color3.fromRGB(205, 205, 225),
			bottom = Color3.fromRGB(70, 70, 95),
			solid = 0.2,
			gap = 0.7,
			scale = 0.85,
		},
		alpine = {
			-- NEON PEAKS pack: glacial cyan burning off into summit
			-- violet — a cold sun for a ridge-line world.
			top = Color3.fromRGB(170, 230, 255),
			bottom = Color3.fromRGB(140, 90, 220),
			solid = 0.45,
			gap = 0.45,
			scale = 0.9,
		},
		noon = {
			-- APE BALL pack: a high warm sun for the day-shift sky —
			-- dense golden dome, stripes barely visible at the rim.
			top = Color3.fromRGB(255, 246, 185),
			bottom = Color3.fromRGB(255, 200, 70),
			solid = 0.85,
			gap = 0.4,
			scale = 1,
		},
	},
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
	-- Deck ribbon primitives (TrackStreamer; the garage preview's
	-- real-scale mini-lane reads the same values so the two can't drift).
	DeckColor = Color3.fromRGB(10, 6, 16), -- purple-black deck; the neon grid carries the read
	EdgeW = 0.6, -- neon edge-rail width, studs
	EdgeH = 0.25, -- neon edge-rail height above the deck surface
	GridH = 0.08, -- grid/center neon strip thickness
	CenterW = 0.35, -- longitudinal center-line width
	-- Banked-deck continuity (§8.6): each slice pivots about the deck
	-- centerline, so a roll change across it leaves a lip at the edge.
	-- TrackStreamer halves rolling spans until the edge step fits this —
	-- FullTilt's ramps emit as many fine slabs as needed, flat and held
	-- spans still merge to single parts.
	RollLipMax = 0.35, -- max vertical seam step at the deck edge, studs
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

-- COLOR LAB (§18): player-picked hues for the `customA/B/C` item params.
-- Attributes RoBallHueA (ring set A + deathfx accent A), RoBallHueB
-- (ring set B + accent B), RoBallHueC (trail + gem fx) hold 0..1 hues.
-- Min/Max is the legal band — it excludes the red seam around hue 0/1
-- where LethalColor lives, so sliders can't mix a lethal look (color law
-- extension: the picker's reachable space is pre-sanitized).
Config.CustomHue = {
	Min = 0.055, -- ≈ hue 20°: orange — red is cut out entirely
	Max = 0.9, -- ≈ hue 324°: rose/magenta — kept a clear step off crimson
	Sat = 0.92,
	Value = 1.0,
	Defaults = { a = 0.52, b = 0.9, c = 0.5 }, -- cyan / magenta / cyan
}

-- Menu feel (MENU.md): osu!-informed chrome — poster thump on the bed,
-- spring pickers, death stamp, menu scope strip. No hitsounds (§5).
Config.Menu = {
	ChromePulse = 0.04, -- §2 poster swell per pulse unit
	SpringStiff = 170, -- §4 cycler spring stiffness
	SpringDamp = 22, -- §4 damping (~critically damped, small overshoot)
	SpringDtMax = 1 / 20, -- §4 frame dt cap — a hitch must not slingshot the spring
	JacketPx = 40, -- §4 cycler overshoot amplitude in px
	-- §4 track jackets: the TRACK cycler's prev/current/next card strip —
	-- card px dims, inter-card gap, and the dim factor side cards fade to.
	Jacket = {
		W = 104, -- card px width
		H = 52, -- card px height
		Gap = 14, -- inter-card gap px
		SideDim = 0.5, -- side-card dim factor under the focused pick
	},
	-- §5: no menu hitsounds — deliberate silence; the bed + audition only.
	StampSec = 0.25, -- §7 death-hero stamp duration
	StampKick = 1.35, -- §7 the hero slams in past 100%, then settles
	StampDuck = 0.3, -- §7 duck depth when the card lands
	StampDuckRelease = 0.5,
	ParallaxPx = 6, -- §9 cursor drift garnish on: ±6px poster drift; 0 = off
}

Config.Leaderboard = {
	TopRunsStore = "RoBall3D_TopRuns_v1", -- OrderedDataStore: userId -> best score
	BestStore = "RoBall3D_Best_v1", -- DataStore: personal best + last seed
	ProfileStore = "RoBall3D_Profile_v1", -- DataStore: equipped cosmetic ids (§18)
	-- Daily board (§14): a per-day OrderedDataStore pair — prefix .. YYYYMMDD
	-- (+ "_Meta" for the seed row). Old days simply go unread; no cleanup.
	DailyStorePrefix = "RoBall3D_Daily_v1_",
	TopCount = 20,
	SaveRetryCount = 3,
	CacheSeconds = 45, -- server-side top-board cache: menu fetches share it
	FetchCooldown = 8, -- per-player GetLeaderboard throttle -> cached rows
	-- Recent runs (§14): profile-persisted history, newest first; the menu
	-- strip shows the newest few, a click prefills the seed box.
	HistoryCount = 8,
	HistoryShown = 5,
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
	-- Test mode ON (debug testing): every pack/product grants instantly on
	-- click with no purchase prompt. MUST be false before release —
	-- production state prompts real dashboard ids, 0-id entries show SOON (§18).
	FreeForTesting = true,
	Passes = {
		-- Every live pack is a complete 7-slot look (Cosmetics.Bundles §18).
		starter = 0, -- STARTER NEON — sunset set + palms world (~49)
		peaks = 0, -- NEON PEAKS — summit set + ridge world (~149)
		synthwave = 0, -- SYNTHWAVE — prism set + grid world (~149)
		midas = 0, -- MIDAS — gold set + meteor world (~149)
		vip = 0, -- VOID VIP — violet set + star-well world (~199)
		bank2x = 0, -- 2X BANK — every pickup banks double, forever (~99)
		aurora = 0, -- AURORA — borealis set + aurora sky (~149)
		polaris = 0, -- POLARIS — phantom set + polar sky (~149)
		acid = 0, -- TOXIC SLUDGE — acid set + peaks world (~149)
		reef = 0, -- NEON REEF — lagoon set + reef world (~199)
		null = 0, -- NULL — mono set + empty world (~149)
		solstice = 0, -- SOLSTICE — seasonal frost set + polar sky (~149)
		apeball = 0, -- APE BALL — capsule set + sky court world (~199)
		-- Retired ids: no longer sold, but already-owned passes keep
		-- granting their contents through Cosmetics.LegacyBundles.
		phantom = 0,
		deepspace = 0,
		inferno = 0,
		candy = 0,
		colorlab = 0,
		sunkissed = 0,
		miami = 0,
		vhs = 0,
	},
	Price = {
		starter = 49,
		synthwave = 149,
		midas = 149,
		vip = 199,
		bank2x = 99,
		peaks = 149,
		aurora = 149,
		phantom = 199,
		deepspace = 149,
		solstice = 149,
		apeball = 199,
		acid = 149,
		reef = 199,
		null = 149,
		inferno = 149,
		candy = 149,
		colorlab = 249,
		sunkissed = 149,
		miami = 149,
		vhs = 99,
		polaris = 149,
	},
	-- Seasonal slot (§18): ONE rotating bundle gated on a yearly UTC
	-- window so the garage always has something coming or going. The
	-- window recurs annually; wrap-around ranges (Dec → Jan) are legal.
	-- Outside the window the pack button shows "IN Nd" and the server
	-- refuses the bundle AND its member items à-la-carte — owned pieces
	-- keep working year-round once granted.
	Seasonal = {
		Bundle = "solstice", -- Cosmetics.Bundles id the window gates
		Start = { 12, 15 }, -- {month, day} UTC, inclusive
		End = { 1, 8 }, -- {month, day} UTC, inclusive
	},
	-- Gem bank (§18 P2): each pickup banks this many gems, credited live.
	BankPerGem = 1,
	-- Daily streak (§14): finishing a daily-seeded run pays
	-- min(streak, cap) * bonus banked gems — retention reward, never score.
	DailyStreakBonus = 10,
	DailyStreakCap = 10,
	-- Daily quests (§14): three seeded missions per UTC day — the day's
	-- seed picks one target per pool. Rewards pay banked gems, never
	-- score; progress counts on any run, not just daily-seeded ones.
	Quests = {
		ReachTargets = { 1200, 1500, 1800, 2200, 2600 }, -- reach N m in one run
		ScoreTargets = { 1600, 2000, 2600, 3200 }, -- score N in one run
		BankTargets = { 60, 100, 140, 200 }, -- bank N gems today (all runs)
		Rewards = { reach = 40, score = 60, bank = 50 },
	},
	-- Achievements (§14): milestone badges, server-evaluated at clean run
	-- end. kind: runDist (one run), lifetimeGems / runs (profile stats),
	-- streak (daily streak), questsAll (all 3 day missions done). Rewards
	-- pay banked gems — never score. Persisted in profile.achievements.
	Achievements = {
		{ id = "ignition", name = "IGNITION", desc = "finish a run", kind = "runs", target = 1, reward = 5 },
		{
			id = "k1",
			name = "KILOMETER",
			desc = "reach 1000m in one run",
			kind = "runDist",
			target = 1000,
			reward = 20,
		},
		{
			id = "k25",
			name = "DEEP CUT",
			desc = "reach 2500m in one run",
			kind = "runDist",
			target = 2500,
			reward = 40,
		},
		{
			id = "k5",
			name = "TERMINAL VELOCITY",
			desc = "reach 5000m in one run",
			kind = "runDist",
			target = 5000,
			reward = 80,
		},
		{
			id = "bank100",
			name = "COLLECTOR",
			desc = "bank 100 gems lifetime",
			kind = "lifetimeGems",
			target = 100,
			reward = 25,
		},
		{
			id = "bank1k",
			name = "VAULT",
			desc = "bank 1000 gems lifetime",
			kind = "lifetimeGems",
			target = 1000,
			reward = 100,
		},
		{ id = "streak3", name = "REGULAR", desc = "3-day streak", kind = "streak", target = 3, reward = 30 },
		{
			id = "quests3",
			name = "DAILY GRIND",
			desc = "finish all 3 day missions",
			kind = "questsAll",
			target = 3,
			reward = 60,
		},
	},
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
	-- Master switch for debug features — MUST be false for release
	-- (PRODUCTION_PROMPT.md checklist): feature-seed keywords in the seed
	-- box stop resolving, so nobody can spawn a single-feature farm map
	-- on the live servers. Forced runs are also flagged ineligible for
	-- every score/quest/streak path in Main.server killRun regardless.
	Enabled = true,
	-- GenVerify solvability sweep (DESIGN.md §8.6): Studio-only audit that
	-- walks seeds asserting corridor/reaction/ballistic invariants on every
	-- generated chunk. 0 seeds = off (production playtests stay clean).
	VerifySeeds = 8,
	VerifyChunks = 600,
	-- Feature-seed runway (DESIGN.md §7): flat approach in front of a
	-- feature-forced track so the element is visible on the roll-in.
	-- ~3s at Speed.Start.
	FeatureRunway = 100,
}

return Config
