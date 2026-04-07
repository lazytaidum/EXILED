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
					Range = 16,
					Targeting = "CurrentTarget",
					Effect = "DamageTarget",
					Damage = 20,
				},

				BreathlessHunt = {
					Id = "BreathlessHunt",
					CastTime = 1.0,
					Cooldown = 40,
					RequireAnyCandidate = true,
					Effect = "SelfBuff",
					Modifier = "Haste",
					Amount = 0.15,
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
					RequireState = "Chase",
					Effect = "SelfBuffFromVisibleTargets",
					Modifier = "Power",
					AmountPerTarget = 0.01,
				},
			},
		},
		
		GroupEntity = false,
		PrimaryEntity = false,
	}
}


return EntityDefinitions
