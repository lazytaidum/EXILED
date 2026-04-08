local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local BreathHoldController = {}
BreathHoldController.Name = "BreathHoldController"

function BreathHoldController:Init()
	self.Active = false
	self.IsHolding = false
	self.RemainingDuration = 0
	self.Progress = 0
	self.Remote = self.World.Remotes:WaitForChild(RemoteNames.BreathHoldStateChanged)
	self.RequestRemote = self.World.Remotes:WaitForChild(RemoteNames.RequestBreathHoldState)
end

function BreathHoldController:Start()
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(payload)
		self:_handleRemote(payload)
	end)

	task.spawn(function()
		while true do
			self:_updateUi(0.05)
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientInteraction", "[BreathHoldController] Started")
end

function BreathHoldController:IsActive()
	return self.Active
end

function BreathHoldController:SetHolding(isHolding)
	if not self.Active or self.IsHolding == isHolding then
		return
	end

	self.IsHolding = isHolding
	self.RequestRemote:FireServer(isHolding)
	self:_refreshVisuals()
end

function BreathHoldController:_handleRemote(payload)
	local state = payload and payload.State
	if state == "Start" or state == "Update" then
		self.Active = true
		self.RemainingDuration = payload.Duration or self.RemainingDuration
		self.Progress = payload.Progress or self.Progress
		self.UI.Root.Enabled = true
		self.UI.Label.Text = payload.Prompt or "Hold your breath"
		self.UI.SubLabel.Text = payload.SubPrompt or "Stay silent"
		self.UI.KeyLabel.Text = payload.RequiredKey or "SPACE"
		self:_refreshVisuals()
	else
		self.Active = false
		self.IsHolding = false
		self.RemainingDuration = 0
		self.Progress = 0
		self.UI.Root.Enabled = false
	end
end

function BreathHoldController:_updateUi(deltaTime)
	if not self.Active then
		return
	end

	self.RemainingDuration = math.max(0, self.RemainingDuration - deltaTime)
	self.UI.Duration.Text = string.format("%.1fs", self.RemainingDuration)
	local urgent = self.RemainingDuration <= 1
	self.UI.Duration.TextColor3 = urgent and Color3.fromRGB(228, 112, 112) or Color3.fromRGB(220, 230, 236)
end

function BreathHoldController:_refreshVisuals()
	local ratio = math.clamp(self.Progress or 0, 0, 1)
	self.UI.Bar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.ProgressLabel.Text = self.IsHolding and "Holding" or "Release = fail"
	self.UI.KeyLabel.BackgroundColor3 = self.IsHolding and Color3.fromRGB(132, 183, 150) or Color3.fromRGB(61, 72, 84)
	self.UI.KeyLabel.TextColor3 = self.IsHolding and Color3.fromRGB(18, 19, 24) or Color3.fromRGB(220, 230, 236)
end

function BreathHoldController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BreathHoldUI"
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.World.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.32)
	container.Position = UDim2.new(0.5, 0, 0.32, 0)
	container.Size = UDim2.new(0, 340, 0, 96)
	container.BackgroundColor3 = Color3.fromRGB(14, 18, 24)
	container.BackgroundTransparency = 0.08
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.new(0, 14, 0, 10)
	label.Size = UDim2.new(1, -28, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(220, 230, 236)
	label.TextSize = 17
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "Hold your breath"
	label.Parent = container

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Position = UDim2.new(0, 14, 0, 32)
	subLabel.Size = UDim2.new(1, -110, 0, 18)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextColor3 = Color3.fromRGB(162, 176, 187)
	subLabel.TextSize = 12
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = "Jiangshi is listening for breath"
	subLabel.Parent = container

	local duration = Instance.new("TextLabel")
	duration.Name = "Duration"
	duration.Position = UDim2.new(1, -78, 0, 12)
	duration.Size = UDim2.new(0, 64, 0, 20)
	duration.BackgroundTransparency = 1
	duration.Font = Enum.Font.GothamBold
	duration.TextColor3 = Color3.fromRGB(220, 230, 236)
	duration.TextSize = 14
	duration.TextXAlignment = Enum.TextXAlignment.Right
	duration.Text = "0.0s"
	duration.Parent = container

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Position = UDim2.new(0, 14, 0, 58)
	keyLabel.Size = UDim2.new(0, 84, 0, 26)
	keyLabel.BackgroundColor3 = Color3.fromRGB(61, 72, 84)
	keyLabel.BorderSizePixel = 0
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextColor3 = Color3.fromRGB(220, 230, 236)
	keyLabel.TextSize = 15
	keyLabel.Text = "SPACE"
	keyLabel.Parent = container

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 8)
	keyCorner.Parent = keyLabel

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Position = UDim2.new(1, -116, 0, 60)
	progressLabel.Size = UDim2.new(0, 102, 0, 18)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextColor3 = Color3.fromRGB(188, 210, 218)
	progressLabel.TextSize = 12
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = "Release = fail"
	progressLabel.Parent = container

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.new(0, 108, 0, 64)
	barBackground.Size = UDim2.new(1, -122, 0, 10)
	barBackground.BackgroundColor3 = Color3.fromRGB(44, 53, 63)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = barBackground

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(132, 183, 150)
	bar.BorderSizePixel = 0
	bar.Parent = barBackground

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = bar

	self.UI = {
		Root = screenGui,
		Label = label,
		SubLabel = subLabel,
		Duration = duration,
		KeyLabel = keyLabel,
		ProgressLabel = progressLabel,
		Bar = bar,
	}
end

return BreathHoldController
