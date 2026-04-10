local ItemDefinitions = {
	Bandage = {
		Id = "Bandage",
		DisplayName = "Bandage",
		ShortDisplayName = "Bandage",
		Kind = "Consumable",
		MaxStack = 2,
		UseDuration = 0.4,
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
