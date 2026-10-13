--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local PlayerDataModule = Data:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataModule)

-- Garantiere, dass Shared.Events und alle RemoteEvents existieren, bevor Module geladen werden
local function ensureRemoteEvents(): Folder
	local eventsFolder = Shared:FindFirstChild("Events")
	if not eventsFolder then
		local newEvents = Instance.new("Folder")
		newEvents.Name = "Events"
		newEvents.Parent = Shared
		eventsFolder = newEvents
	end

	local remoteNames = {
		"GoldUpdated",
		"ShowNotification",
		"DimensionChanged",
		"BossUpdated",
		"BossDefeated",
		"BaseIntruded",
		"InventoryUpdated",
		"RequestInventory",
		"AttackIntent",
		"BossTelegraphStarted",
		"PlotStatusUpdated",
		"ClaimPlotIntent",
		"RequestPlotStatus",
	}

	for _, name in remoteNames do
		if not eventsFolder:FindFirstChild(name) then
			local rem = Instance.new("RemoteEvent")
			rem.Name = name
			rem.Parent = eventsFolder
		end
	end

	return eventsFolder :: Folder
end

ensureRemoteEvents()

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

local RaidServiceModule = Services:WaitForChild("RaidService") :: ModuleScript
local RaidService = require(RaidServiceModule)

local EnvironmentServiceModule = Services:WaitForChild("EnvironmentService") :: ModuleScript
local EnvironmentService = require(EnvironmentServiceModule)

-- Optionale Test-Umgebung (Timișoara)
local TimisoaraModule = Services:FindFirstChild("TimisoaraEnvironment") :: ModuleScript?
if TimisoaraModule then
	local TimisoaraEnvironment = require(TimisoaraModule)
	TimisoaraEnvironment.Init()
end

-- Services initialisieren
DataManager.Init()
PlotService.Init()
EnvironmentService.Init()
PortalService.Init()
BossService.Init()
RaidService.Init()

print("Realm Raiders Framework initialisiert")
print(string.format(
	"[Init] Start-Gold: %d, Start-Gems: %d, Start-Waffe: %s",
	PlayerDataTemplate.Gold,
	PlayerDataTemplate.Gems,
	PlayerDataTemplate.Inventory.Weapons[1] or "Keine"
))
