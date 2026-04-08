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
	local challenge = {
		Id = challengeId,
		Entity = entity,
		StartedAt = os.clock(),
		EndsAt = os.clock() + duration,
		Duration = duration,
		HastePerFailure = params.HastePerFailure or 0.15,
		BaseHasteDuration = params.HasteDuration or 5,
		Participants = {},
	}

	for _, player in ipairs(activePlayers) do
		local roundState = self.RoundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			challenge.Participants[player] = {
				IsHolding = false,
				HeldDuration = 0,
			}

			self.BreathHoldStateRemote:FireClient(player, {
				State = "Start",
				Duration = duration,
				Prompt = "Hold Space to stay silent",
				SubPrompt = "Jiangshi is listening for breath",
				RequiredKey = "SPACE",
			})
		end
	end

	self.ActiveChallenges[challengeId] = challenge
	DebugLog:Log("Interaction", string.format("[BreathHoldService] %s began Breathless Hunt", entity.DisplayName))
	return true
end

function BreathHoldService:HandleHoldState(player, isHolding)
	for _, challenge in pairs(self.ActiveChallenges) do
		local participant = challenge.Participants[player]
		if participant then
			participant.IsHolding = isHolding == true
		end
	end
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
		for player, participant in pairs(challenge.Participants) do
			if participant.IsHolding then
				participant.HeldDuration += self.UpdateInterval
			end

			self.BreathHoldStateRemote:FireClient(player, {
				State = "Update",
				Duration = math.max(0, challenge.EndsAt - now),
				RequiredKey = "SPACE",
				Progress = math.clamp(participant.HeldDuration / challenge.Duration, 0, 1),
				Prompt = "Hold Space to stay silent",
				SubPrompt = "Jiangshi is listening for breath",
			})
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

		local heldRatio = challenge.Duration > 0 and (participant.HeldDuration / challenge.Duration) or 0
		if heldRatio < 0.85 then
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
