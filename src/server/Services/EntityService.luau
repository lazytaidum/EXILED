local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseEntity = require(ServerScriptService.Server.Classes.BaseEntity)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local EntityService = {}
EntityService.Name = "EntityService"

function EntityService:Init(services)
	self.Services = services
	self.Entities = {}
	self.UpdateInterval = 0.2

	self.EntitiesFolder = Workspace:WaitForChild("Entities")
end

function EntityService:Start()
	self:_registerExistingEntities()

	task.spawn(function()
		self:_runEntityLoop()
	end)

	DebugLog:Log("Entity", "[EntityService] Started")
end

function EntityService:_registerExistingEntities()
	for _,model in ipairs(self.EntitiesFolder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart then
			local definition = EntityDefinitions[model.Name]
			local entity = BaseEntity.new(model, definition)

			table.insert(self.Entities, entity)

			DebugLog:Log("Entity", string.format(
				"[EntityService] Registered entity: %s | Stars: %d | Weight: %d",
				entity.DisplayName,
				entity.StarRating,
				entity.Weight
			))
		end
	end
end

function EntityService:_runEntityLoop()
	while true do
		for _, entity in ipairs(self.Entities) do
			if entity.IsActive then
				self:_updateEntity(entity, self.UpdateInterval)
			end
		end

		task.wait(self.UpdateInterval)
	end
end

function EntityService:_updateEntity(entity, deltaTime)
	local targetCharacter = self:_findNearestCharacter(entity)
	if targetCharacter then
		entity:SetTarget(targetCharacter.Player)
		
		if entity:HasAttribute(EntityAttributes.Chase) then
			entity:MoveToward(targetCharacter.RootPart.Position, deltaTime)
		end
		
		if entity:CanAttack() then
			local distance = (targetCharacter.RootPart.Position - entity:GetPosition()).Magnitude
			if distance <= entity.AttackRange then
				local didDamage = targetCharacter:ApplyDamage(entity.Damage)
				if didDamage then
					local targetPlayer = targetCharacter.Player
					targetCharacter:ApplyTemporarySpeedMultiplier("OnHitHaste", 1.45, 1.5)
					
					local interactionService = self.Services.InteractionService
					if interactionService and targetPlayer and interactionService:IsInteracting(targetPlayer) then
						interactionService:InterruptInteraction(targetPlayer, "Damaged")
					end
				end
				entity:MarkAttack()
				
				local player = targetCharacter.Player
				local name = player and player.Name or "Unknown"
				DebugLog:Log("Entity", string.format(
					"[EntityService] %s hit %s for %d",
					entity.Model.Name,
					name,
					entity.Damage
				))
			end
		end
	else
		entity:SetTarget(nil)
	end
end

function EntityService:_findNearestCharacter(entity)
	local roundManager = self.Services.RoundManager
	local characterService = self.Services.CharacterService

	if not roundManager or not characterService then
		return nil
	end

	local entityPosition = entity:GetPosition()
	if not entityPosition then
		return nil
	end

	local nearestCharacter = nil
	local nearestDistance = math.huge

	for _, player in ipairs(roundManager:GetActivePlayers()) do
		local roundState = roundManager:GetRoundState(player)
		if roundState and roundState.IsAlive then
			local character = characterService:GetCharacterByPlayer(player)
			if character and character.RootPart then
				local distance = (character.RootPart.Position - entityPosition).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearestCharacter = character
				end
			end
		end
	end

	return nearestCharacter
end

function EntityService:SetAllEntitiesActive(state)
	for _, entity in ipairs(self.Entities) do
		entity:SetActive(state)
		
		if not state then
			entity:ResetToSpawn()
		end
	end

	DebugLog:Log("Entity", "[EntityService] Entities active:", state)
end

return EntityService
