--!strict

--[[
	WorldBuilder (nur für Roblox Studio)
	====================================

	Die komplette Spielwelt (Plots, schwebende Insel, Säuresee, Hängebrücke,
	Dimensions-Portale, Boss-Arena, Schmiede) wird zur Laufzeit von
	Server-Skripten erzeugt. Im Bau-Modus (Edit-Modus) von Roblox Studio laufen
	diese Skripte NICHT - die Workspace ist dort also (fast) leer.

	Dieses Modul baut die Welt manuell im Bau-Modus auf, damit man sie sehen,
	verschieben und dekorieren kann.

	Benutzung - Studio-Befehlszeile (Command Bar), danach Strg+S zum Speichern:

		require(game.ServerScriptService.Server.Studio.WorldBuilder).BuildAll()

	Einzelne Bauschritte (z.B. nur die Plots neu aufbauen):

		local WB = require(game.ServerScriptService.Server.Studio.WorldBuilder)
		WB.BuildBossArena()   -- Boss-Arena (Wald-Ruinen) inkl. Wald & Schrein
		WB.BuildEnvironment() -- Insel, Allee, Säuresee, Hängebrücke, Schmiede
		WB.BuildPortals()     -- Dimensions-Portale
		WB.BuildPlots()       -- 6 Plots inkl. Sockel, Fallen & Wächter
		WB.Clear()            -- Generierte Welt wieder aus der Workspace entfernen
		WB.Diagnose()         -- Nur prüfen: Was ist da? Welche Version läuft?
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local WorldBuilder = {}

-- Muss zur CODE_VERSION in init.server.luau passen
WorldBuilder.Version = "2026-10-15-b"

-- Service-Module, die für den Aufbau gebraucht werden
local REQUIRED_SERVICES = { "BossService", "EnvironmentService", "PortalService", "PlotService", "DefenseService" }

-- Alles, was von diesem Builder bzw. den Services direkt in die Workspace gebaut wird
local GENERATED_ROOT_NAMES = {
	"Baseplate",
	"Plots",
	"Environment",
	"ToxicAcidLake",
	"Arena_WaldRuinen",
	"Portal_WaldRuinen",
	"Portal_Oberwelt",
}

-- Wurzel-Ordner, die nach einem Aufbau existieren müssen
local WORLD_ROOTS = {
	"Environment",
	"Plots",
	"Arena_WaldRuinen",
	"Portal_WaldRuinen",
	"Portal_Oberwelt",
}

-- Lädt ein Service-Modul. Bewusst FindFirstChild statt WaitForChild:
-- fehlt etwas, gibt es eine klare Fehlermeldung statt eines ewigen Hängens.
local function getService(name: string): any
	local module = Services:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(string.format("Service '%s' fehlt in ServerScriptService.Server.Services - bitte im Rojo-Plugin auf Connect/Sync klicken!", name), 2)
	end
	return require(module)
end

-- Schutz: Der Builder löscht und erzeugt massenhaft Instanzen - nur im Bau-Modus erlaubt!
local function isEditMode(): boolean
	if not RunService:IsStudio() or RunService:IsRunning() then
		warn("[WorldBuilder] Dieses Tool funktioniert nur im Bau-Modus (Edit-Modus) von Roblox Studio.")
		return false
	end
	return true
end

-- Zählt alle BaseParts unter einem Objekt (0, wenn es nicht existiert)
local function countParts(root: Instance?): number
	if not root then
		return 0
	end
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- Prüft die Workspace und protokolliert das Ergebnis (Welt-Check)
local function reportWorld(prefix: string): boolean
	local allFine = true
	local entries = {}

	for _, rootName in ipairs(WORLD_ROOTS) do
		local root = Workspace:FindFirstChild(rootName)
		local parts = countParts(root)
		if not root or parts == 0 then
			allFine = false
		end
		table.insert(entries, string.format("%s %s=%d Parts", if root then "OK  " else "FEHLT", rootName, parts))
	end

	print(string.format("[WorldBuilder] %s: %s", prefix, table.concat(entries, " | ")))
	return allFine
end

-- Führt einen Bauschritt aus, fängt Fehler ab und protokolliert das Ergebnis
local function runStep(label: string, buildFn: () -> ()): boolean
	local startedAt = os.clock()
	local ok, err = pcall(buildFn)
	local duration = os.clock() - startedAt

	if ok then
		print(string.format("[WorldBuilder] OK    %s (%.2fs)", label, duration))
	else
		warn(string.format("[WorldBuilder] FEHLER bei '%s': %s", label, tostring(err)))
	end

	return ok
end

-- Entfernt alles, was dieser Builder erzeugt hat (für einen sauberen Neuaufbau)
function WorldBuilder.Clear()
	if not isEditMode() then
		return
	end

	for _, name in ipairs(GENERATED_ROOT_NAMES) do
		local instance = Workspace:FindFirstChild(name)
		if instance then
			instance:Destroy()
		end
	end

	-- Roblox' Standard-Baseplate heißt je nach Vorlage "Baseplate" oder "BasePlate"
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and string.lower(child.Name):find("baseplate") then
			child:Destroy()
		end
	end

	print("[WorldBuilder] Workspace aufgeräumt.")
end

-- Nur prüfen, nichts ändern: Zeigt Version, Modus und vorhandene Welt-Objekte
function WorldBuilder.Diagnose()
	print(string.format("[WorldBuilder] Diagnose (Version %s)", WorldBuilder.Version))
	print(string.format("[WorldBuilder] Studio=%s, IsRunning=%s, IsEditMode=%s",
		tostring(RunService:IsStudio()),
		tostring(RunService:IsRunning()),
		tostring(RunService:IsStudio() and not RunService:IsRunning())
	))

	for _, serviceName in ipairs(REQUIRED_SERVICES) do
		local module = Services:FindFirstChild(serviceName)
		print(string.format("[WorldBuilder] Service %-18s vorhanden=%s", serviceName, tostring(module ~= nil)))
	end

	-- Versions-Abgleich: Hat BossService schon den Bau-Modus-Support?
	local ok, bossService = pcall(function()
		return getService("BossService")
	end)
	if ok then
		print(string.format("[WorldBuilder] BossService.BuildArenaInStudio vorhanden=%s",
			tostring(bossService.BuildArenaInStudio ~= nil)))
	else
		warn(string.format("[WorldBuilder] BossService konnte nicht geladen werden: %s", tostring(bossService)))
	end

	reportWorld("Welt-Check")
end

-- Boss-Arena (Wald-Ruinen): Boden, Ruinenmauern, Säulen, Wald-Deko & Amethyst-Schrein
function WorldBuilder.BuildBossArena(): boolean
	if not isEditMode() then
		return false
	end

	return runStep("Boss-Arena (Wald-Ruinen)", function()
		local bossService = getService("BossService")
		if bossService.BuildArenaInStudio then
			bossService.BuildArenaInStudio() -- Baut nur die Arena (keine KI, kein Boss-Spawn)
		else
			-- Fallback für ältere Versionen im Studio
			bossService.Init()
		end
	end)
end

-- Umgebung: schwebende Insel mit Allee, Säuresee, Hängebrücke, Portal-Insel, Waffen-Schmiede
function WorldBuilder.BuildEnvironment(): boolean
	if not isEditMode() then
		return false
	end

	return runStep("Umgebung (Insel, Säuresee, Hängebrücke, Schmiede)", function()
		getService("EnvironmentService").BuildInStudio()
	end)
end

-- Dimensions-Portale (Oberwelt <-> Boss-Arena)
function WorldBuilder.BuildPortals(): boolean
	if not isEditMode() then
		return false
	end

	return runStep("Dimensions-Portale", function()
		getService("PortalService").BuildInStudio()
	end)
end

-- Die 6 Spieler-Plots inkl. Sockel, Test-Rivale mit Stachelfallen & Wächter-Minion
function WorldBuilder.BuildPlots(): boolean
	if not isEditMode() then
		return false
	end

	return runStep("6 Spieler-Plots (Sockel, Fallen, Wächter)", function()
		getService("PlotService").BuildPlotsInStudio(true)
	end)
end

-- Baut die komplette Welt im Bau-Modus auf.
-- Reihenfolge ist wichtig: Die Boss-Arena muss vor der Umgebung existieren,
-- weil der EnvironmentService dort die Fackeln aufstellt. Ein fehlgeschlagener
-- Schritt verhindert die restlichen Schritte NICHT (jeder läuft abgesichert).
function WorldBuilder.BuildAll()
	if not isEditMode() then
		return
	end

	print(string.format("[WorldBuilder] Baue komplette Welt im Bau-Modus auf ... (Version %s)", WorldBuilder.Version))

	WorldBuilder.Clear()
	WorldBuilder.BuildBossArena()
	WorldBuilder.BuildEnvironment()
	WorldBuilder.BuildPortals()
	WorldBuilder.BuildPlots()

	local allFine = reportWorld("Welt-Check")
	if allFine then
		print("[WorldBuilder] Tipp: Jetzt Strg+S drücken - danach ist die Welt dauerhaft im Bau-Modus sichtbar.")
	else
		warn("[WorldBuilder] Mindestens ein Welt-Teil fehlt! Bitte den Output oben (FEHLER-Zeilen) an den Entwickler schicken.")
	end
end

return WorldBuilder
