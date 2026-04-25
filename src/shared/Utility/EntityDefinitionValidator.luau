local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local StatusEffectDefinitions = require(ReplicatedStorage.Shared.Data.StatusEffectDefinitions)
local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)

local EntityDefinitionValidator = {}

local ENTITY_STATES = {
	Dormant = true,
	Patrol = true,
	Scout = true,
	Chase = true,
	Casting = true,
	Stunned = true,
	Rage = true,
	Dead = true,
}

local ABILITY_TARGETING_MODES = {
	CurrentTarget = true,
	NearestVisible = true,
}

local EFFECT_TARGET_MODES = {
	CurrentTarget = true,
	Self = true,
	VisibleTargets = true,
	AllCandidates = true,
	NearestVisible = true,
	PlayersInRadius = true,
	PlayersNearPosition = true,
}

local EFFECT_POSITION_SOURCES = {
	CastTargetPosition = true,
	CurrentTargetPosition = true,
	SelfPosition = true,
	ExplicitPosition = true,
}

local PASSIVE_TRIGGERS = {
	Tick = true,
	OnDown = true,
}

local ROUND_HOOK_TRIGGERS = {
	PhaseChanged = true,
	ObjectiveCompleted = true,
	TimerThreshold = true,
}

local DEATH_VISUAL_TYPES = {
	SmokeBurst = true,
	AshBurst = true,
}

local BASIC_ATTACK_COOLDOWN_START_MODES = {
	Start = true,
	Hit = true,
}

local EFFECT_STEP_TYPES = {
	DamageTargets = true,
	RepeatDamageTargets = true,
	HealSelfPercent = true,
	ApplyPersistentModifierSelf = true,
	ApplyTimedModifierSelf = true,
	ApplyTimedModifierSelfPerTarget = true,
	RefreshTargetMemory = true,
	InterruptInteraction = true,
	ApplyCharacterSpeedMultiplier = true,
	ApplyStatusPlaceholder = true,
	ApplyStatus = true,
	ApplyStatusSelfPerTargetCount = true,
	DrainStaminaTargets = true,
	StartStruggle = true,
	BlindHungerLunge = true,
	StartBreathHoldChallenge = true,
	StartSearchMode = true,
	LaunchProjectileStatus = true,
	SpawnEntity = true,
	AbsorbAbility = true,
	ExtendReceptionTime = true,
	SetReceptionTime = true,
	LogMessage = true,
}

local function _sortedKeys(map)
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function _pushIssue(list, path, message)
	table.insert(list, string.format("%s: %s", path, message))
end

local function _isFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function _validateString(report, path, value, required)
	if value == nil then
		if required then
			_pushIssue(report.Errors, path, "missing required string")
		end
		return false
	end

	if type(value) ~= "string" or value == "" then
		_pushIssue(report.Errors, path, "expected non-empty string")
		return false
	end

	return true
end

local function _validateBoolean(report, path, value)
	if value ~= nil and type(value) ~= "boolean" then
		_pushIssue(report.Errors, path, "expected boolean")
	end
end

local function _validateNumber(report, path, value, options)
	options = options or {}
	if value == nil then
		if options.Required then
			_pushIssue(report.Errors, path, "missing required number")
		end
		return false
	end

	if not _isFiniteNumber(value) then
		_pushIssue(report.Errors, path, "expected finite number")
		return false
	end

	if options.Min ~= nil and value < options.Min then
		_pushIssue(report.Errors, path, string.format("expected number >= %s", tostring(options.Min)))
		return false
	end

	return true
end

local function _validateStateValue(report, path, value)
	if type(value) == "table" then
		for index, stateName in ipairs(value) do
			if not ENTITY_STATES[stateName] then
				_pushIssue(report.Errors, string.format("%s[%d]", path, index), string.format("unsupported state '%s'", tostring(stateName)))
			end
		end
	elseif value ~= nil and not ENTITY_STATES[value] then
		_pushIssue(report.Errors, path, string.format("unsupported state '%s'", tostring(value)))
	end
end

local function _validateEffectStep(report, path, step, context)
	if type(step) ~= "table" then
		_pushIssue(report.Errors, path, "expected effect step table")
		return
	end

	local stepType = step.Type
	if not _validateString(report, path .. ".Type", stepType, true) then
		return
	end

	if not EFFECT_STEP_TYPES[stepType] then
		_pushIssue(report.Errors, path .. ".Type", string.format("unsupported effect type '%s'", tostring(stepType)))
	end

	if step.Targets ~= nil and not EFFECT_TARGET_MODES[step.Targets] then
		_pushIssue(report.Errors, path .. ".Targets", string.format("unsupported target mode '%s'", tostring(step.Targets)))
	end

	if step.CountTargets ~= nil and not EFFECT_TARGET_MODES[step.CountTargets] then
		_pushIssue(report.Errors, path .. ".CountTargets", string.format("unsupported target mode '%s'", tostring(step.CountTargets)))
	end

	if step.PositionSource ~= nil and not EFFECT_POSITION_SOURCES[step.PositionSource] then
		_pushIssue(report.Errors, path .. ".PositionSource", string.format("unsupported position source '%s'", tostring(step.PositionSource)))
	end

	if (step.Targets == "PlayersInRadius" or step.Targets == "PlayersNearPosition") and not _validateNumber(report, path .. ".Radius", step.Radius, {
		Required = true,
		Min = 0,
	}) then
		return
	end

	if (stepType == "ApplyStatus" or stepType == "ApplyStatusSelfPerTargetCount" or stepType == "LaunchProjectileStatus") and step.StatusId ~= nil then
		if context.ValidStatusIds[step.StatusId] ~= true then
			_pushIssue(report.Errors, path .. ".StatusId", string.format("unknown status id '%s'", tostring(step.StatusId)))
		end
	elseif stepType == "ApplyStatus" or stepType == "ApplyStatusSelfPerTargetCount" or stepType == "LaunchProjectileStatus" then
		_pushIssue(report.Errors, path .. ".StatusId", "missing required status id")
	end

	if stepType == "SpawnEntity" then
		if _validateString(report, path .. ".EntityId", step.EntityId, true) and context.ValidEntityKeys[step.EntityId] ~= true then
			_pushIssue(report.Errors, path .. ".EntityId", string.format("unknown entity id '%s'", tostring(step.EntityId)))
		end
	end
end

local function _validateEffectList(report, path, definition, context)
	if definition.Effects == nil then
		return
	end

	if type(definition.Effects) ~= "table" then
		_pushIssue(report.Errors, path .. ".Effects", "expected array of effect steps")
		return
	end

	for key in pairs(definition.Effects) do
		if type(key) ~= "number" then
			_pushIssue(report.Warnings, path .. ".Effects", "contains non-array keys; only numeric step order is executed")
			break
		end
	end

	for index, step in ipairs(definition.Effects) do
		_validateEffectStep(report, string.format("%s.Effects[%d]", path, index), step, context)
	end
end

local function _validateBasicAttack(report, path, basicAttack, context)
	if basicAttack == nil then
		_pushIssue(report.Errors, path, "missing required basic attack")
		return
	end

	if type(basicAttack) ~= "table" then
		_pushIssue(report.Errors, path, "expected basic attack table")
		return
	end

	_validateString(report, path .. ".Id", basicAttack.Id, false)
	_validateNumber(report, path .. ".Cooldown", basicAttack.Cooldown, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitDelay", basicAttack.HitDelay, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".ActiveDuration", basicAttack.ActiveDuration, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".RecoveryDuration", basicAttack.RecoveryDuration, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitRecoveryDuration", basicAttack.HitRecoveryDuration, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".MissRecoveryDuration", basicAttack.MissRecoveryDuration, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".WindupSpeedMultiplier", basicAttack.WindupSpeedMultiplier, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".RecoverySpeedMultiplier", basicAttack.RecoverySpeedMultiplier, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitRecoverySpeedMultiplier", basicAttack.HitRecoverySpeedMultiplier, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".MissRecoverySpeedMultiplier", basicAttack.MissRecoverySpeedMultiplier, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitboxWidth", basicAttack.HitboxWidth, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitboxHeight", basicAttack.HitboxHeight, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitboxForwardOffset", basicAttack.HitboxForwardOffset, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".HitboxHeightOffset", basicAttack.HitboxHeightOffset, {
		Required = false,
	})
	_validateNumber(report, path .. ".AttackConeDegrees", basicAttack.AttackConeDegrees, {
		Required = false,
		Min = 0,
		Max = 180,
	})
	_validateNumber(report, path .. ".AttackSightOriginHeight", basicAttack.AttackSightOriginHeight, {
		Required = false,
	})
	_validateNumber(report, path .. ".AttackSightTargetHeight", basicAttack.AttackSightTargetHeight, {
		Required = false,
	})
	_validateNumber(report, path .. ".AttackSightLowerTargetHeight", basicAttack.AttackSightLowerTargetHeight, {
		Required = false,
	})
	if basicAttack.CooldownStartsOn ~= nil and not BASIC_ATTACK_COOLDOWN_START_MODES[basicAttack.CooldownStartsOn] then
		_pushIssue(report.Errors, path .. ".CooldownStartsOn", string.format("unsupported cooldown start mode '%s'", tostring(basicAttack.CooldownStartsOn)))
	end
	_validateEffectList(report, path, basicAttack, context)

	if basicAttack.Variants ~= nil then
		if type(basicAttack.Variants) ~= "table" then
			_pushIssue(report.Errors, path .. ".Variants", "expected variant array")
			return
		end

		for index, variant in ipairs(basicAttack.Variants) do
			local variantPath = string.format("%s.Variants[%d]", path, index)
			if type(variant) ~= "table" then
				_pushIssue(report.Errors, variantPath, "expected variant table")
			else
				_validateString(report, variantPath .. ".Id", variant.Id, true)
				_validateNumber(report, variantPath .. ".Cooldown", variant.Cooldown, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitDelay", variant.HitDelay, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".ActiveDuration", variant.ActiveDuration, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".RecoveryDuration", variant.RecoveryDuration, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitRecoveryDuration", variant.HitRecoveryDuration, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".MissRecoveryDuration", variant.MissRecoveryDuration, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".WindupSpeedMultiplier", variant.WindupSpeedMultiplier, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".RecoverySpeedMultiplier", variant.RecoverySpeedMultiplier, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitRecoverySpeedMultiplier", variant.HitRecoverySpeedMultiplier, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".MissRecoverySpeedMultiplier", variant.MissRecoverySpeedMultiplier, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitboxWidth", variant.HitboxWidth, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitboxHeight", variant.HitboxHeight, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitboxForwardOffset", variant.HitboxForwardOffset, {
					Required = false,
					Min = 0,
				})
				_validateNumber(report, variantPath .. ".HitboxHeightOffset", variant.HitboxHeightOffset, {
					Required = false,
				})
				_validateNumber(report, variantPath .. ".AttackConeDegrees", variant.AttackConeDegrees, {
					Required = false,
					Min = 0,
					Max = 180,
				})
				_validateNumber(report, variantPath .. ".AttackSightOriginHeight", variant.AttackSightOriginHeight, {
					Required = false,
				})
				_validateNumber(report, variantPath .. ".AttackSightTargetHeight", variant.AttackSightTargetHeight, {
					Required = false,
				})
				_validateNumber(report, variantPath .. ".AttackSightLowerTargetHeight", variant.AttackSightLowerTargetHeight, {
					Required = false,
				})
				if variant.CooldownStartsOn ~= nil and not BASIC_ATTACK_COOLDOWN_START_MODES[variant.CooldownStartsOn] then
					_pushIssue(report.Errors, variantPath .. ".CooldownStartsOn", string.format("unsupported cooldown start mode '%s'", tostring(variant.CooldownStartsOn)))
				end
				_validateEffectList(report, variantPath, variant, context)
			end
		end
	end
end

local function _validateAbility(report, entityPath, abilityId, ability, context)
	local path = string.format("%s.Actions.Abilities.%s", entityPath, tostring(abilityId))
	if type(ability) ~= "table" then
		_pushIssue(report.Errors, path, "expected ability table")
		return
	end

	if _validateString(report, path .. ".Id", ability.Id, true) and ability.Id ~= abilityId then
		_pushIssue(report.Errors, path .. ".Id", string.format("must match ability key '%s'", tostring(abilityId)))
	end

	_validateNumber(report, path .. ".CastTime", ability.CastTime, {
		Required = false,
		Min = 0,
	})
	_validateNumber(report, path .. ".Cooldown", ability.Cooldown, {
		Required = false,
		Min = 0,
	})

	if ability.Targeting ~= nil and not ABILITY_TARGETING_MODES[ability.Targeting] then
		_pushIssue(report.Errors, path .. ".Targeting", string.format("unsupported ability targeting mode '%s'", tostring(ability.Targeting)))
	end

	_validateStateValue(report, path .. ".RequireState", ability.RequireState)
	if type(ability.MinStateDuration) == "table" then
		_validateStateValue(report, path .. ".MinStateDuration.State", ability.MinStateDuration.State)
		_validateNumber(report, path .. ".MinStateDuration.Duration", ability.MinStateDuration.Duration, {
			Required = true,
			Min = 0,
		})
	end
	if type(ability.RequireStateEntry) == "table" then
		_validateStateValue(report, path .. ".RequireStateEntry.State", ability.RequireStateEntry.State)
	elseif ability.RequireStateEntry ~= nil then
		_validateStateValue(report, path .. ".RequireStateEntry", ability.RequireStateEntry)
	end

	_validateEffectList(report, path, ability, context)
end

local function _validatePassive(report, entityPath, passiveId, passive, context)
	local path = string.format("%s.Actions.Passives.%s", entityPath, tostring(passiveId))
	if type(passive) ~= "table" then
		_pushIssue(report.Errors, path, "expected passive table")
		return
	end

	if passive.Id ~= nil and type(passive.Id) == "string" and passive.Id ~= passiveId then
		_pushIssue(report.Warnings, path .. ".Id", string.format("differs from passive key '%s'", tostring(passiveId)))
	end

	if not PASSIVE_TRIGGERS[passive.Trigger] then
		_pushIssue(report.Errors, path .. ".Trigger", string.format("unsupported passive trigger '%s'", tostring(passive.Trigger)))
	end

	_validateStateValue(report, path .. ".RequireState", passive.RequireState)
	if passive.Trigger == "Tick" then
		_validateNumber(report, path .. ".TickInterval", passive.TickInterval, {
			Required = false,
			Min = 0,
		})
	end

	_validateEffectList(report, path, passive, context)
end

local function _validateRoundHook(report, entityPath, hookId, hook)
	local path = string.format("%s.Actions.RoundHooks.%s", entityPath, tostring(hookId))
	if type(hook) ~= "table" then
		_pushIssue(report.Errors, path, "expected round hook table")
		return
	end

	if not ROUND_HOOK_TRIGGERS[hook.Trigger] then
		_pushIssue(report.Errors, path .. ".Trigger", string.format("unsupported round hook trigger '%s'", tostring(hook.Trigger)))
	end

	if hook.Trigger == "PhaseChanged" then
		_validateString(report, path .. ".Phase", hook.Phase, true)
	elseif hook.Trigger == "TimerThreshold" then
		_validateNumber(report, path .. ".TimeLeft", hook.TimeLeft, {
			Required = true,
			Min = 0,
		})
	end
end

local function _validateDeathAction(report, entityPath, deathAction)
	local path = entityPath .. ".Actions.Death"
	if type(deathAction) ~= "table" then
		_pushIssue(report.Errors, path, "expected death action table")
		return
	end

	_validateNumber(report, path .. ".DespawnDelay", deathAction.DespawnDelay, {
		Required = false,
		Min = 0,
	})
	if _validateString(report, path .. ".VisualType", deathAction.VisualType, false) and not DEATH_VISUAL_TYPES[deathAction.VisualType] then
		_pushIssue(report.Errors, path .. ".VisualType", string.format("unsupported death visual '%s'", tostring(deathAction.VisualType)))
	end
end

local function _validateCoreEntityNumbers(report, entityPath, definition)
	local stats = type(definition.Stats) == "table" and definition.Stats or nil
	local perception = type(definition.Perception) == "table" and definition.Perception or nil
	local navigation = type(definition.Navigation) == "table" and definition.Navigation or nil
	local targeting = type(definition.Targeting) == "table" and definition.Targeting or nil

	if stats then
		_validateNumber(report, entityPath .. ".Stats.Health", stats.Health, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Stats.Damage", stats.Damage, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Stats.AttackRange", stats.AttackRange, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Stats.AttackInterval", stats.AttackInterval, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Stats.WalkSpeed", stats.WalkSpeed or stats.MoveSpeed, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Stats.ChaseSpeed", stats.ChaseSpeed, { Required = true, Min = 0 })
	end

	if perception then
		_validateNumber(report, entityPath .. ".Perception.TerrorRadius", perception.TerrorRadius or (stats and stats.TerrorRadius), { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Perception.DetectionRadius", perception.DetectionRadius or (stats and stats.DetectionRadius), { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Perception.AttentionDuration", perception.AttentionDuration or (stats and stats.AttentionLevel), { Required = true, Min = 0 })
	end

	if navigation then
		_validateNumber(report, entityPath .. ".Navigation.PatrolRadius", navigation.PatrolRadius, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Navigation.PatrolPointMinDistance", navigation.PatrolPointMinDistance, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Navigation.PatrolPauseDuration", navigation.PatrolPauseDuration, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Navigation.ScoutLingerDuration", navigation.ScoutLingerDuration, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Navigation.SearchSpeedMultiplier", navigation.SearchSpeedMultiplier, { Required = true, Min = 0 })
	end

	if targeting then
		_validateNumber(report, entityPath .. ".Targeting.DistanceWeight", targeting.DistanceWeight, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Targeting.LineOfSightBonus", targeting.LineOfSightBonus, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Targeting.MemoryBonus", targeting.MemoryBonus, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Targeting.CurrentTargetBonus", targeting.CurrentTargetBonus, { Required = true, Min = 0 })
		_validateNumber(report, entityPath .. ".Targeting.StopDistance", targeting.StopDistance, { Required = true, Min = 0 })
	end
end

local function _validateEntityDefinition(report, entityPath, definition, context)
	if type(definition) ~= "table" then
		_pushIssue(report.Errors, entityPath, "expected entity definition table")
		return
	end

	local definitionIdIsValid = _validateString(report, entityPath .. ".Id", definition.Id, true)
	_validateString(report, entityPath .. ".DisplayName", definition.DisplayName, true)
	_validateString(report, entityPath .. ".TemplateName", definition.TemplateName, false)
	_validateNumber(report, entityPath .. ".StarRating", definition.StarRating, {
		Required = true,
		Min = 0,
	})
	_validateNumber(report, entityPath .. ".Weight", definition.Weight, {
		Required = true,
		Min = 0,
	})
	_validateNumber(report, entityPath .. ".DirectorWeight", definition.DirectorWeight, {
		Required = true,
		Min = 0,
	})
	_validateNumber(report, entityPath .. ".TimerValue", definition.TimerValue, {
		Required = true,
		Min = 0,
	})
	_validateBoolean(report, entityPath .. ".CanAppearInVoting", definition.CanAppearInVoting)
	_validateBoolean(report, entityPath .. ".GroupEntity", definition.GroupEntity)
	_validateBoolean(report, entityPath .. ".PrimaryEntity", definition.PrimaryEntity)

	if definition.GroupEntity == true and definition.PrimaryEntity == true then
		_pushIssue(report.Errors, entityPath, "entity cannot be both GroupEntity and PrimaryEntity")
	end

	if definitionIdIsValid and context.EntityDefinitions[definition.Id] ~= definition then
		_pushIssue(report.Errors, entityPath .. ".Id", "entity definition must be addressable by its Id in EntityDefinitions")
	end

	if type(definition.Attributes) ~= "table" then
		_pushIssue(report.Errors, entityPath .. ".Attributes", "expected attribute array")
	else
		local seenAttributes = {}
		for index, attribute in ipairs(definition.Attributes) do
			local attributePath = string.format("%s.Attributes[%d]", entityPath, index)
			if not context.ValidAttributes[attribute] then
				_pushIssue(report.Errors, attributePath, string.format("unknown attribute '%s'", tostring(attribute)))
			elseif seenAttributes[attribute] then
				_pushIssue(report.Warnings, attributePath, string.format("duplicate attribute '%s'", tostring(attribute)))
			else
				seenAttributes[attribute] = true
			end
		end
	end

	for _, blockName in ipairs({ "Stats", "Perception", "Navigation", "Targeting", "Actions" }) do
		if type(definition[blockName]) ~= "table" then
			_pushIssue(report.Errors, entityPath .. "." .. blockName, "expected table")
		end
	end

	_validateCoreEntityNumbers(report, entityPath, definition)

	local actions = type(definition.Actions) == "table" and definition.Actions or {}
	_validateBasicAttack(report, entityPath .. ".Actions.BasicAttack", actions.BasicAttack, context)

	if type(actions.Abilities) == "table" then
		for abilityId, ability in pairs(actions.Abilities) do
			_validateAbility(report, entityPath, abilityId, ability, context)
		end
	else
		_pushIssue(report.Errors, entityPath .. ".Actions.Abilities", "expected table")
	end

	if actions.AbilityOrder ~= nil then
		if type(actions.AbilityOrder) ~= "table" then
			_pushIssue(report.Errors, entityPath .. ".Actions.AbilityOrder", "expected table when provided")
		else
			local seenAbilityOrder = {}
			for index, abilityId in ipairs(actions.AbilityOrder) do
				local orderPath = string.format("%s.Actions.AbilityOrder[%d]", entityPath, index)
				if type(abilityId) ~= "string" then
					_pushIssue(report.Errors, orderPath, "expected ability id string")
				elseif type(actions.Abilities) ~= "table" or actions.Abilities[abilityId] == nil then
					_pushIssue(report.Errors, orderPath, string.format("references unknown ability '%s'", tostring(abilityId)))
				elseif seenAbilityOrder[abilityId] then
					_pushIssue(report.Errors, orderPath, string.format("duplicates ability '%s'", tostring(abilityId)))
				else
					seenAbilityOrder[abilityId] = true
				end
			end
		end
	end

	if type(actions.Passives) == "table" then
		for passiveId, passive in pairs(actions.Passives) do
			_validatePassive(report, entityPath, passiveId, passive, context)
		end
	else
		_pushIssue(report.Errors, entityPath .. ".Actions.Passives", "expected table")
	end

	if actions.RoundHooks ~= nil then
		if type(actions.RoundHooks) ~= "table" then
			_pushIssue(report.Errors, entityPath .. ".Actions.RoundHooks", "expected table")
		else
			for hookId, hook in pairs(actions.RoundHooks) do
				_validateRoundHook(report, entityPath, hookId, hook)
				_validateEffectList(report, string.format("%s.Actions.RoundHooks.%s", entityPath, tostring(hookId)), hook, context)
			end
		end
	end

	if actions.Death ~= nil then
		_validateDeathAction(report, entityPath, actions.Death)
	end
end

function EntityDefinitionValidator.ValidateAll(entityDefinitions, statusEffectDefinitions, entityAttributes)
	entityDefinitions = entityDefinitions or EntityDefinitions
	statusEffectDefinitions = statusEffectDefinitions or StatusEffectDefinitions
	entityAttributes = entityAttributes or EntityAttributes

	local report = {
		Errors = {},
		Warnings = {},
		CanonicalDefinitionCount = 0,
		AliasCount = 0,
	}

	local validAttributes = {}
	for _, attribute in pairs(entityAttributes) do
		validAttributes[attribute] = true
	end

	local validStatusIds = {}
	for statusId in pairs(statusEffectDefinitions) do
		validStatusIds[statusId] = true
	end

	local validEntityKeys = {}
	for key in pairs(entityDefinitions) do
		validEntityKeys[key] = true
	end

	local canonicalEntries = {}
	local groupedDefinitions = {}
	for _, key in ipairs(_sortedKeys(entityDefinitions)) do
		local definition = entityDefinitions[key]
		local group = groupedDefinitions[definition]
		if not group then
			group = {
				Definition = definition,
				Keys = {},
			}
			groupedDefinitions[definition] = group
			table.insert(canonicalEntries, group)
		end
		table.insert(group.Keys, key)
	end

	table.sort(canonicalEntries, function(a, b)
		local aKey = (type(a.Definition) == "table" and a.Definition.Id) or a.Keys[1] or ""
		local bKey = (type(b.Definition) == "table" and b.Definition.Id) or b.Keys[1] or ""
		return tostring(aKey) < tostring(bKey)
	end)

	local context = {
		EntityDefinitions = entityDefinitions,
		ValidAttributes = validAttributes,
		ValidStatusIds = validStatusIds,
		ValidEntityKeys = validEntityKeys,
	}

	report.CanonicalDefinitionCount = #canonicalEntries
	report.AliasCount = math.max(0, #_sortedKeys(entityDefinitions) - report.CanonicalDefinitionCount)

	for _, entry in ipairs(canonicalEntries) do
		local definition = entry.Definition
		local entityPath = string.format("EntityDefinitions[%s]", tostring((type(definition) == "table" and definition.Id) or entry.Keys[1]))
		_validateEntityDefinition(report, entityPath, definition, context)
	end

	report.IsValid = #report.Errors == 0
	if report.IsValid then
		report.Summary = string.format(
			"[EntityValidator] Validated %d canonical entity definitions (%d aliases).",
			report.CanonicalDefinitionCount,
			report.AliasCount
		)
	else
		local lines = {
			string.format(
				"[EntityValidator] Found %d error(s) and %d warning(s) across %d canonical entity definitions.",
				#report.Errors,
				#report.Warnings,
				report.CanonicalDefinitionCount
			),
		}
		for _, issue in ipairs(report.Errors) do
			table.insert(lines, "ERROR: " .. issue)
		end
		for _, issue in ipairs(report.Warnings) do
			table.insert(lines, "WARNING: " .. issue)
		end
		report.Summary = table.concat(lines, "\n")
	end

	return report
end

return EntityDefinitionValidator
