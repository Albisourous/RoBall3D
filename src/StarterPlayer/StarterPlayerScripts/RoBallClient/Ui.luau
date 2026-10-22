--!strict
-- RoBall3D UI — menu, HUD, death screen, all built in code (DESIGN.md §6:
-- everything lives in git, nothing hand-placed in StarterGui). Vaporwave
-- shell: purple-black, hot pink + cyan accents, big centered score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.RoBall.Config)
local Cosmetics = require(ReplicatedStorage.RoBall.Cosmetics)
local Daily = require(ReplicatedStorage.RoBall.Daily)
local AudioMix = require(script.Parent.AudioMix)
local Sfx = require(script.Parent.SfxController)

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

-- Bottom telemetry pills (§4/§12): power meter left, TEMPO scope right —
-- the same untilted capsule footprint mirrored in from the corners, so
-- the pair brackets the lane as a matched set with different guts.
local PILL_W = 246
local PILL_H = 54
local METER_SEGS = 14
local METER_PAD = 9
local WAVE_W = 140
local WAVE_H = 42

-- Menu feel (MENU.md): tunables live in Config.Menu — springs ride the
-- menu's own frame tick (pulseMenu), and the death hero stamps in on
-- the Back ease there.

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

-- Vector gem: the ◊ currency mark as a real diamond — gold body with a
-- darker cut facet and a vertex glint, drawn from rotated frames so no
-- image asset is needed. Matches the wireframe look by being geometry.
local function gemIcon(parent: Instance, size: number, color: Color3): Frame
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	local dia = Instance.new("Frame")
	dia.AnchorPoint = Vector2.new(0.5, 0.5)
	dia.Position = UDim2.fromScale(0.5, 0.5)
	dia.Size = UDim2.fromScale(0.72, 0.72)
	dia.Rotation = 45
	dia.BackgroundColor3 = color
	dia.BorderSizePixel = 0
	dia.Parent = holder
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 45
	sheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.4)),
	})
	sheen.Parent = dia
	local facet = Instance.new("Frame")
	facet.AnchorPoint = Vector2.new(0.5, 0.5)
	facet.Position = UDim2.fromScale(0.5, 0.56)
	facet.Size = UDim2.fromScale(0.3, 0.3)
	facet.Rotation = 45
	facet.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.5)
	facet.BorderSizePixel = 0
	facet.Parent = holder
	local glint = Instance.new("Frame")
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.fromScale(0.5, 0.24)
	glint.Size = UDim2.fromScale(0.13, 0.13)
	glint.Rotation = 45
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.BackgroundTransparency = 0.2
	glint.BorderSizePixel = 0
	glint.Parent = holder
	return holder
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
local function ghostButton(parent, text, size, order, color)
	local base = color or C_DIM
	local b = Instance.new("TextButton")
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Font = F_DATA
	b.TextSize = size
	b.TextColor3 = base
	b.Text = text
	b.Size = UDim2.fromOffset(size * 8, size * 1.6)
	b.LayoutOrder = order or 0
	b.MouseEnter:Connect(function()
		b.TextColor3 = C_WHITE
	end)
	b.MouseLeave:Connect(function()
		b.TextColor3 = base
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

-- One-DOF spring (MENU.md §4): pos/vel integrate toward target each
-- frame; a cycle moves the target, drag/wheel adds vel directly.
local function spring(pos: number, vel: number, target: number, dt: number): (number, number)
	local c = Config.Menu
	vel += (c.SpringStiff * (target - pos) - c.SpringDamp * vel) * dt
	return pos + vel * dt, vel
end

-- Grid-snapped UI hitsounds (MENU.md §5): hover lands a tick, activate
-- lands a kick — the gem-chime trick on quieter voices. Activated covers
-- mouse click AND gamepad A (the menu buttons are Selectable), so one
-- pass arms both input paths.
local function wireTick(b: GuiButton)
	b.MouseEnter:Connect(function()
		Sfx.uiTick("hover")
	end)
	b.Activated:Connect(function()
		Sfx.uiTick("click")
	end)
end

export type Ui = typeof(setmetatable({} :: any, Ui))

function Ui.new(): Ui
	local self = setmetatable({}, Ui)
	self.onPlay = nil :: ((seedText: string) -> ())?
	self.onRetry = nil :: (() -> ())?
	self.onMenu = nil :: (() -> ())?
	self.onEquipCycle = nil :: ((slot: string, dir: number) -> ())?
	self.onRandomize = nil :: (() -> ())? -- RANDOM chip: slot-machine the browse set
	self.onItemSlot = nil :: ((slot: string) -> ())? -- click displayed item name
	self.onDashMode = nil :: (() -> ())? -- menu dash-style toggle
	self.onBuy = nil :: ((bundleId: string) -> ())?
	self.onGemPack = nil :: ((productKey: string) -> ())?
	self.onBuyItem = nil :: ((itemId: string) -> ())? -- à-la-carte inside an open pack
	self.onPadTap = nil :: ((dir: number) -> ())? -- touch pad double-tap dash
	-- Touch input state the drive loop reads each frame (§4): padSteer is
	-- the analog −1..+1 drag; the holds mirror W/S. Written by the pad
	-- zone + buttons below, reset whenever the run isn't showing.
	self.padSteer = 0
	self.boostHeld = false
	self.brakeHeld = false

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
	menu.BackgroundTransparency = 0 -- opaque: the world is not the menu's backdrop (§6)
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

	-- SHOP-FLOOR layout (§6): the menu is opaque — the world is NOT the
	-- backdrop (a live scene behind the merch buries it, and the DLC
	-- preview belongs in a framed window, not the whole screen). Three
	-- permanent zones: left GARAGE rail (the shop is zero clicks away —
	-- conversion needs the merch always visible + a try-before-you-buy
	-- preview), center poster column (title / PLAY / dash / seed /
	-- track / best), right LEADERBOARD rail. The
	-- missions card rides the bottom edge permanently — today's quests
	-- are part of the poster, not a pop-up.

	local function deckPanel(name: string, w: number, h: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = C_PANEL
		f.BackgroundTransparency = 0
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Position = UDim2.new(0.5, 0, 1, -42)
		f.Size = UDim2.fromOffset(w, h)
		f.Visible = false
		f.Parent = menu
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = C_DIM
		s.Thickness = 1
		s.Transparency = 0.5
		s.Parent = f
		return f
	end

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

	local menuCol = Instance.new("Frame")
	menuCol.Name = "Hero"
	menuCol.BackgroundTransparency = 1
	menuCol.Size = UDim2.fromOffset(560, 500) -- poster column: title, PLAY, run controls, best
	menuCol.Position = UDim2.fromScale(0.5, 0.44)
	menuCol.AnchorPoint = Vector2.new(0.5, 0.5)
	menuCol.Parent = menu
	vlist(menuCol, 8)

	local title = label(menuCol, spaced("ROBALL3D"), 72, F_HERO, C_WHITE, 1)
	local tgrad = Instance.new("UIGradient")
	tgrad.Color = ColorSequence.new(C_CYAN, C_PINK)
	tgrad.Rotation = 90
	tgrad.Parent = title

	label(menuCol, "roll forever · don't fall", 18, F_DATA, C_DIM, 2)

	-- Horizon rule: the poster's only ornament — a hairline sunset line
	-- under the tagline, fading to nothing at both ends.
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = C_WHITE
	rule.BorderSizePixel = 0
	rule.Size = UDim2.fromOffset(280, 2)
	rule.LayoutOrder = 3
	rule.Parent = menuCol
	local ruleGrad = Instance.new("UIGradient")
	ruleGrad.Color = ColorSequence.new(C_CYAN, C_PINK)
	ruleGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ruleGrad.Parent = rule
	self.ruleGrad = ruleGrad -- §2: pulseMenu dips the mid keypoint on the beat

	-- Menu scope strip (MENU.md §8): a second, thinner spectrum trace
	-- parked under the horizon rule — the poster's heartbeat monitor
	-- while the menu idles. Child of `rule`, NOT menuCol: a Frame child
	-- doesn't ride menuCol's UIListLayout, so it never takes a slot.
	-- menuScope() paints it with setWave's write-gated discipline.
	local mScope = Instance.new("Frame")
	mScope.Name = "MenuScope"
	mScope.AnchorPoint = Vector2.new(0.5, 0)
	mScope.Position = UDim2.new(0.5, 0, 0, 10)
	mScope.Size = UDim2.fromOffset(rule.Size.X.Offset, Config.Menu.MenuSpecH)
	mScope.BackgroundTransparency = 1
	mScope.Parent = rule
	self.menuWaveSegs = {}
	self._menuWaveCache = {}
	local menuStep = rule.Size.X.Offset / Config.Menu.MenuSpecBars
	for i = 1, Config.Menu.MenuSpecBars do
		local s = Instance.new("Frame")
		s.AnchorPoint = Vector2.new(0, 1)
		s.Position = UDim2.new(0, math.floor((i - 1) * menuStep + 0.5), 1, 0)
		s.Size = UDim2.fromOffset(3, 2)
		s.BackgroundColor3 = C_CYAN
		s.BorderSizePixel = 0
		s.Parent = mScope
		self.menuWaveSegs[i] = s
	end

	label(menuCol, "", 8, F_DATA, C_DIM, 4)

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
	play.LayoutOrder = 5
	play.Parent = menuCol
	local playScale = Instance.new("UIScale") -- MENU.md §2: the poster's beat swell rides this
	playScale.Name = "PulseScale"
	playScale.Scale = 1
	playScale.Parent = play
	self.playScale = playScale
	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(0, 12)
	playCorner.Parent = play
	local playGrad = Instance.new("UIGradient")
	playGrad.Rotation = 90
	playGrad.Color = ColorSequence.new(C_PINK:Lerp(C_WHITE, 0.18), C_PINK:Lerp(Color3.fromRGB(90, 0, 60), 0.25))
	playGrad.Parent = play
	play.Selectable = true -- gamepad: GuiService.SelectedObject target
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
	self.playBtn = play
	wireTick(play)

	self.playHint = label(menuCol, "press ENTER / R to roll", 13, F_DATA, C_DIM, 6)
	self.playHint.TextTransparency = 0.25

	-- DASH button (§4): its own bordered chip right under PLAY — cycles
	-- keys / double-tap; the server mirrors + saves the pick, so
	-- this button IS the whole pref.
	local dash = Instance.new("TextButton")
	dash.Name = "DashToggle"
	dash.Selectable = true -- reachable on the gamepad menu cursor
	dash.BackgroundColor3 = C_BG
	dash.BackgroundTransparency = 0.3
	dash.AutoButtonColor = false
	dash.Font = F_DATA
	dash.TextSize = 15
	dash.TextColor3 = C_GOLD
	dash.Text = "DASH STYLE"
	dash.Size = UDim2.fromOffset(340, 34)
	dash.LayoutOrder = 7
	dash.Parent = menuCol
	local dashCorner = Instance.new("UICorner")
	dashCorner.CornerRadius = UDim.new(0, 8)
	dashCorner.Parent = dash
	local dashStroke = Instance.new("UIStroke")
	dashStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dashStroke.Color = C_GOLD
	dashStroke.Thickness = 1
	dashStroke.Transparency = 0.4
	dashStroke.Parent = dash
	dash.MouseEnter:Connect(function()
		dash.TextColor3 = C_CYAN
		dashStroke.Color = C_CYAN
	end)
	dash.MouseLeave:Connect(function()
		dash.TextColor3 = C_GOLD
		dashStroke.Color = C_GOLD
	end)
	self.dashToggle = dash
	wireTick(dash)

	-- SEED row: empty means "daily" — the placeholder IS the default, no
	-- chip to flip; typed text seeds the map (keywords stay live, §14).
	local seedRow = Instance.new("Frame")
	seedRow.Name = "SeedRow"
	seedRow.BackgroundTransparency = 1
	seedRow.Size = UDim2.fromOffset(340, 32)
	seedRow.LayoutOrder = 8
	seedRow.Parent = menuCol

	local sl = Instance.new("TextLabel")
	sl.BackgroundTransparency = 1
	sl.Font = F_DATA
	sl.TextSize = 12
	sl.TextColor3 = C_DIM
	sl.Text = "SEED"
	sl.TextXAlignment = Enum.TextXAlignment.Left
	sl.Position = UDim2.fromOffset(2, 3)
	sl.Size = UDim2.fromOffset(50, 26)
	sl.Parent = seedRow

	local seedBox = Instance.new("TextBox")
	seedBox.Name = "SeedBox"
	seedBox.BackgroundColor3 = C_BG
	seedBox.BackgroundTransparency = 0.3
	seedBox.BorderSizePixel = 0
	seedBox.Font = F_DATA
	seedBox.TextSize = 16
	seedBox.TextColor3 = C_PINK
	seedBox.PlaceholderText = "daily #" .. Daily.seed() -- today's shared seed, readable at the launch point
	seedBox.PlaceholderColor3 = C_DIM
	seedBox.Text = "" -- blank = today's shared seed; anything typed is a seeded run
	seedBox.Position = UDim2.fromOffset(60, 0)
	seedBox.Size = UDim2.fromOffset(278, 32)
	seedBox.ClearTextOnFocus = false
	seedBox.Selectable = true -- console: A focuses the box, platform OSK types the seed
	local seedStroke = Instance.new("UIStroke")
	seedStroke.Color = C_DIM
	seedStroke.Transparency = 0.5
	seedStroke.Parent = seedBox
	seedBox.Parent = seedRow
	self.seedBox = seedBox
	-- §5: the seed box is the menu's one text field — keyboard players
	-- "hover" it by focusing, so focus lands the tick.
	seedBox.Focused:Connect(function()
		Sfx.uiTick("hover")
	end)

	-- TRACK cycler (AUDIO.md §3): the run's song, picked like an equip —
	-- run-scoped, so it rides the hero column, not the garage.
	local trkRow = Instance.new("Frame")
	trkRow.Name = "TrackRow"
	trkRow.BackgroundTransparency = 1
	trkRow.Size = UDim2.fromOffset(340, 30)
	trkRow.LayoutOrder = 9
	trkRow.Parent = menuCol

	local trkLabel = Instance.new("TextLabel")
	trkLabel.BackgroundTransparency = 1
	trkLabel.Font = F_DATA
	trkLabel.TextSize = 12
	trkLabel.TextColor3 = C_DIM
	trkLabel.TextXAlignment = Enum.TextXAlignment.Left
	trkLabel.Text = "TRACK"
	trkLabel.Position = UDim2.fromOffset(2, 2)
	trkLabel.Size = UDim2.fromOffset(56, 26)
	trkLabel.Parent = trkRow

	local trkName = Instance.new("TextButton")
	trkName.Name = "TrackName"
	trkName.Selectable = true -- gamepad cursor cycles the track pick
	trkName.BackgroundTransparency = 1
	trkName.AutoButtonColor = false
	trkName.Font = F_DATA
	trkName.TextSize = 15
	trkName.TextColor3 = C_WHITE
	trkName.Text = "RANDOM"
	trkName.Position = UDim2.fromOffset(92, 0)
	trkName.Size = UDim2.fromOffset(160, 30)
	trkName.TextXAlignment = Enum.TextXAlignment.Center
	trkName.Parent = trkRow
	self.trackName = trkName
	-- §4 spring cycler: the arrows move the spring's target; the name
	-- rides the residual so each cycle kicks ~JacketPx then re-seats.
	self._trkSpring = { pos = 0, vel = 0, target = 0 }
	self._trkPos = trkName.Position
	self._trkKick = 0
	wireTick(trkName)

	local trkLeft = arrowButton(trkRow, "<", 64, 2)
	trkLeft.Name = "TrackPrev"
	trkLeft.Selectable = true
	trkLeft.MouseButton1Click:Connect(function()
		self._trkSpring.target -= 1
		if self.onTrackCycle then
			self.onTrackCycle(-1)
		end
	end)
	wireTick(trkLeft)
	local trkRight = arrowButton(trkRow, ">", 258, 2)
	trkRight.Name = "TrackNext"
	trkRight.Selectable = true
	trkRight.MouseButton1Click:Connect(function()
		self._trkSpring.target += 1
		if self.onTrackCycle then
			self.onTrackCycle(1)
		end
	end)
	wireTick(trkRight)

	self.bestLabel = label(menuCol, "BEST 0", 18, F_DATA, C_CYAN, 10)

	-- Missions card (§14): today's three seeded missions — ✓ gold when
	-- done, ◇ dim while open; the bank quest shows today's running
	-- total and the footer counts the award tally. Always visible.
	local missions = deckPanel("MissionsPage", 420, 132)
	missions.Visible = true

	label(missions, "TODAY'S MISSIONS", 12, F_DATA, C_DIM, 0).Position = UDim2.fromOffset(0, 8)
	self.questLines = {}
	for i = 1, 3 do
		local ql = label(missions, "", 14, F_DATA, C_DIM, 0)
		ql.Position = UDim2.fromOffset(0, 32 + (i - 1) * 21)
		self.questLines[i] = ql
	end
	self.achLine = label(missions, "", 12, F_DATA, C_GOLD, 0)
	self.achLine.Position = UDim2.fromOffset(0, 102)

	-- Bottom caption: just the keymap — every other control is a visible
	-- rail or a hero button now.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, -8)
	strip.Size = UDim2.new(1, -32, 0, 22)
	strip.Parent = menu
	self.dashHint = label(strip, "", 12, F_DATA, C_DIM, 0)
	self.dashHint.TextTransparency = 0.3

	self.dashToggle.MouseButton1Click:Connect(function()
		if self.onDashMode then
			self.onDashMode()
		end
	end)

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
	-- Right rail, always on: the board is the retention ad — your rank
	-- sits next to PLAY on every menu visit, no click needed.
	board.AnchorPoint = Vector2.new(1, 0.5)
	board.Position = UDim2.fromScale(0.965, 0.5)
	board.Size = UDim2.fromOffset(340, 78 + TOP_N * 25 + RECENT_H)
	board.BackgroundColor3 = C_PANEL
	board.BackgroundTransparency = 0
	board.BorderSizePixel = 0
	board.Parent = menu
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 10)
	boardCorner.Parent = board

	self.boardMode = "daily" :: string
	self.onBoardTab = nil :: ((board: string) -> ())?
	local function boardTab(text, x)
		local b = Instance.new("TextButton")
		b.Selectable = true -- gamepad cursor can reach the board tabs
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DISPLAY
		b.TextSize = 15
		b.Text = text
		b.Position = UDim2.fromOffset(x, 10)
		b.Size = UDim2.fromOffset(96, 26)
		b.Parent = board
		wireTick(b)
		return b
	end
	-- DAILY leads: the menu's default run is today's shared seed, so its
	-- board is the one that answers "how am I doing" at a glance.
	self.tabDaily = boardTab("DAILY", 54)
	self.tabDaily.Name = "TabDaily"
	self.tabTop = boardTab("TOP", 170)
	self.tabTop.Name = "TabTop"
	self.tabDaily.MouseButton1Click:Connect(function()
		self:setBoard("daily")
	end)
	self.tabTop.MouseButton1Click:Connect(function()
		self:setBoard("top")
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

	-- Paint the default selection (onBoardTab is still nil here, so this
	-- only recolors — the real fetch happens via refreshBoard in Main).
	self:setBoard("daily")

	-- Friends filter (§14): rides every board — the fetched top-N rows
	-- shrink to your friends, keeping their REAL rank numbers. The id set
	-- arrives via onFriendsReady (Main lazy-loads GetFriendsAsync).
	self.friendsOnly = false
	self.friendSet = nil :: { [number]: boolean }?
	self.friendsErr = false -- set when the friends list itself failed
	self.onFriendsReady = nil :: (() -> ())?
	local friendsBtn = Instance.new("TextButton")
	friendsBtn.Name = "FriendsBtn"
	friendsBtn.Selectable = true -- gamepad cursor reaches the board filter
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
				self.dailyInfo.Text = dailyText()
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
	-- Neon shop (DESIGN.md §18): the left rail, always on — conversion
	-- needs the merch zero clicks away. Tabbed STYLE (equip cyclers),
	-- PACKS (bundle gamepasses), BANK (gem packs + 2X pass), AUDIO
	-- (mixer). The PREVIEW window at the bottom dresses the BROWSED
	-- items in a ViewportFrame diorama — unowned merch previews too,
	-- that's the try-before-you-buy lever.
	local garage = Instance.new("Frame")
	garage.Name = "Garage"
	garage.AnchorPoint = Vector2.new(0, 0.5)
	garage.Position = UDim2.fromScale(0.035, 0.5)
	garage.Size = UDim2.fromOffset(340, 640)
	garage.BackgroundColor3 = C_PANEL
	garage.BackgroundTransparency = 0
	garage.BorderSizePixel = 0
	garage.Parent = menu
	local gcorner = Instance.new("UICorner")
	gcorner.CornerRadius = UDim.new(0, 10)
	gcorner.Parent = garage

	label(garage, "GARAGE", 20, F_DISPLAY, C_PINK, 0).Position = UDim2.fromOffset(0, 8)

	-- Bank balance in the header: spendable gems always in view, so the
	-- ◊ prices on unowned items read against it at a glance.
	local bal = Instance.new("TextLabel")
	bal.BackgroundTransparency = 1
	bal.Font = F_DATA
	bal.TextSize = 13
	bal.TextColor3 = C_GOLD
	bal.TextXAlignment = Enum.TextXAlignment.Right
	bal.Position = UDim2.new(1, -140, 0, 12)
	bal.Size = UDim2.fromOffset(126, 20)
	bal.Text = "◊ 0"
	bal.Parent = garage
	self.bankLabel = bal

	local gTabs: { [string]: TextButton } = {}
	local gPages: { [string]: Frame } = {}
	for i, name in ipairs({ "STYLE", "PACKS", "BANK", "AUDIO" }) do
		local b = Instance.new("TextButton")
		b.Name = "Tab" .. name
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Font = F_DISPLAY
		b.TextSize = 12
		b.Text = name
		b.Position = UDim2.fromOffset(14 + (i - 1) * 78, 40)
		b.Size = UDim2.fromOffset(72, 24)
		b.Parent = garage
		gTabs[name] = b

		local pg = Instance.new("Frame")
		pg.Name = "Page" .. name
		pg.BackgroundTransparency = 1
		pg.Position = UDim2.fromOffset(0, 72)
		pg.Size = UDim2.new(1, 0, 1, -262) -- bottom 190px is the preview window
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
		wireTick(b)
	end
	setGarageTab("STYLE")

	-- PREVIEW (§18): the try-before-you-buy mannequin — a ViewportFrame
	-- diorama CosmeticFx dresses from the BROWSED items (skin rings,
	-- trail, sun, world motif, gem, death shards), so the merch sells
	-- itself before the purchase. A Gui overlay re-paints the screen
	-- filter effect inside the window's bounds.
	local pvLabel = label(garage, "PREVIEW", 11, F_DATA, C_DIM, 0)
	pvLabel.AnchorPoint = Vector2.new(0, 1)
	pvLabel.Position = UDim2.new(0, 0, 1, -176)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"
	vp.BackgroundColor3 = C_BG
	vp.BorderSizePixel = 0
	vp.AnchorPoint = Vector2.new(0, 1)
	vp.Position = UDim2.new(0, 12, 1, -14)
	vp.Size = UDim2.new(1, -24, 0, 150)
	vp.Ambient = Color3.fromRGB(160, 145, 200)
	vp.LightColor = Color3.fromRGB(255, 245, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.35)
	vp.Parent = garage
	local vpc = Instance.new("UICorner")
	vpc.CornerRadius = UDim.new(0, 8)
	vpc.Parent = vp
	local vps = Instance.new("UIStroke")
	vps.Color = C_DIM
	vps.Thickness = 1
	vps.Transparency = 0.4
	vps.Parent = vp
	self.previewView = vp
	local fov = Instance.new("Frame")
	fov.Name = "FilterOverlay"
	fov.BackgroundTransparency = 1
	fov.Size = UDim2.fromScale(1, 1)
	fov.ZIndex = 5
	fov.Parent = vp
	self.previewFilterFrame = fov

	-- Slot rows: "SKIN   < ITEM NAME  •>". Cycling browses the full
	-- catalog; the name itself is the buy button for priced-but-unowned
	-- items. The chip pinned to the name's right edge wears the item's
	-- own color — a cyan ring means it's the look on the ball right now.
	-- Name tint reads state at a glance: white = owned, gold = ◊price
	-- (à-la-carte buy), dim = pack-locked.
	self.slotItem = {}
	self.slotSwatch = {}
	self.slotSwatchStroke = {}
	self.slotTint = {}
	-- §4 (stretch): the equip rows are persistent frames — setGarage only
	-- rewrites Text — so each name button keeps a cycler spring exactly
	-- like the TRACK row.
	self._slotSpring = {}
	self._slotPos = {}
	self._slotKick = {}
	local pageStyle = gPages.STYLE
	local ROW_Y0 = 4
	local ROW_PITCH = 26 -- 8 slots + the color lab have to fit the page
	for i, slot in ipairs(Cosmetics.Slots) do
		local y = ROW_Y0 + (i - 1) * ROW_PITCH
		local slotLabel = Instance.new("TextLabel")
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = F_DATA
		slotLabel.TextSize = 12
		slotLabel.TextColor3 = C_DIM
		slotLabel.TextXAlignment = Enum.TextXAlignment.Left
		slotLabel.Text = Cosmetics.SlotName[slot]
		slotLabel.Position = UDim2.fromOffset(14, y)
		slotLabel.Size = UDim2.fromOffset(56, 24)
		slotLabel.Parent = pageStyle

		local nm = Instance.new("TextButton")
		nm.BackgroundTransparency = 1
		nm.AutoButtonColor = false
		nm.Font = F_DATA
		nm.TextSize = 15
		nm.TextColor3 = C_WHITE
		nm.Text = "—"
		nm.Position = UDim2.fromOffset(102, y)
		nm.Size = UDim2.fromOffset(182, 24)
		nm.Parent = pageStyle
		self.slotItem[slot] = nm
		self._slotSpring[slot] = { pos = 0, vel = 0, target = 0 }
		self._slotPos[slot] = nm.Position
		self._slotKick[slot] = 0
		local sw = Instance.new("Frame")
		sw.Name = "Swatch"
		sw.AnchorPoint = Vector2.new(1, 0.5)
		sw.Position = UDim2.new(1, -6, 0.5, 0)
		sw.Size = UDim2.fromOffset(9, 9)
		sw.BorderSizePixel = 0
		sw.BackgroundColor3 = C_DIM
		sw.BackgroundTransparency = 0.65
		sw.Parent = nm
		local swc = Instance.new("UICorner")
		swc.CornerRadius = UDim.new(1, 0)
		swc.Parent = sw
		local sws = Instance.new("UIStroke")
		sws.Color = C_DIM
		sws.Thickness = 1
		sws.Transparency = 0.45
		sws.Parent = sw
		self.slotSwatch[slot] = sw
		self.slotSwatchStroke[slot] = sws
		-- Hover read: the name flares pink (it's clickable owned or
		-- locked) and the arrows too; leave re-seats the state tint.
		nm.MouseEnter:Connect(function()
			nm.TextColor3 = C_PINK
		end)
		nm.MouseLeave:Connect(function()
			nm.TextColor3 = self.slotTint[slot] or C_WHITE
		end)
		nm.MouseButton1Click:Connect(function()
			if self.onItemSlot then
				self.onItemSlot(slot)
			end
		end)

		local left = arrowButton(pageStyle, "<", 72, y)
		left.MouseButton1Click:Connect(function()
			self._slotSpring[slot].target -= 1
			if self.onEquipCycle then
				self.onEquipCycle(slot, -1)
			end
		end)
		local right = arrowButton(pageStyle, ">", 288, y)
		right.MouseButton1Click:Connect(function()
			self._slotSpring[slot].target += 1
			if self.onEquipCycle then
				self.onEquipCycle(slot, 1)
			end
		end)
		for _, a in ipairs({ left, right }) do
			a.MouseEnter:Connect(function()
				a.TextColor3 = C_PINK
			end)
			a.MouseLeave:Connect(function()
				a.TextColor3 = C_CYAN
			end)
		end
	end

	-- RANDOM chip: slot-machines the whole browse set — Main rolls a
	-- fresh index per slot a few times so the preview spins before it
	-- settles; owned picks equip exactly like cycling does.
	local rndY = ROW_Y0 + #Cosmetics.Slots * ROW_PITCH + 8
	local rnd = Instance.new("TextButton")
	rnd.Name = "Randomize"
	rnd.BackgroundColor3 = C_BG
	rnd.AutoButtonColor = false
	rnd.Font = F_DATA
	rnd.TextSize = 13
	rnd.TextColor3 = C_PINK
	rnd.Text = "RANDOM"
	rnd.Position = UDim2.fromOffset(102, rndY)
	rnd.Size = UDim2.fromOffset(182, 22)
	rnd.Parent = pageStyle
	local rndCorner = Instance.new("UICorner")
	rndCorner.CornerRadius = UDim.new(0, 6)
	rndCorner.Parent = rnd
	local rndStroke = Instance.new("UIStroke")
	rndStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rndStroke.Color = C_DIM
	rndStroke.Thickness = 1
	rndStroke.Parent = rnd
	rnd.MouseEnter:Connect(function()
		rnd.TextColor3 = C_CYAN
		rndStroke.Color = C_CYAN
	end)
	rnd.MouseLeave:Connect(function()
		rnd.TextColor3 = C_PINK
		rndStroke.Color = C_DIM
	end)
	rnd.MouseButton1Click:Connect(function()
		if self.onRandomize then
			self.onRandomize()
		end
	end)

	local browseHint =
		label(pageStyle, "cycle equips owned · click a locked item to open its pack", 10, F_DATA, C_DIM, 0)
	browseHint.Position = UDim2.fromOffset(0, rndY + 30)
	browseHint.TextTransparency = 0.35

	-- COLOR LAB (§18): three hue sliders feeding the customA/B/C item
	-- params (RING A, RING B, ACCENT = trail + gem fx). The whole block
	-- hides until the player owns a lab item (setGarage state.lab.visible);
	-- writes go out on drag release via self.onHues — the server re-gates
	-- ownership and clamps the legal band, so the UI only ever suggests.
	local H = Config.CustomHue
	self.labVals = { a = H.Defaults.a, b = H.Defaults.b, c = H.Defaults.c }
	self.labRows = {}
	local lab = Instance.new("Frame")
	lab.Name = "ColorLab"
	lab.BackgroundTransparency = 1
	lab.Position = UDim2.fromOffset(0, rndY + 56)
	lab.Size = UDim2.new(1, 0, 0, 100)
	lab.Visible = false
	lab.Parent = pageStyle
	self.labFrame = lab
	label(lab, "COLOR LAB", 12, F_DISPLAY, C_GOLD, 0).TextXAlignment = Enum.TextXAlignment.Left

	local function labColor(v: number): Color3
		return Color3.fromHSV(H.Min + (H.Max - H.Min) * v, H.Sat, H.Value)
	end
	-- Spectrum strip for the track: keypoints march through the legal band
	-- only, so even the picker background can't display the red seam.
	local gradKeys = {}
	for i = 0, 8 do
		gradKeys[i + 1] = ColorSequenceKeypoint.new(i / 8, labColor(i / 8))
	end
	for i, ch in ipairs({ { k = "a", name = "RING A" }, { k = "b", name = "RING B" }, { k = "c", name = "ACCENT" } }) do
		local y = 22 + (i - 1) * 26
		local nl = label(lab, ch.name, 10, F_DATA, C_DIM)
		nl.TextXAlignment = Enum.TextXAlignment.Left
		nl.Position = UDim2.fromOffset(14, y)
		nl.Size = UDim2.fromOffset(52, 19)

		local track = Instance.new("Frame")
		track.BackgroundColor3 = C_BG
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(70, y + 4)
		track.Size = UDim2.fromOffset(180, 10)
		track.Parent = lab
		local tcorner = Instance.new("UICorner")
		tcorner.CornerRadius = UDim.new(0, 5)
		tcorner.Parent = track
		local trackGrad = Instance.new("UIGradient")
		trackGrad.Color = ColorSequence.new(gradKeys)
		trackGrad.Parent = track

		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.BackgroundColor3 = C_WHITE
		knob.BorderSizePixel = 0
		knob.Position = UDim2.fromScale(0.5, 0.5)
		knob.Size = UDim2.fromOffset(6, 16)
		knob.Parent = track
		local kcorner = Instance.new("UICorner")
		kcorner.CornerRadius = UDim.new(0, 3)
		kcorner.Parent = knob

		local swatch = Instance.new("Frame")
		swatch.BackgroundColor3 = labColor(0.5)
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromOffset(258, y + 2)
		swatch.Size = UDim2.fromOffset(26, 15)
		swatch.Parent = lab
		local scorner = Instance.new("UICorner")
		scorner.CornerRadius = UDim.new(0, 4)
		scorner.Parent = swatch

		self.labRows[ch.k] = { track = track, knob = knob, swatch = swatch }

		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Text = ""
		hit.Position = UDim2.fromOffset(70, y - 3)
		hit.Size = UDim2.fromOffset(180, 26)
		hit.Parent = lab

		local dragging = false
		local k = ch.k
		local function write(mx: number)
			local v = math.clamp((mx - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			self.labVals[k] = v
			knob.Position = UDim2.fromScale(v, 0.5)
			swatch.BackgroundColor3 = labColor(v)
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
				-- Slider fraction -> hue on the legal band; the server
				-- re-clamps anyway, this just keeps the roundtrip exact.
				local function hueOf(f: number): number
					return H.Min + (H.Max - H.Min) * f
				end
				if self.onHues then
					self.onHues({
						a = hueOf(self.labVals.a),
						b = hueOf(self.labVals.b),
						c = hueOf(self.labVals.c),
					})
				end
			end
		end)
	end

	-- Pack rows: name + pitch left, price button right. The page scrolls
	-- (14 packs can't fit one panel) and each row is an accordion — tap
	-- the text area to unfold the pack's REAL contents resolved from
	-- bundle.items (SLOT · ITEM NAME, tinted to the item's own color when
	-- it has a concrete one). One pack open at a time. Button state comes
	-- from setGarage: "R$49" enabled / "OWNED" / "SOON" dimmed.
	self.packBtn = {}
	self.packStroke = {}
	self.packEnabled = {}
	self.packRows = {}

	local function itemTint(it: any): Color3
		local c = it.color or it.ringA or it.colorA
		return if typeof(c) == "Color3" then c else C_DIM
	end

	local openPack: Frame? = nil
	local lastPackNotice: string? = nil
	-- Pack-open notifications drive the diorama preview (§18): an open
	-- pack dresses the preview ball/scene in ITS contents — the try-on
	-- is the pitch. `inner` suppresses the close-other-pass notify so a
	-- pack swap doesn't flash the browse set between packs.
	local function setPackOpen(row: Frame, open: boolean, inner: boolean?)
		local contents = row:FindFirstChild("Contents")
		if not contents then
			return
		end
		if open then
			if openPack and openPack ~= row then
				setPackOpen(openPack, false, true)
			end
			openPack = row
			contents.Visible = true
			row.Size = UDim2.new(1, 0, 0, 40 + row:GetAttribute("ItemCount") * 15)
		else
			if openPack == row then
				openPack = nil
			end
			contents.Visible = false
			row.Size = UDim2.new(1, 0, 0, 36)
		end
		if not inner then
			local id = openPack and openPack:GetAttribute("PackId") :: string?
			if id ~= lastPackNotice then
				lastPackNotice = id
				if self.onPackOpen then
					self.onPackOpen(id)
				end
			end
		end
	end
	local function packRow(
		parent: Instance,
		id: string,
		name: string,
		desc: string,
		y: number?,
		order: number?,
		items: { string }?
	)
		local row = Instance.new("Frame")
		row.Name = "Pack_" .. id
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 36)
		row.LayoutOrder = order or 0
		row:SetAttribute("ItemCount", #(items or {}))
		row:SetAttribute("PackId", id)
		if y then
			row.Position = UDim2.fromOffset(0, y)
		end
		row.Parent = parent
		self.packRows[id] = row

		local nl = Instance.new("TextLabel")
		nl.BackgroundTransparency = 1
		nl.Font = F_DATA
		nl.TextSize = 14
		nl.TextColor3 = C_WHITE
		nl.TextXAlignment = Enum.TextXAlignment.Left
		nl.Text = name
		nl.Position = UDim2.fromOffset(14, 2)
		nl.Size = UDim2.fromOffset(210, 18)
		nl.Parent = row

		local dl = Instance.new("TextLabel")
		dl.BackgroundTransparency = 1
		dl.Font = F_DATA
		dl.TextSize = 10
		dl.TextColor3 = C_DIM
		dl.TextXAlignment = Enum.TextXAlignment.Left
		dl.TextTruncate = Enum.TextTruncate.AtEnd
		dl.Text = desc
		dl.Position = UDim2.fromOffset(14, 19)
		dl.Size = UDim2.fromOffset(210, 14)
		dl.Parent = row

		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = C_BG
		btn.BackgroundTransparency = 0
		btn.AutoButtonColor = false
		btn.Font = F_DATA
		btn.TextSize = 14
		btn.TextColor3 = C_PINK
		btn.Text = "R$?"
		btn.Position = UDim2.fromOffset(232, 2)
		btn.Size = UDim2.fromOffset(84, 32)
		btn.Parent = row
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

		if items then
			local contents = Instance.new("Frame")
			contents.Name = "Contents"
			contents.Visible = false
			contents.BackgroundTransparency = 1
			contents.Position = UDim2.fromOffset(0, 37)
			contents.Size = UDim2.new(1, 0, 0, #items * 15)
			contents.Parent = row
			for j, iid in ipairs(items) do
				local it = Cosmetics.item(iid)
				if it then
					-- "buy just this": the à-la-carte escape hatch inside
					-- the bundle pitch — a locked row click lands on the
					-- pack, and the gem price still sells the single.
					local il = Instance.new("TextButton")
					il.BackgroundTransparency = 1
					il.AutoButtonColor = false
					il.Font = F_DATA
					il.TextSize = 10
					il.TextColor3 = itemTint(it)
					il.TextXAlignment = Enum.TextXAlignment.Left
					il.Position = UDim2.fromOffset(24, (j - 1) * 15)
					il.Size = UDim2.fromOffset(290, 15)
					il.Text = string.format(
						"%-8s %s%s",
						Cosmetics.SlotName[it.slot],
						it.name,
						if it.gemPrice then string.format("  ◊%d", it.gemPrice) else ""
					)
					il.Parent = contents
					il.MouseButton1Click:Connect(function()
						if self.onBuyItem then
							self.onBuyItem(iid)
						end
					end)
				end
			end

			local hit = Instance.new("TextButton")
			hit.BackgroundTransparency = 1
			hit.AutoButtonColor = false
			hit.Text = ""
			hit.Position = UDim2.fromOffset(0, 0)
			hit.Size = UDim2.fromOffset(226, 36)
			hit.Parent = row
			hit.MouseButton1Click:Connect(function()
				setPackOpen(row, openPack ~= row)
			end)
		end
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
	local pagePacks = gPages.PACKS
	local packHint = label(pagePacks, "tap a pack · preview its full set", 10, F_DATA, C_DIM, 0)
	packHint.Position = UDim2.fromOffset(0, 2)
	packHint.TextTransparency = 0.35
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PackScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 20)
	scroll.Size = UDim2.new(1, 0, 1, -20)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C_CYAN
	scroll.ScrollBarImageTransparency = 0.45
	scroll.Parent = pagePacks
	vlist(scroll, 2)
	for i, b in ipairs(Cosmetics.Bundles) do
		local desc = if b.id == Config.Monetization.Seasonal.Bundle then seasonalDesc(b.desc) else b.desc
		packRow(scroll, b.id, b.name, desc, nil, i, b.items)
	end

	-- Locked-item funnel (§18): clicking an unowned STYLE row lands the
	-- player on the bundle that unlocks it — PACKS opens, the accordion
	-- unfolds, the scroll snaps the row into view, and the buy chip
	-- flares cyan so the eye lands on the purchase.
	local packFlash = 0
	self._focusPack = function(id: string)
		local row = self.packRows[id]
		if not row then
			return
		end
		setGarageTab("PACKS")
		setPackOpen(row, true)
		-- Measure after the accordion relayout settles — opening one row
		-- can close another and shift every offset below it.
		task.delay(0.1, function()
			scroll.CanvasPosition = Vector2.new(
				0,
				math.max(0, scroll.CanvasPosition.Y + row.AbsolutePosition.Y - scroll.AbsolutePosition.Y - 6)
			)
		end)
		packFlash += 1
		local tk = packFlash
		local st = self.packStroke[id]
		task.spawn(function()
			for i = 1, 6 do
				if packFlash ~= tk or not st or not st.Parent then
					return
				end
				st.Color = if i % 2 == 1 then C_CYAN else C_PINK
				task.wait(0.12)
			end
			st.Color = if self.packEnabled[id] then C_PINK else C_DIM
		end)
	end

	--=========== BANK (§18 P2) ===========--
	-- The economy page, not just a checkout: hero balance card (what you
	-- hold), top-up cards (buy more), a TODAY'S FLOW ledger (what today
	-- already paid + what's still on the table), then the 2X pass.
	-- Everything degrades to SOON until the dashboard ids exist — the
	-- buttons only arm via setGarage.
	local pageBank = gPages.BANK
	-- Section header: dim machine-voice caption + a hairline rule running
	-- to the panel edge — the vaporwave section mark used across the page.
	local function caption(text: string, y: number)
		local c = label(pageBank, text, 10, F_DATA, C_DIM, 0)
		c.Position = UDim2.fromOffset(14, y)
		c.Size = UDim2.fromOffset(120, 14)
		c.TextXAlignment = Enum.TextXAlignment.Left
		c.TextTransparency = 0.35
		local hairline = Instance.new("Frame")
		hairline.BackgroundColor3 = C_DIM
		hairline.BackgroundTransparency = 0.55
		hairline.BorderSizePixel = 0
		hairline.AnchorPoint = Vector2.new(0, 0.5)
		hairline.Position = UDim2.fromOffset(110, y + 6)
		hairline.Size = UDim2.fromOffset(216, 1)
		hairline.Parent = pageBank
		return c
	end

	label(pageBank, "BANK", 14, F_DISPLAY, C_DIM, 0).Position = UDim2.fromOffset(0, 4)

	-- Balance hero: gold card, the gem icon, and the number the whole
	-- page is about — with today's inflow + the streak on the right for
	-- context. A diagonal sheen keeps the card from reading flat. The
	-- header's small ◊ stays (prices read against it everywhere).
	local balCard = Instance.new("Frame")
	balCard.BackgroundColor3 = C_BG
	balCard.Position = UDim2.fromOffset(14, 26)
	balCard.Size = UDim2.fromOffset(312, 58)
	balCard.Parent = pageBank
	local balCorner = Instance.new("UICorner")
	balCorner.CornerRadius = UDim.new(0, 8)
	balCorner.Parent = balCard
	local balSheen = Instance.new("UIGradient")
	balSheen.Rotation = 135
	balSheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_BG:Lerp(C_GOLD, 0.16)),
		ColorSequenceKeypoint.new(0.45, C_BG),
		ColorSequenceKeypoint.new(1, C_BG),
	})
	balSheen.Parent = balCard
	local balStroke = Instance.new("UIStroke")
	balStroke.Color = C_GOLD
	balStroke.Thickness = 1.5
	balStroke.Parent = balCard

	local heroGem = gemIcon(balCard, 30, C_GOLD)
	heroGem.Position = UDim2.fromOffset(14, 14)
	local hero = Instance.new("TextLabel")
	hero.BackgroundTransparency = 1
	hero.Font = F_DATA
	hero.TextSize = 30
	hero.TextColor3 = C_GOLD
	hero.TextXAlignment = Enum.TextXAlignment.Left
	hero.Position = UDim2.fromOffset(52, 0)
	hero.Size = UDim2.fromOffset(120, 58)
	hero.Text = "0"
	hero.Parent = balCard
	self.bankHero = hero
	local bankToday = label(balCard, "", 11, F_DATA, C_DIM, 0)
	bankToday.Position = UDim2.fromOffset(150, 11)
	bankToday.Size = UDim2.fromOffset(152, 16)
	bankToday.TextXAlignment = Enum.TextXAlignment.Right
	local bankStreak = label(balCard, "", 11, F_DATA, C_GOLD, 0)
	bankStreak.Position = UDim2.fromOffset(150, 30)
	bankStreak.Size = UDim2.fromOffset(152, 16)
	bankStreak.TextXAlignment = Enum.TextXAlignment.Right
	self.bankToday = bankToday
	self.bankStreak = bankStreak

	-- Gem packs: three equal cards — gem icon on top, amount big, price
	-- small. Enabled state arrives via setGarage's gemPacks list (SOON
	-- until product ids exist). The vault carries the BEST tag — most
	-- gems per R$ of the three.
	caption("TOP-UP", 94)
	self.gemPackBtn = {}
	self.gemPackStroke = {}
	self.gemPackEnabled = {}
	self.gemPackAmt = {}
	self.gemPackPrice = {}
	for i, key in ipairs(Config.Monetization.ProductOrder) do
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C_BG
		b.BackgroundTransparency = 0
		b.AutoButtonColor = false
		b.Text = ""
		b.Position = UDim2.fromOffset(14 + (i - 1) * 108, 110)
		b.Size = UDim2.fromOffset(96, 64)
		b.Parent = pageBank
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = C_GOLD
		stroke.Thickness = 1.5
		stroke.Parent = b
		local packGem = gemIcon(b, 16, C_GOLD)
		packGem.Position = UDim2.fromOffset(40, 8)
		local amt = Instance.new("TextLabel")
		amt.BackgroundTransparency = 1
		amt.Font = F_DATA
		amt.TextSize = 15
		amt.TextColor3 = C_GOLD
		amt.Text = "?"
		amt.Position = UDim2.fromOffset(0, 26)
		amt.Size = UDim2.new(1, 0, 0, 18)
		amt.Parent = b
		local prc = Instance.new("TextLabel")
		prc.BackgroundTransparency = 1
		prc.Font = F_DATA
		prc.TextSize = 10
		prc.TextColor3 = C_DIM
		prc.Text = "SOON"
		prc.Position = UDim2.fromOffset(0, 45)
		prc.Size = UDim2.new(1, 0, 0, 14)
		prc.Parent = b
		if i == #Config.Monetization.ProductOrder then
			local tag = Instance.new("TextLabel")
			tag.BackgroundTransparency = 1
			tag.Font = F_DATA
			tag.TextSize = 8
			tag.TextColor3 = C_CYAN
			tag.Text = "★ BEST"
			tag.Position = UDim2.fromOffset(0, -11)
			tag.Size = UDim2.new(1, 0, 0, 10)
			tag.Parent = b
		end
		self.gemPackBtn[key] = b
		self.gemPackStroke[key] = stroke
		self.gemPackAmt[key] = amt
		self.gemPackPrice[key] = prc
		b.MouseEnter:Connect(function()
			if self.gemPackEnabled[key] then
				stroke.Color = C_CYAN
			end
		end)
		b.MouseLeave:Connect(function()
			stroke.Color = self.gemPackEnabled[key] and C_GOLD or C_DIM
		end)
		b.MouseButton1Click:Connect(function()
			if self.gemPackEnabled[key] and self.onGemPack then
				self.onGemPack(key)
			end
		end)
	end

	-- TODAY'S FLOW: the ledger — what today already paid, what the open
	-- missions still owe, and what the next daily run's streak pays.
	-- Painted by _paintBankFlow from RoBallQuests + the streak attribute.
	caption("TODAY'S FLOW", 184)
	local ledger = Instance.new("Frame")
	ledger.BackgroundColor3 = C_BG
	ledger.Position = UDim2.fromOffset(14, 200)
	ledger.Size = UDim2.fromOffset(312, 56)
	ledger.Parent = pageBank
	local ledgerCorner = Instance.new("UICorner")
	ledgerCorner.CornerRadius = UDim.new(0, 6)
	ledgerCorner.Parent = ledger
	local ledgerStroke = Instance.new("UIStroke")
	ledgerStroke.Color = C_DIM
	ledgerStroke.Transparency = 0.55
	ledgerStroke.Thickness = 1
	ledgerStroke.Parent = ledger
	local function flowLine(y: number)
		local name = label(ledger, "", 11, F_DATA, C_DIM, 0)
		name.Position = UDim2.fromOffset(10, y)
		name.Size = UDim2.fromOffset(170, 15)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local amt = label(ledger, "", 11, F_DATA, C_GOLD, 0)
		amt.Position = UDim2.fromOffset(170, y)
		amt.Size = UDim2.fromOffset(132, 15)
		amt.TextXAlignment = Enum.TextXAlignment.Right
		return name, amt
	end
	self.flowBanked = { flowLine(4) }
	self.flowMissions = { flowLine(20) }
	self.flowStreak = { flowLine(36) }

	-- 2X BANK rides the pack-row machinery: Passes.bank2x is a gamepass like
	-- the bundles, so packBtn["bank2x"] + onBuy("bank2x") just works.
	packRow(pageBank, "bank2x", "2X BANK", "every gem banks double", 266)

	local hint = label(pageBank, "gems bank on pickup — they're never score", 11, F_DATA, C_DIM, 0)
	hint.Position = UDim2.fromOffset(0, 312)
	hint.TextTransparency = 0.3

	-- The streak only moves at run end — repaint the ledger when it does
	-- (setQuests covers the mission/banked lines on its own pushes).
	Players.LocalPlayer:GetAttributeChangedSignal("RoBallDailyStreak"):Connect(function()
		self:_paintBankFlow()
	end)

	--=========== AUDIO (AUDIO.md §7) ===========--
	-- Mixer page: one channel per row, stacked — the garage panel is too
	-- narrow for the old side-by-side pairs. Drag applies instantly;
	-- release persists through RoBallVol_<ch> -> profile.audio.
	local function sliderUnit(parent: Frame, ch: string, y: number)
		local name = label(parent, Config.Audio.Labels[ch], 11, F_DATA, C_DIM)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Size = UDim2.fromOffset(60, 24)
		name.Position = UDim2.fromOffset(14, y)

		local track = Instance.new("Frame")
		track.BackgroundColor3 = C_BG
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(82, y + 8)
		track.Size = UDim2.fromOffset(168, 8)
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
		pct.Position = UDim2.fromOffset(256, y)
		pct.Size = UDim2.fromOffset(42, 24)
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
		hit.Position = UDim2.fromOffset(76, y)
		hit.Size = UDim2.fromOffset(180, 24)
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
	local pageAudio = gPages.AUDIO
	label(pageAudio, "MIXER", 14, F_DISPLAY, C_DIM, 0).Position = UDim2.fromOffset(0, 6)
	for i, ch in ipairs(Config.Audio.Channels) do
		sliderUnit(pageAudio, ch, 34 + (i - 1) * 32)
	end
	local ahint = label(pageAudio, "drag to mix · release saves", 10, F_DATA, C_DIM, 0)
	ahint.Position = UDim2.fromOffset(0, 34 + #Config.Audio.Channels * 32 + 10)
	ahint.TextTransparency = 0.35

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

	-- Vaporwave hero digit (§12): the score wears the speedo's chrome —
	-- gradient band, neon rim, twin VHS ghosts, outrun slant. Ghosts are
	-- children of the digit so slant/visibility track it for free; Text
	-- syncs in setHud, the beat flare in setSpeedo.
	local scoreText = Instance.new("TextLabel")
	scoreText.BackgroundTransparency = 1
	scoreText.Font = F_DATA
	scoreText.TextSize = 52
	scoreText.TextColor3 = C_PINK
	scoreText.TextStrokeTransparency = 0.4
	scoreText.TextXAlignment = Enum.TextXAlignment.Right
	scoreText.Size = UDim2.new(1, 0, 0, 58)
	scoreText.Rotation = -4
	scoreText.Parent = hud
	self.scoreText = scoreText
	-- Chrome band: bright crown -> dark horizon line -> pale reflection.
	-- The pink TextColor3 multiplies through it — pink chrome, not a
	-- second color.
	local scoreGrad = Instance.new("UIGradient")
	scoreGrad.Rotation = 90
	scoreGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(255, 240, 255)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(70, 45, 115)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(235, 205, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 110, 200)),
	})
	scoreGrad.Parent = scoreText
	local scoreStroke = Instance.new("UIStroke")
	scoreStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	scoreStroke.Color = C_PINK
	scoreStroke.Transparency = 0.72
	scoreStroke.Thickness = 1.5
	scoreStroke.Parent = scoreText
	-- Aberration ghosts: fixed cyan/pink, spread+flare quantized with the
	-- speedo's beat thump.
	local function scoreGhost(dx: number, color: Color3): TextLabel
		local g = Instance.new("TextLabel")
		g.BackgroundTransparency = 1
		g.Font = scoreText.Font
		g.TextSize = scoreText.TextSize
		g.TextColor3 = color
		g.TextTransparency = 0.82
		g.TextXAlignment = scoreText.TextXAlignment
		g.Position = UDim2.fromOffset(dx, 0)
		g.Size = UDim2.fromScale(1, 1)
		g.Text = scoreText.Text
		g.Parent = scoreText
		return g
	end
	self.scoreGhostA = scoreGhost(-2, C_CYAN)
	self.scoreGhostB = scoreGhost(2, C_PINK)

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
	-- Neon tail: the readout warms dim->pink toward the screen edge.
	local subGrad = Instance.new("UIGradient")
	subGrad.Color = ColorSequence.new(C_DIM, C_PINK:Lerp(C_DIM, 0.35))
	subGrad.Parent = subText

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
	-- Neon rim: the streak pops like signage, not plain text.
	local comboStroke = Instance.new("UIStroke")
	comboStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	comboStroke.Color = C_CYAN
	comboStroke.Transparency = 0.6
	comboStroke.Thickness = 1
	comboStroke.Parent = comboText

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
	-- Metallic fade: bright crown over a dimmer base, chrome-lite.
	local bestGrad = Instance.new("UIGradient")
	bestGrad.Rotation = 90
	bestGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 120))
	bestGrad.Parent = bestFlash

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

	-- Live mission tracker (§14): the day's three seeded quests with
	-- in-run progress — reach/score read the live run counters, bank adds
	-- the run's banked delta to the stored today-tally. Dim open, gold
	-- in-the-bag; the whole block hides once nothing is left to chase.
	-- Stacks under the threat name, flush with the radar's right edge —
	-- minimap + quests read as one column.
	self.missionCsv = ""
	self.missionBank0 = 0
	self.missionLines = {}
	for i = 1, 3 do
		local ml = Instance.new("TextLabel")
		ml.Name = "Mission" .. i
		ml.BackgroundTransparency = 1
		ml.Font = F_DATA
		ml.TextSize = 12
		ml.TextColor3 = C_DIM
		ml.TextStrokeTransparency = 0.5
		ml.TextXAlignment = Enum.TextXAlignment.Right
		ml.AnchorPoint = Vector2.new(1, 0)
		ml.Position = UDim2.new(1, 0, 0, 350 + (i - 1) * 15)
		ml.Size = UDim2.new(1, 0, 0, 14)
		ml.Text = ""
		ml.Visible = false
		ml.Parent = hud
		self.missionLines[i] = ml
	end

	-- Deck-edge warning (§12): pink chevrons at the screen edges when the
	-- ball's far side hangs over a cutout or the rail. gui-rooted — they
	-- flank the track view, not the HUD cluster; the driver hides them
	-- the moment the ball is supported.
	local E = Config.EdgeWarn
	local edgeL = Instance.new("TextLabel")
	edgeL.Name = "EdgeL"
	edgeL.BackgroundTransparency = 1
	edgeL.Font = F_DATA
	edgeL.TextSize = 26
	edgeL.TextColor3 = C_PINK
	edgeL.TextStrokeTransparency = 0.4
	edgeL.AnchorPoint = Vector2.new(0, 0.5)
	edgeL.Position = UDim2.new(0, E.Px, E.Y, 0)
	edgeL.Size = UDim2.fromOffset(28, 28)
	edgeL.Text = "◄"
	edgeL.Visible = false
	edgeL.Parent = gui
	self.edgeL = edgeL
	local edgeR = edgeL:Clone()
	edgeR.Name = "EdgeR"
	edgeR.AnchorPoint = Vector2.new(1, 0.5)
	edgeR.Position = UDim2.new(1, -E.Px, E.Y, 0)
	edgeR.Text = "►"
	edgeR.Parent = gui
	self.edgeR = edgeR

	-- Danger vignette (§12): a full-screen stroke that tightens red as a
	-- corridor-overlapping lethal closes in — forward-looking where the
	-- chevrons are lateral. gui-rooted, stroke-only, never a fill.
	local D = Config.Danger
	local dangerFrame = Instance.new("Frame")
	dangerFrame.Name = "DangerVignette"
	dangerFrame.BackgroundTransparency = 1
	dangerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	dangerFrame.Position = UDim2.fromScale(0.5, 0.5)
	dangerFrame.Size = UDim2.fromScale(1, 1)
	dangerFrame.Visible = false
	local dangerStroke = Instance.new("UIStroke")
	dangerStroke.Thickness = D.Stroke
	dangerStroke.Color = C_PINK
	dangerStroke.Transparency = 1
	dangerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dangerStroke.Parent = dangerFrame
	dangerFrame.Parent = gui
	self.dangerFrame = dangerFrame
	self.dangerStroke = dangerStroke

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
	-- Ghost ticks (§14): the PB/rival echoes pinned on the strip edges —
	-- the replay you're racing reads on the same ruler the threats use.
	-- Behind-you clamps to the bottom edge like a minimap indicator;
	-- out-of-range pins the top. PB left/cyan, rival right/gold.
	local function ghostTick(x: UDim, color: Color3): Frame
		local t = Instance.new("Frame")
		t.BorderSizePixel = 0
		t.BackgroundColor3 = color
		t.BackgroundTransparency = 0.15
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Size = UDim2.fromOffset(5, R.BarH)
		t.Position = UDim2.new(x, UDim.new(0.5, 0))
		t.Visible = false
		t.Parent = radar
		return t
	end
	self.pbTick = ghostTick(UDim.new(0, 1), C_CYAN)
	self.rivalTick = ghostTick(UDim.new(1, -6), Config.Ghost.RivalColor)
	self.radar = radar

	-- Threat name (§12): the nearest lethal bar's chunk label under the
	-- strip — names the thing coming, not just its distance.
	local threatName = Instance.new("TextLabel")
	threatName.Name = "ThreatName"
	threatName.BackgroundTransparency = 1
	threatName.Font = F_DATA
	threatName.TextSize = 13
	threatName.TextColor3 = C_PINK
	threatName.TextStrokeTransparency = 0.5
	threatName.TextXAlignment = Enum.TextXAlignment.Right
	threatName.AnchorPoint = Vector2.new(1, 0)
	threatName.Position = UDim2.new(1, 0, 0, 328)
	threatName.Size = UDim2.fromOffset(240, 16)
	threatName.Text = ""
	threatName.Visible = false
	threatName.Parent = hud
	self.threatName = threatName

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
	-- (track bpm x the player's live PlaybackSpeed — it steps in semitones
	-- with the music), chromed like retro lettering and slanted outrun-style. Twin
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

	-- TEMPO module (§12): one untilted capsule — the spectrum scope takes
	-- the lead slot where the digit used to sit; the chrome digit and
	-- its BPM label ride the right edge. Same pill recipe as the power
	-- meter opposite it: C_BG fill, full corner, cyan rim — the two
	-- bottom corners bracket the screen as a set.
	local scope = Instance.new("Frame")
	scope.Name = "BpmScope"
	scope.AnchorPoint = Vector2.new(1, 0.5)
	scope.Position = UDim2.new(0.82, 0, 1, -38)
	scope.Size = UDim2.fromOffset(PILL_W, PILL_H)
	scope.BackgroundColor3 = C_BG
	scope.BackgroundTransparency = 0.25
	scope.BorderSizePixel = 0
	scope.Visible = false
	scope.Parent = gui
	self.bpmScope = scope
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(1, 0)
	sCorner.Parent = scope
	local sStroke = Instance.new("UIStroke")
	sStroke.Color = C_CYAN
	sStroke.Thickness = 1.5
	sStroke.Transparency = 0.55
	sStroke.Parent = scope
	self.scopeStroke = sStroke
	-- Digit + label move inside: positions go local to the capsule.
	spdNum.Parent = scope
	spdNum.AnchorPoint = Vector2.new(1, 0.5)
	spdNum.Position = UDim2.new(1, -10, 0.5, -7)
	spdNum.Size = UDim2.fromOffset(78, 44)
	spdNum.Rotation = 0
	spdNum.Visible = true
	spdUnit.Parent = scope
	spdUnit.AnchorPoint = Vector2.new(1, 1)
	spdUnit.Position = UDim2.new(1, -12, 1, -2)
	spdUnit.Size = UDim2.fromOffset(70, 12)
	spdUnit.Rotation = 0
	spdUnit.TextSize = 10
	spdUnit.Visible = true
	-- Module tag above the pill — mirrors the meter's POWER METER label,
	-- right-aligned so the pair reads inward toward the lane.
	local sLab = Instance.new("TextLabel")
	sLab.AnchorPoint = Vector2.new(1, 1)
	sLab.Position = UDim2.new(1, 0, 0, -3)
	sLab.Size = UDim2.fromOffset(PILL_W, 13)
	sLab.BackgroundTransparency = 1
	sLab.Font = F_DATA
	sLab.TextSize = 11
	sLab.TextColor3 = C_DIM
	sLab.TextXAlignment = Enum.TextXAlignment.Right
	sLab.Text = "TEMPO"
	sLab.Parent = scope

	-- Oscilloscope waveform (§12): the heard spectrum as a mirrored-
	-- envelope trace in the lead slot — one thin strip per bucket,
	-- centered on a dim hairline so a silent mix reads as a flatline.
	-- Bass sits left, air right, ramping cyan→pink like the power strip.
	local wWrap = Instance.new("Frame")
	wWrap.Name = "Waveform"
	wWrap.AnchorPoint = Vector2.new(0, 0.5)
	wWrap.Position = UDim2.new(0, 12, 0.5, 0)
	wWrap.Size = UDim2.fromOffset(WAVE_W, WAVE_H)
	wWrap.BackgroundTransparency = 1
	wWrap.ClipsDescendants = true
	wWrap.Parent = scope
	self.waveWrap = wWrap
	local wBase = Instance.new("Frame")
	wBase.AnchorPoint = Vector2.new(0, 0.5)
	wBase.Position = UDim2.fromScale(0, 0.5)
	wBase.Size = UDim2.new(1, 0, 0, 1)
	wBase.BackgroundColor3 = C_DIM
	wBase.BackgroundTransparency = 0.8
	wBase.BorderSizePixel = 0
	wBase.Parent = wWrap
	self.waveBase = wBase
	self.waveSegs = {}
	self._waveCache = {}
	local nWave = Config.Music.WavePoints
	local waveStep = WAVE_W / nWave
	for i = 1, nWave do
		local s = Instance.new("Frame")
		s.AnchorPoint = Vector2.new(0, 0.5)
		s.Position = UDim2.new(0, math.floor((i - 1) * waveStep + 0.5), 0.5, 0)
		s.Size = UDim2.fromOffset(3, 3)
		s.BackgroundColor3 = C_CYAN:Lerp(C_PINK, (i - 1) / (nWave - 1))
		s.BackgroundTransparency = 0.06
		s.BorderSizePixel = 0
		s.Parent = wWrap
		self.waveSegs[i] = s
	end

	-- Power meter: a vaporwave nitro strip — an untilted pill of LED
	-- segments ramping cyan->magenta like a tape-deck VU meter, twin of
	-- the TEMPO capsule mirrored on the right. A diamond bead rides the
	-- lit edge; the boundary cell glows partial so charge reads
	-- analog-smooth between cells. RechargeGate is a gold notch slotted
	-- between cells, its lock zone tinted warm; the strip still flares
	-- (pink boost, orange brake, gold ready-ping).
	local bWrap = Instance.new("Frame")
	bWrap.Name = "PowerMeter"
	bWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	bWrap.Position = UDim2.new(0.18, PILL_W / 2, 1, -38)
	bWrap.Size = UDim2.fromOffset(PILL_W, PILL_H)
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
	bInner.Position = UDim2.fromOffset(METER_PAD, 13)
	bInner.Size = UDim2.new(1, -METER_PAD * 2, 0, 28)
	bInner.Parent = bWrap
	local innerW = PILL_W - METER_PAD * 2
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
	-- The fill is ONE smooth chrome bar clipped to the eased charge —
	-- cyan→pink ramp with a white-hot leading edge, a gloss sheen on top
	-- and a dim shade line under it. The LED texture survives as slot
	-- dividers laid OVER the bar, so charge slides continuously instead
	-- of stepping cell to cell. Forced states tint the whole ramp.
	self._meterInnerW = innerW
	local fillWrap = Instance.new("Frame")
	fillWrap.BackgroundTransparency = 1
	fillWrap.Position = UDim2.fromOffset(0, 0)
	fillWrap.Size = UDim2.fromScale(0, 1)
	fillWrap.ClipsDescendants = true
	fillWrap.Parent = bInner
	self.powerFillWrap = fillWrap
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = C_WHITE
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, innerW, 1, 0)
	fill.Parent = fillWrap
	self.powerFill = fill
	local fGrad = Instance.new("UIGradient")
	fGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_CYAN),
		ColorSequenceKeypoint.new(0.55, C_PINK:Lerp(C_CYAN, 0.25)),
		ColorSequenceKeypoint.new(0.85, C_PINK),
		ColorSequenceKeypoint.new(1, C_WHITE),
	})
	fGrad.Parent = fill
	local sheen = Instance.new("Frame")
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = C_WHITE
	sheen.BackgroundTransparency = 0.6
	sheen.Size = UDim2.new(1, 0, 0, 1)
	sheen.Parent = fill
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = C_BG
	shade.BackgroundTransparency = 0.5
	shade.Size = UDim2.new(1, 0, 0, 2)
	shade.Parent = fill
	for i = 1, METER_SEGS - 1 do
		local d = Instance.new("Frame")
		d.BackgroundColor3 = C_BG
		d.BackgroundTransparency = 0.15
		d.BorderSizePixel = 0
		d.Position = UDim2.fromOffset(i * cellW + (i - 1) * gap, 0)
		d.Size = UDim2.new(0, gap, 1, 0)
		d.Parent = bInner
	end
	-- The recharge gate is a notch IN the strip, not a floating tick: a
	-- slim gold divider slotted into the gap right after the lock zone.
	local bGate = Instance.new("Frame")
	bGate.AnchorPoint = Vector2.new(0, 0.5)
	bGate.Position = UDim2.new(0, gateCells * cellW + (gateCells - 1) * gap + 0.5, 0.5, 0)
	bGate.Size = UDim2.fromOffset(2, 14)
	bGate.BackgroundColor3 = C_GOLD
	bGate.BackgroundTransparency = 0.25
	bGate.BorderSizePixel = 0
	bGate.Parent = bInner
	self.powerGate = bGate
	-- Diamond bead riding the lit edge — in wrap space so its x tracks
	-- the smoothed fill fraction every frame; a white rim sells the glow.
	local bTip = Instance.new("Frame")
	bTip.AnchorPoint = Vector2.new(0.5, 0.5)
	bTip.Position = UDim2.new(0, METER_PAD, 0.5, 0)
	bTip.Size = UDim2.fromOffset(12, 12)
	bTip.Rotation = 45
	bTip.BackgroundColor3 = C_CYAN
	bTip.BorderSizePixel = 0
	bTip.Visible = false
	bTip.Parent = bWrap
	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = C_WHITE
	tipStroke.Transparency = 0.3
	tipStroke.Thickness = 1
	tipStroke.Parent = bTip
	self.powerTip = bTip
	local bLab = Instance.new("TextLabel")
	bLab.AnchorPoint = Vector2.new(0, 1)
	bLab.Position = UDim2.fromOffset(0, -3)
	bLab.Size = UDim2.fromOffset(PILL_W, 13)
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
	-- "Crash log" report card (§11): a SIGNAL LOST banner over a one-line
	-- verdict (distance + executioner), then a bordered mono readout —
	-- key/value rows in the machine voice — then the gold payout ticker,
	-- late-arriving ranks, ghost margins, and the action row.
	local death = Instance.new("Frame")
	death.Name = "Death"
	death.Size = UDim2.fromScale(1, 1)
	death.BackgroundColor3 = C_BG
	death.BackgroundTransparency = 0.35
	death.BorderSizePixel = 0
	death.Visible = false
	death.Parent = gui
	self.death = death
	self._dailyRank = 0
	self._topRank = 0

	local dCol = Instance.new("Frame")
	dCol.BackgroundTransparency = 1
	dCol.Size = UDim2.fromOffset(540, 0)
	dCol.AutomaticSize = Enum.AutomaticSize.Y
	dCol.Position = UDim2.fromScale(0.5, 0.44)
	dCol.AnchorPoint = Vector2.new(0.5, 0.5)
	dCol.Parent = death
	vlist(dCol, 10)

	-- Banner: thin rails flanking the letterspaced serif title.
	local banner = Instance.new("Frame")
	banner.BackgroundTransparency = 1
	banner.Size = UDim2.new(1, 0, 0, 46)
	banner.LayoutOrder = 1
	banner.Parent = dCol
	local railL = Instance.new("Frame")
	railL.AnchorPoint = Vector2.new(0, 0.5)
	railL.Position = UDim2.fromScale(0, 0.5)
	railL.Size = UDim2.fromOffset(72, 1)
	railL.BackgroundColor3 = C_PINK
	railL.BackgroundTransparency = 0.4
	railL.BorderSizePixel = 0
	railL.Parent = banner
	local railR = railL:Clone()
	railR.AnchorPoint = Vector2.new(1, 0.5)
	railR.Position = UDim2.fromScale(1, 0.5)
	railR.Parent = banner
	local bannerTitle = label(banner, spaced("SIGNAL LOST"), 38, F_HERO, C_PINK, 0)
	bannerTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerTitle.Position = UDim2.fromScale(0.5, 0.5)
	bannerTitle.Size = UDim2.fromScale(1, 1)

	-- Verdict line: "lost at 1646 m — the VOID · inside FORK".
	self.dVerdict = label(dCol, "", 15, F_DATA, C_PINK, 2)

	-- Bordered report panel — left-aligned rows so the keys line up like a
	-- printout. Code is monospace, so %-Ns format widths align the columns.
	local panel = Instance.new("Frame")
	panel.Name = "Report"
	panel.BackgroundColor3 = C_PANEL
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromScale(1, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.LayoutOrder = 3
	panel.Parent = dCol
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = C_DIM
	pStroke.Thickness = 1
	pStroke.Transparency = 0.35
	pStroke.Parent = panel
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 4)
	pCorner.Parent = panel
	local pPad = Instance.new("UIPadding")
	pPad.PaddingTop = UDim.new(0, 12)
	pPad.PaddingBottom = UDim.new(0, 12)
	pPad.PaddingLeft = UDim.new(0, 16)
	pPad.PaddingRight = UDim.new(0, 16)
	pPad.Parent = panel
	local pLayout = Instance.new("UIListLayout")
	pLayout.FillDirection = Enum.FillDirection.Vertical
	pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	pLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pLayout.Padding = UDim.new(0, 4)
	pLayout.Parent = panel
	local function prow(text, order, rich, color)
		local l = label(panel, text, 15, F_DATA, color or C_DIM, order)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.RichText = rich == true
		return l
	end
	self.dPanelTitle = prow("", 1)
	self.dScore = prow("", 2, true)
	self.dScore.Size = UDim2.new(1, 0, 0, 40) -- inline 30px hero number
	-- §7 stamp: UIScale lets showDeath slam the hero row in past 100%.
	local dScoreScale = Instance.new("UIScale")
	dScoreScale.Name = "StampScale"
	dScoreScale.Parent = self.dScore
	self.dScoreScale = dScoreScale
	self.dBest = prow("", 3)
	local pDiv = Instance.new("Frame")
	pDiv.Size = UDim2.new(1, 0, 0, 1)
	pDiv.BackgroundColor3 = C_DIM
	pDiv.BackgroundTransparency = 0.6
	pDiv.BorderSizePixel = 0
	pDiv.LayoutOrder = 4
	pDiv.Parent = panel
	self.dLoot = prow("", 5, true)
	-- Run telemetry (§11): top speed, lethal planes crossed, boost/air
	-- share, tightest near-miss margin. Display-only; never score.
	self.dTele1 = prow("", 6)
	self.dTele2 = prow("", 7)
	self.dTele3 = prow("", 8)

	-- Gold payout ticker (§14): streak + daily-quest bonuses, one line.
	self.dTicker = label(dCol, "", 14, F_DATA, C_GOLD, 4)
	self.dTicker.Visible = false
	-- Board slots (§14): "daily #3 · all-time #7" — fills a beat after the
	-- card via the rank attributes; both share this one line.
	self.dRanks = label(dCol, "", 14, F_DATA, C_CYAN, 5)
	self.dRanks.Visible = false
	-- Ghost margins (§14): where each echo stood at the fall.
	self.dMargins = label(dCol, "", 13, F_DATA, C_DIM, 6)
	self.dMargins.Visible = false

	-- Action row: RETRY primary, menu (garage access, §18) secondary.
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 56)
	actions.LayoutOrder = 7
	actions.Parent = dCol
	local aLayout = Instance.new("UIListLayout")
	aLayout.FillDirection = Enum.FillDirection.Horizontal
	aLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	aLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	aLayout.SortOrder = Enum.SortOrder.LayoutOrder
	aLayout.Padding = UDim.new(0, 28)
	aLayout.Parent = actions
	local retry = outlineButton(actions, "RETRY", 30, 1)
	retry.Size = UDim2.fromOffset(300, 56)
	retry.Selectable = true -- gamepad: A activates the selected button
	retry.MouseButton1Click:Connect(function()
		if self.onRetry then
			self.onRetry()
		end
	end)
	local toMenu = ghostButton(actions, "menu", 15, 2)
	toMenu.Selectable = true
	toMenu.MouseButton1Click:Connect(function()
		if self.onMenu then
			self.onMenu()
		end
	end)
	self.retryBtn = retry
	self.toMenuBtn = toMenu
	wireTick(retry)
	wireTick(toMenu)
	self.deathHint = label(dCol, "press R", 13, F_DATA, C_DIM, 8)
	self.deathHint.TextTransparency = 0.25

	--===================== touch controls (§4) ======================--
	-- A drag zone on the left thumb (steer + tap-tap dash, the "tap" dash
	-- style's gesture) and BOOST/BRAKE hold buttons on the right. Only
	-- built for touch-only devices — a laptop touchscreen (touch + mouse)
	-- keeps the keyboard map and never sees this.
	local touchUi = Instance.new("Frame")
	touchUi.Name = "TouchControls"
	touchUi.BackgroundTransparency = 1
	touchUi.Size = UDim2.fromScale(1, 1)
	touchUi.Visible = false
	touchUi.Parent = gui
	self.touchUi = touchUi
	self.touchEnabled = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	-- Steer zone: invisible full-capture area under the left thumb —
	-- drag for analog steer (floating origin at touch-down, full lock at
	-- PadTravelPx), a quick release reads as a tap and a same-side pair
	-- inside Dash.TapWindow fires onPadTap (the pad's dash). A faint pad
	-- ring + knob ghost in while the thumb is down so the zone has a body.
	local zone = Instance.new("TextButton")
	zone.Name = "SteerZone"
	zone.BackgroundTransparency = 1
	zone.Text = ""
	zone.AnchorPoint = Vector2.new(0, 1)
	zone.Position = UDim2.fromScale(0, 1)
	zone.Size = UDim2.fromScale(Config.Controls.ZoneW, Config.Controls.ZoneH)
	zone.Parent = touchUi
	local pad = Instance.new("Frame")
	pad.Name = "Pad"
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.Position = UDim2.fromScale(0.5, 0.5)
	pad.Size = UDim2.fromOffset(120, 120)
	pad.BackgroundColor3 = C_BG
	pad.BackgroundTransparency = 0.75
	pad.BorderSizePixel = 0
	pad.Visible = false
	pad.Parent = zone
	local padCorner = Instance.new("UICorner")
	padCorner.CornerRadius = UDim.new(1, 0)
	padCorner.Parent = pad
	local padRing = Instance.new("UIStroke")
	padRing.Color = C_CYAN
	padRing.Transparency = 0.55
	padRing.Thickness = 1.5
	padRing.Parent = pad
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(44, 44)
	knob.BackgroundColor3 = C_CYAN
	knob.BackgroundTransparency = 0.25
	knob.BorderSizePixel = 0
	knob.Parent = pad
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	local padInput: InputObject? = nil
	local padDownAt = 0
	local padDownX = 0
	local padLastTap: { [number]: number } = { [-1] = 0, [1] = 0 }
	zone.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		padInput = input
		padDownAt = tick()
		padDownX = input.Position.X
		pad.Visible = true
	end)
	zone.InputChanged:Connect(function(input)
		if input ~= padInput then
			return
		end
		local s = math.clamp((input.Position.X - padDownX) / Config.Controls.PadTravelPx, -1, 1)
		self.padSteer = s
		knob.Position = UDim2.fromScale(0.5 + s * 0.32, 0.5)
	end)
	zone.InputEnded:Connect(function(input)
		if input ~= padInput then
			return
		end
		padInput = nil
		pad.Visible = false
		self.padSteer = 0
		-- Tap read: quick release with almost no travel. A same-side pair
		-- inside TapWindow is the pad's dash — the "tap" dash style
		-- gesture, always live on touch regardless of the menu pick.
		if
			tick() - padDownAt < Config.Dash.TapWindow
			and math.abs(input.Position.X - padDownX) < Config.Controls.PadTapPx
		then
			local half = zone.AbsoluteSize.X / 2
			local dir = if input.Position.X - zone.AbsolutePosition.X < half then -1 else 1
			local now = tick()
			if now - padLastTap[dir] <= Config.Dash.TapWindow then
				padLastTap[dir] = 0
				if self.onPadTap then
					self.onPadTap(dir)
				end
			else
				padLastTap[dir] = now
			end
		end
	end)

	-- HOLD column (§4): BOOST on top where the thumb rests, BRAKE the
	-- smaller deck under it — the power meter's own boost/brake split.
	-- Held flags ride the exact W/S path in the drive loop. Anchored
	-- left of the radar rail and above the TEMPO pill so the cluster
	-- still fits a phone-width landscape screen.
	local function holdButton(text: string, yOff: number, h: number, setter: (boolean) -> ())
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -90, 1, yOff)
		b.Size = UDim2.fromOffset(150, h)
		b.BackgroundColor3 = C_BG
		b.BackgroundTransparency = 0.5
		b.AutoButtonColor = false
		b.Text = ""
		b.BorderSizePixel = 0
		b.Parent = touchUi
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 14)
		bc.Parent = b
		local bs = Instance.new("UIStroke")
		bs.Color = C_CYAN
		bs.Transparency = 0.45
		bs.Thickness = 1.5
		bs.Parent = b
		local bl = Instance.new("TextLabel")
		bl.BackgroundTransparency = 1
		bl.Size = UDim2.fromScale(1, 1)
		bl.Font = F_DISPLAY
		bl.TextSize = 17
		bl.TextColor3 = C_WHITE
		bl.Text = text
		bl.Parent = b
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				setter(true)
				bs.Transparency = 0.05
				b.BackgroundTransparency = 0.25
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				setter(false)
				bs.Transparency = 0.45
				b.BackgroundTransparency = 0.5
			end
		end)
		return b
	end
	holdButton("BOOST", -186, 74, function(v)
		self.boostHeld = v
	end)
	holdButton("BRAKE", -102, 70, function(v)
		self.brakeHeld = v
	end)
	local padHint = Instance.new("TextLabel")
	padHint.AnchorPoint = Vector2.new(0.5, 1)
	padHint.Position = UDim2.new(0.5, 0, 1, -6)
	padHint.Size = UDim2.new(0.9, 0, 0, 14)
	padHint.BackgroundTransparency = 1
	padHint.Font = F_DATA
	padHint.TextSize = 11
	padHint.TextColor3 = C_DIM
	padHint.TextTransparency = 0.35
	padHint.Text = "drag to steer · tap-tap to dash"
	padHint.Parent = zone

	-- First-run coach line (§6): one device-aware sentence mid-screen,
	-- shown only on a fresh profile's first run (Main decides — best==0),
	-- self-hiding after TutHintSec so it never outlives the lesson.
	local runHint = Instance.new("TextLabel")
	runHint.Name = "RunHint"
	runHint.AnchorPoint = Vector2.new(0.5, 0)
	runHint.Position = UDim2.fromScale(0.5, 0.6)
	runHint.Size = UDim2.fromOffset(560, 40)
	runHint.BackgroundTransparency = 1
	runHint.Font = F_DATA
	runHint.TextSize = 15
	runHint.TextColor3 = C_WHITE
	runHint.TextStrokeTransparency = 0.6
	runHint.TextTransparency = 0.2
	runHint.Visible = false
	runHint.Parent = gui
	self.runHint = runHint

	-- Narrow-screen shrink (§12): the power meter + TEMPO pills are
	-- fixed-pixel chrome built for desktop — under ~900px viewport they
	-- collide mid-screen. One shared UIScale shrinks both together so
	-- the bracket pair stays symmetric.
	local pillScale = Instance.new("UIScale")
	pillScale.Parent = self.powerBar
	local pillScale2 = Instance.new("UIScale")
	pillScale2.Parent = self.bpmScope
	local function fitPills()
		local w = gui.AbsoluteSize.X
		local s = if w < 900 then math.max(0.6, w / 1250) else 1
		pillScale.Scale = s
		pillScale2.Scale = s
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPills)
	fitPills()

	return self
end

-- Dash style (§4): the menu toggle label + the controls hint both track
-- the saved pick — "‹ Q / E KEYS ›" / "‹ DOUBLE-TAP A / D ›". The hint
-- row swaps per input device: pad/touch players never see keybinds.
function Ui:setDashMode(m: string)
	self._dashMode = m
	self.dashToggle.Text = "DASH STYLE  " .. (Config.Dash.ModeLabel[m] or m)
	local dev = self._deviceHint
	if dev == "pad" then
		self.dashHint.Text = "L-STICK steer   ·   RT/LT boost/brake   ·   RB/LB dash   ·   START restart"
	elseif dev == "touch" then
		self.dashHint.Text = "drag to steer   ·   tap-tap the pad to dash   ·   BOOST/BRAKE hold"
	else
		self.dashHint.Text = "A/D steer   ·   W/S boost/brake   ·   "
			.. (Config.Dash.ModeHint[m] or "Q/E dash")
			.. "   ·   R restart"
	end
end

-- First-run coach (§6): Main calls this on a fresh profile's first run;
-- the line self-hides after TutHintSec and re-shows replace cleanly.
function Ui:setRunHint(text: string)
	local tag = tick()
	self._runHintAt = tag
	self.runHint.Text = text
	self.runHint.Visible = true
	task.delay(Config.Controls.TutHintSec, function()
		if self._runHintAt == tag then
			self.runHint.Visible = false
		end
	end)
end

-- Input device (§4): Main feeds UserInputService.LastInputType so the
function Ui:setDeviceInput(kind: string)
	self._deviceHint = kind
	if self._dashMode then
		self:setDashMode(self._dashMode)
	end
	if self.playHint then
		self.playHint.Text = if kind == "pad"
			then "press A / START to roll"
			elseif kind == "touch" then "tap PLAY to roll"
			else "press ENTER / R to roll"
	end
	if self.deathHint then
		self.deathHint.Text = if kind == "pad" then "press A" elseif kind == "touch" then "" else "press R"
	end
end

function Ui:deviceHintKind(): string
	return self._deviceHint or "keys"
end

-- Locked-item funnel (§18): clicking an unowned STYLE row calls here with
-- the bundle that unlocks it. The plumbing (tab swap, accordion, scroll
-- snap, buy-chip flare) is a closure in Ui.new; this is just the door.
function Ui:focusPack(id: string)
	if self._focusPack then
		self._focusPack(id)
	end
end

-- Gamepad menu nav (§4): the engine activates GuiService.SelectedObject
-- on button A — put it on the primary action whenever a card shows, but
-- only once the pad is actually the input device (a stray selection box
-- on the keyboard/mouse UI reads as a bug).
local function padActive(): boolean
	local t = UserInputService:GetLastInputType()
	return t == Enum.UserInputType.Gamepad1
		or t == Enum.UserInputType.Gamepad2
		or t == Enum.UserInputType.Gamepad3
		or t == Enum.UserInputType.Gamepad4
end

function Ui:showMenu(best: number)
	self.menu.Visible = true
	self.death.Visible = false
	self.hud.Visible = false
	self.bpmScope.Visible = false
	self.powerBar.Visible = false
	self.seedTag.Visible = false
	self.touchUi.Visible = false
	self.padSteer = 0
	self.boostHeld = false
	self.brakeHeld = false
	if padActive() then
		GuiService.SelectedObject = self.playBtn
	end
	self:setBest(best)
end

function Ui:showHud()
	self.menu.Visible = false
	self.death.Visible = false
	self.bestFlash.Visible = false -- reset for the new run's own crossing
	self.hud.Visible = true
	self.bpmScope.Visible = true
	self.powerBar.Visible = true
	self.seedTag.Visible = true
	self.touchUi.Visible = self.touchEnabled
	self.runHint.Visible = false -- Main re-arms it on a fresh profile
	GuiService.SelectedObject = nil -- no menu selection inside a run
end

function Ui:setHud(score: number, dist: number, gems: number, _speed: number, seed: number)
	local s = tostring(score)
	self.scoreText.Text = s
	self.scoreGhostA.Text = s
	self.scoreGhostB.Text = s
	-- Speed lives on the dial now; the subline stays quiet.
	self.subText.Text = string.format("%d m  ·  gems +%d", dist, gems)
	self.seedTag.Text = string.format("seed %d", seed)
end

-- Audio pulse from Music.sample() (0..1) — the digit thumps on the beat:
-- slight swell, brighter face, and the chromatic ghosts spread wider.
function Ui:setPulse(v: number)
	self.pulse = v
end

-- MENU.md §2: the poster thumps on the menu bed — PLAY swells a few
-- percent and the horizon rule's mid keypoint dips (the menu's only
-- filled element is the one that breathes). setWave's discipline:
-- quantized envelope, write only on change, menu-only. Doubles as the
-- menu's per-frame spring tick (§4): cyclers integrate EVERY call, so
-- they run ahead of the env early-out.
function Ui:pulseMenu()
	if not self.menu.Visible then
		self._menuT = nil -- reopening starts a fresh clock, not a stale dt
		return
	end
	local now = os.clock()
	local dt = math.min(now - (self._menuT or now), Config.Menu.SpringDtMax)
	self._menuT = now
	-- §4 cyclers: the arrows move the target; the label rides the spring
	-- residual (pos - target) — the transient kick that re-seats the name
	-- on its slot once settled. Quantized + write-gated so a parked
	-- cycler costs nothing.
	local s = self._trkSpring
	s.pos, s.vel = spring(s.pos, s.vel, s.target, dt)
	local kq = math.floor((s.pos - s.target) * 64 + 0.5) / 64
	if kq ~= self._trkKick then
		self._trkKick = kq
		self.trackName.Position = self._trkPos + UDim2.fromOffset(kq * Config.Menu.JacketPx, 0)
	end
	for slot, ss in pairs(self._slotSpring) do
		ss.pos, ss.vel = spring(ss.pos, ss.vel, ss.target, dt)
		local sq = math.floor((ss.pos - ss.target) * 64 + 0.5) / 64
		if sq ~= self._slotKick[slot] then
			self._slotKick[slot] = sq
			self.slotItem[slot].Position = self._slotPos[slot] + UDim2.fromOffset(sq * Config.Menu.JacketPx, 0)
		end
	end
	local e8 = math.floor((self.pulse or 0) * 8 + 0.5) / 8
	if e8 == self._menuEnv then
		return
	end
	self._menuEnv = e8
	self.playScale.Scale = 1 + Config.Menu.ChromePulse * e8
	self.ruleGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3 * e8),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- MENU.md §8: a second, thinner scope under the horizon rule — setWave's
-- loop over a second seg set (2px-quantized heights, per-seg cache,
-- repaint on change only), gated on the menu being up so a still menu
-- costs nothing. Main pushes Music.spectrum()'s shared buffer here.
function Ui:menuScope(spec: { number }?)
	if not self.menu.Visible then
		return
	end
	local segs = self.menuWaveSegs
	if not segs then
		return
	end
	local cache = self._menuWaveCache
	local env = math.min(1, (self.pulse or 0) * Config.Music.WaveBeatGain)
	local amp = Config.Music.WaveBeatFloor + (1 - Config.Music.WaveBeatFloor) * env
	local maxH = Config.Menu.MenuSpecH
	local gamma = Config.Music.WaveGamma
	for i, s in ipairs(segs) do
		local v = spec and spec[i] or 0
		v = v ^ gamma
		local h = math.max(2, math.floor(v * amp * maxH / 2 + 0.5) * 2)
		if h ~= cache[i] then
			cache[i] = h
			s.Size = UDim2.fromOffset(3, h)
		end
	end
end

-- Oscilloscope trace (§12): spec is Music.spectrum()'s shared band buffer.
-- Heights quantize to 2 px and writes gate on change — a steady mix costs
-- nothing, only real motion repaints. The heard pulse also swells the
-- whole trace on the kick (amp = floor + (1-floor) x env) and flashes the
-- hairline + capsule rim, so the module visibly pumps on the music.
function Ui:setWave(spec: { number }?)
	local segs = self.waveSegs
	if not segs then
		return
	end
	local cache = self._waveCache
	local env = math.min(1, (self.pulse or 0) * Config.Music.WaveBeatGain)
	local amp = Config.Music.WaveBeatFloor + (1 - Config.Music.WaveBeatFloor) * env
	local e8 = math.floor(env * 8 + 0.5) / 8
	if e8 ~= self._waveEnv then
		self._waveEnv = e8
		self.waveBase.BackgroundTransparency = 0.8 - 0.5 * e8
		self.scopeStroke.Transparency = 0.55 - 0.3 * e8
	end
	local maxH = WAVE_H - 4
	local gamma = Config.Music.WaveGamma
	for i, s in ipairs(segs) do
		local v = spec and spec[i] or 0
		v = v ^ gamma
		local h = math.max(3, math.floor(v * amp * maxH / 2 + 0.5) * 2)
		if h ~= cache[i] then
			cache[i] = h
			s.Size = UDim2.fromOffset(3, h)
		end
	end
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
	-- Write-gating + pixel quantization (PERFORMANCE.md §1): the digit's
	-- pulse used to dirty 3 text relayouts and 10 property writes every
	-- heartbeat — pulse-driven dims snap to whole pixels / quantized
	-- steps, and every write skips when the value didn't actually change.
	local now = tick()
	local pulse = self.pulse or 0
	local num = tostring(math.floor(bpm + 0.5))
	if num ~= self._spdNum then
		self._spdNum = num
		self.spdNum.Text = num
		self.spdGhostA.Text = num
		self.spdGhostB.Text = num
	end
	local size = math.floor(40 + pulse * 6 + 0.5) -- beat thump: swell on the heard grid
	if size ~= self._spdSize then
		self._spdSize = size
		self.spdNum.TextSize = size
		self.spdGhostA.TextSize = size
		self.spdGhostB.TextSize = size
	end
	local spread = math.floor(2 + pulse * 4 + 0.5) -- VHS fringe widens with the kick
	if spread ~= self._spdSpread then
		self._spdSpread = spread
		self.spdGhostA.Position = UDim2.fromOffset(-spread, 0)
		self.spdGhostB.Position = UDim2.fromOffset(spread, 0)
		-- Same fringe on the score hero — one quantum, one flare.
		self.scoreGhostA.Position = UDim2.fromOffset(-spread, 0)
		self.scoreGhostB.Position = UDim2.fromOffset(spread, 0)
	end
	local ssize = math.floor(52 + pulse * 4 + 0.5) -- score thumps on the same grid
	if ssize ~= self._scoreSize then
		self._scoreSize = ssize
		self.scoreText.TextSize = ssize
		self.scoreGhostA.TextSize = ssize
		self.scoreGhostB.TextSize = ssize
	end
	local tr = math.floor((0.82 - pulse * 0.42) * 64 + 0.5) / 64
	if tr ~= self._spdTr then
		self._spdTr = tr
		self.spdGhostA.TextTransparency = tr
		self.spdGhostB.TextTransparency = tr
		self.scoreGhostA.TextTransparency = tr
		self.scoreGhostB.TextTransparency = tr
	end
	local col
	if speed >= 100 then
		-- Over the line: flat hot red, pulsing so it reads as "pegged".
		local v = 0.85 + 0.15 * math.sin(now * 9)
		col = Color3.fromRGB(255, 40, 60):Lerp(Color3.fromRGB(255, 120, 140), v)
	else
		-- Gradient hue cyan(0.53) -> violet(0.75) -> magenta(0.88) with speed.
		local h = 0.53 + (speed / 100) * 0.35
		col = Color3.fromHSV(h, 0.92, 1)
	end
	local cq = col:Lerp(C_WHITE, pulse * 0.3)
	cq = Color3.fromRGB(math.round(cq.R * 255), math.round(cq.G * 255), math.round(cq.B * 255))
	if cq ~= self._spdCol then
		self._spdCol = cq
		self.spdNum.TextColor3 = cq
	end
	local sq = Color3.fromRGB(math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255))
	if sq ~= self._spdStrokeCol then
		self._spdStrokeCol = sq
		self.spdStroke.Color = sq -- rim wears the hue so it reads as glow
	end
	-- Analog-smooth across the discrete cells: the shown charge eases to
	-- the real value (~70ms) and the leading cell only glows partial, so
	-- the strip breathes instead of stepping.
	local frac = math.clamp(powerFrac, 0, 1)
	local disp = self._powerDisp or frac
	disp += (frac - disp) * math.min(1, math.max(0, now - (self._powerT or now)) * 14)
	self._powerT = now
	self._powerDisp = disp
	-- Ready flash: when charge crosses the gate upward, the bar pings gold
	-- for a moment — you feel W come back without watching it.
	local gate = self.gateFrac or 1
	local ready = powerFrac >= gate
	if ready and self._powerReady == false then
		self._readyFlash = now
	end
	self._powerReady = ready
	local blink = powerSpent and math.sin(now * 10) > 0
	local flash = self._readyFlash ~= nil and now - self._readyFlash < 0.45
	-- Forced state color overrides the cyan->magenta ramp: gold ready-ping,
	-- white dash flash, dim flicker on a denied press (§4: broke/latched),
	-- hot orange while braking (S spends the same power meter), pink boost flare.
	local denied = dashDeniedAt ~= nil and (now - dashDeniedAt) < 0.3
	local forced = flash and C_GOLD
		or dashing and C_WHITE
		or (denied and (math.sin(now * 18) > 0 and C_DIM or C_PANEL))
		or (braking and Color3.fromRGB(255, 140, 40) or ((boosting or blink) and C_PINK or nil))
	-- Smooth fill: the chrome bar is one clipped ramp — its clip width
	-- slides with the eased charge and forced states tint the whole bar
	-- instead of flashing cell by cell.
	local fillW = math.floor(disp * self._meterInnerW + 0.5)
	if fillW ~= self._fillW then
		self._fillW = fillW
		self.powerFillWrap.Size = UDim2.new(0, fillW, 1, 0)
	end
	local tint = forced or C_WHITE
	if tint ~= self._fillCol then
		self._fillCol = tint
		self.powerFill.BackgroundColor3 = tint
	end
	-- Lock-zone slots: permanent warm tint, gently pulsing while latched
	-- out — "recharging through the gate" reads without a floating tick.
	-- (Only the unfilled dark slots show; the fill covers them when lit.)
	local segTr = self._segTr or {}
	self._segTr = segTr
	for i = 1, self._gateCells or 0 do
		local s = self.powerSegs[i]
		local ctr = powerSpent and (math.floor((0.35 + 0.3 * math.sin(now * 6)) * 64 + 0.5) / 64) or 0.4
		if ctr ~= segTr[i] then
			segTr[i] = ctr
			s.BackgroundTransparency = ctr
		end
	end
	-- The bead tip rides the smoothed lit edge, wearing the same color;
	-- hidden when the meter is empty so it doesn't dangle off the left end.
	local tipC = forced or C_CYAN:Lerp(C_PINK, disp)
	if tipC ~= self._tipCol then
		self._tipCol = tipC
		self.powerTip.BackgroundColor3 = tipC
	end
	local tipPos = UDim2.new(0, math.floor(METER_PAD + disp * (PILL_W - METER_PAD * 2) + 0.5), 0.5, 0)
	if tipPos ~= self._tipPos then
		self._tipPos = tipPos
		self.powerTip.Position = tipPos
	end
	local tipVis = disp > 0.04
	if tipVis ~= self._tipVis then
		self._tipVis = tipVis
		self.powerTip.Visible = tipVis
	end
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

-- Achievement tally on the menu (§14): "awards n/total" in the
-- always-on missions card's footer.
function Ui:setAchievements(unlocked: number)
	self.achLine.Text = string.format("awards %d/%d", unlocked, #Config.Monetization.Achievements)
end

-- Daily quests (§14): csv "1,0,0,<bankedToday>" from RoBallQuests — quest
-- defs are recomputed here from Daily.quests() so client and server can
-- never disagree about what today's missions are.
function Ui:setQuests(csv: string)
	self.missionCsv = csv
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
	self:_paintBankFlow()
end

-- TODAY'S FLOW (§18 P2): the bank page's ledger — banked today, the
-- open missions' rewards still on the table, and the next daily run's
-- streak payout. RoBallQuests csv carries the flags + today's tally;
-- RoBallDailyStreak carries the day count.
function Ui:_paintBankFlow()
	local parts = string.split(self.missionCsv or "", ",")
	local banked = tonumber(parts[#parts]) or 0
	local open = 0
	for i, q in ipairs(Daily.quests()) do
		if parts[i] ~= "1" then
			open += q.reward
		end
	end
	local lp = Players.LocalPlayer
	local streak = (lp and lp:GetAttribute("RoBallDailyStreak")) or 0
	local m = Config.Monetization
	local nextBonus = math.min(streak + 1, m.DailyStreakCap) * m.DailyStreakBonus
	self.flowBanked[1].Text = "banked today"
	self.flowBanked[2].Text = "+◊" .. tostring(banked)
	self.flowMissions[1].Text = "missions left"
	self.flowMissions[2].Text = open > 0 and ("+◊" .. tostring(open)) or "cleared ✓"
	self.flowMissions[2].TextColor3 = open > 0 and C_GOLD or C_DIM
	self.flowStreak[1].Text = streak > 0 and string.format("day-%d streak", streak) or "no streak yet"
	self.flowStreak[2].Text = "+◊" .. tostring(nextBonus) .. " next daily"
	self.bankToday.Text = string.format("today +◊%d", banked)
	self.bankStreak.Text = streak > 0 and string.format("day-%d streak", streak) or ""
end

-- Live mission tracker (§14): snapshot the bank balance at run start so
-- the bank quest can add this run's pickups to the stored today-tally.
function Ui:missionArm(bankNow: number)
	self.missionBank0 = bankNow
end

local QUEST_LABEL = { reach = "reach %dm", score = "score %d", bank = "bank %d ◊" }

function Ui:setMissionTrack(score: number, dist: number, bankNow: number)
	local parts = string.split(self.missionCsv, ",")
	local banked = (tonumber(parts[#parts]) or 0) + math.max(bankNow - self.missionBank0, 0)
	local allMet = true
	for i, q in ipairs(Daily.quests()) do
		local prog = if q.kind == "reach" then dist elseif q.kind == "score" then score else banked
		local met = parts[i] == "1" or prog >= q.target
		allMet = allMet and met
		local short = string.format(QUEST_LABEL[q.kind] or "%s", q.target)
		local text = string.format(
			"%s %s",
			met and "✓" or "◇",
			if met then short else short .. string.format(" · %d", math.min(prog, q.target))
		)
		local line = self.missionLines[i]
		if line.Text ~= text then
			line.Text = text
		end
		line.TextColor3 = met and C_GOLD or C_DIM
	end
	for _, line in ipairs(self.missionLines) do
		line.Visible = not allMet
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
	stats: {
		top: number,
		boost: number,
		dashes: number,
		hazards: number?,
		closest: number?,
		cause: string?,
		causeLoc: string?,
		air: number?,
		pbDelta: number?,
		rivalDelta: number?,
		rivalName: string?,
	}?
)
	self.menu.Visible = false
	self.hud.Visible = false
	self.bpmScope.Visible = false
	self.powerBar.Visible = false
	self.seedTag.Visible = false
	self.touchUi.Visible = false
	self.padSteer = 0
	self.boostHeld = false
	self.brakeHeld = false
	self.death.Visible = true
	if padActive() then
		GuiService.SelectedObject = self.retryBtn
	end

	-- Verdict: distance + executioner (§11) — the chunk type that killed
	-- the run, or the backstop that fired: VOID for falls, STALL for
	-- wedges. Backstops also name WHERE (causeLoc): "inside PRESS ROW" is
	-- the debug lead for stuck-death reports.
	local verdict = string.format("lost at %d m", dist)
	if stats and (stats.cause or stats.causeLoc) then
		local c = stats.cause
		local name = if c == "VOID"
			then "the VOID"
			elseif c == "STALL" then "wedged geometry"
			elseif c then Config.Features.Label[c] or string.upper(c)
			else "the track"
		local loc = stats.causeLoc and (Config.Features.Label[stats.causeLoc] or stats.causeLoc:gsub("_", " "))
		verdict ..= " — " .. name
		if loc then
			verdict ..= string.format(" · inside %s", loc)
		end
	end
	self.dVerdict.Text = verdict

	-- Report rows: score is the hero (NEW BEST rides its line, gold); the
	-- rest print as key/value pairs — left column padded %-6s/%-13s so
	-- the second key column lines up in the mono font.
	self.dPanelTitle.Text = string.format("RUN %d", seed)
	self.dScore.Text = string.format(
		'score    <font size="30" color="#00E6FF">%s</font>%s',
		spaced(tostring(score)),
		newBest == true and '      <font color="#FFD440">★ NEW BEST!</font>' or ""
	)
	-- Stamp (MENU.md §7): the hero row slams in past 100% and settles on
	-- a Back ease — osu's grade stamp. ★ NEW BEST is inline rich text on
	-- this same label, so the one scale stamps both.
	self.dScoreScale.Scale = Config.Menu.StampKick
	TweenService:Create(
		self.dScoreScale,
		TweenInfo.new(Config.Menu.StampSec, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	self.dBest.Text = string.format("%-6s   %s", "best", spaced(tostring(best)))
	self.dLoot.Text = string.format(
		'%-6s   %-13s  %-6s  <font color="#FFD440">◊ +%d</font>',
		"gems",
		string.format("+%d pts", gems),
		"banked",
		banked or 0
	)
	if stats then
		local boostPct = if dist > 0 then math.floor(100 * stats.boost / dist) else 0
		-- closest < 0 means the ball ran inside a rotor's sweep disc.
		local margin = if stats.closest
			then (stats.closest <= 0 and "in-disc" or string.format("%.1f s", stats.closest))
			else "—"
		self.dTele1.Text = string.format(
			"%-6s   %-13s  %-6s  %d",
			"top",
			string.format("%d s/s", math.floor(stats.top)),
			"gates",
			stats.hazards or 0
		)
		self.dTele2.Text = string.format(
			"%-6s   %-13s  %-6s  %s",
			"boost",
			string.format("%d %%", boostPct),
			"air",
			string.format("%d %%", math.floor(100 * (stats.air or 0)))
		)
		self.dTele3.Text = string.format("%-6s   %s", "margin", margin)
		self.dTele1.Visible = true
		self.dTele2.Visible = true
		self.dTele3.Visible = true
		-- Ghost margins (§14): where each echo stood at the fall — the
		-- last pace deltas, signed by your lead, so the race result
		-- survives the run that ended it.
		local margins = {}
		if stats.pbDelta then
			table.insert(margins, string.format("PB %+d", math.floor(stats.pbDelta + 0.5)))
		end
		if stats.rivalDelta then
			table.insert(
				margins,
				string.format("%s %+d", stats.rivalName or "CHAMP", math.floor(stats.rivalDelta + 0.5))
			)
		end
		self.dMargins.Text = string.format("at the fall: %s", table.concat(margins, " · "))
		self.dMargins.Visible = #margins > 0
	else
		self.dTele1.Visible = false
		self.dTele2.Visible = false
		self.dTele3.Visible = false
		self.dMargins.Visible = false
	end

	-- Payout ticker (§14): streak keeps its own bonus (same-day replays
	-- show the streak without a re-paid bonus), quests list their hits.
	local ticker = {}
	local n = streak or 0
	local bonus = streakBonus or 0
	if n > 0 then
		table.insert(
			ticker,
			if bonus > 0 then string.format("day-%d streak ◊ +%d", n, bonus) else string.format("day-%d streak", n)
		)
	end
	local hits = questHits or 0
	if hits > 0 then
		table.insert(ticker, string.format("%s ◊ +%d", hits == 1 and "quest" or hits .. " quests", questBonus or 0))
	end
	self.dTicker.Text = table.concat(ticker, "  ·  ")
	self.dTicker.Visible = #ticker > 0
	-- Board slots may already be sitting on the player (the attrs can land
	-- during the death-cam orbit, before this card opens) — read them now;
	-- anything later still fills via setDailyRank/setTopRank.
	local lp = Players.LocalPlayer
	self._dailyRank = (lp and lp:GetAttribute("RoBallDailyRank")) or 0
	self._topRank = (lp and lp:GetAttribute("RoBallTopRank")) or 0
	self:_renderRanks()
end

-- Board-slot line (§14): "daily #3 · all-time #7" — the server publishes
-- each a beat after RunEnded (submit → fetch → attr), so the setters
-- re-render the shared line on an already-visible card. 0 hides that
-- half (off the TopCount window).
function Ui:_renderRanks()
	local parts = {}
	if (self._dailyRank or 0) > 0 then
		table.insert(parts, string.format("daily #%d", self._dailyRank))
	end
	if (self._topRank or 0) > 0 then
		table.insert(parts, string.format("all-time #%d", self._topRank))
	end
	self.dRanks.Text = table.concat(parts, "  ·  ")
	self.dRanks.Visible = #parts > 0
end

function Ui:setDailyRank(rank: number?)
	self._dailyRank = rank or 0
	self:_renderRanks()
end

function Ui:setTopRank(rank: number?)
	self._topRank = rank or 0
	self:_renderRanks()
end

-- Garage state push (§18): one table per refresh — slot row text/afford,
-- pack button states (bundles + the bank2x perk), gem-pack buttons, bank
-- balance. Main computes all of it from attributes + catalog.
export type GarageState = {
	slots: {
		[string]: {
			text: string,
			afford: boolean, -- clickable ◊price (unowned + à-la-carte)
			owned: boolean?, -- false = pack-locked → dim name
			equipped: boolean?, -- browsed id IS the ball's look → cyan chip ring
			color: Color3?, -- item's own swatch; nil = no chip color (rainbow/custom)
		},
	},
	packs: { [string]: { label: string, enabled: boolean } },
	gemPacks: { [string]: { label: string, enabled: boolean } },
	bank: number,
	-- COLOR LAB (§18): visible = owns any lab item; hues = server state
	-- (0..1 slider positions on the legal band).
	lab: { visible: boolean, hues: { a: number, b: number, c: number }? }?,
}

function Ui:setGarage(state: GarageState)
	for slot, btn in pairs(self.slotItem) do
		local row = state.slots[slot]
		btn.Text = if row then row.text else "—"
		-- State tint: gold = the ◊ price is a buy button, dim = locked
		-- behind a pack, white = yours. slotTint stores it so the hover
		-- pink can re-seat on MouseLeave.
		local tint = C_WHITE
		if row then
			if row.afford then
				tint = C_GOLD
			elseif not row.owned then
				tint = C_DIM
			end
		end
		self.slotTint[slot] = tint
		btn.TextColor3 = tint
		local sw = self.slotSwatch[slot]
		if sw then
			sw.BackgroundColor3 = if row and row.color then row.color else C_DIM
			sw.BackgroundTransparency = if row and row.color then 0 else 0.65
			local st = self.slotSwatchStroke[slot]
			if st then
				st.Color = if row and row.equipped then C_CYAN else C_DIM
				st.Transparency = if row and row.equipped then 0 else 0.45
			end
		end
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
		local lines = string.split(if st then st.label else "SOON", "\n")
		self.gemPackAmt[key].Text = string.gsub(lines[1] or "", "◊", "") -- card carries the icon
		self.gemPackAmt[key].TextColor3 = enabled and C_GOLD or C_DIM
		self.gemPackPrice[key].Text = lines[2] or ""
		self.gemPackStroke[key].Color = enabled and C_GOLD or C_DIM
		self.gemPackEnabled[key] = enabled
		btn.TextColor3 = enabled and C_GOLD or C_DIM
	end
	self.bankLabel.Text = "◊ " .. tostring(state.bank)
	self.bankHero.Text = tostring(state.bank) -- icon carries the gem mark
	-- COLOR LAB: visibility comes from ownership; the pushed hues re-seat
	-- the knobs/swatches (writes only happen on release, so this never
	-- fights a live drag).
	local lab = state.lab
	self.labFrame.Visible = lab ~= nil and lab.visible == true
	if lab and lab.hues then
		local H = Config.CustomHue
		for k, v in pairs(lab.hues) do
			local row = self.labRows[k]
			if row and typeof(v) == "number" then
				local f = math.clamp((v - H.Min) / (H.Max - H.Min), 0, 1)
				self.labVals[k] = f
				row.knob.Position = UDim2.fromScale(f, 0.5)
				row.swatch.BackgroundColor3 = Color3.fromHSV(math.clamp(v, H.Min, H.Max), H.Sat, H.Value)
			end
		end
	end
end

function Ui:setBest(best: number)
	self.bestLabel.Text = "BEST " .. tostring(best or 0)
end

-- Board tab switch (§14): recolors tabs, shows/hides the daily info line,
-- then asks Main to fetch — rows arrive via setLeaderboard.
function Ui:setBoard(mode: string)
	if mode ~= "top" and mode ~= "daily" then
		return
	end
	self.boardMode = mode
	self.tabTop.TextColor3 = if mode == "top" then C_PINK else C_DIM
	self.tabDaily.TextColor3 = if mode == "daily" then C_PINK else C_DIM
	self.dailyInfo.Visible = mode == "daily"
	if mode == "daily" then
		self.dailyInfo.Text = dailyText()
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

-- Ghost ticks (§14): each replay's dz on the strip, already clamped to
-- 0..Range by the caller — behind-you pins the bottom edge, out-of-range
-- the top. nil hides that tick (echo not replaying).
function Ui:setRadarGhosts(pbDz: number?, rivalDz: number?)
	local function pin(t: Frame, dz: number?)
		if dz then
			t.Position = UDim2.new(t.Position.X, UDim.new(1 - dz / Config.Radar.Range, 0))
			t.Visible = true
		else
			t.Visible = false
		end
	end
	pin(self.pbTick, pbDz)
	pin(self.rivalTick, rivalDz)
end

-- Pace delta (§12): signed meters vs the PB echo; nil hides the line
-- (no ghost, menu, death). Whole ints only — the caller rounds.
function Ui:setPace(delta: number?)
	if delta == nil then
		self.paceText.Visible = false
		return
	end
	-- Duel tag (§14): inside DuelRange either way the race is nose-to-nose.
	local duel = math.abs(delta) <= Config.Ghost.DuelRange and " · DUEL" or ""
	self.paceText.Text = string.format("%+d vs PB%s", delta, duel)
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
	local duel = math.abs(delta) <= Config.Ghost.DuelRange and " · DUEL" or ""
	self.rivalText.Text = string.format("%+d vs %s%s", delta, name, duel)
	self.rivalText.TextColor3 = if delta >= 0 then Config.Ghost.RivalColor else C_PINK
	self.rivalText.Visible = true
end

-- Deck-edge warning (§12): one chevron per unsupported side. Called from
-- the heartbeat probe; both args are "side has ground under it" negated.
function Ui:setEdgeWarn(left: boolean, right: boolean)
	-- Early-out (PERFORMANCE.md §1): called every heartbeat; only write on change.
	if left ~= self._edgeL then
		self._edgeL = left
		self.edgeL.Visible = left
	end
	if right ~= self._edgeR then
		self._edgeR = right
		self.edgeR.Visible = right
	end
end

-- Threat name (§12): the nearest radar bar's chunk label, "" hides.
function Ui:setThreat(text: string)
	self.threatName.Text = text
	self.threatName.Visible = text ~= ""
end

-- Danger vignette (§12): intensity 0..1 of nearest corridor threat —
-- 0 hides, 1 is contact distance at full Config.Danger.MaxAlpha.
function Ui:setDanger(intensity: number)
	-- Early-out (PERFORMANCE.md §1): per-frame caller; intensity quantized
	-- to 1/64 steps so sub-step jitter doesn't dirty the stroke every frame.
	local q = math.floor(math.min(intensity, 1) * 64 + 0.5) / 64
	if q == self._dangerQ then
		return
	end
	self._dangerQ = q
	if q <= 0 then
		self.dangerFrame.Visible = false
		self.dangerStroke.Transparency = 1
		return
	end
	self.dangerFrame.Visible = true
	self.dangerStroke.Transparency = 1 - q * Config.Danger.MaxAlpha
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

-- Preview filter (§18): re-paint the screen-filter look inside the
-- garage's preview window — mirrors the ScreenFilter modes on a small
-- scale so the overlay sells itself in the diorama. Takes the item
-- record (tint/alpha recolor the wash, the lattice modes keep the
-- small-scale bar recipe).
function Ui:setPreviewFilter(item: any)
	local fov = self.previewFilterFrame
	fov:ClearAllChildren()
	local mode = if item then item.filter else "off"
	local col = if item and item.tint then item.tint else Config.Art.PixelColor
	local function bar(x: number, y: number, w: number, h: number)
		local b = Instance.new("Frame")
		b.BackgroundColor3 = col
		b.BackgroundTransparency = Config.Art.PixelAlpha
		b.BorderSizePixel = 0
		b.Position = UDim2.fromScale(x, y)
		b.Size = UDim2.fromScale(w, h)
		b.Parent = fov
	end
	if mode == "scan" then
		for i = 0, 15 do
			bar(0, i / 15, 1, 0.035)
		end
	elseif mode == "pixel" then
		for i = 0, 15 do
			bar(0, i / 15, 1, 0.02)
		end
		for i = 0, 26 do
			bar(i / 26, 0, 0.007, 1)
		end
	elseif mode == "tint" then
		local w = Instance.new("Frame")
		w.BorderSizePixel = 0
		w.Size = UDim2.fromScale(1, 1)
		w.BackgroundColor3 = col
		w.BackgroundTransparency = 1 - (if item.alpha then item.alpha else 0.12)
		w.Parent = fov
	elseif mode == "vignette" then
		local keys = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.35, 0.9),
			NumberSequenceKeypoint.new(0.65, 0.9),
			NumberSequenceKeypoint.new(1, 0.55),
		})
		for _, rot in ipairs({ 0, 90 }) do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = col
			f.Parent = fov
			local g = Instance.new("UIGradient")
			g.Rotation = rot
			g.Transparency = keys
			g.Parent = f
		end
	end
end

return Ui
