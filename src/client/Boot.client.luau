local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldMode = require(ReplicatedStorage.Shared.Enums.WorldMode)
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)
local RingWrapper = require(ReplicatedStorage.Shared.Utility.RingWrapper)
local ClientWorld = require(ReplicatedStorage.Shared.World.ClientWorld)

local ClientFolder = playerScripts:WaitForChild("Client")
local ControllersFolder = ClientFolder:WaitForChild("Controllers")
local UIFolder = ClientFolder:WaitForChild("UI")

local function _buildGameplayBootOrder()
	return {
		require(ControllersFolder.ContextController),
		require(ControllersFolder.ActionResolver),
		require(ControllersFolder.ActionDispatcher),
		require(ControllersFolder.QTEController),
		require(ControllersFolder.BreathHoldController),
		require(ControllersFolder.CameraInputController),
		require(ControllersFolder.CombatController),
		require(ControllersFolder.ViewmodelController),
		require(ControllersFolder.FirearmPresentationController),
		require(ControllersFolder.EntityAbilityVisualController),
		require(ControllersFolder.CrosshairController),
		require(ControllersFolder.StaminaController),
		require(ControllersFolder.SurvivabilityFeedbackController),
		require(ControllersFolder.RemnantController),
		require(ControllersFolder.NotificationController),
		require(ControllersFolder.AuraRevealController),
		require(ControllersFolder.InputController),
		require(ControllersFolder.InteractionController),
		require(ControllersFolder.InteractableDebugController),
		require(ControllersFolder.DevMenuController),
		require(ControllersFolder.RoundController),
		require(ControllersFolder.VotingController),
		require(ControllersFolder.StatusEffectController),
		require(ControllersFolder.EntityDebugController),
		require(UIFolder.UIController),
	}
end

local function _buildWeaponLabBootOrder()
	return {
		require(ControllersFolder.ContextController),
		require(ControllersFolder.ActionResolver),
		require(ControllersFolder.ActionDispatcher),
		require(ControllersFolder.RoundController),
		require(ControllersFolder.CameraInputController),
		require(ControllersFolder.CombatController),
		require(ControllersFolder.ViewmodelController),
		require(ControllersFolder.FirearmPresentationController),
		require(ControllersFolder.CrosshairController),
		require(ControllersFolder.StaminaController),
		require(ControllersFolder.InputController),
		require(ControllersFolder.WeaponLabController),
	}
end

local bootOrder = WorldModeResolver.GetWorldMode() == WorldMode.WeaponLab
	and _buildWeaponLabBootOrder()
	or _buildGameplayBootOrder()

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
