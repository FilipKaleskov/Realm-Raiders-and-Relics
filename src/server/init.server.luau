--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local PlayerDataModule = Data:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataModule)

-- Code-Version (zum Abgleich zwischen Studio & Repo)
local CODE_VERSION = "2026-10-15-b"

-- Kanonische Liste aller RemoteEvents
local EVENT_NAMES = {
	"GoldUpdated",
	"GoldGained",
	"ShowNotification",
	"DimensionChanged",
	"BossUpdated",
	"BossDefeated",
	"BaseIntruded",
	"EntityDamaged",
	"InventoryUpdated",
	"RequestInventory",
	"AttackIntent",
	"BossTelegraphStarted",
	"CameraShakeTrigger",
	"PlotStatusUpdated",
	"ClaimPlotIntent",
	"RequestPlotStatus",
	"BuyWeaponIntent",
	"EquipWeaponIntent",
	"UnlockSlotIntent",
	"BuyDefenseIntent",
	"OpenShopWindow",
}

-- Garantiere, dass Shared.Events und alle RemoteEvents existieren, bevor Module geladen werden.
-- WICHTIG: bewusst kein :WaitForChild() - im Studio-Bau-Modus laufen keine Skripte,
-- ein Warten würde dort ewig hängen. Fehlende Events werden sofort selbst erzeugt.
local function ensureRemoteEvents(): Folder
	local eventsFolder: Folder

	local existing = Shared:FindFirstChild("Events")
	if existing and existing:IsA("Folder") then
		eventsFolder = existing
	else
		if existing then
			existing:Destroy()
		end
		local newEvents = Instance.new("Folder")
		newEvents.Name = "Events"
		newEvents.Parent = Shared
		eventsFolder = newEvents
	end

	for _, name in ipairs(EVENT_NAMES) do
		local remote = eventsFolder:FindFirstChild(name)
		if remote and not remote:IsA("RemoteEvent") then
			remote:Destroy()
			remote = nil
		end
		if not remote then
			local newRemote = Instance.new("RemoteEvent")
			newRemote.Name = name
			newRemote.Parent = eventsFolder
		end
	end

	return eventsFolder
end

ensureRemoteEvents()

-- Watchdog: meldet sich, falls der komplette Aufbau nicht innerhalb von 20s fertig wird
-- (typisches Symptom, wenn ein Modul beim Laden hängt: es passiert einfach gar nichts mehr)
local worldReady = false
task.delay(20, function()
	if not worldReady then
		warn("[Init] Der Weltaufbau ist nach 20 Sekunden nicht fertig! Vermutlich hängt ein Modul beim Laden - bitte das Output-Fenster prüfen.")
	end
end)

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

local DefenseServiceModule = Services:WaitForChild("DefenseService") :: ModuleScript
local DefenseService = require(DefenseServiceModule)

-- Optionale Test-Umgebung (Timișoara)
local TimisoaraModule = Services:FindFirstChild("TimisoaraEnvironment") :: ModuleScript?
if TimisoaraModule then
	local TimisoaraEnvironment = require(TimisoaraModule)
	TimisoaraEnvironment.Init()
end

-- Protokolliert, was tatsächlich in der Workspace aufgebaut wurde
local WORLD_ROOTS = {
	"Environment",
	"Plots",
	"Arena_WaldRuinen",
	"Portal_WaldRuinen",
	"Portal_Oberwelt",
}

local function reportWorld()
	local entries = {}
	for _, rootName in ipairs(WORLD_ROOTS) do
		local root = Workspace:FindFirstChild(rootName)
		local partCount = 0
		if root then
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("BasePart") then
					partCount += 1
				end
			end
		end
		table.insert(entries, string.format("%s=%d Parts", rootName, partCount))
	end
	print(string.format("[Init] Welt-Check: %s", table.concat(entries, " | ")))
end

-- Jeder Service wird einzeln abgesichert: Wirft EIN Service einen Fehler, werden
-- die restlichen trotzdem aufgebaut (sonst bleibt die komplette Welt leer).
local function initService(label: string, initFn: () -> ()): boolean
	local ok, err = pcall(initFn)
	if not ok then
		warn(string.format("[Init] FEHLER in %s: %s", label, tostring(err)))
	end
	return ok
end

-- Services initialisieren
-- WICHTIG (Reihenfolge): BossService.Init() baut die Boss-Arena auf. Der
-- EnvironmentService setzt danach die Fackeln IN dieser Arena - läuft er
-- vorher, bleibt die Arena unbeleuchtet.
initService("DataManager", DataManager.Init)
initService("PlotService", PlotService.Init)
initService("BossService", BossService.Init)
initService("EnvironmentService", EnvironmentService.Init)
initService("PortalService", PortalService.Init)
initService("RaidService", RaidService.Init)
initService("DefenseService", DefenseService.Init)

print(string.format("Realm Raiders Framework initialisiert (Code-Version %s)", CODE_VERSION))
print(string.format(
	"[Init] Start-Gold: %d, Start-Gems: %d, Start-Waffe: %s",
	PlayerDataTemplate.Gold,
	PlayerDataTemplate.Gems,
	PlayerDataTemplate.Inventory.Weapons[1] or "Keine"
))
reportWorld()

worldReady = true
