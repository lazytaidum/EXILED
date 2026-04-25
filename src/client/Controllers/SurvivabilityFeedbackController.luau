local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local SurvivabilityFeedbackController = {}
SurvivabilityFeedbackController.Name = "SurvivabilityFeedbackController"

local HEARTBEAT_MIN_SCALE = 0.86
local HEARTBEAT_MAX_SCALE = 1.18
local HEARTBEAT_BASE_TRANSPARENCY = 0.34
local HEARTBEAT_INTENSE_TRANSPARENCY = 0.04

function SurvivabilityFeedbackController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.StaminaRemote = self.Remotes:WaitForChild(RemoteNames.StaminaStateChanged)
	self.StaminaState = {
		MovementState = "Walk",
	}
	self.LastHealth = nil
	self.LastMaxHealth = nil
	self.SurgeUntil = 0
	self.ChaseAlpha = 0
	self.FatigueAlpha = 0
	self.LowHealthAlpha = 0
	self.LowHealthPulse = 0
	self.Heartbeat = {
		Intensity = 0,
		Pulse = 0,
		LastPulseAt = 0,
	}
end

function SurvivabilityFeedbackController:Start()
	self:_createUi()
	self:_hookCharacter(self.World:GetCharacter())

	self.Player.CharacterAdded:Connect(function(character)
		self:_hookCharacter(character)
	end)

	self.StaminaRemote.OnClientEvent:Connect(function(state)
		self.StaminaState = state or self.StaminaState
	end)

	RunService:BindToRenderStep("SurvivabilityFeedbackController.Update", Enum.RenderPriority.Last.Value, function(deltaTime)
		self:_update(deltaTime)
	end)

	DebugLog:Log("ClientSurvival", "[SurvivabilityFeedbackController] Started")
end

function SurvivabilityFeedbackController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SurvivabilityFeedbackUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.PlayerGui

	local overlay = Instance.new("Frame")
	overlay.Name = "LowHealthOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(120, 16, 16)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	local overlayGradient = Instance.new("UIGradient")
	overlayGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.8, 1),
		NumberSequenceKeypoint.new(1, 0.92),
	})
	overlayGradient.Rotation = 90
	overlayGradient.Parent = overlay

	local stateFrame = Instance.new("Frame")
	stateFrame.Name = "StateFrame"
	stateFrame.AnchorPoint = Vector2.new(0.5, 0)
	stateFrame.Position = UDim2.new(0.5, 0, 0, 74)
	stateFrame.Size = UDim2.new(0, 292, 0, 54)
	stateFrame.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	stateFrame.BackgroundTransparency = 1
	stateFrame.BorderSizePixel = 0
	stateFrame.Parent = screenGui

	local stateCorner = Instance.new("UICorner")
	stateCorner.CornerRadius = UDim.new(0, 10)
	stateCorner.Parent = stateFrame

	local stateStripe = Instance.new("Frame")
	stateStripe.Name = "Stripe"
	stateStripe.Size = UDim2.new(0, 4, 1, 0)
	stateStripe.BackgroundColor3 = Color3.fromRGB(214, 180, 64)
	stateStripe.BorderSizePixel = 0
	stateStripe.Parent = stateFrame

	local stateStripeCorner = Instance.new("UICorner")
	stateStripeCorner.CornerRadius = UDim.new(0, 10)
	stateStripeCorner.Parent = stateStripe

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "Label"
	stateLabel.BackgroundTransparency = 1
	stateLabel.Position = UDim2.new(0, 14, 0, 4)
	stateLabel.Size = UDim2.new(1, -24, 0, 16)
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextSize = 14
	stateLabel.TextColor3 = Color3.fromRGB(255, 232, 166)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Text = ""
	stateLabel.Parent = stateFrame

	local stateSubLabel = Instance.new("TextLabel")
	stateSubLabel.Name = "SubLabel"
	stateSubLabel.BackgroundTransparency = 1
	stateSubLabel.Position = UDim2.new(0, 14, 0, 22)
	stateSubLabel.Size = UDim2.new(1, -24, 0, 26)
	stateSubLabel.Font = Enum.Font.Gotham
	stateSubLabel.TextSize = 11
	stateSubLabel.TextColor3 = Color3.fromRGB(224, 226, 232)
	stateSubLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateSubLabel.TextYAlignment = Enum.TextYAlignment.Top
	stateSubLabel.TextWrapped = true
	stateSubLabel.Text = ""
	stateSubLabel.Parent = stateFrame

	local heartBillboard = Instance.new("BillboardGui")
	heartBillboard.Name = "HeartbeatBillboard"
	heartBillboard.Size = UDim2.fromOffset(70, 70)
	heartBillboard.StudsOffset = Vector3.new(0, 3.25, 0)
	heartBillboard.AlwaysOnTop = true
	heartBillboard.Enabled = false
	heartBillboard.Parent = screenGui

	local heartLabel = Instance.new("TextLabel")
	heartLabel.Name = "HeartLabel"
	heartLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	heartLabel.Position = UDim2.fromScale(0.5, 0.5)
	heartLabel.Size = UDim2.fromScale(1, 1)
	heartLabel.BackgroundTransparency = 1
	heartLabel.Font = Enum.Font.GothamBlack
	heartLabel.Text = "HEART"
	heartLabel.TextScaled = true
	heartLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	heartLabel.TextTransparency = 1
	heartLabel.Parent = heartBillboard

	self.UI = {
		Root = screenGui,
		Overlay = overlay,
		StateFrame = stateFrame,
		StateLabel = stateLabel,
		StateSubLabel = stateSubLabel,
		StateStripe = stateStripe,
		HeartbeatBillboard = heartBillboard,
		HeartbeatLabel = heartLabel,
	}
end

function SurvivabilityFeedbackController:_hookCharacter(character)
	self.Character = character
	self.Humanoid = nil
	self.RootPart = nil
	self.LastHealth = nil
	self.LastMaxHealth = nil
	self.SurgeUntil = 0

	if not character then
		return
	end

	self.RootPart = character:FindFirstChild("HumanoidRootPart")
	self.Humanoid = character:FindFirstChildOfClass("Humanoid")
	if self.UI and self.UI.HeartbeatBillboard then
		self.UI.HeartbeatBillboard.Adornee = self.RootPart
	end

	if not self.Humanoid then
		return
	end

	self.LastHealth = self.Humanoid.Health
	self.LastMaxHealth = self.Humanoid.MaxHealth

	self.Humanoid.HealthChanged:Connect(function(health)
		self:_onHealthChanged(health)
	end)
end

function SurvivabilityFeedbackController:_onHealthChanged(health)
	local previousHealth = self.LastHealth
	self.LastHealth = health
	if self.Humanoid then
		self.LastMaxHealth = self.Humanoid.MaxHealth
	end

	if previousHealth and health < previousHealth and health > 0 then
		self.SurgeUntil = os.clock() + 1.1
		local maxHealth = self.Humanoid and self.Humanoid.MaxHealth or 100
		if maxHealth > 0 and (health / maxHealth) <= 0.4 then
			self.LowHealthPulse = 1
		end
	end
end

function SurvivabilityFeedbackController:_update(deltaTime)
	if not self.UI then
		return
	end

	local roundState = self.World:GetRoundState()
	local phase = roundState and roundState.Phase or "Unknown"
	local inPlayablePhase = phase == GamePhase.Preparation or phase == GamePhase.Reception
	local inReception = phase == GamePhase.Reception

	local heartbeatInfo = self:_getHeartbeatInfo(inReception)
	local isChased = inReception and self:_isPlayerChased()
	local movementState = tostring(self.StaminaState.MovementState or "Walk")
	local isFatigued = inPlayablePhase and movementState == "Fatigue"
	local lowHealthRatio = self:_getLowHealthRatio(inPlayablePhase)
	local healthState = self.Character and self.Character:GetAttribute("RemnantHealthState") or nil

	self.ChaseAlpha = self:_approach(self.ChaseAlpha, isChased and 1 or 0, deltaTime * 5.5)
	self.FatigueAlpha = self:_approach(self.FatigueAlpha, isFatigued and 1 or 0, deltaTime * 5.5)
	self.LowHealthAlpha = self:_approach(self.LowHealthAlpha, lowHealthRatio, deltaTime * 3.2)
	self.LowHealthPulse = self:_approach(self.LowHealthPulse, 0, deltaTime * 2.4)
	self.Heartbeat.Intensity = self:_approach(self.Heartbeat.Intensity, heartbeatInfo.Intensity, deltaTime * 4.2)

	self:_updateHeartbeatUi(inReception, deltaTime)
	self:_updateStateBanner(inPlayablePhase, isChased, isFatigued, heartbeatInfo, lowHealthRatio, healthState)
	self:_updateLowHealthOverlay(inPlayablePhase)
end

function SurvivabilityFeedbackController:_getHeartbeatInfo(isActive)
	if not isActive or not self.RootPart then
		return {
			Intensity = 0,
			NearestEntityName = nil,
		}
	end

	local rootPosition = self.RootPart.Position
	local strongestIntensity = 0
	local nearestEntityName = nil

	for _, model in ipairs((Workspace:FindFirstChild("Entities") and Workspace.Entities:GetChildren()) or {}) do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end

		local terrorRadius = tonumber(model:GetAttribute("EntityTerrorRadius")) or 0
		if terrorRadius <= 0 then
			continue
		end

		local distance = (model.PrimaryPart.Position - rootPosition).Magnitude
		if distance > terrorRadius then
			continue
		end

		local intensity = math.clamp(1 - (distance / terrorRadius), 0, 1)
		if intensity > strongestIntensity then
			strongestIntensity = intensity
			nearestEntityName = model:GetAttribute("EntityDisplayName") or model.Name
		end
	end

	return {
		Intensity = strongestIntensity,
		NearestEntityName = nearestEntityName,
	}
end

function SurvivabilityFeedbackController:_isPlayerChased()
	local playerName = self.Player and self.Player.Name
	if not playerName then
		return false
	end

	local entitiesFolder = Workspace:FindFirstChild("Entities")
	if not entitiesFolder then
		return false
	end

	for _, model in ipairs(entitiesFolder:GetChildren()) do
		if not model:IsA("Model") then
			continue
		end

		local targetName = model:GetAttribute("EntityTarget")
		local state = model:GetAttribute("EntityState")
		if targetName == playerName and (state == "Chase" or state == "Rage" or state == "Casting") then
			return true
		end
	end

	return false
end

function SurvivabilityFeedbackController:_getLowHealthRatio(isActive)
	if not isActive or not self.Humanoid or self.Humanoid.Health <= 0 then
		return 0
	end

	if self.Character and self.Character:GetAttribute("RemnantHealthState") == "Crumbling" then
		return 1
	end

	local maxHealth = math.max(1, self.Humanoid.MaxHealth)
	local healthRatio = math.clamp(self.Humanoid.Health / maxHealth, 0, 1)
	if healthRatio >= 0.55 then
		return 0
	end

	return math.clamp((0.55 - healthRatio) / 0.55, 0, 1)
end

function SurvivabilityFeedbackController:_updateHeartbeatUi(isActive, deltaTime)
	local billboard = self.UI.HeartbeatBillboard
	local label = self.UI.HeartbeatLabel
	if not billboard or not label then
		return
	end

	local intensity = self.Heartbeat.Intensity or 0
	billboard.Enabled = isActive and intensity > 0.02 and self.RootPart ~= nil
	if not billboard.Enabled then
		label.TextTransparency = 1
		return
	end

	local pulseInterval = 1.1 - (0.72 * intensity)
	local now = os.clock()
	if now - (self.Heartbeat.LastPulseAt or 0) >= math.max(0.22, pulseInterval) then
		self.Heartbeat.LastPulseAt = now
		self.Heartbeat.Pulse = 1
	end

	self.Heartbeat.Pulse = self:_approach(self.Heartbeat.Pulse or 0, 0, deltaTime * 4.8)
	local pulse = self.Heartbeat.Pulse or 0
	local scale = HEARTBEAT_MIN_SCALE + (intensity * 0.24) + (pulse * (HEARTBEAT_MAX_SCALE - HEARTBEAT_MIN_SCALE))
	local transparency = HEARTBEAT_BASE_TRANSPARENCY - (intensity * 0.22) - (pulse * 0.18)
	label.Size = UDim2.fromScale(scale, scale)
	label.TextTransparency = math.clamp(transparency, HEARTBEAT_INTENSE_TRANSPARENCY, 1)
	label.TextColor3 = intensity >= 0.7 and Color3.fromRGB(255, 154, 154) or Color3.fromRGB(255, 110, 110)
end

function SurvivabilityFeedbackController:_updateStateBanner(isActive, isChased, isFatigued, heartbeatInfo, lowHealthRatio, healthState)
	local frame = self.UI.StateFrame
	local label = self.UI.StateLabel
	local subLabel = self.UI.StateSubLabel
	local stripe = self.UI.StateStripe
	if not frame or not label or not subLabel or not stripe then
		return
	end

	local title = ""
	local message = ""
	local tint = Color3.fromRGB(214, 180, 64)
	local targetAlpha = 0

	if not isActive then
		targetAlpha = 0
	elseif healthState == "Crumbling" then
		local recovery = self.Character and self.Character:GetAttribute("RemnantRecoveryProgress") or 0
		local bleedOut = self.Character and self.Character:GetAttribute("RemnantBleedOutRemaining") or 0
		local needsAllyRecovery = self.Character and self.Character:GetAttribute("RemnantNeedsAllyRecovery") == true
		title = "CRUMBLING"
		if needsAllyRecovery then
			message = string.format("Recovered as far as you can. Another Remnant must finish. %.0fs before collapse.", bleedOut)
		else
			message = string.format("Hold Interact to recover. %.0f%% recovered, %.0fs before collapse.", recovery, bleedOut)
		end
		tint = Color3.fromRGB(122, 190, 255)
		targetAlpha = 1
	elseif isChased then
		title = "CHASED"
		message = "An Entity is actively pursuing you."
		tint = Color3.fromRGB(255, 122, 122)
		targetAlpha = 0.96
	elseif isFatigued then
		title = "FATIGUE"
		message = "Your panic run is breaking down. Recover stamina."
		tint = Color3.fromRGB(255, 156, 92)
		targetAlpha = 0.92
	elseif (lowHealthRatio or 0) >= 0.32 then
		title = "DANGER"
		message = "You are badly injured and close to collapse."
		tint = Color3.fromRGB(255, 108, 108)
		targetAlpha = 0.9
	elseif (heartbeatInfo.Intensity or 0) >= 0.24 then
		title = "TERROR"
		message = string.format("%s is close enough to feel.", heartbeatInfo.NearestEntityName or "Something")
		tint = Color3.fromRGB(235, 172, 172)
		targetAlpha = 0.86
	end

	frame.BackgroundTransparency = 1 - (targetAlpha * 0.92)
	stripe.BackgroundColor3 = tint
	label.Text = title
	subLabel.Text = message
	label.TextColor3 = tint
	subLabel.TextColor3 = Color3.fromRGB(232, 235, 242)
	frame.Visible = targetAlpha > 0.02
end

function SurvivabilityFeedbackController:_updateLowHealthOverlay(isActive)
	local overlay = self.UI.Overlay
	if not overlay then
		return
	end

	local targetAlpha = isActive and math.clamp((self.LowHealthAlpha or 0) + ((self.LowHealthPulse or 0) * 0.45), 0, 1) or 0
	overlay.Visible = targetAlpha > 0.01
	overlay.BackgroundTransparency = 1 - (targetAlpha * 0.62)
end

function SurvivabilityFeedbackController:_approach(current, target, step)
	if current < target then
		return math.min(target, current + step)
	end
	if current > target then
		return math.max(target, current - step)
	end
	return target
end

return SurvivabilityFeedbackController
