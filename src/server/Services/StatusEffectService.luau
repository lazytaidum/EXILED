local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local StatusEffectDefinitions = require(ReplicatedStorage.Shared.Data.StatusEffectDefinitions)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StatusEffectService = {}
StatusEffectService.Name = "StatusEffectService"
StatusEffectService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"CombatService",
}

function StatusEffectService:Init(services)
	self.Services = services
	self.ActiveStatuses = {}
	self.UpdateInterval = 0.1
end

function StatusEffectService:Start()
	self.StatusEffectsChangedRemote = self.RemoteRegistry:GetRemote(RemoteNames.StatusEffectsChanged)

	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Status", "[StatusEffectService] Started")
end

function StatusEffectService:ApplyStatus(target, statusId, params)
	local definition = StatusEffectDefinitions[statusId]
	if not definition or not target then
		return nil
	end

	local targetType = self:_getTargetType(target)
	if not self:_statusAllowsTarget(definition, targetType) then
		return nil
	end

	local targetState = self:_getOrCreateTargetState(target)
	local instance = self:_getPrimaryStatusInstance(targetState, statusId)

	if definition.IsDamageOverTime then
		instance = self:_applyDotStatus(target, definition, params or {}, instance)
	else
		instance = self:_applySimpleStatus(target, definition, params or {}, instance)
	end

	self:_markTargetDirty(target)
	self:_refreshTargetGameplayState(target)

	DebugLog:Log("Status", string.format("[StatusEffectService] Applied %s to %s", statusId, self:_describeTarget(target)))
	return instance
end

function StatusEffectService:RemoveStatus(target, statusId)
	local targetState = self.ActiveStatuses[target]
	if not targetState then
		return false
	end

	local bucket = targetState.ById[statusId]
	if not bucket or #bucket == 0 then
		return false
	end

	targetState.ById[statusId] = nil
	for index = #targetState.List, 1, -1 do
		if targetState.List[index].Id == statusId then
			table.remove(targetState.List, index)
		end
	end

	self:_markTargetDirty(target)
	self:_refreshTargetGameplayState(target)
	return true
end

function StatusEffectService:ClearStatuses(target)
	if not self.ActiveStatuses[target] then
		return false
	end

	self.ActiveStatuses[target] = nil
	self:_syncTarget(target)
	self:_refreshTargetGameplayState(target)
	return true
end

function StatusEffectService:HasStatus(target, statusId)
	local targetState = self.ActiveStatuses[target]
	local bucket = targetState and targetState.ById[statusId]
	return bucket ~= nil and #bucket > 0
end

function StatusEffectService:GetModifier(target, modifierName)
	local targetState = self.ActiveStatuses[target]
	if not targetState then
		return 0
	end

	local total = 0
	for _, instance in ipairs(targetState.List) do
		local definition = StatusEffectDefinitions[instance.Id]
		local modifiers = definition and definition.Modifiers
		local valueSource = modifiers and modifiers[modifierName]
		if valueSource == "Magnitude" then
			total += instance.Magnitude or 0
		elseif type(valueSource) == "number" then
			total += valueSource
		end
	end

	return total
end

function StatusEffectService:HasFlag(target, flagName)
	local targetState = self.ActiveStatuses[target]
	if not targetState then
		return false
	end

	for _, instance in ipairs(targetState.List) do
		local definition = StatusEffectDefinitions[instance.Id]
		if definition and definition.Flags and definition.Flags[flagName] then
			return true
		end
	end

	return false
end

function StatusEffectService:CanUseAbilities(target)
	return not self:HasFlag(target, "BlocksAbilities") and not self:HasFlag(target, "Stunned")
end

function StatusEffectService:CanInteract(target)
	return not self:HasFlag(target, "BlocksInteraction") and not self:HasFlag(target, "Stunned")
end

function StatusEffectService:CanBeHealed(target)
	return not self:HasFlag(target, "BlocksHealing")
end

function StatusEffectService:GetSnapshotForPlayer(player)
	local targetState = self.ActiveStatuses[player]
	local snapshot = {}
	if not targetState then
		return snapshot
	end

	local now = os.clock()
	local grouped = {}
	for _, instance in ipairs(targetState.List) do
		local group = grouped[instance.Id]
		if not group then
			local definition = StatusEffectDefinitions[instance.Id]
			group = {
				Id = instance.Id,
				DisplayName = definition and definition.DisplayName or instance.Id,
				ShortLabel = definition and definition.ShortLabel or string.sub(instance.Id, 1, 3),
				IsBuff = definition and definition.IsBuff == true or false,
				Duration = 0,
				Stacks = 0,
				Tier = 1,
				Magnitude = 0,
				InstanceCount = 0,
			}
			grouped[instance.Id] = group
		end

		group.Duration = math.max(group.Duration, math.max(0, instance.ExpiresAt - now))
		group.Stacks = math.max(group.Stacks, instance.Stacks or 1)
		group.Tier = math.max(group.Tier, instance.Tier or 1)
		group.Magnitude += instance.Magnitude or 0
		group.InstanceCount += 1
	end

	for _, group in pairs(grouped) do
		if group.InstanceCount > 1 then
			group.Stacks = math.max(group.Stacks, group.InstanceCount)
		end
		table.insert(snapshot, group)
	end

	table.sort(snapshot, function(a, b)
		if a.IsBuff ~= b.IsBuff then
			return a.IsBuff and not b.IsBuff
		end
		return a.DisplayName < b.DisplayName
	end)

	return snapshot
end

function StatusEffectService:_applySimpleStatus(target, definition, params, existing)
	local duration = params.Duration or definition.DefaultDuration or 0
	local magnitude = params.Magnitude
	if magnitude == nil then
		magnitude = definition.DefaultMagnitude or 0
	end

	local now = os.clock()
	if definition.AllowMultipleInstances then
		local instance = {
			Id = definition.Id,
			AppliedAt = now,
			ExpiresAt = now + duration,
			Magnitude = magnitude,
			Stacks = params.Stacks or 1,
			Tier = params.Tier or definition.DefaultTier or 1,
			Source = params.Source,
		}

		self:_insertStatusInstance(target, instance)
		return instance
	end

	if existing then
		existing.ExpiresAt = now + duration
		existing.Magnitude = math.max(existing.Magnitude or 0, magnitude)
		existing.Stacks = math.max(existing.Stacks or 1, params.Stacks or 1)
		return existing
	end

	local instance = {
		Id = definition.Id,
		AppliedAt = now,
		ExpiresAt = now + duration,
		Magnitude = magnitude,
		Stacks = params.Stacks or 1,
		Tier = params.Tier or definition.DefaultTier or 1,
		Source = params.Source,
	}

	self:_insertStatusInstance(target, instance)
	return instance
end

function StatusEffectService:_applyDotStatus(target, definition, params, existing)
	local duration = params.Duration or definition.DefaultDuration or 0
	local tier = params.Tier or definition.DefaultTier or 1
	local maxTier = definition.MaxTier or tier
	local now = os.clock()

	if existing then
		local remainingDuration = math.max(0, existing.ExpiresAt - now)
		local newDuration = remainingDuration + duration
		local newTier = math.max(existing.Tier or 1, tier)

		while newDuration > 15 and newTier < maxTier do
			newDuration *= 0.5
			newTier += 1
		end

		existing.ExpiresAt = now + newDuration
		existing.Tier = newTier
		existing.NextTickAt = now + (definition.TickInterval or 1)

		if definition.Id == StatusEffectId.Bleed and newTier >= maxTier and newDuration > 15 then
			self:RemoveStatus(target, StatusEffectId.Bleed)
			return self:ApplyStatus(target, StatusEffectId.Hemorrhaged, {
				Duration = newDuration,
				Tier = 1,
				Source = params.Source,
			})
		end

		return existing
	end

	local instance = {
		Id = definition.Id,
		AppliedAt = now,
		ExpiresAt = now + duration,
		Magnitude = params.Magnitude or definition.DefaultMagnitude or 0,
		Stacks = 1,
		Tier = tier,
		Source = params.Source,
		NextTickAt = now + (definition.TickInterval or 1),
	}

	self:_insertStatusInstance(target, instance)
	return instance
end

function StatusEffectService:_insertStatusInstance(target, instance)
	local targetState = self:_getOrCreateTargetState(target)
	local bucket = targetState.ById[instance.Id]
	if not bucket then
		bucket = {}
		targetState.ById[instance.Id] = bucket
	end
	table.insert(bucket, instance)
	table.insert(targetState.List, instance)
end

function StatusEffectService:_getPrimaryStatusInstance(targetState, statusId)
	local bucket = targetState and targetState.ById[statusId]
	if not bucket or #bucket == 0 then
		return nil
	end

	return bucket[1]
end

function StatusEffectService:_runLoop()
	while true do
		self:_updateStatuses()
		task.wait(self.UpdateInterval)
	end
end

function StatusEffectService:_updateStatuses()
	local now = os.clock()

	for target, targetState in pairs(self.ActiveStatuses) do
		local changed = false

		for index = #targetState.List, 1, -1 do
			local instance = targetState.List[index]
			local definition = StatusEffectDefinitions[instance.Id]

			if definition and definition.IsDamageOverTime and now >= (instance.NextTickAt or 0) then
				self:_tickDotStatus(target, instance, definition)
				instance.NextTickAt = now + (definition.TickInterval or 1)
				changed = true
			end

			if instance.ExpiresAt <= now then
				local bucket = targetState.ById[instance.Id]
				if bucket then
					for bucketIndex = #bucket, 1, -1 do
						if bucket[bucketIndex] == instance then
							table.remove(bucket, bucketIndex)
							break
						end
					end

					if #bucket == 0 then
						targetState.ById[instance.Id] = nil
					end
				end
				table.remove(targetState.List, index)
				changed = true

				if instance.Id == StatusEffectId.Hemorrhaged then
					self:ApplyStatus(target, StatusEffectId.Broken, {
						Duration = 4,
						Source = "HemorrhagedExpire",
					})
				end
			end
		end

		if #targetState.List == 0 then
			self.ActiveStatuses[target] = nil
			changed = true
		end

		if changed then
			self:_refreshTargetGameplayState(target)
			self:_syncTarget(target)
		end
	end
end

function StatusEffectService:_tickDotStatus(target, instance, definition)
	local actor = self:_resolveTargetActor(target)
	if not actor then
		return
	end

	if instance.Id == StatusEffectId.Bleed then
		local tickDamage = 1
		if instance.Tier >= 3 then
			tickDamage *= 2
		end

		actor:ApplyDamage(tickDamage, {
			IsStatusEffect = true,
			CanFatal = false,
			MinimumHealth = 10,
			IgnoreInvincible = false,
		})
	elseif instance.Id == StatusEffectId.Poison then
		local applied = actor:ApplyDamage(1, {
			IsStatusEffect = true,
			CanFatal = false,
			MinimumHealth = 1,
			IgnoreInvincible = false,
		})
		if applied then
			self:ApplyStatus(target, StatusEffectId.Fragility, {
				Duration = 1,
				Magnitude = math.min(0.10 + ((instance.Tier - 1) * 0.05), 0.35),
				Source = "PoisonTick",
			})
		end
	elseif instance.Id == StatusEffectId.Hemorrhaged then
		actor:ApplyDamage(actor.MaxHealth * 0.01, {
			IsStatusEffect = true,
			CanFatal = true,
			IgnoreInvincible = false,
		})
	end
end

function StatusEffectService:_markTargetDirty(target)
	self:_syncTarget(target)
end

function StatusEffectService:_syncTarget(target)
	local player = self:_resolvePlayerForSync(target)
	if not player or not self.StatusEffectsChangedRemote then
		return
	end

	self.StatusEffectsChangedRemote:FireClient(player, self:GetSnapshotForPlayer(player))
end

function StatusEffectService:_refreshTargetGameplayState(target)
	local actor = self:_resolveTargetActor(target)
	if not actor then
		return
	end

	if actor.RefreshFromStatusEffects then
		actor:RefreshFromStatusEffects()
	end

	local player = self:_resolvePlayerForSync(target)
	if player and self.CombatService and (self:HasFlag(target, "Stunned") or self:HasFlag(target, "BlocksAbilities")) then
		self.CombatService:ForceStopAim(player)
	end
end

function StatusEffectService:_resolvePlayerForSync(target)
	if typeof(target) == "Instance" and target:IsA("Player") then
		return target
	elseif type(target) == "table" and target.Player then
		return target.Player
	end

	return nil
end

function StatusEffectService:_resolveTargetActor(target)
	if typeof(target) == "Instance" and target:IsA("Player") then
		return self.CharacterService:GetCharacterByPlayer(target)
	end

	return target
end

function StatusEffectService:_getOrCreateTargetState(target)
	if not self.ActiveStatuses[target] then
		self.ActiveStatuses[target] = {
			List = {},
			ById = {},
		}
	end

	return self.ActiveStatuses[target]
end

function StatusEffectService:_getTargetType(target)
	local actor = self:_resolveTargetActor(target)
	if not actor then
		return nil
	end

	if actor.Player then
		return "Remnant"
	end

	return "Entity"
end

function StatusEffectService:_statusAllowsTarget(definition, targetType)
	if not definition.AllowedTargets or not targetType then
		return true
	end

	for _, allowedTarget in ipairs(definition.AllowedTargets) do
		if allowedTarget == targetType then
			return true
		end
	end

	return false
end

function StatusEffectService:_describeTarget(target)
	if typeof(target) == "Instance" then
		return target.Name
	elseif type(target) == "table" then
		return target.DisplayName or target.Id or "TableTarget"
	end

	return "Unknown"
end

return StatusEffectService
