--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local AttackIntent = EventsFolder:WaitForChild("AttackIntent") :: RemoteEvent
local BossTelegraph = EventsFolder:WaitForChild("BossTelegraphStarted") :: RemoteEvent

local CombatController = {}
local isInitialized = false
local lastAttackTime = 0

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

	print("[CombatController] Initialisiert: Nahkampf-Input (Linksklick/F) aktiv.")
end

return CombatController
