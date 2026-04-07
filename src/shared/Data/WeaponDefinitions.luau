local WeaponDefinitions = {
	Glock45 = {
		Id = "Glock45",
		DisplayName = "Glock 45",
		MagazineSize = 17,
		ReserveAmmo = 51,
		ReloadDuration = 1.35,
		FireCooldown = 0.16,
		Damage = 20,
		Range = 300,
		Spread = 0.015,
		ViewModelLab = {
			Preview = {
				WeaponSize = Vector3.new(0.55, 0.75, 1.7),
				AccentSize = Vector3.new(0.22, 0.22, 0.55),
				WeaponColor = Color3.fromRGB(44, 44, 52),
				AccentColor = Color3.fromRGB(229, 174, 74),
				RightArmColor = Color3.fromRGB(220, 184, 146),
				LeftArmColor = Color3.fromRGB(196, 160, 124),
				TorsoColor = Color3.fromRGB(73, 90, 122),
			},
			Transforms = {
				WeaponOffset = {
					Position = { X = 0.28, Y = -0.72, Z = -1.5 },
					Rotation = { X = -8, Y = 6, Z = 2 },
				},
				AimOffset = {
					Position = { X = 0, Y = 0.02, Z = 0.52 },
					Rotation = { X = 0, Y = 0, Z = 0 },
				},
				RightHandGrip = {
					Position = { X = 0.38, Y = -0.15, Z = 0.08 },
					Rotation = { X = 12, Y = 90, Z = 72 },
				},
				LeftHandGrip = {
					Position = { X = -0.38, Y = -0.04, Z = 0.62 },
					Rotation = { X = -6, Y = -88, Z = -78 },
				},
				RightShoulder = {
					Position = { X = 0.68, Y = -0.34, Z = 0.08 },
					Rotation = { X = 0, Y = 0, Z = 0 },
				},
				LeftShoulder = {
					Position = { X = -0.68, Y = -0.28, Z = 0.1 },
					Rotation = { X = 0, Y = 0, Z = 0 },
				},
			},
		},
	},
}

return WeaponDefinitions
