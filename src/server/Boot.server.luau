local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService:WaitForChild("Server")
local ServicesFolder = ServerFolder:WaitForChild("Services")
local ManagersFolder = ServerFolder:WaitForChild("Managers")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local RingWrapper = require(ReplicatedStorage.Shared.Utility.RingWrapper)

local bootOrder = {
	require(ServicesFolder.RemoteRegistry),
	require(ServicesFolder.PlayerService),
	require(ServicesFolder.CharacterService),
	require(ServicesFolder.MovementService),
	require(ServicesFolder.StatusEffectService),
	require(ServicesFolder.SpawnService),
	require(ServicesFolder.ObjectiveService),
	require(ServicesFolder.InteractionService),
	require(ServicesFolder.EntityService),
	require(ServicesFolder.EscapeService),
	require(ManagersFolder.RoundManager),
}

local Services = RingWrapper.Boot(bootOrder, "Services")

DebugLog:Log("Boot", "[Boot] Server boot complete.")
