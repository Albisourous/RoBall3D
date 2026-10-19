--!strict
-- RoBall3D UI — menu, HUD, death screen, all built in code (DESIGN.md §6:
-- everything lives in git, nothing hand-placed in StarterGui). Vaporwave
-- shell: dark gradient, SciFi display font, Code data font, cyan/magenta.

local Players = game:GetService("Players")

local Ui = {}
Ui.__index = Ui

local C_BG = Color3.fromRGB(10, 7, 18)
local C_PANEL = Color3.fromRGB(14, 10, 26)
local C_MAGENTA = Color3.fromRGB(255, 45, 120)
local C_CYAN = Color3.fromRGB(0, 255, 240)
local C_DIM = Color3.fromRGB(140, 130, 160)
local C_WHITE = Color3.fromRGB(240, 240, 250)

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
	b.TextColor3 = C_CYAN
	b.Text = text
	b.Size = UDim2.fromOffset(size * 6, size * 1.7)
	b.LayoutOrder = order or 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = C_CYAN
	stroke.Thickness = 2
	stroke.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	b.MouseEnter:Connect(function()
		b.TextColor3 = C_MAGENTA
		stroke.Color = C_MAGENTA
	end)
	b.MouseLeave:Connect(function()
		b.TextColor3 = C_CYAN
		stroke.Color = C_CYAN
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 8, 40)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(10, 7, 18)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 20, 44)),
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
	tgrad.Color = ColorSequence.new(C_MAGENTA, C_CYAN)
	tgrad.Rotation = 90
	tgrad.Parent = title

	label(menuCol, "roll forever · don't fall", 18, F_DATA, C_DIM, 2)
	label(menuCol, "", 8, F_DATA, C_DIM, 3)

	local play = outlineButton(menuCol, "PLAY", 40, 4)
	play.Size = UDim2.fromOffset(260, 68)

	local seedLabel = label(menuCol, "seed — blank = random", 14, F_DATA, C_DIM, 5)
	seedLabel.TextTransparency = 0.2

	local seedBox = Instance.new("TextBox")
	seedBox.BackgroundColor3 = C_PANEL
	seedBox.BackgroundTransparency = 0.35
	seedBox.Font = F_DATA
	seedBox.TextSize = 18
	seedBox.TextColor3 = C_CYAN
	seedBox.PlaceholderText = "random"
	seedBox.PlaceholderColor3 = C_DIM
	seedBox.Text = ""
	seedBox.Size = UDim2.fromOffset(260, 34)
	seedBox.ClearTextOnFocus = false
	seedBox.LayoutOrder = 6
	local seedStroke = Instance.new("UIStroke")
	seedStroke.Color = C_DIM
	seedStroke.Transparency = 0.4
	seedStroke.Parent = seedBox
	seedBox.Parent = menuCol
	self.seedBox = seedBox

	self.bestLabel = label(menuCol, "BEST 0", 18, F_DATA, C_MAGENTA, 7)
	label(menuCol, "", 8, F_DATA, C_DIM, 8)
	label(menuCol, "A/D steer   ·   W/S speed   ·   R retry after death", 14, F_DATA, C_DIM, 9)

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

	label(board, "TOP RUNS", 22, F_DISPLAY, C_MAGENTA, 0)
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
	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0, 14)
	hud.Size = UDim2.fromOffset(560, 40)
	hud.BackgroundColor3 = C_BG
	hud.BackgroundTransparency = 0.45
	hud.BorderSizePixel = 0
	hud.Visible = false
	hud.Parent = gui
	self.hud = hud
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hud

	local hudText = Instance.new("TextLabel")
	hudText.BackgroundTransparency = 1
	hudText.Font = F_DATA
	hudText.TextSize = 20
	hudText.TextColor3 = C_CYAN
	hudText.Size = UDim2.fromScale(1, 1)
	hudText.Parent = hud
	self.hudText = hudText

	local hudAccent = Instance.new("Frame")
	hudAccent.BackgroundColor3 = C_MAGENTA
	hudAccent.BorderSizePixel = 0
	hudAccent.Size = UDim2.new(1, 0, 0, 2)
	hudAccent.Position = UDim2.new(0, 0, 1, -2)
	hudAccent.Parent = hud

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

	label(dCol, "RUN OVER", 52, F_DISPLAY, C_MAGENTA, 1)
	self.dScore = label(dCol, "SCORE 0", 34, F_DATA, C_CYAN, 2)
	self.dBreakdown = label(dCol, "0 m · 0 gems", 18, F_DATA, C_WHITE, 3)
	self.dBest = label(dCol, "BEST 0", 18, F_DATA, C_MAGENTA, 4)
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
	self.bestLabel.Text = "BEST " .. tostring(best or 0)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.hud.Visible = true
end

function Ui:setHud(score: number, dist: number, gems: number, speed: number, seed: number)
	self.hudText.Text =
		string.format("SCORE %d  ·  %d m  ·  GEMS +%d  ·  %d s/s  ·  SEED %d", score, dist, gems, speed, seed)
end

function Ui:showDeath(score: number, dist: number, gems: number, best: number, seed: number)
	self.menu.Visible = false
	self.hud.Visible = false
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
