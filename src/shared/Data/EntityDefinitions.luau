local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityAttributes = require(ReplicatedStorage.Shared.Enums.EntityAttributes)

local EntityDefinitions = {
	TestEntity = {
		Id = "TestEntity",
		DisplayName = "Test Entity",
		StarRating = 1,
		Weight = 1,
		
		Attributes = {
			EntityAttributes.Chase
		},
		
		Stats = {
			Damage = 10,
			AttackRange = 10,
			AttackInterval = 1.5,
			MoveSpeed = 10,
		},
		
		GroupEntity = false,
		PrimaryEntity = false,
	}
}


return EntityDefinitions
