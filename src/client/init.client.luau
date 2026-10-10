--!strict

local Controllers = script:WaitForChild("Controllers")
local HUDControllerModule = Controllers:WaitForChild("HUDController") :: ModuleScript
local HUDController = require(HUDControllerModule)

-- Client-Controller starten
HUDController.Init()

print("[Client] Realm Raiders Client erfolgreich gebootet.")
