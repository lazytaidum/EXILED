local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local QTEType = require(ReplicatedStorage.Shared.Enums.QTEType)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local QTEService = {}
QTEService.Name = "QTEService"
QTEService.Dependencies = {
	"RemoteRegistry",
}

function QTEService:Init(services)
	self.Services = services
	self.ActiveSessions = {}
	self.UpdateInterval = 0.05
	self.SessionCounter = 0
end

function QTEService:Start()
	self.QTEStateRemote = self.RemoteRegistry:GetRemote(RemoteNames.QTEStateChanged)
	local requestQTEInput = self.RemoteRegistry:GetRemote(RemoteNames.RequestQTEInput)

	requestQTEInput.OnServerEvent:Connect(function(player, payload)
		self:HandleInput(player, payload)
	end)

	task.spawn(function()
		while true do
			self:_updateSessions()
			task.wait(self.UpdateInterval)
		end
	end)

	DebugLog:Log("Interaction", "[QTEService] Started")
end

function QTEService:StartSession(player, config)
	if not player or not config then
		return nil
	end

	if self.ActiveSessions[player] then
		self:StopSession(player, "Replaced")
	end

	self.SessionCounter += 1
	local now = os.clock()
	local session = {
		Id = string.format("QTE-%d", self.SessionCounter),
		Player = player,
		Type = config.Type or QTEType.KeyMash,
		Prompt = config.Prompt or "Quick Time Event",
		SubPrompt = config.SubPrompt or "",
		Duration = config.Duration or 5,
		StartedAt = now,
		EndsAt = now + (config.Duration or 5),
		Progress = config.Progress or 0,
		MaxProgress = config.MaxProgress or 1,
		RequiredKey = config.RequiredKey,
		Keys = config.Keys,
		CurrentKeyIndex = 1,
		ProgressPerPress = config.ProgressPerPress or 0.1,
		WrongPenalty = config.WrongPenalty or 0.05,
		TargetDistance = config.TargetDistance or 600,
		MinSliceDelta = config.MinSliceDelta or 6,
		DialAngle = config.DialAngle or Random.new():NextNumber(0, 360),
		DialSpeed = config.DialSpeed or 240,
		DialDirection = config.DialDirection or 1,
		SuccessAngle = config.SuccessAngle or Random.new():NextNumber(0, 360),
		SuccessAngleSize = config.SuccessAngleSize or 42,
		LastUpdatedAt = now,
		OnSuccess = config.OnSuccess,
		OnFail = config.OnFail,
		OnProgress = config.OnProgress,
	}

	self.ActiveSessions[player] = session
	self:_syncSession(session, "Start")
	return session
end

function QTEService:GetSession(player)
	return self.ActiveSessions[player]
end

function QTEService:IsSessionActive(player)
	return self.ActiveSessions[player] ~= nil
end

function QTEService:StopSession(player, reason)
	local session = self.ActiveSessions[player]
	if not session then
		return
	end

	self.ActiveSessions[player] = nil
	self:_syncStop(player, reason or "Ended")
end

function QTEService:HandleInput(player, payload)
	local session = self.ActiveSessions[player]
	if not session or type(payload) ~= "table" then
		return
	end

	if session.Type == QTEType.KeyMash then
		self:_handleKeyMashInput(session, payload)
	elseif session.Type == QTEType.SequenceKeys then
		self:_handleSequenceInput(session, payload)
	elseif session.Type == QTEType.MouseSlice then
		self:_handleMouseSliceInput(session, payload)
	elseif session.Type == QTEType.TimingDial then
		self:_handleTimingDialInput(session, payload)
	end
end

function QTEService:_handleKeyMashInput(session, payload)
	if payload.Kind ~= "Press" then
		return
	end

	local payloadKey = type(payload.Key) == "string" and string.lower(payload.Key) or payload.Key
	local requiredKey = type(session.RequiredKey) == "string" and string.lower(session.RequiredKey) or session.RequiredKey
	if requiredKey and payloadKey ~= requiredKey then
		return
	end

	session.Progress = math.min(session.MaxProgress, session.Progress + session.ProgressPerPress)
	self:_notifyProgress(session)
	if session.Progress >= session.MaxProgress then
		self:_completeSession(session, "Success")
	end
end

function QTEService:_handleSequenceInput(session, payload)
	if payload.Kind ~= "Press" then
		return
	end

	local expectedKey = session.Keys and session.Keys[session.CurrentKeyIndex]
	if not expectedKey then
		return
	end

	local payloadKey = type(payload.Key) == "string" and string.lower(payload.Key) or payload.Key
	local normalizedExpectedKey = type(expectedKey) == "string" and string.lower(expectedKey) or expectedKey
	if payloadKey == normalizedExpectedKey then
		session.CurrentKeyIndex += 1
		session.Progress = math.min(session.MaxProgress, session.Progress + session.ProgressPerPress)
		self:_notifyProgress(session)
		if not session.Keys[session.CurrentKeyIndex] or session.Progress >= session.MaxProgress then
			self:_completeSession(session, "Success")
		end
	else
		session.Progress = math.max(0, session.Progress - session.WrongPenalty)
		self:_notifyProgress(session)
	end
end

function QTEService:_handleMouseSliceInput(session, payload)
	if payload.Kind ~= "Slice" or typeof(payload.Delta) ~= "Vector2" then
		return
	end

	local magnitude = payload.Delta.Magnitude
	if magnitude < session.MinSliceDelta then
		return
	end

	session.Progress = math.min(session.MaxProgress, session.Progress + (magnitude / session.TargetDistance))
	self:_notifyProgress(session)
	if session.Progress >= session.MaxProgress then
		self:_completeSession(session, "Success")
	end
end

function QTEService:_handleTimingDialInput(session, payload)
	if payload.Kind ~= "Press" then
		return
	end

	local angleDelta = math.abs(((session.DialAngle - session.SuccessAngle + 180) % 360) - 180)
	local successThreshold = math.max(1, (session.SuccessAngleSize or 0) * 0.5)
	if angleDelta <= successThreshold then
		session.Progress = math.min(session.MaxProgress, session.Progress + session.ProgressPerPress)
		session.DialDirection *= -1
		session.SuccessAngle = Random.new():NextNumber(0, 360)
		self:_notifyProgress(session)
		if session.Progress >= session.MaxProgress then
			self:_completeSession(session, "Success")
		end
	else
		session.Progress = math.max(0, session.Progress - session.WrongPenalty)
		self:_notifyProgress(session)
	end
end

function QTEService:_notifyProgress(session)
	if session.OnProgress then
		session.OnProgress(session.Player, session)
	end

	self:_syncSession(session, "Update")
end

function QTEService:_updateSessions()
	local now = os.clock()
	for player, session in pairs(self.ActiveSessions) do
		if session.Type == QTEType.TimingDial then
			local deltaTime = math.max(0, now - (session.LastUpdatedAt or now))
			session.DialAngle = (session.DialAngle + ((session.DialSpeed or 0) * (session.DialDirection or 1) * deltaTime)) % 360
			session.LastUpdatedAt = now
		end

		if now >= session.EndsAt then
			self:_failSession(session, "Expired")
		else
			self:_syncSession(session, "Update")
		end
	end
end

function QTEService:_completeSession(session, reason)
	if self.ActiveSessions[session.Player] ~= session then
		return
	end

	self.ActiveSessions[session.Player] = nil
	self:_syncStop(session.Player, reason or "Success")
	if session.OnSuccess then
		session.OnSuccess(session.Player, session)
	end
end

function QTEService:_failSession(session, reason)
	if self.ActiveSessions[session.Player] ~= session then
		return
	end

	self.ActiveSessions[session.Player] = nil
	self:_syncStop(session.Player, reason or "Failed")
	if session.OnFail then
		session.OnFail(session.Player, session, reason or "Failed")
	end
end

function QTEService:_syncSession(session, state)
	if not self.QTEStateRemote then
		return
	end

	local expectedKey = session.Keys and session.Keys[session.CurrentKeyIndex] or nil
	self.QTEStateRemote:FireClient(session.Player, {
		State = state,
		Id = session.Id,
		Type = session.Type,
		Prompt = session.Prompt,
		SubPrompt = session.SubPrompt,
		Duration = math.max(0, session.EndsAt - os.clock()),
		Progress = session.Progress,
		Max = session.MaxProgress,
		RequiredKey = session.RequiredKey,
		ExpectedKey = expectedKey,
		KeysRemaining = session.Keys and math.max(0, (#session.Keys - session.CurrentKeyIndex) + 1) or nil,
		DialAngle = session.DialAngle,
		SuccessAngle = session.SuccessAngle,
		SuccessAngleSize = session.SuccessAngleSize,
	})
end

function QTEService:_syncStop(player, reason)
	if not self.QTEStateRemote then
		return
	end

	self.QTEStateRemote:FireClient(player, {
		State = "Stop",
		Reason = reason or "Ended",
	})
end

return QTEService
