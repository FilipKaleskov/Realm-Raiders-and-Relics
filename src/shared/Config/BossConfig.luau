--!strict

export type BossCoreInfo = {
	DisplayName: string,
	Tier: number,
	BaseCPS: number,
	Description: string?,
	MaxHealth: number,
	AttackDamage: number,
	AttackCooldown: number,
	TelegraphDuration: number,
	TelegraphRadius: number,
	GoldReward: number,
	CoreDropChance: number,
	RespawnTime: number,
}

export type BossConfigType = {
	[string]: BossCoreInfo,
}

local BossConfig: BossConfigType = {
	ForestGolemCore = {
		DisplayName = "Wald-Golem",
		Tier = 1,
		BaseCPS = 5,
		Description = "Ein uralter Kern eines Wald-Golems. Generiert passiv Seelen-Gold.",
		MaxHealth = 300,
		AttackDamage = 30,
		AttackCooldown = 4.0,
		TelegraphDuration = 1.5,
		TelegraphRadius = 14,
		GoldReward = 50,
		CoreDropChance = 1.0, -- 100% Drop zum Testen im MVP
		RespawnTime = 8,
	},
}

return table.freeze(BossConfig)
