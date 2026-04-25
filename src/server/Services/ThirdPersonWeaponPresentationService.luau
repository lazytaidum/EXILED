local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local ThirdPersonWeaponPresentationService = {}
ThirdPersonWeaponPresentationService.Name = "ThirdPersonWeaponPresentationService"
ThirdPersonWeaponPresentationService.Dependencies = {
	"CharacterService",
}

local ASSET_ROOT_NAME = "Assets"
local WEAPON_ASSET_FOLDER_NAME = "Weapons"
local WORLD_MODEL_FOLDER_NAMES = {
	"WorldModels",
	"Models",
	"Viewmodels",
}
local DEFAULT_ATTACH_PART_NAME = "Right Arm"
local DEFAULT_GRIP_ATTACHMENT_NAME = "Grip"
local DEFAULT_THIRD_PERSON_GRIP_OFFSET = CFrame.new(0, -0.95, -0.08) * CFrame.Angles(math.rad(90), 0, 0)
local DEFAULT_MUZZLE_DEPTH = 0.7
local EQUIPPED_MODEL_NAME = "ThirdPersonWeapon"
local EXTERNAL_JOINT_NAME = "EquippedWeaponJoint"

local function _getNormalizedAssetId(assetId)
	if type(assetId) ~= "string" or assetId == "" then
		return nil
	end

	return assetId
end

local function _getPrimaryPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local primaryPart = model.PrimaryPart
		or model:FindFirstChild("Root")
		or model:FindFirstChild("Handle")
		or model:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart and primaryPart:IsA("BasePart") then
		model.PrimaryPart = primaryPart
		return primaryPart
	end

	return nil
end

local function _findAttachment(model, attachmentName)
	if not model or type(attachmentName) ~= "string" or attachmentName == "" then
		return nil
	end

	local attachment = model:FindFirstChild(attachmentName, true)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	return nil
end

local function _partHasJoint(model, part)
	if not model or not part then
		return false
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 == part or part1 == part then
				return true
			end
		end
	end

	return false
end

local function _preparePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
end

function ThirdPersonWeaponPresentationService:Init()
	self.RuntimeByPlayer = {}
end

function ThirdPersonWeaponPresentationService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:_clearPlayerRuntime(player)
	end)

	DebugLog:Log("Character", "[ThirdPersonWeaponPresentationService] Started")
end

function ThirdPersonWeaponPresentationService:_getRuntime(player)
	local runtime = self.RuntimeByPlayer[player]
	if runtime then
		return runtime
	end

	runtime = {
		CharacterModel = nil,
		AttachPart = nil,
		CurrentCombatState = nil,
		EquippedWeaponId = nil,
		EquippedModel = nil,
		EquippedRoot = nil,
		MuzzleAttachment = nil,
	}
	self.RuntimeByPlayer[player] = runtime
	return runtime
end

function ThirdPersonWeaponPresentationService:_clearEquippedModel(runtime)
	if not runtime then
		return
	end

	local equippedModel = runtime.EquippedModel
	runtime.EquippedModel = nil
	runtime.EquippedRoot = nil
	runtime.MuzzleAttachment = nil
	runtime.EquippedWeaponId = nil

	if equippedModel and equippedModel.Parent then
		equippedModel:Destroy()
	end
end

function ThirdPersonWeaponPresentationService:_clearPlayerRuntime(player)
	local runtime = self.RuntimeByPlayer[player]
	if not runtime then
		return
	end

	self:_clearEquippedModel(runtime)
	self.RuntimeByPlayer[player] = nil
end

function ThirdPersonWeaponPresentationService:_bindCharacterRuntime(runtime, characterModel)
	self:_clearEquippedModel(runtime)

	runtime.CharacterModel = characterModel
	runtime.AttachPart = characterModel and characterModel:FindFirstChild(DEFAULT_ATTACH_PART_NAME) or nil
end

function ThirdPersonWeaponPresentationService:_getWeaponDefinitionFromCombatState(combatState)
	if type(combatState) ~= "table" then
		return nil
	end

	local weaponId = combatState.EquippedWeaponId
	local definition = weaponId and WeaponDefinitions[weaponId] or nil
	if not definition or definition.Kind ~= "Firearm" then
		return nil
	end

	return definition
end

function ThirdPersonWeaponPresentationService:_getWeaponAssetsFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSET_ROOT_NAME)
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild(WEAPON_ASSET_FOLDER_NAME)
end

function ThirdPersonWeaponPresentationService:_getAttachPartName(weaponDefinition)
	local attachPartName = weaponDefinition and weaponDefinition.ThirdPersonAttachPartName
	if type(attachPartName) ~= "string" or attachPartName == "" then
		return DEFAULT_ATTACH_PART_NAME
	end

	return attachPartName
end

function ThirdPersonWeaponPresentationService:_getGripAttachmentName(weaponDefinition)
	local attachmentName = weaponDefinition and weaponDefinition.ThirdPersonGripAttachmentName
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return DEFAULT_GRIP_ATTACHMENT_NAME
	end

	return attachmentName
end

function ThirdPersonWeaponPresentationService:_resolveWorldWeaponAsset(weaponDefinition)
	local weaponsFolder = self:_getWeaponAssetsFolder()
	if not weaponsFolder then
		return nil
	end

	local candidateAssetIds = {}
	local thirdPersonAssetId = _getNormalizedAssetId(weaponDefinition and weaponDefinition.ThirdPersonAssetId)
	local viewmodelAssetId = _getNormalizedAssetId(weaponDefinition and weaponDefinition.ViewmodelAssetId)
	if thirdPersonAssetId then
		table.insert(candidateAssetIds, thirdPersonAssetId)
	end
	if viewmodelAssetId and viewmodelAssetId ~= thirdPersonAssetId then
		table.insert(candidateAssetIds, viewmodelAssetId)
	end

	for _, folderName in ipairs(WORLD_MODEL_FOLDER_NAMES) do
		local folder = weaponsFolder:FindFirstChild(folderName)
		if folder then
			for _, assetId in ipairs(candidateAssetIds) do
				local asset = folder:FindFirstChild(assetId)
				if asset and asset:IsA("Model") then
					return asset
				end
			end
		end
	end

	return nil
end

function ThirdPersonWeaponPresentationService:_ensureModelJoints(model, root)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			_preparePart(descendant)
			if descendant ~= root and not _partHasJoint(model, descendant) then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "AutoWeld"
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = root
			end
		end
	end
end

function ThirdPersonWeaponPresentationService:_ensureMuzzleAttachment(model, root)
	local muzzleAttachment = _findAttachment(model, "Muzzle")
	if muzzleAttachment then
		return muzzleAttachment
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "Muzzle"
	attachment.Position = Vector3.new(0, 0, -math.max(DEFAULT_MUZZLE_DEPTH, root.Size.Z * 0.5))
	attachment.Parent = root
	return attachment
end

function ThirdPersonWeaponPresentationService:_ensureGripAttachment(model, root, weaponDefinition)
	local gripAttachmentName = self:_getGripAttachmentName(weaponDefinition)
	local gripAttachment = _findAttachment(model, gripAttachmentName)
	if gripAttachment then
		return gripAttachment
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = gripAttachmentName
	attachment.CFrame = weaponDefinition and weaponDefinition.ThirdPersonGripOffset or DEFAULT_THIRD_PERSON_GRIP_OFFSET
	attachment.Parent = root
	return attachment
end

function ThirdPersonWeaponPresentationService:_prepareAuthoredWeaponModel(assetModel, weaponDefinition)
	if not assetModel or not assetModel:IsA("Model") then
		return nil
	end

	local clone = assetModel:Clone()
	clone.Name = EQUIPPED_MODEL_NAME

	local root = _getPrimaryPart(clone)
	if not root then
		clone:Destroy()
		return nil
	end

	self:_ensureModelJoints(clone, root)
	local muzzleAttachment = self:_ensureMuzzleAttachment(clone, root)
	local gripAttachment = self:_ensureGripAttachment(clone, root, weaponDefinition)

	return clone, root, muzzleAttachment, gripAttachment
end

function ThirdPersonWeaponPresentationService:_createFallbackWeaponModel(weaponDefinition)
	local model = Instance.new("Model")
	model.Name = EQUIPPED_MODEL_NAME

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 1)
	root.Transparency = 1
	root.Parent = model

	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Size = Vector3.new(0.28, 0.2, 0.72)
	frame.Color = Color3.fromRGB(42, 42, 48)
	frame.Material = Enum.Material.Metal
	frame.Parent = model

	local slide = Instance.new("Part")
	slide.Name = "Slide"
	slide.Size = Vector3.new(0.22, 0.14, 0.54)
	slide.Color = Color3.fromRGB(86, 88, 94)
	slide.Material = Enum.Material.Metal
	slide.Parent = model

	local grip = Instance.new("Part")
	grip.Name = "GripBody"
	grip.Size = Vector3.new(0.18, 0.44, 0.2)
	grip.Color = Color3.fromRGB(28, 28, 32)
	grip.Material = Enum.Material.SmoothPlastic
	grip.Parent = model

	model.PrimaryPart = root

	frame.CFrame = root.CFrame
	slide.CFrame = root.CFrame * CFrame.new(0, 0.1, -0.04)
	grip.CFrame = root.CFrame * CFrame.new(0, -0.24, 0.2) * CFrame.Angles(math.rad(-18), 0, 0)

	self:_ensureModelJoints(model, root)

	local muzzleAttachment = Instance.new("Attachment")
	muzzleAttachment.Name = "Muzzle"
	muzzleAttachment.Position = Vector3.new(0, 0.02, -0.72)
	muzzleAttachment.Parent = root

	local gripAttachment = self:_ensureGripAttachment(model, root, weaponDefinition)

	return model, root, muzzleAttachment, gripAttachment
end

function ThirdPersonWeaponPresentationService:_resolveAttachPart(runtime, weaponDefinition)
	if not runtime or not runtime.CharacterModel then
		return nil
	end

	local attachPart = runtime.CharacterModel:FindFirstChild(self:_getAttachPartName(weaponDefinition))
	if attachPart and attachPart:IsA("BasePart") then
		runtime.AttachPart = attachPart
		return attachPart
	end

	return nil
end

function ThirdPersonWeaponPresentationService:_getDesiredGripCFrame(attachPart, weaponDefinition)
	local gripOffset = weaponDefinition and weaponDefinition.ThirdPersonGripOffset or DEFAULT_THIRD_PERSON_GRIP_OFFSET
	return attachPart.CFrame * gripOffset
end

function ThirdPersonWeaponPresentationService:_attachWeaponModel(runtime, weaponDefinition)
	if not runtime or not runtime.CharacterModel or not runtime.CharacterModel.Parent then
		return
	end

	local attachPart = self:_resolveAttachPart(runtime, weaponDefinition)
	if not attachPart then
		return
	end

	self:_clearEquippedModel(runtime)

	local weaponModel, weaponRoot, muzzleAttachment, gripAttachment
	local authoredAsset = self:_resolveWorldWeaponAsset(weaponDefinition)
	if authoredAsset then
		weaponModel, weaponRoot, muzzleAttachment, gripAttachment = self:_prepareAuthoredWeaponModel(authoredAsset, weaponDefinition)
	end
	if not weaponModel then
		weaponModel, weaponRoot, muzzleAttachment, gripAttachment = self:_createFallbackWeaponModel(weaponDefinition)
	end
	if not weaponModel or not weaponRoot then
		return
	end

	weaponModel.Parent = runtime.CharacterModel

	local desiredGripCFrame = self:_getDesiredGripCFrame(attachPart, weaponDefinition)
	if gripAttachment then
		local gripRelativeToRoot = weaponRoot.CFrame:ToObjectSpace(gripAttachment.WorldCFrame)
		weaponRoot.CFrame = desiredGripCFrame * gripRelativeToRoot:Inverse()
	else
		weaponRoot.CFrame = desiredGripCFrame
	end

	local externalJoint = Instance.new("Motor6D")
	externalJoint.Name = EXTERNAL_JOINT_NAME
	externalJoint.Part0 = attachPart
	externalJoint.Part1 = weaponRoot
	externalJoint.C0 = attachPart.CFrame:ToObjectSpace(weaponRoot.CFrame)
	externalJoint.C1 = CFrame.new()
	externalJoint.Parent = weaponRoot

	runtime.EquippedWeaponId = weaponDefinition.Id
	runtime.EquippedModel = weaponModel
	runtime.EquippedRoot = weaponRoot
	runtime.MuzzleAttachment = muzzleAttachment
end

function ThirdPersonWeaponPresentationService:_applyCombatState(player, currentState)
	local runtime = self:_getRuntime(player)
	runtime.CurrentCombatState = currentState

	local definition = self:_getWeaponDefinitionFromCombatState(currentState)
	if not definition then
		self:_clearEquippedModel(runtime)
		return
	end

	if not runtime.CharacterModel or not runtime.CharacterModel.Parent or not runtime.AttachPart or not runtime.AttachPart.Parent then
		local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player) or nil
		local characterModel = character and character.Model or nil
		if not characterModel then
			return
		end

		self:_bindCharacterRuntime(runtime, characterModel)
	end

	if not self:_resolveAttachPart(runtime, definition) then
		return
	end

	local shouldReattach = runtime.EquippedWeaponId ~= definition.Id
		or runtime.EquippedModel == nil
		or runtime.EquippedModel.Parent ~= runtime.CharacterModel
	if shouldReattach then
		self:_attachWeaponModel(runtime, definition)
	end
end

function ThirdPersonWeaponPresentationService:HandleCombatStateChanged(player, _previousState, currentState)
	self:_applyCombatState(player, currentState)
end

function ThirdPersonWeaponPresentationService:HandleCharacterAdded(player, character)
	local runtime = self:_getRuntime(player)
	local characterModel = character and character.Model or character
	if not characterModel then
		return
	end

	self:_bindCharacterRuntime(runtime, characterModel)
	if runtime.CurrentCombatState then
		self:_applyCombatState(player, runtime.CurrentCombatState)
	end
end

function ThirdPersonWeaponPresentationService:HandleCharacterRemoving(player, characterModel)
	local runtime = self.RuntimeByPlayer[player]
	if not runtime or runtime.CharacterModel ~= characterModel then
		return
	end

	self:_clearEquippedModel(runtime)
	runtime.CharacterModel = nil
	runtime.AttachPart = nil
end

function ThirdPersonWeaponPresentationService:GetMuzzleOrigin(player)
	local runtime = self.RuntimeByPlayer[player]
	if not runtime then
		return nil
	end

	local muzzleAttachment = runtime.MuzzleAttachment
	if muzzleAttachment and muzzleAttachment.Parent then
		return muzzleAttachment.WorldPosition
	end

	local weaponRoot = runtime.EquippedRoot
	if weaponRoot and weaponRoot.Parent then
		return weaponRoot.Position + (weaponRoot.CFrame.LookVector * DEFAULT_MUZZLE_DEPTH)
	end

	return nil
end

return ThirdPersonWeaponPresentationService
