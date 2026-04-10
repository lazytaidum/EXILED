local WeaponDefinitions = {
	BushmanKnife = {
		Id = "BushmanKnife",
		DisplayName = "Bushman Knife",
		ShortDisplayName = "Knife",
		Kind = "Melee",
		Damage = 100,
		Range = 10,
		AttackCooldown = 0.42,
		Durability = 10,
		DurabilityCostPerSwing = 1,
		ArcDotThreshold = 0.15,
	},
	Bat = {
		Id = "Bat",
		DisplayName = "Bat",
		ShortDisplayName = "Bat",
		Kind = "Melee",
		Damage = 120,
		Range = 10,
		AttackCooldown = 0.8,
		Durability = 5,
		DurabilityCostPerSwing = 1,
		ArcDotThreshold = 0.12,
		OnHitStatuses = {
			{
				Id = "Stunned",
				Duration = 1,
			},
		},
	},
	Glock19G5 = {
		Id = "Glock19G5",
		DisplayName = "Glock 19 G5",
		ShortDisplayName = "Glock",
		Kind = "Firearm",
		Damage = 8,
		Range = 220,
		AttackCooldown = 0.2,
		ArcDotThreshold = 0.985,
		HitRadius = 4,
		MagazineSize = 12,
		ReserveAmmo = 36,
		ReloadDuration = 2.2,
	},
}

return WeaponDefinitions
