local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local NotificationController = {}
NotificationController.Name = "NotificationController"

local TINTS = {
	Weapon = Color3.fromRGB(103, 194, 255),
	Item = Color3.fromRGB(124, 214, 166),
	Ability = Color3.fromRGB(242, 212, 103),
	Default = Color3.fromRGB(214, 216, 224),
}

function NotificationController:Init()
	self.PlayerGui = self.World.PlayerGui
	self.Remotes = self.World.Remotes
	self.ActiveToasts = {}
end

function NotificationController:Start()
	self.Remote = self.Remotes:WaitForChild(RemoteNames.UiToastRequested)
	self:_createUi()

	self.Remote.OnClientEvent:Connect(function(payload)
		self:_pushToast(payload or {})
	end)

	task.spawn(function()
		while true do
			self:_refresh()
			task.wait(0.05)
		end
	end)

	DebugLog:Log("ClientInteraction", "[NotificationController] Started")
end

function NotificationController:_createUi()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NotificationUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.PlayerGui

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(1, 0)
	stack.Position = UDim2.new(1, -18, 0, 18)
	stack.Size = UDim2.new(0, 280, 0, 220)
	stack.BackgroundTransparency = 1
	stack.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 8)
	layout.Parent = stack

	self.UI = {
		Root = screenGui,
		Stack = stack,
	}
end

function NotificationController:_pushToast(payload)
	local title = tostring(payload.Title or "Notice")
	local message = tostring(payload.Message or "")
	local tint = TINTS[payload.Tint] or TINTS.Default

	local card = Instance.new("Frame")
	card.Name = "Toast"
	card.Size = UDim2.new(0, 280, 0, 48)
	card.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = self.UI.Stack

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = tint
	stripe.BorderSizePixel = 0
	stripe.Parent = card

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 10)
	stripeCorner.Parent = stripe

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 12, 0, 6)
	titleLabel.Size = UDim2.new(1, -18, 0, 14)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 12
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = tint
	titleLabel.Text = title
	titleLabel.Parent = card

	local messageLabel = Instance.new("TextLabel")
	messageLabel.BackgroundTransparency = 1
	messageLabel.Position = UDim2.new(0, 12, 0, 22)
	messageLabel.Size = UDim2.new(1, -18, 0, 18)
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.TextSize = 12
	messageLabel.TextXAlignment = Enum.TextXAlignment.Left
	messageLabel.TextColor3 = Color3.fromRGB(235, 239, 246)
	messageLabel.Text = message
	messageLabel.Parent = card

	table.insert(self.ActiveToasts, {
		Card = card,
		ExpiresAt = os.clock() + 2.2,
	})
end

function NotificationController:_refresh()
	local now = os.clock()
	for index = #self.ActiveToasts, 1, -1 do
		local toast = self.ActiveToasts[index]
		if not toast.Card.Parent or now >= toast.ExpiresAt then
			if toast.Card then
				toast.Card:Destroy()
			end
			table.remove(self.ActiveToasts, index)
		end
	end
end

return NotificationController
