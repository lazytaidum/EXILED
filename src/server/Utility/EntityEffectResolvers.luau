local EntityEffectResolvers = {}

local TARGET_RESOLVERS = {}
local POSITION_RESOLVERS = {}

function POSITION_RESOLVERS.CastTargetPosition(service, entity, step, context)
	return context and context.CastData and context.CastData.TargetPosition or nil
end

function POSITION_RESOLVERS.CurrentTargetPosition(service, entity, step, context)
	local targetPlayer = context and context.TargetPlayer
	local targetCharacter = targetPlayer and service.CharacterService:GetCharacterByPlayer(targetPlayer)
	return targetCharacter and targetCharacter.RootPart and targetCharacter.RootPart.Position or nil
end

function POSITION_RESOLVERS.SelfPosition(_, entity)
	return entity and entity:GetPosition() or nil
end

function POSITION_RESOLVERS.ExplicitPosition(_, _, step)
	return step.Position
end

function TARGET_RESOLVERS.CurrentTarget(_, _, _, context)
	return context.TargetPlayer and { context.TargetPlayer } or {}
end

function TARGET_RESOLVERS.Self(_, entity)
	return { entity }
end

function TARGET_RESOLVERS.VisibleTargets(service, entity)
	return service:_collectVisiblePlayers(entity)
end

function TARGET_RESOLVERS.AllCandidates(service, entity)
	return service:_collectCandidatePlayers(entity)
end

function TARGET_RESOLVERS.NearestVisible(service, entity)
	local nearest = service:_getNearestVisiblePlayer(entity)
	return nearest and { nearest } or {}
end

function TARGET_RESOLVERS.PlayersInRadius(service, entity, step)
	return service:_collectPlayersInRadius(entity, step.Radius or 0)
end

function TARGET_RESOLVERS.PlayersNearPosition(service, entity, step, context)
	local targetPosition = EntityEffectResolvers.ResolvePosition(service, entity, step, context)
	return service:_collectPlayersInRadiusOfPosition(targetPosition, step.Radius or 0)
end

function EntityEffectResolvers.ResolveTargets(service, entity, step, context)
	local targetMode = step.Targets or "CurrentTarget"
	local resolver = TARGET_RESOLVERS[targetMode]
	if not resolver then
		return {}
	end

	return resolver(service, entity, step, context)
end

function EntityEffectResolvers.ResolvePosition(service, entity, step, context)
	local positionSource = step.PositionSource or "CastTargetPosition"
	local resolver = POSITION_RESOLVERS[positionSource]
	if not resolver then
		resolver = POSITION_RESOLVERS.CastTargetPosition
	end

	return resolver(service, entity, step, context)
end

return EntityEffectResolvers
