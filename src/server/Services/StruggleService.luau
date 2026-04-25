local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local QTEType = require(ReplicatedStorage.Shared.Enums.QTEType)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StruggleService = {}
StruggleService.Name = "StruggleService"
StruggleService.Dependencies = {
	"QTEService",
	"CharacterService",
	"StatusEffectService",
	"InteractionService",
	"EntityService",
}

function StruggleService:Init(services)
	self.Services = services
	self.ActiveStruggles = {}
	self.UpdateInterval = 0.1
end

function StruggleService:Start()
	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Interaction", "[StruggleService] Started")
end

function StruggleService:BeginStruggle(entity, targetPlayer, params)
	if not entity or not targetPlayer then
		return false
	end

	local targetCharacter = self.CharacterService:GetCharacterByPlayer(targetPlayer)
	if not targetCharacter or not targetCharacter:IsActionable() then
		return false
	end

	local canBegin, existing = self:CanBeginStruggle(entity, targetPlayer)
	if not canBegin then
		return false
	end

	if existing then
		self:_endStruggle(targetPlayer, "Replaced")
	end

	local now = os.clock()
	local duration = params.Duration or 6
	local qteConfig = params.QTE or {}
	local struggle = {
		Entity = entity,
		TargetPlayer = targetPlayer,
		StartedAt = now,
		EndsAt = now + duration,
		Progress = 0,
		MaxProgress = params.MaxProgress or 1,
		ProgressPerPress = params.ProgressPerPress or 0.075,
		DamagePerSecond = params.DamagePerSecond or 5,
		HealPercentPerSecond = params.HealPercentPerSecond or 0.02,
		NextTickAt = now + 1,
		EntityRecoverStunDuration = params.EntityRecoverStunDuration or 1,
		TargetStatusId = params.TargetStatusId or StatusEffectId.Stunned,
		PeelDuration = params.PeelDuration or 1.2,
		PeelRange = params.PeelRange or 10,
		PeelProgress = 0,
		LungeOriginCFrame = params.LungeOriginCFrame,
		ReturnEntityOnBreakFree = params.ReturnEntityOnBreakFree == true,
	}

	self.ActiveStruggles[targetPlayer] = struggle
	self:_setGrabDebugMarker(targetPlayer, entity)
	if entity.BeginPinned then
		entity:BeginPinned(targetPlayer, {
			TargetPlayer = targetPlayer,
			TargetPosition = targetCharacter.RootPart.Position,
		})
	end

	if self.InteractionService and self.InteractionService:IsInteracting(targetPlayer) then
		self.InteractionService:InterruptInteraction(targetPlayer, "Struggle")
	end

	local statusService = self.StatusEffectService
	if statusService then
		statusService:ApplyStatus(targetPlayer, struggle.TargetStatusId, {
			Duration = duration,
			Source = entity.DisplayName,
		})
		statusService:ApplyStatus(entity, StatusEffectId.Stunned, {
			Duration = duration,
			Source = "BlindHungerChannel",
		})
	end

	self.QTEService:StartSession(targetPlayer, {
		Type = qteConfig.Type or QTEType.KeyMash,
		Duration = duration,
		Prompt = qteConfig.Prompt or "Mash Space to struggle free",
		SubPrompt = qteConfig.SubPrompt or "Break free before Jiangshi drains your Qi",
		RequiredKey = qteConfig.RequiredKey or "Space",
		Keys = qteConfig.Keys,
		Progress = 0,
		MaxProgress = struggle.MaxProgress,
		ProgressPerPress = qteConfig.ProgressPerPress or struggle.ProgressPerPress,
		WrongPenalty = qteConfig.WrongPenalty or 0.05,
		TargetDistance = qteConfig.TargetDistance,
		MinSliceDelta = qteConfig.MinSliceDelta,
		DialAngle = qteConfig.DialAngle,
		DialSpeed = qteConfig.DialSpeed,
		DialDirection = qteConfig.DialDirection,
		SuccessAngle = qteConfig.SuccessAngle,
		SuccessAngleSize = qteConfig.SuccessAngleSize,
		OnProgress = function(_, session)
			struggle.Progress = session.Progress
		end,
		OnSuccess = function(player)
			self:_breakFree(player, struggle)
		end,
		OnFail = function(player, _, reason)
			self:_endStruggle(player, reason)
		end,
	})

	DebugLog:Log("Interaction", string.format("[StruggleService] %s began struggle on %s", entity.DisplayName, targetPlayer.Name))
	return true
end

function StruggleService:CanBeginStruggle(entity, targetPlayer)
	if not entity or not targetPlayer then
		return false, nil
	end

	local existing = self.ActiveStruggles[targetPlayer]
	if not existing then
		return true, nil
	end

	if existing.Entity == entity then
		return true, existing
	end

	local incomingPriority = tonumber(entity.StarRating) or tonumber(entity.Weight) or 0
	local existingEntity = existing.Entity
	local existingPriority = existingEntity and (tonumber(existingEntity.StarRating) or tonumber(existingEntity.Weight)) or 0

	if incomingPriority > existingPriority then
		return true, existing
	end

	return false, existing
end

function StruggleService:IsEntityStruggling(entity)
	if not entity then
		return false
	end

	for _, struggle in pairs(self.ActiveStruggles) do
		if struggle.Entity == entity then
			return true
		end
	end

	return false
end

function StruggleService:IsPlayerStruggling(player)
	return self.ActiveStruggles[player] ~= nil
end

function StruggleService:GetPeelInteractable(helperPlayer)
	local helperCharacter = self.CharacterService:GetCharacterByPlayer(helperPlayer)
	if not helperCharacter or not helperCharacter.RootPart then
		return nil
	end

	local helperPosition = helperCharacter.RootPart.Position
	for victimPlayer, struggle in pairs(self.ActiveStruggles) do
		if victimPlayer ~= helperPlayer then
			local victimCharacter = self.CharacterService:GetCharacterByPlayer(victimPlayer)
			if victimCharacter and victimCharacter.RootPart and victimCharacter:IsActionable() then
				local distance = (victimCharacter.RootPart.Position - helperPosition).Magnitude
				if distance <= struggle.PeelRange then
					return {
						Type = InteractableType.StrugglePeel,
						DisplayName = string.format("Peel %s Off", struggle.Entity.DisplayName),
						Instance = victimCharacter.RootPart,
						Progress = struggle.PeelProgress,
						MaxProgress = 1,
						ChargeRate = 1 / struggle.PeelDuration,
						StruggleTargetPlayer = victimPlayer,
					}
				end
			end
		end
	end

	return nil
end

function StruggleService:ProgressPeel(helperPlayer, interactable, amount)
	if not interactable or interactable.Type ~= InteractableType.StrugglePeel then
		return false, false
	end

	local struggle = self.ActiveStruggles[interactable.StruggleTargetPlayer]
	if not struggle then
		return false, true
	end

	local helperCharacter = self.CharacterService:GetCharacterByPlayer(helperPlayer)
	local victimCharacter = self.CharacterService:GetCharacterByPlayer(interactable.StruggleTargetPlayer)
	if not helperCharacter or not helperCharacter.RootPart or not victimCharacter or not victimCharacter.RootPart then
		return false, true
	end

	local distance = (victimCharacter.RootPart.Position - helperCharacter.RootPart.Position).Magnitude
	if distance > struggle.PeelRange then
		return false, true
	end

	struggle.PeelProgress = math.clamp((struggle.PeelProgress or 0) + amount, 0, 1)
	if struggle.PeelProgress >= 1 then
		self:_peelFree(interactable.StruggleTargetPlayer, struggle, helperPlayer)
		return true, true
	end

	return true, false
end

function StruggleService:InterruptStrugglesForEntity(entity, reason)
	if not entity then
		return 0
	end

	local interruptedCount = 0
	for player, struggle in pairs(self.ActiveStruggles) do
		if struggle.Entity == entity then
			self:_endStruggle(player, reason or "Interrupted", {
				PreserveEntityStun = true,
			})
			interruptedCount += 1
		end
	end

	return interruptedCount
end

function StruggleService:_runLoop()
	while true do
		self:_updateStruggles()
		task.wait(self.UpdateInterval)
	end
end

function StruggleService:_updateStruggles()
	local now = os.clock()

	for player, struggle in pairs(self.ActiveStruggles) do
		local targetCharacter = self.CharacterService:GetCharacterByPlayer(player)
		if not targetCharacter or not targetCharacter:IsActionable() then
			self:_endStruggle(player, "TargetLost")
			continue
		end

		if not struggle.Entity or not struggle.Entity.IsActive or struggle.Entity.Health <= 0 then
			self:_endStruggle(player, "EntityLost")
			continue
		end

		if now >= struggle.NextTickAt then
			targetCharacter:ApplyDamage(struggle.DamagePerSecond)
			struggle.Entity:HealPercent(struggle.HealPercentPerSecond)
			if self.EntityService then
				self.EntityService:_handleTargetDowned(struggle.Entity, player, targetCharacter)
			end
			struggle.NextTickAt += 1
		end

		if now >= struggle.EndsAt then
			self:_endStruggle(player, "Expired")
		end
	end
end

function StruggleService:_breakFree(player, struggle)
	local statusService = self.StatusEffectService
	if statusService then
		statusService:RemoveStatus(player, struggle.TargetStatusId)
		statusService:RemoveStatus(struggle.Entity, StatusEffectId.Stunned)
		statusService:ApplyStatus(struggle.Entity, StatusEffectId.Stunned, {
			Duration = struggle.EntityRecoverStunDuration,
			Source = "BlindHungerBreakFree",
		})
	end

	self:_returnEntityAfterBreakFree(struggle)
	if struggle.Entity and struggle.Entity.EndPinned then
		struggle.Entity:EndPinned("Stunned", {
			TargetPlayer = player,
			TargetPosition = nil,
			HasDirectSight = false,
		})
	end
	self.ActiveStruggles[player] = nil
	self:_clearGrabDebugMarker(player)
	self.QTEService:StopSession(player, "Escaped")

	DebugLog:Log("Interaction", string.format("[StruggleService] %s escaped %s", player.Name, struggle.Entity.DisplayName))
end

function StruggleService:_peelFree(player, struggle, helperPlayer)
	local statusService = self.StatusEffectService
	if statusService then
		statusService:RemoveStatus(player, struggle.TargetStatusId)
		statusService:RemoveStatus(struggle.Entity, StatusEffectId.Stunned)
		statusService:ApplyStatus(struggle.Entity, StatusEffectId.Stunned, {
			Duration = struggle.EntityRecoverStunDuration,
			Source = "BlindHungerPeeled",
		})
	end

	self:_returnEntityAfterBreakFree(struggle)
	if struggle.Entity and struggle.Entity.EndPinned then
		struggle.Entity:EndPinned("Stunned", {
			TargetPlayer = player,
			TargetPosition = nil,
			HasDirectSight = false,
		})
	end
	self.ActiveStruggles[player] = nil
	self:_clearGrabDebugMarker(player)
	self.QTEService:StopSession(player, "Peeled")

	DebugLog:Log("Interaction", string.format("[StruggleService] %s peeled %s off %s", helperPlayer and helperPlayer.Name or "Unknown", struggle.Entity.DisplayName, player.Name))
end

function StruggleService:_endStruggle(player, reason, options)
	local struggle = self.ActiveStruggles[player]
	if not struggle then
		return
	end

	options = options or {}

	local statusService = self.StatusEffectService
	if statusService then
		statusService:RemoveStatus(player, struggle.TargetStatusId)
		if not options.PreserveEntityStun then
			statusService:RemoveStatus(struggle.Entity, StatusEffectId.Stunned)
		end
	end

	if struggle.Entity and struggle.Entity.GetState and struggle.Entity:GetState() == "Pinned" and struggle.Entity.EndPinned then
		struggle.Entity:EndPinned(nil, {
			TargetPlayer = player,
			TargetPosition = nil,
			HasDirectSight = false,
		})
	end

	self.ActiveStruggles[player] = nil
	self:_clearGrabDebugMarker(player)
	self.QTEService:StopSession(player, reason or "Ended")
end

function StruggleService:_returnEntityAfterBreakFree(struggle)
	if not struggle or not struggle.ReturnEntityOnBreakFree then
		return
	end

	local entity = struggle.Entity
	if not entity or not entity.RootPart or not struggle.LungeOriginCFrame then
		return
	end

	entity.RootPart.CFrame = struggle.LungeOriginCFrame
end

function StruggleService:_setGrabDebugMarker(player, entity)
	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.Model then
		return
	end

	character.Model:SetAttribute("DebugIsGrabbed", true)
	character.Model:SetAttribute("DebugGrabbedBy", entity and entity.DisplayName or "Entity")

	local existing = character.Model:FindFirstChild("StruggleDebugHighlight")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "StruggleDebugHighlight"
	highlight.FillColor = Color3.fromRGB(214, 92, 92)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.fromRGB(255, 208, 122)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character.Model
end

function StruggleService:_clearGrabDebugMarker(player)
	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.Model then
		return
	end

	character.Model:SetAttribute("DebugIsGrabbed", nil)
	character.Model:SetAttribute("DebugGrabbedBy", nil)

	local existing = character.Model:FindFirstChild("StruggleDebugHighlight")
	if existing then
		existing:Destroy()
	end
end

return StruggleService
