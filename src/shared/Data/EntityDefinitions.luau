local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)

local JiangshiDefinition = {
	Id = "Jiangshi",
	DisplayName = "Jiangshi",
	StarRating = 1,
	Weight = 1,
	DirectorWeight = 1,
	TimerValue = 180,
	CanAppearInVoting = true,

	Attributes = {
		EntityAttributes.Chase,
		EntityAttributes.Buffing,
		EntityAttributes.Healing,
	},

	Stats = {
		Health = 9500,
		Damage = 15,
		AttackRange = 10,
		AttackInterval = 1.0,
		WalkSpeed = 19,
		ChaseSpeed = 25,
	},

	Perception = {
		TerrorRadius = 90,
		DetectionRadius = 65,
		SearchDetectionRadiusMultiplier = 1.5,
		AttentionDuration = 3,
		ChaseLostSightGraceDuration = 1.2,
		InvestigationSpeedMultiplier = 0.9,
	},

	Navigation = {
		PatrolRadius = 32,
		PatrolPointMinDistance = 10,
		PatrolPauseDuration = 0.9,
		ScoutLingerDuration = 0.22,
		ScoutSearchCommitDuration = 0.5,
		SearchSpeedMultiplier = 1.6,
		UsePathfinding = true,
		PathRecomputeInterval = 0.6,
		PathWaypointTolerance = 2.5,
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentWaypointSpacing = 4,
	},

	Targeting = {
		DistanceWeight = 1,
		LineOfSightBonus = 25,
		MemoryBonus = 12,
		CurrentTargetBonus = 18,
		StopDistance = 4,
	},

	Presentation = {
		AnimationIds = {
			Patrol = "136554754527012",
			Scout = "136554754527012",
			Walk = "136554754527012",
			Move = "136554754527012",
			Attack = "115425961515348",
		},
	},

	Actions = {
		BasicAttack = {
			Id = "FrostbittenVengeance",
			Kind = "BasicAttack",
			Cooldown = 1.0,
			HitDelay = 0.28,
			ActiveDuration = 0.22,
			RecoveryDuration = 0.32,
			MissRecoveryDuration = 0.54,
			WindupSpeedMultiplier = 0.55,
			HitRecoverySpeedMultiplier = 0.75,
			MissRecoverySpeedMultiplier = 0.75,
			HitboxWidth = 5.4,
			HitboxHeight = 4.8,
			HitboxForwardOffset = 4.8,
			HitboxHeightOffset = 2.4,
			CooldownStartsOn = "Hit",
			Effects = {
				{
					Type = "ApplyStatus",
					Targets = "CurrentTarget",
					StatusId = StatusEffectId.Bleed,
					Duration = 5,
					Tier = 1,
				},
			},
		},

		Abilities = {
		},

		Passives = {},

		Death = {
			DespawnDelay = 0.85,
			VisualType = "SmokeBurst",
		},

		RoundHooks = {},
	},

	GroupEntity = false,
	PrimaryEntity = false,
}

local SearchingForWisdomDefinition = {
	Id = "SearchingForWisdom",
	DisplayName = "Searching for Wisdom",
	TemplateName = "SearchingForWisdom",
	StarRating = 2,
	Weight = 2,
	DirectorWeight = 2,
	TimerValue = 240,
	CanAppearInVoting = false,

	Attributes = {
		EntityAttributes.Chase,
		EntityAttributes.StatusApplication,
		EntityAttributes.RangedAttacks,
	},

	Stats = {
		Health = 16000,
		Damage = 15,
		AttackRange = 12,
		AttackInterval = 1.2,
		WalkSpeed = 21,
		ChaseSpeed = 25,
	},

	Perception = {
		TerrorRadius = 105,
		DetectionRadius = 70,
		AttentionDuration = 5,
		InvestigationSpeedMultiplier = 0.95,
	},

	Navigation = {
		PatrolRadius = 34,
		PatrolPointMinDistance = 11,
		PatrolPauseDuration = 1.0,
		ScoutLingerDuration = 1.6,
		SearchSpeedMultiplier = 1.35,
	},

	Targeting = {
		DistanceWeight = 1,
		LineOfSightBonus = 26,
		MemoryBonus = 14,
		CurrentTargetBonus = 18,
		StopDistance = 4,
	},

	Absorption = {
		ResistancePerAbility = 0.15,
		MaxResistance = 0.75,
		FullThreshold = 3,
		RelinquishDamageThreshold = 250,
		Profiles = {
			{
				Id = "StolenBleed",
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.Bleed,
						Duration = 4,
						Tier = 1,
					},
				},
			},
			{
				Id = "StolenHelpless",
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.Helpless,
						Duration = 3,
					},
				},
			},
			{
				Id = "StolenOpenWounds",
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.OpenWounds,
						Duration = 8,
					},
				},
			},
		},
	},

	Actions = {
		BasicAttack = {
			Id = "Till",
			Kind = "BasicAttack",
			Cooldown = 1.2,
			Variants = {
				{
					Id = "TillHoe",
					Damage = 15,
					AttackRange = 12,
					Cooldown = 1.2,
					Effects = {
						{
							Type = "ApplyStatus",
							Targets = "CurrentTarget",
							StatusId = StatusEffectId.Bleed,
							Duration = 8,
							Tier = 1,
						},
					},
				},
				{
					Id = "TillRake",
					Damage = 15,
					AttackRange = 12,
					Cooldown = 1.2,
					Effects = {
						{
							Type = "ApplyStatus",
							Targets = "CurrentTarget",
							StatusId = StatusEffectId.OpenWounds,
							Duration = 10,
						},
						{
							Type = "ApplyStatus",
							Targets = "CurrentTarget",
							StatusId = StatusEffectId.Helpless,
							Duration = 6,
						},
					},
				},
			},
		},

		Abilities = {
		},

		Passives = {},
		RoundHooks = {},

		Death = {
			DespawnDelay = 0.9,
			VisualType = "AshBurst",
		},
	},

	GroupEntity = false,
	PrimaryEntity = false,
}

local VimargaDefinition = {
	Id = "Vimarga",
	DisplayName = "Vimārga",
	TemplateName = "Jiangshi",
	StarRating = 3,
	Weight = 3,
	DirectorWeight = 3,
	TimerValue = 360,
	CanAppearInVoting = false,

	Attributes = {
		EntityAttributes.Chase,
		EntityAttributes.StatusApplication,
	},

	Stats = {
		Health = 32000,
		Damage = 25,
		AttackRange = 13,
		AttackInterval = 1.8,
		WalkSpeed = 21,
		ChaseSpeed = 23,
	},

	Perception = {
		TerrorRadius = 90,
		DetectionRadius = 80,
		AttentionDuration = 2,
		InvestigationSpeedMultiplier = 0.95,
	},

	Navigation = {
		PatrolRadius = 34,
		PatrolPointMinDistance = 10,
		PatrolPauseDuration = 1.0,
		ScoutLingerDuration = 1.2,
		SearchSpeedMultiplier = 1.45,
	},

	Targeting = {
		DistanceWeight = 1,
		LineOfSightBonus = 28,
		MemoryBonus = 10,
		CurrentTargetBonus = 22,
		StopDistance = 5,
	},

	RuntimeAppearance = {
		Color = Color3.fromRGB(111, 92, 73),
		Material = Enum.Material.Fabric,
	},

	Actions = {
		BasicAttack = {
			Id = "Amita",
			Kind = "BasicAttack",
			Cooldown = 1.8,
		},

		Abilities = {
		},

		Passives = {},
		RoundHooks = {},

		Death = {
			DespawnDelay = 1.0,
			VisualType = "SmokeBurst",
			Color = Color3.fromRGB(118, 118, 118),
		},
	},

	GroupEntity = false,
	PrimaryEntity = false,
}

local NihilDefinition = {
	Id = "Nihil",
	DisplayName = "Nihil",
	TemplateName = "Nihil",
	StarRating = 4,
	Weight = 4,
	DirectorWeight = 4,
	TimerValue = 420,
	CanAppearInVoting = false,

	Attributes = {},

	Stats = {
		Health = 1,
		Damage = 0,
		AttackRange = 0,
		AttackInterval = 999,
		WalkSpeed = 0,
		ChaseSpeed = 0,
	},

	Perception = {
		TerrorRadius = 0,
		DetectionRadius = 0,
		AttentionDuration = 0,
		InvestigationSpeedMultiplier = 0,
	},

	Navigation = {
		PatrolRadius = 0,
		PatrolPointMinDistance = 0,
		PatrolPauseDuration = 0,
		ScoutLingerDuration = 0,
		SearchSpeedMultiplier = 0,
	},

	Targeting = {
		DistanceWeight = 0,
		LineOfSightBonus = 0,
		MemoryBonus = 0,
		CurrentTargetBonus = 0,
		StopDistance = 0,
	},

	RuntimeAppearance = {
		Color = Color3.fromRGB(26, 24, 31),
		Material = Enum.Material.SmoothPlastic,
	},

	Actions = {
		BasicAttack = {
			Id = "DormantStrike",
			Kind = "BasicAttack",
			Cooldown = 999,
			Damage = 0,
			AttackRange = 0,
		},

		Abilities = {},
		Passives = {},
	},

	GroupEntity = false,
	PrimaryEntity = true,
}

local EntityDefinitions = {
	Jiangshi = JiangshiDefinition,
	SearchingForWisdom = SearchingForWisdomDefinition,
	Vimarga = VimargaDefinition,
	Nihil = NihilDefinition,
}



return EntityDefinitions
