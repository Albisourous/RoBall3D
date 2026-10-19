--!strict
-- MusicController (AUDIO.md §4): the music runtime on the audio-graph API
-- (AudioPlayer + Wires + FX — Sound/SoundGroup are the discouraged path).
--
-- Modes:
--   single-track — one AudioPlayer on Config.Music.AssetId (works today)
--   layered     — one AudioPlayer + AudioFader per stem, tier-mixed by
--                 Config.Music.Layers, once every Stems id is filled in
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
local analyzer: any = nil
local windPlayer: any = nil
local windFilter: any = nil
local windFader: any = nil
local stingPlayers: { [string]: any } = {}

local norm = 0 -- last speedNorm, kept so layer fades and stings see it
local tier = 1
local pulseSmooth = 0

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
	return m.PlaybackSpeedMin + (m.PlaybackSpeedMax - m.PlaybackSpeedMin) * norm
end

local function applySpeed()
	local speed = ps()
	for _, p in ipairs(players) do
		p.PlaybackSpeed = speed
	end
	if shifter then
		shifter.Pitch = speed ^ -m.PitchCompensation
	end
	if windFader then
		windFader.Volume = m.WindVolume * norm * norm
	end
	if windFilter then
		windFilter.Frequency = m.WindCutMin + (m.WindCutMax - m.WindCutMin) * norm
	end
end

-- Layer fades complete over FadeBars bars at the CURRENT heard tempo —
-- mix moves land on bar lines, not mid-phrase.
local function fadeSeconds(): number
	return m.FadeBars * SongMap.beatsPerBar / (m.BaseBpm * ps() / 60)
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

	local output = Instance.new("AudioDeviceOutput")
	output.Parent = folder
	wire(lowpass, shifter or output)
	if shifter then
		wire(shifter, output)
	end

	analyzer = Instance.new("AudioAnalyzer")
	analyzer.SpectrumEnabled = true
	analyzer.Parent = folder
	wire(lowpass, analyzer) -- hears what you hear (post-filter)

	-- Mode select: layered only when every stem has an asset id/URI
	stemMode = true
	for _, name in ipairs(STEM_ORDER) do
		local id = (m.Stems :: any)[name]
		if id == nil or id == 0 or id == "" then
			stemMode = false
			break
		end
	end

	if stemMode then
		for _, name in ipairs(STEM_ORDER) do
			local p = newPlayer(contentId((m.Stems :: any)[name]), true)
			local f = Instance.new("AudioFader")
			f.Volume = 0 -- faded in by applyLayers
			f.Parent = folder
			wire(p, f)
			wire(f, lowpass)
			table.insert(players, p)
			stemByName[name] = p
			faders[name] = f
		end
		lead = stemByName.lead or stemByName.drums or players[1]
		lead.Looped:Connect(syncStems)
	else
		local p = newPlayer(contentId(m.AssetId), true)
		wire(p, lowpass)
		table.insert(players, p)
		lead = p
	end

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

	-- Readiness watchdog: stems take a few seconds to decode — poll for up
	-- to 15s. If any still isn't ready (bad id, or an rbxasset:// dev path
	-- on a published client) tear the whole layered set down to the master
	-- mix rather than ship a butchered mix or silence.
	if stemMode then
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
			if not stemMode then
				return
			end
			for _, p in ipairs(players) do
				if not p.IsReady then
					for _, q in ipairs(players) do
						q:Destroy()
					end
					for _, f in pairs(faders) do
						f:Destroy()
					end
					players = {}
					faders = {}
					stemByName = {}
					stemMode = false
					local mix = newPlayer(contentId(m.AssetId), true)
					mix.Volume = m.MenuVolume * m.Volume
					wire(mix, lowpass)
					table.insert(players, mix)
					lead = mix
					applySpeed()
					mix:Play()
					return
				end
			end
		end)
	end
end

function Music.onStart()
	if not lead then
		return
	end
	-- GD-style: every run re-hears the track from the top. Instant restart
	-- is sacred — no fade-in tax, filter snaps open on the count-in.
	applySpeed()
	for _, p in ipairs(players) do
		p.Volume = m.Volume
		p.PlaybackSpeed = ps()
		p.TimePosition = 0
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
	norm = 0
	local speed = ps()
	for _, p in ipairs(players) do
		TweenService:Create(p, TweenInfo.new(m.FilterSweepTime), { PlaybackSpeed = speed }):Play()
		p.Volume = m.MenuVolume * m.Volume
	end
	if shifter then
		TweenService:Create(
			shifter,
			TweenInfo.new(m.FilterSweepTime),
			{ Pitch = speed ^ -m.PitchCompensation }
		):Play()
	end
	setFilter(m.MenuCutoffHz, m.FilterSweepTime)
end

-- speedNorm 0..1 (ball fwdSpeed between Speed.Start and Speed.Max).
function Music.setSpeedNorm(n: number)
	norm = math.clamp(n, 0, 1)
	applySpeed()
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
	return lead.TimePosition * m.BaseBpm / 60
end

function Music.section(): { kind: string, energy: number }
	return SongMap.sectionAtBeat(Music.beatPos())
end

-- Beat-quantized one-shots (AUDIO.md §6): the sting waits for the next
-- bar line so it lands ON the grid, GD-trigger style.
function Music.playSting(name: string)
	local id = (m.Stings :: any)[name]
	if id == nil or id == 0 or not lead or not lead.IsPlaying then
		return
	end
	local beatsNow = Music.beatPos()
	local nextBar = math.ceil(beatsNow / SongMap.beatsPerBar) * SongMap.beatsPerBar
	local delay = math.max(0, (nextBar - beatsNow) / (m.BaseBpm * ps() / 60))
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
