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
	local mainHUD = self.PlayerGui:WaitForChild("MainHUD")
	self.Container = mainHUD:WaitForChild("Container")
	self.PhaseLabel = self.Container:WaitForChild("PhaseLabel")
	self.TimerLabel = self.Container:WaitForChild("TimerLabel")
	self.OutcomeLabel = self.Container:WaitForChild("OutcomeLabel")
	
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
		self.PhaseLabel.Text = "Phase: " .. tostring(phase)
	end

	if timeChanged then
		self.LastTimeLeft = timeLeft
		self.TimerLabel.Text = "Time: " .. tostring(timeLeft) 
	end

	if outcomeChanged or phaseChanged then
		self.LastOutcome = outcome
		self.OutcomeLabel.Text = self:_formatOutcomeText(phase, outcome)
		
		if self.OutcomeLabel.Text == "" then
			self.OutcomeLabel.Visible = false
		else
			self.OutcomeLabel.Visible = true
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
		return "Remnants Win"
	elseif outcome == "EntitiesWin" then
		return "Entities Win"
	elseif outcome == "Draw" then
		return "Draw"
	end
	
	return ""
end

return UIController
