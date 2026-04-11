local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StaminaService = {}
StaminaService.Name = "StaminaService"
StaminaService.Dependencies = {
	"RemoteRegistry",
	"RoundManager",
	"CharacterService",
	"PlayerService",
}

function StaminaService:Init(services)
	self.Services = services
	self.States = {}
	self.UpdateInterval = 0.1
	self.MaxStamina = 100
	self.SprintDrainPerSecond = 16
	self.BaseRegenPerSecond = 10
	self.RegenDelay = 1.2
	self.RunDurationBeforeFatigue = 6
end

function StaminaService:_isMovementPhaseActive(character)
	local roundManager = self.RoundManager
	if not roundManager or not character or not character:IsAlive() then
		return false
	end

	local phase = roundManager:GetCurrentPhase()
	return phase == GamePhase.Preparation or phase == GamePhase.Reception
end

function StaminaService:_resolveMovementState(character, state)
	if not character or not character.IsSprintHeld then
		state.ZeroStaminaAt = nil
		return "Walk"
	end

	if state.Current > 0.5 then
		state.ZeroStaminaAt = nil
		return "Sprint"
	end

	if not state.ZeroStaminaAt then
		state.ZeroStaminaAt = os.clock()
	end

	local isFatigued = (os.clock() - state.ZeroStaminaAt) >= self.RunDurationBeforeFatigue
	return isFatigued and "Fatigue" or "Run"
end

function StaminaService:Start()
	self.Remote = self.RemoteRegistry:GetRemote(RemoteNames.StaminaStateChanged)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_ensureState(player)
		self:_pushState(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_ensureState(player)
		self:_pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.States[player] = nil
	end)

	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Movement", "[StaminaService] Started")
end

function StaminaService:_runLoop()
	while true do
		self:_updateStamina()
		task.wait(self.UpdateInterval)
	end
end

function StaminaService:_ensureState(player)
	local state = self.States[player]
	if state then
		return state
	end

	state = {
		Current = self.MaxStamina,
		Max = self.MaxStamina,
		LastDrainAt = 0,
		MovementState = "Walk",
		ZeroStaminaAt = nil,
	}
	self.States[player] = state
	return state
end

function StaminaService:_updateStamina()
	for player, state in pairs(self.States) do
		local character = self.CharacterService:GetCharacterByPlayer(player)
		local isActive = self:_isMovementPhaseActive(character)
		if not isActive then
			local changed = false
			if state.Current < state.Max then
				state.Current = state.Max
				changed = true
			end
			if character then
				character:SetSprintHeld(false)
			end
			changed = self:_setMovementState(character, state, "Walk") or changed
			state.ZeroStaminaAt = nil
			if changed then
				self:_pushState(player)
			end
			continue
		end

		local changed = false
		if character.IsSprintHeld then
			state.LastDrainAt = os.clock()
			if state.Current > 0.5 then
				changed = self:_setMovementState(character, state, self:_resolveMovementState(character, state)) or changed
				changed = self:_drainInternal(player, state, self.SprintDrainPerSecond * self.UpdateInterval) or changed
			else
				changed = self:_setMovementState(character, state, self:_resolveMovementState(character, state)) or changed
			end
		else
			state.ZeroStaminaAt = nil
			changed = self:_setMovementState(character, state, "Walk") or changed
			if (os.clock() - state.LastDrainAt) >= self.RegenDelay then
				local regenRate = self.BaseRegenPerSecond
				changed = self:_restoreInternal(player, state, regenRate * self.UpdateInterval) or changed
			end
		end

		if changed then
			self:_pushState(player)
		end
	end
end

function StaminaService:_setMovementState(character, state, movementState)
	movementState = movementState or "Walk"
	if state.MovementState == movementState then
		return false
	end

	state.MovementState = movementState
	if character then
		character:SetSprintMode(movementState)
	end
	return true
end

function StaminaService:_drainInternal(_player, state, amount)
	if amount <= 0 then
		return false
	end

	local newValue = math.max(0, state.Current - amount)
	if newValue == state.Current then
		return false
	end

	state.Current = newValue
	state.LastDrainAt = os.clock()
	return true
end

function StaminaService:_restoreInternal(_player, state, amount)
	if amount <= 0 then
		return false
	end

	local newValue = math.min(state.Max, state.Current + amount)
	if newValue == state.Current then
		return false
	end

	state.Current = newValue
	return true
end

function StaminaService:DrainStamina(player, amount, reason)
	local state = self:_ensureState(player)
	local changed = self:_drainInternal(player, state, amount or 0)
	if changed then
		self:_pushState(player)
		DebugLog:Log("Movement", string.format("[StaminaService] Drained %s by %.2f (%s)", player.Name, amount or 0, tostring(reason or "Unknown")))
	end
	return changed
end

function StaminaService:GetCurrentStamina(player)
	local state = self:_ensureState(player)
	return state.Current, state.Max
end

function StaminaService:HasSprintStamina(player)
	local state = self:_ensureState(player)
	return state.Current > 0.5
end

function StaminaService:ResetPlayer(player)
	local state = self:_ensureState(player)
	state.Current = state.Max
	state.LastDrainAt = 0
	local character = self.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetSprintHeld(false)
	end
	self:_setMovementState(character, state, "Walk")
	state.ZeroStaminaAt = nil
	self:_pushState(player)
end

function StaminaService:RefreshPlayer(player)
	local state = self:_ensureState(player)
	local character = self.CharacterService:GetCharacterByPlayer(player)
	local movementState = self:_isMovementPhaseActive(character) and self:_resolveMovementState(character, state) or "Walk"
	self:_setMovementState(character, state, movementState)
	self:_pushState(player)
	return state.Current, state.Max
end

function StaminaService:_pushState(player)
	if not self.Remote then
		return
	end

	local state = self:_ensureState(player)
	self.Remote:FireClient(player, {
		Current = state.Current,
		Max = state.Max,
		MovementState = state.MovementState or "Walk",
		RunDurationBeforeFatigue = self.RunDurationBeforeFatigue,
	})
end

return StaminaService
