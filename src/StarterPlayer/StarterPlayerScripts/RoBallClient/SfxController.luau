--!strict
-- SfxController: gem pickup chime. Listens to the server-driven
-- RoBallGems attribute and plays a short bell on every increase.
-- Rapid pickups in a row climb an A-minor pentatonic ladder
-- (ComboScale semitones) so clustered gem lines play little runs
-- instead of machine-gun flat repeats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Music = require(script.Parent.MusicController)

local Sfx = {}

local player = Players.LocalPlayer
local lastGems = 0
local lastAt = 0
local combo = 0

-- Resolve once: AssetId may be numeric (rbxassetid) or a full ContentId
-- URI — rbxasset:// entries resolve Studio's bundled content dir for dev.
local function assetUri(cfg): string
	if cfg.AssetId == 0 then
		return cfg.FallbackId
	elseif type(cfg.AssetId) == "string" then
		return cfg.AssetId
	else
		return "rbxassetid://" .. tostring(cfg.AssetId)
	end
end

-- One physical voice per chime; shares a PlaybackSpeed ratio so a dyad
-- stays consonant. Rides the post-duck SFX tap when the graph is up —
-- true sidechain: the pickup ducks the music, not itself. Falls back to
-- a plain Sound if the bus isn't built yet.
local function spawnChime(cfg, semi: number, volume: number, jitter: number)
	local ratio = 2 ^ (semi / 12) * jitter
	if Music.playOneShot(assetUri(cfg), ratio, volume) then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "GemPickup"
	s.SoundId = assetUri(cfg)
	s.PlaybackSpeed = ratio
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function chime()
	local cfg = Config.GemSfx
	local now = tick()
	combo = if now - lastAt < cfg.ComboWindow then combo + 1 else 0
	lastAt = now
	-- Section-aware harmony (AUDIO.md §6): the combo climbs the chord-tone
	-- ladder of whatever section is playing RIGHT NOW — a pickup run in the
	-- drop spells E7b9 tension; in the break it stays on Am9 color. Falls
	-- back to the generic pentatonic ladder off-grid / pre-init.
	local scale = cfg.ComboScale
	if Music.beatPos() > 0 then
		scale = Music.section().scale
	end
	-- Phrase shape: walk the ladder, wrapping into the next octave so long
	-- combos keep rising instead of stalling on the top rung; every
	-- CadenceEvery-th pickup resolves UP to the root's next octave — the
	-- run lands "on the octave" like a phrase cadence. Past MaxOctaves the
	-- line folds back down so pitches stay sweet, never shrill.
	local n = #scale
	local semi = scale[combo % n + 1] + 12 * math.floor(combo / n)
	if cfg.CadenceEvery > 0 and (combo + 1) % cfg.CadenceEvery == 0 then
		semi = scale[1] + 12 * (math.floor(semi / 12) + 1)
	end
	local cap = 12 * cfg.MaxOctaves
	if semi > cap then
		semi -= cap
	end
	local vol = cfg.Volume * math.min(cfg.ComboVolCap, 1 + combo * cfg.ComboVolGain)
	local jitter = 1 + (math.random() * 2 - 1) * cfg.PitchJitter
	-- Grid-snap (AUDIO.md §6): gems are already placed on beat subdivisions,
	-- so the touch lands near-grid — nudge the chime onto the next 32nd so
	-- the pickup phrase sits dead ON the heard tempo. Capped so it never
	-- adds audible latency; 0 when the music clock isn't running.
	local delay = Music.nextGridDelay(cfg.QuantizeSubdiv, cfg.QuantizeCap)
	task.delay(delay, function()
		spawnChime(cfg, semi, vol, jitter)
		-- Harmony gloss from the second pickup on: a quiet perfect fifth
		-- under the melody — consonant, reads as a shimmer.
		if combo >= 1 then
			spawnChime(cfg, semi + cfg.HarmonySemi, cfg.Volume * cfg.HarmonyVolume, jitter)
		end
	end)
	-- Sidechain punch: the pickup knocks the whole mix down and it blooms
	-- back — the chime reads as hitting the track, not stacking on it.
	Music.duck(cfg.DuckDepth, cfg.DuckRelease)
end

function Sfx.init()
	Music.preloadSfx(assetUri(Config.GemSfx)) -- warm the decode so the first pickup isn't late
	lastGems = player:GetAttribute("RoBallGems") or 0
	player:GetAttributeChangedSignal("RoBallGems"):Connect(function()
		local n = player:GetAttribute("RoBallGems") or 0
		if n > lastGems then
			chime()
		end
		lastGems = n
	end)
end

return Sfx
