--!strict
-- ScreenFilter (§18 "filter" slot): a retro overlay over the 3D view.
--   "pixel" — PIXEL GLASS: an LCD lattice, dark gridlines every
--             PixelPitch px — the whole scene reads as chunky pixels.
--   "scan"  — SCANLINES: horizontal bars only, a CRT raster.
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
local live = "off" -- "off" | "scan" | "pixel"

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
		f.BackgroundColor3 = Art.PixelColor
		f.BackgroundTransparency = 1 - Art.PixelAlpha
		f.Parent = ensureGui()
		bars[i] = f
	end
	f.Visible = true
	return f
end

-- Lay the lattice to the current viewport: "pixel" gets the full grid,
-- "scan" only the raster lines. Bars past the needed count park hidden.
local function relayout()
	local cam = workspace.CurrentCamera
	if not cam or live == "off" then
		return
	end
	local size = cam.ViewportSize
	local pitch = math.max(Art.PixelPitch, 3)
	local i = 0
	if live == "pixel" then
		for c = 0, math.ceil(size.X / pitch) do
			i += 1
			local f = barAt(i)
			f.Size = UDim2.new(0, Art.PixelBar, 1, 0)
			f.Position = UDim2.fromOffset(c * pitch, 0)
		end
	end
	for r = 0, math.ceil(size.Y / pitch) do
		i += 1
		local f = barAt(i)
		f.Size = UDim2.new(1, 0, 0, Art.PixelBar)
		f.Position = UDim2.fromOffset(0, r * pitch)
	end
	for j = i + 1, #bars do
		bars[j].Visible = false
	end
end

local function apply(mode: string)
	live = mode
	if mode == "off" then
		if gui then
			gui.Enabled = false
		end
		return
	end
	ensureGui().Enabled = true
	relayout()
end

function ScreenFilter.init()
	local function fromAttr()
		local item = Cosmetics.item(player:GetAttribute("RoBallEq_filter") :: string?)
		apply(if item and item.filter then item.filter else "off")
	end
	player:GetAttributeChangedSignal("RoBallEq_filter"):Connect(fromAttr)
	fromAttr()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
end

return ScreenFilter
