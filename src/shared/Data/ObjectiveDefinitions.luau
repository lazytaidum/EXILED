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
	DissonanceAnchor = {
		Id = "DissonanceAnchor",
		DisplayName = "Dissonance Anchor",
		Type = ObjectiveType.SecondaryObjective,
		Phase = ObjectivePhase.Secondary,

		MaxProgress = 10,
		ChargeRate = 1,

		Shared = true,
		StartsEnabled = true,

		Completion = {
			ReceptionTimeBonus = 90,
			Message = "Dissonance Anchor stabilized. Reception timer extended.",
		},
	},
	CoalescenceRift = {
		Id = "CoalescenceRift",
		DisplayName = "Coalescence Rift",
		Type = ObjectiveType.MapObjective,
		Phase = ObjectivePhase.Primary,

		MaxProgress = 12,
		ChargeRate = 1,

		Shared = true,
		StartsEnabled = true,

		Completion = {
			EnableEscape = true,
			Message = "Coalescence complete. Escape is open.",
		},
	},
}

return ObjectiveDefinitions
