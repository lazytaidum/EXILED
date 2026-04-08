local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StruggleService = {}
StruggleService.Name = "StruggleService"
StruggleService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"StatusEffectService",
	"InteractionService",
}

function StruggleService:Init(services)
	self.Services = services
	self.ActiveStruggles = {}
	self.UpdateInterval = 0.1
end

function StruggleService:Start()
	self.StruggleStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.StruggleStateChanged)
	local requestStruggleInput = self.RemoteRegistry:GetRemote(RemoteNames.RequestStruggleInput)

	requestStruggleInput.OnServerEvent:Connect(function(player)
		self:HandleStruggleInput(player)
	end)

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

	self:_syncStruggle(targetPlayer, struggle, "Start")
	DebugLog:Log("Interaction", string.format("[StruggleService] %s began struggle on %s", entity.DisplayName, targetPlayer.Name))
	return true
end

function StruggleService:HandleStruggleInput(player)
	local struggle = self.ActiveStruggles[player]
	if not struggle then
		return
	end

	struggle.Progress = math.min(struggle.MaxProgress, struggle.Progress + struggle.ProgressPerPress)
	self:_syncStruggle(player, struggle, "Update")

	if struggle.Progress >= struggle.MaxProgress then
		self:_breakFree(player, struggle)
	end
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
			struggle.NextTickAt += 1
			self:_syncStruggle(player, struggle, "Update")
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
	self.StruggleStateRemote:FireClient(player, {
		State = "Stop",
		Reason = "Escaped",
	})

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
	self.StruggleStateRemote:FireClient(player, {
		State = "Stop",
		Reason = reason or "Ended",
	})
end

function StruggleService:_syncStruggle(player, struggle, state)
	if not self.StruggleStateRemote then
		return
	end

	self.StruggleStateRemote:FireClient(player, {
		State = state or "Update",
		Prompt = "Mash Space to struggle free",
		SubPrompt = "Break free before Jiangshi drains your Qi",
		RequiredKey = "SPACE",
		Progress = struggle.Progress,
		Max = struggle.MaxProgress,
		Duration = math.max(0, struggle.EndsAt - os.clock()),
	})
end

return StruggleService
