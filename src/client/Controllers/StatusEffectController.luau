local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StatusEffectController = {}
StatusEffectController.Name = "StatusEffectController"

function StatusEffectController:Init()
	self.Player = self.World.Player
	self.PlayerGui = self.World.PlayerGui
	self.Shared = self.World.Shared
	self.Remotes = self.Shared:WaitForChild("Remotes")
	self.Remote = self.Remotes:WaitForChild(RemoteNames.StatusEffectsChanged)
	self.ActiveStatuses = {}
	self.StatusFrames = {}
end

function StatusEffectController:Start()
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(snapshot)
		self.ActiveStatuses = snapshot or {}
		self:_renderStatuses()
	end)

	task.spawn(function()
		while true do
			self:_updateDurations()
			task.wait(0.1)
		end
	end)

	DebugLog:Log("ClientStatus", "[StatusEffectController] Started")
end

function StatusEffectController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StatusEffectsUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1, -24, 0.5, 0)
	container.Size = UDim2.new(0, 150, 0, 360)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = container

	self.UI = {
		Root = screenGui,
		Container = container,
	}
end

function StatusEffectController:_renderStatuses()
	local seen = {}

	for _, status in ipairs(self.ActiveStatuses) do
		if type(status) ~= "table" or not status.Id then
			continue
		end

		local frame = self.StatusFrames[status.Id]
		if not frame then
			frame = self:_createStatusFrame(status)
			self.StatusFrames[status.Id] = frame
		end

		seen[status.Id] = true
		frame.Visible = true
		local iconLabel = frame:FindFirstChild("IconLabel")
		local nameLabel = frame:FindFirstChild("NameLabel")
		local metaLabel = frame:FindFirstChild("MetaLabel")
		local durationLabel = frame:FindFirstChild("DurationLabel")

		if iconLabel then
			iconLabel.Text = status.ShortLabel or "???"
			iconLabel.BackgroundColor3 = status.IsBuff and Color3.fromRGB(214, 180, 64) or Color3.fromRGB(168, 57, 57)
		end

		if nameLabel then
			nameLabel.Text = status.DisplayName or status.Id
		end

		if metaLabel then
			metaLabel.Text = self:_formatMeta(status)
		end

		if durationLabel then
			durationLabel.Text = string.format("%.1fs", status.Duration or 0)
		end

		local currentDuration = status.Duration or 0
		local maxDuration = frame:GetAttribute("MaxDuration")
		if maxDuration == nil or currentDuration > maxDuration then
			frame:SetAttribute("MaxDuration", currentDuration)
		end
	end

	for statusId, frame in pairs(self.StatusFrames) do
		if not seen[statusId] then
			frame.Visible = false
		end
	end
end

function StatusEffectController:_createStatusFrame(status)
	local frame = Instance.new("Frame")
	frame.Name = status.Id
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = self.UI.Container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "IconLabel"
	iconLabel.Position = UDim2.new(0, 2, 0, 2)
	iconLabel.Size = UDim2.new(0, 42, 0, 42)
	iconLabel.BorderSizePixel = 0
	iconLabel.BackgroundColor3 = Color3.fromRGB(214, 180, 64)
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.TextScaled = true
	iconLabel.Parent = frame

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = iconLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.new(0, 50, 0, 4)
	nameLabel.Size = UDim2.new(1, -94, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local metaLabel = Instance.new("TextLabel")
	metaLabel.Name = "MetaLabel"
	metaLabel.Position = UDim2.new(0, 50, 0, 20)
	metaLabel.Size = UDim2.new(1, -94, 0, 12)
	metaLabel.BackgroundTransparency = 1
	metaLabel.Font = Enum.Font.Gotham
	metaLabel.TextColor3 = Color3.fromRGB(185, 185, 185)
	metaLabel.TextSize = 11
	metaLabel.TextXAlignment = Enum.TextXAlignment.Left
	metaLabel.Parent = frame

	local durationLabel = Instance.new("TextLabel")
	durationLabel.Name = "DurationLabel"
	durationLabel.Position = UDim2.new(1, -40, 0, 6)
	durationLabel.Size = UDim2.new(0, 34, 0, 14)
	durationLabel.BackgroundTransparency = 1
	durationLabel.Font = Enum.Font.GothamBold
	durationLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	durationLabel.TextSize = 11
	durationLabel.TextXAlignment = Enum.TextXAlignment.Right
	durationLabel.Parent = frame

	local timerBarBackground = Instance.new("Frame")
	timerBarBackground.Name = "TimerBarBackground"
	timerBarBackground.Position = UDim2.new(0, 50, 1, -8)
	timerBarBackground.Size = UDim2.new(1, -58, 0, 4)
	timerBarBackground.BackgroundColor3 = Color3.fromRGB(46, 46, 56)
	timerBarBackground.BorderSizePixel = 0
	timerBarBackground.Parent = frame

	local timerBar = Instance.new("Frame")
	timerBar.Name = "TimerBar"
	timerBar.Size = UDim2.new(1, 0, 1, 0)
	timerBar.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
	timerBar.BorderSizePixel = 0
	timerBar.Parent = timerBarBackground

	return frame
end

function StatusEffectController:_updateDurations()
	for _, status in ipairs(self.ActiveStatuses) do
		if type(status) ~= "table" or not status.Id then
			continue
		end

		local frame = self.StatusFrames[status.Id]
		if frame and frame.Visible then
			status.Duration = math.max(0, (status.Duration or 0) - 0.1)
			local durationLabel = frame:FindFirstChild("DurationLabel")
			if durationLabel then
				durationLabel.Text = string.format("%.1fs", status.Duration)
			end

			local maxDuration = frame:GetAttribute("MaxDuration") or status.Duration
			local fillRatio = maxDuration > 0 and math.clamp(status.Duration / maxDuration, 0, 1) or 0
			local timerBarBackground = frame:FindFirstChild("TimerBarBackground")
			local timerBar = timerBarBackground and timerBarBackground:FindFirstChild("TimerBar")
			if timerBar then
				timerBar.Size = UDim2.new(fillRatio, 0, 1, 0)
			end

			if status.Duration <= 0 then
				frame:SetAttribute("MaxDuration", nil)
			end
		end
	end
end

function StatusEffectController:_formatMeta(status)
	if type(status) ~= "table" then
		return ""
	end

	local fragments = {}
	if (status.Tier or 1) > 1 then
		table.insert(fragments, string.format("T%d", status.Tier))
	end
	if (status.Stacks or 1) > 1 then
		table.insert(fragments, string.format("x%d", status.Stacks))
	end
	if (status.Magnitude or 0) > 0 then
		table.insert(fragments, string.format("%d%%", math.floor((status.Magnitude * 100) + 0.5)))
	end

	return #fragments > 0 and table.concat(fragments, "  ") or ""
end

return StatusEffectController
