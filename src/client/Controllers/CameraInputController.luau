local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local PerspectiveMode = require(ReplicatedStorage.Shared.Enums.PerspectiveMode)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local FirearmAim = require(ReplicatedStorage.Shared.Utility.FirearmAim)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)

local CameraInputController = {}
CameraInputController.Name = "CameraInputController"
CameraInputController.Dependencies = {
	"RoundController",
	"DevMenuController",
	"ContextController",
	"CombatController",
}

local FREE_MOUSE_ACTION = "CameraInputController.FreeMouse"
local CAMERA_BIND_NAME = "CameraInputController.UpdateCamera"
local CAMERA_SENSITIVITY = 0.0056
local CAMERA_PITCH_LIMIT = math.rad(75)
local CAMERA_DISTANCE = 14
local CAMERA_HEIGHT = 2.45
local CAMERA_SHOULDER_OFFSET = 2.15
local CAMERA_FOCUS_FORWARD = 2.4
local CAMERA_FIELD_OF_VIEW = 70
local FIRST_PERSON_HEAD_OFFSET = Vector3.new(0, 0.55, 0)
local FIRST_PERSON_FOCUS_DISTANCE = 1.5

function CameraInputController:Init()
	self.FreeMouseHeld = false
	self.IsLocked = false
	self.IsUsingCustomCamera = false
	self.Yaw = 0
	self.Pitch = math.rad(-8)
	self.ActiveCameraCue = nil
	self.DefaultFieldOfView = CAMERA_FIELD_OF_VIEW
	self.CurrentFieldOfView = CAMERA_FIELD_OF_VIEW
	self.CurrentCameraDistance = CAMERA_DISTANCE
	self.CurrentShoulderOffset = CAMERA_SHOULDER_OFFSET
	self.CurrentFocusForward = CAMERA_FOCUS_FORWARD
	self.RecoilPitchOffset = 0
	self.RecoilYawOffset = 0
	self.RecoilRecoverySpeed = 10
	self.PerspectiveMode = PerspectiveMode.ThirdPerson
end

function CameraInputController:Start()
	self.PlayCutsceneRemote = self.World.Remotes:WaitForChild(RemoteNames.PlayCutscene)
	self.DefaultFieldOfView = self.World.Camera.FieldOfView
	self.CurrentFieldOfView = self.DefaultFieldOfView

	ContextActionService:BindActionAtPriority(
		FREE_MOUSE_ACTION,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self.FreeMouseHeld = true
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				self.FreeMouseHeld = false
			end

			self:_applyCameraMode()
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftAlt
	)

	RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		self:_update(deltaTime)
	end)

	self.PlayCutsceneRemote.OnClientEvent:Connect(function(payload)
		self:_handleCameraCue(payload)
	end)

	DebugLog:Log("ClientMovement", "[CameraInputController] Started")
end

function CameraInputController:_update(deltaTime)
	if self:_updateCameraCue() then
		return
	end

	local shouldLock = self:_shouldLockMouse()
	self:_applyCameraMode(shouldLock)
	if shouldLock then
		self:_updateCustomCamera(deltaTime)
	end
end

function CameraInputController:GetPerspectiveMode()
	return self.PerspectiveMode
end

function CameraInputController:IsFirstPerson()
	return self.PerspectiveMode == PerspectiveMode.FirstPerson
end

function CameraInputController:TogglePerspective()
	if self.PerspectiveMode == PerspectiveMode.FirstPerson then
		self.PerspectiveMode = PerspectiveMode.ThirdPerson
	else
		self.PerspectiveMode = PerspectiveMode.FirstPerson
	end
end

function CameraInputController:_resolveCueTarget(targetNames)
	for _, targetName in ipairs(targetNames or {}) do
		local target = Workspace:FindFirstChild(targetName, true)
		if target then
			if target:IsA("BasePart") then
				return target.CFrame.Position
			end

			if target:IsA("Model") then
				local adornee = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart")
				if adornee then
					return adornee.Position
				end
			end
		end
	end

	return nil
end

function CameraInputController:_handleCameraCue(payload)
	if type(payload) ~= "table" or payload.Type ~= "FocusTarget" then
		return
	end

	local focusPosition = self:_resolveCueTarget(payload.TargetNames)
	if not focusPosition then
		return
	end

	local cameraOffset = payload.CameraOffset or {}
	local lookOffset = payload.LookOffset or {}
	local currentCFrame = self.World.Camera.CFrame
	local targetLookPosition = focusPosition + Vector3.new(
		tonumber(lookOffset.X) or 0,
		tonumber(lookOffset.Y) or 0,
		tonumber(lookOffset.Z) or 0
	)
	local targetCameraPosition = focusPosition + Vector3.new(
		tonumber(cameraOffset.X) or 0,
		tonumber(cameraOffset.Y) or 0,
		tonumber(cameraOffset.Z) or 0
	)

	self.ActiveCameraCue = {
		StartedAt = os.clock(),
		TweenTime = math.max(0.01, tonumber(payload.TweenTime) or 0.35),
		ExpiresAt = os.clock() + math.max(0.1, tonumber(payload.Duration) or 1.2),
		FromCFrame = currentCFrame,
		TargetCFrame = CFrame.lookAt(targetCameraPosition, targetLookPosition),
	}
end

function CameraInputController:_updateCameraCue()
	local cue = self.ActiveCameraCue
	if not cue then
		return false
	end

	local now = os.clock()
	if now >= cue.ExpiresAt then
		self.ActiveCameraCue = nil
		self:_applyCameraMode(self:_shouldLockMouse())
		return false
	end

	local alpha = math.clamp((now - cue.StartedAt) / cue.TweenTime, 0, 1)
	self.World.Camera.CameraType = Enum.CameraType.Scriptable
	self.World.Camera.CFrame = cue.FromCFrame:Lerp(cue.TargetCFrame, alpha)
	self.World.Camera.FieldOfView = self.DefaultFieldOfView
	self.IsUsingCustomCamera = false
	self.IsLocked = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	return true
end

function CameraInputController:_shouldLockMouse()
	if self.FreeMouseHeld then
		return false
	end

	if UserInputService:GetFocusedTextBox() then
		return false
	end

	if self.DevMenuController and self.DevMenuController:IsVisible() then
		return false
	end

	local contextSnapshot = self.ContextController and self.ContextController:GetSnapshot() or {}
	if contextSnapshot.InventoryOpen or contextSnapshot.RadialMenuOpen then
		return false
	end

	local roundState = self.RoundController and self.RoundController:GetState() or nil
	local phase = roundState and roundState.Phase or "Unknown"
	if not WorldModeResolver.IsWeaponLab() and phase ~= GamePhase.Preparation and phase ~= GamePhase.Reception then
		return false
	end

	local character = self.World:GetCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end

	return true
end

function CameraInputController:_applyCameraMode(shouldLock)
	shouldLock = shouldLock == true
	local camera = self.World.Camera
	local character = self.World:GetCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if self.IsLocked == shouldLock and self.IsUsingCustomCamera == shouldLock then
		return
	end

	self.IsLocked = shouldLock
	UserInputService.MouseBehavior = shouldLock and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not shouldLock

	if shouldLock then
		self:_syncAnglesFromCamera()
		camera.CameraType = Enum.CameraType.Scriptable
		self.IsUsingCustomCamera = true
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = self.DefaultFieldOfView
		self.CurrentFieldOfView = self.DefaultFieldOfView
		self.CurrentCameraDistance = CAMERA_DISTANCE
		self.CurrentShoulderOffset = CAMERA_SHOULDER_OFFSET
		self.CurrentFocusForward = CAMERA_FOCUS_FORWARD
		if humanoid then
			camera.CameraSubject = humanoid
		end
		self.IsUsingCustomCamera = false
	end
end

function CameraInputController:_syncAnglesFromCamera()
	local lookVector = self.World.Camera.CFrame.LookVector
	self.Yaw = math.atan2(-lookVector.X, -lookVector.Z)
	self.Pitch = math.clamp(math.asin(lookVector.Y), -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)
end

function CameraInputController:_getFirearmHandlingState()
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	if not combatState or combatState.WeaponKind ~= "Firearm" then
		return nil, combatState, self.CombatController and self.CombatController:GetEquippedDefinition() or nil
	end

	return FirearmAim.GetHandlingData(WeaponDefinitions[combatState.EquippedWeaponId]), combatState, WeaponDefinitions[combatState.EquippedWeaponId]
end

function CameraInputController:AddFirearmKick(kickPitch, kickYaw, recoilRecovery)
	self.RecoilPitchOffset += math.rad(tonumber(kickPitch) or 0)
	local yawMagnitude = math.rad(tonumber(kickYaw) or 0)
	if yawMagnitude > 0 then
		local direction = math.random(0, 1) == 0 and -1 or 1
		self.RecoilYawOffset += yawMagnitude * direction
	end
	if tonumber(recoilRecovery) and recoilRecovery > 0 then
		self.RecoilRecoverySpeed = recoilRecovery
	end
end

function CameraInputController:_updateCustomCamera(deltaTime)
	local character = self.World:GetCharacter()
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local delta = UserInputService:GetMouseDelta()
	self.Yaw -= delta.X * CAMERA_SENSITIVITY
	self.Pitch = math.clamp(self.Pitch - delta.Y * CAMERA_SENSITIVITY, -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)

	local handling, combatState, equippedDefinition = self:_getFirearmHandlingState()
	local isAimingFirearm = handling ~= nil and combatState and combatState.IsAiming == true
	local isFirstPerson = self:IsFirstPerson()
	local targetDistance = isAimingFirearm and handling.AimCameraDistance or CAMERA_DISTANCE
	local targetShoulderOffset = isAimingFirearm and handling.AimShoulderOffset or CAMERA_SHOULDER_OFFSET
	local targetFocusForward = isAimingFirearm and handling.AimFocusForward or CAMERA_FOCUS_FORWARD
	local targetFieldOfView = isAimingFirearm and handling.AimFov or self.DefaultFieldOfView
	local blendSpeed = isAimingFirearm and 12 or 9

	if isFirstPerson then
		targetDistance = 0
		targetShoulderOffset = 0
		targetFocusForward = FIRST_PERSON_FOCUS_DISTANCE
		targetFieldOfView = isAimingFirearm
			and (handling.FirstPersonAimFov or handling.AimFov or self.DefaultFieldOfView)
			or ((equippedDefinition and equippedDefinition.FirstPersonFov) or (handling and handling.FirstPersonFov) or self.DefaultFieldOfView)
	end

	self.CurrentCameraDistance += (targetDistance - self.CurrentCameraDistance) * math.clamp(deltaTime * blendSpeed, 0, 1)
	self.CurrentShoulderOffset += (targetShoulderOffset - self.CurrentShoulderOffset) * math.clamp(deltaTime * blendSpeed, 0, 1)
	self.CurrentFocusForward += (targetFocusForward - self.CurrentFocusForward) * math.clamp(deltaTime * blendSpeed, 0, 1)
	self.CurrentFieldOfView += (targetFieldOfView - self.CurrentFieldOfView) * math.clamp(deltaTime * blendSpeed, 0, 1)
	self.RecoilPitchOffset += (0 - self.RecoilPitchOffset) * math.clamp(deltaTime * self.RecoilRecoverySpeed, 0, 1)
	self.RecoilYawOffset += (0 - self.RecoilYawOffset) * math.clamp(deltaTime * self.RecoilRecoverySpeed, 0, 1)

	local yawCFrame = CFrame.Angles(0, self.Yaw, 0)
	local pitchCFrame = CFrame.Angles(
		math.clamp(self.Pitch + self.RecoilPitchOffset, -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT),
		0,
		0
	)
	local recoilYawCFrame = CFrame.Angles(0, self.RecoilYawOffset, 0)
	local lookCFrame = yawCFrame * recoilYawCFrame * pitchCFrame
	local lookVector = lookCFrame.LookVector
	local rightVector = yawCFrame.RightVector

	local focusOrigin = rootPart.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
	local cameraPosition = nil
	local focusPoint = nil
	if isFirstPerson then
		local head = character:FindFirstChild("Head")
		local headPosition = head and head.Position or (rootPart.Position + Vector3.new(0, 1.55, 0))
		cameraPosition = headPosition + (rightVector * FIRST_PERSON_HEAD_OFFSET.X) + Vector3.new(0, FIRST_PERSON_HEAD_OFFSET.Y, 0)
		focusPoint = cameraPosition + (lookVector * self.CurrentFocusForward)
	else
		focusPoint = focusOrigin + (lookVector * self.CurrentFocusForward)
		cameraPosition = focusPoint - (lookVector * self.CurrentCameraDistance) + (rightVector * self.CurrentShoulderOffset)
	end

	self.World.Camera.CFrame = CFrame.lookAt(cameraPosition, focusPoint)
	self.World.Camera.FieldOfView = self.CurrentFieldOfView
end

return CameraInputController
