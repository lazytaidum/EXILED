local Players = game:GetService("Players")

local UIController = {}
UIController.Name = "UIController"

function UIController:Init(controllers)
	self.Controllers = controllers
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	self.LastPhase = nil
	self.LastTimeLeft = nil
	self.LastOutcome = nil
end

function UIController:Start()
	self:_createUi()

	task.spawn(function()
		while true do
			self:UpdateHUD()
			task.wait(0.1)
		end
	end)
end

function UIController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.PlayerGui

	local phaseCard = Instance.new("Frame")
	phaseCard.Name = "PhaseCard"
	phaseCard.Position = UDim2.new(0, 28, 0, 64)
	phaseCard.Size = UDim2.new(0, 214, 0, 62)
	phaseCard.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	phaseCard.BackgroundTransparency = 0.08
	phaseCard.BorderSizePixel = 0
	phaseCard.Parent = screenGui

	local phaseCorner = Instance.new("UICorner")
	phaseCorner.CornerRadius = UDim.new(0, 12)
	phaseCorner.Parent = phaseCard

	local phaseAccent = Instance.new("Frame")
	phaseAccent.Size = UDim2.new(0, 4, 1, 0)
	phaseAccent.BackgroundColor3 = Color3.fromRGB(103, 194, 255)
	phaseAccent.BorderSizePixel = 0
	phaseAccent.Parent = phaseCard

	local phaseAccentCorner = Instance.new("UICorner")
	phaseAccentCorner.CornerRadius = UDim.new(0, 12)
	phaseAccentCorner.Parent = phaseAccent

	local phaseTitle = Instance.new("TextLabel")
	phaseTitle.BackgroundTransparency = 1
	phaseTitle.Position = UDim2.new(0, 14, 0, 8)
	phaseTitle.Size = UDim2.new(1, -28, 0, 12)
	phaseTitle.Font = Enum.Font.GothamBold
	phaseTitle.TextSize = 11
	phaseTitle.TextXAlignment = Enum.TextXAlignment.Left
	phaseTitle.TextColor3 = Color3.fromRGB(103, 194, 255)
	phaseTitle.Text = "PHASE"
	phaseTitle.Parent = phaseCard

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "PhaseLabel"
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Position = UDim2.new(0, 14, 0, 21)
	phaseLabel.Size = UDim2.new(1, -28, 0, 16)
	phaseLabel.Font = Enum.Font.GothamBold
	phaseLabel.TextSize = 15
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
	phaseLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	phaseLabel.Text = "Preparation"
	phaseLabel.Parent = phaseCard

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Position = UDim2.new(0, 14, 0, 40)
	timerLabel.Size = UDim2.new(1, -28, 0, 14)
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.TextSize = 12
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.TextColor3 = Color3.fromRGB(205, 210, 220)
	timerLabel.Text = "00:00"
	timerLabel.Parent = phaseCard

	local outcomeBanner = Instance.new("Frame")
	outcomeBanner.Name = "OutcomeBanner"
	outcomeBanner.AnchorPoint = Vector2.new(0.5, 0)
	outcomeBanner.Position = UDim2.new(0.5, 0, 0, 18)
	outcomeBanner.Size = UDim2.new(0, 300, 0, 44)
	outcomeBanner.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	outcomeBanner.BackgroundTransparency = 0.08
	outcomeBanner.BorderSizePixel = 0
	outcomeBanner.Visible = false
	outcomeBanner.Parent = screenGui

	local outcomeCorner = Instance.new("UICorner")
	outcomeCorner.CornerRadius = UDim.new(0, 12)
	outcomeCorner.Parent = outcomeBanner

	local outcomeStroke = Instance.new("UIStroke")
	outcomeStroke.Color = Color3.fromRGB(242, 212, 103)
	outcomeStroke.Transparency = 0.35
	outcomeStroke.Thickness = 1
	outcomeStroke.Parent = outcomeBanner

	local outcomeLabel = Instance.new("TextLabel")
	outcomeLabel.Name = "OutcomeLabel"
	outcomeLabel.BackgroundTransparency = 1
	outcomeLabel.Size = UDim2.fromScale(1, 1)
	outcomeLabel.Font = Enum.Font.GothamBold
	outcomeLabel.TextSize = 16
	outcomeLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	outcomeLabel.Text = "Remnants Win"
	outcomeLabel.Parent = outcomeBanner

	self.UI = {
		Root = screenGui,
		PhaseCard = phaseCard,
		PhaseAccent = phaseAccent,
		PhaseTitle = phaseTitle,
		PhaseLabel = phaseLabel,
		TimerLabel = timerLabel,
		OutcomeBanner = outcomeBanner,
		OutcomeLabel = outcomeLabel,
		OutcomeStroke = outcomeStroke,
	}
end

function UIController:UpdateHUD()
	local roundController = self.Controllers.RoundController
	local state = roundController and roundController:GetState()
	if not state or not self.UI then
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
		self.UI.PhaseLabel.Text = tostring(phase)
		self:_applyPhaseStyle(phase)
	end

	if timeChanged then
		self.LastTimeLeft = timeLeft
		self.UI.TimerLabel.Text = self:_formatTime(timeLeft)
	end

	if outcomeChanged or phaseChanged then
		self.LastOutcome = outcome
		local outcomeText = self:_formatOutcomeText(phase, outcome)
		self.UI.OutcomeLabel.Text = outcomeText
		self.UI.OutcomeBanner.Visible = outcomeText ~= ""
	end
end

function UIController:_formatTime(timeLeft)
	local totalSeconds = math.max(0, math.floor(tonumber(timeLeft) or 0))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

function UIController:_applyPhaseStyle(phase)
	local color = Color3.fromRGB(103, 194, 255)
	if phase == "Reception" then
		color = Color3.fromRGB(242, 212, 103)
	elseif phase == "Results" then
		color = Color3.fromRGB(124, 214, 166)
	elseif phase == "Voting" then
		color = Color3.fromRGB(201, 154, 255)
	end

	self.UI.PhaseAccent.BackgroundColor3 = color
	self.UI.PhaseTitle.TextColor3 = color
end

function UIController:_formatOutcomeText(phase, outcome)
	if phase ~= "Results" then
		return ""
	end

	if outcome == "RemnantsWin" then
		return "Remnants Win"
	elseif outcome == "EntitiesWin" then
		return "Entities Win"
	elseif outcome == "Draw" then
		return "Draw"
	end

	return ""
end

return UIController
