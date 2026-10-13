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

local BossService = {}

local ARENA_CENTER = Vector3.new(0, 500, 25000)
local ARENA_RADIUS = 60

BossService.ARENA_CENTER = ARENA_CENTER
BossService.ARENA_RADIUS = ARENA_RADIUS
BossService.ARENA_SPAWN = ARENA_CENTER + Vector3.new(0, 3.5, 38)
BossService.ARENA_PORTAL_POS = ARENA_CENTER + Vector3.new(0, 0.5, 48)

local currentBossModel: Model? = nil
local currentBossHumanoid: Humanoid? = nil
local isBossAlive = false
local isBossAttacking = false
local isBossDying = false
local isInitialized = false

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

-- Zeigt schwebende Schadenszahlen über dem Boss an
local function showDamageNumber(position: Vector3, damage: number)
	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 80, 0, 36)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = string.format("-%d", damage)
	label.TextColor3 = Color3.fromRGB(255, 100, 50)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard

	-- Float & Fade Out
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = part.Position + Vector3.new(0, 4, 0) }
	)
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
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

	local spawnPos = ARENA_CENTER + Vector3.new(0, 1, 0)

	-- HumanoidRootPart
	local root = createPart(model, "HumanoidRootPart", Vector3.new(4, 8, 4), spawnPos + Vector3.new(0, 5, 0), Color3.fromRGB(0, 0, 0), nil, false)
	root.Transparency = 1
	model.PrimaryPart = root

	-- Torso (Massiver Felsen mit Steinadern)
	local torso = createPart(model, "Torso", Vector3.new(9, 11, 7), spawnPos + Vector3.new(0, 6, 0), Color3.fromRGB(75, 80, 70), Enum.Material.Slate, true)
	-- Steinadern auf der Brust (dunklere Linien)
	local veinH = createPart(model, "VeinH", Vector3.new(7, 0.35, 0.35), spawnPos + Vector3.new(0, 7.8, -3.6), Color3.fromRGB(38, 42, 36), Enum.Material.SmoothPlastic, false)
	local veinV = createPart(model, "VeinV", Vector3.new(0.35, 5, 0.35), spawnPos + Vector3.new(0, 6, -3.6), Color3.fromRGB(38, 42, 36), Enum.Material.SmoothPlastic, false)

	-- Leuchtender SMARAGD-Kern auf der Brust (Schwachstelle, pulsierendes Grün)
	local corePart = createPart(model, "Core", Vector3.new(2.8, 2.8, 1.8), spawnPos + Vector3.new(0, 7, -3.6), Color3.fromRGB(46, 204, 113), Enum.Material.Neon, false)
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
	local head = createPart(model, "Head", Vector3.new(5.5, 4.5, 5), spawnPos + Vector3.new(0, 13, 0), Color3.fromRGB(85, 90, 80), Enum.Material.Slate, true)
	-- Wangenknochen (Felsbrocken an den Seiten des Kopfes)
	local cheekL = createPart(model, "CheekL", Vector3.new(1.8, 1.4, 1.4), spawnPos + Vector3.new(-2.6, 12.6, -1.5), Color3.fromRGB(65, 70, 62), Enum.Material.Cobblestone, true)
	local cheekR = createPart(model, "CheekR", Vector3.new(1.8, 1.4, 1.4), spawnPos + Vector3.new(2.6, 12.6, -1.5), Color3.fromRGB(65, 70, 62), Enum.Material.Cobblestone, true)

	-- LEUCHTEND GELBE AUGEN (wie im Pitch-Video!)
	local eyeL = createPart(model, "EyeL", Vector3.new(1.1, 0.9, 0.7), spawnPos + Vector3.new(-1.5, 13.4, -2.6), Color3.fromRGB(255, 235, 40), Enum.Material.Neon, false)
	local eyeR = createPart(model, "EyeR", Vector3.new(1.1, 0.9, 0.7), spawnPos + Vector3.new(1.5, 13.4, -2.6), Color3.fromRGB(255, 235, 40), Enum.Material.Neon, false)
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
		Vector3.new(-1.8, 11.0, -2.7),
		Vector3.new(-0.6, 10.7, -2.75),
		Vector3.new(0.6, 10.7, -2.75),
		Vector3.new(1.8, 11.0, -2.7),
	}
	for i, tPos in ipairs(teethPositions) do
		local tooth = createPart(model, "Tooth_" .. i, Vector3.new(0.7, 1.2, 0.5), spawnPos + tPos, Color3.fromRGB(220, 215, 195), Enum.Material.SmoothPlastic, true)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = tooth
	end

	-- Massive FELSBLOCK-FÄUSTE an den Armen
	-- Linker Arm + Faust
	local armL = createPart(model, "ArmL", Vector3.new(4, 10, 4), spawnPos + Vector3.new(-7, 6.5, 0), Color3.fromRGB(72, 78, 68), Enum.Material.Cobblestone, true)
	local fistL = createPart(model, "FistL", Vector3.new(5, 5, 5), spawnPos + Vector3.new(-7.5, 0.5, 0), Color3.fromRGB(65, 70, 62), Enum.Material.Slate, true)
	-- Knöchelrisse auf der Faust
	local knuckleL = createPart(model, "KnuckleL", Vector3.new(4.5, 0.4, 0.4), spawnPos + Vector3.new(-7.5, 3.0, -2.55), Color3.fromRGB(42, 46, 40), Enum.Material.SmoothPlastic, false)
	-- Rechter Arm + Faust
	local armR = createPart(model, "ArmR", Vector3.new(4, 10, 4), spawnPos + Vector3.new(7, 6.5, 0), Color3.fromRGB(72, 78, 68), Enum.Material.Cobblestone, true)
	local fistR = createPart(model, "FistR", Vector3.new(5, 5, 5), spawnPos + Vector3.new(7.5, 0.5, 0), Color3.fromRGB(65, 70, 62), Enum.Material.Slate, true)
	local knuckleR = createPart(model, "KnuckleR", Vector3.new(4.5, 0.4, 0.4), spawnPos + Vector3.new(7.5, 3.0, -2.55), Color3.fromRGB(42, 46, 40), Enum.Material.SmoothPlastic, false)

	-- MOOS-SCHULTERPOLSTER (Grass-Material in sattem Waldgrün, wie im Video!)
	local mossOffsets = {
		Vector3.new(-5.5, 11.0, 0),   -- linke Schulter
		Vector3.new(5.5, 11.0, 0),    -- rechte Schulter
		Vector3.new(-4.5, 11.6, 1.5), -- links hinten
		Vector3.new(4.5, 11.6, 1.5),  -- rechts hinten
		Vector3.new(0, 12.2, 2.5),    -- Nacken-Moos
	}
	for i, mOff in ipairs(mossOffsets) do
		local moss = createPart(model, "Moss_" .. i, Vector3.new(2.8, 1.2, 2.8), spawnPos + mOff, Color3.fromRGB(55, 120, 45), Enum.Material.Grass, false)
		moss.CastShadow = false
	end
	-- Moos-Klumpen auf dem Kopf
	local mossHead = createPart(model, "MossHead", Vector3.new(4.5, 1.0, 4.5), spawnPos + Vector3.new(0, 15.8, 0), Color3.fromRGB(50, 110, 38), Enum.Material.Grass, false)
	mossHead.CastShadow = false

	-- Beine (massiver, gedrungener Block-Stil)
	local legL = createPart(model, "LegL", Vector3.new(4, 7, 4), spawnPos + Vector3.new(-2.8, 1.5, 0), Color3.fromRGB(68, 72, 62), Enum.Material.Cobblestone, true)
	local legR = createPart(model, "LegR", Vector3.new(4, 7, 4), spawnPos + Vector3.new(2.8, 1.5, 0), Color3.fromRGB(68, 72, 62), Enum.Material.Cobblestone, true)

	-- Schweißungen (Welds)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
			part.Anchored = false
		end
	end
	root.Anchored = false

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = BossConfig.ForestGolemCore.MaxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 9
	humanoid.Parent = model

	-- Overhead-Boss-Health-Bar (nur aus der Nähe sichtbar, kein AlwaysOnTop durch Wände)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossHealthBar"
	billboard.Size = UDim2.new(0, 180, 0, 48)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
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

	local config = BossConfig.ForestGolemCore
	local radius = config.TelegraphRadius
	local duration = config.TelegraphDuration

	-- 1. Rote Indikator-Fläche am Boden erzeugen
	local telegraph = Instance.new("Part")
	telegraph.Name = "TelegraphIndicator"
	telegraph.Shape = Enum.PartType.Cylinder
	telegraph.Size = Vector3.new(0.4, radius * 2, radius * 2)
	telegraph.CFrame = CFrame.new(Vector3.new(targetPos.X, ARENA_CENTER.Y + 1.2, targetPos.Z)) * CFrame.Angles(0, 0, math.rad(90))
	telegraph.Color = Color3.fromRGB(231, 76, 60)
	telegraph.Material = Enum.Material.Neon
	telegraph.Transparency = 0.5
	telegraph.Anchored = true
	telegraph.CanCollide = false
	telegraph.Parent = Workspace

	BossTelegraphEvent:FireAllClients(targetPos, radius, duration)

	-- Telegraph-Dauer abwarten (Zeit zum Ausweichen!)
	task.wait(duration)

	-- 2. Impact / Slam!
	if telegraph then
		telegraph:Destroy()
	end

	-- Shockwave-Optik
	local shockwave = Instance.new("Part")
	shockwave.Shape = Enum.PartType.Ball
	shockwave.Size = Vector3.new(2, 2, 2)
	shockwave.Position = Vector3.new(targetPos.X, ARENA_CENTER.Y + 2, targetPos.Z)
	shockwave.Color = Color3.fromRGB(241, 196, 15)
	shockwave.Material = Enum.Material.Neon
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.Parent = Workspace

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
					NotificationEvent:FireClient(player, string.format("💥 Vom Bodenschlag getroffen! (-%d HP)", config.AttackDamage), true)
				end
			end
		end
	end

	task.wait(1.0) -- Erholungsphase
	isBossAttacking = false
end

-- Boss-KI-Schleife (Server-autoritär)
local function startBossAILoop()
	task.spawn(function()
		local emptyArenaTicks = 0
		while true do
			task.wait(0.3)

			-- Prüfe, ob sich noch Spieler in der Arena aufhalten
			local playersInArena = getPlayersInArenaCount()
			if playersInArena == 0 then
				if isBossAlive and not isBossDying then
					print("[BossService] Keine Spieler in der Arena - Wald-Golem despawnt sofort.")
					despawnGolem()
				end
				continue
			end

			if not isBossAlive or not currentBossModel or not currentBossHumanoid or isBossAttacking then
				continue
			end

			local bossRoot = currentBossModel.PrimaryPart
			if not bossRoot then
				continue
			end

			-- Finde den nächsten Spieler in der Arena
			local closestPlayer: Player? = nil
			local closestDist = math.huge

			for _, player in Players:GetPlayers() do
				local char = player.Character
				if char then
					local hum = char:FindFirstChild("Humanoid") :: Humanoid?
					local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hum and root and hum.Health > 0 then
						local distFromCenter = (root.Position - ARENA_CENTER).Magnitude
						if distFromCenter <= ARENA_RADIUS then
							local distToBoss = (root.Position - bossRoot.Position).Magnitude
							if distToBoss < closestDist then
								closestDist = distToBoss
								closestPlayer = player
							end
						end
					end
				end
			end

			if closestPlayer and closestPlayer.Character then
				local targetRoot = closestPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if targetRoot then
					if closestDist <= 15 then
						-- Nah genug für den telegrafierten Bodenschlag!
						currentBossHumanoid:MoveTo(bossRoot.Position)
						executeTelegraphedAttack(targetRoot.Position)
					else
						-- Dem Spieler nähern
						currentBossHumanoid:MoveTo(targetRoot.Position)
					end
				end
			else
				-- Keine Spieler in der Arena -> Zurück zum Zentrum
				if (bossRoot.Position - ARENA_CENTER).Magnitude > 8 then
					currentBossHumanoid:MoveTo(ARENA_CENTER)
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

		-- Cooldown-Prüfung (0.35 Sekunden zwischen Schlägen)
		local now = os.clock()
		local lastAttack = playerAttackCooldowns[player] or 0
		if now - lastAttack < 0.35 then
			return
		end
		playerAttackCooldowns[player] = now

		-- Schaden ermitteln (basierend auf der Waffe des Spielers im Inventar)
		local playerData = DataManager.Get(player)
		local weaponId = if playerData and playerData.Inventory and playerData.Inventory.Weapons and playerData.Inventory.Weapons[1]
			then playerData.Inventory.Weapons[1]
			else "RustySword"
		local itemConfig = ItemConfig[weaponId]
		local weaponDamage = if itemConfig and itemConfig.Damage then itemConfig.Damage else 25

		-- 1. Prüfe auf Boss in Reichweite (Arena)
		local hitBoss = false
		if isBossAlive and currentBossModel and currentBossHumanoid and currentBossHumanoid.Health > 0 then
			local bossRoot = currentBossModel.PrimaryPart
			if bossRoot then
				local dist = (root.Position - bossRoot.Position).Magnitude
				if dist <= 18 then
					hitBoss = true
					currentBossHumanoid.Health = math.max(0, currentBossHumanoid.Health - weaponDamage)
					showDamageNumber(bossRoot.Position, weaponDamage)
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
				closestHum.Health = math.max(0, closestHum.Health - weaponDamage)
				showDamageNumber(closestRoot.Position, weaponDamage)

				if closestHum.Health <= 0 then
					NotificationEvent:FireClient(player, string.format("⚔️ Du hast %s besiegt!", closestEnemy.DisplayName), false)
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
	crystalMesh.MeshType = Enum.MeshType.Diamond
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
	ensureArenaShrine()
	setupAttackHandler()
	startBossAILoop()

	-- Bereinigung von Cooldown-Einträgen bei Verlassen des Spielers (SE-4 Memory Leak Schutz)
	Players.PlayerRemoving:Connect(function(player: Player)
		playerAttackCooldowns[player] = nil
	end)

	print("[BossService] Wald-Golem initialisiert (Gelbe Augen, Moos, Zähne, Schrein, Waldbäume aktiv).")
end

return BossService
