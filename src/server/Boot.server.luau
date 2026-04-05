local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService:WaitForChild("Server")
local ServicesFolder = ServerFolder:WaitForChild("Services")
local ManagersFolder = ServerFolder:WaitForChild("Managers")

local bootOrder = {
	require(ServicesFolder.RemoteRegistry),
	require(ServicesFolder.PlayerService),
	require(ServicesFolder.CharacterService),
	require(ServicesFolder.SpawnService),
	require(ServicesFolder.ObjectiveService),
	require(ServicesFolder.InteractionService),
	require(ServicesFolder.EntityService),
	require(ServicesFolder.EscapeService),
	require(ManagersFolder.RoundManager),
}

local Services = {}

for _, service in ipairs(bootOrder) do
	Services[service.Name] = service
end

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

print("[Boot] Server boot complete.")
