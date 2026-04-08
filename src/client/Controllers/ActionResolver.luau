local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionResolutionRules = require(ReplicatedStorage.Shared.Data.ActionResolutionRules)

local ActionResolver = {}
ActionResolver.Name = "ActionResolver"

function ActionResolver:ResolveCandidate(candidateToken, contextSnapshot)
	local rules = ActionResolutionRules[candidateToken]
	if not rules then
		return nil
	end
	
	local bestRule = nil
	local bestPriority = -math.huge
	
	for _, rule in ipairs(rules) do
		local matchesContext = rule.context == nil or contextSnapshot[rule.context] == true
		if matchesContext and rule.priority > bestPriority then
			bestPriority = rule.priority
			bestRule = rule
		end
	end
	
	return bestRule and bestRule.action or nil
end

function ActionResolver:ResolveCandidates(candidateTokens, contextSnapshot)
	for _, candidateToken in ipairs(candidateTokens) do
		local resolvedAction = self:ResolveCandidate(candidateToken, contextSnapshot)
		if resolvedAction then
			return resolvedAction
		end
	end
	
	return nil
end

return ActionResolver
