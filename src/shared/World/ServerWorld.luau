local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)

local ServerWorld = {}
ServerWorld.__index = ServerWorld

function ServerWorld.new(services)
	local self = setmetatable({}, ServerWorld)

	self.Services = services
	self.PlayerService = services.PlayerService
	self.CharacterService = services.CharacterService
	self.RoundManager = services.RoundManager
	self.StatusEffectService = services.StatusEffectService
	self.InteractionService = services.InteractionService
	self.ObjectiveService = services.ObjectiveService
	self.WorldMode = WorldModeResolver.GetWorldMode()

	return self
end

function ServerWorld:GetCharacter(player)
	return self.CharacterService and self.CharacterService:GetCharacterByPlayer(player) or nil
end

function ServerWorld:GetRoundState(player)
	return self.RoundManager and self.RoundManager:GetRoundState(player) or nil
end

function ServerWorld:GetActivePlayers()
	return self.RoundManager and self.RoundManager:GetActivePlayers() or {}
end

function ServerWorld:GetWorldMode()
	return self.WorldMode
end

function ServerWorld:ApplyStatus(target, statusId, params)
	if not self.StatusEffectService then
		return nil
	end

	return self.StatusEffectService:ApplyStatus(target, statusId, params)
end

function ServerWorld:RemoveStatus(target, statusId)
	if not self.StatusEffectService then
		return false
	end

	return self.StatusEffectService:RemoveStatus(target, statusId)
end

function ServerWorld:CanUseAbilities(target)
	return not self.StatusEffectService or self.StatusEffectService:CanUseAbilities(target)
end

function ServerWorld:CanInteract(target)
	return not self.StatusEffectService or self.StatusEffectService:CanInteract(target)
end

function ServerWorld:IsInteracting(player)
	return self.InteractionService and self.InteractionService:IsInteracting(player) or false
end

function ServerWorld:InterruptInteraction(player, reason)
	if not self.InteractionService then
		return false
	end

	return self.InteractionService:InterruptInteraction(player, reason)
end

return ServerWorld
