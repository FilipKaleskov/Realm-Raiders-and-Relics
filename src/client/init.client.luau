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

local ShopControllerModule = Controllers:WaitForChild("ShopController") :: ModuleScript
local ShopController = require(ShopControllerModule)

-- Client-Controller starten
HUDController.Init()
CombatController.Init()
MovementController.Init()
PlotSelectionController.Init()
ShopController.Init()

print("[Client] Realm Raiders Client (HUD, Combat, Movement, PlotSelection & Shop) erfolgreich gebootet.")
