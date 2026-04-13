local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ItemPickupService = {}
ItemPickupService.Name = "ItemPickupService"
ItemPickupService.Dependencies = {
	"RemoteRegistry",
	"InventoryService",
	"CombatService",
	"RoundHookService",
}

local DEFAULT_PICKUP_DURATION = 0.25
local RESTORE_HOOK_ID = "ItemPickupService.RestorePlacedPickups"

local function _resolvePickupPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

function ItemPickupService:Init(services)
	self.Services = services
	self.Pickups = {}
	self.PickupTemplates = {}
	self.ItemPickupsFolder = Workspace:FindFirstChild("ItemPickups")
end

function ItemPickupService:Start()
	self.UiToastRemote = self.RemoteRegistry:GetRemote("UiToastRequested")
	if self.ItemPickupsFolder then
		self:_registerExistingPickups()

		self.ItemPickupsFolder.ChildAdded:Connect(function(instance)
			self:_registerPickup(instance)
		end)

		self.ItemPickupsFolder.ChildRemoved:Connect(function(instance)
			self:_unregisterPickup(instance)
		end)
	end

	if self.RoundHookService then
		self.RoundHookService:RegisterHook({
			Id = RESTORE_HOOK_ID,
			Trigger = "PhaseChanged",
			Phase = GamePhase.Lobby,
			Callback = function()
				self:RestorePlacedPickups()
			end,
		})
	end

	DebugLog:Log("Combat", "[ItemPickupService] Started")
end

function ItemPickupService:_registerExistingPickups()
	for _, instance in ipairs(self.ItemPickupsFolder:GetChildren()) do
		self:_registerPickup(instance)
	end
end

function ItemPickupService:_registerPickup(instance)
	if self.Pickups[instance] then
		return
	end

	self:_cachePickupTemplate(instance)

	local itemId = instance:GetAttribute("ItemId") or instance.Name
	local itemDefinition = ItemDefinitions[itemId]
	if not itemDefinition then
		DebugLog:Log("Combat", string.format("[ItemPickupService] Ignored pickup '%s': unknown item '%s'", instance.Name, tostring(itemId)))
		return
	end

	local pickupPart = _resolvePickupPart(instance)
	if not pickupPart then
		DebugLog:Log("Combat", string.format("[ItemPickupService] Ignored pickup '%s': no usable part", instance.Name))
		return
	end

	local pickupDuration = tonumber(instance:GetAttribute("PickupDuration")) or DEFAULT_PICKUP_DURATION
	local quantity = math.max(1, tonumber(instance:GetAttribute("Quantity")) or 1)

	self.Pickups[instance] = {
		Type = InteractableType.ItemPickup,
		Id = instance:GetFullName(),
		DisplayName = instance:GetAttribute("DisplayName") or ("Pick Up " .. itemDefinition.DisplayName),
		Instance = pickupPart,
		Model = instance,
		ItemId = itemId,
		Quantity = quantity,
		Progress = 0,
		MaxProgress = 1,
		ChargeRate = pickupDuration > 0 and (1 / pickupDuration) or 1,
		IsComplete = false,
	}

	DebugLog:Log("Combat", string.format("[ItemPickupService] Registered pickup %s for %s x%d", instance.Name, itemId, quantity))
end

function ItemPickupService:_cachePickupTemplate(instance)
	local templateId = instance:GetAttribute("PickupTemplateId")
	if not templateId or templateId == "" then
		templateId = instance:GetFullName()
		instance:SetAttribute("PickupTemplateId", templateId)
	end

	if self.PickupTemplates[templateId] then
		return
	end

	self.PickupTemplates[templateId] = {
		TemplateId = templateId,
		Name = instance.Name,
		Clone = instance:Clone(),
	}
end

function ItemPickupService:_unregisterPickup(instance)
	self.Pickups[instance] = nil
end

function ItemPickupService:GetAvailablePickups()
	local results = {}
	for _, pickup in pairs(self.Pickups) do
		if pickup.Instance and pickup.Instance.Parent and not pickup.IsComplete then
			table.insert(results, pickup)
		end
	end

	return results
end

function ItemPickupService:CompletePickup(player, pickup)
	if not pickup or pickup.IsComplete then
		return false
	end

	local slotIndex = self.InventoryService:AddItem(player, pickup.ItemId, pickup.Quantity)
	if not slotIndex then
		return false
	end

	if self.CombatService and self.CombatService.RefreshCombatState then
		self.CombatService:RefreshCombatState(player)
	end

	pickup.IsComplete = true
	if pickup.Model and pickup.Model.Parent then
		pickup.Model:Destroy()
	end

	DebugLog:Log("Combat", string.format("[ItemPickupService] %s picked up %s x%d", player.Name, pickup.ItemId, pickup.Quantity or 1))
	if self.UiToastRemote then
		local definition = ItemDefinitions[pickup.ItemId]
		local quantity = pickup.Quantity or 1
		local itemName = definition and definition.DisplayName or pickup.ItemId
		self.UiToastRemote:FireClient(player, {
			Title = "Item Picked Up",
			Message = quantity > 1 and string.format("%s x%d", itemName, quantity) or itemName,
			Tint = "Item",
		})
	end
	return true
end

function ItemPickupService:RestorePlacedPickups()
	if not self.ItemPickupsFolder then
		return
	end

	local activeTemplateIds = {}
	for _, child in ipairs(self.ItemPickupsFolder:GetChildren()) do
		local templateId = child:GetAttribute("PickupTemplateId")
		if templateId and templateId ~= "" then
			activeTemplateIds[templateId] = true
		end
	end

	for templateId, templateData in pairs(self.PickupTemplates) do
		if not activeTemplateIds[templateId] then
			local restoredInstance = templateData.Clone:Clone()
			restoredInstance.Parent = self.ItemPickupsFolder
			DebugLog:Log("Combat", string.format("[ItemPickupService] Restored pickup %s", templateData.Name))
		end
	end
end

function ItemPickupService:CreateDevPickup(itemId, position, quantity)
	if not ItemDefinitions[itemId] or typeof(position) ~= "Vector3" then
		return nil
	end

	if not self.ItemPickupsFolder then
		self.ItemPickupsFolder = Instance.new("Folder")
		self.ItemPickupsFolder.Name = "ItemPickups"
		self.ItemPickupsFolder.Parent = Workspace
	end

	local instance = Instance.new("Part")
	instance.Name = itemId
	instance.Size = Vector3.new(2, 2, 2)
	instance.Shape = Enum.PartType.Ball
	instance.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Material = Enum.Material.Neon
	instance.Color = Color3.fromRGB(0, 143, 0)
	instance:SetAttribute("ItemId", itemId)
	instance:SetAttribute("DisplayName", "Pick Up " .. (ItemDefinitions[itemId].DisplayName or itemId))
	instance:SetAttribute("Quantity", math.max(1, tonumber(quantity) or 1))
	instance:SetAttribute("PickupDuration", DEFAULT_PICKUP_DURATION)
	instance.Parent = self.ItemPickupsFolder
	return instance
end

return ItemPickupService
