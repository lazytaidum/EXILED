local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)

local InputController = {}
InputController.Name = "InputController"

function InputController:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.RemotesFolder = self.Shared:WaitForChild("Remotes")
	self.RequestInteractRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestInteract)
end

function InputController:Start()
	self.IsHoldingInteract = false
	
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		
		if input.KeyCode == Enum.KeyCode.Space then
			self.IsHoldingInteract = true
			self:RequestInteractStart()
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if input.KeyCode == Enum.KeyCode.Space then
			self.IsHoldingInteract = false
			self:RequestInteractStop()
		end
	end)
	
	print("[InputController] Started")
end

function InputController:RequestInteractStart()
	self.RequestInteractRemote:FireServer(true)
end

function InputController:RequestInteractStop()
	self.RequestInteractRemote:FireServer(false)
end

return InputController
