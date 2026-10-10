--!strict

local Controllers = script:WaitForChild("Controllers")

local HUDControllerModule = Controllers:WaitForChild("HUDController") :: ModuleScript
local HUDController = require(HUDControllerModule)

local CombatControllerModule = Controllers:WaitForChild("CombatController") :: ModuleScript
local CombatController = require(CombatControllerModule)

-- Client-Controller starten
HUDController.Init()
CombatController.Init()

print("[Client] Realm Raiders Client (HUD & Combat) erfolgreich gebootet.")
