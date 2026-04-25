local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local EntityPresentationConstants = require(ReplicatedStorage.Shared.Constants.EntityPresentationConstants)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityPresentationController = {}
EntityPresentationController.Name = "EntityPresentationController"

local function _normalizeAnimationId(animationId)
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

local function _isVisualEffectInstance(instance)
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
end

local function _zeroAssemblyVelocities(model)
	if not model then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function _getAnimationKeysForState(stateName)
	if stateName == "Patrol" or stateName == "Scout" then
		return { "Patrol", "Walk", "Move", "Idle" }
	elseif stateName == "Chase" or stateName == "Rage" then
		return { "Chase", "Run", "Move", "Walk", "Idle" }
	elseif stateName == "AttackWindup" or stateName == "AttackRecovery" then
		return { "Attack", "BasicAttack", "Swing", "Move", "Walk", "Idle" }
	elseif stateName == "Casting" then
		return { "Casting", "Cast", "Ability", "Idle" }
	elseif stateName == "Stunned" then
		return { "Stunned", "Hit", "Idle" }
	elseif stateName == "Dead" then
		return { "Death", "Dead" }
	end

	return { "Idle", "Patrol", "Walk" }
end

function EntityPresentationController:Init()
	self.EntitiesFolder = Workspace:WaitForChild("Entities")
	self.RuntimeFolder = self.World.Shared:WaitForChild(EntityPresentationConstants.RuntimeFolderName)
	self.Camera = Workspace.CurrentCamera or self.World.Camera
	self.VisualsFolder = Workspace:FindFirstChild(EntityPresentationConstants.ClientVisualFolderName)
	if not self.VisualsFolder then
		self.VisualsFolder = Instance.new("Folder")
		self.VisualsFolder.Name = EntityPresentationConstants.ClientVisualFolderName
		self.VisualsFolder.Parent = Workspace
	end

	self.CullDistance = EntityPresentationConstants.CullDistance
	self.SnapDistance = EntityPresentationConstants.SnapDistance
	self.InterpolationSpeed = EntityPresentationConstants.InterpolationSpeed
	self.Runtimes = {}
	self.AuthoritativeModelsByRuntimeId = {}
end

function EntityPresentationController:Start()
	for _, model in ipairs(self.EntitiesFolder:GetChildren()) do
		self:_registerAuthoritativeModel(model)
	end

	self.EntitiesFolder.ChildAdded:Connect(function(child)
		self:_registerAuthoritativeModel(child)
	end)

	self.EntitiesFolder.ChildRemoved:Connect(function(child)
		self:_unregisterAuthoritativeModel(child)
	end)

	DebugLog:Log("ClientEntity", "[EntityPresentationController] Started")
end

function EntityPresentationController:_registerAuthoritativeModel(model)
	if not model:IsA("Model") then
		return
	end

	local runtimeId = model:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute)
	if type(runtimeId) ~= "string" or runtimeId == "" then
		return
	end

	self.AuthoritativeModelsByRuntimeId[runtimeId] = model
	self:_setAuthoritativeModelHidden(model, false)
end

function EntityPresentationController:_unregisterAuthoritativeModel(model)
	if not model:IsA("Model") then
		return
	end

	local runtimeId = model:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute)
	if type(runtimeId) == "string" and runtimeId ~= "" and self.AuthoritativeModelsByRuntimeId[runtimeId] == model then
		self.AuthoritativeModelsByRuntimeId[runtimeId] = nil
		local runtime = self.Runtimes[runtimeId]
		if runtime then
			runtime.AuthoritativeModel = nil
		end
	end
end

function EntityPresentationController:_trackRuntime(folder)
	if not folder:IsA("Folder") then
		return
	end

	local runtimeId = folder:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute) or folder.Name
	local runtime = self.Runtimes[runtimeId]
	if runtime then
		runtime.Folder = folder
		return
	end

	runtime = {
		Id = runtimeId,
		Folder = folder,
		AuthoritativeModel = self:_resolveAuthoritativeModel(runtimeId),
		VisualModel = nil,
		AnimationTracks = nil,
		Animator = nil,
		CurrentAnimationKey = nil,
		CurrentState = nil,
		CurrentCFrame = nil,
		Humanoid = nil,
		PresentationHeightOffset = 0,
		UsesHumanoidLocomotion = false,
	}

	self.Runtimes[runtimeId] = runtime
end

function EntityPresentationController:_untrackRuntime(folder)
	local runtimeId = folder:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute) or folder.Name
	local runtime = self.Runtimes[runtimeId]
	if not runtime then
		return
	end

	self:_destroyVisualRuntime(runtime)

	if runtime.AuthoritativeModel then
		self:_setAuthoritativeModelHidden(runtime.AuthoritativeModel, false)
	end

	self.Runtimes[runtimeId] = nil
end

function EntityPresentationController:_resolveAuthoritativeModel(runtimeId)
	local model = self.AuthoritativeModelsByRuntimeId[runtimeId]
	if model and model.Parent then
		return model
	end

	for _, candidate in ipairs(self.EntitiesFolder:GetChildren()) do
		if candidate:IsA("Model") and candidate:GetAttribute(EntityPresentationConstants.RuntimeIdAttribute) == runtimeId then
			self.AuthoritativeModelsByRuntimeId[runtimeId] = candidate
			self:_setAuthoritativeModelHidden(candidate, false)
			return candidate
		end
	end

	return nil
end

function EntityPresentationController:_setAuthoritativeModelHidden(model, hidden)
	if not model or not model.Parent then
		return
	end

	local transparency = hidden and 1 or 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = transparency
		end
	end
end

function EntityPresentationController:_destroyVisualRuntime(runtime)
	if runtime.AnimationTracks then
		for _, track in pairs(runtime.AnimationTracks) do
			pcall(function()
				track:Stop(0.1)
				track:Destroy()
			end)
		end
	end

	runtime.AnimationTracks = nil
	runtime.Animator = nil
	runtime.CurrentAnimationKey = nil
	runtime.CurrentCFrame = nil
	runtime.Humanoid = nil
	runtime.PresentationHeightOffset = 0
	runtime.UsesHumanoidLocomotion = false

	if runtime.VisualModel then
		runtime.VisualModel:Destroy()
		runtime.VisualModel = nil
	end
end

function EntityPresentationController:_getPresentationHeightOffset(visualModel, humanoid)
	if not humanoid or not visualModel or not visualModel.PrimaryPart then
		return 0
	end

	return EntityPresentationConstants.HumanoidPresentationLift or 0
end

function EntityPresentationController:_toPresentationCFrame(runtime, serverCFrame)
	if typeof(serverCFrame) ~= "CFrame" then
		return serverCFrame
	end

	local heightOffset = runtime.PresentationHeightOffset or 0
	if heightOffset <= 0 then
		return serverCFrame
	end

	return serverCFrame + Vector3.new(0, heightOffset, 0)
end

function EntityPresentationController:_ensureAnimator(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	end

	local animationController = model:FindFirstChildOfClass("AnimationController")
	if not animationController then
		animationController = Instance.new("AnimationController")
		animationController.Name = "ClientAnimationController"
		animationController.Parent = model
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animationController
	end

	return animator
end

function EntityPresentationController:_loadAnimationTracks(model, entityId)
	local animator = self:_ensureAnimator(model)
	if not animator then
		return nil, nil
	end

	local animationTracks = {}
	local definition = EntityDefinitions[entityId]
	local presentation = definition and definition.Presentation or nil
	local animationIds = presentation and presentation.AnimationIds or nil

	if type(animationIds) == "table" then
		for key, animationId in pairs(animationIds) do
			local normalizedId = _normalizeAnimationId(animationId)
			if normalizedId then
				local animation = Instance.new("Animation")
				animation.Name = "EntityAnimation_" .. tostring(key)
				animation.AnimationId = normalizedId
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				animation:Destroy()
				if ok and track then
					animationTracks[string.lower(tostring(key))] = track
				end
			end
		end
	end

	local animationsFolder = model:FindFirstChild("Animations")
	if animationsFolder then
		for _, child in ipairs(animationsFolder:GetChildren()) do
			if child:IsA("Animation") and not animationTracks[string.lower(child.Name)] then
				local ok, track = pcall(function()
					return animator:LoadAnimation(child)
				end)
				if ok and track then
					animationTracks[string.lower(child.Name)] = track
				end
			end
		end
	end

	return animator, next(animationTracks) and animationTracks or nil
end

function EntityPresentationController:_createVisualModel(runtime)
	local authoritativeModel = runtime.AuthoritativeModel or self:_resolveAuthoritativeModel(runtime.Id)
	if not authoritativeModel or not authoritativeModel.Parent then
		return nil
	end

	local visualModel = authoritativeModel:Clone()
	visualModel.Name = string.format("ClientVisual_%s", runtime.Id)
	local humanoid = visualModel:FindFirstChildOfClass("Humanoid")
	local hasHumanoid = humanoid ~= nil

	for _, descendant in ipairs(visualModel:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = not hasHumanoid
			if hasHumanoid then
				if descendant.Name == "HumanoidRootPart" then
					descendant.CanCollide = true
					descendant.Massless = false
					descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 1, 1)
				else
					descendant.CanCollide = false
					descendant.Massless = true
					descendant.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
				end
			elseif descendant.Name == "HumanoidRootPart" then
				descendant.CanCollide = false
			elseif descendant.Parent and descendant.Parent:IsA("Accessory") then
				descendant.CanCollide = false
			end
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.LocalTransparencyModifier = 0
		elseif _isVisualEffectInstance(descendant) then
			descendant.Enabled = false
		end
	end

	if not visualModel.PrimaryPart then
		visualModel.PrimaryPart = visualModel:FindFirstChild("HumanoidRootPart") or visualModel:FindFirstChildWhichIsA("BasePart")
	end

	if not visualModel.PrimaryPart then
		visualModel:Destroy()
		return nil
	end

	local entityId = runtime.Folder:GetAttribute(EntityPresentationConstants.EntityIdAttribute)
	local animator, animationTracks = self:_loadAnimationTracks(visualModel, entityId)
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.WalkSpeed = self:_getDesiredMoveSpeed(runtime, runtime.Folder:GetAttribute(EntityPresentationConstants.StateAttribute) or "Patrol")
	end

	runtime.VisualModel = visualModel
	runtime.Animator = animator
	runtime.AnimationTracks = animationTracks
	runtime.CurrentAnimationKey = nil
	runtime.CurrentCFrame = nil
	runtime.Humanoid = humanoid
	runtime.PresentationHeightOffset = self:_getPresentationHeightOffset(visualModel, humanoid)
	runtime.UsesHumanoidLocomotion = humanoid ~= nil

	return visualModel
end

function EntityPresentationController:_resolveAnimationTrack(runtime, stateName)
	if not runtime.AnimationTracks then
		return nil, nil
	end

	for _, key in ipairs(_getAnimationKeysForState(stateName)) do
		local track = runtime.AnimationTracks[string.lower(key)]
		if track then
			return key, track
		end
	end

	return nil, nil
end

function EntityPresentationController:_getEntityDefinitionForRuntime(runtime)
	local entityId = runtime.Folder:GetAttribute(EntityPresentationConstants.EntityIdAttribute)
	return EntityDefinitions[entityId], entityId
end

function EntityPresentationController:_getDesiredMoveSpeed(runtime, stateName)
	local definition = self:_getEntityDefinitionForRuntime(runtime)
	if not definition then
		return 18
	end

	local stats = definition.Stats or {}
	local navigation = definition.Navigation or {}
	if stateName == "Chase" or stateName == "Rage" then
		return stats.ChaseSpeed or stats.WalkSpeed or 18
	elseif stateName == "Scout" then
		return (stats.WalkSpeed or 18) * (navigation.SearchSpeedMultiplier or 1)
	elseif stateName == "Patrol" then
		return stats.WalkSpeed or 18
	end

	return stats.WalkSpeed or 18
end

function EntityPresentationController:_updateAnimation(runtime)
	if not runtime.VisualModel or not runtime.AnimationTracks then
		return
	end

	local stateName = runtime.Folder:GetAttribute(EntityPresentationConstants.StateAttribute) or "Dormant"
	if runtime.CurrentState == stateName and runtime.CurrentAnimationKey ~= nil then
		return
	end

	runtime.CurrentState = stateName
	local desiredKey, desiredTrack = self:_resolveAnimationTrack(runtime, stateName)
	if runtime.CurrentAnimationKey == desiredKey and desiredTrack and desiredTrack.IsPlaying then
		return
	end

	for _, track in pairs(runtime.AnimationTracks) do
		if track ~= desiredTrack then
			pcall(function()
				track:Stop(0.15)
			end)
		end
	end

	runtime.CurrentAnimationKey = desiredKey
	if desiredTrack then
		desiredTrack.Looped = stateName ~= "Dead"
		pcall(function()
			desiredTrack:Play(0.15)
		end)
	end
end

function EntityPresentationController:_shouldCullRuntime(runtime)
	local targetCFrame = runtime.Folder:GetAttribute(EntityPresentationConstants.CFrameAttribute)
	if typeof(targetCFrame) ~= "CFrame" then
		return true
	end

	local camera = Workspace.CurrentCamera or self.Camera
	local focus = camera and camera.Focus.Position or targetCFrame.Position
	return (focus - targetCFrame.Position).Magnitude > self.CullDistance
end

function EntityPresentationController:_updateVisuals(deltaTime)
	for runtimeId, runtime in pairs(self.Runtimes) do
		runtime.AuthoritativeModel = runtime.AuthoritativeModel or self:_resolveAuthoritativeModel(runtimeId)
		if runtime.AuthoritativeModel then
			self:_setAuthoritativeModelHidden(runtime.AuthoritativeModel, true)
		end

		local serverCFrame = runtime.Folder:GetAttribute(EntityPresentationConstants.CFrameAttribute)
		if typeof(serverCFrame) ~= "CFrame" then
			self:_destroyVisualRuntime(runtime)
			continue
		end

		local targetCFrame = self:_toPresentationCFrame(runtime, serverCFrame)

		if self:_shouldCullRuntime(runtime) then
			self:_destroyVisualRuntime(runtime)
			continue
		end

		local visualModel = runtime.VisualModel or self:_createVisualModel(runtime)
		if not visualModel then
			continue
		end

		if visualModel.Parent ~= self.VisualsFolder then
			visualModel.Parent = self.VisualsFolder
		end

		local desiredVisualCFrame = targetCFrame
		local liveCFrame = visualModel:GetPivot()
		local currentAuthoritativeDelta = (liveCFrame.Position - targetCFrame.Position).Magnitude
		if currentAuthoritativeDelta >= EntityPresentationConstants.ServerHardSnapDistance then
			_zeroAssemblyVelocities(visualModel)
			visualModel:PivotTo(targetCFrame)
			runtime.CurrentCFrame = targetCFrame
			continue
		elseif currentAuthoritativeDelta >= EntityPresentationConstants.ServerCorrectionDeadzone then
			local correctionAlpha = 1 - math.exp(-EntityPresentationConstants.ServerCorrectionSpeed * math.max(deltaTime, 0))
			desiredVisualCFrame = desiredVisualCFrame:Lerp(targetCFrame, correctionAlpha)
		end

		local currentCFrame = runtime.Humanoid and liveCFrame or (runtime.CurrentCFrame or liveCFrame)
		if not runtime.CurrentCFrame or (currentCFrame.Position - targetCFrame.Position).Magnitude >= self.SnapDistance then
			_zeroAssemblyVelocities(visualModel)
			visualModel:PivotTo(targetCFrame)
			runtime.CurrentCFrame = targetCFrame
		else
			local alpha = 1 - math.exp(-self.InterpolationSpeed * math.max(deltaTime, 0))
			local nextCFrame = currentCFrame:Lerp(desiredVisualCFrame, alpha)
			visualModel:PivotTo(nextCFrame)
			runtime.CurrentCFrame = nextCFrame
		end

		self:_updateAnimation(runtime)
	end
end

return EntityPresentationController
