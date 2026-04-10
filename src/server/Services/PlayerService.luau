local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local PlayerService = {}
PlayerService.Name = "PlayerService"

function PlayerService:Init()
	self.PlayerStates = {}
end

function PlayerService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end
	
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
	
	DebugLog:Log("Player", "[PlayerService] Started")
end

function PlayerService:_onPlayerAdded(player)
	self.PlayerStates[player] = {
		IsAlive = true,
		HasEscaped = false,
		IsLoaded = true,
		IsSprinting = false,
		IsCrouching = false,
		IsAiming = false,
	}
	DebugLog:Log("Player", "[PlayerService] Added", player.Name)
end

function PlayerService:_onPlayerRemoving(player)
	self.PlayerStates[player] = nil
	DebugLog:Log("Player", "[PlayerService] Removed", player.Name)
end

function PlayerService:GetPlayerState(player)
	return self.PlayerStates[player]
end

function PlayerService:GetPlayers()
	local players = {}
	
	for player in pairs(self.PlayerStates) do
		table.insert(players, player)
	end
	
	return players
end

function PlayerService:SetAlive(player, isAlive)
	local state = self.PlayerStates[player]
	if state then
		state.IsAlive = isAlive
	end
end

function PlayerService:SetMovementState(player, stateKey, value)
	local state = self.PlayerStates[player]
	if not state then
		return
	end

	state[stateKey] = value
end

return PlayerService
