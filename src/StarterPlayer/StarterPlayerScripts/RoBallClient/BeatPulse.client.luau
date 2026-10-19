--!strict
-- BeatPulse (AUDIO.md §8): gems swell on the beat — the GD read where
-- world objects visibly breathe with the track. Stands alone so it needs
-- no wiring in Main; reads MusicController's live beat clock.
--
-- Shape: sharp attack on the beat, decaying swell across the beat —
-- downbeats (bar 1) hit ~30% harder so the pulse reads the meter, not
-- just the grid. Only gems near the camera get resized (perf); distant
-- ones snap back to base.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)
local Music = require(script.Parent.MusicController)

local TAG = "RoBallGem"
local pulseK = Config.Gems.BeatPulse
local radius = Config.Gems.BeatPulseRadius

local bases: { [BasePart]: Vector3 } = {}

local function track(inst: Instance)
	if inst:IsA("BasePart") then
		bases[inst] = inst.Size
	end
end

local function untrack(inst: Instance)
	bases[inst] = nil
end

for _, g in ipairs(CollectionService:GetTagged(TAG)) do
	track(g)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

RunService.RenderStepped:Connect(function()
	local beat = Music.beatPos()
	if beat <= 0 or next(bases) == nil then
		return
	end
	local frac = beat % 1
	local pulse = (1 - frac) ^ 2.5 -- sharp attack, beat-long decay
	local accent = if beat % SongMap.beatsPerBar < 1 then 1.3 else 1 -- bar 1 emphasis
	local scale = 1 + pulseK * pulse * accent

	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local r2 = radius * radius
	for g, base in pairs(bases) do
		local d = g.Position - camPos
		if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
			g.Size = base * scale
		elseif g.Size ~= base then
			g.Size = base
		end
	end
end)
