--!strict
-- RoBall3D UI — menu, HUD, death screen, all built in code (DESIGN.md §6:
-- everything lives in git, nothing hand-placed in StarterGui). Vaporwave
-- shell: purple-black, hot pink + cyan accents, big centered score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Daily = require(ReplicatedStorage.RoBall.Daily)
local AudioMix = require(script.Parent.AudioMix)

local Ui = {}
Ui.__index = Ui

local C_BG = Color3.fromRGB(8, 4, 14)
local C_PANEL = Color3.fromRGB(20, 10, 34)
local C_PINK = Color3.fromRGB(255, 64, 190)
local C_CYAN = Color3.fromRGB(0, 230, 255)
local C_GOLD = Color3.fromRGB(255, 212, 64)
local C_DIM = Color3.fromRGB(150, 120, 185)
local C_WHITE = Color3.fromRGB(245, 238, 255)
local C_GATE_DIM = C_GOLD:Lerp(C_PANEL, 0.78) -- unlit lock-zone cells: faint warm wash

-- Daily-tab status line (§14): today's shared seed + UTC reset countdown
-- + the player's consecutive-day streak when one is alive.
local function dailyText(): string
	local s = Daily.resetIn()
	local text = string.format("seed #%d · resets in %02d:%02d", Daily.seed(), s // 3600, (s % 3600) // 60)
	local lp = Players.LocalPlayer
	local streak = (lp and lp:GetAttribute("RoBallDailyStreak")) or 0
	if streak > 0 then
		text ..= string.format(" · day-%d streak", streak)
	end
	return text
end

-- Weekly-cup status line (§14): this week's shared seed + reset countdown.
local function weeklyText(): string
	local s = Daily.weekResetIn()
	return string.format("cup seed #%d · resets in %dd %02dh", Daily.weekSeed(), s // 86400, (s % 86400) // 3600)
end

-- Vaporwave type system (DESIGN.md §12): three voices, one job each.
--   F_HERO    — Garamond spaced caps: the Floral Shoppe serif for
--               "A E S T H E T I C" titles — menu name + RUN OVER only.
--   F_DISPLAY — Michroma: geometric retro-future caps for chrome
--               headers (TOP RUNS / GARAGE / BANK) and action buttons.
--   F_DATA    — Code: the machine voice — every number, tag and readout
--               (the server's PB gate and GemFx popups share it inline).
local F_HERO = Enum.Font.Garamond
local F_DISPLAY = Enum.Font.Michroma
local F_DATA = Enum.Font.Code

-- Letterspaced caps for the hero serif: "RUN OVER" -> "R U N  O V E R".
local function spaced(s: string): string
	local out = {}
	for w in s:gmatch("%S+") do
		table.insert(out, table.concat(w:split(""), " "))
	end
	return table.concat(out, "  ")
end

-- Power meter strip geometry: LED-cell count + the segment strip's inset
-- inside the capsule (tip/gate math derives the inner width from it).
local METER_W = 220
local METER_SEGS = 14
local METER_PAD = 9

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

-- Quiet text-only button for secondary actions — no box, mono font. The
-- stroked SciFi outline treatment reads as a blur at small sizes.
local function ghostButton(parent, text, size, order)
	local b = Instance.new("TextButton")
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Font = F_DATA
	b.TextSize = size
	b.TextColor3 = C_DIM
	b.Text = text
	b.Size = UDim2.fromOffset(size * 8, size * 1.6)
	b.LayoutOrder = order or 0
	b.MouseEnter:Connect(function()
		b.TextColor3 = C_WHITE
	end)
	b.MouseLeave:Connect(function()
		b.TextColor3 = C_DIM
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
	self.onMenu = nil :: (() -> ())?
	self.onRerun = nil :: (() -> ())?
	self.onEquipCycle = nil :: ((slot: string, dir: number) -> ())?
	self.onItemSlot = nil :: ((slot: string) -> ())? -- click displayed item name
	self.onBuy = nil :: ((bundleId: string) -> ())?
	self.onGemPack = nil :: ((productKey: string) -> ())?

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
	menuCol.Name = "Hero"
	menuCol.BackgroundTransparency = 1
	menuCol.Size = UDim2.fromOffset(520, 700) -- hero column: title, PLAY, run setup, missions
	menuCol.Position = UDim2.fromScale(0.5, 0.5)
	menuCol.AnchorPoint = Vector2.new(0.5, 0.5)
	menuCol.Parent = menu
	vlist(menuCol, 10)

	local title = label(menuCol, spaced("ROBALL3D"), 72, F_HERO, C_WHITE, 1)
	local tgrad = Instance.new("UIGradient")
	tgrad.Color = ColorSequence.new(C_CYAN, C_PINK)
	tgrad.Rotation = 90
	tgrad.Parent = title

	label(menuCol, "roll forever · don't fall", 18, F_DATA, C_DIM, 2)
	label(menuCol, "", 6, F_DATA, C_DIM, 3)

	-- PLAY is the single solid element on the menu — a filled neon slab,
	-- not another ghosted outline, so the one action that matters reads
	-- first. ENTER and R both start.
	local play = Instance.new("TextButton")
	play.Name = "PlayBtn"
	play.BackgroundColor3 = C_PINK
	play.AutoButtonColor = false
	play.Font = F_DISPLAY
	play.TextSize = 34
	play.TextColor3 = Color3.fromRGB(16, 6, 24)
	play.Text = "PLAY"
	play.Size = UDim2.fromOffset(300, 74)
	play.LayoutOrder = 4
	play.Parent = menuCol
	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(0, 12)
	playCorner.Parent = play
	local playGrad = Instance.new("UIGradient")
	playGrad.Rotation = 90
	playGrad.Color = ColorSequence.new(C_PINK:Lerp(C_WHITE, 0.18), C_PINK:Lerp(Color3.fromRGB(90, 0, 60), 0.25))
	playGrad.Parent = play
	local playStroke = Instance.new("UIStroke")
	playStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	playStroke.Color = C_CYAN
	playStroke.Thickness = 1.5
	playStroke.Transparency = 0.55
	playStroke.Parent = play
	play.MouseEnter:Connect(function()
		play.TextColor3 = C_WHITE
		playStroke.Transparency = 0.05
	end)
	play.MouseLeave:Connect(function()
		play.TextColor3 = Color3.fromRGB(16, 6, 24)
		playStroke.Transparency = 0.55
	end)

	label(menuCol, "press ENTER / R to roll", 13, F_DATA, C_DIM, 5).TextTransparency = 0.25

	self.bestLabel = label(menuCol, "BEST 0", 18, F_DATA, C_CYAN, 6)

	-- RUN SETUP (§6): everything that shapes THIS run lives next to PLAY —
	-- one-tap RANDOM/DAILY chips write the seed box, or type a
	-- custom seed, and the TRACK cycler picks the song. The old cryptic
	-- "blank = random · 'daily' = today" explainer is gone: the chips are
	-- self-describing.
	local setup = Instance.new("Frame")
	setup.Name = "RunSetup"
	setup.BackgroundColor3 = C_PANEL
	setup.BackgroundTransparency = 0.45
	setup.BorderSizePixel = 0
	setup.Size = UDim2.fromOffset(392, 122)
	setup.LayoutOrder = 7
	setup.Parent = menuCol
	local setupCorner = Instance.new("UICorner")
	setupCorner.CornerRadius = UDim.new(0, 10)
	setupCorner.Parent = setup
	local setupStroke = Instance.new("UIStroke")
	setupStroke.Color = C_DIM
	setupStroke.Thickness = 1
	setupStroke.Transparency = 0.55
	setupStroke.Parent = setup

	local seedBox = Instance.new("TextBox")
	seedBox.Name = "SeedBox"
	seedBox.BackgroundColor3 = C_BG
	seedBox.BackgroundTransparency = 0.3
	seedBox.BorderSizePixel = 0
	seedBox.Font = F_DATA
	seedBox.TextSize = 17
	seedBox.TextColor3 = C_PINK
	seedBox.PlaceholderText = "or type a seed"
	seedBox.PlaceholderColor3 = C_DIM
	seedBox.Text = "daily" -- default: race today's shared board, not a throwaway
	seedBox.Position = UDim2.fromOffset(18, 46)
	seedBox.Size = UDim2.fromOffset(356, 30)
	seedBox.ClearTextOnFocus = false
	local seedStroke = Instance.new("UIStroke")
	seedStroke.Color = C_DIM
	seedStroke.Transparency = 0.5
	seedStroke.Parent = seedBox
	seedBox.Parent = setup
	self.seedBox = seedBox

	-- Seed chips: segmented quick-pick — RANDOM or DAILY. Lit chip
	-- = what PLAY will run; a typed seed unlatches them all (custom read).
	local chipBtns: { [string]: TextButton } = {}
	local function paintChips()
		local t = string.lower(seedBox.Text)
		local lit = if t == "" then "random" elseif Daily.isKeyword(t) then "daily" else ""
		for key, b in pairs(chipBtns) do
			local on = key == lit
			b.TextColor3 = on and C_PINK or C_DIM
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = b.TextColor3
			end
		end
	end
	for i, key in ipairs({ "random", "daily" }) do
		local b = Instance.new("TextButton")
		b.Name = "Chip" .. key
		b.BackgroundColor3 = C_BG
		b.BackgroundTransparency = 0.3
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 13
		b.TextColor3 = C_DIM
		b.Text = string.upper(key)
		b.Position = UDim2.fromOffset(18 + (i - 1) * 185, 12)
		b.Size = UDim2.fromOffset(171, 26)
		b.Parent = setup
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = b
		local bs = Instance.new("UIStroke")
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bs.Color = C_DIM
		bs.Thickness = 1
		bs.Parent = b
		chipBtns[key] = b
		b.MouseButton1Click:Connect(function()
			seedBox.Text = if key == "random" then "" else key
		end)
	end
	seedBox:GetPropertyChangedSignal("Text"):Connect(paintChips)
	paintChips()

	-- TRACK cycler (AUDIO.md §3): the run's song, picked like an equip —
	-- run-scoped, so it lives in the setup cluster, not the garage.
	local trkLabel = Instance.new("TextLabel")
	trkLabel.BackgroundTransparency = 1
	trkLabel.Font = F_DATA
	trkLabel.TextSize = 12
	trkLabel.TextColor3 = C_DIM
	trkLabel.TextXAlignment = Enum.TextXAlignment.Left
	trkLabel.Text = "TRACK"
	trkLabel.Position = UDim2.fromOffset(18, 84)
	trkLabel.Size = UDim2.fromOffset(56, 26)
	trkLabel.Parent = setup

	local trkName = Instance.new("TextButton")
	trkName.Name = "TrackName"
	trkName.BackgroundTransparency = 1
	trkName.AutoButtonColor = false
	trkName.Font = F_DATA
	trkName.TextSize = 15
	trkName.TextColor3 = C_WHITE
	trkName.Text = "SEEDED"
	trkName.Position = UDim2.fromOffset(102, 84)
	trkName.Size = UDim2.fromOffset(190, 26)
	trkName.TextXAlignment = Enum.TextXAlignment.Center
	trkName.Parent = setup
	self.trackName = trkName

	local function arrowButton(parent, text, x, y)
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 20
		b.TextColor3 = C_CYAN
		b.Text = text
		b.Position = UDim2.fromOffset(x, y - 2)
		b.Size = UDim2.fromOffset(26, 30)
		b.Parent = parent
		return b
	end

	local trkLeft = arrowButton(setup, "<", 74, 84)
	trkLeft.Name = "TrackPrev"
	trkLeft.MouseButton1Click:Connect(function()
		if self.onTrackCycle then
			self.onTrackCycle(-1)
		end
	end)
	local trkRight = arrowButton(setup, ">", 296, 84)
	trkRight.Name = "TrackNext"
	trkRight.MouseButton1Click:Connect(function()
		if self.onTrackCycle then
			self.onTrackCycle(1)
		end
	end)

	label(menuCol, "", 4, F_DATA, C_DIM, 8)
	-- Daily quests (§14): today's three seeded missions — ✓ gold when done,
	-- ◇ dim while open; the bank quest shows today's running total.
	label(menuCol, "today's missions", 12, F_DATA, C_DIM, 9)
	self.questLines = {}
	for i = 1, 3 do
		self.questLines[i] = label(menuCol, "", 14, F_DATA, C_DIM, 9 + i)
	end
	-- Achievements (§14): running unlock count — the celebration itself is
	-- the toast; the menu keeps only the tally.
	self.achLine = label(menuCol, "", 12, F_DATA, C_GOLD, 13)
	label(menuCol, "", 4, F_DATA, C_DIM, 14)
	label(menuCol, "A/D steer   ·   W/S boost/brake   ·   Q/E dash   ·   R restart", 14, F_DATA, C_DIM, 15)

	-- Audio mixer (AUDIO.md §7 / DESIGN.md §6): a mini console hidden
	-- behind an "audio" toggle — click to unfold the channel rows. Drag
	-- applies instantly; release persists through RoBallVol_<ch> ->
	-- profile.audio.
	local mixerRows: { Frame } = {}
	local mixerOpen = false
	local audioToggle = ghostButton(menuCol, "audio ▸", 11, 16)
	audioToggle.MouseButton1Click:Connect(function()
		mixerOpen = not mixerOpen
		audioToggle.Text = if mixerOpen then "audio ▾" else "audio ▸"
		for _, row in ipairs(mixerRows) do
			row.Visible = mixerOpen
		end
	end)
	local function sliderUnit(parent: Frame, ch: string, x: number)
		local name = label(parent, Config.Audio.Labels[ch], 11, F_DATA, C_DIM)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Size = UDim2.fromOffset(64, 19)
		name.Position = UDim2.fromOffset(x, 0)

		local track = Instance.new("Frame")
		track.BackgroundColor3 = C_BG
		track.BorderSizePixel = 0
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, x + 68, 0.5, 0)
		track.Size = UDim2.fromOffset(120, 7)
		track.Parent = parent
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 4)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = C_CYAN
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = track
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill

		local pct = label(parent, "", 10, F_DATA, C_WHITE)
		pct.Position = UDim2.fromOffset(x + 194, 0)
		pct.Size = UDim2.fromOffset(42, 19)
		pct.TextXAlignment = Enum.TextXAlignment.Left

		local function applyRow(v: number)
			fill.Size = UDim2.fromScale(v, 1)
			pct.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
		end
		applyRow(AudioMix.gain(ch))
		AudioMix.onChange(ch, applyRow)

		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Text = ""
		hit.Position = UDim2.fromOffset(x + 62, 0)
		hit.Size = UDim2.new(0, 132, 1, 0)
		hit.Parent = parent

		local dragging = false
		local function write(mx: number)
			AudioMix.set(ch, math.clamp((mx - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
		end
		hit.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				write(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				write(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				dragging = false
				AudioMix.save(ch)
			end
		end)
	end
	for i = 1, 3 do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Visible = false
		row.Size = UDim2.new(1, 0, 0, 19)
		row.LayoutOrder = 17 + i
		row.Parent = menuCol
		table.insert(mixerRows, row)
		sliderUnit(row, Config.Audio.Channels[i * 2 - 1], 20)
		if Config.Audio.Channels[i * 2] then
			sliderUnit(row, Config.Audio.Channels[i * 2], 270)
		end
	end

	play.MouseButton1Click:Connect(function()
		if self.onPlay then
			self.onPlay(seedBox.Text)
		end
	end)

	-- Leaderboard: right-side panel, filled via GetLeaderboard remote. Row
	-- count tracks Config.Leaderboard.TopCount so the fetch and the panel
	-- never disagree. Two boards (§14): ALL-TIME top runs and DAILY — every
	-- run on today's shared seed races the same map.
	local TOP_N = Config.Leaderboard.TopCount
	-- The recent-runs strip (§14) pins to the board's bottom — it shares
	-- the seed column, so a click there prefills the seed box for a rerun.
	local RECENT_H = 16 + Config.Leaderboard.HistoryShown * 17 + 6
	local board = Instance.new("Frame")
	board.Name = "Leaderboard"
	board.AnchorPoint = Vector2.new(1, 0.5)
	board.Position = UDim2.fromScale(0.96, 0.5)
	board.Size = UDim2.fromOffset(320, 78 + TOP_N * 25 + RECENT_H)
	board.BackgroundColor3 = C_PANEL
	board.BackgroundTransparency = 0.25
	board.BorderSizePixel = 0
	board.Parent = menu
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 10)
	boardCorner.Parent = board

	self.boardMode = "top" :: string
	self.onBoardTab = nil :: ((board: string) -> ())?
	local function boardTab(text, x)
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DISPLAY
		b.TextSize = 15
		b.Text = text
		b.Position = UDim2.fromOffset(x, 10)
		b.Size = UDim2.fromOffset(96, 26)
		b.Parent = board
		return b
	end
	self.tabTop = boardTab("TOP", 14)
	self.tabTop.Name = "TabTop"
	self.tabDaily = boardTab("DAILY", 114)
	self.tabDaily.Name = "TabDaily"
	self.tabWeekly = boardTab("WEEKLY", 214)
	self.tabWeekly.Name = "TabWeekly"
	self.tabTop.MouseButton1Click:Connect(function()
		self:setBoard("top")
	end)
	self.tabDaily.MouseButton1Click:Connect(function()
		self:setBoard("daily")
	end)
	self.tabWeekly.MouseButton1Click:Connect(function()
		self:setBoard("weekly")
	end)

	-- Daily status line: today's shared seed + reset countdown (UTC).
	self.dailyInfo = Instance.new("TextLabel")
	self.dailyInfo.BackgroundTransparency = 1
	self.dailyInfo.Font = F_DATA
	self.dailyInfo.TextSize = 12
	self.dailyInfo.TextColor3 = C_GOLD
	self.dailyInfo.TextXAlignment = Enum.TextXAlignment.Left
	self.dailyInfo.Position = UDim2.fromOffset(14, 38)
	self.dailyInfo.Size = UDim2.new(1, -28, 0, 18)
	self.dailyInfo.Visible = false
	self.dailyInfo.Parent = board

	-- Friends filter (§14): rides every board — the fetched top-N rows
	-- shrink to your friends, keeping their REAL rank numbers. The id set
	-- arrives via onFriendsReady (Main lazy-loads GetFriendsAsync).
	self.friendsOnly = false
	self.friendSet = nil :: { [number]: boolean }?
	self.friendsErr = false -- set when the friends list itself failed
	self.onFriendsReady = nil :: (() -> ())?
	local friendsBtn = Instance.new("TextButton")
	friendsBtn.Name = "FriendsBtn"
	friendsBtn.BackgroundTransparency = 1
	friendsBtn.AutoButtonColor = false
	friendsBtn.Font = F_DATA
	friendsBtn.TextSize = 12
	friendsBtn.Text = "◈ friends"
	friendsBtn.TextColor3 = C_DIM
	friendsBtn.TextXAlignment = Enum.TextXAlignment.Right
	friendsBtn.AnchorPoint = Vector2.new(1, 0)
	friendsBtn.Position = UDim2.new(1, -14, 0, 38)
	friendsBtn.Size = UDim2.fromOffset(96, 18)
	friendsBtn.Parent = board
	self.friendsBtn = friendsBtn
	friendsBtn.MouseButton1Click:Connect(function()
		self.friendsOnly = not self.friendsOnly
		friendsBtn.TextColor3 = if self.friendsOnly then C_PINK else C_DIM
		if self.friendsOnly and self.friendSet == nil and self.onFriendsReady then
			self.onFriendsReady() -- async fill; redraws when it lands
		else
			self:drawBoard()
		end
	end)
	-- Slow ticker keeps the countdown honest while the menu sits open —
	-- 15s granularity, gated on Visible so it costs nothing during runs.
	task.spawn(function()
		while true do
			task.wait(15)
			if self.dailyInfo.Visible then
				self.dailyInfo.Text = if self.boardMode == "weekly" then weeklyText() else dailyText()
			end
		end
	end)

	local boardBody = Instance.new("Frame")
	boardBody.BackgroundTransparency = 1
	boardBody.Size = UDim2.new(1, -24, 1, -72 - RECENT_H)
	boardBody.Position = UDim2.fromOffset(12, 62)
	boardBody.Parent = board
	vlist(boardBody, 4)
	self.boardRows = {}
	for i = 1, TOP_N do
		local row = label(boardBody, "", 14, F_DATA, i % 2 == 0 and C_CYAN or C_WHITE, i)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		self.boardRows[i] = row
	end
	self.boardRows[1].Text = "  loading…" -- first refreshBoard() lands shortly after boot

	-- Recent runs (§14): newest-first { s=score, d=dist, z=seed } rows.
	-- Clicking one hands its seed to onHistoryPick (Main fills the seed
	-- box — one tap from PLAY reproduces that exact map).
	self.onHistoryPick = nil :: ((seed: number) -> ())?
	self.historyRows = {} :: { { s: number, d: number, z: number } }
	local recent = Instance.new("Frame")
	recent.Name = "Recent"
	recent.BackgroundTransparency = 1
	recent.AnchorPoint = Vector2.new(0, 1)
	recent.Position = UDim2.new(0, 12, 1, -8)
	recent.Size = UDim2.new(1, -24, 0, RECENT_H)
	recent.Visible = false
	recent.Parent = board
	vlist(recent, 2)
	local recentHead = label(recent, "RECENT  ·  tap to rerun", 11, F_DATA, C_DIM, 1)
	recentHead.TextXAlignment = Enum.TextXAlignment.Left
	self.recentBtns = {}
	for i = 1, Config.Leaderboard.HistoryShown do
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 12
		b.TextColor3 = C_WHITE
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Text = ""
		b.Size = UDim2.new(1, 0, 0, 15)
		b.LayoutOrder = i + 1
		b.Visible = false
		b.Parent = recent
		b.MouseButton1Click:Connect(function()
			local r = self.historyRows[i]
			if r and self.onHistoryPick then
				self.onHistoryPick(r.z)
			end
		end)
		self.recentBtns[i] = b
	end
	self.recent = recent

	--============================ GARAGE ============================--
	-- Neon shop (DESIGN.md §18): left rail, tabbed — STYLE (equip cyclers),
	-- PACKS (bundle gamepasses), BANK (gem packs + 2X pass). One page is
	-- visible at a time: the full shop is 30+ controls, and showing them
	-- all at once drowned PLAY (progressive disclosure).
	local garage = Instance.new("Frame")
	garage.Name = "Garage"
	garage.AnchorPoint = Vector2.new(0, 0.5)
	garage.Position = UDim2.fromScale(0.04, 0.5)
	garage.Size = UDim2.fromOffset(330, 430)
	garage.BackgroundColor3 = C_PANEL
	garage.BackgroundTransparency = 0.25
	garage.BorderSizePixel = 0
	garage.Parent = menu
	local gcorner = Instance.new("UICorner")
	gcorner.CornerRadius = UDim.new(0, 10)
	gcorner.Parent = garage

	label(garage, "GARAGE", 20, F_DISPLAY, C_PINK, 0).Position = UDim2.fromOffset(0, 8)

	local gTabs: { [string]: TextButton } = {}
	local gPages: { [string]: Frame } = {}
	for i, name in ipairs({ "STYLE", "PACKS", "BANK" }) do
		local b = Instance.new("TextButton")
		b.Name = "Tab" .. name
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DISPLAY
		b.TextSize = 13
		b.Text = name
		b.Position = UDim2.fromOffset(14 + (i - 1) * 104, 40)
		b.Size = UDim2.fromOffset(96, 24)
		b.Parent = garage
		gTabs[name] = b

		local pg = Instance.new("Frame")
		pg.BackgroundTransparency = 1
		pg.Position = UDim2.fromOffset(0, 72)
		pg.Size = UDim2.new(1, 0, 1, -72)
		pg.Visible = i == 1
		pg.Parent = garage
		gPages[name] = pg
	end
	local function setGarageTab(name: string)
		for n, b in pairs(gTabs) do
			b.TextColor3 = if n == name then C_PINK else C_DIM
		end
		for n, pg in pairs(gPages) do
			pg.Visible = n == name
		end
	end
	for name, b in pairs(gTabs) do
		b.MouseButton1Click:Connect(function()
			setGarageTab(name)
		end)
	end
	setGarageTab("STYLE")

	-- Slot rows: "SKIN   < ITEM NAME >". Cycling browses the full catalog;
	-- the name itself is the buy button for priced-but-unowned items.
	self.slotItem = {}
	local pageStyle = gPages.STYLE
	for i, slot in ipairs(Cosmetics.Slots) do
		local y = 6 + (i - 1) * 30
		local sl = Instance.new("TextLabel")
		sl.BackgroundTransparency = 1
		sl.Font = F_DATA
		sl.TextSize = 12
		sl.TextColor3 = C_DIM
		sl.TextXAlignment = Enum.TextXAlignment.Left
		sl.Text = Cosmetics.SlotName[slot]
		sl.Position = UDim2.fromOffset(14, y)
		sl.Size = UDim2.fromOffset(56, 28)
		sl.Parent = pageStyle

		local nm = Instance.new("TextButton")
		nm.BackgroundTransparency = 1
		nm.AutoButtonColor = false
		nm.Font = F_DATA
		nm.TextSize = 15
		nm.TextColor3 = C_WHITE
		nm.Text = "—"
		nm.Position = UDim2.fromOffset(102, y)
		nm.Size = UDim2.fromOffset(182, 28)
		nm.Parent = pageStyle
		self.slotItem[slot] = nm
		nm.MouseButton1Click:Connect(function()
			if self.onItemSlot then
				self.onItemSlot(slot)
			end
		end)

		local left = arrowButton(pageStyle, "<", 72, y)
		left.MouseButton1Click:Connect(function()
			if self.onEquipCycle then
				self.onEquipCycle(slot, -1)
			end
		end)
		local right = arrowButton(pageStyle, ">", 288, y)
		right.MouseButton1Click:Connect(function()
			if self.onEquipCycle then
				self.onEquipCycle(slot, 1)
			end
		end)
	end

	local browseHint = label(pageStyle, "cycle equips owned · click a ◊ price to buy", 10, F_DATA, C_DIM, 0)
	browseHint.Position = UDim2.fromOffset(0, 6 + #Cosmetics.Slots * 30 + 6)
	browseHint.TextTransparency = 0.35

	-- Pack rows: name + contents left, price button right. Button state
	-- comes from setGarage: "R$49" enabled / "OWNED" / "SOON" dimmed.
	self.packBtn = {}
	self.packStroke = {}
	self.packEnabled = {}
	local function packRow(parent: Frame, id: string, name: string, desc: string, y: number)
		local nl = Instance.new("TextLabel")
		nl.BackgroundTransparency = 1
		nl.Font = F_DATA
		nl.TextSize = 14
		nl.TextColor3 = C_WHITE
		nl.TextXAlignment = Enum.TextXAlignment.Left
		nl.Text = name
		nl.Position = UDim2.fromOffset(14, y)
		nl.Size = UDim2.fromOffset(210, 18)
		nl.Parent = parent

		local dl = Instance.new("TextLabel")
		dl.BackgroundTransparency = 1
		dl.Font = F_DATA
		dl.TextSize = 10
		dl.TextColor3 = C_DIM
		dl.TextXAlignment = Enum.TextXAlignment.Left
		dl.TextTruncate = Enum.TextTruncate.AtEnd
		dl.Text = desc
		dl.Position = UDim2.fromOffset(14, y + 17)
		dl.Size = UDim2.fromOffset(210, 14)
		dl.Parent = parent

		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = C_BG
		btn.BackgroundTransparency = 0
		btn.AutoButtonColor = false
		btn.Font = F_DATA
		btn.TextSize = 14
		btn.TextColor3 = C_PINK
		btn.Text = "R$?"
		btn.Position = UDim2.fromOffset(232, y + 2)
		btn.Size = UDim2.fromOffset(84, 32)
		btn.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = C_PINK
		stroke.Thickness = 1.5
		stroke.Parent = btn
		self.packBtn[id] = btn
		self.packStroke[id] = stroke
		-- Neon-chip affordance: enabled buttons flare cyan on hover, then
		-- fall back to their state color (setGarage re-pushes it anyway).
		btn.MouseEnter:Connect(function()
			if self.packEnabled[id] then
				btn.TextColor3 = C_CYAN
				stroke.Color = C_CYAN
			end
		end)
		btn.MouseLeave:Connect(function()
			btn.TextColor3 = self.packEnabled[id] and C_PINK or C_DIM
			stroke.Color = btn.TextColor3
		end)
		btn.MouseButton1Click:Connect(function()
			if self.packEnabled[id] and self.onBuy then
				self.onBuy(id)
			end
		end)
	end
	-- Seasonal slot (§18): its desc advertises the yearly window, derived
	-- from Config.Monetization.Seasonal so the text never lies about dates.
	local MONTH_ABBR = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
	local function seasonalDesc(desc: string): string
		local S = Config.Monetization.Seasonal
		local function md(t: { number }): string
			return MONTH_ABBR[t[1]] .. " " .. t[2]
		end
		return string.format("%s · %s–%s", desc, md(S.Start), md(S.End))
	end
	for i, b in ipairs(Cosmetics.Bundles) do
		local desc = if b.id == Config.Monetization.Seasonal.Bundle then seasonalDesc(b.desc) else b.desc
		packRow(gPages.PACKS, b.id, b.name, desc, 6 + (i - 1) * 34)
	end

	--=========== BANK (§18 P2) ===========--
	-- Gem economy page: balance line, three gem-pack dev products, and the
	-- 2X BANK pass row. Everything degrades to SOON until the ids are
	-- created on the dashboard — the buttons only arm via setGarage.
	local pageBank = gPages.BANK
	label(pageBank, "BANK", 14, F_DISPLAY, C_DIM, 0).Position = UDim2.fromOffset(0, 6)
	local bal = Instance.new("TextLabel")
	bal.BackgroundTransparency = 1
	bal.Font = F_DATA
	bal.TextSize = 16
	bal.TextColor3 = C_GOLD
	bal.TextXAlignment = Enum.TextXAlignment.Right
	bal.Text = "◊ 0"
	bal.Position = UDim2.fromOffset(150, 4)
	bal.Size = UDim2.fromOffset(166, 20)
	bal.Parent = pageBank
	self.bankLabel = bal

	-- Gem packs: three equal buttons "◊300\nR$49". Enabled state arrives via
	-- setGarage's gemPacks list (SOON until product ids exist).
	self.gemPackBtn = {}
	self.gemPackStroke = {}
	self.gemPackEnabled = {}
	for i, key in ipairs(Config.Monetization.ProductOrder) do
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C_BG
		b.BackgroundTransparency = 0
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 13
		b.TextColor3 = C_GOLD
		b.Text = "◊?\nSOON"
		b.Position = UDim2.fromOffset(14 + (i - 1) * 103, 32)
		b.Size = UDim2.fromOffset(96, 44)
		b.Parent = pageBank
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = C_GOLD
		stroke.Thickness = 1.5
		stroke.Parent = b
		self.gemPackBtn[key] = b
		self.gemPackStroke[key] = stroke
		b.MouseEnter:Connect(function()
			if self.gemPackEnabled[key] then
				b.TextColor3 = C_CYAN
				stroke.Color = C_CYAN
			end
		end)
		b.MouseLeave:Connect(function()
			b.TextColor3 = self.gemPackEnabled[key] and C_GOLD or C_DIM
			stroke.Color = b.TextColor3
		end)
		b.MouseButton1Click:Connect(function()
			if self.gemPackEnabled[key] and self.onGemPack then
				self.onGemPack(key)
			end
		end)
	end

	-- 2X BANK rides the pack-row machinery: Passes.bank2x is a gamepass like
	-- the bundles, so packBtn["bank2x"] + onBuy("bank2x") just works.
	packRow(pageBank, "bank2x", "2X BANK", "every gem banks double", 90)

	local hint = label(pageBank, "gems bank on pickup — they're never score", 11, F_DATA, C_DIM, 0)
	hint.Position = UDim2.fromOffset(0, 136)
	hint.TextTransparency = 0.3

	--============================= HUD ==============================--
	-- Top-right cluster (§12): the score leaves the center cone clear for
	-- the track read at speed. Right side, not left — Roblox's native
	-- chrome (menu/chat/audio icons) overlays the top-left corner.
	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.AnchorPoint = Vector2.new(1, 0)
	hud.Position = UDim2.new(1, -18, 0, 12)
	hud.Size = UDim2.fromOffset(360, 152)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.Parent = gui
	self.hud = hud

	local scoreText = Instance.new("TextLabel")
	scoreText.BackgroundTransparency = 1
	scoreText.Font = F_DATA
	scoreText.TextSize = 52
	scoreText.TextColor3 = C_PINK
	scoreText.TextXAlignment = Enum.TextXAlignment.Right
	scoreText.Size = UDim2.new(1, 0, 0, 58)
	scoreText.Parent = hud
	self.scoreText = scoreText

	local subText = Instance.new("TextLabel")
	subText.BackgroundTransparency = 1
	subText.Font = F_DATA
	subText.TextSize = 15
	subText.TextColor3 = C_DIM
	subText.TextXAlignment = Enum.TextXAlignment.Right
	subText.Position = UDim2.fromOffset(0, 60)
	subText.Size = UDim2.new(1, 0, 0, 20)
	subText.Parent = hud
	self.subText = subText

	-- Gem combo counter under the subline: "x3" while a pickup streak is
	-- alive (client derives it from RoBallGems timing, ComboWindow).
	local comboText = Instance.new("TextLabel")
	comboText.BackgroundTransparency = 1
	comboText.Font = F_DATA
	comboText.TextSize = 16
	comboText.TextColor3 = C_CYAN
	comboText.TextStrokeTransparency = 0.5
	comboText.TextXAlignment = Enum.TextXAlignment.Right
	comboText.Position = UDim2.fromOffset(0, 80)
	comboText.Size = UDim2.new(1, 0, 0, 18)
	comboText.Text = ""
	comboText.Visible = false
	comboText.Parent = hud
	self.comboText = comboText

	-- Pass-moment gold (§11): the record earns its flash when you cross
	-- the PB gate — flashBest() fires it, it never idles on screen.
	local bestFlash = Instance.new("TextLabel")
	bestFlash.BackgroundTransparency = 1
	bestFlash.Font = F_DATA
	bestFlash.TextSize = 16
	bestFlash.TextColor3 = C_GOLD
	bestFlash.TextStrokeTransparency = 0.5
	bestFlash.TextXAlignment = Enum.TextXAlignment.Right
	bestFlash.Position = UDim2.fromOffset(0, 98)
	bestFlash.Size = UDim2.new(1, 0, 0, 18)
	bestFlash.Text = "★ NEW BEST"
	bestFlash.Visible = false
	bestFlash.Parent = hud
	self.bestFlash = bestFlash

	-- Near-miss ping (§10): a quick cyan "CLOSE +N" under the score when
	-- a lethal-plane crossing grazes the face — the trickle made visible.
	local missFlash = Instance.new("TextLabel")
	missFlash.BackgroundTransparency = 1
	missFlash.Font = F_DATA
	missFlash.TextSize = 14
	missFlash.TextColor3 = C_CYAN
	missFlash.TextStrokeTransparency = 0.5
	missFlash.TextXAlignment = Enum.TextXAlignment.Right
	missFlash.Position = UDim2.fromOffset(0, 116)
	missFlash.Size = UDim2.new(1, 0, 0, 18)
	missFlash.Text = ""
	missFlash.Visible = false
	missFlash.Parent = hud
	self.missFlash = missFlash

	-- Pace delta (§12): while the PB echo replays (same-seed runs), a
	-- persistent "+N vs PB" / "-N vs PB" line — cyan ahead, pink behind.
	local paceText = Instance.new("TextLabel")
	paceText.Name = "PaceText"
	paceText.BackgroundTransparency = 1
	paceText.Font = F_DATA
	paceText.TextSize = 14
	paceText.TextColor3 = C_CYAN
	paceText.TextStrokeTransparency = 0.5
	paceText.TextXAlignment = Enum.TextXAlignment.Right
	paceText.Position = UDim2.fromOffset(0, 134)
	paceText.Size = UDim2.new(1, 0, 0, 16)
	paceText.Text = ""
	paceText.Visible = false
	paceText.Parent = hud
	self.paceText = paceText

	-- Rival pace (§14): while the champion echo replays, a gold
	-- "+N vs <name>" line under the PB one — the gap to the record.
	local rivalText = Instance.new("TextLabel")
	rivalText.Name = "RivalText"
	rivalText.BackgroundTransparency = 1
	rivalText.Font = F_DATA
	rivalText.TextSize = 14
	rivalText.TextColor3 = Config.Ghost.RivalColor
	rivalText.TextStrokeTransparency = 0.5
	rivalText.TextXAlignment = Enum.TextXAlignment.Right
	rivalText.Position = UDim2.fromOffset(0, 150)
	rivalText.Size = UDim2.new(1, 0, 0, 16)
	rivalText.Text = ""
	rivalText.Visible = false
	rivalText.Parent = hud
	self.rivalText = rivalText

	-- Sector splits (§14): on each Config.Sectors.Length boundary a
	-- left-aligned line flashes "SEC n · t" plus a colored delta per
	-- live replay — positive reads ahead of that ghost.
	local sectorFlash = Instance.new("TextLabel")
	sectorFlash.Name = "SectorFlash"
	sectorFlash.BackgroundTransparency = 1
	sectorFlash.Font = F_DATA
	sectorFlash.TextSize = 14
	sectorFlash.TextColor3 = C_CYAN
	sectorFlash.TextStrokeTransparency = 0.5
	sectorFlash.TextXAlignment = Enum.TextXAlignment.Left
	sectorFlash.RichText = true
	sectorFlash.Position = UDim2.fromOffset(0, 170)
	sectorFlash.Size = UDim2.new(1, -Config.Radar.Width - 6, 0, 16)
	sectorFlash.Text = ""
	sectorFlash.Visible = false
	sectorFlash.Parent = hud
	self.sectorFlash = sectorFlash

	-- Look-ahead radar (§12): a vertical strip under the stack — top is
	-- Radar.Range studs out, bottom is the ball; bars are lethal blocks
	-- in ball-relative studs with the cyan line as "you". Pooled bars —
	-- setRadar repositions, never allocates.
	local R = Config.Radar
	local radar = Instance.new("Frame")
	radar.Name = "Radar"
	radar.AnchorPoint = Vector2.new(1, 0)
	radar.Position = UDim2.new(1, 0, 0, 174)
	radar.Size = UDim2.fromOffset(R.Width, R.Height)
	radar.BackgroundColor3 = C_PANEL
	radar.BackgroundTransparency = 0.45
	radar.BorderSizePixel = 0
	radar.ClipsDescendants = true
	radar.Parent = hud
	local radarCorner = Instance.new("UICorner")
	radarCorner.CornerRadius = UDim.new(0, 6)
	radarCorner.Parent = radar
	local radarLine = Instance.new("Frame")
	radarLine.BackgroundColor3 = C_CYAN
	radarLine.BackgroundTransparency = 0.55
	radarLine.BorderSizePixel = 0
	radarLine.AnchorPoint = Vector2.new(0.5, 0)
	radarLine.Position = UDim2.new(0.5, 0, 0, 3)
	radarLine.Size = UDim2.new(0, 1, 1, -6)
	radarLine.Parent = radar
	self.radarBars = {}
	for i = 1, R.MaxBars do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Config.LethalColor
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(4, R.BarH)
		bar.Visible = false
		bar.Parent = radar
		self.radarBars[i] = bar
	end
	self.radar = radar

	-- Achievement toast (§14): top-center gold ribbon on unlock —
	-- toast() writes the line, it never idles.
	local achToast = Instance.new("TextLabel")
	achToast.BackgroundTransparency = 1
	achToast.Font = F_DATA
	achToast.TextSize = 18
	achToast.TextColor3 = C_GOLD
	achToast.TextStrokeTransparency = 0.5
	achToast.AnchorPoint = Vector2.new(0.5, 0)
	achToast.Position = UDim2.new(0.5, 0, 0, 90)
	achToast.Size = UDim2.fromOffset(560, 24)
	achToast.Visible = false
	achToast.Parent = gui
	self.achToast = achToast

	--=========== SPEED + POWER METER (bottom corners) ===========--
	-- Vaporwave BPM readout (DESIGN.md §12): the digit is the heard tempo
	-- (track bpm x snapped PlaybackSpeed — it steps in semitones with the
	-- music), chromed like retro lettering and slanted outrun-style. Twin
	-- cyan/pink ghosts ride it: VHS chromatic aberration that spreads and
	-- flares with the audio pulse, so the digit thumps on the beat. Hue
	-- still keys off ball speed (cyan -> magenta -> hot red past 100 s/s).
	local spdNum = Instance.new("TextLabel")
	spdNum.Name = "SpeedNum"
	spdNum.AnchorPoint = Vector2.new(1, 1)
	spdNum.Position = UDim2.new(0.82, 0, 1, -18)
	spdNum.Size = UDim2.fromOffset(180, 62)
	spdNum.Rotation = -6
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
	-- Chrome band: bright crown -> dark horizon line -> pale reflection.
	-- The speed-hue TextColor3 multiplies through it, so the band reads as
	-- shade of the current hue, never a second color.
	local numGrad = Instance.new("UIGradient")
	numGrad.Rotation = 90
	numGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(255, 240, 255)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(70, 45, 115)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(235, 205, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 110, 200)),
	})
	numGrad.Parent = spdNum
	-- Neon rim: a contextual outline that wears the same speed hue —
	-- reads as glow around the glyph edges, not a second color.
	local numStroke = Instance.new("UIStroke")
	numStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	numStroke.Color = C_CYAN
	numStroke.Transparency = 0.72
	numStroke.Thickness = 1.5
	numStroke.Parent = spdNum
	self.spdStroke = numStroke
	-- Aberration ghosts: children of the digit so slant, position and
	-- visibility track it for free; only Text/TextSize/offset sync per
	-- frame. Fixed cyan/pink — the fringe stays chromatic at any hue.
	local function ghost(dx: number, color: Color3): TextLabel
		local g = Instance.new("TextLabel")
		g.BackgroundTransparency = 1
		g.Font = spdNum.Font
		g.TextSize = spdNum.TextSize
		g.TextColor3 = color
		g.TextTransparency = 0.82
		g.TextXAlignment = spdNum.TextXAlignment
		g.Position = UDim2.fromOffset(dx, 0)
		g.Size = UDim2.fromScale(1, 1)
		g.Text = spdNum.Text
		g.Parent = spdNum
		return g
	end
	local spdGhostA = ghost(-2, C_CYAN)
	local spdGhostB = ghost(2, C_PINK)
	self.spdGhostA = spdGhostA
	self.spdGhostB = spdGhostB

	local spdUnit = Instance.new("TextLabel")
	spdUnit.AnchorPoint = Vector2.new(1, 1)
	spdUnit.Position = UDim2.new(0.82, 0, 1, -8)
	spdUnit.Size = UDim2.fromOffset(180, 14)
	spdUnit.Rotation = -6
	spdUnit.BackgroundTransparency = 1
	spdUnit.Font = F_DATA
	spdUnit.TextSize = 12
	spdUnit.TextColor3 = C_DIM
	spdUnit.TextXAlignment = Enum.TextXAlignment.Right
	spdUnit.Text = "BPM"
	spdUnit.Visible = false
	spdUnit.Parent = gui
	self.spdUnit = spdUnit
	local unitGrad = Instance.new("UIGradient")
	unitGrad.Color = ColorSequence.new(C_DIM, C_PINK:Lerp(C_DIM, 0.35))
	unitGrad.Parent = spdUnit

	-- Power meter: a vaporwave nitro strip — a tilted pill of LED segments
	-- ramping cyan->magenta like a tape-deck VU meter. A diamond bead
	-- rides the lit edge; the boundary cell glows partial so charge reads
	-- analog-smooth between cells. RechargeGate is a gold notch slotted
	-- between cells, its lock zone tinted warm; the strip still flares
	-- (pink boost, orange brake, gold ready-ping).
	local bWrap = Instance.new("Frame")
	bWrap.Name = "PowerMeter"
	bWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	bWrap.Position = UDim2.new(0.18, METER_W / 2, 1, -38)
	bWrap.Size = UDim2.fromOffset(METER_W, 18)
	bWrap.Rotation = -4
	bWrap.BackgroundColor3 = C_BG
	bWrap.BackgroundTransparency = 0.25
	bWrap.BorderSizePixel = 0
	bWrap.Visible = false
	bWrap.Parent = gui
	self.powerBar = bWrap
	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(1, 0)
	bCorner.Parent = bWrap
	local bStroke = Instance.new("UIStroke")
	bStroke.Color = C_CYAN
	bStroke.Thickness = 1.5
	bStroke.Transparency = 0.35
	bStroke.Parent = bWrap
	-- Segment strip inside the capsule; unlit cells stay visible as dark
	-- LED slots so the meter has structure even when empty. Cells below
	-- RechargeGate read as a faint warm "lock zone" — after a burnout the
	-- meter must refill past them before W fires again.
	local bInner = Instance.new("Frame")
	bInner.BackgroundTransparency = 1
	bInner.Position = UDim2.fromOffset(METER_PAD, 4)
	bInner.Size = UDim2.new(1, -METER_PAD * 2, 1, -8)
	bInner.Parent = bWrap
	local innerW = METER_W - METER_PAD * 2
	local gap = 3
	local cellW = (innerW - gap * (METER_SEGS - 1)) / METER_SEGS
	local gateCells = math.floor(Config.Power.RechargeGate * METER_SEGS + 1e-4)
	self._gateCells = gateCells
	self.powerSegs = {}
	for i = 1, METER_SEGS do
		local s = Instance.new("Frame")
		s.Position = UDim2.fromOffset((i - 1) * (cellW + gap), 0)
		s.Size = UDim2.new(0, cellW, 1, 0)
		s.BackgroundColor3 = i <= gateCells and C_GATE_DIM or C_PANEL
		s.BackgroundTransparency = 0.4
		s.BorderSizePixel = 0
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 3)
		sc.Parent = s
		s.Parent = bInner
		self.powerSegs[i] = s
	end
	-- The recharge gate is a notch IN the strip, not a floating tick: a
	-- slim gold divider slotted into the gap right after the lock zone.
	local bGate = Instance.new("Frame")
	bGate.AnchorPoint = Vector2.new(0, 0.5)
	bGate.Position = UDim2.new(0, gateCells * cellW + (gateCells - 1) * gap + 0.5, 0.5, 0)
	bGate.Size = UDim2.fromOffset(2, 8)
	bGate.BackgroundColor3 = C_GOLD
	bGate.BackgroundTransparency = 0.25
	bGate.BorderSizePixel = 0
	bGate.Parent = bInner
	self.powerGate = bGate
	-- Diamond bead riding the lit edge — in wrap space so its x tracks
	-- the smoothed fill fraction every frame.
	local bTip = Instance.new("Frame")
	bTip.AnchorPoint = Vector2.new(0.5, 0.5)
	bTip.Position = UDim2.new(0, METER_PAD, 0.5, 0)
	bTip.Size = UDim2.fromOffset(12, 12)
	bTip.Rotation = 45
	bTip.BackgroundColor3 = C_CYAN
	bTip.BorderSizePixel = 0
	bTip.Visible = false
	bTip.Parent = bWrap
	self.powerTip = bTip
	local bLab = Instance.new("TextLabel")
	bLab.AnchorPoint = Vector2.new(0, 1)
	bLab.Position = UDim2.fromOffset(0, -3)
	bLab.Size = UDim2.fromOffset(METER_W, 13)
	bLab.BackgroundTransparency = 1
	bLab.Font = F_DATA
	bLab.TextSize = 11
	bLab.TextColor3 = C_DIM
	bLab.TextXAlignment = Enum.TextXAlignment.Left
	bLab.Text = "POWER METER"
	bLab.Parent = bWrap

	-- Seed tag pinned to the true bottom-right corner — replantable info,
	-- kept dim and tiny so it never competes with the speed number.
	local seedTag = Instance.new("TextLabel")
	seedTag.Name = "SeedTag"
	seedTag.AnchorPoint = Vector2.new(1, 1)
	seedTag.Position = UDim2.new(1, -8, 1, -6)
	seedTag.Size = UDim2.fromOffset(220, 14)
	seedTag.BackgroundTransparency = 1
	seedTag.Font = F_DATA
	seedTag.TextSize = 12
	seedTag.TextColor3 = C_DIM
	seedTag.TextXAlignment = Enum.TextXAlignment.Right
	seedTag.Text = ""
	seedTag.Visible = false
	seedTag.Parent = gui
	self.seedTag = seedTag

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
	dCol.Size = UDim2.fromOffset(460, 340)
	dCol.Position = UDim2.fromScale(0.5, 0.42)
	dCol.AnchorPoint = Vector2.new(0.5, 0.5)
	dCol.Parent = death
	vlist(dCol, 12)

	label(dCol, spaced("RUN OVER"), 48, F_HERO, C_PINK, 1)
	-- NEW BEST! only shows when the run beat the stored record — gold,
	-- placed right under the title so it's the first thing read.
	self.dNewBest = label(dCol, "★ NEW BEST!", 20, F_DATA, C_GOLD, 2)
	self.dNewBest.Visible = false
	-- The bare number is the hero — no "SCORE" prefix needed.
	self.dScore = label(dCol, "0", 40, F_DATA, C_CYAN, 3)
	-- One quiet stats line: distance + gem pts + the ◊+N banked payout
	-- (§18 P2) folded in via RichText so the screen stays minimal.
	self.dBreakdown = label(dCol, "", 16, F_DATA, C_DIM, 4)
	self.dBreakdown.RichText = true
	self.dBest = label(dCol, "", 14, F_DATA, C_DIM, 5)
	-- Daily-streak payoff line (§14): only when a daily-seeded run counted
	-- the day — "day-3 streak · ◊+30 banked", gold like NEW BEST.
	self.dStreak = label(dCol, "", 15, F_DATA, C_GOLD, 6)
	self.dStreak.Visible = false
	-- Daily quests completed this run (§14): "2 quests done · ◊ +90 banked".
	self.dQuest = label(dCol, "", 15, F_DATA, C_GOLD, 7)
	self.dQuest.Visible = false
	-- Weekly cup payout (§14): run bonus + any lazy podium pay —
	-- "weekly cup · ◊ +225 banked", same gold accent.
	self.dWeekly = label(dCol, "", 15, F_DATA, C_GOLD, 8)
	self.dWeekly.Visible = false
	-- Run-stats card (§11): one quiet dim line — top speed, gates passed,
	-- boost share, closest call. Display-only; never score.
	self.dStats = label(dCol, "", 13, F_DATA, C_DIM, 9)
	self.dStats.Visible = false
	local retry = outlineButton(dCol, "RETRY", 30, 10)
	retry.Size = UDim2.fromOffset(300, 56)
	retry.MouseButton1Click:Connect(function()
		if self.onRetry then
			self.onRetry()
		end
	end)
	label(dCol, "R retry · T rerun", 13, F_DATA, C_DIM, 11).TextTransparency = 0.25
	-- Same-seed rerun (§10): the deterministic rematch — identical map,
	-- your ghost included. Label carries the seed so the intent is plain.
	self.dRerun = ghostButton(dCol, "rerun", 15, 12)
	self.dRerun.MouseButton1Click:Connect(function()
		if self.onRerun then
			self.onRerun()
		end
	end)
	-- Back to the menu = garage access (§18): the shop lives on the menu.
	local toMenu = ghostButton(dCol, "menu", 15, 13)
	toMenu.MouseButton1Click:Connect(function()
		if self.onMenu then
			self.onMenu()
		end
	end)

	return self
end

function Ui:showMenu(best: number)
	self.menu.Visible = true
	self.death.Visible = false
	self.hud.Visible = false
	self.spdNum.Visible = false
	self.spdUnit.Visible = false
	self.powerBar.Visible = false
	self.seedTag.Visible = false
	self:setBest(best)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.bestFlash.Visible = false -- reset for the new run's own crossing
	self.hud.Visible = true
	self.spdNum.Visible = true
	self.spdUnit.Visible = true
	self.powerBar.Visible = true
	self.seedTag.Visible = true
end

function Ui:setHud(score: number, dist: number, gems: number, _speed: number, seed: number)
	self.scoreText.Text = tostring(score)
	-- Speed lives on the dial now; the subline stays quiet.
	self.subText.Text = string.format("%d m  ·  gems +%d", dist, gems)
	self.seedTag.Text = string.format("seed %d", seed)
end

-- Audio pulse from Music.sample() (0..1) — the digit thumps on the beat:
-- slight swell, brighter face, and the chromatic ghosts spread wider.
function Ui:setPulse(v: number)
	self.pulse = v
end

-- BPM number + power meter, called every heartbeat during a run. `bpm` is
-- the heard tempo (Music.bpm()); the digit's hue still keys off s/s:
-- cyan 0 -> magenta 100 -> hot red pegged past it. The meter bar pulses
-- pink while W is held and blinks while the meter is latched out below
-- RechargeGate.
function Ui:setSpeedo(
	speed: number,
	bpm: number,
	powerFrac: number,
	boosting: boolean,
	powerSpent: boolean,
	braking: boolean?,
	dashing: boolean?,
	dashDeniedAt: number?
)
	local num = tostring(math.floor(bpm + 0.5))
	self.spdNum.Text = num
	self.spdGhostA.Text = num
	self.spdGhostB.Text = num
	local pulse = self.pulse or 0
	local size = 56 + pulse * 5 -- beat thump: swell on the heard grid
	self.spdNum.TextSize = size
	self.spdGhostA.TextSize = size
	self.spdGhostB.TextSize = size
	local spread = 2 + pulse * 4 -- VHS fringe widens with the kick
	self.spdGhostA.Position = UDim2.fromOffset(-spread, 0)
	self.spdGhostB.Position = UDim2.fromOffset(spread, 0)
	self.spdGhostA.TextTransparency = 0.82 - pulse * 0.42
	self.spdGhostB.TextTransparency = 0.82 - pulse * 0.42
	local col
	if speed >= 100 then
		-- Over the line: flat hot red, pulsing so it reads as "pegged".
		local v = 0.85 + 0.15 * math.sin(tick() * 9)
		col = Color3.fromRGB(255, 40, 60):Lerp(Color3.fromRGB(255, 120, 140), v)
	else
		-- Gradient hue cyan(0.53) -> violet(0.75) -> magenta(0.88) with speed.
		local h = 0.53 + (speed / 100) * 0.35
		col = Color3.fromHSV(h, 0.92, 1)
	end
	self.spdNum.TextColor3 = col:Lerp(C_WHITE, pulse * 0.3)
	self.spdStroke.Color = col -- rim wears the hue so it reads as glow
	-- Analog-smooth across the discrete cells: the shown charge eases to
	-- the real value (~70ms) and the leading cell only glows partial, so
	-- the strip breathes instead of stepping.
	local frac = math.clamp(powerFrac, 0, 1)
	local now = tick()
	local disp = self._powerDisp or frac
	disp += (frac - disp) * math.min(1, math.max(0, now - (self._powerT or now)) * 14)
	self._powerT = now
	self._powerDisp = disp
	-- Ready flash: when charge crosses the gate upward, the bar pings gold
	-- for a moment — you feel W come back without watching it.
	local gate = self.gateFrac or 1
	local ready = powerFrac >= gate
	if ready and self._powerReady == false then
		self._readyFlash = tick()
	end
	self._powerReady = ready
	local blink = powerSpent and math.sin(tick() * 10) > 0
	local flash = self._readyFlash ~= nil and tick() - self._readyFlash < 0.45
	-- Forced state color overrides the cyan->magenta ramp: gold ready-ping,
	-- white dash flash, dim flicker on a denied press (§4: broke/latched),
	-- hot orange while braking (S spends the same power meter), pink boost flare.
	local denied = dashDeniedAt ~= nil and (now - dashDeniedAt) < 0.3
	local forced = flash and C_GOLD
		or dashing and C_WHITE
		or (denied and (math.sin(now * 18) > 0 and C_DIM or C_PANEL))
		or (braking and Color3.fromRGB(255, 140, 40) or ((boosting or blink) and C_PINK or nil))
	local lit = disp * METER_SEGS
	for i, s in ipairs(self.powerSegs) do
		local edge = lit - (i - 1)
		if edge > 0 then
			s.BackgroundColor3 = forced or C_CYAN:Lerp(C_PINK, (i - 0.5) / METER_SEGS)
			s.BackgroundTransparency = math.clamp((1 - edge) * 0.85, 0, 0.85)
		elseif i <= (self._gateCells or 0) then
			-- Lock-zone slot: permanent warm tint, gently pulsing while
			-- latched out — "recharging through the gate" reads without
			-- needing a floating tick.
			s.BackgroundColor3 = C_GATE_DIM
			s.BackgroundTransparency = powerSpent and (0.35 + 0.3 * math.sin(now * 6)) or 0.4
		else
			s.BackgroundColor3 = C_PANEL
			s.BackgroundTransparency = 0.4
		end
	end
	-- The bead tip rides the smoothed lit edge, wearing the same color;
	-- hidden when the meter is empty so it doesn't dangle off the left end.
	self.powerTip.BackgroundColor3 = forced or C_CYAN:Lerp(C_PINK, disp)
	self.powerTip.Position = UDim2.new(0, METER_PAD + disp * (METER_W - METER_PAD * 2), 0.5, 0)
	self.powerTip.Visible = disp > 0.04
end

-- Gem combo pip under the subline (n>=2 shows "xN").
function Ui:setCombo(n: number)
	self.comboText.Text = "x" .. tostring(n)
	self.comboText.Visible = n >= 2
end

-- PB-gate crossing (§11): one gold flash under the score at the moment
-- the record falls — the marker itself only renders near the deck.
function Ui:flashBest()
	self.bestFlash.Visible = true
	local flash = self.bestFlash
	task.delay(Config.Score.PbFlashSeconds, function()
		flash.Visible = false
	end)
end

-- Near-miss ping (§10): "CLOSE +N" per graze, "+N ×M" while a chain is
-- running — the multiplier suffix only earns its space from chain two.
function Ui:flashMiss(points: number, chain: number?)
	local text = "CLOSE +" .. tostring(points)
	if chain and chain > 1 then
		text ..= " ×" .. tostring(chain)
	end
	self.missFlash.Text = text
	self.missFlash.Visible = true
	local flash = self.missFlash
	task.delay(Config.Score.NearMiss.FlashSeconds, function()
		flash.Visible = false
	end)
end

-- Achievement toast (§14): "◈ NAME · +N gems" — a ribbon for the unlock
-- moment. Back-to-back unlocks queue visually by overwriting the text.
function Ui:toast(text: string)
	self.achToast.Text = text
	self.achToast.Visible = true
	local toast = self.achToast
	task.delay(4, function()
		toast.Visible = false
	end)
end

-- Achievement tally on the menu (§14): "awards n/total".
function Ui:setAchievements(unlocked: number)
	self.achLine.Text = string.format("awards %d/%d", unlocked, #Config.Monetization.Achievements)
end

-- Daily quests (§14): csv "1,0,0,<bankedToday>" from RoBallQuests — quest
-- defs are recomputed here from Daily.quests() so client and server can
-- never disagree about what today's missions are.
function Ui:setQuests(csv: string)
	local parts = string.split(csv, ",")
	local banked = tonumber(parts[#parts]) or 0
	for i, q in ipairs(Daily.quests()) do
		local line = self.questLines[i]
		if line then
			local done = parts[i] == "1"
			local prog = ""
			if q.kind == "bank" and not done then
				prog = string.format(" — %d/%d", math.min(banked, q.target), q.target)
			end
			line.Text = string.format("%s %s%s  ·  +%d ◊", done and "✓" or "◇", q.text, prog, q.reward)
			line.TextColor3 = done and C_GOLD or C_DIM
		end
	end
end

function Ui:showDeath(
	score: number,
	dist: number,
	gems: number,
	best: number,
	seed: number,
	newBest: boolean?,
	banked: number?,
	streak: number?,
	streakBonus: number?,
	questBonus: number?,
	questHits: number?,
	weeklyBonus: number?,
	stats: { top: number, boost: number, dashes: number, hazards: number?, closest: number? }?
)
	self.menu.Visible = false
	self.hud.Visible = false
	self.spdNum.Visible = false
	self.spdUnit.Visible = false
	self.powerBar.Visible = false
	self.seedTag.Visible = false
	self.death.Visible = true
	self.dScore.Text = tostring(score)
	self.dBreakdown.Text =
		string.format('%d m  ·  +%d gem pts    <font color="#FFD440">◊ +%d BANKED</font>', dist, gems, banked or 0)
	self.dBest.Text = string.format("BEST %d   ·   seed %d", best, seed)
	self.dRerun.Text = string.format("rerun #%d", seed)
	self.dNewBest.Visible = newBest == true
	local n = streak or 0
	local bonus = streakBonus or 0
	-- Same-day replays show the streak without a re-paid bonus.
	self.dStreak.Text = if bonus > 0
		then string.format("day-%d streak · ◊ +%d banked", n, bonus)
		else string.format("day-%d streak", n)
	self.dStreak.Visible = n > 0
	local qb = questBonus or 0
	local hits = questHits or 0
	self.dQuest.Text = string.format("%s done · ◊ +%d banked", hits == 1 and "quest" or hits .. " quests", qb)
	self.dQuest.Visible = hits > 0
	local wb = weeklyBonus or 0
	self.dWeekly.Text = string.format("weekly cup · ◊ +%d banked", wb)
	self.dWeekly.Visible = wb > 0
	-- Run-stats card: "top 148 s/s · 214 gates · 41% boost · margin 0.9"
	-- — closest < 0 means the ball ran inside a rotor's sweep disc.
	if stats then
		local boostPct = if dist > 0 then math.floor(100 * stats.boost / dist) else 0
		local margin = if stats.closest
			then (stats.closest <= 0 and "in-disc" or string.format("%.1fs", stats.closest))
			else "—"
		self.dStats.Text = string.format(
			"top %d s/s · %d gates · %d%% boost · margin %s",
			math.floor(stats.top),
			stats.hazards or 0,
			boostPct,
			margin
		)
		self.dStats.Visible = true
	else
		self.dStats.Visible = false
	end
end

-- Garage state push (§18): one table per refresh — slot row text/afford,
-- pack button states (bundles + the bank2x perk), gem-pack buttons, bank
-- balance. Main computes all of it from attributes + catalog.
export type GarageState = {
	slots: { [string]: { text: string, afford: boolean } }, -- afford = clickable price
	packs: { [string]: { label: string, enabled: boolean } },
	gemPacks: { [string]: { label: string, enabled: boolean } },
	bank: number,
}

function Ui:setGarage(state: GarageState)
	for slot, btn in pairs(self.slotItem) do
		local row = state.slots[slot]
		btn.Text = if row then row.text else "—"
		btn.TextColor3 = if row and row.afford then C_GOLD else C_WHITE
	end
	for id, btn in pairs(self.packBtn) do
		local st = state.packs[id]
		local enabled = st ~= nil and st.enabled == true
		btn.Text = if st then st.label else "SOON"
		btn.TextColor3 = enabled and C_PINK or C_DIM
		self.packStroke[id].Color = enabled and C_PINK or C_DIM
		self.packEnabled[id] = enabled
	end
	for key, btn in pairs(self.gemPackBtn) do
		local st = state.gemPacks[key]
		local enabled = st ~= nil and st.enabled == true
		btn.Text = if st then st.label else "SOON"
		btn.TextColor3 = enabled and C_GOLD or C_DIM
		self.gemPackStroke[key].Color = enabled and C_GOLD or C_DIM
		self.gemPackEnabled[key] = enabled
	end
	self.bankLabel.Text = "◊ " .. tostring(state.bank)
end

function Ui:setBest(best: number)
	self.bestLabel.Text = "BEST " .. tostring(best or 0)
end

-- Board tab switch (§14): recolors tabs, shows/hides the daily info line,
-- then asks Main to fetch — rows arrive via setLeaderboard.
function Ui:setBoard(mode: string)
	if mode ~= "top" and mode ~= "daily" and mode ~= "weekly" then
		return
	end
	self.boardMode = mode
	self.tabTop.TextColor3 = if mode == "top" then C_PINK else C_DIM
	self.tabDaily.TextColor3 = if mode == "daily" then C_PINK else C_DIM
	self.tabWeekly.TextColor3 = if mode == "weekly" then C_PINK else C_DIM
	self.dailyInfo.Visible = mode ~= "top"
	if mode == "daily" then
		self.dailyInfo.Text = dailyText()
	elseif mode == "weekly" then
		self.dailyInfo.Text = weeklyText()
	end
	if self.onBoardTab then
		self.onBoardTab(mode)
	end
end

-- nil rows = stores unreachable (offline), {} = real but empty board.
-- Rows are cached so the friends filter can re-render without a refetch.
function Ui:setLeaderboard(rows: { { name: string, score: number, seed: number, userId: number? } }?)
	self.lastRows = rows
	self:drawBoard()
end

function Ui:drawBoard()
	local mode = self.boardMode
	local rows = self.lastRows
	-- Friends filter (§14): row.userId carries the rank owner's id; the
	-- real rank stays on the line so "12. friend" still reads as #12.
	if self.friendsOnly and rows then
		if self.friendsErr then
			for _, row in ipairs(self.boardRows) do
				row.Text = ""
			end
			self.boardRows[1].Text = "  friends list unavailable"
			return
		end
		if self.friendSet then
			local f: { { name: string, score: number, seed: number, userId: number?, rank: number? } } = {}
			for i, r in ipairs(rows) do
				if r.userId and self.friendSet[r.userId] then
					r.rank = i
					table.insert(f, r)
				end
			end
			rows = f
		end
		-- Set still loading — full rows show until it lands.
	end
	for i, row in ipairs(self.boardRows) do
		local r = rows and rows[i]
		row.Text = r and string.format("%2d. %-12s %7d  #%d", r.rank or i, r.name, r.score, r.seed) or ""
	end
	if rows == nil then
		self.boardRows[1].Text = if mode == "top" then "  leaderboard offline" else "  board offline"
	elseif #rows == 0 then
		self.boardRows[1].Text = if self.friendsOnly
			then "  no friends ranked on this board yet"
			elseif mode == "daily" then "  no daily runs yet — type 'daily' and set one."
			elseif mode == "weekly" then "  no cup runs yet — type 'weekly' and set one."
			else "  no saved runs yet — set one."
	end
end

function Ui:seedText(): string
	return self.seedBox.Text
end

-- Look-ahead radar (§12): bars are { dx, dz, w } in ball-relative studs —
-- dz is distance ahead (0 = at the ball), dx/w the block's offset/span.
-- Normalization lives here so callers pass raw world units.
function Ui:setRadar(bars: { { dx: number, dz: number, w: number } })
	local R = Config.Radar
	local px = (R.Width / 2) / R.HalfWidth -- px per stud off-center
	for i, bar in ipairs(self.radarBars) do
		local e = bars[i]
		if e then
			bar.Position = UDim2.fromScale(0.5 + e.dx / R.HalfWidth * 0.5, 1 - e.dz / R.Range)
			bar.Size = UDim2.fromOffset(math.max(3, e.w * px), R.BarH)
			bar.BackgroundTransparency = 0.15 + e.dz / R.Range * 0.55
			bar.Visible = true
		else
			bar.Visible = false
		end
	end
end

-- Pace delta (§12): signed meters vs the PB echo; nil hides the line
-- (no ghost, menu, death). Whole ints only — the caller rounds.
function Ui:setPace(delta: number?)
	if delta == nil then
		self.paceText.Visible = false
		return
	end
	self.paceText.Text = string.format("%+d vs PB", delta)
	self.paceText.TextColor3 = delta >= 0 and C_CYAN or C_PINK
	self.paceText.Visible = true
end

-- Rival pace (§14): "+N vs <name>" while the champion echo replays —
-- gold when you're beating the record's line, pink when it owns you.
function Ui:setRivalPace(delta: number?, name: string?)
	if not delta or not name then
		self.rivalText.Visible = false
		return
	end
	self.rivalText.Text = string.format("%+d vs %s", delta, name)
	self.rivalText.TextColor3 = if delta >= 0 then Config.Ghost.RivalColor else C_PINK
	self.rivalText.Visible = true
end

-- Sector split (§14): "SEC n · 8.2s   PB +0.4s   champion42 -1.1s" —
-- positive delta = ahead of that replay's clock at the same depth.
function Ui:flashSector(idx: number, elapsed: number, pbDelta: number?, rvDelta: number?, rvName: string?)
	local seg = function(name: string, delta: number?, aheadColor: Color3): string?
		if not delta then
			return nil
		end
		local col = if delta >= 0 then aheadColor else C_PINK
		return string.format('<font color="#%s">%s %+.1fs</font>', col:ToHex(), name, delta)
	end
	local text = string.format("SEC %d · %.1fs", idx, elapsed)
	local pb = seg("PB", pbDelta, C_CYAN)
	local rv = seg(rvName or "CHAMP", rvDelta, Config.Ghost.RivalColor)
	if pb then
		text ..= "   " .. pb
	end
	if rv then
		text ..= "   " .. rv
	end
	self.sectorFlash.Text = text
	self.sectorFlash.Visible = true
	local flash = self.sectorFlash
	task.delay(Config.Sectors.FlashSeconds, function()
		flash.Visible = false
	end)
end

function Ui:setSeedText(text: string)
	self.seedBox.Text = text
end

-- Recent runs (§14): rows are { s=score, d=dist, z=seed } newest-first,
-- straight off the RoBallHistory attribute. Hidden entirely when empty
-- (fresh profile) — no "no runs yet" dead space on the board.
function Ui:setHistory(rows: { { s: number, d: number, z: number } })
	self.historyRows = rows
	for i, b in ipairs(self.recentBtns) do
		local r = rows[i]
		if r then
			b.Text = string.format("%6d pts · %5d m · #%d", r.s, r.d, r.z)
			b.Visible = true
		else
			b.Visible = false
		end
	end
	self.recent.Visible = #rows > 0
end

function Ui:setTrackRow(text: string)
	self.trackName.Text = text
end

return Ui
