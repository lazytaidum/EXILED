local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local SpawnService = {}
SpawnService.Name = "SpawnService"

function SpawnService:Init(services)
	self.Services = services
	
	local spawnsFolder = Workspace:WaitForChild("Spawns")
	self.LobbySpawn = spawnsFolder:WaitForChild("LobbySpawn")
	self.ReceptionSpawnsFolder = spawnsFolder:WaitForChild("ReceptionSpawns")
	self.EntitySpawnsFolder = spawnsFolder:FindFirstChild("EntitySpawns")
end

function SpawnService:Start()
	DebugLog:Log("Spawn", "[SpawnService] Started")
end

function SpawnService:TeleportPlayerToLobby(player)
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return
	end
	
	character.RootPart.CFrame = self.LobbySpawn.CFrame + Vector3.new(0,3,0)
end

function SpawnService:TeleportPlayerToReception(player)
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return
	end
	
	local spawnPart = self:GetRandomReceptionSpawn()
	if not spawnPart then
		warn("[SpawnService] No reception spawn found!")
		return
	end
	
	character.RootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
end

function SpawnService:GetRandomReceptionSpawn()
	local spawns = self.ReceptionSpawnsFolder:GetChildren()
	if #spawns == 0 then
		return nil
	end
	
	return spawns[math.random(1, #spawns)]
end

function SpawnService:GetRandomEntitySpawn()
	local entitySpawnsFolder = self.EntitySpawnsFolder
	if entitySpawnsFolder and entitySpawnsFolder.Parent then
		local spawns = entitySpawnsFolder:GetChildren()
		if #spawns > 0 then
			return spawns[math.random(1, #spawns)]
		end
	end

	return self:GetRandomReceptionSpawn()
end

function SpawnService:TeleportPlayersToLobby(players)
	for _, player in ipairs(players) do
		self:TeleportPlayerToLobby(player)
	end
end

function SpawnService:TeleportPlayersToReception(players)
	for _, player in ipairs(players) do
		self:TeleportPlayerToReception(player)
	end
end

function SpawnService:TeleportAllPlayersToLobby()
	for player in pairs(self.Services.PlayerService.PlayerStates) do
		self:TeleportPlayerToLobby(player)
	end
end

function SpawnService:TeleportAllPlayersToReception()
	for player in pairs(self.Services.PlayerService.PlayerStates) do
		self:TeleportPlayerToReception(player)
	end
end

return SpawnService
