--!strict
-- MusicController (DESIGN.md §13): one looped synthwave track whose
-- PlaybackSpeed ramps with ball speed and slides down on death.
-- No-ops until Config.Music.AssetId is set (placeholder for MVP).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.RoBall.Config)

local Music = {}

local sound: Sound? = nil

function Music.init()
	if Config.Music.AssetId == 0 then
		return -- placeholder: wire-up complete, waiting on the track asset
	end
	local s = Instance.new("Sound")
	s.Name = "RoBallMusic"
	s.SoundId = "rbxassetid://" .. tostring(Config.Music.AssetId)
	s.Looped = true
	s.Volume = Config.Music.Volume
	s.PlaybackSpeed = Config.Music.PlaybackSpeedMin
	s.Parent = SoundService
	sound = s
end

function Music.onStart()
	local s = sound
	if s then
		s.PlaybackSpeed = Config.Music.PlaybackSpeedMin
		if not s.IsPlaying then
			s:Play()
		end
	end
end

function Music.onDeath()
	local s = sound
	if s and s.IsPlaying then
		TweenService:Create(s, TweenInfo.new(0.5), { PlaybackSpeed = Config.Music.DeathPitchFloor }):Play()
	end
end

-- speedNorm 0..1 (ball fwdSpeed between Speed.Start and Speed.Max).
function Music.setSpeedNorm(norm: number)
	local s = sound
	if s and s.IsPlaying then
		local lo, hi = Config.Music.PlaybackSpeedMin, Config.Music.PlaybackSpeedMax
		s.PlaybackSpeed = lo + (hi - lo) * math.clamp(norm, 0, 1)
	end
end

return Music
