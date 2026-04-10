local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
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

function InteractableDebugController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.Folders = {
		Objectives = Workspace:FindFirstChild("Objectives"),
		WeaponPickups = Workspace:FindFirstChild("WeaponPickups"),
		ItemPickups = Workspace:FindFirstChild("ItemPickups"),
	}
	self.Overlays = {}
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

	return nil
end

function InteractableDebugController:_refreshOverlays()
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
			local visible = distance <= MAX_VISIBLE_DISTANCE
			overlay.Billboard.Enabled = visible
			overlay.Frame.BackgroundTransparency = visible and 0.22 or 1
		else
			overlay.Billboard.Enabled = true
		end
	end
end

return InteractableDebugController
