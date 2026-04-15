local BaseCharacter = {}
BaseCharacter.__index = BaseCharacter

function BaseCharacter.new(player, model, services)
	local self = setmetatable({}, BaseCharacter)
	
	self.Player = player
	self.Model = model
	self.Services = services
	self.Humanoid = model:WaitForChild("Humanoid")
	self.RootPart = model:WaitForChild("HumanoidRootPart")
	
	self.IsFrozen = false
	self.DefaultWalkSpeed = self.Humanoid.WalkSpeed
	self.DefaultJumpPower = self.Humanoid.JumpPower
	self.DefaultHipHeight = self.Humanoid.HipHeight
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
	
	if self.IsFrozen or self:_hasStatusFlag("Stunned") then
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
	return self.Humanoid and self.Humanoid.Health > 0
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
	
	if self.Humanoid then
		local finalAmount = amount
		if not options.IsStatusEffect then
			finalAmount *= (1 + self:_getStatusModifier("Fragility"))
			finalAmount *= math.max(0, 1 - self:_getStatusModifier("Resistance"))
		end

		finalAmount = math.max(0, finalAmount)
		if finalAmount <= 0 then
			return false
		end

		if options.CanFatal == false then
			local minimumHealth = options.MinimumHealth or 1
			finalAmount = math.min(finalAmount, math.max(0, self.Humanoid.Health - minimumHealth))
			if finalAmount <= 0 then
				return false
			end
		end

		self.Humanoid:TakeDamage(finalAmount)
		return true
	end
	
	return false
end

function BaseCharacter:Heal(amount, options)
	options = options or {}
	if not self.Humanoid or amount <= 0 then
		return false
	end

	if not self:IsAlive() then
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
	return true
end

function BaseCharacter:RefreshFromStatusEffects()
	self:_refreshMovement()
end

function BaseCharacter:SetAiming(state)
	state = state == true
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

function BaseCharacter:Destroy()
	self.Player = nil
	self.Model = nil
	self.Services = nil
	self.Humanoid = nil
	self.RootPart = nil
end

return BaseCharacter
