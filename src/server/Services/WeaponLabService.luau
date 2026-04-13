local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local WorldModeResolver = require(ReplicatedStorage.Shared.Utility.WorldModeResolver)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local DEFAULT_WEAPON_ID = "Glock19G5"
local LAB_STATE_REAPPLY_INTERVAL = 5

local WeaponLabService = {}
WeaponLabService.Name = "WeaponLabService"
WeaponLabService.Dependencies = {
	"RemoteRegistry",
	"CharacterService",
	"CombatService",
	"InventoryService",
}

local function _isAllowedWeapon(weaponId)
	local definition = WeaponDefinitions[weaponId]
	return definition ~= nil and definition.Kind == "Firearm"
end

function WeaponLabService:Init(services)
	self.Services = services
	self.SelectedWeaponByPlayer = {}
	self.LabStateLoopRunning = false
end

function WeaponLabService:Start()
	if not WorldModeResolver.IsWeaponLab() then
		return
	end

	self.RequestRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestWeaponLabCommand)
	self.StateRemote = self.RemoteRegistry:GetRemote(RemoteNames.WeaponLabStateChanged)
	self.RoundStateChangedRemote = self.RemoteRegistry:GetRemote(RemoteNames.RoundStateChanged)
	self.RoundTimerUpdatedRemote = self.RemoteRegistry:GetRemote(RemoteNames.RoundTimerUpdated)

	if self.RequestRemote then
		self.RequestRemote.OnServerEvent:Connect(function(player, payload)
			self:_handleCommand(player, payload)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:_connectPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_connectPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.SelectedWeaponByPlayer[player] = nil
	end)

	self:_startLabStateLoop()

	DebugLog:Log("Boot", "[WeaponLabService] Started")
end

function WeaponLabService:_connectPlayer(player)
	if not _isAllowedWeapon(self.SelectedWeaponByPlayer[player]) then
		self.SelectedWeaponByPlayer[player] = DEFAULT_WEAPON_ID
	end

	player.CharacterAdded:Connect(function()
		task.defer(function()
			self:_applyLabState(player, "Loaded weapon lab")
		end)
	end)

	self:_sendRoundState(player)
	self:_sendState(player)

	if player.Character then
		task.defer(function()
			self:_applyLabState(player, "Loaded weapon lab")
		end)
	end
end

function WeaponLabService:_getSelectedWeaponId(player)
	local weaponId = self.SelectedWeaponByPlayer[player]
	if _isAllowedWeapon(weaponId) then
		return weaponId
	end

	return DEFAULT_WEAPON_ID
end

function WeaponLabService:_sendRoundState(player)
	local payload = {
		Phase = GamePhase.Preparation,
		TimeLeft = 0,
		Outcome = "None",
	}

	if player then
		if self.RoundStateChangedRemote then
			self.RoundStateChangedRemote:FireClient(player, payload)
		end
		if self.RoundTimerUpdatedRemote then
			self.RoundTimerUpdatedRemote:FireClient(player, payload)
		end
	else
		if self.RoundStateChangedRemote then
			self.RoundStateChangedRemote:FireAllClients(payload)
		end
		if self.RoundTimerUpdatedRemote then
			self.RoundTimerUpdatedRemote:FireAllClients(payload)
		end
	end
end

function WeaponLabService:_sendState(player, message)
	if not self.StateRemote then
		return
	end

	self.StateRemote:FireClient(player, {
		SelectedWeaponId = self:_getSelectedWeaponId(player),
		DefaultWeaponId = DEFAULT_WEAPON_ID,
		Message = message,
	})
end

function WeaponLabService:_startLabStateLoop()
	if self.LabStateLoopRunning then
		return
	end

	self.LabStateLoopRunning = true
	task.spawn(function()
		while self.LabStateLoopRunning do
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Parent == Players then
					self:_maintainLabState(player)
				end
			end
			task.wait(LAB_STATE_REAPPLY_INTERVAL)
		end
	end)
end

function WeaponLabService:_maintainLabState(player)
	self:_sendRoundState(player)

	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetInvincible(true)
		character:Unfreeze()
		if character.Humanoid then
			character.Humanoid.Health = character.Humanoid.MaxHealth
		end
	end

	local selectedWeaponId = self:_getSelectedWeaponId(player)
	local needsLoadoutRepair = false
	local entries = self.InventoryService and self.InventoryService:GetEntries(player) or nil
	if not entries or #entries ~= 1 then
		needsLoadoutRepair = true
	else
		local onlyEntry = entries[1]
		needsLoadoutRepair = not onlyEntry
			or onlyEntry.EntryType ~= "Weapon"
			or onlyEntry.ItemId ~= selectedWeaponId
	end

	local equippedState = self.CombatService and self.CombatService:GetEquippedWeaponState(player) or nil
	if not equippedState or equippedState.ItemId ~= selectedWeaponId then
		needsLoadoutRepair = true
	end

	if needsLoadoutRepair and self.InventoryService then
		self.InventoryService:SetWeaponLoadout(player, { selectedWeaponId })
	end

	if needsLoadoutRepair and self.CombatService then
		self.CombatService:HandleEquipWeapon(player, 1)
		self.CombatService:RefreshCombatState(player)
	end
end

function WeaponLabService:_applyLabState(player, message)
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if character then
		character:SetAiming(false)
	end

	self:_maintainLabState(player)

	local selectedWeaponId = self:_getSelectedWeaponId(player)
	self:_sendState(player, message or string.format("Loaded %s", selectedWeaponId))
end

function WeaponLabService:_handleCommand(player, payload)
	if type(payload) ~= "table" then
		return
	end

	local command = payload.Command
	if command == "SetWeapon" then
		local weaponId = payload.WeaponId
		if not _isAllowedWeapon(weaponId) then
			self:_sendState(player, "Invalid lab weapon")
			return
		end

		self.SelectedWeaponByPlayer[player] = weaponId
		self:_applyLabState(player, string.format("Loaded %s", WeaponDefinitions[weaponId].DisplayName or weaponId))
	elseif command == "ResetLoadout" then
		self:_applyLabState(player, "Reset weapon loadout")
	elseif command == "Refresh" then
		self:_sendRoundState(player)
		self:_sendState(player)
	end
end

return WeaponLabService
