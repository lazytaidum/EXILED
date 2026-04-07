local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)

local DebugLog = {}

function DebugLog:IsEnabled(flagName)
	if not DebugFlags.Enabled then
		return false
	end

	return DebugFlags[flagName] == true
end

function DebugLog:Log(flagName, ...)
	if not self:IsEnabled(flagName) then
		return
	end

	print(...)
end

return DebugLog
