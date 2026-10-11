# Roblox Luau Game Development Guidelines

## 1. Code-Standards & Syntax
- Schreibe immer strikt typisiertes Luau mit `--!strict` ganz oben in jeder Datei.
- Verwende ausnahmslos die moderne `task`-Bibliothek (`task.wait`, `task.spawn`, `task.delay`, `task.defer`). Veraltete Methoden wie `wait()`, `spawn()` oder `delay()` sind strikt verboten.
- Nutze `Vector3.zero` und `CFrame.identity` statt redundanter Neukonstruktionen.
- Nutze `OverlapParams` statt veralteter `FindPartsInRegion3`.

## 2. Server-Autorität & Sicherheit
- Der Client ist niemals vertrauenswürdig. Alle Kernberechnungen (Schaden, Goldgutschriften, Inventar, Freischaltungen) laufen auf dem Server.
- Clients senden ausschließlich Absichten (Intents) über RemoteEvents/RemoteFunctions.
- Der Server validiert Parameter strikt (Reichweite via `(pos1 - pos2).Magnitude`, Cooldowns, Besitzprüfungen).
- Setze `NetworkOwnership` für bewegliche Gameplay-Objekte (wie fallengelassene Relikte) serverseitig auf `nil` (`Part:SetNetworkOwner(nil)`).

## 3. Architektur & Dateistruktur
- Entkopplung nach Server, Client und Shared:
  - `src/server`: Nur serverseitige Module und Service-Skripte (`.server.luau` oder Modulskripte).
  - `src/client`: UI-Controller, Animationen, Partikel, Sounds (`.client.luau` oder Modulskripte).
  - `src/shared`: Datentemplates, Boss-Konfigurationen, Utilities (`.luau`).
- Niemals `.rbxl` oder `.rbxlx` Binär-/XML-Dateien editieren. Alle Änderungen erfolgen über `.luau`-Dateien im `src/`-Verzeichnis.