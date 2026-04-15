local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EnvironmentalHazardService = {}
EnvironmentalHazardService.Name = "EnvironmentalHazardService"
EnvironmentalHazardService.Dependencies = {
	"RemoteRegistry",
	"EntityService",
	"StatusEffectService",
	"RoundHookService",
}

local DEFAULT_TRIGGER_DURATION = 0.45
local DEFAULT_STUN_DURATION = 2.5
local DEFAULT_EFFECT_RADIUS = 10
local DEFAULT_INTERACT_RANGE = 12
local RESTORE_HOOK_ID = "EnvironmentalHazardService.RestorePlacedHazards"

local function _resolveHazardPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

function EnvironmentalHazardService:Init(services)
	self.Services = services
	self.Hazards = {}
	self.HazardTemplates = {}
	self.HazardsFolder = Workspace:FindFirstChild("EnvironmentalHazards")
	if not self.HazardsFolder then
		self.HazardsFolder = Instance.new("Folder")
		self.HazardsFolder.Name = "EnvironmentalHazards"
		self.HazardsFolder.Parent = Workspace
	end
end

function EnvironmentalHazardService:Start()
	self.UiToastRemote = self.RemoteRegistry:GetRemote("UiToastRequested")

	if self.HazardsFolder then
		self:_registerExistingHazards()

		self.HazardsFolder.ChildAdded:Connect(function(instance)
			self:_registerHazard(instance)
		end)

		self.HazardsFolder.ChildRemoved:Connect(function(instance)
			self:_unregisterHazard(instance)
		end)
	end

	if self.RoundHookService then
		self.RoundHookService:RegisterHook({
			Id = RESTORE_HOOK_ID,
			Trigger = "PhaseChanged",
			Phase = GamePhase.Lobby,
			Callback = function()
				self:RestorePlacedHazards()
			end,
		})
	end

	DebugLog:Log("Interaction", "[EnvironmentalHazardService] Started")
end

function EnvironmentalHazardService:_registerExistingHazards()
	for _, instance in ipairs(self.HazardsFolder:GetChildren()) do
		self:_registerHazard(instance)
	end
end

function EnvironmentalHazardService:_registerHazard(instance)
	if self.Hazards[instance] then
		return
	end

	self:_cacheHazardTemplate(instance)

	local hazardPart = _resolveHazardPart(instance)
	if not hazardPart then
		DebugLog:Log("Interaction", string.format("[EnvironmentalHazardService] Ignored hazard '%s': no usable part", instance.Name))
		return
	end

	local triggerDuration = tonumber(instance:GetAttribute("TriggerDuration")) or DEFAULT_TRIGGER_DURATION
	local effectRadius = tonumber(instance:GetAttribute("EffectRadius")) or DEFAULT_EFFECT_RADIUS
	local stunDuration = tonumber(instance:GetAttribute("StunDuration")) or DEFAULT_STUN_DURATION
	local singleUse = instance:GetAttribute("SingleUse")
	if singleUse == nil then
		singleUse = true
	end

	local displayName = instance:GetAttribute("DisplayName")
	if not displayName or displayName == "" then
		displayName = "Trigger Hazard"
	end

	local hazard = {
		Type = InteractableType.EnvironmentalHazard,
		Id = instance:GetFullName(),
		HazardType = instance:GetAttribute("HazardType") or "DropLog",
		DisplayName = displayName,
		Instance = hazardPart,
		Model = instance,
		Progress = 0,
		MaxProgress = 1,
		ChargeRate = triggerDuration > 0 and (1 / triggerDuration) or 1,
		EffectRadius = effectRadius,
		StunDuration = stunDuration,
		SingleUse = singleUse == true,
		IsComplete = false,
		IsSpent = instance:GetAttribute("Spent") == true,
	}

	self.Hazards[instance] = hazard
	self:_applyHazardVisualState(hazard)

	DebugLog:Log("Interaction", string.format("[EnvironmentalHazardService] Registered hazard %s (%s)", instance.Name, hazard.HazardType))
end

function EnvironmentalHazardService:_cacheHazardTemplate(instance)
	local templateId = instance:GetAttribute("HazardTemplateId")
	if not templateId or templateId == "" then
		templateId = instance:GetFullName()
		instance:SetAttribute("HazardTemplateId", templateId)
	end

	if self.HazardTemplates[templateId] then
		return
	end

	self.HazardTemplates[templateId] = {
		TemplateId = templateId,
		Name = instance.Name,
		Clone = instance:Clone(),
	}
end

function EnvironmentalHazardService:_unregisterHazard(instance)
	self.Hazards[instance] = nil
end

function EnvironmentalHazardService:GetAvailableHazards()
	local results = {}
	for _, hazard in pairs(self.Hazards) do
		if hazard.Instance and hazard.Instance.Parent and not hazard.IsSpent and not hazard.IsComplete then
			table.insert(results, hazard)
		end
	end

	return results
end

function EnvironmentalHazardService:GetNearestAvailableHazard(player, maxDistance)
	if not player or not self.EntityService then
		return nil
	end

	local character = self.Services.CharacterService and self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		return nil
	end

	local playerPosition = character.RootPart.Position
	local bestHazard = nil
	local bestDistance = maxDistance or DEFAULT_INTERACT_RANGE

	for _, hazard in ipairs(self:GetAvailableHazards()) do
		local hazardInstance = hazard.Instance
		if hazardInstance then
			local distance = (hazardInstance.Position - playerPosition).Magnitude
			if distance <= bestDistance then
				bestHazard = hazard
				bestDistance = distance
			end
		end
	end

	return bestHazard
end

function EnvironmentalHazardService:TriggerNearestHazard(player, maxDistance)
	local hazard = self:GetNearestAvailableHazard(player, maxDistance)
	if not hazard then
		return false
	end

	return self:CompleteHazard(player, hazard)
end

function EnvironmentalHazardService:CompleteHazard(player, hazard)
	if not hazard or hazard.IsSpent or hazard.IsComplete then
		return false
	end

	hazard.IsComplete = true
	self:_playTriggerVisual(hazard)
	local hitCount = self:_triggerHazard(hazard)
	hazard.IsSpent = hazard.SingleUse
	hazard.Progress = hazard.MaxProgress
	self:_applyHazardVisualState(hazard)
	hazard.IsComplete = false

	if self.UiToastRemote then
		self.UiToastRemote:FireClient(player, {
			Title = "Hazard Triggered",
			Message = hitCount > 0 and string.format("%s stunned %d", hazard.DisplayName, hitCount) or (hazard.DisplayName .. " triggered"),
			Tint = "Ability",
		})
	end

	DebugLog:Log("Interaction", string.format("[EnvironmentalHazardService] %s triggered %s (%d hits)", player.Name, hazard.DisplayName, hitCount))
	return true
end

function EnvironmentalHazardService:_playTriggerVisual(hazard)
	if not hazard or not hazard.Instance then
		return
	end

	local origin = hazard.Instance.Position
	local radius = math.max(2, hazard.EffectRadius or DEFAULT_EFFECT_RADIUS)

	local burst = Instance.new("Part")
	burst.Name = "HazardTriggerBurst"
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.CastShadow = false
	burst.Shape = Enum.PartType.Ball
	burst.Material = Enum.Material.Neon
	burst.Color = Color3.fromRGB(255, 184, 104)
	burst.Transparency = 0.2
	burst.Size = Vector3.new(1, 1, 1)
	burst.Position = origin
	burst.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "HazardTriggerRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 212, 103)
	ring.Transparency = 0.12
	ring.Size = Vector3.new(0.35, 0.35, 0.35)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = burst

	local pulse = Instance.new("PointLight")
	pulse.Color = Color3.fromRGB(255, 202, 140)
	pulse.Range = radius * 1.35
	pulse.Brightness = 2.8
	pulse.Parent = burst

	task.spawn(function()
		local duration = 0.2
		local startTime = os.clock()
		while true do
			local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
			burst.Size = Vector3.new(1, 1, 1):Lerp(Vector3.new(radius * 1.4, radius * 1.4, radius * 1.4), alpha)
			burst.Transparency = 0.2 + (alpha * 0.8)
			ring.Size = Vector3.new(radius * 0.3, radius * 2, radius * 2)
			ring.Transparency = 0.12 + (alpha * 0.88)
			pulse.Brightness = 2.8 * (1 - alpha)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
	end)

	Debris:AddItem(burst, 0.25)
	Debris:AddItem(ring, 0.25)
end

function EnvironmentalHazardService:_triggerHazard(hazard)
	if not hazard or not hazard.Instance then
		return 0
	end

	local hitCount = 0
	local origin = hazard.Instance.Position
	for _, entity in ipairs(self.EntityService and self.EntityService.Entities or {}) do
		if entity.IsActive and entity.RootPart and entity.Health > 0 then
			local distance = (entity.RootPart.Position - origin).Magnitude
			if distance <= hazard.EffectRadius then
				self.StatusEffectService:ApplyStatus(entity, StatusEffectId.Stunned, {
					Duration = hazard.StunDuration,
					Source = hazard.HazardType or "EnvironmentalHazard",
					InterruptAbilities = true,
				})
				hitCount += 1
			end
		end
	end

	return hitCount
end

function EnvironmentalHazardService:_applyHazardVisualState(hazard)
	if not hazard or not hazard.Model then
		return
	end

	hazard.Model:SetAttribute("Spent", hazard.IsSpent == true)

	for _, descendant in ipairs(hazard.Model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if not descendant:GetAttribute("HazardOriginalColorStored") then
				descendant:SetAttribute("HazardOriginalColorStored", true)
				descendant:SetAttribute("HazardOriginalColorR", descendant.Color.R)
				descendant:SetAttribute("HazardOriginalColorG", descendant.Color.G)
				descendant:SetAttribute("HazardOriginalColorB", descendant.Color.B)
				descendant:SetAttribute("HazardOriginalMaterial", descendant.Material.Name)
			end

			if hazard.IsSpent then
				descendant.Color = Color3.fromRGB(88, 88, 94)
				descendant.Material = Enum.Material.SmoothPlastic
			else
				local originalColor = Color3.new(
					descendant:GetAttribute("HazardOriginalColorR") or descendant.Color.R,
					descendant:GetAttribute("HazardOriginalColorG") or descendant.Color.G,
					descendant:GetAttribute("HazardOriginalColorB") or descendant.Color.B
				)
				local originalMaterialName = descendant:GetAttribute("HazardOriginalMaterial")
				descendant.Color = originalColor
				if originalMaterialName and Enum.Material[originalMaterialName] then
					descendant.Material = Enum.Material[originalMaterialName]
				end
			end
		end
	end
end

function EnvironmentalHazardService:RestorePlacedHazards()
	if not self.HazardsFolder then
		return
	end

	local activeTemplateIds = {}
	for _, child in ipairs(self.HazardsFolder:GetChildren()) do
		local templateId = child:GetAttribute("HazardTemplateId")
		if templateId and templateId ~= "" then
			activeTemplateIds[templateId] = true
		end
	end

	for templateId, templateData in pairs(self.HazardTemplates) do
		if not activeTemplateIds[templateId] then
			local restoredInstance = templateData.Clone:Clone()
			restoredInstance:SetAttribute("Spent", false)
			restoredInstance.Parent = self.HazardsFolder
		end
	end

	for _, hazard in pairs(self.Hazards) do
		hazard.IsSpent = false
		hazard.IsComplete = false
		hazard.Progress = 0
		self:_applyHazardVisualState(hazard)
	end
end

return EnvironmentalHazardService
