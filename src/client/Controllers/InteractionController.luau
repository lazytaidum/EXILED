local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractionController = {}
InteractionController.Name = "InteractionController"

local function ensureInteractionUI(playerGui)
	local screenGui = playerGui:FindFirstChild("InteractionUI")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "InteractionUI"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = playerGui
	end

	local container = screenGui:FindFirstChild("Container")
	if not container then
		container = Instance.new("Frame")
		container.Name = "Container"
		container.AnchorPoint = Vector2.new(0.5, 1)
		container.Position = UDim2.new(0.5, 0, 1, -70)
		container.Size = UDim2.new(0, 340, 0, 66)
		container.BackgroundColor3 = Color3.fromRGB(18, 23, 31)
		container.BackgroundTransparency = 0.15
		container.Parent = screenGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = container
	end

	local label = container:FindFirstChild("Label")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 16, 0, 10)
		label.Size = UDim2.new(1, -32, 0, 18)
		label.Font = Enum.Font.GothamMedium
		label.Text = "Interacting..."
		label.TextColor3 = Color3.fromRGB(238, 243, 247)
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = container
	end

	local barBackground = container:FindFirstChild("BarBackground")
	if not barBackground then
		barBackground = Instance.new("Frame")
		barBackground.Name = "BarBackground"
		barBackground.Position = UDim2.new(0, 16, 0, 38)
		barBackground.Size = UDim2.new(1, -32, 0, 14)
		barBackground.BackgroundColor3 = Color3.fromRGB(41, 51, 66)
		barBackground.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = barBackground
	end

	local barFill = barBackground:FindFirstChild("BarFill")
	if not barFill then
		barFill = Instance.new("Frame")
		barFill.Name = "BarFill"
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(87, 197, 182)
		barFill.Parent = barBackground

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = barFill
	end

	return screenGui, container, barFill, label
end

function InteractionController:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
<<<<<<< HEAD
	
	local screenGui, container, barFill, label = ensureInteractionUI(self.PlayerGui)
	
	self.UI = {
		Root = screenGui,
		Container = container,
		Bar = barFill,
		Label = label,
	}
	
=======
>>>>>>> 810c075b2889537cc9adaee092fa1a3c8f989cab
	self.Remote = self.Shared.Remotes:WaitForChild(RemoteNames.InteractionStateChanged)
end

function InteractionController:Start()
	self:_createUi()
	self.UI.Root.Enabled = false
	
	self.Remote.OnClientEvent:Connect(function(data)
		self:HandleInteractionUpdate(data)
	end)
	
	DebugLog:Log("ClientInteraction", "[InteractionController] Started")
end

function InteractionController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InteractionUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -18)
	container.Size = UDim2.new(0, 420, 0, 58)
	container.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	container.BackgroundTransparency = 0.08
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 16, 0, 8)
	label.Size = UDim2.new(1, -32, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.Text = "Repairing..."
	label.Parent = container

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 16, 0, 25)
	subLabel.Size = UDim2.new(1, -32, 0, 12)
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = 11
	subLabel.TextColor3 = Color3.fromRGB(190, 194, 206)
	subLabel.Text = "Hold to continue"
	subLabel.Parent = container

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.new(0, 16, 1, -12)
	barBackground.Size = UDim2.new(1, -32, 0, 6)
	barBackground.BackgroundColor3 = Color3.fromRGB(48, 51, 60)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBackground

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	self.UI = {
		Root = screenGui,
		Container = container,
		Bar = barFill,
		Label = label,
		SubLabel = subLabel,
	}
end

function InteractionController:HandleInteractionUpdate(data)
	DebugLog:Log("ClientInteraction", "[InteractionController] Received interaction state:", data.State)

	if data.State == "Start" then
		self.UI.Root.Enabled = true
		self.UI.Label.Text = data.Target or "Interacting..."
<<<<<<< HEAD
=======
		if string.find(string.lower(self.UI.Label.Text), "hazard", 1, true) or string.find(string.lower(self.UI.Label.Text), "log", 1, true) then
			self.UI.SubLabel.Text = "Hold to trigger"
		else
			self.UI.SubLabel.Text = "Hold to continue"
		end
>>>>>>> 810c075b2889537cc9adaee092fa1a3c8f989cab
		self.UI.Bar.Size = UDim2.new(0, 0, 1, 0)
		
	elseif data.State == "Update" then
		local maxValue = data.Max or 1
		local progressValue = data.Progress or 0
		local percent = math.clamp(progressValue / maxValue, 0, 1)
		self.UI.Bar.Size = UDim2.new(percent, 0, 1, 0)
	
	elseif data.State == "Stop" then
		self.UI.Root.Enabled = false
		
	elseif data.State == "Complete" then
		self.UI.SubLabel.Text = "Complete"
		self.UI.Bar.Size = UDim2.new(1, 0, 1, 0)
		task.delay(0.3, function()
			self.UI.Root.Enabled = false
		end)
	end
end

return InteractionController
