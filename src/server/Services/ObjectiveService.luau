local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseObjective = require(ServerScriptService.Server.Classes.BaseObjective)
local ObjectiveDefinitions = require(ReplicatedStorage.Shared.Data.ObjectiveDefinitions)
local ObjectivePhase = require(ReplicatedStorage.Shared.Enums.ObjectivePhase)

local ObjectiveService = {}
ObjectiveService.Name = "ObjectiveService"

function ObjectiveService:Init(services)
	self.Services = services
	self.Objectives = {}
	
	self.ObjectivesFolder = Workspace:WaitForChild("Objectives")
end

function ObjectiveService:Start()
	self:_registerExistingObjectives()
	print("[ObjectiveService] Started")
end

function ObjectiveService:_registerExistingObjectives()
	for _, instance in ipairs(self.ObjectivesFolder:GetChildren()) do
		local definition = ObjectiveDefinitions[instance.Name]
		local objective = BaseObjective.new(instance, definition)
		
		table.insert(self.Objectives, objective)
		
		print(string.format(
			"[ObjectiveService] Registered objective: %s | Type: %s | Phase: %s",
			objective.DisplayName,
			objective.Type,
			objective.Phase
		))
	end
end

function ObjectiveService:GetObjectives()
	return self.Objectives
end

function ObjectiveService:GetObjectivesByPhase(objectivePhase)
	local results = {}
	
	for _, objective in ipairs(self.Objectives) do
		if objective.Phase == objectivePhase then
			table.insert(results, objective)
		end
	end
	
	return results
end

function ObjectiveService:SetPhaseEnabled(objectivePhase, enabled)
	for _, objective in ipairs(self.Objectives) do
		if objective.Phase == objectivePhase then
			objective:SetEnabled(enabled)
		end
	end
	
	print(string.format("[ObjectiveService] Set phase '%s' enabled = %s", objectivePhase, tostring(enabled)))
end

function ObjectiveService:ResetObjectives()
	for _, objective in ipairs(self.Objectives) do
		objective.Progress = 0
		objective.IsComplete = false
		objective.IsEnabled = objective.StartsEnabled
	end
	
	print("[ObjectiveService] Objectives reset")
end

function ObjectiveService:TryProgressObjectiveByName(name, amount)
	for _, objective in ipairs(self.Objectives) do
		if objective.Id == name or objective.DisplayName == name or (objective.Instance and objective.Instance.Name == name) then
			return self:ProgressObjective(objective, amount)
		end
	end
	
	return false
end

function ObjectiveService:ProgressObjective(objective, amount)
	if not objective or objective.IsComplete then
		return false
	end
	
	local succeeded = objective:AddProgress(amount)
	if not succeeded then
		return false
	end
	
	print(string.format(
		"[ObjectiveService] %s progress: %1.f / %1.f",
		objective.DisplayName,
		objective.Progress,
		objective.MaxProgress
	))
	
	if objective.IsComplete then
		print("[ObjectiveService] Completed objective:", objective.DisplayName)
		
		local roundManager = self.Services.RoundManager
		if roundManager and roundManager.OnObjectiveCompleted then
			roundManager:OnObjectiveCompleted(objective)
		end
	end
	
	return true
end

return ObjectiveService
