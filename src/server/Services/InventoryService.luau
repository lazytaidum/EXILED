local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InventoryService = {}
InventoryService.Name = "InventoryService"

local function _createWeaponEntry(weaponId)
	local definition = WeaponDefinitions[weaponId]
	if not definition then
		return nil
	end

	local entry = {
		EntryType = "Weapon",
		ItemId = weaponId,
		Durability = definition.Durability,
	}

	if definition.Kind == "Firearm" then
		entry.CurrentAmmo = definition.MagazineSize or 0
		entry.MaxAmmo = definition.MagazineSize or 0
		entry.ReserveAmmo = definition.ReserveAmmo or 0
	end

	return entry
end

local function _createItemEntry(itemId, count)
	local definition = ItemDefinitions[itemId]
	if not definition then
		return nil
	end

	return {
		EntryType = "Item",
		ItemId = itemId,
		Count = count or 1,
	}
end

function InventoryService:Init()
	self.PlayerInventories = {}
end

function InventoryService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_initializePlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_initializePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerInventories[player] = nil
	end)

	DebugLog:Log("Combat", "[InventoryService] Started")
end

function InventoryService:_initializePlayer(player)
	self:ResetPlayerInventory(player)

	player.CharacterAdded:Connect(function()
		self:ResetPlayerInventory(player)
	end)
end

function InventoryService:ResetPlayerInventory(player)
	self.PlayerInventories[player] = {
		Entries = {
			_createWeaponEntry("BushmanKnife"),
			_createItemEntry("Bandage", 1),
			_createItemEntry("TestTonic", 1),
		},
	}
end

function InventoryService:GetInventory(player)
	return self.PlayerInventories[player]
end

function InventoryService:GetEntries(player)
	local inventory = self.PlayerInventories[player]
	return inventory and inventory.Entries or nil
end

function InventoryService:GetEntry(player, slotIndex)
	local entries = self:GetEntries(player)
	return entries and entries[slotIndex] or nil
end

function InventoryService:AddWeapon(player, weaponId)
	local inventory = self.PlayerInventories[player]
	if not inventory or not WeaponDefinitions[weaponId] then
		return nil
	end

	for slotIndex, entry in ipairs(inventory.Entries) do
		if entry.EntryType == "Weapon" and entry.ItemId == weaponId then
			return slotIndex
		end
	end

	table.insert(inventory.Entries, _createWeaponEntry(weaponId))
	return #inventory.Entries
end

function InventoryService:AddItem(player, itemId, count)
	local inventory = self.PlayerInventories[player]
	local definition = ItemDefinitions[itemId]
	if not inventory or not definition then
		return nil
	end

	local amount = math.max(1, count or 1)
	for slotIndex, entry in ipairs(inventory.Entries) do
		if entry.EntryType == "Item" and entry.ItemId == itemId then
			local maxStack = definition.MaxStack or math.huge
			entry.Count = math.clamp(entry.Count + amount, 0, maxStack)
			return slotIndex
		end
	end

	table.insert(inventory.Entries, _createItemEntry(itemId, amount))
	return #inventory.Entries
end

function InventoryService:ConsumeItem(player, slotIndex, amount)
	local entry = self:GetEntry(player, slotIndex)
	if not entry or entry.EntryType ~= "Item" then
		return nil
	end

	entry.Count = math.max(0, (entry.Count or 0) - math.max(1, amount or 1))
	if entry.Count <= 0 then
		local entries = self:GetEntries(player)
		table.remove(entries, slotIndex)
	end

	return true
end

return InventoryService
