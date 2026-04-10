local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CameraInputController = {}
CameraInputController.Name = "CameraInputController"
CameraInputController.Dependencies = {
	"RoundController",
	"DevMenuController",
	"ContextController",
}

local FREE_MOUSE_ACTION = "CameraInputController.FreeMouse"
local CAMERA_BIND_NAME = "CameraInputController.UpdateCamera"
local CAMERA_SENSITIVITY = 0.0056
local CAMERA_PITCH_LIMIT = math.rad(75)
local CAMERA_DISTANCE = 14
local CAMERA_HEIGHT = 2.1
local CAMERA_SHOULDER_OFFSET = 1.75
local CAMERA_FOCUS_FORWARD = 2.4

function CameraInputController:Init()
	self.FreeMouseHeld = false
	self.IsLocked = false
	self.IsUsingCustomCamera = false
	self.Yaw = 0
	self.Pitch = math.rad(-8)
end

function CameraInputController:Start()
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

	DebugLog:Log("ClientMovement", "[CameraInputController] Started")
end

function CameraInputController:_update(_deltaTime)
	local shouldLock = self:_shouldLockMouse()
	self:_applyCameraMode(shouldLock)
	if shouldLock then
		self:_updateCustomCamera()
	end
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
	if phase ~= GamePhase.Preparation and phase ~= GamePhase.Reception then
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

function CameraInputController:_updateCustomCamera()
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

	local yawCFrame = CFrame.Angles(0, self.Yaw, 0)
	local pitchCFrame = CFrame.Angles(self.Pitch, 0, 0)
	local lookCFrame = yawCFrame * pitchCFrame
	local lookVector = lookCFrame.LookVector
	local rightVector = yawCFrame.RightVector

	local focusPoint = rootPart.Position + Vector3.new(0, CAMERA_HEIGHT, 0) + (lookVector * CAMERA_FOCUS_FORWARD)
	local cameraPosition = focusPoint - (lookVector * CAMERA_DISTANCE) + (rightVector * CAMERA_SHOULDER_OFFSET)

	self.World.Camera.CFrame = CFrame.lookAt(cameraPosition, focusPoint)
end

return CameraInputController
