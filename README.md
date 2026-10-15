# ⚔️ Realm Raiders & Relics

> **Hybrid Tycoon / Action-RPG / Steal & Defend für Roblox**  
> Inspiriert vom Boss-Sammeltrieb aus *Advent of Ascension* kombiniert mit einer hochspannenden *Steal-&-Defend*-Tycoon-Dynamik.

---

## ⚡ Welt im Bau-Modus (Build Mode) sichtbar machen

> **Warum sieht man im Bau-Modus fast nichts?**
> Die komplette Welt – Plots, schwebende Insel, Säuresee, Hängebrücke, Portale, Boss-Arena, Schmiede – wird von **Server-Skripten zur Laufzeit erzeugt** und steckt nicht als dauerhafte Objekte im Place-File. Im **Bau-Modus von Roblox Studio laufen aber keine Skripte**, deshalb ist die Workspace dort leer (man sieht nur Himmel und Void). Erst beim Spielen (Play-Modus) wird alles aufgebaut.

### 🧭 Schritt 1: Prüfen, ob der neue Code in Studio angekommen ist

1. Im **Rojo-Plugin** auf *Connect / Sync* klicken.
2. Im Explorer nachsehen: **`ServerScriptService → Server → Studio → WorldBuilder`** muss existieren.
   *Fehlt dieser Ordner, ist der Sync nicht durchgelaufen – dann siehe „Plan B" weiter unten.*
3. Beim Spielen steht im **Output** (Ansicht → Ausgabe) die Zeile `[Init] Welt-Check: ...` (bzw. beim Bauen `[WorldBuilder] ... Version 2026-10-15-b`). **Beide Versionen müssen identisch sein** – dann ist der Sync vollständig. Fehlt die Zeile `[Init] Welt-Check`, ist der Server-Start hängen geblieben (dann greift nach 20s der Watchdog und schreibt eine Warnung).

### 🌌 Schritt 2: Komplette Welt im Bau-Modus aufbauen

In Roblox Studio die **Befehlszeile (Command Bar)** öffnen (*Ansicht → Befehlszeile*), einfügen und **Enter** drücken:

```lua
require(game.ServerScriptService.Server.Studio.WorldBuilder).BuildAll()
```

Danach **Strg + S**. Der Output zeigt dann z. B.:
`[WorldBuilder] Welt-Check: OK Environment=482 Parts | OK Plots=311 Parts | OK Arena_WaldRuinen=95 Parts | ...`

### 🖱️ Ohne Tippen: Studio-Plugin mit Buttons (empfohlen)

In `%LOCALAPPDATA%\Roblox\Plugins` liegt die Datei `RealmWeltBuilder.rbxmx` (gebaut aus `plugin/` + `plugin.project.json`). Nach einem **Neustart von Roblox Studio** erscheint oben in der Werkzeugleiste der Reiter **„Realm Welt (Bau-Modus)"** mit diesen Buttons:

`[Welt bauen]` `[Umgebung]` `[Plots]` `[Portale]` `[Boss-Arena]` `[Welt löschen]` `[Diagnose]`

Plugin nach Änderungen an `plugin/` neu bauen:
```bash
rojo build plugin.project.json -o "%LOCALAPPDATA%\Roblox\Plugins\RealmWeltBuilder.rbxmx"
```

### 🧩 Einzelne Bereiche gezielt neu aufbauen / nur prüfen
| Befehl (nach `local WB = require(game.ServerScriptService.Server.Studio.WorldBuilder)`) | Ergebnis |
| :--- | :--- |
| `WB.BuildAll()` | Komplette Welt von Grund auf (empfohlen) |
| `WB.BuildPlots()` | 6 Plots mit 3D-Dungeon-Sockeln, Stachelfallen & Wächter-Minions |
| `WB.BuildEnvironment()` | Schwebende Insel mit Allee, Säuresee, Hängebrücke, Sky-Beacons, Fackeln & Waffen-Schmiede |
| `WB.BuildPortals()` | Dimensions-Portale (Oberwelt ↔ Wald-Ruinen) mit Amethyst-Kristall |
| `WB.BuildBossArena()` | Boss-Arena mit Ruinenmauern, Waldbäumen & Amethyst-Schrein |
| `WB.Clear()` | Entfernt die komplette generierte Welt wieder aus der Workspace |
| `WB.Diagnose()` | Nur prüfen: Welche Version läuft? Welche Welt-Teile existieren? |

### 🆘 Plan B – falls `WorldBuilder` nicht auftaucht (funktioniert mit jedem Code-Stand)

Dieser Befehl nutzt ausschließlich die bestehenden Service-Module und baut die Welt damit ebenfalls auf (**Voraussetzung:** die Service-Skripte sind auf dem neuen Stand, also im Rojo-Plugin einmal *Connect/Sync* klicken):

```lua
local S = game.ServerScriptService.Server.Services
for _, n in ipairs({"Plots", "Environment", "ToxicAcidLake", "Arena_WaldRuinen", "Portal_WaldRuinen", "Portal_Oberwelt"}) do
	local i = workspace:FindFirstChild(n)
	if i then i:Destroy() end
end
local function runInit(m) local ok, err = pcall(function() m.Init() end) if not ok then warn("[PlanB] " .. tostring(err)) end end
runInit(require(S.BossService))
runInit(require(S.EnvironmentService))
runInit(require(S.PortalService))
runInit(require(S.PlotService))
print("[PlanB] Welt aufgebaut - jetzt Strg+S drücken")
```

### 🔁 Workflow: Muss ich den Aufbau-Befehl jedes Mal eingeben?

* **Einmal bauen + Strg+S** → die Welt liegt dauerhaft im Place-File und ist bei jedem Öffnen im Bau-Modus da. Für normales Arbeiten brauchst du also nichts weiter.
* **Beim Spielen (Play)** baut der Server die Welt sowieso bei jedem Start neu aus dem Code auf → dort ist **nie** ein Befehl nötig.
* **Nur wenn du die Welt im Code änderst** (Positionen, neue Teile, Farben in den Services) und das Ergebnis schon im **Bau-Modus** sehen willst: Button **„Welt bauen"** (bzw. `WB.BuildAll()`). Häufig reicht auch nur der geänderte Bereich, z. B. **„Plots"** oder **„Umgebung"** – das ist schneller und lässt den Rest unangetastet.
* ⚠️ **Wichtig:** Objekte, die du im Bau-Modus INNERHALB von `Workspace.Plots`, `Workspace.Environment`, `Workspace.Portal_*` oder `Workspace.Arena_WaldRuinen` verschiebst/dekorierst, werden beim Spielen bzw. beim nächsten Aufbau überschrieben. Eigene Bauten deshalb **außerhalb** dieser Ordner anlegen (z. B. in einem eigenen Ordner `Workspace.MeinBau`).

> **Tipp 1:** Ein Fehler in **einem** Service verhindert nicht mehr die ganze Welt: Im Output steht dann `[Init] FEHLER in XYZ: ...` und die übrigen Teile werden trotzdem gebaut. Diese Zeile (plus die `[WorldBuilder]`-Zeilen) bitte beim Melden eines Problems mitschicken.
>
> **Tipp 2:** Die Befehle funktionieren **nur im Bau-Modus** (nicht während des Spielens) – außerhalb wird abgebrochen, um die laufende Welt nicht zu zerstören.
>
> **Tipp 3:** Beim Spielen bauen die Services die Welt wieder selbst auf und räumen vorher auf – es entstehen keine Duplikate, egal wie oft du den Builder benutzt.

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
    │   ├── Init.server.luau  -- Server-Einstiegspunkt & Framework-Bootstrap
    │   ├── Services/         -- PlotService, EnvironmentService, BossService, RaidService, DefenseService, PortalService
    │   └── Studio/
    │       └── WorldBuilder.luau -- Baut die komplette Welt im Bau-Modus von Roblox Studio
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
   * Der Standard-Baseplate wird von der Spielwelt automatisch entfernt (die Insel ist eine schwebende Insel über dem Säuresee).
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
- [x] **Phase 2: Audio & Game Feel (Abgeschlossen):**
  - [x] Sound-Effekte (Klingen, Treffer, Münzen, Sirene, Boss-Roar)
  - [x] Floating Damage Numbers (`-25`, `CRIT!`)
  - [x] Floating Coin-Pickup Popups
- [x] **Phase 3: Mobile & Touch-Support (Abgeschlossen):**
  - [x] Zentraler `MobileControlsController` ("RealmRaidersMobileGui", DisplayOrder 15) – wird nur bei `UserInputService.TouchEnabled` erstellt
  - [x] Mobile Action Cluster im Daumen-Bogen: ⚔️ Angriff (68x68), ⚡ Combat-Dash (58x58), 🏃 Sprint-Toggle (52x52)
  - [x] Check-UI Standard für alle Touch-Buttons (3D-Bevel, 3.0px schwarzer UIStroke, UIGradient, Damier, GothamBlack & HD-Icons)
  - [x] UIScale-Engine (Baseline 400px, 0.85 – 1.25) + dynamischer Sprungkopf-Sicherheitsabstand (keine Überlappung mit Roblox-Sprungknopf/Chat)
  - [x] Dash-Cooldown-Visualisierung (abklingende Dunkelmaske + `1.2s`-Countdown)
  - [x] Sprint-Toggle mit aktivem Limettengrün-Puls, Walk-of-Shame-Sperre inkl. Schloss-Symbol
  - [x] Bugfix: Kamera-Wischen löst keinen Schwertschlag mehr aus (`UserInputType.Touch` aus `CombatController.onInputBegan` entfernt)
  - [x] Öffentliche APIs: `CombatController.TriggerAttack/TriggerDash/GetDashCooldownProgress`, `MovementController.ToggleSprint/ObserveSprintState`
  - [x] Mobile-optimierte ProximityPrompts (`ClickablePrompt = true`, großes Daumen-Ziel mit Halte-Fortschrittsbalken)
  - [x] HUD-Touchflächen: Mindestgröße 44x44px für Inventar-/Menü-Buttons (Desktop-Layout unverändert)
- [ ] **Phase 4 (Content Expansion):**
  - [ ] 2. Dimension (*Nether-Kluft / Magma-Ruinen*) mit Tier 2 Magma-Koloss
  - [ ] Neue Materialien (*Obsidian*, *Feuer-Essenz*) & Tier 2 Seelenkern
- [ ] **Phase 5 (Monetarisierung & Social):**
  - [ ] Gamepasses (2x Gold, Extra Sockel, Base Shield)
  - [ ] Globale Bestenlisten auf der Allee & Badges