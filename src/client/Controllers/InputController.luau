local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local ActionToken = require(ReplicatedStorage.Shared.Enums.ActionToken)
local DefaultKeybinds = require(ReplicatedStorage.Shared.Data.DefaultKeybinds)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InputController = {}
InputController.Name = "InputController"
InputController.Dependencies = {
	"QTEController",
	"BreathHoldController",
	"RemnantController",
	"CameraInputController",
}

function InputController:Init(controllers)
	self.Controllers = controllers
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.RemotesFolder = self.Shared:WaitForChild("Remotes")
	self.RequestInteractRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestInteract)
	self.RequestMovementStateRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestMovementState)
	self.RequestBreathHoldStateRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestBreathHoldState)
	self.RequestRemnantAbilityRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestRemnantAbility)
	self.Keybinds = DefaultKeybinds.Keyboard or {}
end

function InputController:Start()
	self.IsHoldingInteract = false
	
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if self:_shouldIgnoreInput(input, gameProcessedEvent) then
			return
		end

<<<<<<< HEAD
		if self.Controllers and self.Controllers.WeaponLabController and self.Controllers.WeaponLabController:IsCapturingInput() then
			return
		end
		
		if input.KeyCode == Enum.KeyCode.Space then
			self.IsHoldingInteract = true
			DebugLog:Log("ClientInteraction", "[InputController] Interact key pressed")
			self:RequestInteractStart()
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if self.Controllers and self.Controllers.WeaponLabController and self.Controllers.WeaponLabController:IsCapturingInput() then
			return
		end

		if input.KeyCode == Enum.KeyCode.Space then
			self.IsHoldingInteract = false
			DebugLog:Log("ClientInteraction", "[InputController] Interact key released")
			self:RequestInteractStop()
=======
		self:_handleKeyboardInput(input.KeyCode, true)
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if self:_shouldIgnoreInput(input, gameProcessedEvent) then
			return
>>>>>>> 810c075b2889537cc9adaee092fa1a3c8f989cab
		end

		self:_handleKeyboardInput(input.KeyCode, false)
	end)
	
	DebugLog:Log("ClientInteraction", "[InputController] Started")
end

function InputController:_shouldIgnoreInput(input, gameProcessedEvent)
	if not input or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return true
	end

	if UserInputService:GetFocusedTextBox() then
		return true
	end

	if not gameProcessedEvent then
		return false
	end

	local keybinds = self.Keybinds[input.KeyCode.Name]
	if not keybinds then
		return true
	end

	for _, actionToken in ipairs(keybinds) do
		if actionToken == ActionToken.Sprint or actionToken == ActionToken.Crouch then
			return false
		end

		if actionToken == ActionToken.PrimaryContextAction then
			local hasPrompt = (self.QTEController and self.QTEController:IsActive())
				or (self.BreathHoldController and self.BreathHoldController:RequiresHoldInput())
			if hasPrompt then
				return false
			end
		end
	end

	return true
end

function InputController:_handleKeyboardInput(keyCode, isPressed)
	if not keyCode or keyCode == Enum.KeyCode.Unknown then
		return
	end

	local actionTokens = self.Keybinds[keyCode.Name]
	if not actionTokens then
		return
	end

	for _, actionToken in ipairs(actionTokens) do
		if actionToken == ActionToken.PrimaryContextAction then
			if self.QTEController and self.QTEController:IsActive() then
				self.QTEController:HandleKeyboardInput(keyCode, isPressed)
				return
			end

			if self.BreathHoldController and self.BreathHoldController:RequiresHoldInput() then
				DebugLog:Log("ClientInteraction", string.format("[InputController] Breath hold %s", isPressed and "started" or "ended"))
				self.BreathHoldController:SetHolding(isPressed)
				return
			end

			if isPressed then
				self.IsHoldingInteract = true
				DebugLog:Log("ClientInteraction", "[InputController] Interact key pressed")
				self:RequestInteractStart()
			else
				self.IsHoldingInteract = false
				DebugLog:Log("ClientInteraction", "[InputController] Interact key released")
				self:RequestInteractStop()
			end
		elseif actionToken == ActionToken.Sprint then
			DebugLog:Log("ClientMovement", string.format("[InputController] Sprint key %s", isPressed and "pressed" or "released"))
			self:RequestMovementState(ActionName.Sprint, isPressed)
		elseif actionToken == ActionToken.Crouch then
			DebugLog:Log("ClientMovement", string.format("[InputController] Crouch key %s", isPressed and "pressed" or "released"))
			self:RequestMovementState(ActionName.Crouch, isPressed)
		elseif actionToken == ActionToken.Ability1 and isPressed then
			DebugLog:Log("ClientRemnant", "[InputController] Ability1 pressed")
			if self.RemnantController then
				self.RemnantController:TriggerAbility("Ability1")
			else
				self.RequestRemnantAbilityRemote:FireServer("Ability1")
			end
		elseif actionToken == ActionToken.Ability2 and isPressed then
			DebugLog:Log("ClientRemnant", "[InputController] Ability2 pressed")
			if self.RemnantController then
				self.RemnantController:TriggerAbility("Ability2")
			else
				self.RequestRemnantAbilityRemote:FireServer("Ability2")
			end
		elseif actionToken == ActionToken.Ability3 and isPressed then
			DebugLog:Log("ClientRemnant", "[InputController] Ability3 pressed")
			if self.RemnantController then
				self.RemnantController:TriggerAbility("Ability3")
			else
				self.RequestRemnantAbilityRemote:FireServer("Ability3")
			end
		elseif actionToken == ActionToken.TogglePerspective and isPressed then
			DebugLog:Log("ClientMovement", "[InputController] Toggle perspective pressed")
			if self.CameraInputController then
				self.CameraInputController:TogglePerspective()
			end
		end
	end
end

function InputController:RequestInteractStart()
	DebugLog:Log("ClientInteraction", "[InputController] Sending interact start")
	self.RequestInteractRemote:FireServer(true)
end

function InputController:RequestInteractStop()
	DebugLog:Log("ClientInteraction", "[InputController] Sending interact stop")
	self.RequestInteractRemote:FireServer(false)
end

function InputController:RequestMovementState(actionName, isActive)
	DebugLog:Log("ClientMovement", string.format("[InputController] Sending %s=%s", actionName, tostring(isActive)))
	self.RequestMovementStateRemote:FireServer(actionName, isActive)
end

function InputController:RequestBreathHoldState(isHolding)
	self.RequestBreathHoldStateRemote:FireServer(isHolding)
end

return InputController
