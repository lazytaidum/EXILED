local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)

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
				Cooldown = 40,
				RequireState = {
					"Patrol",
					"Scout",
				},
				Weight = 1.2,
				Chance = 0.55,
				RequireAnyCandidate = true,
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
				RequireEnteredChase = false,
				Effects = {
					{
						Type = "StartStruggle",
						Targets = "CurrentTarget",
						Duration = 6,
						ProgressPerPress = 0.075,
						DamagePerSecond = 5,
						HealPercentPerSecond = 0.02,
						EntityRecoverStunDuration = 1,
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
				CastTime = 0.2,
				Cooldown = 60,
				RequireState = "Patrol",
				Weight = 0.85,
				Chance = 0.6,
				PreferNoTarget = 0.8,
				RequireAnyCandidate = false,
				Effects = {
					{
						Type = "StartSearchMode",
						SearchId = "SpiritualFlight",
						Duration = 6,
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
	},

	GroupEntity = false,
	PrimaryEntity = false,
}

local EntityDefinitions = {
	TestEntity = JiangshiDefinition,
	Jiangshi = JiangshiDefinition,
}


return EntityDefinitions
