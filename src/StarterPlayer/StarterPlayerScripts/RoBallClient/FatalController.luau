--!strict
-- FatalController: client-authoritative lethal contact (DESIGN.md §11).
-- The ball's network owner is this client — server-side Touched judged an
-- interpolated copy of the ball, so blocks the player visibly dodged could
-- still register hits ("random deaths"). Contact is tested where the ball
-- is actually simulated: what the player sees hit them is what kills them.
-- Touched covers ordinary contact; a per-frame Spherecast along the
-- frame's displacement catches high-speed tunneling through thin blocks.
-- The server keeps fall/stall backstops — those are self-consistent on
-- its view and can't false-fire.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").RoBall.Config)

local FatalController = {}

local getBall: () -> BasePart? = function()
	return nil
end
local armed: () -> boolean = function()
	return false
end
local report: () -> () = function() end

local lethal = {} :: { [BasePart]: boolean }
local lethalList = {} :: { BasePart }
local listDirty = true
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include
local ballR = Config.Ball.Diameter / 2
local reported = false -- one report per run; clears when disarmed

local function hook(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local p = part :: BasePart
	if lethal[p] then
		return
	end
	lethal[p] = true
	listDirty = true
	p.Touched:Connect(function(hit)
		if hit == getBall() and armed() and not reported then
			reported = true
			report()
		end
	end)
end

function FatalController.init(ballGetter: () -> BasePart?, armedFn: () -> boolean, reportFn: () -> ())
	getBall = ballGetter
	armed = armedFn
	report = reportFn
	for _, p in ipairs(CollectionService:GetTagged("RoBallLethal")) do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallLethal"):Connect(hook)
	CollectionService:GetInstanceRemovedSignal("RoBallLethal"):Connect(function(part)
		if part:IsA("BasePart") and lethal[part :: BasePart] then
			lethal[part :: BasePart] = nil
			listDirty = true
		end
	end)

	local lastPos: Vector3? = nil
	RunService.Heartbeat:Connect(function()
		local b = getBall()
		if not b or not armed() then
			lastPos = nil
			reported = false
			return
		end
		if listDirty then
			table.clear(lethalList)
			for p in lethal do
				table.insert(lethalList, p)
			end
			castParams.FilterDescendantsInstances = lethalList
			listDirty = false
		end
		local pos = b.Position
		-- Swept sphere along this frame's travel: at 200+ s/s a hitch can
		-- carry the ball through a block's contact window between steps —
		-- Touched alone would miss it, and the run would continue through
		-- a wall the player saw them hit.
		if not reported and lastPos and #lethalList > 0 then
			local delta = pos - lastPos
			if delta.Magnitude > 0.01 then
				local hit = workspace:Spherecast(lastPos, ballR, delta, castParams)
				if hit then
					reported = true
					report()
				end
			end
		end
		lastPos = pos
	end)
end

return FatalController
