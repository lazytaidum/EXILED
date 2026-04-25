local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local TransformUtils = require(ReplicatedStorage.Shared.Utility.TransformUtils)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)

local WeaponLabController = {}
WeaponLabController.Name = "WeaponLabController"

WeaponLabController.TransformOrder = {
	"WeaponOffset",
	"AimOffset",
	"RightHandGrip",
	"LeftHandGrip",
	"RightShoulder",
	"LeftShoulder",
}

WeaponLabController.AxisOrder = {
	{ Group = "Position", Axis = "X" },
	{ Group = "Position", Axis = "Y" },
	{ Group = "Position", Axis = "Z" },
	{ Group = "Rotation", Axis = "X" },
	{ Group = "Rotation", Axis = "Y" },
	{ Group = "Rotation", Axis = "Z" },
}

local PANEL_BACKGROUND = Color3.fromRGB(17, 22, 31)
local PANEL_SURFACE = Color3.fromRGB(27, 35, 48)
local PANEL_ELEVATED = Color3.fromRGB(38, 48, 64)
local PANEL_MUTED = Color3.fromRGB(87, 102, 126)
local PANEL_TEXT = Color3.fromRGB(238, 243, 247)
local PANEL_SUBTEXT = Color3.fromRGB(160, 176, 194)
local PANEL_ACCENT = Color3.fromRGB(87, 197, 182)
local PANEL_WARNING = Color3.fromRGB(255, 202, 87)

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent

	return corner
end

local function createStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent

	return stroke
end

local function createPadding(parent, left, right, top, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingRight = UDim.new(0, right or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingBottom = UDim.new(0, bottom or 0)
	padding.Parent = parent

	return padding
end

local function createLabel(name, text, size, parent)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = PANEL_TEXT
	label.TextSize = 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent

	return label
end

local function createButton(name, text, size, parent)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.AutoButtonColor = false
	button.BackgroundColor3 = PANEL_ELEVATED
	button.Font = Enum.Font.GothamSemibold
	button.Text = text
	button.TextColor3 = PANEL_TEXT
	button.TextSize = 14
	button.Parent = parent

	createCorner(button, 10)
	createStroke(button, Color3.fromRGB(74, 92, 118), 1, 0.15)

	return button
end

local function createInput(name, size, parent)
	local input = Instance.new("TextBox")
	input.Name = name
	input.Size = size
	input.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Code
	input.PlaceholderColor3 = PANEL_MUTED
	input.TextColor3 = PANEL_TEXT
	input.PlaceholderText = "0"
	input.TextSize = 14
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Parent = parent

	createCorner(input, 8)
	createStroke(input, Color3.fromRGB(73, 86, 112), 1, 0.2)
	createPadding(input, 10, 10, 0, 0)

	return input
end

local function setButtonSelected(button, isSelected)
	button.BackgroundColor3 = if isSelected then PANEL_ACCENT else PANEL_ELEVATED
	button.TextColor3 = if isSelected then Color3.fromRGB(7, 19, 20) else PANEL_TEXT
end

local function setLinkPart(part, startPosition, endPosition, thickness)
	local delta = endPosition - startPosition
	local length = math.max(delta.Magnitude, 0.001)

	part.Size = Vector3.new(thickness, thickness, length)
	part.CFrame = CFrame.lookAt(startPosition, endPosition) * CFrame.new(0, 0, -length / 2)
end

local function getFirstWeaponId()
	local weaponIds = {}

	for weaponId, definition in pairs(WeaponDefinitions) do
		if definition.ViewModelLab then
			table.insert(weaponIds, weaponId)
		end
	end

	table.sort(weaponIds)

	return weaponIds
end

function WeaponLabController:Init(controllers)
	self.Controllers = controllers
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	self.WeaponIds = getFirstWeaponId()
	self.SelectedWeaponIndex = 1
	self.SelectedTransformName = self.TransformOrder[1]
	self.PositionStep = 0.05
	self.RotationStep = 2.5
	self.IsVisible = false
	self.AxisInputs = {}
	self.TransformButtons = {}
	self.PreviewConfig = {}
	self.SourceTransforms = {}
	self.WorkingTransforms = {}

	if #self.WeaponIds > 0 then
		self:LoadWeapon(self.WeaponIds[self.SelectedWeaponIndex])
	end

	self:BuildUI()
	self:BuildPreview()
end

function WeaponLabController:Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		self:HandleGlobalInput(input, gameProcessedEvent)
	end)

	RunService.RenderStepped:Connect(function()
		if self.IsVisible then
			self:UpdatePreview(true)
		end
	end)

	self:RefreshAll()
	DebugLog:Log("WeaponLab", "[WeaponLabController] Started")
end

function WeaponLabController:IsOpen()
	return self.IsVisible
end

function WeaponLabController:IsCapturingInput()
	return self.IsVisible
end

function WeaponLabController:LoadWeapon(weaponId)
	local definition = WeaponDefinitions[weaponId]
	if not definition or not definition.ViewModelLab then
		return
	end

	self.SelectedWeaponId = weaponId
	self.WeaponDefinition = definition
	self.PreviewConfig = definition.ViewModelLab.Preview or {}
	self.SourceTransforms = TransformUtils.CloneTransformMap(definition.ViewModelLab.Transforms or {})
	self.WorkingTransforms = TransformUtils.CloneTransformMap(self.SourceTransforms)
end

function WeaponLabController:GetSelectedTransform()
	if not self.WorkingTransforms then
		return nil
	end

	if not self.WorkingTransforms[self.SelectedTransformName] then
		self.WorkingTransforms[self.SelectedTransformName] = {
			Position = { X = 0, Y = 0, Z = 0 },
			Rotation = { X = 0, Y = 0, Z = 0 },
		}
	end

	return self.WorkingTransforms[self.SelectedTransformName]
end

function WeaponLabController:BuildUI()
	local root = Instance.new("ScreenGui")
	root.Name = "WeaponLabUI"
	root.ResetOnSpawn = false
	root.IgnoreGuiInset = true
	root.Enabled = false
	root.DisplayOrder = 25
	root.Parent = self.PlayerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 1220, 0, 730)
	panel.BackgroundColor3 = PANEL_BACKGROUND
	panel.Parent = root

	createCorner(panel, 18)
	createStroke(panel, Color3.fromRGB(78, 97, 124), 1, 0.1)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 82)
	header.Parent = panel

	local title = createLabel("Title", "Weapon Lab", UDim2.new(0, 500, 0, 34), header)
	title.Position = UDim2.new(0, 24, 0, 14)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 26

	local subtitle = createLabel(
		"Subtitle",
		"Live offset + grip tuning for viewmodels, tools, and animation anchors. Toggle with F6.",
		UDim2.new(1, -48, 0, 24),
		header
	)
	subtitle.Position = UDim2.new(0, 24, 0, 46)
	subtitle.TextColor3 = PANEL_SUBTEXT
	subtitle.TextSize = 14

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 0, 0, 82)
	body.Size = UDim2.new(1, 0, 1, -82)
	body.Parent = panel

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundTransparency = 1
	sidebar.Position = UDim2.new(0, 20, 0, 0)
	sidebar.Size = UDim2.new(0, 420, 1, -20)
	sidebar.Parent = body

	local viewportCard = Instance.new("Frame")
	viewportCard.Name = "ViewportCard"
	viewportCard.BackgroundColor3 = PANEL_SURFACE
	viewportCard.Position = UDim2.new(0, 460, 0, 0)
	viewportCard.Size = UDim2.new(1, -480, 1, -20)
	viewportCard.Parent = body

	createCorner(viewportCard, 16)
	createStroke(viewportCard, Color3.fromRGB(74, 92, 118), 1, 0.15)

	local viewportLabel = createLabel("ViewportLabel", "Live Preview", UDim2.new(1, -32, 0, 24), viewportCard)
	viewportLabel.Position = UDim2.new(0, 16, 0, 14)
	viewportLabel.Font = Enum.Font.GothamSemibold
	viewportLabel.TextSize = 18

	local viewportHint = createLabel(
		"ViewportHint",
		"Selected controls update the proxy rig in real time. Use this to tune shoulders, grips, offsets, and sight alignment before moving to your real asset.",
		UDim2.new(1, -32, 0, 36),
		viewportCard
	)
	viewportHint.Position = UDim2.new(0, 16, 0, 40)
	viewportHint.TextColor3 = PANEL_SUBTEXT
	viewportHint.TextSize = 13

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundColor3 = Color3.fromRGB(10, 14, 21)
	viewport.Position = UDim2.new(0, 16, 0, 92)
	viewport.Size = UDim2.new(1, -32, 1, -156)
	viewport.Parent = viewportCard

	createCorner(viewport, 16)
	createStroke(viewport, Color3.fromRGB(64, 80, 102), 1, 0.15)

	local statusLabel = createLabel("Status", "", UDim2.new(1, -32, 0, 30), viewportCard)
	statusLabel.Position = UDim2.new(0, 16, 1, -54)
	statusLabel.TextColor3 = PANEL_WARNING
	statusLabel.TextSize = 13

	local sectionsLayout = Instance.new("UIListLayout")
	sectionsLayout.Padding = UDim.new(0, 12)
	sectionsLayout.FillDirection = Enum.FillDirection.Vertical
	sectionsLayout.Parent = sidebar

	local weaponCard = self:CreateCard(sidebar, 126)
	local weaponTitle = createLabel("WeaponTitle", "Weapon", UDim2.new(1, -24, 0, 22), weaponCard)
	weaponTitle.Position = UDim2.new(0, 12, 0, 10)
	weaponTitle.Font = Enum.Font.GothamSemibold
	weaponTitle.TextSize = 18

	local weaponName = createLabel("WeaponName", "", UDim2.new(1, -24, 0, 24), weaponCard)
	weaponName.Position = UDim2.new(0, 12, 0, 38)
	weaponName.TextSize = 17

	local weaponHint = createLabel(
		"WeaponHint",
		"Cycle definitions here. Every transform below edits a local working copy and the export updates instantly.",
		UDim2.new(1, -24, 0, 36),
		weaponCard
	)
	weaponHint.Position = UDim2.new(0, 12, 0, 64)
	weaponHint.TextColor3 = PANEL_SUBTEXT
	weaponHint.TextSize = 13

	local previousButton = createButton("PreviousWeapon", "<", UDim2.new(0, 44, 0, 36), weaponCard)
	previousButton.Position = UDim2.new(1, -104, 0, 16)

	local nextButton = createButton("NextWeapon", ">", UDim2.new(0, 44, 0, 36), weaponCard)
	nextButton.Position = UDim2.new(1, -56, 0, 16)

	local transformCard = self:CreateCard(sidebar, 162)
	local transformTitle = createLabel("TransformTitle", "Transform Set", UDim2.new(1, -24, 0, 22), transformCard)
	transformTitle.Position = UDim2.new(0, 12, 0, 10)
	transformTitle.Font = Enum.Font.GothamSemibold
	transformTitle.TextSize = 18

	local transformContainer = Instance.new("Frame")
	transformContainer.Name = "TransformContainer"
	transformContainer.BackgroundTransparency = 1
	transformContainer.Position = UDim2.new(0, 12, 0, 42)
	transformContainer.Size = UDim2.new(1, -24, 1, -54)
	transformContainer.Parent = transformCard

	local transformLayout = Instance.new("UIGridLayout")
	transformLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	transformLayout.CellSize = UDim2.new(0.5, -5, 0, 42)
	transformLayout.Parent = transformContainer

	for _, transformName in ipairs(self.TransformOrder) do
		local transformButton = createButton(transformName, self:FormatTransformLabel(transformName), UDim2.new(0, 0, 0, 42), transformContainer)
		transformButton.MouseButton1Click:Connect(function()
			self.SelectedTransformName = transformName
			self:RefreshAll()
		end)

		self.TransformButtons[transformName] = transformButton
	end

	local editorCard = self:CreateCard(sidebar, 286)
	local editorTitle = createLabel("EditorTitle", "Numeric Tweaks", UDim2.new(1, -24, 0, 22), editorCard)
	editorTitle.Position = UDim2.new(0, 12, 0, 10)
	editorTitle.Font = Enum.Font.GothamSemibold
	editorTitle.TextSize = 18

	local editorHint = createLabel(
		"EditorHint",
		"Use the plus/minus nudges or type exact values. Position is in studs. Rotation is in degrees.",
		UDim2.new(1, -24, 0, 34),
		editorCard
	)
	editorHint.Position = UDim2.new(0, 12, 0, 34)
	editorHint.TextColor3 = PANEL_SUBTEXT
	editorHint.TextSize = 13

	local editorRows = Instance.new("Frame")
	editorRows.Name = "EditorRows"
	editorRows.BackgroundTransparency = 1
	editorRows.Position = UDim2.new(0, 12, 0, 74)
	editorRows.Size = UDim2.new(1, -24, 0, 146)
	editorRows.Parent = editorCard

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 6)
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.Parent = editorRows

	for _, axisInfo in ipairs(self.AxisOrder) do
		local axisKey = axisInfo.Group .. axisInfo.Axis
		local row = Instance.new("Frame")
		row.Name = axisKey
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.Parent = editorRows

		local rowLabel = createLabel("Label", axisInfo.Group .. " " .. axisInfo.Axis, UDim2.new(0, 120, 1, 0), row)
		rowLabel.TextSize = 14

		local minusButton = createButton("Minus", "-", UDim2.new(0, 34, 1, 0), row)
		minusButton.Position = UDim2.new(0, 128, 0, 0)

		local valueBox = createInput("Value", UDim2.new(1, -214, 1, 0), row)
		valueBox.Position = UDim2.new(0, 170, 0, 0)

		local plusButton = createButton("Plus", "+", UDim2.new(0, 34, 1, 0), row)
		plusButton.Position = UDim2.new(1, -34, 0, 0)

		minusButton.MouseButton1Click:Connect(function()
			self:NudgeAxis(axisInfo.Group, axisInfo.Axis, -self:GetStep(axisInfo.Group))
		end)

		plusButton.MouseButton1Click:Connect(function()
			self:NudgeAxis(axisInfo.Group, axisInfo.Axis, self:GetStep(axisInfo.Group))
		end)

		valueBox.FocusLost:Connect(function(enterPressed)
			if not enterPressed then
				self:RefreshAxisFields()
				return
			end

			local value = tonumber(valueBox.Text)
			if value then
				self:SetAxisValue(axisInfo.Group, axisInfo.Axis, value)
			else
				self:SetStatus(string.format("Could not parse %s %s as a number.", axisInfo.Group, axisInfo.Axis))
			end

			self:RefreshAll()
		end)

		self.AxisInputs[axisKey] = valueBox
	end

	local stepsRow = Instance.new("Frame")
	stepsRow.Name = "StepsRow"
	stepsRow.BackgroundTransparency = 1
	stepsRow.Position = UDim2.new(0, 12, 0, 228)
	stepsRow.Size = UDim2.new(1, -24, 0, 26)
	stepsRow.Parent = editorCard

	local positionStepLabel = createLabel("PositionStepLabel", "Position Step", UDim2.new(0, 110, 1, 0), stepsRow)
	positionStepLabel.TextSize = 14

	local positionStepBox = createInput("PositionStep", UDim2.new(0, 70, 1, 0), stepsRow)
	positionStepBox.Position = UDim2.new(0, 112, 0, 0)

	local rotationStepLabel = createLabel("RotationStepLabel", "Rotation Step", UDim2.new(0, 110, 1, 0), stepsRow)
	rotationStepLabel.Position = UDim2.new(0, 196, 0, 0)
	rotationStepLabel.TextSize = 14

	local rotationStepBox = createInput("RotationStep", UDim2.new(0, 70, 1, 0), stepsRow)
	rotationStepBox.Position = UDim2.new(0, 308, 0, 0)

	positionStepBox.FocusLost:Connect(function(enterPressed)
		self:HandleStepFocusLost(positionStepBox, "Position", enterPressed)
	end)

	rotationStepBox.FocusLost:Connect(function(enterPressed)
		self:HandleStepFocusLost(rotationStepBox, "Rotation", enterPressed)
	end)

	local actionsRow = Instance.new("Frame")
	actionsRow.Name = "ActionsRow"
	actionsRow.BackgroundTransparency = 1
	actionsRow.Position = UDim2.new(0, 12, 0, 258)
	actionsRow.Size = UDim2.new(1, -24, 0, 36)
	actionsRow.Parent = editorCard

	local resetTransformButton = createButton("ResetTransform", "Reset Transform", UDim2.new(0.5, -6, 1, 0), actionsRow)
	resetTransformButton.Position = UDim2.new(0, 0, 0, 0)
	resetTransformButton.MouseButton1Click:Connect(function()
		self:ResetSelectedTransform()
	end)

	local resetWeaponButton = createButton("ResetWeapon", "Reset Weapon", UDim2.new(0.5, -6, 1, 0), actionsRow)
	resetWeaponButton.Position = UDim2.new(0.5, 6, 0, 0)
	resetWeaponButton.MouseButton1Click:Connect(function()
		self:ResetWeaponTransforms()
	end)

	local exportCard = self:CreateCard(sidebar, 198)
	local exportTitle = createLabel("ExportTitle", "Export", UDim2.new(1, -24, 0, 22), exportCard)
	exportTitle.Position = UDim2.new(0, 12, 0, 10)
	exportTitle.Font = Enum.Font.GothamSemibold
	exportTitle.TextSize = 18

	local exportHint = createLabel(
		"ExportHint",
		"Copy this table back into the weapon definition once the pose feels right.",
		UDim2.new(1, -24, 0, 32),
		exportCard
	)
	exportHint.Position = UDim2.new(0, 12, 0, 34)
	exportHint.TextColor3 = PANEL_SUBTEXT
	exportHint.TextSize = 13

	local exportBox = Instance.new("TextBox")
	exportBox.Name = "ExportBox"
	exportBox.ClearTextOnFocus = false
	exportBox.MultiLine = true
	exportBox.TextEditable = true
	exportBox.TextWrapped = false
	exportBox.Font = Enum.Font.Code
	exportBox.TextSize = 14
	exportBox.TextXAlignment = Enum.TextXAlignment.Left
	exportBox.TextYAlignment = Enum.TextYAlignment.Top
	exportBox.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	exportBox.TextColor3 = PANEL_TEXT
	exportBox.Position = UDim2.new(0, 12, 0, 70)
	exportBox.Size = UDim2.new(1, -24, 1, -82)
	exportBox.Parent = exportCard

	createCorner(exportBox, 10)
	createStroke(exportBox, Color3.fromRGB(73, 86, 112), 1, 0.2)
	createPadding(exportBox, 10, 10, 10, 10)

	self.UI = {
		Root = root,
		WeaponName = weaponName,
		PreviousWeapon = previousButton,
		NextWeapon = nextButton,
		PositionStep = positionStepBox,
		RotationStep = rotationStepBox,
		ExportBox = exportBox,
		Viewport = viewport,
		StatusLabel = statusLabel,
	}

	previousButton.MouseButton1Click:Connect(function()
		self:SelectWeaponByDelta(-1)
	end)

	nextButton.MouseButton1Click:Connect(function()
		self:SelectWeaponByDelta(1)
	end)
end

function WeaponLabController:CreateCard(parent, height)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = PANEL_SURFACE
	card.Size = UDim2.new(1, 0, 0, height)
	card.Parent = parent

	createCorner(card, 16)
	createStroke(card, Color3.fromRGB(74, 92, 118), 1, 0.15)

	return card
end

function WeaponLabController:BuildPreview()
	local viewport = self.UI.Viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	self.Preview = {
		Camera = camera,
		WorldModel = worldModel,
		Parts = {},
	}

	self.Preview.Parts.Torso = self:CreatePreviewPart("Torso", Vector3.new(1.75, 1.9, 0.8), self.PreviewConfig.TorsoColor)
	self.Preview.Parts.RightShoulder = self:CreatePreviewPart("RightShoulder", Vector3.new(0.2, 0.2, 0.2), PANEL_WARNING, Enum.PartType.Ball)
	self.Preview.Parts.LeftShoulder = self:CreatePreviewPart("LeftShoulder", Vector3.new(0.2, 0.2, 0.2), PANEL_WARNING, Enum.PartType.Ball)
	self.Preview.Parts.RightHand = self:CreatePreviewPart("RightHand", Vector3.new(0.24, 0.24, 0.24), PANEL_ACCENT, Enum.PartType.Ball)
	self.Preview.Parts.LeftHand = self:CreatePreviewPart("LeftHand", Vector3.new(0.24, 0.24, 0.24), PANEL_ACCENT, Enum.PartType.Ball)
	self.Preview.Parts.RightArm = self:CreatePreviewPart("RightArm", Vector3.new(0.16, 0.16, 1), self.PreviewConfig.RightArmColor)
	self.Preview.Parts.LeftArm = self:CreatePreviewPart("LeftArm", Vector3.new(0.16, 0.16, 1), self.PreviewConfig.LeftArmColor)
	self.Preview.Parts.WeaponBody = self:CreatePreviewPart("WeaponBody", self.PreviewConfig.WeaponSize, self.PreviewConfig.WeaponColor)
	self.Preview.Parts.WeaponAccent = self:CreatePreviewPart("WeaponAccent", self.PreviewConfig.AccentSize, self.PreviewConfig.AccentColor)
	self.Preview.Parts.AimMarker = self:CreatePreviewPart("AimMarker", Vector3.new(0.16, 0.16, 0.16), PANEL_WARNING, Enum.PartType.Ball)
	self.Preview.Parts.Stage = self:CreatePreviewPart("Stage", Vector3.new(7.5, 0.15, 7.5), Color3.fromRGB(23, 31, 43))
	self.Preview.Parts.Backdrop = self:CreatePreviewPart("Backdrop", Vector3.new(8, 5.5, 0.15), Color3.fromRGB(14, 18, 24))

	self.Preview.Parts.Stage.CFrame = CFrame.new(0, -1.65, 0)
	self.Preview.Parts.Backdrop.CFrame = CFrame.new(0, 0.45, -2.5)

	self:UpdatePreview(false)
end

function WeaponLabController:CreatePreviewPart(name, size, color, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size or Vector3.new(1, 1, 1)
	part.Color = color or Color3.fromRGB(220, 220, 220)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = shape or Enum.PartType.Block
	part.Parent = self.Preview.WorldModel

	return part
end

function WeaponLabController:HandleGlobalInput(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.F6 then
		self:SetVisible(not self.IsVisible)
		return
	end

	if not self.IsVisible or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftBracket then
		self:SelectTransformByDelta(-1)
	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		self:SelectTransformByDelta(1)
	elseif input.KeyCode == Enum.KeyCode.BackSlash then
		self:ResetSelectedTransform()
	end
end

function WeaponLabController:SetVisible(isVisible)
	self.IsVisible = isVisible
	self.UI.Root.Enabled = isVisible

	if isVisible then
		self:SetStatus("Live editor open. [ and ] switch transforms. \\ resets the selected transform.")
	else
		self:SetStatus("")
	end

	self:RefreshAll()
end

function WeaponLabController:SetStatus(message)
	self.StatusMessage = message
	if self.UI and self.UI.StatusLabel then
		self.UI.StatusLabel.Text = message
	end
end

function WeaponLabController:SelectWeaponByDelta(delta)
	if #self.WeaponIds == 0 then
		return
	end

	self.SelectedWeaponIndex += delta
	if self.SelectedWeaponIndex < 1 then
		self.SelectedWeaponIndex = #self.WeaponIds
	elseif self.SelectedWeaponIndex > #self.WeaponIds then
		self.SelectedWeaponIndex = 1
	end

	self:LoadWeapon(self.WeaponIds[self.SelectedWeaponIndex])
	self:SetStatus(string.format("Loaded %s for tuning.", self.SelectedWeaponId))
	self:RefreshAll()
end

function WeaponLabController:SelectTransformByDelta(delta)
	local currentIndex = table.find(self.TransformOrder, self.SelectedTransformName) or 1
	currentIndex += delta

	if currentIndex < 1 then
		currentIndex = #self.TransformOrder
	elseif currentIndex > #self.TransformOrder then
		currentIndex = 1
	end

	self.SelectedTransformName = self.TransformOrder[currentIndex]
	self:SetStatus(string.format("Selected %s.", self:FormatTransformLabel(self.SelectedTransformName)))
	self:RefreshAll()
end

function WeaponLabController:GetStep(groupName)
	if groupName == "Rotation" then
		return self.RotationStep
	end

	return self.PositionStep
end

function WeaponLabController:HandleStepFocusLost(input, groupName, enterPressed)
	if not enterPressed then
		self:RefreshStepFields()
		return
	end

	local value = tonumber(input.Text)
	if not value or value <= 0 then
		self:SetStatus(string.format("%s step must be a positive number.", groupName))
		self:RefreshStepFields()
		return
	end

	if groupName == "Rotation" then
		self.RotationStep = value
	else
		self.PositionStep = value
	end

	self:SetStatus(string.format("%s step set to %s.", groupName, TransformUtils.FormatNumber(value)))
	self:RefreshStepFields()
end

function WeaponLabController:NudgeAxis(groupName, axisName, delta)
	local transform = self:GetSelectedTransform()
	if not transform then
		return
	end

	TransformUtils.AdjustAxis(transform, groupName, axisName, delta)
	self:SetStatus(
		string.format(
			"%s %s nudged by %s.",
			groupName,
			axisName,
			TransformUtils.FormatNumber(delta)
		)
	)
	self:RefreshAll()
end

function WeaponLabController:SetAxisValue(groupName, axisName, value)
	local transform = self:GetSelectedTransform()
	if not transform then
		return
	end

	TransformUtils.SetAxis(transform, groupName, axisName, value)
	self:SetStatus(
		string.format(
			"%s %s set to %s.",
			groupName,
			axisName,
			TransformUtils.FormatNumber(value)
		)
	)
end

function WeaponLabController:ResetSelectedTransform()
	if not self.SourceTransforms or not self.WorkingTransforms then
		return
	end

	self.WorkingTransforms[self.SelectedTransformName] = TransformUtils.CloneTransform(
		self.SourceTransforms[self.SelectedTransformName]
	)
	self:SetStatus(string.format("Reset %s to definition defaults.", self:FormatTransformLabel(self.SelectedTransformName)))
	self:RefreshAll()
end

function WeaponLabController:ResetWeaponTransforms()
	if not self.SourceTransforms then
		return
	end

	self.WorkingTransforms = TransformUtils.CloneTransformMap(self.SourceTransforms)
	self:SetStatus(string.format("Reset all %s transforms.", self.SelectedWeaponId))
	self:RefreshAll()
end

function WeaponLabController:RefreshAll()
	self.UI.Root.Enabled = self.IsVisible
	self:RefreshWeaponLabel()
	self:RefreshTransformButtons()
	self:RefreshAxisFields()
	self:RefreshStepFields()
	self:RefreshExportText()
	self:UpdatePreview(false)

	if self.StatusMessage then
		self.UI.StatusLabel.Text = self.StatusMessage
	end
end

function WeaponLabController:RefreshWeaponLabel()
	if not self.WeaponDefinition then
		self.UI.WeaponName.Text = "No weapon definitions expose `ViewModelLab` data yet."
		return
	end

	self.UI.WeaponName.Text = string.format(
		"%s  [%d / %d]",
		self.WeaponDefinition.DisplayName or self.SelectedWeaponId,
		self.SelectedWeaponIndex,
		#self.WeaponIds
	)
end

function WeaponLabController:RefreshTransformButtons()
	for transformName, button in pairs(self.TransformButtons) do
		setButtonSelected(button, transformName == self.SelectedTransformName)
	end
end

function WeaponLabController:RefreshAxisFields()
	local transform = self:GetSelectedTransform()
	if not transform then
		return
	end

	for _, axisInfo in ipairs(self.AxisOrder) do
		local axisKey = axisInfo.Group .. axisInfo.Axis
		local input = self.AxisInputs[axisKey]
		local value = transform[axisInfo.Group] and transform[axisInfo.Group][axisInfo.Axis] or 0
		input.Text = TransformUtils.FormatNumber(value)
	end
end

function WeaponLabController:RefreshStepFields()
	self.UI.PositionStep.Text = TransformUtils.FormatNumber(self.PositionStep)
	self.UI.RotationStep.Text = TransformUtils.FormatNumber(self.RotationStep)
end

function WeaponLabController:RefreshExportText()
	if not self.WorkingTransforms then
		self.UI.ExportBox.Text = "-- No weapon lab transforms available."
		return
	end

	self.UI.ExportBox.Text = string.format(
		"Transforms = %s",
		TransformUtils.FormatTransformMap(self.WorkingTransforms, "\t")
	)
end

function WeaponLabController:UpdatePreview(animateCamera)
	if not self.Preview or not self.WorkingTransforms then
		return
	end

	local previewParts = self.Preview.Parts
	local transforms = self.WorkingTransforms

	local torsoCF = CFrame.new(0, 0.05, 0)
	local rightShoulderCF = torsoCF * TransformUtils.ToCFrame(transforms.RightShoulder or {})
	local leftShoulderCF = torsoCF * TransformUtils.ToCFrame(transforms.LeftShoulder or {})
	local weaponCF = torsoCF * TransformUtils.ToCFrame(transforms.WeaponOffset or {})
	local rightHandCF = weaponCF * TransformUtils.ToCFrame(transforms.RightHandGrip or {})
	local leftHandCF = weaponCF * TransformUtils.ToCFrame(transforms.LeftHandGrip or {})
	local aimMarkerCF = weaponCF * TransformUtils.ToCFrame(transforms.AimOffset or {})

	local bodySize = self.PreviewConfig.WeaponSize or Vector3.new(0.55, 0.75, 1.7)
	local accentSize = self.PreviewConfig.AccentSize or Vector3.new(0.22, 0.22, 0.55)

	previewParts.Torso.CFrame = torsoCF
	previewParts.RightShoulder.CFrame = rightShoulderCF
	previewParts.LeftShoulder.CFrame = leftShoulderCF
	previewParts.RightHand.CFrame = rightHandCF
	previewParts.LeftHand.CFrame = leftHandCF
	previewParts.WeaponBody.Size = bodySize
	previewParts.WeaponBody.CFrame = weaponCF
	previewParts.WeaponAccent.Size = accentSize
	previewParts.WeaponAccent.CFrame = weaponCF * CFrame.new(0, 0.08, bodySize.Z * 0.3)
	previewParts.AimMarker.CFrame = aimMarkerCF

	setLinkPart(previewParts.RightArm, rightShoulderCF.Position, rightHandCF.Position, 0.17)
	setLinkPart(previewParts.LeftArm, leftShoulderCF.Position, leftHandCF.Position, 0.17)

	self:ApplyPreviewColors()

	local orbitAngle = if animateCamera then os.clock() * 0.28 else 0.9
	local cameraPosition = Vector3.new(math.cos(orbitAngle) * 5.8, 1.6, math.sin(orbitAngle) * 5.8)
	self.Preview.Camera.CFrame = CFrame.lookAt(cameraPosition, Vector3.new(0, 0.05, 0))
end

function WeaponLabController:ApplyPreviewColors()
	local previewParts = self.Preview.Parts

	previewParts.Torso.Color = self.PreviewConfig.TorsoColor or Color3.fromRGB(73, 90, 122)
	previewParts.RightArm.Color = self.PreviewConfig.RightArmColor or Color3.fromRGB(220, 184, 146)
	previewParts.LeftArm.Color = self.PreviewConfig.LeftArmColor or Color3.fromRGB(196, 160, 124)
	previewParts.WeaponBody.Color = self.PreviewConfig.WeaponColor or Color3.fromRGB(44, 44, 52)
	previewParts.WeaponAccent.Color = self.PreviewConfig.AccentColor or Color3.fromRGB(229, 174, 74)

	local selectedName = self.SelectedTransformName

	previewParts.RightShoulder.Color = if selectedName == "RightShoulder" then PANEL_ACCENT else PANEL_WARNING
	previewParts.LeftShoulder.Color = if selectedName == "LeftShoulder" then PANEL_ACCENT else PANEL_WARNING
	previewParts.RightHand.Color = if selectedName == "RightHandGrip" then PANEL_ACCENT else Color3.fromRGB(132, 212, 199)
	previewParts.LeftHand.Color = if selectedName == "LeftHandGrip" then PANEL_ACCENT else Color3.fromRGB(132, 212, 199)
	previewParts.AimMarker.Color = if selectedName == "AimOffset" then PANEL_ACCENT else PANEL_WARNING

	if selectedName == "WeaponOffset" then
		previewParts.WeaponBody.Color = Color3.fromRGB(92, 217, 201)
		previewParts.WeaponAccent.Color = Color3.fromRGB(255, 225, 122)
	end
end

function WeaponLabController:FormatTransformLabel(transformName)
	return string.gsub(transformName, "(%u)", " %1"):gsub("^ ", "")
end

return WeaponLabController
