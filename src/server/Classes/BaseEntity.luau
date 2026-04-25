local BaseEntity = {}
BaseEntity.__index = BaseEntity

local ENTITY_STATE = {
	Dormant = "Dormant",
	Patrol = "Patrol",
	Scout = "Scout",
	Chase = "Chase",
	AttackWindup = "AttackWindup",
	AttackRecovery = "AttackRecovery",
	Casting = "Casting",
	SpecialMovement = "SpecialMovement",
	Pinned = "Pinned",
	Stunned = "Stunned",
	Rage = "Rage",
	Dead = "Dead",
}

local function _toPlanar(vector)
	if typeof(vector) ~= "Vector3" then
		return nil
	end

	return Vector3.new(vector.X, 0, vector.Z)
end

local function _planarDistance(a, b)
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return math.huge
	end

	return _toPlanar(a - b).Magnitude
end

local FSM_STATE_HANDLERS = {
	[ENTITY_STATE.Patrol] = {
		OnEnter = function(self)
			if self:GetIntentName() == "Chase" then
				self:ClearIntent()
			end
		end,
		OnUpdate = function(self, context)
			if context.TargetPlayer and context.TargetPosition and context.HasVisibleSight == true then
				return ENTITY_STATE.Chase
			end

			if self:GetIntentName() == "Chase" then
				self:ClearIntent()
			end

			return nil
		end,
	},
	[ENTITY_STATE.Chase] = {
		OnEnter = function(self, _, context)
			self:ResetChaseLostSightTimer()
			local hasVisibleSight = context and context.HasVisibleSight == true
			local targetPosition = (hasVisibleSight and context.TargetPosition) or self:GetTargetLastKnownPosition()
			local targetPlayer = context and context.TargetPlayer or self:GetTarget()
			if typeof(targetPosition) == "Vector3" then
				self:SetCurrentSearchCenter(targetPosition)
				self:SetIntent("Chase", targetPosition, {
					Confidence = 1,
					Duration = context and context.IntentDuration or nil,
					Metadata = {
						Reason = context and context.IntentReason or "FSMChase",
						TargetPlayer = targetPlayer,
					},
				})
			end
		end,
		OnUpdate = function(self, context)
			local targetPlayer = context.TargetPlayer or self:GetTarget()
			local hasVisibleSight = context.HasVisibleSight == true
			local targetPosition = (hasVisibleSight and context.TargetPosition)
				or self:GetTargetLastKnownPosition()
			if not targetPlayer or typeof(targetPosition) ~= "Vector3" then
				self:ResetChaseLostSightTimer()
				return ENTITY_STATE.Patrol
			end

			if hasVisibleSight then
				self:ResetChaseLostSightTimer()
			else
				self:StartChaseLostSightTimer()
				if self:GetChaseLostSightDuration() >= (self.ChaseLostSightGraceDuration or 0) then
					return ENTITY_STATE.Scout
				end
			end

			self:SetCurrentSearchCenter(targetPosition)
			self:SetIntent("Chase", targetPosition, {
				Confidence = 1,
				Duration = context.IntentDuration,
				Metadata = {
					Reason = context.IntentReason or "FSMChase",
					TargetPlayer = targetPlayer,
				},
			})

			return nil
		end,
		OnExit = function(self, nextState)
			self:ResetChaseLostSightTimer()
			if (nextState == ENTITY_STATE.Patrol or nextState == ENTITY_STATE.Scout) and self:GetIntentName() == "Chase" then
				self:ClearIntent()
			end
		end,
	},
	[ENTITY_STATE.Scout] = {
		OnEnter = function(self, _, context)
			self:ResetChaseLostSightTimer()
			self:ClearIntent()
			local visibleContextPosition = context and context.HasVisibleSight == true and context.TargetPosition or nil
			local searchCenter = self:GetPredictedScoutSearchCenter(visibleContextPosition)
				or self:GetCurrentSearchCenter()
				or self:GetTargetLastKnownPosition()
			if typeof(searchCenter) == "Vector3" then
				self.ScoutOrigin = searchCenter
				self.ScoutPointsRemaining = math.max(0, self.ScoutPointCount or 0)
				self.ScoutSweepIndex = 0
				self.ScoutSearchResolved = self:IsNearPosition(searchCenter, self:GetStopDistance() + 1)
				self.ScoutSweepBaseAngle = self:GetScoutSweepBaseAngle(searchCenter)
				self:SetCurrentSearchCenter(searchCenter)
				if self.ScoutSearchResolved ~= true then
					self:SetPatrolDestination(searchCenter, "Search")
				end
			end
		end,
		OnUpdate = function(self, context)
			if context.TargetPlayer and context.TargetPosition and context.HasVisibleSight == true then
				return ENTITY_STATE.Chase
			end

			if self.ScoutArrivalTime and not self:IsPatrolLoitering() then
				self:ClearScoutArrival()
				if self.ScoutPointsRemaining <= 0 and not self:GetPatrolDestination() then
					return ENTITY_STATE.Patrol
				end
			end

			if not self:GetPatrolDestination() then
				local searchCenter = self:GetCurrentSearchCenter() or self:GetTargetLastKnownPosition()
				if typeof(searchCenter) == "Vector3" then
					if self.ScoutSearchResolved ~= true then
						self:SetPatrolDestination(searchCenter, "Search")
					end
				else
					return ENTITY_STATE.Patrol
				end
			end

			return nil
		end,
		OnExit = function(self)
			self:ClearPatrolDestination()
			self:ClearScoutArrival()
		end,
	},
	[ENTITY_STATE.SpecialMovement] = {
		OnEnter = function(self)
			self:ClearIntent()
			self:StopMovement()
		end,
	},
	[ENTITY_STATE.Pinned] = {
		OnEnter = function(self, _, context)
			self:ClearIntent()
			self:StopMovement()
			self.PinnedTargetPlayer = context and context.TargetPlayer or self.PinnedTargetPlayer
		end,
		OnExit = function(self)
			self.PinnedTargetPlayer = nil
		end,
	},
}

local function _requireDefinitionTable(definition, path, entityLabel)
	local value = definition[path]
	if type(value) ~= "table" then
		error(string.format("[BaseEntity] %s is missing required table '%s'", tostring(entityLabel), tostring(path)))
	end

	return value
end

local function _requireNumber(value, path, entityLabel)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(string.format("[BaseEntity] %s is missing required number '%s'", tostring(entityLabel), tostring(path)))
	end

	return value
end

function BaseEntity.new(model, definition, services, runtimeData)
	local self = setmetatable({}, BaseEntity)
	
	self.Model = model
	self.Definition = definition or {}
	self.Services = services
	self.RuntimeData = runtimeData or {}
	self.RootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:WaitForChild("HumanoidRootPart")
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	
	self.Id = self.Definition.Id or model.Name
	self.DisplayName = self.Definition.DisplayName or model.Name
	self.StarRating = _requireNumber(self.Definition.StarRating, "StarRating", self.Id)
	self.Weight = self.Definition.Weight or self.StarRating
	self.TemplateName = self.RuntimeData.TemplateName or self.Definition.TemplateName or self.Id
	self.IsRuntimeEntity = self.RuntimeData.IsRuntimeEntity == true
	self.IsSummon = self.RuntimeData.IsSummon == true
	self.OwnerEntity = self.RuntimeData.OwnerEntity
	self.ExpiresAt = self.RuntimeData.ExpiresAt
	
	self.Attributes = self.Definition.Attributes or {}
	
	local stats = _requireDefinitionTable(self.Definition, "Stats", self.Id)
	local perception = _requireDefinitionTable(self.Definition, "Perception", self.Id)
	local targeting = _requireDefinitionTable(self.Definition, "Targeting", self.Id)
	local navigation = _requireDefinitionTable(self.Definition, "Navigation", self.Id)
	local actions = _requireDefinitionTable(self.Definition, "Actions", self.Id)
	local absorption = self.Definition.Absorption or {}
	
	self.IsActive = false
	self.MaxHealth = _requireNumber(stats.Health, "Stats.Health", self.Id)
	self.Health = self.MaxHealth
	self.Damage = _requireNumber(stats.Damage, "Stats.Damage", self.Id)
	self.AttackRange = _requireNumber(stats.AttackRange, "Stats.AttackRange", self.Id)
	self.AttackInterval = _requireNumber(stats.AttackInterval, "Stats.AttackInterval", self.Id)
	self.WalkSpeed = _requireNumber(stats.WalkSpeed or stats.MoveSpeed, "Stats.WalkSpeed", self.Id)
	self.ChaseSpeed = _requireNumber(stats.ChaseSpeed, "Stats.ChaseSpeed", self.Id)
	self.TerrorRadius = _requireNumber(perception.TerrorRadius or stats.TerrorRadius, "Perception.TerrorRadius", self.Id)
	self.DetectionRadius = _requireNumber(perception.DetectionRadius or stats.DetectionRadius, "Perception.DetectionRadius", self.Id)
	self.AttentionDuration = _requireNumber(perception.AttentionDuration or stats.AttentionLevel, "Perception.AttentionDuration", self.Id)
	self.ChaseLostSightGraceDuration = perception.ChaseLostSightGraceDuration or 1.2
	self.ChaseProximityLockDistance = perception.ChaseProximityLockDistance or math.max((_requireNumber(targeting.StopDistance, "Targeting.StopDistance", self.Id)) + 2, 8)
	self.MemoryDuration = perception.MemoryDuration or (self.AttentionDuration + (navigation.ScoutLingerDuration or 1.25) + 2)
	self.InvestigationSpeedMultiplier = perception.InvestigationSpeedMultiplier or 0.85
	self.SearchDetectionRadiusMultiplier = perception.SearchDetectionRadiusMultiplier or 1
	self.DetectionFOVDegrees = perception.DetectionFOVDegrees or 100
	self.AwarenessRadius = perception.AwarenessRadius or math.min(10, self.DetectionRadius)
	self.SightOriginHeight = perception.SightOriginHeight or 2.5
	self.SightTargetHeights = perception.SightTargetHeights or { 2.5, 1.5, 0.2 }
	self.IgnoreLineOfSightForDetection = perception.IgnoreLineOfSightForDetection == true
	self.IgnoreLineOfSightForInterest = perception.IgnoreLineOfSightForInterest == true
	self.IgnoreLineOfSightForAttacks = perception.IgnoreLineOfSightForAttacks == true
	self.StimulusInvestigationRadiusMultiplier = perception.StimulusInvestigationRadiusMultiplier or 2.5
	self.SearchStimulusRadiusMultiplier = perception.SearchStimulusRadiusMultiplier or 3
	self.InvestigateIntentDuration = perception.InvestigateIntentDuration or 4
	self.SearchIntentDuration = perception.SearchIntentDuration or (self.AttentionDuration + 1.5)
	self.StimulusReinvestigateCooldown = perception.StimulusReinvestigateCooldown or 2.5
	self.TargetRetentionBonus = targeting.CurrentTargetBonus or 18
	self.LineOfSightBonus = targeting.LineOfSightBonus or 25
	self.MemoryBonus = targeting.MemoryBonus or 12
	self.DistanceWeight = _requireNumber(targeting.DistanceWeight, "Targeting.DistanceWeight", self.Id)
	self.StopDistance = _requireNumber(targeting.StopDistance, "Targeting.StopDistance", self.Id)
	self.PatrolRadius = _requireNumber(navigation.PatrolRadius, "Navigation.PatrolRadius", self.Id)
	self.PatrolPointMinDistance = _requireNumber(navigation.PatrolPointMinDistance, "Navigation.PatrolPointMinDistance", self.Id)
	self.PatrolPauseDuration = _requireNumber(navigation.PatrolPauseDuration, "Navigation.PatrolPauseDuration", self.Id)
	self.PatrolLoiterMinDuration = navigation.PatrolLoiterMinDuration or math.max(0.35, self.PatrolPauseDuration * 0.75)
	self.PatrolLoiterMaxDuration = navigation.PatrolLoiterMaxDuration or math.max(self.PatrolLoiterMinDuration, self.PatrolPauseDuration * 1.5)
	self.PatrolRecentPointMemory = navigation.PatrolRecentPointMemory or 3
	self.PatrolPointRandomOffset = navigation.PatrolPointRandomOffset or 4
	self.GlobalPatrolRelocateChance = navigation.GlobalPatrolRelocateChance or 0.3
	self.RoamAnchorMaxDuration = navigation.RoamAnchorMaxDuration or 8
	self.ScoutLingerDuration = _requireNumber(navigation.ScoutLingerDuration, "Navigation.ScoutLingerDuration", self.Id)
	self.ScoutPointRadius = navigation.ScoutPointRadius or math.max(6, self.PatrolPointMinDistance)
	self.ScoutPointMinDistance = navigation.ScoutPointMinDistance or math.max(3, self.PatrolPointMinDistance * 0.5)
	self.ScoutPointCount = navigation.ScoutPointCount or 2
	self.ScoutSearchCommitDuration = navigation.ScoutSearchCommitDuration or 1.1
	self.ScoutPredictionSeconds = navigation.ScoutPredictionSeconds or 0.45
	self.ScoutPredictionMaxDistance = navigation.ScoutPredictionMaxDistance or math.max(self.StopDistance + 2, self.ScoutPointMinDistance)
	self.ScoutSweepAngleDegrees = navigation.ScoutSweepAngleDegrees or 75
	self.ScoutScanAngleDegrees = navigation.ScoutScanAngleDegrees or 55
	self.DestinationCommitDuration = navigation.DestinationCommitDuration or 0.45
	self.SearchSpeedMultiplier = _requireNumber(navigation.SearchSpeedMultiplier, "Navigation.SearchSpeedMultiplier", self.Id)
	self.MovementSpeedAcceleration = navigation.MovementSpeedAcceleration or 95
	self.MovementSpeedDeceleration = navigation.MovementSpeedDeceleration or 140
	self.MovementSpeedSnapThreshold = navigation.MovementSpeedSnapThreshold or 0.05
	self.HoverHeight = navigation.HoverHeight or 0
	self.UsePathfinding = navigation.UsePathfinding == true
	self.LockMovementY = navigation.LockMovementY == true
	self.PathRecomputeInterval = navigation.PathRecomputeInterval or 0.75
	self.PathWaypointTolerance = navigation.PathWaypointTolerance or math.max(self.StopDistance + 1.5, 5)
	self.AgentRadius = navigation.AgentRadius or 2
	self.AgentHeight = navigation.AgentHeight or 5
	self.AgentCanJump = navigation.AgentCanJump == true
	self.AgentWaypointSpacing = navigation.AgentWaypointSpacing or math.max(self.StopDistance + 2, 6)
	self.BasicAttack = _requireDefinitionTable(actions, "BasicAttack", self.Id)
	self.Abilities = _requireDefinitionTable(actions, "Abilities", self.Id)
	self.Passives = _requireDefinitionTable(actions, "Passives", self.Id)
	self.RoundHooks = actions.RoundHooks or {}
	self.DeathAction = actions.Death
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
	self.TargetLastKnownVelocity = nil
	self.TargetLastSeenAt = nil
	self.TargetLastVisibleAt = nil
	self.ChaseLostSightStartedAt = nil
	self.TargetMemory = {}
	self.CurrentIntent = nil
	self.IntentTargetPosition = nil
	self.IntentSourceStimulus = nil
	self.IntentExpiresAt = nil
	self.IntentConfidence = 0
	self.IntentMetadata = nil
	self.InvestigatedStimulusKeys = {}
	self.CurrentSearchCenter = nil
	self.PatrolDestination = nil
	self.PatrolDestinationPointId = nil
	self.PatrolDestinationAssignedAt = 0
	self.PatrolPauseUntil = 0
	self.RecentPatrolPointIds = {}
	self.ScoutArrivalTime = nil
	self.ScoutOrigin = nil
	self.ScoutPointsRemaining = 0
	self.ScoutSweepIndex = 0
	self.ScoutSweepBaseAngle = nil
	self.ScoutSearchResolved = false
	self.SearchMode = nil
	self.ConditionStates = {}
	self.DownedPlayers = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
	self.ActiveBasicAttack = nil
	self.ActiveSpecialMovement = nil
	self.ActionSequenceId = 0
	self.SpecialMovementLockUntil = 0
	self.SpecialMovementPlatformStand = false
	self.PinnedTargetPlayer = nil
	self.BasicAttackVariantIndex = 1
	self.AbsorbedAbilityCount = 0
	self.AbsorbedAbilitiesByPlayer = {}
	self.AbsorbedProfilesByPlayer = {}
	self.AbsorptionDamageProgress = 0
	self.Dead = false
	self.DeathStartedAt = nil
	self.DeathReason = nil
	self.PendingDespawnAt = nil
	self.PendingDespawnReason = nil
	self.PersistentModifiers = {
		Power = 0,
		Haste = 0,
		Resistance = 0,
	}
	
	self.SpawnCFrame = self.RootPart.CFrame
	self.DefaultRootAnchored = self.RootPart.Anchored
	self.HoverBaseY = self.SpawnCFrame.Position.Y
	self.RoamAnchor = self:GetSpawnPosition()
	self.RoamAnchorAssignedAt = os.clock()
	self.NavigationWaypoints = nil
	self.NavigationWaypointIndex = 0
	self.NavigationDestination = nil
	self.NavigationPathComputedAt = 0
	self.LastIssuedMoveTarget = nil
	self.LastIssuedMoveAt = 0
	self.TargetHumanoidWalkSpeed = 0
	self.CurrentHumanoidWalkSpeed = 0
	self.LastHumanoidWalkSpeedTarget = 0
	if self.Humanoid then
		self.Humanoid.WalkSpeed = 0
	end
	
	return self
end

function BaseEntity:SetActive(state)
	self.IsActive = state
	
	if state then
		if self.Humanoid and self.Model then
			for _, descendant in ipairs(self.Model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
				end
			end
		end
		self:EnterState(ENTITY_STATE.Patrol)
	else
		self:ResetRuntimeState()
		self:EnterState(ENTITY_STATE.Dormant)
	end

	self:_applyHumanoidMovementState()
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

function BaseEntity:EnterState(stateName, context)
	if self.CurrentState == stateName then
		return false
	end

	local previousState = self.CurrentState
	local previousHandler = FSM_STATE_HANDLERS[previousState]
	if previousHandler and previousHandler.OnExit then
		previousHandler.OnExit(self, stateName, context)
	end

	self.PreviousState = self.CurrentState
	self.CurrentState = stateName
	self.LastStateChangeTime = os.clock()

	if stateName == ENTITY_STATE.Patrol then
		self.ScoutArrivalTime = nil
		self.ScoutOrigin = nil
		self.ScoutPointsRemaining = 0
		self.ScoutSweepIndex = 0
		self.ScoutSweepBaseAngle = nil
	elseif stateName == ENTITY_STATE.Scout then
		self.PatrolDestination = nil
		self.PatrolPauseUntil = 0
		self.ScoutOrigin = self.TargetLastKnownPosition
		self.ScoutPointsRemaining = 0
		self.ScoutSweepIndex = 0
		self.ScoutSearchResolved = false
		self.ScoutSweepBaseAngle = nil
	elseif stateName == ENTITY_STATE.Chase then
		self.ScoutArrivalTime = nil
	elseif stateName == ENTITY_STATE.Pinned then
		self.ScoutArrivalTime = nil
	end

	local nextHandler = FSM_STATE_HANDLERS[stateName]
	if nextHandler and nextHandler.OnEnter then
		nextHandler.OnEnter(self, previousState, context)
	end

	self:_applyHumanoidMovementState()
	return true
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

function BaseEntity:StartChaseLostSightTimer()
	if self.ChaseLostSightStartedAt == nil then
		self.ChaseLostSightStartedAt = os.clock()
	end
end

function BaseEntity:ResetChaseLostSightTimer()
	self.ChaseLostSightStartedAt = nil
end

function BaseEntity:GetChaseLostSightDuration()
	if self.ChaseLostSightStartedAt == nil then
		return 0
	end

	return math.max(0, os.clock() - self.ChaseLostSightStartedAt)
end

function BaseEntity:IsBehaviorStateLocked()
	return self.CurrentState == ENTITY_STATE.Dead
		or self.CurrentState == ENTITY_STATE.Stunned
		or self.CurrentState == ENTITY_STATE.AttackWindup
		or self.CurrentState == ENTITY_STATE.AttackRecovery
		or self.CurrentState == ENTITY_STATE.Casting
		or self.CurrentState == ENTITY_STATE.SpecialMovement
		or self.CurrentState == ENTITY_STATE.Pinned
		or self.CurrentState == ENTITY_STATE.Rage
end

function BaseEntity:UpdateStateMachine(context)
	context = context or {}

	if self:IsBehaviorStateLocked() then
		return self.CurrentState
	end

	if self.CurrentState ~= ENTITY_STATE.Patrol and self.CurrentState ~= ENTITY_STATE.Chase and self.CurrentState ~= ENTITY_STATE.Scout then
		self:EnterState(context.TargetPlayer and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, context)
	end

	local handler = FSM_STATE_HANDLERS[self.CurrentState]
	if not handler or not handler.OnUpdate then
		return self.CurrentState
	end

	local nextState = handler.OnUpdate(self, context)
	if nextState and nextState ~= self.CurrentState then
		self:EnterState(nextState, context)
		local nextHandler = FSM_STATE_HANDLERS[self.CurrentState]
		if nextHandler and nextHandler.OnUpdate then
			nextHandler.OnUpdate(self, context)
		end
	end

	return self.CurrentState
end

function BaseEntity:CanAttack()
	if not self.IsActive or self.ActiveCast or self.ActiveBasicAttack then
		return false
	end

	return self:IsCooldownReady(self.BasicAttack.Id or "BasicAttack")
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

function BaseEntity:GetPassiveDefinitions()
	return self.Passives
end

function BaseEntity:GetDeathDefinition()
	return self.DeathAction
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

	if not self.IsActive or self.ActiveCast or self.ActiveBasicAttack or self.ActiveSpecialMovement or self.PinnedTargetPlayer then
		return false
	end

	return self:IsCooldownReady(abilityId)
end

function BaseEntity:BeginBasicAttack(targetPlayer, attackDefinition, attackContext)
	if not self.IsActive or self.ActiveCast or self.ActiveBasicAttack then
		return nil
	end

	attackDefinition = attackDefinition or self:GetCurrentBasicAttackDefinition()
	if not attackDefinition then
		return nil
	end

	local hitDelay = math.max(0, attackDefinition.HitDelay or 0)
	local activeDuration = math.max(0.05, attackDefinition.ActiveDuration or 0.22)
	local hitRecoveryDuration = math.max(0, attackDefinition.HitRecoveryDuration or attackDefinition.RecoveryDuration or 0.35)
	local missRecoveryDuration = math.max(hitRecoveryDuration, attackDefinition.MissRecoveryDuration or math.max(hitRecoveryDuration + 0.18, hitRecoveryDuration * 1.5))
	local hitRecoverySpeedMultiplier = math.max(0, attackDefinition.HitRecoverySpeedMultiplier or attackDefinition.RecoverySpeedMultiplier or 0.75)
	local missRecoverySpeedMultiplier = math.max(0, attackDefinition.MissRecoverySpeedMultiplier or attackDefinition.RecoverySpeedMultiplier or 0.75)
	local cooldown = attackDefinition.Cooldown or self.AttackInterval
	local cooldownStartsOn = attackDefinition.CooldownStartsOn or "Hit"
	local now = os.clock()
	self.ActiveBasicAttack = {
		Id = attackDefinition.Id or self.BasicAttack.Id or "BasicAttack",
		Definition = attackDefinition,
		TargetPlayer = targetPlayer,
		Context = attackContext or {},
		StartedAt = now,
		HitsAt = now + hitDelay,
		ActiveEndsAt = now + hitDelay + activeDuration,
		HitRecoveryDuration = hitRecoveryDuration,
		MissRecoveryDuration = missRecoveryDuration,
		WindupSpeedMultiplier = attackDefinition.WindupSpeedMultiplier or 0.55,
		HitRecoverySpeedMultiplier = hitRecoverySpeedMultiplier,
		MissRecoverySpeedMultiplier = missRecoverySpeedMultiplier,
		RecoverySpeedMultiplier = hitRecoverySpeedMultiplier,
		RecoveryEndsAt = nil,
		Cooldown = cooldown,
		CooldownStartsOn = cooldownStartsOn,
		HasResolved = false,
		ResolvedAt = nil,
		Result = nil,
		DidHit = false,
		HitPlayer = nil,
	}

	if cooldownStartsOn == "Start" then
		self:MarkAttack(cooldown)
	end

	self:EnterState(ENTITY_STATE.AttackWindup, attackContext)
	return self.ActiveBasicAttack
end

function BaseEntity:GetActiveBasicAttack()
	return self.ActiveBasicAttack
end

function BaseEntity:IsBasicAttacking()
	return self.ActiveBasicAttack ~= nil
end

function BaseEntity:CompleteBasicAttack()
	local activeBasicAttack = self.ActiveBasicAttack
	self.ActiveBasicAttack = nil
	self:_applyHumanoidMovementState()
	return activeBasicAttack
end

function BaseEntity:CancelBasicAttack()
	self.ActiveBasicAttack = nil
	if not self.IsActive then
		self:EnterState(ENTITY_STATE.Dormant)
	elseif self.CurrentState == ENTITY_STATE.AttackWindup or self.CurrentState == ENTITY_STATE.AttackRecovery then
		local fallbackPosition = self:GetTargetLastKnownPosition()
		self:EnterState(self:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = self:GetTarget(),
			TargetPosition = fallbackPosition,
			HasDirectSight = false,
		})
	else
		self:_applyHumanoidMovementState()
	end
end

function BaseEntity:BeginCast(actionId, actionDefinition, targetPlayer, castContext)
	local castTime = actionDefinition.CastTime or 0
	self.ActiveCast = {
		Id = actionId,
		Definition = actionDefinition,
		TargetPlayer = targetPlayer,
		Context = castContext,
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
	self:_applyHumanoidMovementState()
	return activeCast
end

function BaseEntity:CancelCast()
	self.ActiveCast = nil
	if not self.IsActive then
		self:EnterState(ENTITY_STATE.Dormant)
	else
		self:EnterState(self:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = self:GetTarget(),
			TargetPosition = self:GetTargetLastKnownPosition(),
			HasDirectSight = false,
		})
	end
end

function BaseEntity:LockSpecialMovement(duration)
	self.SpecialMovementLockUntil = math.max(self.SpecialMovementLockUntil or 0, os.clock() + math.max(0, duration or 0))
end

function BaseEntity:IsSpecialMovementLocked()
	return os.clock() < (self.SpecialMovementLockUntil or 0)
end

function BaseEntity:UnlockSpecialMovement()
	self.SpecialMovementLockUntil = 0
end

function BaseEntity:_clearSpecialMovementVelocity()
	if self.RootPart then
		self.RootPart.AssemblyLinearVelocity = Vector3.zero
		self.RootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function BaseEntity:BeginSpecialMovement(movementId, duration, context)
	self.ActiveSpecialMovement = {
		Id = movementId or "SpecialMovement",
		StartedAt = os.clock(),
		EndsAt = duration and (os.clock() + math.max(0, duration)) or nil,
		Context = context,
	}
	if duration then
		self:LockSpecialMovement(duration)
	end
	if self.Humanoid then
		self.SpecialMovementPlatformStand = self.Humanoid.PlatformStand == true
		self.Humanoid.PlatformStand = true
		pcall(function()
			self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	self:EnterState(ENTITY_STATE.SpecialMovement, context)
	return self.ActiveSpecialMovement
end

function BaseEntity:GetActiveSpecialMovement()
	return self.ActiveSpecialMovement
end

function BaseEntity:CompleteSpecialMovement(suppressFallback)
	local activeSpecialMovement = self.ActiveSpecialMovement
	self.ActiveSpecialMovement = nil
	self:UnlockSpecialMovement()
	self:_clearSpecialMovementVelocity()
	if self.Humanoid then
		self.Humanoid.PlatformStand = self.SpecialMovementPlatformStand == true
		self.SpecialMovementPlatformStand = false
	end
	if not suppressFallback and self.CurrentState == ENTITY_STATE.SpecialMovement then
		self:EnterState(self:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = self:GetTarget(),
			TargetPosition = self:GetTargetLastKnownPosition(),
			HasDirectSight = false,
		})
	else
		self:_applyHumanoidMovementState()
	end
	return activeSpecialMovement
end

function BaseEntity:CancelSpecialMovement()
	self.ActiveSpecialMovement = nil
	self:UnlockSpecialMovement()
	self:_clearSpecialMovementVelocity()
	if self.Humanoid then
		self.Humanoid.PlatformStand = self.SpecialMovementPlatformStand == true
		self.SpecialMovementPlatformStand = false
	end
	if not self.IsActive then
		self:EnterState(ENTITY_STATE.Dormant)
	else
		self:EnterState(self:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = self:GetTarget(),
			TargetPosition = self:GetTargetLastKnownPosition(),
			HasDirectSight = false,
		})
	end
end

function BaseEntity:BeginPinned(targetPlayer, context)
	self.ActiveSpecialMovement = nil
	self:UnlockSpecialMovement()
	self:_clearSpecialMovementVelocity()
	if self.Humanoid then
		self.Humanoid.PlatformStand = false
		self.SpecialMovementPlatformStand = false
	end
	self.PinnedTargetPlayer = targetPlayer
	self:EnterState(ENTITY_STATE.Pinned, context or {
		TargetPlayer = targetPlayer,
		TargetPosition = self:GetTargetLastKnownPosition(),
	})
end

function BaseEntity:GetPinnedTarget()
	return self.PinnedTargetPlayer
end

function BaseEntity:EndPinned(nextState, context)
	self.PinnedTargetPlayer = nil
	local fallbackState = nextState
	if not fallbackState then
		fallbackState = self:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol
	end
	self:EnterState(fallbackState, context or {
		TargetPlayer = self:GetTarget(),
		TargetPosition = self:GetTargetLastKnownPosition(),
		HasDirectSight = false,
	})
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

function BaseEntity:SetTarget(player, lastKnownPosition, wasVisible, lastKnownVelocity)
	self.TargetPlayer = player
	if player and lastKnownPosition then
		local remembered = self:RememberTarget(player, lastKnownPosition, wasVisible, lastKnownVelocity)
		if remembered == false then
			self.TargetPlayer = nil
			self.TargetLastKnownPosition = nil
			self.TargetLastKnownVelocity = nil
			self.TargetLastSeenAt = nil
			self.TargetLastVisibleAt = nil
		end
	elseif not player then
		self.TargetLastKnownPosition = nil
		self.TargetLastKnownVelocity = nil
		self.TargetLastSeenAt = nil
		self.TargetLastVisibleAt = nil
	end
end

function BaseEntity:GetTarget()
	return self.TargetPlayer
end

function BaseEntity:SetIntent(intentName, targetPosition, options)
	options = options or {}
	self.CurrentIntent = intentName
	self.IntentTargetPosition = targetPosition
	self.IntentSourceStimulus = options.SourceStimulus
	self.IntentExpiresAt = options.Duration and (os.clock() + math.max(0, options.Duration)) or options.ExpiresAt or nil
	self.IntentConfidence = options.Confidence or 0
	self.IntentMetadata = options.Metadata

	if options.SearchCenter ~= nil then
		self.CurrentSearchCenter = options.SearchCenter
	end
end

function BaseEntity:GetIntentName()
	return self.CurrentIntent
end

function BaseEntity:GetIntentTargetPosition()
	return self.IntentTargetPosition
end

function BaseEntity:GetIntentSourceStimulus()
	return self.IntentSourceStimulus
end

function BaseEntity:GetIntentConfidence()
	return self.IntentConfidence or 0
end

function BaseEntity:GetIntentMetadata()
	return self.IntentMetadata
end

function BaseEntity:GetCurrentSearchCenter()
	return self.CurrentSearchCenter
end

function BaseEntity:SetCurrentSearchCenter(position)
	self.CurrentSearchCenter = position
end

function BaseEntity:HasIntent()
	return self.CurrentIntent ~= nil
end

function BaseEntity:IsIntentExpired()
	return self.IntentExpiresAt ~= nil and os.clock() >= self.IntentExpiresAt
end

function BaseEntity:ClearIntent()
	self.CurrentIntent = nil
	self.IntentTargetPosition = nil
	self.IntentSourceStimulus = nil
	self.IntentExpiresAt = nil
	self.IntentConfidence = 0
	self.IntentMetadata = nil
	self.CurrentSearchCenter = nil
end

function BaseEntity:MarkStimulusInvestigated(stimulusKey, duration)
	if not stimulusKey then
		return
	end

	self.InvestigatedStimulusKeys[stimulusKey] = os.clock() + math.max(0, duration or self.StimulusReinvestigateCooldown)
end

function BaseEntity:HasInvestigatedStimulus(stimulusKey)
	if not stimulusKey then
		return false
	end

	local expiresAt = self.InvestigatedStimulusKeys[stimulusKey]
	if not expiresAt then
		return false
	end

	if os.clock() >= expiresAt then
		self.InvestigatedStimulusKeys[stimulusKey] = nil
		return false
	end

	return true
end

function BaseEntity:ClearExpiredInvestigatedStimuli()
	local now = os.clock()
	for stimulusKey, expiresAt in pairs(self.InvestigatedStimulusKeys) do
		if now >= expiresAt then
			self.InvestigatedStimulusKeys[stimulusKey] = nil
		end
	end
end

function BaseEntity:GetTargetLastKnownPosition()
	return self.TargetLastKnownPosition
end

function BaseEntity:GetTargetLastKnownVelocity()
	return self.TargetLastKnownVelocity
end

function BaseEntity:GetPredictedScoutSearchCenter(basePosition)
	local searchCenter = basePosition or self:GetCurrentSearchCenter() or self:GetTargetLastKnownPosition()
	if typeof(searchCenter) ~= "Vector3" then
		return nil
	end

	local planarVelocity = _toPlanar(self.TargetLastKnownVelocity)
	if planarVelocity and planarVelocity.Magnitude > 0.5 then
		local leadDistance = math.min(
			math.max(0, self.ScoutPredictionMaxDistance or 0),
			planarVelocity.Magnitude * math.max(0, self.ScoutPredictionSeconds or 0)
		)
		if leadDistance > 0 then
			searchCenter += planarVelocity.Unit * leadDistance
		end
	end

	local forcedY = self:GetPreferredWorldY()
	if forcedY then
		searchCenter = Vector3.new(searchCenter.X, forcedY, searchCenter.Z)
	end

	return searchCenter
end

function BaseEntity:GetScoutSweepBaseAngle(searchCenter)
	local planarVelocity = _toPlanar(self.TargetLastKnownVelocity)
	if planarVelocity and planarVelocity.Magnitude > 0.5 then
		return math.atan2(planarVelocity.Z, planarVelocity.X)
	end

	local currentPosition = self:GetPosition()
	local planarDelta = currentPosition and typeof(searchCenter) == "Vector3" and _toPlanar(searchCenter - currentPosition) or nil
	if planarDelta and planarDelta.Magnitude > 0.5 then
		return math.atan2(planarDelta.Z, planarDelta.X)
	end

	return self.Random:NextNumber(0, math.pi * 2)
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

function BaseEntity:RememberTarget(player, position, wasVisible, lastKnownVelocity)
	if not player or not position then
		return false
	end

	local timestamp = os.clock()
	local previousMemory = self.TargetMemory[player]
	if wasVisible ~= true and not previousMemory then
		return false
	end

	local attentionExpiresAt = previousMemory and previousMemory.AttentionExpiresAt or nil
	if wasVisible == true then
		attentionExpiresAt = timestamp + self.AttentionDuration
	end

	local lastKnownPosition = position
	if wasVisible ~= true and previousMemory and typeof(previousMemory.LastKnownPosition) == "Vector3" then
		lastKnownPosition = previousMemory.LastKnownPosition
	end

	local planarVelocity = _toPlanar(lastKnownVelocity)
	if wasVisible ~= true and previousMemory and typeof(previousMemory.LastKnownVelocity) == "Vector3" then
		planarVelocity = previousMemory.LastKnownVelocity
	end

	self.TargetMemory[player] = {
		LastKnownPosition = lastKnownPosition,
		LastKnownVelocity = planarVelocity,
		LastSeenAt = timestamp,
		LastVisibleAt = wasVisible == true and timestamp or (previousMemory and previousMemory.LastVisibleAt) or nil,
		WasVisible = wasVisible == true,
		AttentionExpiresAt = attentionExpiresAt,
	}

	if self.TargetPlayer == player then
		self.TargetLastKnownPosition = lastKnownPosition
		self.TargetLastKnownVelocity = planarVelocity
		self.TargetLastSeenAt = timestamp
		if wasVisible == true then
			self.TargetLastVisibleAt = timestamp
		end
	end

	return true
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
		self.TargetLastKnownVelocity = nil
		self.TargetLastSeenAt = nil
		return
	end

	local memory = self:GetTargetMemory(player)
	if memory then
		self.TargetLastKnownPosition = memory.LastKnownPosition
		self.TargetLastKnownVelocity = memory.LastKnownVelocity
		self.TargetLastSeenAt = memory.LastSeenAt
		self.TargetLastVisibleAt = memory.LastVisibleAt
	else
		self.TargetLastKnownPosition = nil
		self.TargetLastKnownVelocity = nil
		self.TargetLastSeenAt = nil
		self.TargetLastVisibleAt = nil
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
		self.TargetLastKnownVelocity = nil
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

function BaseEntity:GetPatrolDestinationAge()
	if not self.PatrolDestination or not self.PatrolDestinationAssignedAt or self.PatrolDestinationAssignedAt <= 0 then
		return 0
	end

	return math.max(0, os.clock() - self.PatrolDestinationAssignedAt)
end

function BaseEntity:SetPatrolDestination(position, reason, pointId)
	self.PatrolDestination = position
	self.PatrolDestinationReason = reason
	self.PatrolDestinationPointId = pointId
	self.PatrolDestinationAssignedAt = os.clock()
end

function BaseEntity:ClearPatrolDestination()
	self.PatrolDestination = nil
	self.PatrolDestinationReason = nil
	self.PatrolDestinationPointId = nil
	self.PatrolDestinationAssignedAt = 0
	self:ClearNavigationPath()
end

function BaseEntity:GetPatrolDestinationPointId()
	return self.PatrolDestinationPointId
end

function BaseEntity:RememberPatrolPoint(pointId)
	if type(pointId) ~= "string" or pointId == "" then
		return
	end

	for index = #self.RecentPatrolPointIds, 1, -1 do
		if self.RecentPatrolPointIds[index] == pointId then
			table.remove(self.RecentPatrolPointIds, index)
		end
	end

	table.insert(self.RecentPatrolPointIds, 1, pointId)
	local maxMemory = math.max(0, self.PatrolRecentPointMemory or 0)
	while #self.RecentPatrolPointIds > maxMemory do
		table.remove(self.RecentPatrolPointIds)
	end
end

function BaseEntity:HasRecentlyVisitedPatrolPoint(pointId)
	if type(pointId) ~= "string" or pointId == "" then
		return false
	end

	for _, recentPointId in ipairs(self.RecentPatrolPointIds) do
		if recentPointId == pointId then
			return true
		end
	end

	return false
end

function BaseEntity:BeginPatrolLoiter(duration)
	local loiterDuration = duration
	if type(loiterDuration) ~= "number" then
		local minDuration = math.max(0, self.PatrolLoiterMinDuration or 0)
		local maxDuration = math.max(minDuration, self.PatrolLoiterMaxDuration or minDuration)
		loiterDuration = self.Random:NextNumber(minDuration, maxDuration)
	end

	self.PatrolPauseUntil = os.clock() + math.max(0, loiterDuration)
end

function BaseEntity:IsPatrolLoitering()
	return os.clock() < (self.PatrolPauseUntil or 0)
end

function BaseEntity:GetPatrolPauseRemaining()
	return math.max(0, (self.PatrolPauseUntil or 0) - os.clock())
end

function BaseEntity:IsNearPosition(position, range)
	local entityPosition = self:GetPosition()
	if not entityPosition or not position then
		return false
	end

	local forcedY = self:GetPreferredWorldY()
	if forcedY then
		entityPosition = Vector3.new(entityPosition.X, forcedY, entityPosition.Z)
		position = Vector3.new(position.X, forcedY, position.Z)
	end

	return (position - entityPosition).Magnitude <= (range or self.StopDistance)
end

function BaseEntity:ClearScoutArrival()
	self.ScoutArrivalTime = nil
end

function BaseEntity:BeginScoutLinger(duration)
	self.ScoutArrivalTime = os.clock()
	self:BeginPatrolLoiter(duration or self.ScoutLingerDuration)
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

function BaseEntity:GetSearchHeightOffset()
	if not self.SearchMode then
		return 0
	end

	return self.SearchMode.HeightOffset or 0
end

function BaseEntity:GetPreferredHeightOffset()
	if self.SearchMode and self.SearchMode.HeightOffset ~= nil then
		return self.SearchMode.HeightOffset
	end

	return self.HoverHeight or 0
end

function BaseEntity:GetPreferredBaseY()
	if self.SearchMode and self.SearchMode.BaseY ~= nil then
		return self.SearchMode.BaseY
	end

	return self.HoverBaseY or ((self.RootPart and self.RootPart.Position.Y) or 0)
end

function BaseEntity:GetPreferredWorldY()
	local preferredHeightOffset = self:GetPreferredHeightOffset()
	if preferredHeightOffset ~= 0 then
		return self:GetPreferredBaseY() + preferredHeightOffset
	end

	if self.LockMovementY then
		return self:GetPreferredBaseY()
	end

	return nil
end

function BaseEntity:ClearNavigationPath()
	self.NavigationWaypoints = nil
	self.NavigationWaypointIndex = 0
	self.NavigationDestination = nil
	self.NavigationPathComputedAt = 0
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

function BaseEntity:_getDesiredHumanoidWalkSpeed()
	if not self.IsActive then
		return 0
	end

	local baseSpeed = self.WalkSpeed
	if self.CurrentState == ENTITY_STATE.Casting
		or self.CurrentState == ENTITY_STATE.SpecialMovement
		or self.CurrentState == ENTITY_STATE.Pinned
		or self.CurrentState == ENTITY_STATE.Stunned
	then
		baseSpeed = 0
	elseif self.CurrentState == ENTITY_STATE.Chase or self.CurrentState == ENTITY_STATE.AttackWindup or self.CurrentState == ENTITY_STATE.AttackRecovery then
		baseSpeed = self.ChaseSpeed
	elseif self.CurrentState == ENTITY_STATE.Scout then
		baseSpeed = self.WalkSpeed * self.SearchSpeedMultiplier
	end

	local activeBasicAttack = self.ActiveBasicAttack
	if activeBasicAttack then
		if activeBasicAttack.HasResolved then
			baseSpeed *= activeBasicAttack.RecoverySpeedMultiplier or 0.75
		else
			baseSpeed *= activeBasicAttack.WindupSpeedMultiplier or 0.55
		end
	end

	baseSpeed *= math.max(0, 1 + (self:GetModifierValue("Haste") or 0))
	return baseSpeed
end

function BaseEntity:_applyHumanoidMovementState()
	if not self.Humanoid then
		return
	end

	self.Humanoid.AutoRotate = self.CurrentState ~= ENTITY_STATE.SpecialMovement
	self.TargetHumanoidWalkSpeed = math.max(0, self:_getDesiredHumanoidWalkSpeed())
end

function BaseEntity:_stepHumanoidWalkSpeed(deltaTime)
	if not self.Humanoid then
		return
	end

	local targetSpeed = math.max(0, self:_getDesiredHumanoidWalkSpeed())
	local currentSpeed = self.CurrentHumanoidWalkSpeed
	if type(currentSpeed) ~= "number" then
		currentSpeed = self.Humanoid.WalkSpeed or targetSpeed
	end

	local speedDelta = targetSpeed - currentSpeed
	local absoluteDelta = math.abs(speedDelta)
	if absoluteDelta <= math.max(0, self.MovementSpeedSnapThreshold or 0) then
		currentSpeed = targetSpeed
	else
		local rate = speedDelta > 0 and self.MovementSpeedAcceleration or self.MovementSpeedDeceleration
		local maxStep = math.max(0, rate or 0) * math.max(0, deltaTime or 0)
		if maxStep <= 0 or absoluteDelta <= maxStep then
			currentSpeed = targetSpeed
		else
			currentSpeed += (speedDelta > 0 and 1 or -1) * maxStep
		end
	end

	self.TargetHumanoidWalkSpeed = targetSpeed
	self.CurrentHumanoidWalkSpeed = currentSpeed
	self.LastHumanoidWalkSpeedTarget = targetSpeed
	self.Humanoid.WalkSpeed = math.max(0, currentSpeed)
end

function BaseEntity:UpdateHumanoidMovementState(deltaTime)
	if not self.Humanoid then
		return
	end

	self.Humanoid.AutoRotate = self.CurrentState ~= ENTITY_STATE.SpecialMovement
	self:_stepHumanoidWalkSpeed(deltaTime)
end

function BaseEntity:GetCurrentHumanoidWalkSpeed()
	if self.Humanoid then
		return self.Humanoid.WalkSpeed
	end

	return self.CurrentHumanoidWalkSpeed or 0
end

function BaseEntity:GetTargetHumanoidWalkSpeed()
	return self.TargetHumanoidWalkSpeed or 0
end

function BaseEntity:StopMovement()
	if self.Humanoid and self.RootPart then
		self.Humanoid:Move(Vector3.zero, false)
		self.Humanoid:MoveTo(self.RootPart.Position)
	end

	self.LastIssuedMoveTarget = nil
	self.LastIssuedMoveAt = 0
end

function BaseEntity:FacePosition(position)
	if typeof(position) ~= "Vector3" or not self.Model or not self.RootPart then
		return
	end

	local rootPosition = self.RootPart.Position
	local planarDirection = Vector3.new(position.X - rootPosition.X, 0, position.Z - rootPosition.Z)
	if planarDirection.Magnitude <= 0.01 then
		return
	end

	local currentPivot = self.Model:GetPivot()
	local rootOffset = currentPivot:ToObjectSpace(self.RootPart.CFrame)
	local desiredRootCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection.Unit)
	self.Model:PivotTo(desiredRootCFrame * rootOffset:Inverse())
end

function BaseEntity:UpdateScoutScan()
	if self.CurrentState ~= ENTITY_STATE.Scout or not self.RootPart then
		return
	end

	local elapsed = self.ScoutArrivalTime and math.max(0, os.clock() - self.ScoutArrivalTime) or 0
	local baseAngle = self.ScoutSweepBaseAngle
	if type(baseAngle) ~= "number" then
		baseAngle = self:GetScoutSweepBaseAngle(self:GetCurrentSearchCenter() or self.ScoutOrigin or self:GetTargetLastKnownPosition())
		self.ScoutSweepBaseAngle = baseAngle
	end

	local scanAngle = baseAngle + math.sin(elapsed * 5.5) * math.rad(self.ScoutScanAngleDegrees or 55)
	local scanDistance = math.max((self.StopDistance or 0) + 2, self.ScoutPointMinDistance or 3)
	local focusPosition = self.RootPart.Position + Vector3.new(math.cos(scanAngle) * scanDistance, 0, math.sin(scanAngle) * scanDistance)
	self.ScoutScanFocusPosition = focusPosition
end

function BaseEntity:IsInRange(position, range)
	local entityPosition = self:GetPosition()
	if not entityPosition or not position then
		return false
	end

	return (position - entityPosition).Magnitude <= range
end

function BaseEntity:ResetRuntimeState()
	self:StopMovement()
	self.PreviousState = ENTITY_STATE.Dormant
	self.Dead = false
	self.DeathStartedAt = nil
	self.DeathReason = nil
	self.PendingDespawnAt = nil
	self.PendingDespawnReason = nil
	self.TargetPlayer = nil
	self.TargetLastKnownPosition = nil
	self.TargetLastKnownVelocity = nil
	self.TargetLastSeenAt = nil
	self.TargetLastVisibleAt = nil
	self.ChaseLostSightStartedAt = nil
	self.TargetMemory = {}
	self.ScoutScanFocusPosition = nil
	self.CurrentIntent = nil
	self.IntentTargetPosition = nil
	self.IntentSourceStimulus = nil
	self.IntentExpiresAt = nil
	self.IntentConfidence = 0
	self.IntentMetadata = nil
	self.InvestigatedStimulusKeys = {}
	self.CurrentSearchCenter = nil
	self.PatrolDestination = nil
	self.PatrolDestinationReason = nil
	self.PatrolDestinationPointId = nil
	self.PatrolDestinationAssignedAt = 0
	self.PatrolPauseUntil = 0
	self.RecentPatrolPointIds = {}
	self.ScoutArrivalTime = nil
	self.ScoutOrigin = nil
	self.ScoutPointsRemaining = 0
	self.ScoutSweepIndex = 0
	self.ScoutSweepBaseAngle = nil
	self.ScoutSearchResolved = false
	self.RoamAnchor = self:GetSpawnPosition()
	self.RoamAnchorAssignedAt = os.clock()
	self.SearchMode = nil
	self.ConditionStates = {}
	self.DownedPlayers = {}
	self.RegisteredRoundHookIds = {}
	self.Cooldowns = {}
	self.ActiveEffects = {}
	self.ActiveCast = nil
	self.ActiveBasicAttack = nil
	self.ActiveSpecialMovement = nil
	self.ActionSequenceId = 0
	self.SpecialMovementLockUntil = 0
	self.SpecialMovementPlatformStand = false
	self.PinnedTargetPlayer = nil
	self.BasicAttackVariantIndex = 1
	self.AbsorbedAbilityCount = 0
	self.AbsorbedAbilitiesByPlayer = {}
	self.AbsorbedProfilesByPlayer = {}
	self.AbsorptionDamageProgress = 0
	self.LastAttackTime = 0
	self:ClearNavigationPath()
	self.TargetHumanoidWalkSpeed = 0
	self.CurrentHumanoidWalkSpeed = 0
	self.LastHumanoidWalkSpeedTarget = 0
	if self.Humanoid then
		self.Humanoid.WalkSpeed = 0
	end
	if self.RootPart then
		self.RootPart.Anchored = self.DefaultRootAnchored
	end
end

function BaseEntity:ResetToSpawn()
	self:StopMovement()
	if self.Model and self.Model.Parent then
		local currentPivot = self.Model:GetPivot()
		local rootOffset = currentPivot:ToObjectSpace(self.RootPart.CFrame)
		self.Model:PivotTo(self.SpawnCFrame * rootOffset:Inverse())
	elseif self.RootPart then
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
	self.Humanoid = nil
	self.TargetPlayer = nil
	self.DeathAction = nil
	self.ActiveBasicAttack = nil
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

function BaseEntity:IsDead()
	return self.Dead == true
end

function BaseEntity:MarkDead(reason, despawnDelay)
	if self.Dead then
		return false
	end

	self.Dead = true
	self.IsActive = false
	self.DeathReason = reason
	self.DeathStartedAt = os.clock()
	self.PendingDespawnReason = reason or "Died"
	self.PendingDespawnAt = os.clock() + math.max(0, despawnDelay or 0)
	self.ActiveCast = nil
	self.ActiveBasicAttack = nil
	self:UnlockSpecialMovement()
	self:EnterState(ENTITY_STATE.Dead)
	return true
end

function BaseEntity:IsReadyToDespawn()
	return self.PendingDespawnAt ~= nil and os.clock() >= self.PendingDespawnAt
end

function BaseEntity:GetPendingDespawnReason()
	return self.PendingDespawnReason
end

function BaseEntity:BeginSearchMode(searchId, duration, options)
	options = options or {}
	local currentY = (self.RootPart and self.RootPart.Position.Y) or 0
	local currentHeightOffset = self:GetPreferredHeightOffset()
	self.SearchMode = {
		Id = searchId,
		EndsAt = duration and (os.clock() + duration) or nil,
		HeightOffset = options.HeightOffset,
		BaseY = currentY - currentHeightOffset,
		IgnoreMovementBlockers = options.IgnoreMovementBlockers == true,
		DetectionRadiusMultiplier = options.DetectionRadiusMultiplier,
		AnchorRootPart = options.AnchorRootPart == true,
		PreviousAnchored = self.RootPart and self.RootPart.Anchored or self.DefaultRootAnchored,
	}

	self:ClearNavigationPath()

	if self.RootPart and self.SearchMode.AnchorRootPart then
		self.RootPart.Anchored = true
	end
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

	local previousAnchored = self.SearchMode.PreviousAnchored
	self.SearchMode = nil
	self:ClearNavigationPath()

	if self.RootPart then
		self.RootPart.Anchored = previousAnchored ~= nil and previousAnchored or self.DefaultRootAnchored
	end
end

return BaseEntity
