local UISkin = {}

UISkin.Colors = {
	Surface = Color3.fromRGB(15, 18, 26),
	SurfaceRaised = Color3.fromRGB(22, 27, 38),
	SurfaceSoft = Color3.fromRGB(29, 34, 48),
	Panel = Color3.fromRGB(12, 15, 22),
	Text = Color3.fromRGB(240, 242, 247),
	TextSoft = Color3.fromRGB(183, 190, 206),
	TextMuted = Color3.fromRGB(126, 137, 159),
	Blue = Color3.fromRGB(111, 194, 255),
	Gold = Color3.fromRGB(242, 212, 103),
	Green = Color3.fromRGB(124, 214, 166),
	Violet = Color3.fromRGB(195, 156, 255),
	Red = Color3.fromRGB(255, 116, 122),
}

UISkin.Assets = {
	Cards = {
		Default = "",
		Browser = "",
		Inset = "",
	},
	Buttons = {
		Default = "",
		Accent = "",
		Danger = "",
	},
	Icons = {
		Bestiary = "rbxassetid://81548264765271",
		Timer = "rbxassetid://79601943786842",
		Remnants = "rbxassetid://128871259478100",
		Backpack = "rbxassetid://114168771033976",
		Shop = "rbxassetid://99089679395851",
		Spectate = "rbxassetid://90142716595585",
	},
}

UISkin.DefaultSliceCenter = Rect.new(24, 24, 24, 24)

function UISkin:GetAsset(category, key)
	local group = self.Assets[category]
	if type(group) ~= "table" then
		return ""
	end

	local value = group[key]
	if type(value) == "string" or type(value) == "table" then
		return value
	end

	return ""
end

function UISkin:_normalizeAsset(asset)
	if type(asset) == "table" then
		return {
			Image = asset.Image or "",
			ScaleType = asset.ScaleType or Enum.ScaleType.Stretch,
			SliceCenter = asset.SliceCenter or self.DefaultSliceCenter,
		}
	end

	if type(asset) == "string" then
		return {
			Image = asset,
			ScaleType = Enum.ScaleType.Stretch,
			SliceCenter = self.DefaultSliceCenter,
		}
	end

	return {
		Image = "",
		ScaleType = Enum.ScaleType.Stretch,
		SliceCenter = self.DefaultSliceCenter,
	}
end

function UISkin:_attachSkinImage(parent, name, assetId)
	local normalized = self:_normalizeAsset(assetId)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = normalized.Image
	image.ImageTransparency = 0
	image.ScaleType = normalized.ScaleType
	image.SliceCenter = normalized.SliceCenter
	image.Visible = image.Image ~= ""
	image.ZIndex = math.max(parent.ZIndex, 1)
	image.Parent = parent

	local parentCorner = parent:FindFirstChildOfClass("UICorner")
	if parentCorner then
		local imageCorner = parentCorner:Clone()
		imageCorner.Parent = image
	end

	return image
end

function UISkin:ApplyCardSkin(frame, key)
	return self:_attachSkinImage(frame, "SkinImage", self:GetAsset("Cards", key or "Default"))
end

function UISkin:ApplyButtonSkin(button, key)
	local asset = self:GetAsset("Buttons", key or "Default")
	if type(asset) == "string" and asset ~= "" then
		asset = {
			Image = asset,
			ScaleType = Enum.ScaleType.Crop,
		}
	end

	return self:_attachSkinImage(button, "SkinImage", asset)
end

function UISkin:CreateArtSlot(parent, name, position, size)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Position = position or UDim2.new()
	image.Size = size or UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = parent
	return image
end

return UISkin
