--!strict
-- GemFx (DESIGN.md §8.4): pickup juice. Server gems are Destroyed instantly
-- on touch, so the client renders the flourish at the ball's position when
-- RoBallGems ticks up: a ghost of the collected gem — its own shape + tint
-- via RoBallGemShape/RoBallGemColor — pops and rises, a sparkle burst
-- scatters, and a neon ring flashes outward. All parts are client-local
-- one-shots — zero replication cost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local GemTypes = require(ReplicatedStorage.RoBall.GemTypes)

local player = Players.LocalPlayer
local ballName = player.Name .. "_Ball"

local Fx = {}
local lastGems = 0

-- Equipped gemFx item picks the flourish color (§18); "rainbow" resolves
-- to a per-burst hue, "customC" to the COLOR LAB accent channel.
local function gemColor(): Color3
	local item = Cosmetics.item(player:GetAttribute("RoBallEq_gemFx") :: string?)
	return Cosmetics.colorOf(item and item.color, Config.Gems.Color, Cosmetics.huesOf(player))
end

local function ballPos(): Vector3?
	local b = workspace:FindFirstChild(ballName)
	return if b and b:IsA("BasePart") then b.Position else nil
end

-- Ghost of the collected gem: pops oversize, rises, spins, fades — in the
-- real pickup's shape + tier tint (§8.4), resolved through GemTypes.
local function popGem(pos: Vector3, shape: string, size: number, color: Color3)
	local fx = Config.GemFx
	local g = Instance.new("Part")
	g.Name = "GemPopFx"
	g.Anchored = true
	g.CanCollide = false
	g.CastShadow = false
	g.CFrame = CFrame.new(pos) * GemTypes.pose(g, shape, size)
	g.Color = color
	g.Material = Enum.Material.Neon
	g.Parent = workspace
	local baseSize = g.Size
	local ori = g.Orientation
	Debris:AddItem(g, fx.PopTime + 0.1)
	TweenService:Create(g, TweenInfo.new(fx.PopTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = baseSize * fx.PopScale,
		Transparency = 1,
		Orientation = ori + Vector3.new(0, fx.PopSpin, 20),
	}):Play()
	TweenService:Create(g, TweenInfo.new(fx.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = pos + Vector3.new(0, fx.PopRise, 0),
	}):Play()
end

-- Sparkles scatter up-and-out.
local function sparkle(pos: Vector3, color: Color3)
	local fx = Config.GemFx
	local anchor = Instance.new("Part")
	anchor.Name = "GemSparkFx"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = pos
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles.png"
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Lifetime = NumberRange.new(0.25, fx.SparkleLife)
	pe.Speed = NumberRange.new(fx.SparkleSpeed * 0.5, fx.SparkleSpeed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.LightEmission = 1
	pe.Parent = anchor
	anchor.Parent = workspace
	pe:Emit(fx.SparkleCount)
	Debris:AddItem(anchor, fx.SparkleLife + 0.6)
end

-- Thin neon ring that flashes outward across the deck — the "collected!" read.
local function ring(pos: Vector3, color: Color3)
	local fx = Config.GemFx
	local r = Instance.new("Part")
	r.Name = "GemRingFx"
	r.Anchored = true
	r.CanCollide = false
	r.CastShadow = false
	-- cylinder axis is X; pitch it 90° so the disc lies flat in XZ
	r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	r.Size = Vector3.new(0.15, 0.6, 0.6)
	r.Color = color
	r.Material = Enum.Material.Neon
	r.Transparency = 0.15
	r.Parent = workspace
	Debris:AddItem(r, fx.RingTime + 0.1)
	TweenService:Create(r, TweenInfo.new(fx.RingTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, fx.RingSize, fx.RingSize),
		Transparency = 1,
	}):Play()
end

-- "+N" score float: the pickup's point value rises and fades — the
-- immediate "that gem was worth it" read (DESIGN.md §8.4).
local function popup(pos: Vector3, pts: number, color: Color3)
	local fx = Config.GemFx
	local host = Instance.new("Part")
	host.Name = "GemPopupFx"
	host.Anchored = true
	host.CanCollide = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.new(0.1, 0.1, 0.1)
	host.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 30)
	bb.AlwaysOnTop = true
	bb.Parent = host
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.Code
	tl.TextSize = fx.PopupSize
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0.4
	tl.Text = "+" .. tostring(pts)
	tl.Parent = bb
	host.Parent = workspace
	Debris:AddItem(host, fx.PopupTime + 0.1)
	TweenService:Create(host, TweenInfo.new(fx.PopupTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = host.Position + Vector3.new(0, fx.PopupRise, 0),
	}):Play()
	TweenService:Create(tl, TweenInfo.new(fx.PopupTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function burst(pts: number)
	local pos = ballPos()
	if not pos then
		return
	end
	local color = gemColor()
	-- The ghost wears the collected gem's own type: shape lands on
	-- RoBallGemShape (stamped before the RoBallGems bump), tint resolves
	-- from the point delta through the same tier table the streamer used.
	local shape, size, tcolor = GemTypes.of(pts, player:GetAttribute("RoBallGemShape") :: string?)
	-- RoBallGemColor carries the live pickup's own tint (styled worlds
	-- like APE BALL's banana orbs differ from the tier ramp).
	tcolor = player:GetAttribute("RoBallGemColor") or tcolor
	popGem(pos, shape, size, tcolor)
	sparkle(pos, color)
	ring(pos, color)
	if pts > 0 then
		popup(pos, pts, color)
	end
end

function Fx.init()
	lastGems = player:GetAttribute("RoBallGems") or 0
	player:GetAttributeChangedSignal("RoBallGems"):Connect(function()
		local n = player:GetAttribute("RoBallGems") or 0
		if n > lastGems then
			local pts = n - lastGems
			-- RoBallGems is cumulative points — the delta IS this pickup's
			-- value (10/15/25/40 by risk tier), so it lands on the popup.
			-- Defer a step: RoBallGemShape rides the same replication flush
			-- but its apply order vs this attr isn't guaranteed — one step
			-- later the whole batch has landed.
			task.defer(burst, pts)
		end
		lastGems = n
	end)
end

return Fx
