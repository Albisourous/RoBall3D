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

	--================= SPEEDOMETER (bottom-right) =================--
	-- Neon-ring tach (DESIGN.md §12): 270° dial, 0-100 main sweep in cyan,
	-- overshoot arc 100+ in hot magenta, inner ring = boost charge.
	-- Big digital readout — the gauge sells the fantasy, the number is truth.
	local spd = Instance.new("Frame")
	spd.Name = "Speedo"
	spd.AnchorPoint = Vector2.new(0.5, 1)
	spd.Position = UDim2.new(0.72, 0, 1, -12)
	spd.Size = UDim2.fromOffset(226, 226)
	spd.BackgroundTransparency = 1
	spd.Visible = false
	spd.Parent = gui
	self.speedo = spd

	-- F-Zero pod chrome: a dark tilted housing disk, neon bezel, and
	-- slanted vent slits — dresses a bare dial into a retro-future
	-- dashboard pod. Drawn first so it sits behind the gauge parts.
	local function podChrome(parent: Instance, rim: Color3, mirror: boolean)
		local disk = Instance.new("Frame")
		disk.AnchorPoint = Vector2.new(0.5, 0.5)
		disk.Position = UDim2.fromScale(0.5, 0.52)
		disk.Size = UDim2.fromOffset(214, 214)
		disk.BackgroundColor3 = C_BG
		disk.BackgroundTransparency = 0.16
		disk.BorderSizePixel = 0
		disk.Rotation = mirror and 4 or -4
		disk.Parent = parent
		local duc = Instance.new("UICorner")
		duc.CornerRadius = UDim.new(0.16, 0)
		duc.Parent = disk
		local bezel = Instance.new("UIStroke")
		bezel.Color = rim
		bezel.Thickness = 2.5
		bezel.Transparency = 0.15
		bezel.Parent = disk
		-- Inner bezel circle — the recessed instrument well.
		local well = Instance.new("Frame")
		well.AnchorPoint = Vector2.new(0.5, 0.5)
		well.Position = UDim2.fromScale(0.5, 0.5)
		well.Size = UDim2.fromOffset(196, 196)
		well.BackgroundColor3 = Color3.fromRGB(4, 2, 8)
		well.BackgroundTransparency = 0.25
		well.BorderSizePixel = 0
		well.Parent = parent
		local wuc = Instance.new("UICorner")
		wuc.CornerRadius = UDim.new(1, 0)
		wuc.Parent = well
		local wring = Instance.new("UIStroke")
		wring.Color = rim
		wring.Thickness = 1.5
		wring.Transparency = 0.4
		wring.Parent = well
		-- Vent slits along the pod's top edge — pure F-Zero garnish.
		local dir = mirror and -1 or 1
		for i = 0, 2 do
			local v = Instance.new("Frame")
			v.AnchorPoint = Vector2.new(0.5, 0.5)
			v.Position = UDim2.new(0.5, dir * (56 + i * 20), 0, 12)
			v.Size = UDim2.fromOffset(16, 5)
			v.Rotation = dir * -28
			v.BackgroundColor3 = rim
			v.BackgroundTransparency = 0.35
			v.BorderSizePixel = 0
			v.Parent = parent
			local vc = Instance.new("UICorner")
			vc.CornerRadius = UDim.new(1, 0)
			vc.Parent = v
		end
	end
	podChrome(spd, C_CYAN, false)

	local R_OUT = 96 -- main arc radius
	local A0 = -135 -- dial zero angle (deg, 7 o'clock)
	local A100 = 85 -- angle at 100 s/s
	local AMAX = 135 -- needle hard stop (deg, 5 o'clock)
	local OVR_TOP = 240 -- s/s mapped onto the overshoot arc's end

	-- A spoke: invisible arm rotated at the dial center, child mark placed
	-- `r` px up. Parent rotation does the geometry — no trig per element.
	local function spoke(parent: Instance, r: number): Frame
		local arm = Instance.new("Frame")
		arm.BackgroundTransparency = 1
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Position = UDim2.fromScale(0.5, 0.5)
		arm.Size = UDim2.fromOffset(0, 0)
		arm.Parent = parent
		local mark = Instance.new("Frame")
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromOffset(0, -r)
		mark.BorderSizePixel = 0
		mark.Parent = arm
		return mark, arm
	end
	local function seg(a: number, r: number, len: number, thick: number, col: Color3, parent: Instance): Frame
		local mark, arm = spoke(parent, r)
		mark.Size = UDim2.fromOffset(thick, len)
		mark.BackgroundColor3 = col
		arm.Rotation = a
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = mark
		return mark
	end

	-- Main arc: cyan pills 0→100 (each = 10 s/s), overshoot pills past the
	-- 100 tick in pink — the "beyond the bar" zone the needle travels into.
	local arcA = (A100 - A0) / 22
	for i = 0, 22 do
		seg(A0 + i * arcA, R_OUT, 11, 4, C_CYAN, spd)
	end
	self.ovrSegs = {}
	local ovrA = (AMAX - A100) / 5
	for i = 1, 5 do
		local s = seg(A100 + i * ovrA, R_OUT, 13, 5, C_PINK, spd)
		table.insert(self.ovrSegs, s)
	end
	-- Major ticks + upright labels at 0 / 50 / 100 / 100+. Labels use
	-- sin/cos placement (not arm rotation) so the text never tilts.
	local function arcLabel(a: number, text: string, col: Color3)
		local rad = math.rad(a)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.new(0.5, math.sin(rad) * (R_OUT + 17), 0.5, -math.cos(rad) * (R_OUT + 17))
		l.Size = UDim2.fromOffset(40, 14)
		l.Font = F_DATA
		l.TextSize = 12
		l.TextColor3 = col
		l.Text = text
		l.Parent = spd
	end
	for _, t in ipairs({ { 0, "0" }, { 50, "50" }, { 100, "100" } }) do
		local a = A0 + (t[1] / 100) * (A100 - A0)
		seg(a, R_OUT, 20, 5, C_WHITE, spd)
		arcLabel(a, t[2], C_DIM)
	end
	arcLabel(AMAX, "100+", C_PINK)

	-- Needle: pink arm pivoting at center; turns gold while boosting.
	local needle, needleArm = spoke(spd, R_OUT - 16)
	needle.AnchorPoint = Vector2.new(0.5, 1)
	needle.Position = UDim2.fromOffset(0, 0)
	needle.Size = UDim2.fromOffset(3, R_OUT - 16)
	needle.BackgroundColor3 = C_PINK
	needleArm.Rotation = A0
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(10, 10)
	hub.BackgroundColor3 = C_WHITE
	hub.BorderSizePixel = 0
	hub.Parent = spd
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = hub
	self.needleArm = needleArm
	self.needle = needle
	self.spdA = { A0 = A0, A100 = A100, AMAX = AMAX, OVR_TOP = OVR_TOP }

	-- Digital readout: big number center-lower, unit under it.
	local digits = Instance.new("TextLabel")
	digits.BackgroundTransparency = 1
	digits.AnchorPoint = Vector2.new(0.5, 0.5)
	digits.Position = UDim2.new(0.5, 0, 0.5, 26)
	digits.Size = UDim2.fromOffset(140, 44)
	digits.Font = F_DATA
	digits.TextSize = 44
	digits.TextColor3 = C_WHITE
	digits.TextStrokeTransparency = 0.55
	digits.Text = "0"
	digits.Parent = spd
	self.spdDigits = digits
	local unit = Instance.new("TextLabel")
	unit.BackgroundTransparency = 1
	unit.AnchorPoint = Vector2.new(0.5, 0.5)
	unit.Position = UDim2.new(0.5, 0, 0.5, 52)
	unit.Size = UDim2.fromOffset(80, 14)
	unit.Font = F_DATA
	unit.TextSize = 11
	unit.TextColor3 = C_DIM
	unit.Text = "s/s"
	unit.Parent = spd

	--================== BOOST GAUGE (bottom-left) ==================--
	-- Mirrored twin of the speedo: a fill-arc resource gauge, not a needle —
	-- nitro reads as stored energy in every retro racer. Cyan slots = charge;
	-- they flare pink while boosting; a gold tick marks the recharge gate.
	local bst = Instance.new("Frame")
	bst.Name = "BoostGauge"
	bst.AnchorPoint = Vector2.new(0.5, 1)
	bst.Position = UDim2.new(0.28, 0, 1, -12)
	bst.Size = UDim2.fromOffset(226, 226)
	bst.BackgroundTransparency = 1
	bst.Visible = false
	bst.Parent = gui
	self.boostGauge = bst
	podChrome(bst, C_PINK, true)

	local B_R = 80 -- slot arc radius
	local B_A0 = 135 -- empty sits at 5 o'clock — faces the speedo's zero
	local B_SWEEP = 220 -- sweeps counter-clockwise (mirror of the speedo)
	local B_N = 14
	self.boostSegs = {}
	for i = 1, B_N do
		local a = B_A0 - (i - 0.5) / B_N * B_SWEEP
		local s = seg(a, B_R, 13, 5, C_PANEL, bst)
		s.BackgroundTransparency = 0.4
		table.insert(self.boostSegs, s)
	end
	-- Gold gate tick is drawn lazily once Main tells us RechargeGate.
	self.gateFrac = nil :: number?
	self._gateDrawn = false
	self._segFn = seg
	self._bstFrame = bst
	self._bstA = { A0 = B_A0, SWEEP = B_SWEEP, R = B_R, N = B_N }

	local bHead = Instance.new("TextLabel")
	bHead.BackgroundTransparency = 1
	bHead.AnchorPoint = Vector2.new(0.5, 0.5)
	bHead.Position = UDim2.new(0.5, 0, 0.5, -6)
	bHead.Size = UDim2.fromOffset(120, 16)
	bHead.Font = F_DATA
	bHead.TextSize = 11
	bHead.TextColor3 = C_DIM
	bHead.Text = "BOOST"
	bHead.Parent = bst
	local bState = Instance.new("TextLabel")
	bState.BackgroundTransparency = 1
	bState.AnchorPoint = Vector2.new(0.5, 0.5)
	bState.Position = UDim2.new(0.5, 0, 0.5, 18)
	bState.Size = UDim2.fromOffset(140, 38)
	bState.Font = F_DATA
	bState.TextSize = 30
	bState.TextColor3 = C_CYAN
	bState.TextStrokeTransparency = 0.55
	bState.Text = "READY"
	bState.Parent = bst
	self.boostState = bState

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
	self.speedo.Visible = false
	self.boostGauge.Visible = false
	self.bestLabel.Text = "BEST " .. tostring(best or 0)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.hud.Visible = true
	self.speedo.Visible = true
	self.boostGauge.Visible = true
end

function Ui:setHud(score: number, dist: number, gems: number, _speed: number, seed: number)
	self.scoreText.Text = tostring(score)
	-- Speed lives on the dial now; the subline stays quiet.
	self.subText.Text = string.format("%d m  ·  gems +%d  ·  seed %d", dist, gems, seed)
end

-- Speedometer + boost gauge, called every heartbeat during a run.
function Ui:setSpeedo(speed: number, boostFrac: number, boosting: boolean, boostSpent: boolean)
	local a = self.spdA
	-- 0-100 sweeps the cyan arc; past 100 the needle walks the pink
	-- overshoot arc (compressed so deep runs still have travel).
	local ang
	if speed <= 100 then
		ang = a.A0 + (speed / 100) * (a.A100 - a.A0)
	else
		ang = a.A100 + math.min(1, (speed - 100) / (a.OVR_TOP - 100)) * (a.AMAX - a.A100)
	end
	self.needleArm.Rotation = ang
	self.needle.BackgroundColor3 = boosting and C_GOLD or C_PINK
	self.spdDigits.Text = tostring(math.floor(speed + 0.5))
	self.spdDigits.TextColor3 = speed > 100 and C_PINK or C_WHITE

	-- Overshoot arc breathes while pegged past 100.
	local pulse = speed > 100 and (0.1 + 0.12 * math.sin(tick() * 7)) or 0.45
	for _, s in ipairs(self.ovrSegs) do
		s.BackgroundTransparency = pulse
	end

	--================ boost gauge ================--
	local ba = self._bstA
	-- Gold gate tick: drawn once we know RechargeGate (set by Main).
	if self.gateFrac and not self._gateDrawn then
		self._gateDrawn = true
		local ga = ba.A0 - self.gateFrac * ba.SWEEP
		self._segFn(ga, ba.R, 20, 4, C_GOLD, self._bstFrame)
	end
	local n = #self.boostSegs
	local flash = boostSpent and not boosting and (math.sin(tick() * 10) > 0)
	for i, s in ipairs(self.boostSegs) do
		local lit = boostFrac >= i / n - 1e-3
		s.BackgroundColor3 = lit and (boosting and C_PINK or C_CYAN) or C_PANEL
		s.BackgroundTransparency = lit and 0 or (flash and 0.2 or 0.55)
	end
	self.boostState.Text = boosting and "GO!" or (boostSpent and "SPENT" or (boostFrac > 0.98 and "READY" or "CHRG"))
	self.boostState.TextColor3 = boosting and C_PINK or (boostSpent and C_GOLD or C_CYAN)
end

function Ui:showDeath(score: number, dist: number, gems: number, best: number, seed: number)
	self.menu.Visible = false
	self.hud.Visible = false
	self.speedo.Visible = false
	self.boostGauge.Visible = false
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
