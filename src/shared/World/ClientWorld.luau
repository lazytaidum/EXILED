local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientWorld = {}
ClientWorld.__index = ClientWorld

function ClientWorld.new(controllers)
	local self = setmetatable({}, ClientWorld)

	self.Controllers = controllers
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
	self.Camera = Workspace.CurrentCamera
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.Remotes = self.Shared:WaitForChild("Remotes")

	return self
end

function ClientWorld:GetContextSnapshot()
	local contextController = self.Controllers.ContextController
	return contextController and contextController:GetSnapshot() or {}
end

function ClientWorld:GetRoundState()
	local roundController = self.Controllers.RoundController
	return roundController and roundController:GetState() or nil
end

function ClientWorld:DispatchAction(actionName, phase)
	local actionDispatcher = self.Controllers.ActionDispatcher
	if actionDispatcher then
		actionDispatcher:Dispatch(actionName, phase)
	end
end

return ClientWorld
