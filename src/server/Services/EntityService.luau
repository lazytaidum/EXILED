local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local EntityAbilityRules = require(ServerScriptService.Server.Utility.EntityAbilityRules)
local BaseEntity = require(ServerScriptService.Server.Classes.BaseEntity)
local EntityEffectExecutors = require(ServerScriptService.Server.Utility.EntityEffectExecutors)
local EntityEffectResolvers = require(ServerScriptService.Server.Utility.EntityEffectResolvers)
local MovingTargetPathTracker = require(ServerScriptService.Server.Utility.MovingTargetPathTracker)
local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local EntityPresentationConstants = require(ReplicatedStorage.Shared.Constants.EntityPresentationConstants)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local RoundOutcome = require(ReplicatedStorage.Shared.Enums.RoundOutcome)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityService = {}
EntityService.Name = "EntityService"
EntityService.Dependencies = {
	"RoundManager",
	"RoundHookService",
	"CharacterService",
	"StimulusService",
	"SpawnService",
	"StaminaService",
	"StatusEffectService",
	"InteractionService",
	"StruggleService",
	"BreathHoldService",
	"RemoteRegistry",
}

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

local RECENT_HIT_DEBUG_DURATION = 0.75
local LUNGE_DEBUG_VISUAL_DURATION = 2.5
local BASIC_ATTACK_DEBUG_FLASH_DURATION = 0.18
local BASIC_ATTACK_BLOCKED_COOLDOWN_KEY = "BasicAttackBlocked"
local BASIC_ATTACK_BLOCKED_RETRY_DURATION = 0.45
local BASIC_ATTACK_PATH_RETRY_DURATION = 0.25
local ENTITY_ANIMATION_BLEND_TIME = 0.12
local NAVIGATION_SAMPLE_ROOT_NAMES = {
	"CharacterFolders",
	"EntityNavigation",
	"NPCNavigation",
	"Characters",
}
local PATROL_POINT_ROOT_NAME = "PatrolPoints"

function EntityService:Init(services)
	self.Services = services
	self.Entities = {}
	self.ActiveProjectiles = {}
	self.EntityTemplates = {}
	self.UpdateInterval = 0.2
	self.NextRoundHookRuntimeId = 0
	self.NextEntityRuntimeId = 0

	self.EntitiesFolder = Workspace:WaitForChild("Entities")
	self.MapBounds = Workspace:FindFirstChild("MapBounds")
	self.SharedFolder = ReplicatedStorage:WaitForChild("Shared")
	self.EntityPresentationFolder = self.SharedFolder:FindFirstChild(EntityPresentationConstants.RuntimeFolderName)
	if not self.EntityPresentationFolder then
		self.EntityPresentationFolder = Instance.new("Folder")
		self.EntityPresentationFolder.Name = EntityPresentationConstants.RuntimeFolderName
		self.EntityPresentationFolder.Parent = self.SharedFolder
	end
	self.EntityPresentationStates = {}
	self.EntityAnimationRuntimes = {}
	self.EntityMovementTrackers = {}
	self.EntityAttackDebugVisuals = {}
	self.NavigationSampleRoot = nil
	self.NavigationSampleCache = {}
	self.PatrolPointRoot = nil
	self.RoundSuppressionParticipants = {}
	self.RoundSuppressionParticipantCount = 0
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
	self:_bindNavigationSampleRoot()
	self.EntityAbilityVisualRemote = self.RemoteRegistry and self.RemoteRegistry:GetRemote(RemoteNames.EntityAbilityVisual)

	task.spawn(function()
		self:_runEntityLoop()
	end)

	self.MovementSpeedConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_updateEntityMovementSpeeds(deltaTime)
	end)

	DebugLog:Log("Entity", "[EntityService] Started")
end

function EntityService:_updateEntityMovementSpeeds(deltaTime)
	for _, entity in ipairs(self.Entities or {}) do
		if entity.UpdateHumanoidMovementState then
			entity:UpdateHumanoidMovementState(deltaTime)
		end
	end
end

function EntityService:_resolveNavigationSampleRoot()
	for _, rootName in ipairs(NAVIGATION_SAMPLE_ROOT_NAMES) do
		local candidate = Workspace:FindFirstChild(rootName)
		if candidate and candidate:IsA("Folder") then
			for _, child in ipairs(candidate:GetChildren()) do
				if child:IsA("Folder") then
					return candidate
				end
			end
		end
	end

	return nil
end

local function _normalizeEntityAnimationId(animationId)
	if animationId == nil then
		return nil
	end

	if type(animationId) == "number" then
		return "rbxassetid://" .. tostring(animationId)
	end

	if type(animationId) ~= "string" or animationId == "" then
		return nil
	end

	if string.find(animationId, "rbxassetid://", 1, true) == 1 then
		return animationId
	end

	if string.match(animationId, "^%d+$") then
		return "rbxassetid://" .. animationId
	end

	return animationId
end

local function _getEntityAnimationKeysForState(stateName)
	if stateName == ENTITY_STATE.Patrol or stateName == ENTITY_STATE.Scout then
		return { "Patrol", "Scout", "Walk", "Move", "Idle" }
	elseif stateName == ENTITY_STATE.Chase or stateName == ENTITY_STATE.Rage then
		return { "Chase", "Run", "Move", "Walk", "Patrol", "Idle" }
	elseif stateName == ENTITY_STATE.AttackWindup or stateName == ENTITY_STATE.AttackRecovery then
		return { "Attack", "BasicAttack", "Swing", "Move", "Walk", "Patrol", "Idle" }
	elseif stateName == ENTITY_STATE.Casting then
		return { "Casting", "Cast", "Ability", "Idle" }
	elseif stateName == ENTITY_STATE.Stunned then
		return { "Stunned", "Hit", "Idle" }
	elseif stateName == ENTITY_STATE.Dead then
		return { "Death", "Dead" }
	end

	return { "Idle", "Patrol", "Walk", "Move" }
end

function EntityService:_clearEntityAnimationRuntime(entity)
	local runtime = self.EntityAnimationRuntimes[entity]
	if not runtime then
		return
	end

	if runtime.Tracks then
		for _, track in pairs(runtime.Tracks) do
			pcall(function()
				track:Stop(0.05)
				track:Destroy()
			end)
		end
	end

	self.EntityAnimationRuntimes[entity] = nil
end

function EntityService:_resolveEntityAnimator(model)
	if not model or not model.Parent then
		return nil, nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return humanoid, animator
end

function EntityService:_ensureEntityAnimationRuntime(entity)
	if not entity or not entity.Model then
		return nil
	end

	local existingRuntime = self.EntityAnimationRuntimes[entity]
	if existingRuntime and existingRuntime.Model == entity.Model and existingRuntime.Animator and existingRuntime.Animator.Parent then
		return existingRuntime
	end

	self:_clearEntityAnimationRuntime(entity)

	local definition = EntityDefinitions[entity.Id]
	local presentation = definition and definition.Presentation or nil
	local animationIds = presentation and presentation.AnimationIds or nil
	if type(animationIds) ~= "table" then
		return nil
	end

	local humanoid, animator = self:_resolveEntityAnimator(entity.Model)
	if not humanoid or not animator then
		return nil
	end

	local tracks = {}
	for key, animationId in pairs(animationIds) do
		local normalizedId = _normalizeEntityAnimationId(animationId)
		if normalizedId then
			local animation = Instance.new("Animation")
			animation.Name = "EntityAnimation_" .. tostring(key)
			animation.AnimationId = normalizedId
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			animation:Destroy()
			if ok and track then
				local loweredKey = string.lower(tostring(key))
				track.Priority = (loweredKey == "attack" or loweredKey == "basicattack" or loweredKey == "swing")
					and Enum.AnimationPriority.Action
					or Enum.AnimationPriority.Movement
				tracks[loweredKey] = track
			end
		end
	end

	if next(tracks) == nil then
		return nil
	end

	local runtime = {
		Model = entity.Model,
		Humanoid = humanoid,
		Animator = animator,
		Tracks = tracks,
		CurrentKey = nil,
		CurrentState = nil,
	}
	self.EntityAnimationRuntimes[entity] = runtime
	return runtime
end

function EntityService:_resolveEntityAnimationTrack(runtime, stateName)
	if not runtime or not runtime.Tracks then
		return nil, nil
	end

	for _, key in ipairs(_getEntityAnimationKeysForState(stateName)) do
		local track = runtime.Tracks[string.lower(key)]
		if track then
			return key, track
		end
	end

	return nil, nil
end

function EntityService:_updateEntityAnimation(entity)
	local runtime = self:_ensureEntityAnimationRuntime(entity)
	if not runtime then
		return
	end

	local stateName = entity:GetState()
	local desiredKey, desiredTrack = self:_resolveEntityAnimationTrack(runtime, stateName)
	local stateChanged = runtime.CurrentState ~= stateName
	runtime.CurrentState = stateName

	if runtime.CurrentKey == desiredKey and desiredTrack and desiredTrack.IsPlaying and not stateChanged then
		return
	end

	for _, track in pairs(runtime.Tracks) do
		if track ~= desiredTrack then
			pcall(function()
				track:Stop(ENTITY_ANIMATION_BLEND_TIME)
			end)
		end
	end

	runtime.CurrentKey = desiredKey
	if desiredTrack then
		desiredTrack.Looped = not (stateName == ENTITY_STATE.AttackWindup
			or stateName == ENTITY_STATE.AttackRecovery
			or stateName == ENTITY_STATE.Dead)
		pcall(function()
			desiredTrack:Play(ENTITY_ANIMATION_BLEND_TIME)
		end)
	end
end

function EntityService:_resolvePatrolPointRoot()
	if self.PatrolPointRoot and self.PatrolPointRoot.Parent then
		return self.PatrolPointRoot
	end

	self.PatrolPointRoot = Workspace:FindFirstChild(PATROL_POINT_ROOT_NAME)
	return self.PatrolPointRoot
end

function EntityService:_getPatrolPoints()
	local root = self:_resolvePatrolPointRoot()
	if not root then
		return {}
	end

	local points = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		local position = nil
		if descendant:IsA("BasePart") then
			position = descendant.Position
		elseif descendant:IsA("Attachment") and descendant.Parent and descendant.Parent:IsA("BasePart") then
			position = descendant.WorldPosition
		end

		if position then
			table.insert(points, {
				Id = tostring(descendant:GetAttribute("Id") or descendant:GetFullName()),
				Name = descendant.Name,
				Position = position,
				Weight = math.max(0.01, tonumber(descendant:GetAttribute("Weight")) or tonumber(descendant:GetAttribute("Urgency")) or 1),
			})
		end
	end

	return points
end

function EntityService:_collectNavigationSampleParts(folder)
	local samples = {}
	if not folder then
		return samples
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(samples, {
				CFrame = descendant.CFrame,
				Size = descendant.Size,
				Name = descendant.Name,
			})
		end
	end

	return samples
end

function EntityService:_getPreferredEntityRootPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local fallbackPart = model:FindFirstChildWhichIsA("BasePart")
	if fallbackPart then
		return fallbackPart
	end

	return nil
end

function EntityService:_normalizeEntityModelRoot(model)
	local preferredRootPart = self:_getPreferredEntityRootPart(model)
	if not preferredRootPart then
		return nil
	end

	if model.PrimaryPart ~= preferredRootPart then
		model.PrimaryPart = preferredRootPart
	end

	return preferredRootPart
end

function EntityService:_ensureEntityCollisionHull(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local rootPart = self:_getPreferredEntityRootPart(model)
	if not rootPart then
		return nil
	end

	local existingHull = model:FindFirstChild("CollisionHull")
	if existingHull and existingHull:IsA("BasePart") then
		local weld = existingHull:FindFirstChild("CollisionHullWeld")
		if not weld then
			weld = Instance.new("WeldConstraint")
			weld.Name = "CollisionHullWeld"
			weld.Part0 = rootPart
			weld.Part1 = existingHull
			weld.Parent = existingHull
		end
		return existingHull
	end

	local extents = model:GetExtentsSize()
	local hullDiameter = math.max(2.75, math.min(4.5, math.max(extents.X, extents.Z) * 0.9))
	local hullHeight = math.max(4.5, math.min(7, extents.Y * 0.85))

	local hull = Instance.new("Part")
	hull.Name = "CollisionHull"
	hull.Shape = Enum.PartType.Cylinder
	hull.Size = Vector3.new(hullHeight, hullDiameter, hullDiameter)
	hull.Transparency = 1
	hull.CastShadow = false
	hull.Anchored = false
	hull.CanCollide = true
	hull.CanTouch = false
	hull.CanQuery = false
	hull.Massless = false
	hull.Material = Enum.Material.SmoothPlastic
	hull.CFrame = rootPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
	hull.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CollisionHullWeld"
	weld.Part0 = rootPart
	weld.Part1 = hull
	weld.Parent = hull

	return hull
end

function EntityService:_refreshNavigationSampleCache()
	self.NavigationSampleCache = {}
	if not self.NavigationSampleRoot or not self.NavigationSampleRoot.Parent then
		return
	end

	for _, folder in ipairs(self.NavigationSampleRoot:GetChildren()) do
		if folder:IsA("Folder") then
			self.NavigationSampleCache[folder.Name] = self:_collectNavigationSampleParts(folder)
		end
	end
end

function EntityService:_bindNavigationSampleRoot()
	self.NavigationSampleRoot = self:_resolveNavigationSampleRoot()
	self:_refreshNavigationSampleCache()
	if not self.NavigationSampleRoot then
		return
	end

	self.NavigationSampleRoot.ChildAdded:Connect(function()
		self:_refreshNavigationSampleCache()
	end)
	self.NavigationSampleRoot.ChildRemoved:Connect(function()
		self:_refreshNavigationSampleCache()
	end)
	self.NavigationSampleRoot.DescendantAdded:Connect(function()
		self:_refreshNavigationSampleCache()
	end)
	self.NavigationSampleRoot.DescendantRemoving:Connect(function()
		self:_refreshNavigationSampleCache()
	end)
end

function EntityService:_getNavigationSampleKeysForEntity(entity)
	local keys = {}
	local seen = {}

	local function push(value)
		if type(value) ~= "string" or value == "" or seen[value] then
			return
		end
		seen[value] = true
		table.insert(keys, value)
	end

	push(entity.Id)
	push(entity.TemplateName)
	push(entity.DisplayName)
	push(entity.Model and entity.Model.Name or nil)
	push(entity.Model and entity.Model:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute) or nil)
	push("Default")

	return keys
end

function EntityService:_getNavigationSamplesForEntity(entity)
	if not self.NavigationSampleRoot then
		return nil
	end

	for _, key in ipairs(self:_getNavigationSampleKeysForEntity(entity)) do
		local samples = self.NavigationSampleCache[key]
		if samples and #samples > 0 then
			return samples
		end
	end

	return nil
end

function EntityService:_sampleNavigationDestination(entity)
	local samples = self:_getNavigationSamplesForEntity(entity)
	if not samples or #samples <= 0 then
		return nil
	end

	local sample = samples[entity.Random:NextInteger(1, #samples)]
	if not sample or typeof(sample.CFrame) ~= "CFrame" or typeof(sample.Size) ~= "Vector3" then
		return nil
	end

	local localOffsetY = sample.Size.Y * 0.5
	if entity and ((entity.HoverHeight or 0) > 0 or entity.SearchMode) then
		localOffsetY = entity.Random:NextNumber(-sample.Size.Y * 0.5, sample.Size.Y * 0.5)
	end

	local localOffset = Vector3.new(
		entity.Random:NextNumber(-sample.Size.X * 0.5, sample.Size.X * 0.5),
		localOffsetY,
		entity.Random:NextNumber(-sample.Size.Z * 0.5, sample.Size.Z * 0.5)
	)
	local destination = sample.CFrame:PointToWorldSpace(localOffset)
	return self:_clampPositionToMapBounds(destination)
end

function EntityService:_registerExistingTemplates()
	for _, model in ipairs(self.TemplateSourceFolder:GetChildren()) do
		if model:IsA("Model") and self:_normalizeEntityModelRoot(model) then
			local definition = EntityDefinitions[model.Name]
			self:_cacheEntityTemplate(model, definition)
		end
	end
end

function EntityService:_registerExistingEntities()
	for _,model in ipairs(self.EntitiesFolder:GetChildren()) do
		if model:IsA("Model") and self:_normalizeEntityModelRoot(model) then
			self:_registerEntityModel(model)
		end
	end
end

function EntityService:_cacheEntityTemplate(model, definition)
	self:_normalizeEntityModelRoot(model)
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
	self:_normalizeEntityModelRoot(model)
	local definition = EntityDefinitions[model.Name] or EntityDefinitions[(runtimeData and runtimeData.EntityId) or model.Name]
	local entity = BaseEntity.new(model, definition, self.Services, runtimeData)

	self:_cacheEntityTemplate(model, definition)
	self:_enforceServerNetworkOwnership(model)
	table.insert(self.Entities, entity)
	self:_syncDebugAttributes(entity)
	self:_createEntityPresentationState(entity)
	self:_syncEntityPresentationState(entity)
	self:_updateEntityAnimation(entity)

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
		self:_updateProjectiles(self.UpdateInterval)

		for index = #self.Entities, 1, -1 do
			local entity = self.Entities[index]
			if entity.IsReadyToDespawn and entity:IsReadyToDespawn() then
				self:_despawnEntity(entity, entity:GetPendingDespawnReason() or "DeferredDespawn")
			elseif entity:HasExpired() then
				self:_despawnEntity(entity, "Expired")
			elseif entity.IsActive then
				local ok, err = pcall(self._updateEntity, self, entity, self.UpdateInterval)
				if not ok then
					warn(string.format("[EntityService] Fatal entity update error for %s: %s", tostring(entity.DisplayName or entity.Id or "Unknown"), tostring(err)))
					self:_despawnEntity(entity, "RuntimeError")
				end
			end
		end

		task.wait(self.UpdateInterval)
	end
end

function EntityService:_updateEntity(entity, deltaTime)
	entity:ClearExpiredMemory()
	entity:ClearExpiredInvestigatedStimuli()
	entity:UpdateActiveEffects()
	if entity:IsIntentExpired() then
		entity:ClearIntent()
	end

	if not self.RoundManager or not self.RoundManager:IsReceptionActive() then
		self:_stopEntityMovementTracker(entity)
		entity:SetTarget(nil)
		entity:ClearIntent()
		entity:ClearPatrolDestination()
		if entity.SearchMode and entity.EndSearchMode then
			entity:EndSearchMode()
		end
		if entity.StopMovement then
			entity:StopMovement()
		end
		if entity.CancelCast and entity:IsCasting() then
			entity:CancelCast()
		end
		if entity.CancelBasicAttack and entity.IsBasicAttacking and entity:IsBasicAttacking() then
			entity:CancelBasicAttack()
			self:_clearBasicAttackDebugVisual(entity)
		end
		entity:EnterState(ENTITY_STATE.Patrol)

		self:_syncDebugAttributes(entity)
		self:_syncEntityPresentationState(entity)
		self:_updateEntityAnimation(entity)
		return
	end

	local currentState = entity:GetState()
	local bestCandidate = nil
	if currentState == ENTITY_STATE.Patrol then
		bestCandidate = self:_selectNearestActiveRemnantCandidate(entity, {
			RequireDirectSight = true,
		})
	elseif currentState == ENTITY_STATE.Scout then
		bestCandidate = self:_selectNearestActiveRemnantCandidate(entity, {
			RequireDirectSight = true,
			PreferCurrentTarget = true,
			PreferredPlayer = entity:GetTarget(),
		})
	else
		local currentTarget = entity:GetTarget()
		bestCandidate = currentTarget and self:_buildActiveRemnantCandidate(entity, currentTarget, {}) or nil
		if not bestCandidate then
			bestCandidate = self:_selectNearestActiveRemnantCandidate(entity, {
				RequireDirectSight = true,
			})
		end
	end
	local stateContext = {
		TargetPlayer = bestCandidate and bestCandidate.Player or nil,
		TargetPosition = bestCandidate and bestCandidate.Position or nil,
		HasDirectSight = bestCandidate and bestCandidate.HasDirectSight == true or false,
		HasVisibleSight = bestCandidate and bestCandidate.IsVisible == true or false,
		HasMovementLane = bestCandidate and bestCandidate.HasMovementLane == true or false,
		TargetDistance = bestCandidate and bestCandidate.Distance or nil,
		IntentDuration = self.UpdateInterval + 0.1,
		IntentReason = "ActiveRemnant",
	}
	if bestCandidate then
		entity:SetTarget(bestCandidate.Player, bestCandidate.Position, bestCandidate.IsVisible == true, bestCandidate.Velocity)
		if bestCandidate.IsVisible == true then
			entity:SetCurrentSearchCenter(bestCandidate.Position)
		end
	elseif currentState == ENTITY_STATE.Patrol then
		entity:SetTarget(nil)
	end

	self:_syncEntityStatusState(entity, stateContext)
	self:_updateEntityCast(entity)
	local stateBeforeUpdate = entity:GetState()
	entity:UpdateStateMachine(stateContext)
	local stateAfterUpdate = entity:GetState()
	local restartedMovementState = (stateAfterUpdate == ENTITY_STATE.Chase
		and (stateBeforeUpdate == ENTITY_STATE.Patrol or stateBeforeUpdate == ENTITY_STATE.Scout))
		or (stateAfterUpdate == ENTITY_STATE.Scout and stateBeforeUpdate == ENTITY_STATE.Chase)
		or (stateAfterUpdate == ENTITY_STATE.Patrol and stateBeforeUpdate == ENTITY_STATE.Chase)
	if restartedMovementState then
		self:_stopEntityMovementTracker(entity)
	end
	local abilityCandidates = bestCandidate and { bestCandidate } or {}
	if entity:GetState() == ENTITY_STATE.Chase and not entity:IsCasting() and not entity:GetActiveSpecialMovement() then
		self:_tryUseAbility(entity, abilityCandidates)
	end
	self:_updateEntityBasicAttack(entity)
	if entity:GetState() == ENTITY_STATE.Chase and self:_shouldBeginBasicAttack(entity, bestCandidate) then
		self:_beginEntityBasicAttack(entity, bestCandidate)
	end
	self:_updateEntityMovement(entity)

	self:_syncDebugAttributes(entity)
	self:_syncEntityPresentationState(entity)
	self:_updateEntityAnimation(entity)
end

function EntityService:_allocateEntityRuntimeId()
	self.NextEntityRuntimeId += 1
	return string.format("EntityRuntime_%04d", self.NextEntityRuntimeId)
end

function EntityService:_enforceServerNetworkOwnership(model)
	if not model or not model:IsA("Model") then
		return
	end

	local hasHumanoid = model:FindFirstChildOfClass("Humanoid") ~= nil
	local humanoidRootPart = hasHumanoid and model:FindFirstChild("HumanoidRootPart") or nil
	local collisionHull = hasHumanoid and self:_ensureEntityCollisionHull(model) or nil
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if not hasHumanoid then
				descendant.CanCollide = false
				descendant.CanTouch = false
			else
				descendant.Anchored = false
				descendant.CanTouch = false

				if descendant == collisionHull then
					descendant.CanCollide = true
					descendant.CanQuery = false
					descendant.Massless = false
					descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 1, 1)
				elseif descendant == humanoidRootPart then
					descendant.CanCollide = false
					descendant.Massless = false
					descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 1, 1)
				else
					descendant.CanCollide = false
					descendant.Massless = true
					descendant.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
				end
			end
		end
	end

	self:_setModelNetworkOwner(model, nil)
end

function EntityService:_setModelNetworkOwner(model, player)
	if not model or not model:IsA("Model") then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(player)
			end)
		end
	end
end

function EntityService:_createEntityPresentationState(entity)
	if not entity or not entity.Model then
		return nil
	end

	local runtimeId = entity.Model:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute)
	if type(runtimeId) ~= "string" or runtimeId == "" then
		runtimeId = self:_allocateEntityRuntimeId()
		entity.Model:SetAttribute(EntityPresentationConstants.RuntimeIdAttribute, runtimeId)
	end

	local stateFolder = self.EntityPresentationStates[entity]
	if stateFolder and stateFolder.Parent then
		return stateFolder
	end

	stateFolder = self.EntityPresentationFolder:FindFirstChild(runtimeId)
	if not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = runtimeId
		stateFolder.Parent = self.EntityPresentationFolder
	end

	local boundsSize = Vector3.zero
	if entity.Model and entity.Model.Parent then
		local ok, result = pcall(function()
			return entity.Model:GetExtentsSize()
		end)
		if ok and typeof(result) == "Vector3" then
			boundsSize = result
		end
	end

	stateFolder:SetAttribute(EntityPresentationConstants.RuntimeIdAttribute, runtimeId)
	stateFolder:SetAttribute(EntityPresentationConstants.EntityIdAttribute, entity.Id)
	stateFolder:SetAttribute(EntityPresentationConstants.DisplayNameAttribute, entity.DisplayName)
	stateFolder:SetAttribute(EntityPresentationConstants.TemplateNameAttribute, entity.TemplateName or entity.Id)
	stateFolder:SetAttribute(EntityPresentationConstants.AuthoritativeModelNameAttribute, entity.Model.Name)
	stateFolder:SetAttribute(EntityPresentationConstants.BoundsSizeAttribute, boundsSize)

	self.EntityPresentationStates[entity] = stateFolder
	return stateFolder
end

function EntityService:_syncEntityPresentationState(entity)
	local stateFolder = self:_createEntityPresentationState(entity)
	if not stateFolder or not entity then
		return
	end

	local rootPart = entity.RootPart
	local rootCFrame = rootPart and rootPart.CFrame or nil
	local position = rootCFrame and rootCFrame.Position or nil
	local lookVector = rootCFrame and rootCFrame.LookVector or nil
	local moveTarget = entity:GetIntentTargetPosition()
	local intentName = entity:GetIntentName()

	if rootCFrame then
		stateFolder:SetAttribute(EntityPresentationConstants.CFrameAttribute, rootCFrame)
		stateFolder:SetAttribute(EntityPresentationConstants.PositionAttribute, position)
		stateFolder:SetAttribute(EntityPresentationConstants.LookVectorAttribute, lookVector)
	end

	stateFolder:SetAttribute(EntityPresentationConstants.StateAttribute, entity:GetState())
	stateFolder:SetAttribute(EntityPresentationConstants.IntentAttribute, intentName or "")
	stateFolder:SetAttribute(EntityPresentationConstants.MoveTargetAttribute, typeof(moveTarget) == "Vector3" and moveTarget or nil)
	stateFolder:SetAttribute(EntityPresentationConstants.HealthAttribute, math.floor((entity.Health or 0) + 0.5))
	stateFolder:SetAttribute(EntityPresentationConstants.MaxHealthAttribute, math.floor((entity.MaxHealth or 0) + 0.5))
	stateFolder:SetAttribute(EntityPresentationConstants.IsActiveAttribute, entity.IsActive == true)
	stateFolder:SetAttribute(EntityPresentationConstants.IsDeadAttribute, entity.IsDead and entity:IsDead() or false)
	stateFolder:SetAttribute(EntityPresentationConstants.UpdatedAtAttribute, Workspace:GetServerTimeNow())
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

		local context = self:_createEffectContext(entity, entity:GetTarget(), nil, deltaTime, passive)
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
	local castContext = self:_buildAbilityCastContext(entity, abilityId, ability, targetPlayer)
	self:_playEntityAbilityCastVisual(entity, abilityId, targetPlayer, castContext)
	entity:BeginCast(abilityId, ability, targetPlayer, castContext)
	entity:SetCooldown(abilityId, ability.Cooldown or 0)

	DebugLog:Log("Entity", string.format("[EntityService] %s began %s", entity.DisplayName, abilityId))
	self:_markLastAbility(entity, abilityId)
end

function EntityService:_buildAbilityCastContext(entity, _abilityId, _ability, targetPlayer)
	local castContext = {}
	local entityPosition = entity and entity:GetPosition()
	if entityPosition then
		castContext.EntityPosition = entityPosition
	end

	local targetCharacter = targetPlayer and self.CharacterService:GetCharacterByPlayer(targetPlayer)
	if targetCharacter and targetCharacter.RootPart then
		castContext.TargetPosition = targetCharacter.RootPart.Position
		castContext.TargetCFrame = targetCharacter.RootPart.CFrame
	end

	return castContext
end

function EntityService:_syncEntityStatusState(entity, stateContext)
	if not entity or not self.StatusEffectService then
		return
	end

	local isStunned = self.StatusEffectService:HasFlag(entity, "Stunned") == true
	local currentState = entity:GetState()
	if currentState == ENTITY_STATE.Pinned then
		return
	end

	if isStunned then
		if entity:IsCasting() then
			entity:CancelCast()
		end
		if entity.GetActiveSpecialMovement and entity:GetActiveSpecialMovement() and entity.CancelSpecialMovement then
			entity:CancelSpecialMovement()
		end
		if currentState ~= ENTITY_STATE.Stunned then
			entity:EnterState(ENTITY_STATE.Stunned, stateContext)
		end
	elseif currentState == ENTITY_STATE.Stunned then
		entity:EnterState(stateContext.TargetPlayer and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, stateContext)
	end
end

function EntityService:_updateEntityCast(entity)
	local activeCast = entity and entity.GetActiveCast and entity:GetActiveCast() or nil
	if not activeCast then
		return
	end

	if os.clock() < (activeCast.EndsAt or 0) then
		return
	end

	local resolvedCast = entity:CompleteCast()
	if not resolvedCast then
		return
	end

	self:_resolveAbility(entity, resolvedCast.Definition, resolvedCast.TargetPlayer, resolvedCast.Context)
	if entity:GetState() == ENTITY_STATE.Casting and not entity:GetActiveSpecialMovement() and not (self.StruggleService and self.StruggleService:IsEntityStruggling(entity)) then
		entity:EnterState(entity:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = entity:GetTarget(),
			TargetPosition = entity:GetTargetLastKnownPosition(),
			HasDirectSight = false,
		})
	end
	self:_syncDebugAttributes(entity)
end

function EntityService:_selectAbility(entity, candidates)
	local abilities = entity:GetAbilityDefinitions()
	local available = {}

	for abilityId, ability in pairs(abilities) do
		if entity:CanUseAbility(abilityId) and self:_canUseAbility(entity, ability, candidates) then
			table.insert(available, {
				Id = abilityId,
				Ability = ability,
				Weight = self:_scoreAbilitySelection(entity, abilityId, ability, candidates),
			})
		end
	end

	if #available == 0 then
		return nil, nil
	end

	return self:_pickWeightedAbility(entity, available)
end

function EntityService:_canUseAbility(entity, ability, candidates)
	return EntityAbilityRules.CanUseAbility(self, entity, ability, candidates)
end

function EntityService:_scoreAbilitySelection(entity, abilityId, ability, candidates)
	return EntityAbilityRules.ScoreAbilitySelection(self, entity, abilityId, ability, candidates)
end

function EntityService:_abilityStartsStruggle(ability)
	return EntityAbilityRules.AbilityStartsStruggle(self, ability)
end

function EntityService:_pickWeightedAbility(entity, available)
	table.sort(available, function(a, b)
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
	return EntityAbilityRules.SelectAbilityTarget(self, entity, ability, candidates)
end

function EntityService:_resolveAbility(entity, ability, targetPlayer, castData)
	local context = self:_createEffectContext(entity, targetPlayer, nil, nil, ability, castData)
	self:_executeEffectSteps(entity, ability, context)
	self:_playEntityAbilityResolveVisual(entity, ability.Id, targetPlayer, castData)

	DebugLog:Log("Entity", string.format("[EntityService] %s resolved %s", entity.DisplayName, ability.Id or "Ability"))
	self:_syncDebugAttributes(entity)
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

function EntityService:_samplePatrolPointDestination(entity)
	local patrolPoints = self:_getPatrolPoints()
	if not patrolPoints or #patrolPoints <= 0 then
		return nil
	end

	local weightedCandidates = {}
	local totalWeight = 0
	for _, patrolPoint in ipairs(patrolPoints) do
		if not entity:HasRecentlyVisitedPatrolPoint(patrolPoint.Id) then
			local weight = math.max(0.01, patrolPoint.Weight or 1)
			totalWeight += weight
			table.insert(weightedCandidates, {
				Point = patrolPoint,
				CumulativeWeight = totalWeight,
			})
		end
	end

	if #weightedCandidates <= 0 then
		for _, patrolPoint in ipairs(patrolPoints) do
			local weight = math.max(0.01, patrolPoint.Weight or 1)
			totalWeight += weight
			table.insert(weightedCandidates, {
				Point = patrolPoint,
				CumulativeWeight = totalWeight,
			})
		end
	end

	if #weightedCandidates <= 0 then
		return nil
	end

	local roll = entity.Random:NextNumber(0, totalWeight)
	local selectedPoint = weightedCandidates[#weightedCandidates].Point
	for _, candidate in ipairs(weightedCandidates) do
		if roll <= candidate.CumulativeWeight then
			selectedPoint = candidate.Point
			break
		end
	end

	local offsetRadius = math.max(0, entity.PatrolPointRandomOffset or 0)
	local offset = Vector3.zero
	if offsetRadius > 0 then
		local angle = entity.Random:NextNumber(0, math.pi * 2)
		local distance = entity.Random:NextNumber(0, offsetRadius)
		offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	end

	return {
		Position = self:_clampPositionToMapBounds(selectedPoint.Position + offset),
		Reason = "PatrolPOI",
		PointId = selectedPoint.Id,
	}
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
		local patrolSelection = self:_samplePatrolPointDestination(entity)
		if patrolSelection and patrolSelection.Position then
			entity:SetPatrolDestination(patrolSelection.Position, patrolSelection.Reason, patrolSelection.PointId)
			if self:_isNavigationDestinationReachable(entity, patrolSelection.Position) then
				return patrolSelection.Position
			end
		end
	end

	for _ = 1, 8 do
		local destination = self:_sampleNavigationDestination(entity)
		if destination then
			entity:SetPatrolDestination(destination, "Patrol")
			if self:_isNavigationDestinationReachable(entity, destination) then
				return destination
			end
		end
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

function EntityService:_pickScoutDestination(entity)
	local searchCenter = entity:GetCurrentSearchCenter() or entity:GetTargetLastKnownPosition() or entity.ScoutOrigin
	if typeof(searchCenter) ~= "Vector3" then
		return nil
	end

	if entity.ScoutSearchResolved ~= true and not entity:IsNearPosition(searchCenter, entity:GetStopDistance() + 1) then
		return {
			Position = self:_clampPositionToMapBounds(searchCenter),
			Reason = "Search",
		}
	end

	if (entity.ScoutPointsRemaining or 0) <= 0 then
		return nil
	end

	local origin = entity.ScoutOrigin or searchCenter
	local totalPoints = math.max(1, entity.ScoutPointCount or 1)
	local sweepIndex = math.clamp((entity.ScoutSweepIndex or 0) + 1, 1, totalPoints)
	local minDistance = math.max(0, entity.ScoutPointMinDistance or 3)
	local maxDistance = math.max(minDistance, entity.ScoutPointRadius or 8)
	local distanceAlpha = totalPoints <= 1 and 1 or ((sweepIndex - 1) / math.max(1, totalPoints - 1))
	local distance = minDistance + ((maxDistance - minDistance) * distanceAlpha)
	local baseAngle = entity.ScoutSweepBaseAngle or entity:GetScoutSweepBaseAngle(origin)
	local sweepAngle = math.rad(entity.ScoutSweepAngleDegrees or 75)
	local angleOffsets = {
		0,
		sweepAngle,
		-sweepAngle,
		sweepAngle * 2,
		-sweepAngle * 2,
	}
	local preferredOffsetIndex = math.clamp(sweepIndex, 1, #angleOffsets)

	for attempt = 0, (#angleOffsets - 1) do
		local offsetIndex = ((preferredOffsetIndex + attempt - 1) % #angleOffsets) + 1
		local angle = baseAngle + angleOffsets[offsetIndex]
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		candidate = self:_clampPositionToMapBounds(candidate)
		if entity:IsNearPosition(candidate, entity:GetStopDistance() + 1) then
			continue
		end
		if self:_isNavigationDestinationReachable(entity, candidate) then
			entity.ScoutSweepIndex = sweepIndex
			entity.ScoutPointsRemaining = math.max(0, (entity.ScoutPointsRemaining or 0) - 1)
			return {
				Position = candidate,
				Reason = "SearchSweep",
			}
		end
	end

	entity.ScoutPointsRemaining = 0
	return nil
end

function EntityService:_hasMovementLaneToCharacter(entity, character)
	if not entity or not entity.RootPart or not character or not character.RootPart then
		return false
	end

	local origin = entity.RootPart.Position + Vector3.new(0, 1.1, 0)
	local targetRoot = character.RootPart
	local targetPositions = {
		targetRoot.Position + Vector3.new(0, 0.8, 0),
		targetRoot.Position + Vector3.new(0, 1.6, 0),
	}

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	for _, targetPosition in ipairs(targetPositions) do
		local direction = targetPosition - origin
		if direction.Magnitude <= 0.01 then
			return true
		end

		local result = Workspace:Raycast(origin, direction, raycastParams)
		if not result or result.Instance:IsDescendantOf(character.Model) then
			return true
		end
	end

	return false
end

function EntityService:_buildActiveRemnantCandidate(entity, player, options)
	options = options or {}

	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	local entityPosition = entity and entity:GetPosition()
	if not roundManager or not characterService or not entityPosition or not player then
		return nil
	end

	local roundState = roundManager:GetRoundState(player)
	local character = characterService:GetCharacterByPlayer(player)
	if not (roundState and roundState.IsAlive and self:_isCharacterEntityTargetable(character)) then
		return nil
	end

	local position = character.RootPart.Position
	local distance = (position - entityPosition).Magnitude
	local isVisible = self:_hasLineOfSight(entity, character)
	local hasMovementLane = self:_hasMovementLaneToCharacter(entity, character)
	local isDetected = distance <= entity:GetDetectionRange()
	local hasDirectSight = self:_hasDirectSight(entity, character, distance, isVisible)
	if options.RequireDirectSight == true and not hasDirectSight then
		return nil
	end

	return {
		Player = player,
		Character = character,
		Position = position,
		Velocity = character.RootPart.AssemblyLinearVelocity,
		Distance = distance,
		IsVisible = isVisible,
		HasMovementLane = hasMovementLane,
		IsDetected = isDetected,
		HasDirectSight = hasDirectSight,
		Memory = nil,
		Score = math.huge,
	}
end

function EntityService:_isCharacterEntityTargetable(character)
	return character
		and character.RootPart
		and character:IsAlive()
		and (not character.CanBeEntityTargeted or character:CanBeEntityTargeted())
end

function EntityService:_selectNearestActiveRemnantCandidate(entity, options)
	options = options or {}
	local roundManager = self.RoundManager
	local entityPosition = entity and entity:GetPosition()
	if not roundManager or not entityPosition then
		return nil
	end

	if options.PreferCurrentTarget == true and options.PreferredPlayer then
		local preferredCandidate = self:_buildActiveRemnantCandidate(entity, options.PreferredPlayer, options)
		if preferredCandidate then
			return preferredCandidate
		end
	end

	local bestCandidate = nil
	local bestDistance = math.huge
	for _, player in ipairs(roundManager:GetActivePlayers()) do
		if player ~= options.PreferredPlayer then
			local candidate = self:_buildActiveRemnantCandidate(entity, player, options)
			if candidate and candidate.Distance < bestDistance then
				bestDistance = candidate.Distance
				bestCandidate = candidate
			end
		end
	end

	return bestCandidate
end

function EntityService:_getNearestActiveRemnantPosition(entity)
	local candidate = self:_selectNearestActiveRemnantCandidate(entity)
	return candidate and candidate.Position or nil
end

function EntityService:_getLostSightChaseGoal(entity)
	local lastKnownPosition = entity:GetTargetLastKnownPosition()
		or entity:GetIntentTargetPosition()
		or entity:GetCurrentSearchCenter()
	if typeof(lastKnownPosition) ~= "Vector3" then
		return nil
	end

	local predictedSearchCenter = entity.GetPredictedScoutSearchCenter and entity:GetPredictedScoutSearchCenter(lastKnownPosition) or nil
	return typeof(predictedSearchCenter) == "Vector3" and predictedSearchCenter or lastKnownPosition
end

function EntityService:_createMovementTrackerResolver(entity)
	return function()
		if not entity or not entity.IsActive or (entity.IsDead and entity:IsDead()) then
			return nil
		end

		local currentState = entity:GetState()
		if currentState == ENTITY_STATE.Patrol or currentState == ENTITY_STATE.Scout then
			return entity:GetPatrolDestination()
		end

		local targetPlayer = entity:GetTarget()
		local candidate = targetPlayer and self:_buildActiveRemnantCandidate(entity, targetPlayer, {
			PreferCurrentTarget = true,
			PreferredPlayer = targetPlayer,
		}) or nil
		if not candidate then
			return nil
		end

		if currentState == ENTITY_STATE.Chase and candidate.IsVisible ~= true then
			return self:_getLostSightChaseGoal(entity)
		end

		if currentState == ENTITY_STATE.Chase and candidate.IsVisible == true and candidate.HasMovementLane ~= true then
			local aroundObstaclePosition = self:_findAroundObstaclePoint(entity, candidate.Position)
			if typeof(aroundObstaclePosition) == "Vector3" then
				return aroundObstaclePosition
			end

			local projectedVisibleInterest = self:_projectTowardVisibleInterest(entity:GetPosition(), candidate.Position)
			if typeof(projectedVisibleInterest) == "Vector3" then
				return projectedVisibleInterest
			end
		end

		local character = candidate.Character
		if character and character.RootPart then
			return character.RootPart
		end

		return candidate.Position
	end
end

function EntityService:_ensureEntityMovementTracker(entity)
	if not entity or not entity.Model or not entity.Humanoid or not entity.RootPart then
		return nil
	end

	local tracker = self.EntityMovementTrackers[entity]
	if tracker then
		return tracker
	end

	tracker = MovingTargetPathTracker.new(entity.Model, self:_createMovementTrackerResolver(entity), {
		RecomputeInterval = entity.PathRecomputeInterval or self.UpdateInterval,
		AgentRadius = entity.AgentRadius,
		AgentHeight = entity.AgentHeight,
		AgentCanJump = entity.AgentCanJump,
		WaypointSpacing = entity.AgentWaypointSpacing,
		WaypointReachedDistance = entity.PathWaypointTolerance,
		CanDirectChase = function()
			return entity:GetState() == ENTITY_STATE.Chase
		end,
		CanCommitGoal = function()
			if entity:GetState() == ENTITY_STATE.Scout then
				return false
			end

			if entity:GetState() == ENTITY_STATE.Chase then
				local targetPlayer = entity:GetTarget()
				if targetPlayer then
					local candidate = self:_buildActiveRemnantCandidate(entity, targetPlayer, {
						PreferCurrentTarget = true,
						PreferredPlayer = targetPlayer,
					})
					if candidate and candidate.IsVisible ~= true then
						return false
					end
				end
			end

			return true
		end,
	})
	self.EntityMovementTrackers[entity] = tracker
	tracker:Start()
	return tracker
end

function EntityService:_getEntityMotionPart(entity)
	if not entity or not entity.Model then
		return entity and entity.RootPart or nil
	end

	local collisionHull = entity.Model:FindFirstChild("CollisionHull")
	if collisionHull and collisionHull:IsA("BasePart") then
		return collisionHull
	end

	return entity.RootPart
end

function EntityService:_stopEntityMovementTracker(entity)
	local tracker = self.EntityMovementTrackers[entity]
	if tracker then
		tracker:Stop()
		self.EntityMovementTrackers[entity] = nil
	end

	if entity and entity.StopMovement then
		entity:StopMovement()
	end
end

function EntityService:_updateEntityMovement(entity)
	if not entity or not entity.IsActive or (entity.IsDead and entity:IsDead()) then
		self:_stopEntityMovementTracker(entity)
		return
	end

	local currentState = entity:GetState()
	local allowsTrackerMovement = currentState == ENTITY_STATE.Patrol
		or currentState == ENTITY_STATE.Scout
		or currentState == ENTITY_STATE.Chase
		or currentState == ENTITY_STATE.AttackWindup
		or currentState == ENTITY_STATE.AttackRecovery
	if not allowsTrackerMovement then
		self:_stopEntityMovementTracker(entity)
		return
	end

	if currentState == ENTITY_STATE.Patrol or currentState == ENTITY_STATE.Scout then
		if currentState == ENTITY_STATE.Scout and entity:IsPatrolLoitering() then
			if entity.ClearScoutArrival then
				entity:ClearScoutArrival()
			end
			entity.PatrolPauseUntil = 0
		elseif entity:IsPatrolLoitering() then
			if currentState == ENTITY_STATE.Scout and entity.UpdateScoutScan then
				entity:UpdateScoutScan()
			end
			self:_stopEntityMovementTracker(entity)
			return
		end

		local patrolDestination = entity:GetPatrolDestination()
		local movementTracker = self.EntityMovementTrackers and self.EntityMovementTrackers[entity] or nil
		local movementDebug = movementTracker and movementTracker.GetDebugSnapshot and movementTracker:GetDebugSnapshot() or nil
		local patrolDestinationReason = entity.GetPatrolDestinationReason and entity:GetPatrolDestinationReason() or nil
		local destinationAge = entity.GetPatrolDestinationAge and entity:GetPatrolDestinationAge() or 0
		local pathIsIdle = movementDebug and movementDebug.PathStatus ~= "Active"
		local pathHasError = movementDebug and movementDebug.LastPathError and movementDebug.LastPathError ~= ""
		if currentState == ENTITY_STATE.Scout and entity.UpdateScoutScan and (patrolDestination == nil or pathIsIdle) then
			entity:UpdateScoutScan()
		end
		local patrolDestinationStale = currentState == ENTITY_STATE.Patrol
			and patrolDestination
			and not entity:IsNearPosition(patrolDestination, entity:GetStopDistance() + 1)
			and (
				(pathIsIdle and destinationAge >= 0.35)
				or (pathHasError and destinationAge >= 0.2)
			)
		local scoutDestinationStale = currentState == ENTITY_STATE.Scout
			and patrolDestination
			and not entity:IsNearPosition(patrolDestination, entity:GetStopDistance() + 1)
			and (
				(pathIsIdle and destinationAge >= 0.2)
				or ((movementDebug and movementDebug.StuckAge or 0) >= math.max(0.35, (entity.ScoutSearchCommitDuration or 1.1) * 0.5))
			)
		if currentState == ENTITY_STATE.Scout
			and patrolDestination
			and patrolDestinationReason == "Search"
			and not entity:IsNearPosition(patrolDestination, entity:GetStopDistance() + 1)
		then
			if pathIsIdle or destinationAge >= (entity.ScoutSearchCommitDuration or 1.1) then
				entity.ScoutSearchResolved = true
				local scoutSelection = self:_pickScoutDestination(entity)
				if scoutSelection and scoutSelection.Position then
					entity:SetPatrolDestination(scoutSelection.Position, scoutSelection.Reason)
					patrolDestination = scoutSelection.Position
					if pathIsIdle then
						self:_stopEntityMovementTracker(entity)
						movementTracker = nil
						movementDebug = nil
					end
				else
					entity:ClearPatrolDestination()
					patrolDestination = nil
				end
			end
		end

		if patrolDestinationStale and patrolDestination ~= nil then
			entity:ClearPatrolDestination()
			self:_stopEntityMovementTracker(entity)
			patrolDestination = nil
			movementTracker = nil
			movementDebug = nil
		end

		if currentState == ENTITY_STATE.Scout
			and scoutDestinationStale
			and patrolDestination ~= nil
		then
			if patrolDestinationReason == "Search" then
				entity.ScoutSearchResolved = true
			end

			local scoutSelection = self:_pickScoutDestination(entity)
			if scoutSelection and scoutSelection.Position then
				entity:SetPatrolDestination(scoutSelection.Position, scoutSelection.Reason)
				patrolDestination = scoutSelection.Position
				self:_stopEntityMovementTracker(entity)
				movementTracker = nil
				movementDebug = nil
			else
				entity:ClearPatrolDestination()
				entity:EnterState(ENTITY_STATE.Patrol)
				self:_stopEntityMovementTracker(entity)
				return
			end
		end

		if patrolDestination and entity:IsNearPosition(patrolDestination, entity:GetStopDistance() + 0.75) then
			if currentState == ENTITY_STATE.Patrol then
				local patrolPointId = entity:GetPatrolDestinationPointId()
				if patrolPointId then
					entity:RememberPatrolPoint(patrolPointId)
				end
				entity:ClearPatrolDestination()
				entity:BeginPatrolLoiter()
			else
				entity.ScoutSearchResolved = true
				entity:ClearPatrolDestination()
				self:_stopEntityMovementTracker(entity)
				if entity.UpdateScoutScan then
					entity:UpdateScoutScan()
				end
				patrolDestination = nil
				movementTracker = nil
				movementDebug = nil
			end
			if currentState == ENTITY_STATE.Patrol then
				self:_stopEntityMovementTracker(entity)
				return
			end
		end

		if patrolDestination == nil then
			if currentState == ENTITY_STATE.Patrol then
				patrolDestination = self:_pickReachablePatrolDestination(entity)
			else
				local scoutSelection = self:_pickScoutDestination(entity)
				if scoutSelection and scoutSelection.Position then
					entity:SetPatrolDestination(scoutSelection.Position, scoutSelection.Reason)
					patrolDestination = scoutSelection.Position
				else
					entity:EnterState(ENTITY_STATE.Patrol)
					self:_stopEntityMovementTracker(entity)
					return
				end
			end
			if patrolDestination == nil then
				self:_stopEntityMovementTracker(entity)
				return
			end
		end
	end

	if currentState == ENTITY_STATE.Chase then
		local targetPlayer = entity:GetTarget()
		local candidate = targetPlayer and self:_buildActiveRemnantCandidate(entity, targetPlayer, {
			PreferCurrentTarget = true,
			PreferredPlayer = targetPlayer,
		}) or nil
		if candidate and candidate.IsVisible ~= true then
			local scoutAnchor = self:_getLostSightChaseGoal(entity)
			if typeof(scoutAnchor) == "Vector3"
				and (entity.GetChaseLostSightDuration and entity:GetChaseLostSightDuration() or 0) >= (entity.ChaseLostSightGraceDuration or 0)
				and entity:IsNearPosition(scoutAnchor, entity:GetStopDistance() + 0.75)
			then
				entity:EnterState(ENTITY_STATE.Scout, {
					TargetPlayer = targetPlayer,
					TargetPosition = scoutAnchor,
					HasDirectSight = false,
					HasVisibleSight = false,
					HasMovementLane = false,
				})
				self:_stopEntityMovementTracker(entity)
				return
			end
		end
	end

	local trackerTarget = self:_createMovementTrackerResolver(entity)()
	if trackerTarget == nil then
		self:_stopEntityMovementTracker(entity)
		return
	end

	local tracker = self:_ensureEntityMovementTracker(entity)
	if tracker then
		tracker.Target = self:_createMovementTrackerResolver(entity)
	end
end

function EntityService:_shouldBeginBasicAttack(entity, candidate)
	if not entity or not candidate or not entity:CanAttack() then
		return false
	end

	if entity.GetActionCooldown and entity:GetActionCooldown(BASIC_ATTACK_BLOCKED_COOLDOWN_KEY) > 0 then
		return false
	end

	local attackDefinition = entity:GetCurrentBasicAttackDefinition()
	if not attackDefinition then
		return false
	end

	local attackRange = attackDefinition.AttackRange or entity.AttackRange
	if type(candidate.Distance) ~= "number" or candidate.Distance > attackRange then
		return false
	end

	if not self:_passesBasicAttackAngleCheck(entity, candidate, attackDefinition) then
		return false
	end

	if not self:_passesBasicAttackPathSanity(entity, candidate, attackDefinition) then
		self:_markBlockedBasicAttack(entity, BASIC_ATTACK_PATH_RETRY_DURATION)
		return false
	end

	if entity.IgnoreLineOfSightForAttacks then
		return true
	end

	if not self:_hasClearBasicAttackLane(entity, candidate, attackDefinition) then
		self:_markBlockedBasicAttack(entity, BASIC_ATTACK_BLOCKED_RETRY_DURATION)
		return false
	end

	return true
end

function EntityService:_markBlockedBasicAttack(entity, duration)
	if not entity or not entity.SetCooldown then
		return
	end

	entity:SetCooldown(BASIC_ATTACK_BLOCKED_COOLDOWN_KEY, math.max(0, duration or BASIC_ATTACK_BLOCKED_RETRY_DURATION))
end

function EntityService:_passesBasicAttackAngleCheck(entity, candidate, attackDefinition)
	if not entity or not entity.RootPart or not candidate or typeof(candidate.Position) ~= "Vector3" then
		return false
	end

	local entityPosition = entity.RootPart.Position
	local offset = candidate.Position - entityPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	if planarOffset.Magnitude <= 0.05 then
		return true
	end

	local lookVector = entity.RootPart.CFrame.LookVector
	local planarLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if planarLook.Magnitude <= 0.01 then
		return true
	end

	local coneDegrees = math.clamp(attackDefinition.AttackConeDegrees or 90, 1, 179)
	local minimumDot = math.cos(math.rad(coneDegrees * 0.5))
	return planarLook.Unit:Dot(planarOffset.Unit) >= minimumDot
end

function EntityService:_hasClearBasicAttackLane(entity, candidate, attackDefinition)
	if not entity or not entity.RootPart or not candidate or not candidate.Character or not candidate.Character.RootPart then
		return false
	end

	local targetCharacter = candidate.Character
	local originBase = entity.RootPart.Position + Vector3.new(0, attackDefinition.AttackSightOriginHeight or 2.25, 0)
	local targetRoot = targetCharacter.RootPart
	local targetPositions = {
		targetRoot.Position + Vector3.new(0, attackDefinition.AttackSightTargetHeight or 2.0, 0),
		targetRoot.Position + Vector3.new(0, attackDefinition.AttackSightLowerTargetHeight or 1.0, 0),
	}

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	for _, targetPosition in ipairs(targetPositions) do
		local direction = targetPosition - originBase
		if direction.Magnitude <= 0.01 then
			return true
		end

		local result = Workspace:Raycast(originBase, direction, raycastParams)
		if not result or (result.Instance and result.Instance:IsDescendantOf(targetCharacter.Model)) then
			return true
		end
	end

	return false
end

function EntityService:_passesBasicAttackPathSanity(entity, candidate, attackDefinition)
	local tracker = self.EntityMovementTrackers and self.EntityMovementTrackers[entity] or nil
	if not tracker or not tracker.GetDebugSnapshot then
		return true
	end

	local movementDebug = tracker:GetDebugSnapshot()
	if not movementDebug then
		return true
	end

	if movementDebug.MoveMode == "Direct" then
		return true
	end

	local remainingPathDistance = movementDebug.RemainingPathDistance
	if typeof(remainingPathDistance) ~= "number" then
		return true
	end

	local attackRange = attackDefinition.AttackRange or entity.AttackRange or 0
	local maximumReachableAttackDistance = math.max(attackRange + 2.5, attackRange * 1.4)
	return remainingPathDistance <= maximumReachableAttackDistance
end

function EntityService:_beginEntityBasicAttack(entity, candidate)
	local attackDefinition = entity:GetCurrentBasicAttackDefinition()
	if not attackDefinition then
		return nil
	end

	local activeAttack = entity:BeginBasicAttack(candidate.Player, attackDefinition, {
		TargetPosition = candidate.Position,
		TargetDistance = candidate.Distance,
		HasDirectSight = candidate.HasDirectSight == true,
	})
	if not activeAttack then
		return nil
	end

	self:_markLastAbility(entity, activeAttack.Id)
	self:_startEntityBasicAttackActiveWindow(entity, activeAttack)
	self:_syncDebugAttributes(entity)
	return activeAttack
end

function EntityService:_getEntityDebugVisualFolder()
	if not DebugFlags.Enabled or not DebugFlags.Entity or Workspace:GetAttribute("DebugUiEnabled") == false then
		return nil
	end

	local visualsFolder = Workspace:FindFirstChild("EntityDebugVisuals")
	if not visualsFolder then
		visualsFolder = Instance.new("Folder")
		visualsFolder.Name = "EntityDebugVisuals"
		visualsFolder.Parent = Workspace
	end

	return visualsFolder
end

function EntityService:_clearBasicAttackDebugVisual(entity, persistDuration)
	local visual = self.EntityAttackDebugVisuals[entity]
	if not visual then
		return
	end

	self.EntityAttackDebugVisuals[entity] = nil
	local parts = visual.Parts or (visual.Part and { visual.Part }) or nil
	if not parts then
		return
	end

	for _, part in ipairs(parts) do
		if part then
			if persistDuration and persistDuration > 0 then
				Debris:AddItem(part, persistDuration)
			else
				part:Destroy()
			end
		end
	end
end

function EntityService:_updateBasicAttackDebugVisual(entity, samplePositions, sampleRadii, options)
	options = options or {}
	local visualsFolder = self:_getEntityDebugVisualFolder()
	if not visualsFolder or type(samplePositions) ~= "table" or type(sampleRadii) ~= "table" or #samplePositions <= 0 or #samplePositions ~= #sampleRadii then
		self:_clearBasicAttackDebugVisual(entity)
		return nil
	end

	local visual = self.EntityAttackDebugVisuals[entity]
	local parts = visual and visual.Parts or {}
	if not visual then
		visual = {
			Parts = parts,
		}
		self.EntityAttackDebugVisuals[entity] = visual
	end

	for index, position in ipairs(samplePositions) do
		local radius = sampleRadii[index]
		local part = parts[index]
		if not part or not part.Parent then
			part = Instance.new("Part")
			part.Name = string.format("%sBasicAttack_%d", entity.DisplayName or entity.Id or "Entity", index)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Shape = Enum.PartType.Ball
			part.Parent = visualsFolder
			parts[index] = part
		end

		part.Color = options.Color or Color3.fromRGB(255, 178, 92)
		part.Material = Enum.Material.Neon
		part.Transparency = options.Transparency ~= nil and options.Transparency or 0.45
		part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		part.CFrame = CFrame.new(position)
	end

	for index = #parts, #samplePositions + 1, -1 do
		local part = parts[index]
		if part then
			part:Destroy()
		end
		parts[index] = nil
	end

	return parts
end

function EntityService:_resolveEntityAttackFacingVector(entity, targetPlayer)
	local rootPart = entity and entity.RootPart
	if not rootPart then
		return nil
	end

	local facing = rootPart.CFrame.LookVector
	local targetCharacter = targetPlayer and self.CharacterService and self.CharacterService:GetCharacterByPlayer(targetPlayer)
	if targetCharacter and targetCharacter.RootPart then
		local offset = targetCharacter.RootPart.Position - rootPart.Position
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.05 then
			facing = planarOffset.Unit
		end
	end

	local planarFacing = Vector3.new(facing.X, 0, facing.Z)
	if planarFacing.Magnitude <= 0.01 then
		planarFacing = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end

	return planarFacing.Magnitude > 0.01 and planarFacing.Unit or Vector3.new(0, 0, -1)
end

function EntityService:_getEntityBasicAttackSampleData(entity, attackDefinition, targetPlayer)
	if not entity or not entity.RootPart or not attackDefinition then
		return nil, nil
	end

	local facing = self:_resolveEntityAttackFacingVector(entity, targetPlayer)
	local range = math.max(0.5, attackDefinition.AttackRange or entity.AttackRange or 6)
	local width = math.max(2, attackDefinition.HitboxWidth or math.clamp(range * 0.55, 4.5, 6.5))
	local forwardOffset = attackDefinition.HitboxForwardOffset or (range * 0.5)
	local height = math.max(2, attackDefinition.HitboxHeight or 5)
	local heightOffset = attackDefinition.HitboxHeightOffset or math.max(2, height * 0.5)
	local baseRadius = math.max(0.4, width * 0.1)
	local offsets = {
		math.max(1.2, forwardOffset * 0.45),
		math.max(2.1, forwardOffset * 0.72),
		math.max(3.0, forwardOffset),
	}
	local radii = {
		baseRadius,
		baseRadius * 1.2,
		baseRadius * 1.45,
	}
	local pivot = entity.RootPart.Position + Vector3.new(0, heightOffset, 0)
	local positions = {}
	for index, offset in ipairs(offsets) do
		positions[index] = pivot + (facing * offset)
	end

	return positions, radii
end

function EntityService:_getCharactersInBasicAttackHitbox(entity, attackDefinition, targetPlayer)
	local samplePositions, sampleRadii = self:_getEntityBasicAttackSampleData(entity, attackDefinition, targetPlayer)
	if not samplePositions or not sampleRadii then
		return {}, nil, nil
	end

	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	if not roundManager or not characterService then
		return {}, samplePositions, sampleRadii
	end

	local includeInstances = {}
	local candidateEntries = {}
	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		local character = characterService:GetCharacterByPlayer(player)
		if roundState and roundState.IsAlive and character and character.Model and self:_isCharacterEntityTargetable(character) then
			table.insert(includeInstances, character.Model)
			table.insert(candidateEntries, {
				Player = player,
				Character = character,
				Model = character.Model,
				Distance = (character.RootPart.Position - entity.RootPart.Position).Magnitude,
			})
		end
	end

	if #includeInstances <= 0 then
		return {}, samplePositions, sampleRadii
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = includeInstances

	local hits = {}
	local seenPlayers = {}
	for sampleIndex, samplePosition in ipairs(samplePositions) do
		local overlaps = Workspace:GetPartBoundsInRadius(samplePosition, sampleRadii[sampleIndex], overlapParams)
		for _, part in ipairs(overlaps) do
			for _, entry in ipairs(candidateEntries) do
				if not seenPlayers[entry.Player] and part:IsDescendantOf(entry.Model) then
					seenPlayers[entry.Player] = true
					table.insert(hits, entry)
					break
				end
			end
		end
	end

	table.sort(hits, function(a, b)
		if a.Player == targetPlayer then
			return true
		elseif b.Player == targetPlayer then
			return false
		end
		return a.Distance < b.Distance
	end)

	return hits, samplePositions, sampleRadii
end

function EntityService:_resolveEntityBasicAttackHit(entity, activeAttack)
	if not entity or not activeAttack or not activeAttack.Definition then
		return nil, nil, nil
	end

	local hits, samplePositions, sampleRadii = self:_getCharactersInBasicAttackHitbox(entity, activeAttack.Definition, activeAttack.TargetPlayer)
	if #hits <= 0 then
		return nil, samplePositions, sampleRadii
	end

	return hits[1], samplePositions, sampleRadii
end

function EntityService:_finalizeEntityBasicAttack(entity, activeAttack, hitEntry, samplePositions, sampleRadii)
	if not entity or not activeAttack or activeAttack.HasResolved then
		return
	end

	local didHit = hitEntry ~= nil
	activeAttack.HasResolved = true
	activeAttack.ResolvedAt = os.clock()
	activeAttack.DidHit = didHit
	activeAttack.Result = didHit and "Hit" or "Miss"
	activeAttack.HitPlayer = hitEntry and hitEntry.Player or nil
	activeAttack.RecoverySpeedMultiplier = didHit
		and (activeAttack.HitRecoverySpeedMultiplier or activeAttack.RecoverySpeedMultiplier or 0.75)
		or (activeAttack.MissRecoverySpeedMultiplier or activeAttack.RecoverySpeedMultiplier or 0.75)

	if didHit and hitEntry and hitEntry.Character then
		local attackDefinition = activeAttack.Definition
		local damageAmount = entity:GetScaledDamage(attackDefinition.Damage or entity.Damage)
		local didDamage = hitEntry.Character:ApplyDamage(damageAmount)
		if didDamage then
			self:_handleTargetDowned(entity, hitEntry.Player, hitEntry.Character)
			local effectContext = self:_createEffectContext(entity, hitEntry.Player, nil, nil, attackDefinition, {
				AttackId = activeAttack.Id,
				AttackResult = "Hit",
			})
			self:_executeEffectSteps(entity, attackDefinition, effectContext)
		end
	end

	local recoveryDuration = didHit and (activeAttack.HitRecoveryDuration or 0) or (activeAttack.MissRecoveryDuration or activeAttack.HitRecoveryDuration or 0)
	activeAttack.RecoveryEndsAt = activeAttack.ResolvedAt + math.max(0, recoveryDuration)

	if activeAttack.CooldownStartsOn ~= "Start" then
		entity:MarkAttack(activeAttack.Cooldown)
	end

	self:_updateBasicAttackDebugVisual(
		entity,
		samplePositions,
		sampleRadii,
		{
			Color = didHit and Color3.fromRGB(110, 236, 146) or Color3.fromRGB(255, 116, 116),
			Transparency = 0.78,
		}
	)
	self:_clearBasicAttackDebugVisual(entity, BASIC_ATTACK_DEBUG_FLASH_DURATION)
	entity:EnterState(ENTITY_STATE.AttackRecovery, {
		TargetPlayer = entity:GetTarget(),
		TargetPosition = entity:GetTargetLastKnownPosition(),
		HasDirectSight = false,
	})
	self:_syncDebugAttributes(entity)
end

function EntityService:_startEntityBasicAttackActiveWindow(entity, activeAttack)
	if not entity or not activeAttack or activeAttack.ActiveWindowStarted == true then
		return
	end

	activeAttack.ActiveWindowStarted = true
	task.spawn(function()
		while entity:GetActiveBasicAttack() == activeAttack and not activeAttack.HasResolved do
			local now = os.clock()
			if now < activeAttack.HitsAt then
				RunService.Heartbeat:Wait()
				continue
			end

			if now > (activeAttack.ActiveEndsAt or activeAttack.HitsAt) then
				break
			end

			local hitEntry, samplePositions, sampleRadii = self:_resolveEntityBasicAttackHit(entity, activeAttack)
			self:_updateBasicAttackDebugVisual(entity, samplePositions, sampleRadii, {
				Color = Color3.fromRGB(255, 178, 92),
				Transparency = 0.74,
			})
			if hitEntry then
				self:_finalizeEntityBasicAttack(entity, activeAttack, hitEntry, samplePositions, sampleRadii)
				return
			end

			RunService.Heartbeat:Wait()
		end

		if entity:GetActiveBasicAttack() == activeAttack and not activeAttack.HasResolved then
			local samplePositions, sampleRadii = self:_getEntityBasicAttackSampleData(entity, activeAttack.Definition, activeAttack.TargetPlayer)
			self:_finalizeEntityBasicAttack(entity, activeAttack, nil, samplePositions, sampleRadii)
		else
			self:_clearBasicAttackDebugVisual(entity)
		end
	end)
end

function EntityService:_updateEntityBasicAttack(entity)
	local activeAttack = entity and entity.GetActiveBasicAttack and entity:GetActiveBasicAttack() or nil
	if not activeAttack then
		self:_clearBasicAttackDebugVisual(entity)
		return
	end

	if activeAttack.HasResolved and activeAttack.RecoveryEndsAt and os.clock() >= activeAttack.RecoveryEndsAt then
		entity:CompleteBasicAttack()
		entity:AdvanceBasicAttackVariant()
		entity:EnterState(entity:GetTarget() and ENTITY_STATE.Chase or ENTITY_STATE.Patrol, {
			TargetPlayer = entity:GetTarget(),
			TargetPosition = entity:GetTargetLastKnownPosition(),
			HasDirectSight = false,
		})
		self:_clearBasicAttackDebugVisual(entity)
		self:_syncDebugAttributes(entity)
	end
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

	if entity.UsePathfinding and not (entity.SearchMode and entity.SearchMode.IgnoreMovementBlockers) then
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

function EntityService:_createEffectContext(entity, targetPlayer, sourceStep, deltaTime, definition, castData)
	return {
		Entity = entity,
		TargetPlayer = targetPlayer,
		SourceStep = sourceStep,
		DeltaTime = deltaTime,
		Definition = definition,
		CastData = castData,
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
	local executed = EntityEffectExecutors.Execute(self, entity, step, context)
	if not executed then
		warn(string.format("[EntityService] Unsupported effect step '%s' on %s", tostring(step.Type), tostring(entity and entity.DisplayName or "Unknown")))
	end
end

function EntityService:_launchProjectileStatusFromEffect(entity, step, context)
	local targets = self:_resolveEffectTargets(entity, step, context)
	for _, player in ipairs(targets) do
		local character = self.CharacterService:GetCharacterByPlayer(player)
		if self:_isCharacterEntityTargetable(character) then
			self:_spawnEntityProjectile(entity, player, step)
		end
	end
end

function EntityService:_spawnEntityProjectile(entity, targetPlayer, step)
	if not entity or not entity.RootPart then
		return
	end

	local origin = entity.RootPart.Position + Vector3.new(0, step.HeightOffset or 3, 0)
	local targetCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
	local targetPosition = targetCharacter and targetCharacter.RootPart and targetCharacter.RootPart.Position or (origin + entity.RootPart.CFrame.LookVector * 4)
	local forwardDirection = entity.RootPart.CFrame.LookVector
	local initialDirection = (forwardDirection * (step.ForwardBiasDistance or 18)) + ((targetPosition - origin) * (step.InitialTrackingWeight or 0.35))
	if initialDirection.Magnitude <= 0.01 then
		initialDirection = forwardDirection
	end

	local projectilePart = Instance.new("Part")
	projectilePart.Name = step.VisualName or "EntityProjectile"
	projectilePart.Anchored = true
	projectilePart.CanCollide = false
	projectilePart.CanQuery = false
	projectilePart.CanTouch = false
	projectilePart.CastShadow = false
	projectilePart.Material = Enum.Material.Neon
	projectilePart.Color = step.Color or Color3.fromRGB(236, 224, 178)
	projectilePart.Size = step.VisualSize or Vector3.new(0.45, 1.1, 0.18)
	projectilePart.CFrame = CFrame.lookAt(origin, origin + initialDirection.Unit)
	projectilePart.Parent = Workspace

	local projectile = {
		Entity = entity,
		TargetPlayer = targetPlayer,
		Part = projectilePart,
		Direction = initialDirection.Unit,
		Speed = step.Speed or 42,
		TurnRate = step.TurnRate or 0.22,
		HitRadius = step.HitRadius or 1,
		ExpiresAt = os.clock() + (step.Lifetime or 2.5),
		StatusId = step.StatusId,
		StatusDuration = step.Duration,
		StatusMagnitude = step.Magnitude,
		StatusTier = step.Tier,
		StickDuration = step.StickDuration or step.Duration or 0,
		StickName = step.StickName or "QiSealTalisman",
		HomingWeight = step.HomingWeight or 0.18,
		ForwardBiasDistance = step.ForwardBiasDistance or 18,
	}

	table.insert(self.ActiveProjectiles, projectile)
end

function EntityService:_updateProjectiles(deltaTime)
	for index = #self.ActiveProjectiles, 1, -1 do
		local projectile = self.ActiveProjectiles[index]
		if self:_updateProjectile(projectile, deltaTime) ~= true then
			self:_destroyProjectile(projectile)
			table.remove(self.ActiveProjectiles, index)
		end
	end
end

function EntityService:_updateProjectile(projectile, deltaTime)
	if not projectile or not projectile.Part or not projectile.Part.Parent then
		return false
	end

	if os.clock() >= (projectile.ExpiresAt or 0) then
		return false
	end

	local entity = projectile.Entity
	if not entity or not entity.IsActive or entity.Health <= 0 then
		return false
	end

	local targetCharacter = self.CharacterService:GetCharacterByPlayer(projectile.TargetPlayer)
	if not self:_isCharacterEntityTargetable(targetCharacter) then
		return false
	end

	local currentPosition = projectile.Part.Position
	local targetPosition = targetCharacter.RootPart.Position + Vector3.new(0, 1.6, 0)
	local desiredDirection = targetPosition - currentPosition
	if desiredDirection.Magnitude <= 0.01 then
		desiredDirection = projectile.Direction
	end

	local currentDirection = projectile.Direction or desiredDirection.Unit
	local forwardBiasDirection = currentDirection
	local homingWeight = projectile.HomingWeight or 0.18
	local weightedDesiredDirection = (forwardBiasDirection * math.max(0, 1 - homingWeight)) + (desiredDirection.Unit * homingWeight)
	local turnAlpha = math.clamp((projectile.TurnRate or 0.22) * math.max(1, deltaTime * 60), 0, 1)
	local blendedDirection = currentDirection:Lerp(weightedDesiredDirection.Unit, turnAlpha)
	if blendedDirection.Magnitude <= 0.001 then
		blendedDirection = desiredDirection.Unit
	end
	projectile.Direction = blendedDirection.Unit

	local moveDistance = (projectile.Speed or 42) * deltaTime
	local nextPosition = currentPosition + (projectile.Direction * moveDistance)
	projectile.Part.CFrame = CFrame.lookAt(nextPosition, nextPosition + projectile.Direction)

	local hitRadius = projectile.HitRadius or 2.25
	local closestPoint = self:_getClosestPointOnSegment(currentPosition, nextPosition, targetPosition)
	if (targetPosition - closestPoint).Magnitude <= hitRadius then
		self:_resolveProjectileHit(projectile, targetCharacter)
		return false
	end

	return true
end

function EntityService:_getClosestPointOnSegment(segmentStart, segmentEnd, point)
	local segment = segmentEnd - segmentStart
	local segmentLengthSquared = segment:Dot(segment)
	if segmentLengthSquared <= 0.0001 then
		return segmentStart
	end

	local alpha = math.clamp((point - segmentStart):Dot(segment) / segmentLengthSquared, 0, 1)
	return segmentStart + (segment * alpha)
end

function EntityService:_resolveProjectileHit(projectile, targetCharacter)
	if not projectile or not targetCharacter or not targetCharacter.Player then
		return
	end

	if self.StatusEffectService and projectile.StatusId then
		self.StatusEffectService:ApplyStatus(targetCharacter.Player, projectile.StatusId, {
			Duration = projectile.StatusDuration,
			Magnitude = projectile.StatusMagnitude,
			Tier = projectile.StatusTier,
			Source = projectile.Entity and projectile.Entity.DisplayName or "Projectile",
		})
	end

	local characterModel = targetCharacter.Model
	local head = characterModel and characterModel:FindFirstChild("Head")
	if head then
		local talisman = Instance.new("Part")
		talisman.Name = projectile.StickName or "ProjectileSeal"
		talisman.Anchored = false
		talisman.CanCollide = false
		talisman.CanQuery = false
		talisman.CanTouch = false
		talisman.CastShadow = false
		talisman.Material = Enum.Material.Neon
		talisman.Color = projectile.Part and projectile.Part.Color or Color3.fromRGB(236, 224, 178)
		talisman.Size = Vector3.new(0.55, 0.75, 0.08)
		talisman.CFrame = head.CFrame * CFrame.new(0, 0.05, -0.52)
		talisman.Parent = characterModel

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = talisman
		weld.Part1 = head
		weld.Parent = talisman

		task.delay(math.max(0.1, projectile.StickDuration or 0), function()
			if talisman and talisman.Parent then
				talisman:Destroy()
			end
		end)
	end
end

function EntityService:_destroyProjectile(projectile)
	if projectile and projectile.Part and projectile.Part.Parent then
		projectile.Part:Destroy()
	end
end

function EntityService:_cancelProjectilesForEntity(entity)
	if not entity then
		return 0
	end

	local cancelledCount = 0
	for index = #self.ActiveProjectiles, 1, -1 do
		local projectile = self.ActiveProjectiles[index]
		if projectile and projectile.Entity == entity then
			self:_destroyProjectile(projectile)
			table.remove(self.ActiveProjectiles, index)
			cancelledCount += 1
		end
	end

	return cancelledCount
end

function EntityService:_startStruggleFromEffect(entity, step, context)
	if not self.StruggleService then
		return
	end

	for _, target in ipairs(self:_resolveEffectTargets(entity, step, context)) do
		local targetCharacter = self.CharacterService:GetCharacterByPlayer(target)
		if self:_isCharacterEntityTargetable(targetCharacter) then
			local originCFrame = entity.RootPart and entity.RootPart.CFrame or nil
			local struggleParams = table.clone(step)
			struggleParams.LungeOriginCFrame = originCFrame
			struggleParams.ReturnEntityOnBreakFree = step.ReturnEntityOnBreakFree == true

			local hasLunge = (step.LungeDuration or 0) > 0 or (step.LungeSpeed or 0) > 0
			if hasLunge then
				if not step.RequireLineOfSight or entity.IgnoreLineOfSightForAttacks or self:_hasLineOfSight(entity, targetCharacter) then
					self:_performStruggleLunge(entity, target, targetCharacter, struggleParams)
				end
			elseif self:_canResolveStruggleTarget(entity, targetCharacter, step) then
				self:_applyStruggleLunge(entity, targetCharacter, step)
				local started = self.StruggleService:BeginStruggle(entity, target, struggleParams)
				if started and context and context.Definition and context.Definition.Id == "SeekingWisdom" then
					self:_playStruggleLatchVisual(entity, targetCharacter)
				end
			end
		end
	end
end

function EntityService:_startBlindHungerLungeFromEffect(entity, step, context)
	if not self.StruggleService then
		return
	end

	for _, target in ipairs(self:_resolveEffectTargets(entity, step, context)) do
		local targetCharacter = self.CharacterService:GetCharacterByPlayer(target)
		if self:_isCharacterEntityTargetable(targetCharacter) then
			local originCFrame = entity.RootPart and entity.RootPart.CFrame or nil
			local struggleParams = table.clone(step)
			struggleParams.LungeOriginCFrame = originCFrame
			struggleParams.ReturnEntityOnBreakFree = step.ReturnEntityOnBreakFree == true

			if not step.RequireLineOfSight or entity.IgnoreLineOfSightForAttacks or self:_hasLineOfSight(entity, targetCharacter) then
				self:_performBlindHungerLunge(entity, target, targetCharacter, struggleParams)
			end
		end
	end
end

function EntityService:_performBlindHungerLunge(entity, targetPlayer, targetCharacter, struggleParams)
	if not entity or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return
	end

	local motionPart = self:_getEntityMotionPart(entity)
	if not motionPart then
		return
	end

	local startPosition = motionPart.Position
	local targetGroundPosition = self:_getStruggleLungeGroundPosition(startPosition, targetCharacter, struggleParams)
	if not targetGroundPosition then
		return
	end

	local dashOffset = targetGroundPosition - startPosition
	local dashDistance = dashOffset.Magnitude
	if dashDistance <= 0.05 then
		return
	end

	local lungeDuration
	if (struggleParams.LungeSpeed or 0) > 0 then
		lungeDuration = dashDistance / struggleParams.LungeSpeed
		lungeDuration = math.max(struggleParams.MinLungeDuration or 0.1, lungeDuration)
		if struggleParams.MaxLungeDuration then
			lungeDuration = math.min(struggleParams.MaxLungeDuration, lungeDuration)
		end
	else
		lungeDuration = math.max(0.05, struggleParams.LungeDuration or 0.12)
	end

	entity.ActionSequenceId = (entity.ActionSequenceId or 0) + 1
	local actionSequenceId = entity.ActionSequenceId
	entity:BeginSpecialMovement("BlindHunger", lungeDuration + math.max(0, struggleParams.ImpactDelay or 0.05) + 0.1, {
		TargetPlayer = targetPlayer,
		TargetPosition = targetGroundPosition,
	})

	local dashDirection = dashOffset.Unit
	local contactRadius = math.max(0.5, struggleParams.GrabRange or 3.2)
	local minTravelFractionBeforeHit = math.clamp(struggleParams.MinTravelFractionBeforeHit or 0.65, 0, 0.98)
	local gravity = Workspace.Gravity
	local horizontalVelocity = Vector3.new(dashOffset.X, 0, dashOffset.Z) / lungeDuration
	local verticalVelocity = ((targetGroundPosition.Y - startPosition.Y) + (0.5 * gravity * lungeDuration * lungeDuration)) / lungeDuration
	local launchVelocity = Vector3.new(horizontalVelocity.X, verticalVelocity, horizontalVelocity.Z)
	local leapHeight = math.max(0, struggleParams.LeapHeight or 6)

	entity.RootPart.CFrame = CFrame.lookAt(
		entity.RootPart.Position,
		Vector3.new(targetGroundPosition.X, entity.RootPart.Position.Y, targetGroundPosition.Z)
	)
	motionPart.AssemblyLinearVelocity = Vector3.zero
	motionPart.AssemblyAngularVelocity = Vector3.zero
	motionPart.AssemblyLinearVelocity = launchVelocity

	self:_showEntityAbilityVisual("BlindHungerLunge", {
		EntityModel = entity.Model,
		EntityId = entity.Id,
		StartPosition = startPosition,
		EndPosition = targetGroundPosition,
		Duration = lungeDuration,
		LeapHeight = struggleParams.LeapHeight or 0,
		ContactRadius = contactRadius,
	})
	self:_spawnStruggleLungeDebugVisual(startPosition, targetGroundPosition, contactRadius)

	task.spawn(function()
		local elapsed = 0
		local previousPosition = startPosition

		local function finalizeWhiff()
			if entity and entity.GetActiveSpecialMovement and entity:GetActiveSpecialMovement() then
				entity:CompleteSpecialMovement()
			end
		end

		while elapsed < lungeDuration do
			if not entity or not entity.RootPart or not entity.IsActive or entity.Health <= 0 then
				return
			end

			if (entity.ActionSequenceId or 0) ~= actionSequenceId then
				return
			end

			local deltaTime = RunService.Heartbeat:Wait()
			elapsed += deltaTime

			local currentPosition = motionPart.Position
			local planarVelocity = Vector3.new(motionPart.AssemblyLinearVelocity.X, 0, motionPart.AssemblyLinearVelocity.Z)
			if planarVelocity.Magnitude > 0.1 then
				local lookTarget = currentPosition + planarVelocity.Unit
				entity.RootPart.CFrame = CFrame.lookAt(
					entity.RootPart.Position,
					Vector3.new(lookTarget.X, entity.RootPart.Position.Y, lookTarget.Z)
				)
			end

			local traveledDistance = (Vector3.new(currentPosition.X, 0, currentPosition.Z) - Vector3.new(startPosition.X, 0, startPosition.Z)).Magnitude
			if traveledDistance >= (dashDistance * minTravelFractionBeforeHit) then
				local liveCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
				if self:_isCharacterEntityTargetable(liveCharacter) then
					local closestPoint = self:_getClosestPointOnSegment(previousPosition, currentPosition, liveCharacter.RootPart.Position)
					local liveOffset = liveCharacter.RootPart.Position - closestPoint
					local planarLiveOffset = Vector3.new(liveOffset.X, 0, liveOffset.Z)
					if planarLiveOffset.Magnitude <= contactRadius and self:_canResolveStruggleTarget(entity, liveCharacter, struggleParams) then
						if self:_commitStruggleImpact(entity, targetPlayer, struggleParams, struggleParams, actionSequenceId) then
							return
						end
					end
				end
			end

			previousPosition = currentPosition
		end

		if (entity.ActionSequenceId or 0) ~= actionSequenceId then
			return
		end

		finalizeWhiff()
	end)
end

function EntityService:_canResolveStruggleTarget(entity, targetCharacter, step)
	if not entity or not self:_isCharacterEntityTargetable(targetCharacter) then
		return false
	end

	local startRange = step.StartRange or step.Range or 0
	if startRange > 0 and not entity:IsInRange(targetCharacter.RootPart.Position, startRange) then
		return false
	end

	if step.RequireLineOfSight and not (entity.IgnoreLineOfSightForAttacks or self:_hasLineOfSight(entity, targetCharacter)) then
		return false
	end

	return true
end

function EntityService:_applyStruggleLunge(entity, targetCharacter, step)
	if not entity or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return
	end

	local landingCFrame = self:_getStruggleLungeCFrame(entity, targetCharacter, step)
	if not landingCFrame then
		return
	end

	entity.RootPart.CFrame = landingCFrame
end

function EntityService:_getStruggleLungeCFrame(entity, targetCharacter, step)
	if not entity or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return nil
	end

	local origin = entity.RootPart.Position
	local targetPosition = targetCharacter.RootPart.Position
	local offset = targetPosition - origin
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	if planarOffset.Magnitude <= 0.05 then
		return nil
	end

	local lungeStopDistance = step.LungeStopDistance or math.max(entity:GetStopDistance(), 2.25)
	local lungeDistance = math.min(
		planarOffset.Magnitude,
		math.max(0, planarOffset.Magnitude - lungeStopDistance),
		step.LungeDistance or planarOffset.Magnitude
	)
	if lungeDistance <= 0 then
		return nil
	end

	local newPosition = origin + (planarOffset.Unit * lungeDistance)
	newPosition = Vector3.new(newPosition.X, entity.RootPart.Position.Y, newPosition.Z)
	local lookTarget = Vector3.new(targetPosition.X, entity.RootPart.Position.Y, targetPosition.Z)
	return CFrame.lookAt(newPosition, lookTarget)
end

function EntityService:_performStruggleLunge(entity, targetPlayer, targetCharacter, struggleParams)
	if not entity or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return
	end

	local startCFrame = entity.RootPart.CFrame
	local startPosition = startCFrame.Position
	local targetGroundPosition = self:_getStruggleLungeGroundPosition(startPosition, targetCharacter, struggleParams)
	if not targetGroundPosition then
		return
	end

	local dashOffset = targetGroundPosition - startPosition
	local dashDistance = dashOffset.Magnitude
	if dashDistance <= 0.05 then
		return
	end

	local useConstantSpeed = (struggleParams.LungeSpeed or 0) > 0
	local lungeDuration
	if useConstantSpeed then
		lungeDuration = dashDistance / struggleParams.LungeSpeed
		lungeDuration = math.max(struggleParams.MinLungeDuration or 0.1, lungeDuration)
		if struggleParams.MaxLungeDuration then
			lungeDuration = math.min(struggleParams.MaxLungeDuration, lungeDuration)
		end
	else
		lungeDuration = math.max(0.05, struggleParams.LungeDuration or 0.12)
	end

	entity.ActionSequenceId = (entity.ActionSequenceId or 0) + 1
	local actionSequenceId = entity.ActionSequenceId
	entity:LockSpecialMovement(lungeDuration + math.max(0, struggleParams.ImpactDelay or 0.05) + 0.05)

	task.spawn(function()
		local leapHeight = struggleParams.LeapHeight or 0
		local leapSharpness = struggleParams.LeapSharpness or 1.6
		local resolveStep = table.clone(struggleParams)
		resolveStep.StartRange = 0

		local dashDirection = dashOffset.Unit
		local dashLookTarget = startPosition + Vector3.new(dashDirection.X, 0, dashDirection.Z)
		local previousPosition = startPosition
		local contactRadius = math.max(0.5, struggleParams.GrabRange or 3.2)
		local minTravelBeforeHit = math.max(0, struggleParams.MinTravelBeforeHit or 0)
		local minTravelFractionBeforeHit = math.clamp(struggleParams.MinTravelFractionBeforeHit or 0, 0, 0.95)
		local requiredTravelBeforeHit = math.max(
			math.min(minTravelBeforeHit, dashDistance * 0.9),
			dashDistance * minTravelFractionBeforeHit
		)
		self:_showEntityAbilityVisual("BlindHungerLunge", {
			EntityModel = entity.Model,
			EntityId = entity.Id,
			StartPosition = startPosition,
			EndPosition = targetGroundPosition,
			Duration = lungeDuration,
			LeapHeight = leapHeight,
			ContactRadius = contactRadius,
		})
		self:_spawnStruggleLungeDebugVisual(startPosition, targetGroundPosition, contactRadius)

		local elapsed = 0
		while elapsed < lungeDuration do
			if not entity or not entity.RootPart or not entity.IsActive or entity.Health <= 0 then
				return
			end

			if (entity.ActionSequenceId or 0) ~= actionSequenceId then
				return
			end

			local liveCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
			if not self:_isCharacterEntityTargetable(liveCharacter) then
				return
			end

			local alpha = math.clamp(elapsed / lungeDuration, 0, 1)
			local travelAlpha = useConstantSpeed and alpha or (1 - math.pow(1 - alpha, math.max(1, leapSharpness)))
			local blendedPosition = startPosition + (dashDirection * dashDistance * travelAlpha)
			local traveledDistance = (Vector3.new(blendedPosition.X, 0, blendedPosition.Z) - Vector3.new(startPosition.X, 0, startPosition.Z)).Magnitude

			local closestPoint = self:_getClosestPointOnSegment(previousPosition, blendedPosition, liveCharacter.RootPart.Position)
			local hitOffset = liveCharacter.RootPart.Position - closestPoint
			local planarHitOffset = Vector3.new(hitOffset.X, 0, hitOffset.Z)
			if traveledDistance >= requiredTravelBeforeHit and planarHitOffset.Magnitude <= contactRadius and self:_canResolveStruggleTarget(entity, liveCharacter, resolveStep) then
				local impactPosition = Vector3.new(closestPoint.X, entity.RootPart.Position.Y, closestPoint.Z)
				entity.RootPart.CFrame = CFrame.lookAt(impactPosition, impactPosition + Vector3.new(dashDirection.X, 0, dashDirection.Z))
				if self:_commitStruggleImpact(entity, targetPlayer, struggleParams, resolveStep, actionSequenceId) then
					return
				end
			end

			previousPosition = blendedPosition
			elapsed += RunService.Heartbeat:Wait()
		end

		if (entity.ActionSequenceId or 0) ~= actionSequenceId then
			return
		end

		if entity and entity.RootPart then
			local endPosition = Vector3.new(targetGroundPosition.X, entity.RootPart.Position.Y, targetGroundPosition.Z)
			entity.RootPart.CFrame = CFrame.lookAt(endPosition, endPosition + Vector3.new(dashDirection.X, 0, dashDirection.Z))
		end
	end)
end

function EntityService:_showEntityAbilityVisual(visualType, payload)
	if not self.EntityAbilityVisualRemote then
		return
	end

	local finalPayload = {
		Type = visualType,
	}

	for key, value in pairs(payload or {}) do
		finalPayload[key] = value
	end

	self.EntityAbilityVisualRemote:FireAllClients(finalPayload)
end

function EntityService:_createTemporaryAbilityPart(properties, duration)
	local part = Instance.new("Part")
	part.Name = properties.Name or "EntityAbilityVisual"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = properties.Material or Enum.Material.Neon
	part.Color = properties.Color or Color3.fromRGB(255, 206, 143)
	part.Transparency = properties.Transparency or 0.15
	part.Size = properties.Size or Vector3.new(1, 1, 1)
	part.Shape = properties.Shape or Enum.PartType.Ball
	part.CFrame = properties.CFrame or CFrame.new()
	part.Parent = Workspace

	Debris:AddItem(part, duration or 0.25)
	return part
end

function EntityService:_spawnEntityPulseRing(position, color, startRadius, endRadius, duration, yOffset, thickness)
	local ring = self:_createTemporaryAbilityPart({
		Name = "EntityAbilityRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness or 0.12, startRadius * 2, startRadius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, yOffset or 0, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.15,
	}, duration)

	local startedAt = os.clock()
	task.spawn(function()
		while ring and ring.Parent do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			local radius = startRadius + ((endRadius - startRadius) * alpha)
			ring.Size = Vector3.new(thickness or 0.12, radius * 2, radius * 2)
			ring.Transparency = 0.15 + (alpha * 0.8)
			task.wait()
		end
	end)
end

function EntityService:_spawnEntityBurst(position, color, startSize, endSize, duration)
	local burst = self:_createTemporaryAbilityPart({
		Name = "EntityAbilityBurst",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(startSize, startSize, startSize),
		CFrame = CFrame.new(position),
		Color = color,
		Transparency = 0.08,
	}, duration)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = endSize * 2
	light.Brightness = 2.5
	light.Parent = burst

	local startedAt = os.clock()
	task.spawn(function()
		while burst and burst.Parent do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			local size = startSize + ((endSize - startSize) * alpha)
			burst.Size = Vector3.new(size, size, size)
			burst.Transparency = 0.08 + (alpha * 0.86)
			light.Brightness = 2.5 * (1 - alpha)
			task.wait()
		end
	end)
end

function EntityService:_spawnEntityBeamLine(startPosition, endPosition, color, width, duration)
	local offset = endPosition - startPosition
	local distance = offset.Magnitude
	if distance <= 0.05 then
		return
	end

	self:_createTemporaryAbilityPart({
		Name = "EntityAbilityBeam",
		Size = Vector3.new(width or 0.2, width or 0.2, distance),
		CFrame = CFrame.lookAt(startPosition, endPosition) * CFrame.new(0, 0, -(distance * 0.5)),
		Color = color,
		Transparency = 0.12,
	}, duration)
end

function EntityService:_playEntityAbilityCastVisual(entity, abilityId, targetPlayer, castData)
	if not entity or not entity.RootPart then
		return
	end

	local rootPosition = entity.RootPart.Position
	local targetCharacter = targetPlayer and self.CharacterService:GetCharacterByPlayer(targetPlayer)
	local targetPosition = targetCharacter and targetCharacter.RootPart and targetCharacter.RootPart.Position or nil

	if entity.Id == "Vimarga" then
		if abilityId == "Burden" then
			self:_spawnEntityBurst(rootPosition + Vector3.new(0, 2.6, 0), Color3.fromRGB(146, 146, 146), 0.8, 2.8, 0.18)
			self:_spawnEntityPulseRing(rootPosition, Color3.fromRGB(168, 168, 168), 3, 30, 0.32, -2.8, 0.12)
		elseif abilityId == "WeightOfTheVow" then
			local markedPosition = castData and castData.TargetPosition or targetPosition
			if markedPosition then
				local planarTarget = Vector3.new(markedPosition.X, rootPosition.Y, markedPosition.Z)
				self:_spawnEntityBeamLine(rootPosition + Vector3.new(0, 2.4, 0), planarTarget + Vector3.new(0, 0.2, 0), Color3.fromRGB(176, 176, 176), 0.1, 0.2)
				self:_spawnEntityPulseRing(markedPosition, Color3.fromRGB(204, 204, 204), 8, 8, 1.2, -2.8, 0.16)
			end
		end
		return
	end

	if entity.Id ~= "SearchingForWisdom" then
		return
	end

	if abilityId == "RakingWisdom" then
		self:_spawnEntityBurst(rootPosition + Vector3.new(0, 2.4, 0), Color3.fromRGB(214, 132, 94), 0.8, 3.2, 0.18)
		self:_spawnEntityPulseRing(rootPosition, Color3.fromRGB(178, 96, 76), 2.5, 12, 0.35, -2.8, 0.1)
		if targetPosition then
			local planarTarget = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)
			self:_spawnEntityBeamLine(rootPosition + Vector3.new(0, 0.8, 0), planarTarget, Color3.fromRGB(191, 102, 76), 0.16, 0.18)
		end
	elseif abilityId == "SeekingWisdom" then
		self:_spawnEntityBurst(rootPosition + Vector3.new(0, 3.3, 0), Color3.fromRGB(236, 220, 162), 0.6, 2.4, 0.22)
		self:_spawnEntityPulseRing(rootPosition, Color3.fromRGB(184, 154, 104), 1.5, 7.5, 0.28, -2.8, 0.08)
		if targetPosition then
			self:_spawnEntityBeamLine(rootPosition + Vector3.new(0, 3.2, 0), targetPosition + Vector3.new(0, 1.8, 0), Color3.fromRGB(222, 206, 142), 0.12, 0.22)
		end
	elseif abilityId == "Harvest" then
		self:_spawnEntityBurst(rootPosition + Vector3.new(0, 1.6, 0), Color3.fromRGB(205, 88, 88), 0.9, 3.8, 0.2)
		self:_spawnEntityPulseRing(rootPosition, Color3.fromRGB(166, 64, 64), 2.2, 9.5, 0.3, -2.8, 0.1)
		if targetPosition then
			local planarTarget = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)
			self:_spawnEntityBeamLine(rootPosition + Vector3.new(0, 1.1, 0), planarTarget, Color3.fromRGB(202, 96, 96), 0.18, 0.16)
		end
	end
end

function EntityService:_playEntityAbilityResolveVisual(entity, abilityId, targetPlayer, castData)
	if not entity then
		return
	end

	local targetCharacter = targetPlayer and self.CharacterService:GetCharacterByPlayer(targetPlayer)
	local targetPosition = targetCharacter and targetCharacter.RootPart and targetCharacter.RootPart.Position or nil

	if entity.Id == "Vimarga" then
		if abilityId == "WeightOfTheVow" then
			local markedPosition = castData and castData.TargetPosition or targetPosition
			if not markedPosition then
				return
			end

			self:_spawnEntityBurst(markedPosition + Vector3.new(0, 2.1, 0), Color3.fromRGB(214, 214, 214), 0.9, 3.4, 0.2)
			self:_spawnEntityPulseRing(markedPosition, Color3.fromRGB(188, 188, 188), 2.5, 9, 0.24, -2.8, 0.14)
		end
		return
	end

	if entity.Id ~= "SearchingForWisdom" or not targetPosition then
		return
	end

	if abilityId == "RakingWisdom" then
		self:_spawnEntityBurst(targetPosition + Vector3.new(0, 2.1, 0), Color3.fromRGB(198, 88, 72), 0.7, 2.6, 0.18)
		self:_spawnEntityPulseRing(targetPosition, Color3.fromRGB(188, 92, 74), 1.5, 6, 0.24, -2.8, 0.08)
	elseif abilityId == "Harvest" then
		self:_spawnEntityBurst(targetPosition + Vector3.new(0, 1.6, 0), Color3.fromRGB(224, 96, 96), 1.1, 4.4, 0.22)
		self:_spawnEntityPulseRing(targetPosition, Color3.fromRGB(176, 62, 62), 2.2, 7.5, 0.28, -2.8, 0.12)
	end
end

function EntityService:_playStruggleLatchVisual(entity, targetCharacter)
	if not entity or entity.Id ~= "SearchingForWisdom" or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return
	end

	local origin = entity.RootPart.Position + Vector3.new(0, 3.1, 0)
	local targetPosition = targetCharacter.RootPart.Position + Vector3.new(0, 1.8, 0)
	self:_spawnEntityBeamLine(origin, targetPosition, Color3.fromRGB(236, 218, 164), 0.16, 0.32)
	self:_spawnEntityBurst(targetPosition, Color3.fromRGB(240, 226, 178), 0.55, 2.1, 0.18)
	self:_spawnEntityPulseRing(targetCharacter.RootPart.Position, Color3.fromRGB(212, 190, 132), 1.2, 4.4, 0.22, -1.8, 0.08)
end

function EntityService:_spawnStruggleLungeDebugVisual(startPosition, targetPosition, contactRadius)
	if not DebugFlags.Enabled or not DebugFlags.Entity or Workspace:GetAttribute("DebugUiEnabled") == false then
		return
	end

	local visualsFolder = Workspace:FindFirstChild("EntityDebugVisuals")
	if not visualsFolder then
		visualsFolder = Instance.new("Folder")
		visualsFolder.Name = "EntityDebugVisuals"
		visualsFolder.Parent = Workspace
	end

	local dashOffset = targetPosition - startPosition
	local dashDistance = dashOffset.Magnitude
	if dashDistance <= 0.05 then
		return
	end

	local linePart = Instance.new("Part")
	linePart.Name = "BlindHungerPath"
	linePart.Anchored = true
	linePart.CanCollide = false
	linePart.CanQuery = false
	linePart.CanTouch = false
	linePart.Material = Enum.Material.Neon
	linePart.Color = Color3.fromRGB(255, 168, 76)
	linePart.Transparency = 0.05
	linePart.Size = Vector3.new(0.7, 0.7, dashDistance)
	linePart.CFrame = CFrame.lookAt(startPosition, targetPosition) * CFrame.new(0, 0, -(dashDistance * 0.5))
	linePart.Parent = visualsFolder

	local radiusPart = Instance.new("Part")
	radiusPart.Name = "BlindHungerRadius"
	radiusPart.Anchored = true
	radiusPart.CanCollide = false
	radiusPart.CanQuery = false
	radiusPart.CanTouch = false
	radiusPart.Shape = Enum.PartType.Ball
	radiusPart.Material = Enum.Material.Neon
	radiusPart.Color = Color3.fromRGB(255, 225, 125)
	radiusPart.Transparency = 0.45
	radiusPart.Size = Vector3.new(contactRadius * 2, contactRadius * 2, contactRadius * 2)
	radiusPart.Position = targetPosition
	radiusPart.Parent = visualsFolder

	task.delay(LUNGE_DEBUG_VISUAL_DURATION, function()
		if linePart.Parent then
			linePart:Destroy()
		end
		if radiusPart.Parent then
			radiusPart:Destroy()
		end
	end)
end

function EntityService:_commitStruggleImpact(entity, targetPlayer, struggleParams, resolveStep, actionSequenceId)
	local liveCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
	if not liveCharacter or not self:_canResolveStruggleTarget(entity, liveCharacter, resolveStep) then
		return false
	end

	local grabCFrame = self:_getStruggleGrabCFrame(entity, liveCharacter, struggleParams)
	if grabCFrame and entity.RootPart then
		local currentPosition = entity.RootPart.Position
		local targetPosition = grabCFrame.Position
		local planarOffset = Vector3.new(targetPosition.X - currentPosition.X, 0, targetPosition.Z - currentPosition.Z)
		local maxGrabSnapDistance = math.max(0, struggleParams.MaxGrabSnapDistance or 0)

		if maxGrabSnapDistance > 0 and planarOffset.Magnitude > maxGrabSnapDistance then
			local limitedPosition = currentPosition + (planarOffset.Unit * maxGrabSnapDistance)
			local lookTarget = Vector3.new(liveCharacter.RootPart.Position.X, limitedPosition.Y, liveCharacter.RootPart.Position.Z)
			entity.RootPart.CFrame = CFrame.lookAt(limitedPosition, lookTarget)
		else
			entity.RootPart.CFrame = grabCFrame
		end
	end

	local impactDelay = math.max(0, struggleParams.ImpactDelay or 0.05)
	if impactDelay > 0 then
		task.wait(impactDelay)
	end

	if actionSequenceId ~= nil and (entity.ActionSequenceId or 0) ~= actionSequenceId then
		return false
	end

	local finalCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
	if not finalCharacter or not self:_canResolveStruggleTarget(entity, finalCharacter, resolveStep) then
		return false
	end

	return self.StruggleService:BeginStruggle(entity, targetPlayer, struggleParams) == true
end

function EntityService:_getStruggleLungeGroundPosition(startPosition, targetCharacter, step)
	if not startPosition or not targetCharacter or not targetCharacter.RootPart then
		return nil
	end

	local targetPosition = targetCharacter.RootPart.Position
	local predictionSeconds = step.TargetPredictionSeconds or 0.18
	local predictedTargetPosition = targetPosition + (targetCharacter.RootPart.AssemblyLinearVelocity * predictionSeconds)
	local planarOffset = Vector3.new(predictedTargetPosition.X - startPosition.X, 0, predictedTargetPosition.Z - startPosition.Z)
	if planarOffset.Magnitude <= 0.05 then
		return nil
	end

	local lungeStopDistance = step.LungeStopDistance or 0.6
	local overshootDistance = math.max(0, step.OvershootDistance or 0)
	local lungeDistance = math.min(
		planarOffset.Magnitude + overshootDistance,
		math.max(0, (planarOffset.Magnitude - lungeStopDistance) + overshootDistance),
		step.LungeDistance or planarOffset.Magnitude
	)
	if lungeDistance <= 0 then
		return nil
	end

	return startPosition + Vector3.new(planarOffset.Unit.X * lungeDistance, 0, planarOffset.Unit.Z * lungeDistance)
end

function EntityService:_getStruggleGrabCFrame(entity, targetCharacter, step)
	if not entity or not entity.RootPart or not targetCharacter or not targetCharacter.RootPart then
		return nil
	end

	local targetPosition = targetCharacter.RootPart.Position
	local entityPosition = entity.RootPart.Position
	local planarOffset = Vector3.new(targetPosition.X - entityPosition.X, 0, targetPosition.Z - entityPosition.Z)
	if planarOffset.Magnitude <= 0.05 then
		return nil
	end

	local grabStopDistance = step.GrabStopDistance or 0.55
	local targetFloorPosition = Vector3.new(targetPosition.X, entity.RootPart.Position.Y, targetPosition.Z)
	local newPosition = targetFloorPosition - (planarOffset.Unit * grabStopDistance)
	return CFrame.lookAt(newPosition, targetFloorPosition)
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
	local result = self:InterruptEntityRuntime(entity, reason or "Interrupted")
	return result and result.DidInterrupt == true or false
end

function EntityService:InterruptEntityRuntime(entity, reason, options)
	options = options or {}
	local result = {
		DidInterrupt = false,
		CancelledCast = false,
		CancelledBasicAttack = false,
		CancelledSpecialMovement = false,
		CancelledSearchMode = false,
		CancelledProjectiles = 0,
		CancelledStruggles = 0,
		CancelledChallenges = 0,
		AppliedStatus = false,
	}

	if not entity then
		return result
	end

	if options.RequireAlive ~= false and ((entity.IsDead and entity:IsDead()) or entity.Health <= 0) then
		return result
	end

	entity.ActionSequenceId = (entity.ActionSequenceId or 0) + 1

	if options.CancelCast ~= false and entity:IsCasting() then
		entity:CancelCast()
		result.CancelledCast = true
	end

	if options.CancelBasicAttack ~= false and entity.IsBasicAttacking and entity:IsBasicAttacking() then
		entity:CancelBasicAttack()
		self:_clearBasicAttackDebugVisual(entity)
		result.CancelledBasicAttack = true
	end

	if options.CancelSpecialMovement ~= false and entity:IsSpecialMovementLocked() then
		if entity.CancelSpecialMovement then
			entity:CancelSpecialMovement()
		else
			entity:UnlockSpecialMovement()
		end
		result.CancelledSpecialMovement = true
	end

	if options.CancelSearchMode ~= false and entity.SearchMode then
		entity:EndSearchMode()
		result.CancelledSearchMode = true
	end

	if options.CancelProjectiles ~= false then
		result.CancelledProjectiles = self:_cancelProjectilesForEntity(entity)
	end

	if options.CancelStruggles ~= false and self.StruggleService then
		result.CancelledStruggles = self.StruggleService:InterruptStrugglesForEntity(entity, reason or "Interrupted")
	end

	if options.CancelChallenges ~= false and self.BreathHoldService then
		result.CancelledChallenges = self.BreathHoldService:CancelChallengesForEntity(entity, reason or "Interrupted")
	end

	if options.ClearIntent == true then
		entity:ClearIntent()
	end

	if options.ClearPatrolDestination == true then
		entity:ClearPatrolDestination()
	end

	if options.ClearNavigation == true then
		entity:ClearNavigationPath()
		self:_stopEntityMovementTracker(entity)
	end

	local statusId = options.ApplyStatusId
	local statusService = self.StatusEffectService
	if statusId and statusService then
		local instance = statusService:ApplyStatus(entity, statusId, {
			Duration = options.StatusDuration,
			Magnitude = options.StatusMagnitude,
			Tier = options.StatusTier,
			Source = options.StatusSource or reason or "Interrupted",
		})
		result.AppliedStatus = instance ~= nil
	end

	result.DidInterrupt = result.CancelledCast
		or result.CancelledBasicAttack
		or result.CancelledSpecialMovement
		or result.CancelledSearchMode
		or result.CancelledProjectiles > 0
		or result.CancelledStruggles > 0
		or result.CancelledChallenges > 0
		or result.AppliedStatus
		or options.ClearIntent == true
		or options.ClearPatrolDestination == true
		or options.ClearNavigation == true

	self:_syncDebugAttributes(entity)
	if result.DidInterrupt then
		DebugLog:Log("Entity", string.format("[EntityService] %s interrupted (%s)", entity.DisplayName, tostring(reason or "Unknown")))
	end

	return result
end

function EntityService:_cleanupEntityRuntime(entity, reason)
	if not entity then
		return
	end

	self:_clearBasicAttackDebugVisual(entity)
	self:_stopEntityMovementTracker(entity)
	self:InterruptEntityRuntime(entity, reason or "Cleanup", {
		ClearIntent = true,
		ClearPatrolDestination = true,
		ClearNavigation = true,
		RequireAlive = false,
	})
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

function EntityService:_playEntityDeathVisual(entity, reason)
	if not entity or not entity.RootPart then
		return
	end

	local deathDefinition = entity.GetDeathDefinition and entity:GetDeathDefinition() or nil
	local visualType = deathDefinition and deathDefinition.VisualType or nil
	if not visualType then
		return
	end

	local position = entity.RootPart.Position
	local color = deathDefinition.Color
		or (entity.Definition and entity.Definition.RuntimeAppearance and entity.Definition.RuntimeAppearance.Color)
		or Color3.fromRGB(180, 180, 180)

	if visualType == "SmokeBurst" then
		self:_spawnEntityBurst(position + Vector3.new(0, 2.2, 0), color, 0.8, 3.6, 0.32)
		self:_spawnEntityPulseRing(position, color, 2.5, 8.5, 0.28, -2.8, 0.1)
	elseif visualType == "AshBurst" then
		self:_spawnEntityBurst(position + Vector3.new(0, 1.9, 0), color, 0.7, 3.2, 0.22)
		self:_spawnEntityPulseRing(position, color, 1.8, 6.5, 0.22, -2.8, 0.08)
	end

	self:_showEntityAbilityVisual("EntityDeath", {
		EntityModel = entity.Model,
		EntityId = entity.Id,
		Position = position,
		Reason = reason or "Died",
		VisualType = visualType,
		Color = color,
	})
end

function EntityService:_handleEntityDeath(entity, reason)
	if not entity or (entity.IsDead and entity:IsDead()) then
		return false
	end

	local deathDefinition = entity.GetDeathDefinition and entity:GetDeathDefinition() or nil
	local despawnDelay = deathDefinition and deathDefinition.DespawnDelay or 0
	if entity.MarkDead and not entity:MarkDead(reason or "Died", despawnDelay) then
		return false
	end

	self:_cleanupEntityRuntime(entity, reason or "Died")
	if entity.RootPart then
		entity.RootPart.Anchored = true
	end
	self:_clearRoundHooksForEntity(entity)

	local statusEffectService = self.StatusEffectService
	if statusEffectService then
		statusEffectService:ClearStatuses(entity)
	end

	self:_playEntityDeathVisual(entity, reason or "Died")
	self:_syncDebugAttributes(entity)
	self:_syncEntityPresentationState(entity)
	DebugLog:Log("Entity", string.format("[EntityService] %s died (%s)", entity.DisplayName, tostring(reason or "Unknown")))
	self:_checkSuppressionWinCondition(entity, reason or "Died")

	if despawnDelay <= 0 then
		self:_despawnEntity(entity, reason or "Died")
	end

	return true
end

function EntityService:_resetRoundSuppressionTracking()
	self.RoundSuppressionParticipants = {}
	self.RoundSuppressionParticipantCount = 0
end

function EntityService:_shouldTrackRoundSuppressionEntity(entity)
	if not entity then
		return false
	end

	if entity.OwnerEntity ~= nil or entity.IsSummon == true then
		return false
	end

	return true
end

function EntityService:_trackRoundSuppressionEntity(entity)
	if not self:_shouldTrackRoundSuppressionEntity(entity) then
		return
	end

	if self.RoundSuppressionParticipants[entity] then
		return
	end

	self.RoundSuppressionParticipants[entity] = true
	self.RoundSuppressionParticipantCount += 1
end

function EntityService:_isEntitySuppressed(entity)
	if not entity then
		return false
	end

	return (entity.IsDead and entity:IsDead()) or (entity.Health or 0) <= 0
end

function EntityService:_isTrackedSuppressionEntityStillThreatening(entity)
	return entity ~= nil and not self:_isEntitySuppressed(entity)
end

function EntityService:_completeSuppressionWin(summary)
	local roundManager = self.RoundManager
	if not roundManager or not roundManager.IsReceptionActive or not roundManager:IsReceptionActive() then
		return false
	end

	if roundManager.OnEntitiesSuppressed then
		return roundManager:OnEntitiesSuppressed(summary)
	end

	DebugLog:Log("Round", string.format(
		"[EntityService] Entity suppression complete: %s (%s)",
		summary and summary.EntityName or "Entities",
		summary and summary.Reason or "Suppressed"
	))

	if roundManager.EndReception then
		roundManager:EndReception(RoundOutcome.RemnantsWin)
		return true
	end

	return false
end

function EntityService:_checkSuppressionWinCondition(suppressedEntity, reason)
	local roundManager = self.RoundManager
	if not roundManager or not roundManager.IsReceptionActive or not roundManager:IsReceptionActive() then
		return false
	end

	if (self.RoundSuppressionParticipantCount or 0) <= 0 then
		return false
	end

	if suppressedEntity and not self.RoundSuppressionParticipants[suppressedEntity] then
		return false
	end

	local isPrimaryEntity = suppressedEntity
		and suppressedEntity.Definition
		and suppressedEntity.Definition.PrimaryEntity == true
	if isPrimaryEntity then
		return self:_completeSuppressionWin({
			Reason = "PrimaryEntitySuppressed",
			EntityId = suppressedEntity.Id,
			EntityName = suppressedEntity.DisplayName,
			TotalEntities = self.RoundSuppressionParticipantCount,
			RemainingEntities = 0,
		})
	end

	local remainingEntities = 0
	for entity in pairs(self.RoundSuppressionParticipants) do
		if self:_isTrackedSuppressionEntityStillThreatening(entity) then
			remainingEntities += 1
		end
	end

	if remainingEntities > 0 then
		DebugLog:Log("Entity", string.format(
			"[EntityService] Suppression progress: %d/%d threats remain",
			remainingEntities,
			self.RoundSuppressionParticipantCount
		))
		return false
	end

	return self:_completeSuppressionWin({
		Reason = reason or "AllEntitiesSuppressed",
		EntityId = suppressedEntity and suppressedEntity.Id or nil,
		EntityName = suppressedEntity and suppressedEntity.DisplayName or "Entities",
		TotalEntities = self.RoundSuppressionParticipantCount,
		RemainingEntities = 0,
	})
end

function EntityService:_despawnEntity(entity, reason)
	self:_cleanupEntityRuntime(entity, reason or "Despawned")
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

	local stateFolder = self.EntityPresentationStates[entity]
	if stateFolder then
		self.EntityPresentationStates[entity] = nil
		stateFolder:Destroy()
	end

	self:_clearEntityAnimationRuntime(entity)

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

	local intentName = entity:GetIntentName() or "None"
	local intentMetadata = entity:GetIntentMetadata() or {}
	local searchCenter = entity:GetCurrentSearchCenter()
	local searchCenterText = searchCenter and string.format("%d,%d", math.floor(searchCenter.X + 0.5), math.floor(searchCenter.Z + 0.5)) or ""
	local targetPlayer = entity:GetTarget()
	local targetMemoryAge = targetPlayer and entity:GetTargetMemory(targetPlayer) and entity:GetTimeSinceTargetWasVisible(targetPlayer) or math.huge
	local movementTracker = self.EntityMovementTrackers and self.EntityMovementTrackers[entity] or nil
	local movementDebug = movementTracker and movementTracker.GetDebugSnapshot and movementTracker:GetDebugSnapshot() or nil
	local currentWalkSpeed = entity.GetCurrentHumanoidWalkSpeed and entity:GetCurrentHumanoidWalkSpeed() or (entity.Humanoid and entity.Humanoid.WalkSpeed) or 0
	local targetWalkSpeed = entity.GetTargetHumanoidWalkSpeed and entity:GetTargetHumanoidWalkSpeed() or currentWalkSpeed
	local activeAttack = entity.GetActiveBasicAttack and entity:GetActiveBasicAttack() or nil
	local attackPhase = ""
	local attackRemaining = nil
	local attackResult = ""
	if activeAttack then
		if activeAttack.HasResolved then
			attackPhase = "Recovery"
			attackRemaining = activeAttack.RecoveryEndsAt and math.max(0, activeAttack.RecoveryEndsAt - os.clock()) or 0
			attackResult = activeAttack.Result or ""
		else
			local now = os.clock()
			if now < (activeAttack.HitsAt or now) then
				attackPhase = "Windup"
				attackRemaining = math.max(0, (activeAttack.HitsAt or now) - now)
			else
				attackPhase = "Active"
				attackRemaining = math.max(0, (activeAttack.ActiveEndsAt or now) - now)
			end
		end
	end
	local directSight = false
	local visibleSight = false
	if targetPlayer then
		local currentCandidate = self:_buildActiveRemnantCandidate(entity, targetPlayer, {})
		directSight = currentCandidate and currentCandidate.HasDirectSight == true or false
		visibleSight = currentCandidate and currentCandidate.IsVisible == true or false
	end

	entity.Model:SetAttribute("EntityId", entity.Id)
	entity.Model:SetAttribute("EntityDisplayName", entity.DisplayName)
	entity.Model:SetAttribute("EntityState", entity:GetState())
	entity.Model:SetAttribute("EntityTarget", entity:GetTarget() and entity:GetTarget().Name or "")
	entity.Model:SetAttribute("EntityTerrorRadius", entity.TerrorRadius or 0)
	entity.Model:SetAttribute("DebugEntityName", entity.DisplayName)
	entity.Model:SetAttribute("DebugState", entity:GetState())
	entity.Model:SetAttribute("DebugIntent", intentName)
	entity.Model:SetAttribute("DebugIntentConfidence", string.format("%.2f", entity:GetIntentConfidence() or 0))
	entity.Model:SetAttribute("DebugIntentReason", tostring(intentMetadata.Reason or "None"))
	entity.Model:SetAttribute("DebugTopStimuli", "")
	entity.Model:SetAttribute("DebugSearchCenter", searchCenterText)
	entity.Model:SetAttribute("DebugMemoryAge", targetMemoryAge < math.huge and string.format("%.1fs", targetMemoryAge) or "")
	entity.Model:SetAttribute("DebugHealth", math.floor((entity.Health or 0) + 0.5))
	entity.Model:SetAttribute("DebugMaxHealth", math.floor((entity.MaxHealth or 0) + 0.5))
	entity.Model:SetAttribute("DebugSuppressed", self:_isEntitySuppressed(entity))
	entity.Model:SetAttribute("DebugRoundSuppressionTracked", self.RoundSuppressionParticipants[entity] == true)
	entity.Model:SetAttribute("DebugPrimaryEntity", entity.Definition and entity.Definition.PrimaryEntity == true)
	entity.Model:SetAttribute("DebugTarget", entity:GetTarget() and entity:GetTarget().Name or "")
	entity.Model:SetAttribute("DebugDirectSight", visibleSight)
	entity.Model:SetAttribute("DebugDetectionSight", directSight)
	entity.Model:SetAttribute("DebugPatrolReason", entity:GetPatrolDestinationReason() or "")
	entity.Model:SetAttribute("DebugPatrolPointId", entity.GetPatrolDestinationPointId and (entity:GetPatrolDestinationPointId() or "") or "")
	entity.Model:SetAttribute("DebugPatrolPauseRemaining", entity.GetPatrolPauseRemaining and entity:GetPatrolPauseRemaining() or 0)
	entity.Model:SetAttribute("DebugChaseLostSight", entity.GetChaseLostSightDuration and entity:GetChaseLostSightDuration() or 0)
	entity.Model:SetAttribute("DebugAbsorbedCount", entity.GetAbsorbedAbilityCount and entity:GetAbsorbedAbilityCount() or 0)
	entity.Model:SetAttribute("DebugNetworkOwner", "Server")
	entity.Model:SetAttribute("DebugMoveMode", movementDebug and movementDebug.MoveMode or "Idle")
	entity.Model:SetAttribute("DebugWalkSpeed", currentWalkSpeed)
	entity.Model:SetAttribute("DebugTargetWalkSpeed", targetWalkSpeed)
	entity.Model:SetAttribute("DebugPathStatus", movementDebug and movementDebug.PathStatus or "Idle")
	entity.Model:SetAttribute("DebugPathError", movementDebug and movementDebug.LastPathError or "")
	entity.Model:SetAttribute("DebugWaypointIndex", movementDebug and movementDebug.WaypointIndex or 0)
	entity.Model:SetAttribute("DebugWaypointCount", movementDebug and movementDebug.WaypointCount or 0)
	entity.Model:SetAttribute("DebugTargetDistance", movementDebug and movementDebug.TargetDistance or nil)
	entity.Model:SetAttribute("DebugGoalDistance", movementDebug and movementDebug.GoalDistance or nil)
	entity.Model:SetAttribute("DebugPredictionSeconds", movementDebug and movementDebug.PredictionSecondsUsed or nil)
	entity.Model:SetAttribute("DebugPredictionMode", movementDebug and movementDebug.PredictionMode or "None")
	entity.Model:SetAttribute("DebugTurnSeverity", movementDebug and movementDebug.TurnSeverity or nil)
	entity.Model:SetAttribute("DebugPathAge", movementDebug and movementDebug.PathAge or nil)
	entity.Model:SetAttribute("DebugRemainingPathDistance", movementDebug and movementDebug.RemainingPathDistance or nil)
	entity.Model:SetAttribute("DebugLineOfSight", movementDebug and movementDebug.HasLineOfSight or nil)
	entity.Model:SetAttribute("DebugMovementLane", movementDebug and movementDebug.HasMovementLane or nil)
	entity.Model:SetAttribute("DebugDirectGrace", movementDebug and movementDebug.DirectGraceRemaining or nil)
	entity.Model:SetAttribute("DebugAttackPhase", attackPhase)
	entity.Model:SetAttribute("DebugAttackRemaining", attackRemaining)
	entity.Model:SetAttribute("DebugAttackResult", attackResult)
	entity.Model:SetAttribute("DebugAttackBlocked", entity.GetActionCooldown and entity:GetActionCooldown(BASIC_ATTACK_BLOCKED_COOLDOWN_KEY) or 0)
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

	if entity.Health > 0 and options.Interrupt then
		local interruptOptions = type(options.Interrupt) == "table" and table.clone(options.Interrupt) or {}
		self:InterruptEntityRuntime(entity, interruptOptions.Reason or options.Source or options.WeaponId or "Damaged", interruptOptions)
	end

	if entity.Health <= 0 then
		self:_handleEntityDeath(entity, options.Reason or "HealthDepleted")
	end

	self:_syncDebugAttributes(entity)
	self:_syncEntityPresentationState(entity)

	return true
end

function EntityService:_entityMatchesQuery(entity, options)
	options = options or {}
	if not entity or not entity.Model then
		return false
	end

	if options.ExcludeEntity and options.ExcludeEntity == entity then
		return false
	end

	if options.RequireActive ~= false and not entity.IsActive then
		return false
	end

	if options.RequireAlive ~= false then
		if entity.Health <= 0 then
			return false
		end

		if entity.IsDead and entity:IsDead() then
			return false
		end
	end

	if options.ExcludeSummons == true and entity.IsSummon then
		return false
	end

	if options.Predicate and options.Predicate(entity) ~= true then
		return false
	end

	return true
end

function EntityService:GetLiveEntities(options)
	local entities = {}
	for _, entity in ipairs(self.Entities or {}) do
		if self:_entityMatchesQuery(entity, options) then
			table.insert(entities, entity)
		end
	end
	return entities
end

function EntityService:GetEntitiesInRadius(position, radius, options)
	local entities = {}
	if typeof(position) ~= "Vector3" then
		return entities
	end

	options = options or {}
	local maxDistance = math.max(0, radius or options.MaxDistance or 0)
	for _, entity in ipairs(self:GetLiveEntities(options)) do
		local entityPosition = entity:GetPosition()
		if entityPosition and (entityPosition - position).Magnitude <= maxDistance then
			table.insert(entities, entity)
		end
	end

	return entities
end

function EntityService:GetNearestEntity(position, options)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	options = options or {}
	local direction = options.Direction
	local minDot = options.MinDot or -1
	local maxDistance = options.MaxDistance or math.huge
	local bestEntity = nil
	local bestDistance = math.huge

	for _, entity in ipairs(self:GetLiveEntities(options)) do
		local entityPosition = entity:GetPosition()
		if entityPosition then
			local offset = entityPosition - position
			local distance = offset.Magnitude
			if distance <= maxDistance and distance < bestDistance then
				local dot = 1
				if typeof(direction) == "Vector3" and direction.Magnitude > 0 and distance > 0 then
					dot = direction.Unit:Dot(offset.Unit)
				end

				if dot >= minDot then
					bestDistance = distance
					bestEntity = entity
				end
			end
		end
	end

	return bestEntity
end

function EntityService:GetEntityFromInstance(instance, options)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	for _, entity in ipairs(self:GetLiveEntities(options)) do
		if entity.Model and instance:IsDescendantOf(entity.Model) then
			return entity
		end
	end

	return nil
end

function EntityService:ForceChaseTarget(entity, player, position)
	entity:SetTarget(player, position, true)
	entity:RememberTarget(player, position, true)
	entity:EnterState(ENTITY_STATE.Chase)
end

function EntityService:_resolveEffectTargets(entity, step, context)
	return EntityEffectResolvers.ResolveTargets(self, entity, step, context)
end

function EntityService:_resolveEffectTargetPosition(entity, step, context)
	return EntityEffectResolvers.ResolvePosition(self, entity, step, context)
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
	if not entity or not targetPlayer or not targetCharacter or not targetCharacter:IsDowned() then
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
			if self:_isCharacterEntityTargetable(character) then
				local distance = (character.RootPart.Position - entityPosition).Magnitude
				if self:_hasDirectSight(entity, character, distance) then
					table.insert(visiblePlayers, player)
				end
			end
		end
	end

	return visiblePlayers
end

function EntityService:_collectCandidatePlayers(entity)
	local players = {}
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	if not roundManager or not characterService then
		return players
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		local character = characterService:GetCharacterByPlayer(player)
		if roundState and roundState.IsAlive and self:_isCharacterEntityTargetable(character) then
			table.insert(players, player)
		end
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
			if self:_isCharacterEntityTargetable(character) then
				if (character.RootPart.Position - entityPosition).Magnitude <= radius then
					table.insert(players, player)
				end
			end
		end
	end

	return players
end

function EntityService:_collectPlayersInRadiusOfPosition(position, radius)
	local players = {}
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	if not roundManager or not characterService or not position then
		return players
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if self:_isCharacterEntityTargetable(character) then
				if (character.RootPart.Position - position).Magnitude <= radius then
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

function EntityService:_getSightTargetPositions(entity, character)
	local positions = {}
	if not entity or not character or not character.Model then
		return positions
	end

	local isCrouching = character.IsCrouching == true

	local sightHeights = entity.SightTargetHeights
	if type(sightHeights) ~= "table" or #sightHeights == 0 then
		sightHeights = { 2.5, 1.5, 0.2 }
	end
	if isCrouching then
		sightHeights = { 0.35, -0.15, -0.65 }
	end

	local basePart = character.RootPart
	local head = character.Model:FindFirstChild("Head")
	local upperTorso = character.Model:FindFirstChild("UpperTorso")
	local torso = character.Model:FindFirstChild("Torso")
	local lowerTorso = character.Model:FindFirstChild("LowerTorso")

	local seen = {}
	local function push(position)
		if typeof(position) ~= "Vector3" then
			return
		end

		local key = string.format("%.3f|%.3f|%.3f", position.X, position.Y, position.Z)
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(positions, position)
	end

	if not isCrouching and head and head:IsA("BasePart") then
		push(head.Position)
	end
	if not isCrouching and upperTorso and upperTorso:IsA("BasePart") then
		push(upperTorso.Position)
	end
	if not isCrouching and torso and torso:IsA("BasePart") then
		push(torso.Position)
	end
	if not isCrouching and lowerTorso and lowerTorso:IsA("BasePart") then
		push(lowerTorso.Position)
	end
	if isCrouching and torso and torso:IsA("BasePart") then
		for _, height in ipairs(sightHeights) do
			push(torso.Position + Vector3.new(0, height, 0))
		end
		return positions
	end
	if basePart and basePart:IsA("BasePart") then
		for _, height in ipairs(sightHeights) do
			push(basePart.Position + Vector3.new(0, height, 0))
		end
	end

	return positions
end

function EntityService:_canSeeAnyPosition(entity, character, positions)
	local origin = entity:GetPosition()
	if not origin or not character or not character.Model then
		return false
	end

	self.RaycastParams.FilterDescendantsInstances = {
		entity.Model,
		self.EntitiesFolder,
		self.MapBounds,
	}

	local originHeight = entity.SightOriginHeight or 2.5
	local rayOrigin = origin + Vector3.new(0, originHeight, 0)
	for _, targetPosition in ipairs(positions or {}) do
		local direction = targetPosition - rayOrigin
		if direction.Magnitude <= 0.01 then
			return true
		end

		local result = Workspace:Raycast(rayOrigin, direction, self.RaycastParams)
		if not result or (result.Instance and result.Instance:IsDescendantOf(character.Model)) then
			return true
		end
	end

	return false
end

function EntityService:_passesDetectionFOV(entity, character)
	if not entity or entity.IgnoreLineOfSightForDetection then
		return true
	end

	local origin = entity:GetPosition()
	local rootPart = entity.RootPart
	local targetRoot = character and character.RootPart
	if not origin or not rootPart or not targetRoot then
		return false
	end

	local toTarget = targetRoot.Position - origin
	local planarToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if planarToTarget.Magnitude <= 0.01 then
		return true
	end

	local lookVector = rootPart.CFrame.LookVector
	local planarLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if planarLook.Magnitude <= 0.01 then
		return true
	end

	local fovDegrees = entity.DetectionFOVDegrees or 100
	local minimumDot = math.cos(math.rad(math.clamp(fovDegrees, 1, 179) * 0.5))
	return planarLook.Unit:Dot(planarToTarget.Unit) >= minimumDot
end

function EntityService:_hasDirectSight(entity, character, precomputedDistance, precomputedVisibility)
	local origin = entity and entity:GetPosition()
	local targetRoot = character and character.RootPart
	if not origin or not targetRoot then
		return false
	end

	local distance = precomputedDistance or (targetRoot.Position - origin).Magnitude
	if distance > entity:GetDetectionRange() then
		return false
	end

	local isCrouching = character.IsCrouching == true
	local awarenessRadius = entity.AwarenessRadius or math.min(10, entity:GetDetectionRange())
	if distance <= awarenessRadius then
		if isCrouching then
			if precomputedVisibility ~= nil then
				return precomputedVisibility
			end

			return self:_canSeeAnyPosition(entity, character, self:_getSightTargetPositions(entity, character))
		end

		return true
	end

	if entity.IgnoreLineOfSightForDetection then
		return true
	end

	if not self:_passesDetectionFOV(entity, character) then
		return false
	end

	if precomputedVisibility ~= nil then
		return precomputedVisibility
	end

	return self:_canSeeAnyPosition(entity, character, self:_getSightTargetPositions(entity, character))
end

function EntityService:_hasLineOfSight(entity, character)
	if not entity or not character or not character.RootPart then
		return false
	end

	return self:_canSeeAnyPosition(entity, character, self:_getSightTargetPositions(entity, character))
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

function EntityService:_resolveStimulusInvestigationPoint(entity, stimulus, canSeeOrigin)
	local entityPosition = entity:GetPosition()
	local originPoint = stimulus.Position
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
	self:_resetRoundSuppressionTracking()

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

		if not state or not participatesInRound then
			self:_stopEntityMovementTracker(entity)
		end

		entity:SetActive(state and participatesInRound)
		if state and participatesInRound then
			self:_enforceServerNetworkOwnership(entity.Model)
			self:_registerRoundHooksForEntity(entity)
			self:_trackRoundSuppressionEntity(entity)
		end
		
		if not state then
			local statusEffectService = self.StatusEffectService
			if statusEffectService then
				statusEffectService:ClearStatuses(entity)
			end
			entity:ResetToSpawn()
		end

		self:_syncDebugAttributes(entity)
		self:_syncEntityPresentationState(entity)
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
		definitionCopy.SourceKind = "Entity"
		definitionCopy.SourceLabel = string.format("%s.%s", entity.DisplayName, tostring(hookId))
		definitionCopy.OwnerEntityId = entity.Id
		definitionCopy.DisableOnError = true
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
