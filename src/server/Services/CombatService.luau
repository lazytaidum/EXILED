local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local FirearmAim = require(ReplicatedStorage.Shared.Utility.FirearmAim)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CombatService = {}
CombatService.Name = "CombatService"
CombatService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"EntityService",
	"InventoryService",
	"RoundManager",
	"RoundHookService",
	"StatusEffectService",
	"StruggleService",
	"EnvironmentalHazardService",
}

function CombatService:Init(services)
	self.Services = services
	self.PlayerCombatStates = {}
end

function CombatService:Start()
	self.RequestPrimaryAttackRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestPrimaryAttack)
	self.RequestReloadRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestReload)
	self.RequestEquipWeaponRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestEquipWeapon)
	self.RequestUseInventoryItemRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestUseInventoryItem)
	self.CombatStateChangedRemote = self.RemoteRegistry:GetRemote(RemoteNames.CombatStateChanged)
	self.CombatHitConfirmedRemote = self.RemoteRegistry:GetRemote(RemoteNames.CombatHitConfirmed)
	self.CombatShotVisualRemote = self.RemoteRegistry:GetRemote(RemoteNames.CombatShotVisual)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_initializePlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_initializePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerCombatStates[player] = nil
	end)

	self.RequestPrimaryAttackRemote.OnServerEvent:Connect(function(player, attackData)
		self:HandlePrimaryAttack(player, attackData)
	end)

	if self.RequestReloadRemote then
		self.RequestReloadRemote.OnServerEvent:Connect(function(player)
			self:HandleReload(player)
		end)
	end

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

	if self.RoundHookService then
		self.RoundHookService:RegisterHook({
			Id = "CombatService.ResetOnLobby",
			Trigger = "PhaseChanged",
			Phase = GamePhase.Lobby,
			Callback = function()
				self:_resetAllPlayerCombatForRound()
			end,
		})
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
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetAiming(false)
	end

	self.PlayerCombatStates[player] = {
		EquippedSlot = 1,
		LastAttackAt = 0,
		ActiveItemUse = nil,
		ItemUseToken = 0,
		ReloadToken = 0,
		ActiveReload = nil,
	}

	self:_syncCombatState(player)
end

function CombatService:_resetAllPlayerCombatForRound()
	for _, player in ipairs(Players:GetPlayers()) do
		if self.InventoryService then
			self.InventoryService:ResetPlayerInventory(player)
		end
		self:_resetPlayerCombatState(player)
	end
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
	task.defer(function()
		if self.PlayerCombatStates[player] then
			self:_syncCombatState(player)
		end
	end)
	return slotIndex
end

function CombatService:RefreshCombatState(player)
	self:_syncCombatState(player)
	task.defer(function()
		if self.PlayerCombatStates[player] then
			self:_syncCombatState(player)
		end
	end)
end

function CombatService:_isCombatEnabled()
	if WorldModeResolver.IsWeaponLab() then
		return true
	end

	local roundManager = self.RoundManager
	return roundManager ~= nil and roundManager:IsReceptionActive()
end

function CombatService:ForceStopAim(player)
	local combatState = self.PlayerCombatStates[player]
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if character and character.IsAiming then
		character:SetAiming(false)
	end

	if combatState then
		self:_syncCombatState(player)
	end
end

function CombatService:GetEquippedWeaponDefinition(player)
	local equippedState = self:GetEquippedWeaponState(player)
	if not equippedState or equippedState.EntryType ~= "Weapon" then
		return nil, equippedState
	end

	return WeaponDefinitions[equippedState.ItemId], equippedState
end

function CombatService:EmitShotVisual(player, origin, endPosition, didHit)
	if not self.CombatShotVisualRemote or typeof(origin) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return
	end

	self.CombatShotVisualRemote:FireClient(player, {
		Origin = origin,
		EndPosition = endPosition,
		Hit = didHit == true,
	})
end

function CombatService:HandleEquipWeapon(player, requestedSlot)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return false
	end

	if combatState.ActiveItemUse then
		return false
	end

	if combatState.ActiveReload then
		combatState.ReloadToken += 1
		combatState.ActiveReload = nil
	end

	local slotIndex = tonumber(requestedSlot)
	if not slotIndex then
		return false
	end

	local weaponState = self.InventoryService:GetEntry(player, slotIndex)
	if not weaponState then
		return false
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	local definition = weaponState.EntryType == "Weapon" and WeaponDefinitions[weaponState.ItemId] or ItemDefinitions[weaponState.ItemId]
	if character and (weaponState.EntryType ~= "Weapon" or (definition and definition.Kind ~= "Firearm")) then
		character:SetAiming(false)
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

	if combatState.ActiveReload then
		return false
	end

	if not self:_isCombatEnabled() then
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

	character:SetAiming(false)
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

function CombatService:HandlePrimaryAttack(player, attackData)
	local combatState = self.PlayerCombatStates[player]
	if not combatState then
		return false
	end

	if combatState.ActiveItemUse or combatState.ActiveReload then
		return false
	end

	if not self:_isCombatEnabled() then
		return false
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character:IsAlive() or not character.RootPart then
		return false
	end

	local equippedWeaponState = self:_getEquippedWeaponState(player, combatState)
	local weapon = equippedWeaponState and equippedWeaponState.EntryType == "Weapon" and WeaponDefinitions[equippedWeaponState.ItemId] or nil
	if not weapon or not equippedWeaponState or (weapon.Kind == "Melee" and equippedWeaponState.Durability <= 0) then
		self:_syncCombatState(player)
		return false
	end

	local now = os.clock()
	if now - (combatState.LastAttackAt or 0) < (weapon.AttackCooldown or 0.5) then
		return false
	end

	combatState.LastAttackAt = now

	if weapon.Kind == "Firearm" then
		if (equippedWeaponState.CurrentAmmo or 0) <= 0 then
			self:_syncCombatState(player)
			return false
		end

		equippedWeaponState.CurrentAmmo = math.max(0, (equippedWeaponState.CurrentAmmo or 0) - 1)
	else
		equippedWeaponState.Durability = math.max(0, equippedWeaponState.Durability - (weapon.DurabilityCostPerSwing or 1))
	end

	local hitEntity = nil
	local shotEndPosition = nil
	local shotOrigin = nil
	if weapon.Kind == "Firearm" then
		hitEntity, shotEndPosition, shotOrigin = self:_findRangedAttackTarget(character, weapon, attackData)
	else
		hitEntity = self:_findAttackTarget(character, weapon)
	end
	if weapon.Kind == "Firearm" and self.CombatShotVisualRemote and shotEndPosition then
		self.CombatShotVisualRemote:FireClient(player, {
			Origin = shotOrigin or (character.RootPart.Position + Vector3.new(0, 1.5, 0)),
			EndPosition = shotEndPosition,
			Hit = hitEntity ~= nil,
			WeaponId = weapon.Id,
			IsAiming = type(attackData) == "table" and attackData.IsAiming == true,
		})
	end
	if hitEntity then
		local didDamage = self.EntityService and self.EntityService:DamageEntity(hitEntity, weapon.Damage, {
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

function CombatService:HandleReload(player)
	local combatState = self.PlayerCombatStates[player]
	if not combatState or combatState.ActiveItemUse or combatState.ActiveReload then
		return false
	end

	if not self:_isCombatEnabled() then
		return false
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character:IsAlive() then
		return false
	end

	if self.StruggleService and self.StruggleService:IsPlayerStruggling(player) then
		return self.EnvironmentalHazardService and self.EnvironmentalHazardService:TriggerNearestHazard(player, 12) or false
	end

	local equippedWeaponState = self:_getEquippedWeaponState(player, combatState)
	local weapon = equippedWeaponState and equippedWeaponState.EntryType == "Weapon" and WeaponDefinitions[equippedWeaponState.ItemId] or nil
	if not weapon or weapon.Kind ~= "Firearm" then
		return false
	end

	local currentAmmo = equippedWeaponState.CurrentAmmo or 0
	local maxAmmo = equippedWeaponState.MaxAmmo or weapon.MagazineSize or 0
	local reserveAmmo = equippedWeaponState.ReserveAmmo or 0
	if currentAmmo >= maxAmmo or reserveAmmo <= 0 then
		return false
	end

	combatState.ReloadToken += 1
	local reloadToken = combatState.ReloadToken
	local reloadDuration = weapon.ReloadDuration or 0
	character:SetAiming(false)
	combatState.ActiveReload = {
		EndsAt = os.clock() + reloadDuration,
	}
	self:_syncCombatState(player)

	task.delay(reloadDuration, function()
		local liveState = self.PlayerCombatStates[player]
		if not liveState or liveState.ReloadToken ~= reloadToken then
			return
		end

		local liveWeaponState = self:_getEquippedWeaponState(player, liveState)
		local liveWeapon = liveWeaponState and liveWeaponState.EntryType == "Weapon" and WeaponDefinitions[liveWeaponState.ItemId] or nil
		if not liveWeapon or liveWeapon.Kind ~= "Firearm" then
			liveState.ActiveReload = nil
			self:_syncCombatState(player)
			return
		end

		local liveCharacter = self.CharacterService:GetCharacterByPlayer(player)
		if not liveCharacter or not liveCharacter:IsAlive() then
			liveState.ActiveReload = nil
			self:_syncCombatState(player)
			return
		end

		local magazineSize = liveWeaponState.MaxAmmo or liveWeapon.MagazineSize or 0
		local current = liveWeaponState.CurrentAmmo or 0
		local reserve = liveWeaponState.ReserveAmmo or 0
		local needed = math.max(0, magazineSize - current)
		local loaded = math.min(needed, reserve)
		liveWeaponState.CurrentAmmo = current + loaded
		liveWeaponState.ReserveAmmo = reserve - loaded
		liveState.ActiveReload = nil
		self:_syncCombatState(player)
	end)

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

	local entityService = self.EntityService
	for _, entity in ipairs((entityService and entityService.Entities) or {}) do
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

function CombatService:_findRangedAttackTarget(character, weapon, attackData)
	local rootPart = character.RootPart
	local requestedDirection = type(attackData) == "table" and attackData.Direction or nil
	local requestedOrigin = type(attackData) == "table" and attackData.Origin or nil
	local isAiming = type(attackData) == "table" and attackData.IsAiming == true
	local cameraLookVector = FirearmAim.ResolveLookVector(rootPart.CFrame.LookVector, requestedDirection)
	local spreadAngle = FirearmAim.GetSpreadAngle(weapon, isAiming)
	local spreadLookVector = FirearmAim.ApplySpread(cameraLookVector, spreadAngle, Random.new())
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { character.Model }
	local mapBounds = Workspace:FindFirstChild("MapBounds")
	if mapBounds then
		table.insert(filter, mapBounds)
	end
	raycastParams.FilterDescendantsInstances = filter
	local cameraOrigin = (typeof(requestedOrigin) == "Vector3" and (requestedOrigin - rootPart.Position).Magnitude <= 30)
		and requestedOrigin
		or (rootPart.Position + Vector3.new(0, 2, 0))
	local aimPoint = FirearmAim.ResolveAimPoint(cameraOrigin, spreadLookVector, weapon.Range or 0, raycastParams, Workspace)
	local origin = FirearmAim.GetMuzzleOrigin(rootPart.CFrame, cameraLookVector)
	local shotDirection = aimPoint - origin
	if shotDirection.Magnitude <= 0.001 then
		shotDirection = cameraLookVector * (weapon.Range or 0)
	end
	local normalizedShotDirection = shotDirection.Unit
	local shotEndPosition = origin + (normalizedShotDirection * (weapon.Range or 0))
	local result = Workspace:Raycast(origin, normalizedShotDirection * (weapon.Range or 0), raycastParams)
	if result then
		shotEndPosition = result.Position
		local entityService = self.EntityService
		for _, entity in ipairs((entityService and entityService.Entities) or {}) do
			if entity.IsActive and entity.Health > 0 and entity.Model and result.Instance:IsDescendantOf(entity.Model) then
				return entity, shotEndPosition, origin
			end
		end
	end

	return nil, shotEndPosition, origin
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
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	local cooldownRemaining = 0
	if weapon then
		cooldownRemaining = math.max(0, (combatState.LastAttackAt + (weapon.AttackCooldown or 0)) - os.clock())
	end
	local reloadRemaining = combatState.ActiveReload and math.max(0, combatState.ActiveReload.EndsAt - os.clock()) or 0
	local itemUseRemaining = combatState.ActiveItemUse and math.max(0, combatState.ActiveItemUse.EndsAt - os.clock()) or 0
	local activeItemUseDefinition = combatState.ActiveItemUse and ItemDefinitions[combatState.ActiveItemUse.ItemId] or nil

	local payloadWeapons = {}
	for slotIndex, weaponState in ipairs(self.InventoryService:GetEntries(player) or {}) do
		local definition = weaponState.EntryType == "Weapon" and WeaponDefinitions[weaponState.ItemId] or ItemDefinitions[weaponState.ItemId]
		if definition then
			local isBroken = weaponState.EntryType == "Weapon"
				and definition.Kind == "Melee"
				and (weaponState.Durability or 0) <= 0
			table.insert(payloadWeapons, {
				Slot = slotIndex,
				WeaponId = weaponState.ItemId,
				DisplayName = definition.DisplayName,
				ShortDisplayName = definition.ShortDisplayName or definition.DisplayName,
				EntryType = weaponState.EntryType,
				Durability = weaponState.Durability,
				MaxDurability = definition.Durability,
				CurrentAmmo = weaponState.CurrentAmmo,
				MaxAmmo = weaponState.MaxAmmo,
				ReserveAmmo = weaponState.ReserveAmmo,
				Count = weaponState.Count,
				IsBroken = isBroken,
			})
		end
	end

	local isBroken = weapon ~= nil
		and weapon.Kind == "Melee"
		and equippedWeaponState ~= nil
		and (equippedWeaponState.Durability or 0) <= 0

	self.CombatStateChangedRemote:FireClient(player, {
		EquippedWeaponId = equippedWeaponState and equippedWeaponState.ItemId or nil,
		EquippedSlot = combatState.EquippedSlot or 1,
		DisplayName = weapon and weapon.DisplayName or (equippedWeaponState and ItemDefinitions[equippedWeaponState.ItemId] and ItemDefinitions[equippedWeaponState.ItemId].DisplayName or (equippedWeaponState and equippedWeaponState.ItemId or "Unarmed")),
		Durability = weapon and equippedWeaponState and equippedWeaponState.Durability or 0,
		MaxDurability = weapon and weapon.Durability or 0,
		CurrentAmmo = equippedWeaponState and equippedWeaponState.CurrentAmmo or 0,
		MaxAmmo = equippedWeaponState and equippedWeaponState.MaxAmmo or 0,
		ReserveAmmo = equippedWeaponState and equippedWeaponState.ReserveAmmo or 0,
		WeaponKind = weapon and weapon.Kind or nil,
		Cooldown = cooldownRemaining,
		MaxCooldown = weapon and weapon.AttackCooldown or 0,
		IsReloading = combatState.ActiveReload ~= nil,
		ReloadRemaining = reloadRemaining,
		ReloadDuration = weapon and weapon.ReloadDuration or 0,
		IsUsingItem = combatState.ActiveItemUse ~= nil,
		ItemUseItemId = combatState.ActiveItemUse and combatState.ActiveItemUse.ItemId or nil,
		ItemUseDisplayName = activeItemUseDefinition and activeItemUseDefinition.DisplayName or nil,
		ItemUseRemaining = itemUseRemaining,
		ItemUseDuration = activeItemUseDefinition and activeItemUseDefinition.UseDuration or 0,
		IsBroken = isBroken,
		IsAiming = character and character.IsAiming or false,
		Weapons = payloadWeapons,
	})
end

return CombatService
