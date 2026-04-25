local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SimplePath = require(ReplicatedStorage.Shared.Utility.SimplePath)

local MovingTargetPathTracker = {}
MovingTargetPathTracker.__index = MovingTargetPathTracker

local DEFAULT_RECOMPUTE_INTERVAL = 0.2
local DEFAULT_GOAL_STABILITY_DISTANCE = 12
local DEFAULT_PATH_COMMIT_DURATION = 1.2
local DEFAULT_REPATH_ESCAPE_DISTANCE = 18
local DEFAULT_TARGET_PREDICTION_SECONDS = 0.5
local DEFAULT_MAX_PREDICTION_DISTANCE = 18
local DEFAULT_NO_PREDICTION_DISTANCE = 10
local DEFAULT_FULL_PREDICTION_DISTANCE = 32
local DEFAULT_MIN_PREDICTION_SPEED = 1.5
local DEFAULT_TURN_PENALTY_STRENGTH = 1.85
local DEFAULT_DIRECT_CHASE_PREDICTION_SCALE = 0.4
local DEFAULT_DIRECT_CHASE_DISTANCE = 15
local DEFAULT_DIRECT_CHASE_EXIT_DISTANCE = 18
local DEFAULT_DIRECT_CHASE_LOS_MEMORY = 0.2
local DEFAULT_DIRECT_CHASE_LOS_CHECK_INTERVAL = 0.08
local DEFAULT_EYE_HEIGHT = 2.5
local DEFAULT_TARGET_CENTER_HEIGHT = 1.5
local DEFAULT_MOVEMENT_LANE_HEIGHT = 1.1
local DEFAULT_TARGET_MOVEMENT_LANE_HEIGHT = 0.8
local DEFAULT_STUCK_TIMEOUT = 0.45
local DEFAULT_STUCK_PROGRESS_DISTANCE = 1.2
local TARGET_SAMPLE_OFFSETS = {
	Vector3.zero,
	Vector3.new(0, -2.5, 0),
}

local function resolveTargetData(target)
	if typeof(target) == "Vector3" then
		return target, nil, Vector3.zero, nil
	end

	if type(target) == "function" then
		local ok, result = pcall(target)
		if ok then
			return resolveTargetData(result)
		end
		return nil, nil, nil, nil
	end

	if typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position, target.Parent or target, target.AssemblyLinearVelocity, target
		end

		if target:IsA("Model") then
			local primaryPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
			if primaryPart and primaryPart:IsA("BasePart") then
				local focusPart = target:FindFirstChild("UpperTorso")
					or target:FindFirstChild("Torso")
					or target:FindFirstChild("HumanoidRootPart")
					or primaryPart
				return primaryPart.Position, target, primaryPart.AssemblyLinearVelocity, focusPart
			end
		end
	end

	return nil, nil, nil, nil
end

local function planarDistance(a, b)
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return math.huge
	end

	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function clampPlanarMagnitude(vector, maxMagnitude)
	if typeof(vector) ~= "Vector3" then
		return Vector3.zero
	end

	local planar = Vector3.new(vector.X, 0, vector.Z)
	local magnitude = planar.Magnitude
	if magnitude <= 0 or magnitude <= maxMagnitude then
		return planar
	end

	return planar.Unit * maxMagnitude
end

local function projectToWalkablePosition(position, exclusions)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = exclusions or {}

	local rayOrigin = position + Vector3.new(0, 8, 0)
	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -40, 0), raycastParams)
	if result then
		return result.Position + Vector3.new(0, 0.1, 0)
	end

	return position
end

local function sampleWalkableTargetPosition(position, exclusions)
	for _, offset in ipairs(TARGET_SAMPLE_OFFSETS) do
		local projected = projectToWalkablePosition(position + offset, exclusions)
		if projected then
			return projected
		end
	end

	return nil
end

function MovingTargetPathTracker.new(npcModel, target, options)
	options = options or {}

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local rootPart = npcModel.PrimaryPart or npcModel:FindFirstChild("HumanoidRootPart")
	assert(humanoid, "[MovingTargetPathTracker] NPC model must contain a Humanoid")
	assert(rootPart and rootPart:IsA("BasePart"), "[MovingTargetPathTracker] NPC model must have a PrimaryPart or HumanoidRootPart")

	local path = SimplePath.new(npcModel, {
		AgentRadius = options.AgentRadius or 2,
		AgentHeight = options.AgentHeight or 5,
		AgentCanJump = options.AgentCanJump == true,
		WaypointSpacing = options.WaypointSpacing or 4,
	}, {
		TIME_VARIANCE = math.max(0.07, (options.RecomputeInterval or DEFAULT_RECOMPUTE_INTERVAL) * 0.5),
		COMPARISON_CHECKS = 2,
		JUMP_WHEN_STUCK = options.AgentCanJump == true,
	})

	local self = setmetatable({
		Model = npcModel,
		Humanoid = humanoid,
		RootPart = rootPart,
		Target = target,
		Path = path,
		Running = false,
		RunToken = 0,
		Destroyed = false,
		CleanupRequested = false,
		ActivePathCalls = 0,
		RecomputeInterval = options.RecomputeInterval or DEFAULT_RECOMPUTE_INTERVAL,
		GoalStabilityDistance = options.GoalStabilityDistance or DEFAULT_GOAL_STABILITY_DISTANCE,
		PathCommitDuration = options.PathCommitDuration or DEFAULT_PATH_COMMIT_DURATION,
		RepathEscapeDistance = options.RepathEscapeDistance or DEFAULT_REPATH_ESCAPE_DISTANCE,
		TargetPredictionSeconds = options.TargetPredictionSeconds or DEFAULT_TARGET_PREDICTION_SECONDS,
		MaxPredictionDistance = options.MaxPredictionDistance or DEFAULT_MAX_PREDICTION_DISTANCE,
		NoPredictionDistance = options.NoPredictionDistance or DEFAULT_NO_PREDICTION_DISTANCE,
		FullPredictionDistance = options.FullPredictionDistance or DEFAULT_FULL_PREDICTION_DISTANCE,
		MinPredictionSpeed = options.MinPredictionSpeed or DEFAULT_MIN_PREDICTION_SPEED,
		TurnPenaltyStrength = options.TurnPenaltyStrength or DEFAULT_TURN_PENALTY_STRENGTH,
		DirectChasePredictionScale = options.DirectChasePredictionScale or DEFAULT_DIRECT_CHASE_PREDICTION_SCALE,
		DirectChaseDistance = options.DirectChaseDistance or DEFAULT_DIRECT_CHASE_DISTANCE,
		DirectChaseExitDistance = options.DirectChaseExitDistance or DEFAULT_DIRECT_CHASE_EXIT_DISTANCE,
		DirectChaseLoSMemory = options.DirectChaseLoSMemory or DEFAULT_DIRECT_CHASE_LOS_MEMORY,
		DirectChaseLoSCheckInterval = options.DirectChaseLoSCheckInterval or DEFAULT_DIRECT_CHASE_LOS_CHECK_INTERVAL,
		EyeHeight = options.EyeHeight or DEFAULT_EYE_HEIGHT,
		TargetCenterHeight = options.TargetCenterHeight or DEFAULT_TARGET_CENTER_HEIGHT,
		MovementLaneHeight = options.MovementLaneHeight or DEFAULT_MOVEMENT_LANE_HEIGHT,
		TargetMovementLaneHeight = options.TargetMovementLaneHeight or DEFAULT_TARGET_MOVEMENT_LANE_HEIGHT,
		StuckTimeout = options.StuckTimeout or DEFAULT_STUCK_TIMEOUT,
		StuckProgressDistance = options.StuckProgressDistance or DEFAULT_STUCK_PROGRESS_DISTANCE,
		CanDirectChase = options.CanDirectChase,
		CanCommitGoal = options.CanCommitGoal,
		LastGoalPosition = nil,
		LastPathSetAt = 0,
		DirectChasing = false,
		DirectChaseVisibleUntil = 0,
		LastDirectChaseLoSCheckAt = 0,
		LastDirectChaseLoSResult = false,
		LastDirectChaseLoSPosition = nil,
		LastDirectChaseLoSTarget = nil,
		LastDirectChaseMovementLaneResult = false,
		LastTargetVelocityDirection = nil,
		LastPredictionSecondsUsed = 0,
		LastTurnSeverity = 0,
		LastPredictionMode = "None",
		LastProgressPosition = rootPart.Position,
		LastProgressAt = os.clock(),
		LastForcedRepathAt = 0,
	}, MovingTargetPathTracker)

	return self
end

function MovingTargetPathTracker:_finalizePathCleanup()
	if not self.CleanupRequested or self.ActivePathCalls > 0 then
		return
	end

	local path = self.Path
	self.Path = nil
	self.CleanupRequested = false
	if path then
		pcall(function()
			path:Destroy()
		end)
	end
end

function MovingTargetPathTracker:_withPath(callback)
	local path = self.Path
	if not path then
		return nil
	end

	self.ActivePathCalls += 1
	local ok, result = pcall(callback, path)
	self.ActivePathCalls -= 1
	self:_finalizePathCleanup()
	if not ok then
		warn(string.format("[MovingTargetPathTracker] Path call failed: %s", tostring(result)))
		return nil
	end

	return result
end

function MovingTargetPathTracker:_canCommitGoal()
	if type(self.CanCommitGoal) ~= "function" then
		return true
	end

	local ok, canCommitGoal = pcall(self.CanCommitGoal, self)
	return ok and canCommitGoal ~= false
end

function MovingTargetPathTracker:_computePredictionOffset(targetPosition, targetVelocity, isDirectChase)
	if not self.RootPart or typeof(targetPosition) ~= "Vector3" then
		self.LastPredictionSecondsUsed = 0
		self.LastTurnSeverity = 0
		self.LastPredictionMode = "Invalid"
		return Vector3.zero
	end

	local planarVelocity = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
	local speed = planarVelocity.Magnitude
	local currentDirection = speed >= self.MinPredictionSpeed and planarVelocity.Unit or nil
	local previousDirection = self.LastTargetVelocityDirection
	local turnSeverity = 0
	if currentDirection and previousDirection then
		local directionDot = math.clamp(previousDirection:Dot(currentDirection), -1, 1)
		turnSeverity = (1 - directionDot) * 0.5
	end
	self.LastTargetVelocityDirection = currentDirection

	local targetDistance = planarDistance(self.RootPart.Position, targetPosition)
	local distanceRange = math.max(0.001, self.FullPredictionDistance - self.NoPredictionDistance)
	local distanceFactor = math.clamp((targetDistance - self.NoPredictionDistance) / distanceRange, 0, 1)
	local turnFactor = math.clamp(1 - (turnSeverity * self.TurnPenaltyStrength), 0, 1)
	local predictionSeconds = self.TargetPredictionSeconds * distanceFactor * turnFactor
	local predictionMode = "Adaptive"

	if speed < self.MinPredictionSpeed then
		predictionSeconds = 0
		predictionMode = "Slow"
	elseif targetDistance <= self.NoPredictionDistance then
		predictionSeconds = 0
		predictionMode = "Close"
	elseif turnFactor <= 0.05 then
		predictionSeconds = 0
		predictionMode = "Turning"
	end

	if isDirectChase and predictionSeconds > 0 then
		predictionSeconds *= self.DirectChasePredictionScale
		predictionMode = "Direct"
	end

	self.LastPredictionSecondsUsed = predictionSeconds
	self.LastTurnSeverity = turnSeverity
	self.LastPredictionMode = predictionMode

	return clampPlanarMagnitude(planarVelocity * predictionSeconds, self.MaxPredictionDistance)
end

function MovingTargetPathTracker:_isPredictionObstructed(targetPosition, predictedTargetPosition, targetIgnore)
	if typeof(targetPosition) ~= "Vector3" or typeof(predictedTargetPosition) ~= "Vector3" then
		return false
	end

	local origin = targetPosition + Vector3.new(0, self.TargetCenterHeight, 0)
	local destination = predictedTargetPosition + Vector3.new(0, self.TargetCenterHeight, 0)
	local direction = destination - origin
	if direction.Magnitude <= 0.05 then
		return false
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Model, targetIgnore }

	return Workspace:Raycast(origin, direction, raycastParams) ~= nil
end

function MovingTargetPathTracker:_getRemainingPathDistance()
	if not self.RootPart or not self.Path then
		return nil
	end

	local rawWaypoints = rawget(self.Path, "_waypoints")
	if type(rawWaypoints) ~= "table" or #rawWaypoints <= 0 then
		return nil
	end

	local currentWaypoint = tonumber(rawget(self.Path, "_currentWaypoint")) or 0
	local firstIndex = math.clamp(currentWaypoint, 1, #rawWaypoints)
	local previousPosition = self.RootPart.Position
	local totalDistance = 0

	for index = firstIndex, #rawWaypoints do
		local waypoint = rawWaypoints[index]
		local waypointPosition = waypoint and waypoint.Position or nil
		if typeof(waypointPosition) == "Vector3" then
			totalDistance += planarDistance(previousPosition, waypointPosition)
			previousPosition = waypointPosition
		end
	end

	return totalDistance > 0 and totalDistance or nil
end

function MovingTargetPathTracker:_resolveGoalPosition()
	local targetPosition, targetIgnore, targetVelocity = resolveTargetData(self.Target)
	if not targetPosition then
		return nil
	end

	local actualProjectedPosition = sampleWalkableTargetPosition(targetPosition, { self.Model, targetIgnore })
	local predictedOffset = self:_computePredictionOffset(targetPosition, targetVelocity or Vector3.zero, false)
	local predictedTargetPosition = targetPosition + predictedOffset

	if predictedOffset.Magnitude <= 0.05 then
		return actualProjectedPosition or targetPosition
	end

	if self:_isPredictionObstructed(targetPosition, predictedTargetPosition, targetIgnore) then
		self.LastPredictionMode = "Clipped"
		self.LastPredictionSecondsUsed = 0
		return actualProjectedPosition or targetPosition
	end

	local predictedProjectedPosition = sampleWalkableTargetPosition(predictedTargetPosition, { self.Model, targetIgnore })
	if predictedProjectedPosition then
		return predictedProjectedPosition
	end

	self.LastPredictionMode = "Fallback"
	self.LastPredictionSecondsUsed = 0
	return actualProjectedPosition or targetPosition
end

function MovingTargetPathTracker:_resolveDirectChasePosition()
	local targetPosition, _, targetVelocity, targetPart = resolveTargetData(self.Target)
	if not targetPosition then
		return nil
	end

	local predictedOffset = self:_computePredictionOffset(targetPosition, targetVelocity or Vector3.zero, true)
	local predictedTargetPosition = targetPosition + predictedOffset

	if targetPart and targetPart:IsA("BasePart") then
		return predictedTargetPosition + Vector3.new(0, self.TargetCenterHeight, 0), targetPart, predictedTargetPosition
	end

	return predictedTargetPosition + Vector3.new(0, self.TargetCenterHeight, 0), nil, predictedTargetPosition
end

function MovingTargetPathTracker:_hasDirectLineOfSight(targetPosition, targetPart)
	if typeof(targetPosition) ~= "Vector3" or not self.RootPart then
		return false
	end

	local origin = self.RootPart.Position + Vector3.new(0, self.EyeHeight, 0)
	local direction = targetPosition - origin
	if direction.Magnitude <= 0.01 then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Model }

	local result = Workspace:Raycast(origin, direction, raycastParams)
	if not result then
		return true
	end

	if targetPart and (result.Instance == targetPart or result.Instance:IsDescendantOf(targetPart.Parent or targetPart)) then
		return true
	end

	return false
end

function MovingTargetPathTracker:_getDirectLineOfSight(targetPosition, targetPart)
	local now = os.clock()
	local canReuseResult = self.LastDirectChaseLoSTarget == targetPart
		and self.LastDirectChaseLoSPosition ~= nil
		and planarDistance(targetPosition, self.LastDirectChaseLoSPosition) <= 1
		and (now - (self.LastDirectChaseLoSCheckAt or 0)) < self.DirectChaseLoSCheckInterval
	if canReuseResult then
		return self.LastDirectChaseLoSResult == true
	end

	local hasLineOfSight = self:_hasDirectLineOfSight(targetPosition, targetPart)
	self.LastDirectChaseLoSCheckAt = now
	self.LastDirectChaseLoSResult = hasLineOfSight == true
	self.LastDirectChaseLoSPosition = targetPosition
	self.LastDirectChaseLoSTarget = targetPart
	return hasLineOfSight
end

function MovingTargetPathTracker:_hasDirectMovementLane(targetPosition, targetPart)
	if typeof(targetPosition) ~= "Vector3" or not self.RootPart then
		return false
	end

	local origin = self.RootPart.Position + Vector3.new(0, self.MovementLaneHeight, 0)
	local destination = targetPosition - Vector3.new(0, math.max(0, self.TargetCenterHeight - self.TargetMovementLaneHeight), 0)
	local direction = destination - origin
	if direction.Magnitude <= 0.01 then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Model }

	local result = Workspace:Raycast(origin, direction, raycastParams)
	if not result then
		return true
	end

	if targetPart and (result.Instance == targetPart or result.Instance:IsDescendantOf(targetPart.Parent or targetPart)) then
		return true
	end

	return false
end

function MovingTargetPathTracker:_shouldDirectChase(targetPosition, targetPart)
	if type(self.CanDirectChase) == "function" then
		local ok, canDirectChase = pcall(self.CanDirectChase, self)
		if not ok or canDirectChase ~= true then
			self.DirectChaseVisibleUntil = 0
			return false
		end
	end

	if typeof(targetPosition) ~= "Vector3" or not self.RootPart then
		return false
	end

	local distance = planarDistance(self.RootPart.Position, targetPosition)
	local allowedDistance = self.DirectChasing and self.DirectChaseExitDistance or self.DirectChaseDistance
	if distance > allowedDistance then
		self.DirectChaseVisibleUntil = 0
		return false
	end

	local hasLineOfSight = self:_getDirectLineOfSight(targetPosition, targetPart)
	local hasMovementLane = self:_hasDirectMovementLane(targetPosition, targetPart)
	self.LastDirectChaseMovementLaneResult = hasMovementLane == true
	local now = os.clock()
	if hasLineOfSight and hasMovementLane then
		self.DirectChaseVisibleUntil = now + self.DirectChaseLoSMemory
		return true
	end

	return self.DirectChasing and hasMovementLane and now <= (self.DirectChaseVisibleUntil or 0)
end

function MovingTargetPathTracker:_setDirectChasing(state)
	if self.DirectChasing == state then
		return
	end

	self.DirectChasing = state
	if state and self:_isActivelyPathing() then
		self:_withPath(function(path)
			path:Stop()
		end)
	elseif not state then
		self.DirectChaseVisibleUntil = 0
		self.LastDirectChaseLoSCheckAt = 0
		self.LastDirectChaseLoSResult = false
		self.LastDirectChaseLoSPosition = nil
		self.LastDirectChaseLoSTarget = nil
	end
end

function MovingTargetPathTracker:_runDirectMoveLoop()
	local runToken = self.RunToken
	while self.Running and self.RunToken == runToken and not self.Destroyed do
		local directTargetPosition, targetPart, moveTargetPosition = self:_resolveDirectChasePosition()
		local shouldDirectChase = self:_shouldDirectChase(directTargetPosition, targetPart)
		self:_setDirectChasing(shouldDirectChase)
		if shouldDirectChase then
			self.Humanoid:MoveTo(moveTargetPosition or directTargetPosition)
		end

		RunService.Heartbeat:Wait()
	end
end

function MovingTargetPathTracker:_isActivelyPathing()
	local path = self.Path
	return path ~= nil and path.Status == SimplePath.StatusType.Active
end

function MovingTargetPathTracker:_shouldRepath(goalPosition)
	if typeof(goalPosition) ~= "Vector3" then
		return false
	end

	if not self:_isActivelyPathing() then
		return true
	end

	local shiftDistance = planarDistance(goalPosition, self.LastGoalPosition)
	if not self:_canCommitGoal() then
		return shiftDistance > 0.75
	end

	if shiftDistance <= self.GoalStabilityDistance then
		return false
	end

	local pathAge = os.clock() - (self.LastPathSetAt or 0)
	if pathAge < self.PathCommitDuration then
		return false
	end

	return shiftDistance > self.RepathEscapeDistance
end

function MovingTargetPathTracker:_refreshProgressMarker(forceReset)
	if not self.RootPart then
		return
	end

	local currentPosition = self.RootPart.Position
	if forceReset or planarDistance(currentPosition, self.LastProgressPosition) >= self.StuckProgressDistance then
		self.LastProgressPosition = currentPosition
		self.LastProgressAt = os.clock()
	end
end

function MovingTargetPathTracker:_shouldForceRepath()
	if not self:_isActivelyPathing() or not self.RootPart then
		self:_refreshProgressMarker(true)
		return false
	end

	self:_refreshProgressMarker(false)
	return (os.clock() - (self.LastProgressAt or 0)) >= self.StuckTimeout
end

function MovingTargetPathTracker:_runLoop()
	local runToken = self.RunToken
	while self.Running and self.RunToken == runToken and not self.Destroyed do
		if self.DirectChasing then
			self:_refreshProgressMarker(true)
			task.wait(self.RecomputeInterval)
			continue
		end

		local goalPosition = self:_resolveGoalPosition()
		if not goalPosition then
			if self:_isActivelyPathing() then
				self:_withPath(function(path)
					path:Stop()
				end)
			end
			self.LastGoalPosition = nil
			self.LastPathSetAt = 0
			task.wait(self.RecomputeInterval)
			continue
		end

		if self:_canCommitGoal()
			and self.LastGoalPosition
			and planarDistance(goalPosition, self.LastGoalPosition) <= self.GoalStabilityDistance
		then
			goalPosition = self.LastGoalPosition
		end

		if self:_shouldForceRepath() then
			self:_withPath(function(path)
				path:Stop()
			end)
			self.LastGoalPosition = nil
			self.LastPathSetAt = 0
			self.LastForcedRepathAt = os.clock()
		end

		if self:_shouldRepath(goalPosition) then
			local ran = self:_withPath(function(path)
				return path:Run(goalPosition)
			end)
			if ran then
				self.LastGoalPosition = goalPosition
				self.LastPathSetAt = os.clock()
				self:_refreshProgressMarker(true)
			end
		end

		task.wait(self.RecomputeInterval)
	end
end

function MovingTargetPathTracker:GetDebugSnapshot()
	local targetPosition = select(1, resolveTargetData(self.Target))
	local targetDistance = nil
	if self.RootPart and typeof(targetPosition) == "Vector3" then
		targetDistance = planarDistance(self.RootPart.Position, targetPosition)
	end

	local goalDistance = nil
	if self.RootPart and typeof(self.LastGoalPosition) == "Vector3" then
		goalDistance = planarDistance(self.RootPart.Position, self.LastGoalPosition)
	end

	local path = self.Path
	local waypointCount = 0
	local currentWaypoint = 0
	local pathStatus = "Destroyed"
	local lastPathError = ""
	local remainingPathDistance = nil
	if path then
		pathStatus = tostring(path.Status or "Unknown")
		lastPathError = path.LastError and tostring(path.LastError) or ""
		local rawWaypoints = rawget(path, "_waypoints")
		if type(rawWaypoints) == "table" then
			waypointCount = #rawWaypoints
		end
		currentWaypoint = tonumber(rawget(path, "_currentWaypoint")) or 0
		remainingPathDistance = self:_getRemainingPathDistance()
	end

	local moveMode = "Idle"
	if self.DirectChasing then
		moveMode = "Direct"
	elseif self:_isActivelyPathing() then
		moveMode = "Path"
	elseif typeof(self.LastGoalPosition) == "Vector3" then
		moveMode = "Committed"
	end

	return {
		MoveMode = moveMode,
		PathStatus = pathStatus,
		LastPathError = lastPathError,
		WaypointIndex = currentWaypoint,
		WaypointCount = waypointCount,
		RemainingPathDistance = remainingPathDistance,
		TargetDistance = targetDistance,
		GoalDistance = goalDistance,
		PredictionSecondsUsed = self.LastPredictionSecondsUsed,
		TurnSeverity = self.LastTurnSeverity,
		PredictionMode = self.LastPredictionMode,
		PathAge = self.LastPathSetAt > 0 and (os.clock() - self.LastPathSetAt) or nil,
		HasLineOfSight = self.LastDirectChaseLoSCheckAt > 0 and self.LastDirectChaseLoSResult == true or nil,
		HasMovementLane = self.LastDirectChaseMovementLaneResult == true,
		DirectGraceRemaining = math.max(0, (self.DirectChaseVisibleUntil or 0) - os.clock()),
		StuckAge = os.clock() - (self.LastProgressAt or os.clock()),
		LastForcedRepathAge = self.LastForcedRepathAt > 0 and (os.clock() - self.LastForcedRepathAt) or nil,
	}
end

function MovingTargetPathTracker:Start()
	if self.Running or self.Destroyed then
		return
	end

	self.Running = true
	self.RunToken += 1
	task.spawn(function()
		self:_runLoop()
	end)
	task.spawn(function()
		self:_runDirectMoveLoop()
	end)
end

function MovingTargetPathTracker:Stop()
	if self.Destroyed then
		return
	end

	self.Running = false
	self.RunToken += 1
	self.LastGoalPosition = nil
	self.LastPathSetAt = 0
	self.DirectChasing = false
	self.CleanupRequested = true
	self.LastDirectChaseLoSCheckAt = 0
	self.LastDirectChaseLoSResult = false
	self.LastDirectChaseLoSPosition = nil
	self.LastDirectChaseLoSTarget = nil
	self.LastDirectChaseMovementLaneResult = false
	self.LastTargetVelocityDirection = nil
	self.LastPredictionSecondsUsed = 0
	self.LastTurnSeverity = 0
	self.LastPredictionMode = "None"
	self.LastProgressPosition = self.RootPart and self.RootPart.Position or Vector3.zero
	self.LastProgressAt = os.clock()
	self.LastForcedRepathAt = 0

	if self.Path then
		if self.Path.Status == SimplePath.StatusType.Active then
			self:_withPath(function(path)
				path:Stop()
			end)
		end
	end

	self:_finalizePathCleanup()

	self.Destroyed = true
	if self.Humanoid then
		self.Humanoid:Move(Vector3.zero, false)
	end
end

return MovingTargetPathTracker
