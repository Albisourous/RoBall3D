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
local report: (BasePart?) -> () = function(_part: BasePart?) end
-- Asymmetric collider (DashFeel §4): 1 = full hurtbox; during a dash
-- burst this dips below 1 so the swept cast and the Touched rim test
-- both treat the outer band as non-lethal — a graze inside it reads as
-- the dodge it looked like.
local hurtScale: () -> number = function()
	return 1
end

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
			-- Shrunk hurtbox: Touched fires on ANY contact, including the
			-- outer band the dash forgives. Re-test with the scaled
			-- sphere against the part's extents box — rim-only contact
			-- is ignored; a center that still overlaps is a real hit.
			local s = hurtScale()
			local b = hit :: BasePart
			if s < 1 then
				local lp = p.ExtentsCFrame:PointToObjectSpace(b.Position)
				local hs = p.ExtentsSize / 2
				local gap = Vector3.new(
					math.max(math.abs(lp.X) - hs.X, 0),
					math.max(math.abs(lp.Y) - hs.Y, 0),
					math.max(math.abs(lp.Z) - hs.Z, 0)
				)
				if gap.Magnitude > ballR * s then
					return
				end
			end
			reported = true
			report(p)
		end
	end)
end

-- Shared read (PERFORMANCE.md §1): the radar scans the same lethal set —
-- this is the incremental tag-tracking the audit says to reuse instead of
-- re-paying a workspace-wide GetTagged every scan.
local function rebuildList()
	table.clear(lethalList)
	for p in lethal do
		table.insert(lethalList, p)
	end
	-- FilterDescendantsInstances COPIES contents at assignment — and the
	-- radar's lethalParts() can be the caller that consumes listDirty.
	-- Re-seat the cast filter inside rebuild so no caller leaves the
	-- spherecast testing a stale lethal set (a tunneled block would read
	-- as a pass-through).
	castParams.FilterDescendantsInstances = lethalList
	listDirty = false
end

function FatalController.lethalParts(): { BasePart }
	if listDirty then
		rebuildList()
	end
	return lethalList
end

function FatalController.setHurtScale(fn: () -> number)
	hurtScale = fn
end

function FatalController.init(ballGetter: () -> BasePart?, armedFn: () -> boolean, reportFn: (BasePart?) -> ())
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
			rebuildList()
		end
		local pos = b.Position
		-- Swept sphere along this frame's travel: at 200+ s/s a hitch can
		-- carry the ball through a block's contact window between steps —
		-- Touched alone would miss it, and the run would continue through
		-- a wall the player saw them hit.
		if not reported and lastPos and #lethalList > 0 then
			local delta = pos - lastPos
			if delta.Magnitude > 0.01 then
				local hit = workspace:Spherecast(lastPos, ballR * hurtScale(), delta, castParams)
				if hit then
					reported = true
					report(hit.Instance)
				end
			end
		end
		lastPos = pos
	end)
end

return FatalController
