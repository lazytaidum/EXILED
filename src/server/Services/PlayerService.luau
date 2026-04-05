local Players = game:GetService("Players")

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
	
	print("[PlayerService] Started")
end

function PlayerService:_onPlayerAdded(player)
	self.PlayerStates[player] = {
		IsAlive = true,
		HasEscaped = false,
		IsLoaded = true,
	}
	print("[PlayerService] Added", player.Name)
end

function PlayerService:_onPlayerRemoving(player)
	self.PlayerStates[player] = nil
	print("[PlayerService] Removed", player.Name)
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

return PlayerService
