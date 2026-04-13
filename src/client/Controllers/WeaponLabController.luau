local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local WorldMode = require(ReplicatedStorage.Shared.Enums.WorldMode)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local WeaponLabController = {}
WeaponLabController.Name = "WeaponLabController"
WeaponLabController.Dependencies = {
	"CombatController",
	"CameraInputController",
	"ViewmodelController",
}

local ATTACHMENT_EDITOR_NAMES = {
	"Aim",
	"RightHand",
	"LeftHand",
	"Muzzle",
	"RightHandSocket",
	"LeftHandSocket",
	"RightElbowPole",
	"LeftElbowPole",
	"RightShoulderBase",
	"LeftShoulderBase",
}
local DEFAULT_POSITION_STEP = 0.01
local DEFAULT_ROTATION_STEP = 5

local function _buildFirearmIds()
	local ids = {}
	for weaponId, definition in pairs(WeaponDefinitions) do
		if definition.Kind == "Firearm" then
			table.insert(ids, weaponId)
		end
	end
	table.sort(ids)
	return ids
end

function WeaponLabController:Init()
	self.Enabled = self.World:GetWorldMode() == WorldMode.WeaponLab
	if not self.Enabled then
		return
	end

	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.RequestRemote = self.Remotes:WaitForChild(RemoteNames.RequestWeaponLabCommand)
	self.StateRemote = self.Remotes:WaitForChild(RemoteNames.WeaponLabStateChanged)
	self.WeaponIds = _buildFirearmIds()
	self.SelectedWeaponIndex = 1
	self.PositionStep = DEFAULT_POSITION_STEP
	self.RotationStep = DEFAULT_ROTATION_STEP
	self.LastAppliedLabWeaponId = nil
	self.State = {
		SelectedWeaponId = self.WeaponIds[1],
		DefaultWeaponId = self.WeaponIds[1],
		Message = "",
	}
end

function WeaponLabController:Start()
	if not self.Enabled then
		return
	end

	if self.ViewmodelController and self.ViewmodelController.SetLabEnabled then
		self.ViewmodelController:SetLabEnabled(true)
		if self.State and self.State.SelectedWeaponId then
			self.ViewmodelController:SetLabWeapon(self.State.SelectedWeaponId)
			self.LastAppliedLabWeaponId = self.State.SelectedWeaponId
		end
	end

	self:_createUi()
	self:_refreshUi()

	self.StateRemote.OnClientEvent:Connect(function(payload)
		self.State = payload or self.State
		self:_syncSelectedIndexFromState()
		if self.ViewmodelController
			and self.ViewmodelController.SetLabWeapon
			and self.State
			and self.State.SelectedWeaponId
			and self.State.SelectedWeaponId ~= self.LastAppliedLabWeaponId then
			self.ViewmodelController:SetLabWeapon(self.State.SelectedWeaponId)
			self.LastAppliedLabWeaponId = self.State.SelectedWeaponId
		end
		self:_refreshUi()
	end)

	self.RequestRemote:FireServer({
		Command = "Refresh",
	})

	DebugLog:Log("ClientCombat", "[WeaponLabController] Started")
end

function WeaponLabController:_syncSelectedIndexFromState()
	local currentWeaponId = self.State and self.State.SelectedWeaponId
	if not currentWeaponId then
		return
	end

	for index, weaponId in ipairs(self.WeaponIds) do
		if weaponId == currentWeaponId then
			self.SelectedWeaponIndex = index
			return
		end
	end
end

function WeaponLabController:_cycleWeapon(delta)
	local count = #self.WeaponIds
	if count <= 0 then
		return
	end

	local nextIndex = self.SelectedWeaponIndex + delta
	if nextIndex < 1 then
		nextIndex = count
	elseif nextIndex > count then
		nextIndex = 1
	end
	self.SelectedWeaponIndex = nextIndex
	self:_refreshUi()
end

function WeaponLabController:_getSelectedWeaponId()
	return self.WeaponIds[self.SelectedWeaponIndex]
end

function WeaponLabController:_getAttachmentSelectionIndex()
	local selectedAttachment = self.ViewmodelController and self.ViewmodelController:GetLabSelectedAttachment() or ATTACHMENT_EDITOR_NAMES[1]
	for index, attachmentName in ipairs(ATTACHMENT_EDITOR_NAMES) do
		if attachmentName == selectedAttachment then
			return index
		end
	end

	return 1
end

function WeaponLabController:_cycleAttachment(delta)
	if not self.ViewmodelController then
		return
	end

	local count = #ATTACHMENT_EDITOR_NAMES
	local nextIndex = self:_getAttachmentSelectionIndex() + delta
	if nextIndex < 1 then
		nextIndex = count
	elseif nextIndex > count then
		nextIndex = 1
	end

	self.ViewmodelController:SetLabSelectedAttachment(ATTACHMENT_EDITOR_NAMES[nextIndex])
	self:_refreshUi()
end

function WeaponLabController:_adjustAttachment(positionDelta, rotationDelta)
	if not self.ViewmodelController then
		return
	end

	local attachmentName = self.ViewmodelController:GetLabSelectedAttachment()
	self.ViewmodelController:AdjustLabAttachment(attachmentName, positionDelta, rotationDelta)
	self:_refreshUi()
end

function WeaponLabController:_resetAttachment()
	if not self.ViewmodelController then
		return
	end

	local attachmentName = self.ViewmodelController:GetLabSelectedAttachment()
	self.ViewmodelController:ResetLabAttachment(attachmentName)
	self:_refreshUi()
end

function WeaponLabController:_readNumberFromTextBox(textBox, fallbackValue)
	if not textBox then
		return fallbackValue
	end

	local parsedValue = tonumber(textBox.Text)
	if not parsedValue or parsedValue <= 0 then
		textBox.Text = tostring(fallbackValue)
		return fallbackValue
	end

	return parsedValue
end

function WeaponLabController:_getPositionStep()
	self.PositionStep = self:_readNumberFromTextBox(self.UI and self.UI.PositionStepBox or nil, self.PositionStep or DEFAULT_POSITION_STEP)
	return self.PositionStep
end

function WeaponLabController:_getRotationStep()
	self.RotationStep = self:_readNumberFromTextBox(self.UI and self.UI.RotationStepBox or nil, self.RotationStep or DEFAULT_ROTATION_STEP)
	return self.RotationStep
end

function WeaponLabController:_createButton(parent, text, position, size, onClick)
	local button = Instance.new("TextButton")
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.Text = text
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.MouseButton1Click:Connect(onClick)
	return button
end

function WeaponLabController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WeaponLabUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -18, 0, 18)
	frame.Size = UDim2.new(0, 300, 0, 620)
	frame.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 12, 0, 10)
	title.Size = UDim2.new(1, -24, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Weapon Lab"
	title.Parent = frame

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.BackgroundTransparency = 1
	stateLabel.Position = UDim2.new(0, 12, 0, 32)
	stateLabel.Size = UDim2.new(1, -24, 0, 38)
	stateLabel.Font = Enum.Font.Gotham
	stateLabel.TextSize = 11
	stateLabel.TextWrapped = true
	stateLabel.TextYAlignment = Enum.TextYAlignment.Top
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.TextColor3 = Color3.fromRGB(190, 194, 206)
	stateLabel.Parent = frame

	local weaponName = Instance.new("TextLabel")
	weaponName.Name = "WeaponName"
	weaponName.BackgroundTransparency = 1
	weaponName.Position = UDim2.new(0, 52, 0, 82)
	weaponName.Size = UDim2.new(0, 140, 0, 22)
	weaponName.Font = Enum.Font.GothamBold
	weaponName.TextSize = 12
	weaponName.TextColor3 = Color3.fromRGB(240, 240, 240)
	weaponName.TextXAlignment = Enum.TextXAlignment.Center
	weaponName.Parent = frame

	self:_createButton(frame, "<", UDim2.new(0, 12, 0, 82), UDim2.new(0, 32, 0, 22), function()
		self:_cycleWeapon(-1)
	end)
	self:_createButton(frame, ">", UDim2.new(0, 200, 0, 82), UDim2.new(0, 32, 0, 22), function()
		self:_cycleWeapon(1)
	end)

	local loadButton = self:_createButton(frame, "Load", UDim2.new(0, 240, 0, 82), UDim2.new(0, 48, 0, 22), function()
		local weaponId = self:_getSelectedWeaponId()
		if weaponId then
			self.RequestRemote:FireServer({
				Command = "SetWeapon",
				WeaponId = weaponId,
			})
		end
	end)

	local resetButton = self:_createButton(frame, "Reset Loadout", UDim2.new(0, 12, 0, 112), UDim2.new(0, 132, 0, 22), function()
		self.RequestRemote:FireServer({
			Command = "ResetLoadout",
		})
	end)

	local perspectiveButton = self:_createButton(frame, "Toggle Perspective", UDim2.new(0, 156, 0, 112), UDim2.new(0, 132, 0, 22), function()
		if self.CameraInputController then
			self.CameraInputController:TogglePerspective()
			self:_refreshUi()
		end
	end)

	local aimButton = self:_createButton(frame, "Toggle ADS", UDim2.new(0, 12, 0, 150), UDim2.new(0, 88, 0, 22), function()
		local combatState = self.CombatController and self.CombatController:GetState() or nil
		local nextAimState = not (combatState and combatState.IsAiming == true)
		if self.CombatController and self.CombatController.RequestMovementStateRemote then
			self.CombatController.RequestMovementStateRemote:FireServer(ActionName.Aim, nextAimState)
		end
	end)

	local fireButton = self:_createButton(frame, "Fire", UDim2.new(0, 106, 0, 150), UDim2.new(0, 56, 0, 22), function()
		if self.CombatController and self.CombatController.RequestPrimaryAttackRemote then
			local combatState = self.CombatController:GetState()
			self.CombatController.RequestPrimaryAttackRemote:FireServer({
				Origin = self.World.Camera.CFrame.Position,
				Direction = self.World.Camera.CFrame.LookVector,
				IsAiming = combatState and combatState.IsAiming == true,
			})
		end
	end)

	local reloadButton = self:_createButton(frame, "Reload", UDim2.new(0, 168, 0, 150), UDim2.new(0, 58, 0, 22), function()
		if self.CombatController and self.CombatController.RequestReloadRemote then
			self.CombatController.RequestReloadRemote:FireServer()
		end
	end)

	local equipButton = self:_createButton(frame, "Equip", UDim2.new(0, 232, 0, 150), UDim2.new(0, 56, 0, 22), function()
		if self.ViewmodelController then
			self.ViewmodelController:PlayAction("Equip")
		end
	end)

	local captureStaticButton = self:_createButton(frame, "Capture Static", UDim2.new(0, 12, 0, 188), UDim2.new(0, 132, 0, 22), function()
		if self.ViewmodelController and self.ViewmodelController.CaptureLabStaticRig then
			self.ViewmodelController:CaptureLabStaticRig()
			self:_refreshUi()
		end
	end)

	local clearStaticButton = self:_createButton(frame, "Clear Static", UDim2.new(0, 156, 0, 188), UDim2.new(0, 132, 0, 22), function()
		if self.ViewmodelController and self.ViewmodelController.ClearLabStaticRig then
			self.ViewmodelController:ClearLabStaticRig()
			self:_refreshUi()
		end
	end)

	local autoRefreshButton = self:_createButton(frame, "Auto Refresh Static", UDim2.new(0, 12, 0, 218), UDim2.new(0, 132, 0, 22), function()
		if self.ViewmodelController and self.ViewmodelController.SetLabAutoRefreshStatic then
			self.ViewmodelController:SetLabAutoRefreshStatic(not self.ViewmodelController:IsLabAutoRefreshingStatic())
			self:_refreshUi()
		end
	end)

	local debugPointsButton = self:_createButton(frame, "Show Debug Points", UDim2.new(0, 156, 0, 218), UDim2.new(0, 132, 0, 22), function()
		if self.ViewmodelController and self.ViewmodelController.SetLabDebugPointsEnabled then
			self.ViewmodelController:SetLabDebugPointsEnabled(not self.ViewmodelController:IsLabDebugPointsEnabled())
			self:_refreshUi()
		end
	end)

	local showLiveButton = self:_createButton(frame, "Show Live Rig", UDim2.new(0, 12, 0, 248), UDim2.new(0, 276, 0, 22), function()
		if self.ViewmodelController and self.ViewmodelController.SetLabShowSourceRig then
			self.ViewmodelController:SetLabShowSourceRig(not self.ViewmodelController:IsLabShowingSourceRig())
			self:_refreshUi()
		end
	end)

	local attachmentLabel = Instance.new("TextLabel")
	attachmentLabel.Name = "AttachmentLabel"
	attachmentLabel.BackgroundTransparency = 1
	attachmentLabel.Position = UDim2.new(0, 12, 0, 280)
	attachmentLabel.Size = UDim2.new(1, -24, 0, 18)
	attachmentLabel.Font = Enum.Font.GothamBold
	attachmentLabel.TextSize = 12
	attachmentLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	attachmentLabel.TextXAlignment = Enum.TextXAlignment.Left
	attachmentLabel.Parent = frame

	local attachmentName = Instance.new("TextLabel")
	attachmentName.Name = "AttachmentName"
	attachmentName.BackgroundTransparency = 1
	attachmentName.Position = UDim2.new(0, 52, 0, 302)
	attachmentName.Size = UDim2.new(0, 140, 0, 22)
	attachmentName.Font = Enum.Font.GothamBold
	attachmentName.TextSize = 12
	attachmentName.TextColor3 = Color3.fromRGB(240, 240, 240)
	attachmentName.TextXAlignment = Enum.TextXAlignment.Center
	attachmentName.Parent = frame

	self:_createButton(frame, "<", UDim2.new(0, 12, 0, 302), UDim2.new(0, 32, 0, 22), function()
		self:_cycleAttachment(-1)
	end)
	self:_createButton(frame, ">", UDim2.new(0, 200, 0, 302), UDim2.new(0, 32, 0, 22), function()
		self:_cycleAttachment(1)
	end)

	local resetAttachmentButton = self:_createButton(frame, "Reset", UDim2.new(0, 240, 0, 302), UDim2.new(0, 48, 0, 22), function()
		self:_resetAttachment()
	end)

	local positionStepLabel = Instance.new("TextLabel")
	positionStepLabel.Name = "PositionStepLabel"
	positionStepLabel.BackgroundTransparency = 1
	positionStepLabel.Position = UDim2.new(0, 12, 0, 328)
	positionStepLabel.Size = UDim2.new(0, 70, 0, 18)
	positionStepLabel.Font = Enum.Font.Gotham
	positionStepLabel.TextSize = 11
	positionStepLabel.TextColor3 = Color3.fromRGB(190, 194, 206)
	positionStepLabel.TextXAlignment = Enum.TextXAlignment.Left
	positionStepLabel.Text = "Pos Step"
	positionStepLabel.Parent = frame

	local positionStepBox = Instance.new("TextBox")
	positionStepBox.Name = "PositionStepBox"
	positionStepBox.Position = UDim2.new(0, 78, 0, 326)
	positionStepBox.Size = UDim2.new(0, 58, 0, 22)
	positionStepBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	positionStepBox.BorderSizePixel = 0
	positionStepBox.Font = Enum.Font.Gotham
	positionStepBox.TextSize = 12
	positionStepBox.TextColor3 = Color3.fromRGB(240, 240, 240)
	positionStepBox.PlaceholderText = tostring(DEFAULT_POSITION_STEP)
	positionStepBox.Text = tostring(self.PositionStep)
	positionStepBox.Parent = frame

	local positionStepCorner = Instance.new("UICorner")
	positionStepCorner.CornerRadius = UDim.new(0, 8)
	positionStepCorner.Parent = positionStepBox

	local rotationStepLabel = Instance.new("TextLabel")
	rotationStepLabel.Name = "RotationStepLabel"
	rotationStepLabel.BackgroundTransparency = 1
	rotationStepLabel.Position = UDim2.new(0, 150, 0, 328)
	rotationStepLabel.Size = UDim2.new(0, 70, 0, 18)
	rotationStepLabel.Font = Enum.Font.Gotham
	rotationStepLabel.TextSize = 11
	rotationStepLabel.TextColor3 = Color3.fromRGB(190, 194, 206)
	rotationStepLabel.TextXAlignment = Enum.TextXAlignment.Left
	rotationStepLabel.Text = "Rot Step"
	rotationStepLabel.Parent = frame

	local rotationStepBox = Instance.new("TextBox")
	rotationStepBox.Name = "RotationStepBox"
	rotationStepBox.Position = UDim2.new(0, 214, 0, 326)
	rotationStepBox.Size = UDim2.new(0, 74, 0, 22)
	rotationStepBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	rotationStepBox.BorderSizePixel = 0
	rotationStepBox.Font = Enum.Font.Gotham
	rotationStepBox.TextSize = 12
	rotationStepBox.TextColor3 = Color3.fromRGB(240, 240, 240)
	rotationStepBox.PlaceholderText = tostring(DEFAULT_ROTATION_STEP)
	rotationStepBox.Text = tostring(self.RotationStep)
	rotationStepBox.Parent = frame

	local rotationStepCorner = Instance.new("UICorner")
	rotationStepCorner.CornerRadius = UDim.new(0, 8)
	rotationStepCorner.Parent = rotationStepBox

	local xMinusButton = self:_createButton(frame, "X-", UDim2.new(0, 12, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(-step, 0, 0), Vector3.zero)
	end)
	local xPlusButton = self:_createButton(frame, "X+", UDim2.new(0, 58, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(step, 0, 0), Vector3.zero)
	end)
	local yMinusButton = self:_createButton(frame, "Y-", UDim2.new(0, 106, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(0, -step, 0), Vector3.zero)
	end)
	local yPlusButton = self:_createButton(frame, "Y+", UDim2.new(0, 152, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(0, step, 0), Vector3.zero)
	end)
	local zMinusButton = self:_createButton(frame, "Z-", UDim2.new(0, 200, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(0, 0, -step), Vector3.zero)
	end)
	local zPlusButton = self:_createButton(frame, "Z+", UDim2.new(0, 246, 0, 356), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getPositionStep()
		self:_adjustAttachment(Vector3.new(0, 0, step), Vector3.zero)
	end)

	local pitchMinusButton = self:_createButton(frame, "P-", UDim2.new(0, 12, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(-step, 0, 0))
	end)
	local pitchPlusButton = self:_createButton(frame, "P+", UDim2.new(0, 58, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(step, 0, 0))
	end)
	local yawMinusButton = self:_createButton(frame, "Yw-", UDim2.new(0, 106, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(0, -step, 0))
	end)
	local yawPlusButton = self:_createButton(frame, "Yw+", UDim2.new(0, 152, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(0, step, 0))
	end)
	local rollMinusButton = self:_createButton(frame, "R-", UDim2.new(0, 200, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(0, 0, -step))
	end)
	local rollPlusButton = self:_createButton(frame, "R+", UDim2.new(0, 246, 0, 386), UDim2.new(0, 42, 0, 22), function()
		local step = self:_getRotationStep()
		self:_adjustAttachment(Vector3.zero, Vector3.new(0, 0, step))
	end)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 12, 0, 420)
	statusLabel.Size = UDim2.new(1, -24, 0, 188)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 11
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = Color3.fromRGB(124, 214, 166)
	statusLabel.Parent = frame

	self.UI = {
		Root = screenGui,
		Frame = frame,
		StateLabel = stateLabel,
		WeaponName = weaponName,
		LoadButton = loadButton,
		ResetButton = resetButton,
		PerspectiveButton = perspectiveButton,
		AimButton = aimButton,
		FireButton = fireButton,
		ReloadButton = reloadButton,
		EquipButton = equipButton,
		CaptureStaticButton = captureStaticButton,
		ClearStaticButton = clearStaticButton,
		AutoRefreshButton = autoRefreshButton,
		DebugPointsButton = debugPointsButton,
		ShowLiveButton = showLiveButton,
		AttachmentLabel = attachmentLabel,
		AttachmentName = attachmentName,
		PositionStepBox = positionStepBox,
		RotationStepBox = rotationStepBox,
		ResetAttachmentButton = resetAttachmentButton,
		XMinusButton = xMinusButton,
		XPlusButton = xPlusButton,
		YMinusButton = yMinusButton,
		YPlusButton = yPlusButton,
		ZMinusButton = zMinusButton,
		ZPlusButton = zPlusButton,
		PitchMinusButton = pitchMinusButton,
		PitchPlusButton = pitchPlusButton,
		YawMinusButton = yawMinusButton,
		YawPlusButton = yawPlusButton,
		RollMinusButton = rollMinusButton,
		RollPlusButton = rollPlusButton,
		StatusLabel = statusLabel,
	}
end

function WeaponLabController:_refreshUi()
	if not self.UI then
		return
	end

	local selectedWeaponId = self:_getSelectedWeaponId()
	local selectedDefinition = selectedWeaponId and WeaponDefinitions[selectedWeaponId] or nil
	local liveWeaponId = self.State and self.State.SelectedWeaponId or nil
	local liveDefinition = liveWeaponId and WeaponDefinitions[liveWeaponId] or nil
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	local labStatus = self.ViewmodelController and self.ViewmodelController.GetLabStatus and self.ViewmodelController:GetLabStatus() or nil
	local labEnabled = labStatus and labStatus.Enabled == true
	local showLiveRig = labStatus and labStatus.ShowSourceRig == true
	local staticCaptured = labStatus and labStatus.StaticRigCaptured == true
	local autoRefreshStatic = labStatus and labStatus.AutoRefreshStatic == true
	local debugPointsEnabled = labStatus and labStatus.DebugPointsEnabled == true
	local firearmIkStatus = labStatus and labStatus.FirearmIk or nil
	local firearmSolverMode = labStatus and labStatus.FirearmSolverMode or "LegacySingleArm"
	local firearmSolveDebug = labStatus and labStatus.FirearmSolveDebug or nil
	local handSocketStatus = labStatus and labStatus.HandSocketStatus or nil
	local selectedAttachmentName = labStatus and labStatus.SelectedAttachmentName or ATTACHMENT_EDITOR_NAMES[1]
	local isPositionOnlyEditor = selectedAttachmentName == "RightShoulderBase"
		or selectedAttachmentName == "LeftShoulderBase"
		or selectedAttachmentName == "RightElbowPole"
		or selectedAttachmentName == "LeftElbowPole"
	local selectedAttachmentOverride = labStatus and labStatus.SelectedAttachmentOverride or {
		Position = Vector3.zero,
		Rotation = Vector3.zero,
	}
	local attachmentDump = labStatus and labStatus.AttachmentOverrideDump or "No attachment override data."
	local perspectiveLabel = self.CameraInputController and (self.CameraInputController:IsFirstPerson() and "First Person" or "Third Person") or "Unknown"
	local ikSummary = string.format(
		"IK: %s  |  R: %s (%.2f)  |  L: %s (%.2f)",
		(firearmIkStatus and firearmIkStatus.Active) and "On" or "Off",
		(firearmIkStatus and firearmIkStatus.RightTargetAvailable) and "Target" or "Missing",
		tonumber(firearmIkStatus and firearmIkStatus.RightInfluence) or 0,
		(firearmIkStatus and firearmIkStatus.LeftTargetAvailable) and "Target" or "Missing",
		tonumber(firearmIkStatus and firearmIkStatus.LeftInfluence) or 0
	)
	local rightSolveDebug = firearmSolveDebug and firearmSolveDebug.RightShoulder or nil
	local leftSolveDebug = firearmSolveDebug and firearmSolveDebug.LeftShoulder or nil
	local solveSummary = string.format(
		"Solve Δ  |  R: %.3f, %.3f, %.3f  |  L: %.3f, %.3f, %.3f",
		rightSolveDebug and rightSolveDebug.FinalCorrectionPosition and rightSolveDebug.FinalCorrectionPosition.X or 0,
		rightSolveDebug and rightSolveDebug.FinalCorrectionPosition and rightSolveDebug.FinalCorrectionPosition.Y or 0,
		rightSolveDebug and rightSolveDebug.FinalCorrectionPosition and rightSolveDebug.FinalCorrectionPosition.Z or 0,
		leftSolveDebug and leftSolveDebug.FinalCorrectionPosition and leftSolveDebug.FinalCorrectionPosition.X or 0,
		leftSolveDebug and leftSolveDebug.FinalCorrectionPosition and leftSolveDebug.FinalCorrectionPosition.Y or 0,
		leftSolveDebug and leftSolveDebug.FinalCorrectionPosition and leftSolveDebug.FinalCorrectionPosition.Z or 0
	)

	local socketSummary = string.format(
		"Sockets  |  Runtime R: %s  |  Runtime L: %s  |  Static R: %s  |  Static L: %s",
		tostring(handSocketStatus and handSocketStatus.RuntimeRight or "Unknown"),
		tostring(handSocketStatus and handSocketStatus.RuntimeLeft or "Unknown"),
		tostring(handSocketStatus and handSocketStatus.StaticRight or "Unknown"),
		tostring(handSocketStatus and handSocketStatus.StaticLeft or "Unknown")
	)

	self.UI.WeaponName.Text = selectedDefinition and (selectedDefinition.DisplayName or selectedWeaponId) or "-"
	self.UI.AttachmentLabel.Text = isPositionOnlyEditor and "Rig / Attachment Editor (Pos Only)" or "Rig / Attachment Editor"
	self.UI.AttachmentName.Text = tostring(selectedAttachmentName)
	self.UI.StateLabel.Text = string.format("Selected: %s\nLoaded: %s\nPerspective: %s", tostring(selectedWeaponId or "-"), tostring(liveDefinition and (liveDefinition.DisplayName or liveWeaponId) or liveWeaponId or "-"), tostring(perspectiveLabel))
	self.UI.StatusLabel.Text = string.format(
		"Lab: %s  |  Static: %s  |  Auto Refresh: %s  |  Debug Points: %s  |  Live Rig: %s\nAim: %s\nSolver: %s\n%s\n%s\n%s\nEditor Pos: %.3f, %.3f, %.3f\nEditor Rot: %.1f, %.1f, %.1f\n%s\n%s",
		labEnabled and "On" or "Off",
		staticCaptured and "Captured" or "Empty",
		autoRefreshStatic and "On" or "Off",
		debugPointsEnabled and "On" or "Off",
		showLiveRig and "On" or "Off",
		(combatState and combatState.IsAiming) and "On" or "Off",
		tostring(firearmSolverMode),
		ikSummary,
		solveSummary,
		socketSummary,
		selectedAttachmentOverride.Position.X,
		selectedAttachmentOverride.Position.Y,
		selectedAttachmentOverride.Position.Z,
		selectedAttachmentOverride.Rotation.X,
		selectedAttachmentOverride.Rotation.Y,
		selectedAttachmentOverride.Rotation.Z,
		attachmentDump,
		tostring((self.State and self.State.Message) or "")
	)

	self.UI.CaptureStaticButton.BackgroundColor3 = staticCaptured and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.ClearStaticButton.BackgroundColor3 = staticCaptured and Color3.fromRGB(168, 57, 57) or Color3.fromRGB(54, 58, 70)
	self.UI.AutoRefreshButton.BackgroundColor3 = autoRefreshStatic and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.DebugPointsButton.BackgroundColor3 = debugPointsEnabled and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.ShowLiveButton.Text = showLiveRig and "Hide Live Rig" or "Show Live Rig"
	self.UI.ShowLiveButton.BackgroundColor3 = showLiveRig and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.AimButton.BackgroundColor3 = (combatState and combatState.IsAiming) and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.PerspectiveButton.Text = "Perspective: " .. tostring(perspectiveLabel)

	local rotationButtons = {
		self.UI.PitchMinusButton,
		self.UI.PitchPlusButton,
		self.UI.YawMinusButton,
		self.UI.YawPlusButton,
		self.UI.RollMinusButton,
		self.UI.RollPlusButton,
	}
	for _, button in ipairs(rotationButtons) do
		button.Active = not isPositionOnlyEditor
		button.AutoButtonColor = not isPositionOnlyEditor
		button.BackgroundColor3 = isPositionOnlyEditor and Color3.fromRGB(30, 34, 42) or Color3.fromRGB(40, 44, 54)
	end
end

return WeaponLabController
