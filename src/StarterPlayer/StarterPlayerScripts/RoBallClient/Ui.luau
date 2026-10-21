--!strict
-- RoBall3D UI — menu, HUD, death screen, all built in code (DESIGN.md §6:
-- everything lives in git, nothing hand-placed in StarterGui). Vaporwave
-- shell: purple-black, hot pink + cyan accents, big centered score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)

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

local F_DISPLAY = Enum.Font.SciFi
local F_DATA = Enum.Font.Code

-- Boost strip geometry: LED-cell count + the segment strip's inset
-- inside the capsule (tip/gate math derives the inner width from it).
local BOOST_W = 220
local BOOST_SEGS = 14
local BOOST_PAD = 9

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

	-- Leaderboard: right-side panel, filled via GetLeaderboard remote. Row
	-- count tracks Config.Leaderboard.TopCount so the fetch and the panel
	-- never disagree.
	local TOP_N = Config.Leaderboard.TopCount
	local board = Instance.new("Frame")
	board.Name = "Leaderboard"
	board.AnchorPoint = Vector2.new(1, 0.5)
	board.Position = UDim2.fromScale(0.96, 0.5)
	board.Size = UDim2.fromOffset(320, 58 + TOP_N * 25)
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
	for i = 1, TOP_N do
		local row = label(boardBody, "", 14, F_DATA, i % 2 == 0 and C_CYAN or C_WHITE, i)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		self.boardRows[i] = row
	end
	self.boardRows[1].Text = "  loading…" -- first refreshBoard() lands shortly after boot

	--============================ GARAGE ============================--
	-- Neon shop (DESIGN.md §18): left-panel mirror of the leaderboard.
	-- Equip arrows cycle the whole catalog per slot — owned items equip on
	-- browse, unowned ones show their gem price and buy on name-click.
	-- Pack buttons prompt bundle gamepasses, the BANK block sells gem-pack
	-- dev products and the 2X BANK pass. Pure presentation — Main feeds
	-- names/status via setGarage and owns the callbacks.
	local garage = Instance.new("Frame")
	garage.Name = "Garage"
	garage.AnchorPoint = Vector2.new(0, 0.5)
	garage.Position = UDim2.fromScale(0.04, 0.5)
	garage.Size = UDim2.fromOffset(330, 660)
	garage.BackgroundColor3 = C_PANEL
	garage.BackgroundTransparency = 0.25
	garage.BorderSizePixel = 0
	garage.Parent = menu
	local gcorner = Instance.new("UICorner")
	gcorner.CornerRadius = UDim.new(0, 10)
	gcorner.Parent = garage

	label(garage, "GARAGE", 22, F_DISPLAY, C_PINK, 0).Position = UDim2.fromOffset(0, 8)

	local function arrowButton(parent, text, x, y)
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 20
		b.TextColor3 = C_CYAN
		b.Text = text
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(26, 30)
		b.Parent = parent
		return b
	end

	-- Slot rows: "SKIN   < ITEM NAME >". Cycling browses the full catalog;
	-- the name itself is the buy button for priced-but-unowned items.
	self.slotItem = {}
	for i, slot in ipairs(Cosmetics.Slots) do
		local y = 46 + (i - 1) * 30
		local sl = Instance.new("TextLabel")
		sl.BackgroundTransparency = 1
		sl.Font = F_DATA
		sl.TextSize = 12
		sl.TextColor3 = C_DIM
		sl.TextXAlignment = Enum.TextXAlignment.Left
		sl.Text = Cosmetics.SlotName[slot]
		sl.Position = UDim2.fromOffset(14, y)
		sl.Size = UDim2.fromOffset(56, 28)
		sl.Parent = garage

		local nm = Instance.new("TextButton")
		nm.BackgroundTransparency = 1
		nm.AutoButtonColor = false
		nm.Font = F_DATA
		nm.TextSize = 15
		nm.TextColor3 = C_WHITE
		nm.Text = "—"
		nm.Position = UDim2.fromOffset(102, y)
		nm.Size = UDim2.fromOffset(182, 28)
		nm.Parent = garage
		self.slotItem[slot] = nm
		nm.MouseButton1Click:Connect(function()
			if self.onItemSlot then
				self.onItemSlot(slot)
			end
		end)

		local left = arrowButton(garage, "<", 72, y)
		left.MouseButton1Click:Connect(function()
			if self.onEquipCycle then
				self.onEquipCycle(slot, -1)
			end
		end)
		local right = arrowButton(garage, ">", 288, y)
		right.MouseButton1Click:Connect(function()
			if self.onEquipCycle then
				self.onEquipCycle(slot, 1)
			end
		end)
	end

	local browseHint = label(garage, "cycle equips owned · click a ◊ price to buy", 10, F_DATA, C_DIM, 0)
	browseHint.Position = UDim2.fromOffset(0, 218)
	browseHint.TextTransparency = 0.35

	label(garage, "PACKS", 14, F_DISPLAY, C_DIM, 0).Position = UDim2.fromOffset(0, 238)

	-- Pack rows: name + contents left, price button right. Button state
	-- comes from setGarage: "R$49" enabled / "OWNED" / "SOON" dimmed.
	self.packBtn = {}
	self.packStroke = {}
	self.packEnabled = {}
	local function packRow(id: string, name: string, desc: string, y: number)
		local nl = Instance.new("TextLabel")
		nl.BackgroundTransparency = 1
		nl.Font = F_DATA
		nl.TextSize = 14
		nl.TextColor3 = C_WHITE
		nl.TextXAlignment = Enum.TextXAlignment.Left
		nl.Text = name
		nl.Position = UDim2.fromOffset(14, y)
		nl.Size = UDim2.fromOffset(210, 18)
		nl.Parent = garage

		local dl = Instance.new("TextLabel")
		dl.BackgroundTransparency = 1
		dl.Font = F_DATA
		dl.TextSize = 10
		dl.TextColor3 = C_DIM
		dl.TextXAlignment = Enum.TextXAlignment.Left
		dl.Text = desc
		dl.Position = UDim2.fromOffset(14, y + 17)
		dl.Size = UDim2.fromOffset(210, 14)
		dl.Parent = garage

		local btn = Instance.new("TextButton")
		btn.BackgroundTransparency = 1
		btn.AutoButtonColor = false
		btn.Font = F_DATA
		btn.TextSize = 14
		btn.TextColor3 = C_PINK
		btn.Text = "R$?"
		btn.Position = UDim2.fromOffset(232, y + 2)
		btn.Size = UDim2.fromOffset(84, 32)
		btn.Parent = garage
		local stroke = Instance.new("UIStroke")
		stroke.Color = C_PINK
		stroke.Thickness = 1.5
		stroke.Parent = btn
		self.packBtn[id] = btn
		self.packStroke[id] = stroke
		btn.MouseButton1Click:Connect(function()
			if self.packEnabled[id] and self.onBuy then
				self.onBuy(id)
			end
		end)
	end
	for i, b in ipairs(Cosmetics.Bundles) do
		packRow(b.id, b.name, b.desc, 258 + (i - 1) * 48)
	end

	--=========== BANK (§18 P2) ===========--
	-- Gem economy surface: balance line, three gem-pack dev products, and
	-- the 2X BANK pass row. Everything degrades to SOON until the ids are
	-- created on the dashboard — the buttons only arm via setGarage.
	label(garage, "BANK", 14, F_DISPLAY, C_DIM, 0).Position = UDim2.fromOffset(0, 498)
	local bal = Instance.new("TextLabel")
	bal.BackgroundTransparency = 1
	bal.Font = F_DATA
	bal.TextSize = 16
	bal.TextColor3 = C_GOLD
	bal.TextXAlignment = Enum.TextXAlignment.Right
	bal.Text = "◊ 0"
	bal.Position = UDim2.fromOffset(150, 496)
	bal.Size = UDim2.fromOffset(166, 20)
	bal.Parent = garage
	self.bankLabel = bal

	-- Gem packs: three equal buttons "◊300\nR$49". Enabled state arrives via
	-- setGarage's gemPacks list (SOON until product ids exist).
	self.gemPackBtn = {}
	self.gemPackStroke = {}
	self.gemPackEnabled = {}
	for i, key in ipairs(Config.Monetization.ProductOrder) do
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DATA
		b.TextSize = 13
		b.TextColor3 = C_GOLD
		b.Text = "◊?\nSOON"
		b.Position = UDim2.fromOffset(14 + (i - 1) * 103, 524)
		b.Size = UDim2.fromOffset(96, 44)
		b.Parent = garage
		local stroke = Instance.new("UIStroke")
		stroke.Color = C_GOLD
		stroke.Thickness = 1.5
		stroke.Parent = b
		self.gemPackBtn[key] = b
		self.gemPackStroke[key] = stroke
		b.MouseButton1Click:Connect(function()
			if self.gemPackEnabled[key] and self.onGemPack then
				self.onGemPack(key)
			end
		end)
	end

	-- 2X BANK rides the pack-row machinery: Passes.bank2x is a gamepass like
	-- the bundles, so packBtn["bank2x"] + onBuy("bank2x") just works.
	packRow("bank2x", "2X BANK", "every gem banks double", 580)

	local hint = label(garage, "gems bank on pickup — they're never score", 11, F_DATA, C_DIM, 0)
	hint.Position = UDim2.fromOffset(0, 632)
	hint.TextTransparency = 0.3

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

	-- Gem combo counter under the subline: "x3" while a pickup streak is
	-- alive (client derives it from RoBallGems timing, ComboWindow).
	local comboText = Instance.new("TextLabel")
	comboText.BackgroundTransparency = 1
	comboText.Font = F_DATA
	comboText.TextSize = 16
	comboText.TextColor3 = C_CYAN
	comboText.TextStrokeTransparency = 0.5
	comboText.Position = UDim2.fromOffset(0, 80)
	comboText.Size = UDim2.new(1, 0, 0, 18)
	comboText.Text = ""
	comboText.Visible = false
	comboText.Parent = hud
	self.comboText = comboText

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

	-- Boost bar: a vaporwave nitro strip — a tilted pill of LED segments
	-- ramping cyan->magenta like a tape-deck VU meter. A diamond bead
	-- rides the lit edge; the boundary cell glows partial so charge reads
	-- analog-smooth between cells. RechargeGate is a gold notch slotted
	-- between cells, its lock zone tinted warm; the strip still flares
	-- (pink boost, orange brake, gold ready-ping).
	local bWrap = Instance.new("Frame")
	bWrap.Name = "BoostBar"
	bWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	bWrap.Position = UDim2.new(0.18, BOOST_W / 2, 1, -38)
	bWrap.Size = UDim2.fromOffset(BOOST_W, 18)
	bWrap.Rotation = -4
	bWrap.BackgroundColor3 = C_BG
	bWrap.BackgroundTransparency = 0.25
	bWrap.BorderSizePixel = 0
	bWrap.Visible = false
	bWrap.Parent = gui
	self.boostBar = bWrap
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
	bInner.Position = UDim2.fromOffset(BOOST_PAD, 4)
	bInner.Size = UDim2.new(1, -BOOST_PAD * 2, 1, -8)
	bInner.Parent = bWrap
	local innerW = BOOST_W - BOOST_PAD * 2
	local gap = 3
	local cellW = (innerW - gap * (BOOST_SEGS - 1)) / BOOST_SEGS
	local gateCells = math.floor(Config.Boost.RechargeGate * BOOST_SEGS + 1e-4)
	self._gateCells = gateCells
	self.boostSegs = {}
	for i = 1, BOOST_SEGS do
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
		self.boostSegs[i] = s
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
	self.boostGate = bGate
	-- Diamond bead riding the lit edge — in wrap space so its x tracks
	-- the smoothed fill fraction every frame.
	local bTip = Instance.new("Frame")
	bTip.AnchorPoint = Vector2.new(0.5, 0.5)
	bTip.Position = UDim2.new(0, BOOST_PAD, 0.5, 0)
	bTip.Size = UDim2.fromOffset(12, 12)
	bTip.Rotation = 45
	bTip.BackgroundColor3 = C_CYAN
	bTip.BorderSizePixel = 0
	bTip.Visible = false
	bTip.Parent = bWrap
	self.boostTip = bTip
	local bLab = Instance.new("TextLabel")
	bLab.AnchorPoint = Vector2.new(0, 1)
	bLab.Position = UDim2.fromOffset(0, -3)
	bLab.Size = UDim2.fromOffset(BOOST_W, 13)
	bLab.BackgroundTransparency = 1
	bLab.Font = F_DATA
	bLab.TextSize = 11
	bLab.TextColor3 = C_DIM
	bLab.TextXAlignment = Enum.TextXAlignment.Left
	bLab.Text = "BOOST"
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

	label(dCol, "RUN OVER", 48, F_DISPLAY, C_PINK, 1)
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
	local retry = outlineButton(dCol, "RETRY", 30, 7)
	retry.Size = UDim2.fromOffset(300, 56)
	retry.MouseButton1Click:Connect(function()
		if self.onRetry then
			self.onRetry()
		end
	end)
	label(dCol, "or press R", 13, F_DATA, C_DIM, 8).TextTransparency = 0.25
	-- Back to the menu = garage access (§18): the shop lives on the menu.
	local toMenu = ghostButton(dCol, "menu", 15, 9)
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
	self.boostBar.Visible = false
	self.seedTag.Visible = false
	self:setBest(best)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.hud.Visible = true
	self.spdNum.Visible = true
	self.spdUnit.Visible = true
	self.boostBar.Visible = true
	self.seedTag.Visible = true
end

function Ui:setHud(score: number, dist: number, gems: number, _speed: number, seed: number)
	self.scoreText.Text = tostring(score)
	-- Speed lives on the dial now; the subline stays quiet.
	self.subText.Text = string.format("%d m  ·  gems +%d", dist, gems)
	self.seedTag.Text = string.format("seed %d", seed)
end

-- Speed number + boost bar, called every heartbeat during a run.
-- The digit's hue IS the speed read: cyan 0 -> magenta 100 -> hot red
-- pegged past it. The boost bar pulses pink while W is held and blinks
-- while the meter is latched out below RechargeGate.
function Ui:setSpeedo(speed: number, boostFrac: number, boosting: boolean, boostSpent: boolean, braking: boolean?)
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
	-- Analog-smooth across the discrete cells: the shown charge eases to
	-- the real value (~70ms) and the leading cell only glows partial, so
	-- the strip breathes instead of stepping.
	local frac = math.clamp(boostFrac, 0, 1)
	local now = tick()
	local disp = self._boostDisp or frac
	disp += (frac - disp) * math.min(1, math.max(0, now - (self._boostT or now)) * 14)
	self._boostT = now
	self._boostDisp = disp
	-- Ready flash: when charge crosses the gate upward, the bar pings gold
	-- for a moment — you feel W come back without watching it.
	local gate = self.gateFrac or 1
	local ready = boostFrac >= gate
	if ready and self._boostReady == false then
		self._readyFlash = tick()
	end
	self._boostReady = ready
	local blink = boostSpent and math.sin(tick() * 10) > 0
	local flash = self._readyFlash ~= nil and tick() - self._readyFlash < 0.45
	-- Forced state color overrides the cyan->magenta ramp: gold ready-ping,
	-- hot orange while braking (S spends the same meter), pink boost flare.
	local forced = flash and C_GOLD
		or (braking and Color3.fromRGB(255, 140, 40) or ((boosting or blink) and C_PINK or nil))
	local lit = disp * BOOST_SEGS
	for i, s in ipairs(self.boostSegs) do
		local edge = lit - (i - 1)
		if edge > 0 then
			s.BackgroundColor3 = forced or C_CYAN:Lerp(C_PINK, (i - 0.5) / BOOST_SEGS)
			s.BackgroundTransparency = math.clamp((1 - edge) * 0.85, 0, 0.85)
		elseif i <= (self._gateCells or 0) then
			-- Lock-zone slot: permanent warm tint, gently pulsing while
			-- latched out — "recharging through the gate" reads without
			-- needing a floating tick.
			s.BackgroundColor3 = C_GATE_DIM
			s.BackgroundTransparency = boostSpent and (0.35 + 0.3 * math.sin(now * 6)) or 0.4
		else
			s.BackgroundColor3 = C_PANEL
			s.BackgroundTransparency = 0.4
		end
	end
	-- The bead tip rides the smoothed lit edge, wearing the same color;
	-- hidden when the meter is empty so it doesn't dangle off the left end.
	self.boostTip.BackgroundColor3 = forced or C_CYAN:Lerp(C_PINK, disp)
	self.boostTip.Position = UDim2.new(0, BOOST_PAD + disp * (BOOST_W - BOOST_PAD * 2), 0.5, 0)
	self.boostTip.Visible = disp > 0.04
end

-- Gem combo pip under the subline (n>=2 shows "xN").
function Ui:setCombo(n: number)
	self.comboText.Text = "x" .. tostring(n)
	self.comboText.Visible = n >= 2
end

function Ui:showDeath(
	score: number,
	dist: number,
	gems: number,
	best: number,
	seed: number,
	newBest: boolean?,
	banked: number?
)
	self.menu.Visible = false
	self.hud.Visible = false
	self.spdNum.Visible = false
	self.spdUnit.Visible = false
	self.boostBar.Visible = false
	self.seedTag.Visible = false
	self.death.Visible = true
	self.dScore.Text = tostring(score)
	self.dBreakdown.Text =
		string.format('%d m  ·  +%d gem pts    <font color="#FFD440">◊ +%d BANKED</font>', dist, gems, banked or 0)
	self.dBest.Text = string.format("BEST %d   ·   seed %d", best, seed)
	self.dNewBest.Visible = newBest == true
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

-- nil rows = stores unreachable (offline), {} = real but empty board.
function Ui:setLeaderboard(rows: { { name: string, score: number, seed: number } }?)
	for i, row in ipairs(self.boardRows) do
		local r = rows and rows[i]
		row.Text = r and string.format("%2d. %-12s %7d  #%d", i, r.name, r.score, r.seed) or ""
	end
	if rows == nil then
		self.boardRows[1].Text = "  leaderboard offline"
	elseif #rows == 0 then
		self.boardRows[1].Text = "  no saved runs yet — set one."
	end
end

function Ui:seedText(): string
	return self.seedBox.Text
end

return Ui
