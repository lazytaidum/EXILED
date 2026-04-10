local FirearmAim = {}

function FirearmAim.ResolveLookVector(rootLookVector, requestedDirection)
	local lookVector = rootLookVector
	if typeof(requestedDirection) == "Vector3" and requestedDirection.Magnitude > 0.001 then
		local normalizedDirection = requestedDirection.Unit
		if rootLookVector:Dot(normalizedDirection) >= 0.25 then
			lookVector = normalizedDirection
		end
	end

	return lookVector
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

return FirearmAim
