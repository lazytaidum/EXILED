local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseCharacter = require(ServerScriptService.Server.Classes.BaseCharacter)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InteractableType = require(ReplicatedStorage.Shared.Enums.InteractableType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local CharacterService = {}
CharacterService.Name = "CharacterService"
CharacterService.Dependencies = {
	"PlayerService",
	"RoundManager",
	"StatusEffectService",
	"ThirdPersonAnimationService",
	"ThirdPersonWeaponPresentationService",
}

local HEAL_RANGE = 10
local HEAL_PROGRESS_MAX = 100
local ALLY_HEAL_PER_SECOND = 10
local SELF_HEAL_PER_SECOND = ALLY_HEAL_PER_SECOND / 3

function CharacterService:Init(services)
	self.Services = services
	self.CharactersByPlayer = {}
	self.CharactersByModel = {}
	self.HealingProgressByTarget = {}
	self.SurvivabilityUpdateInterval = 0.25
end

function CharacterService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_connectPlayer(player)
		
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end
	
	Players.PlayerAdded:Connect(function(player: Player)
		self:_connectPlayer(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)

	task.spawn(function()
		self:_runSurvivabilityLoop()
	end)
	
	DebugLog:Log("Character", "[CharacterService] Started")
end

function CharacterService:_connectPlayer(player)
	player.CharacterAdded:Connect(function(characterModel)
		self:_onCharacterAdded(player, characterModel)
	end)
	
	player.CharacterRemoving:Connect(function(characterModel)
		self:_onCharacterRemoving(player, characterModel)
	end)
end

function CharacterService:_onCharacterAdded(player, characterModel)
	local oldCharacter = self.CharactersByPlayer[player]
	if oldCharacter then
		self:_removeCharacter(player, oldCharacter.Model)
	end

	self:_disableDefaultCharacterScripts(characterModel)
	
	local character = BaseCharacter.new(player, characterModel, self.Services)
	self.CharactersByPlayer[player] = character
	self.CharactersByModel[characterModel] = character
	
	local playerService = self.PlayerService
	if playerService then
		playerService:SetAlive(player, true)
		playerService:SetMovementState(player, "IsSprinting", false)
		playerService:SetMovementState(player, "IsCrouching", false)
		playerService:SetMovementState(player, "IsAiming", false)
	end

	local roundManager = self.RoundManager
	if roundManager then
		roundManager:ApplyCurrentPhaseStateToPlayer(player)
	end

	if self.Services.StaminaService then
		self.Services.StaminaService:ResetPlayer(player)
	end
	
	character.Humanoid.Died:Connect(function()
		if character.IsInvincible then
			DebugLog:Log("Character", "[CharacterService] Ignoring death for invincible character", player.Name)
			return
		end
		character.IsDead = true
		character.IsCrumbling = false
		if character._syncSurvivabilityAttributes then
			character:_syncSurvivabilityAttributes()
		end
		local livePlayerService = self.PlayerService
		if livePlayerService then
			livePlayerService:SetAlive(player, false)
			livePlayerService:SetMovementState(player, "IsSprinting", false)
			livePlayerService:SetMovementState(player, "IsCrouching", false)
			livePlayerService:SetMovementState(player, "IsAiming", false)
		end
		
		local liveRoundManager = self.RoundManager
		if liveRoundManager and liveRoundManager:IsPlayerActive(player) then
			liveRoundManager:SetPlayerEliminated(player)
		end
		DebugLog:Log("Character", "[CharacterService] Character died for", player.Name)
	end)
	
	DebugLog:Log("Character", "[CharacterService] Registered character for", player.Name)

	if self.ThirdPersonAnimationService then
		self.ThirdPersonAnimationService:HandleCharacterAdded(player, character)
	end
	if self.ThirdPersonWeaponPresentationService then
		self.ThirdPersonWeaponPresentationService:HandleCharacterAdded(player, character)
	end
end

function CharacterService:_disableDefaultCharacterScripts(characterModel)
	local healthScript = characterModel:FindFirstChild("Health")
	if healthScript and healthScript:IsA("Script") then
		healthScript:Destroy()
	end

	local animateScript = characterModel:FindFirstChild("Animate")
	if animateScript and (animateScript:IsA("LocalScript") or animateScript:IsA("Script")) then
		animateScript:Destroy()
	end

	characterModel.ChildAdded:Connect(function(child)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		elseif child.Name == "Animate" and (child:IsA("LocalScript") or child:IsA("Script")) then
			child:Destroy()
		end
	end)
end

function CharacterService:_onCharacterRemoving(player, characterModel)
	self:_removeCharacter(player, characterModel)
end

function CharacterService:_removeCharacter(player, characterModel)
	local character = self.CharactersByPlayer[player]

	if characterModel then
		if self.ThirdPersonAnimationService then
			self.ThirdPersonAnimationService:HandleCharacterRemoving(player, characterModel)
		end
		if self.ThirdPersonWeaponPresentationService then
			self.ThirdPersonWeaponPresentationService:HandleCharacterRemoving(player, characterModel)
		end
	end
	
	if character then
		character:Destroy()
	end
	
	self:_clearHealingProgress(player)
	self.CharactersByPlayer[player] = nil
	
	if characterModel then
		self.CharactersByModel[characterModel] = nil
	end
	
	local playerService = self.PlayerService
	if playerService then
		playerService:SetAlive(player, false)
		playerService:SetMovementState(player, "IsSprinting", false)
		playerService:SetMovementState(player, "IsCrouching", false)
		playerService:SetMovementState(player, "IsAiming", false)
	end

	local statusEffectService = self.StatusEffectService
	if statusEffectService then
		statusEffectService:ClearStatuses(player)
	end
	
	DebugLog:Log("Character", "[CharacterService] Removed character for", player.Name)
end

function CharacterService:_runSurvivabilityLoop()
	while true do
		local isReceptionActive = self.RoundManager and self.RoundManager:IsReceptionActive() or false
		for _, character in pairs(self.CharactersByPlayer) do
			if character.UpdateCrumbling then
				character:UpdateCrumbling(self.SurvivabilityUpdateInterval, isReceptionActive)
			end
		end

		task.wait(self.SurvivabilityUpdateInterval)
	end
end

function CharacterService:ResetRoundStateForAll()
	table.clear(self.HealingProgressByTarget)

	for player, character in pairs(self.CharactersByPlayer) do
		if character.ResetSurvivabilityForRound then
			character:ResetSurvivabilityForRound()
		end

		self:_syncHealingAttributes(player, 0, nil, false)
	end
end

function CharacterService:_syncHealingAttributes(targetPlayer, progress, helperPlayer, isActive)
	if not targetPlayer then
		return
	end

	local targetCharacter = self:GetCharacterByPlayer(targetPlayer)
	if not targetCharacter or not targetCharacter.Model then
		return
	end

	targetCharacter.Model:SetAttribute("RemnantHealingProgress", progress or 0)
	targetCharacter.Model:SetAttribute("RemnantHealingMax", HEAL_PROGRESS_MAX)
	targetCharacter.Model:SetAttribute("RemnantIsBeingHealed", isActive == true)
	targetCharacter.Model:SetAttribute("RemnantHealingHelperUserId", helperPlayer and helperPlayer.UserId or 0)
end

function CharacterService:_clearHealingProgress(targetPlayer)
	if not targetPlayer then
		return
	end

	self.HealingProgressByTarget[targetPlayer] = nil
	self:_syncHealingAttributes(targetPlayer, 0, nil, false)
end

function CharacterService:_canHealCharacter(helperPlayer, targetPlayer, targetCharacter)
	local helperCharacter = self:GetCharacterByPlayer(helperPlayer)
	if not helperCharacter or not helperCharacter.RootPart or not helperCharacter:IsAlive() or not helperCharacter:IsActionable() then
		return false
	end

	if not targetCharacter or not targetCharacter.RootPart or not targetCharacter.Humanoid then
		return false
	end

	if not targetCharacter:IsAlive() or not targetCharacter:IsActionable() or targetCharacter:IsDowned() then
		return false
	end

	if targetCharacter.Humanoid.Health >= targetCharacter.Humanoid.MaxHealth then
		return false
	end

	local statusEffectService = self.StatusEffectService
	if statusEffectService and not statusEffectService:CanBeHealed(targetPlayer) then
		return false
	end

	if helperPlayer ~= targetPlayer then
		local distance = (targetCharacter.RootPart.Position - helperCharacter.RootPart.Position).Magnitude
		if distance > HEAL_RANGE then
			return false
		end
	end

	return true
end

function CharacterService:_buildHealingInteractable(helperPlayer, targetPlayer, targetCharacter)
	local isSelf = helperPlayer == targetPlayer
	return {
		Type = InteractableType.RemnantHealing,
		DisplayName = isSelf and "Self-Heal" or string.format("Heal %s", targetPlayer.Name),
		Instance = targetCharacter.RootPart,
		Progress = self.HealingProgressByTarget[targetPlayer] or 0,
		MaxProgress = HEAL_PROGRESS_MAX,
		ChargeRate = isSelf and SELF_HEAL_PER_SECOND or ALLY_HEAL_PER_SECOND,
		InteractRange = HEAL_RANGE,
		HealingTargetPlayer = targetPlayer,
	}
end

function CharacterService:GetHealingInteractableForPlayer(helperPlayer)
	local helperCharacter = self:GetCharacterByPlayer(helperPlayer)
	if not helperCharacter or not helperCharacter.RootPart or not helperCharacter:IsAlive() or not helperCharacter:IsActionable() then
		return nil
	end

	local helperPosition = helperCharacter.RootPart.Position
	local bestTargetPlayer = nil
	local bestTargetCharacter = nil
	local bestDistance = math.huge
	for targetPlayer, targetCharacter in pairs(self.CharactersByPlayer) do
		if targetPlayer ~= helperPlayer and self:_canHealCharacter(helperPlayer, targetPlayer, targetCharacter) then
			local distance = (targetCharacter.RootPart.Position - helperPosition).Magnitude
			if distance < bestDistance then
				bestTargetPlayer = targetPlayer
				bestTargetCharacter = targetCharacter
				bestDistance = distance
			end
		end
	end

	if bestTargetPlayer and bestTargetCharacter then
		return self:_buildHealingInteractable(helperPlayer, bestTargetPlayer, bestTargetCharacter)
	end

	return nil
end

function CharacterService:GetSelfHealingInteractableForPlayer(player)
	local character = self:GetCharacterByPlayer(player)
	if not self:_canHealCharacter(player, player, character) then
		return nil
	end

	return self:_buildHealingInteractable(player, player, character)
end

function CharacterService:ProgressHealing(helperPlayer, targetPlayer, amount)
	local targetCharacter = self:GetCharacterByPlayer(targetPlayer)
	if not self:_canHealCharacter(helperPlayer, targetPlayer, targetCharacter) then
		self:_clearHealingProgress(targetPlayer)
		return false, false, nil
	end

	local progress = math.clamp((self.HealingProgressByTarget[targetPlayer] or 0) + amount, 0, HEAL_PROGRESS_MAX)
	self.HealingProgressByTarget[targetPlayer] = progress
	self:_syncHealingAttributes(targetPlayer, progress, helperPlayer, true)

	if progress < HEAL_PROGRESS_MAX then
		return true, false, {
			Progress = progress,
			MaxProgress = HEAL_PROGRESS_MAX,
		}
	end

	local maxHealth = targetCharacter.Humanoid and targetCharacter.Humanoid.MaxHealth or 0
	local healed = targetCharacter:Heal(maxHealth, {
		Source = helperPlayer == targetPlayer and "SelfHealing" or "Healing",
		HelperPlayer = helperPlayer,
	})
	self:_clearHealingProgress(targetPlayer)
	return healed, healed, {
		Progress = HEAL_PROGRESS_MAX,
		MaxProgress = HEAL_PROGRESS_MAX,
	}
end

function CharacterService:_buildRecoveryInteractable(helperPlayer, targetPlayer, targetCharacter)
	local isSelf = helperPlayer == targetPlayer
	return {
		Type = InteractableType.RemnantRecovery,
		DisplayName = isSelf and "Recover" or string.format("Recover %s", targetPlayer.Name),
		Instance = targetCharacter.RootPart,
		Progress = targetCharacter.RecoveryProgress,
		MaxProgress = 100,
		ChargeRate = targetCharacter:GetRecoveryRate(helperPlayer),
		RecoveryTargetPlayer = targetPlayer,
	}
end

function CharacterService:GetRecoveryInteractableForPlayer(helperPlayer)
	local helperCharacter = self:GetCharacterByPlayer(helperPlayer)
	if not helperCharacter or not helperCharacter.RootPart or not helperCharacter:IsAlive() then
		return nil
	end

	if helperCharacter:IsDowned() then
		if helperCharacter:CanProgressRecovery(helperPlayer) then
			return self:_buildRecoveryInteractable(helperPlayer, helperPlayer, helperCharacter)
		end

		return nil
	end

	local helperPosition = helperCharacter.RootPart.Position
	local bestTargetPlayer = nil
	local bestTargetCharacter = nil
	local bestDistance = math.huge
	for targetPlayer, targetCharacter in pairs(self.CharactersByPlayer) do
		if targetPlayer ~= helperPlayer and targetCharacter.RootPart and targetCharacter:IsDowned() and targetCharacter:CanProgressRecovery(helperPlayer) then
			local distance = (targetCharacter.RootPart.Position - helperPosition).Magnitude
			if distance <= 10 and distance < bestDistance then
				bestTargetPlayer = targetPlayer
				bestTargetCharacter = targetCharacter
				bestDistance = distance
			end
		end
	end

	if bestTargetPlayer and bestTargetCharacter then
		return self:_buildRecoveryInteractable(helperPlayer, bestTargetPlayer, bestTargetCharacter)
	end

	return nil
end

function CharacterService:ProgressRecovery(helperPlayer, targetPlayer, amount)
	local helperCharacter = self:GetCharacterByPlayer(helperPlayer)
	local targetCharacter = self:GetCharacterByPlayer(targetPlayer)
	if not helperCharacter or not targetCharacter or not helperCharacter.RootPart or not targetCharacter.RootPart then
		return false, false, nil
	end

	if not helperCharacter:IsAlive() or not targetCharacter:IsDowned() then
		return false, false, nil
	end

	if helperPlayer ~= targetPlayer then
		local distance = (targetCharacter.RootPart.Position - helperCharacter.RootPart.Position).Magnitude
		if distance > 10 then
			return false, false, nil
		end
	end

	local progressed, completed = targetCharacter:ProgressRecovery(amount, helperPlayer)
	return progressed, completed, {
		Progress = targetCharacter.RecoveryProgress,
		MaxProgress = 100,
	}
end

function CharacterService:FreezeAll()
	for _, character in pairs(self.CharactersByPlayer) do
		character:Freeze()
	end
end

function CharacterService:UnfreezeAll()
	for _, character in pairs(self.CharactersByPlayer) do
		character:Unfreeze()
	end
end

function CharacterService:_cleanupPlayer(player)
	local character = self.CharactersByPlayer[player]
	if character then
		self:_removeCharacter(player, character.Model)
	end
end

function CharacterService:GetCharacterByPlayer(player)
	return self.CharactersByPlayer[player]
end

function CharacterService:GetCharacterByModel(model)
	return self.CharactersByModel[model]
end

return CharacterService
