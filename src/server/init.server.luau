--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local PlayerDataModule = Data:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataModule)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

local PlotServiceModule = Services:WaitForChild("PlotService") :: ModuleScript
local PlotService = require(PlotServiceModule)

local PortalServiceModule = Services:WaitForChild("PortalService") :: ModuleScript
local PortalService = require(PortalServiceModule)

local BossServiceModule = Services:WaitForChild("BossService") :: ModuleScript
local BossService = require(BossServiceModule)

-- Optionale Test-Umgebung (Timișoara)
local TimisoaraModule = Services:FindFirstChild("TimisoaraEnvironment") :: ModuleScript?
if TimisoaraModule then
	local TimisoaraEnvironment = require(TimisoaraModule)
	TimisoaraEnvironment.Init()
end

-- Services initialisieren
DataManager.Init()
PlotService.Init()
PortalService.Init()
BossService.Init()

print("Realm Raiders Framework initialisiert")
print(string.format(
	"[Init] Start-Gold: %d, Start-Gems: %d, Start-Waffe: %s",
	PlayerDataTemplate.Gold,
	PlayerDataTemplate.Gems,
	PlayerDataTemplate.Inventory.Weapons[1] or "Keine"
))
