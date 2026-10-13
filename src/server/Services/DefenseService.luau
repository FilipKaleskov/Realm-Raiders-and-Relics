--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local ConfigFolder = Shared:WaitForChild("Config")

local BossConfigModule = ConfigFolder:WaitForChild("BossConfig") :: ModuleScript
local BossConfig = require(BossConfigModule)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

local NotificationEvent = EventsFolder:WaitForChild("ShowNotification") :: RemoteEvent
local GoldUpdatedEvent = EventsFolder:WaitForChild("GoldUpdated") :: RemoteEvent

local DefenseService = {}
local isInitialized = false

-- Typ-Definitionen
export type GuardMinion = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Eyes: { BasePart },
	HomePosition: Vector3,
	OwnerUserId: number,
	PlotModel: Model,
	TargetPlayer: Player?,
	LastAttackTime: number,
	IsDead: boolean,
}

local activeMinions: { [Model]: GuardMinion } = {}
local activeTraps: { [Model]: {
	Model: Model,
	OwnerUserId: number,
	LastTriggered: number,
	IsActive: boolean,
	SpikeParts: { BasePart },
} } = {}

-- Hilfsfunktion: Standard Part erstellen
local function createPart(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = pos
	part.Color = color
	part.Material = mat or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = if collide ~= nil then collide else false
	part.Parent = parent
	return part
end

-- ============================================================================
-- 1. STACHELFALLEN (SPIKE TRAPS)
-- ============================================================================

-- Erstellt ein detailliertes 3D-Modell einer Stachelfalle
function DefenseService.CreateSpikeTrap(plotModel: Model, relativePos: Vector3, ownerUserId: number): Model
	local trapModel = Instance.new("Model")
	trapModel.Name = "SpikeTrap"
	trapModel:SetAttribute("OwnerUserId", ownerUserId)
	trapModel.Parent = plotModel

	local floor = plotModel:FindFirstChild("PlotFloor") :: BasePart?
	local baseWorldPos = if floor then floor.Position + relativePos else relativePos

	-- 1. Boden-Rahmenplatte (Dunkles Eisen / Verankerung)
	local frame = createPart(trapModel, "TrapFrame", Vector3.new(5.2, 0.4, 5.2), baseWorldPos + Vector3.new(0, 0.2, 0), Color3.fromRGB(35, 38, 42), Enum.Material.DiamondPlate, true)
	trapModel.PrimaryPart = frame

	-- Vertiefte Innenplatte (Gitter/Schlitze)
	createPart(trapModel, "TrapGrate", Vector3.new(4.4, 0.15, 4.4), baseWorldPos + Vector3.new(0, 0.35, 0), Color3.fromRGB(25, 28, 30), Enum.Material.Metal, false)

	-- 2. Metall-Stacheln (4 scharfe Spitzen, im Normalzustand eingefahren)
	local spikeParts: { BasePart } = {}
	local spikeOffsets = {
		Vector3.new(-1.3, 0, -1.3),
		Vector3.new(1.3, 0, -1.3),
		Vector3.new(-1.3, 0, 1.3),
		Vector3.new(1.3, 0, 1.3),
	}

	for i, offset in ipairs(spikeOffsets) do
		local spike = Instance.new("Part")
		spike.Name = "Spike_" .. i
		spike.Size = Vector3.new(0.6, 2.2, 0.6)
		spike.Position = baseWorldPos + offset + Vector3.new(0, -0.7, 0) -- Eingefahren
		spike.Color = Color3.fromRGB(180, 190, 200)
		spike.Material = Enum.Material.Metal
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = trapModel

		-- Mesh für spitzen Stachel-Look
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Scale = Vector3.new(1.0, 1.0, 1.0)
		mesh.Parent = spike

		table.insert(spikeParts, spike)
	end

	-- 3. Unsichtbare Trigger-Hitbox
	local trigger = Instance.new("Part")
	trigger.Name = "TriggerBox"
	trigger.Size = Vector3.new(4.8, 1.8, 4.8)
	trigger.Position = baseWorldPos + Vector3.new(0, 1.0, 0)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.Anchored = true
	trigger.Parent = trapModel

	activeTraps[trapModel] = {
		Model = trapModel,
		OwnerUserId = ownerUserId,
		LastTriggered = 0,
		IsActive = false,
		SpikeParts = spikeParts,
	}

	-- Berührungs-Erkennung
	trigger.Touched:Connect(function(hitPart: BasePart)
		local char = hitPart.Parent :: Model?
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end

		-- Falle löst NUR bei fremden Spielern aus!
		local trapData = activeTraps[trapModel]
		if not trapData or trapData.IsActive then return end
		if os.clock() - trapData.LastTriggered < 3.0 then return end

		-- Plot-Besitzer prüfen
		local currentOwnerId = (plotModel:GetAttribute("OwnerUserId") :: number?) or 0
		if player.UserId == currentOwnerId and currentOwnerId ~= 0 then
			return -- Eigener Besitzer ist immun
		end

		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root or hum.Health <= 0 then return end

		-- FALLE SCHNAPPT ZU!
		trapData.IsActive = true
		trapData.LastTriggered = os.clock()

		-- 1. Stacheln schnellen explosiv hoch
		for _, sp in ipairs(spikeParts) do
			local upPos = sp.Position + Vector3.new(0, 2.0, 0)
			TweenService:Create(sp, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = upPos,
				Color = Color3.fromRGB(220, 50, 50), -- Blutig rot
			}):Play()
		end

		-- 2. Schaden & Slowdown zufügen (Server-Autorität)
		local damage = 25
		hum:TakeDamage(damage)

		-- Temporärer Slowdown (WalkSpeed 6 für 2.5 Sekunden)
		local originalSpeed = hum.WalkSpeed
		hum.WalkSpeed = math.min(hum.WalkSpeed, 6)

		-- Funken- & Blutpartikel
		local sparkPart = Instance.new("Part")
		sparkPart.Size = Vector3.new(1, 1, 1)
		sparkPart.Position = trigger.Position
		sparkPart.Transparency = 1
		sparkPart.Anchored = true
		sparkPart.CanCollide = false
		sparkPart.Parent = Workspace

		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 35
		sparks.Speed = NumberRange.new(5, 12)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Lifetime = NumberRange.new(0.4, 0.8)
		sparks.Size = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 60, 60))
		sparks.LightEmission = 0.9
		sparks.Parent = sparkPart
		Debris:AddItem(sparkPart, 1.0)

		-- Schmerzens-Sound (Roblox Impact)
		local hitSound = Instance.new("Sound")
		hitSound.SoundId = "rbxassetid://566593606" -- Sharp metal hit
		hitSound.Volume = 0.9
		hitSound.Parent = trigger
		hitSound:Play()
		Debris:AddItem(hitSound, 1.5)

		-- Notification an das Opfer (dezent)
		NotificationEvent:FireClient(player, "🩸 Stachelfalle ausgelöst! (-25 HP)", true)

		-- Echten Besitzer benachrichtigen, falls online (nicht Test-NPC)
		if currentOwnerId > 0 and currentOwnerId ~= 999999 and currentOwnerId ~= player.UserId then
			for _, p in Players:GetPlayers() do
				if p.UserId == currentOwnerId then
					NotificationEvent:FireClient(p, string.format("⚔️ Deine Stachelfalle hat %s erwischt!", player.DisplayName), false)
					break
				end
			end
		end

		-- Nach 2.5s: Stacheln wieder einfahren und Normalzustand
		task.delay(2.2, function()
			if hum and hum.Health > 0 and player:GetAttribute("CarryingCore") == nil then
				hum.WalkSpeed = 16
			end

			for _, sp in ipairs(spikeParts) do
				local downPos = sp.Position - Vector3.new(0, 2.0, 0)
				TweenService:Create(sp, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = downPos,
					Color = Color3.fromRGB(180, 190, 200),
				}):Play()
			end

			task.wait(0.5)
			trapData.IsActive = false
		end)
	end)

	return trapModel
end

-- ============================================================================
-- 2. WÄCHTER-MINION-KI (GUARD MINION)
-- ============================================================================

-- Erstellt einen prozeduralen Wächter-Minion auf dem Plot
function DefenseService.CreateGuardMinion(plotModel: Model, spawnOffset: Vector3, ownerUserId: number): Model
	local minionModel = Instance.new("Model")
	minionModel.Name = "GuardMinion"
	minionModel:SetAttribute("OwnerUserId", ownerUserId)
	minionModel.Parent = plotModel

	local floor = plotModel:FindFirstChild("PlotFloor") :: BasePart?
	local basePos = if floor then floor.Position + spawnOffset else spawnOffset

	-- Humanoid & Rig aufbauen
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 120
	humanoid.Health = 120
	humanoid.WalkSpeed = 13
	humanoid.HipHeight = 1.3
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid.Parent = minionModel

	-- RootPart (Fels-Unterkörper)
	local root = createPart(minionModel, "HumanoidRootPart", Vector3.new(2.4, 2.6, 1.8), basePos + Vector3.new(0, 2.0, 0), Color3.fromRGB(60, 68, 62), Enum.Material.Slate, true)
	root.Anchored = false
	root.CanCollide = true
	minionModel.PrimaryPart = root

	-- Torso (Moosiger Felsen mit Runen-Symbol)
	local torso = createPart(minionModel, "Torso", Vector3.new(2.8, 3.0, 2.0), basePos + Vector3.new(0, 3.2, 0), Color3.fromRGB(55, 62, 55), Enum.Material.Slate, false)
	local torsoWeld = Instance.new("WeldConstraint")
	torsoWeld.Part0 = root
	torsoWeld.Part1 = torso
	torsoWeld.Parent = torso

	-- Moos-Schultern
	local mossShoulderL = createPart(minionModel, "MossL", Vector3.new(1.2, 0.6, 1.2), torso.Position + Vector3.new(-1.6, 1.2, 0), Color3.fromRGB(46, 120, 50), Enum.Material.Grass, false)
	local mwL = Instance.new("WeldConstraint")
	mwL.Part0 = torso
	mwL.Part1 = mossShoulderL
	mwL.Parent = mossShoulderL

	local mossShoulderR = createPart(minionModel, "MossR", Vector3.new(1.2, 0.6, 1.2), torso.Position + Vector3.new(1.6, 1.2, 0), Color3.fromRGB(46, 120, 50), Enum.Material.Grass, false)
	local mwR = Instance.new("WeldConstraint")
	mwR.Part0 = torso
	mwR.Part1 = mossShoulderR
	mwR.Parent = mossShoulderR

	-- Kopf mit Hörnern/Felsformation
	local head = createPart(minionModel, "Head", Vector3.new(1.8, 1.6, 1.8), torso.Position + Vector3.new(0, 2.2, 0), Color3.fromRGB(70, 78, 70), Enum.Material.Cobblestone, false)
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head

	-- Gelb leuchtende Augen (wie beim Boss!)
	local eyes: { BasePart } = {}
	for idx, xOff in { -0.4, 0.4 } do
		local eye = createPart(minionModel, "Eye_" .. idx, Vector3.new(0.3, 0.3, 0.2), head.Position + Vector3.new(xOff, 0.2, -0.95), Color3.fromRGB(255, 230, 40), Enum.Material.Neon, false)
		local eyeWeld = Instance.new("WeldConstraint")
		eyeWeld.Part0 = head
		eyeWeld.Part1 = eye
		eyeWeld.Parent = eye
		table.insert(eyes, eye)
	end

	-- Waffe: Steinaxt in der Hand
	local axe = createPart(minionModel, "MinionAxe", Vector3.new(0.8, 3.2, 1.4), torso.Position + Vector3.new(2.0, 0, -0.6), Color3.fromRGB(45, 45, 45), Enum.Material.Slate, false)
	local axeWeld = Instance.new("WeldConstraint")
	axeWeld.Part0 = torso
	axeWeld.Part1 = axe
	axeWeld.Parent = axe

	-- Billboard über dem Kopf
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MinionTag"
	billboard.Size = UDim2.new(0, 150, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3.8, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "StatusLabel"
	label.Size = UDim2.new(1, 0, 0.55, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(24, 32, 28)
	label.TextColor3 = Color3.fromRGB(46, 204, 113)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "🛡️ BASIS-WÄCHTER"
	label.Parent = billboard

	local hpBarBg = Instance.new("Frame")
	hpBarBg.Name = "HpBg"
	hpBarBg.Size = UDim2.new(1, 0, 0.35, 0)
	hpBarBg.Position = UDim2.new(0, 0, 0.65, 0)
	hpBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBarBg.BorderSizePixel = 0
	hpBarBg.Parent = billboard

	local hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "HpFill"
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	hpBarFill.BorderSizePixel = 0
	hpBarFill.Parent = hpBarBg

	-- Lebensleiste aktualisieren
	humanoid.HealthChanged:Connect(function(health: number)
		local frac = math.clamp(health / humanoid.MaxHealth, 0, 1)
		hpBarFill.Size = UDim2.new(frac, 0, 1, 0)
		if frac < 0.3 then
			hpBarFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
		elseif frac < 0.6 then
			hpBarFill.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
		else
			hpBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
		end
	end)

	local minionData: GuardMinion = {
		Model = minionModel,
		Humanoid = humanoid,
		RootPart = root,
		Eyes = eyes,
		HomePosition = basePos,
		OwnerUserId = ownerUserId,
		PlotModel = plotModel,
		TargetPlayer = nil,
		LastAttackTime = 0,
		IsDead = false,
	}

	activeMinions[minionModel] = minionData

	-- Tod des Minions
	humanoid.Died:Connect(function()
		minionData.IsDead = true
		label.Text = "💀 BESIEGT"
		label.TextColor3 = Color3.fromRGB(180, 180, 180)

		-- Nach 30s respawnen
		task.delay(30, function()
			if plotModel and plotModel.Parent then
				minionModel:Destroy()
				activeMinions[minionModel] = nil
				DefenseService.CreateGuardMinion(plotModel, spawnOffset, ownerUserId)
			end
		end)
	end)

	return minionModel
end

-- ============================================================================
-- 3. SCHMELZ-ALTAR (SECURING & TRANSMUTATION ALTAR)
-- ============================================================================

-- Erstellt den mystischen Altar zum Sichern oder Einschmelzen gestohlener Kerne
function DefenseService.CreateSecuringAltar(plotModel: Model, relativePos: Vector3): Model
	local altar = Instance.new("Model")
	altar.Name = "SecuringAltar"
	altar.Parent = plotModel

	local floor = plotModel:FindFirstChild("PlotFloor") :: BasePart?
	local basePos = if floor then floor.Position + relativePos else relativePos

	-- 1. Fundament-Sockel (Obsidian-Stufen)
	local baseSlab = createPart(altar, "AltarBase", Vector3.new(7.0, 0.8, 7.0), basePos + Vector3.new(0, 0.4, 0), Color3.fromRGB(28, 30, 36), Enum.Material.Slate, true)
	altar.PrimaryPart = baseSlab

	local midSlab = createPart(altar, "AltarMid", Vector3.new(5.6, 0.8, 5.6), basePos + Vector3.new(0, 1.2, 0), Color3.fromRGB(36, 40, 48), Enum.Material.Slate, true)
	local topBowl = createPart(altar, "AltarBowl", Vector3.new(4.2, 1.2, 4.2), basePos + Vector3.new(0, 2.2, 0), Color3.fromRGB(24, 26, 32), Enum.Material.Cobblestone, true)

	-- 2. Flammendes Schmelz-Becken (Pulsierendes Gold/Amethyst-Neon)
	local fireCore = createPart(altar, "FireCore", Vector3.new(2.8, 0.4, 2.8), basePos + Vector3.new(0, 2.9, 0), Color3.fromRGB(255, 170, 0), Enum.Material.Neon, false)

	local fireLight = Instance.new("PointLight")
	fireLight.Color = Color3.fromRGB(255, 180, 40)
	fireLight.Range = 16
	fireLight.Brightness = 2.5
	fireLight.Parent = fireCore

	-- Partikel: Aufsteigende Flammenfunken & Seelen-Aura
	local flameParticles = Instance.new("ParticleEmitter")
	flameParticles.Rate = 14
	flameParticles.Speed = NumberRange.new(2.0, 4.5)
	flameParticles.Lifetime = NumberRange.new(1.0, 2.0)
	flameParticles.SpreadAngle = Vector2.new(25, 25)
	flameParticles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	}
	flameParticles.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 100, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 40, 200)),
	}
	flameParticles.LightEmission = 0.9
	flameParticles.Parent = fireCore

	-- 3. Billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AltarInfo"
	billboard.Size = UDim2.new(0, 160, 0, 42)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = topBowl

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	label.TextColor3 = Color3.fromRGB(255, 215, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "🔥 SCHMELZ-ALTAR 🔥\n[E] Beute einschmelzen"
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.2
	stroke.Parent = label

	-- 4. ProximityPrompt: Beute einschmelzen für Sofort-Gold-Bonus!
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SmeltPrompt"
	prompt.ActionText = "Kern einschmelzen (+Sofort-Gold)"
	prompt.ObjectText = "Schmelz-Altar"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = fireCore

	prompt.Triggered:Connect(function(player: Player)
		local plotOwnerId = (plotModel:GetAttribute("OwnerUserId") :: number?) or 0
		if player.UserId ~= plotOwnerId and plotOwnerId ~= 0 then
			return
		end

		local carriedCore = player:GetAttribute("CarryingCore") :: string?
		if not carriedCore then
			NotificationEvent:FireClient(player, "Kein Seelenkern zum Einschmelzen! Stiehl einen Kern bei Raids oder besiege Bosse.", true)
			return
		end

		local coreLevel = (player:GetAttribute("CarryingCoreLevel") :: number?) or 1
		local bossInfo = BossConfig[carriedCore]
		local coreName = if bossInfo then bossInfo.DisplayName else carriedCore

		-- Sofort-Gold: 150 * Level
		local goldGain = 150 * coreLevel
		DataManager.AddGold(player, goldGain)

		-- Trägerstatus über RaidService beenden (Visuals entfernen)
		local ServicesMod = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
		local RaidService = require(ServicesMod:WaitForChild("RaidService") :: ModuleScript)
		
		-- Attribute bereinigen
		player:SetAttribute("CarryingCore", nil)
		player:SetAttribute("CarryingCoreLevel", nil)
		player:SetAttribute("StolenFromUserId", nil)
		player:SetAttribute("StolenFromName", nil)

		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid") :: Humanoid?
			if hum then hum.WalkSpeed = 16 end
			local relic = char:FindFirstChild("CarriedCoreRelic")
			if relic then relic:Destroy() end
			local sky = char:FindFirstChild("BeaconSkyAnchor")
			if sky then sky:Destroy() end
			local hl = char:FindFirstChild("TheftHighlight")
			if hl then hl:Destroy() end
			local bb = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("TheftBillboard")
			if bb then bb:Destroy() end
		end

		-- Spektakulärer Gold-VFX Burst am Altar
		local burstLight = Instance.new("PointLight")
		burstLight.Color = Color3.fromRGB(255, 230, 80)
		burstLight.Range = 35
		burstLight.Brightness = 6.0
		burstLight.Parent = fireCore

		TweenService:Create(burstLight, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0,
			Range = 5,
		}):Play()
		Debris:AddItem(burstLight, 1.2)

		-- UI & Benachrichtigungen
		local currentData = DataManager.Get(player)
		if currentData then
			local PlotService = require(ServicesMod:WaitForChild("PlotService") :: ModuleScript)
			GoldUpdatedEvent:FireClient(player, currentData.Gold, PlotService.CalculateCPS(player))
		end

		-- Einzelne Erfolgs-Nachricht an den Spieler
		NotificationEvent:FireClient(player, string.format("🔥 %s-Seelenkern (Stufe %d) eingeschmolzen! +%d Gold erhalten!", coreName, coreLevel, goldGain), false)

		-- Nur an ANDERE Spieler im Server senden (kein doppelter Toast für den Spieler)
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player then
				NotificationEvent:FireClient(otherPlayer, string.format("🏆 %s hat einen Seelenkern am Altar eingeschmolzen!", player.DisplayName), false)
			end
		end
	end)

	return altar
end

-- ============================================================================
-- 4. MINION KI-LOOP & VERWALTUNG
-- ============================================================================

local function startMinionAILoop()
	task.spawn(function()
		while true do
			task.wait(0.35)

			for model, minion in pairs(activeMinions) do
				if not model.Parent or minion.IsDead or minion.Humanoid.Health <= 0 then
					continue
				end

				local root = minion.RootPart
				local hum = minion.Humanoid
				local plot = minion.PlotModel
				local ownerId = (plot:GetAttribute("OwnerUserId") :: number?) or minion.OwnerUserId

				local floor = plot:FindFirstChild("PlotFloor") :: BasePart?
				local plotCenter = if floor then floor.Position else minion.HomePosition
				local plotRadius = 22 -- Plot-Größe 40x40 -> Radius ca. 20-22 Studs

				-- 1. Suche nach Feinden auf dem Plot (Eindringlinge, die nicht Besitzer sind)
				local closestEnemy: Player? = nil
				local closestDist = math.huge

				for _, player in Players:GetPlayers() do
					-- Besitzer wird niemals attackiert
					if player.UserId == ownerId and ownerId ~= 0 then
						continue
					end

					local pChar = player.Character
					local pHum = if pChar then pChar:FindFirstChild("Humanoid") :: Humanoid? else nil
					local pRoot = if pChar then pChar:FindFirstChild("HumanoidRootPart") :: BasePart? else nil

					if pHum and pHum.Health > 0 and pRoot then
						-- Distanz zum Plot-Zentrum
						local distToPlot = (Vector2.new(pRoot.Position.X, pRoot.Position.Z) - Vector2.new(plotCenter.X, plotCenter.Z)).Magnitude
						if distToPlot <= plotRadius then
							-- Befindet sich auf dem Plot!
							local distToMinion = (pRoot.Position - root.Position).Magnitude
							if distToMinion < closestDist then
								closestDist = distToMinion
								closestEnemy = player
							end
						end
					end
				end

				-- 2. Verhalten steuern
				local tag = model:FindFirstChild("Head") and model.Head:FindFirstChild("MinionTag")
				local label = tag and tag:FindFirstChild("StatusLabel") :: TextLabel?

				if closestEnemy then
					-- FEIND ENTDECKT! -> AGGRO-MODUS
					minion.TargetPlayer = closestEnemy
					local targetChar = closestEnemy.Character
					local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
					local targetHum = targetChar and targetChar:FindFirstChild("Humanoid") :: Humanoid?

					if targetRoot and targetHum then
						-- Augen leuchten rot
						for _, eye in ipairs(minion.Eyes) do
							eye.Color = Color3.fromRGB(255, 30, 30)
						end
						if label then
							label.Text = "🚨 ANGRIFF! (" .. closestEnemy.DisplayName .. ")"
							label.TextColor3 = Color3.fromRGB(231, 76, 60)
						end

						-- Auf den Feind zubewegen
						hum:MoveTo(targetRoot.Position)

						-- Nahkampf-Attacke (Reichweite <= 6.5 Studs, Cooldown 1.2s)
						local attackDist = (targetRoot.Position - root.Position).Magnitude
						if attackDist <= 6.5 and (os.clock() - minion.LastAttackTime >= 1.2) then
							minion.LastAttackTime = os.clock()

							-- Schaden zufügen
							local damage = 15
							targetHum:TakeDamage(damage)

							-- Schlag-Effekt (Schwung)
							local axe = model:FindFirstChild("MinionAxe") :: BasePart?
							if axe then
								local originalAxePos = axe.Position
								TweenService:Create(axe, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									Position = originalAxePos + (targetRoot.Position - root.Position).Unit * 1.5,
								}):Play()
								task.delay(0.15, function()
									if axe and axe.Parent then
										TweenService:Create(axe, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
											Position = originalAxePos,
										}):Play()
									end
								end)
							end
						end
					end
				else
					-- KEIN FEIND AUF DEM PLOT -> ZURÜCK ZUM POSTEN
					if minion.TargetPlayer ~= nil then
						minion.TargetPlayer = nil
						for _, eye in ipairs(minion.Eyes) do
							eye.Color = Color3.fromRGB(255, 230, 40)
						end
						if label then
							label.Text = "🛡️ BASIS-WÄCHTER"
							label.TextColor3 = Color3.fromRGB(46, 204, 113)
						end
					end

					-- Zurück zur Heimatposition gehen
					local distToHome = (root.Position - minion.HomePosition).Magnitude
					if distToHome > 3.0 then
						hum:MoveTo(minion.HomePosition)
					end

					-- Langsam regenerieren
					if hum.Health < hum.MaxHealth then
						hum.Health = math.min(hum.MaxHealth, hum.Health + 2)
					end
				end
			end
		end
	end)
end

-- ============================================================================
-- 5. SERVICE INITIALISIERUNG
-- ============================================================================

function DefenseService.SetupPlotDefenses(plotModel: Model, ownerUserId: number)
	-- Bestehende Verteidigungs-Modelle auf dem Plot bereinigen
	for _, child in plotModel:GetChildren() do
		if child.Name == "SpikeTrap" or child.Name == "GuardMinion" or child.Name == "SecuringAltar" then
			child:Destroy()
		end
	end

	-- 1. Schmelz-Altar aufbauen (Hinten rechts auf dem Plot)
	-- WICHTIG: NUR auf echten Spieler-Plots! Niemals auf freien Plots (0) und niemals beim Rivalen (999999)!
	if ownerUserId > 0 and ownerUserId ~= 999999 then
		DefenseService.CreateSecuringAltar(plotModel, Vector3.new(13.5, 0.5, 13.5))
	end

	-- 2. Zwei Stachelfallen & Wächter aufbauen (NUR wenn Plot vergeben ist oder Rivale)
	if ownerUserId > 0 then
		DefenseService.CreateSpikeTrap(plotModel, Vector3.new(-12, 0.5, -8), ownerUserId)
		DefenseService.CreateSpikeTrap(plotModel, Vector3.new(12, 0.5, -8), ownerUserId)
		DefenseService.CreateGuardMinion(plotModel, Vector3.new(0, 0.5, -6), ownerUserId)
	end

	print(string.format("[DefenseService] Verteidigungsanlagen für Plot '%s' aufgebaut (Besitzer: %d).", plotModel.Name, ownerUserId))
end

function DefenseService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	startMinionAILoop()
	print("[DefenseService] Minion-KI-Loop und Stachelfallen-System aktiv.")
end

return DefenseService
