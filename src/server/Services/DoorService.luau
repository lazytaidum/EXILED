local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local StatusEffectId = require(ReplicatedStorage.Shared.Enums.StatusEffectId)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local DoorService = {}
DoorService.Name = "DoorService"
DoorService.Dependencies = {
	"CharacterService",
	"EntityService",
	"StatusEffectService",
}

local DEFAULT_INTERACT_RANGE = 9
local DEFAULT_OPEN_ANGLE = 95
local DEFAULT_TOGGLE_DURATION = 0.42
local DEFAULT_SLAM_DURATION = 0.18
local DEFAULT_SLAM_RADIUS = 8
local DEFAULT_SLAM_STUN_DURATION = 1.25

local function _resolveDoorPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		local doorPanel = instance:FindFirstChild("DoorPanel")
		if doorPanel and doorPanel:IsA("BasePart") then
			return doorPanel
		end

		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function _readBooleanAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)
	if value == nil then
		return defaultValue
	end

	return value == true
end

local function _easeInOut(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - (2 * alpha))
end

local function _signFromNumber(value, fallback)
	if type(value) ~= "number" or value == 0 then
		return fallback
	end

	return value > 0 and 1 or -1
end

function DoorService:Init(services)
	self.Services = services
	self.Doors = {}
	self.ActiveDoors = {}
	self.DoorsFolder = self:_resolveDoorsFolder()
end

function DoorService:Start()
	self:_registerExistingDoors()

	if self.DoorsFolder then
		self.DoorsFolder.ChildAdded:Connect(function(instance)
			self:_registerDoor(instance)
		end)

		self.DoorsFolder.ChildRemoved:Connect(function(instance)
			self:_unregisterDoor(instance)
		end)
	end

	DebugLog:Log("Interaction", "[DoorService] Started")
end

function DoorService:_resolveDoorsFolder()
	local interactablesFolder = Workspace:FindFirstChild("Interactables")
	local nestedDoorsFolder = interactablesFolder and interactablesFolder:FindFirstChild("Doors")
	if nestedDoorsFolder and nestedDoorsFolder:IsA("Folder") then
		return nestedDoorsFolder
	end

	local directDoorsFolder = Workspace:FindFirstChild("Doors")
	if directDoorsFolder and directDoorsFolder:IsA("Folder") then
		return directDoorsFolder
	end

	if not interactablesFolder then
		interactablesFolder = Instance.new("Folder")
		interactablesFolder.Name = "Interactables"
		interactablesFolder.Parent = Workspace
	end

	local doorsFolder = Instance.new("Folder")
	doorsFolder.Name = "Doors"
	doorsFolder.Parent = interactablesFolder
	return doorsFolder
end

function DoorService:_registerExistingDoors()
	if not self.DoorsFolder then
		return
	end

	for _, instance in ipairs(self.DoorsFolder:GetChildren()) do
		self:_registerDoor(instance)
	end
end

function DoorService:_registerDoor(instance)
	if self.Doors[instance] then
		return
	end

	local doorPart = _resolveDoorPart(instance)
	if not doorPart then
		DebugLog:Log("Interaction", string.format("[DoorService] Ignored door '%s': no usable part", instance.Name))
		return
	end

	local hingeSide = string.lower(tostring(instance:GetAttribute("HingeSide") or "Left"))
	local defaultOpenSign = hingeSide == "right" and -1 or 1
	local openDirection = string.lower(tostring(instance:GetAttribute("OpenDirection") or ""))
	local openSign = defaultOpenSign
	if openDirection == "back" or openDirection == "backward" or openDirection == "negative" then
		openSign = -1
	elseif openDirection == "front" or openDirection == "forward" or openDirection == "positive" then
		openSign = 1
	else
		openSign = _signFromNumber(tonumber(instance:GetAttribute("OpenSign")), defaultOpenSign)
	end

	local displayName = instance:GetAttribute("DisplayName")
	if not displayName or displayName == "" then
		displayName = "Door"
	end

	local door = {
		Type = InteractableType.Door,
		Id = instance:GetFullName(),
		BaseDisplayName = displayName,
		DisplayName = displayName,
		Instance = doorPart,
		Model = instance,
		IsModel = instance:IsA("Model"),
		Progress = 0,
		MaxProgress = 1,
		ChargeRate = 1,
		InteractRange = math.max(2, tonumber(instance:GetAttribute("InteractRange")) or DEFAULT_INTERACT_RANGE),
		OpenAngle = math.rad(tonumber(instance:GetAttribute("OpenAngle")) or DEFAULT_OPEN_ANGLE) * openSign,
		ToggleDuration = math.clamp(tonumber(instance:GetAttribute("ToggleDuration")) or DEFAULT_TOGGLE_DURATION, 0.05, 2),
		SlamDuration = math.clamp(tonumber(instance:GetAttribute("SlamDuration")) or DEFAULT_SLAM_DURATION, 0.05, 1),
		SlamRadius = math.max(0, tonumber(instance:GetAttribute("SlamRadius")) or DEFAULT_SLAM_RADIUS),
		SlamStunDuration = math.max(0, tonumber(instance:GetAttribute("SlamStunDuration")) or DEFAULT_SLAM_STUN_DURATION),
		SlamEnabled = _readBooleanAttribute(instance, "SlamEnabled", false),
		HingeSide = hingeSide,
		ClosedPartCFrame = doorPart.CFrame,
		ClosedPivot = instance:IsA("Model") and instance:GetPivot() or doorPart.CFrame,
		CurrentAngle = 0,
		IsOpen = instance:GetAttribute("Open") == true,
		IsBusy = false,
		IsComplete = false,
	}

	if door.IsOpen then
		door.CurrentAngle = door.OpenAngle
		self:_applyDoorAngle(door, door.CurrentAngle)
	end

	self.Doors[instance] = door
	self:_applyDoorAttributes(door)

	DebugLog:Log("Interaction", string.format("[DoorService] Registered door %s", instance.Name))
end

function DoorService:_unregisterDoor(instance)
	self.Doors[instance] = nil
end

function DoorService:_applyDoorAttributes(door)
	if not door or not door.Model then
		return
	end

	door.DisplayName = self:_getDoorDisplayName(door)
	door.Model:SetAttribute("InteractableType", InteractableType.Door)
	door.Model:SetAttribute("DoorRegistered", true)
	door.Model:SetAttribute("Open", door.IsOpen == true)
	door.Model:SetAttribute("Busy", door.IsBusy == true)
	if door.Instance and door.Instance ~= door.Model then
		door.Instance:SetAttribute("InteractableType", InteractableType.Door)
		door.Instance:SetAttribute("DoorRegistered", true)
		door.Instance:SetAttribute("Open", door.IsOpen == true)
		door.Instance:SetAttribute("Busy", door.IsBusy == true)
	end
end

function DoorService:_getDoorDisplayName(door)
	local verb = door.IsOpen and "Close" or "Open"
	return string.format("%s %s", verb, door.BaseDisplayName or "Door")
end

function DoorService:_getHingeFrame(door)
	local partCFrame = door.ClosedPartCFrame
	local partSize = door.Instance and door.Instance.Size or Vector3.new(4, 8, 1)
	local hingeX = door.HingeSide == "right" and (partSize.X * 0.5) or (-partSize.X * 0.5)
	return partCFrame * CFrame.new(hingeX, 0, 0)
end

function DoorService:_getDoorTransformForAngle(door, angle)
	local hingeFrame = self:_getHingeFrame(door)
	return hingeFrame * CFrame.Angles(0, angle, 0) * hingeFrame:Inverse()
end

function DoorService:_applyDoorAngle(door, angle)
	if not door or not door.Instance then
		return
	end

	local transform = self:_getDoorTransformForAngle(door, angle)
	if door.IsModel and door.Model and door.Model.Parent then
		door.Model:PivotTo(transform * door.ClosedPivot)
	elseif door.Instance.Parent then
		door.Instance.CFrame = transform * door.ClosedPartCFrame
	end

	door.CurrentAngle = angle
end

function DoorService:GetAvailableDoors()
	local results = {}
	for _, door in pairs(self.Doors) do
		local model = door.Model
		if door.Instance and door.Instance.Parent and model and model.Parent and model:GetAttribute("Disabled") ~= true then
			door.DisplayName = self:_getDoorDisplayName(door)
			table.insert(results, door)
		end
	end

	return results
end

function DoorService:CanUseDoor(player, door)
	if not player or not door or door.IsBusy then
		return false
	end

	if door.Model and door.Model:GetAttribute("Locked") == true then
		return false
	end

	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart or not character:IsActionable() then
		return false
	end

	local statusService = self.StatusEffectService
	if statusService and not statusService:CanInteract(player) then
		return false
	end

	return (door.Instance.Position - character.RootPart.Position).Magnitude <= (door.InteractRange or DEFAULT_INTERACT_RANGE)
end

function DoorService:CompleteDoor(player, door)
	if not self:CanUseDoor(player, door) then
		return false
	end

	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	local shouldOpen = not door.IsOpen
	local isSlam = door.SlamEnabled == true
		and character
		and (character.IsSprintHeld == true or character.IsSprinting == true or character.IsRunning == true)
	local duration = isSlam and door.SlamDuration or door.ToggleDuration

	door.IsBusy = true
	door.Progress = door.MaxProgress
	self:_applyDoorAttributes(door)

	task.spawn(function()
		self:_animateDoor(door, shouldOpen, duration, isSlam)
	end)

	DebugLog:Log("Interaction", string.format(
		"[DoorService] %s %s %s%s",
		player.Name,
		shouldOpen and "opened" or "closed",
		door.BaseDisplayName or "Door",
		isSlam and " with a slam" or ""
	))
	return true
end

function DoorService:_animateDoor(door, shouldOpen, duration, isSlam)
	local startAngle = door.CurrentAngle or 0
	local targetAngle = shouldOpen and door.OpenAngle or 0
	local startedAt = os.clock()
	duration = math.max(0.05, duration or DEFAULT_TOGGLE_DURATION)

	while true do
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local easedAlpha = _easeInOut(alpha)
		local angle = startAngle + ((targetAngle - startAngle) * easedAlpha)
		self:_applyDoorAngle(door, angle)

		if alpha >= 1 then
			break
		end

		RunService.Heartbeat:Wait()
	end

	self:_applyDoorAngle(door, targetAngle)
	door.IsOpen = shouldOpen
	door.IsBusy = false
	self:_applyDoorAttributes(door)

	if isSlam then
		self:_applyDoorSlam(door)
	end
end

function DoorService:_applyDoorSlam(door)
	if not door or not self.EntityService or not self.StatusEffectService then
		return 0
	end

	local origin = door.Instance and door.Instance.Position
	if not origin then
		return 0
	end

	local hitCount = 0
	for _, entity in ipairs(self.EntityService.Entities or {}) do
		if entity.IsActive and entity.RootPart and entity.Health > 0 then
			local distance = (entity.RootPart.Position - origin).Magnitude
			if distance <= (door.SlamRadius or DEFAULT_SLAM_RADIUS) then
				self.StatusEffectService:ApplyStatus(entity, StatusEffectId.Stunned, {
					Duration = door.SlamStunDuration or DEFAULT_SLAM_STUN_DURATION,
					Source = "DoorSlam",
					InterruptAbilities = true,
				})
				hitCount += 1
			end
		end
	end

	if hitCount > 0 then
		DebugLog:Log("Interaction", string.format("[DoorService] %s stunned %d entities", door.BaseDisplayName or "Door", hitCount))
	end

	return hitCount
end

return DoorService
