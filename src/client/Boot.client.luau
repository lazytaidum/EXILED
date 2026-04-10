local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local RingWrapper = require(ReplicatedStorage.Shared.Utility.RingWrapper)
local ClientWorld = require(ReplicatedStorage.Shared.World.ClientWorld)

local ClientFolder = playerScripts:WaitForChild("Client")
local ControllersFolder = ClientFolder:WaitForChild("Controllers")
local UIFolder = ClientFolder:WaitForChild("UI")

local bootOrder = {
	require(ControllersFolder.ContextController),
	require(ControllersFolder.ActionResolver),
	require(ControllersFolder.ActionDispatcher),
	require(ControllersFolder.QTEController),
	require(ControllersFolder.BreathHoldController),
	require(ControllersFolder.CameraInputController),
	require(ControllersFolder.CombatController),
	require(ControllersFolder.CrosshairController),
	require(ControllersFolder.StaminaController),
	require(ControllersFolder.RemnantController),
	require(ControllersFolder.NotificationController),
	require(ControllersFolder.AuraRevealController),
	require(ControllersFolder.InputController),
	require(ControllersFolder.InteractionController),
	require(ControllersFolder.InteractableDebugController),
	require(ControllersFolder.DevMenuController),
	require(ControllersFolder.RoundController),
	require(ControllersFolder.StatusEffectController),
	require(ControllersFolder.EntityDebugController),
	require(UIFolder.UIController),
}

local Controllers = RingWrapper.CreateRing(bootOrder)
RingWrapper.Attach(bootOrder, Controllers, "Controllers")

local World = ClientWorld.new(Controllers)
RingWrapper.AttachField(bootOrder, "World", World)

for _, coreGuiType in ipairs({
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.SelfView,
}) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGuiType, false)
	end)
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
