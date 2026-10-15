--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local BossConfigModule = ConfigFolder:WaitForChild("BossConfig") :: ModuleScript
local BossConfig = require(BossConfigModule)
local ItemConfigModule = ConfigFolder:WaitForChild("ItemConfig") :: ModuleScript
local ItemConfig = require(ItemConfigModule)
local AudioConfigModule = ConfigFolder:WaitForChild("AudioConfig") :: ModuleScript
local AudioConfig = require(AudioConfigModule)

local EventsFolder = Shared:WaitForChild("Events")

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

-- RemoteEvents initialisieren
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

local AttackIntentEvent = getOrCreateRemoteEvent(EventsFolder, "AttackIntent")
local BossUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "BossUpdated")
local BossTelegraphEvent = getOrCreateRemoteEvent(EventsFolder, "BossTelegraphStarted")
local NotificationEvent = getOrCreateRemoteEvent(EventsFolder, "ShowNotification")
local GoldUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "GoldUpdated")
local BossDefeatedEvent = getOrCreateRemoteEvent(EventsFolder, "BossDefeated")
local EntityDamagedEvent = getOrCreateRemoteEvent(EventsFolder, "EntityDamaged")
local GoldGainedEvent = getOrCreateRemoteEvent(EventsFolder, "GoldGained")

local BossService = {}

-- Combat-Juice-Konstanten (Phase 2)
local CRIT_CHANCE = 0.2 -- 20% Chance auf einen kritischen Treffer
local CRIT_MULTIPLIER = 1.75 -- Kritischer Treffer verursacht 1.75x Schaden
local DAMAGE_FEEDBACK_RADIUS = 250 -- Nur Spieler in diesem Umkreis erhalten Schadens-Feedback (Zahlen, Funken, Sounds)

local ARENA_CENTER = Vector3.new(0, 500, 25000)
local ARENA_RADIUS = 60

BossService.ARENA_CENTER = ARENA_CENTER
BossService.ARENA_RADIUS = ARENA_RADIUS
BossService.ARENA_SPAWN = ARENA_CENTER + Vector3.new(0, 3.5, 38)
BossService.ARENA_PORTAL_POS = ARENA_CENTER + Vector3.new(0, 0.5, 48)

local currentBossModel: Model? = nil
local currentBossHumanoid: Humanoid? = nil
local currentBossMover: BodyVelocity? = nil
local currentBossRotator: BodyGyro? = nil
local isBossAlive = false
local isBossAttacking = false
local isBossDying = false
local isInitialized = false
local lastBossAttackTime = 0

local playerAttackCooldowns: { [Player]: number } = {}

-- Erzeugt ein Standard-Part
local function createPart(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = pos
	part.Color = color
	part.Material = mat or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = if collide ~= nil then collide else true
	part.Parent = parent
	return part
end

-- Erstellt die Boss-Arena in den Wald-Ruinen als vollständig abgekapselte Kammer (25.000 Studs entfernt)
local function ensureArenaExists(): Folder
	local existing = Workspace:FindFirstChild("Arena_WaldRuinen")
	if existing then
		existing:Destroy()
	end

	local arena = Instance.new("Folder")
	arena.Name = "Arena_WaldRuinen"
	arena.Parent = Workspace

	-- 1. Große kreisförmige/oktogonale Arena-Bodenplatte
	local floor = createPart(arena, "ArenaFloor", Vector3.new(130, 3, 130), ARENA_CENTER, Color3.fromRGB(45, 55, 45), Enum.Material.Slate)

	-- Äußerer Zierring / Tempel-Fundament
	createPart(arena, "ArenaOuterRing", Vector3.new(136, 1.5, 136), ARENA_CENTER - Vector3.new(0, 1, 0), Color3.fromRGB(35, 42, 35), Enum.Material.Cobblestone)

	-- 2. Vollständig geschlossene antike Ruinen-Außenmauer (16 Segmente, Höhe 42 Studs!)
	local wallSegmentCount = 16
	local wallWidth = ((2 * math.pi * ARENA_RADIUS) / wallSegmentCount) + 3
	local wallHeight = 42
	local wallThickness = 5

	for i = 1, wallSegmentCount do
		local angle = (i / wallSegmentCount) * math.pi * 2
		local x = math.cos(angle) * ARENA_RADIUS
		local z = math.sin(angle) * ARENA_RADIUS
		local wallPos = ARENA_CENTER + Vector3.new(x, wallHeight / 2, z)

		local wall = Instance.new("Part")
		wall.Name = "RuinsWall_" .. i
		wall.Size = Vector3.new(wallWidth, wallHeight, wallThickness)
		wall.CFrame = CFrame.new(wallPos, ARENA_CENTER + Vector3.new(0, wallHeight / 2, 0))
		wall.Color = if i % 2 == 0 then Color3.fromRGB(55, 65, 55) else Color3.fromRGB(60, 70, 60)
		wall.Material = Enum.Material.Cobblestone
		wall.Anchored = true
		wall.CanCollide = true
		wall.Parent = arena

		-- Moosiger Sims / Mauerkrone
		local rim = Instance.new("Part")
		rim.Name = "RuinsRim_" .. i
		rim.Size = Vector3.new(wallWidth + 1, 3, wallThickness + 2)
		rim.CFrame = CFrame.new(wallPos + Vector3.new(0, wallHeight / 2 + 1.5, 0), ARENA_CENTER + Vector3.new(0, wallHeight / 2 + 1.5, 0))
		rim.Color = Color3.fromRGB(40, 75, 45)
		rim.Material = Enum.Material.Grass
		rim.Anchored = true
		rim.CanCollide = true
		rim.Parent = arena
	end

	-- 3. Begrenzungsmauer & antike Steinsäulen mit leuchtenden Smaragd-Runen & Fackellicht
	local pillarCount = 8
	for i = 1, pillarCount do
		local angle = (i / pillarCount) * math.pi * 2
		local x = math.cos(angle) * (ARENA_RADIUS - 6)
		local z = math.sin(angle) * (ARENA_RADIUS - 6)
		local pillarPos = ARENA_CENTER + Vector3.new(x, 15, z)

		local pillar = createPart(arena, "Pillar_" .. i, Vector3.new(7, 30, 7), pillarPos, Color3.fromRGB(65, 75, 65), Enum.Material.Cobblestone)
		pillar.TopSurface = Enum.SurfaceType.Smooth

		-- Leuchtende Runen auf Säulen
		local rune = createPart(arena, "Rune_" .. i, Vector3.new(7.4, 4, 7.4), pillarPos + Vector3.new(0, 4, 0), Color3.fromRGB(46, 204, 113), Enum.Material.Neon, false)

		-- Atmosphärisches Smaragd-Licht
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(46, 204, 113)
		light.Range = 24
		light.Brightness = 2.2
		light.Parent = rune
	end

	-- 4. Unsichtbare Decken-Barriere (verhindert Ausbrechen ins Void)
	local ceiling = createPart(arena, "ArenaCeiling", Vector3.new(140, 2, 140), ARENA_CENTER + Vector3.new(0, wallHeight + 1, 0), Color3.fromRGB(0, 0, 0), nil, true)
	ceiling.Transparency = 1

	return arena
end

-- Sendet ein schlankes EntityDamaged-RemoteEvent an alle Spieler in der Nähe des Einschlags.
-- Der Client erzeugt daraus juicige, federnde Schadenszahlen, Funken & Treffersounds (Null-Latenz-Design).
--   targetKind: "Boss" | "Player" | "Minion" - bestimmt auf dem Client den Material-Sound (Stein/Fleisch)
--   victim:     optionaler Spieler, der den Schaden EINGESTECKT hat (erhält alarmierend rote Zahlen)
local function broadcastDamageFeedback(position: Vector3, damage: number, isCrit: boolean, targetKind: string, victim: Player?)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not root then
			continue
		end
		if (root.Position - position).Magnitude > DAMAGE_FEEDBACK_RADIUS then
			continue
		end

		local isLocalPlayerVictim = (victim ~= nil and player == victim)
		EntityDamagedEvent:FireClient(player, position, damage, isCrit, isLocalPlayerVictim, targetKind)
	end
end

-- Öffentliche API (für andere Services wie DefenseService): Treffer-Feedback an nahe Spieler replizieren
function BossService.BroadcastDamageFeedback(position: Vector3, damage: number, isCrit: boolean, targetKind: string, victim: Player?)
	broadcastDamageFeedback(position, damage, isCrit, targetKind, victim)
end

-- Aktualisiert den Boss-Lebensbalken
local function updateBossHealthUI(health: number, maxHealth: number)
	if not currentBossModel then
		return
	end

	local head = currentBossModel:FindFirstChild("Head") :: BasePart?
	if head then
		local billboard = head:FindFirstChild("BossHealthBar") :: BillboardGui?
		if billboard then
			local barFill = billboard:FindFirstChild("BarFill", true) :: Frame?
			local hpLabel = billboard:FindFirstChild("HPText", true) :: TextLabel?

			local pct = math.clamp(health / maxHealth, 0, 1)
			if barFill then
				barFill.Size = UDim2.new(pct, 0, 1, 0)
			end
			if hpLabel then
				hpLabel.Text = string.format("%d / %d HP", math.max(0, math.floor(health)), maxHealth)
			end
		end
	end

	BossUpdatedEvent:FireAllClients("Wald-Golem", health, maxHealth, isBossAlive)
end

-- Erstellt das Golem-Modell und den Overhead-Health-Balken (Pitch-Video-Fidelity)
local function spawnGolemModel(): Model
	local model = Instance.new("Model")
	model.Name = "ForestGolem"
	model.Parent = Workspace

	-- ArenaFloor liegt bei ARENA_CENTER.Y = 500, Dicke 3 -> Oberkante ArenaFloor ist exakt bei Y = 501.5
	-- HumanoidRootPart: Schwebt sauber bei HipHeight 5.0 (Center Y = 501.5 + 5.0 + (10/2) = 511.5)
	local root = createPart(model, "HumanoidRootPart", Vector3.new(6, 10, 6), ARENA_CENTER + Vector3.new(0, 11.5, 0), Color3.fromRGB(0, 0, 0), nil, false)
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	model.PrimaryPart = root

	-- Torso (Massiver Felsen mit Steinadern)
	local torso = createPart(model, "Torso", Vector3.new(9, 11, 7), ARENA_CENTER + Vector3.new(0, 12.5, 0), Color3.fromRGB(75, 80, 70), Enum.Material.Slate, false)
	-- Steinadern auf der Brust (dunklere Linien)
	local veinH = createPart(model, "VeinH", Vector3.new(7, 0.35, 0.35), ARENA_CENTER + Vector3.new(0, 14.3, -3.65), Color3.fromRGB(38, 42, 36), Enum.Material.SmoothPlastic, false)
	local veinV = createPart(model, "VeinV", Vector3.new(0.35, 5, 0.35), ARENA_CENTER + Vector3.new(0, 12.5, -3.65), Color3.fromRGB(38, 42, 36), Enum.Material.SmoothPlastic, false)

	-- Leuchtender SMARAGD-Kern auf der Brust (Schwachstelle, pulsierendes Grün)
	local corePart = createPart(model, "Core", Vector3.new(2.8, 2.8, 1.8), ARENA_CENTER + Vector3.new(0, 13.5, -3.65), Color3.fromRGB(46, 204, 113), Enum.Material.Neon, false)
	local coreAtt = Instance.new("Attachment")
	coreAtt.Parent = corePart
	local corePulse = Instance.new("ParticleEmitter")
	corePulse.Rate = 12
	corePulse.Lifetime = NumberRange.new(1.2, 2.0)
	corePulse.Speed = NumberRange.new(1.5, 3.0)
	corePulse.SpreadAngle = Vector2.new(180, 180)
	corePulse.Size = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }
	corePulse.Color = ColorSequence.new(Color3.fromRGB(46, 230, 130))
	corePulse.LightEmission = 1.0
	corePulse.Parent = coreAtt

	-- Kopf (massiver Felsblock mit markanten Wangenknochen)
	local head = createPart(model, "Head", Vector3.new(5.5, 4.5, 5), ARENA_CENTER + Vector3.new(0, 19.5, 0), Color3.fromRGB(85, 90, 80), Enum.Material.Slate, false)
	-- Wangenknochen (Felsbrocken an den Seiten des Kopfes)
	local cheekL = createPart(model, "CheekL", Vector3.new(1.8, 1.4, 1.4), ARENA_CENTER + Vector3.new(-2.6, 19.1, -1.5), Color3.fromRGB(65, 70, 62), Enum.Material.Cobblestone, false)
	local cheekR = createPart(model, "CheekR", Vector3.new(1.8, 1.4, 1.4), ARENA_CENTER + Vector3.new(2.6, 19.1, -1.5), Color3.fromRGB(65, 70, 62), Enum.Material.Cobblestone, false)

	-- LEUCHTEND GELBE AUGEN (wie im Pitch-Video!)
	local eyeL = createPart(model, "EyeL", Vector3.new(1.1, 0.9, 0.7), ARENA_CENTER + Vector3.new(-1.5, 19.9, -2.6), Color3.fromRGB(255, 235, 40), Enum.Material.Neon, false)
	local eyeR = createPart(model, "EyeR", Vector3.new(1.1, 0.9, 0.7), ARENA_CENTER + Vector3.new(1.5, 19.9, -2.6), Color3.fromRGB(255, 235, 40), Enum.Material.Neon, false)
	-- Gelbe Augenlicht-Emitter
	local eyeLLight = Instance.new("PointLight")
	eyeLLight.Color = Color3.fromRGB(255, 220, 0)
	eyeLLight.Range = 20
	eyeLLight.Brightness = 2.5
	eyeLLight.Parent = eyeL
	local eyeRLight = Instance.new("PointLight")
	eyeRLight.Color = Color3.fromRGB(255, 220, 0)
	eyeRLight.Range = 20
	eyeRLight.Brightness = 2.5
	eyeRLight.Parent = eyeR

	-- FELSEN-ZÄHNE / STOSSZÄHNE am Maul
	local teethPositions = {
		Vector3.new(-1.8, 17.5, -2.7),
		Vector3.new(-0.6, 17.2, -2.75),
		Vector3.new(0.6, 17.2, -2.75),
		Vector3.new(1.8, 17.5, -2.7),
	}
	for i, tPos in ipairs(teethPositions) do
		local tooth = createPart(model, "Tooth_" .. i, Vector3.new(0.7, 1.2, 0.5), ARENA_CENTER + tPos, Color3.fromRGB(220, 215, 195), Enum.Material.SmoothPlastic, false)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = tooth
	end

	-- Massive FELSBLOCK-FÄUSTE an den Armen
	-- Linker Arm + Faust
	local armL = createPart(model, "ArmL", Vector3.new(4, 10, 4), ARENA_CENTER + Vector3.new(-7, 13.0, 0), Color3.fromRGB(72, 78, 68), Enum.Material.Cobblestone, false)
	local fistL = createPart(model, "FistL", Vector3.new(5, 5, 5), ARENA_CENTER + Vector3.new(-7.5, 7.0, 0), Color3.fromRGB(65, 70, 62), Enum.Material.Slate, false)
	-- Knöchelrisse auf der Faust
	local knuckleL = createPart(model, "KnuckleL", Vector3.new(4.5, 0.4, 0.4), ARENA_CENTER + Vector3.new(-7.5, 9.5, -2.55), Color3.fromRGB(42, 46, 40), Enum.Material.SmoothPlastic, false)
	-- Rechter Arm + Faust
	local armR = createPart(model, "ArmR", Vector3.new(4, 10, 4), ARENA_CENTER + Vector3.new(7, 13.0, 0), Color3.fromRGB(72, 78, 68), Enum.Material.Cobblestone, false)
	local fistR = createPart(model, "FistR", Vector3.new(5, 5, 5), ARENA_CENTER + Vector3.new(7.5, 7.0, 0), Color3.fromRGB(65, 70, 62), Enum.Material.Slate, false)
	local knuckleR = createPart(model, "KnuckleR", Vector3.new(4.5, 0.4, 0.4), ARENA_CENTER + Vector3.new(7.5, 9.5, -2.55), Color3.fromRGB(42, 46, 40), Enum.Material.SmoothPlastic, false)

	-- MOOS-SCHULTERPOLSTER (Grass-Material in sattem Waldgrün, wie im Video!)
	local mossOffsets = {
		Vector3.new(-5.5, 17.5, 0),   -- linke Schulter
		Vector3.new(5.5, 17.5, 0),    -- rechte Schulter
		Vector3.new(-4.5, 18.1, 1.5), -- links hinten
		Vector3.new(4.5, 18.1, 1.5),  -- rechts hinten
		Vector3.new(0, 18.7, 2.5),    -- Nacken-Moos
	}
	for i, mOff in ipairs(mossOffsets) do
		local moss = createPart(model, "Moss_" .. i, Vector3.new(2.8, 1.2, 2.8), ARENA_CENTER + mOff, Color3.fromRGB(55, 120, 45), Enum.Material.Grass, false)
		moss.CastShadow = false
	end
	-- Moos-Klumpen auf dem Kopf
	local mossHead = createPart(model, "MossHead", Vector3.new(4.5, 1.0, 4.5), ARENA_CENTER + Vector3.new(0, 22.3, 0), Color3.fromRGB(50, 110, 38), Enum.Material.Grass, false)
	mossHead.CastShadow = false

	-- Beine (massiver, gedrungener Block-Stil - Unterkante sitzt auf Y = 501.5)
	local legL = createPart(model, "LegL", Vector3.new(3.8, 7, 3.8), ARENA_CENTER + Vector3.new(-2.8, 5.0, 0), Color3.fromRGB(68, 72, 62), Enum.Material.Cobblestone, true)
	local legR = createPart(model, "LegR", Vector3.new(3.8, 7, 3.8), ARENA_CENTER + Vector3.new(2.8, 5.0, 0), Color3.fromRGB(68, 72, 62), Enum.Material.Cobblestone, true)

	-- Rutsch-Eigenschaften auf den Fuß-Kanten (verhindert Reibungs-Verkeilen am Boden)
	local slickProps = PhysicalProperties.new(0.7, 0.02, 0, 1, 1)
	legL.CustomPhysicalProperties = slickProps
	legR.CustomPhysicalProperties = slickProps

	-- Schweißungen (Welds): Beine, Torso & Kopf solide für echte physische Präsenz
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
			part.Anchored = false
			part.Massless = true
			if part == legL or part == legR or part == torso or part == head then
				part.CanCollide = true
			else
				part.CanCollide = false
			end
		end
	end
	root.Anchored = false
	root.CanCollide = false

	-- Strikte Server-Netzwerk-Autorität erzwingen (verhindert Client-Physik-Übernahme/Lag)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- Unaufhaltsame, flüssige Fortbewegung & Drehung via BodyVelocity & BodyGyro
	local mover = Instance.new("BodyVelocity")
	mover.Name = "BossMover"
	mover.MaxForce = Vector3.new(2e6, 0, 2e6) -- Nur horizontal! Y = 0 lässt Schwerkraft natürlich auf die Beine wirken
	mover.Velocity = Vector3.zero
	mover.Parent = root

	local rotator = Instance.new("BodyGyro")
	rotator.Name = "BossRotator"
	rotator.MaxTorque = Vector3.new(4e6, 4e6, 4e6) -- Boss permanent aufrecht halten & flüssig drehen
	rotator.CFrame = root.CFrame
	rotator.D = 120
	rotator.P = 4000
	rotator.Parent = root

	currentBossMover = mover
	currentBossRotator = rotator

	-- Humanoid für Lebensleiste & Schadensverwaltung
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = BossConfig.ForestGolemCore.MaxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 12
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
	humanoid.Parent = model

	-- Overhead-Boss-Health-Bar (nur aus der Nähe sichtbar, kein AlwaysOnTop durch Wände)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossHealthBar"
	billboard.Size = UDim2.new(0, 180, 0, 48)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 75
	billboard.Parent = head

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, 0, 0, 16)
	barBg.Position = UDim2.new(0, 0, 0, 24)
	barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	barBg.BorderSizePixel = 0
	barBg.Parent = billboard

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = barFill

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "BossTitle"
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "👹 Wald-Golem (Tier 1)"
	nameLabel.TextColor3 = Color3.fromRGB(255, 230, 100)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 14
	nameLabel.Parent = billboard

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2.4
	nameStroke.Parent = nameLabel

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPText"
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = string.format("%d / %d HP", humanoid.Health, humanoid.MaxHealth)
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.Font = Enum.Font.GothamBlack
	hpLabel.TextSize = 11
	hpLabel.Parent = barBg

	local hpStroke = Instance.new("UIStroke")
	hpStroke.Color = Color3.fromRGB(0, 0, 0)
	hpStroke.Thickness = 2.0
	hpStroke.Parent = hpLabel

	currentBossModel = model
	currentBossHumanoid = humanoid
	isBossAlive = true
	isBossDying = false

	-- Tiefes Monsterbrüllen beim Erwachen des Wald-Golems (3D mit Distanzdämpfung)
	AudioConfig.PlayTag("BossRoar", head)

	return model
end

-- Liefert die Anzahl lebender Spieler in der Boss-Arena
local function getPlayersInArenaCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid") :: Humanoid?
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				local dist = (root.Position - ARENA_CENTER).Magnitude
				if dist <= (ARENA_RADIUS + 25) then
					count += 1
				end
			end
		end
	end
	return count
end

-- Despawnt das Boss-Modell sauber (z. B. wenn alle Spieler die Arena verlassen)
local function despawnGolem()
	if currentBossMover then
		currentBossMover:Destroy()
		currentBossMover = nil
	end
	if currentBossRotator then
		currentBossRotator:Destroy()
		currentBossRotator = nil
	end
	if currentBossModel then
		currentBossModel:Destroy()
		currentBossModel = nil
		currentBossHumanoid = nil
	end
	isBossAlive = false
	isBossAttacking = false
	isBossDying = false
	BossUpdatedEvent:FireAllClients("Wald-Golem", 0, BossConfig.ForestGolemCore.MaxHealth, false)
end

-- Öffentliche API: Wird von PortalService aufgerufen, wenn ein Spieler die Arena durch das Portal betritt
function BossService.OnPlayerEnteredArena(player: Player)
	print(string.format("[BossService] %s hat die Boss-Arena betreten.", player.Name))

	-- Falls der Boss noch nicht existiert und nicht im Respawn-Timer steckt -> Spawnen!
	if not isBossAlive and not isBossDying then
		spawnGolemModel()
		updateBossHealthUI(BossConfig.ForestGolemCore.MaxHealth, BossConfig.ForestGolemCore.MaxHealth)
		NotificationEvent:FireClient(player, "⚠️ Der Wald-Golem erwacht aus den Ruinen!", false)
	elseif isBossAlive and currentBossHumanoid then
		-- Aktuellen Boss-Stand sofort gezielt an den beitretenden Spieler senden
		BossUpdatedEvent:FireClient(player, "Wald-Golem", currentBossHumanoid.Health, currentBossHumanoid.MaxHealth, true)
	end
end

-- Öffentliche API: Wird von PortalService aufgerufen, wenn ein Spieler die Arena durch das Portal verlässt
function BossService.OnPlayerLeftArena(player: Player)
	print(string.format("[BossService] %s hat die Boss-Arena verlassen.", player.Name))

	task.defer(function()
		local remaining = getPlayersInArenaCount()
		if remaining == 0 and isBossAlive and not isBossDying then
			print("[BossService] Keine Spieler mehr in der Arena - Wald-Golem despawnt sofort.")
			despawnGolem()
		end
	end)
end

-- Boss-Tod und Belohnungsvergabe
local function handleBossDefeated(killer: Player?)
	if not isBossAlive then
		return
	end
	isBossAlive = false
	isBossDying = true

	print("[BossService] Wald-Golem besiegt!")

	if currentBossMover then
		currentBossMover.Velocity = Vector3.zero
		currentBossMover:Destroy()
		currentBossMover = nil
	end
	if currentBossRotator then
		currentBossRotator:Destroy()
		currentBossRotator = nil
	end

	if currentBossModel and currentBossModel.PrimaryPart then
		-- Partikel / Einsturz
		for _, part in currentBossModel:GetChildren() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
	end

	-- Belohnung für den Bezwinger
	local goldReward = BossConfig.ForestGolemCore.GoldReward
	if killer then
		DataManager.AddGold(killer, goldReward)
		DataManager.AddCore(killer, "ForestGolemCore")

		local killerData = DataManager.Get(killer)
		if killerData then
			GoldUpdatedEvent:FireClient(killer, killerData.Gold)
		end

		-- 🎉 Celebration-Event für das +Gold-Popup auf dem Client (wie im Pitch-Video)
		BossDefeatedEvent:FireClient(killer, "ForestGolemCore", goldReward)

		-- Floating "+XX Gold"-Popup über dem Charakter + Münzklingeln & Goldflash (Phase 2)
		GoldGainedEvent:FireClient(killer, goldReward, "Boss")

		NotificationEvent:FireClient(
			killer,
			string.format("🏆 Wald-Golem besiegt! +%d Gold & 'Wald-Golem Kern' erhalten!", goldReward),
			false
		)
	end

	BossUpdatedEvent:FireAllClients("Wald-Golem", 0, BossConfig.ForestGolemCore.MaxHealth, false)

	-- Modell nach 2 Sekunden entfernen
	task.delay(2, function()
		if currentBossModel then
			currentBossModel:Destroy()
			currentBossModel = nil
			currentBossHumanoid = nil
		end
	end)

	-- Respawn-Timer: Nur respawnen, wenn noch Spieler in der Arena sind!
	task.delay(BossConfig.ForestGolemCore.RespawnTime, function()
		isBossDying = false
		if getPlayersInArenaCount() > 0 then
			print("[BossService] Spieler in der Arena - Wald-Golem respawnt...")
			spawnGolemModel()
			updateBossHealthUI(BossConfig.ForestGolemCore.MaxHealth, BossConfig.ForestGolemCore.MaxHealth)
		else
			print("[BossService] Keine Spieler mehr in der Arena - Respawn pausiert bis zum nächsten Portal-Eintritt.")
		end
	end)
end

-- Führt den telegrafierten Flächenangriff aus (Ground Slam)
local function executeTelegraphedAttack(targetPos: Vector3)
	isBossAttacking = true

	-- Boss hält sofort an für den Schlag
	if currentBossMover then
		currentBossMover.Velocity = Vector3.zero
	end

	local config = BossConfig.ForestGolemCore
	local radius = config.TelegraphRadius
	local duration = config.TelegraphDuration

	-- 1. Rote Indikator-Fläche am Boden erzeugen (sauber über der Bodenplatte bei Y = 501.58 platziert)
	local indicatorY = ARENA_CENTER.Y + 1.58
	local telegraph = Instance.new("Part")
	telegraph.Name = "TelegraphIndicator"
	telegraph.Shape = Enum.PartType.Cylinder
	telegraph.Size = Vector3.new(0.3, radius * 2, radius * 2)
	telegraph.CFrame = CFrame.new(Vector3.new(targetPos.X, indicatorY, targetPos.Z)) * CFrame.Angles(0, 0, math.rad(90))
	telegraph.Color = Color3.fromRGB(231, 76, 60)
	telegraph.Material = Enum.Material.Neon
	telegraph.Transparency = 0.45
	telegraph.Anchored = true
	telegraph.CanCollide = false
	telegraph.Parent = Workspace

	BossTelegraphEvent:FireAllClients(targetPos, radius, duration)

	-- Der Golem brüllt seinen Slam an (3D-Audio, bevor der Schlag einschlägt)
	local telegraphHead = if currentBossModel then currentBossModel:FindFirstChild("Head") :: BasePart? else nil
	if telegraphHead then
		AudioConfig.PlaySound(AudioConfig.Sounds.BossRoar.Id, 0.85, 0.14, telegraphHead)
	end

	-- Telegraph-Dauer abwarten (Zeit zum Ausweichen per Dash!)
	task.wait(duration)

	-- 2. Impact / Slam!
	if telegraph then
		telegraph:Destroy()
	end

	-- Shockwave-Optik
	local shockwave = Instance.new("Part")
	shockwave.Shape = Enum.PartType.Ball
	shockwave.Size = Vector3.new(2, 2, 2)
	shockwave.Position = Vector3.new(targetPos.X, ARENA_CENTER.Y + 2.0, targetPos.Z)
	shockwave.Color = Color3.fromRGB(241, 196, 15)
	shockwave.Material = Enum.Material.Neon
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.Parent = Workspace

	-- Wuchtiger Einschlag-Sound über einen langlebigeren Audio-Anker (überlebt die kurze Shockwave-Optik)
	local audioAnchor = Instance.new("Part")
	audioAnchor.Name = "SlamAudioAnchor"
	audioAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	audioAnchor.Position = shockwave.Position
	audioAnchor.Transparency = 1
	audioAnchor.Anchored = true
	audioAnchor.CanCollide = false
	audioAnchor.CanQuery = false
	audioAnchor.CanTouch = false
	audioAnchor.CastShadow = false
	audioAnchor.Parent = Workspace
	local slamSound = AudioConfig.PlayTag("BossSlamImpact", audioAnchor)
	slamSound.Ended:Once(function()
		audioAnchor:Destroy()
	end)
	Debris:AddItem(audioAnchor, 5) -- Sicherheitsnetz, falls das Asset nicht (rechtzeitig) lädt

	local shockTween = TweenService:Create(
		shockwave,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius * 2, 4, radius * 2), Transparency = 1 }
	)
	shockTween:Play()
	Debris:AddItem(shockwave, 0.45)

	-- 3. Server-autoritärer Schaden an allen Spielern im Radius
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid") :: Humanoid?
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				local dist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude
				if dist <= radius then
					hum:TakeDamage(config.AttackDamage)
					-- Eingesteckter Schaden: Alarmierend rote Schadenszahl über dem Getroffenen
					broadcastDamageFeedback(root.Position, config.AttackDamage, false, "Player", player)
					NotificationEvent:FireClient(player, string.format("💥 Vom Bodenschlag getroffen! (-%d HP)", config.AttackDamage), true)
				end
			end
		end
	end

	task.wait(0.8) -- Erholungsphase nach dem Schlag
	isBossAttacking = false
end

-- Boss-KI-Schleife (Server-autoritär via BodyVelocity & BodyGyro)
local function startBossAILoop()
	task.spawn(function()
		while true do
			task.wait(0.12)

			-- Prüfe, ob sich noch Spieler in der Arena aufhalten
			local playersInArena = getPlayersInArenaCount()
			if playersInArena == 0 then
				if isBossAlive and not isBossDying then
					print("[BossService] Keine Spieler in der Arena - Wald-Golem despawnt sofort.")
					despawnGolem()
				end
				continue
			end

			-- Falls Spieler in der Arena sind, aber der Boss noch nicht lebt -> sofort aufwecken!
			if not isBossAlive and not isBossDying then
				print("[BossService] Spieler in der Arena entdeckt - Wald-Golem erwacht!")
				spawnGolemModel()
				updateBossHealthUI(BossConfig.ForestGolemCore.MaxHealth, BossConfig.ForestGolemCore.MaxHealth)
			end

			if not isBossAlive or not currentBossModel or not currentBossHumanoid or isBossAttacking then
				continue
			end

			local bossRoot = currentBossModel.PrimaryPart
			if not bossRoot then
				continue
			end

			-- Finde den nächsten lebenden Spieler in der Arena anhand 2D-Horizontaldistanz
			local closestPlayer: Player? = nil
			local closestFlatDist = math.huge
			local closestTargetRoot: BasePart? = nil

			for _, player in Players:GetPlayers() do
				local char = player.Character
				if char then
					local hum = char:FindFirstChild("Humanoid") :: Humanoid?
					local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hum and root and hum.Health > 0 then
						local flatDistFromCenter = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(ARENA_CENTER.X, ARENA_CENTER.Z)).Magnitude
						if flatDistFromCenter <= (ARENA_RADIUS + 25) then
							local flatDistToBoss = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(bossRoot.Position.X, bossRoot.Position.Z)).Magnitude
							if flatDistToBoss < closestFlatDist then
								closestFlatDist = flatDistToBoss
								closestPlayer = player
								closestTargetRoot = root
							end
						end
					end
				end
			end

			if closestPlayer and closestTargetRoot then
				local now = os.clock()
				local attackCooldown = BossConfig.ForestGolemCore.AttackCooldown
				local canAttack = (now - lastBossAttackTime) >= attackCooldown

				local toPlayer = Vector3.new(closestTargetRoot.Position.X - bossRoot.Position.X, 0, closestTargetRoot.Position.Z - bossRoot.Position.Z)
				local flatDist = toPlayer.Magnitude

				if closestFlatDist <= 16 and canAttack then
					-- Nah genug für den telegrafierten Bodenschlag!
					lastBossAttackTime = now
					if currentBossMover then
						currentBossMover.Velocity = Vector3.zero
					end
					if currentBossRotator and flatDist > 0.1 then
						currentBossRotator.CFrame = CFrame.lookAt(bossRoot.Position, bossRoot.Position + toPlayer)
					end
					executeTelegraphedAttack(closestTargetRoot.Position)
				else
					-- Dem Spieler aktiv nähern
					if not isBossAttacking then
						local speed = 11
						if flatDist > 5.5 then
							local moveDir = toPlayer.Unit
							if currentBossMover then
								currentBossMover.Velocity = moveDir * speed
							end
							if currentBossRotator then
								currentBossRotator.CFrame = CFrame.lookAt(bossRoot.Position, bossRoot.Position + moveDir)
							end
						else
							-- Direkt vor dem Spieler stehen bleiben und ihn fixieren
							if currentBossMover then
								currentBossMover.Velocity = Vector3.zero
							end
							if currentBossRotator and flatDist > 0.1 then
								currentBossRotator.CFrame = CFrame.lookAt(bossRoot.Position, bossRoot.Position + toPlayer)
							end
						end
					end
				end
			else
				-- Keine Spieler in Reichweite -> Zurück zum Zentrum der Arena
				local toCenter = Vector3.new(ARENA_CENTER.X - bossRoot.Position.X, 0, ARENA_CENTER.Z - bossRoot.Position.Z)
				local distToCenter = toCenter.Magnitude

				if distToCenter > 4 and not isBossAttacking then
					local moveDir = toCenter.Unit
					if currentBossMover then
						currentBossMover.Velocity = moveDir * 8
					end
					if currentBossRotator then
						currentBossRotator.CFrame = CFrame.lookAt(bossRoot.Position, bossRoot.Position + moveDir)
					end
				else
					if currentBossMover then
						currentBossMover.Velocity = Vector3.zero
					end
				end
			end
		end
	end)
end

-- Server-Validierung von Spieler-Angriffen (PvE gegen Boss & PvP in der Oberwelt)
local function setupAttackHandler()
	AttackIntentEvent.OnServerEvent:Connect(function(player: Player)
		local char = player.Character
		if not char then
			return
		end

		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root or hum.Health <= 0 then
			return
		end

		-- Cooldown-Prüfung (0.22s Server vs 0.35s Client fängt Latenzschwankungen ab)
		local now = os.clock()
		local lastAttack = playerAttackCooldowns[player] or 0
		if now - lastAttack < 0.22 then
			return
		end
		playerAttackCooldowns[player] = now

		-- Schaden ermitteln (basierend auf der Waffe des Spielers im Inventar)
		local playerData = DataManager.Get(player)
		local weaponId = if playerData and playerData.Inventory and playerData.Inventory.EquippedWeapon
			then playerData.Inventory.EquippedWeapon
			elseif playerData and playerData.Inventory and playerData.Inventory.Weapons and playerData.Inventory.Weapons[1]
			then playerData.Inventory.Weapons[1]
			else "RustySword"
		local itemConfig = ItemConfig[weaponId]
		local weaponDamage = if itemConfig and itemConfig.Damage then itemConfig.Damage else 25

		-- Kritischer Treffer (server-autoritär gewürfelt): 20% Chance auf 1.75x Schaden
		local isCrit = math.random() < CRIT_CHANCE
		local damage = if isCrit then math.max(1, math.floor(weaponDamage * CRIT_MULTIPLIER + 0.5)) else weaponDamage

		-- 1. Prüfe auf Boss in Reichweite (Arena, großzügiger Trefferradius von 30 Studs)
		local hitBoss = false
		if isBossAlive and currentBossModel and currentBossHumanoid and currentBossHumanoid.Health > 0 then
			local bossRoot = currentBossModel.PrimaryPart
			if bossRoot then
				local flatDist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(bossRoot.Position.X, bossRoot.Position.Z)).Magnitude
				local dy = math.abs(root.Position.Y - bossRoot.Position.Y)
				if flatDist <= 30 and dy <= 28 then
					hitBoss = true
					currentBossHumanoid:TakeDamage(damage)

					-- Client-Juice: Schadenszahl, Funken & Steintreffer-Sound (an alle nahen Spieler)
					broadcastDamageFeedback(bossRoot.Position, damage, isCrit, "Boss")

					updateBossHealthUI(currentBossHumanoid.Health, currentBossHumanoid.MaxHealth)

					if currentBossHumanoid.Health <= 0 then
						handleBossDefeated(player)
					end
				end
			end
		end

		-- 2. Wenn kein Boss getroffen: Prüfe auf feindliche Spieler in Nahkampfreichweite (PvP / Raid-Abwehr)
		if not hitBoss then
			local closestEnemy: Player? = nil
			local closestHum: Humanoid? = nil
			local closestRoot: BasePart? = nil
			local closestDist = 14

			for _, otherPlayer in Players:GetPlayers() do
				if otherPlayer ~= player then
					local oChar = otherPlayer.Character
					if oChar then
						local oHum = oChar:FindFirstChild("Humanoid") :: Humanoid?
						local oRoot = oChar:FindFirstChild("HumanoidRootPart") :: BasePart?
						if oHum and oRoot and oHum.Health > 0 then
							local dist = (root.Position - oRoot.Position).Magnitude
							if dist <= closestDist then
								closestDist = dist
								closestEnemy = otherPlayer
								closestHum = oHum
								closestRoot = oRoot
							end
						end
					end
				end
			end

			if closestEnemy and closestHum and closestRoot then
				closestHum.Health = math.max(0, closestHum.Health - damage)
				broadcastDamageFeedback(closestRoot.Position, damage, isCrit, "Player", closestEnemy)

				if closestHum.Health <= 0 then
					NotificationEvent:FireClient(player, string.format("⚔️ Du hast %s besiegt!", closestEnemy.DisplayName), false)
				end
			else
				-- 3. Prüfe auf feindliche Wächter-Minions (z.B. bei Plot-Überfällen)
				local plotsFolder = Workspace:FindFirstChild("Plots")
				if plotsFolder then
					for _, plot in plotsFolder:GetChildren() do
						local minion = plot:FindFirstChild("GuardMinion") :: Model?
						if minion then
							local mOwner = (minion:GetAttribute("OwnerUserId") :: number?) or 0
							if mOwner ~= player.UserId then
								local mHum = minion:FindFirstChild("Humanoid") :: Humanoid?
								local mRoot = minion:FindFirstChild("HumanoidRootPart") :: BasePart?
								if mHum and mRoot and mHum.Health > 0 then
									local dist = (root.Position - mRoot.Position).Magnitude
									if dist <= 14 then
										mHum.Health = math.max(0, mHum.Health - damage)
										broadcastDamageFeedback(mRoot.Position, damage, isCrit, "Minion")
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

-- Erstellt Ruinen-Nadelbäume rund um die Arena (wie im Pitch-Video)
local function createArenaForestDecor(arena: Folder)
	local treePositions = {
		{ pos = ARENA_CENTER + Vector3.new(ARENA_RADIUS + 12, 0, 0), scale = 1.4 },
		{ pos = ARENA_CENTER + Vector3.new(-(ARENA_RADIUS + 12), 0, 0), scale = 1.6 },
		{ pos = ARENA_CENTER + Vector3.new(0, 0, ARENA_RADIUS + 12), scale = 1.2 },
		{ pos = ARENA_CENTER + Vector3.new(0, 0, -(ARENA_RADIUS + 14)), scale = 1.5 },
		{ pos = ARENA_CENTER + Vector3.new(ARENA_RADIUS + 10, 0, ARENA_RADIUS + 10), scale = 1.3 },
		{ pos = ARENA_CENTER + Vector3.new(-(ARENA_RADIUS + 10), 0, -(ARENA_RADIUS + 10)), scale = 1.1 },
		{ pos = ARENA_CENTER + Vector3.new(ARENA_RADIUS + 14, 0, -(ARENA_RADIUS + 8)), scale = 1.7 },
		{ pos = ARENA_CENTER + Vector3.new(-(ARENA_RADIUS + 14), 0, ARENA_RADIUS + 8), scale = 1.2 },
	}
	local treeFolder = Instance.new("Folder")
	treeFolder.Name = "ArenaForest"
	treeFolder.Parent = arena
	for i, treeData in ipairs(treePositions) do
		local s = treeData.scale
		local base = treeData.pos
		-- Stamm
		local trunk = createPart(treeFolder, "Trunk_" .. i, Vector3.new(2.2 * s, 14 * s, 2.2 * s), base + Vector3.new(0, 7 * s, 0), Color3.fromRGB(55, 40, 28), Enum.Material.WoodPlanks, true)
		-- Untere Astebene
		local cone1 = createPart(treeFolder, "Cone1_" .. i, Vector3.new(9 * s, 5 * s, 9 * s), base + Vector3.new(0, 13 * s, 0), Color3.fromRGB(32, 68, 30), Enum.Material.Grass, false)
		local mesh1 = Instance.new("SpecialMesh")
		mesh1.MeshType = Enum.MeshType.FileMesh
		mesh1.MeshId = "rbxassetid://1058430"
		mesh1.Parent = cone1
		-- Mittlere Astebene
		local cone2 = createPart(treeFolder, "Cone2_" .. i, Vector3.new(7 * s, 5.5 * s, 7 * s), base + Vector3.new(0, 17 * s, 0), Color3.fromRGB(28, 58, 26), Enum.Material.Grass, false)
		local mesh2 = Instance.new("SpecialMesh")
		mesh2.MeshType = Enum.MeshType.FileMesh
		mesh2.MeshId = "rbxassetid://1058430"
		mesh2.Parent = cone2
		-- Spitze
		local cone3 = createPart(treeFolder, "Cone3_" .. i, Vector3.new(4.5 * s, 5 * s, 4.5 * s), base + Vector3.new(0, 21 * s, 0), Color3.fromRGB(26, 52, 24), Enum.Material.Grass, false)
		local mesh3 = Instance.new("SpecialMesh")
		mesh3.MeshType = Enum.MeshType.FileMesh
		mesh3.MeshId = "rbxassetid://1058430"
		mesh3.Parent = cone3
	end
end

-- Erstellt einen antiken Relikt-Schrein in der Arena-Mitte (wo der Kern nach dem Boss-Kill erscheint)
local function ensureArenaShrine()
	local arena = Workspace:FindFirstChild("Arena_WaldRuinen")
	if not arena then return end
	local existing = arena:FindFirstChild("ArenaShrine")
	if existing then existing:Destroy() end

	local shrine = Instance.new("Model")
	shrine.Name = "ArenaShrine"
	shrine.Parent = arena
	local shrinePos = ARENA_CENTER + Vector3.new(0, 1, -20)

	-- Stufensockel (3 Ebenen Marmor)
	for step = 1, 3 do
		local size = 6.5 - (step - 1) * 1.2
		local yOff = (step - 1) * 0.9
		local slab = createPart(shrine, "Slab_" .. step, Vector3.new(size, 0.8, size), shrinePos + Vector3.new(0, yOff, 0), Color3.fromRGB(220, 218, 210), Enum.Material.Marble, true)
		if step == 1 then shrine.PrimaryPart = slab end
	end

	-- Schwebender Schrein-Kristall (Amethyst, wie im Video)
	local crystal = createPart(shrine, "ShrinecrystalBase", Vector3.new(2, 3.5, 2), shrinePos + Vector3.new(0, 4.2, 0), Color3.fromRGB(155, 60, 255), Enum.Material.Neon, false)
	local crystalMesh = Instance.new("SpecialMesh")
	crystalMesh.MeshType = Enum.MeshType.Sphere
	crystalMesh.Scale = Vector3.new(1.0, 1.8, 1.0)
	crystalMesh.Parent = crystal
	-- Animiertes Schweben + Rotieren
	task.spawn(function()
		local t = 0
		while crystal:IsDescendantOf(Workspace) do
			t += task.wait(0.04)
			crystal.CFrame = CFrame.new(shrinePos + Vector3.new(0, 4.2 + math.sin(t * 1.5) * 0.6, 0)) * CFrame.Angles(0, t * 0.8, 0)
		end
	end)
	local crystalLight = Instance.new("PointLight")
	crystalLight.Color = Color3.fromRGB(180, 60, 255)
	crystalLight.Range = 28
	crystalLight.Brightness = 3.5
	crystalLight.Parent = crystal

	-- 4 flankierende Amethyst-Säulen
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2
		local pPos = shrinePos + Vector3.new(math.cos(angle) * 4.5, 0, math.sin(angle) * 4.5)
		local pillar = createPart(shrine, "ShrPillar_" .. i, Vector3.new(1.0, 5.5, 1.0), pPos + Vector3.new(0, 2.5, 0), Color3.fromRGB(48, 42, 58), Enum.Material.Slate, true)
		local cap = createPart(shrine, "ShrCap_" .. i, Vector3.new(1.5, 0.5, 1.5), pPos + Vector3.new(0, 5.5, 0), Color3.fromRGB(155, 60, 255), Enum.Material.Neon, false)
		local capLight = Instance.new("PointLight")
		capLight.Color = Color3.fromRGB(155, 60, 255)
		capLight.Range = 10
		capLight.Brightness = 1.8
		capLight.Parent = cap
	end
end

function BossService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	local arena = ensureArenaExists()
	createArenaForestDecor(arena)
	pcall(ensureArenaShrine)
	setupAttackHandler()
	startBossAILoop()

	-- Bereinigung von Cooldown-Einträgen bei Verlassen des Spielers (SE-4 Memory Leak Schutz)
	Players.PlayerRemoving:Connect(function(player: Player)
		playerAttackCooldowns[player] = nil
	end)

	print("[BossService] Wald-Golem initialisiert (Gelbe Augen, Moos, Zähne, Schrein, Waldbäume aktiv).")
end

return BossService
