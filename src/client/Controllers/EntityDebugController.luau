local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
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
	billboard.Size = UDim2.new(0, 236, 0, 90)
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

	local abilityLabel = Instance.new("TextLabel")
	abilityLabel.Name = "AbilityLabel"
	abilityLabel.Position = UDim2.new(0, 10, 0, 39)
	abilityLabel.Size = UDim2.new(1, -20, 0, 12)
	abilityLabel.BackgroundTransparency = 1
	abilityLabel.Font = Enum.Font.Gotham
	abilityLabel.TextColor3 = Color3.fromRGB(214, 180, 64)
	abilityLabel.TextSize = 10
	abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
	abilityLabel.Parent = frame

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthLabel"
	healthLabel.Position = UDim2.new(0, 10, 0, 54)
	healthLabel.Size = UDim2.new(1, -20, 0, 12)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Font = Enum.Font.Gotham
	healthLabel.TextColor3 = Color3.fromRGB(178, 228, 196)
	healthLabel.TextSize = 10
	healthLabel.TextXAlignment = Enum.TextXAlignment.Left
	healthLabel.Parent = frame

	local hitLabel = Instance.new("TextLabel")
	hitLabel.Name = "HitLabel"
	hitLabel.Position = UDim2.new(0, 10, 0, 68)
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
		local health = model:GetAttribute("DebugHealth") or 0
		local maxHealth = model:GetAttribute("DebugMaxHealth") or 0
		local target = model:GetAttribute("DebugTarget") or ""
		local lastAbility = model:GetAttribute("DebugLastAbility") or "None"
		local absorbed = model:GetAttribute("DebugAbsorbedCount") or 0
		local hitDamage = model:GetAttribute("DebugRecentHitDamage")
		local hitSource = model:GetAttribute("DebugRecentHitSource")
		local hitExpiresAt = model:GetAttribute("DebugRecentHitExpiresAt") or 0
		local hitActive = hitDamage ~= nil and now <= hitExpiresAt

		overlay.NameLabel.Text = _clampText(name, 32)
		overlay.StateLabel.Text = string.format("State: %s%s", _clampText(state, 12), target ~= "" and ("  Target: " .. _clampText(target, 14)) or "")
		overlay.AbilityLabel.Text = string.format("Last: %s%s", _clampText(lastAbility, 18), absorbed > 0 and ("  Absorbed: " .. tostring(absorbed)) or "")
		overlay.HealthLabel.Text = string.format("HP: %d / %d", health, maxHealth)
		overlay.HitLabel.Text = hitActive and string.format("HIT %s (%s)", tostring(hitDamage), _clampText(hitSource or "Unknown", 18)) or ""
		overlay.Frame.BackgroundColor3 = hitActive and Color3.fromRGB(23, 40, 30) or Color3.fromRGB(16, 18, 24)
	end
end

return EntityDebugController
