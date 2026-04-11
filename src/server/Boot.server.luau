local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService:WaitForChild("Server")
local ServicesFolder = ServerFolder:WaitForChild("Services")
local ManagersFolder = ServerFolder:WaitForChild("Managers")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local RingWrapper = require(ReplicatedStorage.Shared.Utility.RingWrapper)
local ServerWorld = require(ReplicatedStorage.Shared.World.ServerWorld)

local bootOrder = {
	require(ServicesFolder.RemoteRegistry),
	require(ServicesFolder.DevService),
	require(ServicesFolder.PlayerService),
	require(ServicesFolder.CharacterService),
	require(ServicesFolder.StimulusService),
	require(ServicesFolder.StaminaService),
	require(ServicesFolder.MovementService),
	require(ServicesFolder.StatusEffectService),
	require(ServicesFolder.InventoryService),
	require(ServicesFolder.CombatService),
	require(ServicesFolder.WeaponPickupService),
	require(ServicesFolder.ItemPickupService),
	require(ServicesFolder.EnvironmentalHazardService),
	require(ServicesFolder.QTEService),
	require(ServicesFolder.StruggleService),
	require(ServicesFolder.BreathHoldService),
	require(ServicesFolder.SpawnService),
	require(ServicesFolder.ObjectiveService),
	require(ServicesFolder.RoundHookService),
	require(ServicesFolder.InteractionService),
	require(ServicesFolder.EntityService),
	require(ServicesFolder.RemnantService),
	require(ServicesFolder.EscapeService),
	require(ServicesFolder.VotingService),
	require(ManagersFolder.RoundManager),
}

local Services = RingWrapper.CreateRing(bootOrder)
RingWrapper.Attach(bootOrder, Services, "Services")

local World = ServerWorld.new(Services)
RingWrapper.AttachField(bootOrder, "World", World)

for _, service in ipairs(bootOrder) do
	if service.Init then
		service:Init(Services)
	end
end

for _, service in ipairs(bootOrder) do
	if service.Start then
		service:Start()
	end
end

DebugLog:Log("Boot", "[Boot] Server boot complete.")
