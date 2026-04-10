local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
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
}

local MOVEMENT_STATE_KEYS = {
	[ActionName.Sprint] = "IsSprinting",
	[ActionName.Crouch] = "IsCrouching",
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

	if actionName ~= ActionName.Sprint and actionName ~= ActionName.Crouch then
		return
	end

	local character = self.World:GetCharacter(player)
	if not character or not character:IsAlive() then
		return
	end

	local statusEffectService = self.StatusEffectService
	if statusEffectService and statusEffectService:HasFlag(player, "Stunned") then
		return
	end

	if actionName == ActionName.Sprint then
		if isActive and self.StaminaService and not self.StaminaService:HasSprintStamina(player) then
			return
		end

		if isActive and self.World:IsInteracting(player) then
			self.World:InterruptInteraction(player, "Sprint")
		end
		character:SetSprinting(isActive)
		if isActive then
			character:SetCrouching(false)
		end
	else
		character:SetCrouching(isActive)
		if isActive then
			character:SetSprinting(false)
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
			local oppositeStateKey = actionName == ActionName.Sprint and MOVEMENT_STATE_KEYS[ActionName.Crouch] or MOVEMENT_STATE_KEYS[ActionName.Sprint]
			playerService:SetMovementState(player, oppositeStateKey, false)
		end
	end

	DebugLog:Log("Movement", string.format("[MovementService] %s set %s=%s", player.Name, actionName, tostring(isActive)))
end

return MovementService
