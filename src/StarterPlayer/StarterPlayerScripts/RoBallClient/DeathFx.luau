--!strict
-- DeathFx (DESIGN.md §18): the run-over flourish, fired at the last ball
-- position when RunEnded lands (the ball itself is already Destroyed).
-- Equipped deathFx item picks the style + accent colors; all parts are
-- client-local one-shots, gone in under a second.
--
-- Styles: "pop" (ghost ball pops + ring), "shatter" (shards fly out),
-- "nova" (staggered expanding rings + flash), "implode" (shards converge
-- into a flash), "geyser" (an upward fountain of shards), "corona" (a
-- horizontal ring of shards blooming outward).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)

local player = Players.LocalPlayer

local Fx = {}

local function randDir(): Vector3
	return Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5).Unit
end

-- Neon shard that tweens between two radii while tumbling + fading.
local function shard(parent: Instance, pos: Vector3, dir: Vector3, r0: number, r1: number, color: Color3, life: number)
	local s = Instance.new("Part")
	s.Name = "DeathShardFx"
	s.Anchored = true
	s.CanCollide = false
	s.CastShadow = false
	s.Size = Vector3.new(0.55, 0.16, 0.16)
	s.Color = color
	s.Material = Enum.Material.Neon
	s.CFrame = CFrame.new(pos + dir * r0) * CFrame.Angles(math.rad(math.random(360)), math.rad(math.random(360)), 0)
	s.Parent = parent
	Debris:AddItem(s, life + 0.1)
	TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = pos + dir * r1,
		Transparency = 1,
		Orientation = s.Orientation + Vector3.new(math.random(-200, 200), math.random(-200, 200), 0),
	}):Play()
end

-- Flat neon ring expanding across the deck plane (same read as GemFx).
local function flatRing(parent: Instance, pos: Vector3, finalSize: number, color: Color3, time: number)
	local r = Instance.new("Part")
	r.Name = "DeathRingFx"
	r.Anchored = true
	r.CanCollide = false
	r.CastShadow = false
	r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	r.Size = Vector3.new(0.15, 0.6, 0.6)
	r.Color = color
	r.Material = Enum.Material.Neon
	r.Transparency = 0.15
	r.Parent = parent
	Debris:AddItem(r, time + 0.1)
	TweenService:Create(r, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, finalSize, finalSize),
		Transparency = 1,
	}):Play()
end

-- Bright core flash: neon sphere expands and fades.
local function flash(parent: Instance, pos: Vector3, size: number, color: Color3, time: number)
	local f = Instance.new("Part")
	f.Name = "DeathFlashFx"
	f.Shape = Enum.PartType.Ball
	f.Anchored = true
	f.CanCollide = false
	f.CastShadow = false
	f.Size = Vector3.one * 0.5
	f.Color = color
	f.Material = Enum.Material.Neon
	f.Position = pos
	f.Parent = parent
	Debris:AddItem(f, time + 0.1)
	TweenService:Create(f, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
end

-- Ghost of the ball itself: oversize pop + spin + fade (the "WHITEOUT" look).
local function ghostPop(parent: Instance, pos: Vector3, color: Color3)
	local g = Instance.new("Part")
	g.Name = "DeathGhostFx"
	g.Shape = Enum.PartType.Ball
	g.Anchored = true
	g.CanCollide = false
	g.CastShadow = false
	g.Size = Vector3.one * 2.7
	g.Color = color
	g.Material = Enum.Material.Neon
	g.Transparency = 0.25
	g.Position = pos
	g.Parent = parent
	Debris:AddItem(g, 0.55)
	TweenService:Create(g, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * 6.5,
		Transparency = 1,
	}):Play()
end

local STYLES = {
	pop = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		ghostPop(parent, pos, cA)
		flatRing(parent, pos, 12, cB, 0.35)
	end,
	shatter = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		for i = 1, 12 do
			local dir = randDir()
			shard(
				parent,
				pos,
				dir,
				0.3,
				4 + math.random() * 5,
				if i % 2 == 0 then cA else cB,
				0.5 + math.random() * 0.3
			)
		end
		flatRing(parent, pos, 14, cB, 0.4)
	end,
	nova = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		flash(parent, pos, 5, cB, 0.3)
		flatRing(parent, pos, 12, cA, 0.4)
		task.delay(0.12, function()
			flatRing(parent, pos, 22, cB, 0.45)
		end)
		task.delay(0.24, function()
			flatRing(parent, pos, 34, cA, 0.5)
		end)
	end,
	implode = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		for i = 1, 12 do
			local dir = randDir()
			shard(parent, pos, dir, 6 + math.random() * 3, 0.2, if i % 2 == 0 then cA else cB, 0.45)
		end
		task.delay(0.4, function()
			flash(parent, pos, 5.5, cB, 0.3)
			flatRing(parent, pos, 10, cA, 0.35)
		end)
	end,
	-- Upward fountain: shards spray high off the kill spot — reads like a
	-- geyser of light when the run ends.
	geyser = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		for i = 1, 14 do
			local dir =
				Vector3.new((math.random() - 0.5) * 0.9, 0.85 + math.random() * 0.6, (math.random() - 0.5) * 0.9).Unit
			shard(
				parent,
				pos,
				dir,
				0.2,
				9 + math.random() * 7,
				if i % 2 == 0 then cA else cB,
				0.5 + math.random() * 0.3
			)
		end
		flatRing(parent, pos, 12, cB, 0.4)
	end,
	-- Flat bloom: shards placed on a ring around the ball burst outward
	-- level with the deck — the "corona" read.
	corona = function(parent: Instance, pos: Vector3, cA: Color3, cB: Color3)
		for i = 1, 10 do
			local th = (i / 10) * math.pi * 2
			local dir = Vector3.new(math.cos(th), 0.15, math.sin(th)).Unit
			shard(
				parent,
				pos,
				dir,
				0.3,
				7 + math.random() * 4,
				if i % 2 == 0 then cA else cB,
				0.45 + math.random() * 0.2
			)
		end
		flash(parent, pos, 4.5, cB, 0.3)
	end,
}

local function burstInto(parent: Instance, pos: Vector3, item: any)
	local style = (item and item.style) or "shatter"
	local hues = Cosmetics.huesOf(player)
	local cA = Cosmetics.colorOf(item and item.colorA, Color3.fromRGB(0, 230, 255), hues)
	local cB = Cosmetics.colorOf(item and item.colorB, Color3.fromRGB(255, 64, 190), hues)
	local fn = STYLES[style] or STYLES.shatter
	fn(parent, pos, cA, cB)
end

function Fx.burst(pos: Vector3)
	burstInto(workspace, pos, Cosmetics.item(player:GetAttribute("RoBallEq_deathFx") :: string?))
end

-- Garage diorama (CosmeticFx): the same burst fired into the preview's
-- WorldModel, styled by the BROWSED item so unowned merch previews too.
function Fx.previewBurst(parent: Instance, pos: Vector3, item: any)
	burstInto(parent, pos, item)
end

return Fx
