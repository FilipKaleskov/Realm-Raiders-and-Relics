--!strict

-- Wut-Phase (Enrage): Stat-Modifikatoren ab einem HP-Schwellwert
export type EnrageInfo = {
	HealthThreshold: number, -- HP-Anteil, unter dem die Wut-Phase startet (0.35 = 35% MaxHealth)
	WalkSpeed: number, -- Boss-Tempo in der Wut-Phase (Studs/s)
	AttackCooldown: number, -- Bodenschlag-Cooldown in der Wut-Phase (Sekunden)
	TelegraphDuration: number, -- Telegraph-/Ausweichfenster in der Wut-Phase (Sekunden)
}

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
	WalkSpeed: number,
	GoldReward: number,
	CoreDropChance: number,
	RespawnTime: number,
	Enrage: EnrageInfo?, -- Optionale Wut-Phase (Bosse ohne Eintrag kämpfen immer im Normalmodus)
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
		-- Tanky-Balancing: 900 HP bei 30 Schaden erzwingen einen 15-25s-Kampf mit aktivem Ausweichen
		MaxHealth = 900,
		AttackDamage = 30,
		AttackCooldown = 3.2,
		TelegraphDuration = 1.4,
		TelegraphRadius = 15,
		WalkSpeed = 11,
		GoldReward = 50,
		CoreDropChance = 1.0, -- 100% Drop zum Testen im MVP
		RespawnTime = 8,
		-- Wut-Phase unter 35% MaxHealth (<= 315 HP): schneller, härter, gnadenloser
		Enrage = {
			HealthThreshold = 0.35,
			WalkSpeed = 14.5,
			AttackCooldown = 2.4,
			TelegraphDuration = 1.05,
		},
	},
}

return table.freeze(BossConfig)
