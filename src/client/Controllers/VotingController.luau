local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local VotingController = {}
VotingController.Name = "VotingController"
VotingController.Dependencies = {
	"RoundController",
}

local PANEL_WIDTH = 1020
local PANEL_HEIGHT = 360
local CARD_WIDTH = 168
local CARD_HEIGHT = 228
local CARD_INITIAL_REVEAL_DELAY = 0.35
local CARD_REVEAL_DELAY = 0.12

local function _createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function _createStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function _formatTimerValue(seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	return string.format("+%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function VotingController:Init()
	self.State = {
		IsActive = false,
		Options = {},
		SelectedEntityIds = {},
		WeightTarget = 5,
		TotalWeight = 0,
		SecondsLeft = 0,
		VotedPlayers = 0,
		EligiblePlayers = 0,
		AllVotesShortened = false,
	}
	self.LastRoundIndex = nil
	self.LastOptionSignature = nil
	self.RevealGeneration = 0
	self.LocalVotedEntityId = nil
	self.PendingReveal = false
end

function VotingController:Start()
	self.RequestVoteRemote = self.World.Remotes:WaitForChild(RemoteNames.RequestVote)
	self.StateRemote = self.World.Remotes:WaitForChild(RemoteNames.VotingStateChanged)

	self:_createUI()
	self:_refreshUi()

	self.StateRemote.OnClientEvent:Connect(function(state)
		local previousRoundIndex = self.State and self.State.RoundIndex or nil
		local previousOptionSignature = self:_buildOptionSignature(self.State and self.State.Options or {})
		self.State = state or self.State

		local shouldResetVote = previousRoundIndex ~= self.State.RoundIndex
			or previousOptionSignature ~= self:_buildOptionSignature(self.State.Options or {})
		if shouldResetVote then
			self.LocalVotedEntityId = nil
		end

		self:_refreshUi()
	end)

	DebugLog:Log("ClientRound", "[VotingController] Started")
end

function VotingController:_createCard(parent, optionIndex)
	local button = Instance.new("TextButton")
	button.Name = string.format("Option%d", optionIndex)
	button.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	button.LayoutOrder = optionIndex
	button.BackgroundColor3 = Color3.fromRGB(22, 20, 18)
	button.BackgroundTransparency = 0.02
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent

	_createCorner(button, 12)
	local stroke = _createStroke(button, Color3.fromRGB(92, 79, 61), 1, 0.18)

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.Size = UDim2.new(1, 0, 1, 0)
	glow.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	glow.BackgroundTransparency = 0.94
	glow.BorderSizePixel = 0
	glow.Visible = false
	glow.ZIndex = 4
	glow.Parent = button
	_createCorner(glow, 12)

	local faceDown = Instance.new("Frame")
	faceDown.Name = "FaceDown"
	faceDown.Size = UDim2.new(1, 0, 1, 0)
	faceDown.BackgroundColor3 = Color3.fromRGB(30, 28, 26)
	faceDown.BorderSizePixel = 0
	faceDown.ZIndex = 6
	faceDown.Parent = button
	_createCorner(faceDown, 12)
	_createStroke(faceDown, Color3.fromRGB(139, 111, 65), 1, 0.18)

	local faceDownTitle = Instance.new("TextLabel")
	faceDownTitle.BackgroundTransparency = 1
	faceDownTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	faceDownTitle.Position = UDim2.new(0.5, 0, 0.45, 0)
	faceDownTitle.Size = UDim2.new(1, -24, 0, 22)
	faceDownTitle.Font = Enum.Font.GothamBold
	faceDownTitle.TextSize = 16
	faceDownTitle.TextColor3 = Color3.fromRGB(226, 219, 206)
	faceDownTitle.Text = "CASTING"
	faceDownTitle.ZIndex = 7
	faceDownTitle.Parent = faceDown

	local faceDownSub = Instance.new("TextLabel")
	faceDownSub.BackgroundTransparency = 1
	faceDownSub.AnchorPoint = Vector2.new(0.5, 0.5)
	faceDownSub.Position = UDim2.new(0.5, 0, 0.56, 0)
	faceDownSub.Size = UDim2.new(1, -24, 0, 16)
	faceDownSub.Font = Enum.Font.Gotham
	faceDownSub.TextSize = 10
	faceDownSub.TextColor3 = Color3.fromRGB(157, 151, 142)
	faceDownSub.Text = "Hidden Selection"
	faceDownSub.ZIndex = 7
	faceDownSub.Parent = faceDown

	local weightLabel = Instance.new("TextLabel")
	weightLabel.Name = "WeightLabel"
	weightLabel.BackgroundTransparency = 1
	weightLabel.Position = UDim2.new(0, 12, 0, 12)
	weightLabel.Size = UDim2.new(0, 70, 0, 18)
	weightLabel.Font = Enum.Font.GothamBold
	weightLabel.TextSize = 12
	weightLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	weightLabel.TextXAlignment = Enum.TextXAlignment.Left
	weightLabel.ZIndex = 2
	weightLabel.Parent = button

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.new(1, -12, 0, 12)
	timerLabel.Size = UDim2.new(0, 72, 0, 18)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 12
	timerLabel.TextColor3 = Color3.fromRGB(124, 214, 166)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.ZIndex = 2
	timerLabel.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 12, 0, 44)
	nameLabel.Size = UDim2.new(1, -24, 0, 60)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 17
	nameLabel.TextWrapped = true
	nameLabel.TextColor3 = Color3.fromRGB(240, 238, 232)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.ZIndex = 2
	nameLabel.Parent = button

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "DescLabel"
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 12, 0, 106)
	descLabel.Size = UDim2.new(1, -24, 0, 54)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextWrapped = true
	descLabel.TextColor3 = Color3.fromRGB(188, 196, 209)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.ZIndex = 2
	descLabel.Parent = button

	local voteLabel = Instance.new("TextLabel")
	voteLabel.Name = "VoteLabel"
	voteLabel.BackgroundTransparency = 1
	voteLabel.Position = UDim2.new(0, 12, 1, -24)
	voteLabel.Size = UDim2.new(1, -24, 0, 16)
	voteLabel.Font = Enum.Font.GothamBold
	voteLabel.TextSize = 11
	voteLabel.TextColor3 = Color3.fromRGB(124, 214, 166)
	voteLabel.TextXAlignment = Enum.TextXAlignment.Left
	voteLabel.ZIndex = 2
	voteLabel.Parent = button

	button.MouseButton1Click:Connect(function()
		local option = self.State.Options and self.State.Options[optionIndex]
		if not option or not option.Id then
			return
		end

		self.LocalVotedEntityId = option.Id
		self.RequestVoteRemote:FireServer({
			EntityId = option.Id,
		})
		self:_refreshUi()
	end)

	return {
		Button = button,
		Stroke = stroke,
		Glow = glow,
		FaceDown = faceDown,
		WeightLabel = weightLabel,
		TimerLabel = timerLabel,
		NameLabel = nameLabel,
		DescLabel = descLabel,
		VoteLabel = voteLabel,
	}
end

function VotingController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "VotingUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.World.PlayerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 68)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	_createCorner(panel, 14)
	_createStroke(panel, Color3.fromRGB(76, 69, 57), 1, 0.18)

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Position = UDim2.new(0, 0, 0, 0)
	banner.Size = UDim2.new(1, 0, 0, 52)
	banner.BackgroundColor3 = Color3.fromRGB(24, 22, 19)
	banner.BackgroundTransparency = 0.04
	banner.BorderSizePixel = 0
	banner.Parent = panel
	_createCorner(banner, 14)

	local bannerMask = Instance.new("Frame")
	bannerMask.Size = UDim2.new(1, 0, 0, 16)
	bannerMask.Position = UDim2.new(0, 0, 1, -16)
	bannerMask.BackgroundColor3 = panel.BackgroundColor3
	bannerMask.BorderSizePixel = 0
	bannerMask.Parent = banner

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 18, 0, 10)
	title.Size = UDim2.new(0, 300, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 19
	title.TextColor3 = Color3.fromRGB(240, 238, 232)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Projector Casting"
	title.Parent = banner

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 18, 0, 29)
	subLabel.Size = UDim2.new(0, 500, 0, 14)
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = 11
	subLabel.TextColor3 = Color3.fromRGB(186, 193, 205)
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Parent = banner

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.new(1, -18, 0, 11)
	timerLabel.Size = UDim2.new(0, 120, 0, 18)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 18
	timerLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.Parent = banner

	local hasteLabel = Instance.new("TextLabel")
	hasteLabel.Name = "HasteLabel"
	hasteLabel.BackgroundTransparency = 1
	hasteLabel.AnchorPoint = Vector2.new(1, 0)
	hasteLabel.Position = UDim2.new(1, -18, 0, 31)
	hasteLabel.Size = UDim2.new(0, 200, 0, 12)
	hasteLabel.Font = Enum.Font.GothamBold
	hasteLabel.TextSize = 10
	hasteLabel.TextColor3 = Color3.fromRGB(124, 214, 166)
	hasteLabel.TextXAlignment = Enum.TextXAlignment.Right
	hasteLabel.Parent = banner

	local lineupTitle = Instance.new("TextLabel")
	lineupTitle.BackgroundTransparency = 1
	lineupTitle.Position = UDim2.new(0, 18, 0, 64)
	lineupTitle.Size = UDim2.new(0, 140, 0, 14)
	lineupTitle.Font = Enum.Font.GothamBold
	lineupTitle.TextSize = 11
	lineupTitle.TextColor3 = Color3.fromRGB(242, 212, 103)
	lineupTitle.TextXAlignment = Enum.TextXAlignment.Left
	lineupTitle.Text = "CURRENT CAST"
	lineupTitle.Parent = panel

	local lineupStrip = Instance.new("Frame")
	lineupStrip.Name = "LineupStrip"
	lineupStrip.Position = UDim2.new(0, 18, 0, 84)
	lineupStrip.Size = UDim2.new(0, 548, 0, 34)
	lineupStrip.BackgroundTransparency = 1
	lineupStrip.Parent = panel

	local lineupLayout = Instance.new("UIListLayout")
	lineupLayout.FillDirection = Enum.FillDirection.Horizontal
	lineupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	lineupLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	lineupLayout.Padding = UDim.new(0, 8)
	lineupLayout.Parent = lineupStrip

	local meterTitle = Instance.new("TextLabel")
	meterTitle.BackgroundTransparency = 1
	meterTitle.Position = UDim2.new(0, 584, 0, 64)
	meterTitle.Size = UDim2.new(0, 180, 0, 14)
	meterTitle.Font = Enum.Font.GothamBold
	meterTitle.TextSize = 11
	meterTitle.TextColor3 = Color3.fromRGB(242, 212, 103)
	meterTitle.TextXAlignment = Enum.TextXAlignment.Left
	meterTitle.Text = "DIRECTOR WEIGHT"
	meterTitle.Parent = panel

	local meterFrame = Instance.new("Frame")
	meterFrame.Name = "MeterFrame"
	meterFrame.Position = UDim2.new(0, 584, 0, 84)
	meterFrame.Size = UDim2.new(0, 418, 0, 34)
	meterFrame.BackgroundColor3 = Color3.fromRGB(26, 27, 31)
	meterFrame.BackgroundTransparency = 0.08
	meterFrame.BorderSizePixel = 0
	meterFrame.Parent = panel
	_createCorner(meterFrame, 10)
	_createStroke(meterFrame, Color3.fromRGB(82, 78, 65), 1, 0.2)

	local weightSummary = Instance.new("TextLabel")
	weightSummary.Name = "WeightSummary"
	weightSummary.AnchorPoint = Vector2.new(1, 0.5)
	weightSummary.Position = UDim2.new(1, -10, 0.5, 0)
	weightSummary.Size = UDim2.new(0, 90, 0, 18)
	weightSummary.BackgroundTransparency = 1
	weightSummary.Font = Enum.Font.GothamBold
	weightSummary.TextSize = 12
	weightSummary.TextColor3 = Color3.fromRGB(240, 238, 232)
	weightSummary.TextXAlignment = Enum.TextXAlignment.Right
	weightSummary.Parent = meterFrame

	local segmentFrame = Instance.new("Frame")
	segmentFrame.Name = "SegmentFrame"
	segmentFrame.Position = UDim2.new(0, 10, 0, 8)
	segmentFrame.Size = UDim2.new(1, -112, 0, 18)
	segmentFrame.BackgroundTransparency = 1
	segmentFrame.Parent = meterFrame

	local segmentLayout = Instance.new("UIListLayout")
	segmentLayout.FillDirection = Enum.FillDirection.Horizontal
	segmentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	segmentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	segmentLayout.Padding = UDim.new(0, 6)
	segmentLayout.Parent = segmentFrame

	local weightSegments = {}
	for segmentIndex = 1, 5 do
		local segment = Instance.new("Frame")
		segment.Name = string.format("Segment%d", segmentIndex)
		segment.Size = UDim2.new(0, 56, 0, 18)
		segment.BackgroundColor3 = Color3.fromRGB(44, 46, 54)
		segment.BackgroundTransparency = 0.12
		segment.BorderSizePixel = 0
		segment.Parent = segmentFrame
		_createCorner(segment, 8)
		_createStroke(segment, Color3.fromRGB(76, 79, 86), 1, 0.32)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
		fill.BackgroundTransparency = 0.08
		fill.BorderSizePixel = 0
		fill.Parent = segment
		_createCorner(fill, 8)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 10
		label.TextColor3 = Color3.fromRGB(228, 231, 238)
		label.Text = tostring(segmentIndex)
		label.Parent = segment

		weightSegments[segmentIndex] = {
			Frame = segment,
			Fill = fill,
			Label = label,
		}
	end

	local promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "PromptLabel"
	promptLabel.BackgroundTransparency = 1
	promptLabel.Position = UDim2.new(0, 18, 0, 130)
	promptLabel.Size = UDim2.new(1, -36, 0, 14)
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.TextSize = 11
	promptLabel.TextColor3 = Color3.fromRGB(162, 170, 184)
	promptLabel.TextXAlignment = Enum.TextXAlignment.Left
	promptLabel.Text = "Vote for the next entity to join the reception."
	promptLabel.Parent = panel

	local optionsRow = Instance.new("Frame")
	optionsRow.Name = "OptionsRow"
	optionsRow.BackgroundTransparency = 1
	optionsRow.Position = UDim2.new(0, 18, 0, 148)
	optionsRow.Size = UDim2.new(1, -36, 0, CARD_HEIGHT)
	optionsRow.Parent = panel

	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.FillDirection = Enum.FillDirection.Horizontal
	optionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	optionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Padding = UDim.new(0, 10)
	optionsLayout.Parent = optionsRow

	local optionCards = {}
	for optionIndex = 1, 5 do
		optionCards[optionIndex] = self:_createCard(optionsRow, optionIndex)
	end

	self.UI = {
		Root = screenGui,
		Panel = panel,
		TimerLabel = timerLabel,
		HasteLabel = hasteLabel,
		SubLabel = subLabel,
		PromptLabel = promptLabel,
		LineupStrip = lineupStrip,
		MeterFrame = meterFrame,
		WeightSummary = weightSummary,
		WeightSegments = weightSegments,
		OptionCards = optionCards,
	}
end

function VotingController:_buildOptionSignature(options)
	local parts = {}
	for _, option in ipairs(options or {}) do
		table.insert(parts, tostring(option.Id))
	end
	return table.concat(parts, "|")
end

function VotingController:_clearLineupStrip()
	local strip = self.UI and self.UI.LineupStrip
	if not strip then
		return
	end

	for _, child in ipairs(strip:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

function VotingController:_refreshLineupStrip()
	self:_clearLineupStrip()

	local selected = self.State.SelectedEntityIds or {}
	if #selected <= 0 then
		local placeholder = Instance.new("TextLabel")
		placeholder.BackgroundTransparency = 1
		placeholder.Size = UDim2.new(0, 220, 0, 30)
		placeholder.Font = Enum.Font.Gotham
		placeholder.TextSize = 12
		placeholder.TextColor3 = Color3.fromRGB(156, 162, 174)
		placeholder.TextXAlignment = Enum.TextXAlignment.Left
		placeholder.Text = "No entities locked in yet"
		placeholder.Parent = self.UI.LineupStrip
		return
	end

	for _, entityId in ipairs(selected) do
		local chip = Instance.new("Frame")
		chip.Size = UDim2.new(0, 160, 0, 30)
		chip.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
		chip.BackgroundTransparency = 0.08
		chip.BorderSizePixel = 0
		chip.Parent = self.UI.LineupStrip
		_createCorner(chip, 9)
		_createStroke(chip, Color3.fromRGB(86, 112, 90), 1, 0.2)

		local accent = Instance.new("Frame")
		accent.Size = UDim2.new(0, 4, 1, 0)
		accent.BackgroundColor3 = Color3.fromRGB(124, 214, 166)
		accent.BorderSizePixel = 0
		accent.Parent = chip
		_createCorner(accent, 9)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 12, 0, 0)
		label.Size = UDim2.new(1, -18, 1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextColor3 = Color3.fromRGB(236, 239, 244)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = entityId
		label.Parent = chip
	end
end

function VotingController:_refreshWeightMeter()
	local totalWeight = math.max(0, tonumber(self.State.TotalWeight) or 0)
	local weightTarget = math.max(1, tonumber(self.State.WeightTarget) or 5)

	for segmentIndex, segment in ipairs(self.UI.WeightSegments) do
		local filled = segmentIndex <= totalWeight
		segment.Fill.Size = filled and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0)
		segment.Frame.BackgroundColor3 = filled and Color3.fromRGB(70, 60, 36) or Color3.fromRGB(44, 46, 54)
	end

	self.UI.WeightSummary.Text = string.format("%d / %d", totalWeight, weightTarget)
end

function VotingController:_playRevealSequenceIfNeeded()
	local roundIndex = self.State.RoundIndex
	local optionSignature = self:_buildOptionSignature(self.State.Options or {})
	if roundIndex == self.LastRoundIndex and optionSignature == self.LastOptionSignature then
		return
	end

	self.LastRoundIndex = roundIndex
	self.LastOptionSignature = optionSignature
	self.RevealGeneration += 1
	self.PendingReveal = true
	local generation = self.RevealGeneration

	for _, card in ipairs(self.UI.OptionCards) do
		card.FaceDown.Visible = card.Button.Visible
		card.FaceDown.BackgroundTransparency = 0
		card.Button.BackgroundTransparency = 0.02
	end

	task.spawn(function()
		task.wait(CARD_INITIAL_REVEAL_DELAY)
		if generation ~= self.RevealGeneration then
			return
		end

		for index, card in ipairs(self.UI.OptionCards) do
			if generation ~= self.RevealGeneration then
				return
			end

			if card.Button.Visible then
				task.wait(CARD_REVEAL_DELAY)
				card.Glow.Visible = true
				card.Glow.BackgroundTransparency = 0.82
				TweenService:Create(card.Glow, TweenInfo.new(0.24), {
					BackgroundTransparency = 0.96,
				}):Play()
				TweenService:Create(card.FaceDown, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				}):Play()
				task.delay(0.25, function()
					if generation == self.RevealGeneration and card.Glow then
						card.Glow.Visible = false
					end
				end)
				task.delay(0.19, function()
					if generation == self.RevealGeneration and card.FaceDown then
						card.FaceDown.Visible = false
					end
				end)
			else
				card.FaceDown.Visible = false
			end
		end

		if generation == self.RevealGeneration then
			self.PendingReveal = false
		end
	end)
end

function VotingController:_refreshUi()
	if not self.UI then
		return
	end

	local roundState = self.RoundController and self.RoundController:GetState() or nil
	local shouldShow = self.State.IsActive == true and roundState and roundState.Phase == GamePhase.Voting
	self.UI.Panel.Visible = shouldShow
	if not shouldShow then
		return
	end

	self.UI.TimerLabel.Text = string.format("%ss", tostring(self.State.SecondsLeft or 0))
	self.UI.HasteLabel.Text = (self.State.AllVotesShortened == true) and "All votes cast - draft accelerating" or ""
	self.UI.SubLabel.Text = string.format(
		"Draw %d  |  Votes %d / %d  |  Timer bonus %s",
		tonumber(self.State.RoundIndex) or 1,
		tonumber(self.State.VotedPlayers) or 0,
		tonumber(self.State.EligiblePlayers) or 0,
		_formatTimerValue(self.State.TotalTimerValue or 0)
	)
	self.UI.PromptLabel.Text = string.format(
		"Choose the next entity to join the cast. Remaining weight: %d",
		math.max(0, (tonumber(self.State.WeightTarget) or 5) - (tonumber(self.State.TotalWeight) or 0))
	)

	self:_refreshLineupStrip()
	self:_refreshWeightMeter()

	for index, card in ipairs(self.UI.OptionCards) do
		local option = self.State.Options and self.State.Options[index]
		card.Button.Visible = option ~= nil
		if option then
			local isLocalVote = self.LocalVotedEntityId ~= nil and self.LocalVotedEntityId == option.Id
			local isFaceDown = self.PendingReveal and self.LastRoundIndex == self.State.RoundIndex and self.LastOptionSignature == self:_buildOptionSignature(self.State.Options or {})
			card.WeightLabel.Text = string.format("%d STAR", option.StarRating or option.DirectorWeight or 1)
			card.TimerLabel.Text = _formatTimerValue(option.TimerValue or 0)
			card.NameLabel.Text = option.DisplayName or option.Id or "Unknown"
			card.DescLabel.Text = string.format(
				"Weight %d enters the lineup and adds round time.",
				option.DirectorWeight or option.StarRating or 1
			)
			card.VoteLabel.Text = string.format("%d vote%s%s",
				option.VoteCount or 0,
				(option.VoteCount or 0) == 1 and "" or "s",
				isLocalVote and "  -  YOUR PICK" or ""
			)
			card.Button.BackgroundColor3 = isLocalVote and Color3.fromRGB(37, 42, 52) or Color3.fromRGB(22, 20, 18)
			card.Stroke.Color = isLocalVote and Color3.fromRGB(124, 214, 166) or Color3.fromRGB(92, 79, 61)
			card.Glow.BackgroundColor3 = isLocalVote and Color3.fromRGB(124, 214, 166) or Color3.fromRGB(242, 212, 103)
			card.Glow.Visible = false
			card.FaceDown.Visible = isFaceDown
		end
	end

	self:_playRevealSequenceIfNeeded()
end

return VotingController
