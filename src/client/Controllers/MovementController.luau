--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local NotificationEvent = EventsFolder:WaitForChild("ShowNotification") :: RemoteEvent

local ConfigFolder = Shared:WaitForChild("Config")
local AudioConfigModule = ConfigFolder:WaitForChild("AudioConfig") :: ModuleScript
local AudioConfig = require(AudioConfigModule)

local MovementController = {}
local isInitialized = false

-- Geschwindigkeits- & Kamera-Konfiguration
local DEFAULT_WALK_SPEED = 16
local SPRINT_WALK_SPEED = 26
local CARRYING_WALK_SPEED = 10

local DEFAULT_FOV = 70
local SPRINT_FOV = 82

local isSprinting = false
local isShiftDown = false
local currentHumanoid: Humanoid? = nil
local lastWarnTime = 0
local runningPuffAtt: Attachment? = nil
local runningPuffEmitter: ParticleEmitter? = nil

-- Prüft, ob der Spieler gerade einen Seelenkern stiehlt / trägt
local function isCarryingCore(): boolean
	return LocalPlayer:GetAttribute("CarryingCore") ~= nil
end

-- Passt das Field of View (FOV) sanft an
local function setCameraFOV(targetFOV: number)
	if not Camera then
		Camera = Workspace.CurrentCamera
	end
	if Camera then
		TweenService:Create(
			Camera,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = targetFOV }
		):Play()
	end
end

-- Erstellt / entfernt Footstep-Staubpartikel beim Sprinten ("Running Puffs" aus dem Pitch-Video)
local function setRunningPuffs(enabled: boolean)
	local char = LocalPlayer.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	if enabled then
		if runningPuffAtt then return end
		runningPuffAtt = Instance.new("Attachment")
		runningPuffAtt.Name = "RunPuffAtt"
		runningPuffAtt.Position = Vector3.new(0, -2.8, 0)
		runningPuffAtt.Parent = root

		runningPuffEmitter = Instance.new("ParticleEmitter")
		runningPuffEmitter.Name = "RunPuffEmitter"
		runningPuffEmitter.Rate = 18
		runningPuffEmitter.Lifetime = NumberRange.new(0.35, 0.65)
		runningPuffEmitter.Speed = NumberRange.new(2.5, 5.5)
		runningPuffEmitter.SpreadAngle = Vector2.new(70, 70)
		runningPuffEmitter.Size = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(0.5, 2.2),
			NumberSequenceKeypoint.new(1, 0),
		}
		runningPuffEmitter.Transparency = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.8),
			NumberSequenceKeypoint.new(1, 1.0),
		}
		runningPuffEmitter.Color = ColorSequence.new(Color3.fromRGB(210, 205, 195))
		runningPuffEmitter.LightEmission = 0.05
		runningPuffEmitter.RotSpeed = NumberRange.new(-90, 90)
		runningPuffEmitter.Rotation = NumberRange.new(-45, 45)
		runningPuffEmitter.Parent = runningPuffAtt
	else
		if runningPuffAtt then
			runningPuffAtt:Destroy()
			runningPuffAtt = nil
			runningPuffEmitter = nil
		end
	end
end

-- Zeigt das ikonische rote "BASE INTRUDED!"-Comic-Banner (wie im Pitch-Video)
local function showBaseIntrudedBanner(thiefName: string?, coreName: string?)
	-- 🚨 RaidAlarmSiren: Schrilles Warnhorn synchron zum roten Banner (2D -> beim Opfer garantiert hörbar).
	-- Ein zweiter Puls folgt kurz darauf, damit die Sirene den Raubzug akustisch antreibt.
	AudioConfig.PlayTag("RaidAlarmSiren")
	task.delay(2.4, function()
		AudioConfig.PlayTag("RaidAlarmSiren")
	end)

	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local existing = playerGui:FindFirstChild("BaseIntrudedGui")
	if existing then existing:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name = "BaseIntrudedGui"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui

	-- Sternenburst-Hintergrund (gezackter roter Rahmen)
	local burst = Instance.new("Frame")
	burst.Name = "StarBurst"
	burst.Size = UDim2.new(0, 780, 0, 160)
	burst.Position = UDim2.new(0.5, -390, 0, -180) -- startet oben außerhalb
	burst.BackgroundColor3 = Color3.fromRGB(200, 22, 22)
	burst.BorderSizePixel = 0
	burst.ZIndex = 30
	burst.AnchorPoint = Vector2.new(0, 0)
	burst.Parent = sg

	local burstCorner = Instance.new("UICorner")
	burstCorner.CornerRadius = UDim.new(0, 12)
	burstCorner.Parent = burst

	local burstStroke = Instance.new("UIStroke")
	burstStroke.Color = Color3.fromRGB(255, 80, 80)
	burstStroke.Thickness = 5
	burstStroke.Parent = burst

	-- Zackige Dekoration (kleine Dreiecks-Indikator-Rechtecke an den Ecken)
	local function addSpike(xOff: number, yOff: number, rot: number)
		local spike = Instance.new("Frame")
		spike.Size = UDim2.new(0, 30, 0, 30)
		spike.Position = UDim2.new(0, xOff, 0, yOff)
		spike.Rotation = rot
		spike.BackgroundColor3 = Color3.fromRGB(200, 22, 22)
		spike.BorderSizePixel = 0
		spike.ZIndex = 29
		spike.Parent = sg
	end
	addSpike(100, 10, 30)
	addSpike(660, 10, -30)
	addSpike(100, 120, -30)
	addSpike(660, 120, 30)

	-- Haupt-Text: "BASE INTRUDED!" in Weiß, fett, GothamBlack mit Kontur
	local mainLabel = Instance.new("TextLabel")
	mainLabel.Name = "MainText"
	mainLabel.Size = UDim2.new(1, -20, 0, 85)
	mainLabel.Position = UDim2.new(0, 10, 0, 10)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Text = "🚨  BASE INTRUDED!  🚨"
	mainLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.TextSize = 62
	mainLabel.TextTransparency = 1
	mainLabel.ZIndex = 31
	mainLabel.Parent = burst

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(100, 0, 0)
	mainStroke.Thickness = 5
	mainStroke.Transparency = 1
	mainStroke.Parent = mainLabel

	-- Sub-Text: Spieler-Info (falls der Server Name & Kern mitgeliefert hat)
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubText"
	subLabel.Size = UDim2.new(1, -20, 0, 40)
	subLabel.Position = UDim2.new(0, 10, 0, 92)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = if thiefName and coreName
		then string.format("⚠️  %s STIEHLT DEINEN %s-KERN!", string.upper(thiefName), string.upper(coreName))
		else "⚠️  EIN SPIELER STIEHLT DEINEN SEELENKERN!"
	subLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	subLabel.Font = Enum.Font.GothamBlack
	subLabel.TextSize = 22
	subLabel.TextTransparency = 1
	subLabel.ZIndex = 31
	subLabel.Parent = burst
	local subStroke = Instance.new("UIStroke")
	subStroke.Color = Color3.fromRGB(80, 30, 0)
	subStroke.Thickness = 3
	subStroke.Transparency = 1
	subStroke.Parent = subLabel

	-- Animation: Von oben einfliegen + Pulsieren
	task.spawn(function()
		-- Einflug von oben
		TweenService:Create(burst, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -390, 0, 18)
		}):Play()
		task.wait(0.15)
		TweenService:Create(mainLabel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
		TweenService:Create(mainStroke, TweenInfo.new(0.18), { Transparency = 0 }):Play()
		task.wait(0.2)
		TweenService:Create(subLabel, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.15), { Transparency = 0 }):Play()

		-- Puls-Schlag (3x Rot-Weiß flashen)
		for _ = 1, 3 do
			task.wait(0.22)
			TweenService:Create(burst, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(255, 60, 60) }):Play()
			task.wait(0.1)
			TweenService:Create(burst, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(200, 22, 22) }):Play()
		end

		-- Kamera-Schütteln (Sirenen-Effekt über Humanoid.CameraOffset)
		local char = LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.Health > 0 then
			for _ = 1, 5 do
				hum.CameraOffset = Vector3.new(
					(math.random() - 0.5) * 0.35,
					(math.random() - 0.5) * 0.35,
					0
				)
				task.wait(0.04)
			end
			hum.CameraOffset = Vector3.zero
		end

		task.wait(2.0)
		-- Ausblenden nach oben
		TweenService:Create(mainLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(subLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(burst, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, -390, 0, -200)
		}):Play()
		task.wait(0.4)
		sg:Destroy()
	end)
end

-- ==========================================
-- PHASE 3: SPRINT-ZUSTANDS-BEOBACHTER (für den mobilen Sprint-Toggle-Button)
-- Der MobileControlsController reagiert damit ohne Polling auf Sprint- & Walk-of-Shame-Änderungen.
-- ==========================================
export type SprintStateListener = (isSprinting: boolean, isLocked: boolean) -> ()

local sprintListeners: { [SprintStateListener]: boolean } = {}

-- Meldet allen Beobachtern den aktuellen Zustand (Sprinten an/aus + Walk-of-Shame-Sperre)
local function fireSprintStateChanged()
	local locked = isCarryingCore()
	for listener in pairs(sprintListeners) do
		task.spawn(listener, isSprinting, locked)
	end
end

-- Startet das Sprinten
local function startSprint()
	if isCarryingCore() then
		if os.clock() - lastWarnTime > 2 then
			lastWarnTime = os.clock()
			NotificationEvent:Fire("❌ Kein Sprinten möglich, während du einen Seelenkern trägst!", true)
		end
		fireSprintStateChanged()
		return
	end

	if not currentHumanoid or currentHumanoid.Health <= 0 then
		fireSprintStateChanged()
		return
	end

	isSprinting = true
	currentHumanoid.WalkSpeed = SPRINT_WALK_SPEED
	setCameraFOV(SPRINT_FOV)
	setRunningPuffs(true)
	fireSprintStateChanged()
end

-- Beendet das Sprinten
local function stopSprint()
	isSprinting = false
	setRunningPuffs(false)

	if not currentHumanoid or currentHumanoid.Health <= 0 then
		setCameraFOV(DEFAULT_FOV)
		fireSprintStateChanged()
		return
	end

	if isCarryingCore() then
		currentHumanoid.WalkSpeed = CARRYING_WALK_SPEED
	else
		currentHumanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end
	setCameraFOV(DEFAULT_FOV)
	fireSprintStateChanged()
end

-- Bindet Humanoid des Spieler-Charakters
local function hookHumanoid(character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end

	currentHumanoid = hum
	isSprinting = false
	setCameraFOV(DEFAULT_FOV)

	if isCarryingCore() then
		hum.WalkSpeed = CARRYING_WALK_SPEED
	else
		hum.WalkSpeed = DEFAULT_WALK_SPEED
	end

	hum.Died:Connect(function()
		isSprinting = false
		setCameraFOV(DEFAULT_FOV)
		fireSprintStateChanged()
	end)

	fireSprintStateChanged()
end

-- ==========================================
-- PHASE 3: ÖFFENTLICHE SPRINT-API (Tastatur, Gamepad UND Touch)
-- ==========================================

-- Registriert einen Beobachter für Sprint-Änderungen und liefert eine Abmelde-Funktion.
-- Der Beobachter erhält sofort einmal den aktuellen Zustand (isSprinting, isLocked).
function MovementController.ObserveSprintState(listener: SprintStateListener): () -> ()
	sprintListeners[listener] = true
	listener(isSprinting, isCarryingCore())
	return function()
		sprintListeners[listener] = nil
	end
end

-- Schaltet das Sprinten um (mobiler Touch-Button, Gamepad L3 oder Tastatur-Shift).
-- Rückgabe: true, wenn danach tatsächlich gesprintet wird.
function MovementController.ToggleSprint(): boolean
	if isSprinting then
		stopSprint()
		return isSprinting
	end
	startSprint()
	return isSprinting
end

-- true, wenn der Spieler gerade sprintet
function MovementController.IsSprinting(): boolean
	return isSprinting
end

-- Walk of Shame: Mit einem gestohlenen Seelenkern ist Sprinten gesperrt
function MovementController.IsSprintLocked(): boolean
	return isCarryingCore()
end

function MovementController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	if LocalPlayer.Character then
		hookHumanoid(LocalPlayer.Character)
	end
	LocalPlayer.CharacterAdded:Connect(hookHumanoid)

	-- Tastenbindung: LeftShift / RightShift (Halten) oder ButtonL3 (Gamepad Toggle)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		local code = input.KeyCode
		if code == Enum.KeyCode.LeftShift or code == Enum.KeyCode.RightShift then
			isShiftDown = true
			startSprint()
		elseif code == Enum.KeyCode.ButtonL3 then
			if isSprinting then
				stopSprint()
			else
				startSprint()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local code = input.KeyCode
		if code == Enum.KeyCode.LeftShift or code == Enum.KeyCode.RightShift then
			isShiftDown = false
			stopSprint()
		end
	end)

	-- Automatische Reaktion bei Raubzug: Wenn Kern aufgenommen wird -> Sprint sofort abbrechen
	LocalPlayer:GetAttributeChangedSignal("CarryingCore"):Connect(function()
		if isCarryingCore() then
			if isSprinting then
				stopSprint()
			end
			if currentHumanoid then
				currentHumanoid.WalkSpeed = CARRYING_WALK_SPEED
			end
			-- Eigene Basis wird überfallen: BASE INTRUDED! Banner (das Banner erscheint beim OPFER)
			-- (Die Eigenschaft CarryingCore ist auf dem DIEB, nicht dem Opfer gesetzt - deshalb
			--  wird das Banner serverseitig via Notification/Extra-Event an das Opfer gesendet)
			fireSprintStateChanged()
		else
			setRunningPuffs(false)
			if isShiftDown then
				startSprint()
			else
				if currentHumanoid then
					currentHumanoid.WalkSpeed = DEFAULT_WALK_SPEED
				end
				fireSprintStateChanged()
			end
		end
	end)

	-- BASE INTRUDED! Banner + RaidAlarmSiren via speziellem Event (wird vom Server an das Opfer gesendet)
	local BaseIntrudedEvent = EventsFolder:WaitForChild("BaseIntruded") :: RemoteEvent
	BaseIntrudedEvent.OnClientEvent:Connect(function(thiefName: string?, coreName: string?)
		showBaseIntrudedBanner(thiefName, coreName)
	end)

	-- Hinweis: Der mobile Sprint-Toggle-Button wird vom MobileControlsController
	-- (Phase 3, "RealmRaidersMobileGui") erstellt und ruft MovementController.ToggleSprint() auf.

	print("[MovementController] Initialisiert: Sprinten aktiv (WalkSpeed 16 -> 26, Dynamisches FOV 70 -> 82, Raid-Sperre, RunningPuffs, BASE INTRUDED! Banner).")
end

return MovementController
