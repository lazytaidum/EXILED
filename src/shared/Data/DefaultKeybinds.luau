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
		F = { ActionToken.Flashlight },

		Q = { ActionToken.Ability1 },

		Z = { ActionToken.Perk1 },
		X = { ActionToken.Perk2 },
		C = { ActionToken.Perk3 },
		V = { ActionToken.Perk4 },
	},

	Mouse = {
<<<<<<< HEAD
		MouseButton1 = { ActionToken.PrimaryFire },
=======
		MouseButton1 = {},
>>>>>>> 9defa84 (WHOLE LOTTA SHT)
		MouseButton2 = {},
		MouseWheel = {},
	},
}

return DefaultKeybinds
