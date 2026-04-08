local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
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
	"CharacterService",
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
			local entity = BaseEntity.new(model, definition, self.Services)

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
		entity:EnterState(ENTITY_STATE.Patrol)
		return
	end

	local memory = entity:GetTargetMemory(targetPlayer)
	if not memory then
		entity:SetTarget(nil)
		entity:EnterState(ENTITY_STATE.Patrol)
		return
	end

	if memory.WasVisible then
		entity:EnterState(ENTITY_STATE.Chase)
	else
		entity:EnterState(ENTITY_STATE.Scout)
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

		local targetCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
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
	local context = self:_createEffectContext(entity, targetPlayer, nil, nil)
	self:_executeEffectSteps(entity, ability, context)

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
	if state ~= ENTITY_STATE.Chase and state ~= ENTITY_STATE.Scout and state ~= ENTITY_STATE.Rage then
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

	if not entity:IsInRange(targetCharacter.RootPart.Position, entity.AttackRange) then
		return
	end

	local damageAmount = entity:GetScaledDamage(entity.Damage)
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

		self:_executeBasicAttackEffects(entity, targetPlayer)
	end

	entity:MarkAttack()

	DebugLog:Log("Entity", string.format(
		"[EntityService] %s hit %s for %d",
		entity.Model.Name,
		targetPlayer.Name,
		damageAmount
	))
end

function EntityService:_executeBasicAttackEffects(entity, targetPlayer)
	local basicAttack = entity.BasicAttack
	if not basicAttack or not basicAttack.Effects then
		return
	end

	local context = self:_createEffectContext(entity, targetPlayer, nil, nil)
	for _, step in ipairs(basicAttack.Effects) do
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
	end
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
				if distance <= entity.DetectionRadius and self:_hasLineOfSight(entity, character) then
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
	local count = 0
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
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
			local statusEffectService = self.StatusEffectService
			if statusEffectService then
				statusEffectService:ClearStatuses(entity)
			end
			entity:ResetToSpawn()
		end
	end

	DebugLog:Log("Entity", "[EntityService] Entities active:", state)
end

return EntityService
