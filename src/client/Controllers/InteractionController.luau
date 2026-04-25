local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractionController = {}
InteractionController.Name = "InteractionController"

function InteractionController:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
	self.Remote = self.Shared.Remotes:WaitForChild(RemoteNames.InteractionStateChanged)
end

function InteractionController:Start()
	self:_createUi()
	self.UI.Root.Enabled = false
	self.DisplayToken = 0
	self.ActiveProgress = 0
	self.ActiveMax = 1
	self.ActiveChargeRate = 0

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
	barBackground.ClipsDescendants = true
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

function InteractionController:_setProgress(progress, maxProgress)
	local safeMax = math.max(maxProgress or 1, 0.001)
	local percent = math.clamp((progress or 0) / safeMax, 0, 1)
	self.UI.Bar.Size = UDim2.new(percent, 0, 1, 0)
end

function InteractionController:_stopProgressClock()
	if self.ProgressConnection then
		self.ProgressConnection:Disconnect()
		self.ProgressConnection = nil
	end
end

function InteractionController:_startProgressClock(progress, maxProgress, chargeRate)
	self:_stopProgressClock()

	self.ActiveProgress = progress or 0
	self.ActiveMax = math.max(maxProgress or 1, 0.001)
	self.ActiveChargeRate = math.max(chargeRate or 0, 0)
	self:_setProgress(self.ActiveProgress, self.ActiveMax)

	if self.ActiveChargeRate <= 0 then
		return
	end

	self.ProgressConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self.UI or not self.UI.Root.Enabled then
			return
		end

		self.ActiveProgress = math.min(self.ActiveMax, self.ActiveProgress + self.ActiveChargeRate * deltaTime)
		self:_setProgress(self.ActiveProgress, self.ActiveMax)
	end)
end

function InteractionController:HandleInteractionUpdate(data)
	DebugLog:Log("ClientInteraction", "[InteractionController] Received interaction state:", data.State)

	if data.State == "Start" then
		self.DisplayToken += 1
		self.UI.Root.Enabled = true
		self.UI.Label.Text = data.Target or "Interacting..."
		local lowerLabel = string.lower(self.UI.Label.Text)
		if string.find(lowerLabel, "recover", 1, true) then
			self.UI.SubLabel.Text = "Hold to recover"
		elseif string.find(lowerLabel, "heal", 1, true) then
			self.UI.SubLabel.Text = "Hold to heal"
		elseif string.find(lowerLabel, "vault", 1, true) then
			self.UI.SubLabel.Text = "Vaulting"
		elseif string.find(lowerLabel, "door", 1, true) then
			self.UI.SubLabel.Text = "Using door"
		elseif string.find(lowerLabel, "hazard", 1, true) or string.find(lowerLabel, "log", 1, true) then
			self.UI.SubLabel.Text = "Hold to trigger"
		else
			self.UI.SubLabel.Text = "Hold to continue"
		end
		self:_startProgressClock(data.Progress or 0, data.Max or 1, data.ChargeRate or 0)
	elseif data.State == "Update" then
		local maxValue = data.Max or 1
		local progressValue = data.Progress or 0
		self.ActiveProgress = progressValue
		self.ActiveMax = math.max(maxValue, 0.001)
		self.ActiveChargeRate = math.max(data.ChargeRate or self.ActiveChargeRate or 0, 0)
		self:_setProgress(self.ActiveProgress, self.ActiveMax)

		if self.ActiveChargeRate > 0 and not self.ProgressConnection then
			self:_startProgressClock(self.ActiveProgress, self.ActiveMax, self.ActiveChargeRate)
		end
	elseif data.State == "Stop" then
		self.DisplayToken += 1
		self:_stopProgressClock()
		self.UI.Root.Enabled = false
	elseif data.State == "Complete" then
		self.DisplayToken += 1
		local token = self.DisplayToken
		self:_stopProgressClock()
		self.UI.SubLabel.Text = "Complete"
		self:_setProgress(data.Progress or data.Max or 1, data.Max or 1)
		task.delay(0.3, function()
			if self.DisplayToken == token then
				self.UI.Root.Enabled = false
			end
		end)
	end
end

return InteractionController
