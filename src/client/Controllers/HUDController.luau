--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = Shared:WaitForChild("Events")
local GoldUpdated = Events:WaitForChild("GoldUpdated") :: RemoteEvent
local NotificationEvent = Events:WaitForChild("ShowNotification") :: RemoteEvent

local HUDController = {}

-- UI-Element-Referenzen
local screenGui: ScreenGui? = nil
local goldAmountLabel: TextLabel? = nil
local cpsLabel: TextLabel? = nil
local goldCardFrame: Frame? = nil

-- Toast-Referenzen
local toastFrame: Frame? = nil
local toastText: TextLabel? = nil
local toastIcon: TextLabel? = nil
local toastStroke: UIStroke? = nil
local currentToastThread: thread? = nil

-- Hilfsfunktion: Formatierung großer Zahlen mit Tausendertrennzeichen
local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

-- Erstellt das gesamte HUD programmgesteuert
local function createHUD()
	if screenGui then
		return
	end

	-- Haupt-ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RealmRaidersHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	screenGui = gui

	-- 1. OBERER CONTAINER: Gold & CPS Anzeige
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(0, 320, 0, 75)
	topBar.Position = UDim2.new(0.5, -160, 0, 20)
	topBar.BackgroundTransparency = 1
	topBar.Parent = gui

	-- Gold-Card (Hintergrund mit abgerundeten Ecken & Umrandung)
	local goldCard = Instance.new("Frame")
	goldCard.Name = "GoldCard"
	goldCard.Size = UDim2.new(1, 0, 1, 0)
	goldCard.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	goldCard.BackgroundTransparency = 0.15
	goldCard.Parent = topBar
	goldCardFrame = goldCard

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = goldCard

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(241, 196, 15)
	cardStroke.Thickness = 2
	cardStroke.Transparency = 0.3
	cardStroke.Parent = goldCard

	-- Gold Icon / Emblem
	local goldIcon = Instance.new("TextLabel")
	goldIcon.Name = "GoldIcon"
	goldIcon.Size = UDim2.new(0, 45, 0, 45)
	goldIcon.Position = UDim2.new(0, 15, 0.5, -22)
	goldIcon.BackgroundTransparency = 1
	goldIcon.Text = "🪙"
	goldIcon.TextSize = 32
	goldIcon.Parent = goldCard

	-- Gold Betrag
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldAmount"
	goldLabel.Size = UDim2.new(1, -160, 0, 36)
	goldLabel.Position = UDim2.new(0, 65, 0, 8)
	goldLabel.BackgroundTransparency = 1
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextScaled = true
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Text = "0"
	goldLabel.Parent = goldCard
	goldAmountLabel = goldLabel

	-- CPS Badge (Cash per second)
	local cpsBadge = Instance.new("Frame")
	cpsBadge.Name = "CPSBadge"
	cpsBadge.Size = UDim2.new(0, 85, 0, 26)
	cpsBadge.Position = UDim2.new(1, -95, 0.5, -13)
	cpsBadge.BackgroundColor3 = Color3.fromRGB(39, 174, 96)
	cpsBadge.BackgroundTransparency = 0.2
	cpsBadge.Parent = goldCard

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 8)
	badgeCorner.Parent = cpsBadge

	local cpsText = Instance.new("TextLabel")
	cpsText.Name = "CPSText"
	cpsText.Size = UDim2.new(1, 0, 1, 0)
	cpsText.BackgroundTransparency = 1
	cpsText.TextColor3 = Color3.fromRGB(255, 255, 255)
	cpsText.Font = Enum.Font.GothamBold
	cpsText.TextSize = 13
	cpsText.Text = "+0 /s"
	cpsText.Parent = cpsBadge
	cpsLabel = cpsText

	-- Unterer kleiner Text "SEELEN-GOLD"
	local subTitle = Instance.new("TextLabel")
	subTitle.Name = "Subtitle"
	subTitle.Size = UDim2.new(0, 100, 0, 18)
	subTitle.Position = UDim2.new(0, 65, 0, 44)
	subTitle.BackgroundTransparency = 1
	subTitle.TextColor3 = Color3.fromRGB(160, 160, 175)
	subTitle.Font = Enum.Font.Gotham
	subTitle.TextSize = 12
	subTitle.TextXAlignment = Enum.TextXAlignment.Left
	subTitle.Text = "SEELEN-GOLD"
	subTitle.Parent = goldCard

	-- 2. TOAST-BENACHRICHTIGUNG (unter dem Gold-Header)
	local toast = Instance.new("Frame")
	toast.Name = "ToastBanner"
	toast.Size = UDim2.new(0, 360, 0, 44)
	toast.Position = UDim2.new(0.5, -180, 0, 105)
	toast.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	toast.BackgroundTransparency = 1
	toast.Visible = false
	toast.Parent = gui
	toastFrame = toast

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 10)
	tCorner.Parent = toast

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(46, 204, 113)
	tStroke.Thickness = 1.5
	tStroke.Transparency = 1
	tStroke.Parent = toast
	toastStroke = tStroke

	local tIcon = Instance.new("TextLabel")
	tIcon.Name = "Icon"
	tIcon.Size = UDim2.new(0, 34, 1, 0)
	tIcon.Position = UDim2.new(0, 8, 0, 0)
	tIcon.BackgroundTransparency = 1
	tIcon.Text = "✅"
	tIcon.TextSize = 20
	tIcon.TextTransparency = 1
	tIcon.Parent = toast
	toastIcon = tIcon

	local tLabel = Instance.new("TextLabel")
	tLabel.Name = "Message"
	tLabel.Size = UDim2.new(1, -50, 1, 0)
	tLabel.Position = UDim2.new(0, 42, 0, 0)
	tLabel.BackgroundTransparency = 1
	tLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	tLabel.Font = Enum.Font.GothamBold
	tLabel.TextSize = 13
	tLabel.TextXAlignment = Enum.TextXAlignment.Left
	tLabel.TextTransparency = 1
	tLabel.Text = ""
	tLabel.Parent = toast
	toastText = tLabel

	-- 3. UNTERER RECHTER CONTAINER: Status-Kachel
	local infoContainer = Instance.new("Frame")
	infoContainer.Name = "InfoContainer"
	infoContainer.Size = UDim2.new(0, 210, 0, 60)
	infoContainer.Position = UDim2.new(1, -225, 1, -75)
	infoContainer.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	infoContainer.BackgroundTransparency = 0.25
	infoContainer.Parent = gui

	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0, 10)
	infoCorner.Parent = infoContainer

	local infoStroke = Instance.new("UIStroke")
	infoStroke.Color = Color3.fromRGB(70, 75, 90)
	infoStroke.Thickness = 1
	infoStroke.Parent = infoContainer

	local dimensionLabel = Instance.new("TextLabel")
	dimensionLabel.Name = "Dimension"
	dimensionLabel.Size = UDim2.new(1, -20, 0, 22)
	dimensionLabel.Position = UDim2.new(0, 10, 0, 8)
	dimensionLabel.BackgroundTransparency = 1
	dimensionLabel.TextColor3 = Color3.fromRGB(116, 185, 255)
	dimensionLabel.Font = Enum.Font.GothamBold
	dimensionLabel.TextSize = 13
	dimensionLabel.TextXAlignment = Enum.TextXAlignment.Left
	dimensionLabel.Text = "📍 Dimension: Oberwelt"
	dimensionLabel.Parent = infoContainer

	local weaponLabel = Instance.new("TextLabel")
	weaponLabel.Name = "Weapon"
	weaponLabel.Size = UDim2.new(1, -20, 0, 18)
	weaponLabel.Position = UDim2.new(0, 10, 0, 32)
	weaponLabel.BackgroundTransparency = 1
	weaponLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	weaponLabel.Font = Enum.Font.Gotham
	weaponLabel.TextSize = 12
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
	weaponLabel.Text = "⚔️ Waffe: Rostiges Schwert"
	weaponLabel.Parent = infoContainer
end

-- Zeigt eine animierte Benachrichtigung an
function HUDController.ShowNotification(message: string, isError: boolean?)
	if not toastFrame or not toastText or not toastIcon or not toastStroke then
		return
	end

	if currentToastThread then
		task.cancel(currentToastThread)
		currentToastThread = nil
	end

	local accentColor = if isError then Color3.fromRGB(231, 76, 60) else Color3.fromRGB(46, 204, 113)
	local iconText = if isError then "⚠️" else "✅"

	toastText.Text = message
	toastIcon.Text = iconText
	toastStroke.Color = accentColor
	toastFrame.Visible = true

	-- Einblenden
	TweenService:Create(toastFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(toastStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.2 }):Play()
	TweenService:Create(toastText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	TweenService:Create(toastIcon, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

	currentToastThread = task.delay(3, function()
		if not toastFrame or not toastText or not toastIcon or not toastStroke then
			return
		end
		-- Ausblenden
		local fadeOut = TweenService:Create(toastFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		TweenService:Create(toastStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		TweenService:Create(toastText, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(toastIcon, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if toastFrame then
				toastFrame.Visible = false
			end
		end)
	end)
end

-- Aktualisiert die Anzeige und spielt eine dezente Pop-Animation ab
function HUDController.UpdateGold(newGold: number, currentCPS: number?)
	if not goldAmountLabel or not cpsLabel then
		return
	end

	goldAmountLabel.Text = formatNumber(newGold)

	if currentCPS ~= nil then
		cpsLabel.Text = string.format("+%s /s", formatNumber(currentCPS))
	end

	-- Sanfte Tween-Animation bei Gold-Erhalt
	if goldCardFrame then
		local growTween = TweenService:Create(
			goldCardFrame,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(1, 4, 1, 4) }
		)
		local resetTween = TweenService:Create(
			goldCardFrame,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(1, 0, 1, 0) }
		)

		growTween:Play()
		growTween.Completed:Connect(function()
			resetTween:Play()
		end)
	end
end

-- Initialisiert den Controller
function HUDController.Init()
	createHUD()

	-- Auf Server-Events reagieren
	GoldUpdated.OnClientEvent:Connect(function(newGold: number, currentCPS: number?)
		HUDController.UpdateGold(newGold, currentCPS)
	end)

	NotificationEvent.OnClientEvent:Connect(function(message: string, isError: boolean?)
		HUDController.ShowNotification(message, isError)
	end)

	print("[HUDController] Initialisiert und ScreenGui erstellt.")
end

return HUDController
