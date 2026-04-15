local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FirearmAim = require(ReplicatedStorage.Shared.Utility.FirearmAim)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local FirearmPresentationController = {}
FirearmPresentationController.Name = "FirearmPresentationController"
FirearmPresentationController.Dependencies = {
	"CameraInputController",
	"CombatController",
	"ViewmodelController",
}

function FirearmPresentationController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.CombatShotVisualRemote = self.Remotes:WaitForChild(RemoteNames.CombatShotVisual)
	self.ReticleExpansion = 0
end

function FirearmPresentationController:Start()
	self.CombatShotVisualRemote.OnClientEvent:Connect(function(payload)
		self:_playShotPresentation(payload)
	end)

	RunService:BindToRenderStep("FirearmPresentationController.Update", Enum.RenderPriority.Last.Value, function(deltaTime)
		self.ReticleExpansion = math.max(0, self.ReticleExpansion - (deltaTime * 3.4))
	end)

	DebugLog:Log("ClientCombat", "[FirearmPresentationController] Started")
end

function FirearmPresentationController:GetReticleExpansion()
	return self.ReticleExpansion or 0
end

function FirearmPresentationController:_tweenAndCleanup(instance, tweenInfo, properties, lifetime)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	Debris:AddItem(instance, lifetime)
end

function FirearmPresentationController:_createBillowedPart(name, color, size, cframe, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = Workspace
	return part
end

function FirearmPresentationController:_playShotPresentation(payload)
	if type(payload) ~= "table" or typeof(payload.Origin) ~= "Vector3" or typeof(payload.EndPosition) ~= "Vector3" then
		return
	end

	local weaponDefinition = WeaponDefinitions[payload.WeaponId]
	local handling = FirearmAim.GetHandlingData(weaponDefinition)
	local color = handling.FireVisualColor
	local origin = (self.ViewmodelController and self.ViewmodelController:GetVisualMuzzleOrigin(payload.WeaponId)) or payload.Origin
	local endPosition = payload.EndPosition
	local isAiming = payload.IsAiming == true
	local hit = payload.Hit == true
	local direction = endPosition - origin
	local distance = direction.Magnitude
	if distance <= 0.05 then
		return
	end

	local tracerWidth = handling.TracerWidth * (isAiming and 0.9 or 1.15)
	local tracer = self:_createBillowedPart(
		"FirearmTracer",
		hit and Color3.fromRGB(136, 236, 170) or color,
		Vector3.new(tracerWidth, tracerWidth, distance),
		CFrame.lookAt(origin, endPosition) * CFrame.new(0, 0, -(distance * 0.5))
	)
	tracer.Transparency = 0.04
	self:_tweenAndCleanup(tracer, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	}, 0.14)

	local muzzleFlash = self:_createBillowedPart(
		"MuzzleFlash",
		color,
		Vector3.new(handling.MuzzleFlashSize, handling.MuzzleFlashSize, handling.MuzzleFlashSize),
		CFrame.new(origin)
	)
	muzzleFlash.Shape = Enum.PartType.Ball
	muzzleFlash.Transparency = 0.02
	self:_tweenAndCleanup(muzzleFlash, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = muzzleFlash.Size * 1.8,
		Transparency = 1,
	}, 0.1)

	local shellBurst = self:_createBillowedPart(
		"ShellBurst",
		Color3.fromRGB(255, 196, 105),
		Vector3.new(0.15, 0.15, 0.55),
		CFrame.lookAt(origin, origin + Vector3.new(1, 0.2, 0))
	)
	shellBurst.Transparency = 0.1
	self:_tweenAndCleanup(shellBurst, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = shellBurst.CFrame * CFrame.new(0.55, 0.12, -0.2),
		Transparency = 1,
	}, 0.12)

	local impactFlash = self:_createBillowedPart(
		"ImpactFlash",
		hit and Color3.fromRGB(145, 234, 181) or Color3.fromRGB(186, 214, 255),
		Vector3.new(handling.ImpactFlashSize, handling.ImpactFlashSize, handling.ImpactFlashSize),
		CFrame.new(endPosition)
	)
	impactFlash.Shape = Enum.PartType.Ball
	impactFlash.Transparency = 0.08
	self:_tweenAndCleanup(impactFlash, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = impactFlash.Size * 1.65,
		Transparency = 1,
	}, 0.12)

	if self.CameraInputController then
		self.CameraInputController:AddFirearmKick(
			(handling.CameraKickPitch or handling.RecoilKick) * (isAiming and 0.85 or 1),
			handling.CameraKickYaw or 0,
			handling.RecoilRecovery or 11
		)
	end
	if self.ViewmodelController then
		self.ViewmodelController:PlayAction("Fire")
	end

	self.ReticleExpansion = math.min(1.4, math.max(self.ReticleExpansion, 0) + (isAiming and 0.22 or 0.5))
end

return FirearmPresentationController
