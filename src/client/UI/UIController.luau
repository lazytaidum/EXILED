local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIController = {}
UIController.Name = "UIController"

local THEME = {
	Panel = Color3.fromRGB(19, 27, 39),
	PanelAlt = Color3.fromRGB(28, 39, 55),
	PanelSoft = Color3.fromRGB(44, 58, 79),
	Text = Color3.fromRGB(239, 244, 248),
	MutedText = Color3.fromRGB(151, 165, 184),
	Accent = Color3.fromRGB(145, 211, 255),
	WarmAccent = Color3.fromRGB(255, 214, 92),
	Stroke = Color3.fromRGB(102, 130, 161),
}

-- Drop your final artist-delivered asset ids here when they're ready.
local MENU_BUTTONS = {
	Left = {
		{ Name = "Inventory", AssetId = "", Fallback = "INV" },
		{ Name = "RemnantUI", AssetId = "", Fallback = "REM" },
		{ Name = "Shop", AssetId = "", Fallback = "SHOP" },
	},
	Right = {
		{ Name = "Bestiary", AssetId = "", Fallback = "BEST" },
		{ Name = "DailyRewards", AssetId = "", Fallback = "DAY" },
		{ Name = "Achievements", AssetId = "", Fallback = "ACH" },
	},
	BottomRight = {
		{ Name = "Settings", AssetId = "", Fallback = "SET" },
	},
}

local PHASE_DISPLAY = {
	Lobby = "LOBBY OPEN",
	Voting = "MAP VOTING",
	Preparation = "GET READY",
	Reception = "GAME IN PROGRESS",
	Results = "ROUND COMPLETE",
}

local function applyCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
	return corner
end

local function applyStroke(instance, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

local function createText(parent, name, size, position, text, textSize, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font or Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = color or THEME.Text
	label.TextSize = textSize
	label.TextTransparency = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function createPanel(parent, name, position, size, anchorPoint)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = anchorPoint or Vector2.new(0, 0)
	panel.Position = position
	panel.Size = size
	panel.BackgroundColor3 = THEME.Panel
	panel.BackgroundTransparency = 0.2
	panel.Parent = parent

	applyCorner(panel, 22)
	applyStroke(panel, THEME.Stroke, 0.55, 1.5)

	return panel
end

local function normalizeAssetId(assetId)
	if assetId == nil or assetId == "" then
		return ""
	end

	if string.find(assetId, "rbxassetid://", 1, true) or string.find(assetId, "http", 1, true) then
		return assetId
	end

	local numericId = tonumber(assetId)
	if numericId then
		return "rbxassetid://" .. tostring(numericId)
	end

	return assetId
end

local function attachHover(button, fill, stroke)
	local inactiveFill = fill.BackgroundColor3
	local hoverFill = THEME.PanelSoft
	local inactiveTransparency = fill.BackgroundTransparency
	local hoverTransparency = 0.06
	local inactiveStroke = stroke.Color
	local hoverStroke = THEME.Accent
	local tweenInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	button.MouseEnter:Connect(function()
		TweenService:Create(fill, tweenInfo, {
			BackgroundColor3 = hoverFill,
			BackgroundTransparency = hoverTransparency,
		}):Play()
		TweenService:Create(stroke, tweenInfo, {
			Color = hoverStroke,
			Transparency = 0.15,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(fill, tweenInfo, {
			BackgroundColor3 = inactiveFill,
			BackgroundTransparency = inactiveTransparency,
		}):Play()
		TweenService:Create(stroke, tweenInfo, {
			Color = inactiveStroke,
			Transparency = 0.35,
		}):Play()
	end)
end

local function createIconButton(parent, definition)
	local button = Instance.new("ImageButton")
	button.Name = definition.Name .. "Button"
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(92, 92)
	button.ImageTransparency = 1
	button.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = button

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(0.76, 0.76)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = THEME.Panel
	diamond.BackgroundTransparency = 0.14
	diamond.Parent = button

	applyCorner(diamond, 18)
	local diamondStroke = applyStroke(diamond, THEME.Stroke, 0.35, 2)

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	iconHolder.Position = UDim2.fromScale(0.5, 0.5)
	iconHolder.Size = UDim2.fromScale(0.74, 0.74)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Rotation = -45
	iconHolder.Parent = diamond

	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0.88, 0.88)
	image.BackgroundTransparency = 1
	image.Image = normalizeAssetId(definition.AssetId)
	image.ImageColor3 = THEME.Text
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = image.Image ~= ""
	image.Parent = iconHolder

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.BackgroundTransparency = 1
	fallback.Font = Enum.Font.GothamBlack
	fallback.Text = definition.Fallback
	fallback.TextColor3 = THEME.Text
	fallback.TextScaled = true
	fallback.Visible = image.Image == ""
	fallback.Parent = iconHolder

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 12)
	padding.Parent = fallback

	attachHover(button, diamond, diamondStroke)

	return button
end

local function createPillButton(parent, name, position, size, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = THEME.Panel
	button.BackgroundTransparency = 0.08
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = THEME.Text
	button.TextSize = 24
	button.Parent = parent

	applyCorner(button, math.floor(size.Y.Offset / 2))
	local stroke = applyStroke(button, THEME.Stroke, 0.35, 1.5)
	attachHover(button, button, stroke)

	return button
end

local function createMenuRail(parent, name, position, definitions)
	local rail = Instance.new("Frame")
	rail.Name = name
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = position
	rail.Size = UDim2.fromOffset(110, (#definitions * 104))
	rail.BackgroundTransparency = 1
	rail.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = rail

	local buttons = {}
	for _, definition in ipairs(definitions) do
		table.insert(buttons, createIconButton(rail, definition))
	end

	return rail, buttons
end

local function createSeparator(parent, positionY)
	local line = Instance.new("Frame")
	line.Name = "Separator"
	line.Position = UDim2.new(0, 16, 0, positionY)
	line.Size = UDim2.new(1, -32, 0, 1)
	line.BackgroundColor3 = THEME.Stroke
	line.BackgroundTransparency = 0.65
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

local function createQuestColumn(parent, name, title, accentColor, position)
	local column = Instance.new("Frame")
	column.Name = name
	column.BackgroundTransparency = 1
	column.Position = position
	column.Size = UDim2.new(0.48, 0, 1, -32)
	column.Parent = parent

	local header = createText(column, "Header", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 0), title, 19, accentColor, Enum.Font.GothamBold)
	header.TextXAlignment = Enum.TextXAlignment.Left

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.Parent = column

	header.LayoutOrder = 1

	for index = 1, 4 do
		local row = createText(column, "Row" .. index, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 0), "#" .. tostring(index), 16, THEME.MutedText, Enum.Font.GothamMedium)
		row.LayoutOrder = index + 1
	end

	return column
end

local function ensureMainHUD(playerGui)
	local mainHUD = playerGui:FindFirstChild("MainHUD")
	if not mainHUD then
		mainHUD = Instance.new("ScreenGui")
		mainHUD.Name = "MainHUD"
		mainHUD.ResetOnSpawn = false
		mainHUD.IgnoreGuiInset = true
		mainHUD.Parent = playerGui
	end

	local shell = mainHUD:FindFirstChild("Shell")
	if shell then
		shell:Destroy()
	end

	local legacyContainer = mainHUD:FindFirstChild("Container")
	if legacyContainer then
		legacyContainer:Destroy()
	end

	shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.BackgroundTransparency = 1
	shell.Size = UDim2.fromScale(1, 1)
	shell.Parent = mainHUD

	local chatPanel = createPanel(shell, "ChatPanel", UDim2.new(0, 16, 0, 16), UDim2.fromOffset(250, 118))
	local chatTitle = createText(chatPanel, "Title", UDim2.new(1, -28, 0, 24), UDim2.new(0, 14, 0, 12), "CHAT", 18, THEME.Text, Enum.Font.GothamBold)
	chatTitle.TextXAlignment = Enum.TextXAlignment.Left
	createSeparator(chatPanel, 44)

	local chatDock = Instance.new("Frame")
	chatDock.Name = "Dock"
	chatDock.Position = UDim2.new(0, 14, 0, 56)
	chatDock.Size = UDim2.new(1, -28, 1, -70)
	chatDock.BackgroundColor3 = THEME.PanelAlt
	chatDock.BackgroundTransparency = 0.28
	chatDock.Parent = chatPanel
	applyCorner(chatDock, 14)

	local serverButton = createPillButton(shell, "ServerBrowserButton", UDim2.new(0, 108, 0, 154), UDim2.fromOffset(184, 44), "SERVER BROWSER")
	serverButton.AnchorPoint = Vector2.new(0, 0)
	serverButton.Position = UDim2.new(0, 16, 0, 140)
	serverButton.TextSize = 20

	local statusPanel = createPanel(shell, "StatusPanel", UDim2.new(0.5, 0, 0, 16), UDim2.fromOffset(430, 120), Vector2.new(0.5, 0))
	local statusLabel = createText(statusPanel, "StatusLabel", UDim2.new(1, -36, 0, 20), UDim2.new(0, 18, 0, 14), "LOBBY OPEN", 18, THEME.Accent, Enum.Font.GothamBold)
	local timerLabel = createText(statusPanel, "TimerLabel", UDim2.new(1, -36, 0, 58), UDim2.new(0, 18, 0, 34), "00:00", 48, THEME.Text, Enum.Font.GothamBlack)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.Size = UDim2.new(1, -36, 0, 58)
	local outcomeLabel = createText(statusPanel, "OutcomeLabel", UDim2.new(1, -36, 0, 20), UDim2.new(0, 18, 1, -30), "", 16, THEME.MutedText, Enum.Font.GothamMedium)
	outcomeLabel.TextXAlignment = Enum.TextXAlignment.Center
	outcomeLabel.Visible = false

	local playersPanel = createPanel(shell, "PlayersPanel", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(250, 238), Vector2.new(1, 0))
	local playersTitle = createText(playersPanel, "Title", UDim2.new(1, -24, 0, 24), UDim2.new(0, 14, 0, 12), "PLAYERS", 18, THEME.Text, Enum.Font.GothamBold)
	playersTitle.TextXAlignment = Enum.TextXAlignment.Left

	local listFrame = Instance.new("Frame")
	listFrame.Name = "List"
	listFrame.BackgroundTransparency = 1
	listFrame.Position = UDim2.new(0, 10, 0, 44)
	listFrame.Size = UDim2.new(1, -20, 1, -54)
	listFrame.Parent = playersPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = listFrame

	local currenciesPanel = createPanel(shell, "CurrenciesPanel", UDim2.new(0, 16, 1, -16), UDim2.fromOffset(280, 116), Vector2.new(0, 1))
	local currenciesTitle = createText(currenciesPanel, "Title", UDim2.new(1, -28, 0, 24), UDim2.new(0, 14, 0, 12), "CURRENCIES", 17, THEME.Text, Enum.Font.GothamBold)
	currenciesTitle.TextXAlignment = Enum.TextXAlignment.Left
	createSeparator(currenciesPanel, 44)

	local leftCurrency = createText(currenciesPanel, "FractalsValue", UDim2.new(0.46, 0, 0, 24), UDim2.new(0, 14, 0, 58), "XXX", 26, THEME.Accent, Enum.Font.GothamBlack)
	leftCurrency.TextXAlignment = Enum.TextXAlignment.Left
	local leftLabel = createText(currenciesPanel, "FractalsLabel", UDim2.new(0.46, 0, 0, 16), UDim2.new(0, 14, 0, 84), "FRACTALS", 14, THEME.MutedText, Enum.Font.GothamMedium)
	leftLabel.TextXAlignment = Enum.TextXAlignment.Left

	local rightCurrency = createText(currenciesPanel, "SoulCoinsValue", UDim2.new(0.46, 0, 0, 24), UDim2.new(0.54, 0, 0, 58), "???", 26, THEME.WarmAccent, Enum.Font.GothamBlack)
	rightCurrency.TextXAlignment = Enum.TextXAlignment.Left
	local rightLabel = createText(currenciesPanel, "SoulCoinsLabel", UDim2.new(0.46, 0, 0, 16), UDim2.new(0.54, 0, 0, 84), "SOUL COINS", 14, THEME.MutedText, Enum.Font.GothamMedium)
	rightLabel.TextXAlignment = Enum.TextXAlignment.Left

	local ritualsPanel = createPanel(shell, "RitualsPanel", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(350, 138), Vector2.new(1, 1))
	local ritualsTitle = createText(ritualsPanel, "Title", UDim2.new(1, -28, 0, 24), UDim2.new(0, 14, 0, 12), "RITUALS", 17, THEME.Text, Enum.Font.GothamBold)
	ritualsTitle.TextXAlignment = Enum.TextXAlignment.Left
	createSeparator(ritualsPanel, 44)
	createQuestColumn(ritualsPanel, "DailyColumn", "DAILY", THEME.Accent, UDim2.new(0, 14, 0, 58))
	createQuestColumn(ritualsPanel, "WeeklyColumn", "WEEKLY", THEME.WarmAccent, UDim2.new(0.52, 0, 0, 58))

	local _, leftButtons = createMenuRail(shell, "LeftRail", UDim2.new(0, 72, 0.5, 40), MENU_BUTTONS.Left)
	local _, rightButtons = createMenuRail(shell, "RightRail", UDim2.new(1, -74, 0.56, 0), MENU_BUTTONS.Right)
	local _, bottomRightButtons = createMenuRail(shell, "BottomRightRail", UDim2.new(1, -74, 1, -166), MENU_BUTTONS.BottomRight)

	local spectateButton = createPillButton(shell, "SpectateButton", UDim2.new(0.5, 0, 1, -32), UDim2.fromOffset(224, 52), "SPECTATE")

	return {
		Root = mainHUD,
		Shell = shell,
		StatusLabel = statusLabel,
		TimerLabel = timerLabel,
		OutcomeLabel = outcomeLabel,
		PlayerList = listFrame,
		LeftButtons = leftButtons,
		RightButtons = rightButtons,
		BottomRightButtons = bottomRightButtons,
		SpectateButton = spectateButton,
	}
end

function UIController:Init(controllers)
	self.Controllers = controllers
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	self.LastPhase = nil
	self.LastTimeLeft = nil
	self.LastOutcome = nil
	self.PlayerCards = {}
end

function UIController:Start()
	local refs = ensureMainHUD(self.PlayerGui)
	self.Root = refs.Root
	self.Shell = refs.Shell
	self.StatusLabel = refs.StatusLabel
	self.TimerLabel = refs.TimerLabel
	self.OutcomeLabel = refs.OutcomeLabel
	self.PlayerList = refs.PlayerList
	self.SpectateButton = refs.SpectateButton

	self:_refreshPlayerRoster()

	Players.PlayerAdded:Connect(function()
		self:_refreshPlayerRoster()
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:_refreshPlayerRoster()
		end)
	end)

	task.spawn(function()
		while true do
			self:UpdateHUD()
			task.wait(0.2)
		end
	end)

	print("[UIController] Started")
end

function UIController:UpdateHUD()
	local roundController = self.Controllers.RoundController
	local state = roundController and roundController:GetState()

	if not state then
		return
	end

	local phase = state.Phase or "Unknown"
	local timeLeft = state.TimeLeft
	if timeLeft == nil then
		timeLeft = 0
	end

	local outcome = state.Outcome or "None"
	local phaseChanged = phase ~= self.LastPhase
	local timeChanged = timeLeft ~= self.LastTimeLeft
	local outcomeChanged = outcome ~= self.LastOutcome

	if phaseChanged then
		self.LastPhase = phase
		self.StatusLabel.Text = PHASE_DISPLAY[phase] or string.upper(tostring(phase))
	end

	if timeChanged then
		self.LastTimeLeft = timeLeft
		self.TimerLabel.Text = self:_formatTime(timeLeft)
	end

	if outcomeChanged or phaseChanged then
		self.LastOutcome = outcome
		local outcomeText = self:_formatOutcomeText(phase, outcome)
		self.OutcomeLabel.Text = outcomeText
		self.OutcomeLabel.Visible = outcomeText ~= ""
	end

	self:_refreshPlayerRoster()
end

function UIController:_refreshPlayerRoster()
	if not self.PlayerList then
		return
	end

	local orderedPlayers = Players:GetPlayers()
	table.sort(orderedPlayers, function(left, right)
		if left == self.Player then
			return true
		end

		if right == self.Player then
			return false
		end

		return string.lower(left.Name) < string.lower(right.Name)
	end)

	local activeCards = {}

	for index, player in ipairs(orderedPlayers) do
		local card = self.PlayerCards[player]
		if not card then
			card = self:_createPlayerCard(player)
			self.PlayerCards[player] = card
		end

		card.LayoutOrder = index
		card.Parent = self.PlayerList
		self:_populatePlayerCard(card, player)
		activeCards[player] = true
	end

	for player, card in pairs(self.PlayerCards) do
		if not activeCards[player] then
			card:Destroy()
			self.PlayerCards[player] = nil
		end
	end
end

function UIController:_createPlayerCard(player)
	local card = Instance.new("Frame")
	card.Name = player.Name .. "Card"
	card.Size = UDim2.new(1, 0, 0, 44)
	card.BackgroundColor3 = THEME.PanelAlt
	card.BackgroundTransparency = 0.08

	applyCorner(card, 14)
	applyStroke(card, THEME.Stroke, 0.6, 1)

	local nameLabel = createText(card, "DisplayName", UDim2.new(0.56, 0, 0, 18), UDim2.new(0, 12, 0, 7), player.DisplayName, 18, THEME.Text, Enum.Font.GothamBold)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local handleLabel = createText(card, "Handle", UDim2.new(0.44, -10, 0, 16), UDim2.new(0.56, 0, 0, 10), "@" .. player.Name, 14, THEME.MutedText, Enum.Font.GothamMedium)
	handleLabel.TextXAlignment = Enum.TextXAlignment.Right

	local statusLabel = createText(card, "Status", UDim2.new(1, -24, 0, 14), UDim2.new(0, 12, 0, 24), "IN LOBBY", 12, THEME.Accent, Enum.Font.GothamBold)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left

	return card
end

function UIController:_populatePlayerCard(card, player)
	local displayName = player.DisplayName
	if displayName == nil or displayName == "" then
		displayName = player.Name
	end

	local roleText = player == self.Player and "YOU" or "IN LOBBY"
	local roleColor = player == self.Player and THEME.WarmAccent or THEME.Accent

	card.DisplayName.Text = string.upper(displayName)
	card.Handle.Text = "@" .. player.Name
	card.Status.Text = roleText
	card.Status.TextColor3 = roleColor
end

function UIController:_formatTime(timeLeft)
	local safeTime = math.max(0, math.floor(tonumber(timeLeft) or 0))
	local minutes = math.floor(safeTime / 60)
	local seconds = safeTime % 60
	return string.format("%02d:%02d", minutes, seconds)
end

function UIController:_formatOutcomeText(phase, outcome)
	if phase ~= "Results" then
		return ""
	end

	if outcome == "RemnantsWin" then
		return "REMNANTS WIN"
	elseif outcome == "EntitiesWin" then
		return "ENTITIES WIN"
	elseif outcome == "Draw" then
		return "DRAW"
	end

	return ""
end

return UIController
