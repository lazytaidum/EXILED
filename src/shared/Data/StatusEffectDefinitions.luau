local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)

local StatusEffectDefinitions = {
	[StatusEffectId.Haste] = {
		Id = StatusEffectId.Haste,
		DisplayName = "Haste",
		ShortLabel = "HST",
		IsBuff = true,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 5,
		DefaultMagnitude = 0.15,
		Modifiers = {
			Haste = "Magnitude",
		},
	},

	[StatusEffectId.Power] = {
		Id = StatusEffectId.Power,
		DisplayName = "Power",
		ShortLabel = "PWR",
		IsBuff = true,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 5,
		DefaultMagnitude = 0.1,
		Modifiers = {
			Power = "Magnitude",
		},
	},

	[StatusEffectId.Resistance] = {
		Id = StatusEffectId.Resistance,
		DisplayName = "Resistance",
		ShortLabel = "RES",
		IsBuff = true,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 4,
		DefaultMagnitude = 0.1,
		Modifiers = {
			Resistance = "Magnitude",
		},
	},

	[StatusEffectId.Hinder] = {
		Id = StatusEffectId.Hinder,
		DisplayName = "Hinder",
		ShortLabel = "HND",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 3,
		DefaultMagnitude = 0.12,
		Modifiers = {
			Hinder = "Magnitude",
		},
	},

	[StatusEffectId.Stunned] = {
		Id = StatusEffectId.Stunned,
		DisplayName = "Stunned",
		ShortLabel = "STN",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 1.5,
		Flags = {
			Stunned = true,
			BlocksAbilities = true,
			BlocksInteraction = true,
		},
	},

	[StatusEffectId.Fragility] = {
		Id = StatusEffectId.Fragility,
		DisplayName = "Fragility",
		ShortLabel = "FRG",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 4,
		DefaultMagnitude = 0.2,
		Modifiers = {
			Fragility = "Magnitude",
		},
	},

	[StatusEffectId.Weakness] = {
		Id = StatusEffectId.Weakness,
		DisplayName = "Weakness",
		ShortLabel = "WEK",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 4,
		DefaultMagnitude = 0.2,
		Modifiers = {
			Weakness = "Magnitude",
		},
	},

	[StatusEffectId.Broken] = {
		Id = StatusEffectId.Broken,
		DisplayName = "Broken",
		ShortLabel = "BRK",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 6,
		Flags = {
			BlocksHealing = true,
		},
	},

	[StatusEffectId.Helpless] = {
		Id = StatusEffectId.Helpless,
		DisplayName = "Helpless",
		ShortLabel = "HLP",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 4,
		Flags = {
			BlocksAbilities = true,
		},
	},

	[StatusEffectId.Bleed] = {
		Id = StatusEffectId.Bleed,
		DisplayName = "Bleed",
		ShortLabel = "BLD",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 5,
		DefaultTier = 1,
		IsDamageOverTime = true,
		MaxTier = 5,
		TickInterval = 1,
	},

	[StatusEffectId.Poison] = {
		Id = StatusEffectId.Poison,
		DisplayName = "Poison",
		ShortLabel = "PSN",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 4,
		DefaultTier = 1,
		IsDamageOverTime = true,
		MaxTier = 5,
		TickInterval = 0.5,
		Flags = {
			BlocksHealing = true,
		},
	},

	[StatusEffectId.Hemorrhaged] = {
		Id = StatusEffectId.Hemorrhaged,
		DisplayName = "Hemorrhaged",
		ShortLabel = "HEM",
		IsBuff = false,
		AllowedTargets = { "Remnant", "Entity" },
		DefaultDuration = 6,
		IsDamageOverTime = true,
		TickInterval = 1,
		Flags = {
			BlocksHealing = true,
		},
	},

	[StatusEffectId.NilValue] = {
		Id = StatusEffectId.NilValue,
		DisplayName = "nil.value",
		ShortLabel = "NIL",
		IsBuff = false,
		AllowedTargets = { "Remnant" },
		DefaultDuration = 5,
		Flags = {
			BlocksAbilities = true,
			HidesHeartbeat = true,
		},
	},
}

return StatusEffectDefinitions
