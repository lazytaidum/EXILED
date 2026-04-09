local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")

local TOOLBAR_NAME = "EXILED Tools"
local BUTTON_NAME = "Distance Visualizer"
local WIDGET_ID = "EXILEDStudDistanceVisualizer"
local DEFAULT_RADIUS = 16

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toggleButton = toolbar:CreateButton(
	BUTTON_NAME,
	"Visualize stud distances around the current Studio selection.",
	"rbxassetid://115537602092385"
)
toggleButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	true,
	false,
	280,
	180,
	240,
	160
)

local widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
widget.Title = BUTTON_NAME

local radius = DEFAULT_RADIUS
local shapeMode = "Sphere"
local adornments = {}
local connections = {}

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function clearAdornments()
	for _, adornment in ipairs(adornments) do
		adornment:Destroy()
	end

	table.clear(adornments)
end

local function getAdornee(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	if instance:IsA("Attachment") and instance.Parent and instance.Parent:IsA("BasePart") then
		return instance.Parent
	end

	return nil
end

local function createAdornment(adornee)
	if shapeMode == "Circle" then
		local disc = Instance.new("CylinderHandleAdornment")
		disc.Name = "DistanceVisualizerCircle"
		disc.Adornee = adornee
		disc.AlwaysOnTop = true
		disc.ZIndex = 5
		disc.Transparency = 0.95
		disc.Color3 = Color3.fromRGB(0, 255, 0)
		disc.Radius = radius
		disc.Height = 0.08
		disc.CFrame = CFrame.Angles(math.rad(90), 0, 0)
		disc.Parent = CoreGui

		local outline = Instance.new("CylinderHandleAdornment")
		outline.Name = "DistanceVisualizerCircleOutline"
		outline.Adornee = adornee
		outline.AlwaysOnTop = true
		outline.ZIndex = 6
		outline.Transparency = 0.55
		outline.Color3 = Color3.fromRGB(0, 255, 0)
		outline.Radius = radius
		outline.Height = 0.01
		outline.CFrame = CFrame.Angles(math.rad(90), 0, 0)
		outline.Parent = CoreGui

		table.insert(adornments, disc)
		table.insert(adornments, outline)
		return
	end

	local sphere = Instance.new("SphereHandleAdornment")
	sphere.Name = "DistanceVisualizerAdornment"
	sphere.Adornee = adornee
	sphere.AlwaysOnTop = true
	sphere.ZIndex = 5
	sphere.Transparency = 0.9
	sphere.Color3 = Color3.fromRGB(0, 255, 0)
	sphere.Radius = radius
	sphere.Parent = CoreGui

	local outline = Instance.new("SphereHandleAdornment")
	outline.Name = "DistanceVisualizerOutline"
	outline.Adornee = adornee
	outline.AlwaysOnTop = true
	outline.ZIndex = 6
	outline.Transparency = 0.55
	outline.Color3 = Color3.fromRGB(0, 255, 0)
	outline.Radius = radius
	outline.Parent = CoreGui

	table.insert(adornments, sphere)
	table.insert(adornments, outline)
end

local function refreshAdornments()
	clearAdornments()

	if not widget.Enabled then
		return
	end

	local seen = {}
	for _, instance in ipairs(Selection:Get()) do
		local adornee = getAdornee(instance)
		if adornee and not seen[adornee] then
			seen[adornee] = true
			createAdornment(adornee)
		end
	end
end

local function setEnabled(isEnabled)
	widget.Enabled = isEnabled
	toggleButton:SetActive(isEnabled)
	refreshAdornments()
end

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(20, 24, 31)
root.BorderSizePixel = 0
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Parent = root

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Stud Distance Visualizer"
title.TextColor3 = Color3.fromRGB(236, 242, 247)
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = root

local description = Instance.new("TextLabel")
description.Name = "Description"
description.Size = UDim2.new(1, 0, 0, 42)
description.BackgroundTransparency = 1
description.Font = Enum.Font.Gotham
description.Text = "Select any part, model, or attachment to preview a spherical radius in studs."
description.TextWrapped = true
description.TextColor3 = Color3.fromRGB(177, 188, 199)
description.TextSize = 12
description.TextXAlignment = Enum.TextXAlignment.Left
description.TextYAlignment = Enum.TextYAlignment.Top
description.Parent = root

local row = Instance.new("Frame")
row.Name = "RadiusRow"
row.Size = UDim2.new(1, 0, 0, 36)
row.BackgroundTransparency = 1
row.Parent = root

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.Padding = UDim.new(0, 8)
rowLayout.Parent = row

local radiusLabel = Instance.new("TextLabel")
radiusLabel.Name = "RadiusLabel"
radiusLabel.Size = UDim2.new(0, 94, 1, 0)
radiusLabel.BackgroundTransparency = 1
radiusLabel.Font = Enum.Font.GothamMedium
radiusLabel.Text = "Radius (studs)"
radiusLabel.TextColor3 = Color3.fromRGB(210, 220, 228)
radiusLabel.TextSize = 13
radiusLabel.TextXAlignment = Enum.TextXAlignment.Left
radiusLabel.Parent = row

local radiusBox = Instance.new("TextBox")
radiusBox.Name = "RadiusBox"
radiusBox.Size = UDim2.new(1, -94, 1, 0)
radiusBox.BackgroundColor3 = Color3.fromRGB(31, 38, 48)
radiusBox.BorderSizePixel = 0
radiusBox.ClearTextOnFocus = false
radiusBox.Font = Enum.Font.Gotham
radiusBox.PlaceholderText = tostring(DEFAULT_RADIUS)
radiusBox.Text = tostring(DEFAULT_RADIUS)
radiusBox.TextColor3 = Color3.fromRGB(236, 242, 247)
radiusBox.TextSize = 14
radiusBox.Parent = row

local radiusCorner = Instance.new("UICorner")
radiusCorner.CornerRadius = UDim.new(0, 8)
radiusCorner.Parent = radiusBox

local shapeRow = Instance.new("Frame")
shapeRow.Name = "ShapeRow"
shapeRow.Size = UDim2.new(1, 0, 0, 36)
shapeRow.BackgroundTransparency = 1
shapeRow.Parent = root

local shapeRowLayout = Instance.new("UIListLayout")
shapeRowLayout.FillDirection = Enum.FillDirection.Horizontal
shapeRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
shapeRowLayout.Padding = UDim.new(0, 8)
shapeRowLayout.Parent = shapeRow

local shapeLabel = Instance.new("TextLabel")
shapeLabel.Name = "ShapeLabel"
shapeLabel.Size = UDim2.new(0, 94, 1, 0)
shapeLabel.BackgroundTransparency = 1
shapeLabel.Font = Enum.Font.GothamMedium
shapeLabel.Text = "Shape"
shapeLabel.TextColor3 = Color3.fromRGB(210, 220, 228)
shapeLabel.TextSize = 13
shapeLabel.TextXAlignment = Enum.TextXAlignment.Left
shapeLabel.Parent = shapeRow

local shapeButton = Instance.new("TextButton")
shapeButton.Name = "ShapeButton"
shapeButton.Size = UDim2.new(1, -94, 1, 0)
shapeButton.BackgroundColor3 = Color3.fromRGB(31, 38, 48)
shapeButton.BorderSizePixel = 0
shapeButton.Font = Enum.Font.Gotham
shapeButton.Text = shapeMode
shapeButton.TextColor3 = Color3.fromRGB(236, 242, 247)
shapeButton.TextSize = 14
shapeButton.Parent = shapeRow

local shapeCorner = Instance.new("UICorner")
shapeCorner.CornerRadius = UDim.new(0, 8)
shapeCorner.Parent = shapeButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, 0, 0, 32)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "Toggle the plugin on, then select objects in Studio."
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(132, 196, 165)
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = root

local function applyRadiusFromText()
	local parsed = tonumber(radiusBox.Text)
	if not parsed or parsed <= 0 then
		radiusBox.Text = tostring(radius)
		statusLabel.Text = "Enter a radius above 0 studs."
		statusLabel.TextColor3 = Color3.fromRGB(226, 145, 145)
		return
	end

	radius = parsed
	radiusBox.Text = tostring(radius)
	statusLabel.Text = string.format("Showing a %s stud radius around the current selection.", tostring(radius))
	statusLabel.TextColor3 = Color3.fromRGB(132, 196, 165)
	refreshAdornments()
	ChangeHistoryService:SetWaypoint("Updated Distance Visualizer Radius")
end

table.insert(connections, radiusBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		applyRadiusFromText()
		return
	end

	applyRadiusFromText()
end))

table.insert(connections, shapeButton.MouseButton1Click:Connect(function()
	shapeMode = if shapeMode == "Sphere" then "Circle" else "Sphere"
	shapeButton.Text = shapeMode
	statusLabel.Text = string.format("Showing a %s %s stud %s around the current selection.", shapeMode:lower(), tostring(radius), shapeMode == "Circle" and "radius" or "radius")
	statusLabel.TextColor3 = Color3.fromRGB(132, 196, 165)
	refreshAdornments()
end))

table.insert(connections, Selection.SelectionChanged:Connect(function()
	refreshAdornments()
end))

table.insert(connections, widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if not widget.Enabled then
		clearAdornments()
	else
		refreshAdornments()
	end
end))

table.insert(connections, plugin.Unloading:Connect(function()
	disconnectAll()
	clearAdornments()
end))

toggleButton.Click:Connect(function()
	setEnabled(not widget.Enabled)
end)

setEnabled(true)
