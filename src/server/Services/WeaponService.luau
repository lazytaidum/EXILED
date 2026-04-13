local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponDefinitions = require(ReplicatedStorage.Shared.Data.WeaponDefinitions)
local WeaponAction = require(ReplicatedStorage.Shared.Enums.WeaponAction)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local WeaponService = {}
WeaponService.Name = "WeaponService"

function WeaponService:Init(services)
	self.Services = services
	self.PlayerWeapons = {}
end

function WeaponService:Start()
	self.RequestWeaponActionRemote = self.Services.RemoteRegistry:GetRemote(RemoteNames.RequestWeaponAction)
	self.WeaponStateChangedRemote = self.Services.RemoteRegistry:GetRemote(RemoteNames.WeaponStateChanged)

	self.RequestWeaponActionRemote.OnServerEvent:Connect(function(player, actionName)
		self:HandleWeaponAction(player, actionName)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:EquipDefaultWeapon(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:EquipDefaultWeapon(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerWeapons[player] = nil
	end)

	DebugLog:Log("Weapon", "[WeaponService] Started")
end

function WeaponService:HandleWeaponAction(player, actionName)
	local weaponState = self.PlayerWeapons[player]
	if not weaponState then
		return
	end

	local playerState = self.Services.PlayerService and self.Services.PlayerService:GetPlayerState(player)
	if not playerState or not playerState.IsAlive then
		DebugLog:Log("Weapon", string.format("[WeaponService] Ignored %s from %s: player not alive", tostring(actionName), player.Name))
		return
	end

	if actionName == WeaponAction.Fire then
		self:FireWeapon(player, weaponState)
	elseif actionName == WeaponAction.Reload then
		self:ReloadWeapon(player, weaponState)
	end
end

function WeaponService:EquipDefaultWeapon(player)
	local definition = WeaponDefinitions.Glock45
	if not definition then
		return
	end

	self.PlayerWeapons[player] = {
		WeaponId = definition.Id,
		AmmoInMagazine = definition.MagazineSize,
		ReserveAmmo = definition.ReserveAmmo,
		IsReloading = false,
		LastFireTime = 0,
		ReloadToken = 0,
	}

	self:SendWeaponState(player)
	DebugLog:Log("Weapon", string.format("[WeaponService] Equipped %s for %s", definition.Id, player.Name))
end

function WeaponService:FireWeapon(player, weaponState)
	local definition = WeaponDefinitions[weaponState.WeaponId]
	if not definition then
		return
	end

	if weaponState.IsReloading then
		DebugLog:Log("Weapon", string.format("[WeaponService] Ignored fire from %s: reload in progress", player.Name))
		return
	end

	local now = os.clock()
	if now - weaponState.LastFireTime < definition.FireCooldown then
		return
	end

	if weaponState.AmmoInMagazine <= 0 then
		DebugLog:Log("Weapon", string.format("[WeaponService] Ignored fire from %s: empty magazine", player.Name))
		return
	end

	weaponState.LastFireTime = now
	weaponState.AmmoInMagazine -= 1

	-- Hit detection and damage stay server-owned and can be layered in here later.
	self:SendWeaponState(player)
	DebugLog:Log(
		"Weapon",
		string.format(
			"[WeaponService] %s fired %s (%d/%d)",
			player.Name,
			weaponState.WeaponId,
			weaponState.AmmoInMagazine,
			weaponState.ReserveAmmo
		)
	)
end

function WeaponService:ReloadWeapon(player, weaponState)
	local definition = WeaponDefinitions[weaponState.WeaponId]
	if not definition then
		return
	end

	if weaponState.IsReloading then
		return
	end

	if weaponState.AmmoInMagazine >= definition.MagazineSize then
		return
	end

	if weaponState.ReserveAmmo <= 0 then
		return
	end

	weaponState.IsReloading = true
	weaponState.ReloadToken += 1
	local reloadToken = weaponState.ReloadToken

	self:SendWeaponState(player)
	DebugLog:Log("Weapon", string.format("[WeaponService] %s started reload for %s", player.Name, weaponState.WeaponId))

	task.delay(definition.ReloadDuration, function()
		local liveWeaponState = self.PlayerWeapons[player]
		if not liveWeaponState or liveWeaponState.ReloadToken ~= reloadToken then
			return
		end

		local missingAmmo = definition.MagazineSize - liveWeaponState.AmmoInMagazine
		local ammoToLoad = math.min(missingAmmo, liveWeaponState.ReserveAmmo)
		liveWeaponState.AmmoInMagazine += ammoToLoad
		liveWeaponState.ReserveAmmo -= ammoToLoad
		liveWeaponState.IsReloading = false

		self:SendWeaponState(player)
		DebugLog:Log("Weapon", string.format("[WeaponService] %s completed reload for %s", player.Name, liveWeaponState.WeaponId))
	end)
end

function WeaponService:SendWeaponState(player)
	local weaponState = self.PlayerWeapons[player]
	if not weaponState then
		return
	end

	self.WeaponStateChangedRemote:FireClient(player, {
		WeaponId = weaponState.WeaponId,
		AmmoInMagazine = weaponState.AmmoInMagazine,
		ReserveAmmo = weaponState.ReserveAmmo,
		IsReloading = weaponState.IsReloading,
	})
end

return WeaponService
