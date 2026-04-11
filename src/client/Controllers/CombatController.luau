local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CombatController = {}
CombatController.Name = "CombatController"
CombatController.Dependencies = {
	"QTEController",
	"BreathHoldController",
}

local SLOT_HEIGHT = 24
local SLOT_PADDING = 6
local SLOT_WIDTH = 102
local BASE_CONTAINER_OFFSET_Y = -24
local SLOT_STACK_GAP = 10

function CombatController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.RequestPrimaryAttackRemote = self.Remotes:WaitForChild(RemoteNames.RequestPrimaryAttack)
	self.RequestMovementStateRemote = self.Remotes:WaitForChild(RemoteNames.RequestMovementState)
	self.RequestReloadRemote = self.Remotes:WaitForChild(RemoteNames.RequestReload)
	self.RequestEquipWeaponRemote = self.Remotes:WaitForChild(RemoteNames.RequestEquipWeapon)
	self.RequestUseInventoryItemRemote = self.Remotes:WaitForChild(RemoteNames.RequestUseInventoryItem)
	self.CombatStateChangedRemote = self.Remotes:WaitForChild(RemoteNames.CombatStateChanged)
	self.CombatHitConfirmedRemote = self.Remotes:WaitForChild(RemoteNames.CombatHitConfirmed)
	self.CombatShotVisualRemote = self.Remotes:WaitForChild(RemoteNames.CombatShotVisual)
	self.State = {
		EquippedWeaponId = nil,
		EquippedSlot = 1,
		DisplayName = "Unarmed",
		Durability = 0,
		MaxDurability = 0,
		CurrentAmmo = 0,
		MaxAmmo = 0,
		ReserveAmmo = 0,
		WeaponKind = nil,
		Cooldown = 0,
		MaxCooldown = 0,
		IsReloading = false,
		ReloadRemaining = 0,
		ReloadDuration = 0,
		IsBroken = false,
		Weapons = {},
		IsUsingItem = false,
		ItemUseDisplayName = nil,
		ItemUseRemaining = 0,
		ItemUseDuration = 0,
		IsAiming = false,
	}
	self.LastHitAt = 0
	self.LastHitTargetName = nil
	self.LocalAimHeld = false
end

function CombatController:Start()
	self:_createUI()

	self.CombatStateChangedRemote.OnClientEvent:Connect(function(payload)
		self.State = payload or self.State
		self:_refreshUi()
	end)

	self.CombatHitConfirmedRemote.OnClientEvent:Connect(function(payload)
		self.LastHitAt = os.clock()
		self.LastHitTargetName = payload and payload.TargetName or "Entity"
		self:_refreshUi()
	end)

	self.CombatShotVisualRemote.OnClientEvent:Connect(function(payload)
		self:_showShotVisual(payload)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self:_canAim() then
				self.LocalAimHeld = true
				self.RequestMovementStateRemote:FireServer(ActionName.Aim, true)
			end
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			if self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0 then
				return
			end

			if self.QTEController and self.QTEController:IsActive() then
				return
			end

			if self.BreathHoldController and self.BreathHoldController:RequiresHoldInput() then
				return
			end

			local requestedSlot = self:_getRequestedSlotFromInput(input)
			if requestedSlot then
				local slotState = self.State.Weapons and self.State.Weapons[requestedSlot]
				if slotState and slotState.EntryType == "Item" then
					self.RequestUseInventoryItemRemote:FireServer(requestedSlot)
				else
					self.RequestEquipWeaponRemote:FireServer(requestedSlot)
				end
			elseif input.KeyCode == Enum.KeyCode.R then
				self.RequestReloadRemote:FireServer()
			end
			return
		end

		if self.QTEController and self.QTEController:IsActive() then
			return
		end

		if self.BreathHoldController and self.BreathHoldController:RequiresHoldInput() then
			return
		end

		if self.State.IsBroken then
			return
		end

		if self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0 then
			return
		end

		if self.State.WeaponKind == "Firearm" and not self.State.IsAiming then
			return
		end

		self.RequestPrimaryAttackRemote:FireServer({
			Origin = self.World.Camera.CFrame.Position,
			Direction = self.World.Camera.CFrame.LookVector,
		})
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent and input.UserInputType ~= Enum.UserInputType.MouseButton2 then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.LocalAimHeld = false
			self.RequestMovementStateRemote:FireServer(ActionName.Aim, false)
		end
	end)

	RunService:BindToRenderStep("CombatController.AimFacing", Enum.RenderPriority.Character.Value + 1, function()
		self:_updateAimFacing()
	end)

	task.spawn(function()
		while true do
			if self.State.Cooldown and self.State.Cooldown > 0 then
				self.State.Cooldown = math.max(0, self.State.Cooldown - 0.05)
			end
			if self.State.ReloadRemaining and self.State.ReloadRemaining > 0 then
				self.State.ReloadRemaining = math.max(0, self.State.ReloadRemaining - 0.05)
				if self.State.ReloadRemaining <= 0 then
					self.State.IsReloading = false
				end
			end
			if self.State.ItemUseRemaining and self.State.ItemUseRemaining > 0 then
				self.State.ItemUseRemaining = math.max(0, self.State.ItemUseRemaining - 0.05)
			end

			self:_refreshUi()

			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientCombat", "[CombatController] Started")
end

function CombatController:_releaseAim()
	if not self.LocalAimHeld and not self.State.IsAiming then
		return
	end

	self.LocalAimHeld = false
	self.RequestMovementStateRemote:FireServer(ActionName.Aim, false)
end

function CombatController:_showShotVisual(payload)
	if type(payload) ~= "table" or typeof(payload.Origin) ~= "Vector3" or typeof(payload.EndPosition) ~= "Vector3" then
		return
	end

	local origin = payload.Origin
	local endPosition = payload.EndPosition
	local direction = endPosition - origin
	local distance = direction.Magnitude
	if distance <= 0.05 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "DebugShotTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = payload.Hit and Color3.fromRGB(124, 214, 166) or Color3.fromRGB(103, 194, 255)
	tracer.Transparency = 0.02
	tracer.Size = Vector3.new(0.22, 0.22, distance)
	tracer.CFrame = CFrame.lookAt(origin, endPosition) * CFrame.new(0, 0, -(distance * 0.5))
	tracer.Parent = Workspace

	local impact = Instance.new("Part")
	impact.Name = "DebugShotImpact"
	impact.Anchored = true
	impact.CanCollide = false
	impact.CanQuery = false
	impact.CanTouch = false
	impact.CastShadow = false
	impact.Material = Enum.Material.Neon
	impact.Shape = Enum.PartType.Ball
	impact.Color = tracer.Color
	impact.Transparency = 0.08
	impact.Size = Vector3.new(0.45, 0.45, 0.45)
	impact.Position = endPosition
	impact.Parent = Workspace

	Debris:AddItem(tracer, 0.18)
	Debris:AddItem(impact, 0.18)
end

function CombatController:_canAim()
	return self.State.WeaponKind == "Firearm"
		and not self.State.IsBroken
		and not (self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0)
		and not (self.QTEController and self.QTEController:IsActive())
		and not (self.BreathHoldController and self.BreathHoldController:RequiresHoldInput())
end

function CombatController:GetState()
	return self.State
end

function CombatController:IsRecentHit()
	return (os.clock() - (self.LastHitAt or 0)) <= 0.2
end

function CombatController:_updateAimFacing()
	if not self.State.IsAiming then
		return
	end

	local character = self.World:GetCharacter()
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local cameraLook = self.World.Camera.CFrame.LookVector
	local flatLook = Vector3.new(cameraLook.X, 0, cameraLook.Z)
	if flatLook.Magnitude <= 0.001 then
		return
	end

	local position = rootPart.Position
	rootPart.CFrame = CFrame.lookAt(position, position + flatLook.Unit)
end

function CombatController:_getRequestedSlotFromInput(input)
	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.One then
		return 1
	elseif keyCode == Enum.KeyCode.Two then
		return 2
	elseif keyCode == Enum.KeyCode.Three then
		return 3
	elseif keyCode == Enum.KeyCode.Four then
		return 4
	elseif keyCode == Enum.KeyCode.Five then
		return 5
	elseif keyCode == Enum.KeyCode.Six then
		return 6
	elseif keyCode == Enum.KeyCode.Seven then
		return 7
	elseif keyCode == Enum.KeyCode.Eight then
		return 8
	elseif keyCode == Enum.KeyCode.Nine then
		return 9
	end

	return nil
end

function CombatController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CombatUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 24, 1, BASE_CONTAINER_OFFSET_Y)
	container.Size = UDim2.new(0, 210, 0, 62)
	container.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	container.BackgroundTransparency = 0.08
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.Size = UDim2.new(1, -24, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = "Bushman Knife"
	nameLabel.Parent = container

	local durabilityLabel = Instance.new("TextLabel")
	durabilityLabel.Name = "DurabilityLabel"
	durabilityLabel.Position = UDim2.new(0, 12, 0, 28)
	durabilityLabel.Size = UDim2.new(0.55, 0, 0, 16)
	durabilityLabel.BackgroundTransparency = 1
	durabilityLabel.Font = Enum.Font.Gotham
	durabilityLabel.TextSize = 12
	durabilityLabel.TextColor3 = Color3.fromRGB(197, 197, 204)
	durabilityLabel.TextXAlignment = Enum.TextXAlignment.Left
	durabilityLabel.Text = "Durability 10/10"
	durabilityLabel.Parent = container

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Position = UDim2.new(1, -74, 0, 28)
	statusLabel.Size = UDim2.new(0, 62, 0, 16)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = Color3.fromRGB(214, 180, 64)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.Text = "READY"
	statusLabel.Parent = container

	local hitLabel = Instance.new("TextLabel")
	hitLabel.Name = "HitLabel"
	hitLabel.Position = UDim2.new(0, 12, 0, 44)
	hitLabel.Size = UDim2.new(1, -24, 0, 14)
	hitLabel.BackgroundTransparency = 1
	hitLabel.Font = Enum.Font.Gotham
	hitLabel.TextSize = 11
	hitLabel.TextColor3 = Color3.fromRGB(164, 224, 176)
	hitLabel.TextXAlignment = Enum.TextXAlignment.Left
	hitLabel.Text = ""
	hitLabel.Parent = container

	local cooldownBackground = Instance.new("Frame")
	cooldownBackground.Name = "CooldownBackground"
	cooldownBackground.Position = UDim2.new(0, 12, 1, -10)
	cooldownBackground.Size = UDim2.new(1, -24, 0, 5)
	cooldownBackground.BackgroundColor3 = Color3.fromRGB(48, 51, 60)
	cooldownBackground.BorderSizePixel = 0
	cooldownBackground.Parent = container

	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = UDim.new(0, 999)
	cooldownCorner.Parent = cooldownBackground

	local cooldownBar = Instance.new("Frame")
	cooldownBar.Name = "CooldownBar"
	cooldownBar.Size = UDim2.new(0, 0, 1, 0)
	cooldownBar.BackgroundColor3 = Color3.fromRGB(214, 180, 64)
	cooldownBar.BorderSizePixel = 0
	cooldownBar.Parent = cooldownBackground

	local cooldownBarCorner = Instance.new("UICorner")
	cooldownBarCorner.CornerRadius = UDim.new(0, 999)
	cooldownBarCorner.Parent = cooldownBar

	local slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "SlotsFrame"
	slotsFrame.AnchorPoint = Vector2.new(0, 1)
	slotsFrame.Position = UDim2.new(0, 0, 0, -SLOT_STACK_GAP)
	slotsFrame.Size = UDim2.new(0, SLOT_WIDTH, 0, 0)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = container

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Vertical
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	slotsLayout.Padding = UDim.new(0, 6)
	slotsLayout.Parent = slotsFrame

	self.UI = {
		Root = screenGui,
		Container = container,
		NameLabel = nameLabel,
		DurabilityLabel = durabilityLabel,
		StatusLabel = statusLabel,
		HitLabel = hitLabel,
		CooldownBar = cooldownBar,
		SlotsFrame = slotsFrame,
		SlotButtons = {},
	}

	self:_refreshUi()
end

function CombatController:_refreshSlots()
	local slotsFrame = self.UI and self.UI.SlotsFrame
	if not slotsFrame then
		return
	end

	local weaponCount = math.max(1, #(self.State.Weapons or {}))
	for index = 1, weaponCount do
		local slotButton = self.UI.SlotButtons[index]
		if not slotButton then
			slotButton = Instance.new("Frame")
			slotButton.Name = "Slot" .. tostring(index)
			slotButton.LayoutOrder = index
			slotButton.Size = UDim2.new(1, 0, 0, SLOT_HEIGHT)
			slotButton.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
			slotButton.BackgroundTransparency = 0.12
			slotButton.BorderSizePixel = 0
			slotButton.Parent = slotsFrame

			local slotCorner = Instance.new("UICorner")
			slotCorner.CornerRadius = UDim.new(0, 8)
			slotCorner.Parent = slotButton

			local keyBadge = Instance.new("TextLabel")
			keyBadge.Name = "KeyBadge"
			keyBadge.Position = UDim2.new(0, 4, 0, 4)
			keyBadge.Size = UDim2.new(0, 14, 0, 14)
			keyBadge.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
			keyBadge.BackgroundTransparency = 0.08
			keyBadge.BorderSizePixel = 0
			keyBadge.Font = Enum.Font.GothamBold
			keyBadge.TextSize = 9
			keyBadge.TextColor3 = Color3.fromRGB(20, 22, 28)
			keyBadge.Text = tostring(index)
			keyBadge.Parent = slotButton

			local keyCorner = Instance.new("UICorner")
			keyCorner.CornerRadius = UDim.new(0, 5)
			keyCorner.Parent = keyBadge

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "NameLabel"
			nameLabel.Position = UDim2.new(0, 20, 0, 0)
			nameLabel.Size = UDim2.new(1, -24, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 10
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = slotButton

			self.UI.SlotButtons[index] = slotButton
		end

		local slotState = self.State.Weapons[index]
		local isEquipped = (self.State.EquippedSlot or 1) == index
		local isBroken = slotState and slotState.IsBroken
		local isItem = slotState and slotState.EntryType == "Item"
		local keyBadge = slotButton:FindFirstChild("KeyBadge")
		local nameLabel = slotButton:FindFirstChild("NameLabel")
		slotButton.Visible = true
		slotButton.BackgroundColor3 = isEquipped and Color3.fromRGB(214, 180, 64) or (isItem and Color3.fromRGB(58, 86, 68) or Color3.fromRGB(34, 36, 44))
		if keyBadge then
			keyBadge.Text = tostring(index)
			keyBadge.BackgroundColor3 = isEquipped and Color3.fromRGB(20, 22, 28) or Color3.fromRGB(240, 240, 240)
			keyBadge.TextColor3 = isEquipped and Color3.fromRGB(242, 212, 103) or Color3.fromRGB(20, 22, 28)
		end

		if nameLabel then
			nameLabel.TextColor3 = isEquipped and Color3.fromRGB(20, 22, 28) or (isBroken and Color3.fromRGB(214, 94, 94) or Color3.fromRGB(224, 226, 232))
			nameLabel.Text = slotState and string.format("%s%s", slotState.ShortDisplayName or slotState.DisplayName, isItem and (" x" .. tostring(slotState.Count or 0)) or "") or "-"
		end
	end

	for index = weaponCount + 1, #self.UI.SlotButtons do
		self.UI.SlotButtons[index].Visible = false
	end

	local visibleSlotCount = #(self.State.Weapons or {})
	local slotsHeight = visibleSlotCount > 0 and ((visibleSlotCount * SLOT_HEIGHT) + (math.max(0, visibleSlotCount - 1) * SLOT_PADDING)) or 0
	slotsFrame.Size = UDim2.new(0, SLOT_WIDTH, 0, slotsHeight)
	slotsFrame.Position = UDim2.new(0, 0, 0, -SLOT_STACK_GAP)
end

function CombatController:_refreshUi()
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

	local maxDurability = math.max(0, self.State.MaxDurability or 0)
	local durability = math.max(0, self.State.Durability or 0)
	self.UI.NameLabel.Text = self.State.DisplayName or "Unarmed"
	if self.State.WeaponKind == "Firearm" then
		self.UI.DurabilityLabel.Text = string.format("Ammo %d/%d  |  Reserve %d", self.State.CurrentAmmo or 0, self.State.MaxAmmo or 0, self.State.ReserveAmmo or 0)
	else
		self.UI.DurabilityLabel.Text = string.format("Durability %d/%d", durability, maxDurability)
	end

	local statusText = "READY"
	local statusColor = Color3.fromRGB(214, 180, 64)
	local recentHit = (os.clock() - self.LastHitAt) <= 0.2
	if self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0 then
		statusText = "USE"
		statusColor = Color3.fromRGB(103, 194, 255)
	elseif self.State.IsReloading and (self.State.ReloadRemaining or 0) > 0 then
		statusText = "RELOAD"
		statusColor = Color3.fromRGB(103, 194, 255)
	elseif self.State.IsAiming and self.State.WeaponKind == "Firearm" then
		statusText = "AIM"
		statusColor = Color3.fromRGB(103, 194, 255)
	elseif self.State.IsBroken then
		statusText = "BROKEN"
		statusColor = Color3.fromRGB(214, 94, 94)
	elseif (self.State.Cooldown or 0) > 0 then
		statusText = "SWING"
		statusColor = Color3.fromRGB(240, 240, 240)
	end

	if recentHit then
		statusText = "HIT"
		statusColor = Color3.fromRGB(118, 208, 144)
	end

	self.UI.StatusLabel.Text = statusText
	self.UI.StatusLabel.TextColor3 = statusColor
	if self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0 then
		self.UI.HitLabel.Text = string.format("Using %s", self.State.ItemUseDisplayName or "Item")
	elseif self.State.IsReloading and (self.State.ReloadRemaining or 0) > 0 then
		self.UI.HitLabel.Text = string.format("Reloading %.1fs", self.State.ReloadRemaining or 0)
	else
		self.UI.HitLabel.Text = recentHit and string.format("Hit %s", self.LastHitTargetName or "Entity") or ""
	end

	local maxCooldown = self.State.MaxCooldown or 0
	local remaining = self.State.Cooldown or 0
	local maxProgressDuration = maxCooldown
	local progressRemaining = remaining
	if self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0 then
		maxProgressDuration = self.State.ItemUseDuration or 0
		progressRemaining = self.State.ItemUseRemaining or 0
	elseif self.State.IsReloading and (self.State.ReloadRemaining or 0) > 0 then
		maxProgressDuration = self.State.ReloadDuration or 0
		progressRemaining = self.State.ReloadRemaining or 0
	end

	local ratio = maxProgressDuration > 0 and math.clamp(1 - (progressRemaining / maxProgressDuration), 0, 1) or 1
	self.UI.CooldownBar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.CooldownBar.BackgroundColor3 = ((self.State.IsUsingItem and (self.State.ItemUseRemaining or 0) > 0) or (self.State.IsReloading and (self.State.ReloadRemaining or 0) > 0)) and Color3.fromRGB(103, 194, 255)
		or (recentHit and Color3.fromRGB(118, 208, 144) or ((self.State.IsAiming and self.State.WeaponKind == "Firearm") and Color3.fromRGB(103, 194, 255) or (self.State.IsBroken and Color3.fromRGB(214, 94, 94) or Color3.fromRGB(214, 180, 64))))
	self.UI.Container.BackgroundColor3 = recentHit and Color3.fromRGB(28, 44, 33) or Color3.fromRGB(18, 19, 24)

	if self.LocalAimHeld and not self:_canAim() then
		self:_releaseAim()
	end

	if self.LocalAimHeld and ((self.QTEController and self.QTEController:IsActive()) or (self.BreathHoldController and self.BreathHoldController:RequiresHoldInput())) then
		self:_releaseAim()
	end

	self:_refreshSlots()
end

return CombatController
