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
		UsageTip = "Automatisch aktiv. Schlage auf Feinde mit Linksklick oder Taste [F].",
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

return table.freeze(ItemConfig)
