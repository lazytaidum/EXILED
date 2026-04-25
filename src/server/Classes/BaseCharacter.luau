local HEALTH_STATE = {
	Whole = "Whole",
	Injured = "Injured",
	Shattered = "Shattered",
	Crumbling = "Crumbling",
	Dead = "Dead",
}

local DEFAULT_MAX_SHARDS = 2
local BLEED_OUT_DURATION = 240
local DOWNED_HEALTH_FLOOR = 1
local SHATTERED_HEALTH_RATIO = 0.4
local INJURED_HEALTH_RATIO = 0.5
local RECOVERY_MAX = 100
local PASSIVE_RECOVERY_CAP = 95
local PASSIVE_RECOVERY_PER_SECOND = 1.25
local SELF_RECOVERY_PER_SECOND = 4
local ALLY_RECOVERY_PER_SECOND = 8
local RECOVERED_HEALTH_RATIO = 0.4

local BaseCharacter = {}
BaseCharacter.__index = BaseCharacter

function BaseCharacter.new(player, model, services)
	local self = setmetatable({}, BaseCharacter)
	
	self.Player = player
	self.Model = model
	self.Services = services
	self.Humanoid = model:WaitForChild("Humanoid")
	self.RootPart = model:WaitForChild("HumanoidRootPart")
	self.Humanoid.BreakJointsOnDeath = true
	
	self.IsFrozen = false
	self.DefaultWalkSpeed = self.Humanoid.WalkSpeed
	self.DefaultJumpPower = self.Humanoid.JumpPower
	self.DefaultHipHeight = self.Humanoid.HipHeight
	self.MaxHealth = self.Humanoid.MaxHealth
	self.IsInvincible = false
	self.IsSprintHeld = false
	self.IsSprinting = false
	self.IsRunning = false
	self.IsFatigued = false
	self.IsCrouching = false
	self.IsAiming = false
	
	self.SpeedMultipliers = {}
	self.SpeedModifierToken = 0
	self.SprintMultiplier = 1.5
	self.RunMultiplier = 1.25
	self.FatigueRunMultiplier = 1.1
	self.CrouchMultiplier = 0.5
	self.AimMultiplier = 0.82
	self.CrouchHipHeightMultiplier = 0.6

	self.MaxShards = DEFAULT_MAX_SHARDS
	self.Shards = self.MaxShards
	self.HealthState = HEALTH_STATE.Whole
	self.IsCrumbling = false
	self.IsDead = false
	self.RecoveryProgress = 0
	self.BleedOutDuration = BLEED_OUT_DURATION
	self.BleedOutRemaining = self.BleedOutDuration
	self.HasSelfRecoveredThisRound = false
	self.LastSurvivabilitySyncAt = 0

	self.HealthChangedConnection = self.Humanoid.HealthChanged:Connect(function()
		self.MaxHealth = self.Humanoid and self.Humanoid.MaxHealth or self.MaxHealth
		self:_syncSurvivabilityAttributes()
	end)

	self:_syncSurvivabilityAttributes()
	
	return self
end

function BaseCharacter:_getCombinedSpeedMultiplier()
	local boostMultiplier = 1
	local slowMultiplier = 1
	
	for key, value in pairs(self.SpeedMultipliers) do
		if key == "OnHitHaste" and value > 1 then
			boostMultiplier = math.max(boostMultiplier, value)
		elseif value > 1 then
			boostMultiplier *= value
		else
			slowMultiplier *= value
		end
	end
	
	if self.SpeedMultipliers.OnHitHaste then
		slowMultiplier = 1
	end
	
	return boostMultiplier * slowMultiplier
end

function BaseCharacter:_getStatusModifier(modifierName)
	local statusService = self.Services and self.Services.StatusEffectService
	if not statusService then
		return 0
	end

	return statusService:GetModifier(self.Player, modifierName)
end

function BaseCharacter:_hasStatusFlag(flagName)
	local statusService = self.Services and self.Services.StatusEffectService
	if not statusService then
		return false
	end

	return statusService:HasFlag(self.Player, flagName)
end

function BaseCharacter:_refreshMovement()
	if not self.Humanoid then
		return
	end
	
	if self.IsFrozen or self.IsCrumbling or self:_hasStatusFlag("Stunned") then
		self.Humanoid.WalkSpeed = 0
		self.Humanoid.JumpPower = 0
		self.Humanoid.HipHeight = self.DefaultHipHeight
		self.Humanoid.AutoRotate = false
		return
	end

	local movementMultiplier = self:_getCombinedSpeedMultiplier()
	if self.IsSprinting then
		movementMultiplier *= self.SprintMultiplier
	elseif self.IsRunning then
		movementMultiplier *= self.IsFatigued and self.FatigueRunMultiplier or self.RunMultiplier
	end

	if self.IsCrouching then
		movementMultiplier *= self.CrouchMultiplier
		self.Humanoid.JumpPower = 0
		self.Humanoid.HipHeight = self.DefaultHipHeight * self.CrouchHipHeightMultiplier
	else
		self.Humanoid.JumpPower = self.DefaultJumpPower
		self.Humanoid.HipHeight = self.DefaultHipHeight
	end

	if self.IsAiming then
		movementMultiplier *= self.AimMultiplier
	end

	movementMultiplier *= (1 + self:_getStatusModifier("Haste"))
	movementMultiplier *= math.max(0, 1 - self:_getStatusModifier("Hinder"))

	self.Humanoid.WalkSpeed = self.DefaultWalkSpeed * movementMultiplier
	self.Humanoid.AutoRotate = not self.IsAiming
end

function BaseCharacter:SetWalkSpeed(speed)
	if self.Humanoid then
		self.DefaultWalkSpeed = speed
		self:_refreshMovement()
	end
end

function BaseCharacter:SetJumpPower(jumpPower)
	if self.Humanoid then
		self.DefaultJumpPower = jumpPower
		self:_refreshMovement()
	end
end

function BaseCharacter:SetSpeedMultiplier(key, multiplier)
	if multiplier == nil then
		self.SpeedMultipliers[key] = nil
	else
		self.SpeedMultipliers[key] = multiplier
	end
	
	self:_refreshMovement()
end

function BaseCharacter:SetSprintHeld(state)
	state = state == true
	if self.IsSprintHeld == state then
		return
	end

	if state then
		self.IsCrouching = false
	else
		self.IsSprinting = false
		self.IsRunning = false
		self.IsFatigued = false
	end
	self.IsSprintHeld = state

	self:_refreshMovement()
end

function BaseCharacter:SetSprintMode(mode)
	mode = mode or "Walk"
	local isSprinting = mode == "Sprint"
	local isRunning = mode == "Run" or mode == "Fatigue"
	local isFatigued = mode == "Fatigue"

	if self.IsSprinting == isSprinting and self.IsRunning == isRunning and self.IsFatigued == isFatigued then
		return
	end

	self.IsSprinting = isSprinting
	self.IsRunning = isRunning
	self.IsFatigued = isFatigued
	self:_refreshMovement()
end

function BaseCharacter:SetCrouching(state)
	state = state == true
	if self.IsCrouching == state then
		return
	end

	self.IsCrouching = state
	if state then
		self.IsSprintHeld = false
		self.IsSprinting = false
		self.IsRunning = false
		self.IsFatigued = false
	end

	self:_refreshMovement()
end

function BaseCharacter:ApplyTemporarySpeedMultiplier(key, multiplier, duration)
	self.SpeedModifierToken += 1
	local token = self.SpeedModifierToken
	
	self:SetSpeedMultiplier(key, multiplier)
	
	task.delay(duration, function()
		if self.SpeedModifierToken ~= token then
			return
		end
		
		self:SetSpeedMultiplier(key, nil)
	end)
end

function BaseCharacter:Freeze()
	if not self.Humanoid or self.IsFrozen then
		return
	end
	
	self.IsFrozen = true
	self:_refreshMovement()
end

function BaseCharacter:Unfreeze()
	if not self.Humanoid or not self.IsFrozen then
		return
	end

	self.IsFrozen = false
	self:_refreshMovement()
end

function BaseCharacter:IsAlive()
	return not self.IsDead and self.Humanoid and self.Humanoid.Health > 0
end

function BaseCharacter:IsDowned()
	return self.IsCrumbling == true
end

function BaseCharacter:IsActionable()
	return self:IsAlive() and not self:IsDowned()
end

function BaseCharacter:CanBeEntityTargeted()
	return self:IsActionable()
end

function BaseCharacter:SetInvincible(state)
	if self.IsInvincible == state then
		return
	end
	
	self.IsInvincible = state
	
	if self.Humanoid then
		if state then
			self.Humanoid.Health = self.Humanoid.MaxHealth
		end
	end
end

function BaseCharacter:ApplyDamage(amount, options)
	options = options or {}
	if self.IsInvincible and not options.IgnoreInvincible then
		return false
	end

	if self.IsDead then
		return false
	end
	
	if self.Humanoid then
		if self.IsCrumbling then
			return false
		end

		local finalAmount = amount
		if not options.IsStatusEffect then
			finalAmount *= (1 + self:_getStatusModifier("Fragility"))
			finalAmount *= math.max(0, 1 - self:_getStatusModifier("Resistance"))
		end

		finalAmount = math.max(0, finalAmount)
		if finalAmount <= 0 then
			return false
		end

		local currentHealth = self.Humanoid.Health
		if finalAmount >= currentHealth and options.CanFatal ~= false then
			if self.Shards > 0 then
				self:EnterCrumbling(options.Source or "Damage")
			else
				self:Eliminate(options.Source or "NoShards")
			end
			return true
		end

		if options.CanFatal == false then
			local minimumHealth = options.MinimumHealth or 1
			finalAmount = math.min(finalAmount, math.max(0, currentHealth - minimumHealth))
			if finalAmount <= 0 then
				return false
			end
		end

		self.Humanoid.Health = math.max(DOWNED_HEALTH_FLOOR, currentHealth - finalAmount)
		self:_syncSurvivabilityAttributes()
		return true
	end
	
	return false
end

function BaseCharacter:Heal(amount, options)
	options = options or {}
	if not self.Humanoid or amount <= 0 then
		return false
	end

	if not self:IsActionable() then
		return false
	end

	local currentHealth = self.Humanoid.Health
	local maxHealth = self.Humanoid.MaxHealth
	if currentHealth >= maxHealth then
		return false
	end

	local healAmount = math.min(amount, maxHealth - currentHealth)
	if healAmount <= 0 then
		return false
	end

	self.Humanoid.Health = currentHealth + healAmount
	self:_syncSurvivabilityAttributes()
	return true
end

function BaseCharacter:ResetSurvivabilityForRound()
	self.IsDead = false
	self.IsCrumbling = false
	self.Shards = self.MaxShards
	self.RecoveryProgress = 0
	self.BleedOutRemaining = self.BleedOutDuration
	self.HasSelfRecoveredThisRound = false
	self.HealthState = HEALTH_STATE.Whole

	if self.Humanoid then
		self.Humanoid.Health = self.Humanoid.MaxHealth
	end

	self:_refreshMovement()
	self:_syncSurvivabilityAttributes()
end

function BaseCharacter:EnterCrumbling(source)
	if self.IsDead then
		return false
	end

	if self.IsCrumbling then
		return true
	end

	if self.Shards <= 0 then
		return self:Eliminate(source or "NoShards")
	end

	self.Shards -= 1
	self.IsCrumbling = true
	self.RecoveryProgress = 0
	self.BleedOutRemaining = self.BleedOutDuration
	self.HealthState = HEALTH_STATE.Crumbling

	self.IsSprintHeld = false
	self.IsSprinting = false
	self.IsRunning = false
	self.IsFatigued = false
	self.IsCrouching = false
	self.IsAiming = false
	table.clear(self.SpeedMultipliers)

	if self.Humanoid then
		self.Humanoid.Health = DOWNED_HEALTH_FLOOR
	end

	if self.Services then
		if self.Services.InteractionService then
			self.Services.InteractionService:InterruptInteraction(self.Player, "Crumbling")
		end
		if self.Services.CombatService then
			self.Services.CombatService:CancelActiveActions(self.Player)
		end
		if self.Services.StaminaService then
			self.Services.StaminaService:ResetPlayer(self.Player)
		end
		if self.Services.PlayerService then
			self.Services.PlayerService:SetMovementState(self.Player, "IsSprinting", false)
			self.Services.PlayerService:SetMovementState(self.Player, "IsCrouching", false)
			self.Services.PlayerService:SetMovementState(self.Player, "IsAiming", false)
		end
	end

	self:_refreshMovement()
	self:_syncSurvivabilityAttributes()
	return true
end

function BaseCharacter:Eliminate(_source)
	if self.IsDead then
		return false
	end

	self.IsDead = true
	self.IsCrumbling = false
	self.HealthState = HEALTH_STATE.Dead
	self.RecoveryProgress = 0
	self.BleedOutRemaining = 0
	self:_syncSurvivabilityAttributes()

	if self.Humanoid and self.Humanoid.Health > 0 then
		self.Humanoid.Health = 0
	end

	return true
end

function BaseCharacter:GetRecoveryRate(helperPlayer)
	if helperPlayer == self.Player then
		return SELF_RECOVERY_PER_SECOND
	end

	return ALLY_RECOVERY_PER_SECOND
end

function BaseCharacter:_hasAvailableRecoveryHelper()
	local services = self.Services
	local roundManager = services and services.RoundManager
	local characterService = services and services.CharacterService
	if not roundManager or not characterService then
		return false
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		if player ~= self.Player then
			local roundState = roundManager:GetRoundState(player)
			local character = characterService:GetCharacterByPlayer(player)
			if roundState and roundState.IsAlive and character and character:IsActionable() then
				return true
			end
		end
	end

	return false
end

function BaseCharacter:CanSelfRecoverFully()
	if not self.HasSelfRecoveredThisRound then
		return true
	end

	return not self:_hasAvailableRecoveryHelper()
end

function BaseCharacter:GetRecoveryCap(helperPlayer)
	if helperPlayer == self.Player and not self:CanSelfRecoverFully() then
		return PASSIVE_RECOVERY_CAP
	end

	return RECOVERY_MAX
end

function BaseCharacter:CanProgressRecovery(helperPlayer)
	if not self.IsCrumbling or self.IsDead then
		return false
	end

	local statusService = self.Services and self.Services.StatusEffectService
	if statusService and not statusService:CanBeHealed(self.Player) then
		return false
	end

	return self.RecoveryProgress < self:GetRecoveryCap(helperPlayer)
end

function BaseCharacter:ProgressRecovery(amount, helperPlayer)
	if not self:CanProgressRecovery(helperPlayer) then
		return false, false
	end

	local cap = self:GetRecoveryCap(helperPlayer)
	self.RecoveryProgress = math.clamp(self.RecoveryProgress + math.max(0, amount or 0), 0, cap)

	if self.RecoveryProgress >= RECOVERY_MAX then
		self:RecoverFromCrumbling(helperPlayer)
		return true, true
	end

	self:_syncSurvivabilityAttributes()
	return true, false
end

function BaseCharacter:RecoverFromCrumbling(helperPlayer)
	if not self.IsCrumbling or self.IsDead then
		return false
	end

	if helperPlayer == self.Player then
		self.HasSelfRecoveredThisRound = true
	end

	self.IsCrumbling = false
	self.RecoveryProgress = 0
	self.BleedOutRemaining = self.BleedOutDuration

	if self.Humanoid then
		local recoveredHealth = math.max(DOWNED_HEALTH_FLOOR + 1, self.Humanoid.MaxHealth * RECOVERED_HEALTH_RATIO)
		self.Humanoid.Health = math.min(self.Humanoid.MaxHealth, recoveredHealth)
	end

	self:_refreshMovement()
	self:_syncSurvivabilityAttributes()
	return true
end

function BaseCharacter:UpdateCrumbling(deltaTime, isReceptionActive)
	if not self.IsCrumbling or self.IsDead then
		return
	end

	if not isReceptionActive then
		self:_syncSurvivabilityAttributes()
		return
	end

	self.BleedOutRemaining = math.max(0, self.BleedOutRemaining - math.max(0, deltaTime or 0))
	if self.BleedOutRemaining <= 0 then
		self:Eliminate("BleedOut")
		return
	end

	if self.RecoveryProgress < PASSIVE_RECOVERY_CAP then
		local moveDirection = self.Humanoid and self.Humanoid.MoveDirection or Vector3.zero
		if moveDirection.Magnitude <= 0.05 then
			self.RecoveryProgress = math.min(
				PASSIVE_RECOVERY_CAP,
				self.RecoveryProgress + (PASSIVE_RECOVERY_PER_SECOND * math.max(0, deltaTime or 0))
			)
		end
	end

	self:_syncSurvivabilityAttributes()
end

function BaseCharacter:RefreshFromStatusEffects()
	self:_refreshMovement()
end

function BaseCharacter:SetAiming(state)
	state = state == true
	if self.IsCrumbling then
		state = false
	end

	if self.IsAiming == state then
		return
	end

	self.IsAiming = state
	if state then
		self.IsSprintHeld = false
		self.IsSprinting = false
		self.IsRunning = false
		self.IsFatigued = false
	end

	self:_refreshMovement()
end

function BaseCharacter:_resolveHealthState()
	if self.IsDead then
		return HEALTH_STATE.Dead
	end

	if self.IsCrumbling then
		return HEALTH_STATE.Crumbling
	end

	if not self.Humanoid then
		return HEALTH_STATE.Dead
	end

	local maxHealth = math.max(1, self.Humanoid.MaxHealth)
	local healthRatio = math.clamp(self.Humanoid.Health / maxHealth, 0, 1)
	if healthRatio >= 0.999 then
		return HEALTH_STATE.Whole
	elseif healthRatio <= SHATTERED_HEALTH_RATIO then
		return HEALTH_STATE.Shattered
	elseif healthRatio <= INJURED_HEALTH_RATIO then
		return HEALTH_STATE.Injured
	end

	return HEALTH_STATE.Injured
end

function BaseCharacter:_syncSurvivabilityAttributes()
	if not self.Model then
		return
	end

	self.HealthState = self:_resolveHealthState()
	local selfRecoveryCap = self:GetRecoveryCap(self.Player)
	self.Model:SetAttribute("RemnantHealthState", self.HealthState)
	self.Model:SetAttribute("RemnantShards", self.Shards)
	self.Model:SetAttribute("RemnantMaxShards", self.MaxShards)
	self.Model:SetAttribute("RemnantIsCrumbling", self.IsCrumbling)
	self.Model:SetAttribute("RemnantRecoveryProgress", self.RecoveryProgress)
	self.Model:SetAttribute("RemnantRecoveryMax", RECOVERY_MAX)
	self.Model:SetAttribute("RemnantSelfRecoveryCap", selfRecoveryCap)
	self.Model:SetAttribute("RemnantCanSelfRecoverFully", selfRecoveryCap >= RECOVERY_MAX)
	self.Model:SetAttribute("RemnantNeedsAllyRecovery", self.IsCrumbling and selfRecoveryCap < RECOVERY_MAX and self.RecoveryProgress >= selfRecoveryCap)
	self.Model:SetAttribute("RemnantBleedOutRemaining", self.BleedOutRemaining)
	self.Model:SetAttribute("RemnantBleedOutDuration", self.BleedOutDuration)
	self.Model:SetAttribute("RemnantHasSelfRecovered", self.HasSelfRecoveredThisRound)
end

function BaseCharacter:Destroy()
	if self.HealthChangedConnection then
		self.HealthChangedConnection:Disconnect()
		self.HealthChangedConnection = nil
	end

	self.Player = nil
	self.Model = nil
	self.Services = nil
	self.Humanoid = nil
	self.RootPart = nil
end

return BaseCharacter
