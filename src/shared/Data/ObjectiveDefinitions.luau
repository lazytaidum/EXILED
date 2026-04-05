local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectivePhase = require(ReplicatedStorage.Shared.Enums.ObjectivePhase)
local ObjectiveType = require(ReplicatedStorage.Shared.Enums.ObjectiveType)

local ObjectiveDefinitions = {
	TestObjective = {
		Id = "TestObjective",
		DisplayName = "Test Objective",
		Type = ObjectiveType.MapObjective,
		Phase = ObjectivePhase.Primary,
		
		MaxProgress = 5,
		ChargeRate = 1,
		
		Shared = true,
		StartsEnabled = true,
	},
}

return ObjectiveDefinitions
