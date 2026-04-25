local RemnantDefinitions = {
	Baam = {
		Id = "Baam",
		DisplayName = "Baam",
		Archetype = "Insight",
		Difficulty = 1.5,
		DefaultFragments = 3, -- Temporary developer value until Soul Fragments are fully implemented.
		ThirdPersonAnimationIds = {
			Idle = "94253937973725",
			Walk = "104033904275982",
			Run = "96694263435744",
			CrouchIdle = "81820278647674",
			CrouchWalk = "71047579720711",
		},
		Abilities = {
			Ability1 = {
				Id = "WatchersEye",
				DisplayName = "Watcher's Eye",
				Keybind = "Q",
				Cooldown = 30,
				Description = "Reveal available subjects across the map.",
			},
			Ability2 = {
				Id = "Refixture",
				DisplayName = "Refixture",
				Keybind = "E",
				Cooldown = 45,
				Description = "Hologram gun burst.",
				IsImplemented = true,
				DamageMultiplier = 0.5,
				Range = 160,
				ShotInterval = 0.06,
				EntityInterrupt = {
					Reason = "Refixture",
					CancelCast = true,
					CancelSpecialMovement = true,
					CancelSearchMode = true,
					CancelProjectiles = true,
				},
			},
			Ability3 = {
				Id = "Watchtower",
				DisplayName = "Watchtower",
				Keybind = "F",
				Cooldown = 60,
				Description = "Deploy a reveal zone.",
				Duration = 50,
				Radius = 300,
				OwnerRadius = 450,
				IsImplemented = true,
			},
		},
	},
}

return RemnantDefinitions
