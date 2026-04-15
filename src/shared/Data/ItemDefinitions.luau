local ItemDefinitions = {
	Bandage = {
		Id = "Bandage",
		DisplayName = "Bandage",
		ShortDisplayName = "Bandage",
		Kind = "Consumable",
		MaxStack = 2,
		UseDuration = 0.4,
		ViewmodelAssetId = nil,
		ViewmodelGripOffset = CFrame.new(0.18, -0.34, -0.62) * CFrame.Angles(math.rad(0), math.rad(90), 0),
		FirstPersonFov = 70,
		AnimationIds = {
			Equip = nil,
			Idle = nil,
			Fire = nil,
			Reload = nil,
			Aim = nil,
		},
		Effects = {
			{
				Type = "HealSelf",
				Amount = 30,
			},
		},
	},
	TestTonic = {
		Id = "TestTonic",
		DisplayName = "Test Tonic",
		ShortDisplayName = "Tonic",
		Kind = "Consumable",
		MaxStack = 3,
		UseDuration = 0.2,
		ViewmodelAssetId = nil,
		ViewmodelGripOffset = CFrame.new(0.22, -0.32, -0.68) * CFrame.Angles(math.rad(4), math.rad(90), 0),
		FirstPersonFov = 70,
		AnimationIds = {
			Equip = nil,
			Idle = nil,
			Fire = nil,
			Reload = nil,
			Aim = nil,
		},
		Effects = {
			{
				Type = "Status",
				StatusId = "Haste",
				Duration = 5,
				Magnitude = 0.1,
			},
		},
	},
}

return ItemDefinitions
