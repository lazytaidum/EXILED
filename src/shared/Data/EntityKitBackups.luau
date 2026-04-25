local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)

local EntityKitBackups = {
	Jiangshi = {
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
						StatusId = StatusEffectId.Stunned,
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
				RequireVisibleTarget = true,
				Weight = 2.15,
				PreferDistanceAbove = 8,
				PreferDistanceAboveBonus = 2.2,
				PreferDistanceBelow = 24,
				PreferDistanceBelowBonus = 0.9,
				Effects = {
					{
						Type = "StartStruggle",
						Targets = "CurrentTarget",
						StartRange = 999,
						RequireLineOfSight = true,
						LungeDistance = 999,
						LungeStopDistance = 0.45,
						OvershootDistance = 3.25,
						LungeSpeed = 0.1,
						MinLungeDuration = 0.45,
						MaxLungeDuration = 1.12,
						LeapHeight = 4.5,
						LeapSharpness = 1.85,
						GrabRange = 2,
						GrabStopDistance = 0.45,
						ImpactDelay = 0.06,
						TargetPredictionSeconds = 0.24,
						ReturnEntityOnBreakFree = true,
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
				RequireVisibleTarget = true,
				MinTargetDistance = 10,
				MaxTargetDistance = 24,
				Weight = 0.7,
				PreferDistanceAbove = 14,
				PreferDistanceAboveBonus = 1.25,
				Effects = {
					{
						Type = "LaunchProjectileStatus",
						Targets = "CurrentTarget",
						VisualName = "QiSealTalisman",
						StatusId = StatusEffectId.Stunned,
						Duration = 3,
						StickDuration = 3,
						Speed = 46,
						TurnRate = 0.18,
						HitRadius = 1,
						Lifetime = 2.4,
						HeightOffset = 3,
						ForwardBiasDistance = 18,
						InitialTrackingWeight = 0.52,
						HomingWeight = 0.38,
						Color = Color3.fromRGB(233, 226, 184),
						VisualSize = Vector3.new(0.7, 1.3, 0.12),
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
						AnchorRootPart = true,
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
						StatusId = StatusEffectId.Power,
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

	SearchingForWisdom = {
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
							DialSpeed = 400,
							SuccessAngleSize = 46,
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
		RoundHooks = {},
	},

	Vimarga = {
		Abilities = {
			Burden = {
				Id = "Burden",
				CastTime = 0.25,
				Cooldown = 18,
				RequireState = "Chase",
				RequirePlayersInRadius = 30,
				Weight = 1.7,
				PreferDistanceBelow = 18,
				PreferDistanceBelowBonus = 1.0,
				Effects = {
					{
						Type = "ApplyStatus",
						Targets = "PlayersInRadius",
						Radius = 30,
						StatusId = StatusEffectId.Hinder,
						Duration = 4,
						Magnitude = 0.30,
					},
					{
						Type = "ApplyStatus",
						Targets = "PlayersInRadius",
						Radius = 30,
						StatusId = StatusEffectId.Helpless,
						Duration = 4,
					},
				},
			},

			WeightOfTheVow = {
				Id = "WeightOfTheVow",
				CastTime = 1.2,
				Cooldown = 26,
				RequireState = "Chase",
				RequireTarget = true,
				RequireVisibleTarget = true,
				MaxTargetDistance = 22,
				Weight = 1.55,
				PreferOnChaseEntry = 1.1,
				PreferDistanceBelow = 20,
				PreferDistanceBelowBonus = 0.8,
				Effects = {
					{
						Type = "DamageTargets",
						Targets = "PlayersNearPosition",
						PositionSource = "CastTargetPosition",
						Radius = 8,
						Range = 999,
						Amount = 15,
					},
					{
						Type = "ApplyStatus",
						Targets = "PlayersNearPosition",
						PositionSource = "CastTargetPosition",
						Radius = 8,
						StatusId = StatusEffectId.Stunned,
						Duration = 3,
					},
				},
			},
		},

		AbilityOrder = {
			"Burden",
			"WeightOfTheVow",
		},

		Passives = {},
		RoundHooks = {},
	},

	Nihil = {
		Abilities = {},
		AbilityOrder = {},
		Passives = {},
		RoundHooks = {},
	},
}

return EntityKitBackups
