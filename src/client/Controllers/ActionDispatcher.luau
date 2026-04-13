local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ActionDispatcher = {}
ActionDispatcher.Name = "ActionDispatcher"

function ActionDispatcher:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.RemotesFolder = self.Shared:WaitForChild("Remotes")
	self.RequestInteractRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestInteract)
	self.LocalActionState = {
		Sprint = false,
		Crouch = false,
		Inventory = false,
		RadialMenu = false,
	}
end

function ActionDispatcher:Dispatch(actionName, phase)
	if actionName == ActionName.Interact then
		if phase == "Begin" then
			self.RequestInteractRemote:FireServer(true)
		elseif phase == "End" then
			self.RequestInteractRemote:FireServer(false)
		end
	elseif actionName == ActionName.Sprint then
		self.LocalActionState.Sprint = (phase == "Begin")
		DebugLog:Log("ClientInteraction", string.format("[ActionDispatcher] Sprint %s", self.LocalActionState.Sprint and "enabled" or "disabled"))
	elseif actionName == ActionName.Crouch then
		if phase == "Begin" then
			self.LocalActionState.Crouch = not self.LocalActionState.Crouch
			DebugLog:Log("ClientInteraction", string.format("[ActionDispatcher] Crouch %s", self.LocalActionState.Crouch and "enabled" or "disabled"))
		end
	elseif actionName == ActionName.Inventory then
		if phase == "Begin" then
			self.LocalActionState.Inventory = not self.LocalActionState.Inventory
			DebugLog:Log("ClientInteraction", string.format("[ActionDispatcher] Inventory %s", self.LocalActionState.Inventory and "enabled" or "disabled"))
		end
	elseif actionName == ActionName.RadialMenu then
		self.LocalActionState.RadialMenu = (phase == "Begin")
		DebugLog:Log("ClientInteraction", string.format("[ActionDispatcher] Radial menu %s", self.LocalActionState.RadialMenu and "enabled" or "disabled"))
	elseif phase == "Begin" then
		DebugLog:Log("ClientInteraction", string.format("[ActionDispatcher] %s triggered", tostring(actionName)))
	
	end
end

return ActionDispatcher
