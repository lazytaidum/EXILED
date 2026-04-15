local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local FirearmAim = require(ReplicatedStorage.Shared.Utility.FirearmAim)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CrosshairController = {}
CrosshairController.Name = "CrosshairController"
CrosshairController.Dependencies = {
	"CombatController",
	"CameraInputController",
	"FirearmPresentationController",
	"RoundController",
}

function CrosshairController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Camera = self.World.Camera
end

function CrosshairController:Start()
	self:_createUi()

	task.spawn(function()
		while true do
			self:_refresh()
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientCombat", "[CrosshairController] Started")
end

function CrosshairController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrosshairUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.PlayerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 40, 0, 40)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local center = Instance.new("Frame")
	center.Name = "Center"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.new(0, 4, 0, 4)
	center.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	center.BorderSizePixel = 0
	center.Parent = root

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(1, 0)
	centerCorner.Parent = center

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 1)
	top.Position = UDim2.fromScale(0.5, 0.42)
	top.Size = UDim2.new(0, 2, 0, 8)
	top.BackgroundColor3 = center.BackgroundColor3
	top.BorderSizePixel = 0
	top.Parent = root

	local bottom = top:Clone()
	bottom.Name = "Bottom"
	bottom.AnchorPoint = Vector2.new(0.5, 0)
	bottom.Position = UDim2.fromScale(0.5, 0.58)
	bottom.Parent = root

	local left = Instance.new("Frame")
	left.Name = "Left"
	left.AnchorPoint = Vector2.new(1, 0.5)
	left.Position = UDim2.fromScale(0.42, 0.5)
	left.Size = UDim2.new(0, 8, 0, 2)
	left.BackgroundColor3 = center.BackgroundColor3
	left.BorderSizePixel = 0
	left.Parent = root

	local right = left:Clone()
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(0, 0.5)
	right.Position = UDim2.fromScale(0.58, 0.5)
	right.Parent = root

	self.UI = {
		Root = screenGui,
		Container = root,
		Center = center,
		Top = top,
		Bottom = bottom,
		Left = left,
		Right = right,
	}
end

function CrosshairController:_refresh()
	local roundState = self.RoundController and self.RoundController:GetState() or nil
	local inRound = roundState and (roundState.Phase == GamePhase.Preparation or roundState.Phase == GamePhase.Reception)
	local cameraLocked = self.CameraInputController and self.CameraInputController.IsLocked
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	local hasFirearmEquipped = combatState and combatState.WeaponKind == "Firearm"
	local isAimingFirearm = hasFirearmEquipped and combatState.IsAiming
	local isFirstPerson = self.CameraInputController and self.CameraInputController:IsFirstPerson()
	local show = inRound and cameraLocked and hasFirearmEquipped

	self.UI.Root.Enabled = show
	if not show then
		return
	end

	local color = isAimingFirearm and Color3.fromRGB(103, 194, 255) or Color3.fromRGB(240, 240, 240)
	local alpha = 0
	local rootPosition = self:_getProjectedReticlePosition() or UDim2.fromScale(0.5, 0.5)
	if self.CombatController and self.CombatController:IsRecentHit() then
		color = Color3.fromRGB(124, 214, 166)
	end

	local weaponDefinition = self.CombatController and self.CombatController:GetEquippedWeaponDefinition() or nil
	local handling = FirearmAim.GetHandlingData(weaponDefinition)
	local expansion = self.FirearmPresentationController and self.FirearmPresentationController:GetReticleExpansion() or 0
	local baseGap = isAimingFirearm
		and (6 + math.floor((handling.AimSpread or 0.5) * 3))
		or (8 + math.floor((handling.HipfireSpread or 3.5) * 2))
	if isFirstPerson then
		baseGap = math.max(5, baseGap - (isAimingFirearm and 2 or 3))
	end
	local gap = baseGap + math.floor(expansion * (isAimingFirearm and 8 or 14))
	local lineLength = isAimingFirearm and 8 or 10
	local lineThickness = isAimingFirearm and 2 or 3
	local rootSize = 24 + (gap * 2) + lineLength

	self.UI.Container.Position = rootPosition
	self.UI.Container.Size = UDim2.fromOffset(rootSize, rootSize)
	self.UI.Center.Size = UDim2.fromOffset(isAimingFirearm and 4 or 5, isAimingFirearm and 4 or 5)
	self.UI.Top.Position = UDim2.new(0.5, 0, 0.5, -gap)
	self.UI.Top.Size = UDim2.fromOffset(lineThickness, lineLength)
	self.UI.Bottom.Position = UDim2.new(0.5, 0, 0.5, gap)
	self.UI.Bottom.Size = UDim2.fromOffset(lineThickness, lineLength)
	self.UI.Left.Position = UDim2.new(0.5, -gap, 0.5, 0)
	self.UI.Left.Size = UDim2.fromOffset(lineLength, lineThickness)
	self.UI.Right.Position = UDim2.new(0.5, gap, 0.5, 0)
	self.UI.Right.Size = UDim2.fromOffset(lineLength, lineThickness)

	for _, key in ipairs({ "Center", "Top", "Bottom", "Left", "Right" }) do
		self.UI[key].BackgroundColor3 = color
		self.UI[key].BackgroundTransparency = alpha
	end
end

function CrosshairController:_getProjectedReticlePosition()
	local character = self.World:GetCharacter()
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local combatState = self.CombatController and self.CombatController:GetState() or nil
	local equippedWeaponId = combatState and combatState.EquippedWeaponId or nil
	local weaponDefinition = equippedWeaponId and WeaponDefinitions[equippedWeaponId] or nil
	local range = weaponDefinition and weaponDefinition.Range or 220
	local lookVector = FirearmAim.ResolveLookVector(rootPart.CFrame.LookVector, self.Camera.CFrame.LookVector)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { character }
	local mapBounds = Workspace:FindFirstChild("MapBounds")
	if mapBounds then
		table.insert(filter, mapBounds)
	end
	raycastParams.FilterDescendantsInstances = filter

	local worldPoint = FirearmAim.ResolveAimPoint(self.Camera.CFrame.Position, lookVector, range, raycastParams, Workspace)
	local screenPoint, onScreen = self.Camera:WorldToViewportPoint(worldPoint)
	if not onScreen then
		return nil
	end

	return UDim2.fromOffset(screenPoint.X, screenPoint.Y)
end

return CrosshairController
