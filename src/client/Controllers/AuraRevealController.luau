local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local COLORS = {
	Entity = Color3.fromRGB(99, 176, 255),
	Objective = Color3.fromRGB(108, 248, 255),
	Remnant = Color3.fromRGB(118, 255, 174),
	Loot = Color3.fromRGB(255, 223, 112),
}

local AuraRevealController = {}
AuraRevealController.Name = "AuraRevealController"

function AuraRevealController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Camera = self.World.Camera
	self.Remotes = self.World.Remotes
	self.Active = {}
end

function AuraRevealController:Start()
	self.Remote = self.Remotes:WaitForChild(RemoteNames.AuraRevealStateChanged)
	self.Remote.OnClientEvent:Connect(function(snapshot)
		self:_applySnapshot(snapshot or {})
	end)

	task.spawn(function()
		while true do
			self:_refresh()
			task.wait(0.1)
		end
	end)

	DebugLog:Log("ClientRemnant", "[AuraRevealController] Started")
end

function AuraRevealController:_applySnapshot(snapshot)
	local seen = {}
	local now = os.clock()

	for _, entry in ipairs(snapshot) do
		local instance = entry.Instance
		if instance and instance.Parent then
			seen[instance] = true
			local active = self.Active[instance]
			if not active then
				active = self:_createReveal(entry)
				self.Active[instance] = active
			end

			active.Type = entry.Type
			active.DisplayName = entry.DisplayName or instance.Name
			active.ExpiresAt = now + math.max(0, entry.Duration or 0)
			self:_styleReveal(active)
		end
	end

	for instance, active in pairs(self.Active) do
		if not seen[instance] then
			self:_destroyReveal(active)
			self.Active[instance] = nil
		end
	end
end

function AuraRevealController:_createReveal(entry)
	local instance = entry.Instance
	local highlight = Instance.new("Highlight")
	highlight.Name = "AuraReveal"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.78
	highlight.OutlineTransparency = 0.15
	highlight.Adornee = instance
	highlight.Parent = self.Camera or self.PlayerGui

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AuraRevealLabel"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.new(0, 120, 0, 24)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.Adornee = self:_resolveAdornee(instance)
	billboard.Parent = self.PlayerGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextStrokeTransparency = 0.55
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = entry.DisplayName or instance.Name
	label.Parent = billboard

	return {
		Instance = instance,
		Highlight = highlight,
		Billboard = billboard,
		Label = label,
		Type = entry.Type,
		DisplayName = entry.DisplayName or instance.Name,
		ExpiresAt = os.clock(),
	}
end

function AuraRevealController:_resolveAdornee(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart")
	end

	if instance:IsA("BasePart") then
		return instance
	end

	return nil
end

function AuraRevealController:_styleReveal(active)
	local color = COLORS[active.Type] or Color3.fromRGB(180, 220, 255)
	active.Highlight.FillColor = color
	active.Highlight.OutlineColor = color
	active.Label.TextColor3 = color
	active.Label.Text = string.upper(active.DisplayName or "Reveal")
	active.Billboard.Adornee = self:_resolveAdornee(active.Instance)
end

function AuraRevealController:_refresh()
	local now = os.clock()
	for instance, active in pairs(self.Active) do
		if active.ExpiresAt <= now or instance == nil or instance.Parent == nil then
			self:_destroyReveal(active)
			self.Active[instance] = nil
		end
	end
end

function AuraRevealController:_destroyReveal(active)
	if active.Highlight then
		active.Highlight:Destroy()
	end

	if active.Billboard then
		active.Billboard:Destroy()
	end
end

return AuraRevealController
