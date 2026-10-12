# 3D Assets & Model Pipeline

Dieses Verzeichnis verwaltet alle 3D-Assets für **Realm Raiders & Relics**.

## Verzeichnisstruktur

- **`blender/`**: 
  - Enthält alle `.blend`-Quelldateien (3D-Meshes, Modifier, Rigs, Textur-Setups).
  - Arbeitsdateien verbleiben hier.

- **`exports/`**: 
  - Enthält exportierte Zwischenformate wie `.fbx` und `.obj` für den Import in Roblox Studio.
  - Achte beim Exportieren auf die korrekte Skalierung (Roblox-Einheiten: 1 Stud ≈ 0.28m, Skalierung 0.01 oder 1.0 je nach Einheitensystem).

## Workflow nach Roblox Studio

1. **Modellieren & Texturieren:** In Blender arbeiten (`assets/blender/*.blend`).
2. **Export:** Als `.fbx` nach `assets/exports/` exportieren.
3. **Studio-Import & Setup:** In Roblox Studio über den Asset Manager importieren, Materialien, Kollisionen (`CanCollide`), Anker (`Anchored`) und Effekte einrichten.
4. **Finales Ingame-Modell:** Fertig aufbereitete Modelle als `.rbxm` (Roblox Model) nach `src/shared/Assets/Models/` speichern.
   - Rojo synchronisiert `src/shared` automatisch nach `ReplicatedStorage.Shared.Assets.Models`.
   - Sowohl Server als auch Client können dort zentral auf die Modelle zugreifen.
