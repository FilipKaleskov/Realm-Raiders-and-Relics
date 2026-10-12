--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local NotificationEvent = EventsFolder:WaitForChild("ShowNotification") :: RemoteEvent

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

-- Startet das Sprinten
local function startSprint()
	if isCarryingCore() then
		if os.clock() - lastWarnTime > 2 then
			lastWarnTime = os.clock()
			NotificationEvent:Fire("❌ Kein Sprinten möglich, während du einen Seelenkern trägst!", true)
		end
		return
	end

	if not currentHumanoid or currentHumanoid.Health <= 0 then
		return
	end

	isSprinting = true
	currentHumanoid.WalkSpeed = SPRINT_WALK_SPEED
	setCameraFOV(SPRINT_FOV)
end

-- Beendet das Sprinten
local function stopSprint()
	isSprinting = false

	if not currentHumanoid or currentHumanoid.Health <= 0 then
		setCameraFOV(DEFAULT_FOV)
		return
	end

	if isCarryingCore() then
		currentHumanoid.WalkSpeed = CARRYING_WALK_SPEED
	else
		currentHumanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end
	setCameraFOV(DEFAULT_FOV)
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
	end)
end

-- Erstellt einen Touch-Sprint-Button für Mobilgeräte
local function setupMobileSprintButton()
	if not UserInputService.TouchEnabled then
		return
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local screenGui = playerGui:FindFirstChild("MobileSprintGui") :: ScreenGui?
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "MobileSprintGui"
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 10
		screenGui.Parent = playerGui
	end

	local sprintBtn = Instance.new("ImageButton")
	sprintBtn.Name = "MobileSprintButton"
	sprintBtn.Size = UDim2.new(0, 58, 0, 58)
	sprintBtn.Position = UDim2.new(1, -85, 1, -155)
	sprintBtn.BackgroundColor3 = Color3.fromRGB(26, 44, 52)
	sprintBtn.BorderSizePixel = 0
	sprintBtn.AutoButtonColor = false
	sprintBtn.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 29)
	corner.Parent = sprintBtn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 255, 25)
	stroke.Thickness = 2.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = sprintBtn

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "🏃"
	label.TextSize = 28
	label.Font = Enum.Font.GothamBlack
	label.Parent = sprintBtn

	local touchActive = false
	sprintBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchActive = not touchActive
			if touchActive then
				sprintBtn.BackgroundColor3 = Color3.fromRGB(105, 225, 0)
				startSprint()
			else
				sprintBtn.BackgroundColor3 = Color3.fromRGB(26, 44, 52)
				stopSprint()
			end
		end
	end)
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
		else
			if isShiftDown then
				startSprint()
			else
				if currentHumanoid then
					currentHumanoid.WalkSpeed = DEFAULT_WALK_SPEED
				end
			end
		end
	end)

	setupMobileSprintButton()
	print("[MovementController] Initialisiert: Sprinten aktiv (WalkSpeed 16 -> 26, Dynamisches FOV 70 -> 82, Raid-Sperre).")
end

return MovementController
