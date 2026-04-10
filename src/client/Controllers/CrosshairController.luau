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
	local isAimingFirearm = combatState and combatState.WeaponKind == "Firearm" and combatState.IsAiming
	local show = inRound and cameraLocked and isAimingFirearm

	self.UI.Root.Enabled = show
	if not show then
		return
	end

	local color = Color3.fromRGB(240, 240, 240)
	local alpha = 0.08
	local rootPosition = UDim2.fromScale(0.5, 0.5)
	if isAimingFirearm then
		color = Color3.fromRGB(103, 194, 255)
		alpha = 0
		rootPosition = self:_getProjectedReticlePosition() or rootPosition
	elseif self.CombatController and self.CombatController:IsRecentHit() then
		color = Color3.fromRGB(124, 214, 166)
		alpha = 0
	end

	self.UI.Container.Position = rootPosition

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
