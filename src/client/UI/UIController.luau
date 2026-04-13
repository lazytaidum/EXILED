local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local GamePhase = require(game:GetService("ReplicatedStorage").Shared.Enums.GamePhase)
local RoundOutcome = require(game:GetService("ReplicatedStorage").Shared.Enums.RoundOutcome)

local UIController = {}
UIController.Name = "UIController"

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

function UIController:Init(controllers)
	self.Controllers = controllers
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	self.LastPhase = nil
	self.LastTimeLeft = nil
	self.LastOutcome = nil
	self.ActivePhaseBannerId = 0
	self.ActiveOutcomeBannerId = 0
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

	local bannerStack = Instance.new("Frame")
	bannerStack.Name = "BannerStack"
	bannerStack.AnchorPoint = Vector2.new(0.5, 0)
	bannerStack.Position = UDim2.new(0.5, 0, 0, 18)
	bannerStack.Size = UDim2.new(0, 420, 0, 188)
	bannerStack.BackgroundTransparency = 1
	bannerStack.Parent = screenGui

	local bannerLayout = Instance.new("UIListLayout")
	bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	bannerLayout.Padding = UDim.new(0, 8)
	bannerLayout.Parent = bannerStack

	local phaseCard = Instance.new("Frame")
	phaseCard.Name = "PhaseCard"
	phaseCard.Position = UDim2.new(0, 28, 0, 64)
	phaseCard.Size = UDim2.new(0, 226, 0, 96)
	phaseCard.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	phaseCard.BackgroundTransparency = 0.08
	phaseCard.BorderSizePixel = 0
	phaseCard.Parent = screenGui
	_createCorner(phaseCard, 12)

	local phaseAccent = Instance.new("Frame")
	phaseAccent.Size = UDim2.new(0, 4, 1, 0)
	phaseAccent.BackgroundColor3 = Color3.fromRGB(103, 194, 255)
	phaseAccent.BorderSizePixel = 0
	phaseAccent.Parent = phaseCard
	_createCorner(phaseAccent, 12)

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
	phaseLabel.Position = UDim2.new(0, 14, 0, 22)
	phaseLabel.Size = UDim2.new(1, -98, 0, 18)
	phaseLabel.Font = Enum.Font.GothamBold
	phaseLabel.TextSize = 16
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
	phaseLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	phaseLabel.Text = "Lobby"
	phaseLabel.Parent = phaseCard

	local phaseSubLabel = Instance.new("TextLabel")
	phaseSubLabel.Name = "PhaseSubLabel"
	phaseSubLabel.BackgroundTransparency = 1
	phaseSubLabel.Position = UDim2.new(0, 14, 0, 42)
	phaseSubLabel.Size = UDim2.new(1, -28, 0, 40)
	phaseSubLabel.Font = Enum.Font.Gotham
	phaseSubLabel.TextSize = 11
	phaseSubLabel.TextXAlignment = Enum.TextXAlignment.Left
	phaseSubLabel.TextWrapped = true
	phaseSubLabel.TextYAlignment = Enum.TextYAlignment.Top
	phaseSubLabel.TextColor3 = Color3.fromRGB(205, 210, 220)
	phaseSubLabel.Text = "Awaiting next phase"
	phaseSubLabel.Parent = phaseCard

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundColor3 = Color3.fromRGB(26, 28, 34)
	timerLabel.BackgroundTransparency = 0.12
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.new(1, -8, 0, 14)
	timerLabel.Size = UDim2.new(0, 72, 0, 24)
	timerLabel.BorderSizePixel = 0
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 15
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	timerLabel.Text = "00:00"
	timerLabel.Parent = phaseCard
	_createCorner(timerLabel, 8)

	local announcementBanner = Instance.new("Frame")
	announcementBanner.Name = "AnnouncementBanner"
	announcementBanner.LayoutOrder = 1
	announcementBanner.Size = UDim2.new(0, 420, 0, 74)
	announcementBanner.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	announcementBanner.BackgroundTransparency = 1
	announcementBanner.BorderSizePixel = 0
	announcementBanner.ClipsDescendants = true
	announcementBanner.Visible = false
	announcementBanner.Parent = bannerStack
	_createCorner(announcementBanner, 14)
	local announcementStroke = _createStroke(announcementBanner, Color3.fromRGB(242, 212, 103), 1, 0.2)

	local announcementTitle = Instance.new("TextLabel")
	announcementTitle.Name = "AnnouncementTitle"
	announcementTitle.BackgroundTransparency = 1
	announcementTitle.Position = UDim2.new(0, 16, 0, 12)
	announcementTitle.Size = UDim2.new(1, -32, 0, 18)
	announcementTitle.Font = Enum.Font.GothamBold
	announcementTitle.TextSize = 18
	announcementTitle.TextColor3 = Color3.fromRGB(242, 212, 103)
	announcementTitle.Text = "Reception Begins"
	announcementTitle.Parent = announcementBanner

	local announcementSub = Instance.new("TextLabel")
	announcementSub.Name = "AnnouncementSub"
	announcementSub.BackgroundTransparency = 1
	announcementSub.Position = UDim2.new(0, 16, 0, 34)
	announcementSub.Size = UDim2.new(1, -32, 0, 18)
	announcementSub.Font = Enum.Font.Gotham
	announcementSub.TextSize = 12
	announcementSub.TextColor3 = Color3.fromRGB(230, 233, 239)
	announcementSub.Text = "The entities have entered the theatre."
	announcementSub.Parent = announcementBanner

	local outcomeBanner = Instance.new("Frame")
	outcomeBanner.Name = "OutcomeBanner"
	outcomeBanner.LayoutOrder = 2
	outcomeBanner.Size = UDim2.new(0, 360, 0, 88)
	outcomeBanner.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	outcomeBanner.BackgroundTransparency = 1
	outcomeBanner.BorderSizePixel = 0
	outcomeBanner.ClipsDescendants = true
	outcomeBanner.Visible = false
	outcomeBanner.Parent = bannerStack
	_createCorner(outcomeBanner, 14)
	local outcomeStroke = _createStroke(outcomeBanner, Color3.fromRGB(242, 212, 103), 1, 0.16)

	local outcomeOverline = Instance.new("TextLabel")
	outcomeOverline.Name = "OutcomeOverline"
	outcomeOverline.BackgroundTransparency = 1
	outcomeOverline.Position = UDim2.new(0, 16, 0, 12)
	outcomeOverline.Size = UDim2.new(1, -32, 0, 12)
	outcomeOverline.Font = Enum.Font.GothamBold
	outcomeOverline.TextSize = 11
	outcomeOverline.TextColor3 = Color3.fromRGB(242, 212, 103)
	outcomeOverline.Text = "ROUND OUTCOME"
	outcomeOverline.Parent = outcomeBanner

	local outcomeLabel = Instance.new("TextLabel")
	outcomeLabel.Name = "OutcomeLabel"
	outcomeLabel.BackgroundTransparency = 1
	outcomeLabel.Position = UDim2.new(0, 16, 0, 30)
	outcomeLabel.Size = UDim2.new(1, -32, 0, 24)
	outcomeLabel.Font = Enum.Font.GothamBold
	outcomeLabel.TextSize = 22
	outcomeLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	outcomeLabel.Text = "Remnants Win"
	outcomeLabel.Parent = outcomeBanner

	local outcomeSub = Instance.new("TextLabel")
	outcomeSub.Name = "OutcomeSub"
	outcomeSub.BackgroundTransparency = 1
	outcomeSub.Position = UDim2.new(0, 16, 0, 56)
	outcomeSub.Size = UDim2.new(1, -32, 0, 16)
	outcomeSub.Font = Enum.Font.Gotham
	outcomeSub.TextSize = 12
	outcomeSub.TextColor3 = Color3.fromRGB(230, 233, 239)
	outcomeSub.Text = "The reception has concluded."
	outcomeSub.Parent = outcomeBanner

	self.UI = {
		Root = screenGui,
		BannerStack = bannerStack,
		PhaseCard = phaseCard,
		PhaseAccent = phaseAccent,
		PhaseTitle = phaseTitle,
		PhaseLabel = phaseLabel,
		PhaseSubLabel = phaseSubLabel,
		TimerLabel = timerLabel,
		AnnouncementBanner = announcementBanner,
		AnnouncementTitle = announcementTitle,
		AnnouncementSub = announcementSub,
		AnnouncementStroke = announcementStroke,
		OutcomeBanner = outcomeBanner,
		OutcomeOverline = outcomeOverline,
		OutcomeLabel = outcomeLabel,
		OutcomeSub = outcomeSub,
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
	local outcome = state.Outcome or RoundOutcome.None
	local phaseChanged = phase ~= self.LastPhase
	local timeChanged = timeLeft ~= self.LastTimeLeft
	local outcomeChanged = outcome ~= self.LastOutcome

	if phaseChanged then
		self.LastPhase = phase
		self.UI.PhaseLabel.Text = tostring(phase)
		self.UI.PhaseSubLabel.Text = self:_formatPhaseSubtext(phase)
		self:_applyPhaseStyle(phase)
		self:_handlePhaseArrival(phase)
	end

	if timeChanged then
		self.LastTimeLeft = timeLeft
		self.UI.TimerLabel.Text = self:_formatTime(timeLeft)
		self:_applyTimerStyle(phase, timeLeft)
	end

	if outcomeChanged or phaseChanged then
		self.LastOutcome = outcome
		self:_refreshOutcomeBanner(phase, outcome)
	end
end

function UIController:_formatTime(timeLeft)
	local totalSeconds = math.max(0, math.floor(tonumber(timeLeft) or 0))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

function UIController:_formatPhaseSubtext(phase)
	if phase == GamePhase.Lobby then
		return "Awaiting the next gathering"
	elseif phase == GamePhase.Voting then
		return "The projector is casting the next reception"
	elseif phase == GamePhase.Preparation then
		return "Prepare your route, allies, and loadout"
	elseif phase == GamePhase.Reception then
		return "The theatre is no longer safe"
	elseif phase == GamePhase.Results then
		return "The night settles on the stage"
	end

	return "Awaiting next phase"
end

function UIController:_applyPhaseStyle(phase)
	local color = Color3.fromRGB(103, 194, 255)
	if phase == GamePhase.Reception then
		color = Color3.fromRGB(242, 212, 103)
	elseif phase == GamePhase.Results then
		color = Color3.fromRGB(124, 214, 166)
	elseif phase == GamePhase.Voting then
		color = Color3.fromRGB(201, 154, 255)
	elseif phase == GamePhase.Lobby then
		color = Color3.fromRGB(180, 188, 204)
	end

	self.UI.PhaseAccent.BackgroundColor3 = color
	self.UI.PhaseTitle.TextColor3 = color
end

function UIController:_applyTimerStyle(phase, timeLeft)
	local color = Color3.fromRGB(240, 240, 240)
	if phase == GamePhase.Reception and tonumber(timeLeft) and tonumber(timeLeft) <= 20 then
		color = Color3.fromRGB(242, 212, 103)
	elseif phase == GamePhase.Results then
		color = Color3.fromRGB(124, 214, 166)
	elseif phase == GamePhase.Voting then
		color = Color3.fromRGB(201, 154, 255)
	end

	self.UI.TimerLabel.TextColor3 = color
end

function UIController:_handlePhaseArrival(phase)
	if phase == GamePhase.Reception then
		self:_showAnnouncement("Reception Begins", "The entities have entered the theatre.", Color3.fromRGB(242, 212, 103))
	elseif phase == GamePhase.Results then
		self:_showAnnouncement("Curtain Falls", "The reception has reached its end.", Color3.fromRGB(124, 214, 166))
	end
end

function UIController:_showAnnouncement(title, subtext, color)
	self.ActivePhaseBannerId += 1
	local bannerId = self.ActivePhaseBannerId
	local banner = self.UI.AnnouncementBanner

	self.UI.AnnouncementTitle.Text = title
	self.UI.AnnouncementSub.Text = subtext
	self.UI.AnnouncementTitle.TextColor3 = color
	self.UI.AnnouncementStroke.Color = color

	banner.Visible = true
	banner.Size = UDim2.new(0, 420, 0, 0)
	banner.BackgroundTransparency = 0.2
	self.UI.AnnouncementTitle.TextTransparency = 0
	self.UI.AnnouncementSub.TextTransparency = 0

	TweenService:Create(banner, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 420, 0, 74),
		BackgroundTransparency = 0.06,
	}):Play()

	task.delay(1.7, function()
		if bannerId ~= self.ActivePhaseBannerId then
			return
		end

		TweenService:Create(banner, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 420, 0, 0),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(self.UI.AnnouncementTitle, TweenInfo.new(0.18), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(self.UI.AnnouncementSub, TweenInfo.new(0.18), {
			TextTransparency = 1,
		}):Play()

		task.delay(0.24, function()
			if bannerId == self.ActivePhaseBannerId then
				banner.Visible = false
			end
		end)
	end)
end

function UIController:_refreshOutcomeBanner(phase, outcome)
	if phase ~= GamePhase.Results then
		self.UI.OutcomeBanner.Visible = false
		return
	end

	local label, subtext, color = self:_formatOutcomePresentation(outcome)
	if label == "" then
		self.UI.OutcomeBanner.Visible = false
		return
	end

	self.UI.OutcomeLabel.Text = label
	self.UI.OutcomeSub.Text = subtext
	self.UI.OutcomeLabel.TextColor3 = color
	self.UI.OutcomeOverline.TextColor3 = color
	self.UI.OutcomeStroke.Color = color
	self:_showOutcomeBanner()
end

function UIController:_showOutcomeBanner()
	self.ActiveOutcomeBannerId += 1
	local bannerId = self.ActiveOutcomeBannerId
	local banner = self.UI.OutcomeBanner

	banner.Visible = true
	banner.Size = UDim2.new(0, 330, 0, 0)
	banner.BackgroundTransparency = 0.18

	TweenService:Create(banner, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 360, 0, 88),
		BackgroundTransparency = 0.06,
	}):Play()

	task.delay(0.22, function()
		if bannerId ~= self.ActiveOutcomeBannerId then
			return
		end

		TweenService:Create(banner, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 348, 0, 84),
		}):Play()
	end)
end

function UIController:_formatOutcomePresentation(outcome)
	if outcome == RoundOutcome.RemnantsWin then
		return "Remnants Win", "Enough survivors escaped the reception alive.", Color3.fromRGB(124, 214, 166)
	elseif outcome == RoundOutcome.EntitiesWin then
		return "Entities Win", "The theatre claimed every remaining remnant.", Color3.fromRGB(242, 212, 103)
	elseif outcome == RoundOutcome.Draw then
		return "Draw", "The reception expired before a decisive end.", Color3.fromRGB(103, 194, 255)
	end

	return "", "", Color3.fromRGB(240, 240, 240)
end

return UIController
