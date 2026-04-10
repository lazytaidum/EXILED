local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local InterestService = {}
InterestService.Name = "InterestService"
InterestService.Dependencies = {
	"RoundManager",
	"CharacterService",
}

function InterestService:Init(services)
	self.Services = services
	self.Points = {}
	self.LastPointByPlayer = {}
	self.SampleInterval = 0.4
	self.MinMoveDistance = 6
	self.PointLifetime = 5
	self.DefaultInterestRadius = 140
	self.BaseFollowDistance = 10
	self.SprintMoveDistanceMultiplier = 0.75
	self.SprintStrengthMultiplier = 1.45
	self.SprintLifetimeMultiplier = 1.2
	self.SprintFollowDistanceMultiplier = 1.35
	self.CrouchMoveDistanceMultiplier = 1.75
	self.CrouchStrengthMultiplier = 0.35
	self.CrouchLifetimeMultiplier = 0.6
	self.CrouchFollowDistanceMultiplier = 0.65
end

function InterestService:Start()
	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Entity", "[InterestService] Started")
end

function InterestService:_runLoop()
	while true do
		self:_cleanupExpiredPoints()
		self:_sampleActivePlayers()
		task.wait(self.SampleInterval)
	end
end

function InterestService:_cleanupExpiredPoints()
	local now = os.clock()
	for index = #self.Points, 1, -1 do
		local point = self.Points[index]
		if point.ExpiresAt <= now then
			table.remove(self.Points, index)
		end
	end
end

function InterestService:_sampleActivePlayers()
	local roundManager = self.RoundManager
	local characterService = self.CharacterService
	if not roundManager or not characterService or not roundManager:IsReceptionActive() then
		return
	end

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				self:_sampleCharacterInterest(player, character)
			end
		end
	end
end

function InterestService:_sampleCharacterInterest(player, character)
	local position = character.RootPart.Position
	local lastPoint = self.LastPointByPlayer[player]
	local isCrouching = character.IsCrouching == true
	local isSprinting = character.IsSprinting == true
	local moveDistanceMultiplier = 1
	local strengthMultiplier = 1
	local lifetimeMultiplier = 1
	local followDistanceMultiplier = 1

	if isSprinting then
		moveDistanceMultiplier *= self.SprintMoveDistanceMultiplier
		strengthMultiplier *= self.SprintStrengthMultiplier
		lifetimeMultiplier *= self.SprintLifetimeMultiplier
		followDistanceMultiplier *= self.SprintFollowDistanceMultiplier
	end

	if isCrouching then
		moveDistanceMultiplier *= self.CrouchMoveDistanceMultiplier
		strengthMultiplier *= self.CrouchStrengthMultiplier
		lifetimeMultiplier *= self.CrouchLifetimeMultiplier
		followDistanceMultiplier *= self.CrouchFollowDistanceMultiplier
	end

	local minMoveDistance = self.MinMoveDistance * moveDistanceMultiplier
	if lastPoint and (position - lastPoint.Position).Magnitude < minMoveDistance then
		return
	end

	local direction = Vector3.zero
	if lastPoint then
		local delta = position - lastPoint.Position
		if delta.Magnitude > 0 then
			direction = delta.Unit
		end
	end

	local point = {
		Player = player,
		Position = position,
		Direction = direction,
		FollowDistance = self.BaseFollowDistance * followDistanceMultiplier,
		CreatedAt = os.clock(),
		ExpiresAt = os.clock() + (self.PointLifetime * lifetimeMultiplier),
		Strength = strengthMultiplier,
	}

	table.insert(self.Points, point)
	self.LastPointByPlayer[player] = point
end

function InterestService:GetStrongestInterestNear(position, radius, options)
	if not position then
		return nil
	end

	options = options or {}
	radius = radius or self.DefaultInterestRadius
	local now = os.clock()
	local bestPoint = nil
	local bestScore = -math.huge

	for _, point in ipairs(self.Points) do
		local offset = point.Position - position
		local distance = offset.Magnitude
		if distance <= radius then
			local ageAlpha = math.clamp((point.ExpiresAt - now) / self.PointLifetime, 0, 1)
			local score = (ageAlpha * 100) + math.max(0, radius - distance) + (point.Strength or 1) * 10
			if options.WeightByDirection and point.Direction and point.Direction.Magnitude > 0 then
				local toPoint = offset.Magnitude > 0 and offset.Unit or Vector3.zero
				score += math.max(0, point.Direction:Dot(toPoint)) * 12
			end
			if options.PreferPlayer and point.Player == options.PreferPlayer then
				score += 30
			end
			if score > bestScore then
				bestScore = score
				bestPoint = point
			end
		end
	end

	if bestPoint and bestPoint.Direction and bestPoint.Direction.Magnitude > 0 then
		bestPoint = table.clone(bestPoint)
		bestPoint.Destination = bestPoint.Position + (bestPoint.Direction * (bestPoint.FollowDistance or self.BaseFollowDistance))
	elseif bestPoint then
		bestPoint = table.clone(bestPoint)
		bestPoint.Destination = bestPoint.Position
	end

	return bestPoint
end

function InterestService:Reset()
	table.clear(self.Points)
	table.clear(self.LastPointByPlayer)
end

return InterestService
