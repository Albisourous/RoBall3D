--!strict
-- GemFx (DESIGN.md §8.4): pickup juice. Server gems are Destroyed instantly
-- on touch, so the client renders the flourish at the ball's position when
-- RoBallGems ticks up: a ghost diamond pops and rises, a sparkle burst
-- scatters, and a neon ring flashes outward. All parts are client-local
-- one-shots — zero replication cost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)

local player = Players.LocalPlayer
local ballName = player.Name .. "_Ball"

local Fx = {}
local lastGems = 0

-- Equipped gemFx item picks the flourish color (§18); "rainbow" resolves
-- to a per-burst hue inside colorOf.
local function gemColor(): Color3
	local item = Cosmetics.item(player:GetAttribute("RoBallEq_gemFx") :: string?)
	return Cosmetics.colorOf(item and item.color, Config.Gems.Color)
end

local function ballPos(): Vector3?
	local b = workspace:FindFirstChild(ballName)
	return if b and b:IsA("BasePart") then b.Position else nil
end

-- Ghost of the collected gem: pops oversize, rises, spins, fades.
local function popGem(pos: Vector3, color: Color3)
	local fx = Config.GemFx
	local g = Instance.new("Part")
	g.Name = "GemPopFx"
	g.Anchored = true
	g.CanCollide = false
	g.CastShadow = false
	g.Size = Vector3.one * Config.Gems.Size
	g.Color = color
	g.Material = Enum.Material.Neon
	-- same corner-cube diamond silhouette the real gems use
	g.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(35.264), math.rad(45), 0)
	g.Parent = workspace
	Debris:AddItem(g, fx.PopTime + 0.1)
	TweenService:Create(g, TweenInfo.new(fx.PopTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * Config.Gems.Size * fx.PopScale,
		Transparency = 1,
		Orientation = Vector3.new(35.264, 45 + fx.PopSpin, 20),
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

local function burst()
	local pos = ballPos()
	if not pos then
		return
	end
	local color = gemColor()
	popGem(pos, color)
	sparkle(pos, color)
	ring(pos, color)
end

function Fx.init()
	lastGems = player:GetAttribute("RoBallGems") or 0
	player:GetAttributeChangedSignal("RoBallGems"):Connect(function()
		local n = player:GetAttribute("RoBallGems") or 0
		if n > lastGems then
			burst()
		end
		lastGems = n
	end)
end

return Fx
