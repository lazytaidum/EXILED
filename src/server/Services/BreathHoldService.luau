local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local BreathHoldService = {}
BreathHoldService.Name = "BreathHoldService"
BreathHoldService.Dependencies = {
	"RemoteRegistry",
	"RoundManager",
	"CharacterService",
	"StatusEffectService",
}

function BreathHoldService:Init(services)
	self.Services = services
	self.ActiveChallenges = {}
	self.UpdateInterval = 0.1
end

function BreathHoldService:Start()
	self.BreathHoldStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.BreathHoldStateChanged)
	local requestBreathHoldState = self.RemoteRegistry:GetRemote(RemoteNames.RequestBreathHoldState)

	requestBreathHoldState.OnServerEvent:Connect(function(player, isHolding)
		self:HandleHoldState(player, isHolding)
	end)

	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Interaction", "[BreathHoldService] Started")
end

function BreathHoldService:BeginChallenge(entity, params)
	if not entity or not self.RoundManager or not self.RoundManager:IsReceptionActive() then
		return false
	end

	local activePlayers = self.RoundManager:GetActivePlayers()
	if #activePlayers <= 0 then
		return false
	end

	local challengeId = tostring(os.clock())
	local duration = params.Duration or 3
	local indicatorDuration = params.IndicatorDuration or 2.5
	local reactionWindow = params.ReactionWindow or 1
	local entityPosition = entity:GetPosition()
	local radius = params.Radius
	local challenge = {
		Id = challengeId,
		Entity = entity,
		StartedAt = os.clock(),
		ActiveAt = os.clock() + indicatorDuration,
		EndsAt = os.clock() + indicatorDuration + duration,
		Duration = duration,
		IndicatorDuration = indicatorDuration,
		ReactionWindow = reactionWindow,
		Phase = "Indicator",
		HastePerFailure = params.HastePerFailure or 0.15,
		BaseHasteDuration = params.HasteDuration or 5,
		FailDrainRate = params.FailDrainRate or (reactionWindow > 0 and (1 / reactionWindow) or 1),
		HoldDrainRate = params.HoldDrainRate or 0.05,
		Radius = radius,
		Participants = {},
	}

	for _, player in ipairs(activePlayers) do
		local roundState = self.RoundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
			local isInRange = true
			if radius and entityPosition and character and character.RootPart then
				isInRange = (character.RootPart.Position - entityPosition).Magnitude <= radius
			end

			if isInRange then
				challenge.Participants[player] = {
					IsHolding = false,
					BreathRemaining = 1,
				}

				self.BreathHoldStateRemote:FireClient(player, {
					State = "Indicator",
					Duration = indicatorDuration,
					Prompt = "Breathless Hunt",
					SubPrompt = "Mist gathers. Be ready to hold your breath.",
					RequiredKey = "GET READY",
				})
			end
		end
	end

	if next(challenge.Participants) == nil then
		return false
	end

	self.ActiveChallenges[challengeId] = challenge
	DebugLog:Log("Interaction", string.format("[BreathHoldService] %s began Breathless Hunt", entity.DisplayName))
	return true
end

function BreathHoldService:HandleHoldState(player, isHolding)
	for _, challenge in pairs(self.ActiveChallenges) do
		local participant = challenge.Participants[player]
		if participant and challenge.Phase == "Challenge" then
			participant.IsHolding = isHolding == true
		end
	end
end

function BreathHoldService:CancelChallengesForEntity(entity, reason)
	if not entity then
		return 0
	end

	local cancelledCount = 0
	for challengeId, challenge in pairs(self.ActiveChallenges) do
		if challenge.Entity == entity then
			for player in pairs(challenge.Participants) do
				self.BreathHoldStateRemote:FireClient(player, {
					State = "Stop",
					Reason = reason or "Interrupted",
				})
			end

			self.ActiveChallenges[challengeId] = nil
			cancelledCount += 1
		end
	end

	return cancelledCount
end

function BreathHoldService:_runLoop()
	while true do
		self:_updateChallenges()
		task.wait(self.UpdateInterval)
	end
end

function BreathHoldService:_updateChallenges()
	local now = os.clock()

	for challengeId, challenge in pairs(self.ActiveChallenges) do
		if challenge.Phase == "Indicator" and now >= challenge.ActiveAt then
			challenge.Phase = "Challenge"
			for player in pairs(challenge.Participants) do
				self.BreathHoldStateRemote:FireClient(player, {
					State = "Start",
					Duration = challenge.Duration,
					RequiredKey = "SPACE",
					Prompt = "Hold Space to stay silent",
					SubPrompt = string.format("Your breath will give you away in %.1fs if you do not react", challenge.ReactionWindow),
					Breath = 1,
				})
			end
		end

		if challenge.Phase == "Challenge" then
			for player, participant in pairs(challenge.Participants) do
				local drainRate = participant.IsHolding and challenge.HoldDrainRate or challenge.FailDrainRate
				participant.BreathRemaining = math.max(0, participant.BreathRemaining - (drainRate * self.UpdateInterval))

				self.BreathHoldStateRemote:FireClient(player, {
					State = "Update",
					Duration = math.max(0, challenge.EndsAt - now),
					RequiredKey = "SPACE",
					Breath = participant.BreathRemaining,
					Prompt = "Hold Space to stay silent",
					SubPrompt = string.format("Your breath will give you away in %.1fs if you do not react", challenge.ReactionWindow),
				})
			end
		end

		if now >= challenge.EndsAt then
			self:_resolveChallenge(challengeId, challenge)
		end
	end
end

function BreathHoldService:_resolveChallenge(challengeId, challenge)
	local failedPlayers = {}
	local entityPosition = challenge.Entity:GetPosition()

	for player, participant in pairs(challenge.Participants) do
		self.BreathHoldStateRemote:FireClient(player, {
			State = "Stop",
		})

		if participant.BreathRemaining <= 0 then
			table.insert(failedPlayers, player)
		end
	end

	if #failedPlayers > 0 then
		self.StatusEffectService:ApplyStatus(challenge.Entity, "Haste", {
			Duration = challenge.BaseHasteDuration * #failedPlayers,
			Magnitude = challenge.HastePerFailure * #failedPlayers,
			Source = "BreathlessHunt",
		})

		local bestTarget = nil
		local bestDistance = math.huge

		for _, player in ipairs(failedPlayers) do
			local character = self.CharacterService:GetCharacterByPlayer(player)
			if character and character.RootPart and entityPosition then
				challenge.Entity:RememberTarget(player, character.RootPart.Position, true)

				local distance = (character.RootPart.Position - entityPosition).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					bestTarget = {
						Player = player,
						Position = character.RootPart.Position,
					}
				end
			end
		end

		if bestTarget then
			challenge.Entity:SetTarget(bestTarget.Player, bestTarget.Position, true)
			challenge.Entity:EnterState("Chase")
		end
	end

	self.ActiveChallenges[challengeId] = nil
end

return BreathHoldService
