local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CombatService = {}
CombatService.Name = "CombatService"
CombatService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"EntityService",
	"InventoryService",
	"RoundManager",
	"StatusEffectService",
}

function CombatService:Init(services)
	self.Services = services
	self.PlayerCombatStates = {}
end

function CombatService:Start()
	self.RequestPrimaryAttackRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestPrimaryAttack)
	self.RequestEquipWeaponRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestEquipWeapon)
	self.RequestUseInventoryItemRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestUseInventoryItem)
	self.CombatStateChangedRemote = self.RemoteRegistry:GetRemote(RemoteNames.CombatStateChanged)
	self.CombatHitConfirmedRemote = self.RemoteRegistry:GetRemote(RemoteNames.CombatHitConfirmed)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_initializePlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_initializePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerCombatStates[player] = nil
	end)

	self.RequestPrimaryAttackRemote.OnServerEvent:Connect(function(player)
		self:HandlePrimaryAttack(player)
	end)

	if self.RequestEquipWeaponRemote then
		self.RequestEquipWeaponRemote.OnServerEvent:Connect(function(player, requestedSlot)
			self:HandleEquipWeapon(player, requestedSlot)
		end)
	end

	if self.RequestUseInventoryItemRemote then
		self.RequestUseInventoryItemRemote.OnServerEvent:Connect(function(player, requestedSlot)
			self:HandleUseInventoryItem(player, requestedSlot)
		end)
	end

	DebugLog:Log("Combat", "[CombatService] Started")
end

function CombatService:_initializePlayer(player)
	self:_resetPlayerCombatState(player)

	player.CharacterAdded:Connect(function()
		self:_resetPlayerCombatState(player)
	end)
end

function CombatService:_resetPlayerCombatState(player)
	self.PlayerCombatStates[player] = {
		EquippedSlot = 1,
		LastAttackAt = 0,
		ActiveItemUse = nil,
		ItemUseToken = 0,
	}

	self:_syncCombatState(player)
end

function CombatService:GetEquippedWeaponState(player)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return nil
	end

	return self:_getEquippedWeaponState(player, combatState)
end

function CombatService:GiveWeapon(player, weaponId)
	local slotIndex = self.InventoryService:AddWeapon(player, weaponId)
	self:_syncCombatState(player)
	return slotIndex
end

function CombatService:RefreshCombatState(player)
	self:_syncCombatState(player)
end

function CombatService:HandleEquipWeapon(player, requestedSlot)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return false
	end

	if combatState.ActiveItemUse then
		return false
	end

	local slotIndex = tonumber(requestedSlot)
	if not slotIndex then
		return false
	end

	local weaponState = self.InventoryService:GetEntry(player, slotIndex)
	if not weaponState then
		return false
	end

	combatState.EquippedSlot = slotIndex
	self:_syncCombatState(player)
	return true
end

function CombatService:HandleUseInventoryItem(player, requestedSlot)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return false
	end

	if combatState.ActiveItemUse then
		return false
	end

	local roundManager = self.RoundManager
	if roundManager and not roundManager:IsReceptionActive() then
		return false
	end

	local slotIndex = tonumber(requestedSlot)
	if not slotIndex then
		return false
	end

	local entry = self.InventoryService:GetEntry(player, slotIndex)
	if not entry or entry.EntryType ~= "Item" then
		return false
	end

	local itemDefinition = ItemDefinitions[entry.ItemId]
	if not itemDefinition then
		return false
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character:IsAlive() then
		return false
	end

	if not self:_canUseInventoryItem(player, entry, itemDefinition, character) then
		return false
	end

	local useDuration = math.max(0, itemDefinition.UseDuration or 0)
	if useDuration <= 0 then
		return self:_completeInventoryItemUse(player, slotIndex, entry, itemDefinition, character)
	end

	combatState.ItemUseToken += 1
	local useToken = combatState.ItemUseToken
	combatState.ActiveItemUse = {
		Slot = slotIndex,
		ItemId = entry.ItemId,
		EndsAt = os.clock() + useDuration,
	}
	character:SetSpeedMultiplier("ItemUseSlow", 0.72)
	self:_syncCombatState(player)

	task.delay(useDuration, function()
		local liveState = self.PlayerCombatStates[player]
		local liveCharacter = self.CharacterService:GetCharacterByPlayer(player)
		if not liveState or liveState.ItemUseToken ~= useToken then
			return
		end

		liveState.ActiveItemUse = nil
		if liveCharacter then
			liveCharacter:SetSpeedMultiplier("ItemUseSlow", nil)
		end

		local liveEntry = self.InventoryService:GetEntry(player, slotIndex)
		if not liveEntry or liveEntry.EntryType ~= "Item" or liveEntry.ItemId ~= entry.ItemId then
			self:_syncCombatState(player)
			return
		end

		if not liveCharacter or not liveCharacter:IsAlive() then
			self:_syncCombatState(player)
			return
		end

		self:_completeInventoryItemUse(player, slotIndex, liveEntry, itemDefinition, liveCharacter)
	end)

	DebugLog:Log("Combat", string.format("[CombatService] %s started using item %s", player.Name, entry.ItemId))
	return true
end

function CombatService:_canUseInventoryItem(player, entry, itemDefinition, character)
	if not entry or not itemDefinition or not character then
		return false
	end

	for _, effect in ipairs(itemDefinition.Effects or {}) do
		if effect.Type == "Status" then
			return true
		elseif effect.Type == "HealSelf" then
			if self.StatusEffectService and not self.StatusEffectService:CanBeHealed(player) then
				continue
			end

			if character.Humanoid and character.Humanoid.Health < character.Humanoid.MaxHealth then
				return true
			end
		end
	end

	return false
end

function CombatService:_completeInventoryItemUse(player, slotIndex, entry, itemDefinition, character)
	local usedSuccessfully = false

	for _, effect in ipairs(itemDefinition.Effects or {}) do
		if effect.Type == "Status" and self.StatusEffectService then
			local statusInstance = self.StatusEffectService:ApplyStatus(player, effect.StatusId, {
				Duration = effect.Duration,
				Magnitude = effect.Magnitude,
			})
			if statusInstance then
				usedSuccessfully = true
			end
		elseif effect.Type == "HealSelf" then
			if self.StatusEffectService and not self.StatusEffectService:CanBeHealed(player) then
				continue
			end

			if character:Heal(effect.Amount or 0) then
				usedSuccessfully = true
			end
		end
	end

	if not usedSuccessfully then
		self:_syncCombatState(player)
		return false
	end

	self.InventoryService:ConsumeItem(player, slotIndex, 1)
	self:_syncCombatState(player)
	DebugLog:Log("Combat", string.format("[CombatService] %s used item %s", player.Name, entry.ItemId))
	return true
end

function CombatService:HandlePrimaryAttack(player)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return false
	end

	if combatState.ActiveItemUse then
		return false
	end

	local roundManager = self.RoundManager
	if roundManager and not roundManager:IsReceptionActive() then
		return false
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character:IsAlive() or not character.RootPart then
		return false
	end

	local equippedWeaponState = self:_getEquippedWeaponState(player, combatState)
	local weapon = equippedWeaponState and equippedWeaponState.EntryType == "Weapon" and WeaponDefinitions[equippedWeaponState.ItemId] or nil
	if not weapon or not equippedWeaponState or equippedWeaponState.Durability <= 0 then
		self:_syncCombatState(player)
		return false
	end

	local now = os.clock()
	if now - (combatState.LastAttackAt or 0) < (weapon.AttackCooldown or 0.5) then
		return false
	end

	combatState.LastAttackAt = now
	equippedWeaponState.Durability = math.max(0, equippedWeaponState.Durability - (weapon.DurabilityCostPerSwing or 1))

	local hitEntity = self:_findAttackTarget(character, weapon)
	if hitEntity then
		local didDamage = self.EntityService:DamageEntity(hitEntity, weapon.Damage, {
			SourcePlayer = player,
			WeaponId = weapon.Id,
		})

		if didDamage and self.CombatHitConfirmedRemote then
			self.CombatHitConfirmedRemote:FireClient(player, {
				TargetName = hitEntity.DisplayName,
				Damage = weapon.Damage,
				WeaponId = weapon.Id,
			})
		end

		DebugLog:Log("Combat", string.format("[CombatService] %s hit %s with %s for %d", player.Name, hitEntity.DisplayName, weapon.DisplayName, weapon.Damage))
	else
		DebugLog:Log("Combat", string.format("[CombatService] %s swung %s and missed", player.Name, weapon.DisplayName))
	end

	self:_syncCombatState(player)
	return true
end

function CombatService:_getEquippedWeaponState(player, combatState)
	if not combatState then
		return nil
	end

	local equippedSlot = combatState.EquippedSlot or 1
	return self.InventoryService:GetEntry(player, equippedSlot)
end

function CombatService:_findAttackTarget(character, weapon)
	local rootPart = character.RootPart
	local origin = rootPart.Position
	local lookVector = rootPart.CFrame.LookVector
	local bestEntity = nil
	local bestDistance = math.huge

	for _, entity in ipairs(self.EntityService.Entities or {}) do
		if entity.IsActive and entity.Health > 0 then
			local entityPosition = entity:GetPosition()
			if entityPosition then
				local offset = entityPosition - origin
				local distance = offset.Magnitude
				if distance <= (weapon.Range or 0) then
					local direction = distance > 0 and offset.Unit or lookVector
					local dot = lookVector:Dot(direction)
					if dot >= (weapon.ArcDotThreshold or 0) and distance < bestDistance then
						bestDistance = distance
						bestEntity = entity
					end
				end
			end
		end
	end

	return bestEntity
end

function CombatService:_syncCombatState(player)
	if not self.CombatStateChangedRemote then
		return
	end

	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return
	end

	local equippedWeaponState = self:_getEquippedWeaponState(player, combatState)
	local weapon = equippedWeaponState and equippedWeaponState.EntryType == "Weapon" and WeaponDefinitions[equippedWeaponState.ItemId] or nil
	local cooldownRemaining = 0
	if weapon then
		cooldownRemaining = math.max(0, (combatState.LastAttackAt + (weapon.AttackCooldown or 0)) - os.clock())
	end
	local itemUseRemaining = combatState.ActiveItemUse and math.max(0, combatState.ActiveItemUse.EndsAt - os.clock()) or 0
	local activeItemUseDefinition = combatState.ActiveItemUse and ItemDefinitions[combatState.ActiveItemUse.ItemId] or nil

	local payloadWeapons = {}
	for slotIndex, weaponState in ipairs(self.InventoryService:GetEntries(player) or {}) do
		local definition = weaponState.EntryType == "Weapon" and WeaponDefinitions[weaponState.ItemId] or ItemDefinitions[weaponState.ItemId]
		if definition then
			table.insert(payloadWeapons, {
				Slot = slotIndex,
				WeaponId = weaponState.ItemId,
				DisplayName = definition.DisplayName,
				ShortDisplayName = definition.ShortDisplayName or definition.DisplayName,
				EntryType = weaponState.EntryType,
				Durability = weaponState.Durability,
				MaxDurability = definition.Durability,
				Count = weaponState.Count,
				IsBroken = weaponState.EntryType == "Weapon" and weaponState.Durability <= 0 or false,
			})
		end
	end

	self.CombatStateChangedRemote:FireClient(player, {
		EquippedWeaponId = equippedWeaponState and equippedWeaponState.ItemId or nil,
		EquippedSlot = combatState.EquippedSlot or 1,
		DisplayName = weapon and weapon.DisplayName or (equippedWeaponState and ItemDefinitions[equippedWeaponState.ItemId] and ItemDefinitions[equippedWeaponState.ItemId].DisplayName or (equippedWeaponState and equippedWeaponState.ItemId or "Unarmed")),
		Durability = weapon and equippedWeaponState and equippedWeaponState.Durability or 0,
		MaxDurability = weapon and weapon.Durability or 0,
		Cooldown = cooldownRemaining,
		MaxCooldown = weapon and weapon.AttackCooldown or 0,
		IsUsingItem = combatState.ActiveItemUse ~= nil,
		ItemUseItemId = combatState.ActiveItemUse and combatState.ActiveItemUse.ItemId or nil,
		ItemUseDisplayName = activeItemUseDefinition and activeItemUseDefinition.DisplayName or nil,
		ItemUseRemaining = itemUseRemaining,
		ItemUseDuration = activeItemUseDefinition and activeItemUseDefinition.UseDuration or 0,
		IsBroken = weapon ~= nil and equippedWeaponState ~= nil and equippedWeaponState.Durability <= 0 or false,
		Weapons = payloadWeapons,
	})
end

return CombatService
