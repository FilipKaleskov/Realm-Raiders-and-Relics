--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

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
local isBannerOpen = false
local playerHasPlot = false
local isManuallyDismissed = false
local autoDismissThread: thread? = nil

export type PlotStatus = {
	PlotIndex: number,
	OwnerUserId: number,
	OwnerName: string,
	IsRival: boolean,
}

local cachedPlotStatuses: { [any]: PlotStatus } = {}

-- UI-Elemente
local screenGui: ScreenGui? = nil
local infoCard: Frame? = nil
local cardScale: UIScale? = nil
local chipsContainer: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local timerProgressBar: Frame? = nil
local cardStroke: UIStroke? = nil
local topPillBtn: TextButton? = nil
local quickPickBtnRef: TextButton? = nil

-- Fügt TextLabel einen kräftigen schwarzen Stroke hinzu (Check-UI Standard)
local function addCheckUIStroke(label: TextLabel | TextButton, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness or 2.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

-- Bricht den Auto-Dismiss-Timer ab
local function cancelAutoDismiss()
	if autoDismissThread then
		task.cancel(autoDismissThread)
		autoDismissThread = nil
	end
end

-- Schnelles, flüssiges Ausblenden (z. B. nach Klick auf Schnellwahl)
function PlotSelectionController.FastClose()
	if not infoCard then
		return
	end
	isBannerOpen = false
	cancelAutoDismiss()

	local tween = TweenService:Create(
		infoCard,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -180) }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if not isBannerOpen and infoCard then
			infoCard.Visible = false
		end
	end)

	if topPillBtn then
		topPillBtn.Visible = false
	end
end

-- Normales Schließen / Minimieren der Infobox in die Top-Pill
function PlotSelectionController.Close()
	if not infoCard then
		return
	end
	isBannerOpen = false
	cancelAutoDismiss()

	local tween = TweenService:Create(
		infoCard,
		TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -180) }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if not isBannerOpen and infoCard then
			infoCard.Visible = false
		end
	end)

	-- Pill-Button nur anzeigen, wenn der Spieler noch immer keinen Plot hat
	if not playerHasPlot and topPillBtn then
		topPillBtn.Visible = true
	end
end

-- Aktualisiert die horizontalen Plot-Buttons (Schnellwahl + freie Plots 1, 3, 4, 5, 6)
local function refreshChips()
	if not chipsContainer then
		return
	end

	for _, child in chipsContainer:GetChildren() do
		if child:IsA("TextButton") and child.Name ~= "QuickPickBtn" then
			child:Destroy()
		end
	end

	-- Plots 1 bis 6 durchlaufen (Plot 2 = Rivale)
	for slotIndex = 1, 6 do
		if slotIndex == 2 then
			continue
		end

		local status = cachedPlotStatuses[slotIndex] or cachedPlotStatuses[tostring(slotIndex)]
		local ownerId = if status then status.OwnerUserId else 0
		local isOwnedBySelf = (ownerId == LocalPlayer.UserId)
		local isAvailable = (ownerId == 0)

		local chip = Instance.new("TextButton")
		chip.Name = "Chip_" .. slotIndex
		chip.LayoutOrder = slotIndex
		chip.Size = UDim2.new(0, 68, 0, 36)
		chip.BorderSizePixel = 0
		chip.AutoButtonColor = false
		chip.ClipsDescendants = true
		chip.Text = ""
		chip.ZIndex = 27
		chip.Parent = chipsContainer

		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 4)
		chipCorner.Parent = chip

		local chipStroke = Instance.new("UIStroke")
		chipStroke.Color = Color3.fromRGB(12, 20, 26)
		chipStroke.Thickness = 2.0
		chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		chipStroke.Parent = chip

		local chipGrad = Instance.new("UIGradient")
		chipGrad.Rotation = 90
		chipGrad.Parent = chip

		local chipBevel = Instance.new("Frame")
		chipBevel.Name = "Bevel"
		chipBevel.Size = UDim2.new(1, 0, 0, 3)
		chipBevel.Position = UDim2.new(0, 0, 1, -3)
		chipBevel.BorderSizePixel = 0
		chipBevel.ZIndex = 27
		chipBevel.Parent = chip

		local chipLabel = Instance.new("TextLabel")
		chipLabel.Name = "Label"
		chipLabel.Size = UDim2.new(1, 0, 1, 0)
		chipLabel.BackgroundTransparency = 1
		chipLabel.Font = CheckUITheme.Typography.Font
		chipLabel.TextSize = 12
		chipLabel.ZIndex = 28
		chipLabel.Parent = chip
		addCheckUIStroke(chipLabel, 2.0)

		if isOwnedBySelf then
			chip.Active = false
			chipGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 208, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 0)),
			}
			chipBevel.BackgroundColor3 = Color3.fromRGB(153, 76, 0)
			chipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			chipLabel.Text = string.format("Plot %d ★", slotIndex)
		elseif isAvailable then
			-- Freier Plot: Saftiges Lime-Grün
			chip.Active = true
			chipGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, CheckUITheme.Colors.ClaimGradientTop),
				ColorSequenceKeypoint.new(1, CheckUITheme.Colors.ClaimGradientBottom),
			}
			chipBevel.BackgroundColor3 = CheckUITheme.Colors.ClaimBevel
			chipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			chipLabel.Text = string.format("Plot %d", slotIndex)

			local chipScale = Instance.new("UIScale")
			chipScale.Scale = 1
			chipScale.Parent = chip
			CheckUIController.bindButtonAnimations(chip, chipScale, 1.06, 0.94)

			local function onPickPlot()
				chip.Active = false
				PlotSelectionController.FastClose()
				ClaimPlotIntentEvent:FireServer(slotIndex)
			end

			chip.Activated:Connect(onPickPlot)
			chip.MouseButton1Click:Connect(onPickPlot)
		else
			-- Belegt: Gedecktes Slate-Grau
			chip.Active = false
			chipGrad.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 100, 110)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 68, 76)),
			}
			chipBevel.BackgroundColor3 = Color3.fromRGB(36, 42, 48)
			chipLabel.TextColor3 = Color3.fromRGB(160, 170, 180)
			chipLabel.Text = string.format("Plot %d", slotIndex)
		end
	end
end

-- Startet den 12-Sekunden-Timer zum automatischen Minimieren
local function startAutoDismiss()
	cancelAutoDismiss()

	if timerProgressBar then
		timerProgressBar.Size = UDim2.new(1, 0, 0, 3)
		TweenService:Create(
			timerProgressBar,
			TweenInfo.new(12, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, 0, 0, 3) }
		):Play()
	end

	autoDismissThread = task.delay(12, function()
		if not playerHasPlot and isBannerOpen then
			PlotSelectionController.Close()
		end
	end)
end

-- Öffnet die Infobox als eleganter, schwebender Banner am oberen Bildschirmrand
function PlotSelectionController.Open()
	if not infoCard or isBannerOpen then
		return
	end
	isBannerOpen = true

	refreshChips()

	if topPillBtn then
		topPillBtn.Visible = false
	end

	infoCard.Visible = true

	local targetScale = CheckUIController.getDeviceScale()
	if cardScale then
		cardScale.Scale = targetScale
	end

	infoCard.Position = UDim2.new(0.5, 0, 0, -180)
	TweenService:Create(
		infoCard,
		TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 20) }
	):Play()

	startAutoDismiss()
end

-- Erstellt die Infobox & den dezenten Top-Pill-Button
local function createPlotSelectionGUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlotSelectionGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 18
	screenGui.Parent = playerGui

	-- ========================================================
	-- 1. SCHWEBENDE INFOBOX (CARD BANNER OBEN ZENTRIERT)
	-- ========================================================
	local banner = Instance.new("Frame")
	banner.Name = "PlotInfoBanner"
	banner.Size = UDim2.new(0, 560, 0, 108)
	banner.Position = UDim2.new(0.5, 0, 0, -180)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	banner.BorderSizePixel = 0
	banner.ClipsDescendants = true
	banner.ZIndex = 25
	banner.Visible = false
	banner.Parent = screenGui
	infoCard = banner

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 6)
	bCorner.Parent = banner

	local bStroke = Instance.new("UIStroke")
	bStroke.Name = "OuterStroke"
	bStroke.Color = Color3.fromRGB(0, 210, 255)
	bStroke.Thickness = 2.4
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = banner
	cardStroke = bStroke

	local cScale = Instance.new("UIScale")
	cScale.Name = "CardScale"
	cScale.Scale = 1
	cScale.Parent = banner
	cardScale = cScale

	-- Oberer Cyan-Glanzstreifen
	local topAccent = Instance.new("Frame")
	topAccent.Name = "TopAccent"
	topAccent.Size = UDim2.new(1, 0, 0, 3)
	topAccent.Position = UDim2.new(0, 0, 0, 0)
	topAccent.BorderSizePixel = 0
	topAccent.ZIndex = 26
	topAccent.Parent = banner

	local accentGrad = Instance.new("UIGradient")
	accentGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 210, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 255, 25)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 210, 255)),
	}
	accentGrad.Parent = topAccent

	-- Icon Box
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.Size = UDim2.new(0, 34, 0, 34)
	iconBox.Position = UDim2.new(0, 12, 0, 10)
	iconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	iconBox.BorderSizePixel = 0
	iconBox.ZIndex = 26
	iconBox.Parent = banner

	local iCorner = Instance.new("UICorner")
	iCorner.CornerRadius = UDim.new(0, 4)
	iCorner.Parent = iconBox

	local iStroke = Instance.new("UIStroke")
	iStroke.Color = Color3.fromRGB(0, 0, 0)
	iStroke.Thickness = 1.6
	iStroke.Parent = iconBox

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "🏰"
	iconLabel.TextSize = 18
	iconLabel.Font = CheckUITheme.Typography.Font
	iconLabel.ZIndex = 27
	iconLabel.Parent = iconBox

	-- Titel & Untertitel
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -100, 0, 20)
	title.Position = UDim2.new(0, 54, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = CheckUITheme.Typography.Font
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "WÄHLE DEINE BASIS"
	title.ZIndex = 26
	title.Parent = banner
	addCheckUIStroke(title, 2.2)
	titleLabel = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -100, 0, 16)
	subtitle.Position = UDim2.new(0, 54, 0, 27)
	subtitle.BackgroundTransparency = 1
	subtitle.TextColor3 = Color3.fromRGB(180, 220, 240)
	subtitle.Font = CheckUITheme.Typography.Font
	subtitle.TextSize = 10
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Laufe zu einem freien Plot [E] oder wähle hier:"
	subtitle.ZIndex = 26
	subtitle.Parent = banner
	addCheckUIStroke(subtitle, 1.8)
	subtitleLabel = subtitle

	-- 3D Beveled Schließen-Button [X] (Sauberes ASCII "X")
	local closeBtn = Instance.new("ImageButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = CheckUITheme.Colors.CloseBase
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ClipsDescendants = false
	closeBtn.Active = true
	closeBtn.Selectable = true
	closeBtn.ZIndex = 30
	closeBtn.Parent = banner

	local clCorner = Instance.new("UICorner")
	clCorner.CornerRadius = UDim.new(0, 4)
	clCorner.Parent = closeBtn

	local clStroke = Instance.new("UIStroke")
	clStroke.Color = Color3.fromRGB(0, 0, 0)
	clStroke.Thickness = 2.0
	clStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	clStroke.Parent = closeBtn

	local clFace = Instance.new("Frame")
	clFace.Name = "Face"
	clFace.Size = UDim2.new(1, 0, 1, -3)
	clFace.Position = UDim2.new(0, 0, 0, 0)
	clFace.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	clFace.BorderSizePixel = 0
	clFace.Active = false
	clFace.ZIndex = 31
	clFace.Parent = closeBtn

	local clFaceGrad = Instance.new("UIGradient")
	clFaceGrad.Rotation = 90
	clFaceGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, CheckUITheme.Colors.CloseFaceTop),
		ColorSequenceKeypoint.new(1, CheckUITheme.Colors.CloseFaceBottom),
	}
	clFaceGrad.Parent = clFace

	local clLabel = Instance.new("TextLabel")
	clLabel.Name = "XLabel"
	clLabel.Size = UDim2.new(1, 0, 1, 0)
	clLabel.BackgroundTransparency = 1
	clLabel.Text = "X"
	clLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	clLabel.Font = CheckUITheme.Typography.Font
	clLabel.TextSize = 14
	clLabel.Active = false
	clLabel.Selectable = false
	clLabel.ZIndex = 32
	clLabel.Parent = clFace
	addCheckUIStroke(clLabel, 2.2)

	local clScale = Instance.new("UIScale")
	clScale.Scale = 1
	clScale.Parent = closeBtn
	CheckUIController.bindButtonAnimations(closeBtn, clScale, 1.08, 0.92)

	local function handleClose()
		isManuallyDismissed = true
		PlotSelectionController.Close()
	end

	closeBtn.Activated:Connect(handleClose)
	closeBtn.MouseButton1Click:Connect(handleClose)

	-- Container für die Buttons
	local btnRow = Instance.new("Frame")
	btnRow.Name = "ButtonsRow"
	btnRow.Size = UDim2.new(1, -24, 0, 42)
	btnRow.Position = UDim2.new(0, 12, 0, 52)
	btnRow.BackgroundTransparency = 1
	btnRow.ZIndex = 26
	btnRow.Parent = banner
	chipsContainer = btnRow

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = btnRow

	-- Schnellwahl-Button
	local quickPickBtn = Instance.new("TextButton")
	quickPickBtn.Name = "QuickPickBtn"
	quickPickBtn.LayoutOrder = 0
	quickPickBtn.Size = UDim2.new(0, 120, 0, 36)
	quickPickBtn.BorderSizePixel = 0
	quickPickBtn.AutoButtonColor = false
	quickPickBtn.ClipsDescendants = true
	quickPickBtn.Text = ""
	quickPickBtn.ZIndex = 27
	quickPickBtn.Parent = btnRow
	quickPickBtnRef = quickPickBtn

	local qCorner = Instance.new("UICorner")
	qCorner.CornerRadius = UDim.new(0, 4)
	qCorner.Parent = quickPickBtn

	local qStroke = Instance.new("UIStroke")
	qStroke.Color = Color3.fromRGB(12, 20, 26)
	qStroke.Thickness = 2.0
	qStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	qStroke.Parent = quickPickBtn

	local qGrad = Instance.new("UIGradient")
	qGrad.Rotation = 90
	qGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 215, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 130, 240)),
	}
	qGrad.Parent = quickPickBtn

	local qBevel = Instance.new("Frame")
	qBevel.Size = UDim2.new(1, 0, 0, 3)
	qBevel.Position = UDim2.new(0, 0, 1, -3)
	qBevel.BackgroundColor3 = Color3.fromRGB(0, 60, 140)
	qBevel.BorderSizePixel = 0
	qBevel.ZIndex = 27
	qBevel.Parent = quickPickBtn

	local qLabel = Instance.new("TextLabel")
	qLabel.Size = UDim2.new(1, 0, 1, 0)
	qLabel.BackgroundTransparency = 1
	qLabel.Text = "⚡ Schnell-Wahl"
	qLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	qLabel.Font = CheckUITheme.Typography.Font
	qLabel.TextSize = 12
	qLabel.ZIndex = 28
	qLabel.Parent = quickPickBtn
	addCheckUIStroke(qLabel, 2.2)

	local qScale = Instance.new("UIScale")
	qScale.Scale = 1
	qScale.Parent = quickPickBtn
	CheckUIController.bindButtonAnimations(quickPickBtn, qScale, 1.05, 0.95)

	local function onQuickPick()
		quickPickBtn.Active = false
		PlotSelectionController.FastClose()
		ClaimPlotIntentEvent:FireServer(0)
	end

	quickPickBtn.Activated:Connect(onQuickPick)
	quickPickBtn.MouseButton1Click:Connect(onQuickPick)

	-- Automatischer Fortschrittsbalken am unteren Rand
	local progBar = Instance.new("Frame")
	progBar.Name = "AutoDismissProgress"
	progBar.Size = UDim2.new(1, 0, 0, 3)
	progBar.Position = UDim2.new(0, 0, 1, -3)
	progBar.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
	progBar.BorderSizePixel = 0
	progBar.ZIndex = 27
	progBar.Parent = banner
	timerProgressBar = progBar

	banner.MouseEnter:Connect(cancelAutoDismiss)
	banner.MouseLeave:Connect(startAutoDismiss)

	-- ========================================================
	-- 2. DEZENTER TOP-PILL BUTTON (WENN MINIMIERT)
	-- ========================================================
	local pill = Instance.new("TextButton")
	pill.Name = "PlotPillButton"
	pill.Size = UDim2.new(0, 175, 0, 32)
	pill.Position = UDim2.new(0.5, 0, 0, 12)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	pill.BorderSizePixel = 0
	pill.AutoButtonColor = false
	pill.Text = "🏠 Basis wählen  [P]"
	pill.TextColor3 = Color3.fromRGB(255, 255, 255)
	pill.Font = CheckUITheme.Typography.Font
	pill.TextSize = 11
	pill.ZIndex = 15
	pill.Visible = false
	pill.Parent = screenGui
	topPillBtn = pill

	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 16)
	pCorner.Parent = pill

	local pStroke = Instance.new("UIStroke")
	pStroke.Color = Color3.fromRGB(0, 210, 255)
	pStroke.Thickness = 2.0
	pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pStroke.Parent = pill
	addCheckUIStroke(pill, 2.0)

	local pScale = Instance.new("UIScale")
	pScale.Scale = 1
	pScale.Parent = pill
	CheckUIController.bindButtonAnimations(pill, pScale, 1.05, 0.95)

	pill.MouseButton1Click:Connect(function()
		isManuallyDismissed = false
		PlotSelectionController.Open()
	end)
end

function PlotSelectionController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	createPlotSelectionGUI()

	-- Multi-Device Responsive Scaling
	local function updateScale()
		if cardScale then
			cardScale.Scale = CheckUIController.getDeviceScale()
		end
	end
	if Camera then
		Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()

	-- Server-Events verbinden
	PlotStatusUpdatedEvent.OnClientEvent:Connect(function(statusList: { [any]: PlotStatus }, hasPlot: boolean)
		cachedPlotStatuses = statusList or {}
		playerHasPlot = (hasPlot == true)

		refreshChips()

		if playerHasPlot then
			-- Spieler besitzt bereits einen Plot -> Sofort schnell schließen
			PlotSelectionController.FastClose()
			if topPillBtn then
				topPillBtn.Visible = false
			end
		else
			-- Spieler hat noch keinen Plot
			if not isManuallyDismissed then
				PlotSelectionController.Open()
			end
		end
	end)

	-- Taste [P] / [Escape] zum manuellen Umschalten der Infobox
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			if isBannerOpen then
				isManuallyDismissed = true
				PlotSelectionController.Close()
			else
				isManuallyDismissed = false
				PlotSelectionController.Open()
			end
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if isBannerOpen then
				isManuallyDismissed = true
				PlotSelectionController.Close()
			end
		end
	end)

	-- Initialen Plot-Status anfordern
	task.defer(function()
		RequestPlotStatusEvent:FireServer()
	end)

	print("[PlotSelectionController] Initialisiert: Check-UI Infobox aktiv (Fast-Dismiss, 3D Close [X], Taste [P]).")
end

return PlotSelectionController
