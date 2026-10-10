# Game Design Document (GDD): Realm Raiders & Relics (Arbeitstitel)

## 1. Executive Summary
* **Plattform:** Roblox (PC, Mobile, Konsole)
* **Genre:** Hybrid-Tycoon / Action-RPG / Steal & Defend
* **Zielgruppe:** 9–17 Jahre (Fokus auf Sammeltrieb, Progression, virale PvP-Momente)
* **Engine & Sprache:** Roblox Studio / Luau
* **Kern-Pitch:** *Advent of Ascension* trifft *Steal-a-Brainrot*. Spieler bereisen fremde Dimensionen, besiegen fordernde Bosse, platzieren deren Seelen als gewinnbringende Statuen in ihrer Basis und verteidigen diese vor diebischen Mitspielern.

---

## 2. Core Game Loop
1. **Explore & Fight (PvE):** Durch Dimensions-Portale reisen, Mobs/Bosse bekämpfen, Boss-Seelenkerne und Crafting-Materialien erbeuten.
2. **Build & Earn (Tycoon):** In der eigenen Basis Boss-Statuen auf Sockeln errichten. Diese generieren passiv Währung (*Seelen-Essenz / Gold pro Sekunde*).
3. **Defend & Raid (PvP):** Die eigene Basis mit Fallen und Wächtern sichern. In fremde Basen einbrechen, Seelenkerne entwenden und zu Fuß über die Oberwelt zur eigenen Basis flüchten.
4. **Upgrade & Craft (Progression):** Erwirtschaftetes Gold und gefundene Erze nutzen, um stärkere Waffen zu schmieden, Basisschutz zu erweitern und höhere Dimensionen freizuschalten.

---

## 3. Gameplay-Systeme & Mechaniken

### 3.1 Dimensions- & Boss-System (PvE)
* **Portal-Hub:** Ein zentraler Bereich in der Oberwelt, über den Spieler Instanzen oder offene Dimensions-Zonen betreten.
* **Boss-Mechanik:** Keine simplen Stat-Checks. Bosse besitzen telegrafierte Angriffe (rote Indikator-Flächen am Boden, Ansturm-Phasen, Geschoss-Salven), die Ausweichen und Timing erfordern.
* **Loot-Distribution:** 
  * Garantierter Basis-Loot (Erze, Gold).
  * Wahrscheinlichkeitsbasierter Drop für den **Seelenkern** (z. B. 10 % bis 1 % je nach Seltenheit).

### 3.2 Das Statuen- & Tycoon-System
* **Plot-System:** Jeder Spieler beansprucht automatisch ein Grundstück auf der Haupt-Map.
* **Statuen-Sockel:** Feste Plätze auf dem Grundstück, auf denen Seelenkerne platziert werden.
* **Passive Einkommensgenerierung (CPS):**
  * Tier 1 Boss-Statue: 5 Gold / Sekunde
  * Tier 2 Boss-Statue: 25 Gold / Sekunde
  * Tier 3 (Legendary) Boss-Statue: 150 Gold / Sekunde + visueller Partikeleffekt
* **Upgrades:** Investition von Gold in Multiplikatoren (z. B. Sockel-Verstärker).

### 3.3 Steal-&-Defend-Mechanik (PvP)
* **Der Einbruch:** Spieler können ungesicherte Plots betreten und an fremden Statuen interagieren (Halte-Interaktion: 3–5 Sekunden), um den Seelenkern herauszubrechen.
* **Der "Walk of Shame" (Flucht-Restriktion):**
  * Wer einen Kern trägt, kann **nicht sprinten**, **keine Portale/Teleporter nutzen** und **keine Fahrzeuge besteigen**.
  * Ein globaler Alarm oder ein sichtbares Leuchtfeuer markiert den Träger auf der Minimap.
  * Ziel: Den Kern lebend zum eigenen Altar tragen, um ihn dauerhaft zu übernehmen oder gegen Sofort-Gold einzuschmelzen.
* **Verteidigungsanlagen (Defense):**
  * **Fallen:** Bodenspikes (verlangsamen), Laser-Schranken (Schaden), Sprungfedern (werfen Diebe zurück).
  * **Minion-Wachen:** Platzierbare NPCs (Skelette, Golems), die automatisiert Angreifer attackieren.

---

## 4. Wirtschaft & Monetarisierung

### 4.1 Ingame-Währungen
* **Gold / Seelen-Essenz:** Erfarmbar durch Statuen, Quests und Boss-Kills. Dient für Basis-Upgrades, Fallen und Standard-Crafting.
* **Gems / Rubine (Premium):** Kaufbar mit Robux oder als seltene Belohnung für Meilensteine.

### 4.2 Monetarisierungs-Katalog (Robux)
| Typ | Produkt | Funktion |
| :--- | :--- | :--- |
| **Gamepass** | 2x Seelen-Ertrag | Verdoppelt das passive Goldeinkommen aller Statuen dauerhaft. |
| **Gamepass** | VIP-Dungeon-Pass | Exklusiver Zugriff auf kosmetische Boss-Varianten und VIP-Lounge. |
| **Gamepass** | Extra Sockelplatz | Erlaubt das Aufstellen von 2 zusätzlichen Statuen auf dem Plot. |
| **Developer Product** | Base Shield (15 Min.) | Schützt die eigene Basis temporär vor Plünderungen. |
| **Developer Product** | Luck Boost (30 Min.) | Verdoppelt die Drop-Chance für seltene Seelenkerne bei Bossen. |

> **Compliance-Hinweis (Roblox Policy):** Werden Kisten/Waffenboxen gegen Robux angeboten, muss zwingend `PolicyService:GetPolicyInfoForPlayerAsync` implementiert sein, um bezahlte Zufallsobjekte für regulierte Länder zu deaktivieren. Exakte Prozentchancen müssen im UI deklariert werden.

---

## 5. Technische Architektur & Datenmodell

### 5.1 Projekt-Setup (Empfohlener Stack)
* **Framework:** Knit oder eigenständiges Modul-Skript-System (Client-Server-Trennung).
* **Sync-Tool:** Rojo für externen Code-Workflow via VS Code & Git.
* **Datenverwaltung:** ProfileService für ausfallsichere `DataStore2`-Speicherung.

### 5.2 Daten-Schema (ProfileService Template)
```lua
local PlayerDataTemplate = {
    Gold = 0,
    Gems = 0,
    Inventory = {
        Weapons = {"RustySword"},
        Materials = {
            IronOre = 0, 
            VoidCrystal = 0
        },
        Cores = {} -- Unplatzierte Seelenkerne
    },
    BaseData = {
        Slots = {
            [1] = {CoreId = "ForestGolemCore", Level = 1},
            [2] = nil,
            [3] = nil
        },
        Defenses = {
            Spikes = 2,
            Guards = 1
        }
    },
    UnlockedDimensions = {"Dimension_Forest"}
}

```

### 5.3 Sicherheitsregeln & Anti-Exploit
* **Strikte Server-Autorität:** Sämtliche Schadensberechnungen, Gold-Transaktionen, Statuen-Platzierungen und Loot-Vergaben laufen ausschließlich auf dem Server. Der Client sendet nur Eingabe-Absichten (Intent), keine Ergebnisdaten.
* **Hitbox-Validierung:** Der Server überprüft bei jedem Treffer Distanz und Blickwinkel zwischen Angreifer und Ziel (`(Char1.Position - Char2.Position).Magnitude <= MaxReach`), um Range- und Kill-Aura-Exploits zu verhindern.
* **Flucht-Status & Speed-Checks:** Der Trägerstatus eines Seelenkerns ist ein Server-Attribut (`Player:SetAttribute("CarryingCore", true)`). Der Server erzwingt serverseitig die Gehgeschwindigkeit (`Humanoid.WalkSpeed = 10`) und gleicht die Bewegung über Delta-Positionen ab, um Teleport- und Speed-Hacks sofort zu stoppen.
* **Network Ownership:** Wenn ein Kern physisch getragen oder fallen gelassen wird, verbleibt der `NetworkOwner` auf dem Server (`Part:SetNetworkOwner(nil)`), damit Cheater das Objekt nicht ins Nichts schleudern können.

---

## 6. MVP-Phasenplan (Milestones & Roadmap)

### Phase 1: Minimal Viable Product (Wochen 1–4)
* **Woche 1:** Setup von Rojo, Git und Knit/ProfileService. Basis-Plot-Zuweisung und einfacher Speicherkreislauf.
* **Woche 2:** Erste Dimension (Wald/Ruinen) mit 2 Bossen. Implementierung von Telegraphen-Angriffen und einfachem Nahkampf-System mit Trefferfeedback.
* **Woche 3:** Statuen-Sockel auf dem Tycoon-Plot mit passivem Einkommen (CPS) und Upgrade-Knöpfen.
* **Woche 4:** Steal-&-Defend-Mechanik (Kern stehlen, Walk of Shame, Sicherung am eigenen Altar). Interner Playtest des Core Loops.

### Phase 2: Content, Crafting & Monetarisierung (Wochen 5–7)
* **Woche 5:** 2 weitere Dimensionen (Unterwelt/Feuer und Kristall-Leere) mit jeweils 2 neuen Bossen und einzigartigen Statuen.
* **Woche 6:** Erz-Spawns in den Dimensionen + 1-Klick-Schmiede in der Basis zur Waffenherstellung.
* **Woche 7:** Verteidigungsanlagen (Spikes, Laser, 1 Minion-Typ) und Integration der Gamepässe (2x CPS, Basis-Schild) inklusive `PolicyService`-Prüfung.

### Phase 3: Endgame, Retention & Social (Wochen 8+)
* **Woche 8:** Zentrales PvP-Kolosseum in der Oberwelt für Duelle ohne Verlust von Basiskernen.
* **Woche 9:** Globale Leaderboards (Meiste Bosssiege, Höchster Basiswert) und automatisierte Chat-Announcements für 0,1%-Drops.
* **Woche 10:** Social-Showroom / Trophäen-Feature (Passanten zahlen optional passive Eintrittsgebühr bei hochrangigen Basen).

---

## 7. Risiken & Mitigation

| Risiko | Wahrscheinlichkeit | Auswirkung | Gegenmaßnahme |
| :--- | :--- | :--- | :--- |
| **Server-Lags bei vielen Minions/Bossen** | Hoch | Kritisch | Aggressives Culling, Server-KI-Ticks drosseln (`task.wait(0.2)` für Pfadfindung) und Effekte rein clientseitig rendern. |
| **Griefing durch übermächtige Diebe** | Hoch | Hoch | Noob-Schutz (Safe-Zone für neue Spieler bis Stufe 5) und Cooldown-Timer nach einem erfolgreichen Raub. |
| **Content-Trockenheit nach Release** | Mittel | Hoch | Modulare Tabellenarchitektur: Neue Bosse und Waffen müssen über Konfigurations-Dateien ohne Code-Umbau in wenigen Stunden hinzufügbar sein. |
