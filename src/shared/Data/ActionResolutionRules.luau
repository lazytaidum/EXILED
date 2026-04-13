local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionName = require(ReplicatedStorage.Shared.Enums.ActionName)
local ActionToken = require(ReplicatedStorage.Shared.Enums.ActionToken)
local InputContext = require(ReplicatedStorage.Shared.Enums.InputContext)

local ActionResolutionRules = {
	[ActionToken.PrimaryContextAction] = {
		{ context = InputContext.SkillCheck, action = ActionName.SkillCheck, priority = 100 },
		{ context = InputContext.DoorSlam, action = ActionName.DoorSlam, priority = 90 },
		{ context = InputContext.NearObjective, action = ActionName.Interact, priority = 50 },
		{ action = ActionName.Interact, priority = 0 },
	},

	[ActionToken.SecondaryContextAction] = {
		{ context = InputContext.NearToolboxObjective, action = ActionName.ToolboxUse, priority = 100 },
		{ action = ActionName.Ability2, priority = 0 },
	},

	[ActionToken.PrimaryFire] = {
		{ action = ActionName.PrimaryFire, priority = 0 },
	},

	[ActionToken.Sprint] = {
		{ action = ActionName.Sprint, priority = 0 },
	},

	[ActionToken.Crouch] = {
		{ action = ActionName.Crouch, priority = 0 },
	},

	[ActionToken.Inventory] = {
		{ action = ActionName.Inventory, priority = 0 },
	},

	[ActionToken.RadialMenu] = {
		{ action = ActionName.RadialMenu, priority = 0 },
	},

	[ActionToken.Reload] = {
		{ action = ActionName.Reload, priority = 0 },
	},

	[ActionToken.Flashlight] = {
		{ action = ActionName.Flashlight, priority = 0 },
	},

	[ActionToken.Ability1] = {
		{ action = ActionName.Ability1, priority = 0 },
	},

	[ActionToken.Ability2] = {
		{ action = ActionName.Ability2, priority = 0 },
	},

	[ActionToken.Ability3] = {
		{ action = ActionName.Ability3, priority = 0 },
	},

	[ActionToken.Perk1] = {
		{ action = ActionName.Perk1, priority = 0 },
	},

	[ActionToken.Perk2] = {
		{ action = ActionName.Perk2, priority = 0 },
	},

	[ActionToken.Perk3] = {
		{ action = ActionName.Perk3, priority = 0 },
	},

	[ActionToken.Perk4] = {
		{ action = ActionName.Perk4, priority = 0 },
	},
}

return ActionResolutionRules
