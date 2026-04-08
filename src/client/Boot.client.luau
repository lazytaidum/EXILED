local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local RingWrapper = require(ReplicatedStorage.Shared.Utility.RingWrapper)

local ClientFolder = playerScripts:WaitForChild("Client")
local ControllersFolder = ClientFolder:WaitForChild("Controllers")
local UIFolder = ClientFolder:WaitForChild("UI")

local bootOrder = {
	require(ControllersFolder.ContextController),
	require(ControllersFolder.ActionResolver),
	require(ControllersFolder.ActionDispatcher),
	require(ControllersFolder.InputController),
	require(ControllersFolder.InteractionController),
	require(ControllersFolder.RoundController),
	require(ControllersFolder.StatusEffectController),
	require(UIFolder.UIController),
}

local Controllers = RingWrapper.Boot(bootOrder, "Controllers")

DebugLog:Log("Boot", "[Boot] Client boot complete.")
