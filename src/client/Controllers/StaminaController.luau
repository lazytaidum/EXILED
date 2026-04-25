local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StaminaController = {}
StaminaController.Name = "StaminaController"

function StaminaController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.Remote = self.Remotes:WaitForChild(RemoteNames.StaminaStateChanged)
	self.State = {
		Current = 100,
		Max = 100,
		MovementState = "Walk",
		RunDurationBeforeFatigue = 6,
	}
	self.Character = nil
	self.Humanoid = nil
	self.Health = 100
	self.MaxHealth = 100
end

function StaminaController:Start()
	self:_createUI()
	self:_hookCharacter(self.World:GetCharacter())

	self.Player.CharacterAdded:Connect(function(character)
		self:_hookCharacter(character)
	end)

	self.Remote.OnClientEvent:Connect(function(state)
		self.State = state or self.State
		self:_refresh()
	end)

	task.spawn(function()
		while true do
			self:_refresh()
			task.wait(0.1)
		end
	end)

	DebugLog:Log("ClientMovement", "[StaminaController] Started")
end

function StaminaController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StaminaUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 18, 1, -18)
	frame.Size = UDim2.new(0, 300, 0, 96)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.new(0, 0, 0, 12)
	portrait.Size = UDim2.new(0, 74, 0, 74)
	portrait.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	portrait.BackgroundTransparency = 0.08
	portrait.BorderSizePixel = 0
	portrait.Parent = frame

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 12)
	portraitCorner.Parent = portrait

	local portraitLabel = Instance.new("TextLabel")
	portraitLabel.Name = "PortraitLabel"
	portraitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	portraitLabel.Position = UDim2.fromScale(0.5, 0.5)
	portraitLabel.Size = UDim2.new(1, -12, 1, -12)
	portraitLabel.BackgroundTransparency = 1
	portraitLabel.Font = Enum.Font.GothamBlack
	portraitLabel.TextScaled = true
	portraitLabel.TextColor3 = Color3.fromRGB(238, 240, 245)
	portraitLabel.Text = ":)"
	portraitLabel.Parent = portrait

	local vitals = Instance.new("Frame")
	vitals.Name = "Vitals"
	vitals.Position = UDim2.new(0, 84, 0, 18)
	vitals.Size = UDim2.new(0, 216, 0, 64)
	vitals.BackgroundTransparency = 1
	vitals.Parent = frame

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthLabel"
	healthLabel.BackgroundTransparency = 1
	healthLabel.Position = UDim2.new(0, 0, 0, 0)
	healthLabel.Size = UDim2.new(1, 0, 0, 14)
	healthLabel.Font = Enum.Font.GothamBold
	healthLabel.TextSize = 11
	healthLabel.TextColor3 = Color3.fromRGB(255, 226, 226)
	healthLabel.TextXAlignment = Enum.TextXAlignment.Left
	healthLabel.Text = "Health 100/100"
	healthLabel.Parent = vitals

	local healthBarBackground = Instance.new("Frame")
	healthBarBackground.Name = "HealthBarBackground"
	healthBarBackground.Position = UDim2.new(0, 0, 0, 16)
	healthBarBackground.Size = UDim2.new(1, 0, 0, 10)
	healthBarBackground.BackgroundColor3 = Color3.fromRGB(58, 38, 40)
	healthBarBackground.BorderSizePixel = 0
	healthBarBackground.Parent = vitals

	local healthBarCorner = Instance.new("UICorner")
	healthBarCorner.CornerRadius = UDim.new(0, 999)
	healthBarCorner.Parent = healthBarBackground

	local healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.new(1, 0, 1, 0)
	healthBar.BackgroundColor3 = Color3.fromRGB(207, 66, 66)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = healthBarBackground

	local healthBarFillCorner = Instance.new("UICorner")
	healthBarFillCorner.CornerRadius = UDim.new(0, 999)
	healthBarFillCorner.Parent = healthBar

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, 32)
	label.Size = UDim2.new(0.62, 0, 0, 12)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(180, 214, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "Stamina"
	label.Parent = vitals

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "State"
	stateLabel.BackgroundTransparency = 1
	stateLabel.AnchorPoint = Vector2.new(1, 0)
	stateLabel.Position = UDim2.new(1, 0, 0, 32)
	stateLabel.Size = UDim2.new(0.34, 0, 0, 12)
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextSize = 11
	stateLabel.TextColor3 = Color3.fromRGB(180, 214, 255)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Right
	stateLabel.Text = "WALK"
	stateLabel.Parent = vitals

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.new(0, 0, 0, 48)
	barBackground.Size = UDim2.new(1, 0, 0, 10)
	barBackground.BackgroundColor3 = Color3.fromRGB(46, 46, 56)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = vitals

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 999)
	barCorner.Parent = barBackground

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	bar.BorderSizePixel = 0
	bar.Parent = barBackground

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 999)
	barFillCorner.Parent = bar

	self.UI = {
		Root = screenGui,
		Frame = frame,
		PortraitLabel = portraitLabel,
		HealthLabel = healthLabel,
		HealthBar = healthBar,
		Label = label,
		StateLabel = stateLabel,
		Bar = bar,
	}

	self:_refresh()
end

function StaminaController:_hookCharacter(character)
	self.Character = character
	self.Humanoid = nil

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	self.Humanoid = humanoid
	self.Health = humanoid.Health
	self.MaxHealth = humanoid.MaxHealth

	humanoid.HealthChanged:Connect(function(health)
		self.Health = health
		self.MaxHealth = humanoid.MaxHealth
		self:_refresh()
	end)

	self:_refresh()
end

function StaminaController:_refresh()
	if not self.UI then
		return
	end

	local roundState = self.World:GetRoundState()
	local phase = roundState and roundState.Phase or "Unknown"
	local shouldShow = phase == GamePhase.Preparation or phase == GamePhase.Reception
	self.UI.Root.Enabled = shouldShow
	if not shouldShow then
		return
	end

	local current = self.State.Current or 0
	local max = math.max(1, self.State.Max or 100)
	local ratio = math.clamp(current / max, 0, 1)
	local health = self.Humanoid and self.Humanoid.Health or self.Health or 100
	local maxHealth = math.max(1, self.Humanoid and self.Humanoid.MaxHealth or self.MaxHealth or 100)
	local healthState = self.Character and self.Character:GetAttribute("RemnantHealthState") or nil
	local shards = self.Character and self.Character:GetAttribute("RemnantShards") or nil
	local maxShards = self.Character and self.Character:GetAttribute("RemnantMaxShards") or nil
	local recoveryProgress = self.Character and self.Character:GetAttribute("RemnantRecoveryProgress") or 0
	local recoveryMax = math.max(1, self.Character and self.Character:GetAttribute("RemnantRecoveryMax") or 100)
	local selfRecoveryCap = self.Character and self.Character:GetAttribute("RemnantSelfRecoveryCap") or recoveryMax
	local needsAllyRecovery = self.Character and self.Character:GetAttribute("RemnantNeedsAllyRecovery") == true
	local bleedOutRemaining = self.Character and self.Character:GetAttribute("RemnantBleedOutRemaining") or 0
	local healthRatio = math.clamp(health / maxHealth, 0, 1)
	local movementState = tostring(self.State.MovementState or "Walk")
	local isCrumbling = healthState == "Crumbling"
	if isCrumbling then
		healthRatio = math.clamp(recoveryProgress / recoveryMax, 0, 1)
	end

	self.UI.Bar.Size = UDim2.new(ratio, 0, 1, 0)
	self.UI.HealthBar.Size = UDim2.new(healthRatio, 0, 1, 0)
	if isCrumbling then
		if needsAllyRecovery then
			self.UI.HealthLabel.Text = string.format("Crumbling %.0f%% | Needs ally | %.0fs", recoveryProgress, bleedOutRemaining)
		elseif selfRecoveryCap < recoveryMax then
			self.UI.HealthLabel.Text = string.format("Crumbling %.0f/%.0f%% | Shards %d/%d | %.0fs", recoveryProgress, selfRecoveryCap, shards or 0, maxShards or 0, bleedOutRemaining)
		else
			self.UI.HealthLabel.Text = string.format("Crumbling %.0f%% | Shards %d/%d | %.0fs", recoveryProgress, shards or 0, maxShards or 0, bleedOutRemaining)
		end
	else
		self.UI.HealthLabel.Text = string.format("Health %.0f/%.0f | Shards %d/%d", health, maxHealth, shards or 0, maxShards or 0)
	end
	self.UI.Label.Text = string.format("Stamina %.1f/%.0f", current, max)
	self.UI.StateLabel.Text = string.upper(movementState)
	self.UI.PortraitLabel.Text = isCrumbling and "!!" or (maxHealth > 0 and (health / maxHealth <= 0.35 and ":(" or ":)") or ":|")

	if isCrumbling then
		self.UI.HealthBar.BackgroundColor3 = Color3.fromRGB(122, 190, 255)
	elseif healthRatio <= 0.25 then
		self.UI.HealthBar.BackgroundColor3 = Color3.fromRGB(214, 92, 92)
	elseif healthRatio <= 0.5 then
		self.UI.HealthBar.BackgroundColor3 = Color3.fromRGB(229, 123, 88)
	else
		self.UI.HealthBar.BackgroundColor3 = Color3.fromRGB(207, 66, 66)
	end

	if movementState == "Fatigue" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(255, 156, 92)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(255, 156, 92)
	elseif movementState == "Run" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	elseif movementState == "Sprint" then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(132, 224, 255)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	elseif ratio <= 0.25 then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(214, 92, 92)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(214, 92, 92)
	elseif ratio <= 0.5 then
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(242, 212, 103)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(242, 212, 103)
	else
		self.UI.StateLabel.TextColor3 = Color3.fromRGB(180, 214, 255)
		self.UI.Bar.BackgroundColor3 = Color3.fromRGB(109, 180, 255)
	end
end

return StaminaController
