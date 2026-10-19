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

-- One physical Sound per voice; shares a PlaybackSpeed ratio so a dyad
-- stays consonant.
local function spawnChime(cfg, semi: number, volume: number, jitter: number)
	local s = Instance.new("Sound")
	s.Name = "GemPickup"
	if cfg.AssetId ~= 0 then
		s.SoundId = "rbxassetid://" .. tostring(cfg.AssetId)
	else
		s.SoundId = cfg.FallbackId
	end
	s.PlaybackSpeed = 2 ^ (semi / 12) * jitter
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
	spawnChime(cfg, semi, vol, jitter)
	-- Harmony gloss from the second pickup on: a quiet perfect fifth under
	-- the melody — consonant against any chord tone, reads as a shimmer.
	if combo >= 1 then
		spawnChime(cfg, semi + cfg.HarmonySemi, cfg.Volume * cfg.HarmonyVolume, jitter)
	end
end

function Sfx.init()
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
