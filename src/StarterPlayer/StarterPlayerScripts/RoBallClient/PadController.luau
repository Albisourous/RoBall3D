--!strict
-- PadController: LaunchPad kicks (DESIGN.md §8.3/§8.6). Server places
-- "RoBallPad"-tagged strips carrying a KickY attribute; the ball's
-- network owner is this client, so the kick applies here — zero latency.
-- The drive loop preserves v.Y every frame, so gravity takes the arc
-- from there. Each pad fires once per run.
-- Contact is a per-frame sphere-vs-strip overlap test, not bare Touched:
-- a fast-descending ball can tunnel the 0.35-stud strip between physics
-- steps and an edge graze can miss the contact window — both read on
-- screen as "the pad didn't work" (FatalController §11 swept the same
-- way for lethal parts; pads are CanQuery=false so the test is geometric,
-- not a cast).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage").RoBall.Config)

local PadController = {}

local getBall: () -> BasePart? = function()
	return nil
end
-- Weak keys: pads die with their chunks; a strong table would pin every
-- dead pad part for the whole session.
local fired = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })
local pads = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })
local padList = {} :: { BasePart }
local listDirty = true
local ballR = Config.Ball.Diameter / 2

local function rebuildList()
	table.clear(padList)
	for p in pads do
		table.insert(padList, p)
	end
	listDirty = false
end

local function fire(pad: BasePart, b: BasePart)
	if fired[pad] then
		return
	end
	local kick = pad:GetAttribute("KickY")
	if typeof(kick) ~= "number" or kick <= 0 then
		return
	end
	fired[pad] = true
	local v = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(v.X, kick, v.Z)
	-- Stamp the intentional launch so the landing squash (§11) can
	-- tell it apart from a solver pop.
	b:SetAttribute("KickAt", time())
	-- Local-only flash: the strip blooms for a beat to confirm the grab.
	pad.LocalTransparencyModifier = -0.4
	TweenService:Create(pad, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { LocalTransparencyModifier = 0 }):Play()
end

local function hook(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	local p = pad :: BasePart
	if pads[p] then
		return
	end
	pads[p] = true
	listDirty = true
	-- Physics contact is the zero-cost fast path; the heartbeat sweep
	-- below is the backstop for steps that skip the overlap.
	p.Touched:Connect(function(hit)
		local b = getBall()
		if b and hit == b then
			fire(p, b)
		end
	end)
end

function PadController.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	for _, p in ipairs(CollectionService:GetTagged("RoBallPad")) do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallPad"):Connect(hook)
	CollectionService:GetInstanceRemovedSignal("RoBallPad"):Connect(function(part)
		if part:IsA("BasePart") and pads[part :: BasePart] then
			pads[part :: BasePart] = nil
			listDirty = true
		end
	end)

	RunService.Heartbeat:Connect(function()
		local b = getBall()
		if not b then
			return
		end
		if listDirty then
			rebuildList()
		end
		local pos = b.Position
		for _, p in ipairs(padList) do
			if not fired[p] then
				local half = p.Size / 2
				-- Cheap z reject before the frame transform; the ball only
				-- ever approaches a handful of pads at once.
				if math.abs(pos.Z - p.Position.Z) <= half.Z + ballR + 1 then
					-- Sphere vs strip in pad-local space (the strip carries
					-- the deck's pitch/roll, so world-axis AABBs would lie).
					-- The trigger reaches GrabH above the strip top: a
					-- "grounded" ball can ride ContactPad off the deck at
					-- speed and would sail over the 0.35-stud band.
					local lp = p.CFrame:PointToObjectSpace(pos)
					local near = Vector3.new(
						math.clamp(lp.X, -half.X, half.X),
						math.clamp(lp.Y, -half.Y, half.Y + Config.Pads.GrabH),
						math.clamp(lp.Z, -half.Z, half.Z)
					)
					if (lp - near).Magnitude <= ballR then
						fire(p, b)
					end
				end
			end
		end
	end)
end

return PadController
