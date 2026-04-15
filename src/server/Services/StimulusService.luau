local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local StimulusService = {}
StimulusService.Name = "StimulusService"
StimulusService.Dependencies = {
	"RoundManager",
	"CharacterService",
}

function StimulusService:Init(services)
	self.Services = services
	self.Stimuli = {}
	self.ActiveStimuliByKey = {}
	self.LastMovementStimulusByPlayer = {}
	self.NextStimulusId = 0

	self.SampleInterval = 0.4
	self.MinMoveDistance = 6
	self.DefaultLifetime = 5
	self.DefaultStimulusRadius = 140
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

function StimulusService:Start()
	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Entity", "[StimulusService] Started")
end

function StimulusService:_runLoop()
	while true do
		self:_cleanupExpiredStimuli()
		self:_sampleMovementNoise()
		task.wait(self.SampleInterval)
	end
end

function StimulusService:_cleanupExpiredStimuli()
	local now = os.clock()
	for index = #self.Stimuli, 1, -1 do
		local stimulus = self.Stimuli[index]
		if stimulus.ExpiresAt <= now then
			table.remove(self.Stimuli, index)
			if stimulus.Key and self.ActiveStimuliByKey[stimulus.Key] == stimulus then
				self.ActiveStimuliByKey[stimulus.Key] = nil
			end
		end
	end
end

function StimulusService:_sampleMovementNoise()
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
				self:_sampleCharacterMovementNoise(player, character)
			end
		end
	end
end

function StimulusService:_sampleCharacterMovementNoise(player, character)
	local position = character.RootPart.Position
	local lastStimulus = self.LastMovementStimulusByPlayer[player]
	local isCrouching = character.IsCrouching == true
	local isSprinting = character.IsSprinting == true
	local isRunning = character.IsRunning == true
	local moveDistanceMultiplier = 1
	local strengthMultiplier = 1
	local lifetimeMultiplier = 1
	local followDistanceMultiplier = 1
	local confidence = 0.55

	if isSprinting or isRunning then
		moveDistanceMultiplier *= self.SprintMoveDistanceMultiplier
		strengthMultiplier *= self.SprintStrengthMultiplier
		lifetimeMultiplier *= self.SprintLifetimeMultiplier
		followDistanceMultiplier *= self.SprintFollowDistanceMultiplier
		confidence = 0.8
	end

	if isCrouching then
		moveDistanceMultiplier *= self.CrouchMoveDistanceMultiplier
		strengthMultiplier *= self.CrouchStrengthMultiplier
		lifetimeMultiplier *= self.CrouchLifetimeMultiplier
		followDistanceMultiplier *= self.CrouchFollowDistanceMultiplier
		confidence *= 0.55
	end

	local minMoveDistance = self.MinMoveDistance * moveDistanceMultiplier
	if lastStimulus and (position - lastStimulus.Position).Magnitude < minMoveDistance then
		return
	end

	local direction = Vector3.zero
	if lastStimulus then
		local delta = position - lastStimulus.Position
		if delta.Magnitude > 0 then
			direction = delta.Unit
		end
	end

	local stimulus = self:PushStimulus({
		Key = string.format("MovementNoise:%d", player.UserId),
		Type = "MovementNoise",
		Position = position,
		Direction = direction,
		SourcePlayer = player,
		Strength = strengthMultiplier,
		Confidence = confidence,
		Duration = self.DefaultLifetime * lifetimeMultiplier,
		Metadata = {
			FollowDistance = self.BaseFollowDistance * followDistanceMultiplier,
			IsSprinting = isSprinting == true,
			IsRunning = isRunning == true,
			IsCrouching = isCrouching == true,
		},
		Tags = {
			Movement = true,
			Noise = true,
		},
	})

	self.LastMovementStimulusByPlayer[player] = stimulus
end

function StimulusService:PushStimulus(stimulus)
	if type(stimulus) ~= "table" or not stimulus.Position then
		return nil
	end

	local now = os.clock()
	local key = stimulus.Key or self:_makeStimulusKey(stimulus)
	local existing = key and self.ActiveStimuliByKey[key] or nil
	local duration = math.max(0.1, stimulus.Duration or ((stimulus.ExpiresAt and (stimulus.ExpiresAt - now)) or self.DefaultLifetime))
	local target = existing

	if not target then
		self.NextStimulusId += 1
		target = {
			Id = self.NextStimulusId,
			Key = key,
			CreatedAt = now,
		}
		table.insert(self.Stimuli, target)
		if key then
			self.ActiveStimuliByKey[key] = target
		end
	end

	target.Type = stimulus.Type or "Unknown"
	target.Position = stimulus.Position
	target.Direction = stimulus.Direction
	target.SourcePlayer = stimulus.SourcePlayer
	target.SourceEntity = stimulus.SourceEntity
	target.Strength = stimulus.Strength or 1
	target.Confidence = stimulus.Confidence or 0.5
	target.LastUpdatedAt = now
	target.ExpiresAt = now + duration
	target.Tags = stimulus.Tags
	target.Metadata = stimulus.Metadata

	return target
end

function StimulusService:_makeStimulusKey(stimulus)
	local typeName = tostring(stimulus.Type or "Unknown")
	if stimulus.SourcePlayer then
		return string.format("%s:Player:%d", typeName, stimulus.SourcePlayer.UserId)
	end

	if stimulus.SourceEntity then
		return string.format("%s:Entity:%s", typeName, tostring(stimulus.SourceEntity.Id or stimulus.SourceEntity.DisplayName or "Unknown"))
	end

	return nil
end

function StimulusService:GetStimuliNearPosition(position, radius, queryOptions)
	if not position then
		return {}
	end

	queryOptions = queryOptions or {}
	radius = radius or self.DefaultStimulusRadius
	local rankedStimuli = {}

	for _, stimulus in ipairs(self.Stimuli) do
		if self:_stimulusMatchesQuery(stimulus, queryOptions) then
			local offset = stimulus.Position - position
			local distance = offset.Magnitude
			if distance <= radius then
				local scoredStimulus = self:_cloneStimulusForQuery(stimulus)
				scoredStimulus.Distance = distance
				scoredStimulus.Score = self:_scoreStimulus(position, radius, scoredStimulus, queryOptions)
				table.insert(rankedStimuli, scoredStimulus)
			end
		end
	end

	table.sort(rankedStimuli, function(a, b)
		if a.Score == b.Score then
			return (a.Distance or math.huge) < (b.Distance or math.huge)
		end
		return a.Score > b.Score
	end)

	return rankedStimuli
end

function StimulusService:GetBestStimulusForEntity(entity, queryOptions)
	if not entity then
		return nil
	end

	queryOptions = queryOptions or {}
	local position = entity:GetPosition()
	local radius = queryOptions.Radius or (entity.DetectionRadius * (entity.StimulusInvestigationRadiusMultiplier or 2.5))
	local stimuli = self:GetStimuliNearPosition(position, radius, queryOptions)
	return stimuli[1]
end

function StimulusService:_stimulusMatchesQuery(stimulus, queryOptions)
	local allowedTypes = queryOptions.Types
	if allowedTypes and allowedTypes[stimulus.Type] ~= true then
		return false
	end

	local sourcePlayer = queryOptions.SourcePlayer
	if sourcePlayer and stimulus.SourcePlayer ~= sourcePlayer then
		return false
	end

	local blockedKeys = queryOptions.ExcludeKeys
	if blockedKeys and stimulus.Key and blockedKeys[stimulus.Key] then
		return false
	end

	return true
end

function StimulusService:_cloneStimulusForQuery(stimulus)
	local clone = table.clone(stimulus)
	local metadata = clone.Metadata or {}
	local followDistance = metadata.FollowDistance or self.BaseFollowDistance
	if clone.Direction and clone.Direction.Magnitude > 0 then
		clone.Destination = clone.Position + (clone.Direction.Unit * followDistance)
	else
		clone.Destination = clone.Position
	end
	return clone
end

function StimulusService:_scoreStimulus(position, radius, stimulus, queryOptions)
	local now = os.clock()
	local lifetime = math.max(0.1, (stimulus.ExpiresAt or now) - (stimulus.CreatedAt or now))
	local remainingLifetime = math.max(0, (stimulus.ExpiresAt or now) - now)
	local ageAlpha = math.clamp(remainingLifetime / lifetime, 0, 1)
	local score = (ageAlpha * 100) + math.max(0, radius - (stimulus.Distance or 0))
	score += (stimulus.Strength or 1) * 16
	score += (stimulus.Confidence or 0) * 24

	if queryOptions.WeightByDirection and stimulus.Direction and stimulus.Direction.Magnitude > 0 then
		local toStimulus = (stimulus.Position - position)
		if toStimulus.Magnitude > 0 then
			score += math.max(0, stimulus.Direction.Unit:Dot(toStimulus.Unit)) * 12
		end
	end

	if queryOptions.PreferPlayer and stimulus.SourcePlayer == queryOptions.PreferPlayer then
		score += 30
	end

	return score
end

function StimulusService:Reset()
	table.clear(self.Stimuli)
	table.clear(self.ActiveStimuliByKey)
	table.clear(self.LastMovementStimulusByPlayer)
end

return StimulusService
