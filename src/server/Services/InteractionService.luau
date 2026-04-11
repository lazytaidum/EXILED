local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InteractionService = {}
InteractionService.Name = "InteractionService"
InteractionService.Dependencies = {
	"RemoteRegistry",
	"RoundManager",
	"StatusEffectService",
	"QTEService",
	"CharacterService",
	"ObjectiveService",
	"WeaponPickupService",
	"ItemPickupService",
	"EnvironmentalHazardService",
	"StruggleService",
}

function InteractionService:Init(services)
	self.Services = services
	self.ActiveInteractions = {}
end

function InteractionService:Start()
	self.InteractionStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.InteractionStateChanged)
	self.UpdateInterval = 0.1
	
	local requestInteract = self.RemoteRegistry:GetRemote(RemoteNames.RequestInteract)
	
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
	local roundManager = self.RoundManager
	if not roundManager or not roundManager:IsReceptionActive() then
		DebugLog:Log("Interaction", string.format("[InteractionService] Ignored start for %s: reception inactive", player.Name))
		return
	end

	local statusService = self.StatusEffectService
	if statusService and not statusService:CanInteract(player) then
		if self.QTEService and self.QTEService:IsSessionActive(player) then
			self.QTEService:HandleInput(player, {
				Kind = "Press",
				Key = "Space",
			})
			DebugLog:Log("Interaction", string.format("[InteractionService] Routed interact press from %s into active QTE", player.Name))
			return
		end

		DebugLog:Log("Interaction", string.format("[InteractionService] Ignored start for %s: status blocked", player.Name))
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
	
	local character = self.CharacterService:GetCharacterByPlayer(player)
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
		
		local character = self.CharacterService:GetCharacterByPlayer(player)
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
	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return nil
	end
	
	local playerPosition = character.RootPart.Position
	local bestTarget = nil
	local bestDistance = math.huge

	local struggleService = self.StruggleService
	if struggleService then
		local peelTarget = struggleService:GetPeelInteractable(player)
		if peelTarget and peelTarget.Instance then
			local distance = (peelTarget.Instance.Position - playerPosition).Magnitude
			if distance <= 12 then
				return peelTarget
			end
		end
	end
	
	for _, objective in ipairs(self.ObjectiveService:GetObjectives()) do
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

	local weaponPickupService = self.WeaponPickupService
	if weaponPickupService then
		for _, pickup in ipairs(weaponPickupService:GetAvailablePickups()) do
			local pickupInstance = pickup.Instance
			if pickupInstance then
				local distance = (pickupInstance.Position - playerPosition).Magnitude
				if distance <= 12 and distance < bestDistance then
					bestTarget = pickup
					bestDistance = distance
				end
			end
		end
	end

	local itemPickupService = self.ItemPickupService
	if itemPickupService then
		for _, pickup in ipairs(itemPickupService:GetAvailablePickups()) do
			local pickupInstance = pickup.Instance
			if pickupInstance then
				local distance = (pickupInstance.Position - playerPosition).Magnitude
				if distance <= 12 and distance < bestDistance then
					bestTarget = pickup
					bestDistance = distance
				end
			end
		end
	end

	local environmentalHazardService = self.EnvironmentalHazardService
	if environmentalHazardService then
		for _, hazard in ipairs(environmentalHazardService:GetAvailableHazards()) do
			local hazardInstance = hazard.Instance
			if hazardInstance then
				local distance = (hazardInstance.Position - playerPosition).Magnitude
				if distance <= 12 and distance < bestDistance then
					bestTarget = hazard
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

	if target and target.Type == InteractableType.WeaponPickup then
		local completed = self.WeaponPickupService and self.WeaponPickupService:CompletePickup(player, target)
		self.InteractionStateRemote:FireClient(player, {
			State = completed and "Complete" or "Stop"
		})
		self:StopInteraction(player)
		return
	end

	if target and target.Type == InteractableType.ItemPickup then
		local completed = self.ItemPickupService and self.ItemPickupService:CompletePickup(player, target)
		self.InteractionStateRemote:FireClient(player, {
			State = completed and "Complete" or "Stop"
		})
		self:StopInteraction(player)
		return
	end

	if target and target.Type == InteractableType.EnvironmentalHazard then
		local completed = self.EnvironmentalHazardService and self.EnvironmentalHazardService:CompleteHazard(player, target)
		self.InteractionStateRemote:FireClient(player, {
			State = completed and "Complete" or "Stop"
		})
		self:StopInteraction(player)
		return
	end

	if target and target.Type == InteractableType.StrugglePeel then
		local amount = target.ChargeRate * self.UpdateInterval
		local progressed, completed = self.StruggleService and self.StruggleService:ProgressPeel(player, target, amount)
		if not progressed then
			self.InteractionStateRemote:FireClient(player, {
				State = "Stop"
			})
			self:StopInteraction(player)
			return
		end

		target.Progress = self.StruggleService.ActiveStruggles[target.StruggleTargetPlayer]
			and self.StruggleService.ActiveStruggles[target.StruggleTargetPlayer].PeelProgress
			or target.Progress

		self.InteractionStateRemote:FireClient(player, {
			State = completed and "Complete" or "Update",
			Target = target.DisplayName,
			Progress = math.clamp(target.Progress or 0, 0, target.MaxProgress or 1),
			Max = target.MaxProgress or 1,
		})

		if completed then
			self:StopInteraction(player)
		end
		return
	end
	
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
	
	local character = self.CharacterService:GetCharacterByPlayer(player)
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
	local progressed = self.ObjectiveService:ProgressObjective(target, amount)
	
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
