local BaseCharacter = {}
BaseCharacter.__index = BaseCharacter

function BaseCharacter.new(player, model)
	local self = setmetatable({}, BaseCharacter)
	
	self.Player = player
	self.Model = model
	self.Humanoid = model:WaitForChild("Humanoid")
	self.RootPart = model:WaitForChild("HumanoidRootPart")
	
	self.IsFrozen = false
	self.DefaultWalkSpeed = self.Humanoid.WalkSpeed
	self.DefaultJumpPower = self.Humanoid.JumpPower
	self.IsInvincible = false
	
	self.SpeedMultiplier = 1
	self.SpeedModifierToken = 0
	
	return self
end

function BaseCharacter:_refreshMovement()
	if not self.Humanoid then
		return
	end
	
	if self.IsFrozen then
		self.Humanoid.WalkSpeed = 0
		self.Humanoid.JumpPower = 0
		self.Humanoid.AutoRotate = false
		return
	end
	
	self.Humanoid.WalkSpeed = self.DefaultWalkSpeed * self.SpeedMultiplier
	self.Humanoid.JumpPower = self.DefaultJumpPower
	self.Humanoid.AutoRotate = true
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

function BaseCharacter:SetSpeedMultiplier(multiplier)
	self.SpeedMultiplier = multiplier or 1
	self:_refreshMovement()
end

function BaseCharacter:ApplyTemporarySpeedMultiplier(multiplier, duration)
	self.SpeedModifierToken += 1
	local token = self.SpeedModifierToken
	
	self:SetSpeedMultiplier(multiplier)
	
	task.delay(duration, function()
		if self.SpeedModifierToken ~= token then
			return
		end
		
		self:SetSpeedMultiplier(1)
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

function BaseCharacter:ApplyDamage(amount)
	if self.IsInvincible then
		return false
	end
	
	if self.Humanoid then
		self.Humanoid:TakeDamage(amount)
		return true
	end

	return false
end

function BaseCharacter:Destroy()
	self.Player = nil
	self.Model = nil
	self.Humanoid = nil
	self.RootPart = nil
end

return BaseCharacter
