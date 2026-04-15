local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityAbilityVisualController = {}
EntityAbilityVisualController.Name = "EntityAbilityVisualController"

local function _setModelLocalTransparency(model, transparency)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = transparency
		end
	end
end

local function _createVisualClone(model)
	local clone = model:Clone()
	clone.Name = model.Name .. "_BlindHungerVisual"

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end

	return clone
end

local function _resolveEntityModel(payload)
	local entityModel = payload.EntityModel
	if typeof(entityModel) == "Instance" and entityModel:IsA("Model") then
		return entityModel
	end

	local entitiesFolder = Workspace:FindFirstChild("Entities")
	local startPosition = payload.StartPosition
	if not entitiesFolder or typeof(startPosition) ~= "Vector3" then
		return nil
	end

	local wantedEntityId = payload.EntityId
	local closestModel = nil
	local closestDistance = math.huge

	for _, candidate in ipairs(entitiesFolder:GetChildren()) do
		if candidate:IsA("Model") then
			local root = candidate.PrimaryPart or candidate:FindFirstChild("HumanoidRootPart")
			if root then
				local candidateEntityId = candidate:GetAttribute("EntityId") or candidate.Name
				if not wantedEntityId or candidateEntityId == wantedEntityId then
					local distance = (root.Position - startPosition).Magnitude
					if distance < closestDistance then
						closestDistance = distance
						closestModel = candidate
					end
				end
			end
		end
	end

	if closestDistance <= 12 then
		return closestModel
	end

	return nil
end

function EntityAbilityVisualController:Init()
	self.Remotes = self.World.Remotes
	self.VisualRemote = self.Remotes:WaitForChild(RemoteNames.EntityAbilityVisual)
	self.ActiveLunges = {}
end

function EntityAbilityVisualController:Start()
	self.VisualRemote.OnClientEvent:Connect(function(payload)
		self:_handleVisual(payload)
	end)

	RunService:BindToRenderStep("EntityAbilityVisualController.BlindHunger", Enum.RenderPriority.Camera.Value + 2, function(deltaTime)
		self:_updateLunges(deltaTime)
	end)

	DebugLog:Log("ClientCombat", "[EntityAbilityVisualController] Started")
end

function EntityAbilityVisualController:_handleVisual(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Type == "BlindHungerLunge" then
		self:_startBlindHungerLunge(payload)
	end
end

function EntityAbilityVisualController:_startBlindHungerLunge(payload)
	local startPosition = payload.StartPosition
	local endPosition = payload.EndPosition
	local duration = tonumber(payload.Duration)
	local leapHeight = tonumber(payload.LeapHeight) or 0
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" or not duration or duration <= 0 then
		return
	end

	local dashOffset = endPosition - startPosition
	if dashOffset.Magnitude <= 0.05 then
		return
	end

	self:_spawnBlindHungerDashOrb(startPosition, endPosition, duration, leapHeight)

	local entityModel = _resolveEntityModel(payload)
	if not entityModel or not entityModel:IsA("Model") then
		return
	end

	local rootPart = entityModel.PrimaryPart or entityModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	if self.ActiveLunges[entityModel] then
		self:_finishLunge(entityModel)
	end

	local visualClone = _createVisualClone(entityModel)
	local cloneRoot = visualClone.PrimaryPart or visualClone:FindFirstChild("HumanoidRootPart")
	if not cloneRoot then
		visualClone:Destroy()
		return
	end

	visualClone.Parent = Workspace
	visualClone:PivotTo(rootPart.CFrame)
	_setModelLocalTransparency(entityModel, 1)

	self.ActiveLunges[entityModel] = {
		Model = entityModel,
		RootPart = rootPart,
		VisualClone = visualClone,
		VisualRoot = cloneRoot,
		StartPosition = startPosition,
		EndPosition = endPosition,
		Direction = dashOffset.Unit,
		Duration = duration,
		Elapsed = 0,
		LeapHeight = leapHeight,
	}

	if DebugFlags.Enabled and DebugFlags.Entity and Workspace:GetAttribute("DebugUiEnabled") ~= false then
		self:_spawnBlindHungerDebugVisual(startPosition, endPosition, tonumber(payload.ContactRadius) or 0)
	end
end

function EntityAbilityVisualController:_spawnBlindHungerDashOrb(startPosition, endPosition, duration, leapHeight)
	local orb = Instance.new("Part")
	orb.Name = "BlindHungerDashOrb"
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 166, 84)
	orb.Transparency = 0.08
	orb.Size = Vector3.new(1.1, 1.1, 1.1)
	orb.Position = startPosition
	orb.Parent = Workspace

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not orb.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		elapsed += deltaTime
		local alpha = math.clamp(elapsed / math.max(duration, 0.01), 0, 1)
		local blendedPosition = startPosition:Lerp(endPosition, alpha)
		if leapHeight > 0 then
			local arcAlpha = math.sin(alpha * math.pi)
			blendedPosition += Vector3.new(0, math.pow(arcAlpha, 0.75) * leapHeight, 0)
		end
		orb.Position = blendedPosition

		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			orb:Destroy()
		end
	end)

	Debris:AddItem(orb, math.max(duration + 0.2, 0.6))
end

function EntityAbilityVisualController:_updateLunges(deltaTime)
	for model, lunge in pairs(self.ActiveLunges) do
		if not model.Parent or not lunge.RootPart or not lunge.RootPart.Parent or not lunge.VisualClone or not lunge.VisualClone.Parent then
			self:_finishLunge(model)
			continue
		end

		lunge.Elapsed += deltaTime
		local alpha = math.clamp(lunge.Elapsed / lunge.Duration, 0, 1)
		local flatPosition = lunge.StartPosition:Lerp(lunge.EndPosition, alpha)
		local blendedPosition = flatPosition
		if lunge.LeapHeight > 0 then
			local arcAlpha = math.sin(alpha * math.pi)
			blendedPosition += Vector3.new(0, math.pow(arcAlpha, 0.75) * lunge.LeapHeight, 0)
		end

		local lookTarget = blendedPosition + Vector3.new(lunge.Direction.X, 0, lunge.Direction.Z)
		lunge.VisualClone:PivotTo(CFrame.lookAt(blendedPosition, lookTarget))

		if alpha >= 1 then
			self:_finishLunge(model)
		end
	end
end

function EntityAbilityVisualController:_finishLunge(model)
	local lunge = self.ActiveLunges[model]
	if not lunge then
		return
	end

	if lunge.Model and lunge.Model.Parent then
		_setModelLocalTransparency(lunge.Model, 0)
	end

	if lunge.VisualClone and lunge.VisualClone.Parent then
		lunge.VisualClone:Destroy()
	end

	self.ActiveLunges[model] = nil
end

function EntityAbilityVisualController:_spawnBlindHungerDebugVisual(startPosition, endPosition, contactRadius)
	local dashOffset = endPosition - startPosition
	local dashDistance = dashOffset.Magnitude
	if dashDistance <= 0.05 then
		return
	end

	local visualsFolder = Workspace:FindFirstChild("EntityDebugVisuals")
	if not visualsFolder then
		visualsFolder = Instance.new("Folder")
		visualsFolder.Name = "EntityDebugVisuals"
		visualsFolder.Parent = Workspace
	end

	local linePart = Instance.new("Part")
	linePart.Name = "BlindHungerPath"
	linePart.Anchored = true
	linePart.CanCollide = false
	linePart.CanQuery = false
	linePart.CanTouch = false
	linePart.Material = Enum.Material.Neon
	linePart.Color = Color3.fromRGB(255, 168, 76)
	linePart.Transparency = 0.05
	linePart.Size = Vector3.new(0.7, 0.7, dashDistance)
	linePart.CFrame = CFrame.lookAt(startPosition, endPosition) * CFrame.new(0, 0, -(dashDistance * 0.5))
	linePart.Parent = visualsFolder

	local radiusPart = Instance.new("Part")
	radiusPart.Name = "BlindHungerRadius"
	radiusPart.Anchored = true
	radiusPart.CanCollide = false
	radiusPart.CanQuery = false
	radiusPart.CanTouch = false
	radiusPart.Shape = Enum.PartType.Ball
	radiusPart.Material = Enum.Material.Neon
	radiusPart.Color = Color3.fromRGB(255, 225, 125)
	radiusPart.Transparency = 0.45
	radiusPart.Size = Vector3.new(contactRadius * 2, contactRadius * 2, contactRadius * 2)
	radiusPart.Position = endPosition
	radiusPart.Parent = visualsFolder

	Debris:AddItem(linePart, 2.5)
	Debris:AddItem(radiusPart, 2.5)
end

return EntityAbilityVisualController
