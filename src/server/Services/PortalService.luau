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
local NotificationEvent = getOrCreateRemoteEvent(EventsFolder, "ShowNotification")

local PortalService = {}
local isInitialized = false

-- Koordinaten für Oberwelt & Boss-Arena
local OVERWORLD_PORTAL_POS = Vector3.new(160, 0.5, 0)
local OVERWORLD_SPAWN = Vector3.new(148, 3.5, 0)
local ARENA_SPAWN = BossService.ARENA_SPAWN
local ARENA_PORTAL_POS = BossService.ARENA_PORTAL_POS

-- Erstellt eine Feuerschale / Fackel als Portal-Dekoration
local function createPortalBrazier(position: Vector3, parent: Instance)
	local stand = Instance.new("Part")
	stand.Name = "BrazierStand"
	stand.Size = Vector3.new(2.0, 3.6, 2.0)
	stand.Position = position + Vector3.new(0, 1.8, 0)
	stand.Color = Color3.fromRGB(45, 50, 54)
	stand.Material = Enum.Material.Slate
	stand.Anchored = true
	stand.CanCollide = true
	stand.Parent = parent

	local bowl = Instance.new("Part")
	bowl.Name = "BrazierBowl"
	bowl.Size = Vector3.new(3.0, 1.0, 3.0)
	bowl.Position = position + Vector3.new(0, 3.9, 0)
	bowl.Color = Color3.fromRGB(28, 30, 34)
	bowl.Material = Enum.Material.CorrodedMetal
	bowl.Anchored = true
	bowl.CanCollide = true
	bowl.Parent = parent

	local fireCore = Instance.new("Part")
	fireCore.Name = "FireCore"
	fireCore.Size = Vector3.new(1.8, 0.4, 1.8)
	fireCore.Position = position + Vector3.new(0, 4.3, 0)
	fireCore.Color = Color3.fromRGB(255, 140, 25)
	fireCore.Material = Enum.Material.Neon
	fireCore.Anchored = true
	fireCore.CanCollide = false
	fireCore.Parent = parent

	local fire = Instance.new("Fire")
	fire.Size = 2.0
	fire.Heat = 2
	fire.Color = Color3.fromRGB(255, 130, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 10)
	fire.Parent = fireCore

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 155, 45)
	light.Range = 14
	light.Brightness = 1.0
	light.Parent = fireCore
end

-- Erstellt einen antiken Tempel mit Stufen-Sockel, Steintor & schwebendem, rotierendem Amethyst-Kristall
local function createPortal(
	name: string,
	position: Vector3,
	facingLookAt: Vector3,
	destination: Vector3,
	dimensionName: string,
	promptText: string
): Model
	local portalModel = Instance.new("Model")
	portalModel.Name = name
	portalModel.Parent = Workspace

	local rootCFrame = CFrame.lookAt(position, Vector3.new(facingLookAt.X, position.Y, facingLookAt.Z))

	-- 1. Dreistufiger Sockel aus weißem Marmor (wie im Trailer-Video)
	local stepTiers = {
		{ Size = Vector3.new(22, 1.2, 18), OffsetY = 0.6 },
		{ Size = Vector3.new(18, 1.2, 14), OffsetY = 1.8 },
		{ Size = Vector3.new(14, 1.2, 10), OffsetY = 3.0 },
	}

	for idx, tier in ipairs(stepTiers) do
		local step = Instance.new("Part")
		step.Name = "PlinthStep_" .. idx
		step.Size = tier.Size
		step.CFrame = rootCFrame * CFrame.new(0, tier.OffsetY, 0)
		step.Color = Color3.fromRGB(240, 242, 246)
		step.Material = Enum.Material.Marble
		step.Anchored = true
		step.CanCollide = true
		step.Parent = portalModel
	end

	-- Flankierende Feuerschalen am Fuß des Tempels
	createPortalBrazier((rootCFrame * CFrame.new(-9.5, 0, 7)).Position, portalModel)
	createPortalBrazier((rootCFrame * CFrame.new(9.5, 0, 7)).Position, portalModel)

	-- 2. Antiker Steintor-Bogen (Säulen, Kapitelle, Querbalken & Giebel)
	local pillarL = Instance.new("Part")
	pillarL.Name = "PillarLeft"
	pillarL.Size = Vector3.new(3.0, 16.0, 3.0)
	pillarL.CFrame = rootCFrame * CFrame.new(-5.5, 11.6, 0)
	pillarL.Color = Color3.fromRGB(48, 54, 60)
	pillarL.Material = Enum.Material.Slate
	pillarL.Anchored = true
	pillarL.CanCollide = true
	pillarL.Parent = portalModel

	local pillarR = Instance.new("Part")
	pillarR.Name = "PillarRight"
	pillarR.Size = Vector3.new(3.0, 16.0, 3.0)
	pillarR.CFrame = rootCFrame * CFrame.new(5.5, 11.6, 0)
	pillarR.Color = Color3.fromRGB(48, 54, 60)
	pillarR.Material = Enum.Material.Slate
	pillarR.Anchored = true
	pillarR.CanCollide = true
	pillarR.Parent = portalModel

	-- Kapitell-Aufsätze über den Säulen
	for _, xSide in { -5.5, 5.5 } do
		local cap = Instance.new("Part")
		cap.Name = "Capital"
		cap.Size = Vector3.new(4.0, 1.4, 4.0)
		cap.CFrame = rootCFrame * CFrame.new(xSide, 20.3, 0)
		cap.Color = Color3.fromRGB(62, 68, 76)
		cap.Material = Enum.Material.Slate
		cap.Anchored = true
		cap.CanCollide = true
		cap.Parent = portalModel
	end

	-- Massiver Torbogen-Querbalken
	local lintel = Instance.new("Part")
	lintel.Name = "LintelBeam"
	lintel.Size = Vector3.new(16.0, 3.2, 4.2)
	lintel.CFrame = rootCFrame * CFrame.new(0, 22.0, 0)
	lintel.Color = Color3.fromRGB(42, 47, 52)
	lintel.Material = Enum.Material.Slate
	lintel.Anchored = true
	lintel.CanCollide = true
	lintel.Parent = portalModel

	-- Antiker Zier-Giebel auf dem Balken
	local pediment = Instance.new("Part")
	pediment.Name = "Pediment"
	pediment.Size = Vector3.new(10.0, 2.2, 3.8)
	pediment.CFrame = rootCFrame * CFrame.new(0, 24.5, 0)
	pediment.Color = Color3.fromRGB(52, 58, 66)
	pediment.Material = Enum.Material.Slate
	pediment.Anchored = true
	pediment.CanCollide = true
	pediment.Parent = portalModel

	-- 3. Schwebender, rotierender Amethyst-Kristall (Portal-Kern)
	local crystalOrigin = rootCFrame * CFrame.new(0, 11.5, 0)

	local crystal = Instance.new("Part")
	crystal.Name = "AmethystCrystal"
	crystal.Size = Vector3.new(3.8, 6.4, 3.8)
	crystal.CFrame = crystalOrigin
	crystal.Color = Color3.fromRGB(160, 45, 230) -- Reiner, klarer Amethyst
	crystal.Material = Enum.Material.Glass
	crystal.Transparency = 0.2
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.Parent = portalModel

	-- Diamant-Facetten Mesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Scale = Vector3.new(1.0, 1.0, 1.0)
	mesh.Parent = crystal

	-- Dezenter, klarer Amethyst-Lichtschein (ohne Überstrahlung / kein Blendeffekt)
	local crystalLight = Instance.new("PointLight")
	crystalLight.Name = "CrystalLight"
	crystalLight.Color = Color3.fromRGB(180, 60, 255)
	crystalLight.Brightness = 1.0
	crystalLight.Range = 16
	crystalLight.Parent = crystal

	-- Feine, winzige Sternen-Funken (keine dichte Nebelwolke mehr)
	local att = Instance.new("Attachment")
	att.Name = "ParticleAtt"
	att.Parent = crystal

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "CrystalSparks"
	particles.Rate = 5
	particles.Lifetime = NumberRange.new(0.8, 1.4)
	particles.Speed = NumberRange.new(0.4, 1.0)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 0.05),
	}
	particles.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1.0),
	}
	particles.Color = ColorSequence.new(Color3.fromRGB(225, 130, 255))
	particles.LightEmission = 0.2
	particles.Parent = att

	-- Sanfte Rotation & Schwebung animieren
	task.spawn(function()
		local startTime = os.clock()
		while crystal:IsDescendantOf(Workspace) do
			local elapsed = os.clock() - startTime
			local bobOffset = math.sin(elapsed * 2.2) * 0.65
			local spinCFrame = CFrame.Angles(0, math.rad(elapsed * 45), 0)
			crystal.CFrame = crystalOrigin * CFrame.new(0, bobOffset, 0) * spinCFrame
			task.wait(0.03)
		end
	end)

	-- 4. ProximityPrompt für Dimensionstransfer
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = promptText
	prompt.ObjectText = dimensionName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = crystal

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		if not character then
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - crystal.Position).Magnitude > 18 then
			return
		end

		-- Prüfe, ob der Spieler einen gestohlenen Kern trägt (Flucht-Restriktion)
		if player:GetAttribute("CarryingCore") ~= nil then
			NotificationEvent:FireClient(player, "🚫 Du kannst keine Portale betreten, solange du einen Kern trägst!", true)
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

	-- 1. Portal in der Oberwelt (steht auf der Felseninsel am Ende der Hängebrücke, blickt nach Westen zur Brücke)
	createPortal(
		"Portal_WaldRuinen",
		OVERWORLD_PORTAL_POS,
		Vector3.new(75, 0.5, 0), -- Blickrichtung zur Hängebrücke
		ARENA_SPAWN,
		"Wald-Ruinen (Boss-Arena)",
		"Dimension betreten"
	)

	-- 2. Portal in der Boss-Arena -> führt zurück zur Oberwelt (steht am Arenarand, blickt zum Bosszentrum)
	createPortal(
		"Portal_Oberwelt",
		ARENA_PORTAL_POS,
		BossService.ARENA_CENTER or Vector3.new(0, 500, 25000),
		OVERWORLD_SPAWN,
		"Oberwelt",
		"Zurückkehren"
	)

	print("[PortalService] Dimensions-Tempel & Amethyst-Portale erfolgreich initialisiert.")
end

-- Für die Studio Command Bar
function PortalService.BuildInStudio()
	isInitialized = false
	PortalService.Init()
end

return PortalService
