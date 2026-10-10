--!strict

export type BossCoreInfo = {
	DisplayName: string,
	Tier: number,
	BaseCPS: number,
	Description: string?,
}

export type BossConfigType = {
	[string]: BossCoreInfo,
}

local BossConfig: BossConfigType = {
	ForestGolemCore = {
		DisplayName = "Wald-Golem Kern",
		Tier = 1,
		BaseCPS = 5,
		Description = "Ein uralter Kern eines Wald-Golems. Generiert passiv Seelen-Gold.",
	},
}

return table.freeze(BossConfig)
