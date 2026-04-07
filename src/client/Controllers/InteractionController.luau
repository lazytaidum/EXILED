local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractionController = {}
InteractionController.Name = "InteractionController"

function InteractionController:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
	
	local screenGui = self.PlayerGui:WaitForChild("InteractionUI")
	local container = screenGui:WaitForChild("Container")
	
	self.UI = {
		Root = screenGui,
		Container = container,
		Bar = container.BarBackground.BarFill,
		Label = container.Label,
	}
	
	self.Remote = self.Shared.Remotes:WaitForChild(RemoteNames.InteractionStateChanged)
end

function InteractionController:Start()
	self.UI.Root.Enabled = false
	
	self.Remote.OnClientEvent:Connect(function(data)
		self:HandleInteractionUpdate(data)
	end)
	
	DebugLog:Log("ClientInteraction", "[InteractionController] Started")
end

function InteractionController:HandleInteractionUpdate(data)
	DebugLog:Log("ClientInteraction", "[InteractionController] Received interaction state:", data.State)

	if data.State == "Start" then
		self.UI.Root.Enabled = true
		self.UI.Label.Text = data.Target or "Interacting..."
		
	elseif data.State == "Update" then
		local maxValue = data.Max or 1
		local progressValue = data.Progress or 0
		local percent = math.clamp(progressValue / maxValue, 0, 1)
		self.UI.Bar.Size = UDim2.new(percent, 0, 1, 0)
	
	elseif data.State == "Stop" then
		self.UI.Root.Enabled = false
		
	elseif data.State == "Complete" then
		self.UI.Bar.Size = UDim2.new(1, 0, 1, 0)
		task.delay(0.3, function()
			self.UI.Root.Enabled = false
		end)
	end
end

return InteractionController
