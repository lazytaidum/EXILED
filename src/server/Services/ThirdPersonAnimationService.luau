local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local RemnantDefinitions = require(ReplicatedStorage.Shared.Data.RemnantDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ThirdPersonAnimationService = {}
ThirdPersonAnimationService.Name = "ThirdPersonAnimationService"
ThirdPersonAnimationService.Dependencies = {
	"CharacterService",
	"PlayerService",
	"RemnantService",
}

local LOOP_ACTIONS = {
	Idle = true,
	Aim = true,
}

local ACTION_TRACK_PRIORITIES = {
	Equip = Enum.AnimationPriority.Action2,
	Idle = Enum.AnimationPriority.Movement,
	Aim = Enum.AnimationPriority.Action,
	Fire = Enum.AnimationPriority.Action2,
	Reload = Enum.AnimationPriority.Action2,
}

local MOVEMENT_TRACK_PRIORITIES = {
	Idle = Enum.AnimationPriority.Movement,
	Walk = Enum.AnimationPriority.Movement,
	Run = Enum.AnimationPriority.Movement,
	CrouchIdle = Enum.AnimationPriority.Action,
	CrouchWalk = Enum.AnimationPriority.Action,
}

local MOVEMENT_LOOP_BLEND_TIME = 0.12

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

function ThirdPersonAnimationService:Init()
	self.RuntimeByPlayer = {}
	self.PreloadedAnimationIds = {}
end

function ThirdPersonAnimationService:_preloadAnimationIds(animationIds)
	if type(animationIds) ~= "table" then
		return
	end

	local animationsToPreload = {}
	for _, animationId in pairs(animationIds) do
		local normalizedId = _normalizeAnimationId(animationId)
		if normalizedId and not self.PreloadedAnimationIds[normalizedId] then
			local animation = Instance.new("Animation")
			animation.AnimationId = normalizedId
			table.insert(animationsToPreload, animation)
			self.PreloadedAnimationIds[normalizedId] = true
		end
	end

	if #animationsToPreload <= 0 then
		return
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(animationsToPreload)
	end)

	for _, animation in ipairs(animationsToPreload) do
		animation:Destroy()
	end

	if not ok then
		DebugLog:Log("Character", string.format("[ThirdPersonAnimationService] Failed to preload animations: %s", tostring(err)))
	end
end

function ThirdPersonAnimationService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:_clearPlayerRuntime(player)
	end)

	task.spawn(function()
		while true do
			for player, runtime in pairs(self.RuntimeByPlayer) do
				if runtime.CharacterModel and runtime.CharacterModel.Parent and runtime.Animator then
					self:_applyLoopState(player, runtime, runtime.CurrentCombatState)
				end
			end
			task.wait(0.1)
		end
	end)

	DebugLog:Log("Character", "[ThirdPersonAnimationService] Started")
end

function ThirdPersonAnimationService:_getRuntime(player)
	local runtime = self.RuntimeByPlayer[player]
	if runtime then
		return runtime
	end

	runtime = {
		Player = player,
		CharacterModel = nil,
		Humanoid = nil,
		Animator = nil,
		LoadedTracks = {},
		MovementTracks = {},
		LoadedWeaponId = nil,
		CurrentLoopAction = nil,
		CurrentMovementAction = nil,
		CurrentCombatState = nil,
		OneShotToken = 0,
		SkipNextEquip = false,
	}
	self.RuntimeByPlayer[player] = runtime
	return runtime
end

function ThirdPersonAnimationService:_clearTracks(runtime)
	if not runtime then
		return
	end

	runtime.OneShotToken += 1
	for _, track in pairs(runtime.LoadedTracks or {}) do
		if track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end

	runtime.LoadedTracks = {}
	runtime.LoadedWeaponId = nil
	runtime.CurrentLoopAction = nil
end

function ThirdPersonAnimationService:_clearMovementTracks(runtime)
	if not runtime then
		return
	end

	for _, track in pairs(runtime.MovementTracks or {}) do
		if track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end

	runtime.MovementTracks = {}
	runtime.CurrentMovementAction = nil
end

function ThirdPersonAnimationService:_clearPlayerRuntime(player)
	local runtime = self.RuntimeByPlayer[player]
	if not runtime then
		return
	end

	self:_clearTracks(runtime)
	self:_clearMovementTracks(runtime)
	self.RuntimeByPlayer[player] = nil
end

function ThirdPersonAnimationService:_resolveAnimatorFromModel(characterModel)
	if not characterModel or not characterModel.Parent then
		return nil, nil
	end

	local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil, nil
	end

	local torso = characterModel:FindFirstChild("Torso")
	local rightArm = characterModel:FindFirstChild("Right Arm")
	local leftArm = characterModel:FindFirstChild("Left Arm")
	if not torso or not rightArm or not leftArm then
		return nil, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return humanoid, animator
end

function ThirdPersonAnimationService:_bindCharacterRuntime(runtime, characterModel)
	self:_clearTracks(runtime)
	self:_clearMovementTracks(runtime)

	runtime.CharacterModel = characterModel
	runtime.Humanoid, runtime.Animator = self:_resolveAnimatorFromModel(characterModel)
	runtime.SkipNextEquip = true
end

function ThirdPersonAnimationService:_getRemnantDefinitionForPlayer(player)
	local playerState = self.RemnantService and self.RemnantService.PlayerStates and self.RemnantService.PlayerStates[player] or nil
	local remnantId = playerState and playerState.RemnantId or nil
	return remnantId and RemnantDefinitions[remnantId] or nil
end

function ThirdPersonAnimationService:_getWeaponDefinitionFromCombatState(combatState)
	if type(combatState) ~= "table" then
		return nil
	end

	local weaponId = combatState.EquippedWeaponId
	local definition = weaponId and WeaponDefinitions[weaponId] or nil
	if not definition or definition.Kind ~= "Firearm" then
		return nil
	end

	return definition
end

function ThirdPersonAnimationService:_loadTracks(runtime, weaponDefinition)
	self:_clearTracks(runtime)

	local animator = runtime and runtime.Animator
	local animationIds = weaponDefinition and weaponDefinition.ThirdPersonAnimationIds
	if not animator or type(animationIds) ~= "table" then
		return
	end

	self:_preloadAnimationIds(animationIds)

	for actionName, animationId in pairs(animationIds) do
		local normalizedId = _normalizeAnimationId(animationId)
		if normalizedId then
			local animation = Instance.new("Animation")
			animation.AnimationId = normalizedId

			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			animation:Destroy()

			if ok and track then
				track.Priority = ACTION_TRACK_PRIORITIES[actionName] or Enum.AnimationPriority.Action
				track.Looped = LOOP_ACTIONS[actionName] == true
				runtime.LoadedTracks[actionName] = track
			end
		end
	end

	runtime.LoadedWeaponId = weaponDefinition and weaponDefinition.Id or nil
end

function ThirdPersonAnimationService:_loadMovementTracks(player, runtime)
	self:_clearMovementTracks(runtime)

	local animator = runtime and runtime.Animator
	if not animator then
		return
	end

	local remnantDefinition = self:_getRemnantDefinitionForPlayer(player)
	local animationIds = remnantDefinition and remnantDefinition.ThirdPersonAnimationIds or nil
	local loadedTrackKeys = {}

	self:_preloadAnimationIds(animationIds)

	if type(animationIds) == "table" then
		for actionName, animationId in pairs(animationIds) do
			if MOVEMENT_TRACK_PRIORITIES[actionName] then
				local normalizedId = _normalizeAnimationId(animationId)
				if normalizedId then
					local animation = Instance.new("Animation")
					animation.AnimationId = normalizedId

					local ok, track = pcall(function()
						return animator:LoadAnimation(animation)
					end)

					animation:Destroy()

					if ok and track then
						track.Priority = MOVEMENT_TRACK_PRIORITIES[actionName]
						track.Looped = true
						runtime.MovementTracks[actionName] = track
						loadedTrackKeys[actionName] = true
					end
				end
			end
		end
	end

	local animationsFolder = runtime.CharacterModel and runtime.CharacterModel:FindFirstChild("Animations")
	if animationsFolder then
		for _, child in ipairs(animationsFolder:GetChildren()) do
			if child:IsA("Animation") and MOVEMENT_TRACK_PRIORITIES[child.Name] and not loadedTrackKeys[child.Name] then
				local ok, track = pcall(function()
					return animator:LoadAnimation(child)
				end)
				if ok and track then
					track.Priority = MOVEMENT_TRACK_PRIORITIES[child.Name]
					track.Looped = true
					runtime.MovementTracks[child.Name] = track
					loadedTrackKeys[child.Name] = true
				end
			end
		end
	end
end

function ThirdPersonAnimationService:_resolveDesiredLoopAction(runtime, combatState)
	if combatState and combatState.IsAiming == true and runtime.LoadedTracks.Aim then
		return "Aim"
	end

	if runtime.LoadedTracks.Idle then
		return "Idle"
	end

	return nil
end

function ThirdPersonAnimationService:_resolveDesiredMovementAction(player, runtime)
	local playerState = self.PlayerService and self.PlayerService:GetPlayerState(player) or nil
	local humanoid = runtime and runtime.Humanoid
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player) or nil
	if not humanoid or not playerState then
		return nil
	end

	local isMoving = humanoid.MoveDirection.Magnitude > 0.08
	if playerState.IsCrouching == true then
		if isMoving and runtime.MovementTracks.CrouchWalk then
			return "CrouchWalk"
		end

		if runtime.MovementTracks.CrouchIdle then
			return "CrouchIdle"
		end

		return nil
	end

	local isRunning = character and (character.IsSprinting == true or character.IsRunning == true)
	if isMoving and isRunning and runtime.MovementTracks.Run then
		return "Run"
	end

	if isMoving and runtime.MovementTracks.Walk then
		return "Walk"
	end

	if runtime.MovementTracks.Idle then
		return "Idle"
	end

	return nil
end

function ThirdPersonAnimationService:_stopLoopTracks(runtime)
	for loopActionName in pairs(LOOP_ACTIONS) do
		local track = runtime.LoadedTracks[loopActionName]
		if track and track.IsPlaying then
			track:Stop(0.08)
		end
	end
	runtime.CurrentLoopAction = nil
end

function ThirdPersonAnimationService:_stopMovementLoopTracks(runtime)
	for _, track in pairs(runtime.MovementTracks or {}) do
		if track and track.IsPlaying then
			track:Stop(MOVEMENT_LOOP_BLEND_TIME)
		end
	end
	runtime.CurrentMovementAction = nil
end

function ThirdPersonAnimationService:_applyLoopState(player, runtime, combatState)
	if combatState and combatState.IsAiming == true and runtime.LoadedTracks.Aim then
		self:_stopMovementLoopTracks(runtime)
		self:_playLoopAction(runtime, combatState)
		return
	end

	local desiredMovementAction = self:_resolveDesiredMovementAction(player, runtime)
	if desiredMovementAction then
		if runtime.CurrentMovementAction == desiredMovementAction then
			local currentTrack = runtime.MovementTracks[desiredMovementAction]
			if currentTrack and currentTrack.IsPlaying then
				return
			end
		end

		self:_stopLoopTracks(runtime)
		self:_stopMovementLoopTracks(runtime)

		local desiredMovementTrack = runtime.MovementTracks[desiredMovementAction]
		if desiredMovementTrack then
			runtime.CurrentMovementAction = desiredMovementAction
			desiredMovementTrack:Play(MOVEMENT_LOOP_BLEND_TIME, 1, 1)
		end
		return
	end

	self:_stopMovementLoopTracks(runtime)
	self:_stopLoopTracks(runtime)
end

function ThirdPersonAnimationService:_playLoopAction(runtime, combatState)
	local desiredAction = self:_resolveDesiredLoopAction(runtime, combatState)
	if not desiredAction then
		self:_stopLoopTracks(runtime)
		return
	end

	if runtime.CurrentLoopAction == desiredAction then
		local currentTrack = runtime.LoadedTracks[desiredAction]
		if currentTrack and currentTrack.IsPlaying then
			return
		end
	end

	self:_stopLoopTracks(runtime)

	local desiredTrack = runtime.LoadedTracks[desiredAction]
	if not desiredTrack then
		return
	end

	runtime.CurrentLoopAction = desiredAction
	desiredTrack:Play(0.12, 1, 1)
end

function ThirdPersonAnimationService:_playOneShot(runtime, actionName)
	local track = runtime.LoadedTracks[actionName]
	if not track then
		self:_applyLoopState(runtime.Player, runtime, runtime.CurrentCombatState)
		return
	end

	runtime.OneShotToken += 1
	local currentToken = runtime.OneShotToken

	self:_stopLoopTracks(runtime)
	self:_stopMovementLoopTracks(runtime)
	if track.IsPlaying then
		track:Stop(0.03)
	end
	track:Play(0.05, 1, 1)

	local stoppedConnection
	stoppedConnection = track.Stopped:Connect(function()
		if stoppedConnection then
			stoppedConnection:Disconnect()
			stoppedConnection = nil
		end

		if runtime.OneShotToken ~= currentToken then
			return
		end

		self:_applyLoopState(runtime.Player, runtime, runtime.CurrentCombatState)
	end)
end

function ThirdPersonAnimationService:_didWeaponFire(previousState, currentState)
	if type(previousState) ~= "table" or type(currentState) ~= "table" then
		return false
	end

	if previousState.EquippedWeaponId ~= currentState.EquippedWeaponId then
		return false
	end

	local previousAmmo = tonumber(previousState.CurrentAmmo)
	local currentAmmo = tonumber(currentState.CurrentAmmo)
	if not previousAmmo or not currentAmmo then
		return false
	end

	return currentAmmo < previousAmmo and currentState.IsReloading ~= true
end

function ThirdPersonAnimationService:_applyCombatState(player, previousState, currentState)
	local runtime = self:_getRuntime(player)
	runtime.Player = player
	runtime.CurrentCombatState = currentState

	local definition = self:_getWeaponDefinitionFromCombatState(currentState)
	if not definition then
		self:_clearTracks(runtime)
		return
	end

	if not runtime.CharacterModel or not runtime.CharacterModel.Parent or not runtime.Animator then
		local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player) or nil
		local characterModel = character and character.Model or nil
		if not characterModel then
			return
		end

		self:_bindCharacterRuntime(runtime, characterModel)
	end

	if not runtime.Animator then
		return
	end

	if next(runtime.MovementTracks or {}) == nil then
		self:_loadMovementTracks(player, runtime)
	end

	local weaponChanged = runtime.LoadedWeaponId ~= definition.Id
	if weaponChanged then
		self:_loadTracks(runtime, definition)
	end

	local shouldPlayEquip = weaponChanged
		and runtime.SkipNextEquip ~= true
		and type(previousState) == "table"
		and previousState.EquippedWeaponId ~= currentState.EquippedWeaponId

	runtime.SkipNextEquip = false

	if shouldPlayEquip then
		self:_playOneShot(runtime, "Equip")
		return
	end

	if currentState.IsReloading == true and not (previousState and previousState.IsReloading == true) then
		self:_playOneShot(runtime, "Reload")
		return
	end

	if self:_didWeaponFire(previousState, currentState) then
		self:_playOneShot(runtime, "Fire")
		return
	end

	self:_applyLoopState(player, runtime, currentState)
end

function ThirdPersonAnimationService:HandleCombatStateChanged(player, previousState, currentState)
	self:_applyCombatState(player, previousState, currentState)
end

function ThirdPersonAnimationService:HandleCharacterAdded(player, character)
	local runtime = self:_getRuntime(player)
	local characterModel = character and character.Model or character
	if not characterModel then
		return
	end

	self:_bindCharacterRuntime(runtime, characterModel)
	runtime.Player = player
	self:_loadMovementTracks(player, runtime)

	if runtime.CurrentCombatState then
		self:_applyCombatState(player, nil, runtime.CurrentCombatState)
	end
end

function ThirdPersonAnimationService:HandleCharacterRemoving(player, characterModel)
	local runtime = self.RuntimeByPlayer[player]
	if not runtime then
		return
	end

	if runtime.CharacterModel ~= characterModel then
		return
	end

	self:_clearTracks(runtime)
	self:_clearMovementTracks(runtime)
	runtime.CharacterModel = nil
	runtime.Humanoid = nil
	runtime.Animator = nil
	runtime.SkipNextEquip = true
end

return ThirdPersonAnimationService
