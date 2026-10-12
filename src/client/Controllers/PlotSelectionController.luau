--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local CheckUIFolder = Shared:WaitForChild("CheckUI")

local CheckUIThemeModule = CheckUIFolder:WaitForChild("CheckUITheme") :: ModuleScript
local CheckUITheme = require(CheckUIThemeModule)

local CheckUIControllerModule = CheckUIFolder:WaitForChild("CheckUIController") :: ModuleScript
local CheckUIController = require(CheckUIControllerModule)

local PlotStatusUpdatedEvent = EventsFolder:WaitForChild("PlotStatusUpdated") :: RemoteEvent
local ClaimPlotIntentEvent = EventsFolder:WaitForChild("ClaimPlotIntent") :: RemoteEvent
local RequestPlotStatusEvent = EventsFolder:WaitForChild("RequestPlotStatus") :: RemoteEvent

local PlotSelectionController = {}
local isInitialized = false
local isModalOpen = false
local playerHasPlot = false

export type PlotStatus = {
	PlotIndex: number,
	OwnerUserId: number,
	OwnerName: string,
	IsRival: boolean,
}

local cachedPlotStatuses: { [number]: PlotStatus } = {}

-- UI-Elemente
local screenGui: ScreenGui? = nil
local backdropFrame: Frame? = nil
local modalFrame: Frame? = nil
local windowScale: UIScale? = nil
local gridContainer: Frame? = nil
local topReminderBtn: TextButton? = nil

-- Fügt TextLabel einen kräftigen schwarzen Stroke hinzu (Check-UI Standard)
local function addCheckUIStroke(label: TextLabel, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness or 2.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

-- Aktualisiert die Anzeige aller 6 Plot-Karten im Grid
local function refreshPlotCards()
	if not gridContainer then
		return
	end

	-- Vorherige Karten aufräumen
	for _, child in gridContainer:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for slotIndex = 1, 6 do
		local status = cachedPlotStatuses[slotIndex]
		local isRival = (slotIndex == 2) or (status and status.IsRival)
		local ownerId = if status then status.OwnerUserId else 0
		local ownerName = if status then status.OwnerName else ""
		local isTakenByOther = (ownerId ~= 0 and ownerId ~= LocalPlayer.UserId and not isRival)
		local isOwnedBySelf = (ownerId == LocalPlayer.UserId)
		local isAvailable = (ownerId == 0 and not isRival)

		local card = Instance.new("Frame")
		card.Name = "PlotCard_" .. slotIndex
		card.BackgroundColor3 = CheckUITheme.Colors.CardBackground
		card.BorderSizePixel = 0
		card.Parent = gridContainer

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 4)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = if isOwnedBySelf then Color3.fromRGB(105, 225, 0) elseif isAvailable then CheckUITheme.Colors.CardHighlight else Color3.fromRGB(18, 25, 30)
		cardStroke.Thickness = if isOwnedBySelf then 2.2 else 1.6
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = card

		-- Titel (z. B. "PLOT 1" oder "PLOT 2 [RIVALE]")
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "PlotTitle"
		titleLabel.Size = UDim2.new(1, -16, 0, 24)
		titleLabel.Position = UDim2.new(0, 8, 0, 8)
		titleLabel.BackgroundTransparency = 1
		titleLabel.TextColor3 = if isRival then Color3.fromRGB(255, 110, 90) elseif isOwnedBySelf then Color3.fromRGB(255, 215, 0) else Color3.fromRGB(255, 255, 255)
		titleLabel.Font = CheckUITheme.Typography.Font
		titleLabel.TextSize = 15
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.Text = if isRival then "PLOT 2 [RIVALE]" else string.format("PLOT %d", slotIndex)
		titleLabel.Parent = card
		addCheckUIStroke(titleLabel, 2.2)

		-- Info-Text
		local infoLabel = Instance.new("TextLabel")
		infoLabel.Name = "PlotInfo"
		infoLabel.Size = UDim2.new(1, -16, 0, 16)
		infoLabel.Position = UDim2.new(0, 8, 0, 32)
		infoLabel.BackgroundTransparency = 1
		infoLabel.TextColor3 = Color3.fromRGB(160, 180, 200)
		infoLabel.Font = CheckUITheme.Typography.Font
		infoLabel.TextSize = 10
		infoLabel.Text = "3 Statuen-Sockel • CPS"
		infoLabel.Parent = card
		addCheckUIStroke(infoLabel, 1.8)

		-- Status-Badge
		local statusBadge = Instance.new("Frame")
		statusBadge.Name = "StatusBadge"
		statusBadge.Size = UDim2.new(1, -20, 0, 26)
		statusBadge.Position = UDim2.new(0, 10, 0, 56)
		statusBadge.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
		statusBadge.BorderSizePixel = 0
		statusBadge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 4)
		badgeCorner.Parent = statusBadge

		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = Color3.fromRGB(0, 0, 0)
		badgeStroke.Thickness = 1.6
		badgeStroke.Parent = statusBadge

		local badgeText = Instance.new("TextLabel")
		badgeText.Size = UDim2.new(1, 0, 1, 0)
		badgeText.BackgroundTransparency = 1
		badgeText.Font = CheckUITheme.Typography.Font
		badgeText.TextSize = 11
		badgeText.TextTruncate = Enum.TextTruncate.AtEnd
		badgeText.Parent = statusBadge

		if isOwnedBySelf then
			badgeText.Text = "🌟 DEINE BASIS"
			badgeText.TextColor3 = Color3.fromRGB(255, 215, 0)
		elseif isRival then
			badgeText.Text = "🤖 TEST-RIVALE (NPC)"
			badgeText.TextColor3 = Color3.fromRGB(255, 90, 80)
		elseif isTakenByOther then
			badgeText.Text = "👤 " .. ownerName
			badgeText.TextColor3 = Color3.fromRGB(160, 175, 195)
		else
			badgeText.Text = "✨ VERFÜGBAR"
			badgeText.TextColor3 = Color3.fromRGB(105, 225, 0)
		end
		addCheckUIStroke(badgeText, 1.8)

		-- Button (Button State Triad: Claim / Claimed / Locked)
		local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionBtn"
		actionBtn.Size = UDim2.new(1, -20, 0, 36)
		actionBtn.Position = UDim2.new(0, 10, 0, 92)
		actionBtn.BorderSizePixel = 0
		actionBtn.AutoButtonColor = false
		actionBtn.ClipsDescendants = true
		actionBtn.Text = ""
		actionBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = actionBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(12, 20, 26)
		btnStroke.Thickness = 2.4
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Parent = actionBtn

		local btnGrad = Instance.new("UIGradient")
		btnGrad.Rotation = 90
		btnGrad.Parent = actionBtn

		local btnBevel = Instance.new("Frame")
		btnBevel.Name = "Bevel"
		btnBevel.Size = UDim2.new(1, 0, 0, 3)
		btnBevel.Position = UDim2.new(0, 0, 1, -3)
		btnBevel.BorderSizePixel = 0
		btnBevel.Parent = actionBtn

		local btnLabel = Instance.new("TextLabel")
		btnLabel.Name = "BtnLabel"
		btnLabel.Size = UDim2.new(1, 0, 1, 0)
		btnLabel.BackgroundTransparency = 1
		btnLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnLabel.Font = CheckUITheme.Typography.Font
		btnLabel.TextSize = 13
		btnLabel.Parent = actionBtn
		addCheckUIStroke(btnLabel, 2.4)

		if isOwnedBySelf then
			actionBtn.Active = false
			btnGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 208, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 0)),
			}
			btnBevel.BackgroundColor3 = Color3.fromRGB(153, 76, 0)
			btnLabel.Text = "AKTIV"
		elseif isAvailable then
			-- Claim State: Lime Green
			actionBtn.Active = true
			btnGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, CheckUITheme.Colors.ClaimGradientTop),
				ColorSequenceKeypoint.new(1, CheckUITheme.Colors.ClaimGradientBottom),
			}
			btnBevel.BackgroundColor3 = CheckUITheme.Colors.ClaimBevel
			btnLabel.Text = "BEANSPRUCHEN"

			local btnScale = Instance.new("UIScale")
			btnScale.Name = "ButtonScale"
			btnScale.Scale = 1
			btnScale.Parent = actionBtn

			CheckUIController.bindButtonAnimations(actionBtn, btnScale, 1.04, 0.95)

			actionBtn.MouseButton1Click:Connect(function()
				ClaimPlotIntentEvent:FireServer(slotIndex)
			end)
		elseif isRival then
			-- Locked State: Crimson Red
			actionBtn.Active = false
			btnGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, CheckUITheme.Colors.LockedGradientTop),
				ColorSequenceKeypoint.new(1, CheckUITheme.Colors.LockedGradientBottom),
			}
			btnBevel.BackgroundColor3 = CheckUITheme.Colors.LockedBevel
			btnLabel.Text = "GESPERRT"
		else
			-- Claimed State: Metallic Silver
			actionBtn.Active = false
			btnGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, CheckUITheme.Colors.ClaimedGradientTop),
				ColorSequenceKeypoint.new(1, CheckUITheme.Colors.ClaimedGradientBottom),
			}
			btnBevel.BackgroundColor3 = CheckUITheme.Colors.ClaimedBevel
			btnLabel.Text = "BELEGT"
		end
	end
end

-- Öffnet das Plot-Auswahlfenster
function PlotSelectionController.Open()
	if not modalFrame or not backdropFrame or isModalOpen then
		return
	end
	isModalOpen = true

	refreshPlotCards()

	backdropFrame.Visible = true
	modalFrame.Visible = true

	if topReminderBtn then
		topReminderBtn.Visible = false
	end

	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		windowScale.Scale = targetScale * 0.75
		TweenService:Create(
			windowScale,
			TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = targetScale }
		):Play()
	end
end

-- Schließt das Plot-Auswahlfenster
function PlotSelectionController.Close()
	if not modalFrame or not backdropFrame or not isModalOpen then
		return
	end
	isModalOpen = false

	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		local closeTween = TweenService:Create(
			windowScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = targetScale * 0.70 }
		)
		closeTween:Play()
		closeTween.Completed:Connect(function()
			if not isModalOpen and modalFrame and backdropFrame then
				modalFrame.Visible = false
				backdropFrame.Visible = false
				windowScale.Scale = targetScale
			end
		end)
	else
		modalFrame.Visible = false
		backdropFrame.Visible = false
	end

	if not playerHasPlot and topReminderBtn then
		topReminderBtn.Visible = true
	end
end

-- Erstellt das grafische Interface für die Plot-Auswahl nach Check-UI Standard
local function createPlotSelectionGUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlotSelectionGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 18
	screenGui.Parent = playerGui

	-- Dunkler Hintergrund-Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 15, 20)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = screenGui
	backdropFrame = backdrop

	-- Hauptfenster (Check-UI Solid Slate Canvas #3B5866)
	local window = Instance.new("Frame")
	window.Name = "PlotSelectionModal"
	window.Size = UDim2.new(0, 640, 0, 480)
	window.Position = UDim2.new(0.5, 0, 0.5, 0)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = CheckUITheme.Colors.Canvas
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.ZIndex = 31
	window.Visible = false
	window.Parent = screenGui
	modalFrame = window

	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 4)
	windowCorner.Parent = window

	local windowStroke = Instance.new("UIStroke")
	windowStroke.Name = "OuterStroke"
	windowStroke.Color = CheckUITheme.Colors.CanvasBorder
	windowStroke.Thickness = 3.5
	windowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	windowStroke.Parent = window

	local wScale = Instance.new("UIScale")
	wScale.Name = "WindowScale"
	wScale.Scale = 1
	wScale.Parent = window
	windowScale = wScale

	-- Header (Electric Cyan Theme)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 68)
	header.BorderSizePixel = 0
	header.ZIndex = 32
	header.Parent = window

	local headerGrad = Instance.new("UIGradient")
	headerGrad.Rotation = 90
	headerGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 205, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 130, 245)),
	}
	headerGrad.Parent = header

	-- 2-Tier Header Divider
	local divDark = Instance.new("Frame")
	divDark.Name = "DividerBlack"
	divDark.Size = UDim2.new(1, 0, 0, 4)
	divDark.Position = UDim2.new(0, 0, 1, -4)
	divDark.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	divDark.BorderSizePixel = 0
	divDark.ZIndex = 33
	divDark.Parent = header

	local divShadow = Instance.new("Frame")
	divShadow.Name = "DividerShadow"
	divShadow.Size = UDim2.new(1, 0, 0, 3)
	divShadow.Position = UDim2.new(0, 0, 1, 0)
	divShadow.BackgroundColor3 = Color3.fromRGB(0, 50, 110)
	divShadow.BorderSizePixel = 0
	divShadow.ZIndex = 33
	divShadow.Parent = header

	-- Header-Titel & Untertitel
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -90, 0, 30)
	title.Position = UDim2.new(0, 24, 0, 10)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = CheckUITheme.Typography.Font
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "WÄHLE DEINE BASIS"
	title.ZIndex = 34
	title.Parent = header
	addCheckUIStroke(title, 2.8)

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -90, 0, 18)
	subtitle.Position = UDim2.new(0, 24, 0, 40)
	subtitle.BackgroundTransparency = 1
	subtitle.TextColor3 = Color3.fromRGB(220, 245, 255)
	subtitle.Font = CheckUITheme.Typography.Font
	subtitle.TextSize = 11
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Beanspruche einen freien Plot, um Seelenkerne zu platzieren!"
	subtitle.ZIndex = 34
	subtitle.Parent = header
	addCheckUIStroke(subtitle, 1.8)

	-- 3D Square Close Button [X]
	local closeBtn = Instance.new("ImageButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 38, 0, 38)
	closeBtn.Position = UDim2.new(1, -48, 0.5, -2)
	closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	closeBtn.BackgroundColor3 = CheckUITheme.Colors.CloseBase
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ClipsDescendants = false
	closeBtn.ZIndex = 35
	closeBtn.Parent = header

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(0, 0, 0)
	closeStroke.Thickness = 2.8
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = closeBtn

	local closeFace = Instance.new("Frame")
	closeFace.Name = "Face"
	closeFace.Size = UDim2.new(1, 0, 1, -4)
	closeFace.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	closeFace.BorderSizePixel = 0
	closeFace.ZIndex = 36
	closeFace.Parent = closeBtn

	local closeFaceGrad = Instance.new("UIGradient")
	closeFaceGrad.Rotation = 90
	closeFaceGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, CheckUITheme.Colors.CloseFaceTop),
		ColorSequenceKeypoint.new(1, CheckUITheme.Colors.CloseFaceBottom),
	}
	closeFaceGrad.Parent = closeFace

	local closeX = Instance.new("TextLabel")
	closeX.Name = "XLabel"
	closeX.Size = UDim2.new(1, 0, 1, 0)
	closeX.BackgroundTransparency = 1
	closeX.Text = "X"
	closeX.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeX.Font = CheckUITheme.Typography.Font
	closeX.TextSize = 20
	closeX.ZIndex = 37
	closeX.Parent = closeFace
	addCheckUIStroke(closeX, 2.6)

	closeBtn.MouseButton1Click:Connect(function()
		PlotSelectionController.Close()
	end)

	-- Grid-Container für die 6 Plots
	local content = Instance.new("Frame")
	content.Name = "GridContent"
	content.Size = UDim2.new(1, -36, 1, -88)
	content.Position = UDim2.new(0, 18, 0, 78)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ZIndex = 32
	content.Parent = window
	gridContainer = content

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 192, 0, 140)
	gridLayout.CellPadding = UDim2.new(0, 14, 0, 12)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.Name
	gridLayout.Parent = content

	-- Kleiner Top-Reminder-Button (erscheint nur, wenn der Spieler noch keinen Plot gewählt hat)
	local reminder = Instance.new("TextButton")
	reminder.Name = "PlotReminderButton"
	reminder.Size = UDim2.new(0, 160, 0, 36)
	reminder.Position = UDim2.new(0.5, 0, 0, 16)
	reminder.AnchorPoint = Vector2.new(0.5, 0)
	reminder.BackgroundColor3 = Color3.fromRGB(0, 160, 240)
	reminder.BorderSizePixel = 0
	reminder.AutoButtonColor = false
	reminder.Text = "🏠 BASIS WÄHLEN"
	reminder.TextColor3 = Color3.fromRGB(255, 255, 255)
	reminder.Font = CheckUITheme.Typography.Font
	reminder.TextSize = 12
	reminder.ZIndex = 15
	reminder.Visible = false
	reminder.Parent = screenGui
	topReminderBtn = reminder

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 4)
	rCorner.Parent = reminder

	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Color3.fromRGB(12, 20, 26)
	rStroke.Thickness = 2.4
	rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rStroke.Parent = reminder
	addCheckUIStroke(reminder, 2.2)

	local rScale = Instance.new("UIScale")
	rScale.Scale = 1
	rScale.Parent = reminder
	CheckUIController.bindButtonAnimations(reminder, rScale, 1.04, 0.96)

	reminder.MouseButton1Click:Connect(function()
		PlotSelectionController.Open()
	end)
end

function PlotSelectionController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	createPlotSelectionGUI()

	-- Server-Events verbinden
	PlotStatusUpdatedEvent.OnClientEvent:Connect(function(statusList: { [number]: PlotStatus }, hasPlot: boolean)
		cachedPlotStatuses = statusList or {}
		playerHasPlot = (hasPlot == true)

		if isModalOpen then
			refreshPlotCards()
		end

		if not playerHasPlot then
			-- Spieler hat noch keinen Plot -> Fenster automatisch öffnen!
			PlotSelectionController.Open()
		else
			-- Spieler besitzt bereits einen Plot -> Fenster schließen
			if isModalOpen then
				PlotSelectionController.Close()
			end
			if topReminderBtn then
				topReminderBtn.Visible = false
			end
		end
	end)

	-- Taste [P] zum manuellen Öffnen / Schließen des Plot-Menüs
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			if isModalOpen then
				PlotSelectionController.Close()
			else
				PlotSelectionController.Open()
			end
		elseif isModalOpen and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			PlotSelectionController.Close()
		end
	end)

	-- Initialen Plot-Status anfordern
	task.defer(function()
		RequestPlotStatusEvent:FireServer()
	end)

	print("[PlotSelectionController] Initialisiert: Check-UI Plot-Auswahlfenster aktiv (Auto-Prompt bei Spielstart, Taste [P]).")
end

return PlotSelectionController
