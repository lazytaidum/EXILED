local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractionService = {}
InteractionService.Name = "InteractionService"

function InteractionService:Init(services)
	self.Services = services
	self.ActiveInteractions = {}
end

function InteractionService:Start()
	self.InteractionStateRemote = self.Services.RemoteRegistry:GetRemote(RemoteNames.InteractionStateChanged)
	self.UpdateInterval = 0.1
	
	local requestInteract = self.Services.RemoteRegistry:GetRemote(RemoteNames.RequestInteract)
	
	requestInteract.OnServerEvent:Connect(function(player, isStarting)
		DebugLog:Log("Interaction", string.format("[InteractionService] Remote received from %s (start=%s)", player.Name, tostring(isStarting)))
		if isStarting then
			self:StartInteraction(player)
		else
			self:StopInteraction(player)
		end
	end)
	
	task.spawn(function()
		self:_runInteractionLoop()
	end)
	
	DebugLog:Log("Interaction", "[InteractionService] Started")
end

function InteractionService:StartInteraction(player)
	local roundManager = self.Services.RoundManager
	if not roundManager or not roundManager:IsReceptionActive() then
		DebugLog:Log("Interaction", string.format("[InteractionService] Ignored start for %s: reception inactive", player.Name))
		return
	end
	
	local target = self:FindBestInteractable(player)
	if not target then
		DebugLog:Log("Interaction", string.format("[InteractionService] Ignored start for %s: no valid target", player.Name))
		return
	end
	
	self.ActiveInteractions[player] = {
		Target = target,
	}
	
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetSpeedMultiplier("InteractionSlow", 0.5)
	end
	
	self.InteractionStateRemote:FireClient(player, {
		State = "Start",
		Target = target.DisplayName,
		Progress = target.Progress or 0,
		Max = target.MaxProgress or 1,
	})
	
	DebugLog:Log("Interaction", string.format("[InteractionService] %s started interacting with %s", player.Name, target.DisplayName))
end

function InteractionService:StopInteraction(player)
	if self.ActiveInteractions[player] then
		local target = self.ActiveInteractions[player].Target
		local name = target and target.DisplayName or "Unknown"
		
		local character = self.Services.CharacterService:GetCharacterByPlayer(player)
		if character then
			character:SetSpeedMultiplier("InteractionSlow", nil)
		end
		
		self.InteractionStateRemote:FireClient(player, {
			State = "Stop"
		})
		
		DebugLog:Log("Interaction", string.format("[InteractionService] %s stopped interacting with %s", player.Name, name))
	end
	
	self.ActiveInteractions[player] = nil
end

function InteractionService:InterruptInteraction(player, reason)
	if not self.ActiveInteractions[player] then
		return false
	end
	
	self:StopInteraction(player)
	DebugLog:Log("Interaction", string.format("[InteractionService] %s interaction interrupted (%s)", player.Name, tostring(reason or "Unknown")))
	return true
end

function InteractionService:StopAllInteractions(reason)
	for player in pairs(self.ActiveInteractions) do
		self:InterruptInteraction(player, reason or "StoppedAll")
	end
end

function InteractionService:IsInteracting(player)
	return self.ActiveInteractions[player] ~= nil
end

function InteractionService:FindBestInteractable(player)
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return nil
	end
	
	local playerPosition = character.RootPart.Position
	local bestTarget = nil
	local bestDistance = math.huge
	
	for _, objective in ipairs(self.Services.ObjectiveService:GetObjectives()) do
		if objective.Type == InteractableType.Objective or objective.Type == "MapObjective" then
			if objective:CanInteract() and objective.Instance then
				local distance = (objective.Instance.Position - playerPosition).Magnitude
				if distance <= 12 and distance < bestDistance then
					bestTarget = objective
					bestDistance = distance
				end
			end
		end
	end
	
	return bestTarget
end

function InteractionService:_runInteractionLoop()
	while true do
		for player, interaction in pairs(self.ActiveInteractions) do
			self:_updateInteraction(player, interaction)
		end
		
		task.wait(self.UpdateInterval)
	end
end

function InteractionService:_updateInteraction(player, interaction)
	local target = interaction.Target
	
	if target.IsComplete then
		self.InteractionStateRemote:FireClient(player, {
			State = "Complete"
		})
		self:StopInteraction(player)
		return
	end
	
	if not target or target.IsComplete then
		self:StopInteraction(player)
		return
	end
	
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		self:StopInteraction(player)
		return
	end
	
	local distance = (target.Instance.Position - character.RootPart.Position).Magnitude
	if distance > 12 then
		DebugLog:Log("Interaction", string.format("[InteractionService] %s moved too far from %s", player.Name, target.DisplayName))
		self:StopInteraction(player)
		return
	end
	
	local amount = target.ChargeRate * self.UpdateInterval
	local progressed = self.Services.ObjectiveService:ProgressObjective(target, amount)
	
	self.InteractionStateRemote:FireClient(player, {
		State = "Update",
		Target = target.DisplayName,
		Progress = target.Progress,
		Max = target.MaxProgress or 1,
	})
	
	if not progressed or target.IsComplete then
		self:StopInteraction(player)
	end
end

return InteractionService
