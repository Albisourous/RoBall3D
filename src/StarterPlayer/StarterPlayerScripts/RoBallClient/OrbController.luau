--!strict
-- OrbController: JumpOrb taps (DESIGN.md §8.6 stretch, flag-off). The
-- streamer places "RoBallOrb"-tagged spheres carrying KickY + Radius
-- attributes. A jump input while the ball is inside Radius re-kicks vY —
-- GD's tap-orb: the second arc carries a gap the pad arc alone cannot.
-- Proximity-checked on input, never a physics contact, so the orb can't
-- fire from a stray graze. Each orb fires once per run.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local OrbController = {}

local getBall: () -> BasePart? = function()
	return nil
end
local enabled = false
-- Weak keys: orbs die with their chunks; see PadController.
local fired = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })

local function tryOrb()
	local b = getBall()
	if not b then
		return
	end
	local best: BasePart? = nil
	local bestD = math.huge
	for _, o in ipairs(CollectionService:GetTagged("RoBallOrb")) do
		if o:IsA("BasePart") and not fired[o] then
			local r = o:GetAttribute("Radius")
			local d = (o.Position - b.Position).Magnitude
			if typeof(r) == "number" and d <= r and d < bestD then
				best = o
				bestD = d
			end
		end
	end
	if not best then
		return
	end
	local kick = best:GetAttribute("KickY")
	if typeof(kick) ~= "number" or kick <= 0 then
		return
	end
	fired[best] = true
	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(v.X, kick, v.Z)
	-- Stamp the intentional launch so the landing squash (§11) can
	-- tell it apart from a solver pop.
	b:SetAttribute("KickAt", time())
	-- Local-only pop: shrink-bloom confirms the tap connected.
	best.LocalTransparencyModifier = -0.4
	TweenService:Create(best, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { LocalTransparencyModifier = 0 }):Play()
end

function OrbController.init(ballGetter: () -> BasePart?, isEnabled: boolean)
	getBall = ballGetter
	enabled = isEnabled
	if not enabled then
		return
	end
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.Touch then
			tryOrb()
		end
	end)
end

return OrbController
