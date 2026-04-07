local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseEntity = require(ServerScriptService.Server.Classes.BaseEntity)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityService = {}
EntityService.Name = "EntityService"

local ENTITY_STATE = {
	Dormant = "Dormant",
	Idle = "Idle",
	Investigate = "Investigate",
	Chase = "Chase",
	Casting = "Casting",
	Stunned = "Stunned",
	Rage = "Rage",
}

function EntityService:Init(services)
	self.Services = services
	self.Entities = {}
	self.UpdateInterval = 0.2

	self.EntitiesFolder = Workspace:WaitForChild("Entities")
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
end

function EntityService:Start()
	self:_registerExistingEntities()

	task.spawn(function()
		self:_runEntityLoop()
	end)

	DebugLog:Log("Entity", "[EntityService] Started")
end

function EntityService:_registerExistingEntities()
	for _,model in ipairs(self.EntitiesFolder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart then
			local definition = EntityDefinitions[model.Name]
			local entity = BaseEntity.new(model, definition)

			table.insert(self.Entities, entity)

			DebugLog:Log("Entity", string.format(
				"[EntityService] Registered entity: %s | Stars: %d | Weight: %d",
				entity.DisplayName,
				entity.StarRating,
				entity.Weight
			))
		end
	end
end

function EntityService:_runEntityLoop()
	while true do
		for _, entity in ipairs(self.Entities) do
			if entity.IsActive then
				self:_updateEntity(entity, self.UpdateInterval)
			end
		end

		task.wait(self.UpdateInterval)
	end
end

function EntityService:_updateEntity(entity, deltaTime)
	entity:ClearExpiredMemory()

	local candidates = self:_collectTargetCandidates(entity)
	local bestCandidate = self:_selectBestCandidate(entity, candidates)
	self:_updateTargetSelection(entity, bestCandidate)
	self:_updateCasting(entity)
	self:_updateEntityState(entity)
	self:_tickEntityPassives(entity, deltaTime)
	self:_tryUseAbility(entity, candidates)
	self:_updateEntityMovement(entity, deltaTime)
	self:_tryBasicAttack(entity)
end

function EntityService:_collectTargetCandidates(entity)
	local roundManager = self.Services.RoundManager
	local characterService = self.Services.CharacterService

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
				local isVisible = distance <= entity.DetectionRadius and self:_hasLineOfSight(entity, character)
				local memory = entity:GetTargetMemory(player)
				local candidatePosition = livePosition
				local candidateDistance = distance

				if not isVisible and memory then
					candidatePosition = memory.LastKnownPosition
					candidateDistance = (candidatePosition - entityPosition).Magnitude
				end

				if isVisible or memory then
					table.insert(candidates, {
						Player = player,
						Character = character,
						Position = candidatePosition,
						Distance = candidateDistance,
						IsVisible = isVisible,
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
	local effectiveRange = math.max(entity.DetectionRadius * 1.25, entity.AttackRange)

	score += math.max(0, effectiveRange - candidate.Distance) * entity.DistanceWeight

	if candidate.IsVisible then
		score += entity.LineOfSightBonus
	end

	if candidate.Memory then
		score += entity.MemoryBonus
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

	entity:SetTarget(bestCandidate.Player, bestCandidate.Position, bestCandidate.IsVisible)
	if bestCandidate.IsVisible then
		entity:RememberTarget(bestCandidate.Player, bestCandidate.Position, true)
	end
end

function EntityService:_updateEntityState(entity)
	if entity:IsCasting() then
		entity:EnterState(ENTITY_STATE.Casting)
		return
	end

	local targetPlayer = entity:GetTarget()
	if not targetPlayer then
		entity:EnterState(ENTITY_STATE.Idle)
		return
	end

	local memory = entity:GetTargetMemory(targetPlayer)
	if not memory then
		entity:SetTarget(nil)
		entity:EnterState(ENTITY_STATE.Idle)
		return
	end

	if memory.WasVisible then
		entity:EnterState(ENTITY_STATE.Chase)
	else
		entity:EnterState(ENTITY_STATE.Investigate)
	end
end

function EntityService:_updateCasting(entity)
	local activeCast = entity:GetActiveCast()
	if not activeCast then
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

		if passive.Effect == "SelfBuffFromVisibleTargets" then
			local visibleTargets = self:_countVisibleTargets(entity)
			if visibleTargets > 0 and passive.Modifier then
				entity:ApplyPersistentModifier(passive.Modifier, (passive.AmountPerTarget or 0) * visibleTargets * deltaTime)
			end
		end
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
end

function EntityService:_selectAbility(entity, candidates)
	local abilities = entity:GetAbilityDefinitions()
	for _, abilityId in ipairs(entity:GetAbilityOrder()) do
		local ability = abilities[abilityId]
		if ability and entity:CanUseAbility(abilityId) and self:_canUseAbility(entity, ability, candidates) then
			return abilityId, ability
		end
	end

	for abilityId, ability in pairs(abilities) do
		if entity:CanUseAbility(abilityId) and self:_canUseAbility(entity, ability, candidates) then
			return abilityId, ability
		end
	end

	return nil, nil
end

function EntityService:_canUseAbility(entity, ability, candidates)
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

	if ability.RequireTarget and not entity:GetTarget() then
		return false
	end

	if ability.RequireVisibleTarget and self:_countVisibleTargets(entity) <= 0 then
		return false
	end

	if ability.MinVisibleTargets and self:_countVisibleTargets(entity) < ability.MinVisibleTargets then
		return false
	end

	if ability.Range then
		local targetPlayer = entity:GetTarget()
		if not targetPlayer then
			return false
		end

		local targetCharacter = self.Services.CharacterService:GetCharacterByPlayer(targetPlayer)
		if not targetCharacter or not targetCharacter.RootPart then
			return false
		end

		if not entity:IsInRange(targetCharacter.RootPart.Position, ability.Range) then
			return false
		end
	end

	return #candidates > 0 or not ability.RequireAnyCandidate
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
	local effect = ability.Effect
	if effect == "SelfBuff" then
		if ability.Modifier and ability.Amount then
			entity:ApplyPersistentModifier(ability.Modifier, ability.Amount)
		end
	elseif effect == "DamageTarget" then
		local character = targetPlayer and self.Services.CharacterService:GetCharacterByPlayer(targetPlayer)
		if character and character.RootPart and entity:IsInRange(character.RootPart.Position, ability.Range or entity.AttackRange) then
			character:ApplyDamage(ability.Damage or entity.Damage)
		end
	elseif effect == "RefreshTargetMemory" then
		local character = targetPlayer and self.Services.CharacterService:GetCharacterByPlayer(targetPlayer)
		if character and character.RootPart then
			entity:RememberTarget(targetPlayer, character.RootPart.Position, true)
		end
	end

	DebugLog:Log("Entity", string.format("[EntityService] %s resolved %s", entity.DisplayName, ability.Id or "Ability"))
end

function EntityService:_updateEntityMovement(entity, deltaTime)
	if entity:IsCasting() then
		return
	end

	if not entity:HasAttribute(EntityAttributes.Chase) then
		return
	end

	local state = entity:GetState()
	if state ~= ENTITY_STATE.Chase and state ~= ENTITY_STATE.Investigate and state ~= ENTITY_STATE.Rage then
		return
	end

	local destination = entity:GetTargetLastKnownPosition()
	if destination then
		entity:MoveToward(destination, deltaTime)
	end
end

function EntityService:_tryBasicAttack(entity)
	local targetPlayer = entity:GetTarget()
	if not targetPlayer or not entity:CanAttack() or entity:IsCasting() then
		return
	end

	local characterService = self.Services.CharacterService
	if not characterService then
		return
	end

	local targetCharacter = characterService:GetCharacterByPlayer(targetPlayer)
	if not targetCharacter or not targetCharacter.RootPart then
		return
	end

	if not entity:IsInRange(targetCharacter.RootPart.Position, entity.AttackRange) then
		return
	end

	local didDamage = targetCharacter:ApplyDamage(entity.Damage)
	if didDamage then
		targetCharacter:ApplyTemporarySpeedMultiplier("OnHitHaste", 1.45, 1.5)
		
		local interactionService = self.Services.InteractionService
		if interactionService and interactionService:IsInteracting(targetPlayer) then
			interactionService:InterruptInteraction(targetPlayer, "Damaged")
		end
	end

	entity:MarkAttack()

	DebugLog:Log("Entity", string.format(
		"[EntityService] %s hit %s for %d",
		entity.Model.Name,
		targetPlayer.Name,
		entity.Damage
	))
end

function EntityService:_countVisibleTargets(entity)
	local count = 0
	local roundManager = self.Services.RoundManager
	local characterService = self.Services.CharacterService
	local entityPosition = entity:GetPosition()
	if not roundManager or not characterService then
		return 0
	end

	if not entityPosition then
		return 0
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				local position = character.RootPart.Position
				local distance = (position - entityPosition).Magnitude
				if distance <= entity.DetectionRadius and self:_hasLineOfSight(entity, character) then
					count += 1
				end
			end
		end
	end

	return count
end

function EntityService:_hasLineOfSight(entity, character)
	local origin = entity:GetPosition()
	if not origin or not character or not character.RootPart then
		return false
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
	}

	local direction = character.RootPart.Position - origin
	local result = Workspace:Raycast(origin, direction, self.RaycastParams)
	if not result then
		return true
	end

	return result.Instance and result.Instance:IsDescendantOf(character.Model)
end

function EntityService:SetAllEntitiesActive(state)
	for _, entity in ipairs(self.Entities) do
		entity:SetActive(state)
		
		if not state then
			entity:ResetToSpawn()
		end
	end

	DebugLog:Log("Entity", "[EntityService] Entities active:", state)
end

return EntityService
