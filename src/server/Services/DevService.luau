local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugFlags = require(ReplicatedStorage.Shared.Data.DebugFlags)
local EntityDefinitions = require(ReplicatedStorage.Shared.Data.EntityDefinitions)
local ItemDefinitions = require(ReplicatedStorage.Shared.Data.ItemDefinitions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local DevService = {}
DevService.Name = "DevService"
DevService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"CombatService",
	"InventoryService",
	"EntityService",
	"RoundManager",
	"EscapeService",
	"WeaponPickupService",
	"ItemPickupService",
}

local function _isValidDefinitionId(definitions, id)
	return id ~= nil and definitions[id] ~= nil
end

function DevService:Init(services)
	self.Services = services
	self.GodModeByPlayer = {}
	self.DebugUiEnabledByPlayer = {}
end

function DevService:Start()
	if not DebugFlags.Enabled or not DebugFlags.DevMenu then
		return
	end

	Workspace:SetAttribute("DebugUiEnabled", true)

	self.RequestRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestDevCommand)
	self.StateRemote = self.RemoteRegistry:GetRemote(RemoteNames.DevStateChanged)
	self.PlacementStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.DevPlacementStateChanged)

	if self.RequestRemote then
		self.RequestRemote.OnServerEvent:Connect(function(player, payload)
			self:_handleCommand(player, payload)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_sendState(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				local character = self.CharacterService:GetCharacterByPlayer(player)
				if character and self.GodModeByPlayer[player] == true then
					character:SetInvincible(true)
				end
				self:_sendState(player)
			end)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.defer(function()
				local character = self.CharacterService:GetCharacterByPlayer(player)
				if character and self.GodModeByPlayer[player] == true then
					character:SetInvincible(true)
				end
				self:_sendState(player)
			end)
		end)
		self:_sendState(player)
	end

	DebugLog:Log("Boot", "[DevService] Started")
end

function DevService:_handleCommand(player, payload)
	if type(payload) ~= "table" then
		return
	end

	local command = payload.Command
	if command == "GiveWeapon" then
		self:_giveWeapon(player, payload.WeaponId)
	elseif command == "GiveItem" then
		self:_giveItem(player, payload.ItemId, payload.Count)
	elseif command == "SpawnEntity" then
		self:_spawnEntity(player, payload.EntityId)
	elseif command == "SpawnEntityAt" then
		self:_spawnEntityAt(player, payload.EntityId, payload.Position)
	elseif command == "AdjustTimer" then
		self:_adjustTimer(player, payload.Delta)
	elseif command == "SetTimer" then
		self:_setTimer(player, payload.TimeLeft)
	elseif command == "ToggleEscape" then
		self:_toggleEscape(player)
	elseif command == "PlaceWeaponPickup" then
		self:_placeWeaponPickup(player, payload.WeaponId, payload.Position)
	elseif command == "PlaceItemPickup" then
		self:_placeItemPickup(player, payload.ItemId, payload.Position, payload.Quantity)
	elseif command == "ToggleGodMode" then
		self:_toggleGodMode(player)
	elseif command == "ToggleDebugUi" then
		self:_toggleDebugUi(player)
	elseif command == "SetHealth" then
		self:_setHealth(player, payload.Health)
	elseif command == "Refresh" then
		self:_sendState(player)
	end
end

function DevService:_giveWeapon(player, weaponId)
	if not _isValidDefinitionId(WeaponDefinitions, weaponId) then
		self:_sendState(player, "Unknown weapon")
		return
	end

	local slotIndex = self.CombatService:GiveWeapon(player, weaponId)
	if not slotIndex then
		self:_sendState(player, "Failed to give weapon")
		return
	end

	self.CombatService:RefreshCombatState(player)
	self:_sendState(player, string.format("Gave %s", WeaponDefinitions[weaponId].DisplayName))
end

function DevService:_giveItem(player, itemId, count)
	if not _isValidDefinitionId(ItemDefinitions, itemId) then
		self:_sendState(player, "Unknown item")
		return
	end

	self.InventoryService:AddItem(player, itemId, tonumber(count) or 1)
	self.CombatService:RefreshCombatState(player)
	self:_sendState(player, string.format("Gave %s", ItemDefinitions[itemId].DisplayName))
end

function DevService:_spawnEntity(player, entityId)
	if not _isValidDefinitionId(EntityDefinitions, entityId) then
		self:_sendState(player, "Unknown entity")
		return
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.RootPart then
		self:_sendState(player, "No character root")
		return
	end

	local origin = character.RootPart.CFrame
	local spawnPosition = origin.Position + (origin.LookVector * 16) + Vector3.new(0, 2, 0)
	local spawnCFrame = CFrame.new(spawnPosition, origin.Position)
	local entity = self.EntityService:SpawnEntity(entityId, {
		CFrame = spawnCFrame,
		Activate = true,
		IsSummon = false,
	})

	if not entity then
		self:_sendState(player, "Failed to spawn entity")
		return
	end

	self:_sendState(player, string.format("Spawned %s", entity.DisplayName))
end

function DevService:_resolvePosition(payloadPosition)
	if type(payloadPosition) ~= "table" then
		return nil
	end

	local x = tonumber(payloadPosition.X)
	local y = tonumber(payloadPosition.Y)
	local z = tonumber(payloadPosition.Z)
	if not x or not y or not z then
		return nil
	end

	return Vector3.new(x, y, z)
end

function DevService:_spawnEntityAt(player, entityId, payloadPosition)
	if not _isValidDefinitionId(EntityDefinitions, entityId) then
		self:_sendState(player, "Unknown entity")
		return
	end

	local position = self:_resolvePosition(payloadPosition)
	if not position then
		self:_sendState(player, "Invalid placement position")
		return
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	local lookAt = character and character.RootPart and character.RootPart.Position or (position + Vector3.new(0, 0, -1))
	local entity = self.EntityService:SpawnEntity(entityId, {
		CFrame = CFrame.new(position + Vector3.new(0, 2, 0), lookAt),
		Activate = true,
		IsSummon = false,
	})

	if not entity then
		self:_sendState(player, "Failed to spawn entity")
		return
	end

	self:_sendState(player, string.format("Spawned %s", entity.DisplayName))
end

function DevService:_adjustTimer(player, delta)
	local amount = tonumber(delta)
	if not amount then
		self:_sendState(player, "Invalid timer delta")
		return
	end

	self.RoundManager.TimeLeft = math.max(0, self.RoundManager.TimeLeft + amount)
	self.RoundManager:BroadcastTimer()
	self:_sendState(player, string.format("Adjusted timer by %ds", amount))
end

function DevService:_setTimer(player, timeLeft)
	local amount = tonumber(timeLeft)
	if amount == nil then
		self:_sendState(player, "Invalid timer value")
		return
	end

	self.RoundManager.TimeLeft = math.max(0, amount)
	self.RoundManager:BroadcastTimer()
	self:_sendState(player, string.format("Set timer to %ds", self.RoundManager.TimeLeft))
end

function DevService:_toggleEscape(player)
	local escapeService = self.EscapeService
	escapeService:SetEscapeEnabled(not escapeService:IsEscapeEnabled())
	self:_sendState(player, escapeService:IsEscapeEnabled() and "Escape enabled" or "Escape disabled")
end

function DevService:_placeWeaponPickup(player, weaponId, payloadPosition)
	if not _isValidDefinitionId(WeaponDefinitions, weaponId) then
		self:_sendState(player, "Unknown weapon")
		return
	end

	local position = self:_resolvePosition(payloadPosition)
	if not position then
		self:_sendState(player, "Invalid placement position")
		return
	end

	local instance = self.WeaponPickupService and self.WeaponPickupService:CreateDevPickup(weaponId, position)
	if not instance then
		self:_sendState(player, "Failed to place weapon pickup")
		return
	end

	self:_sendState(player, string.format("Placed %s pickup", WeaponDefinitions[weaponId].DisplayName))
end

function DevService:_placeItemPickup(player, itemId, payloadPosition, quantity)
	if not _isValidDefinitionId(ItemDefinitions, itemId) then
		self:_sendState(player, "Unknown item")
		return
	end

	local position = self:_resolvePosition(payloadPosition)
	if not position then
		self:_sendState(player, "Invalid placement position")
		return
	end

	local instance = self.ItemPickupService and self.ItemPickupService:CreateDevPickup(itemId, position, quantity)
	if not instance then
		self:_sendState(player, "Failed to place item pickup")
		return
	end

	self:_sendState(player, string.format("Placed %s pickup", ItemDefinitions[itemId].DisplayName))
end

function DevService:_toggleGodMode(player)
	local nextState = not (self.GodModeByPlayer[player] == true)
	self.GodModeByPlayer[player] = nextState

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetInvincible(nextState)
	end

	self:_sendState(player, nextState and "God mode enabled" or "God mode disabled")
end

function DevService:_toggleDebugUi(player)
	local nextState = not (self.DebugUiEnabledByPlayer[player] ~= false)
	self.DebugUiEnabledByPlayer[player] = nextState
	Workspace:SetAttribute("DebugUiEnabled", nextState)
	self:_sendState(player, nextState and "Debug UI enabled" or "Debug UI disabled")
end

function DevService:_setHealth(player, healthValue)
	local targetHealth = tonumber(healthValue)
	if targetHealth == nil then
		self:_sendState(player, "Invalid health value")
		return
	end

	local character = self.CharacterService:GetCharacterByPlayer(player)
	if not character or not character.Humanoid then
		self:_sendState(player, "No active character")
		return
	end

	local humanoid = character.Humanoid
	humanoid.Health = math.clamp(targetHealth, 1, humanoid.MaxHealth)
	self:_sendState(player, string.format("Set health to %d", math.floor(humanoid.Health + 0.5)))
end

function DevService:_sendState(player, message)
	if not self.StateRemote then
		return
	end

	self.StateRemote:FireClient(player, {
		Message = message,
		Phase = self.RoundManager and self.RoundManager:GetCurrentPhase() or "Unknown",
		TimeLeft = self.RoundManager and self.RoundManager.TimeLeft or 0,
		EscapeEnabled = self.EscapeService and self.EscapeService:IsEscapeEnabled() or false,
		GodMode = self.GodModeByPlayer[player] == true,
		DebugUiEnabled = self.DebugUiEnabledByPlayer[player] ~= false,
	})
end

return DevService
