local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local RoundConfig = require(ReplicatedStorage.Shared.Data.RoundConfig)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local VotingService = {}
VotingService.Name = "VotingService"
VotingService.Dependencies = {
	"RemoteRegistry",
	"PlayerService",
}

local function _shallowCopyArray(values)
	local copy = {}
	for index, value in ipairs(values) do
		copy[index] = value
	end
	return copy
end

function VotingService:Init()
	self.RequestVoteRemote = nil
	self.StateRemote = nil
	self.PlayCutsceneRemote = nil
	self.WeightTarget = RoundConfig.VotingWeightTarget or 5
	self.RoundDuration = RoundConfig.VotingRoundDuration or RoundConfig.VotingDuration or 10
	self.AllVotesGraceDuration = RoundConfig.VotingAllVotesGraceDuration or 3
	self.CardCount = RoundConfig.VotingCardCount or 5
	self.CurrentState = nil
	self.LastDraftResult = {
		SelectedEntityIds = {},
		TotalWeight = 0,
		TotalTimerValue = 0,
		ReceptionDuration = RoundConfig.ReceptionDuration or 90,
	}
	self.Random = Random.new()
	self.EntityPool = {}
end

function VotingService:Start()
	self.RequestVoteRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestVote)
	self.StateRemote = self.RemoteRegistry:GetRemote(RemoteNames.VotingStateChanged)
	self.PlayCutsceneRemote = self.RemoteRegistry:GetRemote(RemoteNames.PlayCutscene)
	self.EntityPool = self:_buildEntityPool()

	if self.RequestVoteRemote then
		self.RequestVoteRemote.OnServerEvent:Connect(function(player, payload)
			self:_handleVoteRequest(player, payload)
		end)
	end

	DebugLog:Log("Voting", "[VotingService] Started")
end

function VotingService:_buildEntityPool()
	local pool = {}
	local seen = {}

	for _, definition in pairs(EntityDefinitions) do
		local entityId = definition.Id
		if entityId and not seen[entityId] and definition.CanAppearInVoting ~= false then
			seen[entityId] = true
			table.insert(pool, {
				Id = entityId,
				DisplayName = definition.DisplayName or entityId,
				DirectorWeight = definition.DirectorWeight or definition.Weight or definition.StarRating or 1,
				StarRating = definition.StarRating or definition.DirectorWeight or definition.Weight or 1,
				TimerValue = definition.TimerValue or 0,
			})
		end
	end

	table.sort(pool, function(a, b)
		if a.DirectorWeight == b.DirectorWeight then
			return a.DisplayName < b.DisplayName
		end
		return a.DirectorWeight < b.DirectorWeight
	end)

	return pool
end

function VotingService:ResetDraft()
	self.CurrentState = nil
	self.LastDraftResult = {
		SelectedEntityIds = {},
		TotalWeight = 0,
		TotalTimerValue = 0,
		ReceptionDuration = RoundConfig.ReceptionDuration or 90,
	}
	self:_broadcastState()
end

function VotingService:GetRoundDuration()
	return self.RoundDuration
end

function VotingService:GetLastDraftResult()
	return self.LastDraftResult
end

function VotingService:RunDraft()
	local selectedEntityIds = {}
	local selectedSet = {}
	local totalWeight = 0
	local totalTimerValue = 0
	local roundIndex = 0

	while totalWeight < self.WeightTarget do
		local remainingWeight = self.WeightTarget - totalWeight
		local options = self:_buildOptions(remainingWeight, selectedSet)
		if #options <= 0 then
			break
		end

		roundIndex += 1
		local winner = self:_runVotingRound(roundIndex, selectedEntityIds, totalWeight, totalTimerValue, options)
		if not winner then
			break
		end

		table.insert(selectedEntityIds, winner.Id)
		selectedSet[winner.Id] = true
		totalWeight += winner.DirectorWeight
		totalTimerValue += winner.TimerValue
	end

	self.CurrentState = nil
	self.LastDraftResult = {
		SelectedEntityIds = _shallowCopyArray(selectedEntityIds),
		TotalWeight = totalWeight,
		TotalTimerValue = totalTimerValue,
		ReceptionDuration = (RoundConfig.ReceptionDuration or 90) + totalTimerValue,
	}
	self:_broadcastState()

	DebugLog:Log("Voting", string.format(
		"[VotingService] Draft complete | weight=%d | timerBonus=%d | lineup=%s",
		totalWeight,
		totalTimerValue,
		table.concat(selectedEntityIds, ", ")
	))

	return self.LastDraftResult
end

function VotingService:_buildOptions(remainingWeight, selectedSet)
	local validOptions = {}

	for _, entry in ipairs(self.EntityPool) do
		if entry.DirectorWeight <= remainingWeight and not selectedSet[entry.Id] then
			table.insert(validOptions, entry)
		end
	end

	if #validOptions <= self.CardCount then
		return validOptions
	end

	local shuffled = _shallowCopyArray(validOptions)
	for index = #shuffled, 2, -1 do
		local swapIndex = self.Random:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	local options = {}
	for index = 1, math.min(self.CardCount, #shuffled) do
		table.insert(options, shuffled[index])
	end

	table.sort(options, function(a, b)
		if a.DirectorWeight == b.DirectorWeight then
			return a.DisplayName < b.DisplayName
		end
		return a.DirectorWeight < b.DirectorWeight
	end)

	return options
end

function VotingService:_getEligiblePlayers()
	return self.PlayerService:GetPlayers()
end

function VotingService:_runVotingRound(roundIndex, selectedEntityIds, totalWeight, totalTimerValue, options)
	self.CurrentState = {
		IsActive = true,
		RoundIndex = roundIndex,
		SecondsLeft = self.RoundDuration,
		WeightTarget = self.WeightTarget,
		TotalWeight = totalWeight,
		TotalTimerValue = totalTimerValue,
		SelectedEntityIds = _shallowCopyArray(selectedEntityIds),
		Options = options,
		VotesByPlayer = {},
		AllVotesShortened = false,
	}

	local deadline = os.clock() + self.RoundDuration
	local shortened = false
	self:_playVotingCameraCue(roundIndex)
	self:_broadcastState()

	while true do
		local secondsLeft = math.max(0, math.ceil(deadline - os.clock()))
		if secondsLeft ~= self.CurrentState.SecondsLeft then
			self.CurrentState.SecondsLeft = secondsLeft
			self:_broadcastState()
		end

		if secondsLeft <= 0 then
			break
		end

		if not shortened and self:_haveAllEligiblePlayersVoted() then
			deadline = math.min(deadline, os.clock() + self.AllVotesGraceDuration)
			shortened = true
			self.CurrentState.AllVotesShortened = true
			self:_broadcastState()
		end

		task.wait(0.1)
	end

	local winner = self:_resolveRoundWinner(options)
	if winner then
		DebugLog:Log("Voting", string.format("[VotingService] Round %d winner: %s", roundIndex, winner.Id))
	end

	return winner
end

function VotingService:_playVotingCameraCue(roundIndex)
	if not self.PlayCutsceneRemote then
		return
	end

	self.PlayCutsceneRemote:FireAllClients({
		Type = "FocusTarget",
		Sequence = "VotingRoundStart",
		RoundIndex = roundIndex,
		TargetNames = {
			"VotingCameraFocus",
			"ProjectorScreen",
			"Projector",
		},
		Duration = 1.2,
		TweenTime = 0.35,
		CameraOffset = {
			X = 0,
			Y = 4.5,
			Z = 16,
		},
		LookOffset = {
			X = 0,
			Y = 1.5,
			Z = 0,
		},
	})
end

function VotingService:_haveAllEligiblePlayersVoted()
	local players = self:_getEligiblePlayers()
	if #players <= 0 then
		return false
	end

	for _, player in ipairs(players) do
		if self.CurrentState.VotesByPlayer[player.UserId] == nil then
			return false
		end
	end

	return true
end

function VotingService:_handleVoteRequest(player, payload)
	if not self.CurrentState or not self.CurrentState.IsActive then
		return
	end

	local entityId = type(payload) == "table" and payload.EntityId or payload
	if type(entityId) ~= "string" or entityId == "" then
		return
	end

	for _, option in ipairs(self.CurrentState.Options) do
		if option.Id == entityId then
			self.CurrentState.VotesByPlayer[player.UserId] = entityId
			self:_broadcastState()
			return
		end
	end
end

function VotingService:_resolveRoundWinner(options)
	if #options <= 0 then
		return nil
	end

	local countsById = {}
	local bestVoteCount = -1
	local winners = {}

	for _, entityId in pairs(self.CurrentState.VotesByPlayer) do
		countsById[entityId] = (countsById[entityId] or 0) + 1
	end

	for _, option in ipairs(options) do
		local voteCount = countsById[option.Id] or 0
		if voteCount > bestVoteCount then
			bestVoteCount = voteCount
			winners = { option }
		elseif voteCount == bestVoteCount then
			table.insert(winners, option)
		end
	end

	if #winners <= 0 then
		winners = options
	end

	return winners[self.Random:NextInteger(1, #winners)]
end

function VotingService:_buildVoteCounts()
	local counts = {}
	if not self.CurrentState then
		return counts
	end

	for _, option in ipairs(self.CurrentState.Options or {}) do
		counts[option.Id] = 0
	end

	for _, entityId in pairs(self.CurrentState.VotesByPlayer or {}) do
		if counts[entityId] ~= nil then
			counts[entityId] += 1
		end
	end

	return counts
end

function VotingService:_broadcastState()
	if not self.StateRemote then
		return
	end

	if not self.CurrentState then
		self.StateRemote:FireAllClients({
			IsActive = false,
			WeightTarget = self.WeightTarget,
			LastDraftResult = self.LastDraftResult,
		})
		return
	end

	local voteCounts = self:_buildVoteCounts()
	local options = {}
	for _, option in ipairs(self.CurrentState.Options or {}) do
		table.insert(options, {
			Id = option.Id,
			DisplayName = option.DisplayName,
			DirectorWeight = option.DirectorWeight,
			StarRating = option.StarRating,
			TimerValue = option.TimerValue,
			VoteCount = voteCounts[option.Id] or 0,
		})
	end

	local votedPlayers = 0
	for _ in pairs(self.CurrentState.VotesByPlayer or {}) do
		votedPlayers += 1
	end

	self.StateRemote:FireAllClients({
		IsActive = true,
		RoundIndex = self.CurrentState.RoundIndex or 1,
		SecondsLeft = self.CurrentState.SecondsLeft or 0,
		WeightTarget = self.CurrentState.WeightTarget or self.WeightTarget,
		TotalWeight = self.CurrentState.TotalWeight or 0,
		TotalTimerValue = self.CurrentState.TotalTimerValue or 0,
		SelectedEntityIds = _shallowCopyArray(self.CurrentState.SelectedEntityIds or {}),
		Options = options,
		VotedPlayers = votedPlayers,
		EligiblePlayers = #self:_getEligiblePlayers(),
		AllVotesShortened = self.CurrentState.AllVotesShortened == true,
	})
end

return VotingService
