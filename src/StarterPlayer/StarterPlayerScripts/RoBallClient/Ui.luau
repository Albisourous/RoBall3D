--!strict
-- RoBall3D UI — menu, HUD, death screen, all built in code (DESIGN.md §6:
-- everything lives in git, nothing hand-placed in StarterGui). Vaporwave
-- shell: purple-black, hot pink + cyan accents, big centered score.

local Players = game:GetService("Players")

local Ui = {}
Ui.__index = Ui

local C_BG = Color3.fromRGB(8, 4, 14)
local C_PANEL = Color3.fromRGB(20, 10, 34)
local C_PINK = Color3.fromRGB(255, 64, 190)
local C_CYAN = Color3.fromRGB(0, 230, 255)
local C_GOLD = Color3.fromRGB(255, 212, 64)
local C_DIM = Color3.fromRGB(150, 120, 185)
local C_WHITE = Color3.fromRGB(245, 238, 255)

local F_DISPLAY = Enum.Font.SciFi
local F_DATA = Enum.Font.Code

local function label(parent, text, size, font, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.Size = UDim2.new(1, 0, 0, size * 1.4)
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

local function outlineButton(parent, text, size, order)
	local b = Instance.new("TextButton")
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Font = F_DISPLAY
	b.TextSize = size
	b.TextColor3 = C_PINK
	b.Text = text
	b.Size = UDim2.fromOffset(size * 6, size * 1.7)
	b.LayoutOrder = order or 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = C_PINK
	stroke.Thickness = 2
	stroke.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	b.MouseEnter:Connect(function()
		b.TextColor3 = C_CYAN
		stroke.Color = C_CYAN
	end)
	b.MouseLeave:Connect(function()
		b.TextColor3 = C_PINK
		stroke.Color = C_PINK
	end)
	b.Parent = parent
	return b
end

local function vlist(parent, padding)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, padding or 10)
	l.Parent = parent
end

export type Ui = typeof(setmetatable({} :: any, Ui))

function Ui.new(): Ui
	local self = setmetatable({}, Ui)
	self.onPlay = nil :: ((seedText: string) -> ())?
	self.onRetry = nil :: (() -> ())?

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoBallGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	--============================= MENU =============================--
	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.Size = UDim2.fromScale(1, 1)
	menu.BackgroundColor3 = C_BG
	menu.BackgroundTransparency = 0.12
	menu.BorderSizePixel = 0
	menu.Visible = true
	menu.Parent = gui
	self.menu = menu

	local grad = Instance.new("UIGradient")
	grad.Rotation = 115
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 8, 30)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(8, 4, 14)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 18, 30)),
	})
	grad.Parent = menu

	local menuCol = Instance.new("Frame")
	menuCol.BackgroundTransparency = 1
	menuCol.Size = UDim2.fromOffset(520, 420)
	menuCol.Position = UDim2.fromScale(0.5, 0.5)
	menuCol.AnchorPoint = Vector2.new(0.5, 0.5)
	menuCol.Parent = menu
	vlist(menuCol, 14)

	local title = label(menuCol, "ROBALL3D", 72, F_DISPLAY, C_WHITE, 1)
	local tgrad = Instance.new("UIGradient")
	tgrad.Color = ColorSequence.new(C_CYAN, C_PINK)
	tgrad.Rotation = 90
	tgrad.Parent = title

	label(menuCol, "roll forever · don't fall", 18, F_DATA, C_DIM, 2)
	label(menuCol, "", 8, F_DATA, C_DIM, 3)

	local play = outlineButton(menuCol, "PLAY", 40, 4)
	play.Size = UDim2.fromOffset(260, 68)

	label(menuCol, "or press R", 13, F_DATA, C_DIM, 5).TextTransparency = 0.25

	local seedLabel = label(menuCol, "seed — blank = random", 14, F_DATA, C_DIM, 6)
	seedLabel.TextTransparency = 0.2

	local seedBox = Instance.new("TextBox")
	seedBox.BackgroundColor3 = C_PANEL
	seedBox.BackgroundTransparency = 0.35
	seedBox.Font = F_DATA
	seedBox.TextSize = 18
	seedBox.TextColor3 = C_PINK
	seedBox.PlaceholderText = "random"
	seedBox.PlaceholderColor3 = C_DIM
	seedBox.Text = ""
	seedBox.Size = UDim2.fromOffset(260, 34)
	seedBox.ClearTextOnFocus = false
	seedBox.LayoutOrder = 7
	local seedStroke = Instance.new("UIStroke")
	seedStroke.Color = C_DIM
	seedStroke.Transparency = 0.4
	seedStroke.Parent = seedBox
	seedBox.Parent = menuCol
	self.seedBox = seedBox

	self.bestLabel = label(menuCol, "BEST 0", 18, F_DATA, C_CYAN, 8)
	label(menuCol, "", 8, F_DATA, C_DIM, 9)
	label(menuCol, "A/D steer   ·   hold W to boost   ·   R instant restart", 14, F_DATA, C_DIM, 10)

	play.MouseButton1Click:Connect(function()
		if self.onPlay then
			self.onPlay(seedBox.Text)
		end
	end)

	-- Leaderboard: right-side panel, filled via GetLeaderboard remote.
	local board = Instance.new("Frame")
	board.Name = "Leaderboard"
	board.AnchorPoint = Vector2.new(1, 0.5)
	board.Position = UDim2.fromScale(0.96, 0.5)
	board.Size = UDim2.fromOffset(320, 420)
	board.BackgroundColor3 = C_PANEL
	board.BackgroundTransparency = 0.25
	board.BorderSizePixel = 0
	board.Parent = menu
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 10)
	boardCorner.Parent = board

	label(board, "TOP RUNS", 22, F_DISPLAY, C_PINK, 0)
	local boardBody = Instance.new("Frame")
	boardBody.BackgroundTransparency = 1
	boardBody.Size = UDim2.new(1, -24, 1, -50)
	boardBody.Position = UDim2.fromOffset(12, 42)
	boardBody.Parent = board
	vlist(boardBody, 4)
	self.boardRows = {}
	for i = 1, 10 do
		local row = label(boardBody, "", 15, F_DATA, i % 2 == 0 and C_CYAN or C_WHITE, i)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		self.boardRows[i] = row
	end
	self:setLeaderboard(nil)

	--============================= HUD ==============================--
	-- Slope read: one big green score centered at the top; a thin subline
	-- carries distance/speed/seed without competing for attention.
	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0, 10)
	hud.Size = UDim2.fromOffset(560, 92)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.Parent = gui
	self.hud = hud

	local scoreText = Instance.new("TextLabel")
	scoreText.BackgroundTransparency = 1
	scoreText.Font = F_DATA
	scoreText.TextSize = 52
	scoreText.TextColor3 = C_PINK
	scoreText.Size = UDim2.new(1, 0, 0, 58)
	scoreText.Parent = hud
	self.scoreText = scoreText

	local subText = Instance.new("TextLabel")
	subText.BackgroundTransparency = 1
	subText.Font = F_DATA
	subText.TextSize = 15
	subText.TextColor3 = C_DIM
	subText.Position = UDim2.fromOffset(0, 60)
	subText.Size = UDim2.new(1, 0, 0, 20)
	subText.Parent = hud
	self.subText = subText

	--=========== SPEED + BOOST (bottom corners) ===========--
	-- Minimal vaporwave readout (DESIGN.md §12): the speed NUMBER is the
	-- meter — it gradients cyan -> violet -> magenta as speed climbs and
	-- snaps hot red past 100. No dial chrome; the digit does the work.
	local spdNum = Instance.new("TextLabel")
	spdNum.Name = "SpeedNum"
	spdNum.AnchorPoint = Vector2.new(1, 1)
	spdNum.Position = UDim2.new(0.82, 0, 1, -18)
	spdNum.Size = UDim2.fromOffset(180, 62)
	spdNum.BackgroundTransparency = 1
	spdNum.Font = F_DATA
	spdNum.TextSize = 56
	spdNum.TextColor3 = C_CYAN
	spdNum.TextStrokeTransparency = 0.55
	spdNum.TextXAlignment = Enum.TextXAlignment.Right
	spdNum.Text = "0"
	spdNum.Visible = false
	spdNum.Parent = gui
	self.spdNum = spdNum
	local numGrad = Instance.new("UIGradient")
	numGrad.Rotation = 90
	numGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 150, 255))
	numGrad.Parent = spdNum

	local spdUnit = Instance.new("TextLabel")
	spdUnit.AnchorPoint = Vector2.new(1, 1)
	spdUnit.Position = UDim2.new(0.82, 0, 1, -8)
	spdUnit.Size = UDim2.fromOffset(180, 14)
	spdUnit.BackgroundTransparency = 1
	spdUnit.Font = F_DATA
	spdUnit.TextSize = 12
	spdUnit.TextColor3 = C_DIM
	spdUnit.TextXAlignment = Enum.TextXAlignment.Right
	spdUnit.Text = "S/S"
	spdUnit.Visible = false
	spdUnit.Parent = gui
	self.spdUnit = spdUnit

	-- Boost bar: a glanceable horizontal nitro bar. Cyan fill over a dark
	-- track, gold gate tick at RechargeGate, flares pink while boosting,
	-- blinks while latched out.
	local bWrap = Instance.new("Frame")
	bWrap.Name = "BoostBar"
	bWrap.AnchorPoint = Vector2.new(0, 1)
	bWrap.Position = UDim2.new(0.18, 0, 1, -22)
	bWrap.Size = UDim2.fromOffset(220, 16)
	bWrap.BackgroundColor3 = C_BG
	bWrap.BackgroundTransparency = 0.25
	bWrap.BorderSizePixel = 0
	bWrap.Visible = false
	bWrap.Parent = gui
	self.boostBar = bWrap
	local bStroke = Instance.new("UIStroke")
	bStroke.Color = C_CYAN
	bStroke.Thickness = 1.5
	bStroke.Transparency = 0.35
	bStroke.Parent = bWrap
	local bFill = Instance.new("Frame")
	bFill.BackgroundColor3 = C_CYAN
	bFill.BorderSizePixel = 0
	bFill.Size = UDim2.fromScale(1, 1)
	bFill.Parent = bWrap
	self.boostFill = bFill
	local bGate = Instance.new("Frame") -- gate tick; positioned by gateFrac
	bGate.AnchorPoint = Vector2.new(0.5, 0)
	bGate.Position = UDim2.fromScale(0.35, 0)
	bGate.Size = UDim2.fromOffset(2, 16)
	bGate.BackgroundColor3 = C_GOLD
	bGate.BorderSizePixel = 0
	bGate.Parent = bWrap
	self.boostGate = bGate
	local bLab = Instance.new("TextLabel")
	bLab.AnchorPoint = Vector2.new(0, 1)
	bLab.Position = UDim2.fromOffset(0, -3)
	bLab.Size = UDim2.fromOffset(220, 13)
	bLab.BackgroundTransparency = 1
	bLab.Font = F_DATA
	bLab.TextSize = 11
	bLab.TextColor3 = C_DIM
	bLab.TextXAlignment = Enum.TextXAlignment.Left
	bLab.Text = "BOOST  ·  W"
	bLab.Parent = bWrap

	--============================ DEATH =============================--
	local death = Instance.new("Frame")
	death.Name = "Death"
	death.Size = UDim2.fromScale(1, 1)
	death.BackgroundColor3 = C_BG
	death.BackgroundTransparency = 0.35
	death.BorderSizePixel = 0
	death.Visible = false
	death.Parent = gui
	self.death = death

	local dCol = Instance.new("Frame")
	dCol.BackgroundTransparency = 1
	dCol.Size = UDim2.fromOffset(460, 320)
	dCol.Position = UDim2.fromScale(0.5, 0.42)
	dCol.AnchorPoint = Vector2.new(0.5, 0.5)
	dCol.Parent = death
	vlist(dCol, 10)

	label(dCol, "RUN OVER", 52, F_DISPLAY, C_PINK, 1)
	self.dScore = label(dCol, "SCORE 0", 34, F_DATA, C_CYAN, 2)
	self.dBreakdown = label(dCol, "0 m · 0 gems", 18, F_DATA, C_WHITE, 3)
	self.dBest = label(dCol, "BEST 0", 18, F_DATA, C_GOLD, 4)
	self.dSeed = label(dCol, "SEED 0", 14, F_DATA, C_DIM, 5)
	local retry = outlineButton(dCol, "RETRY", 30, 6)
	retry.Size = UDim2.fromOffset(300, 56)
	retry.MouseButton1Click:Connect(function()
		if self.onRetry then
			self.onRetry()
		end
	end)
	label(dCol, "or press R", 13, F_DATA, C_DIM, 7)

	return self
end

function Ui:showMenu(best: number)
	self.menu.Visible = true
	self.death.Visible = false
	self.hud.Visible = false
	self.spdNum.Visible = false
	self.spdUnit.Visible = false
	self.boostBar.Visible = false
	self.bestLabel.Text = "BEST " .. tostring(best or 0)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.hud.Visible = true
	self.spdNum.Visible = true
	self.spdUnit.Visible = true
	self.boostBar.Visible = true
end

function Ui:setHud(score: number, dist: number, gems: number, _speed: number, seed: number)
	self.scoreText.Text = tostring(score)
	-- Speed lives on the dial now; the subline stays quiet.
	self.subText.Text = string.format("%d m  ·  gems +%d  ·  seed %d", dist, gems, seed)
end

-- Speed number + boost bar, called every heartbeat during a run.
-- The digit's hue IS the speed read: cyan 0 -> magenta 100 -> hot red
-- pegged past it. The boost bar pulses pink while W is held and blinks
-- while the meter is latched out below RechargeGate.
function Ui:setSpeedo(speed: number, boostFrac: number, boosting: boolean, boostSpent: boolean)
	self.spdNum.Text = tostring(math.floor(speed + 0.5))
	if speed >= 100 then
		-- Over the line: flat hot red, pulsing so it reads as "pegged".
		local v = 0.85 + 0.15 * math.sin(tick() * 9)
		self.spdNum.TextColor3 = Color3.fromRGB(255, 40, 60):Lerp(Color3.fromRGB(255, 120, 140), v)
	else
		-- Gradient hue cyan(0.53) -> violet(0.75) -> magenta(0.88) with speed.
		local h = 0.53 + (speed / 100) * 0.35
		self.spdNum.TextColor3 = Color3.fromHSV(h, 0.92, 1)
	end
	if self.gateFrac then
		self.boostGate.Position = UDim2.fromScale(self.gateFrac, 0)
	end
	self.boostFill.Size = UDim2.fromScale(math.clamp(boostFrac, 0, 1), 1)
	local blink = boostSpent and math.sin(tick() * 10) > 0
	self.boostFill.BackgroundColor3 = (boosting or blink) and C_PINK or C_CYAN
end

function Ui:showDeath(score: number, dist: number, gems: number, best: number, seed: number)
	self.menu.Visible = false
	self.hud.Visible = false
	self.spdNum.Visible = false
	self.spdUnit.Visible = false
	self.boostBar.Visible = false
	self.death.Visible = true
	self.dScore.Text = "SCORE " .. tostring(score)
	self.dBreakdown.Text = string.format("%d m  ·  +%d gem pts", dist, gems)
	self.dBest.Text = "BEST " .. tostring(best)
	self.dSeed.Text = "SEED " .. tostring(seed)
end

function Ui:setLeaderboard(rows: { { name: string, score: number, seed: number } }?)
	for i, row in ipairs(self.boardRows) do
		local r = rows and rows[i]
		row.Text = r and string.format("%2d. %-14s %7d  #%d", i, r.name, r.score, r.seed) or ""
	end
	if not rows or #rows == 0 then
		self.boardRows[1].Text = "  no saved runs yet — set one."
	end
end

function Ui:seedText(): string
	return self.seedBox.Text
end

return Ui
