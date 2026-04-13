local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InputContext = require(ReplicatedStorage.Shared.Enums.InputContext)

local ContextController = {}
ContextController.Name = "ContextController"

function ContextController:Init()
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
end

function ContextController:GetSnapshot()
	return {
		[InputContext.SkillCheck] = self:_isSkillCheckActive(),
		[InputContext.DoorSlam] = false,
		[InputContext.NearObjective] = self:_isNearObjective(),
		[InputContext.NearToolboxObjective] = self:_isNearToolboxObjective(),
		[InputContext.InventoryOpen] = self:_isGuiEnabled("InventoryUI"),
		[InputContext.RadialMenuOpen] = self:_isGuiEnabled("RadialMenuUI"),
		[InputContext.ChatFocused] = UserInputService:GetFocusedTextBox() ~= nil,
	}
end

function ContextController:_isNearObjective()
	local character = self.Player.Character
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	local objectivesFolder = Workspace:FindFirstChild("Objectives")
	if not objectivesFolder then
		return false
	end

	for _, objective in ipairs(objectivesFolder:GetChildren()) do
		if objective:IsA("BasePart") then
			local distance = (objective.Position - rootPart.Position).Magnitude
			if distance <= 12 then
				return true
			end
		elseif objective:IsA("Model") and objective.PrimaryPart then
			local distance = (objective.PrimaryPart.Position - rootPart.Position).Magnitude
			if distance <= 12 then
				return true
			end
		end
	end

	return false
end

function ContextController:_isNearToolboxObjective()
	return false
end

function ContextController:_isSkillCheckActive()
	return self:_isGuiEnabled("SkillCheckUI")
end

function ContextController:_isGuiEnabled(guiName)
	local gui = self.PlayerGui:FindFirstChild(guiName)
	return gui ~= nil and gui.Enabled == true
end

return ContextController
