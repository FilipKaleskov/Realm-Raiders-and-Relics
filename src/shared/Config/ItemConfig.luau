--!strict

export type ItemRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type ItemInfo = {
	Id: string,
	DisplayName: string,
	Category: "Weapon" | "Core" | "Material",
	TypeLabel: string,
	Rarity: ItemRarity,
	RarityLabel: string,
	RarityColor: Color3,
	Icon: string,
	Description: string,
	StatsText: string,
	DetailedStats: string,
	UsageTip: string,
	Damage: number?,
	Cooldown: number?,
	Reach: number?, -- Nahkampf-Reichweite in Studs (nil = Standard-Reichweite 14.0 im BossService)
	CostGold: number?,
	CostMaterials: { [string]: number }?,
	TrailColor: Color3?,
	TrailSecondaryColor: Color3?,
}

export type DefenseShopItem = {
	Id: "Spikes" | "Guards",
	DisplayName: string,
	Category: "Defense",
	Icon: string,
	Description: string,
	StatsText: string,
	CostGold: number,
	CostMaterials: { [string]: number },
	MaxCount: number,
}

export type SlotUnlockInfo = {
	SlotIndex: number,
	CostGold: number,
	DisplayName: string,
	Description: string,
}

local ItemConfig: { [string]: ItemInfo } = {
	-- Waffen
	RustySword = {
		Id = "RustySword",
		DisplayName = "Rostiges Schwert",
		Category = "Weapon",
		TypeLabel = "Nahkampfwaffe",
		Rarity = "Common",
		RarityLabel = "GEWÖHNLICH",
		RarityColor = Color3.fromRGB(150, 160, 185),
		Icon = "⚔️",
		Description = "Eine einfache Klinge, die von vergangenen Abenteuern und Expeditionen gezeichnet ist. Trotz Rost verursacht sie verlässlichen Nahkampfschaden.",
		StatsText = "25 Schaden",
		DetailedStats = "25 HP Schaden  •  0.35s Cooldown",
		UsageTip = "Standard-Waffe. Schlage auf Feinde mit Linksklick oder Taste [F].",
		Damage = 25,
		Cooldown = 0.35,
		Reach = 13.0,
		CostGold = 0,
		CostMaterials = {},
		TrailColor = Color3.fromRGB(255, 235, 120),
		TrailSecondaryColor = Color3.fromRGB(255, 160, 0),
	},

	IronSword = {
		Id = "IronSword",
		DisplayName = "Eisenschwert",
		Category = "Weapon",
		TypeLabel = "Solide Schmiedeklinge",
		Rarity = "Uncommon",
		RarityLabel = "UNGEWÖHNLICH",
		RarityColor = Color3.fromRGB(80, 180, 255),
		Icon = "🗡️",
		Description = "Aus reinem Eisenerz geschmiedet und auf einem Granit-Schleifstein abgezogen. Liegt perfekt in der Hand und durchschlägt selbst Golem-Rinde.",
		StatsText = "45 Schaden",
		DetailedStats = "45 HP Schaden  •  0.30s Cooldown",
		UsageTip = "Richte fast doppelten Schaden an. Ideal gegen Wächter-Minions und Bosse.",
		Damage = 45,
		Cooldown = 0.30,
		Reach = 14.5,
		CostGold = 250,
		CostMaterials = { IronOre = 10 },
		TrailColor = Color3.fromRGB(160, 230, 255),
		TrailSecondaryColor = Color3.fromRGB(40, 120, 240),
	},

	AmethystBlade = {
		Id = "AmethystBlade",
		DisplayName = "Amethyst-Klinge",
		Category = "Weapon",
		TypeLabel = "Magische Dimensions-Waffe",
		Rarity = "Epic",
		RarityLabel = "EPISCH",
		RarityColor = Color3.fromRGB(180, 70, 255),
		Icon = "🔮",
		Description = "Eine edle Klinge aus geschliffenem Amethyst-Kristall, durchströmt von arkaner Void-Energie. Zerschneidet Rüstungen mit Leichtigkeit.",
		StatsText = "80 Schaden",
		DetailedStats = "80 HP Schaden  •  0.24s Cooldown  •  Schnelle Hiebe",
		UsageTip = "Gewährt rasante Angriffsgeschwindigkeit und hohen Burst-Schaden.",
		Damage = 80,
		Cooldown = 0.24,
		Reach = 16.0,
		CostGold = 800,
		CostMaterials = { VoidCrystal = 5 },
		TrailColor = Color3.fromRGB(225, 110, 255),
		TrailSecondaryColor = Color3.fromRGB(140, 20, 220),
	},

	VoidScythe = {
		Id = "VoidScythe",
		DisplayName = "Leeren-Sense",
		Category = "Weapon",
		TypeLabel = "Legendäre Relikt-Sense",
		Rarity = "Legendary",
		RarityLabel = "LEGENDÄR",
		RarityColor = Color3.fromRGB(255, 60, 80),
		Icon = "☠️",
		Description = "Die ultimative Waffe aus den tiefsten Abgründen des Dimensions-Risses. Ihre Klinge hinterlässt purpurne Risse in der Realität.",
		StatsText = "140 Schaden",
		DetailedStats = "140 HP Schaden  •  0.20s Cooldown  •  Hohe Reichweite",
		UsageTip = "Vernichtet Feinde und Bosse in Rekordzeit.",
		Damage = 140,
		Cooldown = 0.20,
		Reach = 18.5,
		CostGold = 2500,
		CostMaterials = { VoidCrystal = 15 },
		TrailColor = Color3.fromRGB(255, 40, 80),
		TrailSecondaryColor = Color3.fromRGB(160, 0, 30),
	},

	-- Seelenkerne
	ForestGolemCore = {
		Id = "ForestGolemCore",
		DisplayName = "Wald-Golem Kern",
		Category = "Core",
		TypeLabel = "Seelenkern (Boss)",
		Rarity = "Rare",
		RarityLabel = "SELTEN",
		RarityColor = Color3.fromRGB(46, 204, 113),
		Icon = "🌿",
		Description = "Der pulsierende Lebenskern des uralten Wald-Golems. Ausgestattet mit naturmagischer Energie erzeugt er kontinuierlich passives Seelen-Gold.",
		StatsText = "+5 Gold/s",
		DetailedStats = "+5 Gold/s pro Sockel-Stufe  •  Tier 1",
		UsageTip = "Tritt auf deiner Basis an einen leeren Sockel heran und drücke [E], um ihn zu platzieren.",
	},

	-- Materialien
	IronOre = {
		Id = "IronOre",
		DisplayName = "Eisenerz",
		Category = "Material",
		TypeLabel = "Schmiede-Rohstoff",
		Rarity = "Common",
		RarityLabel = "GEWÖHNLICH",
		RarityColor = Color3.fromRGB(150, 160, 185),
		Icon = "⛏️",
		Description = "Schweres, unverarbeitetes Gestein mit dichtem Eisengehalt. Grundbaustein für solide Fallen und Werkzeuge.",
		StatsText = "Rohstoff",
		DetailedStats = "Handwerks- & Baumaterial",
		UsageTip = "Wird zum Errichten von Stachelfallen und Barrikaden auf deiner Basis benötigt.",
	},
	VoidCrystal = {
		Id = "VoidCrystal",
		DisplayName = "Void-Kristall",
		Category = "Material",
		TypeLabel = "Dimensions-Kristall",
		Rarity = "Epic",
		RarityLabel = "EPISCH",
		RarityColor = Color3.fromRGB(155, 89, 182),
		Icon = "🔮",
		Description = "Ein finster schimmerndes Kristallfragment aus den Tiefen des Dimensions-Risses. Enthält instabile magische Essenz.",
		StatsText = "Seltener Kristall",
		DetailedStats = "Magisches Reliktmaterial",
		UsageTip = "Wird für hochstufige Sockel-Verstärkungen und mystische Fallen benötigt.",
	},
}

-- Konfiguration für Shop-Verteidigung und Sockel-Upgrades
local ShopConfig = {
	Defenses = {
		Spikes = {
			Id = "Spikes",
			DisplayName = "Stachelfalle",
			Category = "Defense",
			Icon = "🩸",
			Description = "Versteckte Bodenspikes, die Dieben beim Betreten 25 Schaden zufügen und sie temporär verlangsamen.",
			StatsText = "25 Schaden + Slowdown",
			CostGold = 150,
			CostMaterials = { IronOre = 5 },
			MaxCount = 4,
		} :: DefenseShopItem,
		Guards = {
			Id = "Guards",
			DisplayName = "Wächter-Minion",
			Category = "Defense",
			Icon = "🛡️",
			Description = "Ein treuer Steinkoloss mit Holz-Axt, der auf deinem Plot patrouilliert und Einbrecher sofort attackiert.",
			StatsText = "15 Schaden / Hieb  •  100 HP",
			CostGold = 500,
			CostMaterials = { IronOre = 12 },
			MaxCount = 2,
		} :: DefenseShopItem,
	},

	SlotUnlocks = {
		[2] = {
			SlotIndex = 2,
			CostGold = 500,
			DisplayName = "Sockel 2 Freischaltung",
			Description = "Ermöglicht das Aufstellen eines zweiten Seelenkerns zur Verdopplung deines passiven Einkommens.",
		} :: SlotUnlockInfo,
		[3] = {
			SlotIndex = 3,
			CostGold = 2000,
			DisplayName = "Sockel 3 Freischaltung",
			Description = "Ermöglicht das Aufstellen eines dritten Seelenkerns für maximale Tycoon-Goldproduktion.",
		} :: SlotUnlockInfo,
	},

	WeaponOrder = { "RustySword", "IronSword", "AmethystBlade", "VoidScythe" },
}

-- Shop-Konfiguration als Property anhängen für Rückwärtskompatibilität
(ItemConfig :: any).Shop = table.freeze(ShopConfig)

return table.freeze(ItemConfig)
