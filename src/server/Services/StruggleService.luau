local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local QTEType = require(ReplicatedStorage.Shared.Enums.QTEType)
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
	if not targetCharacter or not targetCharacter:IsAlive() then
		return false
	end

	local existing = self.ActiveStruggles[targetPlayer]
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
	}

	self.ActiveStruggles[targetPlayer] = struggle

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

function StruggleService:IsPlayerStruggling(player)
	return self.ActiveStruggles[player] ~= nil
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
		if not targetCharacter or not targetCharacter:IsAlive() then
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

	self.ActiveStruggles[player] = nil
	self.QTEService:StopSession(player, "Escaped")

	DebugLog:Log("Interaction", string.format("[StruggleService] %s escaped %s", player.Name, struggle.Entity.DisplayName))
end

function StruggleService:_endStruggle(player, reason)
	local struggle = self.ActiveStruggles[player]
	if not struggle then
		return
	end

	local statusService = self.StatusEffectService
	if statusService then
		statusService:RemoveStatus(player, struggle.TargetStatusId)
		statusService:RemoveStatus(struggle.Entity, StatusEffectId.Stunned)
	end

	self.ActiveStruggles[player] = nil
	self.QTEService:StopSession(player, reason or "Ended")
end

return StruggleService
