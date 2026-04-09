local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local QTEType = require(ReplicatedStorage.Shared.Enums.QTEType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local QTEController = {}
QTEController.Name = "QTEController"

function QTEController:Init()
	self.Remote = self.World.Remotes:WaitForChild(RemoteNames.QTEStateChanged)
	self.RequestRemote = self.World.Remotes:WaitForChild(RemoteNames.RequestQTEInput)
	self.Active = false
	self.Type = nil
	self.Progress = 0
	self.MaxProgress = 1
	self.RemainingDuration = 0
	self.RequiredKey = nil
	self.ExpectedKey = nil
	self.DialAngle = 0
	self.SuccessAngle = 0
	self.SuccessAngleSize = 40
	self.LastKeyboardInputAt = 0
	self.LastSliceAt = 0
	self.DialFeedback = nil
	self.DialFeedbackUntil = 0
	self.DefaultContainerPosition = UDim2.new(0.5, 0, 0.75, 0)
	self.DialContainerPosition = UDim2.new(0.5, 0, 0.54, 0)
end

function QTEController:Start()
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(payload)
		self:_handleRemote(payload)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not self.Active or self.Type ~= QTEType.MouseSlice then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local delta = input.Delta
		if delta.Magnitude <= 0 then
			return
		end

		self.LastSliceAt = os.clock()
		self.RequestRemote:FireServer({
			Kind = "Slice",
			Delta = delta,
		})
	end)

	task.spawn(function()
		while true do
			self:_updateUiState(0.05)
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientInteraction", "[QTEController] Started")
end

function QTEController:IsActive()
	return self.Active
end

function QTEController:RequiresKeyboardInput()
	return self.Active and (self.Type == QTEType.KeyMash or self.Type == QTEType.SequenceKeys or self.Type == QTEType.TimingDial)
end

function QTEController:HandleKeyboardInput(keyCode, isPressed)
	if not self:RequiresKeyboardInput() or not isPressed or not keyCode or keyCode == Enum.KeyCode.Unknown then
		return false
	end

	local keyName = keyCode.Name
	if self.Type == QTEType.KeyMash and self.RequiredKey and keyName ~= self.RequiredKey then
		return false
	end

	self.LastKeyboardInputAt = os.clock()
	self.UI.KeyLabel.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	self.UI.KeyLabel.TextColor3 = Color3.fromRGB(20, 22, 28)
	self.RequestRemote:FireServer({
		Kind = "Press",
		Key = keyName,
	})
	return true
end

function QTEController:_handleRemote(payload)
	local state = payload and payload.State
	if state == "Stop" then
		self.Active = false
		self.Type = nil
		self.Progress = 0
		self.MaxProgress = 1
		self.RemainingDuration = 0
		self.RequiredKey = nil
		self.ExpectedKey = nil
		self.DialAngle = 0
		self.SuccessAngle = 0
		self.SuccessAngleSize = 40
		self.DialFeedback = nil
		self.DialFeedbackUntil = 0
		self.UI.Root.Enabled = false
		return
	end

	local previousProgress = self.Progress
	self.Active = true
	self.Type = payload.Type or self.Type or QTEType.KeyMash
	self.Progress = payload.Progress or 0
	self.MaxProgress = payload.Max or 1
	self.RemainingDuration = payload.Duration or self.RemainingDuration
	self.RequiredKey = payload.RequiredKey or self.RequiredKey
	self.ExpectedKey = payload.ExpectedKey
	self.DialAngle = payload.DialAngle or self.DialAngle
	self.SuccessAngle = payload.SuccessAngle or self.SuccessAngle
	self.SuccessAngleSize = payload.SuccessAngleSize or self.SuccessAngleSize
	self.UI.Root.Enabled = true
	self.UI.Label.Text = payload.Prompt or "Quick Time Event"
	self.UI.SubLabel.Text = payload.SubPrompt or ""

	if self.Type == QTEType.TimingDial and state == "Update" then
		if self.Progress > previousProgress then
			self:_setDialFeedback("success")
		elseif self.Progress < previousProgress then
			self:_setDialFeedback("fail")
		end
	end

	self:_refreshPromptText(payload)
	self:_refreshProgress()
end

function QTEController:_refreshPromptText(payload)
	if self.Type == QTEType.KeyMash then
		self.UI.KeyLabel.Text = payload.RequiredKey or self.RequiredKey or "SPACE"
	elseif self.Type == QTEType.SequenceKeys then
		self.UI.KeyLabel.Text = payload.ExpectedKey or self.ExpectedKey or "?"
	elseif self.Type == QTEType.MouseSlice then
		self.UI.KeyLabel.Text = "SLICE"
	elseif self.Type == QTEType.TimingDial then
		self.UI.KeyLabel.Text = payload.RequiredKey or self.RequiredKey or "SPACE"
	else
		self.UI.KeyLabel.Text = "QTE"
	end
end

function QTEController:_updateUiState(deltaTime)
	if not self.Active or not self.UI then
		return
	end

	self.RemainingDuration = math.max(0, self.RemainingDuration - deltaTime)
	self.UI.Duration.Text = string.format("%.1fs", self.RemainingDuration)

	local recentKeyboardInput = os.clock() - self.LastKeyboardInputAt <= 0.08
	local recentSlice = os.clock() - self.LastSliceAt <= 0.08
	if not recentKeyboardInput and not recentSlice then
		self.UI.KeyLabel.BackgroundColor3 = Color3.fromRGB(56, 49, 38)
		self.UI.KeyLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
	end

	local urgency = self.RemainingDuration <= 2
	self.UI.Duration.TextColor3 = urgency and Color3.fromRGB(228, 112, 112) or Color3.fromRGB(240, 240, 240)
	self.UI.Bar.BackgroundColor3 = urgency and Color3.fromRGB(232, 132, 132) or Color3.fromRGB(214, 180, 64)
	self:_updateDialVisuals()
end

function QTEController:_refreshProgress()
	local ratio = self.MaxProgress > 0 and math.clamp(self.Progress / self.MaxProgress, 0, 1) or 0
	self.UI.Bar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.ProgressLabel.Text = string.format("%d%%", math.floor((ratio * 100) + 0.5))
	self.UI.Duration.Text = string.format("%.1fs", self.RemainingDuration)
	self:_updateDialVisuals()
end

function QTEController:_updateDialVisuals()
	if not self.UI or not self.UI.DialContainer then
		return
	end

	local showDial = self.Active and self.Type == QTEType.TimingDial
	self.UI.DialContainer.Visible = showDial
	self.UI.Container.Position = showDial and self.DialContainerPosition or self.DefaultContainerPosition
	if not showDial then
		self.UI.DialStroke.Color = Color3.fromRGB(110, 114, 128)
		self.UI.Pointer.BackgroundColor3 = Color3.fromRGB(232, 122, 122)
		self.UI.PointerArm.BackgroundColor3 = Color3.fromRGB(232, 122, 122)
		self.UI.SuccessZone.BackgroundColor3 = Color3.fromRGB(118, 208, 144)
		return
	end

	self.UI.Pointer.Rotation = self.DialAngle
	self.UI.SuccessMarker.Rotation = self.SuccessAngle
	self.UI.SuccessZone.Size = UDim2.new(0, math.max(16, self.SuccessAngleSize * 1.1), 0, 8)

	local now = os.clock()
	local strokeColor = Color3.fromRGB(110, 114, 128)
	local pointerColor = Color3.fromRGB(232, 122, 122)
	local successColor = Color3.fromRGB(118, 208, 144)
	local position = self.DialContainerPosition

	if self.DialFeedbackUntil > now then
		if self.DialFeedback == "success" then
			strokeColor = Color3.fromRGB(118, 208, 144)
			pointerColor = Color3.fromRGB(140, 232, 164)
			successColor = Color3.fromRGB(166, 242, 181)
		elseif self.DialFeedback == "fail" then
			strokeColor = Color3.fromRGB(214, 102, 102)
			pointerColor = Color3.fromRGB(242, 124, 124)
			successColor = Color3.fromRGB(202, 110, 110)
			position = position + UDim2.fromOffset(math.random(-4, 4), math.random(-2, 2))
		end
	end

	self.UI.Container.Position = position
	self.UI.DialStroke.Color = strokeColor
	self.UI.Pointer.BackgroundColor3 = pointerColor
	self.UI.PointerArm.BackgroundColor3 = pointerColor
	self.UI.SuccessZone.BackgroundColor3 = successColor
end

function QTEController:_setDialFeedback(feedbackKind)
	self.DialFeedback = feedbackKind
	self.DialFeedbackUntil = os.clock() + 0.14
end

function QTEController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QTEUI"
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
	label.Text = "Quick Time Event"
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
	subLabel.Text = ""
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

	local dialContainer = Instance.new("Frame")
	dialContainer.Name = "DialContainer"
	dialContainer.AnchorPoint = Vector2.new(0.5, 1)
	dialContainer.Position = UDim2.new(0.5, 0, 0, -16)
	dialContainer.Size = UDim2.new(0, 156, 0, 156)
	dialContainer.BackgroundTransparency = 1
	dialContainer.Visible = false
	dialContainer.Parent = container

	local dialCircle = Instance.new("Frame")
	dialCircle.Name = "DialCircle"
	dialCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	dialCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
	dialCircle.Size = UDim2.new(0, 132, 0, 132)
	dialCircle.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
	dialCircle.BackgroundTransparency = 0.12
	dialCircle.BorderSizePixel = 0
	dialCircle.Parent = dialContainer

	local dialCircleCorner = Instance.new("UICorner")
	dialCircleCorner.CornerRadius = UDim.new(1, 0)
	dialCircleCorner.Parent = dialCircle

	local dialStroke = Instance.new("UIStroke")
	dialStroke.Color = Color3.fromRGB(110, 114, 128)
	dialStroke.Thickness = 2
	dialStroke.Parent = dialCircle

	local successMarker = Instance.new("Frame")
	successMarker.Name = "SuccessMarker"
	successMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	successMarker.Position = UDim2.new(0.5, 0, 0.5, 0)
	successMarker.Size = UDim2.new(0, 0, 0, 0)
	successMarker.BackgroundTransparency = 1
	successMarker.BorderSizePixel = 0
	successMarker.Parent = dialCircle

	local successAnchor = Instance.new("Frame")
	successAnchor.Name = "SuccessAnchor"
	successAnchor.AnchorPoint = Vector2.new(0.5, 1)
	successAnchor.Position = UDim2.new(0.5, 0, 0.5, 0)
	successAnchor.Size = UDim2.new(0, 0, 0, 54)
	successAnchor.BackgroundTransparency = 1
	successAnchor.Parent = successMarker

	local successZone = Instance.new("Frame")
	successZone.Name = "SuccessZone"
	successZone.AnchorPoint = Vector2.new(0.5, 0.5)
	successZone.Position = UDim2.new(0.5, 0, 0, 6)
	successZone.Size = UDim2.new(0, 42, 0, 8)
	successZone.BackgroundColor3 = Color3.fromRGB(118, 208, 144)
	successZone.BorderSizePixel = 0
	successZone.Parent = successAnchor

	local successCorner = Instance.new("UICorner")
	successCorner.CornerRadius = UDim.new(1, 0)
	successCorner.Parent = successZone

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.new(0.5, 0, 0.5, 0)
	pointer.Size = UDim2.new(0, 8, 0, 8)
	pointer.BackgroundColor3 = Color3.fromRGB(232, 122, 122)
	pointer.BorderSizePixel = 0
	pointer.Parent = dialCircle

	local pointerCorner = Instance.new("UICorner")
	pointerCorner.CornerRadius = UDim.new(1, 0)
	pointerCorner.Parent = pointer

	local pointerArm = Instance.new("Frame")
	pointerArm.Name = "PointerArm"
	pointerArm.AnchorPoint = Vector2.new(0.5, 1)
	pointerArm.Position = UDim2.new(0.5, 0, 0.5, 0)
	pointerArm.Size = UDim2.new(0, 4, 0, 56)
	pointerArm.BackgroundColor3 = Color3.fromRGB(232, 122, 122)
	pointerArm.BorderSizePixel = 0
	pointerArm.Parent = pointer

	local pointerArmCorner = Instance.new("UICorner")
	pointerArmCorner.CornerRadius = UDim.new(1, 0)
	pointerArmCorner.Parent = pointerArm

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
		Container = container,
		DialContainer = dialContainer,
		DialCircle = dialCircle,
		DialStroke = dialStroke,
		Pointer = pointer,
		PointerArm = pointerArm,
		SuccessMarker = successMarker,
		SuccessZone = successZone,
	}
end

return QTEController
