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
			local roundController = self.Controllers.RoundController
			local state = roundController and roundController:GetState()
			
			if state then
				print(string.format("[UI] Phase: %s | TimeLeft: %d | Outcome: %s", tostring(state.Phase), tonumber(state.TimeLeft) or 0, tostring(state.Outcome or "None")))
			end
			
			self:UpdateHUD()
			task.wait(0.1)
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
