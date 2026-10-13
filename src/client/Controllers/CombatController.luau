--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local AttackIntent = EventsFolder:WaitForChild("AttackIntent") :: RemoteEvent
local BossTelegraph = EventsFolder:WaitForChild("BossTelegraphStarted") :: RemoteEvent
local BossDefeated = EventsFolder:WaitForChild("BossDefeated") :: RemoteEvent

local CombatController = {}
local isInitialized = false
local lastAttackTime = 0
local lastDashTime = 0
local DASH_COOLDOWN = 1.2

-- Spielt einen kleinen visuellen Schwertschwung / Screenshake ab
local function playAttackFeedback()
	if not Camera then
		return
	end

	-- Subtiler Camera Punch
	local origCFrame = Camera.CFrame
	local punch = TweenService:Create(
		Camera,
		TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = origCFrame * CFrame.Angles(0, 0, math.rad(0.8)) }
	)
	local reset = TweenService:Create(
		Camera,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = origCFrame }
	)
	punch:Play()
	punch.Completed:Connect(function()
		reset:Play()
	end)

	-- Klingen-Schwung-Trail: Cyan/Gold-Bogen der Klinge
	local char = LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local slashPart = Instance.new("Part")
			slashPart.Name = "SlashTrail"
			slashPart.Size = Vector3.new(0.1, 4.5, 0.1)
			slashPart.CFrame = root.CFrame * CFrame.new(0, 0.5, -2.5) * CFrame.Angles(math.rad(45), 0, 0)
			slashPart.Material = Enum.Material.Neon
			slashPart.Color = Color3.fromRGB(255, 220, 60)
			slashPart.CanCollide = false
			slashPart.Anchored = true
			slashPart.Parent = Workspace

			-- Schimmer-Trail-Part (breiterer Lichtbogen)
			local trailAtt0 = Instance.new("Attachment")
			trailAtt0.Position = Vector3.new(0, 2.2, 0)
			trailAtt0.Parent = slashPart
			local trailAtt1 = Instance.new("Attachment")
			trailAtt1.Position = Vector3.new(0, -2.2, 0)
			trailAtt1.Parent = slashPart
			local trail = Instance.new("Trail")
			trail.Attachment0 = trailAtt0
			trail.Attachment1 = trailAtt1
			trail.Lifetime = 0.18
			trail.MinLength = 0
			trail.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 120)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 0)),
			}
			trail.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.0), NumberSequenceKeypoint.new(1, 1.0) }
			trail.WidthScale = NumberSequence.new(1)
			trail.Parent = slashPart

			-- Sweep-Animation (von links oben nach rechts unten)
			local sweepTween = TweenService:Create(
				slashPart,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = root.CFrame * CFrame.new(1.5, -0.3, -2.8) * CFrame.Angles(math.rad(-30), math.rad(35), 0) }
			)
			sweepTween:Play()
			sweepTween.Completed:Connect(function()
				local fadeTween = TweenService:Create(
					slashPart,
					TweenInfo.new(0.12),
					{ Transparency = 1 }
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					slashPart:Destroy()
				end)
			end)
		end
	end
end

-- Spielt Screenshake bei telegrafiertem Boss-Angriff
local function playWarningShake()
	if not Camera then
		return
	end

	task.spawn(function()
		for _ = 1, 6 do
			local offset = Vector3.new(
				(math.random() - 0.5) * 0.4,
				(math.random() - 0.5) * 0.4,
				0
			)
			Camera.CFrame = Camera.CFrame + offset
			task.wait(0.03)
		end
	end)
end

-- Erzeugt den blauen Flammen-Dash-Trail-VFX (wie im Pitch-Video)
local function spawnBlueDashVFX()
	local char = LocalPlayer.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	-- Erstelle 8 schnelle Nachleucht-Partikel in Cyan/Blau hinter dem Spieler
	for step = 0, 7 do
		task.delay(step * 0.025, function()
			if not char:IsDescendantOf(Workspace) then return end
			local ghostPart = Instance.new("Part")
			ghostPart.Size = Vector3.new(1.8, 3.0, 1.2)
			ghostPart.CFrame = root.CFrame * CFrame.new(0, 0.2, step * 0.4)
			ghostPart.Material = Enum.Material.Neon
			ghostPart.Color = if step < 4 then Color3.fromRGB(0, 200, 255) else Color3.fromRGB(0, 130, 255)
			ghostPart.Transparency = 0.3 + step * 0.09
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
	local camLook = Camera.CFrame.LookVector
	local dashDir = Vector3.new(camLook.X, 0, camLook.Z).Unit

	-- Kurzer BodyVelocity-Schubs
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Velocity = dashDir * 52
	bv.Parent = root

	spawnBlueDashVFX()

	-- FOV-Blur-Effekt
	if Camera then
		TweenService:Create(Camera, TweenInfo.new(0.06), { FieldOfView = 95 }):Play()
		task.delay(0.18, function()
			TweenService:Create(Camera, TweenInfo.new(0.22), { FieldOfView = 70 }):Play()
		end)
	end

	-- BodyVelocity nach 0.18s entfernen
	task.delay(0.18, function()
		bv:Destroy()
	end)
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

	-- Kamera-Schütteln beim Boss-Kill
	task.spawn(function()
		for _ = 1, 8 do
			local offset = Vector3.new(
				(math.random() - 0.5) * 0.55,
				(math.random() - 0.5) * 0.55,
				0
			)
			Camera.CFrame = Camera.CFrame + offset
			task.wait(0.04)
		end
	end)
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

		local now = os.clock()
		if now - lastAttackTime < 0.35 then
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

	BossTelegraph.OnClientEvent:Connect(function(_pos: Vector3, _radius: number, _duration: number)
		playWarningShake()
	end)

	-- Boss-Sieg: Riesiges +Gold Celebration-Popup
	BossDefeated.OnClientEvent:Connect(function(_coreId: string, goldAmount: number)
		showGoldCelebration(goldAmount)
	end)

	print("[CombatController] Initialisiert: Nahkampf (F/Klick), Blauer Combat-Dash (Q), Slash-Trail & Gold-Popup aktiv.")
end

return CombatController
