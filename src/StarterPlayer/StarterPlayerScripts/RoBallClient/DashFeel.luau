--!strict
-- DashFeel (DESIGN.md §4): the game-feel layer around the raw burst —
-- input buffering, coyote legality, surface projection, asymmetric
-- colliders, and the camera punch. This module owns timing state and
-- answers only; Main.client stays the physics authority and consumes
-- the outputs. Every threshold lives in Config.DashFeel.
--
--   Buffer/coyote: fireLegal() gates the burst to grounded or inside
--     CoyoteTime of leaving the deck (AirDash flips the gate off — the
--     old any-altitude rule). A press that fails keeps a BufferWindow
--     life in Main's dashBuffered slot; the heartbeat retries it and the
--     landing frame fires it.
--   Projection: driveY() tilts the drive vector onto the eased surface
--     normal — the dart gets the downhill Y component the deck demands,
--     so a burst on a bank keeps contact instead of shearing off the
--     crest. Same math as the general slope track, routed through here
--     so the dash reads as the surface-projected move it is. The eased
--     normal itself comes from the drive loop's down-facing lane probe —
--     the spec's "down-facing raycast" is that existing probe.
--   Colliders: hurtScale() shrinks the swept radius + Touched rim test
--     FatalController applies (HurtScale); the pickup half of the pair
--     is the widened gem claim tube this module sweeps per frame while
--     a burst is live (PickupScale) — claims go through the ClaimGem
--     remote and the server re-validates distance on its own view.
--   Camera: noteBurst() stamps the fire frame; camKick() hands
--     RenderStepped a decaying FOV punch + Perlin eye shake (the
--     cam.DoFov punch of the Unity reference).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)

local DashFeel = {}
local DF = Config.DashFeel

local getBall: () -> BasePart? = function()
	return nil
end
local evClaimGem: RemoteEvent? = nil

-- Coyote clock: seconds since the lane probe last found contact.
-- math.huge = "never grounded" (menu / fresh bind) — no free coyote.
local grounded = true
local airT = math.huge

-- Burst window: stamped at fire — collider scales and cam envelopes key
-- off this, not the press.
local burstEnd = -1
-- Camera punch envelopes — decayed inside camKick.
local fovKick = 0
local shakeKick = 0

-- Gem sweep (PERFORMANCE.md §1): the incremental tag list mirrors
-- FatalController's lethal set — chunks stream in and out, so a
-- GetTagged-per-frame scan is out. Weak keys: collected/despawned gems
-- can't pin the table.
local gems = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })
local gemList = {} :: { BasePart }
local gemDirty = true
local gemParams = RaycastParams.new()
gemParams.FilterType = Enum.RaycastFilterType.Include
local claimed = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })
local lastPos: Vector3? = nil
local ballR = Config.Ball.Diameter / 2
-- Pickup band: claims reach (ballR + gemHalf)·PickupScale off the swept
-- line — the whole contact reach scaled, not just the ball's share.
local claimR = (ballR + Config.Gems.Size / 2) * DF.PickupScale

local function rebuildGems()
	table.clear(gemList)
	for p in gems do
		table.insert(gemList, p)
	end
	-- Re-seat the filter inside rebuild — assignment copies the list, so
	-- a stale seat would test yesterday's gem set.
	gemParams.FilterDescendantsInstances = gemList
	gemDirty = false
end

local function hookGem(part: Instance)
	if part:IsA("BasePart") then
		gems[part :: BasePart] = true
		gemDirty = true
	end
end

-- Drive vector → surface-projected Y: drive - n·(drive·n) drops the
-- component that would shear off the surface, so the burst's lateral
-- channel rides the bank instead of detaching. Shared math with the
-- general slope track — the dash is a bigger version of the same move.
function DashFeel.driveY(drive: Vector3, normal: Vector3): number
	return (drive - normal * drive:Dot(normal)).Y
end

function DashFeel.noteGrounded(g: boolean, dt: number)
	grounded = g
	airT = if g then 0 else airT + dt
end

-- Coyote gate: the burst is a ground verb — legal on the deck or inside
-- the grace window after leaving it.
function DashFeel.fireLegal(): boolean
	return DF.AirDash or grounded or airT <= DF.CoyoteTime
end

-- Stamped by the drive loop the frame a burst actually fires — dur is
-- the real window (a snapped goal extends it).
function DashFeel.noteBurst(dur: number)
	burstEnd = time() + dur
	fovKick = DF.FovAdd
	shakeKick = DF.ShakeAmp
end

function DashFeel.active(): boolean
	return time() < burstEnd
end

-- Lethal half of the asymmetric pair — FatalController multiplies this
-- into its swept radius and its Touched rim test.
function DashFeel.hurtScale(): number
	return if DashFeel.active() then DF.HurtScale else 1
end

-- Camera comfort: RenderStepped consumes (fovAdd, eyeShake). The kick
-- jumps on fire then exp-decays — a punch, not a zoom; the shake reads
-- Perlin so it trembles rather than lurches.
function DashFeel.camKick(dt: number): (number, Vector3)
	fovKick += (0 - fovKick) * (1 - math.exp(-dt / DF.FovTau))
	shakeKick += (0 - shakeKick) * (1 - math.exp(-dt / DF.ShakeTau))
	if fovKick < 0.02 and shakeKick < 0.01 then
		fovKick = 0
		shakeKick = 0
	end
	local t = time() * DF.ShakeFreq
	local shake = Vector3.new(math.noise(t, 7), math.noise(3, t), 0) * shakeKick
	return fovKick, shake
end

function DashFeel.reset()
	grounded = true
	airT = math.huge
	burstEnd = -1
	fovKick = 0
	shakeKick = 0
	lastPos = nil
	table.clear(claimed)
end

function DashFeel.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	evClaimGem = ReplicatedStorage:WaitForChild("RoBallRemotes"):WaitForChild("ClaimGem") :: RemoteEvent
	for _, p in ipairs(CollectionService:GetTagged("RoBallGem")) do
		hookGem(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallGem"):Connect(hookGem)
	CollectionService:GetInstanceRemovedSignal("RoBallGem"):Connect(function(part)
		if part:IsA("BasePart") and gems[part :: BasePart] then
			gems[part :: BasePart] = nil
			gemDirty = true
		end
	end)

	-- Pickup half of the asymmetric pair: while a burst is live the gem
	-- claim tube widens to ballR·PickupScale and sweeps the frame's travel
	-- — a committed dodge still collects the line it grazed, and a
	-- frame-skipping dart can't tunnel past a pickup. Claims are reported
	-- client→server like §11's fatal reports; the server bounds the check
	-- on its own interpolated view before paying out. Real contact is
	-- still collected server-side by Touched — this is only the widened
	-- band around it.
	RunService.Heartbeat:Connect(function()
		local b = getBall()
		if not b or not DashFeel.active() then
			lastPos = nil
			return
		end
		if gemDirty then
			rebuildGems()
		end
		local pos = b.Position
		if lastPos and #gemList > 0 and evClaimGem then
			local delta = pos - lastPos
			if delta.Magnitude > 0.01 then
				local hit = workspace:Spherecast(lastPos, claimR, delta, gemParams)
				if hit then
					local g = hit.Instance :: BasePart
					if not claimed[g] then
						claimed[g] = true -- dedupe: the server can still say no
						evClaimGem:FireServer(g)
					end
				end
			end
		end
		lastPos = pos
	end)
end

return DashFeel
