--!strict

export type BaseSlot = {
	CoreId: string,
	Level: number,
}

export type DefensesData = {
	Spikes: number,
	Guards: number,
}

export type MaterialsData = {
	IronOre: number,
	VoidCrystal: number,
}

export type InventoryData = {
	Weapons: { string },
	Materials: MaterialsData,
	Cores: { any },
}

export type BaseData = {
	Slots: { [number]: BaseSlot? },
	Defenses: DefensesData,
}

export type PlayerData = {
	Gold: number,
	Gems: number,
	Inventory: InventoryData,
	BaseData: BaseData,
	UnlockedDimensions: { string },
}

local PlayerDataTemplate: PlayerData = {
	Gold = 0,
	Gems = 0,
	Inventory = {
		Weapons = { "RustySword" },
		Materials = {
			IronOre = 0,
			VoidCrystal = 0,
		},
		Cores = {},
	},
	BaseData = {
		Slots = {
			[1] = {
				CoreId = "ForestGolemCore",
				Level = 1,
			},
			[2] = nil,
			[3] = nil,
		},
		Defenses = {
			Spikes = 2,
			Guards = 1,
		},
	},
	UnlockedDimensions = {
		"Dimension_Forest",
	},
}

return PlayerDataTemplate
