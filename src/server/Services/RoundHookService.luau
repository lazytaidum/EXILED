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
	self.TriggeredThresholds = {}
end

function RoundHookService:Start()
	DebugLog:Log("Round", "[RoundHookService] Started")
end

function RoundHookService:ResetHooks()
	self.ActiveHooks = {}
	self.TriggeredThresholds = {}
end

function RoundHookService:RegisterHook(hook)
	if not hook or not hook.Id then
		return nil
	end

	self.ActiveHooks[hook.Id] = hook
	return hook.Id
end

function RoundHookService:RemoveHook(hookId)
	self.ActiveHooks[hookId] = nil
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
	if hook.Callback then
		hook.Callback(context)
	end

	DebugLog:Log("Round", string.format("[RoundHookService] Triggered hook %s", tostring(hook.Id)))
end

return RoundHookService
