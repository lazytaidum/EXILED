local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EscapeService = {}
EscapeService.Name = "EscapeService"

function EscapeService:Init(services)
	self.Services = services
	self.EscapeZone = Workspace:WaitForChild("EscapeZone")
	self.TouchDebounce = {}
end

function EscapeService:Start()
	self.EscapeZone.Touched:Connect(function(hit)
		self:_onEscapeZoneTouched(hit)
	end)
	
	DebugLog:Log("Round", "[EscapeService] Started")
end

function EscapeService:_onEscapeZoneTouched(hit)
	local characterModel = hit and hit.Parent
	if not characterModel then
		return
	end
	
	local player = Players:GetPlayerFromCharacter(characterModel)
	if not player then
		return
	end
	
	if self.TouchDebounce[player] then
		return
	end
	
	self.TouchDebounce[player] = true
	
	self:TryEscapePlayer(player)
	
	task.delay(1, function()
		self.TouchDebounce[player] = nil
	end)
end

function EscapeService:TryEscapePlayer(player)
	local roundManager = self.Services.RoundManager
	if not roundManager then
		return
	end
	
	if not roundManager:IsReceptionActive() then
		return
	end
	
	if not roundManager:IsPlayerActive(player) then
		return
	end
	
	local roundState = roundManager:GetRoundState(player)
	if not roundState or not roundState.IsAlive then
		return
	end
	
	roundManager:SetPlayerEscaped(player)

	local character = self.Services.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:Freeze()
		if character.RootPart then
			character.RootPart.CFrame = CFrame.new(0, -1000, 0) -- Temporary extraction method..
		end
	end

	DebugLog:Log("Round", "[EscapeService] Player escaped:", player.Name)
end

return EscapeService
