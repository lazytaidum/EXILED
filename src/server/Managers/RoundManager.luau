local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RoundOutcome = require(ReplicatedStorage.Shared.Enums.RoundOutcome)
local RoundConfig = require(ReplicatedStorage.Shared.Data.RoundConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RoundManager = {}
RoundManager.Name = "RoundManager"

function RoundManager:Init(services)
	self.Services = services
	self.CurrentPhase = GamePhase.Lobby
	self.CurrentOutcome = RoundOutcome.None
	self.TimeLeft = 0
	self.IsRunning = false
	self.SkipPhase = false

	self.ActivePlayers = {}
	self.RoundStates = {}
	self.SelectedEntityLineup = {}
	self.CurrentReceptionDuration = RoundConfig.ReceptionDuration
end

function RoundManager:Start()
	DebugLog:Log("Round", "[RoundManager] Started")

	if self.IsRunning then
		return
	end

	self.IsRunning = true

	task.spawn(function()
		self:RunLoop()
	end)
end

function RoundManager:SetPhase(phase, duration)
	self.CurrentPhase = phase
	self.TimeLeft = duration or 0

	DebugLog:Log("Round", string.format("[RoundManager] Phase -> %s (%ds)", phase, self.TimeLeft))

	if phase == GamePhase.Lobby then
		if self.Services.InteractionService then
			self.Services.InteractionService:StopAllInteractions("LobbyReset")
		end
		if self.Services.ObjectiveService then
			self.Services.ObjectiveService:ResetObjectives()
		end
		if self.Services.VotingService then
			self.Services.VotingService:ResetDraft()
		end
		if self.Services.EntityService then
			self.Services.EntityService:SetRoundLineup(nil)
		end
		self:ClearRound()
		for _, player in ipairs(self.Services.PlayerService:GetPlayers()) do
			self:ApplyCurrentPhaseStateToPlayer(player)
		end
		self.Services.SpawnService:TeleportAllPlayersToLobby()
		self.Services.EntityService:SetAllEntitiesActive(false, {
			ResetRound = true,
		})

	elseif phase == GamePhase.Preparation then
		self:BuildRoundRoster()
		self.Services.SpawnService:TeleportPlayersToReception(self.ActivePlayers)
		self.Services.EntityService:SetAllEntitiesActive(false)
		for _, player in ipairs(self.ActivePlayers) do
			self:ApplyCurrentPhaseStateToPlayer(player)
		end

	elseif phase == GamePhase.Reception then
		self.Services.EntityService:SetAllEntitiesActive(true)
		for _, player in ipairs(self.ActivePlayers) do
			self:ApplyCurrentPhaseStateToPlayer(player)
		end

	elseif phase == GamePhase.Results then
		if self.Services.InteractionService then
			self.Services.InteractionService:StopAllInteractions("Results")
		end
		self.Services.EntityService:SetAllEntitiesActive(false)
		for _, player in ipairs(self.ActivePlayers) do
			self:ApplyCurrentPhaseStateToPlayer(player)
		end
		
	end

	local roundStateChanged = self.Services.RemoteRegistry:GetRemote(RemoteNames.RoundStateChanged)
	if roundStateChanged then
		roundStateChanged:FireAllClients({
			Phase = self.CurrentPhase,
			TimeLeft = self.TimeLeft,
			Outcome = self.CurrentOutcome,
		})
	end

	self:BroadcastTimer()

	if self.Services.RoundHookService then
		self.Services.RoundHookService:RaisePhaseChanged(self.CurrentPhase, self.TimeLeft)
	end
end

function RoundManager:BroadcastTimer()
	local roundTimerUpdated = self.Services.RemoteRegistry:GetRemote(RemoteNames.RoundTimerUpdated)
	if roundTimerUpdated then
		roundTimerUpdated:FireAllClients({
			Phase = self.CurrentPhase,
			TimeLeft = self.TimeLeft,
			Outcome = self.CurrentOutcome,
		})
	end
end

function RoundManager:RunPhase(phase, duration)
	self.SkipPhase = false
	self:SetPhase(phase, duration)

	while self.TimeLeft > 0 do
		if self.SkipPhase then
			self.TimeLeft = 0
			self:BroadcastTimer()
			break
		end

		task.wait(1)
		self.TimeLeft -= 1
		self:BroadcastTimer()
		if self.Services.RoundHookService then
			self.Services.RoundHookService:RaiseTimerTick(phase, self.TimeLeft)
		end
	end

	if phase == GamePhase.Reception and not self.SkipPhase then
		self:OnReceptionTimerExpired()
	end
end

function RoundManager:RunLoop()
	while true do
		self:RunPhase(GamePhase.Lobby, RoundConfig.IntermissionDuration)
		self:RunVotingPhase()
		self:RunPhase(GamePhase.Preparation, RoundConfig.PreparationDuration)
		self:RunPhase(GamePhase.Reception, self.CurrentReceptionDuration or RoundConfig.ReceptionDuration)
		self:RunPhase(GamePhase.Results, RoundConfig.ResultsDuration)
	end
end

function RoundManager:RunVotingPhase()
	local votingService = self.Services.VotingService
	if not votingService then
		self.SelectedEntityLineup = {}
		self.CurrentReceptionDuration = RoundConfig.ReceptionDuration
		self:RunPhase(GamePhase.Voting, RoundConfig.VotingDuration)
		return
	end

	self.SkipPhase = false
	self:SetPhase(GamePhase.Voting, votingService:GetRoundDuration())

	local draftResult = votingService:RunDraft()
	self.SelectedEntityLineup = draftResult.SelectedEntityIds or {}
	self.CurrentReceptionDuration = draftResult.ReceptionDuration or RoundConfig.ReceptionDuration

	if self.Services.EntityService then
		self.Services.EntityService:SetRoundLineup(self.SelectedEntityLineup)
	end

	self.TimeLeft = 0
	self:BroadcastTimer()
end

function RoundManager:BuildRoundRoster()
	table.clear(self.ActivePlayers)
	table.clear(self.RoundStates)

	local players = self.Services.PlayerService:GetPlayers()

	for _, player in ipairs(players) do
		local character = self.Services.CharacterService:GetCharacterByPlayer(player)

		if character and character:IsAlive() then
			table.insert(self.ActivePlayers, player)

			self.RoundStates[player] = {
				IsActive = true,
				IsAlive = true,
				HasEscaped = false,
				IsEliminated = false,
			}
		end
	end

	DebugLog:Log("Round", string.format("[RoundManager] Built roster with %d active players", #self.ActivePlayers))
end

function RoundManager:ClearRound()
	table.clear(self.ActivePlayers)
	table.clear(self.RoundStates)
	table.clear(self.SelectedEntityLineup)
	self.CurrentOutcome = RoundOutcome.None
	self.CurrentReceptionDuration = RoundConfig.ReceptionDuration
	if self.Services.InterestService then
		self.Services.InterestService:Reset()
	end
	if self.Services.RoundHookService then
		self.Services.RoundHookService:ResetHooks()
	end
end

function RoundManager:GetRoundState(player)
	return self.RoundStates[player]
end

function RoundManager:GetActivePlayers()
	return self.ActivePlayers
end

function RoundManager:IsPlayerActive(player)
	local roundState = self.RoundStates[player]
	return roundState ~= nil and roundState.IsActive == true
end

function RoundManager:IsReceptionActive()
	return self.CurrentPhase == GamePhase.Reception
end

function RoundManager:GetCurrentPhase()
	return self.CurrentPhase
end

function RoundManager:IsInvinciblePhase(phase)
	return phase == GamePhase.Preparation or phase == GamePhase.Results
end

function RoundManager:ApplyCurrentPhaseStateToPlayer(player)
	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if not character then
		return
	end
	
	local isActivePlayer = self:IsPlayerActive(player)
	local shouldBeInvincible = isActivePlayer and self:IsInvinciblePhase(self.CurrentPhase)
	local shouldBeFrozen = isActivePlayer and (self.CurrentPhase == GamePhase.Results)
	
	character:SetInvincible(shouldBeInvincible)
	
	if shouldBeFrozen then
		character:Freeze()
	else
		character:Unfreeze()
	end
end

function RoundManager:FreezeActivePlayers()
	for _, player in ipairs(self.ActivePlayers) do
		local character = self.Services.CharacterService:GetCharacterByPlayer(player)
		if character then
			character:Freeze()
		end
	end
end

function RoundManager:UnfreezeActivePlayers()
	for _, player in ipairs(self.ActivePlayers) do
		local character = self.Services.CharacterService:GetCharacterByPlayer(player)
		if character then
			character:Unfreeze()
		end
	end
end

function RoundManager:SetPlayerEliminated(player)
	if not self:IsReceptionActive() then
		return
	end

	local roundState = self.RoundStates[player]
	if not roundState then
		return
	end

	roundState.IsAlive = false
	roundState.IsEliminated = true

	DebugLog:Log("Round", "[RoundManager] Eliminated", player.Name)
	DebugLog:Log("Round", "[RoundManager] Alive remaining:", self:GetAliveCount())

	self:CheckRoundEnd()
end

function RoundManager:SetPlayerEscaped(player)
	if not self:IsReceptionActive() then
		return
	end
	
	local roundState = self.RoundStates[player]
	if not roundState then
		return
	end

	roundState.IsAlive = false
	roundState.HasEscaped = true

	DebugLog:Log("Round", "[RoundManager] Escaped", player.Name)
	DebugLog:Log("Round", "[RoundManager] Escaped count:", self:GetEscapedCount(), "/", self:GetRequiredEscapeCount())
	DebugLog:Log("Round", "[RoundManager] Alive remaining:", self:GetAliveCount())

	self:CheckRoundEnd()
end

function RoundManager:GetActivePlayerCount()
	return #self.ActivePlayers
end

function RoundManager:GetRequiredEscapeCount()
	local total = self:GetActivePlayerCount()
	return math.floor(total / 2) + 1
end

function RoundManager:GetAliveCount()
	local count = 0

	for _, roundState in pairs(self.RoundStates) do
		if roundState.IsAlive then
			count += 1
		end
	end

	return count
end

function RoundManager:GetEscapedCount()
	local count = 0

	for _, roundState in pairs(self.RoundStates) do
		if roundState.HasEscaped then
			count += 1
		end
	end

	return count
end

function RoundManager:GetEliminatedCount()
	local count = 0

	for _, roundState in pairs(self.RoundStates) do
		if roundState.IsEliminated then
			count += 1
		end
	end

	return count
end

function RoundManager:CheckRoundEnd()
	if not self:IsReceptionActive() then
		return
	end

	local aliveCount = self:GetAliveCount()
	local escapedCount = self:GetEscapedCount()
	local requiredEscapeCount = self:GetRequiredEscapeCount()
	
	if escapedCount >= requiredEscapeCount then
		DebugLog:Log("Round", "[RoundManager] Escape threshold reached, Remnants win")
		self:EndReception(RoundOutcome.RemnantsWin)
		return
	end

	if aliveCount <= 0 then
		local escapedCount = self:GetEscapedCount()
		local outcome = escapedCount > 0 and RoundOutcome.RemnantsWin or RoundOutcome.EntitiesWin
		DebugLog:Log("Round", "[RoundManager] No active players remain, ending round early.")
		self:EndReception(outcome)
	end
end

function RoundManager:EndReception(outcome)
	if not self:IsReceptionActive() then
		return
	end

	self.CurrentOutcome = outcome or RoundOutcome.None
	self.SkipPhase = true

	DebugLog:Log("Round", "[RoundManager] Reception ended with outcome:", self.CurrentOutcome)
end

function RoundManager:OnReceptionTimerExpired()
	DebugLog:Log("Round", "[RoundManager] Reception timer expired")

	local aliveCount = self:GetAliveCount()
	local escapedCount = self:GetEscapedCount()

	if aliveCount > 0 then
		self:EndReception(RoundOutcome.Draw)
	elseif escapedCount > 0 then
		self:EndReception(RoundOutcome.RemnantsWin)
	else
		self:EndReception(RoundOutcome.EntitiesWin)
	end
end

function RoundManager:OnObjectiveCompleted(objective)
	if self.Services.RoundHookService then
		self.Services.RoundHookService:RaiseObjectiveCompleted(objective)
	end
end

return RoundManager
