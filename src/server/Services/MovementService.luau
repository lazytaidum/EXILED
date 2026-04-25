local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local MovementService = {}
MovementService.Name = "MovementService"
MovementService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"StaminaService",
	"StatusEffectService",
	"InteractionService",
	"PlayerService",
	"InventoryService",
	"CombatService",
}

local MOVEMENT_STATE_KEYS = {
	[ActionName.Sprint] = "IsSprinting",
	[ActionName.Crouch] = "IsCrouching",
	[ActionName.Aim] = "IsAiming",
}

function MovementService:Init(services)
	self.Services = services
end

function MovementService:Start()
	local requestMovementState = self.RemoteRegistry:GetRemote(RemoteNames.RequestMovementState)
	requestMovementState.OnServerEvent:Connect(function(player, actionName, isActive)
		self:HandleMovementRequest(player, actionName, isActive)
	end)

	DebugLog:Log("Movement", "[MovementService] Started")
end

function MovementService:HandleMovementRequest(player, actionName, isActive)
	if type(actionName) ~= "string" or type(isActive) ~= "boolean" then
		return
	end

	if actionName ~= ActionName.Sprint and actionName ~= ActionName.Crouch and actionName ~= ActionName.Aim then
		return
	end

	local character = self.World:GetCharacter(player)
	if not character or not character:IsActionable() then
		return
	end

	local statusEffectService = self.StatusEffectService
	if statusEffectService and statusEffectService:HasFlag(player, "Stunned") then
		return
	end

	if actionName == ActionName.Sprint then
		if isActive and self.World:IsInteracting(player) then
			self.World:InterruptInteraction(player, "Sprint")
		end
		character:SetSprintHeld(isActive)
		if isActive then
			character:SetCrouching(false)
			character:SetAiming(false)
		end
	elseif actionName == ActionName.Crouch then
		character:SetCrouching(isActive)
		if isActive then
			character:SetSprintHeld(false)
		end
	else
		local equippedEntry = self.InventoryService and self.InventoryService:GetEntry(player, (self.CombatService and self.CombatService.PlayerCombatStates[player] and self.CombatService.PlayerCombatStates[player].EquippedSlot) or 1)
		local equippedDefinition = equippedEntry and equippedEntry.EntryType == "Weapon" and WeaponDefinitions[equippedEntry.ItemId] or nil
		if isActive and (not equippedDefinition or equippedDefinition.Kind ~= "Firearm") then
			return
		end

		character:SetAiming(isActive)
		if isActive then
			character:SetSprintHeld(false)
		end
	end

	if self.StaminaService then
		self.StaminaService:RefreshPlayer(player)
	end

	local stateKey = MOVEMENT_STATE_KEYS[actionName]
	local playerService = self.PlayerService
	if playerService and stateKey then
		playerService:SetMovementState(player, stateKey, isActive)

		if isActive then
			if actionName == ActionName.Sprint then
				playerService:SetMovementState(player, MOVEMENT_STATE_KEYS[ActionName.Crouch], false)
				playerService:SetMovementState(player, MOVEMENT_STATE_KEYS[ActionName.Aim], false)
			elseif actionName == ActionName.Crouch then
				playerService:SetMovementState(player, MOVEMENT_STATE_KEYS[ActionName.Sprint], false)
			elseif actionName == ActionName.Aim then
				playerService:SetMovementState(player, MOVEMENT_STATE_KEYS[ActionName.Sprint], false)
			end
		end
	end

	if self.CombatService then
		self.CombatService:RefreshCombatState(player)
	end

	DebugLog:Log("Movement", string.format("[MovementService] %s set %s=%s", player.Name, actionName, tostring(isActive)))
end

return MovementService
