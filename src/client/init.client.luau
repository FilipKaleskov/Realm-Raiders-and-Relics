--!strict

local Controllers = script:WaitForChild("Controllers")

local HUDControllerModule = Controllers:WaitForChild("HUDController") :: ModuleScript
local HUDController = require(HUDControllerModule)

local CombatControllerModule = Controllers:WaitForChild("CombatController") :: ModuleScript
local CombatController = require(CombatControllerModule)

local MovementControllerModule = Controllers:WaitForChild("MovementController") :: ModuleScript
local MovementController = require(MovementControllerModule)

local PlotSelectionControllerModule = Controllers:WaitForChild("PlotSelectionController") :: ModuleScript
local PlotSelectionController = require(PlotSelectionControllerModule)

-- Client-Controller starten
HUDController.Init()
CombatController.Init()
MovementController.Init()
PlotSelectionController.Init()

print("[Client] Realm Raiders Client (HUD, Combat, Movement & PlotSelection) erfolgreich gebootet.")
