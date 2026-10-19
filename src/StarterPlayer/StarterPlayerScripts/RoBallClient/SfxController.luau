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
local SongMap = require(ReplicatedStorage.RoBall.SongMap)
local Music = require(script.Parent.MusicController)

local Sfx = {}

local player = Players.LocalPlayer
local lastGems = 0
local lastAt = 0
local combo = 0

local function chime()
	local cfg = Config.GemSfx
	local s = Instance.new("Sound")
	s.Name = "GemPickup"
	if cfg.AssetId ~= 0 then
		s.SoundId = "rbxassetid://" .. tostring(cfg.AssetId)
	else
		s.SoundId = cfg.FallbackId
	end
	local now = tick()
	combo = if now - lastAt < cfg.ComboWindow then combo + 1 else 0
	lastAt = now
	-- Section-aware harmony (AUDIO.md §6): the combo climbs the chord-tone
	-- ladder of whatever section is playing RIGHT NOW — a pickup run in the
	-- drop spells E7b9 tension; in the break it stays on Am9 color. Falls
	-- back to the generic pentatonic ladder off-grid / pre-init.
	local scale = cfg.ComboScale
	if Music.beatPos() > 0 then
		scale = SongMap.sectionAtBeat(Music.beatPos()).scale
	end
	local rise = 2 ^ (scale[math.min(combo + 1, #scale)] / 12)
	local jitter = 1 + (math.random() * 2 - 1) * cfg.PitchJitter
	s.PlaybackSpeed = rise * jitter
	s.Volume = cfg.Volume
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
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
