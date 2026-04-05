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
	
	return self
end

function BaseCharacter:SetWalkSpeed(speed)
	if self.Humanoid then
		self.Humanoid.WalkSpeed = speed
	end
end

function BaseCharacter:SetJumpPower(jumpPower)
	if self.Humanoid then
		self.Humanoid.JumpPower = jumpPower
	end
end

function BaseCharacter:Freeze()
	if not self.Humanoid or self.IsFrozen then
		return
	end
	
	self.IsFrozen = true
	self.Humanoid.WalkSpeed = 0
	self.Humanoid.JumpPower = 0
	self.Humanoid.AutoRotate = false
end

function BaseCharacter:Unfreeze()
	if not self.Humanoid or not self.IsFrozen then
		return
	end

	self.IsFrozen = false
	self.Humanoid.WalkSpeed = self.DefaultWalkSpeed
	self.Humanoid.JumpPower = self.DefaultJumpPower
	self.Humanoid.AutoRotate = true
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
		return
	end
	
	if self.Humanoid then
		self.Humanoid:TakeDamage(amount)
	end
end

function BaseCharacter:Destroy()
	self.Player = nil
	self.Model = nil
	self.Humanoid = nil
	self.RootPart = nil
end

return BaseCharacter
