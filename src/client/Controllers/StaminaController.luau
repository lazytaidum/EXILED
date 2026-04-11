local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StaminaController = {}
StaminaController.Name = "StaminaController"

function StaminaController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.Remote = self.Remotes:WaitForChild(RemoteNames.StaminaStateChanged)
	self.State = {
		Current = 100,
		Max = 100,
		MovementState = "Walk",
		RunDurationBeforeFatigue = 6,
	}
end

function StaminaController:Start()
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(state)
		self.State = state or self.State
		self:_refresh()
	end)

	DebugLog:Log("ClientMovement", "[StaminaController] Started")
end

function StaminaController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StaminaUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 242, 1, -24)
	frame.Size = UDim2.new(0, 180, 0, 30)
	frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 10, 0, 4)
	label.Size = UDim2.new(0.62, 0, 0, 12)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextColor3 = Color3.fromRGB(180, 214, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "Stamina"
	label.Parent = frame

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "State"
	stateLabel.BackgroundTransparency = 1
	stateLabel.AnchorPoint = Vector2.new(1, 0)
	stateLabel.Position = UDim2.new(1, -10, 0, 4)
	stateLabel.Size = UDim2.new(0.34, 0, 0, 12)
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextSize = 10
	stateLabel.TextColor3 = Color3.fromRGB(180, 214, 255)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Right
	stateLabel.Text = "WALK"
	stateLabel.Parent = frame

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.new(0, 10, 1, -12)
	barBackground.Size = UDim2.new(1, -20, 0, 6)
	barBackground.BackgroundColor3 = Color3.fromRGB(46, 46, 56)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	bar.BorderSizePixel = 0
	bar.Parent = barBackground

	self.UI = {
		Root = screenGui,
		Frame = frame,
		Label = label,
		StateLabel = stateLabel,
		Bar = bar,
	}

	self:_refresh()
end

function StaminaController:_refresh()
	if not self.UI then
		return
	end

	local roundState = self.World:GetRoundState()
	local phase = roundState and roundState.Phase or "Unknown"
	local shouldShow = phase == GamePhase.Preparation or phase == GamePhase.Reception
	self.UI.Root.Enabled = shouldShow
	if not shouldShow then
		return
	end

	local current = self.State.Current or 0
	local max = math.max(1, self.State.Max or 100)
	local ratio = math.clamp(current / max, 0, 1)
	local movementState = tostring(self.State.MovementState or "Walk")
	self.UI.Bar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.Label.Text = string.format("Stamina %.1f/%.0f", current, max)
	self.UI.StateLabel.Text = string.upper(movementState)

	if movementState == "Fatigue" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(255, 156, 92)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(255, 156, 92)
	elseif movementState == "Run" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	elseif movementState == "Sprint" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(132, 224, 255)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	elseif ratio <= 0.25 then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(214, 92, 92)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(214, 92, 92)
	elseif ratio <= 0.5 then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	else
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(180, 214, 255)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	end
end

return StaminaController
