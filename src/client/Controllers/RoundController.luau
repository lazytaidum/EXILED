local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RoundController = {}
RoundController.Name = "RoundController"

function RoundController:Init()
	local defaultPhase = WorldModeResolver.IsWeaponLab() and GamePhase.Preparation or "Unknown"
	self.CurrentState = {
		Phase = defaultPhase,
		TimeLeft = 0,
		Outcome = "None",
	}
end

function RoundController:Start()
	local roundStateChanged = self.World.Remotes:WaitForChild(RemoteNames.RoundStateChanged)
	local roundTimerUpdated = self.World.Remotes:WaitForChild(RemoteNames.RoundTimerUpdated)

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
