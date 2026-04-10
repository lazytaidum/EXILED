local BaseEntity = {}
BaseEntity.__index = BaseEntity

local ENTITY_STATE = {
	Dormant = "Dormant",
	Patrol = "Patrol",
	Scout = "Scout",
	Chase = "Chase",
	Casting = "Casting",
	Stunned = "Stunned",
	Rage = "Rage",
}

function BaseEntity.new(model, definition, services, runtimeData)
	local self = setmetatable({}, BaseEntity)
	
	self.Model = model
	self.Definition = definition or {}
	self.Services = services
	self.RuntimeData = runtimeData or {}
	self.RootPart = model.PrimaryPart or model:WaitForChild("HumanoidRootPart")
	
	self.Id = self.Definition.Id or model.Name
	self.DisplayName = self.Definition.DisplayName or model.Name
	self.StarRating = self.Definition.StarRating or self.Definition.StarRation or 1
	self.Weight = self.Definition.Weight or self.StarRating
	self.TemplateName = self.RuntimeData.TemplateName or self.Definition.TemplateName or self.Id
	self.IsRuntimeEntity = self.RuntimeData.IsRuntimeEntity == true
	self.IsSummon = self.RuntimeData.IsSummon == true
	self.OwnerEntity = self.RuntimeData.OwnerEntity
	self.ExpiresAt = self.RuntimeData.ExpiresAt
	
	self.Attributes = self.Definition.Attributes or {}
	
	local stats = self.Definition.Stats or {}
	local perception = self.Definition.Perception or {}
	local targeting = self.Definition.Targeting or {}
	local navigation = self.Definition.Navigation or {}
	local actions = self.Definition.Actions or {}
	local absorption = self.Definition.Absorption or {}
	
	self.IsActive = false
	self.MaxHealth = stats.Health or 100
	self.Health = self.MaxHealth
	self.Damage = stats.Damage or 10
	self.AttackRange = stats.AttackRange or 10
	self.AttackInterval = stats.AttackInterval or 1.5
	self.WalkSpeed = stats.WalkSpeed or stats.MoveSpeed or 10
	self.ChaseSpeed = stats.ChaseSpeed or self.WalkSpeed
	self.TerrorRadius = perception.TerrorRadius or stats.TerrorRadius or 80
	self.DetectionRadius = perception.DetectionRadius or stats.DetectionRadius or 60
	self.AttentionDuration = perception.AttentionDuration or stats.AttentionLevel or 2
	self.ChaseLostSightGraceDuration = perception.ChaseLostSightGraceDuration or math.min(self.AttentionDuration, 0.3)
	self.MemoryDuration = perception.MemoryDuration or (self.AttentionDuration + (navigation.ScoutLingerDuration or 1.25) + 2)
	self.InvestigationSpeedMultiplier = perception.InvestigationSpeedMultiplier or 0.85
	self.SearchDetectionRadiusMultiplier = perception.SearchDetectionRadiusMultiplier or 1
	self.IgnoreLineOfSightForDetection = perception.IgnoreLineOfSightForDetection == true
	self.IgnoreLineOfSightForInterest = perception.IgnoreLineOfSightForInterest == true
	self.IgnoreLineOfSightForAttacks = perception.IgnoreLineOfSightForAttacks == true
	self.TargetRetentionBonus = targeting.CurrentTargetBonus or 18
	self.LineOfSightBonus = targeting.LineOfSightBonus or 25
	self.MemoryBonus = targeting.MemoryBonus or 12
	self.DistanceWeight = targeting.DistanceWeight or 1
	self.StopDistance = targeting.StopDistance or math.max(self.AttackRange * 0.5, 2)
	self.PatrolRadius = navigation.PatrolRadius or 28
	self.PatrolPointMinDistance = navigation.PatrolPointMinDistance or 8
	self.PatrolPauseDuration = navigation.PatrolPauseDuration or 1.2
	self.GlobalPatrolRelocateChance = navigation.GlobalPatrolRelocateChance or 0.3
	self.RoamAnchorMaxDuration = navigation.RoamAnchorMaxDuration or 8
	self.ScoutLingerDuration = navigation.ScoutLingerDuration or 1.25
	self.ScoutPointRadius = navigation.ScoutPointRadius or math.max(6, self.PatrolPointMinDistance)
	self.ScoutPointMinDistance = navigation.ScoutPointMinDistance or math.max(3, self.PatrolPointMinDistance * 0.5)
	self.ScoutPointCount = navigation.ScoutPointCount or 2
	self.SearchSpeedMultiplier = navigation.SearchSpeedMultiplier or 1.5
	self.BasicAttack = actions.BasicAttack or {
		Id = "BasicAttack",
		Kind = "BasicAttack",
		Cooldown = self.AttackInterval,
	}
	self.Abilities = actions.Abilities or {}
	self.AbilityOrder = actions.AbilityOrder or {}
	self.Passives = actions.Passives or {}
	self.RoundHooks = actions.RoundHooks or {}
	self.AttackInterval = self.BasicAttack.Cooldown or self.AttackInterval
	self.AbsorptionResistancePerAbility = absorption.ResistancePerAbility or 0
	self.AbsorptionMaxResistance = absorption.MaxResistance or 0.75
	self.AbsorptionFullThreshold = absorption.FullThreshold or 0
	self.AbsorptionRelinquishDamageThreshold = absorption.RelinquishDamageThreshold or 0
	self.AbsorptionProfiles = absorption.Profiles or {}
	
	self.LastAttackTime = 0
	self.LastStateChangeTime = os.clock()
	self.PreviousState = ENTITY_STATE.Dormant
	self.CurrentState = ENTITY_STATE.Dormant
	self.Random = Random.new()
	self.TargetPlayer = nil
	self.TargetLastKnownPosition = nil
	self.TargetLastSeenAt = nil
	self.TargetLastVisibleAt = nil
	self.TargetMemory = {}
	self.PatrolDestination = nil
	self.PatrolPauseUntil = 0
	self.ScoutArrivalTime = nil
	self.ScoutOrigin = nil
	self.ScoutPointsRemaining = 0
	self.SearchMode = nil
	self.ConditionStates = {}
	self.DownedPlayers = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
	self.BasicAttackVariantIndex = 1
	self.AbsorbedAbilityCount = 0
	self.AbsorbedAbilitiesByPlayer = {}
	self.AbsorbedProfilesByPlayer = {}
	self.AbsorptionDamageProgress = 0
	self.PersistentModifiers = {
		Power = 0,
		Haste = 0,
		Resistance = 0,
	}
	
	self.SpawnCFrame = self.RootPart.CFrame
	self.RoamAnchor = self:GetSpawnPosition()
	self.RoamAnchorAssignedAt = os.clock()
	
	return self
end

function BaseEntity:SetActive(state)
	self.IsActive = state
	
	if state then
		self:EnterState(ENTITY_STATE.Patrol)
	else
		self:ResetRuntimeState()
		self:EnterState(ENTITY_STATE.Dormant)
	end
end

function BaseEntity:HasAttribute(attributeName)
	for _, value in ipairs(self.Attributes) do
		if value == attributeName then
			return true
		end
	end
	
	return false
end

function BaseEntity:GetState()
	return self.CurrentState
end

function BaseEntity:EnterState(stateName)
	if self.CurrentState == stateName then
		return
	end

	self.PreviousState = self.CurrentState
	self.CurrentState = stateName
	self.LastStateChangeTime = os.clock()

	if stateName == ENTITY_STATE.Patrol then
		self.ScoutArrivalTime = nil
		self.ScoutOrigin = nil
		self.ScoutPointsRemaining = 0
	elseif stateName == ENTITY_STATE.Scout then
		self.PatrolDestination = nil
		self.PatrolPauseUntil = 0
		self.ScoutOrigin = self.TargetLastKnownPosition
		self.ScoutPointsRemaining = 0
	elseif stateName == ENTITY_STATE.Chase then
		self.ScoutArrivalTime = nil
	end
end

function BaseEntity:GetStateDuration()
	return os.clock() - self.LastStateChangeTime
end

function BaseEntity:JustEnteredState(stateName, window)
	window = window or 0.4
	return self.CurrentState == stateName and self:GetStateDuration() <= window
end

function BaseEntity:EnteredCurrentStateFrom(stateName)
	return self.PreviousState == stateName
end

function BaseEntity:CanAttack()
	return os.clock() - self.LastAttackTime >= self.AttackInterval
end

function BaseEntity:MarkAttack(cooldown)
	self.LastAttackTime = os.clock()
	self:SetCooldown(self.BasicAttack.Id or "BasicAttack", cooldown or self.AttackInterval)
end

function BaseEntity:SetCooldown(key, duration)
	if duration == nil then
		self.Cooldowns[key] = nil
		return
	end

	self.Cooldowns[key] = os.clock() + duration
end

function BaseEntity:IsCooldownReady(key)
	local readyAt = self.Cooldowns[key]
	return readyAt == nil or os.clock() >= readyAt
end

function BaseEntity:UpdateActiveEffects()
	local now = os.clock()
	for index = #self.ActiveEffects, 1, -1 do
		local effect = self.ActiveEffects[index]
		if effect.ExpiresAt <= now then
			table.remove(self.ActiveEffects, index)
		end
	end
end

function BaseEntity:GetAbilityDefinitions()
	return self.Abilities
end

function BaseEntity:GetAbilityOrder()
	return self.AbilityOrder
end

function BaseEntity:GetPassiveDefinitions()
	return self.Passives
end

function BaseEntity:TriggerPassives(triggerName, context)
	for _, passive in pairs(self.Passives) do
		if passive.Trigger ~= triggerName then
			continue
		end

		for _, step in ipairs(passive.Effects or {}) do
			if step.Type == "ApplyPersistentModifierSelf" and step.Modifier and step.Amount then
				self:ApplyPersistentModifier(step.Modifier, step.Amount)
			end
		end
	end
end

function BaseEntity:GetActionCooldown(actionId)
	local readyAt = self.Cooldowns[actionId]
	if readyAt == nil then
		return 0
	end

	return math.max(0, readyAt - os.clock())
end

function BaseEntity:CanUseAbility(abilityId)
	local ability = self.Abilities[abilityId]
	if not ability then
		return false
	end

	if not self.IsActive or self.ActiveCast then
		return false
	end

	return self:IsCooldownReady(abilityId)
end

function BaseEntity:BeginCast(actionId, actionDefinition, targetPlayer)
	local castTime = actionDefinition.CastTime or 0
	self.ActiveCast = {
		Id = actionId,
		Definition = actionDefinition,
		TargetPlayer = targetPlayer,
		StartedAt = os.clock(),
		EndsAt = os.clock() + castTime,
	}

	self:EnterState(ENTITY_STATE.Casting)
end

function BaseEntity:GetActiveCast()
	return self.ActiveCast
end

function BaseEntity:IsCasting()
	return self.ActiveCast ~= nil
end

function BaseEntity:CompleteCast()
	local activeCast = self.ActiveCast
	self.ActiveCast = nil
	return activeCast
end

function BaseEntity:CancelCast()
	self.ActiveCast = nil
end

function BaseEntity:ApplyPersistentModifier(modifierName, amount)
	if self.PersistentModifiers[modifierName] == nil then
		self.PersistentModifiers[modifierName] = 0
	end

	self.PersistentModifiers[modifierName] += amount
end

function BaseEntity:ApplyTimedModifier(modifierName, amount, duration, sourceKey)
	table.insert(self.ActiveEffects, {
		Modifier = modifierName,
		Amount = amount,
		ExpiresAt = os.clock() + duration,
		SourceKey = sourceKey,
	})
end

function BaseEntity:GetModifierValue(modifierName)
	local total = self.PersistentModifiers[modifierName] or 0

	for _, effect in ipairs(self.ActiveEffects) do
		if effect.Modifier == modifierName then
			total += effect.Amount
		end
	end

	return total
end

function BaseEntity:GetScaledDamage(baseAmount)
	local amount = baseAmount or self.Damage
	local statusService = self.Services and self.Services.StatusEffectService
	local statusPower = statusService and statusService:GetModifier(self, "Power") or 0
	local weakness = statusService and statusService:GetModifier(self, "Weakness") or 0
	return math.max(0, math.floor((amount * (1 + self:GetModifierValue("Power") + statusPower) * math.max(0, 1 - weakness)) + 0.5))
end

function BaseEntity:Heal(amount)
	self.Health = math.clamp(self.Health + amount, 0, self.MaxHealth)
	return self.Health
end

function BaseEntity:HealPercent(percent)
	return self:Heal(self.MaxHealth * percent)
end

function BaseEntity:GetPosition()
	if self.RootPart then
		return self.RootPart.Position
	end
	
	return nil
end

function BaseEntity:SetTarget(player, lastKnownPosition, wasVisible)
	self.TargetPlayer = player
	if player and lastKnownPosition then
		self:RememberTarget(player, lastKnownPosition, wasVisible)
	elseif not player then
		self.TargetLastKnownPosition = nil
		self.TargetLastSeenAt = nil
		self.TargetLastVisibleAt = nil
	end
end

function BaseEntity:GetTarget()
	return self.TargetPlayer
end

function BaseEntity:GetTargetLastKnownPosition()
	return self.TargetLastKnownPosition
end

function BaseEntity:GetSpawnPosition()
	return self.SpawnCFrame and self.SpawnCFrame.Position or self:GetPosition()
end

function BaseEntity:GetRoamAnchor()
	return self.RoamAnchor or self:GetSpawnPosition()
end

function BaseEntity:SetRoamAnchor(position)
	if not position then
		return
	end

	self.RoamAnchor = position
	self.RoamAnchorAssignedAt = os.clock()
end

function BaseEntity:ShouldRelocateRoamAnchor()
	return (os.clock() - (self.RoamAnchorAssignedAt or 0)) >= self.RoamAnchorMaxDuration
end

function BaseEntity:RememberTarget(player, position, wasVisible)
	if not player or not position then
		return
	end

	local timestamp = os.clock()
	local previousMemory = self.TargetMemory[player]
	local attentionExpiresAt = previousMemory and previousMemory.AttentionExpiresAt or nil
	if wasVisible == true then
		attentionExpiresAt = timestamp + self.AttentionDuration
	end

	self.TargetMemory[player] = {
		LastKnownPosition = position,
		LastSeenAt = timestamp,
		LastVisibleAt = wasVisible == true and timestamp or (previousMemory and previousMemory.LastVisibleAt) or nil,
		WasVisible = wasVisible == true,
		AttentionExpiresAt = attentionExpiresAt,
	}

	if self.TargetPlayer == player then
		self.TargetLastKnownPosition = position
		self.TargetLastSeenAt = timestamp
		if wasVisible == true then
			self.TargetLastVisibleAt = timestamp
		end
	end
end

function BaseEntity:GetTargetMemory(player)
	local memory = self.TargetMemory[player]
	if not memory then
		return nil
	end

	if os.clock() - memory.LastSeenAt > self.MemoryDuration then
		self.TargetMemory[player] = nil
		return nil
	end

	return memory
end

function BaseEntity:HasTargetMemory(player)
	return self:GetTargetMemory(player) ~= nil
end

function BaseEntity:ClearExpiredMemory()
	local now = os.clock()
	for player, memory in pairs(self.TargetMemory) do
		if now - memory.LastSeenAt > self.MemoryDuration then
			self.TargetMemory[player] = nil
		end
	end
end

function BaseEntity:HasAttentionOnTarget(player)
	local memory = self:GetTargetMemory(player)
	if not memory or not memory.AttentionExpiresAt then
		return false
	end

	return os.clock() < memory.AttentionExpiresAt
end

function BaseEntity:SetTrackedTarget(player)
	self.TargetPlayer = player

	if not player then
		self.TargetLastKnownPosition = nil
		self.TargetLastSeenAt = nil
		return
	end

	local memory = self:GetTargetMemory(player)
	if memory then
		self.TargetLastKnownPosition = memory.LastKnownPosition
		self.TargetLastSeenAt = memory.LastSeenAt
		self.TargetLastVisibleAt = memory.LastVisibleAt
	end
end

function BaseEntity:ForgetTarget(player)
	if not player then
		return
	end

	self.TargetMemory[player] = nil

	if self.TargetPlayer == player then
		self.TargetPlayer = nil
		self.TargetLastKnownPosition = nil
		self.TargetLastSeenAt = nil
		self.TargetLastVisibleAt = nil
	end
end

function BaseEntity:GetTimeSinceTargetWasVisible(player)
	local memory = self:GetTargetMemory(player)
	local lastVisibleAt = memory and memory.LastVisibleAt
	if not lastVisibleAt then
		return math.huge
	end

	return math.max(0, os.clock() - lastVisibleAt)
end

function BaseEntity:SetConditionActive(key, isActive)
	if not key then
		return
	end

	local now = os.clock()
	local conditionState = self.ConditionStates[key]
	if isActive then
		if not conditionState or not conditionState.IsActive then
			self.ConditionStates[key] = {
				IsActive = true,
				StartedAt = now,
			}
			return
		end

		conditionState.IsActive = true
		return
	end

	if conditionState then
		conditionState.IsActive = false
		conditionState.StartedAt = nil
	end
end

function BaseEntity:GetConditionDuration(key)
	local conditionState = key and self.ConditionStates[key]
	if not conditionState or not conditionState.IsActive or not conditionState.StartedAt then
		return 0
	end

	return math.max(0, os.clock() - conditionState.StartedAt)
end

function BaseEntity:GetPatrolDestination()
	return self.PatrolDestination
end

function BaseEntity:GetPatrolDestinationReason()
	return self.PatrolDestinationReason
end

function BaseEntity:SetPatrolDestination(position, reason)
	self.PatrolDestination = position
	self.PatrolDestinationReason = reason
end

function BaseEntity:ClearPatrolDestination()
	self.PatrolDestination = nil
	self.PatrolDestinationReason = nil
end

function BaseEntity:IsNearPosition(position, range)
	local entityPosition = self:GetPosition()
	if not entityPosition or not position then
		return false
	end

	return (position - entityPosition).Magnitude <= (range or self.StopDistance)
end

function BaseEntity:HasReachedPatrolDestination()
	return self.PatrolDestination ~= nil and self:IsNearPosition(self.PatrolDestination, self.StopDistance + 0.5)
end

function BaseEntity:HasReachedScoutDestination()
	return self.TargetLastKnownPosition ~= nil and self:IsNearPosition(self.TargetLastKnownPosition, self.StopDistance + 0.5)
end

function BaseEntity:MarkPatrolPause(duration)
	self.PatrolPauseUntil = os.clock() + (duration or self.PatrolPauseDuration)
end

function BaseEntity:IsPatrolPaused()
	return os.clock() < (self.PatrolPauseUntil or 0)
end

function BaseEntity:MarkScoutArrival()
	if not self.ScoutArrivalTime then
		self.ScoutArrivalTime = os.clock()
	end
end

function BaseEntity:ClearScoutArrival()
	self.ScoutArrivalTime = nil
end

function BaseEntity:HasFinishedScoutLinger()
	return self.ScoutArrivalTime ~= nil and (os.clock() - self.ScoutArrivalTime) >= self.ScoutLingerDuration
end

function BaseEntity:BeginScoutSweep(origin)
	self.ScoutOrigin = origin or self.TargetLastKnownPosition or self:GetPosition()
	self.ScoutPointsRemaining = math.max(0, self.ScoutPointCount or 0)
	self.ScoutArrivalTime = nil
	self.PatrolDestination = nil
end

function BaseEntity:HasScoutSweepRemaining()
	return (self.ScoutPointsRemaining or 0) > 0
end

function BaseEntity:PickScoutDestination()
	local origin = self.ScoutOrigin or self.TargetLastKnownPosition or self:GetPosition()
	if not origin then
		return nil
	end

	for _ = 1, 8 do
		local angle = self.Random:NextNumber(0, math.pi * 2)
		local distance = self.Random:NextNumber(self.ScoutPointMinDistance, self.ScoutPointRadius)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not self:IsNearPosition(candidate, self.ScoutPointMinDistance * 0.75) then
			self.PatrolDestination = candidate
			self.PatrolDestinationReason = "Scout"
			self.ScoutPointsRemaining = math.max(0, (self.ScoutPointsRemaining or 0) - 1)
			return candidate
		end
	end

	self.PatrolDestination = origin
	self.PatrolDestinationReason = "Scout"
	self.ScoutPointsRemaining = math.max(0, (self.ScoutPointsRemaining or 0) - 1)
	return origin
end

function BaseEntity:PickPatrolDestination()
	local origin = self:GetRoamAnchor()
	if not origin then
		return nil
	end

	for _ = 1, 8 do
		local angle = self.Random:NextNumber(0, math.pi * 2)
		local distance = self.Random:NextNumber(self.PatrolPointMinDistance, self.PatrolRadius)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not self:IsNearPosition(candidate, self.PatrolPointMinDistance * 0.75) then
			self.PatrolDestination = candidate
			self.PatrolDestinationReason = "Patrol"
			return candidate
		end
	end

	self.PatrolDestination = origin
	self.PatrolDestinationReason = "Patrol"
	return origin
end

function BaseEntity:GetMoveSpeed()
	local haste = self:GetModifierValue("Haste")
	local statusService = self.Services and self.Services.StatusEffectService
	if statusService then
		if statusService:HasFlag(self, "Stunned") then
			return 0
		end

		haste += statusService:GetModifier(self, "Haste")
	end

	local hinder = statusService and statusService:GetModifier(self, "Hinder") or 0
	if self.SearchMode then
		return (self.ChaseSpeed * self.SearchSpeedMultiplier) * (1 + haste) * math.max(0, 1 - hinder)
	end

	if self.CurrentState == ENTITY_STATE.Chase or self.CurrentState == ENTITY_STATE.Rage then
		return self.ChaseSpeed * (1 + haste) * math.max(0, 1 - hinder)
	end

	if self.CurrentState == ENTITY_STATE.Scout then
		return (self.ChaseSpeed * self.InvestigationSpeedMultiplier) * (1 + haste) * math.max(0, 1 - hinder)
	end

	return self.WalkSpeed * (1 + haste) * math.max(0, 1 - hinder)
end

function BaseEntity:GetSearchHeightOffset()
	if not self.SearchMode then
		return 0
	end

	return self.SearchMode.HeightOffset or 0
end

function BaseEntity:GetCurrentBasicAttackDefinition()
	local basicAttack = self.BasicAttack or {}
	local variants = basicAttack.Variants
	if not variants or #variants == 0 then
		return basicAttack
	end

	local index = math.clamp(self.BasicAttackVariantIndex or 1, 1, #variants)
	local variant = variants[index]
	local merged = table.clone(basicAttack)
	for key, value in pairs(variant) do
		merged[key] = value
	end

	return merged
end

function BaseEntity:AdvanceBasicAttackVariant()
	local variants = self.BasicAttack and self.BasicAttack.Variants
	if not variants or #variants == 0 then
		return
	end

	self.BasicAttackVariantIndex += 1
	if self.BasicAttackVariantIndex > #variants then
		self.BasicAttackVariantIndex = 1
	end
end

function BaseEntity:AbsorbAbilityFromPlayer(player, count)
	if not player then
		return 0
	end

	count = count or 1
	local previousCount = self.AbsorbedAbilitiesByPlayer[player] or 0
	self.AbsorbedAbilitiesByPlayer[player] = previousCount + count
	self.AbsorbedAbilityCount += count
	self:_refreshAbsorptionResistance()

	local profiles = self.AbsorptionProfiles
	if profiles and #profiles > 0 then
		local playerProfiles = self.AbsorbedProfilesByPlayer[player] or {}
		for absorbIndex = previousCount + 1, self.AbsorbedAbilitiesByPlayer[player] do
			local profile = profiles[((absorbIndex - 1) % #profiles) + 1]
			if profile then
				table.insert(playerProfiles, profile)
			end
		end
		self.AbsorbedProfilesByPlayer[player] = playerProfiles
	end

	return self.AbsorbedAbilitiesByPlayer[player]
end

function BaseEntity:_refreshAbsorptionResistance()
	self.PersistentModifiers.Resistance = math.min(self.AbsorptionMaxResistance, self.AbsorbedAbilityCount * self.AbsorptionResistancePerAbility)
end

function BaseEntity:GetAbsorbedAbilityCount()
	return self.AbsorbedAbilityCount or 0
end

function BaseEntity:GetAbsorbedAbilityCountForPlayer(player)
	return player and (self.AbsorbedAbilitiesByPlayer[player] or 0) or 0
end

function BaseEntity:IsPlayerFullyAbsorbed(player)
	if not player or self.AbsorptionFullThreshold <= 0 then
		return false
	end

	return self:GetAbsorbedAbilityCountForPlayer(player) >= self.AbsorptionFullThreshold
end

function BaseEntity:GetInheritedBasicAttackEffects()
	local effects = {}

	for _, profiles in pairs(self.AbsorbedProfilesByPlayer) do
		for _, profile in ipairs(profiles) do
			for _, step in ipairs(profile.Effects or {}) do
				table.insert(effects, step)
			end
		end
	end

	return effects
end

function BaseEntity:RelinquishRandomAbsorbedAbility()
	if self.AbsorbedAbilityCount <= 0 then
		return nil
	end

	local candidates = {}
	for player, count in pairs(self.AbsorbedAbilitiesByPlayer) do
		if count and count > 0 then
			table.insert(candidates, player)
		end
	end

	if #candidates <= 0 then
		return nil
	end

	local targetPlayer = candidates[self.Random:NextInteger(1, #candidates)]
	self.AbsorbedAbilitiesByPlayer[targetPlayer] -= 1
	self.AbsorbedAbilityCount = math.max(0, self.AbsorbedAbilityCount - 1)

	local playerProfiles = self.AbsorbedProfilesByPlayer[targetPlayer]
	local removedProfile = nil
	if playerProfiles and #playerProfiles > 0 then
		removedProfile = table.remove(playerProfiles)
		if #playerProfiles <= 0 then
			self.AbsorbedProfilesByPlayer[targetPlayer] = nil
		end
	end

	if self.AbsorbedAbilitiesByPlayer[targetPlayer] <= 0 then
		self.AbsorbedAbilitiesByPlayer[targetPlayer] = nil
	end

	self:_refreshAbsorptionResistance()

	return {
		Player = targetPlayer,
		Profile = removedProfile,
		RemainingOnTarget = self.AbsorbedAbilitiesByPlayer[targetPlayer] or 0,
		TotalRemaining = self.AbsorbedAbilityCount,
	}
end

function BaseEntity:RegisterIncomingDamage(amount)
	if not amount or amount <= 0 then
		return {}
	end

	if self.AbsorptionRelinquishDamageThreshold <= 0 then
		return {}
	end

	self.AbsorptionDamageProgress += amount
	local released = {}
	while self.AbsorptionDamageProgress >= self.AbsorptionRelinquishDamageThreshold and self.AbsorbedAbilityCount > 0 do
		self.AbsorptionDamageProgress -= self.AbsorptionRelinquishDamageThreshold
		local relinquished = self:RelinquishRandomAbsorbedAbility()
		if not relinquished then
			self.AbsorptionDamageProgress = 0
			break
		end

		table.insert(released, relinquished)
	end

	return released
end

function BaseEntity:GetDetectionRange()
	if self.SearchMode then
		local multiplier = self.SearchMode.DetectionRadiusMultiplier or self.SearchDetectionRadiusMultiplier
		return self.DetectionRadius * multiplier
	end

	return self.DetectionRadius
end

function BaseEntity:GetStopDistance()
	return self.StopDistance
end

function BaseEntity:MoveToward(position, deltaTime)
	if not self.RootPart or not position then
		return
	end
	
	local currentPosition = self.RootPart.Position
	local offset = position - currentPosition
	local distance = offset.Magnitude
	
	if distance <= 0.01 then
		return
	end
	
	local stopDistance = self:GetStopDistance()
	if distance <= stopDistance then
		return
	end
	
	local direction = offset.Unit
	local moveStep = math.min(distance - stopDistance, self:GetMoveSpeed() * deltaTime)
	if moveStep <= 0 then
		return
	end
	
	local nextPosition = currentPosition + direction * moveStep

	if self.SearchMode and self.SearchMode.HeightOffset then
		nextPosition = Vector3.new(nextPosition.X, self.SearchMode.BaseY + self.SearchMode.HeightOffset, nextPosition.Z)
		position = Vector3.new(position.X, self.SearchMode.BaseY + self.SearchMode.HeightOffset, position.Z)
	end
	
	self.RootPart.CFrame = CFrame.new(nextPosition, position)
end

function BaseEntity:IsInRange(position, range)
	local entityPosition = self:GetPosition()
	if not entityPosition or not position then
		return false
	end

	return (position - entityPosition).Magnitude <= range
end

function BaseEntity:ResetRuntimeState()
	self.PreviousState = ENTITY_STATE.Dormant
	self.TargetPlayer = nil
	self.TargetLastKnownPosition = nil
	self.TargetLastSeenAt = nil
	self.TargetLastVisibleAt = nil
	self.TargetMemory = {}
	self.PatrolDestination = nil
	self.PatrolDestinationReason = nil
	self.PatrolPauseUntil = 0
	self.ScoutArrivalTime = nil
	self.ScoutOrigin = nil
	self.ScoutPointsRemaining = 0
	self.RoamAnchor = self:GetSpawnPosition()
	self.RoamAnchorAssignedAt = os.clock()
	self.SearchMode = nil
	self.ConditionStates = {}
	self.DownedPlayers = {}
	self.RegisteredRoundHookIds = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
	self.BasicAttackVariantIndex = 1
	self.AbsorbedAbilityCount = 0
	self.AbsorbedAbilitiesByPlayer = {}
	self.AbsorbedProfilesByPlayer = {}
	self.AbsorptionDamageProgress = 0
	self.LastAttackTime = 0
end

function BaseEntity:ResetToSpawn()
	if self.RootPart then
		self.RootPart.CFrame = self.SpawnCFrame
	end
	
	self.Health = self.MaxHealth
	self.PersistentModifiers.Power = 0
	self.PersistentModifiers.Haste = 0
	self.PersistentModifiers.Resistance = 0
	self:ResetRuntimeState()
	self:EnterState(self.IsActive and ENTITY_STATE.Patrol or ENTITY_STATE.Dormant)
end

function BaseEntity:Destroy()
	self.Model = nil
	self.Definition = nil
	self.RootPart = nil
	self.TargetPlayer = nil
end

function BaseEntity:SetLifetime(duration)
	if duration == nil then
		self.ExpiresAt = nil
		return
	end

	self.ExpiresAt = os.clock() + duration
end

function BaseEntity:HasExpired()
	return self.ExpiresAt ~= nil and os.clock() >= self.ExpiresAt
end

function BaseEntity:BeginSearchMode(searchId, duration, options)
	options = options or {}
	self.SearchMode = {
		Id = searchId,
		EndsAt = duration and (os.clock() + duration) or nil,
		HeightOffset = options.HeightOffset,
		BaseY = (self.RootPart and self.RootPart.Position.Y) or 0,
		IgnoreMovementBlockers = options.IgnoreMovementBlockers == true,
		DetectionRadiusMultiplier = options.DetectionRadiusMultiplier,
	}
end

function BaseEntity:IsSearchModeActive(searchId)
	if not self.SearchMode then
		return false
	end

	if searchId ~= nil and self.SearchMode.Id ~= searchId then
		return false
	end

	if self.SearchMode.EndsAt == nil then
		return true
	end

	return os.clock() < self.SearchMode.EndsAt
end

function BaseEntity:EndSearchMode(searchId)
	if not self.SearchMode then
		return
	end

	if searchId ~= nil and self.SearchMode.Id ~= searchId then
		return
	end

	if self.RootPart and self.SearchMode.BaseY then
		local currentPosition = self.RootPart.Position
		local lookVector = self.RootPart.CFrame.LookVector
		local groundedPosition = Vector3.new(currentPosition.X, self.SearchMode.BaseY, currentPosition.Z)
		self.RootPart.CFrame = CFrame.new(groundedPosition, groundedPosition + Vector3.new(lookVector.X, 0, lookVector.Z))
	end

	self.SearchMode = nil
end

return BaseEntity
