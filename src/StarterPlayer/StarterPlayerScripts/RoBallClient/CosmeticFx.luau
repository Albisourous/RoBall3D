--!strict
-- CosmeticFx (DESIGN.md §18): client-local vanity surfaces.
-- 1) Menu preview ball — a dressed ball parked at the menu camera's look
--    target, rebuilt on every equip change so the garage has a live
--    mannequin. Destroyed outside menu mode (it would haunt the lane).
-- 2) Animated skin/trail flags ("rainbow"/"pulse") applied to the live
--    ball AND the preview in the render loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local BallDress = require(ReplicatedStorage.RoBall.BallDress)
local Palette = require(ReplicatedStorage.RoBall.Palette)

local player = Players.LocalPlayer

-- The live ball comes from Main's getter (PERFORMANCE.md §1): polling
-- workspace:FindFirstChild by name every render frame was a per-frame
-- string-keyed lookup — the bound ball is already canonical.
local getBall: () -> BasePart? = function()
	return nil
end

-- Menu cam orbits but always aims at (0, StartY-15, -120): a ball parked
-- on that look-ray stays centered in frame at any orbit phase. Rendered 5x
-- and pulled close to the orbit — the menu sits over the vista at ~88%
-- opacity, so only a big neon presence bleeds through as the mannequin.
local PREVIEW_POS = Vector3.new(0, Config.Generation.StartY - 12, -70)
local PREVIEW_SCALE = 5

local Fx = {}

local preview: BasePart? = nil
local inMenu = false

local skinItem: any = nil
local trailItem: any = nil

type Watched = { rings: { CylinderHandleAdornment }, bases: { Color3 }, trail: Trail? }
local watched: { [BasePart]: Watched } = {}

local function equipped()
	skinItem = Cosmetics.item(player:GetAttribute("RoBallEq_skin") :: string?)
	trailItem = Cosmetics.item(player:GetAttribute("RoBallEq_trail") :: string?)
end

-- Snapshot a dressed ball's rings (+base colors for pulse) and trail.
local function collect(ball: BasePart)
	local w: Watched = { rings = {}, bases = {}, trail = ball:FindFirstChildOfClass("Trail") }
	for _, c in ipairs(ball:GetChildren()) do
		if c:IsA("CylinderHandleAdornment") then
			table.insert(w.rings, c)
			table.insert(w.bases, c.Color3)
		end
	end
	watched[ball] = w
end

local function buildPreview()
	if preview then
		preview:Destroy()
		preview = nil
	end
	local d = Config.Ball.Diameter * PREVIEW_SCALE
	local b = Instance.new("Part")
	b.Name = "RoBallPreview"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.one * d
	b.Anchored = true
	b.CanCollide = false
	b.CastShadow = false
	b.Material = Enum.Material.SmoothPlastic
	b.Position = PREVIEW_POS
	BallDress.dress(b, skinItem, trailItem, PREVIEW_SCALE, Cosmetics.huesOf(player))
	b.Parent = workspace
	preview = b
	collect(b)
end

local ANIM_FX = { rainbow = true, pulse = true, strobe = true, wave = true }

local function step()
	local fx = skinItem and skinItem.fx
	local doRings = ANIM_FX[fx] == true
	local doTrail = trailItem ~= nil and trailItem.color == "rainbow"
	if not doRings and not doTrail then
		return
	end
	local h = (tick() * 0.28) % 1
	local k = 0.5 + 0.5 * math.sin(tick() * 2.6)
	for ball, w in pairs(watched) do
		if not ball.Parent then
			watched[ball] = nil
			continue
		end
		if doRings then
			for i, r in ipairs(w.rings) do
				if fx == "rainbow" then
					r.Color3 = Color3.fromHSV((h + i * 0.13) % 1, 0.9, 1)
				elseif fx == "strobe" then
					-- Hot flicker: fast hue cycle + per-ring bright/dark
					-- alternation — the CHROMA skin's marquee look.
					local v = if math.floor(tick() * 7 + i) % 2 == 0 then 1 else 0.28
					r.Color3 = Color3.fromHSV((h * 2.2 + i * 0.4) % 1, 0.95, v)
				elseif fx == "wave" then
					-- The run palette flows across the rings, offset per
					-- ring — the IRIS skin's gradient-cage look.
					r.Color3 = Palette.neonAt(tick() * 60 + i * 35)
				else -- pulse
					r.Color3 = w.bases[i]:Lerp(Color3.new(0, 0, 0), 0.55 * k)
				end
			end
		end
		if doTrail and w.trail then
			w.trail.Color = ColorSequence.new(Color3.fromHSV(h, 0.95, 1))
		end
	end
end

-- Mode transitions: the preview exists only in the menu vista.
function Fx.onMode(mode: string)
	inMenu = mode == "menu"
	if inMenu then
		equipped()
		buildPreview()
	elseif preview then
		preview:Destroy()
		preview = nil
	end
end

-- Equip/attribute change: re-read ids and re-dress the mannequin. The live
-- ball's static colors are re-painted server-side (BallDress.retint).
function Fx.refresh()
	equipped()
	if inMenu then
		buildPreview()
	end
end

function Fx.init(ballGetter: () -> BasePart?)
	getBall = ballGetter
	equipped()
	-- COLOR LAB (§18): a hue write lands on attributes — re-dress the
	-- mannequin so the sliders preview live.
	for _, attr in pairs(Cosmetics.HueAttr) do
		player:GetAttributeChangedSignal(attr):Connect(Fx.refresh)
	end
	RunService.RenderStepped:Connect(function()
		local fx = skinItem and skinItem.fx
		local anim = ANIM_FX[fx] == true or (trailItem ~= nil and trailItem.color == "rainbow")
		if anim then
			-- Lazy-collect the run ball: replication order of parts vs
			-- adornments isn't guaranteed, so watch until rings show up.
			local b = getBall()
			if b and not watched[b] and b:FindFirstChildOfClass("CylinderHandleAdornment") then
				collect(b)
			end
		end
		if preview then
			-- Slow tumble so the wireframe cage reads as 3D.
			preview.CFrame = CFrame.new(PREVIEW_POS) * CFrame.Angles(tick() * 0.9, tick() * 0.5, 0)
		end
		step()
	end)
end

return Fx
