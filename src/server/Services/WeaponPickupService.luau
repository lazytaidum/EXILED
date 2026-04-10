local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local WeaponPickupService = {}
WeaponPickupService.Name = "WeaponPickupService"
WeaponPickupService.Dependencies = {
	"RemoteRegistry",
	"CombatService",
	"RoundHookService",
}

local DEFAULT_PICKUP_DURATION = 0.35
local RESTORE_HOOK_ID = "WeaponPickupService.RestorePlacedPickups"

local function _resolvePickupPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

function WeaponPickupService:Init(services)
	self.Services = services
	self.Pickups = {}
	self.PickupTemplates = {}
	self.WeaponPickupsFolder = Workspace:FindFirstChild("WeaponPickups")
end

function WeaponPickupService:Start()
	self.UiToastRemote = self.RemoteRegistry:GetRemote("UiToastRequested")
	if self.WeaponPickupsFolder then
		self:_registerExistingPickups()

		self.WeaponPickupsFolder.ChildAdded:Connect(function(instance)
			self:_registerPickup(instance)
		end)

		self.WeaponPickupsFolder.ChildRemoved:Connect(function(instance)
			self:_unregisterPickup(instance)
		end)
	end

	if self.RoundHookService then
		self.RoundHookService:RegisterHook({
			Id = RESTORE_HOOK_ID,
			Trigger = "PhaseChanged",
			Phase = GamePhase.Lobby,
			Callback = function()
				self:RestorePlacedPickups()
			end,
		})
	end

	DebugLog:Log("Combat", "[WeaponPickupService] Started")
end

function WeaponPickupService:_registerExistingPickups()
	for _, instance in ipairs(self.WeaponPickupsFolder:GetChildren()) do
		self:_registerPickup(instance)
	end
end

function WeaponPickupService:_registerPickup(instance)
	if self.Pickups[instance] then
		return
	end

	self:_cachePickupTemplate(instance)

	local weaponId = instance:GetAttribute("WeaponId") or instance.Name
	local weaponDefinition = WeaponDefinitions[weaponId]
	if not weaponDefinition then
		DebugLog:Log("Combat", string.format("[WeaponPickupService] Ignored pickup '%s': unknown weapon '%s'", instance.Name, tostring(weaponId)))
		return
	end

	local pickupPart = _resolvePickupPart(instance)
	if not pickupPart then
		DebugLog:Log("Combat", string.format("[WeaponPickupService] Ignored pickup '%s': no usable part", instance.Name))
		return
	end

	local pickupDuration = tonumber(instance:GetAttribute("PickupDuration")) or DEFAULT_PICKUP_DURATION
	local autoEquip = instance:GetAttribute("AutoEquip")
	if autoEquip == nil then
		autoEquip = true
	end

	self.Pickups[instance] = {
		Type = InteractableType.WeaponPickup,
		Id = instance:GetFullName(),
		DisplayName = instance:GetAttribute("DisplayName") or ("Pick Up " .. weaponDefinition.DisplayName),
		Instance = pickupPart,
		Model = instance,
		WeaponId = weaponId,
		Progress = 0,
		MaxProgress = 1,
		ChargeRate = pickupDuration > 0 and (1 / pickupDuration) or 1,
		IsComplete = false,
		AutoEquip = autoEquip == true,
	}

	DebugLog:Log("Combat", string.format("[WeaponPickupService] Registered pickup %s for %s", instance.Name, weaponId))
end

function WeaponPickupService:_cachePickupTemplate(instance)
	local templateId = instance:GetAttribute("PickupTemplateId")
	if not templateId or templateId == "" then
		templateId = instance:GetFullName()
		instance:SetAttribute("PickupTemplateId", templateId)
	end

	if self.PickupTemplates[templateId] then
		return
	end

	self.PickupTemplates[templateId] = {
		TemplateId = templateId,
		Name = instance.Name,
		Clone = instance:Clone(),
	}
end

function WeaponPickupService:_unregisterPickup(instance)
	self.Pickups[instance] = nil
end

function WeaponPickupService:GetAvailablePickups()
	local results = {}
	for _, pickup in pairs(self.Pickups) do
		if pickup.Instance and pickup.Instance.Parent and not pickup.IsComplete then
			table.insert(results, pickup)
		end
	end

	return results
end

function WeaponPickupService:CompletePickup(player, pickup)
	if not pickup or pickup.IsComplete then
		return false
	end

	local slotIndex = self.CombatService:GiveWeapon(player, pickup.WeaponId)
	if not slotIndex then
		return false
	end

	if pickup.AutoEquip then
		self.CombatService:HandleEquipWeapon(player, slotIndex)
	end

	pickup.IsComplete = true
	if pickup.Model and pickup.Model.Parent then
		pickup.Model:Destroy()
	end

	DebugLog:Log("Combat", string.format("[WeaponPickupService] %s picked up %s", player.Name, pickup.WeaponId))
	if self.UiToastRemote then
		self.UiToastRemote:FireClient(player, {
			Title = "Weapon Picked Up",
			Message = WeaponDefinitions[pickup.WeaponId].DisplayName,
			Tint = "Weapon",
		})
	end
	return true
end

function WeaponPickupService:RestorePlacedPickups()
	if not self.WeaponPickupsFolder then
		return
	end

	local activeTemplateIds = {}
	for _, child in ipairs(self.WeaponPickupsFolder:GetChildren()) do
		local templateId = child:GetAttribute("PickupTemplateId")
		if templateId and templateId ~= "" then
			activeTemplateIds[templateId] = true
		end
	end

	for templateId, templateData in pairs(self.PickupTemplates) do
		if not activeTemplateIds[templateId] then
			local restoredInstance = templateData.Clone:Clone()
			restoredInstance.Parent = self.WeaponPickupsFolder
			DebugLog:Log("Combat", string.format("[WeaponPickupService] Restored pickup %s", templateData.Name))
		end
	end
end

function WeaponPickupService:CreateDevPickup(weaponId, position)
	if not WeaponDefinitions[weaponId] or typeof(position) ~= "Vector3" then
		return nil
	end

	if not self.WeaponPickupsFolder then
		self.WeaponPickupsFolder = Instance.new("Folder")
		self.WeaponPickupsFolder.Name = "WeaponPickups"
		self.WeaponPickupsFolder.Parent = Workspace
	end

	local instance = Instance.new("Part")
	instance.Name = weaponId
	instance.Size = Vector3.new(2, 2, 2)
	instance.Shape = Enum.PartType.Ball
	instance.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Material = Enum.Material.Neon
	instance.Color = Color3.fromRGB(0, 109, 163)
	instance:SetAttribute("WeaponId", weaponId)
	instance:SetAttribute("DisplayName", "Pick Up " .. (WeaponDefinitions[weaponId].DisplayName or weaponId))
	instance:SetAttribute("PickupDuration", DEFAULT_PICKUP_DURATION)
	instance:SetAttribute("AutoEquip", true)
	instance.Parent = self.WeaponPickupsFolder
	return instance
end

return WeaponPickupService
