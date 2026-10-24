--!strict
-- SfxController: the two non-music voices — the hoop whoosh on a ring
-- thread and the proximity ping while a corridor threat closes. Gem
-- pickups are silent (GD plays nothing on collection); the xN HUD
-- streak keeps counting in Main.client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Music = require(script.Parent.MusicController)
local AudioMix = require(script.Parent.AudioMix)

local Sfx = {}

local player = Players.LocalPlayer

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

-- Hoop whoosh (§10): the bell inhale-swept up through the pass — air
-- rushing through the ring's opening the ball just threaded. Rides the
-- `gems` mixer channel (the hoop pays gems, so the award rides its gain).
function Sfx.hoop()
	local cfg = Config.Hoop
	local s = Instance.new("Sound")
	s.Name = "HoopWhoosh"
	s.SoundId = assetUri(cfg)
	s.Volume = cfg.WhooshVol * AudioMix.gain("gems")
	local ps = Instance.new("PitchShiftSoundEffect")
	ps.Octave = cfg.WhooshStartOct
	ps.Parent = s
	s.Parent = SoundService
	s:Play()
	TweenService:Create(
		ps,
		TweenInfo.new(cfg.WhooshTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Octave = cfg.WhooshEndOct }
	):Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

-- Proximity ping (§12): one flattened blip of the same bell — pitched
-- down PingOctave so it can't read as a pickup, lifting PingLift at
-- contact distance. The cadence itself is scheduled by the caller.
function Sfx.dangerPing(intensity: number)
	local cfg = Config.Danger
	local s = Instance.new("Sound")
	s.Name = "DangerPing"
	s.SoundId = assetUri(cfg)
	s.Volume = cfg.PingVol * AudioMix.gain("dash")
	local ps = Instance.new("PitchShiftSoundEffect")
	ps.Octave = cfg.PingOctave * (1 + cfg.PingLift * math.clamp(intensity, 0, 1))
	ps.Parent = s
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(3, function()
		s:Destroy()
	end)
end

-- Menu audio (MENU.md §5): the menu is deliberately silent — no
-- hitsounds anywhere on the chrome; the bed and the track audition are
-- the only voices.

function Sfx.init()
	Music.preloadSfx(assetUri(Config.Danger)) -- warm the decode so the first ping isn't late
	local lastHoop = player:GetAttribute("RoBallHoop") or 0
	player:GetAttributeChangedSignal("RoBallHoop"):Connect(function()
		local n = player:GetAttribute("RoBallHoop") or 0
		if n > lastHoop then
			Sfx.hoop()
		end
		lastHoop = n
	end)
end

return Sfx
