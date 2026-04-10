local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)

local JiangshiDefinition = {
	Id = "Jiangshi",
	DisplayName = "Jiangshi",
	StarRating = 1,
	Weight = 1,

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
		InvestigationSpeedMultiplier = 0.9,
	},

	Navigation = {
		PatrolRadius = 32,
		PatrolPointMinDistance = 10,
		PatrolPauseDuration = 1.1,
		ScoutLingerDuration = 1.4,
		SearchSpeedMultiplier = 1.6,
	},

	Targeting = {
		DistanceWeight = 1,
		LineOfSightBonus = 25,
		MemoryBonus = 12,
		CurrentTargetBonus = 18,
		StopDistance = 4,
	},

	Actions = {
		BasicAttack = {
			Id = "FrostbittenVengeance",
			Kind = "BasicAttack",
			Cooldown = 1.0,
			Effects = {
				{
					Type = "ApplyStatus",
					Targets = "CurrentTarget",
					StatusId = "Bleed",
					Duration = 5,
					Tier = 1,
				},
			},
		},

		Abilities = {
			BreathlessHunt = {
				Id = "BreathlessHunt",
				CastTime = 0,
				Cooldown = 60,
				ForbidSearchMode = true,
				RequireState = {
					"Patrol",
					"Scout",
				},
				MinStateDuration = {
					State = "Scout",
					Duration = 1.1,
				},
				Weight = 1.2,
				Chance = 0.55,
				RequirePlayersInRadius = 250,
				RequirePlayersInRadiusForDuration = 2,
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "Self",
						StatusId = "Stunned",
						Duration = 5.5,
					},
					{
						Type = "StartBreathHoldChallenge",
						Duration = 3,
						IndicatorDuration = 2.5,
						ReactionWindow = 1.0,
						Radius = 250,
						HastePerFailure = 0.15,
						HasteDuration = 5,
					},
				},
			},

			BlindHunger = {
				Id = "BlindHunger",
				CastTime = 0.35,
				Cooldown = 30,
				RequireState = "Chase",
				RequireTarget = true,
				MaxTargetDistance = 12,
				Weight = 1.4,
				PreferDistanceBelow = 10,
				PreferDistanceBelowBonus = 1.2,
				Effects = {
					{
						Type = "StartStruggle",
						Targets = "CurrentTarget",
						Duration = 6,
						ProgressPerPress = 0.075,
						DamagePerSecond = 5,
						HealPercentPerSecond = 0.02,
						EntityRecoverStunDuration = 1,
						PeelDuration = 1.2,
						PeelRange = 12,
					},
				},
			},

			QiSeal = {
				Id = "QiSeal",
				CastTime = 0.25,
				Cooldown = 25,
				RequireState = "Chase",
				RequireTarget = true,
				MaxTargetDistance = 24,
				Weight = 1.1,
				PreferDistanceAbove = 10,
				PreferDistanceAboveBonus = 1.1,
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = "Stunned",
						Duration = 3,
					},
				},
			},

			SpiritualFlight = {
				Id = "SpiritualFlight",
				CastTime = 0.9,
				Cooldown = 60,
				RequireState = "Patrol",
				Weight = 0.85,
				Chance = 0.6,
				PreferNoTarget = 0.8,
				Effects = {
					{
						Type = "StartSearchMode",
						SearchId = "SpiritualFlight",
						HeightOffset = 24,
						IgnoreMovementBlockers = true,
						DetectionRadiusMultiplier = 2.2,
					},
				},
			},

		},

		AbilityOrder = {
			"BreathlessHunt",
			"SpiritualFlight",
			"BlindHunger",
			"QiSeal",
		},

		Passives = {
			QiSiphon = {
				Id = "QiSiphon",
				Trigger = "Tick",
				TickInterval = 1.0,
				RequireState = "Chase",
				Effects = {
					{
						Type = "DamageTargets",
						Targets = "VisibleTargets",
						Amount = 1,
						Range = 65,
					},
					{
						Type = "ApplyStatusSelfPerTargetCount",
						CountTargets = "VisibleTargets",
						StatusId = "Power",
						Duration = 1.0,
						Magnitude = 0.01,
					},
					{
						Type = "DrainStaminaTargets",
						Targets = "PlayersInRadius",
						Radius = 20,
						Amount = 0.5,
						Reason = "QiSiphon",
					},
				},
			},

			GrowingSpirit = {
				Id = "GrowingSpirit",
				Trigger = "OnDown",
				Effects = {
					{
						Type = "ApplyPersistentModifierSelf",
						Modifier = "Power",
						Amount = 0.10,
					},
				},
			},
		},

		RoundHooks = {
			ReceptionStart = {
				Trigger = "PhaseChanged",
				Phase = "Reception",
				Effects = {
					{
						Type = "LogMessage",
						Message = "hooked Reception start ({Phase})",
					},
				},
			},

			ObjectivePressure = {
				Trigger = "ObjectiveCompleted",
				Effects = {
					{
						Type = "LogMessage",
						Message = "noticed objective completion: {ObjectiveName}",
					},
				},
			},

			LateReception = {
				Trigger = "TimerThreshold",
				TimeLeft = 60,
				Effects = {
					{
						Type = "LogMessage",
						Message = "noticed low reception timer ({TimeLeft}s left)",
					},
				},
			},
		},
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
			RakingWisdom = {
				Id = "RakingWisdom",
				CastTime = 0.3,
				Cooldown = 24,
				RequireState = "Chase",
				RequireTarget = true,
				MaxTargetDistance = 18,
				Weight = 1.45,
				PreferOnChaseEntry = 1.2,
				PreferDistanceAbove = 10,
				PreferDistanceAboveBonus = 0.8,
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "Self",
						StatusId = StatusEffectId.Haste,
						Duration = 4,
						Magnitude = 0.25,
					},
					{
						Type = "DamageTargets",
						Targets = "CurrentTarget",
						Amount = 18,
						Range = 20,
					},
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.Bleed,
						Duration = 8,
						Tier = 2,
					},
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.DeepWounds,
						Duration = 12,
					},
					{
						Type = "AbsorbAbility",
						Targets = "CurrentTarget",
						Count = 1,
					},
				},
			},

			SeekingWisdom = {
				Id = "SeekingWisdom",
				CastTime = 0.8,
				Cooldown = 35,
				RequireState = "Chase",
				RequireTarget = true,
				MaxTargetDistance = 22,
				Weight = 1.35,
				PreferDistanceAbove = 9,
				PreferDistanceAboveBonus = 0.65,
				Effects = {
					{
						Type = "AbsorbAbility",
						Targets = "CurrentTarget",
						Count = 1,
					},
					{
						Type = "StartStruggle",
						Targets = "CurrentTarget",
						Duration = 6,
						ProgressPerPress = 0.125,
						DamagePerSecond = 7,
						HealPercentPerSecond = 0,
						EntityRecoverStunDuration = 0.6,
						QTE = {
							Type = "TimingDial",
							Prompt = "Hit Space in the success zone",
							SubPrompt = "Break the siphon before your mind is stripped away",
							RequiredKey = "Space",
							ProgressPerPress = 0.125,
							WrongPenalty = 0.075,
							DialSpeed = 265,
							SuccessAngleSize = 42,
						},
					},
				},
			},

			Harvest = {
				Id = "Harvest",
				CastTime = 0.45,
				Cooldown = 30,
				RequireState = "Chase",
				RequireTarget = true,
				MaxTargetDistance = 10,
				Weight = 1.3,
				PreferDistanceBelow = 8,
				PreferDistanceBelowBonus = 0.9,
				Effects = {
					{
						Type = "AbsorbAbility",
						Targets = "CurrentTarget",
						Count = 1,
					},
					{
						Type = "ApplyStatus",
						Targets = "Self",
						StatusId = StatusEffectId.Stunned,
						Duration = 1.35,
					},
					{
						Type = "ApplyStatus",
						Targets = "CurrentTarget",
						StatusId = StatusEffectId.Stunned,
						Duration = 1.25,
					},
					{
						Type = "RepeatDamageTargets",
						Targets = "CurrentTarget",
						Amount = 18,
						Hits = 5,
						Interval = 0.18,
						Range = 12,
					},
				},
			},
		},

		AbilityOrder = {
			"RakingWisdom",
			"SeekingWisdom",
			"Harvest",
		},

		Passives = {},
	},

	GroupEntity = false,
	PrimaryEntity = false,
}

local EntityDefinitions = {
	TestEntity = JiangshiDefinition,
	Jiangshi = JiangshiDefinition,
	SearchingForWisdom = SearchingForWisdomDefinition,
	["Searching for Wisdom"] = SearchingForWisdomDefinition,
}


return EntityDefinitions
