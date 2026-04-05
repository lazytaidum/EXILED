local BaseEntity = {}
BaseEntity.__index = BaseEntity

function BaseEntity.new(model, definition)
	local self = setmetatable({}, BaseEntity)
	
	self.Model = model
	self.Definition = definition or {}
	self.RootPart = model.PrimaryPart or model:WaitForChild("HumanoidRootPart")
	
	self.Id = self.Definition.Id or model.Name
	self.DisplayName = self.Definition.DisplayName or model.Name
	self.StarRating = self.Definition.StarRation or 1
	self.Weight = self.Definition.Weight or self.StarRating
	
	self.Attributes = self.Definition.Attributes or {}
	
	local stats = self.Definition.Stats or {}
	
	self.IsActive = false
	self.Damage = stats.Damage or 10
	self.AttackRange = stats.AttackRange or 10
	self.AttackInterval = stats.AttackInterval or 1.5
	self.MoveSpeed = stats.MoveSpeed or 10
	
	self.LastAttackTime = 0
	self.TargetPlayer = nil
	
	self.SpawnCFrame = self.RootPart.CFrame
	
	return self
end

function BaseEntity:SetActive(state)
	self.IsActive = state
	
	if not state then
		self.TargetPlayer = nil
	end
end

function BaseEntity:HasAttribute(attributeName)
	for _, value in ipairs(self.Attributes) do
		if value == attributeName then
			return true
		end
	end
	
	return false
end

function BaseEntity:CanAttack()
	return os.clock() - self.LastAttackTime >= self.AttackInterval
end

function BaseEntity:MarkAttack()
	self.LastAttackTime = os.clock()
end

function BaseEntity:GetPosition()
	if self.RootPart then
		return self.RootPart.Position
	end
	
	return nil
end

function BaseEntity:SetTarget(player)
	self.TargetPlayer = player
end

function BaseEntity:GetTarget()
	return self.TargetPlayer
end

function BaseEntity:MoveToward(position, deltaTime)
	if not self.RootPart or not position then
		return
	end
	
	local currentPosition = self.RootPart.Position
	local offset = position - currentPosition
	local distance = offset.Magnitude
	
	if distance <= 0.01 then
		return
	end
	
	local stopDistance = math.max(self.AttackRange * 0.5, 2)
	if distance <= stopDistance then
		return
	end
	
	local direction = offset.Unit
	local moveStep = math.min(distance - stopDistance, self.MoveSpeed * deltaTime)
	if moveStep <= 0 then
		return
	end
	
	local nextPosition = currentPosition + direction * moveStep
	
	self.RootPart.CFrame = CFrame.new(nextPosition, position)
end

function BaseEntity:ResetToSpawn()
	if self.RootPart then
		self.RootPart.CFrame = self.SpawnCFrame
	end
	
	self.TargetPlayer = nil
	self.LastAttackTime = 0
end

function BaseEntity:Destroy()
	self.Model = nil
	self.Definition = nil
	self.RootPart = nil
	self.TargetPlayer = nil
end

return BaseEntity
