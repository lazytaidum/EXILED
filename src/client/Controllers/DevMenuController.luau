local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local DevMenuController = {}
DevMenuController.Name = "DevMenuController"

local TOGGLE_KEY = Enum.KeyCode.RightShift
local TOGGLE_ACTION = "ToggleDevMenu"

local function _buildUniqueEntityIds()
	local ids = {}
	local seen = {}
	for _, definition in pairs(EntityDefinitions) do
		if definition.Id and not seen[definition.Id] then
			seen[definition.Id] = true
			table.insert(ids, definition.Id)
		end
	end
	table.sort(ids)
	return ids
end

local function _buildSortedIds(definitions)
	local ids = {}
	for id in pairs(definitions) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function DevMenuController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.RequestRemote = self.Remotes:WaitForChild(RemoteNames.RequestDevCommand)
	self.StateRemote = self.Remotes:WaitForChild(RemoteNames.DevStateChanged)
	self.Visible = false
	self.PlacementMode = nil
	self.EntityIds = _buildUniqueEntityIds()
	self.ItemIds = _buildSortedIds(ItemDefinitions)
	self.WeaponIds = _buildSortedIds(WeaponDefinitions)
	self.SelectedEntityIndex = 1
	self.SelectedItemIndex = 1
	self.SelectedWeaponIndex = 1
	self.DevState = {
		Phase = "Unknown",
		TimeLeft = 0,
		EscapeEnabled = true,
		GodMode = false,
		DebugUiEnabled = true,
		Message = "",
	}
	self.PlacementRaycastParams = RaycastParams.new()
	self.PlacementRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
end

function DevMenuController:Start()
	if not DebugFlags.Enabled or not DebugFlags.DevMenu then
		return
	end

	self:_createUI()
	self:_refreshUi()

	self.StateRemote.OnClientEvent:Connect(function(payload)
		self.DevState = payload or self.DevState
		self:_refreshUi()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.Visible then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_handlePlacementClick()
		end
	end)

	ContextActionService:BindActionAtPriority(
		TOGGLE_ACTION,
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Sink
			end

			self:_toggleVisible()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		TOGGLE_KEY
	)

	DebugLog:Log("ClientCombat", "[DevMenuController] Started")
end

function DevMenuController:_toggleVisible()
	self.Visible = not self.Visible

	if self.UI and self.UI.Panel then
		self.UI.Panel.Visible = self.Visible
	end

	if self.Visible then
		self:_request("Refresh")
	end
end

function DevMenuController:IsVisible()
	return self.Visible == true
end

function DevMenuController:_applyDebugUiState()
	local enabled = self.DevState.DebugUiEnabled ~= false
	if self.EntityDebugController and self.EntityDebugController.SetDebugUiEnabled then
		self.EntityDebugController:SetDebugUiEnabled(enabled)
	end
	if self.InteractableDebugController and self.InteractableDebugController.SetDebugUiEnabled then
		self.InteractableDebugController:SetDebugUiEnabled(enabled)
	end
end

function DevMenuController:_request(command, payload)
	self.RequestRemote:FireServer(payload or {
		Command = command,
	})
end

function DevMenuController:_setPlacementMode(mode)
	self.PlacementMode = mode
	self:_refreshUi()
end

function DevMenuController:_serializePosition(position)
	return {
		X = position.X,
		Y = position.Y,
		Z = position.Z,
	}
end

function DevMenuController:_getPlacementPosition()
	local ignoreList = {}
	local character = self.World:GetCharacter()
	if character then
		table.insert(ignoreList, character)
	end

	local mapBounds = Workspace:FindFirstChild("MapBounds")
	if mapBounds then
		table.insert(ignoreList, mapBounds)
	end

	self.PlacementRaycastParams.FilterDescendantsInstances = ignoreList

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = self.World.Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, self.PlacementRaycastParams)
	if not result then
		return nil
	end

	return result.Position
end

function DevMenuController:_handlePlacementClick()
	if not self.PlacementMode then
		return false
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local hoveredGui = self.PlayerGui:GetGuiObjectsAtPosition(mouseLocation.X, mouseLocation.Y)
	for _, guiObject in ipairs(hoveredGui) do
		if self.UI and self.UI.Root and guiObject:IsDescendantOf(self.UI.Root) then
			return false
		end
	end

	local position = self:_getPlacementPosition()
	if not position then
		self.DevState.Message = "No valid ground clicked"
		self:_refreshUi()
		return true
	end

	if self.PlacementMode == "Entity" then
		self:_request("SpawnEntityAt", {
			Command = "SpawnEntityAt",
			EntityId = self:_getSelectedEntityId(),
			Position = self:_serializePosition(position),
		})
	elseif self.PlacementMode == "WeaponPickup" then
		self:_request("PlaceWeaponPickup", {
			Command = "PlaceWeaponPickup",
			WeaponId = self:_getSelectedWeaponId(),
			Position = self:_serializePosition(position),
		})
	elseif self.PlacementMode == "ItemPickup" then
		self:_request("PlaceItemPickup", {
			Command = "PlaceItemPickup",
			ItemId = self:_getSelectedItemId(),
			Quantity = 1,
			Position = self:_serializePosition(position),
		})
	end

	self.PlacementMode = nil
	self:_refreshUi()
	return true
end

function DevMenuController:_getSelectedWeaponId()
	return self.WeaponIds[self.SelectedWeaponIndex]
end

function DevMenuController:_getSelectedItemId()
	return self.ItemIds[self.SelectedItemIndex]
end

function DevMenuController:_getSelectedEntityId()
	return self.EntityIds[self.SelectedEntityIndex]
end

function DevMenuController:_cycleIndex(current, delta, list)
	local count = #list
	if count <= 0 then
		return 1
	end

	local nextIndex = current + delta
	if nextIndex < 1 then
		nextIndex = count
	elseif nextIndex > count then
		nextIndex = 1
	end
	return nextIndex
end

function DevMenuController:_createButton(parent, text, position, size, onClick)
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

function DevMenuController:_createSectionLabel(parent, text, y)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 12, 0, y)
	label.Size = UDim2.new(1, -24, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(242, 212, 103)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function DevMenuController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DevMenuUI"
	screenGui.Enabled = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local launcher = Instance.new("TextButton")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(0, 0.5)
	launcher.Position = UDim2.new(0, 18, 0.5, -210)
	launcher.Size = UDim2.new(0, 46, 0, 24)
	launcher.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	launcher.BackgroundTransparency = 0.08
	launcher.BorderSizePixel = 0
	launcher.Font = Enum.Font.GothamBold
	launcher.TextSize = 12
	launcher.TextColor3 = Color3.fromRGB(242, 212, 103)
	launcher.Text = "DEV"
	launcher.Parent = screenGui

	local launcherCorner = Instance.new("UICorner")
	launcherCorner.CornerRadius = UDim.new(0, 8)
	launcherCorner.Parent = launcher

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 18, 0.5, 0)
	frame.Size = UDim2.new(0, 280, 0, 448)
	frame.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 12, 0, 8)
	title.Size = UDim2.new(1, -24, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Dev Menu [RightShift]"
	title.Parent = frame

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.BackgroundTransparency = 1
	stateLabel.Position = UDim2.new(0, 12, 0, 28)
	stateLabel.Size = UDim2.new(1, -24, 0, 16)
	stateLabel.Font = Enum.Font.Gotham
	stateLabel.TextSize = 11
	stateLabel.TextColor3 = Color3.fromRGB(190, 194, 206)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Parent = frame

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "MessageLabel"
	messageLabel.BackgroundTransparency = 1
	messageLabel.Position = UDim2.new(0, 12, 0, 46)
	messageLabel.Size = UDim2.new(1, -24, 0, 42)
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.TextSize = 11
	messageLabel.TextWrapped = true
	messageLabel.TextColor3 = Color3.fromRGB(124, 214, 166)
	messageLabel.TextXAlignment = Enum.TextXAlignment.Left
	messageLabel.TextYAlignment = Enum.TextYAlignment.Top
	messageLabel.Parent = frame

	self:_createSectionLabel(frame, "Weapons", 96)
	local weaponName = Instance.new("TextLabel")
	weaponName.Name = "WeaponName"
	weaponName.BackgroundTransparency = 1
	weaponName.Position = UDim2.new(0, 52, 0, 118)
	weaponName.Size = UDim2.new(0, 120, 0, 22)
	weaponName.Font = Enum.Font.GothamBold
	weaponName.TextSize = 12
	weaponName.TextColor3 = Color3.fromRGB(240, 240, 240)
	weaponName.TextXAlignment = Enum.TextXAlignment.Center
	weaponName.Parent = frame

	self:_createButton(frame, "<", UDim2.new(0, 12, 0, 118), UDim2.new(0, 32, 0, 22), function()
		self.SelectedWeaponIndex = self:_cycleIndex(self.SelectedWeaponIndex, -1, self.WeaponIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, ">", UDim2.new(0, 176, 0, 118), UDim2.new(0, 32, 0, 22), function()
		self.SelectedWeaponIndex = self:_cycleIndex(self.SelectedWeaponIndex, 1, self.WeaponIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, "Give", UDim2.new(0, 214, 0, 118), UDim2.new(0, 54, 0, 22), function()
		self:_request("GiveWeapon", {
			Command = "GiveWeapon",
			WeaponId = self:_getSelectedWeaponId(),
		})
	end)
	self:_createButton(frame, "Place", UDim2.new(0, 214, 0, 144), UDim2.new(0, 54, 0, 20), function()
		self:_setPlacementMode("WeaponPickup")
	end)

	self:_createSectionLabel(frame, "Items", 172)
	local itemName = Instance.new("TextLabel")
	itemName.Name = "ItemName"
	itemName.BackgroundTransparency = 1
	itemName.Position = UDim2.new(0, 52, 0, 194)
	itemName.Size = UDim2.new(0, 120, 0, 22)
	itemName.Font = Enum.Font.GothamBold
	itemName.TextSize = 12
	itemName.TextColor3 = Color3.fromRGB(240, 240, 240)
	itemName.TextXAlignment = Enum.TextXAlignment.Center
	itemName.Parent = frame

	self:_createButton(frame, "<", UDim2.new(0, 12, 0, 194), UDim2.new(0, 32, 0, 22), function()
		self.SelectedItemIndex = self:_cycleIndex(self.SelectedItemIndex, -1, self.ItemIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, ">", UDim2.new(0, 176, 0, 194), UDim2.new(0, 32, 0, 22), function()
		self.SelectedItemIndex = self:_cycleIndex(self.SelectedItemIndex, 1, self.ItemIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, "Give", UDim2.new(0, 214, 0, 194), UDim2.new(0, 54, 0, 22), function()
		self:_request("GiveItem", {
			Command = "GiveItem",
			ItemId = self:_getSelectedItemId(),
			Count = 1,
		})
	end)
	self:_createButton(frame, "Place", UDim2.new(0, 214, 0, 220), UDim2.new(0, 54, 0, 20), function()
		self:_setPlacementMode("ItemPickup")
	end)

	self:_createSectionLabel(frame, "Entities", 248)
	local entityName = Instance.new("TextLabel")
	entityName.Name = "EntityName"
	entityName.BackgroundTransparency = 1
	entityName.Position = UDim2.new(0, 52, 0, 270)
	entityName.Size = UDim2.new(0, 120, 0, 22)
	entityName.Font = Enum.Font.GothamBold
	entityName.TextSize = 12
	entityName.TextColor3 = Color3.fromRGB(240, 240, 240)
	entityName.TextXAlignment = Enum.TextXAlignment.Center
	entityName.Parent = frame

	self:_createButton(frame, "<", UDim2.new(0, 12, 0, 270), UDim2.new(0, 32, 0, 22), function()
		self.SelectedEntityIndex = self:_cycleIndex(self.SelectedEntityIndex, -1, self.EntityIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, ">", UDim2.new(0, 176, 0, 270), UDim2.new(0, 32, 0, 22), function()
		self.SelectedEntityIndex = self:_cycleIndex(self.SelectedEntityIndex, 1, self.EntityIds)
		self:_refreshUi()
	end)
	self:_createButton(frame, "Spawn", UDim2.new(0, 214, 0, 270), UDim2.new(0, 54, 0, 22), function()
		self:_request("SpawnEntity", {
			Command = "SpawnEntity",
			EntityId = self:_getSelectedEntityId(),
		})
	end)
	self:_createButton(frame, "Place", UDim2.new(0, 214, 0, 296), UDim2.new(0, 54, 0, 20), function()
		self:_setPlacementMode("Entity")
	end)

	self:_createSectionLabel(frame, "Timer", 324)
	local timerBox = Instance.new("TextBox")
	timerBox.Name = "TimerBox"
	timerBox.Position = UDim2.new(0, 12, 0, 346)
	timerBox.Size = UDim2.new(0, 62, 0, 22)
	timerBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	timerBox.BorderSizePixel = 0
	timerBox.Font = Enum.Font.GothamBold
	timerBox.TextSize = 12
	timerBox.TextColor3 = Color3.fromRGB(240, 240, 240)
	timerBox.PlaceholderText = "secs"
	timerBox.Text = ""
	timerBox.Parent = frame
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 8)
	timerCorner.Parent = timerBox

	self:_createButton(frame, "-30", UDim2.new(0, 82, 0, 346), UDim2.new(0, 42, 0, 22), function()
		self:_request("AdjustTimer", {
			Command = "AdjustTimer",
			Delta = -30,
		})
	end)
	self:_createButton(frame, "+30", UDim2.new(0, 130, 0, 346), UDim2.new(0, 42, 0, 22), function()
		self:_request("AdjustTimer", {
			Command = "AdjustTimer",
			Delta = 30,
		})
	end)
	self:_createButton(frame, "Set", UDim2.new(0, 178, 0, 346), UDim2.new(0, 42, 0, 22), function()
		self:_request("SetTimer", {
			Command = "SetTimer",
			TimeLeft = tonumber(timerBox.Text),
		})
	end)

	self:_createSectionLabel(frame, "Utilities", 378)
	local escapeButton = self:_createButton(frame, "Toggle Escape", UDim2.new(0, 12, 0, 392), UDim2.new(0, 124, 0, 22), function()
		self:_request("ToggleEscape", {
			Command = "ToggleEscape",
		})
	end)
	escapeButton.Name = "EscapeButton"
	local godButton = self:_createButton(frame, "God Mode", UDim2.new(0, 144, 0, 392), UDim2.new(0, 124, 0, 22), function()
		self:_request("ToggleGodMode", {
			Command = "ToggleGodMode",
		})
	end)
	godButton.Name = "GodModeButton"
	local debugUiButton = self:_createButton(frame, "Debug UI", UDim2.new(0, 12, 0, 418), UDim2.new(0, 256, 0, 20), function()
		self:_request("ToggleDebugUi", {
			Command = "ToggleDebugUi",
		})
	end)
	debugUiButton.Name = "DebugUiButton"

	launcher.MouseButton1Click:Connect(function()
		self:_toggleVisible()
	end)

	self.UI = {
		Root = screenGui,
		Launcher = launcher,
		Panel = frame,
		StateLabel = stateLabel,
		MessageLabel = messageLabel,
		WeaponName = weaponName,
		ItemName = itemName,
		EntityName = entityName,
		TimerBox = timerBox,
		EscapeButton = escapeButton,
		GodModeButton = godButton,
		DebugUiButton = debugUiButton,
	}
end

function DevMenuController:_refreshUi()
	if not self.UI then
		return
	end

	local weaponId = self:_getSelectedWeaponId()
	local itemId = self:_getSelectedItemId()
	local entityId = self:_getSelectedEntityId()
	self.UI.WeaponName.Text = weaponId and (WeaponDefinitions[weaponId].DisplayName or weaponId) or "-"
	self.UI.ItemName.Text = itemId and (ItemDefinitions[itemId].DisplayName or itemId) or "-"
	self.UI.EntityName.Text = entityId or "-"
	self.UI.StateLabel.Text = string.format("Phase: %s  |  Time: %ss", tostring(self.DevState.Phase or "Unknown"), tostring(self.DevState.TimeLeft or 0))
	local placementText = self.PlacementMode and string.format("Click ground to place: %s", self.PlacementMode) or ""
	local message = self.DevState.Message or ""
	if placementText ~= "" and message ~= "" then
		self.UI.MessageLabel.Text = placementText .. "\n" .. message
	elseif placementText ~= "" then
		self.UI.MessageLabel.Text = placementText
	else
		self.UI.MessageLabel.Text = message
	end
	self.UI.EscapeButton.Text = (self.DevState.EscapeEnabled and "Disable Escape" or "Enable Escape")
	self.UI.EscapeButton.BackgroundColor3 = self.DevState.EscapeEnabled and Color3.fromRGB(168, 57, 57) or Color3.fromRGB(58, 86, 68)
	self.UI.GodModeButton.Text = (self.DevState.GodMode and "Disable God" or "Enable God")
	self.UI.GodModeButton.BackgroundColor3 = self.DevState.GodMode and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self.UI.DebugUiButton.Text = (self.DevState.DebugUiEnabled ~= false and "Disable Debug UI" or "Enable Debug UI")
	self.UI.DebugUiButton.BackgroundColor3 = (self.DevState.DebugUiEnabled ~= false) and Color3.fromRGB(88, 122, 206) or Color3.fromRGB(54, 58, 70)
	self:_applyDebugUiState()
end

return DevMenuController
