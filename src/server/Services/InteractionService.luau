local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)

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
		if isStarting then
			self:StartInteraction(player)
		else
			self:StopInteraction(player)
		end
	end)
	
	task.spawn(function()
		self:_runInteractionLoop()
	end)
	
	print("[InteractionService] Started")
end

function InteractionService:StartInteraction(player)
	local roundManager = self.Services.RoundManager
	if not roundManager or not roundManager:IsReceptionActive() then
		return
	end
	
	local target = self:FindBestInteractable(player)
	if not target then
		return
	end
	
	self.ActiveInteractions[player] = {
		Target = target,
	}
	
	self.InteractionStateRemote:FireClient(player, {
		State = "Start",
		Target = target.DisplayName,
		Progress = target.Progress or 0,
		Max = target.MaxProgress or 1,
	})
	
	print(string.format("[InteractionService] %s started interacting with %s", player.Name, target.DisplayName))
end

function InteractionService:StopInteraction(player)
	if self.ActiveInteractions[player] then
		local target = self.ActiveInteractions[player].Target
		local name = target and target.DisplayName or "Unknown"
		
		self.InteractionStateRemote:FireClient(player, {
			State = "Stop"
		})
		
		print(string.format("[InteractionService] %s stopped interacting with %s", player.Name, name))
	end
	
	self.ActiveInteractions[player] = nil
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
	end
	
	if not target or target.IsComplete then
		self.ActiveInteractions[player] = nil
		return
	end
	
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		self.ActiveInteractions[player] = nil
		return
	end
	
	local distance = (target.Instance.Position - character.RootPart.Position).Magnitude
	if distance > 12 then
		print(string.format("[InteractionService] %s moved too far from %s", player.Name, target.DisplayName))
		self.ActiveInteractions[player] = nil
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
		self.ActiveInteractions[player] = nil
	end
end

return InteractionService
