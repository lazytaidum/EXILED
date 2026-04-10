local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RemnantController = {}
RemnantController.Name = "RemnantController"

function RemnantController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.State = {
		DisplayName = "Unknown",
		Fragments = 0,
		Abilities = {},
	}
	self.LastStateSyncAt = os.clock()
end

function RemnantController:Start()
	self.Remote = self.Remotes:WaitForChild(RemoteNames.RemnantStateChanged)
	self.RequestAbilityRemote = self.Remotes:WaitForChild(RemoteNames.RequestRemnantAbility)
	self:_createUI()

	self.Remote.OnClientEvent:Connect(function(state)
		self.State = state or self.State
		self.LastStateSyncAt = os.clock()
		self:_refresh()
	end)

	task.spawn(function()
		while true do
			self:_refresh()
			task.wait(0.1)
		end
	end)

	DebugLog:Log("ClientRemnant", "[RemnantController] Started")
end

function RemnantController:TriggerAbility(slotName)
	if not self.RequestAbilityRemote then
		return
	end

	local ability = self.State.Abilities and self.State.Abilities[slotName]
	if not ability or ability.IsImplemented == false then
		return
	end

	self.RequestAbilityRemote:FireServer(slotName)
end

function RemnantController:_createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RemnantUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.new(1, -18, 1, -18)
	root.Size = UDim2.new(0, 230, 0, 116)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(1, 1)
	header.Position = UDim2.new(1, 0, 0, 34)
	header.Size = UDim2.new(0, 230, 0, 34)
	header.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	header.BackgroundTransparency = 0.08
	header.BorderSizePixel = 0
	header.Parent = root

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 10, 0, 5)
	nameLabel.Size = UDim2.new(1, -80, 0, 12)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(218, 236, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = "Baam"
	nameLabel.Parent = header

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 10, 0, 18)
	subLabel.Size = UDim2.new(1, -20, 0, 10)
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = 10
	subLabel.TextColor3 = Color3.fromRGB(154, 170, 194)
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = "Fragments 0"
	subLabel.Parent = header

	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.AnchorPoint = Vector2.new(1, 1)
	cards.Position = UDim2.new(1, 0, 1, 0)
	cards.Size = UDim2.new(0, 230, 0, 72)
	cards.BackgroundTransparency = 1
	cards.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.Parent = cards

	self.UI = {
		Root = screenGui,
		NameLabel = nameLabel,
		SubLabel = subLabel,
		Cards = cards,
		CardBySlot = {},
	}

	for _, slotName in ipairs({ "Ability1", "Ability2", "Ability3" }) do
		local card = self:_createAbilityCard(cards, slotName)
		self.UI.CardBySlot[slotName] = card
	end
end

function RemnantController:_createAbilityCard(parent, slotName)
	local frame = Instance.new("Frame")
	frame.Name = slotName
	frame.Size = UDim2.new(0, 72, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Position = UDim2.new(0, 6, 0, 4)
	key.Size = UDim2.new(0, 18, 0, 12)
	key.Font = Enum.Font.GothamBold
	key.TextSize = 11
	key.TextColor3 = Color3.fromRGB(255, 231, 122)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.Text = "Q"
	key.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 6, 0, 18)
	title.Size = UDim2.new(1, -12, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextWrapped = true
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextColor3 = Color3.fromRGB(235, 239, 246)
	title.Text = slotName
	title.Parent = frame

	local state = Instance.new("TextLabel")
	state.Name = "State"
	state.BackgroundTransparency = 1
	state.Position = UDim2.new(0, 6, 1, -16)
	state.Size = UDim2.new(1, -12, 0, 12)
	state.Font = Enum.Font.Gotham
	state.TextSize = 10
	state.TextColor3 = Color3.fromRGB(132, 206, 255)
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.Text = "READY"
	state.Parent = frame

	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.new(0, 0, 1, 0)
	overlay.Size = UDim2.new(1, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Parent = frame

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 10)
	overlayCorner.Parent = overlay

	return {
		Frame = frame,
		Key = key,
		Title = title,
		State = state,
		Overlay = overlay,
	}
end

function RemnantController:_refresh()
	if not self.UI then
		return
	end

	self.UI.NameLabel.Text = self.State.DisplayName or "Unknown"
	self.UI.SubLabel.Text = string.format("Fragments %d", self.State.Fragments or 0)

	for _, slotName in ipairs({ "Ability1", "Ability2", "Ability3" }) do
		local card = self.UI.CardBySlot[slotName]
		local ability = self.State.Abilities and self.State.Abilities[slotName]
		if card and ability then
			card.Key.Text = ability.Keybind or "?"
			card.Title.Text = ability.DisplayName or slotName

			if ability.IsImplemented == false then
				card.State.Text = "SOON"
				card.State.TextColor3 = Color3.fromRGB(170, 170, 170)
				card.Overlay.Size = UDim2.new(1, 0, 1, 0)
			else
				local cooldown = math.max(0, ability.Cooldown or 0)
				local syncedRemaining = math.max(0, ability.CooldownRemaining or 0)
				local elapsed = math.max(0, os.clock() - (self.LastStateSyncAt or os.clock()))
				local remaining = math.max(0, syncedRemaining - elapsed)
				if remaining > 0 then
					card.State.Text = string.format("%.1fs", remaining)
					card.State.TextColor3 = Color3.fromRGB(255, 207, 115)
					local ratio = cooldown > 0 and math.clamp(remaining / cooldown, 0, 1) or 0
					card.Overlay.Size = UDim2.new(1, 0, ratio, 0)
				else
					card.State.Text = "READY"
					card.State.TextColor3 = Color3.fromRGB(132, 206, 255)
					card.Overlay.Size = UDim2.new(1, 0, 0, 0)
				end
			end
		end
	end
end

return RemnantController
