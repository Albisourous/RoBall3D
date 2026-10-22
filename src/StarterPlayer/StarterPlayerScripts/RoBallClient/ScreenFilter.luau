--!strict
-- ScreenFilter (§18 "filter" slot): a retro overlay over the 3D view.
--   "pixel"    — PIXEL GLASS: an LCD lattice, dark gridlines every
--                pitch px — the whole scene reads as chunky pixels.
--   "scan"     — SCANLINES/PHOSPHOR: horizontal bars only, a CRT raster.
--                item.pitch/bar/alpha retune the lattice recipe.
--   "tint"     — a full-screen color grade wash (item.tint + item.alpha).
--   "vignette" — dark edge falloff, a tube-TV frame around the playfield.
-- The overlay sits on its own ScreenGui at a lower DisplayOrder than the
-- HUD (Ui's gui is 10) — every line of text renders above the lattice and
-- stays crisp; the filter never touches readability.
-- Equip path mirrors Backdrop: the RoBallEq_filter attribute lands async
-- after join, the listener swaps live. Non-owners pay nothing — the bar
-- pool builds lazily on first equip.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)

local Art = Config.Art
local player = Players.LocalPlayer

local ScreenFilter = {}

local gui: ScreenGui? = nil
local bars: { Frame } = {} -- pooled lattice lines; relayout hides spares
local live = "off" -- "off" | "scan" | "pixel" | "tint" | "vignette"
local liveItem: any = nil -- equipped filter record; fields override Art defaults

local function ensureGui(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "RoBallFilter"
	g.IgnoreGuiInset = true
	g.DisplayOrder = 1 -- everything readable lives on higher orders
	g.ResetOnSpawn = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

local function barAt(i: number): Frame
	local f = bars[i]
	if not f then
		f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Parent = ensureGui()
		bars[i] = f
	end
	local it = liveItem
	f.BackgroundColor3 = if it and it.tint then it.tint else Art.PixelColor
	f.BackgroundTransparency = 1 - (if it and it.alpha then it.alpha else Art.PixelAlpha)
	f.Visible = true
	return f
end

-- One full-screen frame with a UIGradient transparency profile — used for
-- the tint wash (flat) and each vignette axis (dark edges, clear center).
-- Pooled by name like the bar pool so re-equips don't stack frames.
local function gradeAt(i: number, rotation: number, keys: { NumberSequenceKeypoint }): Frame
	local g = ensureGui()
	local f = g:FindFirstChild("G" .. i) :: Frame?
	if not f then
		f = Instance.new("Frame")
		f.Name = "G" .. i
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(1, 1)
		f.Parent = g
	end
	f.BackgroundColor3 = Art.PixelColor
	local grad = f:FindFirstChildOfClass("UIGradient")
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Parent = f
	end
	grad.Rotation = rotation
	grad.Transparency = NumberSequence.new(keys)
	f.Visible = true
	return f
end

-- Lay the lattice to the current viewport: "pixel" gets the full grid,
-- "scan" only the raster lines. Bars past the needed count park hidden.
-- The equipped item's pitch/bar override Config.Art's recipe so filter
-- variants (PHOSPHOR's fine raster) share one code path.
local function relayout()
	local cam = workspace.CurrentCamera
	if not cam or (live ~= "scan" and live ~= "pixel") then
		return
	end
	local size = cam.ViewportSize
	local it = liveItem
	local pitch = math.max(if it and it.pitch then it.pitch else Art.PixelPitch, 3)
	local thick = if it and it.bar then it.bar else Art.PixelBar
	local i = 0
	if live == "pixel" then
		for c = 0, math.ceil(size.X / pitch) do
			i += 1
			local f = barAt(i)
			f.Size = UDim2.new(0, thick, 1, 0)
			f.Position = UDim2.fromOffset(c * pitch, 0)
		end
	end
	for r = 0, math.ceil(size.Y / pitch) do
		i += 1
		local f = barAt(i)
		f.Size = UDim2.new(1, 0, 0, thick)
		f.Position = UDim2.fromOffset(0, r * pitch)
	end
	for j = i + 1, #bars do
		bars[j].Visible = false
	end
end

local function hideAll()
	for _, f in ipairs(bars) do
		f.Visible = false
	end
	local g = ensureGui()
	for _, c in ipairs(g:GetChildren()) do
		if c.Name:sub(1, 1) == "G" then
			c.Visible = false
		end
	end
end

local function apply(item: any)
	liveItem = item
	live = if item and item.filter then item.filter else "off"
	local g = ensureGui()
	hideAll()
	if live == "off" then
		g.Enabled = false
		return
	end
	g.Enabled = true
	if live == "scan" or live == "pixel" then
		relayout()
	elseif live == "tint" then
		-- Color grade: a flat wash at the item's alpha — reads as a lens.
		local f = gradeAt(1, 0, {
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
		f.BackgroundColor3 = if liveItem.tint then liveItem.tint else Art.PixelColor
		f.BackgroundTransparency = 1 - (if liveItem.alpha then liveItem.alpha else 0.12)
	elseif live == "vignette" then
		-- Dark edge falloff on both axes — the corner double-cover is what
		-- rounds it into a vignette instead of a letterbox.
		local keys = {
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.35, 0.9),
			NumberSequenceKeypoint.new(0.65, 0.9),
			NumberSequenceKeypoint.new(1, 0.55),
		}
		gradeAt(1, 0, keys)
		gradeAt(2, 90, keys)
	end
end

function ScreenFilter.init()
	local function fromAttr()
		apply(Cosmetics.item(player:GetAttribute("RoBallEq_filter") :: string?))
	end
	player:GetAttributeChangedSignal("RoBallEq_filter"):Connect(fromAttr)
	fromAttr()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
end

return ScreenFilter
