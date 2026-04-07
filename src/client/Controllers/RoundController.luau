local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RoundController = {}
RoundController.Name = "RoundController"

function RoundController:Init()
	self.CurrentState = {
		Phase = "Unknown",
		TimeLeft = 0,
		Outcome = "None",
	}
end

function RoundController:Start()
	local remotesFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
	local roundStateChanged = remotesFolder:WaitForChild(RemoteNames.RoundStateChanged)
	local roundTimerUpdated = remotesFolder:WaitForChild(RemoteNames.RoundTimerUpdated)

	roundStateChanged.OnClientEvent:Connect(function(state)
		self.CurrentState = {
			Phase = state.Phase or "Unknown",
			TimeLeft = state.TimeLeft or 0,
			Outcome = state.Outcome or "None",
		}
		
		DebugLog:Log("ClientRound", "[RoundController] Received state:", state.Phase, state.TimeLeft)
	end)
	
	roundTimerUpdated.OnClientEvent:Connect(function(state)
		self.CurrentState = {
			Phase = state.Phase or self.CurrentState.Phase,
			TimeLeft = state.TimeLeft or 0,
			Outcome = state.Outcome or self.CurrentState.Outcome,
		}
	end)

	DebugLog:Log("ClientRound", "[RoundController] Started")
end

function RoundController:GetState()
	return self.CurrentState
end

return RoundController
