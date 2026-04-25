local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local ObjectiveDefinitions = require(ReplicatedStorage.Shared.Data.ObjectiveDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractableDebugController = {}
InteractableDebugController.Name = "InteractableDebugController"

local MAX_VISIBLE_DISTANCE = 140

local function _resolveAdornee(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function _getObjectiveLabel(instance)
	local definition = ObjectiveDefinitions[instance.Name]
	if definition then
		return definition.DisplayName or instance.Name, "OBJECTIVE", Color3.fromRGB(103, 194, 255)
	end

	return instance.Name, "OBJECTIVE", Color3.fromRGB(103, 194, 255)
end

local function _getWeaponPickupLabel(instance)
	local weaponId = instance:GetAttribute("WeaponId") or instance.Name
	local weapon = WeaponDefinitions[weaponId]
	local displayName = instance:GetAttribute("DisplayName")
	if displayName and displayName ~= "" then
		return displayName, "PICKUP", Color3.fromRGB(242, 212, 103)
	end

	return weapon and weapon.DisplayName or tostring(weaponId), "PICKUP", Color3.fromRGB(242, 212, 103)
end

local function _getItemPickupLabel(instance)
	local itemId = instance:GetAttribute("ItemId") or instance.Name
	local item = ItemDefinitions[itemId]
	local quantity = math.max(1, tonumber(instance:GetAttribute("Quantity")) or 1)
	local displayName = instance:GetAttribute("DisplayName")
	if displayName and displayName ~= "" then
		return displayName, "ITEM", Color3.fromRGB(124, 214, 166)
	end

	local baseName = item and item.DisplayName or tostring(itemId)
	local label = quantity > 1 and string.format("%s x%d", baseName, quantity) or baseName
	return label, "ITEM", Color3.fromRGB(124, 214, 166)
end

local function _getHazardLabel(instance)
	local displayName = instance:GetAttribute("DisplayName")
	local spent = instance:GetAttribute("Spent") == true
	local name = (displayName and displayName ~= "" and displayName) or instance.Name
	return name, spent and "SPENT" or "HAZARD", spent and Color3.fromRGB(128, 128, 136) or Color3.fromRGB(255, 168, 92)
end

local function _getDoorLabel(instance)
	local displayName = instance:GetAttribute("DisplayName")
	local open = instance:GetAttribute("Open") == true
	local busy = instance:GetAttribute("Busy") == true
	local locked = instance:GetAttribute("Locked") == true
	local name = (displayName and displayName ~= "" and displayName) or instance.Name
	local state = locked and "LOCKED" or (busy and "MOVING" or (open and "OPEN" or "DOOR"))
	local color = locked and Color3.fromRGB(150, 150, 156)
		or (busy and Color3.fromRGB(255, 222, 134))
		or (open and Color3.fromRGB(133, 228, 169))
		or Color3.fromRGB(185, 154, 112)
	return name, state, color
end

local function _getVaultLabel(instance)
	local displayName = instance:GetAttribute("DisplayName")
	local name = (displayName and displayName ~= "" and displayName) or instance.Name
	return name, "VAULT", Color3.fromRGB(132, 194, 255)
end

function InteractableDebugController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.DebugUiEnabled = true
	local interactablesFolder = Workspace:FindFirstChild("Interactables")
	self.Folders = {
		Objectives = Workspace:FindFirstChild("Objectives"),
		WeaponPickups = Workspace:FindFirstChild("WeaponPickups"),
		ItemPickups = Workspace:FindFirstChild("ItemPickups"),
		EnvironmentalHazards = Workspace:FindFirstChild("EnvironmentalHazards"),
		Doors = (interactablesFolder and interactablesFolder:FindFirstChild("Doors")) or Workspace:FindFirstChild("Doors"),
		Vaults = (interactablesFolder and interactablesFolder:FindFirstChild("Vaults")) or Workspace:FindFirstChild("Vaults"),
	}
	self.Overlays = {}
end

function InteractableDebugController:SetDebugUiEnabled(enabled)
	self.DebugUiEnabled = enabled ~= false

	for _, overlay in pairs(self.Overlays) do
		if overlay.Billboard then
			overlay.Billboard.Enabled = self.DebugUiEnabled
		end
	end
end

function InteractableDebugController:Start()
	if not DebugFlags.Enabled or not DebugFlags.InteractableDebugOverlay then
		return
	end

	for _, folder in pairs(self.Folders) do
		if folder then
			self:_trackFolder(folder)
		end
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "EnvironmentalHazards" and child:IsA("Folder") and not self.Folders.EnvironmentalHazards then
			self.Folders.EnvironmentalHazards = child
			self:_trackFolder(child)
		elseif child.Name == "Vaults" and child:IsA("Folder") and not self.Folders.Vaults then
			self.Folders.Vaults = child
			self:_trackFolder(child)
		elseif child.Name == "Doors" and child:IsA("Folder") and not self.Folders.Doors then
			self.Folders.Doors = child
			self:_trackFolder(child)
		elseif child.Name == "Interactables" and child:IsA("Folder") then
			local doorsFolder = child:FindFirstChild("Doors")
			if doorsFolder and doorsFolder:IsA("Folder") and not self.Folders.Doors then
				self.Folders.Doors = doorsFolder
				self:_trackFolder(doorsFolder)
			end

			local vaultsFolder = child:FindFirstChild("Vaults")
			if vaultsFolder and vaultsFolder:IsA("Folder") and not self.Folders.Vaults then
				self.Folders.Vaults = vaultsFolder
				self:_trackFolder(vaultsFolder)
			end

			child.ChildAdded:Connect(function(grandchild)
				if grandchild.Name == "Doors" and grandchild:IsA("Folder") and not self.Folders.Doors then
					self.Folders.Doors = grandchild
					self:_trackFolder(grandchild)
				elseif grandchild.Name == "Vaults" and grandchild:IsA("Folder") and not self.Folders.Vaults then
					self.Folders.Vaults = grandchild
					self:_trackFolder(grandchild)
				end
			end)
		end
	end)

	if self.Player then
		self.Player.CharacterAdded:Connect(function()
			task.defer(function()
				self:_rebuildOverlays()
			end)
		end)
	end

	task.spawn(function()
		while true do
			self:_refreshOverlays()
			task.wait(0.1)
		end
	end)

	DebugLog:Log("ClientInteraction", "[InteractableDebugController] Started")
end

function InteractableDebugController:_trackFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		self:_trackInstance(child)
	end

	folder.ChildAdded:Connect(function(child)
		self:_trackInstance(child)
	end)

	folder.ChildRemoved:Connect(function(child)
		self:_untrackInstance(child)
	end)
end

function InteractableDebugController:_trackInstance(instance)
	if self.Overlays[instance] then
		return
	end

	local adornee = _resolveAdornee(instance)
	if not adornee then
		return
	end

	local labelText, kindText, accentColor = self:_describeInstance(instance)
	if not labelText then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "InteractableDebugOverlay"
	billboard.Size = UDim2.new(0, 172, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = self.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	frame.BackgroundTransparency = 0.22
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local kindLabel = Instance.new("TextLabel")
	kindLabel.Name = "KindLabel"
	kindLabel.Position = UDim2.new(0, 8, 0, 4)
	kindLabel.Size = UDim2.new(1, -16, 0, 12)
	kindLabel.BackgroundTransparency = 1
	kindLabel.Font = Enum.Font.GothamBold
	kindLabel.TextSize = 9
	kindLabel.TextColor3 = accentColor
	kindLabel.TextXAlignment = Enum.TextXAlignment.Left
	kindLabel.Text = kindText
	kindLabel.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.new(0, 8, 0, 16)
	nameLabel.Size = UDim2.new(1, -16, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = labelText
	nameLabel.Parent = frame

	self.Overlays[instance] = {
		Billboard = billboard,
		Frame = frame,
		KindLabel = kindLabel,
		NameLabel = nameLabel,
	}
end

function InteractableDebugController:_untrackInstance(instance)
	local overlay = self.Overlays[instance]
	if not overlay then
		return
	end

	if overlay.Billboard then
		overlay.Billboard:Destroy()
	end

	self.Overlays[instance] = nil
end

function InteractableDebugController:_rebuildOverlays()
	for instance, _ in pairs(self.Overlays) do
		self:_untrackInstance(instance)
	end

	for _, folder in pairs(self.Folders) do
		if folder then
			for _, instance in ipairs(folder:GetChildren()) do
				self:_trackInstance(instance)
			end
		end
	end
end

function InteractableDebugController:_describeInstance(instance)
	if self.Folders.Objectives and instance.Parent == self.Folders.Objectives then
		return _getObjectiveLabel(instance)
	end

	if self.Folders.WeaponPickups and instance.Parent == self.Folders.WeaponPickups then
		return _getWeaponPickupLabel(instance)
	end

	if self.Folders.ItemPickups and instance.Parent == self.Folders.ItemPickups then
		return _getItemPickupLabel(instance)
	end

	if self.Folders.EnvironmentalHazards and instance.Parent == self.Folders.EnvironmentalHazards then
		return _getHazardLabel(instance)
	end

	if self.Folders.Doors and instance.Parent == self.Folders.Doors then
		return _getDoorLabel(instance)
	end

	if self.Folders.Vaults and instance.Parent == self.Folders.Vaults then
		return _getVaultLabel(instance)
	end

	return nil
end

function InteractableDebugController:_refreshOverlays()
	local roundState = self.World:GetRoundState()
	local phase = roundState and roundState.Phase or "Unknown"
	local debugUiEnabled = self.DebugUiEnabled and (phase == GamePhase.Preparation or phase == GamePhase.Reception)
	local character = nil
	if self.World and self.World.GetCharacter then
		character = self.World:GetCharacter()
	end
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local playerPosition = rootPart and rootPart.Position or nil

	for _, folder in pairs(self.Folders) do
		if folder then
			for _, instance in ipairs(folder:GetChildren()) do
				if not self.Overlays[instance] then
					self:_trackInstance(instance)
				end
			end
		end
	end

	for instance, overlay in pairs(self.Overlays) do
		if not instance.Parent then
			self:_untrackInstance(instance)
			continue
		end

		local adornee = _resolveAdornee(instance)
		if not adornee then
			self:_untrackInstance(instance)
			continue
		end

		overlay.Billboard.Adornee = adornee

		local labelText, kindText, accentColor = self:_describeInstance(instance)
		if labelText then
			overlay.NameLabel.Text = labelText
			overlay.KindLabel.Text = kindText
			overlay.KindLabel.TextColor3 = accentColor
		end

		if playerPosition then
			local distance = (adornee.Position - playerPosition).Magnitude
			local visible = debugUiEnabled and distance <= MAX_VISIBLE_DISTANCE
			overlay.Billboard.Enabled = visible
			overlay.Frame.BackgroundTransparency = visible and 0.22 or 1
		else
			overlay.Billboard.Enabled = debugUiEnabled
		end
	end
end

return InteractableDebugController
