--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local AttackIntent = EventsFolder:WaitForChild("AttackIntent") :: RemoteEvent
local BossTelegraph = EventsFolder:WaitForChild("BossTelegraphStarted") :: RemoteEvent
local BossDefeated = EventsFolder:WaitForChild("BossDefeated") :: RemoteEvent
local InventoryUpdated = EventsFolder:WaitForChild("InventoryUpdated") :: RemoteEvent
local EntityDamaged = EventsFolder:WaitForChild("EntityDamaged") :: RemoteEvent

local ConfigFolder = Shared:WaitForChild("Config")
local ItemConfigModule = ConfigFolder:WaitForChild("ItemConfig") :: ModuleScript
local ItemConfig = require(ItemConfigModule)
local AudioConfigModule = ConfigFolder:WaitForChild("AudioConfig") :: ModuleScript
local AudioConfig = require(AudioConfigModule)

local CombatController = {}
local isInitialized = false
local lastAttackTime = 0
local lastDashTime = 0
local DASH_COOLDOWN = 1.2
local currentAttackCooldown = 0.35
local equippedWeaponId = "RustySword"

-- Prüft, ob sich die Kamera in der Egoperspektive (First-Person) befindet
local function isFirstPerson(): boolean
	if not Camera then
		Camera = Workspace.CurrentCamera
	end
	if not Camera then
		return false
	end
	local char = LocalPlayer.Character
	if not char then
		return false
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then
		return false
	end
	return (Camera.CFrame.Position - head.Position).Magnitude < 1.4
end

-- Spielt einen kleinen visuellen Schwertschwung / Screenshake + Klingen-Whoosh ab
local function playAttackFeedback()
	local char = LocalPlayer.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Klingen-Whoosh mit Pitch-Variation (sofort hörbar -> Null-Latenz-Gefühl)
	AudioConfig.PlayTag("SwordSwing", root)

	-- Subtiler Camera Punch über Humanoid.CameraOffset (funktioniert nahtlos in First-Person & Third-Person ohne CFrame-Reset!)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		local punchOffset = if isFirstPerson()
			then Vector3.new(0.03, -0.05, -0.04)
			else Vector3.new(0.04, -0.08, -0.06)

		local punch = TweenService:Create(
			hum,
			TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CameraOffset = punchOffset }
		)
		local reset = TweenService:Create(
			hum,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CameraOffset = Vector3.zero }
		)
		punch:Play()
		punch.Completed:Connect(function()
			reset:Play()
		end)
	end

	-- Klingen-Schwung-Trail: Farbe & Stil passen sich der ausgerüsteten Waffe an
	if not root then
		return
	end

	local itemInfo = ItemConfig[equippedWeaponId]
	local mainColor = if itemInfo and itemInfo.TrailColor then itemInfo.TrailColor else Color3.fromRGB(255, 220, 60)
	local secColor = if itemInfo and itemInfo.TrailSecondaryColor then itemInfo.TrailSecondaryColor else Color3.fromRGB(255, 160, 0)

	local inFP = isFirstPerson()
	local slashPart = Instance.new("Part")
	slashPart.Name = "SlashTrail"
	slashPart.Material = Enum.Material.Neon
	slashPart.Color = mainColor
	slashPart.Transparency = 1 -- Vollständig unsichtbar, damit kein Neon-Klotz im Sichtfeld clippt!
	slashPart.CanCollide = false
	slashPart.CastShadow = false
	slashPart.Anchored = true

	local startCF: CFrame
	local endCF: CFrame
	local halfHeight: number

	if inFP and Camera then
		-- In Egoperspektive: Folgt dynamisch der Blickrichtung der Kamera (inkl. Auf-/Absehen!)
		halfHeight = 1.2
		slashPart.Size = Vector3.new(0.05, halfHeight * 2, 0.05)
		startCF = Camera.CFrame * CFrame.new(0.55, 0.25, -1.9) * CFrame.Angles(math.rad(28), math.rad(-15), math.rad(35))
		endCF = Camera.CFrame * CFrame.new(-0.65, -0.35, -1.9) * CFrame.Angles(math.rad(-22), math.rad(20), math.rad(-40))
	else
		-- In Third-Person: Ausrichtung am HumanoidRootPart
		halfHeight = 2.4
		slashPart.Size = Vector3.new(0.1, halfHeight * 2, 0.1)
		startCF = root.CFrame * CFrame.new(-0.2, 0.5, -2.5) * CFrame.Angles(math.rad(45), 0, 0)
		endCF = root.CFrame * CFrame.new(1.5, -0.3, -2.8) * CFrame.Angles(math.rad(-30), math.rad(35), 0)
	end

	slashPart.CFrame = startCF
	slashPart.Parent = Workspace

	-- Schimmer-Trail-Part (eleganter Lichtbogen)
	local trailAtt0 = Instance.new("Attachment")
	trailAtt0.Position = Vector3.new(0, halfHeight, 0)
	trailAtt0.Parent = slashPart
	local trailAtt1 = Instance.new("Attachment")
	trailAtt1.Position = Vector3.new(0, -halfHeight, 0)
	trailAtt1.Parent = slashPart

	local trail = Instance.new("Trail")
	trail.Attachment0 = trailAtt0
	trail.Attachment1 = trailAtt1
	trail.Lifetime = if inFP then 0.15 else 0.18
	trail.MinLength = 0
	trail.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, mainColor),
		ColorSequenceKeypoint.new(1, secColor),
	}
	trail.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.0), NumberSequenceKeypoint.new(1, 1.0) }
	trail.WidthScale = NumberSequence.new(1)
	trail.Parent = slashPart

	-- Sweep-Animation
	local sweepDuration = if inFP then 0.15 else 0.18
	local sweepTween = TweenService:Create(
		slashPart,
		TweenInfo.new(sweepDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = endCF }
	)
	sweepTween:Play()
	sweepTween.Completed:Connect(function()
		task.delay(0.08, function()
			slashPart:Destroy()
		end)
	end)
end

-- Spielt Screenshake bei telegrafiertem Boss-Angriff (über Humanoid.CameraOffset)
local function playWarningShake()
	local char = LocalPlayer.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not hum or hum.Health <= 0 then
		return
	end

	task.spawn(function()
		for _ = 1, 6 do
			hum.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 0.35,
				(math.random() - 0.5) * 0.35,
				0
			)
			task.wait(0.03)
		end
		hum.CameraOffset = Vector3.zero
	end)
end

-- Erzeugt den blauen Flammen-Dash-Trail-VFX (wie im Pitch-Video)
local function spawnBlueDashVFX()
	local char = LocalPlayer.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	-- In First-Person keine Ghost-Parts auf Kopfhöhe spawnen, um Sicht nicht zu verdecken!
	local inFP = isFirstPerson()
	local startStep = if inFP then 2 else 0

	-- Erstelle Nachleucht-Partikel in Cyan/Blau hinter dem Spieler
	for step = startStep, 7 do
		task.delay(step * 0.025, function()
			if not char:IsDescendantOf(Workspace) then return end
			local ghostPart = Instance.new("Part")
			ghostPart.Size = if inFP then Vector3.new(1.4, 2.0, 1.0) else Vector3.new(1.8, 3.0, 1.2)
			local yOffset = if inFP then -0.5 else 0.2
			local zDist = if inFP then (step + 1) * 0.8 else step * 0.4
			ghostPart.CFrame = root.CFrame * CFrame.new(0, yOffset, zDist)
			ghostPart.Material = Enum.Material.Neon
			ghostPart.Color = if step < 4 then Color3.fromRGB(0, 200, 255) else Color3.fromRGB(0, 130, 255)
			ghostPart.Transparency = 0.35 + step * 0.09
			ghostPart.CanCollide = false
			ghostPart.Anchored = true
			ghostPart.CastShadow = false
			ghostPart.Parent = Workspace
			-- Verblassen und verschwinden
			TweenService:Create(
				ghostPart,
				TweenInfo.new(0.22, Enum.EasingStyle.Linear),
				{ Transparency = 1 }
			):Play()
			game:GetService("Debris"):AddItem(ghostPart, 0.25)
		end)
	end

	-- Cyan-Aura Partikel (SpreadAngle)
	local att = Instance.new("Attachment")
	att.Parent = root
	local particles = Instance.new("ParticleEmitter")
	particles.Rate = 0
	particles.Lifetime = NumberRange.new(0.3, 0.55)
	particles.Speed = NumberRange.new(8, 18)
	particles.SpreadAngle = Vector2.new(60, 60)
	particles.Size = NumberSequence.new{ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0) }
	particles.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 100, 255)),
	}
	particles.LightEmission = 0.95
	particles.Parent = att
	particles:Emit(22)
	task.delay(0.15, function()
		particles:Destroy()
		att:Destroy()
	end)
end

-- Führt den Vorwärts-Dash aus (Physik-Impuls über BodyVelocity)
local function executeDash()
	local char = LocalPlayer.Character
	if not char then return end

	-- Kein Dash beim Walk-of-Shame
	if LocalPlayer:GetAttribute("CarryingCore") ~= nil then
		return
	end

	local hum = char:FindFirstChild("Humanoid") :: Humanoid?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then return end

	local now = os.clock()
	if now - lastDashTime < DASH_COOLDOWN then return end
	lastDashTime = now

	-- Richtung: Blick-Richtung der Kamera (flach, Y=0)
	local camLook = if Camera then Camera.CFrame.LookVector else root.CFrame.LookVector
	local dashDir = Vector3.new(camLook.X, 0, camLook.Z).Unit

	-- Kurzer BodyVelocity-Schubs
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Velocity = dashDir * 52
	bv.Parent = root

	spawnBlueDashVFX()

	-- Windstoß/Energie-Zischen mit Pitch-Variation
	AudioConfig.PlayTag("DashWhoosh", root)

	-- FoV-Punch: kurz von 70 auf 78 und zurück auf 70 (respektiert vorheriges FOV wie z.B. Sprinten)
	if Camera then
		local origFOV = Camera.FieldOfView
		TweenService:Create(
			Camera,
			TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = math.min(105, origFOV + 8) }
		):Play()
		task.delay(0.12, function()
			TweenService:Create(
				Camera,
				TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = origFOV }
			):Play()
		end)
	end

	-- BodyVelocity nach 0.18s entfernen
	task.delay(0.18, function()
		bv:Destroy()
	end)
end

-- ==========================================
-- PHASE 2: JUICY DAMAGE NUMBERS & HIT-SPARKS (clientseitig, Check-UI Standard)
-- ==========================================

-- Basengröße der schwebenden Schadenszahl (wird für den Bounce skaliert)
local DAMAGE_NUMBER_BASE_SIZE = UDim2.new(0, 130, 0, 46)
local DAMAGE_NUMBER_LIFETIME = 1.1

-- Check-UI Farbcodes: Ausgeteilter Schaden = Gelb/Orange, Krit = Purpur/Gold, Eingesteckt = Rot
local DAMAGE_COLOR_OUTGOING = Color3.fromRGB(255, 210, 40)
local DAMAGE_COLOR_OUTGOING_DEEP = Color3.fromRGB(255, 140, 0)
local DAMAGE_COLOR_CRIT = Color3.fromRGB(190, 80, 255)
local DAMAGE_COLOR_CRIT_GOLD = Color3.fromRGB(255, 215, 0)
local DAMAGE_COLOR_INCOMING = Color3.fromRGB(255, 60, 60)

-- Erstellt eine unsichtbare, nicht kollidierbare Anker-Part (Basis für Billboards, Sounds & Partikel)
local function createEffectAnchor(position: Vector3, name: string): Part
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace
	return anchor
end

-- Erzeugt eine juicy, federnde Schadenszahl mit GothamBlack-Typografie & dicker schwarzer Kontur
-- (Bounce: explosionsartig auf 1.3x, federt zurück, steigt 4 Studs auf und verblasst nach ~0.8s)
local function spawnDamageNumber(position: Vector3, damage: number, isCrit: boolean, isIncoming: boolean)
	local anchor = createEffectAnchor(
		position + Vector3.new(math.random(-12, 12) / 10, 2.7, math.random(-12, 12) / 10),
		"DamageNumberAnchor"
	)

	local baseSize = if isCrit then DAMAGE_NUMBER_BASE_SIZE * 1.25 else DAMAGE_NUMBER_BASE_SIZE

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = baseSize * 0.45 -- Start klein für den Pop
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextTransparency = 1
	label.ZIndex = 2
	label.Parent = billboard

	-- Text & Farbgebung
	if isIncoming then
		-- Eingesteckter Schaden: Alarmierendes Rot
		label.Text = string.format("-%d", math.max(0, math.floor(damage)))
		label.TextColor3 = DAMAGE_COLOR_INCOMING
	elseif isCrit then
		-- Kritischer Treffer / Hohe Waffe: Leuchtendes Purpur/Gold
		label.Text = string.format("💥 CRIT! -%d", math.max(0, math.floor(damage)))
		label.TextColor3 = DAMAGE_COLOR_CRIT
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, DAMAGE_COLOR_CRIT),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 120, 255)),
			ColorSequenceKeypoint.new(1, DAMAGE_COLOR_CRIT_GOLD),
		}
		gradient.Parent = label
	else
		-- Ausgeteilter Schaden: Knalliges Gelb/Orange
		label.Text = string.format("-%d", math.max(0, math.floor(damage)))
		label.TextColor3 = DAMAGE_COLOR_OUTGOING
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, DAMAGE_COLOR_OUTGOING),
			ColorSequenceKeypoint.new(1, DAMAGE_COLOR_OUTGOING_DEEP),
		}
		gradient.Parent = label
	end

	-- Dicker schwarzer Kontur-Stroke (Check-UI Standard)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = if isCrit then 4.0 else 3.2
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	-- Juicy Bounce-Animation: explosionsartig auf 1.3x skalieren, dann leicht zurückfedern
	local popIn = TweenService:Create(
		billboard,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = baseSize * 1.3 }
	)
	local settle = TweenService:Create(
		billboard,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = baseSize }
	)
	TweenService:Create(label, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
	popIn:Play()
	popIn.Completed:Once(function()
		settle:Play()
	end)

	-- Ca. 4 Studs nach oben steigen, während sie nach 0.8s verblasst
	TweenService:Create(
		anchor,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 4, 0) }
	):Play()

	task.delay(0.55, function()
		if not anchor.Parent then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end)

	-- Garantiertes Memory-Cleanup (Anker + Billboard + Label + Stroke auf einen Schlag)
	Debris:AddItem(anchor, DAMAGE_NUMBER_LIFETIME)
end

-- Erzeugt einen kurzen 3D-Neonfunken-Burst an der Einschlagposition (Gold/Gelb, Lebensdauer 0.15s)
local function spawnHitSparks(position: Vector3, isCrit: boolean, isIncoming: boolean)
	local anchor = createEffectAnchor(position + Vector3.new(0, 0.9, 0), "HitSparksAnchor")

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "HitSparks"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.12, 0.15)
	emitter.Speed = NumberRange.new(18, 30)
	emitter.Drag = 4
	emitter.Acceleration = Vector3.new(0, -60, 0)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, if isCrit then 0.42 else 0.3),
		NumberSequenceKeypoint.new(1, 0),
	}
	emitter.Transparency = NumberSequence.new(0.05)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	if isIncoming then
		-- Rot-Orange Funken, wenn der Spieler selbst getroffen wurde
		emitter.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 40)),
		}
	elseif isCrit then
		-- Krit: Purpur/Gold Funken (passend zur Schadenszahl)
		emitter.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(215, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 0)),
		}
	else
		-- Standard: 3D-Neonfunken in Gold/Gelb
		emitter.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 0)),
		}
	end
	emitter.Parent = attachment
	emitter:Emit(if isCrit then 20 else 12)

	-- Partikel leben 0.15s -> Anker nach 0.5s restlos entfernen
	Debris:AddItem(anchor, 0.5)
end

-- Gesamtes Treffer-Feedback: Schadenszahl + Funken + Treffersound (Stein/Fleisch) an der Einschlagposition
local function playHitFeedback(position: Vector3, damage: number, isCrit: boolean, isIncoming: boolean, targetKind: string)
	spawnDamageNumber(position, damage, isCrit, isIncoming)
	spawnHitSparks(position, isCrit, isIncoming)

	-- Treffersound läuft auf einem eigenen Audio-Anker, der die kurzen Funken überlebt und
	-- nach Ablauf des Sounds sofort entfernt wird (keine abgeschnittenen Sounds, kein Leak).
	local audioAnchor = createEffectAnchor(position, "HitSoundAnchor")
	local hitTag: string = if targetKind == "Player" then "SwordHitFlesh" else "SwordHitStone"
	local hitSound = AudioConfig.PlayTag(hitTag, audioAnchor)
	hitSound.Ended:Once(function()
		audioAnchor:Destroy()
	end)
	Debris:AddItem(audioAnchor, 4) -- Sicherheitsnetz, falls das Asset nicht (rechtzeitig) lädt
end

-- ==========================================
-- GOLD CELEBRATION POPUP (Boss besiegt!)
-- ==========================================
local function showGoldCelebration(goldAmount: number)
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local existingGui = playerGui:FindFirstChild("GoldCelebrationGui")
	if existingGui then existingGui:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name = "GoldCelebrationGui"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui

	-- Riesen-Schriftzug: "+150,000!" in Gold mit Kontur (wie im Pitch-Video)
	local formatted = string.gsub(tostring(math.floor(goldAmount)), "^(-?%d+)(%d%d%d)$", "%1,%2")
	-- Mehrfach-Format für große Zahlen
	while true do
		local result, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if count == 0 then break end
		formatted = result
	end

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldPopup"
	goldLabel.Size = UDim2.new(0, 600, 0, 120)
	goldLabel.Position = UDim2.new(0.5, -300, 0.28, 0)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "+" .. formatted .. "!"
	goldLabel.TextColor3 = Color3.fromRGB(255, 235, 30)
	goldLabel.Font = Enum.Font.GothamBlack
	goldLabel.TextSize = 90
	goldLabel.TextTransparency = 1
	goldLabel.ZIndex = 20
	goldLabel.Parent = sg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 60, 0)
	stroke.Thickness = 6
	stroke.Transparency = 1
	stroke.Parent = goldLabel

	-- "BOSS BESIEGT!" Sub-Text
	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(0, 500, 0, 55)
	subLabel.Position = UDim2.new(0.5, -250, 0.38, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "⭐  BOSS BESIEGT!  ⭐"
	subLabel.TextColor3 = Color3.fromRGB(255, 200, 40)
	subLabel.Font = Enum.Font.GothamBlack
	subLabel.TextSize = 36
	subLabel.TextTransparency = 1
	subLabel.ZIndex = 20
	subLabel.Parent = sg
	local subStroke = Instance.new("UIStroke")
	subStroke.Color = Color3.fromRGB(80, 40, 0)
	subStroke.Thickness = 4
	subStroke.Transparency = 1
	subStroke.Parent = subLabel

	-- Skalierungsstart klein -> groß (Bounce-Effekt)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.3
	uiScale.Parent = sg

	-- Animation: Einblenden + Bounce + Ausblenden
	task.spawn(function()
		-- Phase 1: Pop-In
		TweenService:Create(goldLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
		task.wait(0.45)
		TweenService:Create(subLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
		task.wait(1.6)
		-- Phase 2: Aufsteigen & Ausblenden
		TweenService:Create(goldLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(subLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.35 }):Play()
		task.wait(0.55)
		sg:Destroy()
	end)

	-- Kamera-Schütteln beim Boss-Kill über Humanoid.CameraOffset
	local char = LocalPlayer.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if hum and hum.Health > 0 then
		task.spawn(function()
			for _ = 1, 8 do
				hum.CameraOffset = Vector3.new(
					(math.random() - 0.5) * 0.45,
					(math.random() - 0.5) * 0.45,
					0
				)
				task.wait(0.04)
			end
			hum.CameraOffset = Vector3.zero
		end)
	end
end

-- Verarbeitet Eingaben
local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	-- Linksklick (Maus), Touch (Mobile) oder Taste 'F' für Angriff
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.F then

		-- Kein Angriff, wenn Menüs offen sind (z.B. Shop oder Inventar)
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			local rrUI = playerGui:FindFirstChild("RealmRaidersUI")
			if rrUI then
				local shopWin = rrUI:FindFirstChild("BlacksmithShopWindow")
				if shopWin and shopWin.Visible then
					return
				end
				local invModal = rrUI:FindFirstChild("InventoryModal")
				if invModal and invModal.Visible then
					return
				end
			end
		end

		local now = os.clock()
		if now - lastAttackTime < currentAttackCooldown then
			return
		end
		lastAttackTime = now

		-- Client-Feedback sofort abspielen (Null Latenzgefühl)
		playAttackFeedback()

		-- Server-autoritären Angriffs-Intent senden
		AttackIntent:FireServer()
	end

	-- Q-Taste oder Gamepad-ButtonR2 = Combat-Dash
	if input.KeyCode == Enum.KeyCode.Q
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		executeDash()
	end
end

function CombatController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	UserInputService.InputBegan:Connect(onInputBegan)

	-- Inventar-Updates abhören, um ausgerüstete Waffe & Cooldowns synchron zu halten
	InventoryUpdated.OnClientEvent:Connect(function(inventoryData: any)
		if inventoryData and inventoryData.EquippedWeapon then
			equippedWeaponId = inventoryData.EquippedWeapon
			local itemInfo = ItemConfig[equippedWeaponId]
			if itemInfo and itemInfo.Cooldown then
				currentAttackCooldown = itemInfo.Cooldown
			end
		end
	end)

	BossTelegraph.OnClientEvent:Connect(function(_pos: Vector3, _radius: number, _duration: number)
		playWarningShake()
	end)

	-- Boss-Sieg: Riesiges +Gold Celebration-Popup
	BossDefeated.OnClientEvent:Connect(function(_coreId: string, goldAmount: number)
		showGoldCelebration(goldAmount)
	end)

	-- Server-bestätigter Schaden -> sofortige Client-Juice (Schadenszahlen, Funken, Treffersounds).
	-- isLocalPlayerVictim = true -> Alarmierendes Rot (der lokale Spieler hat Schaden eingesteckt).
	EntityDamaged.OnClientEvent:Connect(function(
		position: Vector3,
		damage: number,
		isCrit: boolean,
		isLocalPlayerVictim: boolean,
		targetKind: string?
	)
		if typeof(position) ~= "Vector3" or typeof(damage) ~= "number" then
			return
		end
		local kind = if typeof(targetKind) == "string" then targetKind else "Boss"
		playHitFeedback(position, damage, isCrit == true, isLocalPlayerVictim == true, kind)
	end)

	print("[CombatController] Initialisiert: Nahkampf (F/Klick), Dash (Q) mit FoV-Punch, Slash-Trail, Damage Numbers, Hit-Sparks & Sound-Juice aktiv.")
end

return CombatController
