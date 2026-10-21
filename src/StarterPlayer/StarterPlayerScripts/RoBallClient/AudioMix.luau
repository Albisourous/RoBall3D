--!strict
-- AudioMix (AUDIO.md §7): the user's mixer state. Five channels ride
-- dedicated graph taps inside MusicController + SfxController; this
-- module is the single owner of the gain values — the menu AUDIO panel
-- writes through AudioMix.set, server-pushed RoBallVol_<ch> attributes
-- re-apply saved mixes on join, and consumers read/apply via gain().
--
-- Apply is local-immediate (drag = hear it); persistence is a separate
-- save() that invokes the SetAudio remote — the attribute echo that
-- follows re-applies the same value, so it never re-invokes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Music = require(script.Parent.MusicController)

local AudioMix = {}

local player = Players.LocalPlayer
local fnSetAudio: RemoteFunction? = nil
local gains: { [string]: number } = {}
local onChange: { [string]: { (number) -> () } } = {}

local function attr(ch: string): string
	return Config.Audio.AttrPrefix .. ch
end

function AudioMix.gain(ch: string): number
	return gains[ch] or Config.Audio.Defaults[ch] or 1
end

-- Ui registers a per-channel refresh so a server echo (or a future
-- second UI surface) repaints sliders too.
function AudioMix.onChange(ch: string, fn: (number) -> ())
	local l = onChange[ch] or {}
	table.insert(l, fn)
	onChange[ch] = l
end

local function apply(ch: string)
	Music.setGain(ch, AudioMix.gain(ch)) -- graph taps; "dash" is a no-op there
	for _, fn in ipairs(onChange[ch] or {}) do
		fn(AudioMix.gain(ch))
	end
end

-- Drag-time write: apply now, no save. Call save() once on release.
function AudioMix.set(ch: string, v: number)
	gains[ch] = math.clamp(v, 0, 1)
	apply(ch)
end

function AudioMix.save(ch: string)
	if not fnSetAudio then
		return
	end
	local v = gains[ch]
	task.spawn(function()
		pcall(function()
			(fnSetAudio :: RemoteFunction):InvokeServer(ch, v)
		end)
	end)
end

function AudioMix.init()
	for _, ch in ipairs(Config.Audio.Channels) do
		gains[ch] = Config.Audio.Defaults[ch] or 1
		local cur = player:GetAttribute(attr(ch))
		if typeof(cur) == "number" then
			gains[ch] = math.clamp(cur, 0, 1)
		end
		apply(ch)
		player:GetAttributeChangedSignal(attr(ch)):Connect(function()
			local v = player:GetAttribute(attr(ch))
			if typeof(v) == "number" then
				gains[ch] = math.clamp(v, 0, 1)
				apply(ch)
			end
		end)
	end
	fnSetAudio = ReplicatedStorage:WaitForChild("RoBallRemotes"):WaitForChild(Config.Audio.RemoteName) :: RemoteFunction
end

return AudioMix
