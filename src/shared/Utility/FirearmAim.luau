local FirearmAim = {}

local DEFAULT_HANDLING = {
	HipfireSpread = 3.5,
	AimSpread = 0.55,
	RecoilKick = 1,
	RecoilRecovery = 11,
	AimFov = 56,
	AimCameraDistance = 9.25,
	AimShoulderOffset = 1.1,
	AimFocusForward = 3,
	TracerWidth = 0.24,
	MuzzleFlashSize = 0.75,
	ImpactFlashSize = 0.5,
	FireVisualColor = Color3.fromRGB(255, 226, 148),
	CameraKickPitch = 1,
	CameraKickYaw = 0.35,
}

function FirearmAim.ResolveLookVector(rootLookVector, requestedDirection)
	if typeof(requestedDirection) == "Vector3" and requestedDirection.Magnitude > 0.001 then
		return requestedDirection.Unit
	end

	return rootLookVector
end

function FirearmAim.GetMuzzleOrigin(rootCFrame, lookVector)
	local origin = rootCFrame.Position + Vector3.new(0, 1.5, 0)
	return origin + (lookVector * 2.15) + (rootCFrame.RightVector * 0.7) + Vector3.new(0, 0.55, 0)
end

function FirearmAim.ResolveAimPoint(cameraOrigin, lookVector, range, raycastParams, workspace)
	local fallbackPoint = cameraOrigin + (lookVector * range)
	if typeof(cameraOrigin) ~= "Vector3" or typeof(lookVector) ~= "Vector3" then
		return fallbackPoint
	end

	if workspace and raycastParams then
		local result = workspace:Raycast(cameraOrigin, lookVector * range, raycastParams)
		if result then
			return result.Position
		end
	end

	return fallbackPoint
end

function FirearmAim.GetHandlingData(weaponDefinition)
	local merged = table.clone(DEFAULT_HANDLING)
	if type(weaponDefinition) ~= "table" then
		return merged
	end

	for key, defaultValue in pairs(DEFAULT_HANDLING) do
		local value = weaponDefinition[key]
		if value ~= nil then
			merged[key] = value
		else
			merged[key] = defaultValue
		end
	end

	return merged
end

function FirearmAim.GetSpreadAngle(weaponDefinition, isAiming)
	local handling = FirearmAim.GetHandlingData(weaponDefinition)
	return isAiming and handling.AimSpread or handling.HipfireSpread
end

function FirearmAim.ApplySpread(lookVector, spreadAngleDegrees, randomGenerator)
	if typeof(lookVector) ~= "Vector3" or lookVector.Magnitude <= 0.001 then
		return lookVector
	end

	local spreadAngle = math.rad(math.max(0, tonumber(spreadAngleDegrees) or 0))
	if spreadAngle <= 0 then
		return lookVector.Unit
	end

	local rng = randomGenerator or Random.new()
	local base = lookVector.Unit
	local helper = math.abs(base.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local right = base:Cross(helper).Unit
	local up = right:Cross(base).Unit

	local yaw = rng:NextNumber(-spreadAngle, spreadAngle)
	local pitch = rng:NextNumber(-spreadAngle, spreadAngle)
	local spreadDirection = base + (right * math.tan(yaw)) + (up * math.tan(pitch))
	if spreadDirection.Magnitude <= 0.001 then
		return base
	end

	return spreadDirection.Unit
end

return FirearmAim
