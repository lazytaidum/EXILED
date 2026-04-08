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

function BaseEntity.new(model, definition, services)
	local self = setmetatable({}, BaseEntity)
	
	self.Model = model
	self.Definition = definition or {}
	self.Services = services
	self.RootPart = model.PrimaryPart or model:WaitForChild("HumanoidRootPart")
	
	self.Id = self.Definition.Id or model.Name
	self.DisplayName = self.Definition.DisplayName or model.Name
	self.StarRating = self.Definition.StarRating or self.Definition.StarRation or 1
	self.Weight = self.Definition.Weight or self.StarRating
	
	self.Attributes = self.Definition.Attributes or {}
	
	local stats = self.Definition.Stats or {}
	local perception = self.Definition.Perception or {}
	local targeting = self.Definition.Targeting or {}
	local actions = self.Definition.Actions or {}
	
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
	self.InvestigationSpeedMultiplier = perception.InvestigationSpeedMultiplier or 0.85
	self.TargetRetentionBonus = targeting.CurrentTargetBonus or 18
	self.LineOfSightBonus = targeting.LineOfSightBonus or 25
	self.MemoryBonus = targeting.MemoryBonus or 12
	self.DistanceWeight = targeting.DistanceWeight or 1
	self.StopDistance = targeting.StopDistance or math.max(self.AttackRange * 0.5, 2)
	self.BasicAttack = actions.BasicAttack or {
		Id = "BasicAttack",
		Kind = "BasicAttack",
		Cooldown = self.AttackInterval,
	}
	self.Abilities = actions.Abilities or {}
	self.AbilityOrder = actions.AbilityOrder or {}
	self.Passives = actions.Passives or {}
	self.AttackInterval = self.BasicAttack.Cooldown or self.AttackInterval
	
	self.LastAttackTime = 0
	self.LastStateChangeTime = os.clock()
	self.CurrentState = ENTITY_STATE.Dormant
	self.TargetPlayer = nil
	self.TargetLastKnownPosition = nil
	self.TargetLastSeenAt = nil
	self.TargetMemory = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
	self.PersistentModifiers = {
		Power = 0,
		Haste = 0,
		Resistance = 0,
	}
	
	self.SpawnCFrame = self.RootPart.CFrame
	
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

	self.CurrentState = stateName
	self.LastStateChangeTime = os.clock()
end

function BaseEntity:GetStateDuration()
	return os.clock() - self.LastStateChangeTime
end

function BaseEntity:CanAttack()
	return os.clock() - self.LastAttackTime >= self.AttackInterval
end

function BaseEntity:MarkAttack()
	self.LastAttackTime = os.clock()
	self:SetCooldown(self.BasicAttack.Id or "BasicAttack", self.AttackInterval)
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
	end
end

function BaseEntity:GetTarget()
	return self.TargetPlayer
end

function BaseEntity:GetTargetLastKnownPosition()
	return self.TargetLastKnownPosition
end

function BaseEntity:RememberTarget(player, position, wasVisible)
	if not player or not position then
		return
	end

	local timestamp = os.clock()
	self.TargetMemory[player] = {
		LastKnownPosition = position,
		LastSeenAt = timestamp,
		WasVisible = wasVisible == true,
	}

	if self.TargetPlayer == player then
		self.TargetLastKnownPosition = position
		self.TargetLastSeenAt = timestamp
	end
end

function BaseEntity:GetTargetMemory(player)
	local memory = self.TargetMemory[player]
	if not memory then
		return nil
	end

	if os.clock() - memory.LastSeenAt > self.AttentionDuration then
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
		if now - memory.LastSeenAt > self.AttentionDuration then
			self.TargetMemory[player] = nil
		end
	end
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
	if self.CurrentState == ENTITY_STATE.Chase or self.CurrentState == ENTITY_STATE.Rage then
		return self.ChaseSpeed * (1 + haste) * math.max(0, 1 - hinder)
	end

	if self.CurrentState == ENTITY_STATE.Scout then
		return (self.ChaseSpeed * self.InvestigationSpeedMultiplier) * (1 + haste) * math.max(0, 1 - hinder)
	end

	return self.WalkSpeed * (1 + haste) * math.max(0, 1 - hinder)
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
	self.TargetPlayer = nil
	self.TargetLastKnownPosition = nil
	self.TargetLastSeenAt = nil
	self.TargetMemory = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
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

return BaseEntity
