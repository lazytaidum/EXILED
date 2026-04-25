local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityEffectExecutors = {}

local EXECUTORS = {}

function EXECUTORS.DamageTargets(service, entity, step, context)
	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		service:_damageTargetFromEffect(entity, player, step)
	end
end

function EXECUTORS.RepeatDamageTargets(service, entity, step, context)
	service:_repeatDamageTargetsFromEffect(entity, step, context)
end

function EXECUTORS.HealSelfPercent(_, entity, step)
	entity:HealPercent(step.Amount or 0)
end

function EXECUTORS.ApplyPersistentModifierSelf(_, entity, step)
	if step.Modifier and step.Amount then
		entity:ApplyPersistentModifier(step.Modifier, step.Amount)
	end
end

function EXECUTORS.ApplyTimedModifierSelf(_, entity, step)
	if step.Modifier and step.Amount and step.Duration then
		entity:ApplyTimedModifier(step.Modifier, step.Amount, step.Duration, step.SourceKey or step.Modifier)
	end
end

function EXECUTORS.ApplyTimedModifierSelfPerTarget(service, entity, step, context)
	local targets = service:_resolveEffectTargets(entity, step, context)
	for _ = 1, #targets do
		entity:ApplyTimedModifier(step.Modifier, step.Amount or 0, step.Duration or 0, step.SourceKey or step.Modifier)
	end
end

function EXECUTORS.RefreshTargetMemory(service, entity, step, context)
	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		local character = service.CharacterService:GetCharacterByPlayer(player)
		if character and character.RootPart then
			entity:RememberTarget(player, character.RootPart.Position, true)
		end
	end
end

function EXECUTORS.InterruptInteraction(service, entity, step, context)
	local interactionService = service.InteractionService
	if not interactionService then
		return
	end

	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		interactionService:InterruptInteraction(player, step.Reason or "EntityEffect")
	end
end

function EXECUTORS.ApplyCharacterSpeedMultiplier(service, entity, step, context)
	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		local character = service.CharacterService:GetCharacterByPlayer(player)
		if character then
			character:ApplyTemporarySpeedMultiplier(step.Key or "EntityEffectSlow", step.Multiplier or 1, step.Duration or 0)
		end
	end
end

function EXECUTORS.ApplyStatusPlaceholder(service, entity, step, context)
	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		DebugLog:Log("Entity", string.format("[EntityService] Placeholder status %s applied to %s", tostring(step.StatusId), player.Name))
	end
end

function EXECUTORS.ApplyStatus(service, entity, step, context)
	local statusService = service.StatusEffectService
	if not statusService then
		return
	end

	for _, target in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		statusService:ApplyStatus(target, step.StatusId, {
			Duration = step.Duration,
			Magnitude = step.Magnitude,
			Tier = step.Tier,
			Source = entity.DisplayName,
		})
	end
end

function EXECUTORS.ApplyStatusSelfPerTargetCount(service, entity, step, context)
	local statusService = service.StatusEffectService
	if not statusService then
		return
	end

	local targets = service:_resolveEffectTargets(entity, {
		Targets = step.CountTargets or "VisibleTargets",
	}, context)

	if #targets > 0 then
		statusService:ApplyStatus(entity, step.StatusId, {
			Duration = step.Duration,
			Magnitude = (step.Magnitude or 0) * #targets,
			Tier = step.Tier,
			Source = entity.DisplayName,
		})
	end
end

function EXECUTORS.DrainStaminaTargets(service, entity, step, context)
	if not service.StaminaService then
		return
	end

	for _, target in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		service.StaminaService:DrainStamina(target, step.Amount or 0, step.Reason or entity.DisplayName)
	end
end

function EXECUTORS.StartStruggle(service, entity, step, context)
	service:_startStruggleFromEffect(entity, step, context)
end

function EXECUTORS.BlindHungerLunge(service, entity, step, context)
	service:_startBlindHungerLungeFromEffect(entity, step, context)
end

function EXECUTORS.StartBreathHoldChallenge(service, entity, step)
	if service.BreathHoldService then
		service.BreathHoldService:BeginChallenge(entity, step)
	end
end

function EXECUTORS.StartSearchMode(service, entity, step)
	local searchId = step.SearchId or "SearchMode"
	entity:BeginSearchMode(searchId, step.Duration, {
		HeightOffset = step.HeightOffset,
		IgnoreMovementBlockers = step.IgnoreMovementBlockers,
		DetectionRadiusMultiplier = step.DetectionRadiusMultiplier,
		AnchorRootPart = step.AnchorRootPart,
	})
	service:_pickReachablePatrolDestination(entity)
end

function EXECUTORS.LaunchProjectileStatus(service, entity, step, context)
	service:_launchProjectileStatusFromEffect(entity, step, context)
end

function EXECUTORS.SpawnEntity(service, entity, step, context)
	service:_spawnEntitiesFromEffect(entity, step, context)
end

function EXECUTORS.AbsorbAbility(service, entity, step, context)
	for _, player in ipairs(service:_resolveEffectTargets(entity, step, context)) do
		local totalAbsorbed = entity:AbsorbAbilityFromPlayer(player, step.Count or 1)
		DebugLog:Log("Entity", string.format("[EntityService] %s absorbed from %s (%d total on target)", entity.DisplayName, player.Name, totalAbsorbed))
	end
end

function EXECUTORS.ExtendReceptionTime(service, entity, step)
	if service.RoundHookService then
		service.RoundHookService:ExtendReceptionTime(step.Amount or 0, step.Reason or entity.DisplayName)
	end
end

function EXECUTORS.SetReceptionTime(service, entity, step)
	if service.RoundHookService then
		service.RoundHookService:SetReceptionTime(step.TimeLeft or 0, step.Reason or entity.DisplayName)
	end
end

function EXECUTORS.LogMessage(_, entity, step, context)
	local message = step.Message or "[EntityService] Round hook triggered"
	local hookContext = context and context.RoundHookContext
	if hookContext and hookContext.Phase then
		message = string.gsub(message, "{Phase}", tostring(hookContext.Phase))
	end
	if hookContext and hookContext.TimeLeft ~= nil then
		message = string.gsub(message, "{TimeLeft}", tostring(hookContext.TimeLeft))
	end
	if hookContext and hookContext.Objective and hookContext.Objective.Name then
		message = string.gsub(message, "{ObjectiveName}", tostring(hookContext.Objective.Name))
	end

	DebugLog:Log("Entity", string.format("[EntityService] %s %s", entity.DisplayName, message))
end

function EntityEffectExecutors.Execute(service, entity, step, context)
	local executor = EXECUTORS[step.Type]
	if not executor then
		return false
	end

	executor(service, entity, step, context)
	return true
end

return EntityEffectExecutors
