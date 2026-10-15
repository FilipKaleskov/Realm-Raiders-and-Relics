--[[
	Realm Welt-Builder  (Roblox Studio Plugin)
	==========================================

	Zeigt in der Studio-Werkzeugleiste Buttons, mit denen die komplette Spielwelt
	im Bau-Modus aufgebaut werden kann - ohne Befehlszeile.

	Die eigentliche Logik steckt im Place selbst:
		ServerScriptService.Server.Studio.WorldBuilder

	Installation: Diese Datei als Plugin in den Studio-Plugin-Ordner bauen
	(rojo build plugin.project.json -o "%LOCALAPPDATA%\Roblox\Plugins\RealmWeltBuilder.rbxmx")
	und Studio neu starten.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local toolbar = plugin:CreateToolbar("Realm Welt (Bau-Modus)")

-- Lädt den WorldBuilder aus dem aktuellen Place (muss per Rojo synchronisiert sein)
local function getWorldBuilder(): any
	local server = ServerScriptService:FindFirstChild("Server")
	local studioFolder = if server then server:FindFirstChild("Studio") else nil
	local module = if studioFolder then studioFolder:FindFirstChild("WorldBuilder") else nil

	if not module or not module:IsA("ModuleScript") then
		error("WorldBuilder nicht gefunden! Bitte im Rojo-Plugin auf Connect/Sync klicken.", 2)
	end

	return require(module)
end

-- Führt eine Aktion abgesichert aus und meldet Fehler ins Output-Fenster
local function run(label: string, action: (builder: any) -> ())
	local ok, err = pcall(function()
		action(getWorldBuilder())
	end)

	if not ok then
		warn(string.format("[Realm Welt] '%s' fehlgeschlagen: %s", label, tostring(err)))
	else
		print(string.format("[Realm Welt] '%s' fertig - nicht vergessen: Strg+S zum Speichern.", label))
	end
end

local function createButton(name: string, tooltip: string, textIcon: string): PluginToolbarButton
	return toolbar:CreateButton(name, tooltip, "", textIcon)
end

local buildAllButton = createButton("Welt bauen", "Baut die komplette Welt im Bau-Modus auf", "Welt")
buildAllButton.Click:Connect(function()
	run("Welt bauen", function(builder)
		builder.BuildAll()
	end)
end)

local environmentButton = createButton("Umgebung", "Nur Insel, Säuresee, Hängebrücke & Schmiede", "Umgeb.")
environmentButton.Click:Connect(function()
	run("Umgebung", function(builder)
		builder.BuildEnvironment()
	end)
end)

local plotsButton = createButton("Plots", "Nur die 6 Spieler-Plots mit Sockeln & Verteidigung", "Plots")
plotsButton.Click:Connect(function()
	run("Plots", function(builder)
		builder.BuildPlots()
	end)
end)

local portalsButton = createButton("Portale", "Nur die Dimensions-Portale", "Portale")
portalsButton.Click:Connect(function()
	run("Portale", function(builder)
		builder.BuildPortals()
	end)
end)

local arenaButton = createButton("Boss-Arena", "Nur die Boss-Arena (Wald-Ruinen)", "Arena")
arenaButton.Click:Connect(function()
	run("Boss-Arena", function(builder)
		builder.BuildBossArena()
	end)
end)

local clearButton = createButton("Welt löschen", "Entfernt die generierte Welt wieder", "Löschen")
clearButton.Click:Connect(function()
	run("Welt löschen", function(builder)
		builder.Clear()
	end)
end)

local diagnoseButton = createButton("Diagnose", "Zeigt Version und vorhandene Welt-Teile", "Info")
diagnoseButton.Click:Connect(function()
	run("Diagnose", function(builder)
		builder.Diagnose()
	end)
end)
