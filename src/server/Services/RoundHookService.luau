local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePhase = require(ReplicatedStorage.Shared.Enums.GamePhase)
local DebugLog = require(ReplicatedStorage.Shared.Utility.DebugLog)

local RoundHookService = {}
RoundHookService.Name = "RoundHookService"
RoundHookService.Dependencies = {
	"RoundManager",
}

function RoundHookService:Init(services)
	self.Services = services
	self.ActiveHooks = {}
	self.DisabledHooks = {}
	self.TriggeredThresholds = {}
end

function RoundHookService:Start()
	DebugLog:Log("Round", "[RoundHookService] Started")
end

function RoundHookService:ResetHooks()
	self.ActiveHooks = {}
	self.DisabledHooks = {}
	self.TriggeredThresholds = {}
end

function RoundHookService:RegisterHook(hook)
	if not hook or not hook.Id then
		return nil
	end

	self.DisabledHooks[hook.Id] = nil
	self.ActiveHooks[hook.Id] = hook
	return hook.Id
end

function RoundHookService:RemoveHook(hookId)
	self.ActiveHooks[hookId] = nil
	self.DisabledHooks[hookId] = nil
	self.TriggeredThresholds[hookId] = nil
end

function RoundHookService:RaisePhaseChanged(phase, duration)
	if phase == GamePhase.Lobby then
		self.TriggeredThresholds = {}
	end

	for _, hook in pairs(self.ActiveHooks) do
		if hook.Trigger == "PhaseChanged" and hook.Phase == phase then
			self:_invokeHook(hook, {
				Phase = phase,
				Duration = duration,
			})
		end
	end
end

function RoundHookService:RaiseObjectiveCompleted(objective)
	for _, hook in pairs(self.ActiveHooks) do
		if hook.Trigger == "ObjectiveCompleted" then
			self:_invokeHook(hook, {
				Objective = objective,
			})
		end
	end
end

function RoundHookService:RaiseTimerTick(phase, timeLeft)
	if phase ~= GamePhase.Reception then
		return
	end

	for _, hook in pairs(self.ActiveHooks) do
		if hook.Trigger == "TimerThreshold" and hook.TimeLeft ~= nil and timeLeft <= hook.TimeLeft then
			if not self.TriggeredThresholds[hook.Id] then
				self.TriggeredThresholds[hook.Id] = true
				self:_invokeHook(hook, {
					Phase = phase,
					TimeLeft = timeLeft,
				})
			end
		end
	end
end

function RoundHookService:ExtendReceptionTime(amount, reason)
	if not amount or amount == 0 then
		return
	end

	local roundManager = self.RoundManager
	if not roundManager or not roundManager:IsReceptionActive() then
		return
	end

	roundManager.TimeLeft = math.max(0, roundManager.TimeLeft + amount)
	roundManager:BroadcastTimer()
	DebugLog:Log("Round", string.format("[RoundHookService] Extended reception by %ss (%s)", tostring(amount), tostring(reason or "Hook")))
end

function RoundHookService:SetReceptionTime(timeLeft, reason)
	if timeLeft == nil then
		return
	end

	local roundManager = self.RoundManager
	if not roundManager or not roundManager:IsReceptionActive() then
		return
	end

	roundManager.TimeLeft = math.max(0, timeLeft)
	roundManager:BroadcastTimer()
	DebugLog:Log("Round", string.format("[RoundHookService] Set reception time to %ss (%s)", tostring(timeLeft), tostring(reason or "Hook")))
end

function RoundHookService:_invokeHook(hook, context)
	if not hook or self.DisabledHooks[hook.Id] then
		return false
	end

	if hook.Callback then
		local ok, err = xpcall(function()
			hook.Callback(context)
		end, debug.traceback)
		if not ok then
			hook.FailureCount = (hook.FailureCount or 0) + 1
			local sourceLabel = hook.SourceLabel or hook.Id or "UnknownHook"
			warn(string.format("[RoundHookService] Hook %s failed: %s", tostring(sourceLabel), tostring(err)))
			DebugLog:Log("Round", string.format("[RoundHookService] Hook %s failed (%d): %s", tostring(sourceLabel), hook.FailureCount, tostring(err)))

			if hook.OnError then
				local onErrorOk, onErrorErr = xpcall(function()
					hook.OnError(err, context)
				end, debug.traceback)
				if not onErrorOk then
					warn(string.format("[RoundHookService] Hook %s OnError failed: %s", tostring(sourceLabel), tostring(onErrorErr)))
				end
			end

			if hook.DisableOnError ~= false then
				self.DisabledHooks[hook.Id] = {
					FailedAt = os.clock(),
					Error = tostring(err),
					FailureCount = hook.FailureCount,
					SourceLabel = sourceLabel,
				}
				self.ActiveHooks[hook.Id] = nil
				self.TriggeredThresholds[hook.Id] = nil
				DebugLog:Log("Round", string.format("[RoundHookService] Disabled failing hook %s", tostring(sourceLabel)))
			end

			return false
		end
	end

	DebugLog:Log("Round", string.format("[RoundHookService] Triggered hook %s", tostring(hook.Id)))
	return true
end

return RoundHookService
