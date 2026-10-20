--!strict
-- PadController: LaunchPad kicks (DESIGN.md §8.3/§8.6). Server places
-- "RoBallPad"-tagged strips carrying a KickY attribute; the ball's
-- network owner is this client, so the kick applies here — zero latency.
-- The drive loop preserves v.Y every frame, so gravity takes the arc
-- from there. Each pad fires once per run.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local PadController = {}

local getBall: () -> BasePart? = function()
	return nil
end
local fired: { [BasePart]: boolean } = {}

local function hook(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	(pad :: BasePart).Touched:Connect(function(hit)
		local b = getBall()
		if not b or hit ~= b or fired[pad :: BasePart] then
			return
		end
		local kick = pad:GetAttribute("KickY")
		if typeof(kick) ~= "number" or kick <= 0 then
			return
		end
		fired[pad :: BasePart] = true
		local v = b.AssemblyLinearVelocity
		b.AssemblyLinearVelocity = Vector3.new(v.X, kick, v.Z)
		-- Local-only flash: the strip blooms for a beat to confirm the grab.
		local p = pad :: BasePart
		p.LocalTransparencyModifier = -0.4
		TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { LocalTransparencyModifier = 0 }):Play()
	end)
end

function PadController.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	for _, p in ipairs(CollectionService:GetTagged("RoBallPad")) do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallPad"):Connect(hook)
end

return PadController
