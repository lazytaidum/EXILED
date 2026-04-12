local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local PerspectiveMode = require(ReplicatedStorage.Shared.Enums.PerspectiveMode)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ViewmodelController = {}
ViewmodelController.Name = "ViewmodelController"
ViewmodelController.Dependencies = {
	"CameraInputController",
	"CombatController",
}

local ASSET_ROOT_NAME = "Assets"
local WEAPON_ASSET_FOLDER_NAME = "Weapons"
local ITEM_ASSET_FOLDER_NAME = "Items"
local VIEWMODEL_FOLDER_NAME = "Viewmodels"
local RIG_FOLDER_NAME = "Rig"
local RIG_ASSET_NAME = "ViewModelRig"
local VIEWMODEL_OFFSET = CFrame.new(0, -0.2, 0)
local RIGHT_HAND_OFFSET = CFrame.new(0.55, -0.4, -0.85)
local LEFT_HAND_OFFSET = CFrame.new(-0.45, -0.5, -0.45)
local RIGHT_FIREARM_SHOULDER_OFFSET = CFrame.new(0.78, -0.08, -0.24)
local LEFT_FIREARM_SHOULDER_OFFSET = CFrame.new(-0.6, -0.18, -0.2)
local WEAPON_ROOT_OFFSET = CFrame.new(0, -0.2, -0.6)
local DEFAULT_AIM_WORLD_OFFSET = CFrame.new(0, -0.03, -0.32)
local RIGHT_HAND_END_LOCAL_OFFSET = Vector3.new(0, -0.62, -0.08)
local LEFT_HAND_END_LOCAL_OFFSET = Vector3.new(0, -0.62, -0.08)
local RIGHT_FIREARM_HAND_END_LOCAL_OFFSET = Vector3.new(0, -0.28, -0.04)
local LEFT_FIREARM_HAND_END_LOCAL_OFFSET = Vector3.new(0, -0.56, -0.08)
local WEAPON_JOINT_BLEND_ALPHA = 0.18
local HELD_ITEM_BLEND_ALPHA = 0.2
local ARM_SOLVE_BLEND_ALPHA = 0.16
local LAB_PREVIEW_OFFSET = CFrame.new(0, -0.9, -9) * CFrame.Angles(0, math.rad(180), 0)
local LAB_STATIC_OFFSET = CFrame.new(0, -0.9, -8) * CFrame.Angles(0, math.rad(180), 0)
local DEBUG_MARKER_SIZE = Vector3.new(0.08, 0.08, 0.08)
local LOOP_ACTIONS = {
	Idle = true,
	Aim = true,
}
local ACTION_TRACK_PRIORITIES = {
	Equip = Enum.AnimationPriority.Action4,
	Idle = Enum.AnimationPriority.Action,
	Aim = Enum.AnimationPriority.Action2,
	Fire = Enum.AnimationPriority.Action4,
	Reload = Enum.AnimationPriority.Action4,
}

local function _safeUnit(vector, fallback)
	if vector.Magnitude <= 1e-4 then
		return fallback
	end

	return vector.Unit
end

function ViewmodelController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.Character = nil
	self.HiddenDescendants = {}
	self.ActiveRig = nil
	self.ActiveItemId = nil
	self.ActiveEntryType = nil
	self.ActiveTracks = {}
	self.IsBodyHidden = false
	self.LastCombatSnapshot = nil
	self.ActiveHeldModel = nil
	self.ActiveMuzzleAttachment = nil
	self.ActiveAimAttachment = nil
	self.ActiveRightHandAttachment = nil
	self.ActiveLeftHandAttachment = nil
	self.LoadedAnimationTracks = {}
	self.CurrentLoopAction = nil
	self.LastAppliedJointCorrections = {}
	self.HybridFirearmActive = false
	self.LastUpdateAt = os.clock()
	self.IsRigVisible = false
	self.LabEnabled = false
	self.LabFrozen = false
	self.LabLoopOverride = nil
	self.LabLastAction = "Idle"
	self.LabShowSourceRig = false
	self.LabOverrideEntry = nil
	self.LabSnapshotEntry = nil
	self.LabPreviewRig = nil
	self.LabPreviewPartMap = {}
	self.LabPreviewSourceRig = nil
	self.LabPreviewSignature = nil
	self.LabAutoRefreshStatic = false
	self.LabStaticRig = nil
	self.LabStaticPartMap = {}
	self.LabStaticSourceRig = nil
	self.LabStaticAnchorCFrame = nil
	self.LabStaticSignature = nil
	self.LabStaticCapturedAt = nil
	self.LabDebugPointsEnabled = false
	self.LabDebugMarkers = {}
	self.LabSelectedAttachmentName = "Aim"
	self.LabAttachmentOverrides = {}
	self.ActiveAttachmentBaseCFrames = {}
	self.LastFirearmIkStatus = {
		Active = false,
		RightTargetAvailable = false,
		LeftTargetAvailable = false,
		RightInfluence = 0,
		LeftInfluence = 0,
	}
end

function ViewmodelController:Start()
	self:_hookCharacter(self.World:GetCharacter())

	self.Player.CharacterAdded:Connect(function(character)
		self:_hookCharacter(character)
	end)

	RunService:BindToRenderStep("ViewmodelController.Update", Enum.RenderPriority.Camera.Value + 2, function()
		self:_update()
	end)

	DebugLog:Log("ClientCombat", "[ViewmodelController] Started")
end

function ViewmodelController:_hookCharacter(character)
	self.Character = character
	self.HiddenDescendants = {}
	self:_setBodyHidden(false)
end

function ViewmodelController:IsFirstPersonActive()
	return self.CameraInputController
		and self.CameraInputController:GetPerspectiveMode() == PerspectiveMode.FirstPerson
		and self.CameraInputController.IsLocked == true
end

function ViewmodelController:GetVisualMuzzleOrigin(_weaponId)
	if self.ActiveMuzzleAttachment and self.ActiveMuzzleAttachment.Parent then
		return self.ActiveMuzzleAttachment.WorldPosition
	end

	if not self.ActiveRig then
		return nil
	end

	local muzzle = self.ActiveRig:FindFirstChild("Muzzle", true)
	return muzzle and muzzle.WorldPosition or nil
end

function ViewmodelController:PlayAction(actionName)
	if not self.ActiveRig then
		return
	end

	self.LabLastAction = actionName
	self.ActiveRig:SetAttribute("LastAction", actionName)
	if self.ActiveHeldModel then
		self.ActiveHeldModel:SetAttribute("LastAction", actionName)
	end

	self:_playAnimationAction(actionName)
end

function ViewmodelController:SetLabEnabled(enabled)
	local desired = enabled == true
	if self.LabEnabled == desired then
		return
	end

	self.LabEnabled = desired
	if not desired then
		self.LabFrozen = false
		self.LabLoopOverride = nil
		self.LabOverrideEntry = nil
		self.LabSnapshotEntry = nil
		self.LabAutoRefreshStatic = false
		self:_destroyLabPreview()
		self:ClearLabStaticRig()
		self:SetLabDebugPointsEnabled(false)
	else
		self.LabLastAction = self.CurrentLoopAction or self.LabLastAction or "Idle"
	end
end

function ViewmodelController:IsLabEnabled()
	return self.LabEnabled == true
end

function ViewmodelController:SetLabFrozen(frozen)
	self.LabFrozen = frozen == true
end

function ViewmodelController:IsLabFrozen()
	return self.LabFrozen == true
end

function ViewmodelController:SetLabShowSourceRig(visible)
	self.LabShowSourceRig = visible == true
end

function ViewmodelController:IsLabShowingSourceRig()
	return self.LabShowSourceRig == true
end

function ViewmodelController:SetLabAutoRefreshStatic(enabled)
	self.LabAutoRefreshStatic = enabled == true
	if self.LabAutoRefreshStatic and self.LabEnabled and self.ActiveRig and self.ActiveRig.PrimaryPart then
		if self.LabStaticRig then
			self:_syncLabStaticRigFromActiveRig()
		else
			self:CaptureLabStaticRig()
		end
	end
end

function ViewmodelController:IsLabAutoRefreshingStatic()
	return self.LabAutoRefreshStatic == true
end

function ViewmodelController:CaptureLabStaticRig()
	if not self.ActiveRig or not self.ActiveRig.PrimaryPart then
		return false
	end

	self:_destroyLabStaticRig()

	local staticRig = self.ActiveRig:Clone()
	staticRig.Name = "ViewmodelLabStatic"

	for _, descendant in ipairs(staticRig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
			descendant.LocalTransparencyModifier = 0
		end
	end

	local sourceRoot = self.ActiveRig.PrimaryPart
	local staticRoot = staticRig.PrimaryPart or staticRig:FindFirstChild(sourceRoot.Name, true)
	if staticRoot and staticRoot:IsA("BasePart") then
		staticRig.PrimaryPart = staticRoot
	end

	local staticPartMap = {}
	for _, sourceDescendant in ipairs(self.ActiveRig:GetDescendants()) do
		if sourceDescendant:IsA("BasePart") then
			local relativePath = self:_getRelativeDescendantPath(self.ActiveRig, sourceDescendant)
			local staticDescendant = self:_findDescendantByPath(staticRig, relativePath)
			if staticDescendant and staticDescendant:IsA("BasePart") then
				staticPartMap[sourceDescendant] = staticDescendant
			end
		end
	end

	staticRig.Parent = Workspace
	self.LabStaticRig = staticRig
	self.LabStaticPartMap = staticPartMap
	self.LabStaticSourceRig = self.ActiveRig
	self.LabStaticAnchorCFrame = self.World.Camera.CFrame * LAB_STATIC_OFFSET
	self.LabStaticSignature = self:_getLabPreviewSignature()
	self.LabStaticCapturedAt = os.clock()
	self:_syncLabStaticRigFromActiveRig()
	return true
end

function ViewmodelController:ClearLabStaticRig()
	self:_destroyLabStaticRig()
end

function ViewmodelController:HasLabStaticRig()
	return self.LabStaticRig ~= nil
end

function ViewmodelController:SetLabDebugPointsEnabled(enabled)
	self.LabDebugPointsEnabled = enabled == true
	if not self.LabDebugPointsEnabled then
		self:_destroyLabDebugMarkers()
	end
end

function ViewmodelController:IsLabDebugPointsEnabled()
	return self.LabDebugPointsEnabled == true
end

function ViewmodelController:SetLabWeapon(weaponId)
	if type(weaponId) ~= "string" or weaponId == "" or not WeaponDefinitions[weaponId] then
		return
	end

	self.LabOverrideEntry = {
		EntryType = "Weapon",
		WeaponId = weaponId,
	}
	self.LabSnapshotEntry = self.LabOverrideEntry
	self.LabLastAction = self.LabLoopOverride or self.CurrentLoopAction or "Idle"
	self.ActiveItemId = nil
	self.ActiveEntryType = nil
	self:_destroyLabPreview()
end

function ViewmodelController:SetLabSelectedAttachment(attachmentName)
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return
	end

	self.LabSelectedAttachmentName = attachmentName
end

function ViewmodelController:GetLabSelectedAttachment()
	return self.LabSelectedAttachmentName
end

function ViewmodelController:_getLabAttachmentOverrideKey(attachmentName)
	local weaponId = self.ActiveItemId
	if not weaponId and self.LabOverrideEntry then
		weaponId = self.LabOverrideEntry.WeaponId
	end
	if not weaponId and self.LabSnapshotEntry then
		weaponId = self.LabSnapshotEntry.WeaponId
	end
	if not weaponId or not attachmentName or attachmentName == "" then
		return nil
	end

	return string.format("%s:%s", tostring(weaponId), tostring(attachmentName))
end

function ViewmodelController:GetLabAttachmentOverride(attachmentName)
	local key = self:_getLabAttachmentOverrideKey(attachmentName)
	if not key then
		return {
			Position = Vector3.zero,
			Rotation = Vector3.zero,
		}
	end

	local override = self.LabAttachmentOverrides[key]
	if not override then
		override = {
			Position = Vector3.zero,
			Rotation = Vector3.zero,
		}
		self.LabAttachmentOverrides[key] = override
	end

	return override
end

function ViewmodelController:AdjustLabAttachment(attachmentName, positionDelta, rotationDelta)
	local override = self:GetLabAttachmentOverride(attachmentName)
	override.Position += positionDelta or Vector3.zero
	override.Rotation += rotationDelta or Vector3.zero
	self:_applyActiveAttachmentOverrides()
	if self.LabEnabled and self.LabAutoRefreshStatic then
		if self.LabStaticRig then
			self:_syncLabStaticRigFromActiveRig()
		else
			self:CaptureLabStaticRig()
		end
	end
end

function ViewmodelController:ResetLabAttachment(attachmentName)
	local key = self:_getLabAttachmentOverrideKey(attachmentName)
	if key then
		self.LabAttachmentOverrides[key] = {
			Position = Vector3.zero,
			Rotation = Vector3.zero,
		}
	end
	self:_applyActiveAttachmentOverrides()
	if self.LabEnabled and self.LabAutoRefreshStatic then
		if self.LabStaticRig then
			self:_syncLabStaticRigFromActiveRig()
		else
			self:CaptureLabStaticRig()
		end
	end
end

function ViewmodelController:ClearLabWeapon()
	self.LabOverrideEntry = nil
	self.LabSnapshotEntry = nil
	self.ActiveItemId = nil
	self.ActiveEntryType = nil
	self:_destroyLabPreview()
	self:ClearLabStaticRig()
end

function ViewmodelController:PreviewLabAction(actionName)
	if type(actionName) ~= "string" or actionName == "" then
		return
	end

	if LOOP_ACTIONS[actionName] then
		self.LabLoopOverride = actionName
	end

	self.LabLastAction = actionName
	self:PlayAction(actionName)
	if self.LabEnabled and self.LabAutoRefreshStatic then
		if self.LabStaticRig then
			self:_syncLabStaticRigFromActiveRig()
		else
			self:CaptureLabStaticRig()
		end
	end
end

function ViewmodelController:GetLabAttachmentOverrideDump()
	local weaponId = self.ActiveItemId
	if not weaponId and self.LabOverrideEntry then
		weaponId = self.LabOverrideEntry.WeaponId
	end
	if not weaponId and self.LabSnapshotEntry then
		weaponId = self.LabSnapshotEntry.WeaponId
	end
	if not weaponId then
		return "No active weapon override context."
	end

	local lines = {
		string.format("Weapon: %s", tostring(weaponId)),
	}
	for _, attachmentName in ipairs({ "Aim", "RightHand", "LeftHand", "Muzzle" }) do
		local override = self:GetLabAttachmentOverride(attachmentName)
		table.insert(
			lines,
			string.format(
				"%s Pos(%.3f, %.3f, %.3f) Rot(%.1f, %.1f, %.1f)",
				attachmentName,
				override.Position.X,
				override.Position.Y,
				override.Position.Z,
				override.Rotation.X,
				override.Rotation.Y,
				override.Rotation.Z
			)
		)
	end

	return table.concat(lines, "\n")
end

function ViewmodelController:GetLabStatus()
	local attachmentOverride = self:GetLabAttachmentOverride(self.LabSelectedAttachmentName)
	return {
		Enabled = self.LabEnabled == true,
		Frozen = self.LabFrozen == true,
		LoopAction = self.LabLoopOverride or self.CurrentLoopAction or "Idle",
		LastAction = self.LabLastAction or "Idle",
		ShowSourceRig = self.LabShowSourceRig == true,
		WeaponId = self.LabOverrideEntry and self.LabOverrideEntry.WeaponId or nil,
		SnapshotWeaponId = self.LabSnapshotEntry and self.LabSnapshotEntry.WeaponId or nil,
		FirearmIk = self.LastFirearmIkStatus,
		SelectedAttachmentName = self.LabSelectedAttachmentName,
		SelectedAttachmentOverride = attachmentOverride,
		AttachmentOverrideDump = self:GetLabAttachmentOverrideDump(),
		StaticRigCaptured = self:HasLabStaticRig(),
		AutoRefreshStatic = self:IsLabAutoRefreshingStatic(),
		DebugPointsEnabled = self:IsLabDebugPointsEnabled(),
	}
end

function ViewmodelController:_getEquippedEntry()
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	if not combatState or not combatState.Weapons then
		return nil
	end

	local equippedSlot = combatState.EquippedSlot or 1
	return combatState.Weapons[equippedSlot]
end

function ViewmodelController:_getLabEntry()
	if self.LabOverrideEntry then
		return self.LabOverrideEntry
	end

	local liveEntry = self:_getEquippedEntry()
	if liveEntry and liveEntry.EntryType and liveEntry.WeaponId then
		self.LabSnapshotEntry = {
			EntryType = liveEntry.EntryType,
			WeaponId = liveEntry.WeaponId,
		}
		return liveEntry
	end

	return self.LabSnapshotEntry
end

function ViewmodelController:_getDefinitionForEntry(entry)
	if not entry then
		return nil
	end

	if entry.EntryType == "Weapon" then
		return WeaponDefinitions[entry.WeaponId]
	elseif entry.EntryType == "Item" then
		return ItemDefinitions[entry.WeaponId]
	end

	return nil
end

function ViewmodelController:_createRig()
	local authoredRig = self:_createAuthoredRig()
	if authoredRig then
		return authoredRig
	end

	DebugLog:Log("ClientCombat", "[ViewmodelController] Falling back to generated rig")

	local camera = self.World.Camera

	local model = Instance.new("Model")
	model.Name = "ViewmodelRig"
	model.Parent = camera

	local animationController = Instance.new("AnimationController")
	animationController.Name = "AnimationController"
	animationController.Parent = model

	local animator = Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = animationController

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	local rightArm = Instance.new("Part")
	rightArm.Name = "RightArm"
	rightArm.Size = Vector3.new(0.38, 1.25, 0.38)
	rightArm.Color = Color3.fromRGB(234, 208, 180)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.CanCollide = false
	rightArm.CanQuery = false
	rightArm.CanTouch = false
	rightArm.CastShadow = false
	rightArm.Massless = true
	rightArm.Parent = model

	local leftArm = rightArm:Clone()
	leftArm.Name = "LeftArm"
	leftArm.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.4, 1.6, 0.8)
	torso.Transparency = 1
	torso.CanCollide = false
	torso.CanQuery = false
	torso.CanTouch = false
	torso.CastShadow = false
	torso.Massless = true
	torso.Parent = model

	local weaponRoot = Instance.new("Part")
	weaponRoot.Name = "WeaponRoot"
	weaponRoot.Size = Vector3.new(0.2, 0.2, 0.2)
	weaponRoot.Transparency = 1
	weaponRoot.CanCollide = false
	weaponRoot.CanQuery = false
	weaponRoot.CanTouch = false
	weaponRoot.CastShadow = false
	weaponRoot.Massless = true
	weaponRoot.Parent = model

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.6)
	muzzle.Parent = weaponRoot

	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = root
	rootJoint.Part1 = torso
	rootJoint.C0 = CFrame.new(0, -0.2, 0)
	rootJoint.Parent = root

	local rightShoulder = Instance.new("Motor6D")
	rightShoulder.Name = "RightShoulder"
	rightShoulder.Part0 = torso
	rightShoulder.Part1 = rightArm
	rightShoulder.C0 = RIGHT_HAND_OFFSET
	rightShoulder.Parent = torso

	local leftShoulder = Instance.new("Motor6D")
	leftShoulder.Name = "LeftShoulder"
	leftShoulder.Part0 = torso
	leftShoulder.Part1 = leftArm
	leftShoulder.C0 = LEFT_HAND_OFFSET
	leftShoulder.Parent = torso

	local weaponJoint = Instance.new("Motor6D")
	weaponJoint.Name = "WeaponJoint"
	weaponJoint.Part0 = root
	weaponJoint.Part1 = weaponRoot
	weaponJoint.C0 = WEAPON_ROOT_OFFSET
	weaponJoint.Parent = root

	return model
end

function ViewmodelController:_normalizeAnimationId(animationId)
	if animationId == nil then
		return nil
	end

	if type(animationId) == "number" then
		return "rbxassetid://" .. tostring(animationId)
	end

	if type(animationId) ~= "string" then
		return nil
	end

	if animationId == "" then
		return nil
	end

	if string.find(animationId, "rbxassetid://", 1, true) == 1 then
		return animationId
	end

	if string.match(animationId, "^%d+$") then
		return "rbxassetid://" .. animationId
	end

	return animationId
end

function ViewmodelController:_getAnimator()
	if not self.ActiveRig then
		return nil
	end

	local animationController = self.ActiveRig:FindFirstChild("AnimationController", true)
	return animationController and animationController:FindFirstChildOfClass("Animator") or nil
end

function ViewmodelController:_setRigVisible(visible)
	if not self.ActiveRig or self.IsRigVisible == visible then
		return
	end

	self.IsRigVisible = visible
	for _, descendant in ipairs(self.ActiveRig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = visible and 0 or 1
		end
	end
end

function ViewmodelController:_clearLoadedAnimationTracks()
	for _, track in pairs(self.LoadedAnimationTracks or {}) do
		if track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end

	self.LoadedAnimationTracks = {}
	self.CurrentLoopAction = nil
end

function ViewmodelController:_loadAnimationTracks(definition)
	self:_clearLoadedAnimationTracks()

	local animator = self:_getAnimator()
	local animationIds = definition and definition.AnimationIds
	if not animator or type(animationIds) ~= "table" then
		return
	end

	for actionName, animationId in pairs(animationIds) do
		local normalizedId = self:_normalizeAnimationId(animationId)
		if normalizedId then
			local animation = Instance.new("Animation")
			animation.AnimationId = normalizedId

			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			animation:Destroy()

			if ok and track then
				track.Priority = ACTION_TRACK_PRIORITIES[actionName] or Enum.AnimationPriority.Action
				track.Looped = LOOP_ACTIONS[actionName] == true
				self.LoadedAnimationTracks[actionName] = track
			else
				DebugLog:Log("ClientCombat", string.format("[ViewmodelController] Failed to load %s animation", tostring(actionName)))
			end
		end
	end
end

function ViewmodelController:_hasLoadedAnimationTracks()
	return next(self.LoadedAnimationTracks or {}) ~= nil
end

function ViewmodelController:_playLoopAction(actionName)
	local desiredAction = LOOP_ACTIONS[actionName] and actionName or "Idle"
	if self.CurrentLoopAction == desiredAction then
		return
	end

	local nextTrack = self.LoadedAnimationTracks and self.LoadedAnimationTracks[desiredAction] or nil
	if self.CurrentLoopAction and self.LoadedAnimationTracks then
		local currentTrack = self.LoadedAnimationTracks[self.CurrentLoopAction]
		if currentTrack and currentTrack.IsPlaying then
			currentTrack:Stop(0.12)
		end
	end

	self.CurrentLoopAction = desiredAction
	if nextTrack then
		nextTrack:Play(0.12, 1, 1)
	end
end

function ViewmodelController:_playAnimationAction(actionName)
	if LOOP_ACTIONS[actionName] then
		self:_playLoopAction(actionName)
		return
	end

	local track = self.LoadedAnimationTracks and self.LoadedAnimationTracks[actionName] or nil
	if track then
		if track.IsPlaying then
			track:Stop(0.03)
		end
		track:Play(0.03, 1, 1)
	end
end

function ViewmodelController:_getBaseJointTransform(joint, key)
	if not joint then
		return CFrame.new()
	end

	local currentTransform = joint.Transform
	local lastCorrection = self.LastAppliedJointCorrections[key]
	if lastCorrection then
		return currentTransform * lastCorrection:Inverse()
	end

	return currentTransform
end

function ViewmodelController:_applyJointCorrection(joint, key, correction)
	if not joint then
		return
	end

	local safeCorrection = correction or CFrame.new()
	local baseTransform = self:_getBaseJointTransform(joint, key)
	joint.Transform = baseTransform * safeCorrection
	self.LastAppliedJointCorrections[key] = safeCorrection
end

function ViewmodelController:_clearJointCorrection(joint, key)
	if not joint then
		self.LastAppliedJointCorrections[key] = nil
		return
	end

	joint.Transform = self:_getBaseJointTransform(joint, key)
	self.LastAppliedJointCorrections[key] = nil
end

function ViewmodelController:_blendCFrame(currentValue, targetValue, alpha)
	local safeAlpha = math.clamp(alpha or 1, 0, 1)
	return currentValue:Lerp(targetValue, safeAlpha)
end

function ViewmodelController:_resolveRigAsset()
	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSET_ROOT_NAME)
	if not assetsFolder then
		DebugLog:Log("ClientCombat", "[ViewmodelController] Missing ReplicatedStorage.Assets")
		return nil
	end

	local weaponsFolder = assetsFolder:FindFirstChild(WEAPON_ASSET_FOLDER_NAME)
	local viewmodelsFolder = weaponsFolder and weaponsFolder:FindFirstChild(VIEWMODEL_FOLDER_NAME)
	local rigFolder = viewmodelsFolder and viewmodelsFolder:FindFirstChild(RIG_FOLDER_NAME)
	local rigAsset = rigFolder and rigFolder:FindFirstChild(RIG_ASSET_NAME)
	if not rigAsset then
		DebugLog:Log("ClientCombat", "[ViewmodelController] Missing authored viewmodel rig asset")
		return nil
	end

	return rigAsset
end

function ViewmodelController:_isValidRig(model)
	if not model or not model:IsA("Model") then
		return false
	end

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local torso = model:FindFirstChild("Torso")
	local leftArm = model:FindFirstChild("LeftArm")
	local rightArm = model:FindFirstChild("RightArm")
	local weaponRoot = model:FindFirstChild("WeaponRoot")
	local rootJoint = model:FindFirstChild("RootJoint", true)
	local leftShoulder = model:FindFirstChild("LeftShoulder", true)
	local rightShoulder = model:FindFirstChild("RightShoulder", true)
	local weaponJoint = model:FindFirstChild("WeaponJoint", true)
	local animationController = model:FindFirstChild("AnimationController", true)
	local animator = animationController and animationController:FindFirstChildOfClass("Animator")

	if not (root and root:IsA("BasePart")) then
		return false
	end

	if not (torso and torso:IsA("BasePart") and leftArm and leftArm:IsA("BasePart") and rightArm and rightArm:IsA("BasePart") and weaponRoot and weaponRoot:IsA("BasePart")) then
		return false
	end

	if not (rootJoint and rootJoint:IsA("Motor6D") and leftShoulder and leftShoulder:IsA("Motor6D") and rightShoulder and rightShoulder:IsA("Motor6D") and weaponJoint and weaponJoint:IsA("Motor6D")) then
		return false
	end

	if not (animationController and animationController:IsA("AnimationController") and animator) then
		return false
	end

	return true
end

function ViewmodelController:_createAuthoredRig()
	local rigAsset = self:_resolveRigAsset()
	if not rigAsset then
		return nil
	end

	local clone = rigAsset:Clone()
	clone.Name = "ViewmodelRig"

	local root = clone.PrimaryPart or clone:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		clone.PrimaryPart = root
	end

	if not self:_isValidRig(clone) then
		DebugLog:Log("ClientCombat", "[ViewmodelController] Authored viewmodel rig is invalid; using fallback")
		clone:Destroy()
		return nil
	end

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end

	clone.Parent = self.World.Camera
	return clone
end

function ViewmodelController:_createFallbackItemModel(entry, definition)
	local itemModel = Instance.new("Model")
	itemModel.Name = "HeldItem"

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.28, 0.28, 1.1)
	core.Color = entry.EntryType == "Weapon" and Color3.fromRGB(54, 58, 68) or Color3.fromRGB(86, 114, 96)
	core.Material = Enum.Material.SmoothPlastic
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Massless = true
	core.Parent = itemModel
	itemModel.PrimaryPart = core

	local front = Instance.new("Part")
	front.Name = "Front"
	front.Size = Vector3.new(0.18, 0.18, 0.36)
	front.Color = entry.EntryType == "Weapon" and Color3.fromRGB(218, 224, 235) or Color3.fromRGB(226, 233, 220)
	front.Material = Enum.Material.SmoothPlastic
	front.CanCollide = false
	front.CanQuery = false
	front.CanTouch = false
	front.CastShadow = false
	front.Massless = true
	front.Parent = itemModel

	local frontWeld = Instance.new("WeldConstraint")
	frontWeld.Part0 = core
	frontWeld.Part1 = front
	frontWeld.Parent = core
	front.CFrame = core.CFrame * CFrame.new(0, 0, -0.6)

	local label = Instance.new("BillboardGui")
	label.Name = "ItemLabel"
	label.Size = UDim2.fromOffset(140, 30)
	label.StudsOffset = Vector3.new(0, 0.26, 0)
	label.AlwaysOnTop = true
	label.Parent = core

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(240, 240, 240)
	text.TextStrokeTransparency = 0.6
	text.Text = definition and (definition.ShortDisplayName or definition.DisplayName) or (entry.WeaponId or "Held")
	text.Parent = label

	return itemModel
end

function ViewmodelController:_getViewmodelAssetFolder(entryType)
	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSET_ROOT_NAME)
	if not assetsFolder then
		return nil
	end

	local categoryFolderName = entryType == "Item" and ITEM_ASSET_FOLDER_NAME or WEAPON_ASSET_FOLDER_NAME
	local categoryFolder = assetsFolder:FindFirstChild(categoryFolderName)
	if not categoryFolder then
		return nil
	end

	return categoryFolder:FindFirstChild(VIEWMODEL_FOLDER_NAME)
end

function ViewmodelController:_resolveViewmodelAsset(entry, definition)
	local assetId = definition and definition.ViewmodelAssetId
	if not assetId or assetId == "" then
		return nil
	end

	local folder = self:_getViewmodelAssetFolder(entry and entry.EntryType or nil)
	if not folder then
		return nil
	end

	return folder:FindFirstChild(assetId)
end

function ViewmodelController:_prepareAuthoredItemModel(assetModel)
	if not assetModel or not assetModel:IsA("Model") then
		return nil
	end

	local clone = assetModel:Clone()
	clone.Name = "HeldItem"

	local root = clone.PrimaryPart or clone:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		clone:Destroy()
		return nil
	end

	clone.PrimaryPart = root

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end

	return clone
end

function ViewmodelController:_cacheHeldItemHandles(itemModel)
	self.ActiveHeldModel = itemModel
	self.ActiveMuzzleAttachment = itemModel and itemModel:FindFirstChild("Muzzle", true) or nil
	self.ActiveAimAttachment = itemModel and itemModel:FindFirstChild("Aim", true) or nil
	self.ActiveRightHandAttachment = itemModel and itemModel:FindFirstChild("RightHand", true) or nil
	self.ActiveLeftHandAttachment = itemModel and itemModel:FindFirstChild("LeftHand", true) or nil
	self.ActiveAttachmentBaseCFrames = {}

	for attachmentName, attachment in pairs({
		Aim = self.ActiveAimAttachment,
		RightHand = self.ActiveRightHandAttachment,
		LeftHand = self.ActiveLeftHandAttachment,
		Muzzle = self.ActiveMuzzleAttachment,
	}) do
		if attachment then
			self.ActiveAttachmentBaseCFrames[attachmentName] = attachment.CFrame
		end
	end

	self:_applyActiveAttachmentOverrides()
end

function ViewmodelController:_applyActiveAttachmentOverrides()
	for attachmentName, attachment in pairs({
		Aim = self.ActiveAimAttachment,
		RightHand = self.ActiveRightHandAttachment,
		LeftHand = self.ActiveLeftHandAttachment,
		Muzzle = self.ActiveMuzzleAttachment,
	}) do
		local baseCFrame = self.ActiveAttachmentBaseCFrames[attachmentName]
		if attachment and baseCFrame then
			local override = self:GetLabAttachmentOverride(attachmentName)
			attachment.CFrame = baseCFrame
				* CFrame.new(override.Position)
				* CFrame.Angles(
					math.rad(override.Rotation.X),
					math.rad(override.Rotation.Y),
					math.rad(override.Rotation.Z)
				)
		end
	end
end

function ViewmodelController:_destroyLabPreview()
	if self.LabPreviewRig then
		self.LabPreviewRig:Destroy()
	end

	self.LabPreviewRig = nil
	self.LabPreviewPartMap = {}
	self.LabPreviewSourceRig = nil
	self.LabPreviewSignature = nil
end

function ViewmodelController:_destroyLabStaticRig()
	if self.LabStaticRig then
		self.LabStaticRig:Destroy()
	end

	self.LabStaticRig = nil
	self.LabStaticPartMap = {}
	self.LabStaticSourceRig = nil
	self.LabStaticAnchorCFrame = nil
	self.LabStaticSignature = nil
	self.LabStaticCapturedAt = nil
end

function ViewmodelController:_destroyLabDebugMarkers()
	for _, marker in pairs(self.LabDebugMarkers) do
		if marker then
			marker:Destroy()
		end
	end

	self.LabDebugMarkers = {}
end

function ViewmodelController:_getRelativeDescendantPath(root, descendant)
	if not root or not descendant or descendant == root then
		return ""
	end

	local segments = {}
	local current = descendant
	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end

	return table.concat(segments, "/")
end

function ViewmodelController:_findDescendantByPath(root, relativePath)
	if not root or relativePath == "" then
		return root
	end

	local current = root
	for segment in string.gmatch(relativePath, "[^/]+") do
		current = current and current:FindFirstChild(segment) or nil
		if not current then
			return nil
		end
	end

	return current
end

function ViewmodelController:_getLabPreviewSignature()
	return string.format("%s:%s", tostring(self.ActiveEntryType or "None"), tostring(self.ActiveItemId or "None"))
end

function ViewmodelController:_ensureLabPreview()
	if not self.LabEnabled or not self.ActiveRig then
		self:_destroyLabPreview()
		return nil
	end

	local signature = self:_getLabPreviewSignature()
	if self.LabPreviewRig and self.LabPreviewSourceRig == self.ActiveRig and self.LabPreviewSignature == signature then
		return self.LabPreviewRig
	end

	self:_destroyLabPreview()

	local previewRig = self.ActiveRig:Clone()
	previewRig.Name = "ViewmodelLabPreview"

	for _, descendant in ipairs(previewRig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
			descendant.LocalTransparencyModifier = 0
		end
	end

	previewRig.Parent = Workspace

	local previewMap = {}
	local sourceRoot = self.ActiveRig.PrimaryPart
	for _, sourceDescendant in ipairs(self.ActiveRig:GetDescendants()) do
		if sourceDescendant:IsA("BasePart") then
			local relativePath = self:_getRelativeDescendantPath(self.ActiveRig, sourceDescendant)
			local previewDescendant = self:_findDescendantByPath(previewRig, relativePath)
			if previewDescendant and previewDescendant:IsA("BasePart") then
				previewMap[sourceDescendant] = previewDescendant
			end
		end
	end

	self.LabPreviewRig = previewRig
	self.LabPreviewPartMap = previewMap
	self.LabPreviewSourceRig = self.ActiveRig
	self.LabPreviewSignature = signature

	if sourceRoot and not previewRig.PrimaryPart then
		local previewRoot = previewMap[sourceRoot]
		if previewRoot then
			previewRig.PrimaryPart = previewRoot
		end
	end

	return previewRig
end

function ViewmodelController:_getLabPreviewRootCFrame()
	return self.World.Camera.CFrame * LAB_PREVIEW_OFFSET
end

function ViewmodelController:_getLabStaticRootCFrame()
	return self.LabStaticAnchorCFrame or (self.World.Camera.CFrame * LAB_STATIC_OFFSET)
end

function ViewmodelController:_syncLabStaticRigFromActiveRig()
	if not self.LabStaticRig or not self.ActiveRig or not self.ActiveRig.PrimaryPart then
		return
	end

	local signature = self:_getLabPreviewSignature()
	if self.LabStaticSourceRig ~= self.ActiveRig or self.LabStaticSignature ~= signature then
		self:CaptureLabStaticRig()
		return
	end

	local sourceRoot = self.ActiveRig.PrimaryPart
	local staticRootCFrame = self:_getLabStaticRootCFrame()
	for sourcePart, staticPart in pairs(self.LabStaticPartMap) do
		if sourcePart.Parent and staticPart.Parent then
			local relativeCFrame = sourceRoot.CFrame:ToObjectSpace(sourcePart.CFrame)
			staticPart.CFrame = staticRootCFrame * relativeCFrame
		end
	end

	self.LabStaticCapturedAt = os.clock()
end

function ViewmodelController:_syncLabPreview(forceSync)
	local previewRig = self:_ensureLabPreview()
	if not previewRig or not self.ActiveRig or not self.ActiveRig.PrimaryPart then
		return
	end

	if self.LabFrozen and not forceSync then
		return
	end

	local sourceRoot = self.ActiveRig.PrimaryPart
	local previewRootCFrame = self:_getLabPreviewRootCFrame()
	for sourcePart, previewPart in pairs(self.LabPreviewPartMap) do
		if sourcePart.Parent and previewPart.Parent then
			local relativeCFrame = sourceRoot.CFrame:ToObjectSpace(sourcePart.CFrame)
			previewPart.CFrame = previewRootCFrame * relativeCFrame
		end
	end
end

function ViewmodelController:_getRigHandSocket(armName)
	if not self.ActiveRig then
		return nil
	end

	local socketNames = armName == "RightArm" and { "RightHandSocket", "RightWrist", "RightGripPoint" } or { "LeftHandSocket", "LeftWrist", "LeftGripPoint" }
	for _, socketName in ipairs(socketNames) do
		local candidate = self.ActiveRig:FindFirstChild(socketName, true)
		if candidate and candidate:IsA("Attachment") then
			return candidate
		end
	end

	return nil
end

function ViewmodelController:_getHeldItemJoint()
	local weaponRoot = self.ActiveRig and self.ActiveRig:FindFirstChild("WeaponRoot")
	return weaponRoot and weaponRoot:FindFirstChild("HeldItemJoint") or nil
end

function ViewmodelController:_getHeldTargetAttachment(targetAttachmentName)
	if not self.ActiveHeldModel or type(targetAttachmentName) ~= "string" or targetAttachmentName == "" then
		return nil
	end

	local targetAttachment = self.ActiveHeldModel:FindFirstChild(targetAttachmentName, true)
	if targetAttachment and targetAttachment:IsA("Attachment") and targetAttachment.Parent then
		return targetAttachment
	end

	return nil
end

function ViewmodelController:_getStaticAttachment(attachmentName)
	if not self.LabStaticRig or type(attachmentName) ~= "string" or attachmentName == "" then
		return nil
	end

	local attachment = self.LabStaticRig:FindFirstChild(attachmentName, true)
	if attachment and attachment:IsA("Attachment") and attachment.Parent then
		return attachment
	end

	return nil
end

function ViewmodelController:_getStaticRigHandSocket(armName)
	if not self.LabStaticRig then
		return nil
	end

	local socketNames = armName == "RightArm" and { "RightHandSocket", "RightWrist", "RightGripPoint" } or { "LeftHandSocket", "LeftWrist", "LeftGripPoint" }
	for _, socketName in ipairs(socketNames) do
		local candidate = self.LabStaticRig:FindFirstChild(socketName, true)
		if candidate and candidate:IsA("Attachment") then
			return candidate
		end
	end

	return nil
end

function ViewmodelController:_getJointWorldCFrame(rigModel, jointName)
	if not rigModel or type(jointName) ~= "string" then
		return nil
	end

	local joint = rigModel:FindFirstChild(jointName, true)
	if not joint or not joint:IsA("Motor6D") or not joint.Part0 then
		return nil
	end

	return joint.Part0.CFrame * joint.C0
end

function ViewmodelController:_ensureLabDebugMarker(markerName, color)
	local marker = self.LabDebugMarkers[markerName]
	if marker and marker.Parent then
		return marker
	end

	marker = Instance.new("Part")
	marker.Name = markerName
	marker.Size = DEBUG_MARKER_SIZE
	marker.Shape = Enum.PartType.Ball
	marker.Material = Enum.Material.Neon
	marker.Color = color
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = Workspace

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(120, 18)
	label.StudsOffset = Vector3.new(0, 0.18, 0)
	label.AlwaysOnTop = true
	label.Parent = marker

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.5
	text.Text = markerName
	text.Parent = label

	self.LabDebugMarkers[markerName] = marker
	return marker
end

function ViewmodelController:_updateLabDebugMarkers()
	if not self.LabEnabled or not self.LabDebugPointsEnabled then
		self:_destroyLabDebugMarkers()
		return
	end

	local markerSpecs = {
		{
			Name = "Runtime_Aim",
			Attachment = self.ActiveAimAttachment,
			Color = Color3.fromRGB(99, 196, 255),
		},
		{
			Name = "Runtime_RightHand",
			Attachment = self.ActiveRightHandAttachment,
			Color = Color3.fromRGB(255, 138, 138),
		},
		{
			Name = "Runtime_LeftHand",
			Attachment = self.ActiveLeftHandAttachment,
			Color = Color3.fromRGB(138, 255, 180),
		},
		{
			Name = "Runtime_Muzzle",
			Attachment = self.ActiveMuzzleAttachment,
			Color = Color3.fromRGB(255, 220, 110),
		},
		{
			Name = "Runtime_RightSocket",
			Attachment = self:_getRigHandSocket("RightArm"),
			Color = Color3.fromRGB(255, 88, 88),
		},
		{
			Name = "Runtime_LeftSocket",
			Attachment = self:_getRigHandSocket("LeftArm"),
			Color = Color3.fromRGB(88, 255, 146),
		},
		{
			Name = "Runtime_RightShoulder",
			CFrame = self:_getJointWorldCFrame(self.ActiveRig, "RightShoulder"),
			Color = Color3.fromRGB(255, 96, 96),
		},
		{
			Name = "Runtime_LeftShoulder",
			CFrame = self:_getJointWorldCFrame(self.ActiveRig, "LeftShoulder"),
			Color = Color3.fromRGB(96, 255, 160),
		},
		{
			Name = "Static_Aim",
			Attachment = self:_getStaticAttachment("Aim"),
			Color = Color3.fromRGB(66, 140, 255),
		},
		{
			Name = "Static_RightHand",
			Attachment = self:_getStaticAttachment("RightHand"),
			Color = Color3.fromRGB(214, 88, 88),
		},
		{
			Name = "Static_LeftHand",
			Attachment = self:_getStaticAttachment("LeftHand"),
			Color = Color3.fromRGB(88, 214, 126),
		},
		{
			Name = "Static_Muzzle",
			Attachment = self:_getStaticAttachment("Muzzle"),
			Color = Color3.fromRGB(214, 184, 88),
		},
		{
			Name = "Static_RightSocket",
			Attachment = self:_getStaticRigHandSocket("RightArm"),
			Color = Color3.fromRGB(176, 66, 66),
		},
		{
			Name = "Static_LeftSocket",
			Attachment = self:_getStaticRigHandSocket("LeftArm"),
			Color = Color3.fromRGB(66, 176, 104),
		},
		{
			Name = "Static_RightShoulder",
			CFrame = self:_getJointWorldCFrame(self.LabStaticRig, "RightShoulder"),
			Color = Color3.fromRGB(184, 76, 76),
		},
		{
			Name = "Static_LeftShoulder",
			CFrame = self:_getJointWorldCFrame(self.LabStaticRig, "LeftShoulder"),
			Color = Color3.fromRGB(76, 184, 116),
		},
	}

	local activeMarkers = {}
	for _, spec in ipairs(markerSpecs) do
		local attachment = spec.Attachment
		local markerCFrame = spec.CFrame
		if attachment and attachment.Parent then
			markerCFrame = attachment.WorldCFrame
		end

		if markerCFrame then
			local marker = self:_ensureLabDebugMarker(spec.Name, spec.Color)
			marker.CFrame = markerCFrame
			activeMarkers[spec.Name] = true
		end
	end

	for markerName, marker in pairs(self.LabDebugMarkers) do
		if marker and marker.Parent and not activeMarkers[markerName] then
			marker:Destroy()
			self.LabDebugMarkers[markerName] = nil
		end
	end
end

function ViewmodelController:_resolveHandShoulderC0(joint, handAttachment, fallbackC0)
	local jointRoot = joint and joint.Part0
	if not jointRoot or not handAttachment or not handAttachment.Parent then
		return fallbackC0
	end

	return CFrame.new(jointRoot.CFrame:PointToObjectSpace(handAttachment.WorldPosition))
end

function ViewmodelController:_getArmLocalHandOffset(arm)
	if not arm then
		return Vector3.zero
	end

	local rigHandSocket = self:_getRigHandSocket(arm.Name)
	if rigHandSocket and rigHandSocket.Parent then
		return arm.CFrame:PointToObjectSpace(rigHandSocket.WorldPosition)
	end

	local handOffset
	if self.HybridFirearmActive then
		-- The current firearm rig is still a single-part arm, not a forearm/hand chain.
		-- Shorten the effective wrist point for firearm grips so the primary hand can
		-- actually reach a pistol grip without needing impossible arm length.
		handOffset = arm.Name == "RightArm" and RIGHT_FIREARM_HAND_END_LOCAL_OFFSET or LEFT_FIREARM_HAND_END_LOCAL_OFFSET
	else
		handOffset = arm.Name == "RightArm" and RIGHT_HAND_END_LOCAL_OFFSET or LEFT_HAND_END_LOCAL_OFFSET
	end

	return Vector3.new(
		handOffset.X * math.max(0.5, arm.Size.X),
		handOffset.Y * math.max(0.5, arm.Size.Y),
		handOffset.Z * math.max(0.5, arm.Size.Z)
	)
end

function ViewmodelController:_getArmLocalShoulderOffset(arm)
	if not arm then
		return Vector3.zero
	end

	return Vector3.new(0, arm.Size.Y * 0.5, 0)
end

function ViewmodelController:_buildProceduralArmRotation(shoulderRoot, shoulderWorldPosition, targetAttachment, sideSign)
	-- This is intentionally a single-arm-part procedural solve, not a full elbow/wrist IK chain.
	-- The shoulder stays body-anchored and we derive one believable arm orientation from the
	-- target attachment plus a default bend plane.
	if not shoulderRoot then
		return nil
	end

	local targetWorldPosition = targetAttachment.WorldPosition
	local shoulderToTarget = targetWorldPosition - shoulderWorldPosition
	local targetDirection = _safeUnit(shoulderToTarget, -(shoulderRoot.CFrame.UpVector))
	local yAxis = -targetDirection

	local bendReference = (
		(shoulderRoot.CFrame.RightVector * sideSign)
		+ (shoulderRoot.CFrame.UpVector * -0.35)
		+ (shoulderRoot.CFrame.LookVector * -0.55)
	)
	bendReference = _safeUnit(bendReference, shoulderRoot.CFrame.LookVector)

	if math.abs(yAxis:Dot(bendReference)) > 0.98 then
		bendReference = _safeUnit(
			shoulderRoot.CFrame.LookVector + (shoulderRoot.CFrame.RightVector * sideSign * 0.25),
			shoulderRoot.CFrame.LookVector
		)
	end

	local xAxis = _safeUnit(bendReference:Cross(yAxis), shoulderRoot.CFrame.RightVector * sideSign)
	local zAxis = _safeUnit(xAxis:Cross(yAxis), shoulderRoot.CFrame.LookVector)
	xAxis = _safeUnit(yAxis:Cross(zAxis), shoulderRoot.CFrame.RightVector * sideSign)

	return CFrame.fromMatrix(Vector3.zero, xAxis, yAxis, zAxis)
end

function ViewmodelController:_resolveFirearmArmSolveCorrection(shoulder, arm, baseC0, targetAttachmentName, influenceAlpha, correctionKey, sideSign)
	-- Runtime firearm posing is authoritative here for v1:
	-- weapon pose comes from HeldItemJoint/ADS offsets, and this solve adapts the arm to that
	-- weapon pose without moving the shoulder origin off the torso.
	if not shoulder or not arm or not self.ActiveHeldModel then
		return nil, false
	end

	local targetAttachment = self:_getHeldTargetAttachment(targetAttachmentName)
	if not targetAttachment then
		return nil, false
	end

	local shoulderRoot = shoulder.Part0
	if not shoulderRoot then
		return nil, false
	end

	local solveInfluence = math.clamp(tonumber(influenceAlpha) or 0, 0, 1)
	if solveInfluence <= 0 then
		return nil, true
	end

	local shoulderWorldPosition = shoulderRoot.CFrame:PointToWorldSpace(baseC0.Position)
	local desiredRotation = self:_buildProceduralArmRotation(shoulderRoot, shoulderWorldPosition, targetAttachment, sideSign)
	if not desiredRotation then
		return nil, true
	end

	local localShoulderOffset = self:_getArmLocalShoulderOffset(arm)
	local localHandOffset = self:_getArmLocalHandOffset(arm)
	local desiredArmPosition = targetAttachment.WorldPosition - desiredRotation:VectorToWorldSpace(localHandOffset)
	local desiredArmWorldCFrame = CFrame.fromMatrix(
		desiredArmPosition,
		desiredRotation.XVector,
		desiredRotation.YVector,
		desiredRotation.ZVector
	)

	local baseTransform = self:_getBaseJointTransform(shoulder, correctionKey)
	local baseArmWorldCFrame = shoulderRoot.CFrame * baseC0 * baseTransform
	local desiredCorrection = baseArmWorldCFrame:ToObjectSpace(desiredArmWorldCFrame)
	local influencedCorrection = CFrame.new():Lerp(desiredCorrection, solveInfluence)

	local predictedShoulderWorldPosition = desiredArmWorldCFrame:PointToWorldSpace(localShoulderOffset)
	local shoulderErrorWorld = shoulderWorldPosition - predictedShoulderWorldPosition
	local shoulderErrorLocal = shoulderRoot.CFrame:VectorToObjectSpace(shoulderErrorWorld)
	local shoulderErrorCompensation = CFrame.new(shoulderErrorLocal * 0.2 * solveInfluence)

	local predictedHandWorldPosition = desiredArmWorldCFrame:PointToWorldSpace(localHandOffset)
	local handErrorWorld = targetAttachment.WorldPosition - predictedHandWorldPosition
	local handErrorLocal = shoulderRoot.CFrame:VectorToObjectSpace(handErrorWorld)
	local handErrorCompensation = CFrame.new(handErrorLocal * 0.15 * solveInfluence)

	return influencedCorrection * shoulderErrorCompensation * handErrorCompensation, true
end

function ViewmodelController:_resolveRightHandIkCorrection(definition, rightShoulder)
	if not rightShoulder then
		return nil, false
	end

	local arm = rightShoulder.Part1
	local baseC0 = CFrame.new(RIGHT_FIREARM_SHOULDER_OFFSET.Position)
	local alpha = tonumber(definition and definition.RightHandIkAlpha) or 0
	local targetName = (definition and definition.RightHandIkTargetName) or "RightHand"
	return self:_resolveFirearmArmSolveCorrection(rightShoulder, arm, baseC0, targetName, alpha, "RightShoulder", 1)
end

function ViewmodelController:_resolveLeftHandIkCorrection(definition, leftShoulder)
	if not leftShoulder then
		return nil, false
	end

	local arm = leftShoulder.Part1
	local baseC0 = CFrame.new(LEFT_FIREARM_SHOULDER_OFFSET.Position)
	local alpha = tonumber(definition and definition.LeftHandIkAlpha) or 0.85
	local targetName = (definition and definition.LeftHandIkTargetName) or "LeftHand"
	return self:_resolveFirearmArmSolveCorrection(leftShoulder, arm, baseC0, targetName, alpha, "LeftShoulder", -1)
end

function ViewmodelController:_resolveHeldItemC0(definition, isAiming)
	local baseGripOffset = definition and definition.ViewmodelGripOffset or CFrame.new()
	if not isAiming or not self.ActiveRig or not self.ActiveHeldModel or not self.ActiveAimAttachment or not self.ActiveAimAttachment.Parent then
		return baseGripOffset
	end

	local weaponRoot = self.ActiveRig:FindFirstChild("WeaponRoot")
	local heldRoot = self.ActiveHeldModel.PrimaryPart
	if not weaponRoot or not heldRoot then
		return baseGripOffset
	end

	local aimOffset = (definition and definition.ViewmodelAimOffset) or DEFAULT_AIM_WORLD_OFFSET
	local desiredAimWorldCFrame = self.World.Camera.CFrame * aimOffset
	local aimRelativeToHeldRoot = heldRoot.CFrame:ToObjectSpace(self.ActiveAimAttachment.WorldCFrame)
	local desiredHeldRootWorldCFrame = desiredAimWorldCFrame * aimRelativeToHeldRoot:Inverse()
	return weaponRoot.CFrame:ToObjectSpace(desiredHeldRootWorldCFrame)
end

function ViewmodelController:_mountItem(entry, definition)
	if not self.ActiveRig then
		return
	end

	local existing = self.ActiveRig:FindFirstChild("HeldItem")
	if existing then
		existing:Destroy()
	end
	local weaponRoot = self.ActiveRig:FindFirstChild("WeaponRoot")
	if weaponRoot then
		local existingJoint = weaponRoot:FindFirstChild("HeldItemJoint")
		if existingJoint then
			existingJoint:Destroy()
		end
	end
	self:_cacheHeldItemHandles(nil)

	local authoredAsset = self:_resolveViewmodelAsset(entry, definition)
	if definition and definition.ViewmodelAssetId and not authoredAsset then
		DebugLog:Log("ClientCombat", string.format("[ViewmodelController] Missing viewmodel asset '%s' for %s", tostring(definition.ViewmodelAssetId), tostring(entry.WeaponId)))
	end
	local itemModel = self:_prepareAuthoredItemModel(authoredAsset) or self:_createFallbackItemModel(entry, definition)
	itemModel.Parent = self.ActiveRig
	self:_cacheHeldItemHandles(itemModel)

	local core = itemModel.PrimaryPart
	if not weaponRoot or not core then
		return
	end

	local joint = Instance.new("Motor6D")
	joint.Name = "HeldItemJoint"
	joint.Part0 = weaponRoot
	joint.Part1 = core
	joint.C0 = definition and definition.ViewmodelGripOffset or CFrame.new()
	joint.Parent = weaponRoot

	self.HybridFirearmActive = definition and definition.Kind == "Firearm" or false
	self:_loadAnimationTracks(definition)
	if self.LabEnabled and self.LabAutoRefreshStatic then
		if self.LabStaticRig then
			self:_syncLabStaticRigFromActiveRig()
		else
			self:CaptureLabStaticRig()
		end
	end
end

function ViewmodelController:_ensureRig(entry, definition)
	if not self.ActiveRig then
		self.ActiveRig = self:_createRig()
	end

	if self.ActiveItemId ~= entry.WeaponId or self.ActiveEntryType ~= entry.EntryType then
		self.ActiveItemId = entry.WeaponId
		self.ActiveEntryType = entry.EntryType
		self:_mountItem(entry, definition)
		self:PlayAction("Equip")
	end
end

function ViewmodelController:_setBodyHidden(hidden)
	if not self.Character then
		return
	end

	if self.IsBodyHidden == hidden then
		return
	end

	self.IsBodyHidden = hidden
	for _, descendant in ipairs(self.Character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Name == "HumanoidRootPart" then
				descendant.LocalTransparencyModifier = 1
			else
				descendant.LocalTransparencyModifier = hidden and 1 or 0
			end
		end
	end
end

function ViewmodelController:_getDesiredLoopAction(combatState)
	if self.LabEnabled and self.LabLoopOverride then
		return self.LabLoopOverride
	end

	return (combatState and combatState.IsAiming == true) and "Aim" or "Idle"
end

function ViewmodelController:_updateActionState()
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	if not combatState then
		self.LastCombatSnapshot = nil
		return
	end

	local previous = self.LastCombatSnapshot or {}
	local desiredLoopAction = self:_getDesiredLoopAction(combatState)
	if combatState.IsReloading and not previous.IsReloading then
		self:PlayAction("Reload")
	elseif previous.IsReloading == nil and previous.LoopAction == nil then
		self:PlayAction(desiredLoopAction)
	elseif desiredLoopAction ~= previous.LoopAction then
		self:PlayAction(desiredLoopAction)
	end

	self.LastCombatSnapshot = {
		IsReloading = combatState.IsReloading == true,
		IsAiming = desiredLoopAction == "Aim",
		LoopAction = desiredLoopAction,
	}
end

function ViewmodelController:_updateRigPose(entry, definition)
	if not self.ActiveRig then
		return
	end

	local root = self.ActiveRig.PrimaryPart
	if not root then
		return
	end

	local camera = self.World.Camera
	local cameraCFrame = camera.CFrame * VIEWMODEL_OFFSET
	root.CFrame = cameraCFrame

	local rightShoulder = self.ActiveRig:FindFirstChild("RightShoulder", true)
	local leftShoulder = self.ActiveRig:FindFirstChild("LeftShoulder", true)
	local weaponJoint = self.ActiveRig:FindFirstChild("WeaponJoint", true)
	local combatState = self.CombatController and self.CombatController:GetState() or nil
	local aiming = self:_getDesiredLoopAction(combatState) == "Aim"
	local hasAnimationTracks = self.HybridFirearmActive and self:_hasLoadedAnimationTracks()
	local isFirearm = definition and definition.Kind == "Firearm"
	local rightBaseC0 = isFirearm and RIGHT_FIREARM_SHOULDER_OFFSET or CFrame.new(RIGHT_HAND_OFFSET.Position)
	local leftBaseC0 = isFirearm and LEFT_FIREARM_SHOULDER_OFFSET or CFrame.new(LEFT_HAND_OFFSET.Position)
	local rightTargetAvailable = false
	local leftTargetAvailable = false

	if rightShoulder then
		rightShoulder.C0 = rightBaseC0
	end
	if leftShoulder then
		leftShoulder.C0 = leftBaseC0
	end

	if rightShoulder then
		if isFirearm then
			local rightCorrection
			rightCorrection, rightTargetAvailable = self:_resolveRightHandIkCorrection(definition, rightShoulder)
			local currentRightCorrection = self.LastAppliedJointCorrections.RightShoulder or CFrame.new()
			local blendedRightCorrection = self:_blendCFrame(currentRightCorrection, rightCorrection or CFrame.new(), ARM_SOLVE_BLEND_ALPHA)
			self:_applyJointCorrection(rightShoulder, "RightShoulder", blendedRightCorrection)
		elseif hasAnimationTracks then
			self:_clearJointCorrection(rightShoulder, "RightShoulder")
		else
			self:_clearJointCorrection(rightShoulder, "RightShoulder")
			rightShoulder.C0 = self:_resolveHandShoulderC0(rightShoulder, self.ActiveRightHandAttachment, RIGHT_HAND_OFFSET)
		end
	end
	if leftShoulder then
		if isFirearm then
			local leftCorrection
			leftCorrection, leftTargetAvailable = self:_resolveLeftHandIkCorrection(definition, leftShoulder)
			local currentCorrection = self.LastAppliedJointCorrections.LeftShoulder or CFrame.new()
			local blendedCorrection = self:_blendCFrame(currentCorrection, leftCorrection or CFrame.new(), ARM_SOLVE_BLEND_ALPHA)
			self:_applyJointCorrection(leftShoulder, "LeftShoulder", blendedCorrection)
		elseif hasAnimationTracks then
			self:_clearJointCorrection(leftShoulder, "LeftShoulder")
		else
			self:_clearJointCorrection(leftShoulder, "LeftShoulder")
			leftShoulder.C0 = self:_resolveHandShoulderC0(leftShoulder, self.ActiveLeftHandAttachment, LEFT_HAND_OFFSET)
		end
	end
	if weaponJoint then
		local sway = aiming and CFrame.new(0, 0.02, -0.05) or CFrame.new()
		local currentWeaponCorrection = self.LastAppliedJointCorrections.WeaponJoint or CFrame.new()
		local blendedWeaponCorrection = self:_blendCFrame(currentWeaponCorrection, sway, WEAPON_JOINT_BLEND_ALPHA)
		self:_applyJointCorrection(weaponJoint, "WeaponJoint", blendedWeaponCorrection)
	end

	local heldJoint = self:_getHeldItemJoint()
	if heldJoint then
		local baseGripOffset = definition and definition.ViewmodelGripOffset or CFrame.new()
		local desiredGripOffset = self:_resolveHeldItemC0(definition, aiming)
		heldJoint.C0 = self:_blendCFrame(heldJoint.C0, desiredGripOffset, HELD_ITEM_BLEND_ALPHA)
		self.LastAppliedJointCorrections.HeldItemJoint = baseGripOffset:Inverse() * heldJoint.C0
	end

	self.LastFirearmIkStatus = {
		Active = isFirearm,
		RightTargetAvailable = rightTargetAvailable,
		LeftTargetAvailable = leftTargetAvailable,
		RightInfluence = tonumber(definition and definition.RightHandIkAlpha) or 0,
		LeftInfluence = tonumber(definition and definition.LeftHandIkAlpha) or 0,
	}

	self.ActiveRig:SetAttribute("CurrentItemId", entry.WeaponId)
end

function ViewmodelController:_update()
	local shouldShow = self:IsFirstPersonActive()
	local shouldLab = self.LabEnabled == true
	local shouldShowSourceRig = shouldLab and self.LabShowSourceRig == true
	local shouldRenderSourceRig = shouldLab and shouldShowSourceRig or (not shouldLab and shouldShow)
	local entry = (shouldLab and self:_getLabEntry()) or self:_getEquippedEntry()
	local definition = self:_getDefinitionForEntry(entry)

	if (not shouldShow and not shouldLab) or not entry or not definition then
		self:_setBodyHidden(false)
		self:_setRigVisible(false)
		if self.ActiveRig then
			self.ActiveRig.Parent = nil
		end
		self.ActiveItemId = nil
		self.ActiveEntryType = nil
		self:_cacheHeldItemHandles(nil)
		self:_clearLoadedAnimationTracks()
		self.LastAppliedJointCorrections = {}
		self.HybridFirearmActive = false
		self.LastCombatSnapshot = nil
		self.LastFirearmIkStatus = {
			Active = false,
			RightTargetAvailable = false,
			LeftTargetAvailable = false,
			RightInfluence = 0,
			LeftInfluence = 0,
		}
		self:_destroyLabPreview()
		self:_updateLabDebugMarkers()
		return
	end

	self:_setBodyHidden(shouldShow)
	self:_ensureRig(entry, definition)
	if self.ActiveRig then
		local desiredParent = shouldLab
			and (shouldShowSourceRig and Workspace or nil)
			or self.World.Camera
		if self.ActiveRig.Parent ~= desiredParent then
			self.ActiveRig.Parent = desiredParent
		end
	end
	self:_setRigVisible(shouldRenderSourceRig)

	self:_updateRigPose(entry, definition)
	self:_updateActionState()
	if shouldLab and self.LabAutoRefreshStatic and self.LabStaticRig then
		self:_syncLabStaticRigFromActiveRig()
	else
		self:_destroyLabPreview()
	end
	self:_updateLabDebugMarkers()
end

return ViewmodelController
