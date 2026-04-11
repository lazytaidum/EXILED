local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseEntity = require(ServerScriptService.Server.Classes.BaseEntity)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityService = {}
EntityService.Name = "EntityService"
EntityService.Dependencies = {
	"RoundManager",
	"RoundHookService",
	"CharacterService",
	"InterestService",
	"SpawnService",
	"StaminaService",
	"StatusEffectService",
	"InteractionService",
	"StruggleService",
	"BreathHoldService",
}

local ENTITY_STATE = {
	Dormant = "Dormant",
	Patrol = "Patrol",
	Scout = "Scout",
	Chase = "Chase",
	Casting = "Casting",
	Stunned = "Stunned",
	Rage = "Rage",
}

local RECENT_HIT_DEBUG_DURATION = 0.75

function EntityService:Init(services)
	self.Services = services
	self.Entities = {}
	self.EntityTemplates = {}
	self.UpdateInterval = 0.2
	self.NextRoundHookRuntimeId = 0

	self.EntitiesFolder = Workspace:WaitForChild("Entities")
	self.MapBounds = Workspace:FindFirstChild("MapBounds")
	self.TemplateSourceFolder = ServerStorage:FindFirstChild("EntityTemplates")
	if not self.TemplateSourceFolder then
		self.TemplateSourceFolder = Instance.new("Folder")
		self.TemplateSourceFolder.Name = "EntityTemplates"
		self.TemplateSourceFolder.Parent = ServerStorage
	end

	self.TemplateStorage = Instance.new("Folder")
	self.TemplateStorage.Name = "EntityTemplateCache"
	self.TemplateStorage.Parent = ServerStorage
	self.SelectedRoundEntityIds = {}
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
end

function EntityService:Start()
	self:_registerExistingTemplates()
	self:_registerExistingEntities()

	task.spawn(function()
		self:_runEntityLoop()
	end)

	DebugLog:Log("Entity", "[EntityService] Started")
end

function EntityService:_registerExistingTemplates()
	for _, model in ipairs(self.TemplateSourceFolder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart then
			local definition = EntityDefinitions[model.Name]
			self:_cacheEntityTemplate(model, definition)
		end
	end
end

function EntityService:_registerExistingEntities()
	for _,model in ipairs(self.EntitiesFolder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart then
			self:_registerEntityModel(model)
		end
	end
end

function EntityService:_cacheEntityTemplate(model, definition)
	local templateName = (definition and definition.TemplateName) or (definition and definition.Id) or model.Name
	if self.EntityTemplates[templateName] then
		return
	end

	local template = model:Clone()
	template.Name = templateName
	template.Parent = self.TemplateStorage

	local aliases = {
		templateName,
		model.Name,
		definition and definition.Id or nil,
		definition and definition.TemplateName or nil,
	}

	for _, alias in ipairs(aliases) do
		if alias and not self.EntityTemplates[alias] then
			self.EntityTemplates[alias] = template
		end
	end
end

function EntityService:_registerEntityModel(model, runtimeData)
	local definition = EntityDefinitions[model.Name] or EntityDefinitions[(runtimeData and runtimeData.EntityId) or model.Name]
	local entity = BaseEntity.new(model, definition, self.Services, runtimeData)

	self:_cacheEntityTemplate(model, definition)
	table.insert(self.Entities, entity)
	self:_syncDebugAttributes(entity)

	DebugLog:Log("Entity", string.format(
		"[EntityService] Registered entity: %s | Stars: %d | Weight: %d",
		entity.DisplayName,
		entity.StarRating,
		entity.Weight
	))

	return entity
end

function EntityService:_runEntityLoop()
	while true do
		for index = #self.Entities, 1, -1 do
			local entity = self.Entities[index]
			if entity:HasExpired() then
				self:_despawnEntity(entity, "Expired")
			elseif entity.IsActive then
				self:_updateEntity(entity, self.UpdateInterval)
			end
		end

		task.wait(self.UpdateInterval)
	end
end

function EntityService:_updateEntity(entity, deltaTime)
	entity:ClearExpiredMemory()
	entity:UpdateActiveEffects()

	local candidates = self:_collectTargetCandidates(entity)
	local bestCandidate = self:_selectBestCandidate(entity, candidates)
	self:_updateTargetSelection(entity, bestCandidate)
	self:_updateCasting(entity)
	self:_updateEntityState(entity)
	self:_tickEntityPassives(entity, deltaTime)
	self:_tryUseAbility(entity, candidates)
	self:_updateEntityMovement(entity, deltaTime)
	self:_tryBasicAttack(entity)
	self:_syncDebugAttributes(entity)
end

function EntityService:_collectTargetCandidates(entity)
	local roundManager = self.RoundManager
	local characterService = self.CharacterService

	if not roundManager or not characterService then
		return {}
	end

	local entityPosition = entity:GetPosition()
	if not entityPosition then
		return {}
	end

	local candidates = {}

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				local livePosition = character.RootPart.Position
				local distance = (livePosition - entityPosition).Magnitude
				local isFullyAbsorbed = entity.IsPlayerFullyAbsorbed and entity:IsPlayerFullyAbsorbed(player)
				local canSenseTarget = entity.IgnoreLineOfSightForDetection or self:_hasLineOfSight(entity, character)
				local isVisible = distance <= entity:GetDetectionRange() and canSenseTarget
				local isDetected = isVisible or isFullyAbsorbed
				local memory = entity:GetTargetMemory(player)
				local candidatePosition = livePosition
				local candidateDistance = distance

				if not isDetected and memory then
					candidatePosition = memory.LastKnownPosition
					candidateDistance = (candidatePosition - entityPosition).Magnitude
				end

				if isDetected or memory then
					table.insert(candidates, {
						Player = player,
						Character = character,
						Position = candidatePosition,
						Distance = candidateDistance,
						IsVisible = isVisible,
						IsDetected = isDetected,
						IsFullyAbsorbed = isFullyAbsorbed,
						Memory = memory,
					})
				end
			end
		end
	end

	return candidates
end

function EntityService:_selectBestCandidate(entity, candidates)
	local bestCandidate = nil
	local bestScore = -math.huge

	for _, candidate in ipairs(candidates) do
		local score = self:_scoreTargetCandidate(entity, candidate)
		candidate.Score = score

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	return bestCandidate
end

function EntityService:_scoreTargetCandidate(entity, candidate)
	local score = 0
	local effectiveRange = math.max(entity:GetDetectionRange() * 1.25, entity.AttackRange)

	score += math.max(0, effectiveRange - candidate.Distance) * entity.DistanceWeight

	if candidate.IsVisible then
		score += entity.LineOfSightBonus
	end

	if candidate.Memory then
		score += entity.MemoryBonus
	end

	if candidate.IsDetected and not candidate.IsVisible then
		score += 22
	end

	if candidate.IsFullyAbsorbed then
		score += 36
	end

	if entity:GetTarget() == candidate.Player then
		score += entity.TargetRetentionBonus
	end

	return score
end

function EntityService:_updateTargetSelection(entity, bestCandidate)
	if not bestCandidate then
		entity:SetTarget(nil)
		return
	end

	if bestCandidate.IsVisible then
		entity:SetTarget(bestCandidate.Player, bestCandidate.Position, true)
		entity:EndSearchMode()
	else
		entity:SetTrackedTarget(bestCandidate.Player)
	end
end

function EntityService:_updateEntityState(entity)
	if entity:IsCasting() then
		entity:EnterState(ENTITY_STATE.Casting)
		return
	end

	local targetPlayer = entity:GetTarget()
	if not targetPlayer then
		if entity:GetState() ~= ENTITY_STATE.Patrol then
			entity:PickPatrolDestination()
		end
		entity:EnterState(ENTITY_STATE.Patrol)
		return
	end

	local memory = entity:GetTargetMemory(targetPlayer)
	if not memory then
		entity:SetTarget(nil)
		entity:PickPatrolDestination()
		entity:EnterState(ENTITY_STATE.Patrol)
		return
	end

	if entity:HasAttentionOnTarget(targetPlayer) then
		local lastKnownPosition = entity:GetTargetLastKnownPosition()
		local hasRecentlySeenTarget = entity:GetTimeSinceTargetWasVisible(targetPlayer) <= entity.ChaseLostSightGraceDuration
		local shouldKeepChasing = hasRecentlySeenTarget

		if lastKnownPosition and not shouldKeepChasing then
			shouldKeepChasing = not entity:IsNearPosition(lastKnownPosition, entity:GetStopDistance() + 1)
		end

		entity:EnterState(shouldKeepChasing and ENTITY_STATE.Chase or ENTITY_STATE.Scout)
	else
		entity:EnterState(ENTITY_STATE.Scout)
	end
end

function EntityService:_updateCasting(entity)
	local activeCast = entity:GetActiveCast()
	if not activeCast then
		return
	end

	local statusService = self.StatusEffectService
	if statusService and not statusService:CanUseAbilities(entity) then
		entity:CancelCast()
		self:_syncDebugAttributes(entity)
		return
	end

	if os.clock() < activeCast.EndsAt then
		return
	end

	entity:CompleteCast()
	self:_resolveAbility(entity, activeCast.Definition, activeCast.TargetPlayer)
end

function EntityService:_tickEntityPassives(entity, deltaTime)
	for passiveId, passive in pairs(entity:GetPassiveDefinitions()) do
		if passive.Trigger ~= "Tick" then
			continue
		end

		if not self:_passiveCanRun(entity, passive) then
			continue
		end

		local cooldownKey = string.format("Passive:%s", passiveId)
		local tickInterval = passive.TickInterval or deltaTime
		if not entity:IsCooldownReady(cooldownKey) then
			continue
		end

		local context = self:_createEffectContext(entity, entity:GetTarget(), nil, deltaTime)
		self:_executeEffectSteps(entity, passive, context)
		entity:SetCooldown(cooldownKey, tickInterval)
	end
end

function EntityService:_passiveCanRun(entity, passive)
	if passive.RequireState then
		local currentState = entity:GetState()
		local requiredState = passive.RequireState
		if type(requiredState) == "table" then
			local matches = false
			for _, stateName in ipairs(requiredState) do
				if currentState == stateName then
					matches = true
					break
				end
			end

			if not matches then
				return false
			end
		elseif currentState ~= requiredState then
			return false
		end
	end

	return true
end

function EntityService:_tryUseAbility(entity, candidates)
	if entity:IsCasting() then
		return
	end

	local abilityId, ability = self:_selectAbility(entity, candidates)
	if not abilityId or not ability then
		return
	end

	local targetPlayer = self:_selectAbilityTarget(entity, ability, candidates)
	entity:BeginCast(abilityId, ability, targetPlayer)
	entity:SetCooldown(abilityId, ability.Cooldown or 0)

	DebugLog:Log("Entity", string.format("[EntityService] %s began %s", entity.DisplayName, abilityId))
	self:_markLastAbility(entity, abilityId)
end

function EntityService:_selectAbility(entity, candidates)
	local abilities = entity:GetAbilityDefinitions()
	local available = {}
	local orderIndexById = {}

	for index, abilityId in ipairs(entity:GetAbilityOrder()) do
		orderIndexById[abilityId] = index
	end

	for abilityId, ability in pairs(abilities) do
		if entity:CanUseAbility(abilityId) and self:_canUseAbility(entity, ability, candidates) then
			table.insert(available, {
				Id = abilityId,
				Ability = ability,
				Weight = self:_scoreAbilitySelection(entity, abilityId, ability, candidates),
				OrderIndex = orderIndexById[abilityId] or math.huge,
			})
		end
	end

	if #available == 0 then
		return nil, nil
	end

	return self:_pickWeightedAbility(entity, available)
end

function EntityService:_canUseAbility(entity, ability, candidates)
	local statusService = self.StatusEffectService
	if statusService and not statusService:CanUseAbilities(entity) then
		return false
	end

	if ability.RequireState then
		local currentState = entity:GetState()
		local requireState = ability.RequireState
		if type(requireState) == "table" then
			local matches = false
			for _, stateName in ipairs(requireState) do
				if currentState == stateName then
					matches = true
					break
				end
			end
			if not matches then
				return false
			end
		elseif currentState ~= requireState then
			return false
		end
	end

	if ability.MinStateDuration then
		local currentState = entity:GetState()
		local requiredState = ability.MinStateDuration.State
		local minimumDuration = ability.MinStateDuration.Duration or 0
		if requiredState and currentState ~= requiredState then
			-- This condition only applies while the entity is in the specified state.
		elseif entity:GetStateDuration() < minimumDuration then
			return false
		end
	end

	if ability.RequireTarget and not entity:GetTarget() then
		return false
	end

	if self.StruggleService and self:_abilityStartsStruggle(ability) then
		local struggleTarget = self:_selectAbilityTarget(entity, ability, candidates)
		if not struggleTarget then
			return false
		end

		if not self.StruggleService:CanBeginStruggle(entity, struggleTarget) then
			return false
		end
	end

	if ability.RequireVisibleTarget and self:_countVisibleTargets(entity) <= 0 then
		return false
	end

	if ability.MinVisibleTargets and self:_countVisibleTargets(entity) < ability.MinVisibleTargets then
		return false
	end

	if ability.MaxVisibleTargets and self:_countVisibleTargets(entity) > ability.MaxVisibleTargets then
		return false
	end

	if ability.Range then
		local targetPlayer = entity:GetTarget()
		if not targetPlayer then
			return false
		end

		local targetCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
		if not targetCharacter or not targetCharacter.RootPart then
			return false
		end

		if not entity:IsInRange(targetCharacter.RootPart.Position, ability.Range) then
			return false
		end
	end

	local targetDistance = self:_getTargetDistance(entity, entity:GetTarget())
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

	if ability.RequirePlayersInRadius and self:_countPlayersInRadius(entity, ability.RequirePlayersInRadius) <= 0 then
		return false
	end

	if ability.RequirePlayersInRadiusForDuration then
		local radius = ability.RequirePlayersInRadius or ability.PlayerPresenceRadius
		if not radius then
			return false
		end

		local hasNearbyPlayers = self:_countPlayersInRadius(entity, radius) > 0
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

function EntityService:_scoreAbilitySelection(entity, abilityId, ability, candidates)
	local weight = ability.Weight or 1
	local targetDistance = self:_getTargetDistance(entity, entity:GetTarget())

	if ability.Priority then
		weight += ability.Priority
	end

	if ability.PreferOnChaseEntry and entity:JustEnteredState(ENTITY_STATE.Chase, ability.ChaseEntryWindow or 0.5) then
		weight += ability.PreferOnChaseEntry
	end

	if ability.PreferVisibleTargets and self:_countVisibleTargets(entity) > 0 then
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

function EntityService:_abilityStartsStruggle(ability)
	for _, step in ipairs(self:_getEffectSteps(ability)) do
		if step.Type == "StartStruggle" then
			return true
		end
	end

	return false
end

function EntityService:_pickWeightedAbility(entity, available)
	table.sort(available, function(a, b)
		if a.Weight == b.Weight then
			return a.OrderIndex < b.OrderIndex
		end
		return a.Weight > b.Weight
	end)

	local totalWeight = 0
	for _, entry in ipairs(available) do
		totalWeight += entry.Weight
	end

	local roll = entity.Random:NextNumber(0, totalWeight)
	local cursor = 0
	for _, entry in ipairs(available) do
		cursor += entry.Weight
		if roll <= cursor then
			return entry.Id, entry.Ability
		end
	end

	local fallback = available[1]
	return fallback.Id, fallback.Ability
end

function EntityService:_getTargetDistance(entity, targetPlayer)
	if not targetPlayer then
		return nil
	end

	local targetCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
	local entityPosition = entity:GetPosition()
	if not targetCharacter or not targetCharacter.RootPart or not entityPosition then
		return nil
	end

	return (targetCharacter.RootPart.Position - entityPosition).Magnitude
end

function EntityService:_selectAbilityTarget(entity, ability, candidates)
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

function EntityService:_resolveAbility(entity, ability, targetPlayer)
	local context = self:_createEffectContext(entity, targetPlayer, nil, nil)
	self:_executeEffectSteps(entity, ability, context)

	DebugLog:Log("Entity", string.format("[EntityService] %s resolved %s", entity.DisplayName, ability.Id or "Ability"))
	self:_syncDebugAttributes(entity)
end

function EntityService:_updateEntityMovement(entity, deltaTime)
	if entity:IsCasting() then
		return
	end

	if not entity:HasAttribute(EntityAttributes.Chase) then
		return
	end

	local state = entity:GetState()
	if state == ENTITY_STATE.Patrol then
		self:_updatePatrolMovement(entity, deltaTime)
	elseif state == ENTITY_STATE.Scout then
		self:_updateScoutMovement(entity, deltaTime)
	elseif state == ENTITY_STATE.Chase or state == ENTITY_STATE.Rage then
		local destination = entity:GetTargetLastKnownPosition()
		if destination then
			entity:MoveToward(destination, deltaTime)
		end
	end
end

function EntityService:_updatePatrolMovement(entity, deltaTime)
	if entity.SearchMode and not entity:IsSearchModeActive() then
		entity:EndSearchMode()
	end

	if entity:ShouldRelocateRoamAnchor() then
		entity:ClearPatrolDestination()
		if not self:_tryAssignInterestDestination(entity, entity.DetectionRadius * 2.5) then
			self:_maybeRelocateRoamAnchor(entity, true)
		end
	end

	if entity:IsPatrolPaused() then
		return
	end

	local destination = entity:GetPatrolDestination()
	if not destination then
		if not self:_tryAssignInterestDestination(entity, entity.DetectionRadius * 2.5) then
			self:_maybeRelocateRoamAnchor(entity, true)
		end
		destination = self:_pickReachablePatrolDestination(entity)
	end

	if not destination then
		return
	end

	if entity:HasReachedPatrolDestination() then
		local destinationReason = entity:GetPatrolDestinationReason()
		entity:SetRoamAnchor(self:_clampPositionToMapBounds(entity:GetPosition()))
		entity:ClearPatrolDestination()
		if entity.SearchMode then
			if not self:_tryAssignInterestDestination(entity, entity.DetectionRadius * 3) then
				self:_maybeRelocateRoamAnchor(entity, true)
			end
			self:_pickReachablePatrolDestination(entity)
			destination = entity:GetPatrolDestination()
			if not destination then
				return
			end
		else
			if destinationReason ~= "Interest" then
				entity:MarkPatrolPause()
			end
			if not self:_tryAssignInterestDestination(entity, entity.DetectionRadius * 2) then
				self:_maybeRelocateRoamAnchor(entity, false)
			end
			self:_pickReachablePatrolDestination(entity)
			if destinationReason ~= "Interest" then
				return
			end
		end
	end

	if self:_isMovementStepBlocked(entity, destination) then
		entity:ClearPatrolDestination()
		if not self:_tryAssignInterestDestination(entity, entity.DetectionRadius * 2) then
			self:_maybeRelocateRoamAnchor(entity, true)
		end
		self:_pickReachablePatrolDestination(entity)
		return
	end

	entity:MoveToward(destination, deltaTime)
end

function EntityService:_updateScoutMovement(entity, deltaTime)
	local destination = entity:GetTargetLastKnownPosition()
	if not destination then
		entity:ClearScoutArrival()
		entity:SetTarget(nil)
		entity:EnterState(ENTITY_STATE.Patrol)
		entity:ClearPatrolDestination()
		entity.PatrolPauseUntil = 0
		self:_pickReachablePatrolDestination(entity)
		return
	end

	local scoutDestination = entity:GetPatrolDestination()
	if scoutDestination then
		if entity:IsNearPosition(scoutDestination, entity:GetStopDistance() + 0.5) then
			entity:ClearPatrolDestination()
			if entity:HasScoutSweepRemaining() then
				self:_pickReachableScoutDestination(entity)
			else
				local targetPlayer = entity:GetTarget()
				entity:SetRoamAnchor(self:_clampPositionToMapBounds(entity.ScoutOrigin or destination))
				entity:ClearScoutArrival()
				if targetPlayer then
					entity:ForgetTarget(targetPlayer)
				else
					entity:SetTarget(nil)
				end
				entity:EnterState(ENTITY_STATE.Patrol)
				entity.PatrolPauseUntil = 0
				self:_pickReachablePatrolDestination(entity)
			end
			return
		end

	if self:_isMovementStepBlocked(entity, scoutDestination) then
		entity:ClearPatrolDestination()
		self:_pickReachableScoutDestination(entity)
		return
	end

	entity:MoveToward(scoutDestination, deltaTime)
	return
end

	if entity:HasReachedScoutDestination() then
		entity:BeginScoutSweep(destination)
		if entity:HasScoutSweepRemaining() then
			self:_pickReachableScoutDestination(entity)
		else
			local targetPlayer = entity:GetTarget()
			entity:SetRoamAnchor(self:_clampPositionToMapBounds(entity.ScoutOrigin or destination))
			entity:ClearScoutArrival()
			if targetPlayer then
				entity:ForgetTarget(targetPlayer)
			else
				entity:SetTarget(nil)
			end
			entity:EnterState(ENTITY_STATE.Patrol)
			entity.PatrolPauseUntil = 0
			self:_pickReachablePatrolDestination(entity)
		end
		return
	end

	entity:ClearScoutArrival()
	if self:_isMovementStepBlocked(entity, destination) then
		entity:BeginScoutSweep(destination)
		if entity:HasScoutSweepRemaining() then
			self:_pickReachableScoutDestination(entity)
		end
		return
	end

	entity:MoveToward(destination, deltaTime)
end

function EntityService:_maybeRelocateRoamAnchor(entity, forceRelocate)
	if not self.MapBounds or not self.MapBounds:IsA("BasePart") then
		return false
	end

	if not forceRelocate and entity.Random:NextNumber() > entity.GlobalPatrolRelocateChance then
		return false
	end

	local anchor = self:_pickRandomPointInMapBounds(entity)
	if not anchor then
		return false
	end

	entity:SetRoamAnchor(self:_clampPositionToMapBounds(anchor))
	return true
end

function EntityService:_tryAssignInterestDestination(entity, radius)
	local interestService = self.InterestService
	if not interestService then
		return false
	end

	local entityPosition = entity:GetPosition()
	local preferredPlayer = entity:GetTarget()
	local interestPoint = interestService:GetStrongestInterestNear(entityPosition, radius, {
		WeightByDirection = true,
		PreferPlayer = preferredPlayer,
	})
	if not interestPoint then
		return false
	end

	local interestDestination = interestPoint.Destination or interestPoint.Position
	if not entity.IgnoreLineOfSightForInterest then
		local canSeeProjected = self:_hasLineOfSightToPosition(entity, interestDestination)
		local canSeeOrigin = self:_hasLineOfSightToPosition(entity, interestPoint.Position)

		if not canSeeProjected then
			interestDestination = self:_resolveInterestInvestigationPoint(entity, interestPoint, canSeeOrigin)
		end
	end

	local clampedPosition = self:_clampPositionToMapBounds(interestDestination)
	entity:SetRoamAnchor(clampedPosition)
	entity:SetPatrolDestination(clampedPosition, "Interest")
	return true
end

function EntityService:_pickRandomPointInMapBounds(entity)
	local boundsPart = self.MapBounds
	if not boundsPart or not boundsPart:IsA("BasePart") then
		return nil
	end

	local size = boundsPart.Size
	local center = boundsPart.Position
	local currentPosition = entity:GetPosition() or center
	local y = currentPosition.Y

	for _ = 1, 12 do
		local x = center.X + entity.Random:NextNumber(-size.X * 0.5, size.X * 0.5)
		local z = center.Z + entity.Random:NextNumber(-size.Z * 0.5, size.Z * 0.5)
		local candidate = Vector3.new(x, y, z)
		if not entity:IsNearPosition(candidate, entity.PatrolPointMinDistance * 2) then
			return self:_clampPositionToMapBounds(candidate)
		end
	end

	return self:_clampPositionToMapBounds(Vector3.new(center.X, y, center.Z))
end

function EntityService:_pickReachablePatrolDestination(entity)
	local currentDestination = entity:GetPatrolDestination()
	if currentDestination
		and not entity:IsNearPosition(currentDestination, entity:GetStopDistance() + 0.5)
		and self:_isNavigationDestinationReachable(entity, currentDestination)
	then
		return currentDestination
	end

	for _ = 1, 8 do
		local destination = self:_clampPositionToMapBounds(entity:PickPatrolDestination())
		if destination then
			entity:SetPatrolDestination(destination, "Patrol")
		end
		if not destination or self:_isNavigationDestinationReachable(entity, destination) then
			return destination
		end
	end

	return entity:GetPatrolDestination()
end

function EntityService:_pickReachableScoutDestination(entity)
	local currentDestination = entity:GetPatrolDestination()
	if currentDestination
		and not entity:IsNearPosition(currentDestination, entity:GetStopDistance() + 0.5)
		and self:_isNavigationDestinationReachable(entity, currentDestination)
	then
		return currentDestination
	end

	for _ = 1, 8 do
		local destination = self:_clampPositionToMapBounds(entity:PickScoutDestination())
		if destination then
			entity:SetPatrolDestination(destination, "Scout")
		end
		if not destination or self:_isNavigationDestinationReachable(entity, destination) then
			return destination
		end
	end

	return entity:GetPatrolDestination()
end

function EntityService:_clampPositionToMapBounds(position)
	local boundsPart = self.MapBounds
	if not position or not boundsPart or not boundsPart:IsA("BasePart") then
		return position
	end

	local size = boundsPart.Size
	local center = boundsPart.Position
	local halfX = math.max(0, (size.X * 0.5) - 2)
	local halfZ = math.max(0, (size.Z * 0.5) - 2)

	return Vector3.new(
		math.clamp(position.X, center.X - halfX, center.X + halfX),
		position.Y,
		math.clamp(position.Z, center.Z - halfZ, center.Z + halfZ)
	)
end

function EntityService:_isNavigationDestinationReachable(entity, destination)
	local origin = entity:GetPosition()
	if not origin or not destination then
		return true
	end

	local direction = destination - origin
	if direction.Magnitude <= entity:GetStopDistance() then
		return true
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	local start = origin + Vector3.new(0, 2, 0)
	local result = Workspace:Raycast(start, direction, self.RaycastParams)
	if not result then
		return true
	end

	return (result.Position - start).Magnitude >= (direction.Magnitude - 1)
end

function EntityService:_isMovementStepBlocked(entity, destination)
	if entity.SearchMode and entity.SearchMode.IgnoreMovementBlockers then
		return false
	end

	local origin = entity:GetPosition()
	if not origin or not destination then
		return false
	end

	local direction = destination - origin
	local distance = direction.Magnitude
	if distance <= entity:GetStopDistance() then
		return false
	end

	local moveDistance = math.min(distance - entity:GetStopDistance(), entity:GetMoveSpeed() * self.UpdateInterval)
	if moveDistance <= 0 then
		return false
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	local start = origin + Vector3.new(0, 2, 0)
	local result = Workspace:Raycast(start, direction.Unit * moveDistance, self.RaycastParams)
	return result ~= nil
end

function EntityService:_tryBasicAttack(entity)
	local targetPlayer = entity:GetTarget()
	if not targetPlayer or not entity:CanAttack() or entity:IsCasting() then
		return
	end

	local attackDefinition = entity:GetCurrentBasicAttackDefinition()

	local statusService = self.StatusEffectService
	if statusService and not statusService:CanUseAbilities(entity) then
		return
	end

	local characterService = self.CharacterService
	if not characterService then
		return
	end

	local targetCharacter = characterService:GetCharacterByPlayer(targetPlayer)
	if not targetCharacter or not targetCharacter.RootPart then
		return
	end

	local attackRange = attackDefinition.AttackRange or entity.AttackRange
	if not entity:IsInRange(targetCharacter.RootPart.Position, attackRange) then
		return
	end

	if not entity.IgnoreLineOfSightForAttacks and not self:_hasLineOfSight(entity, targetCharacter) then
		return
	end

	local damageAmount = entity:GetScaledDamage(attackDefinition.Damage or entity.Damage)
	local didDamage = targetCharacter:ApplyDamage(damageAmount)
	if didDamage then
		if statusService then
			statusService:ApplyStatus(targetPlayer, StatusEffectId.Haste, {
				Duration = 1.5,
				Magnitude = 0.45,
				Source = "OnHitHaste",
			})
		end
		
		local interactionService = self.InteractionService
		if interactionService and interactionService:IsInteracting(targetPlayer) then
			interactionService:InterruptInteraction(targetPlayer, "Damaged")
		end

		self:_executeBasicAttackEffects(entity, targetPlayer, attackDefinition)
		self:_handleTargetDowned(entity, targetPlayer, targetCharacter)
	end

	entity:MarkAttack(attackDefinition.Cooldown or entity.AttackInterval)
	entity:AdvanceBasicAttackVariant()

	DebugLog:Log("Entity", string.format(
		"[EntityService] %s hit %s for %d",
		entity.Model.Name,
		targetPlayer.Name,
		damageAmount
	))
end

function EntityService:_executeBasicAttackEffects(entity, targetPlayer, attackDefinition)
	local basicAttack = attackDefinition or entity:GetCurrentBasicAttackDefinition()
	if not basicAttack then
		return
	end

	local context = self:_createEffectContext(entity, targetPlayer, nil, nil)
	local effectSteps = {}
	for _, step in ipairs(basicAttack.Effects or {}) do
		table.insert(effectSteps, step)
	end

	if entity.GetInheritedBasicAttackEffects then
		for _, step in ipairs(entity:GetInheritedBasicAttackEffects()) do
			table.insert(effectSteps, step)
		end
	end

	if #effectSteps <= 0 then
		return
	end

	for _, step in ipairs(effectSteps) do
		self:_executeEffectStep(entity, step, context)
	end
end

function EntityService:_createEffectContext(entity, targetPlayer, sourceStep, deltaTime)
	return {
		Entity = entity,
		TargetPlayer = targetPlayer,
		SourceStep = sourceStep,
		DeltaTime = deltaTime,
	}
end

function EntityService:_executeEffectSteps(entity, definition, context)
	for _, step in ipairs(self:_getEffectSteps(definition)) do
		self:_executeEffectStep(entity, step, context)
	end
end

function EntityService:_getEffectSteps(definition)
	if definition.Effects then
		return definition.Effects
	end

	local legacyEffect = definition.Effect
	if not legacyEffect then
		return {}
	end

	if legacyEffect == "SelfBuff" then
		return {
			{
				Type = "ApplyPersistentModifierSelf",
				Modifier = definition.Modifier,
				Amount = definition.Amount,
			},
		}
	elseif legacyEffect == "DamageTarget" then
		return {
			{
				Type = "DamageTargets",
				Targets = definition.Targeting or "CurrentTarget",
				Amount = definition.Damage,
				Range = definition.Range,
			},
		}
	elseif legacyEffect == "RefreshTargetMemory" then
		return {
			{
				Type = "RefreshTargetMemory",
				Targets = definition.Targeting or "CurrentTarget",
			},
		}
	elseif legacyEffect == "SelfBuffFromVisibleTargets" then
		return {
			{
				Type = "ApplyTimedModifierSelfPerTarget",
				Targets = "VisibleTargets",
				Modifier = definition.Modifier,
				Amount = definition.AmountPerTarget,
				Duration = definition.Duration or 1,
			},
		}
	end

	return {}
end

function EntityService:_executeEffectStep(entity, step, context)
	local stepType = step.Type

	if stepType == "DamageTargets" then
		for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			self:_damageTargetFromEffect(entity, player, step)
		end
	elseif stepType == "RepeatDamageTargets" then
		self:_repeatDamageTargetsFromEffect(entity, step, context)
	elseif stepType == "HealSelfPercent" then
		entity:HealPercent(step.Amount or 0)
	elseif stepType == "ApplyPersistentModifierSelf" then
		if step.Modifier and step.Amount then
			entity:ApplyPersistentModifier(step.Modifier, step.Amount)
		end
	elseif stepType == "ApplyTimedModifierSelf" then
		if step.Modifier and step.Amount and step.Duration then
			entity:ApplyTimedModifier(step.Modifier, step.Amount, step.Duration, step.SourceKey or step.Modifier)
		end
	elseif stepType == "ApplyTimedModifierSelfPerTarget" then
		local targets = self:_resolveEffectTargets(entity, step, context)
		for _ = 1, #targets do
			entity:ApplyTimedModifier(step.Modifier, step.Amount or 0, step.Duration or 0, step.SourceKey or step.Modifier)
		end
	elseif stepType == "RefreshTargetMemory" then
		for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			local character = self.CharacterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				entity:RememberTarget(player, character.RootPart.Position, true)
			end
		end
	elseif stepType == "InterruptInteraction" then
		local interactionService = self.InteractionService
		if interactionService then
			for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
				interactionService:InterruptInteraction(player, step.Reason or "EntityEffect")
			end
		end
	elseif stepType == "ApplyCharacterSpeedMultiplier" then
		for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			local character = self.CharacterService:GetCharacterByPlayer(player)
			if character then
				character:ApplyTemporarySpeedMultiplier(step.Key or "EntityEffectSlow", step.Multiplier or 1, step.Duration or 0)
			end
		end
	elseif stepType == "ApplyStatusPlaceholder" then
		for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			DebugLog:Log("Entity", string.format("[EntityService] Placeholder status %s applied to %s", tostring(step.StatusId), player.Name))
		end
	elseif stepType == "ApplyStatus" then
		local statusService = self.StatusEffectService
		if not statusService then
			return
		end

		for _, target in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			statusService:ApplyStatus(target, step.StatusId, {
				Duration = step.Duration,
				Magnitude = step.Magnitude,
				Tier = step.Tier,
				Source = entity.DisplayName,
			})
		end
	elseif stepType == "ApplyStatusSelfPerTargetCount" then
		local statusService = self.StatusEffectService
		if not statusService then
			return
		end

		local targets = self:_resolveEffectTargets(entity, {
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
	elseif stepType == "DrainStaminaTargets" then
		if not self.StaminaService then
			return
		end

		for _, target in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			self.StaminaService:DrainStamina(target, step.Amount or 0, step.Reason or entity.DisplayName)
		end
	elseif stepType == "StartStruggle" then
		if not self.StruggleService then
			return
		end

		for _, target in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			self.StruggleService:BeginStruggle(entity, target, step)
		end
	elseif stepType == "StartBreathHoldChallenge" then
		if not self.BreathHoldService then
			return
		end

		self.BreathHoldService:BeginChallenge(entity, step)
	elseif stepType == "StartSearchMode" then
		local searchId = step.SearchId or "SearchMode"
		local duration = step.Duration
		entity:BeginSearchMode(searchId, duration, {
			HeightOffset = step.HeightOffset,
			IgnoreMovementBlockers = step.IgnoreMovementBlockers,
			DetectionRadiusMultiplier = step.DetectionRadiusMultiplier,
		})
		self:_pickReachablePatrolDestination(entity)
	elseif stepType == "SpawnEntity" then
		self:_spawnEntitiesFromEffect(entity, step, context)
	elseif stepType == "AbsorbAbility" then
		for _, player in ipairs(self:_resolveEffectTargets(entity, step, context)) do
			local totalAbsorbed = entity:AbsorbAbilityFromPlayer(player, step.Count or 1)
			DebugLog:Log("Entity", string.format("[EntityService] %s absorbed from %s (%d total on target)", entity.DisplayName, player.Name, totalAbsorbed))
		end
	elseif stepType == "ExtendReceptionTime" then
		local roundHookService = self.RoundHookService
		if not roundHookService then
			return
		end

		roundHookService:ExtendReceptionTime(step.Amount or 0, step.Reason or entity.DisplayName)
	elseif stepType == "SetReceptionTime" then
		local roundHookService = self.RoundHookService
		if not roundHookService then
			return
		end

		roundHookService:SetReceptionTime(step.TimeLeft or 0, step.Reason or entity.DisplayName)
	elseif stepType == "LogMessage" then
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
end

function EntityService:_repeatDamageTargetsFromEffect(entity, step, context)
	local targets = self:_resolveEffectTargets(entity, step, context)
	local hits = math.max(1, step.Hits or 1)
	local interval = math.max(0, step.Interval or 0)
	local actionSequenceId = entity.ActionSequenceId or 0

	for _, player in ipairs(targets) do
		if interval <= 0 then
			for _ = 1, hits do
				if (entity.ActionSequenceId or 0) ~= actionSequenceId then
					return
				end
				self:_damageTargetFromEffect(entity, player, step)
			end
		else
			task.spawn(function()
				for hitIndex = 1, hits do
					if not entity or not entity.IsActive or entity.Health <= 0 then
						return
					end

					if (entity.ActionSequenceId or 0) ~= actionSequenceId then
						return
					end

					local statusService = self.StatusEffectService
					if statusService and not statusService:CanUseAbilities(entity) then
						return
					end

					self:_damageTargetFromEffect(entity, player, step)

					if hitIndex < hits then
						task.wait(interval)
					end
				end
			end)
		end
	end
end

function EntityService:InterruptEntityAbilities(entity, reason)
	if not entity then
		return false
	end

	entity.ActionSequenceId = (entity.ActionSequenceId or 0) + 1
	entity:CancelCast()

	if self.StruggleService then
		self.StruggleService:InterruptStrugglesForEntity(entity, reason or "Interrupted")
	end

	if self.BreathHoldService then
		self.BreathHoldService:CancelChallengesForEntity(entity, reason or "Interrupted")
	end

	self:_syncDebugAttributes(entity)
	DebugLog:Log("Entity", string.format("[EntityService] %s interrupted (%s)", entity.DisplayName, tostring(reason or "Unknown")))
	return true
end

function EntityService:_spawnEntitiesFromEffect(entity, step, context)
	local entityId = step.EntityId
	if not entityId then
		return
	end

	local count = math.max(1, step.Count or 1)
	local spawnCFrames = self:_buildSpawnCFrames(entity, step, context, count)
	for _, spawnCFrame in ipairs(spawnCFrames) do
		self:SpawnEntity(entityId, {
			CFrame = spawnCFrame,
			OwnerEntity = entity,
			Lifetime = step.Lifetime,
			IsSummon = step.IsSummon ~= false,
			Activate = step.Activate ~= false,
		})
	end
end

function EntityService:_buildSpawnCFrames(entity, step, context, count)
	local spawnCFrames = {}
	local origin = self:_resolveSpawnOrigin(entity, step, context)
	if not origin then
		return spawnCFrames
	end

	local radius = step.Radius or 0
	local heightOffset = step.HeightOffset or 0
	local random = entity.Random
	for index = 1, count do
		local offset = Vector3.zero
		if radius > 0 then
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = count == 1 and radius or random:NextNumber(math.max(0, radius * 0.35), radius)
			offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end

		local position = origin.Position + offset + Vector3.new(0, heightOffset, 0)
		local lookAt = position + origin.LookVector
		if step.FaceOrigin == true then
			lookAt = origin.Position
		end

		spawnCFrames[index] = CFrame.new(position, lookAt)
	end

	return spawnCFrames
end

function EntityService:_resolveSpawnOrigin(entity, step, context)
	local mode = step.SpawnAt or "Self"
	if mode == "Self" then
		return entity.RootPart and entity.RootPart.CFrame or nil
	end

	if mode == "Target" or mode == "CurrentTarget" then
		local targetPlayer = context and context.TargetPlayer
		local targetCharacter = targetPlayer and self.CharacterService:GetCharacterByPlayer(targetPlayer)
		return targetCharacter and targetCharacter.RootPart and targetCharacter.RootPart.CFrame or nil
	end

	if mode == "Position" and step.Position then
		return CFrame.new(step.Position)
	end

	return entity.RootPart and entity.RootPart.CFrame or nil
end

function EntityService:SpawnEntity(entityId, params)
	params = params or {}

	local definition = EntityDefinitions[entityId]
	if not definition then
		warn(string.format("[EntityService] Missing entity definition for summon '%s'", tostring(entityId)))
		return nil
	end

	local templateName = definition.TemplateName or definition.Id or entityId
	local sourceDefinition = EntityDefinitions[templateName]
	if sourceDefinition then
		templateName = sourceDefinition.TemplateName or sourceDefinition.Id or templateName
	end

	local template = self.EntityTemplates[templateName]
	if not template then
		local liveModel = self.EntitiesFolder:FindFirstChild(templateName)
			or self.EntitiesFolder:FindFirstChild(entityId)
			or (sourceDefinition and sourceDefinition.Id and self.EntitiesFolder:FindFirstChild(sourceDefinition.Id))
		if liveModel and liveModel:IsA("Model") then
			self:_cacheEntityTemplate(liveModel, sourceDefinition or definition)
			template = self.EntityTemplates[templateName]
		end
	end

	if not template then
		local sourceModel = self.TemplateSourceFolder:FindFirstChild(templateName)
			or self.TemplateSourceFolder:FindFirstChild(entityId)
			or (sourceDefinition and sourceDefinition.Id and self.TemplateSourceFolder:FindFirstChild(sourceDefinition.Id))
		if sourceModel and sourceModel:IsA("Model") and sourceModel.PrimaryPart then
			self:_cacheEntityTemplate(sourceModel, sourceDefinition or definition)
			template = self.EntityTemplates[templateName]
		end
	end

	if not template then
		for _, existingEntity in ipairs(self.Entities) do
			local matchesTemplate = existingEntity.TemplateName == templateName
				or existingEntity.Id == templateName
				or (existingEntity.Definition and existingEntity.Definition.Id == templateName)
				or (sourceDefinition and existingEntity.Definition == sourceDefinition)
				or (existingEntity.Model and existingEntity.Model.Name == templateName)

			if matchesTemplate and existingEntity.Model then
				self:_cacheEntityTemplate(existingEntity.Model, sourceDefinition or existingEntity.Definition)
				template = self.EntityTemplates[templateName]
				if template then
					break
				end
			end
		end
	end

	if not template then
		warn(string.format("[EntityService] Missing entity template for summon '%s'", tostring(entityId)))
		return nil
	end

	local model = template:Clone()
	if not model then
		warn(string.format("[EntityService] Failed to clone entity template '%s' for summon '%s'", tostring(templateName), tostring(entityId)))
		return nil
	end

	model.Name = entityId
	self:_applyRuntimeEntityAppearance(model, definition, params)
	model.Parent = self.EntitiesFolder

	local targetCFrame = params.CFrame
	if targetCFrame then
		model:PivotTo(targetCFrame)
	end

	local runtimeData = {
		EntityId = entityId,
		TemplateName = templateName,
		IsRuntimeEntity = true,
		IsSummon = params.IsSummon ~= false,
		OwnerEntity = params.OwnerEntity,
		ExpiresAt = params.Lifetime and (os.clock() + params.Lifetime) or nil,
	}

	local entity = self:_registerEntityModel(model, runtimeData)
	if params.Activate ~= false then
		entity:SetActive(true)
	end

	self:_registerRoundHooksForEntity(entity)

	DebugLog:Log("Entity", string.format("[EntityService] Spawned runtime entity: %s using template %s", entity.DisplayName, tostring(templateName)))

	return entity
end

function EntityService:SetRoundLineup(entityIds)
	self.SelectedRoundEntityIds = {}

	for _, entityId in ipairs(entityIds or {}) do
		self.SelectedRoundEntityIds[entityId] = true
	end

	self:_ensureRoundLineupEntities(entityIds or {})

	DebugLog:Log("Entity", string.format(
		"[EntityService] Round lineup set: %s",
		#(entityIds or {}) > 0 and table.concat(entityIds, ", ") or "None"
	))
end

function EntityService:_ensureRoundLineupEntities(entityIds)
	for _, entityId in ipairs(entityIds or {}) do
		if not self:_findRoundEntityById(entityId) then
			local spawnPart = self.SpawnService and self.SpawnService:GetRandomEntitySpawn()
			local targetCFrame = spawnPart and (spawnPart.CFrame + Vector3.new(0, 3, 0)) or nil
			self:SpawnEntity(entityId, {
				CFrame = targetCFrame,
				Activate = false,
				IsSummon = false,
			})
		end
	end
end

function EntityService:_findRoundEntityById(entityId)
	for _, entity in ipairs(self.Entities) do
		if entity.Id == entityId and entity.OwnerEntity == nil then
			return entity
		end
	end

	return nil
end

function EntityService:_applyRuntimeEntityAppearance(model, definition, params)
	local appearance = (params and params.RuntimeAppearance) or (definition and definition.RuntimeAppearance)
	if not appearance then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if appearance.Color then
				descendant.Color = appearance.Color
			end

			if appearance.Material then
				descendant.Material = appearance.Material
			end

			if appearance.Transparency ~= nil then
				descendant.Transparency = appearance.Transparency
			end
		elseif descendant:IsA("ParticleEmitter") and appearance.DisableParticles == true then
			descendant.Enabled = false
		end
	end
end

function EntityService:_despawnEntity(entity, reason)
	self:_clearRoundHooksForEntity(entity)

	local statusEffectService = self.StatusEffectService
	if statusEffectService then
		statusEffectService:ClearStatuses(entity)
	end

	for index = #self.Entities, 1, -1 do
		if self.Entities[index] == entity then
			table.remove(self.Entities, index)
			break
		end
	end

	if entity.Model then
		entity.Model:Destroy()
	end

	DebugLog:Log("Entity", string.format("[EntityService] Despawned %s (%s)", entity.DisplayName, tostring(reason or "Unknown")))
	entity:Destroy()
end

function EntityService:_markLastAbility(entity, abilityId)
	if not entity or not entity.Model then
		return
	end

	entity.Model:SetAttribute("DebugLastAbility", tostring(abilityId or "None"))
end

function EntityService:_markRecentHit(entity, amount, sourceLabel)
	if not entity or not entity.Model then
		return
	end

	entity.Model:SetAttribute("DebugRecentHitDamage", math.floor((amount or 0) + 0.5))
	entity.Model:SetAttribute("DebugRecentHitSource", tostring(sourceLabel or "Unknown"))
	entity.Model:SetAttribute("DebugRecentHitExpiresAt", Workspace:GetServerTimeNow() + RECENT_HIT_DEBUG_DURATION)
end

function EntityService:_syncDebugAttributes(entity)
	if not entity or not entity.Model then
		return
	end

	entity.Model:SetAttribute("EntityId", entity.Id)
	entity.Model:SetAttribute("EntityDisplayName", entity.DisplayName)
	entity.Model:SetAttribute("EntityState", entity:GetState())
	entity.Model:SetAttribute("EntityTarget", entity:GetTarget() and entity:GetTarget().Name or "")
	entity.Model:SetAttribute("EntityTerrorRadius", entity.TerrorRadius or 0)
	entity.Model:SetAttribute("DebugEntityName", entity.DisplayName)
	entity.Model:SetAttribute("DebugState", entity:GetState())
	entity.Model:SetAttribute("DebugHealth", math.floor((entity.Health or 0) + 0.5))
	entity.Model:SetAttribute("DebugMaxHealth", math.floor((entity.MaxHealth or 0) + 0.5))
	entity.Model:SetAttribute("DebugTarget", entity:GetTarget() and entity:GetTarget().Name or "")
	entity.Model:SetAttribute("DebugAbsorbedCount", entity.GetAbsorbedAbilityCount and entity:GetAbsorbedAbilityCount() or 0)
end

function EntityService:DamageEntity(entity, amount, options)
	options = options or {}
	if not entity or not amount or amount <= 0 or entity.Health <= 0 then
		return false
	end

	local finalAmount = amount
	local statusService = self.StatusEffectService
	if statusService and not options.IsStatusEffect then
		finalAmount *= (1 + statusService:GetModifier(entity, "Fragility"))
		finalAmount *= math.max(0, 1 - statusService:GetModifier(entity, "Resistance"))
	end

	finalAmount *= math.max(0, 1 - (entity:GetModifierValue("Resistance") or 0))
	finalAmount = math.max(0, finalAmount)
	if finalAmount <= 0 then
		return false
	end

	entity.Health = math.clamp(entity.Health - finalAmount, 0, entity.MaxHealth)
	self:_markRecentHit(entity, finalAmount, options.SourcePlayer and options.SourcePlayer.Name or options.WeaponId or "Unknown")
	local relinquished = entity:RegisterIncomingDamage(finalAmount)
	for _, release in ipairs(relinquished) do
		DebugLog:Log("Entity", string.format(
			"[EntityService] %s relinquished an absorbed ability back to %s (%d remaining on target)",
			entity.DisplayName,
			release.Player and release.Player.Name or "Unknown",
			release.RemainingOnTarget or 0
		))
	end

	if entity.Health <= 0 then
		entity.IsActive = false
		DebugLog:Log("Entity", string.format("[EntityService] %s reached 0 health", entity.DisplayName))
	end

	self:_syncDebugAttributes(entity)

	return true
end

function EntityService:ForceChaseTarget(entity, player, position)
	entity:SetTarget(player, position, true)
	entity:RememberTarget(player, position, true)
	entity:EnterState(ENTITY_STATE.Chase)
end

function EntityService:_resolveEffectTargets(entity, step, context)
	local targetMode = step.Targets or "CurrentTarget"
	if targetMode == "CurrentTarget" then
		return context.TargetPlayer and { context.TargetPlayer } or {}
	elseif targetMode == "Self" then
		return { entity }
	elseif targetMode == "VisibleTargets" then
		return self:_collectVisiblePlayers(entity)
	elseif targetMode == "AllCandidates" then
		return self:_collectCandidatePlayers(entity)
	elseif targetMode == "NearestVisible" then
		local nearest = self:_getNearestVisiblePlayer(entity)
		return nearest and { nearest } or {}
	elseif targetMode == "PlayersInRadius" then
		return self:_collectPlayersInRadius(entity, step.Radius or 0)
	end

	return {}
end

function EntityService:_damageTargetFromEffect(entity, player, step)
	local character = player and self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return
	end

	local range = step.Range or entity.AttackRange
	if range and not entity:IsInRange(character.RootPart.Position, range) then
		return
	end

	local amount = entity:GetScaledDamage(step.Amount or entity.Damage)
	local didDamage = character:ApplyDamage(amount)
	if not didDamage then
		return
	end

	if step.OnHitHasteMultiplier then
		local statusService = self.StatusEffectService
		if statusService then
			statusService:ApplyStatus(player, StatusEffectId.Haste, {
				Duration = step.OnHitHasteDuration or 1.5,
				Magnitude = math.max(0, (step.OnHitHasteMultiplier or 1) - 1),
				Source = step.OnHitHasteKey or "OnHitHaste",
			})
		end
	end

	self:_handleTargetDowned(entity, player, character)
end

function EntityService:_handleTargetDowned(entity, targetPlayer, targetCharacter)
	if not entity or not targetPlayer or not targetCharacter or targetCharacter:IsAlive() then
		return false
	end

	if entity.DownedPlayers[targetPlayer] then
		return false
	end

	entity.DownedPlayers[targetPlayer] = true
	entity:TriggerPassives("OnDown", {
		Player = targetPlayer,
		Character = targetCharacter,
	})

	DebugLog:Log("Entity", string.format("[EntityService] %s downed %s", entity.DisplayName, targetPlayer.Name))
	return true
end

function EntityService:_collectVisiblePlayers(entity)
	local visiblePlayers = {}
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	local entityPosition = entity:GetPosition()
	if not roundManager or not characterService or not entityPosition then
		return visiblePlayers
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				local distance = (character.RootPart.Position - entityPosition).Magnitude
				if distance <= entity:GetDetectionRange() and (entity.IgnoreLineOfSightForDetection or self:_hasLineOfSight(entity, character)) then
					table.insert(visiblePlayers, player)
				end
			end
		end
	end

	return visiblePlayers
end

function EntityService:_collectCandidatePlayers(entity)
	local players = {}
	for _, candidate in ipairs(self:_collectTargetCandidates(entity)) do
		table.insert(players, candidate.Player)
	end
	return players
end

function EntityService:_getNearestVisiblePlayer(entity)
	local bestPlayer = nil
	local bestDistance = math.huge
	local entityPosition = entity:GetPosition()

	for _, player in ipairs(self:_collectVisiblePlayers(entity)) do
		local character = self.CharacterService:GetCharacterByPlayer(player)
		if character and character.RootPart then
			local distance = (character.RootPart.Position - entityPosition).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestPlayer = player
			end
		end
	end

	return bestPlayer
end

function EntityService:_collectPlayersInRadius(entity, radius)
	local players = {}
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	local entityPosition = entity:GetPosition()
	if not roundManager or not characterService or not entityPosition then
		return players
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				if (character.RootPart.Position - entityPosition).Magnitude <= radius then
					table.insert(players, player)
				end
			end
		end
	end

	return players
end

function EntityService:_countVisibleTargets(entity)
	return #self:_collectVisiblePlayers(entity)
end

function EntityService:_countPlayersInRadius(entity, radius)
	return #self:_collectPlayersInRadius(entity, radius)
end

function EntityService:_hasLineOfSight(entity, character)
	local origin = entity:GetPosition()
	if not origin or not character or not character.RootPart then
		return false
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	local direction = character.RootPart.Position - origin
	local result = Workspace:Raycast(origin, direction, self.RaycastParams)
	if not result then
		return true
	end

	return result.Instance and result.Instance:IsDescendantOf(character.Model)
end

function EntityService:_hasLineOfSightToPosition(entity, position)
	local origin = entity:GetPosition()
	if not origin or not position then
		return false
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	local direction = position - origin
	local result = Workspace:Raycast(origin, direction, self.RaycastParams)
	return result == nil
end

function EntityService:_resolveInterestInvestigationPoint(entity, interestPoint, canSeeOrigin)
	local entityPosition = entity:GetPosition()
	local originPoint = interestPoint.Position
	if canSeeOrigin then
		return originPoint
	end

	local aroundPoint = self:_findAroundObstaclePoint(entity, originPoint)
	if aroundPoint then
		return aroundPoint
	end

	return self:_projectTowardVisibleInterest(entityPosition, originPoint)
end

function EntityService:_findAroundObstaclePoint(entity, blockedPosition)
	local origin = entity:GetPosition()
	if not origin or not blockedPosition then
		return nil
	end

	local direction = blockedPosition - origin
	local planar = Vector3.new(direction.X, 0, direction.Z)
	if planar.Magnitude <= 0.01 then
		return nil
	end

	local forward = planar.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local baseDistance = math.min(planar.Magnitude, math.max(entity.DetectionRadius * 0.75, 16))
	local sideDistances = { 8, 14, 20, 28 }

	for _, sideDistance in ipairs(sideDistances) do
		for _, sign in ipairs({ 1, -1 }) do
			local candidate = origin + (forward * baseDistance) + (right * sideDistance * sign)
			candidate = self:_clampPositionToMapBounds(candidate)
			if self:_hasLineOfSightToPosition(entity, candidate) and self:_isNavigationDestinationReachable(entity, candidate) then
				return candidate
			end
		end
	end

	return nil
end

function EntityService:_projectTowardVisibleInterest(origin, blockedPosition)
	if not origin or not blockedPosition then
		return blockedPosition
	end

	local direction = blockedPosition - origin
	local distance = direction.Magnitude
	if distance <= 0.01 then
		return blockedPosition
	end

	local stepBack = math.min(8, distance * 0.35)
	return blockedPosition - (direction.Unit * stepBack)
end

function EntityService:SetAllEntitiesActive(state, options)
	options = options or {}
	local resetRound = options.ResetRound == true
	local selectedRoundEntityIds = self.SelectedRoundEntityIds or {}
	local hasRoundSelection = next(selectedRoundEntityIds) ~= nil

	for index = #self.Entities, 1, -1 do
		local entity = self.Entities[index]
		local participatesInRound = (not hasRoundSelection) or selectedRoundEntityIds[entity.Id] == true

		if entity.IsRuntimeEntity and (resetRound or not participatesInRound) then
			self:_despawnEntity(entity, resetRound and "RoundReset" or "LineupReset")
			continue
		end

		if not state then
			self:_clearRoundHooksForEntity(entity)
		end

		entity:SetActive(state and participatesInRound)
		if state and participatesInRound then
			self:_registerRoundHooksForEntity(entity)
		end
		
		if not state then
			local statusEffectService = self.StatusEffectService
			if statusEffectService then
				statusEffectService:ClearStatuses(entity)
			end
			entity:ResetToSpawn()
		end
	end

	DebugLog:Log("Entity", "[EntityService] Entities active:", state)
end

function EntityService:_registerRoundHooksForEntity(entity)
	local roundHookService = self.RoundHookService
	if not roundHookService or not entity.IsActive then
		return
	end

	self:_clearRoundHooksForEntity(entity)

	for hookId, hookDefinition in pairs(entity.RoundHooks or {}) do
		self.NextRoundHookRuntimeId += 1
		local runtimeHookId = string.format("%s:%s:%d", entity.DisplayName, tostring(hookId), self.NextRoundHookRuntimeId)
		local definitionCopy = table.clone(hookDefinition)
		definitionCopy.Id = runtimeHookId
		definitionCopy.Callback = function(context)
			if not entity.IsActive then
				return
			end

			local targetPlayer = entity:GetTarget()
			local effectContext = self:_createEffectContext(entity, targetPlayer, nil, nil)
			effectContext.RoundHookContext = context
			self:_executeEffectSteps(entity, hookDefinition, effectContext)
		end

		roundHookService:RegisterHook(definitionCopy)
		table.insert(entity.RegisteredRoundHookIds, runtimeHookId)
	end
end

function EntityService:_clearRoundHooksForEntity(entity)
	local roundHookService = self.RoundHookService
	if not roundHookService then
		return
	end

	for _, hookId in ipairs(entity.RegisteredRoundHookIds or {}) do
		roundHookService:RemoveHook(hookId)
	end

	entity.RegisteredRoundHookIds = {}
end

return EntityService
