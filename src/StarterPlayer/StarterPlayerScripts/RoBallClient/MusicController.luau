--!strict
-- MusicController (AUDIO.md §4): the music runtime on the audio-graph API
-- (AudioPlayer + Wires + FX — Sound/SoundGroup are the discouraged path).
--
-- Modes:
--   single-track — one AudioPlayer on the track's TrackAssets.AssetId
--   layered      — one AudioPlayer + AudioFader per stem, tier-mixed by
--                  Config.Music.Layers, once every Stems id resolves
--
-- Track rotation (AUDIO.md §3): each run plays SongMap.trackIdFor(seed,
-- Tracklist) — GenCore stamps sections from the same pick. Switching
-- tracks tears down and rebuilds the stem/single player set; the shared
-- bus tail (filter/shifter/analyzer) and stings persist.
--
-- Shared behavior either way:
--   PlaybackSpeed ramps with ball speed on every player (the speed signature)
--   AudioPitchShifter counters PitchCompensation of the squeak
--   AudioFilter lowpass on the bus: menu muffle, death tape-stop sweep
--   AudioAnalyzer tap feeds Music.sample() for audio-reactive visuals
--   Beat clock = lead.TimePosition -> SongBeats; tier stings quantize to
--   the next bar line; a watchdog snaps drifting stems on every loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.RoBall.Config)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)
local MusicGrid = require(ReplicatedStorage.RoBall.MusicGrid)

local m = Config.Music

local Music = {}

local player = Players.LocalPlayer

local root: Folder? = nil
local players: { any } = {} -- ordered AudioPlayer list (ipairs-safe)
local stemByName: { [string]: any } = {}
local faders: { any } = {} -- stem name -> AudioFader (layered mode only)
local stemMode = false
local lead: any = nil -- beat-clock + watchdog reference player
local lowpass: any = nil
local shifter: any = nil
local duckFader: any = nil
local sfxFader: any = nil -- post-duck tap for one-shot voices (gem chimes)
local duckGen = 0 -- duck() generation: a newer dip cancels an older release
local analyzer: any = nil
local windPlayer: any = nil
local windFilter: any = nil
local windFader: any = nil
local stingPlayers: { [string]: any } = {}

local norm = 0 -- last speedNorm, kept so layer fades and stings see it
local tier = 1
local pulseSmooth = 0
local curMap: SongMap.Map = SongMap -- active track's chart (default until a run picks)
local curTrack: string? = nil
local curAssets: any = nil -- active track's TrackAssets entry

local STEM_ORDER = { "pad", "air", "bass", "drums", "arp", "lead" }

local function wire(src: Instance, dst: Instance)
	local w = Instance.new("Wire")
	w.SourceInstance = src
	w.TargetInstance = dst
	w.Parent = root
end

-- Stem/sting ids may be numeric (rbxassetid) or full ContentId strings —
-- rbxasset:// entries point at Studio's bundled content dir for local dev.
local function contentId(v: any): string
	return type(v) == "string" and v or "rbxassetid://" .. tostring(v)
end

local function newPlayer(asset: string, looped: boolean): any
	local p = Instance.new("AudioPlayer")
	p.Asset = asset
	p.Looping = looped
	p.AutoLoad = true
	p.Volume = m.Volume
	p.Parent = root
	return p
end

local function ps(): number
	return MusicGrid.playbackSpeedForNorm(norm)
end

local lastPs: number = 0 -- last applied step; steps glide, holds are free
local windSmV = 0 -- smoothed wind fader level
local windSmHz = m.WindCutMin -- smoothed wind cutoff
local windLastT = tick()

local function applySpeed()
	local speed = ps()
	if speed ~= lastPs then
		-- Tempo steps (Config.Music.TempoStepSt): a new step glides in over
		-- TempoStepGlide — reads as a deliberate tempo/key lift, not warble.
		local glide = lastPs == 0 and 0 or m.TempoStepGlide
		for _, p in ipairs(players) do
			if glide > 0 then
				TweenService:Create(p, TweenInfo.new(glide, Enum.EasingStyle.Quad), { PlaybackSpeed = speed }):Play()
			else
				p.PlaybackSpeed = speed
			end
		end
		if shifter then
			local pitch = speed ^ -m.PitchCompensation
			if glide > 0 then
				TweenService:Create(shifter, TweenInfo.new(glide, Enum.EasingStyle.Quad), { Pitch = pitch }):Play()
			else
				shifter.Pitch = pitch
			end
		end
		lastPs = speed
	end
	if windFader then
		-- Exponential smoothing (~140ms approach): the wind bed tracks
		-- speed every heartbeat — hard sets would zipper-noise the filter
		-- and step the loudness. dt-based so it's frame-rate independent.
		local now = tick()
		local k = math.min(1, (now - windLastT) * 7)
		windLastT = now
		windSmV += (m.WindVolume * norm * norm - windSmV) * k
		windSmHz += (m.WindCutMin + (m.WindCutMax - m.WindCutMin) * norm - windSmHz) * k
		windFader.Volume = windSmV
		windFilter.Frequency = windSmHz
	end
end

-- Layer fades complete over FadeBars bars at the CURRENT heard tempo —
-- mix moves land on bar lines, not mid-phrase.
local function fadeSeconds(): number
	return m.FadeBars * curMap.beatsPerBar / (curMap.bpm * ps() / 60)
end

local function applyLayers()
	if not stemMode then
		return
	end
	local secs = fadeSeconds()
	local info = TweenInfo.new(secs, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for _, name in ipairs(STEM_ORDER) do
		local f = faders[name]
		local layer = m.Layers[name]
		if f and layer then
			local target = layer[math.min(tier, #layer)] or 1
			TweenService:Create(f, info, { Volume = target }):Play()
		end
	end
end

local function setFilter(hz: number, secs: number)
	if lowpass then
		TweenService:Create(lowpass, TweenInfo.new(secs), { Frequency = hz }):Play()
	end
end

local function playStingNowOrQueued(name: string)
	local id = (m.Stings :: any)[name]
	if id == nil or id == 0 or not root then
		return
	end
	local p = stingPlayers[name]
	if not p then
		p = newPlayer(contentId(id), false)
		wire(p, lowpass)
		stingPlayers[name] = p
	end
	p:Play()
end

local function syncStems()
	-- Equal-length streams hold sync, but verify: snap any follower that
	-- drifted past SyncDriftMs against the lead's position.
	if not stemMode or not lead then
		return
	end
	local ref = lead.TimePosition
	for _, p in ipairs(players) do
		if p ~= lead and math.abs(p.TimePosition - ref) > m.SyncDriftMs / 1000 then
			p.TimePosition = ref
		end
	end
end

-- Tear down the current track's player set (track switch at run start).
-- The bus tail, wind, and sting players are shared and survive.
local function teardownPlayers()
	for _, p in ipairs(players) do
		p:Destroy()
	end
	for _, f in pairs(faders) do
		f:Destroy()
	end
	table.clear(players)
	table.clear(faders)
	table.clear(stemByName)
	stemMode = false
	lead = nil
end

-- Readiness watchdog: stems take a few seconds to decode — poll for up
-- to 15s. If any still isn't ready (bad id, or an rbxasset:// dev path
-- on a published client) tear the layered set down to the track's full
-- mix rather than ship a butchered mix or silence.
local function watchStems()
	local track = curTrack -- stale watchdogs yield to the new track's
	task.spawn(function()
		local deadline = os.clock() + 15
		repeat
			local allReady = true
			for _, p in ipairs(players) do
				if not p.IsReady then
					allReady = false
					break
				end
			end
			if allReady or os.clock() > deadline then
				break
			end
			task.wait(0.5)
		until false
		if not stemMode or curTrack ~= track then
			return
		end
		for _, p in ipairs(players) do
			if not p.IsReady then
				teardownPlayers()
				local mix = newPlayer(contentId(curAssets.AssetId), true)
				mix.Volume = m.MenuVolume * m.Volume
				wire(mix, lowpass)
				table.insert(players, mix)
				lead = mix
				applySpeed()
				mix:Play()
				return
			end
		end
		-- All decoded: snap once — startup decode stagger leaves tens of ms
		-- of skew the per-loop Looped watchdog won't reach until first wrap.
		syncStems()
	end)
end

-- Build the player set for one TrackAssets entry: layered when every stem
-- resolves, else a single AudioPlayer on the full mix.
local function buildPlayers(ta: any)
	stemMode = type(ta.Stems) == "table"
	if stemMode then
		for _, name in ipairs(STEM_ORDER) do
			local id = ta.Stems[name]
			if id == nil or id == 0 or id == "" then
				stemMode = false
				break
			end
		end
	end

	if stemMode then
		for _, name in ipairs(STEM_ORDER) do
			local p = newPlayer(contentId(ta.Stems[name]), true)
			local f = Instance.new("AudioFader")
			f.Volume = 0 -- faded in by applyLayers
			f.Parent = root
			wire(p, f)
			wire(f, lowpass)
			table.insert(players, p)
			stemByName[name] = p
			faders[name] = f
		end
		lead = stemByName.lead or stemByName.drums or players[1]
		lead.Looped:Connect(syncStems)
		watchStems()
	else
		local p = newPlayer(contentId(ta.AssetId), true)
		wire(p, lowpass)
		table.insert(players, p)
		lead = p
	end
end

-- Point the runtime at a track: resolves its SongMap + assets and rebuilds
-- the player set when it differs from what's playing.
local function selectTrack(id: string)
	if id == curTrack then
		return
	end
	-- Splice dip (AUDIO.md §3): swapping the player set is a hard cut —
	-- a ~50ms duck masks the teardown click without costing a fade-in.
	local wasLive = lead ~= nil and lead.IsPlaying
	curTrack = id
	curMap = SongMap.forTrack(id)
	curAssets = (m.TrackAssets :: any)[id] or { AssetId = 0 }
	teardownPlayers()
	if wasLive then
		Music.duck(0.45, 0.35)
	end
	buildPlayers(curAssets)
end

function Music.init()
	if root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RoBallAudio"
	folder.Parent = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	root = folder

	-- Bus tail: lowpass -> pitch shifter -> output, with an analyzer tap
	lowpass = Instance.new("AudioFilter")
	lowpass.FilterType = Enum.AudioFilterType.Lowpass24dB
	lowpass.Frequency = m.OpenCutoffHz
	lowpass.Parent = folder

	local k = m.PitchCompensation
	if k > 0 then
		shifter = Instance.new("AudioPitchShifter")
		shifter.Parent = folder
	end

	-- Bus fader for the pickup sidechain duck (AUDIO.md §6): gem chimes
	-- knock the whole mix down a touch and let it bloom back — the pickup
	-- "punches" the track like a producer's sidechain.
	duckFader = Instance.new("AudioFader")
	duckFader.Volume = 1
	duckFader.Parent = folder

	local output = Instance.new("AudioDeviceOutput")
	output.Parent = folder
	wire(lowpass, shifter or duckFader)
	if shifter then
		wire(shifter, duckFader)
	end
	wire(duckFader, output)

	-- SFX voices (gem chimes) tap the bus AFTER the duck fader — a pickup
	-- ducks the music, never itself (true sidechain) — and stay clear of
	-- the lowpass + shifter: the payout reads bright even under the menu
	-- muffle, and the shifter can't detune the combo ladder's semitones.
	sfxFader = Instance.new("AudioFader")
	sfxFader.Volume = 1
	sfxFader.Parent = folder
	wire(sfxFader, output)

	analyzer = Instance.new("AudioAnalyzer")
	analyzer.SpectrumEnabled = true
	analyzer.Parent = folder
	-- Post-duck tap: visuals follow the heard level — the world dims on
	-- the same sidechain dip the ear hears.
	wire(duckFader, analyzer)

	-- Menu boots on the dedicated menu bed (Config.Music.menuTrackId
	-- resolves MenuTrack when uploaded, else the seeded default); runs
	-- re-pick per seed in onStart.
	selectTrack(m.menuTrackId())

	-- Speed-wind bed (optional until the asset is uploaded)
	if m.WindAssetId ~= 0 then
		windPlayer = newPlayer(contentId(m.WindAssetId), true)
		windFilter = Instance.new("AudioFilter")
		windFilter.FilterType = Enum.AudioFilterType.Lowpass12dB
		windFilter.Frequency = m.WindCutMin
		windFilter.Parent = folder
		windFader = Instance.new("AudioFader")
		windFader.Volume = 0
		windFader.Parent = folder
		wire(windPlayer, windFilter)
		wire(windFilter, windFader)
		wire(windFader, lowpass)
		task.defer(function()
			windPlayer:Play()
		end)
	end

	-- Boot in the menu state: same track, muffled under the lowpass.
	lowpass.Frequency = m.MenuCutoffHz
	for _, p in ipairs(players) do
		p.Volume = m.MenuVolume * m.Volume
	end
	applySpeed()
	for _, p in ipairs(players) do
		p:Play() -- queued until IsReady by the engine
	end
end

function Music.onStart(seed: number?)
	if not lead then
		return
	end
	-- GD-style: every run opens on the grid. Instant restart is sacred —
	-- no fade-in tax, filter snaps open on the count-in. The seed picks
	-- the track AND rotates the opening accent across downbeats
	-- (AUDIO.md §3/§6); GenCore picks and seeds its clock identically.
	if seed then
		selectTrack(SongMap.trackIdFor(seed, m.ActiveTracklist))
	end
	local startBeat = 0
	if seed and Config.MusicSync.SeededStartOffset then
		startBeat = curMap.startBeatFor(seed)
	end
	local startSec = startBeat * 60 / curMap.bpm
	applySpeed()
	for _, p in ipairs(players) do
		p.Volume = m.Volume
		p.PlaybackSpeed = ps()
		p.TimePosition = startSec
		if not p.IsPlaying then
			p:Play()
		end
	end
	if windPlayer and not windPlayer.IsPlaying then
		windPlayer:Play()
	end
	tier = 1
	applyLayers()
	setFilter(m.OpenCutoffHz, 0.25)
	playStingNowOrQueued("menuStart")
end

function Music.onDeath()
	-- Tape-stop (AUDIO.md §7): pitch slide + lowpass sweep shut together,
	-- held under the death screen until the next run snaps it open.
	for _, p in ipairs(players) do
		TweenService:Create(p, TweenInfo.new(m.FilterSweepTime), { PlaybackSpeed = m.DeathPitchFloor }):Play()
	end
	setFilter(m.DeathCutoffHz, m.FilterSweepTime)
	if shifter then
		-- pitch compensation would fight the slide — open it back up
		TweenService:Create(shifter, TweenInfo.new(m.FilterSweepTime), { Pitch = 1 }):Play()
	end
	if windFader then
		TweenService:Create(windFader, TweenInfo.new(m.FilterSweepTime), { Volume = 0 }):Play()
	end
	playStingNowOrQueued("deathFall")
end

-- Back to the menu (§18: the garage lives there): reverse the tape-stop —
-- playback speed and the lowpass ease back to the muffled menu bed.
function Music.onMenu()
	selectTrack(m.menuTrackId()) -- parked bed, not the run's seeded pick
	norm = 0
	local speed = ps()
	for _, p in ipairs(players) do
		TweenService:Create(p, TweenInfo.new(m.FilterSweepTime), { PlaybackSpeed = speed }):Play()
		p.Volume = m.MenuVolume * m.Volume
	end
	if shifter then
		TweenService:Create(shifter, TweenInfo.new(m.FilterSweepTime), { Pitch = speed ^ -m.PitchCompensation }):Play()
	end
	setFilter(m.MenuCutoffHz, m.FilterSweepTime)
end

-- speedNorm (ball fwdSpeed vs Speed.Start..Max). The top is UNclamped —
-- endless speed ramps forever, so the tempo keeps lifting past norm 1.
function Music.setSpeedNorm(n: number)
	norm = math.max(n, 0)
	applySpeed()
end

-- Heard tempo right now (AUDIO.md §4): the track's bpm x the snapped
-- playback speed applied to the players — the HUD's BPM digit, so the
-- number steps in semitones exactly when the music does.
function Music.bpm(): number
	return curMap.bpm * ps()
end

-- Tier index from the client drive loop: layer mix + beat-quantized sting.
function Music.setTier(t: number)
	if t == tier then
		return
	end
	tier = t
	applyLayers()
	if t > 1 then
		Music.playSting("tierUp")
	end
end

-- Song-beats elapsed in the composition (asset time — PlaybackSpeed only
-- changes how fast we traverse it).
function Music.beatPos(): number
	if not lead then
		return 0
	end
	return lead.TimePosition * curMap.bpm / 60
end

function Music.section(): SongMap.Section
	return curMap.sectionAtBeat(Music.beatPos())
end

-- Sidechain-style duck (AUDIO.md §6): knock the bus down `depth` and let
-- it bloom back over `release` seconds. Gem pickups call this so a chime
-- punches through the track instead of stacking on it. The dip itself is
-- a ~15ms tween — a hard gain step is an audible click; fast-but-smooth
-- keeps the punch. Generation-guarded: a rapid second pickup cancels the
-- previous release so dips re-trigger cleanly instead of fighting.
function Music.duck(depth: number, release: number?)
	if not duckFader then
		return
	end
	duckGen += 1
	local gen = duckGen
	local dip = TweenService:Create(duckFader, TweenInfo.new(0.015), { Volume = 1 - depth })
	dip:Play()
	dip.Completed:Once(function()
		if gen == duckGen then
			TweenService:Create(
				duckFader,
				TweenInfo.new(release or 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Volume = 1 }
			):Play()
		end
	end)
end

-- One-shot voice on the post-duck SFX tap (see init): takes a resolved
-- ContentId string, plays at `speedRatio`, self-destroys. Returns false
-- when the bus isn't built so callers can fall back to a plain Sound.
function Music.playOneShot(asset: string, speedRatio: number, volume: number): boolean
	if not sfxFader or not root then
		return false
	end
	local p = Instance.new("AudioPlayer")
	p.Asset = asset
	p.Looping = false
	p.AutoLoad = true
	p.PlaybackSpeed = speedRatio
	p.Volume = volume
	p.Parent = root
	wire(p, sfxFader)
	p:Play()
	-- AudioPlayer.Ended is unreliable for clean-up; the gem file is 0.75s
	-- and the slowest ladder step plays it back at ~0.25x — 4s covers all.
	task.delay(4, function()
		if p.Parent then
			p:Destroy()
		end
	end)
	return true
end

-- Warm a one-shot's decode at boot so its first real play isn't late:
-- AutoLoad pulls the asset into memory without ever pressing Play.
function Music.preloadSfx(asset: string)
	if not root then
		return
	end
	local p = Instance.new("AudioPlayer")
	p.Asset = asset
	p.AutoLoad = true
	p.Parent = root
	task.spawn(function()
		local deadline = os.clock() + 10
		while not p.IsReady and os.clock() < deadline and p.Parent do
			task.wait(0.25)
		end
		p:Destroy()
	end)
end

-- Seconds until the next `subdiv`-of-a-beat boundary on the HEARD grid —
-- lets pickup chimes land on a subdivision even if the touch was early.
-- Returns 0 when the wait would exceed `cap` (don't add audible latency).
function Music.nextGridDelay(subdiv: number, cap: number): number
	if not lead or not lead.IsPlaying then
		return 0
	end
	local beatsNow = Music.beatPos()
	local nextB = math.ceil(beatsNow * subdiv - 1e-4) / subdiv
	local delay = (nextB - beatsNow) * 60 / (curMap.bpm * ps())
	return delay <= cap and delay or 0
end

-- Beat-quantized one-shots (AUDIO.md §6): the sting waits for the next
-- bar line so it lands ON the grid, GD-trigger style.
function Music.playSting(name: string)
	local id = (m.Stings :: any)[name]
	if id == nil or id == 0 or not lead or not lead.IsPlaying then
		return
	end
	local beatsNow = Music.beatPos()
	local nextBar = math.ceil(beatsNow / curMap.beatsPerBar) * curMap.beatsPerBar
	local delay = math.max(0, (nextBar - beatsNow) / (curMap.bpm * ps() / 60))
	if delay > 4 then
		return -- pathological; a bar is never this far out
	end
	task.delay(delay, function()
		playStingNowOrQueued(name)
	end)
end

-- Audio-reactive pulse for visuals (AUDIO.md §8): smoothed 0..1 energy
-- mixed from overall level + low spectrum bins. Client-only by design —
-- the analyzer reads zeros on the server, which is fine: decorative only.
function Music.sample(): number
	if not analyzer then
		return 0
	end
	local energy = analyzer.RmsLevel
	local ok, spectrum = pcall(function()
		return analyzer:GetSpectrum()
	end)
	if ok and type(spectrum) == "table" and #spectrum >= 8 then
		local bass = 0
		for i = 2, 8 do
			bass += spectrum[i]
		end
		energy = math.max(energy, bass / 7)
	end
	-- attack fast, release slow — reads as a thump not a strobe
	pulseSmooth = math.max(energy, pulseSmooth * 0.88)
	return pulseSmooth
end

return Music
