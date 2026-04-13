local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionToken = require(ReplicatedStorage.Shared.Enums.ActionToken)

local DefaultKeybinds = {
	Keyboard = {
		Space = { ActionToken.PrimaryContextAction },
		E = { ActionToken.SecondaryContextAction, ActionToken.Ability2 },

		LeftShift = { ActionToken.Sprint },
		LeftControl = { ActionToken.Crouch },

		G = { ActionToken.Inventory },
		LeftAlt = { ActionToken.RadialMenu },

		R = { ActionToken.Reload },
		F = { ActionToken.Ability3 },

		Q = { ActionToken.Ability1 },

		Z = { ActionToken.Perk1 },
		X = { ActionToken.Perk2 },
		C = { ActionToken.Perk3 },
		V = { ActionToken.TogglePerspective },
	},

	Mouse = {
		MouseButton1 = { ActionToken.PrimaryFire },
		MouseButton2 = {},
		MouseWheel = {},
	},
}

return DefaultKeybinds
