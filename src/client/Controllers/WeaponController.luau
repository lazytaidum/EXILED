local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local WeaponAction = require(ReplicatedStorage.Shared.Enums.WeaponAction)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local WeaponController = {}
WeaponController.Name = "WeaponController"

function WeaponController:Init()
	self.Shared = ReplicatedStorage:WaitForChild("Shared")
	self.RemotesFolder = self.Shared:WaitForChild("Remotes")
	self.RequestWeaponActionRemote = self.RemotesFolder:WaitForChild(RemoteNames.RequestWeaponAction)
	self.WeaponStateChangedRemote = self.RemotesFolder:WaitForChild(RemoteNames.WeaponStateChanged)
	self.WeaponState = nil
end

function WeaponController:Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:RequestWeaponAction(WeaponAction.Fire)
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			self:RequestWeaponAction(WeaponAction.Reload)
		end
	end)

	self.WeaponStateChangedRemote.OnClientEvent:Connect(function(weaponState)
		self:HandleWeaponStateChanged(weaponState)
	end)

	DebugLog:Log("ClientWeapon", "[WeaponController] Started")
end

function WeaponController:RequestWeaponAction(actionName)
	DebugLog:Log("ClientWeapon", string.format("[WeaponController] Requesting weapon action %s", actionName))
	self.RequestWeaponActionRemote:FireServer(actionName)
end

function WeaponController:HandleWeaponStateChanged(weaponState)
	self.WeaponState = weaponState

	DebugLog:Log(
		"ClientWeapon",
		string.format(
			"[WeaponController] Weapon state updated: %s ammo=%d reserve=%d reloading=%s",
			tostring(weaponState.WeaponId),
			weaponState.AmmoInMagazine or 0,
			weaponState.ReserveAmmo or 0,
			tostring(weaponState.IsReloading)
		)
	)
end

return WeaponController
