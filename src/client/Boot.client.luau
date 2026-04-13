local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ClientFolder = playerScripts:WaitForChild("Client")
local ControllersFolder = ClientFolder:WaitForChild("Controllers")
local UIFolder = ClientFolder:WaitForChild("UI")

local bootOrder = {
	require(ControllersFolder.InputController),
	require(ControllersFolder.WeaponController),
	require(ControllersFolder.InteractionController),
	require(ControllersFolder.RoundController),
	require(UIFolder.UIController),
}

local Controllers = {}

for _, controller in ipairs(bootOrder) do
	Controllers[controller.Name] = controller
end

for _, controller in ipairs(bootOrder) do
	if controller.Init then
		controller:Init(Controllers)
	end
end

for _, controller in ipairs(bootOrder) do
	if controller.Start then
		controller:Start()
	end
end

DebugLog:Log("Boot", "[Boot] Client boot complete.")
