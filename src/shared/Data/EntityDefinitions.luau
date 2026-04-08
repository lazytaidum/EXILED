local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)

local EntityDefinitions = {
	TestEntity = {
		Id = "TestEntity",
		DisplayName = "Test Entity",
		StarRating = 1,
		Weight = 1,
		
		Attributes = {
			EntityAttributes.Chase
		},
		
		Stats = {
			Health = 9500,
			Damage = 10,
			AttackRange = 10,
			AttackInterval = 1.5,
			WalkSpeed = 10,
			ChaseSpeed = 14,
		},

		Perception = {
			TerrorRadius = 80,
			DetectionRadius = 65,
			AttentionDuration = 3,
			InvestigationSpeedMultiplier = 0.9,
		},

		Targeting = {
			DistanceWeight = 1,
			LineOfSightBonus = 25,
			MemoryBonus = 12,
			CurrentTargetBonus = 18,
			StopDistance = 5,
		},

		Actions = {
			BasicAttack = {
				Id = "FrostbittenVengeance",
				Kind = "BasicAttack",
				Cooldown = 1.5,
			},

			Abilities = {
				BlindHunger = {
					Id = "BlindHunger",
					CastTime = 0.35,
					Cooldown = 30,
					RequireState = "Chase",
					RequireTarget = true,
					Effects = {
						{
							Type = "DamageTargets",
							Targets = "CurrentTarget",
							Range = 16,
							Amount = 20,
							OnHitHasteMultiplier = 1.45,
							OnHitHasteDuration = 1.5,
						},
						{
							Type = "HealSelfPercent",
							Amount = 0.02,
						},
						{
							Type = "InterruptInteraction",
							Targets = "CurrentTarget",
							Reason = "BlindHunger",
						},
						{
							Type = "ApplyStatus",
							Targets = "CurrentTarget",
							StatusId = "Bleed",
							Duration = 5,
							Tier = 1,
						},
					},
				},

				BreathlessHunt = {
					Id = "BreathlessHunt",
					CastTime = 1.0,
					Cooldown = 40,
					RequireAnyCandidate = true,
					Effects = {
						{
							Type = "ApplyStatus",
							Targets = "Self",
							StatusId = "Haste",
							Duration = 5,
							Magnitude = 0.15,
						},
						{
							Type = "RefreshTargetMemory",
							Targets = "NearestVisible",
						},
					},
				},
			},

			AbilityOrder = {
				"BlindHunger",
				"BreathlessHunt",
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
			},
		},
		
		GroupEntity = false,
		PrimaryEntity = false,
	}
}


return EntityDefinitions
