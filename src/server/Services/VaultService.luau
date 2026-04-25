local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local VaultService = {}
VaultService.Name = "VaultService"
VaultService.Dependencies = {
	"CharacterService",
	"StatusEffectService",
}

local DEFAULT_INTERACT_RANGE = 8
local DEFAULT_VAULT_DURATION = 0.42
local DEFAULT_FAST_VAULT_DURATION = 0.32
local DEFAULT_VAULT_CLEARANCE = 3.35
local DEFAULT_VAULT_ARC_HEIGHT = 1.35
local DEFAULT_VAULT_COOLDOWN = 0.3
local DEFAULT_FACING_DOT = 0.08

local function _resolveVaultPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function _getPlanarUnit(vector)
	local planar = Vector3.new(vector.X, 0, vector.Z)
	if planar.Magnitude <= 0.001 then
		return nil
	end

	return planar.Unit
end

local function _easeInOut(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - (2 * alpha))
end

local function _quadraticBezier(a, b, c, alpha)
	local inverse = 1 - alpha
	return (a * inverse * inverse) + (b * 2 * inverse * alpha) + (c * alpha * alpha)
end

local function _readBooleanAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)
	if value == nil then
		return defaultValue
	end

	return value == true
end

function VaultService:Init(services)
	self.Services = services
	self.Vaults = {}
	self.ActiveVaultsByPlayer = {}
	self.PlayerCooldowns = {}
	self.VaultsFolder = self:_resolveVaultsFolder()
end

function VaultService:Start()
	self:_registerExistingVaults()

	if self.VaultsFolder then
		self.VaultsFolder.ChildAdded:Connect(function(instance)
			self:_registerVault(instance)
		end)

		self.VaultsFolder.ChildRemoved:Connect(function(instance)
			self:_unregisterVault(instance)
		end)
	end

	DebugLog:Log("Interaction", "[VaultService] Started")
end

function VaultService:_resolveVaultsFolder()
	local interactablesFolder = Workspace:FindFirstChild("Interactables")
	local nestedVaultsFolder = interactablesFolder and interactablesFolder:FindFirstChild("Vaults")
	if nestedVaultsFolder and nestedVaultsFolder:IsA("Folder") then
		return nestedVaultsFolder
	end

	local directVaultsFolder = Workspace:FindFirstChild("Vaults")
	if directVaultsFolder and directVaultsFolder:IsA("Folder") then
		return directVaultsFolder
	end

	if not interactablesFolder then
		interactablesFolder = Instance.new("Folder")
		interactablesFolder.Name = "Interactables"
		interactablesFolder.Parent = Workspace
	end

	local vaultsFolder = Instance.new("Folder")
	vaultsFolder.Name = "Vaults"
	vaultsFolder.Parent = interactablesFolder
	return vaultsFolder
end

function VaultService:_registerExistingVaults()
	if not self.VaultsFolder then
		return
	end

	for _, instance in ipairs(self.VaultsFolder:GetChildren()) do
		self:_registerVault(instance)
	end
end

function VaultService:_registerVault(instance)
	if self.Vaults[instance] then
		return
	end

	local vaultPart = _resolveVaultPart(instance)
	if not vaultPart then
		DebugLog:Log("Interaction", string.format("[VaultService] Ignored vault '%s': no usable part", instance.Name))
		return
	end

	local duration = tonumber(instance:GetAttribute("VaultDuration")) or DEFAULT_VAULT_DURATION
	local fastDuration = tonumber(instance:GetAttribute("FastVaultDuration")) or DEFAULT_FAST_VAULT_DURATION
	local interactRange = tonumber(instance:GetAttribute("InteractRange")) or DEFAULT_INTERACT_RANGE
	local clearance = tonumber(instance:GetAttribute("VaultClearance")) or DEFAULT_VAULT_CLEARANCE
	local arcHeight = tonumber(instance:GetAttribute("VaultArcHeight")) or DEFAULT_VAULT_ARC_HEIGHT
	local cooldown = tonumber(instance:GetAttribute("Cooldown")) or DEFAULT_VAULT_COOLDOWN
	local displayName = instance:GetAttribute("DisplayName")
	if not displayName or displayName == "" then
		displayName = "Vault"
	end

	local vault = {
		Type = InteractableType.Vault,
		Id = instance:GetFullName(),
		DisplayName = displayName,
		Instance = vaultPart,
		Model = instance,
		Progress = 0,
		MaxProgress = 1,
		ChargeRate = 1,
		Duration = math.clamp(duration, 0.12, 1.25),
		FastDuration = math.clamp(fastDuration, 0.12, 1.25),
		InteractRange = math.max(2, interactRange),
		Clearance = math.max(1.5, clearance),
		ArcHeight = math.max(0, arcHeight),
		Cooldown = math.max(0, cooldown),
		Axis = tostring(instance:GetAttribute("VaultAxis") or "Look"),
		RequireFacing = _readBooleanAttribute(instance, "RequireFacing", true),
		FacingDot = tonumber(instance:GetAttribute("FacingDot")) or DEFAULT_FACING_DOT,
		IsComplete = false,
	}

	self.Vaults[instance] = vault
	self:_applyVaultAttributes(vault)

	DebugLog:Log("Interaction", string.format("[VaultService] Registered vault %s", instance.Name))
end

function VaultService:_unregisterVault(instance)
	self.Vaults[instance] = nil
end

function VaultService:_applyVaultAttributes(vault)
	if not vault or not vault.Model then
		return
	end

	vault.Model:SetAttribute("InteractableType", InteractableType.Vault)
	vault.Model:SetAttribute("VaultRegistered", true)
	if vault.Instance and vault.Instance ~= vault.Model then
		vault.Instance:SetAttribute("InteractableType", InteractableType.Vault)
		vault.Instance:SetAttribute("VaultRegistered", true)
	end
end

function VaultService:GetAvailableVaults()
	local results = {}
	for _, vault in pairs(self.Vaults) do
		local model = vault.Model
		if vault.Instance and vault.Instance.Parent and model and model.Parent and model:GetAttribute("Disabled") ~= true then
			table.insert(results, vault)
		end
	end

	return results
end

function VaultService:IsVaulting(player)
	return self.ActiveVaultsByPlayer[player] == true
end

function VaultService:CanVault(player, vault)
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	return self:_buildVaultTrajectory(player, character, vault) ~= nil
end

function VaultService:CompleteVault(player, vault)
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	local trajectory = self:_buildVaultTrajectory(player, character, vault)
	if not trajectory then
		return false
	end

	self.ActiveVaultsByPlayer[player] = true
	self.PlayerCooldowns[player] = os.clock() + (vault.Cooldown or DEFAULT_VAULT_COOLDOWN)
	vault.Progress = vault.MaxProgress

	task.spawn(function()
		self:_performVault(player, character, vault, trajectory)
	end)

	DebugLog:Log("Interaction", string.format("[VaultService] %s vaulted %s", player.Name, vault.DisplayName))
	return true
end

function VaultService:_buildVaultTrajectory(player, character, vault)
	if not player or not character or not character.RootPart or not character.Humanoid or not character:IsActionable() then
		return nil
	end

	if self.ActiveVaultsByPlayer[player] then
		return nil
	end

	local cooldownEndsAt = self.PlayerCooldowns[player] or 0
	if os.clock() < cooldownEndsAt then
		return nil
	end

	local statusService = self.StatusEffectService
	if statusService and not statusService:CanInteract(player) then
		return nil
	end

	local vaultPart = vault and vault.Instance
	if not vaultPart or not vaultPart.Parent then
		return nil
	end

	local rootPart = character.RootPart
	local startPosition = rootPart.Position
	local distance = (vaultPart.Position - startPosition).Magnitude
	if distance > (vault.InteractRange or DEFAULT_INTERACT_RANGE) then
		return nil
	end

	local useRightAxis = string.lower(tostring(vault.Axis or "")) == "right"
	local axisVector = useRightAxis and vaultPart.CFrame.RightVector or vaultPart.CFrame.LookVector
	local crossAxis = _getPlanarUnit(axisVector)
	if not crossAxis then
		return nil
	end

	if vault.RequireFacing then
		local toVault = _getPlanarUnit(vaultPart.Position - startPosition)
		local facing = _getPlanarUnit(rootPart.CFrame.LookVector)
		if toVault and facing and facing:Dot(toVault) < (vault.FacingDot or DEFAULT_FACING_DOT) then
			return nil
		end
	end

	local localPosition = vaultPart.CFrame:PointToObjectSpace(startPosition)
	local targetLocalPosition
	if useRightAxis then
		local side = localPosition.X >= 0 and 1 or -1
		local targetX = -side * ((vaultPart.Size.X * 0.5) + (vault.Clearance or DEFAULT_VAULT_CLEARANCE))
		local clampedZ = math.clamp(localPosition.Z, -vaultPart.Size.Z * 0.5, vaultPart.Size.Z * 0.5)
		targetLocalPosition = Vector3.new(targetX, localPosition.Y, clampedZ)
	else
		local side = localPosition.Z >= 0 and 1 or -1
		local targetZ = -side * ((vaultPart.Size.Z * 0.5) + (vault.Clearance or DEFAULT_VAULT_CLEARANCE))
		local clampedX = math.clamp(localPosition.X, -vaultPart.Size.X * 0.5, vaultPart.Size.X * 0.5)
		targetLocalPosition = Vector3.new(clampedX, localPosition.Y, targetZ)
	end

	local worldTarget = vaultPart.CFrame:PointToWorldSpace(targetLocalPosition)
	local endPosition = Vector3.new(worldTarget.X, startPosition.Y, worldTarget.Z)
	local planarDelta = Vector3.new(endPosition.X - startPosition.X, 0, endPosition.Z - startPosition.Z)
	if planarDelta.Magnitude <= 0.1 then
		return nil
	end

	local lookDirection = planarDelta.Unit
	local midpoint = startPosition:Lerp(endPosition, 0.5)
	local apex = midpoint + Vector3.new(0, vault.ArcHeight or DEFAULT_VAULT_ARC_HEIGHT, 0)
	local velocity = rootPart.AssemblyLinearVelocity
	local isFastVault = character.IsSprintHeld == true or character.IsSprinting == true or Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= 12

	return {
		StartPosition = startPosition,
		ApexPosition = apex,
		EndPosition = endPosition,
		LookDirection = lookDirection,
		Duration = isFastVault and (vault.FastDuration or DEFAULT_FAST_VAULT_DURATION) or (vault.Duration or DEFAULT_VAULT_DURATION),
	}
end

function VaultService:_performVault(player, character, vault, trajectory)
	local rootPart = character and character.RootPart
	local humanoid = character and character.Humanoid
	if not rootPart or not humanoid then
		self.ActiveVaultsByPlayer[player] = nil
		return
	end

	local previousAnchored = rootPart.Anchored
	local previousAutoRotate = humanoid.AutoRotate
	local previousPlatformStand = humanoid.PlatformStand

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	character:SetSpeedMultiplier("VaultLock", 0)
	character.Model:SetAttribute("RemnantIsVaulting", true)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.Anchored = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	local startedAt = os.clock()
	local duration = math.max(0.05, trajectory.Duration or DEFAULT_VAULT_DURATION)
	while true do
		if not character:IsAlive() or character:IsDowned() then
			break
		end

		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local easedAlpha = _easeInOut(alpha)
		local position = _quadraticBezier(
			trajectory.StartPosition,
			trajectory.ApexPosition,
			trajectory.EndPosition,
			easedAlpha
		)
		rootPart.CFrame = CFrame.lookAt(position, position + trajectory.LookDirection)

		if alpha >= 1 then
			break
		end

		RunService.Heartbeat:Wait()
	end

	if rootPart and rootPart.Parent then
		rootPart.CFrame = CFrame.lookAt(trajectory.EndPosition, trajectory.EndPosition + trajectory.LookDirection)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		rootPart.Anchored = previousAnchored
		pcall(function()
			rootPart:SetNetworkOwner(player)
		end)
	end

	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = previousPlatformStand
		humanoid.AutoRotate = previousAutoRotate
	end

	if character then
		character:SetSpeedMultiplier("VaultLock", nil)
		if character.Model then
			character.Model:SetAttribute("RemnantIsVaulting", false)
		end
	end

	self.ActiveVaultsByPlayer[player] = nil
end

return VaultService
