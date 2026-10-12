--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local BossServiceModule = Services:WaitForChild("BossService") :: ModuleScript
local BossService = require(BossServiceModule)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")

-- Hilfsfunktion für RemoteEvents
local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = name
	newRemote.Parent = parent
	return newRemote
end

local DimensionChangedEvent = getOrCreateRemoteEvent(EventsFolder, "DimensionChanged")

local PortalService = {}
local isInitialized = false

local OVERWORLD_PORTAL_POS = Vector3.new(95, 0.5, 0)
local OVERWORLD_SPAWN = Vector3.new(82, 3.5, 0)
local ARENA_SPAWN = BossService.ARENA_SPAWN
local ARENA_PORTAL_POS = BossService.ARENA_PORTAL_POS

-- Erstellt einen Portal-Rahmen mit leuchtendem Portal-Vortex
local function createPortal(name: string, position: Vector3, destination: Vector3, dimensionName: string, promptText: string): Model
	local portalModel = Instance.new("Model")
	portalModel.Name = name
	portalModel.Parent = Workspace

	-- Eigene Vorplatz-Plattform für das Oberwelt-Portal (damit es komplett frei steht)
	if name == "Portal_WaldRuinen" then
		local plaza = Instance.new("Part")
		plaza.Name = "PortalPlaza"
		plaza.Size = Vector3.new(26, 1, 26)
		plaza.Position = position + Vector3.new(-4, 0, 0)
		plaza.Color = Color3.fromRGB(50, 55, 65)
		plaza.Material = Enum.Material.Cobblestone
		plaza.Anchored = true
		plaza.CanCollide = true
		plaza.Parent = portalModel
	end

	-- Portal-Sockel
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(14, 2, 8)
	base.Position = position + Vector3.new(0, 1, 0)
	base.Color = Color3.fromRGB(60, 65, 75)
	base.Material = Enum.Material.Cobblestone
	base.Anchored = true
	base.CanCollide = true
	base.Parent = portalModel

	-- Linke & Rechte Säule
	local pillarL = Instance.new("Part")
	pillarL.Name = "PillarLeft"
	pillarL.Size = Vector3.new(2.5, 14, 2.5)
	pillarL.Position = position + Vector3.new(-5, 8, 0)
	pillarL.Color = Color3.fromRGB(80, 85, 95)
	pillarL.Material = Enum.Material.Slate
	pillarL.Anchored = true
	pillarL.CanCollide = true
	pillarL.Parent = portalModel

	local pillarR = Instance.new("Part")
	pillarR.Name = "PillarRight"
	pillarR.Size = Vector3.new(2.5, 14, 2.5)
	pillarR.Position = position + Vector3.new(5, 8, 0)
	pillarR.Color = Color3.fromRGB(80, 85, 95)
	pillarR.Material = Enum.Material.Slate
	pillarR.Anchored = true
	pillarR.CanCollide = true
	pillarR.Parent = portalModel

	-- Oberer Querbalken
	local topBeam = Instance.new("Part")
	topBeam.Name = "TopBeam"
	topBeam.Size = Vector3.new(13, 2.5, 3)
	topBeam.Position = position + Vector3.new(0, 15, 0)
	topBeam.Color = Color3.fromRGB(60, 65, 75)
	topBeam.Material = Enum.Material.Cobblestone
	topBeam.Anchored = true
	topBeam.CanCollide = true
	topBeam.Parent = portalModel

	-- Leuchtender Portal-Vortex (Wirbel)
	local vortex = Instance.new("Part")
	vortex.Name = "PortalVortex"
	vortex.Size = Vector3.new(7.5, 12, 0.6)
	vortex.Position = position + Vector3.new(0, 8, 0)
	vortex.Color = Color3.fromRGB(46, 204, 113)
	vortex.Material = Enum.Material.Neon
	vortex.Transparency = 0.25
	vortex.Anchored = true
	vortex.CanCollide = false
	vortex.Parent = portalModel

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(46, 204, 113)
	light.Brightness = 3
	light.Range = 20
	light.Parent = vortex

	-- ProximityPrompt für Interaktion
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = promptText
	prompt.ObjectText = dimensionName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = vortex

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		if not character then
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - vortex.Position).Magnitude > 16 then
			return
		end

		-- Teleportation auf dem Server
		root.CFrame = CFrame.new(destination)
		DimensionChangedEvent:FireClient(player, dimensionName)
		print(string.format("[PortalService] %s teleportiert nach: %s", player.Name, dimensionName))

		-- Boss dynamisch aufwecken/spawnen, falls Spieler die Arena betritt
		if destination == ARENA_SPAWN then
			task.defer(function()
				BossService.OnPlayerEnteredArena(player)
			end)
		elseif destination == OVERWORLD_SPAWN then
			task.defer(function()
				BossService.OnPlayerLeftArena(player)
			end)
		end
	end)

	return portalModel
end

function PortalService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Vorhandene Portale aufräumen
	local existingOverworld = Workspace:FindFirstChild("Portal_WaldRuinen")
	if existingOverworld then
		existingOverworld:Destroy()
	end
	local existingArena = Workspace:FindFirstChild("Portal_Oberwelt")
	if existingArena then
		existingArena:Destroy()
	end

	-- 1. Portal in der Oberwelt (auf eigenem Vorplatz östlich der Plots) -> führt in die Wald-Ruinen
	createPortal(
		"Portal_WaldRuinen",
		OVERWORLD_PORTAL_POS,
		ARENA_SPAWN,
		"Wald-Ruinen (Boss-Arena)",
		"Dimension betreten"
	)

	-- 2. Portal in der Boss-Arena -> führt zurück zur Oberwelt
	createPortal(
		"Portal_Oberwelt",
		ARENA_PORTAL_POS,
		OVERWORLD_SPAWN,
		"Oberwelt",
		"Zurückkehren"
	)

	print("[PortalService] Dimensions-Portale erfolgreich initialisiert.")
end

return PortalService
