local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldMode = require(ReplicatedStorage.Shared.Enums.WorldMode)

local WORLD_MODE_ATTRIBUTE = "WorldMode"

local WorldModeResolver = {}

local function _normalizeWorldMode(rawMode)
	if rawMode == WorldMode.WeaponLab then
		return WorldMode.WeaponLab
	end

	return WorldMode.Gameplay
end

function WorldModeResolver.GetWorldMode()
	return _normalizeWorldMode(Workspace:GetAttribute(WORLD_MODE_ATTRIBUTE))
end

function WorldModeResolver.IsWeaponLab()
	return WorldModeResolver.GetWorldMode() == WorldMode.WeaponLab
end

return WorldModeResolver
