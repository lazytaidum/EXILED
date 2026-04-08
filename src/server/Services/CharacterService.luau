local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseCharacter = require(ServerScriptService.Server.Classes.BaseCharacter)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CharacterService = {}
CharacterService.Name = "CharacterService"
CharacterService.Dependencies = {
	"PlayerService",
	"RoundManager",
	"StatusEffectService",
}

function CharacterService:Init(services)
	self.Services = services
	self.CharactersByPlayer = {}
	self.CharactersByModel = {}
end

function CharacterService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_connectPlayer(player)
		
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end
	
	Players.PlayerAdded:Connect(function(player: Player)
		self:_connectPlayer(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
	
	DebugLog:Log("Character", "[CharacterService] Started")
end

function CharacterService:_connectPlayer(player)
	player.CharacterAdded:Connect(function(characterModel)
		self:_onCharacterAdded(player, characterModel)
	end)
	
	player.CharacterRemoving:Connect(function(characterModel)
		self:_onCharacterRemoving(player, characterModel)
	end)
end

function CharacterService:_onCharacterAdded(player, characterModel)
	local oldCharacter = self.CharactersByPlayer[player]
	if oldCharacter then
		self:_removeCharacter(player, oldCharacter.Model)
	end
	
	local character = BaseCharacter.new(player, characterModel, self.Services)
	self.CharactersByPlayer[player] = character
	self.CharactersByModel[characterModel] = character
	
	local playerService = self.PlayerService
	if playerService then
		playerService:SetAlive(player, true)
		playerService:SetMovementState(player, "IsSprinting", false)
		playerService:SetMovementState(player, "IsCrouching", false)
	end

	local roundManager = self.RoundManager
	if roundManager then
		roundManager:ApplyCurrentPhaseStateToPlayer(player)
	end
	
	character.Humanoid.Died:Connect(function()
		if character.IsInvincible then
			DebugLog:Log("Character", "[CharacterService] Ignoring death for invincible character", player.Name)
			return
		end
		local livePlayerService = self.PlayerService
		if livePlayerService then
			livePlayerService:SetAlive(player, false)
			livePlayerService:SetMovementState(player, "IsSprinting", false)
			livePlayerService:SetMovementState(player, "IsCrouching", false)
		end
		
		local liveRoundManager = self.RoundManager
		if liveRoundManager and liveRoundManager:IsPlayerActive(player) then
			liveRoundManager:SetPlayerEliminated(player)
		end
		DebugLog:Log("Character", "[CharacterService] Character died for", player.Name)
	end)
	
	DebugLog:Log("Character", "[CharacterService] Registered character for", player.Name)
end

function CharacterService:_onCharacterRemoving(player, characterModel)
	self:_removeCharacter(player, characterModel)
end

function CharacterService:_removeCharacter(player, characterModel)
	local character = self.CharactersByPlayer[player]
	
	if character then
		character:Destroy()
	end
	
	self.CharactersByPlayer[player] = nil
	
	if characterModel then
		self.CharactersByModel[characterModel] = nil
	end
	
	local playerService = self.PlayerService
	if playerService then
		playerService:SetAlive(player, false)
		playerService:SetMovementState(player, "IsSprinting", false)
		playerService:SetMovementState(player, "IsCrouching", false)
	end

	local statusEffectService = self.StatusEffectService
	if statusEffectService then
		statusEffectService:ClearStatuses(player)
	end
	
	DebugLog:Log("Character", "[CharacterService] Removed character for", player.Name)
end

function CharacterService:FreezeAll()
	for _, character in pairs(self.CharactersByPlayer) do
		character:Freeze()
	end
end

function CharacterService:UnfreezeAll()
	for _, character in pairs(self.CharactersByPlayer) do
		character:Unfreeze()
	end
end

function CharacterService:_cleanupPlayer(player)
	local character = self.CharactersByPlayer[player]
	if character then
		self:_removeCharacter(player, character.Model)
	end
end

function CharacterService:GetCharacterByPlayer(player)
	return self.CharactersByPlayer[player]
end

function CharacterService:GetCharacterByModel(model)
	return self.CharactersByModel[model]
end

return CharacterService
