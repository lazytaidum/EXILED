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
	self.Completion = self.Definition.Completion or {}
	
	self.Progress = 0
	self.LastLoggedProgressStep = -1
	self.IsComplete = false
	self.IsEnabled = self.StartsEnabled

	self:_syncDebugAttributes()
	
	return self
end

function BaseObjective:SetEnabled(state)
	self.IsEnabled = state
	self:_syncDebugAttributes()
end

function BaseObjective:Reset()
	self.Progress = 0
	self.LastLoggedProgressStep = -1
	self.IsComplete = false
	self.IsEnabled = self.StartsEnabled
	self:_syncDebugAttributes()
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

	self:_syncDebugAttributes()
	
	return true
end

function BaseObjective:GetPosition()
	if not self.Instance then
		return nil
	end

	if self.Instance:IsA("BasePart") then
		return self.Instance.Position
	end

	if self.Instance:IsA("Model") then
		local primaryPart = self.Instance.PrimaryPart or self.Instance:FindFirstChildWhichIsA("BasePart", true)
		return primaryPart and primaryPart.Position or nil
	end

	return nil
end

function BaseObjective:GetProgressAlpha()
	if self.MaxProgress <= 0 then
		return 0
	end
	
	return self.Progress / self.MaxProgress
end

function BaseObjective:_syncDebugAttributes()
	if not self.Instance then
		return
	end

	self.Instance:SetAttribute("ObjectiveId", self.Id)
	self.Instance:SetAttribute("ObjectiveType", self.Type)
	self.Instance:SetAttribute("ObjectivePhase", self.Phase)
	self.Instance:SetAttribute("ObjectiveEnabled", self.IsEnabled)
	self.Instance:SetAttribute("ObjectiveComplete", self.IsComplete)
	self.Instance:SetAttribute("ObjectiveProgress", self.Progress)
	self.Instance:SetAttribute("ObjectiveMaxProgress", self.MaxProgress)
	self.Instance:SetAttribute("ObjectiveProgressAlpha", self:GetProgressAlpha())
end

function BaseObjective:Destroy()
	self.Instance = nil
	self.Definition = nil
end

return BaseObjective
