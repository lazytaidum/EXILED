local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local RemnantDefinitions = require(ReplicatedStorage.Shared.Data.RemnantDefinitions)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RemnantService = {}
RemnantService.Name = "RemnantService"
RemnantService.Dependencies = {
	"RemoteRegistry",
	"RoundManager",
	"CharacterService",
	"ObjectiveService",
	"WeaponPickupService",
	"ItemPickupService",
	"EntityService",
}

function RemnantService:Init(services)
	self.Services = services
	self.PlayerStates = {}
	self.ActiveWatchtowers = {}
	self.UpdateInterval = 0.15
	self.DevicesFolder = Workspace:FindFirstChild("RemnantDevices")
	if not self.DevicesFolder then
		self.DevicesFolder = Instance.new("Folder")
		self.DevicesFolder.Name = "RemnantDevices"
		self.DevicesFolder.Parent = Workspace
	end
end

function RemnantService:Start()
	self.RequestAbilityRemote = self.RemoteRegistry:GetRemote(RemoteNames.RequestRemnantAbility)
	self.RemnantStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.RemnantStateChanged)
	self.AuraRevealStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.AuraRevealStateChanged)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_initializePlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_initializePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_destroyWatchtower(player)
		self.PlayerStates[player] = nil
	end)

	if self.RequestAbilityRemote then
		self.RequestAbilityRemote.OnServerEvent:Connect(function(player, abilitySlot)
			self:HandleAbilityRequest(player, abilitySlot)
		end)
	end

	task.spawn(function()
		self:_runLoop()
	end)

	DebugLog:Log("Remnant", "[RemnantService] Started")
end

function RemnantService:_runLoop()
	while true do
		self:_cleanupInactiveRoundState()
		self:_updateWatchtowers()
		self:_updateRevealStates()
		task.wait(self.UpdateInterval)
	end
end

function RemnantService:_initializePlayer(player)
	local definition = RemnantDefinitions.Baam
	local abilities = {}
	for slotName, abilityDefinition in pairs(definition.Abilities or {}) do
		abilities[slotName] = {
			Id = abilityDefinition.Id,
			DisplayName = abilityDefinition.DisplayName,
			Keybind = abilityDefinition.Keybind,
			Cooldown = abilityDefinition.Cooldown or 0,
			CooldownEndsAt = 0,
			IsImplemented = abilityDefinition.IsImplemented ~= false,
		}
	end

	self.PlayerStates[player] = {
		RemnantId = definition.Id,
		Fragments = definition.DefaultFragments or 0,
		Abilities = abilities,
		Reveals = {},
	}

	self:_pushState(player)
	self:_pushRevealState(player)
end

function RemnantService:_cleanupInactiveRoundState()
	if self.RoundManager and self.RoundManager:IsReceptionActive() then
		return
	end

	for player, state in pairs(self.PlayerStates) do
		local hadChanges = false

		if self.ActiveWatchtowers[player] then
			self:_destroyWatchtower(player)
			hadChanges = true
		end

		if next(state.Reveals) ~= nil then
			table.clear(state.Reveals)
			hadChanges = true
			self:_pushRevealState(player)
		end

		for _, abilityState in pairs(state.Abilities or {}) do
			if (abilityState.CooldownEndsAt or 0) > 0 then
				abilityState.CooldownEndsAt = 0
				hadChanges = true
			end
		end

		if hadChanges then
			self:_pushState(player)
		end
	end
end

function RemnantService:GetPlayerState(player)
	return self.PlayerStates[player]
end

function RemnantService:HandleAbilityRequest(player, abilitySlot)
	if type(abilitySlot) ~= "string" then
		return false
	end

	local state = self.PlayerStates[player]
	if not state then
		return false
	end

	if not self.RoundManager or not self.RoundManager:IsReceptionActive() then
		return false
	end

	local roundState = self.RoundManager:GetRoundState(player)
	local character = self.CharacterService and self.CharacterService:GetCharacterByPlayer(player)
	if not roundState or not roundState.IsAlive or not character or not character:IsAlive() then
		return false
	end

	local abilityState = state.Abilities[abilitySlot]
	if not abilityState or not abilityState.IsImplemented then
		return false
	end

	local now = os.clock()
	if (abilityState.CooldownEndsAt or 0) > now then
		return false
	end

	local didUse = false
	if abilityState.Id == "WatchersEye" then
		didUse = self:_useWatchersEye(player, state)
	elseif abilityState.Id == "Watchtower" then
		didUse = self:_useWatchtower(player, state, character)
	end

	if not didUse then
		return false
	end

	abilityState.CooldownEndsAt = now + (abilityState.Cooldown or 0)
	self:_pushState(player)
	DebugLog:Log("Remnant", string.format("[RemnantService] %s used %s", player.Name, abilityState.Id))
	return true
end

function RemnantService:_useWatchersEye(player, state)
	local fragments = state.Fragments or 0
	local duration = 2.5
	if fragments >= 5 then
		duration += 1.5
	end

	local reveals = {}

	if fragments >= 1 and self.ObjectiveService then
		for _, objective in ipairs(self.ObjectiveService:GetObjectives()) do
			if objective.Instance then
				table.insert(reveals, {
					Instance = objective.Instance,
					Type = "Objective",
					DisplayName = objective.DisplayName or objective.Id or objective.Instance.Name,
					Duration = duration,
				})
			end
		end
	end

	if fragments >= 2 and self.RoundManager and self.CharacterService then
		for _, otherPlayer in ipairs(self.RoundManager:GetActivePlayers()) do
			if otherPlayer ~= player then
				local otherCharacter = self.CharacterService:GetCharacterByPlayer(otherPlayer)
				if otherCharacter and otherCharacter.Model then
					table.insert(reveals, {
						Instance = otherCharacter.Model,
						Type = "Remnant",
						DisplayName = otherPlayer.Name,
						Duration = duration,
					})
				end
			end
		end
	end

	if fragments >= 3 and self.EntityService then
		for _, entity in ipairs(self.EntityService.Entities or {}) do
			if entity.IsActive and entity.Model then
				table.insert(reveals, {
					Instance = entity.Model,
					Type = "Entity",
					DisplayName = entity.DisplayName or entity.Id,
					Duration = duration,
				})
			end
		end
	end

	if fragments >= 4 then
		if self.WeaponPickupService then
			for _, pickup in ipairs(self.WeaponPickupService:GetAvailablePickups() or {}) do
				if pickup.Instance then
					table.insert(reveals, {
						Instance = pickup.Instance,
						Type = "Loot",
						DisplayName = pickup.DisplayName or pickup.WeaponId or pickup.Instance.Name,
						Duration = duration,
					})
				end
			end
		end

		if self.ItemPickupService then
			for _, pickup in ipairs(self.ItemPickupService:GetAvailablePickups() or {}) do
				if pickup.Instance then
					table.insert(reveals, {
						Instance = pickup.Instance,
						Type = "Loot",
						DisplayName = pickup.DisplayName or pickup.ItemId or pickup.Instance.Name,
						Duration = duration,
					})
				end
			end
		end
	end

	if #reveals == 0 then
		return false
	end

	local now = os.clock()
	local activeReveals = state.Reveals
	for _, reveal in ipairs(reveals) do
		local key = reveal.Instance
		local existing = activeReveals[key]
		local expiresAt = now + (reveal.Duration or duration)
		if existing then
			existing.ExpiresAt = math.max(existing.ExpiresAt or 0, expiresAt)
			existing.Type = reveal.Type
			existing.DisplayName = reveal.DisplayName
		else
			activeReveals[key] = {
				Instance = reveal.Instance,
				Type = reveal.Type,
				DisplayName = reveal.DisplayName,
				ExpiresAt = expiresAt,
			}
		end
	end

	self:_pushRevealState(player)
	return true
end

function RemnantService:_useWatchtower(player, state, character)
	local definition = RemnantDefinitions[state.RemnantId] or RemnantDefinitions.Baam
	local abilityDefinition = definition.Abilities and definition.Abilities.Ability3
	if not abilityDefinition or not character or not character.RootPart then
		return false
	end

	self:_destroyWatchtower(player)

	local rootPart = character.RootPart
	local forward = rootPart.CFrame.LookVector
	local position = rootPart.Position + (forward * 4)

	local beacon = Instance.new("Part")
	beacon.Name = string.format("%sWatchtower", player.Name)
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(0.7, 2.4, 2.4)
	beacon.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(102, 214, 255)
	beacon.Transparency = 0.15
	beacon.Parent = self.DevicesFolder

	local pulse = Instance.new("Part")
	pulse.Name = "Radius"
	pulse.Shape = Enum.PartType.Cylinder
	pulse.Size = Vector3.new(0.08, abilityDefinition.Radius * 2, abilityDefinition.Radius * 2)
	pulse.CFrame = CFrame.new(position + Vector3.new(0, -2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanQuery = false
	pulse.CanTouch = false
	pulse.Material = Enum.Material.ForceField
	pulse.Color = Color3.fromRGB(90, 184, 255)
	pulse.Transparency = 0.82
	pulse.Parent = self.DevicesFolder

	-- Soft center marker for the owner's stronger reveal radius.
	local innerPulse = Instance.new("Part")
	innerPulse.Name = "OwnerRadius"
	innerPulse.Shape = Enum.PartType.Cylinder
	innerPulse.Size = Vector3.new(0.05, abilityDefinition.OwnerRadius * 2, abilityDefinition.OwnerRadius * 2)
	innerPulse.CFrame = CFrame.new(position + Vector3.new(0, -2.78, 0)) * CFrame.Angles(0, 0, math.rad(90))
	innerPulse.Anchored = true
	innerPulse.CanCollide = false
	innerPulse.CanQuery = false
	innerPulse.CanTouch = false
	innerPulse.Material = Enum.Material.ForceField
	innerPulse.Color = Color3.fromRGB(160, 233, 255)
	innerPulse.Transparency = 0.93
	innerPulse.Parent = self.DevicesFolder

	self.ActiveWatchtowers[player] = {
		Player = player,
		Position = position,
		Radius = abilityDefinition.Radius or 300,
		OwnerRadius = abilityDefinition.OwnerRadius or abilityDefinition.Radius or 300,
		ExpiresAt = os.clock() + (abilityDefinition.Duration or 50),
		Beacon = beacon,
		Pulse = pulse,
		InnerPulse = innerPulse,
	}

	return true
end

function RemnantService:_updateWatchtowers()
	local now = os.clock()
	for player, tower in pairs(self.ActiveWatchtowers) do
		if not tower or tower.ExpiresAt <= now then
			self:_destroyWatchtower(player)
		else
			self:_tickWatchtower(tower)
		end
	end
end

function RemnantService:_tickWatchtower(tower)
	if not self.RoundManager or not self.CharacterService or not self.EntityService then
		return
	end

	local changedPlayers = {}
	for _, occupant in ipairs(self.RoundManager:GetActivePlayers()) do
		local roundState = self.RoundManager:GetRoundState(occupant)
		local character = self.CharacterService:GetCharacterByPlayer(occupant)
		if roundState and roundState.IsAlive and character and character.RootPart then
			local distanceToTower = (character.RootPart.Position - tower.Position).Magnitude
			if distanceToTower <= tower.Radius then
				local revealRadius = occupant == tower.Player and tower.OwnerRadius or tower.Radius
				for _, entity in ipairs(self.EntityService.Entities or {}) do
					if entity.IsActive and entity.Model then
						local entityPosition = entity:GetPosition()
						if entityPosition and (entityPosition - tower.Position).Magnitude <= revealRadius then
							local changed = self:_grantReveal(occupant, {
								Instance = entity.Model,
								Type = "Entity",
								DisplayName = entity.DisplayName or entity.Id,
							}, 0.35)
							if changed then
								changedPlayers[occupant] = true
							end
						end
					end
				end
			end
		end
	end

	for player in pairs(changedPlayers) do
		if self.PlayerStates[player] then
			self:_pushRevealState(player)
		end
	end
end

function RemnantService:_grantReveal(player, reveal, duration)
	local state = self.PlayerStates[player]
	if not state or not reveal or not reveal.Instance then
		return false
	end

	local activeReveals = state.Reveals
	local key = reveal.Instance
	local expiresAt = os.clock() + math.max(0, duration or 0)
	local existing = activeReveals[key]
	if existing then
		local previousExpiry = existing.ExpiresAt or 0
		existing.ExpiresAt = math.max(previousExpiry, expiresAt)
		existing.Type = reveal.Type
		existing.DisplayName = reveal.DisplayName
		return expiresAt > previousExpiry
	end

	activeReveals[key] = {
		Instance = reveal.Instance,
		Type = reveal.Type,
		DisplayName = reveal.DisplayName,
		ExpiresAt = expiresAt,
	}
	return true
end

function RemnantService:_destroyWatchtower(player)
	local tower = self.ActiveWatchtowers[player]
	if not tower then
		return
	end

	if tower.Beacon then
		tower.Beacon:Destroy()
	end
	if tower.Pulse then
		tower.Pulse:Destroy()
	end
	if tower.InnerPulse then
		tower.InnerPulse:Destroy()
	end

	self.ActiveWatchtowers[player] = nil
end

function RemnantService:_updateRevealStates()
	local now = os.clock()
	for player, state in pairs(self.PlayerStates) do
		local changed = false
		for instance, reveal in pairs(state.Reveals) do
			if reveal.ExpiresAt <= now or instance == nil or instance.Parent == nil then
				state.Reveals[instance] = nil
				changed = true
			end
		end

		if changed then
			self:_pushRevealState(player)
		end
	end
end

function RemnantService:_pushState(player)
	if not self.RemnantStateRemote then
		return
	end

	local state = self.PlayerStates[player]
	if not state then
		return
	end

	local definition = RemnantDefinitions[state.RemnantId] or RemnantDefinitions.Baam

	local abilities = {}
	local now = os.clock()
	for slotName, abilityState in pairs(state.Abilities) do
		abilities[slotName] = {
			Id = abilityState.Id,
			DisplayName = abilityState.DisplayName,
			Keybind = abilityState.Keybind,
			Cooldown = abilityState.Cooldown,
			CooldownRemaining = math.max(0, (abilityState.CooldownEndsAt or 0) - now),
			IsImplemented = abilityState.IsImplemented,
		}
	end

	self.RemnantStateRemote:FireClient(player, {
		RemnantId = state.RemnantId,
		DisplayName = definition.DisplayName or state.RemnantId,
		Fragments = state.Fragments,
		Abilities = abilities,
	})
end

function RemnantService:_pushRevealState(player)
	if not self.AuraRevealStateRemote then
		return
	end

	local state = self.PlayerStates[player]
	if not state then
		return
	end

	local now = os.clock()
	local snapshot = {}
	for _, reveal in pairs(state.Reveals) do
		if reveal.Instance and reveal.Instance.Parent then
			table.insert(snapshot, {
				Instance = reveal.Instance,
				Type = reveal.Type,
				DisplayName = reveal.DisplayName,
				Duration = math.max(0, reveal.ExpiresAt - now),
			})
		end
	end

	self.AuraRevealStateRemote:FireClient(player, snapshot)
end

return RemnantService
