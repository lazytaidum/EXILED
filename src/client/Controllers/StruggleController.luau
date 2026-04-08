local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StruggleController = {}
StruggleController.Name = "StruggleController"

function StruggleController:Init()
	self.Active = false
	self.Progress = 0
	self.MaxProgress = 1
	self.RemainingDuration = 0
	self.LastPressAt = 0
	self.Remote = self.World.Remotes:WaitForChild(RemoteNames.StruggleStateChanged)
end

function StruggleController:Start()
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(payload)
		self:_handleRemote(payload)
	end)

	task.spawn(function()
		while true do
			self:_updateUiState(0.05)
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientInteraction", "[StruggleController] Started")
end

function StruggleController:IsActive()
	return self.Active
end

function StruggleController:RegisterLocalPress()
	if not self.Active then
		return
	end

	self.LastPressAt = os.clock()
	self.UI.KeyLabel.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	self.UI.KeyLabel.TextColor3 = Color3.fromRGB(20, 22, 28)
end

function StruggleController:_handleRemote(payload)
	local state = payload and payload.State
	if state == "Start" or state == "Update" then
		self.Active = true
		self.Progress = payload.Progress or 0
		self.MaxProgress = payload.Max or 1
		self.RemainingDuration = payload.Duration or 0
		self.UI.Root.Enabled = true
		self.UI.Label.Text = payload.Prompt or "Struggle"
		self.UI.SubLabel.Text = payload.SubPrompt or "Break free before Jiangshi finishes feeding"
		self.UI.KeyLabel.Text = payload.RequiredKey or "SPACE"
		self:_refreshProgress()
	else
		self.Active = false
		self.Progress = 0
		self.MaxProgress = 1
		self.RemainingDuration = 0
		self.UI.Root.Enabled = false
	end
end

function StruggleController:_updateUiState(deltaTime)
	if not self.Active or not self.UI then
		return
	end

	self.RemainingDuration = math.max(0, self.RemainingDuration - deltaTime)
	self.UI.Duration.Text = string.format("%.1fs", self.RemainingDuration)

	if os.clock() - self.LastPressAt > 0.08 then
		self.UI.KeyLabel.BackgroundColor3 = Color3.fromRGB(56, 49, 38)
		self.UI.KeyLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	end

	local urgency = self.RemainingDuration <= 2
	self.UI.Duration.TextColor3 = urgency and Color3.fromRGB(228, 112, 112) or Color3.fromRGB(240, 240, 240)
	self.UI.Bar.BackgroundColor3 = urgency and Color3.fromRGB(232, 132, 132) or Color3.fromRGB(214, 180, 64)
end

function StruggleController:_refreshProgress()
	local ratio = self.MaxProgress > 0 and math.clamp(self.Progress / self.MaxProgress, 0, 1) or 0
	self.UI.Bar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.ProgressLabel.Text = string.format("%d%%", math.floor((ratio * 100) + 0.5))
	self.UI.Duration.Text = string.format("%.1fs", self.RemainingDuration)
end

function StruggleController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SkillCheckUI"
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.World.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.75)
	container.Position = UDim2.new(0.5, 0, 0.75, 0)
	container.Size = UDim2.new(0, 360, 0, 108)
	container.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	container.BackgroundTransparency = 0.05
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
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextSize = 17
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "Struggle"
	label.Parent = container

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Position = UDim2.new(0, 14, 0, 32)
	subLabel.Size = UDim2.new(1, -120, 0, 18)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextColor3 = Color3.fromRGB(182, 182, 190)
	subLabel.TextSize = 12
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = "Break free before the grapple finishes"
	subLabel.Parent = container

	local duration = Instance.new("TextLabel")
	duration.Name = "Duration"
	duration.Position = UDim2.new(1, -78, 0, 12)
	duration.Size = UDim2.new(0, 64, 0, 20)
	duration.BackgroundTransparency = 1
	duration.Font = Enum.Font.GothamBold
	duration.TextColor3 = Color3.fromRGB(240, 240, 240)
	duration.TextSize = 14
	duration.TextXAlignment = Enum.TextXAlignment.Right
	duration.Text = "0.0s"
	duration.Parent = container

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Position = UDim2.new(0, 14, 0, 58)
	keyLabel.Size = UDim2.new(0, 82, 0, 28)
	keyLabel.BackgroundColor3 = Color3.fromRGB(56, 49, 38)
	keyLabel.BorderSizePixel = 0
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	keyLabel.TextSize = 16
	keyLabel.Text = "SPACE"
	keyLabel.Parent = container

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 8)
	keyCorner.Parent = keyLabel

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Position = UDim2.new(1, -74, 0, 60)
	progressLabel.Size = UDim2.new(0, 60, 0, 18)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	progressLabel.TextSize = 13
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = "0%"
	progressLabel.Parent = container

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.new(0, 104, 0, 66)
	barBackground.Size = UDim2.new(1, -118, 0, 12)
	barBackground.BackgroundColor3 = Color3.fromRGB(48, 51, 60)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local barBackgroundCorner = Instance.new("UICorner")
	barBackgroundCorner.CornerRadius = UDim.new(0, 6)
	barBackgroundCorner.Parent = barBackground

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(214, 180, 64)
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

return StruggleController
