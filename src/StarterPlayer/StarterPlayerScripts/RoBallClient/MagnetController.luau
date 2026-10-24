--!strict
-- MagnetController: MagnetLane rails (DESIGN.md §8.3, GD_DESIGN.md).
-- Server places "RoBallMagnet"-tagged strips carrying a PullK attribute;
-- while the ball overlaps a strip's footprint, `pull` returns a
-- studs-per-second nudge toward the rail's centerline — folded into the
-- drive loop's targetLat alongside bankPull. The cap sits under
-- Config.Steering.MaxLateralSpeed so a hard steer always wins: the rail
-- gathers, it never grabs. Same zero-latency client idiom as PadController.

local CollectionService = game:GetService("CollectionService")

local Config = require(game:GetService("ReplicatedStorage").RoBall.Config)

local MagnetController = {}

local strips = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })
local stripList = {} :: { BasePart }
local listDirty = true
local ballR = Config.Ball.Diameter / 2

local function rebuildList()
	table.clear(stripList)
	for p in strips do
		table.insert(stripList, p)
	end
	listDirty = false
end

-- studs/s of lateral pull toward the nearest overlapping rail line;
-- 0 when the ball is off every strip. Scans are a handful of parts.
function MagnetController.pull(pos: Vector3): number
	if listDirty then
		rebuildList()
	end
	local best = 0
	for _, p in ipairs(stripList) do
		local half = p.Size / 2
		-- Cheap z reject; the ball only approaches a strip or two at once.
		if math.abs(pos.Z - p.Position.Z) <= half.Z + ballR then
			local lp = p.CFrame:PointToObjectSpace(pos)
			if math.abs(lp.X) <= half.X + ballR and math.abs(lp.Z) <= half.Z + ballR and lp.Y <= half.Y + 4 then
				local k = p:GetAttribute("PullK") :: number? or Config.Magnet.K
				local pull = math.clamp(-lp.X * k, -Config.Magnet.Cap, Config.Magnet.Cap)
				if math.abs(pull) > math.abs(best) then
					best = pull
				end
			end
		end
	end
	return best
end

local function hook(part: Instance)
	if part:IsA("BasePart") then
		strips[part :: BasePart] = true
		listDirty = true
	end
end

function MagnetController.init()
	for _, p in ipairs(CollectionService:GetTagged("RoBallMagnet")) do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallMagnet"):Connect(hook)
	CollectionService:GetInstanceRemovedSignal("RoBallMagnet"):Connect(function(part)
		if part:IsA("BasePart") and strips[part :: BasePart] then
			strips[part :: BasePart] = nil
			listDirty = true
		end
	end)
end

return MagnetController
