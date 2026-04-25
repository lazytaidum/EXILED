local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityDebugController = {}
EntityDebugController.Name = "EntityDebugController"

local function _clampText(text, maxLength)
	text = tostring(text or "")
	if #text <= maxLength then
		return text
	end

	return string.sub(text, 1, math.max(0, maxLength - 3)) .. "..."
end

function EntityDebugController:Init()
	self.EntitiesFolder = Workspace:WaitForChild("Entities")
	self.Overlays = {}
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.DebugUiEnabled = true
end

function EntityDebugController:SetDebugUiEnabled(enabled)
	self.DebugUiEnabled = enabled ~= false

	for _, overlay in pairs(self.Overlays) do
		if overlay.Billboard then
			overlay.Billboard.Enabled = self.DebugUiEnabled
		end
	end
end

function EntityDebugController:Start()
	if not DebugFlags.Enabled or not DebugFlags.EntityDebugOverlay then
		return
	end

	for _, model in ipairs(self.EntitiesFolder:GetChildren()) do
		self:_trackEntity(model)
	end

	self.EntitiesFolder.ChildAdded:Connect(function(child)
		self:_trackEntity(child)
	end)

	self.EntitiesFolder.ChildRemoved:Connect(function(child)
		self:_untrackEntity(child)
	end)

	if self.Player then
		self.Player.CharacterAdded:Connect(function()
			task.defer(function()
				self:_rebuildOverlays()
			end)
		end)
	end

	task.spawn(function()
		while true do
			self:_refreshOverlays()
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientCombat", "[EntityDebugController] Started")
end

function EntityDebugController:_trackEntity(model)
	if not model:IsA("Model") then
		return
	end

	local adornee = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not adornee then
		return
	end

	if self.Overlays[model] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EntityDebugOverlay"
	billboard.Size = UDim2.new(0, 270, 0, 136)
	billboard.StudsOffset = Vector3.new(0, 5.55, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = self.World.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.new(0, 10, 0, 6)
	nameLabel.Size = UDim2.new(1, -20, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Position = UDim2.new(0, 10, 0, 24)
	stateLabel.Size = UDim2.new(1, -20, 0, 12)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.Gotham
	stateLabel.TextColor3 = Color3.fromRGB(199, 205, 216)
	stateLabel.TextSize = 10
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Parent = frame

	local intentLabel = Instance.new("TextLabel")
	intentLabel.Name = "IntentLabel"
	intentLabel.Position = UDim2.new(0, 10, 0, 39)
	intentLabel.Size = UDim2.new(1, -20, 0, 12)
	intentLabel.BackgroundTransparency = 1
	intentLabel.Font = Enum.Font.Gotham
	intentLabel.TextColor3 = Color3.fromRGB(214, 180, 64)
	intentLabel.TextSize = 10
	intentLabel.TextXAlignment = Enum.TextXAlignment.Left
	intentLabel.Parent = frame

	local stimulusLabel = Instance.new("TextLabel")
	stimulusLabel.Name = "StimulusLabel"
	stimulusLabel.Position = UDim2.new(0, 10, 0, 54)
	stimulusLabel.Size = UDim2.new(1, -20, 0, 24)
	stimulusLabel.BackgroundTransparency = 1
	stimulusLabel.Font = Enum.Font.Gotham
	stimulusLabel.TextColor3 = Color3.fromRGB(164, 208, 250)
	stimulusLabel.TextSize = 10
	stimulusLabel.TextWrapped = true
	stimulusLabel.TextYAlignment = Enum.TextYAlignment.Top
	stimulusLabel.TextXAlignment = Enum.TextXAlignment.Left
	stimulusLabel.Parent = frame

	local memoryLabel = Instance.new("TextLabel")
	memoryLabel.Name = "MemoryLabel"
	memoryLabel.Position = UDim2.new(0, 10, 0, 80)
	memoryLabel.Size = UDim2.new(1, -20, 0, 12)
	memoryLabel.BackgroundTransparency = 1
	memoryLabel.Font = Enum.Font.Gotham
	memoryLabel.TextColor3 = Color3.fromRGB(224, 192, 138)
	memoryLabel.TextSize = 10
	memoryLabel.TextXAlignment = Enum.TextXAlignment.Left
	memoryLabel.Parent = frame

	local abilityLabel = Instance.new("TextLabel")
	abilityLabel.Name = "AbilityLabel"
	abilityLabel.Position = UDim2.new(0, 10, 0, 94)
	abilityLabel.Size = UDim2.new(1, -20, 0, 12)
	abilityLabel.BackgroundTransparency = 1
	abilityLabel.Font = Enum.Font.Gotham
	abilityLabel.TextColor3 = Color3.fromRGB(214, 180, 64)
	abilityLabel.TextSize = 10
	abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
	abilityLabel.Parent = frame

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthLabel"
	healthLabel.Position = UDim2.new(0, 10, 0, 108)
	healthLabel.Size = UDim2.new(1, -20, 0, 12)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Font = Enum.Font.Gotham
	healthLabel.TextColor3 = Color3.fromRGB(178, 228, 196)
	healthLabel.TextSize = 10
	healthLabel.TextXAlignment = Enum.TextXAlignment.Left
	healthLabel.Parent = frame

	local hitLabel = Instance.new("TextLabel")
	hitLabel.Name = "HitLabel"
	hitLabel.Position = UDim2.new(0, 10, 0, 121)
	hitLabel.Size = UDim2.new(1, -20, 0, 12)
	hitLabel.BackgroundTransparency = 1
	hitLabel.Font = Enum.Font.GothamBold
	hitLabel.TextColor3 = Color3.fromRGB(132, 232, 156)
	hitLabel.TextSize = 10
	hitLabel.TextXAlignment = Enum.TextXAlignment.Left
	hitLabel.Parent = frame

	self.Overlays[model] = {
		Billboard = billboard,
		Frame = frame,
		NameLabel = nameLabel,
		StateLabel = stateLabel,
		IntentLabel = intentLabel,
		StimulusLabel = stimulusLabel,
		MemoryLabel = memoryLabel,
		AbilityLabel = abilityLabel,
		HealthLabel = healthLabel,
		HitLabel = hitLabel,
	}
end

function EntityDebugController:_untrackEntity(model)
	local overlay = self.Overlays[model]
	if not overlay then
		return
	end

	if overlay.Billboard then
		overlay.Billboard:Destroy()
	end

	self.Overlays[model] = nil
end

function EntityDebugController:_rebuildOverlays()
	for model, _ in pairs(self.Overlays) do
		self:_untrackEntity(model)
	end

	for _, model in ipairs(self.EntitiesFolder:GetChildren()) do
		self:_trackEntity(model)
	end
end

function EntityDebugController:_refreshOverlays()
	local now = Workspace:GetServerTimeNow()
	local roundState = self.World:GetRoundState()
	local phase = roundState and roundState.Phase or "Unknown"
	local debugUiEnabled = self.DebugUiEnabled and phase == GamePhase.Reception

	for _, model in ipairs(self.EntitiesFolder:GetChildren()) do
		if not self.Overlays[model] then
			self:_trackEntity(model)
		end
	end

	for model, overlay in pairs(self.Overlays) do
		if not model.Parent then
			self:_untrackEntity(model)
			continue
		end

		local name = model:GetAttribute("DebugEntityName") or model.Name
		local state = model:GetAttribute("DebugState") or "Unknown"
		local intent = model:GetAttribute("DebugIntent") or "None"
		local intentConfidence = model:GetAttribute("DebugIntentConfidence") or "0.00"
		local intentReason = model:GetAttribute("DebugIntentReason") or "None"
		local health = model:GetAttribute("DebugHealth") or 0
		local maxHealth = model:GetAttribute("DebugMaxHealth") or 0
		local target = model:GetAttribute("DebugTarget") or ""
		local directSight = model:GetAttribute("DebugDirectSight")
		local detectionSight = model:GetAttribute("DebugDetectionSight")
		local patrolReason = model:GetAttribute("DebugPatrolReason") or ""
		local patrolPointId = model:GetAttribute("DebugPatrolPointId") or ""
		local patrolPauseRemaining = model:GetAttribute("DebugPatrolPauseRemaining")
		local chaseLostSight = model:GetAttribute("DebugChaseLostSight")
		local lastAbility = model:GetAttribute("DebugLastAbility") or "None"
		local networkOwner = model:GetAttribute("DebugNetworkOwner") or "Server"
		local moveMode = model:GetAttribute("DebugMoveMode") or "Idle"
		local walkSpeed = model:GetAttribute("DebugWalkSpeed")
		local targetWalkSpeed = model:GetAttribute("DebugTargetWalkSpeed")
		local pathStatus = model:GetAttribute("DebugPathStatus") or "Idle"
		local pathError = model:GetAttribute("DebugPathError") or ""
		local waypointIndex = model:GetAttribute("DebugWaypointIndex") or 0
		local waypointCount = model:GetAttribute("DebugWaypointCount") or 0
		local targetDistance = model:GetAttribute("DebugTargetDistance")
		local goalDistance = model:GetAttribute("DebugGoalDistance")
		local predictionSeconds = model:GetAttribute("DebugPredictionSeconds")
		local predictionMode = model:GetAttribute("DebugPredictionMode") or "None"
		local turnSeverity = model:GetAttribute("DebugTurnSeverity")
		local pathAge = model:GetAttribute("DebugPathAge")
		local remainingPathDistance = model:GetAttribute("DebugRemainingPathDistance")
		local hasLineOfSight = model:GetAttribute("DebugLineOfSight")
		local hasMovementLane = model:GetAttribute("DebugMovementLane")
		local directGrace = model:GetAttribute("DebugDirectGrace")
		local attackPhase = model:GetAttribute("DebugAttackPhase") or ""
		local attackRemaining = model:GetAttribute("DebugAttackRemaining")
		local attackResult = model:GetAttribute("DebugAttackResult") or ""
		local attackBlocked = model:GetAttribute("DebugAttackBlocked")
		local hitDamage = model:GetAttribute("DebugRecentHitDamage")
		local hitSource = model:GetAttribute("DebugRecentHitSource")
		local hitExpiresAt = model:GetAttribute("DebugRecentHitExpiresAt") or 0
		local hitActive = hitDamage ~= nil and now <= hitExpiresAt
		local losText = hasLineOfSight == nil and "Unknown" or (hasLineOfSight and "Clear" or "Blocked")
		local laneText = hasMovementLane == nil and "Unknown" or (hasMovementLane and "Clear" or "Blocked")
		local targetDistanceText = typeof(targetDistance) == "number" and string.format("%.1f", targetDistance) or "--"
		local goalDistanceText = typeof(goalDistance) == "number" and string.format("%.1f", goalDistance) or "--"
		local predictionSecondsText = typeof(predictionSeconds) == "number" and string.format("%.2fs", predictionSeconds) or "--"
		local turnSeverityText = typeof(turnSeverity) == "number" and string.format("%.2f", turnSeverity) or "--"
		local pathAgeText = typeof(pathAge) == "number" and string.format("%.2fs", pathAge) or "--"
		local remainingPathText = typeof(remainingPathDistance) == "number" and string.format("%.1f", remainingPathDistance) or "--"
		local directGraceText = typeof(directGrace) == "number" and string.format("%.2fs", directGrace) or "--"
		local walkSpeedText = typeof(walkSpeed) == "number" and string.format("%.1f", walkSpeed) or "--"
		local targetWalkSpeedText = typeof(targetWalkSpeed) == "number" and string.format("%.1f", targetWalkSpeed) or "--"
		local attackRemainingText = typeof(attackRemaining) == "number" and string.format("%.2fs", attackRemaining) or "--"
		local attackBlockedText = typeof(attackBlocked) == "number" and string.format("%.2fs", attackBlocked) or "--"
		local patrolPauseText = typeof(patrolPauseRemaining) == "number" and string.format("%.2fs", patrolPauseRemaining) or "--"
		local chaseLostSightText = typeof(chaseLostSight) == "number" and string.format("%.2fs", chaseLostSight) or "--"

		overlay.Billboard.Enabled = debugUiEnabled
		overlay.NameLabel.Text = _clampText(name, 32)
		overlay.StateLabel.Text = string.format(
			"State: %s%s%s%s",
			_clampText(state, 12),
			target ~= "" and ("  Target: " .. _clampText(target, 12)) or "",
			directSight ~= nil and ("  Sight: " .. (directSight and "Yes" or "No")) or "",
			detectionSight ~= nil and ("  Detect: " .. (detectionSight and "Yes" or "No")) or ""
		)
		overlay.IntentLabel.Text = string.format("Intent: %s (%s)  via %s", _clampText(intent, 12), _clampText(intentConfidence, 4), _clampText(intentReason, 16))
		overlay.StimulusLabel.Text = string.format(
			"Move: %s %s>%s  Path: %s  WP: %d/%d  Dist: %s  Goal: %s  Rem: %s",
			_clampText(moveMode, 10),
			walkSpeedText,
			targetWalkSpeedText,
			_clampText(pathStatus, 14),
			waypointIndex,
			waypointCount,
			targetDistanceText,
			goalDistanceText,
			remainingPathText
		)
		overlay.MemoryLabel.Text = string.format(
			"Pred: %s @ %s  Turn: %s  LoS: %s  Lane: %s  Lost: %s",
			_clampText(predictionMode, 10),
			predictionSecondsText,
			turnSeverityText,
			losText,
			laneText,
			chaseLostSightText
		)
		overlay.AbilityLabel.Text = string.format(
			"Last: %s  Owner: %s  Age: %s%s%s",
			_clampText(lastAbility, 12),
			_clampText(networkOwner, 10),
			pathAgeText,
			pathError ~= "" and ("  Err: " .. _clampText(pathError, 10)) or "",
			attackPhase ~= "" and ("  Atk: " .. _clampText(attackPhase, 8) .. "@" .. attackRemainingText .. (attackResult ~= "" and ("/" .. _clampText(attackResult, 6)) or "") .. " B:" .. attackBlockedText) or ""
		)
		overlay.HealthLabel.Text = string.format(
			"HP: %d / %d  Grace: %s%s",
			health,
			maxHealth,
			directGraceText,
			patrolReason ~= "" and ("  Patrol: " .. _clampText(patrolReason, 8) .. "/" .. _clampText(patrolPointId, 8) .. "@" .. patrolPauseText) or ""
		)
		overlay.HitLabel.Text = hitActive and string.format("HIT %s (%s)", tostring(hitDamage), _clampText(hitSource or "Unknown", 18)) or ""
		overlay.Frame.BackgroundColor3 = hitActive and Color3.fromRGB(23, 40, 30) or Color3.fromRGB(16, 18, 24)
	end
end

return EntityDebugController
