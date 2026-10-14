# ⚔️ Realm Raiders & Relics

> **Hybrid Tycoon / Action-RPG / Steal & Defend für Roblox**  
> Inspiriert vom Boss-Sammeltrieb aus *Advent of Ascension* kombiniert mit einer hochspannenden *Steal-&-Defend*-Tycoon-Dynamik.

---

## ⚡ Roblox Studio Quick Commands (Befehlszeile)

Füge diese Befehle unten in die **Befehlszeile (Command Bar)** in Roblox Studio ein und drücke **Enter**, um die Welt direkt im **gestoppten Zustand (Edit-Modus)** aufzubauen:

### 🌌 Komplette Welt mit allen Features generieren (Hängebrücke + Plots mit **Schmelz-Altar**, **Stachelfallen**, **Wächter-Minions** + Portale + **Golem Facelift** + **Waldbäume** + **Sky-Beacons**):
```lua
pcall(function() workspace.Baseplate:Destroy() end); pcall(function() workspace.Environment:Destroy() end); pcall(function() workspace.Plots:Destroy() end); require(game.ServerScriptService.Server.Services.EnvironmentService).Init(); require(game.ServerScriptService.Server.Services.PlotService).Init(); require(game.ServerScriptService.Server.Services.PortalService).Init(); require(game.ServerScriptService.Server.Services.BossService).Init(); require(game.ServerScriptService.Server.Services.DefenseService).Init()
```

### 🏰 Nur Plots & Verteidigungsanlagen aufbauen (**Schmelz-Altar**, **Stachelfallen**, **Wächter-Minions** & **Trophäenstatuen**):
```lua
pcall(function() workspace.Plots:Destroy() end); require(game.ServerScriptService.Server.Services.PlotService).Init(); require(game.ServerScriptService.Server.Services.DefenseService).Init()
```

### 🌉 Nur Video-Umgebung aufbauen (Säuresee, Hängebrücke, **rote Sky-Beacons**, Fackeln):
```lua
pcall(function() workspace.Baseplate:Destroy() end); require(game.ServerScriptService.Server.Services.EnvironmentService).Init()
```

### 👹 Nur Boss-Arena aufbauen (Golem mit **gelben Augen**, **Moos-Schultern**, **Felszähnen** + **Waldbäume** + **Amethyst-Schrein**):
```lua
require(game.ServerScriptService.Server.Services.BossService).Init()
```

> **Tipp:** Drücke nach dem Ausführen einfach **Strg + S**, um die generierten 3D-Objekte dauerhaft in deiner Roblox-Studio-Welt zu speichern.

### 🎮 Gameplay- & Kampffunktionen im Spiel:
| Taste / Interaktion | Aktion |
| :--- | :--- |
| **Linksklick / F** | Schwertangriff (trifft Bosse, feindliche Spieler & **feindliche Wächter-Minions**) |
| **Q** | Combat-Dash mit **blauem Cyan-Flammen-Trail** (weicht Angriffen & Fallen aus) |
| **Shift** | Sprinten (erzeugt weiße Footstep-Staubpartikel, bei Raubzug deaktiviert) |
| **[E] am Schmelz-Altar** | Gestohlene Seelenkerne **einschmelzen** für massiven **Sofort-Gold-Bonus** |
| **B / [E] an der Schmiede** | **Waffen-Schmiede & Shop** öffnen (Schwerter schmieden, Sockel & Fallen kaufen) |
| **[E] am fremden Sockel** | Seelenkern stehlen (3.5s Raub-Interaktion, löst Alarm aus) |
| **[E] am gesperrten Sockel** | Sockel 2 (500 Gold) oder Sockel 3 (2.000 Gold) freischalten |
| **🛡️ Wächter-Minion** | Greift fremde Eindringlinge automatisch mit Steinaxt an (15 Schaden) |
| **🩸 Stachelfallen** | Schnellen bei fremden Dieben hoch (25 Schaden + temporärer Slowdown) |
| *Automatisch* | **🚨 BASE INTRUDED!** rotes Comic-Banner beim Opfer bei Raubzügen |
| *Automatisch* | **+Gold Celebration-Popup** beim Besiegen des Bosses |

---

## 📖 Übersicht

In **Realm Raiders & Relics** bereisen Spieler fremde Dimensionen, bezwingen anspruchsvolle Bosse und platzieren deren erbeutete Seelenkerne als majestätische Statuen auf ihrer Basis. Diese Statuen generieren passiv Einkommen – doch der Reichtum lockt diebische Mitspieler an!

### Der Core Game Loop
1. **Explore & Fight (PvE):** Reise durch Dimensions-Portale, weiche telegrafierten Boss-Angriffen aus und erbeute seltene Seelenkerne sowie Crafting-Erze.
2. **Build & Earn (Tycoon):** Errichte auf deinem Grundstück Sockel-Statuen aus den Seelenkernen. Je seltener der Boss, desto höher der passive Gold-Ertrag (*CPS - Cash Per Second*).
3. **Defend & Raid (PvP):** Schütze deine Basis mit Stachelfallen und Wächter-Minions. Brich in fremde Basen ein, entziehe Seelenkerne und trage sie zu Fuß über die Oberwelt zur eigenen Basis (*Walk of Shame*).
4. **Upgrade & Craft (Progression):** Investiere dein Gold in mächtigere Waffen, Sockel-Multiplikatoren und schalte neue, gefährlichere Dimensionen frei.

---

## 🛠️ Technische Architektur & Prinzipien

Das Projekt wird nach modernen Luau- und Roblox-Entwicklungsstandards gepflegt:

* **Striktes Luau (`--!strict`):** Vollständige statische Typisierung für maximale Zuverlässigkeit und Autovervollständigung.
* **Strikte Server-Autorität (Anti-Exploit):**
  * Sämtliche Schadensberechnungen, Goldtransaktionen, Inventarverwaltung und Seelendiebstähle laufen ausschließlich auf dem Server.
  * Server-validierte Treffererkennung (Distanz-/Magnitude- und Blickwinkel-Checks).
  * Server-erzwungener Trägerstatus (`WalkSpeed = 10`, Deaktivierung von Sprint & Teleportation).
  * Gesicherter Network-Ownership (`SetNetworkOwner(nil)`) für fallengelassene/getragene Relikte.
* **Moderne Task-Library:** Konsequenter Einsatz von `task.wait()`, `task.spawn()`, `task.delay()` statt veralteter globaler Funktionen.
* **Rojo Sync:** Vollständige Entkopplung von Code und Roblox Studio für Versionskontrolle über Git.

---

## 📁 Projektstruktur & Rojo-Mapping

Das Projekt nutzt [Rojo](https://rojo.space/) zur Synchronisation:

```text
Realm-Raiders-and-Relics/
├── default.project.json      -- Rojo-Konfigurationsdatei
├── roblox/                   -- Game Design Documents & Konzeptpapiere
└── src/
    ├── shared/               --> ReplicatedStorage.Shared
    │   └── Data/
    │       └── PlayerDataTemplate.luau -- Typisiertes Datenmodell (ProfileService-kompatibel)
    ├── server/               --> ServerScriptService.Server
    │   └── Init.server.luau  -- Server-Einstiegspunkt & Framework-Bootstrap
    └── client/               --> StarterPlayer.StarterPlayerScripts.Client
        └── init.client.luau  -- Client-Einstiegspunkt
```

---

## 🚀 Setup & Lokale Entwicklung

### Voraussetzungen
* [Roblox Studio](https://www.roblox.com/create)
* [Rojo CLI](https://rojo.space/) (Version 7.x) oder die [Rojo VS Code Extension](https://marketplace.visualstudio.com/items?itemName=evaera.vscode-rojo)
* [Visual Studio Code](https://code.visualstudio.com/)

### Erste Schritte

1. **Repository klonen:**
   ```bash
   git clone https://github.com/FilipKaleskov/Realm-Raiders-and-Relics.git
   cd Realm-Raiders-and-Relics
   ```

2. **Rojo-Server starten:**
   ```bash
   rojo serve
   ```

3. **In Roblox Studio verbinden:**
   * Öffne Roblox Studio und erstelle einen leeren Baseplate-Ort (oder baue das Place-File mit `rojo build -o "RealmRaiders.rbxlx"`).
   * Öffne das **Rojo Plugin** in Studio und klicke auf **Connect** (Standardport: `34872`).



## 🗺️ Roadmap & Meilensteine

- [x] **Setup & Architektur:** Git-Repository, Rojo-Konfiguration und typisiertes `PlayerDataTemplate`
- [x] **MVP Core Loop (Abgeschlossen):**
  - [x] Tycoon-Plot-System & automatische Zuweisung
  - [x] Sockel-Platzierung & passive Goldgenerierung (CPS)
  - [x] Erste Dimension (*Wald/Ruinen*) mit Forest Golem Boss
  - [x] Telegrafierte Angriffe (rote Bodenindikatoren) & Server-validiertes Kampfsystem
  - [x] Steal-&-Defend-Interaktion, Sky-Beacon & Alarmsystem
  - [x] Schmelz-Altar für Sofort-Gold-Bonus
  - [x] Basis-Verteidigung (Stachelfallen & Minion-Wächter mit Steinaxt)
  - [x] Check-UI Design System HUD & Inventar-Menü
- [x] **Phase 1: Economy & Shop-Loop (Abgeschlossen):**
  - [x] Waffen-Schmiede & Shop (Eisenschwert, Amethyst-Klinge, Leeren-Sense)
  - [x] Basis-Erweiterung (Sockel 2 & 3 für Gold im Shop & direkt am Sockel freischalten)
  - [x] Verteidigungs-Shop (Weitere Stachelfallen & Minions kaufen)
  - [x] In-World 3D-Schmiede auf der zentralen Allee (Amboss, glühendes Eisen, Glutofen)
  - [x] Dynamische Waffen-Klingenschwünge (Farben & Cooldowns nach Waffe)
- [ ] **Nächster Fokus: Phase 2 (Audio & Game Feel):**
  - [ ] Sound-Effekte (Klingen, Treffer, Münzen, Sirene, Boss-Roar)
  - [ ] Floating Damage Numbers (`-25`, `CRIT!`)
  - [ ] Floating Coin-Pickup Popups
- [ ] **Phase 3 (Mobile Support):**
  - [ ] On-Screen Touch Buttons (Angriff, Dash, Sprint)
  - [ ] Mobile-optimierte Prompts & Interaktionen
- [ ] **Phase 4 (Content Expansion):**
  - [ ] 2. Dimension (*Nether-Kluft / Magma-Ruinen*) mit Tier 2 Magma-Koloss
  - [ ] Neue Materialien (*Obsidian*, *Feuer-Essenz*) & Tier 2 Seelenkern
- [ ] **Phase 5 (Monetarisierung & Social):**
  - [ ] Gamepasses (2x Gold, Extra Sockel, Base Shield)
  - [ ] Globale Bestenlisten auf der Allee & Badges