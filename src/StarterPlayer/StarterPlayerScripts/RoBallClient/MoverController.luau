--!strict
-- MoverController (DESIGN.md §8.6): smooth client-side animation for
-- beat-locked hazard movers. The server steps them at Movers.StepHz —
-- enough for its own bookkeeping, but the replicated writes land as
-- visible teleports (a PressRow slam was ~6 snaps). Each mover part
-- carries its full waveform as attributes, so the client re-evaluates
-- it every Heartbeat on the synced server clock: presses glide, pacers
-- slide, rotors spin — and kills test exactly what the player sees,
-- since FatalController is client-authoritative.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local MoveWave = require(ReplicatedStorage.RoBall.MoveWave)

local MoverController = {}

local getBall: () -> BasePart? = function()
	return nil
end

type MoverRec = {
	kind: string,
	base: Vector3,
	amp: number,
	period: number,
	phase: number,
	epoch: number,
	outline: SelectionBox?, -- dropY press plates: slam telegraph surface
}

local active: { [BasePart]: MoverRec } = {}

local function hook(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local p = part :: BasePart
	local kind = p:GetAttribute("MoverKind")
	local base = p:GetAttribute("MoverBase")
	if type(kind) ~= "string" or typeof(base) ~= "Vector3" then
		-- Attributes can replicate a tick after the tag fires — retry
		-- when the waveform lands instead of silently skipping the mover.
		-- Arm BOTH signals: whichever field arrives LAST re-triggers —
		-- a MoverKind that's already set would otherwise dead-end here.
		p:GetAttributeChangedSignal("MoverKind"):Once(function()
			hook(p)
		end)
		p:GetAttributeChangedSignal("MoverBase"):Once(function()
			hook(p)
		end)
		return
	end
	active[p] = {
		kind = kind,
		base = base,
		amp = (p:GetAttribute("MoverAmp") :: number?) or 0,
		period = (p:GetAttribute("MoverPeriod") :: number?) or 1,
		phase = (p:GetAttribute("MoverPhase") :: number?) or 0,
		epoch = (p:GetAttribute("MoverEpoch") :: number?) or 0,
	}
end

function MoverController.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	for _, p in ipairs(CollectionService:GetTagged("RoBallMover")) do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("RoBallMover"):Connect(hook)
	CollectionService:GetInstanceRemovedSignal("RoBallMover"):Connect(function(part)
		if part:IsA("BasePart") then
			active[part :: BasePart] = nil
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not next(active) then
			return
		end
		local now = workspace:GetServerTimeNow()
		local b = getBall()
		-- Same cull as the server: movers behind the ball are off-camera.
		local cullZ = (b and b.Position.Z or 0) + Config.Movers.CullBehind
		for p, m in active do
			if p.Parent == nil then
				active[p] = nil
			elseif m.base.Z <= cullZ then
				local ang = (now - m.epoch) / m.period * math.pi * 2 + m.phase
				if m.kind == "slideX" then
					p.Position = Vector3.new(m.base.X + m.amp * math.sin(ang), m.base.Y, m.base.Z)
				elseif m.kind == "dropY" then
					local x = (ang / (math.pi * 2)) % 1
					local pulse = MoveWave.pressPulse(x)
					p.Position = Vector3.new(m.base.X, m.base.Y - m.amp * pulse, m.base.Z)
					-- Slam telegraph (PressRow readability): the wireframe
					-- plate fills toward solid as the wave drops — wireframe
					-- = raised/safe, filled = armed.
					local sb = m.outline
					if sb == nil then
						sb = p:FindFirstChildOfClass("SelectionBox")
						m.outline = sb
					end
					if sb then
						sb.SurfaceTransparency = 1 - (1 - Config.Press.SlamFill) * pulse
					end
				else -- spin
					p.CFrame = CFrame.new(m.base) * CFrame.Angles(0, ang, 0)
				end
			end
		end
	end)
end

return MoverController
