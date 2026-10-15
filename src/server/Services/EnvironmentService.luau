--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

-- RemoteEvents: fehlende Events werden sofort selbst erzeugt.
-- Bewusst KEIN :WaitForChild() - im Studio-Bau-Modus laufen keine Skripte,
-- ein Warten auf noch nicht existierende Events würde dort ewig hängen.
local function getEventsFolder(): Folder
	local events = Shared:FindFirstChild("Events")
	if events and events:IsA("Folder") then
		return events
	end
	if events then
		events:Destroy()
	end
	local newEvents = Instance.new("Folder")
	newEvents.Name = "Events"
	newEvents.Parent = Shared
	return newEvents
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local events = getEventsFolder()
	local existing = events:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = name
	newRemote.Parent = events
	return newRemote
end

local OpenShopWindowEvent = getOrCreateRemoteEvent("OpenShopWindow")

local EnvironmentService = {}
local isInitialized = false

-- Erstellt eine brennende Feuerschale / Fackel mit flackerndem Licht & Partikeln
function EnvironmentService.CreateBrazier(position: Vector3, parent: Instance): Model
	local brazier = Instance.new("Model")
	brazier.Name = "Brazier"
	brazier.Parent = parent

	-- Sockel (Antiker Schieferstein)
	local stand = Instance.new("Part")
	stand.Name = "Stand"
	stand.Size = Vector3.new(2.2, 4.0, 2.2)
	stand.Position = position + Vector3.new(0, 2.0, 0)
	stand.Color = Color3.fromRGB(45, 50, 54)
	stand.Material = Enum.Material.Slate
	stand.Anchored = true
	stand.CanCollide = true
	stand.Parent = brazier

	-- Schale (Dunkles Schmiedeeisen)
	local bowl = Instance.new("Part")
	bowl.Name = "Bowl"
	bowl.Size = Vector3.new(3.2, 1.2, 3.2)
	bowl.Position = position + Vector3.new(0, 4.4, 0)
	bowl.Color = Color3.fromRGB(28, 30, 34)
	bowl.Material = Enum.Material.CorrodedMetal
	bowl.Anchored = true
	bowl.CanCollide = true
	bowl.Parent = brazier

	-- Glühende Kohlen / Flammenkern
	local fireCore = Instance.new("Part")
	fireCore.Name = "FireCore"
	fireCore.Size = Vector3.new(2.0, 0.4, 2.0)
	fireCore.Position = position + Vector3.new(0, 4.9, 0)
	fireCore.Color = Color3.fromRGB(255, 140, 25)
	fireCore.Material = Enum.Material.Neon
	fireCore.Anchored = true
	fireCore.CanCollide = false
	fireCore.Parent = brazier

	-- Roblox Feuer-Effekt
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 5
	fire.Color = Color3.fromRGB(255, 130, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 10)
	fire.Parent = fireCore

	-- Warmes Umgebungslicht mit sanftem Flackern
	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = Color3.fromRGB(255, 155, 45)
	light.Range = 22
	light.Brightness = 1.8
	light.Shadows = true
	light.Parent = fireCore

	-- Flackern animieren
	task.spawn(function()
		while fireCore:IsDescendantOf(Workspace) do
			light.Brightness = 1.6 + math.random() * 0.5
			task.wait(0.08 + math.random() * 0.08)
		end
	end)

	return brazier
end



-- Erstellt das schwebende Fels-Plateau unter den Plots inklusive zentraler Allee
local function createMainPlateau(envFolder: Folder): Model
	local plateauModel = Instance.new("Model")
	plateauModel.Name = "MainCitadelPlateau"
	plateauModel.Parent = envFolder

	-- 1. Massiver Fels-Körper unter den Plots (Schwebende Felseninsel)
	local rockBase = Instance.new("Part")
	rockBase.Name = "RockBase"
	rockBase.Size = Vector3.new(160, 8, 130)
	rockBase.Position = Vector3.new(0, -4.0, 0)
	rockBase.Color = Color3.fromRGB(38, 42, 46)
	rockBase.Material = Enum.Material.Slate
	rockBase.Anchored = true
	rockBase.CanCollide = true
	rockBase.Parent = plateauModel

	-- 2. Zentrale Pflasterstein-Allee zwischen den Plot-Reihen (führt direkt zur Hängebrücke)
	local mainAvenue = Instance.new("Part")
	mainAvenue.Name = "MainAvenue"
	mainAvenue.Size = Vector3.new(160, 0.4, 18)
	mainAvenue.Position = Vector3.new(0, 0.2, 0)
	mainAvenue.Color = Color3.fromRGB(56, 62, 70)
	mainAvenue.Material = Enum.Material.Cobblestone
	mainAvenue.Anchored = true
	mainAvenue.CanCollide = true
	mainAvenue.Parent = plateauModel

	-- Fackeln entlang der zentralen Allee (West, Mitte, Ost)
	local brazierOffsets = { -60, -20, 20, 60 }
	for _, xOffset in brazierOffsets do
		EnvironmentService.CreateBrazier(Vector3.new(xOffset, 0.2, -10), plateauModel)
		EnvironmentService.CreateBrazier(Vector3.new(xOffset, 0.2, 10), plateauModel)
	end

	return plateauModel
end

-- Erstellt den atmosphärischen Waffen-Schmiede-Stand auf der zentralen Allee
local function createBlacksmithShop(envFolder: Folder): Model
	local shopModel = Instance.new("Model")
	shopModel.Name = "BlacksmithShop"
	shopModel.Parent = envFolder

	local origin = Vector3.new(0, 0.2, -6.5)

	-- 1. Holz-Werkstatt-Podest
	local deck = Instance.new("Part")
	deck.Name = "ShopDeck"
	deck.Size = Vector3.new(12, 0.4, 6)
	deck.Position = origin + Vector3.new(0, 0.2, 0)
	deck.Color = Color3.fromRGB(80, 55, 38)
	deck.Material = Enum.Material.WoodPlanks
	deck.Anchored = true
	deck.CanCollide = true
	deck.Parent = shopModel

	-- 2. Amboss-Sockel (Massiver Eichenholz-Block)
	local anvilLog = Instance.new("Part")
	anvilLog.Name = "AnvilLog"
	anvilLog.Size = Vector3.new(2.4, 2.2, 2.4)
	anvilLog.Position = origin + Vector3.new(0, 1.3, 0)
	anvilLog.Color = Color3.fromRGB(65, 45, 30)
	anvilLog.Material = Enum.Material.Wood
	anvilLog.Anchored = true
	anvilLog.CanCollide = true
	anvilLog.Parent = shopModel

	-- 3. Amboss (Schweres Schmiedeeisen)
	local anvilBase = Instance.new("Part")
	anvilBase.Name = "AnvilBase"
	anvilBase.Size = Vector3.new(3.4, 1.2, 1.6)
	anvilBase.Position = origin + Vector3.new(0, 2.8, 0)
	anvilBase.Color = Color3.fromRGB(35, 38, 42)
	anvilBase.Material = Enum.Material.Metal
	anvilBase.Anchored = true
	anvilBase.CanCollide = true
	anvilBase.Parent = shopModel

	local anvilHorn = Instance.new("Part")
	anvilHorn.Name = "AnvilHorn"
	anvilHorn.Size = Vector3.new(1.4, 0.8, 1.0)
	anvilHorn.Position = origin + Vector3.new(-2.0, 2.8, 0)
	anvilHorn.Color = Color3.fromRGB(42, 45, 50)
	anvilHorn.Material = Enum.Material.Metal
	anvilHorn.Anchored = true
	anvilHorn.CanCollide = false
	anvilHorn.Parent = shopModel

	-- 4. Glühender Eisenbarren auf dem Amboss
	local glowingBillet = Instance.new("Part")
	glowingBillet.Name = "GlowingSteel"
	glowingBillet.Size = Vector3.new(1.6, 0.3, 0.7)
	glowingBillet.Position = origin + Vector3.new(0, 3.55, 0)
	glowingBillet.Color = Color3.fromRGB(255, 115, 20)
	glowingBillet.Material = Enum.Material.Neon
	glowingBillet.Anchored = true
	glowingBillet.CanCollide = false
	glowingBillet.Parent = shopModel

	local glowLight = Instance.new("PointLight")
	glowLight.Color = Color3.fromRGB(255, 140, 30)
	glowLight.Brightness = 1.6
	glowLight.Range = 12
	glowLight.Parent = glowingBillet

	-- 5. Stein-Schmiedeofen mit Glut
	local forgeOven = Instance.new("Part")
	forgeOven.Name = "ForgeOven"
	forgeOven.Size = Vector3.new(3.6, 5.0, 3.6)
	forgeOven.Position = origin + Vector3.new(4.2, 2.5, 0)
	forgeOven.Color = Color3.fromRGB(50, 52, 56)
	forgeOven.Material = Enum.Material.Cobblestone
	forgeOven.Anchored = true
	forgeOven.CanCollide = true
	forgeOven.Parent = shopModel

	local coalGlow = Instance.new("Part")
	coalGlow.Name = "CoalGlow"
	coalGlow.Size = Vector3.new(2.2, 0.6, 1.2)
	coalGlow.Position = origin + Vector3.new(4.2, 1.8, 1.3)
	coalGlow.Color = Color3.fromRGB(255, 80, 15)
	coalGlow.Material = Enum.Material.Neon
	coalGlow.Anchored = true
	coalGlow.CanCollide = false
	coalGlow.Parent = shopModel

	-- 6. Ausstellungs-Waffenständer (Links)
	local weaponRack = Instance.new("Part")
	weaponRack.Name = "WeaponRack"
	weaponRack.Size = Vector3.new(2.8, 3.6, 0.8)
	weaponRack.Position = origin + Vector3.new(-4.2, 1.8, 0)
	weaponRack.Color = Color3.fromRGB(75, 52, 35)
	weaponRack.Material = Enum.Material.WoodPlanks
	weaponRack.Anchored = true
	weaponRack.CanCollide = true
	weaponRack.Parent = shopModel

	-- 7. 3D-Billboard über dem Amboss
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShopSign"
	billboard.Size = UDim2.new(0, 240, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 4.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	billboard.Parent = anvilBase

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, 0.55, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "⚔️ WAFFEN-SCHMIEDE"
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Text = "Waffen schmieden & Upgrades"
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 13
	sub.TextColor3 = Color3.fromRGB(220, 225, 235)
	sub.TextStrokeTransparency = 0.4
	sub.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	sub.Parent = billboard

	-- 8. ProximityPrompt zum Öffnen des Shop-Guis
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Schmiede & Shop öffnen"
	prompt.ObjectText = "Waffen-Schmiede"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	-- Phase 3 (Mobile): Prompt ist auf Touch-Geräten antippbar und wird clientseitig
	-- durch ein großes, daumenfreundliches Touch-Ziel ersetzt.
	prompt.ClickablePrompt = true
	prompt.Parent = anvilBase

	prompt.Triggered:Connect(function(player: Player)
		OpenShopWindowEvent:FireClient(player)
	end)

	return shopModel
end

-- Erstellt den giftgrünen Säure-Abgrund tief unter den Inseln & Brücken
local function createToxicAcidLake(envFolder: Folder): Model
	local acidModel = Instance.new("Model")
	acidModel.Name = "ToxicAcidLake"
	acidModel.Parent = envFolder

	-- Haupt-Säurefläche (Klares Giftgrün, ohne Neon-Glow / ohne Nebelpartikel)
	local acidTop = Instance.new("Part")
	acidTop.Name = "AcidSurface"
	acidTop.Size = Vector3.new(800, 4, 800)
	acidTop.Position = Vector3.new(50, -22, 0)
	acidTop.Color = Color3.fromRGB(35, 175, 25)
	acidTop.Material = Enum.Material.SmoothPlastic
	acidTop.Transparency = 0.2
	acidTop.Anchored = true
	acidTop.CanCollide = false
	acidTop.CastShadow = false
	acidTop.Parent = acidModel

	-- Dunklere Tiefenschicht darunter
	local acidDeep = Instance.new("Part")
	acidDeep.Name = "AcidDeep"
	acidDeep.Size = Vector3.new(802, 8, 802)
	acidDeep.Position = Vector3.new(50, -26, 0)
	acidDeep.Color = Color3.fromRGB(15, 90, 10)
	acidDeep.Material = Enum.Material.SmoothPlastic
	acidDeep.Anchored = true
	acidDeep.CanCollide = false
	acidDeep.Parent = acidModel

	-- Tödlicher Säure-Schaden bei Kontakt
	local damageDebounce: { [Player]: number } = {}
	acidTop.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		local player = Players:GetPlayerFromCharacter(char)
		if hum and hum.Health > 0 and player then
			local now = os.clock()
			local lastHit = damageDebounce[player] or 0
			if now - lastHit >= 0.8 then
				damageDebounce[player] = now
				hum:TakeDamage(25) -- 25 Schaden pro Sekunde in der Säure
			end
		end
	end)

	return acidModel
end

-- Erstellt die monumentale Hängebrücke über die Säure (Verbindung zum Portal)
local function createSuspensionBridge(envFolder: Folder): Model
	local bridge = Instance.new("Model")
	bridge.Name = "SuspensionBridge"
	bridge.Parent = envFolder

	local bridgeStart = Vector3.new(75, 0.5, 0) -- Östlicher Rand des Plot-Plateaus
	local bridgeEnd = Vector3.new(135, 0.5, 0)  -- Westlicher Rand der Portal-Insel
	local bridgeWidth = 14
	local spanLength = (bridgeEnd.X - bridgeStart.X)
	local midX = (bridgeStart.X + bridgeEnd.X) / 2

	-- 1. Pylonen-Torbögen an beiden Enden (Massiver dunkler Schieferstein)
	local function buildStoneArch(pos: Vector3, isWest: boolean)
		local archModel = Instance.new("Model")
		archModel.Name = if isWest then "PylonWest" else "PylonEast"
		archModel.Parent = bridge

		local pillarL = Instance.new("Part")
		pillarL.Name = "PillarLeft"
		pillarL.Size = Vector3.new(4, 22, 4)
		pillarL.Position = pos + Vector3.new(0, 10, -bridgeWidth/2 - 1.5)
		pillarL.Color = Color3.fromRGB(48, 54, 60)
		pillarL.Material = Enum.Material.Slate
		pillarL.Anchored = true
		pillarL.CanCollide = true
		pillarL.Parent = archModel

		local pillarR = Instance.new("Part")
		pillarR.Name = "PillarRight"
		pillarR.Size = Vector3.new(4, 22, 4)
		pillarR.Position = pos + Vector3.new(0, 10, bridgeWidth/2 + 1.5)
		pillarR.Color = Color3.fromRGB(48, 54, 60)
		pillarR.Material = Enum.Material.Slate
		pillarR.Anchored = true
		pillarR.CanCollide = true
		pillarR.Parent = archModel

		-- Oberer Querbalken / Torbogen
		local crossBeam = Instance.new("Part")
		crossBeam.Name = "CrossBeam"
		crossBeam.Size = Vector3.new(5, 3.5, bridgeWidth + 8)
		crossBeam.Position = pos + Vector3.new(0, 20.5, 0)
		crossBeam.Color = Color3.fromRGB(38, 43, 48)
		crossBeam.Material = Enum.Material.Slate
		crossBeam.Anchored = true
		crossBeam.CanCollide = true
		crossBeam.Parent = archModel

		-- Feuerschalen auf den Pylonen
		EnvironmentService.CreateBrazier(pos + Vector3.new(0, 22, -bridgeWidth/2 - 1.5), archModel)
		EnvironmentService.CreateBrazier(pos + Vector3.new(0, 22, bridgeWidth/2 + 1.5), archModel)
	end

	buildStoneArch(bridgeStart, true)
	buildStoneArch(bridgeEnd, false)

	-- 1b. SKY-BEACONS: Rote Laser-Lichtsäulen an den Pylonen-Kronen (wie im Pitch-Video!)
	-- Je zwei schmale, weithin sichtbare rote Strahlensäulen je Pylonturm
	local beaconData = {
		{ x = bridgeStart.X, z = -bridgeWidth/2 - 1.5 },
		{ x = bridgeStart.X, z = bridgeWidth/2 + 1.5 },
		{ x = bridgeEnd.X, z = -bridgeWidth/2 - 1.5 },
		{ x = bridgeEnd.X, z = bridgeWidth/2 + 1.5 },
	}
	for i, bd in ipairs(beaconData) do
		-- Beacon-Basis auf dem Pylonen-Kopf
		local beaconBase = Instance.new("Part")
		beaconBase.Name = "SkyBeaconBase_" .. i
		beaconBase.Size = Vector3.new(1.4, 2.5, 1.4)
		beaconBase.Position = Vector3.new(bd.x, 27.5, bd.z)
		beaconBase.Color = Color3.fromRGB(180, 30, 30)
		beaconBase.Material = Enum.Material.Neon
		beaconBase.Anchored = true
		beaconBase.CanCollide = false
		beaconBase.CastShadow = false
		beaconBase.Parent = bridge
		-- Rotes Basislicht
		local baseLight = Instance.new("PointLight")
		baseLight.Color = Color3.fromRGB(255, 30, 30)
		baseLight.Range = 30
		baseLight.Brightness = 3.5
		baseLight.Parent = beaconBase

		-- Vertikale Laser-Säule: langer schmaler Zylinder in den Nachthimmel
		local beamHeight = 350
		local beaconBeam = Instance.new("Part")
		beaconBeam.Name = "SkyBeaconLaser_" .. i
		beaconBeam.Shape = Enum.PartType.Cylinder
		beaconBeam.Size = Vector3.new(beamHeight, 2.2, 2.2)
		beaconBeam.CFrame = CFrame.new(
			Vector3.new(bd.x, 28 + beamHeight / 2, bd.z)
		) * CFrame.Angles(0, 0, math.rad(90))
		beaconBeam.Color = Color3.fromRGB(255, 20, 20)
		beaconBeam.Material = Enum.Material.Neon
		beaconBeam.Transparency = 0.35
		beaconBeam.Anchored = true
		beaconBeam.CanCollide = false
		beaconBeam.CastShadow = false
		beaconBeam.Parent = bridge
	end

	-- 2. Brückendeck: Holzbohlen / Planken mit Fugen (Säure leuchtet hindurch)
	local plankLength = 2.2
	local plankCount = math.floor(spanLength / (plankLength + 0.4))
	local stepX = spanLength / plankCount

	for i = 0, plankCount do
		local currentX = bridgeStart.X + (i * stepX)
		-- Leichter natürlicher Hängebrücken-Durchhang in der Mitte
		local sagY = -math.sin((i / plankCount) * math.pi) * 2.2

		local plank = Instance.new("Part")
		plank.Name = "Plank_" .. i
		plank.Size = Vector3.new(plankLength, 1.0, bridgeWidth)
		plank.Position = Vector3.new(currentX, 0.2 + sagY, 0)
		plank.Color = Color3.fromRGB(68, 60, 52) -- Verwittertes Holz
		plank.Material = Enum.Material.WoodPlanks
		plank.Anchored = true
		plank.CanCollide = true
		plank.Parent = bridge

		-- Vertikale Halteseile alle 2 Planken
		if i % 2 == 0 then
			for _, zSide in { -bridgeWidth/2 + 0.5, bridgeWidth/2 - 0.5 } do
				local rope = Instance.new("Part")
				rope.Name = "SuspensionRope"
				rope.Size = Vector3.new(0.3, 4.2, 0.3)
				rope.Position = Vector3.new(currentX, 2.3 + sagY, zSide)
				rope.Color = Color3.fromRGB(30, 32, 35)
				rope.Material = Enum.Material.CorrodedMetal
				rope.Anchored = true
				rope.CanCollide = false
				rope.Parent = bridge
			end
		end
	end

	-- 3. Durchgehende Handläufe / Spannseile (Links & Rechts)
	for _, zSide in { -bridgeWidth/2 + 0.5, bridgeWidth/2 - 0.5 } do
		local handrail = Instance.new("Part")
		handrail.Name = "Handrail"
		handrail.Size = Vector3.new(spanLength, 0.6, 0.6)
		handrail.Position = Vector3.new(midX, 4.0 - 1.1, zSide)
		handrail.Color = Color3.fromRGB(40, 44, 48)
		handrail.Material = Enum.Material.CorrodedMetal
		handrail.Anchored = true
		handrail.CanCollide = true
		handrail.Parent = bridge
	end

	return bridge
end

-- Erstellt die schwebende Felseninsel für das Dimensions-Portal
local function createPortalIsland(envFolder: Folder): Model
	local islandModel = Instance.new("Model")
	islandModel.Name = "PortalIsland"
	islandModel.Parent = envFolder

	-- Felsbasis unter der Portal-Plattform
	local base = Instance.new("Part")
	base.Name = "PortalIslandRock"
	base.Size = Vector3.new(42, 8, 42)
	base.Position = Vector3.new(154, -4.0, 0)
	base.Color = Color3.fromRGB(38, 42, 46)
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.CanCollide = true
	base.Parent = islandModel

	-- Pflasterstein-Vorplatz
	local plaza = Instance.new("Part")
	plaza.Name = "PortalIslandPlaza"
	plaza.Size = Vector3.new(42, 0.8, 42)
	plaza.Position = Vector3.new(154, 0.4, 0)
	plaza.Color = Color3.fromRGB(52, 58, 66)
	plaza.Material = Enum.Material.Cobblestone
	plaza.Anchored = true
	plaza.CanCollide = true
	plaza.Parent = islandModel

	-- Fackeln an den 4 Ecken des Vorplatzes
	local cornerOffsets = {
		Vector3.new(138, 0.4, -18),
		Vector3.new(138, 0.4, 18),
		Vector3.new(170, 0.4, -18),
		Vector3.new(170, 0.4, 18),
	}
	for _, cPos in cornerOffsets do
		EnvironmentService.CreateBrazier(cPos, islandModel)
	end

	return islandModel
end

-- Richtet die Fackeln und Monolithen in der Wald-Golem Boss-Arena ein
local function setupBossArenaAtmosphere(envFolder: Folder)
	local arena = Workspace:FindFirstChild("Arena_WaldRuinen")
	if not arena then
		return
	end

	-- Altes Deko-Setup aufräumen
	local oldDeko = arena:FindFirstChild("ArenaAtmosphere")
	if oldDeko then
		oldDeko:Destroy()
	end

	local deko = Instance.new("Model")
	deko.Name = "ArenaAtmosphere"
	deko.Parent = arena

	local ARENA_CENTER = Vector3.new(0, 500, 25000)
	local ARENA_RADIUS = 54

	-- 8 brennende Feuerschalen entlang des inneren Ringes der Boss-Arena
	local brazierCount = 8
	for i = 1, brazierCount do
		local angle = (i / brazierCount) * math.pi * 2
		local x = math.cos(angle) * ARENA_RADIUS
		local z = math.sin(angle) * ARENA_RADIUS
		EnvironmentService.CreateBrazier(ARENA_CENTER + Vector3.new(x, 1.5, z), deko)
	end
end

-- Haupt-Initialisierung der gesamten Video-Welt
function EnvironmentService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- 0. Standard Roblox Studio Baseplate entfernen (verhindert Z-Fighting & legt den Säure-Abgrund frei)
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and string.lower(child.Name):find("baseplate") then
			child:Destroy()
		end
	end

	-- Alle Nebel-, Dunst- und Überstrahleffekte aus Lighting & Terrain restlos aufräumen
	local Lighting = game:GetService("Lighting")
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child.Name:find("Cinematic") then
			child:Destroy()
		end
	end
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0

	local terrain = Workspace.Terrain
	if terrain then
		local clouds = terrain:FindFirstChildOfClass("Clouds")
		if clouds then
			clouds:Destroy()
		end
	end

	-- Altes Environment & lose Säureseen aufräumen
	local existingEnv = Workspace:FindFirstChild("Environment")
	if existingEnv then
		existingEnv:Destroy()
	end
	local looseLake = Workspace:FindFirstChild("ToxicAcidLake")
	if looseLake then
		looseLake:Destroy()
	end

	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = Workspace

	-- 2. Haupt-Plateau unter den Plots mit Allee
	createMainPlateau(envFolder)

	-- 3. Schwebende Insel für das Portal
	createPortalIsland(envFolder)

	-- 4. Giftgrüner Säure-Abgrund unter allen Inseln
	createToxicAcidLake(envFolder)

	-- 5. Monumentale Hängebrücke zwischen Plots und Portal
	createSuspensionBridge(envFolder)

	-- 6. Fackeln in der Boss-Arena
	setupBossArenaAtmosphere(envFolder)

	-- 7. Waffen-Schmiede & Shop auf der Haupt-Allee
	createBlacksmithShop(envFolder)

	print("[EnvironmentService] Welt erfolgreich aufgebaut: Säure-Abgrund, Hängebrücke, Schmiede & Fackeln aktiv.")
end

-- Für die Studio-Befehlszeile (Baut die Welt direkt im Edit-Modus auf)
function EnvironmentService.BuildInStudio()
	isInitialized = false
	EnvironmentService.Init()
end

return EnvironmentService
