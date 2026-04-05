local BaseObjective = {}
BaseObjective.__index = BaseObjective

function BaseObjective.new(instance, definition)
	local self = setmetatable({}, BaseObjective)
	
	self.Instance = instance
	self.Definition = definition or {}
	
	self.Id = self.Definition.Id or instance.Name
	self.DisplayName = self.Definition.DisplayName or instance.Name
	self.Type = self.Definition.Type or "Unknown"
	self.Phase = self.Definition.Phase or "None"
	self.Shared = self.Definition.Shared == true
	self.StartsEnabled = self.Definition.StartsEnabled == true
	self.MaxProgress = self.Definition.MaxProgress or 1
	self.ChargeRate = self.Definition.ChargeRate or 1
	
	self.Progress = 0
	self.IsComplete = false
	self.IsEnabled = self.StartsEnabled
	
	return self
end

function BaseObjective:SetEnabled(state)
	self.IsEnabled = state
end

function BaseObjective:CanInteract()
	return self.IsEnabled and not self.IsComplete
end

function BaseObjective:AddProgress(amount)
	if not self:CanInteract() then
		return false
	end
	
	self.Progress += amount
	
	if self.Progress >= self.MaxProgress then
		self.Progress = self.MaxProgress
		self.IsComplete = true
	end
	
	return true
end

function BaseObjective:GetProgressAlpha()
	if self.MaxProgress <= 0 then
		return 0
	end
	
	return self.Progress / self.MaxProgress
end

function BaseObjective:Destroy()
	self.Instance = nil
	self.Definition = nil
end

return BaseObjective
