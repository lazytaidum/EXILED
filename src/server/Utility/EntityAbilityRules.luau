local EntityAbilityRules = {}

local ENTITY_STATE = {
	Chase = "Chase",
}

local function matchesRequiredState(currentState, requiredState)
	if type(requiredState) == "table" then
		for _, stateName in ipairs(requiredState) do
			if currentState == stateName then
				return true
			end
		end
		return false
	end

	return currentState == requiredState
end

function EntityAbilityRules.SelectAbilityTarget(service, entity, ability, candidates)
	if not ability.Targeting or ability.Targeting == "CurrentTarget" then
		return entity:GetTarget()
	end

	if ability.Targeting == "NearestVisible" then
		local bestPlayer = nil
		local bestDistance = math.huge
		for _, candidate in ipairs(candidates) do
			if candidate.IsVisible and candidate.Distance < bestDistance then
				bestDistance = candidate.Distance
				bestPlayer = candidate.Player
			end
		end
		return bestPlayer
	end

	return entity:GetTarget()
end

function EntityAbilityRules.AbilityStartsStruggle(service, ability)
	for _, step in ipairs(service:_getEffectSteps(ability)) do
		if step.Type == "StartStruggle" or step.Type == "BlindHungerLunge" then
			return true
		end
	end

	return false
end

function EntityAbilityRules.CanUseAbility(service, entity, ability, candidates)
	local statusService = service.StatusEffectService
	if statusService and not statusService:CanUseAbilities(entity) then
		return false
	end

	if ability.RequireState and not matchesRequiredState(entity:GetState(), ability.RequireState) then
		return false
	end

	if ability.MinStateDuration then
		local currentState = entity:GetState()
		local requiredState = ability.MinStateDuration.State
		local minimumDuration = ability.MinStateDuration.Duration or 0
		if (not requiredState or currentState == requiredState) and entity:GetStateDuration() < minimumDuration then
			return false
		end
	end

	if ability.RequireTarget and not entity:GetTarget() then
		return false
	end

	if service.StruggleService and EntityAbilityRules.AbilityStartsStruggle(service, ability) then
		local struggleTarget = EntityAbilityRules.SelectAbilityTarget(service, entity, ability, candidates)
		if not struggleTarget then
			return false
		end

		if not service.StruggleService:CanBeginStruggle(entity, struggleTarget) then
			return false
		end
	end

	local visibleTargetCount = service:_countVisibleTargets(entity)
	if ability.RequireVisibleTarget and visibleTargetCount <= 0 then
		return false
	end

	if ability.MinVisibleTargets and visibleTargetCount < ability.MinVisibleTargets then
		return false
	end

	if ability.MaxVisibleTargets and visibleTargetCount > ability.MaxVisibleTargets then
		return false
	end

	if ability.Range then
		local targetPlayer = entity:GetTarget()
		if not targetPlayer then
			return false
		end

		local targetCharacter = service.CharacterService:GetCharacterByPlayer(targetPlayer)
		if not targetCharacter or not targetCharacter.RootPart then
			return false
		end

		if not entity:IsInRange(targetCharacter.RootPart.Position, ability.Range) then
			return false
		end
	end

	local targetDistance = service:_getTargetDistance(entity, entity:GetTarget())
	if ability.MinTargetDistance and (targetDistance == nil or targetDistance < ability.MinTargetDistance) then
		return false
	end

	if ability.MaxTargetDistance and (targetDistance == nil or targetDistance > ability.MaxTargetDistance) then
		return false
	end

	if ability.RequireSearchMode and not entity:IsSearchModeActive(ability.RequireSearchMode == true and nil or ability.RequireSearchMode) then
		return false
	end

	if ability.ForbidSearchMode and entity.SearchMode then
		return false
	end

	if ability.RequireTargetMemory and not entity:GetTargetMemory(entity:GetTarget()) then
		return false
	end

	if ability.RequireStateEntry then
		local stateName = ability.RequireStateEntry.State or ability.RequireStateEntry
		local window = type(ability.RequireStateEntry) == "table" and ability.RequireStateEntry.Window or nil
		if not entity:JustEnteredState(stateName, window) then
			return false
		end
	end

	if ability.RequireEnteredChase and not entity:JustEnteredState(ENTITY_STATE.Chase, ability.RequireEnteredChaseWindow or 0.5) then
		return false
	end

	if ability.Chance and entity.Random:NextNumber() > ability.Chance then
		return false
	end

	if ability.RequireAnyCandidate == true and #candidates <= 0 then
		return false
	end

	if ability.RequirePlayersInRadius and service:_countPlayersInRadius(entity, ability.RequirePlayersInRadius) <= 0 then
		return false
	end

	if ability.RequirePlayersInRadiusForDuration then
		local radius = ability.RequirePlayersInRadius or ability.PlayerPresenceRadius
		if not radius then
			return false
		end

		local hasNearbyPlayers = service:_countPlayersInRadius(entity, radius) > 0
		local conditionKey = string.format("PlayersInRadius:%s:%s", tostring(ability.Id or "Ability"), tostring(radius))
		entity:SetConditionActive(conditionKey, hasNearbyPlayers)
		if not hasNearbyPlayers then
			return false
		end

		if entity:GetConditionDuration(conditionKey) < ability.RequirePlayersInRadiusForDuration then
			return false
		end
	end

	return true
end

function EntityAbilityRules.ScoreAbilitySelection(service, entity, abilityId, ability, candidates)
	local _ = candidates
	local weight = ability.Weight or 1
	local targetDistance = service:_getTargetDistance(entity, entity:GetTarget())

	if ability.Priority then
		weight += ability.Priority
	end

	if ability.PreferOnChaseEntry and entity:JustEnteredState(ENTITY_STATE.Chase, ability.ChaseEntryWindow or 0.5) then
		weight += ability.PreferOnChaseEntry
	end

	if ability.PreferVisibleTargets and service:_countVisibleTargets(entity) > 0 then
		weight += ability.PreferVisibleTargets
	end

	if ability.PreferDistanceBelow and targetDistance and targetDistance <= ability.PreferDistanceBelow then
		weight += ability.PreferDistanceBelowBonus or 1
	end

	if ability.PreferDistanceAbove and targetDistance and targetDistance >= ability.PreferDistanceAbove then
		weight += ability.PreferDistanceAboveBonus or 1
	end

	if ability.PreferSearchMode and entity.SearchMode then
		weight += ability.PreferSearchMode
	end

	if ability.PreferNoTarget and not entity:GetTarget() then
		weight += ability.PreferNoTarget
	end

	return math.max(0.01, weight)
end

return EntityAbilityRules
