--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local Camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = Shared:WaitForChild("Events")
local ConfigFolder = Shared:WaitForChild("Config")
local DataFolder = Shared:WaitForChild("Data")

-- Check-UI Design System Bibliotheken
local CheckUIFolder = Shared:WaitForChild("CheckUI")
local CheckUITheme = require(CheckUIFolder:WaitForChild("CheckUITheme") :: ModuleScript)
local CheckUIComponents = require(CheckUIFolder:WaitForChild("CheckUIComponents") :: ModuleScript)
local CheckUIController = require(CheckUIFolder:WaitForChild("CheckUIController") :: ModuleScript)
local CheckUIIcons = require(CheckUIFolder:WaitForChild("CheckUIIcons") :: ModuleScript)

local PlayerDataTemplateModule = DataFolder:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataTemplateModule)
export type InventoryData = PlayerDataTemplate.InventoryData

local ItemConfigModule = ConfigFolder:WaitForChild("ItemConfig") :: ModuleScript
local ItemConfig = require(ItemConfigModule)

local GoldUpdated = Events:WaitForChild("GoldUpdated") :: RemoteEvent
local NotificationEvent = Events:WaitForChild("ShowNotification") :: RemoteEvent
local DimensionChanged = Events:WaitForChild("DimensionChanged") :: RemoteEvent
local BossUpdated = Events:WaitForChild("BossUpdated") :: RemoteEvent
local InventoryUpdated = Events:WaitForChild("InventoryUpdated") :: RemoteEvent
local RequestInventory = Events:WaitForChild("RequestInventory") :: RemoteEvent

local HUDController = {}

-- UI-Element-Referenzen
local screenGui: ScreenGui? = nil

-- 1. Boss Bar Referenzen
local bossBarContainer: Frame? = nil
local bossBarFill: Frame? = nil
local bossTitleLabel: TextLabel? = nil

-- 2. Geld & CPS Referenzen (Oben rechts)
local goldCardFrame: Frame? = nil
local goldAmountLabel: TextLabel? = nil
local cpsLabel: TextLabel? = nil
local goldCoinIcon: TextLabel? = nil

-- 3. Spieler-Lebensanzeige (Unten links)
local healthCardFrame: Frame? = nil
local healthFillBar: Frame? = nil
local damageTrailBar: Frame? = nil
local healthTextLabel: TextLabel? = nil
local playerDimLabel: TextLabel? = nil
local healthCardStroke: UIStroke? = nil
local avatarImageLabel: ImageLabel? = nil

-- 4. Toast-Referenzen
local toastFrame: Frame? = nil
local toastText: TextLabel? = nil
local toastIcon: TextLabel? = nil
local toastStroke: UIStroke? = nil
local currentToastThread: thread? = nil

-- 5. Inventar UI Referenzen
local invButtonFrame: TextButton? = nil
local invBtnTitleLabel: TextLabel? = nil
local invCloseHintLabel: TextLabel? = nil
local invBadgeLabel: TextLabel? = nil
local invModalFrame: Frame? = nil
local invBackdrop: TextButton? = nil
local invGridFrame: ScrollingFrame? = nil
local invEmptyLabel: TextLabel? = nil
local invCategoryTabs: { [string]: TextButton } = {}
local lbTabButton: TextButton? = nil
local rbTabButton: TextButton? = nil

-- 6. Detail Modal (Infobox) Referenzen
local itemDetailModal: Frame? = nil
local isDetailOpen = false
local detailIconText: TextLabel? = nil
local detailTitleLabel: TextLabel? = nil
local detailRarityBadge: TextLabel? = nil
local detailStroke: UIStroke? = nil
local detailIconStroke: UIStroke? = nil
local detailStatsLabel: TextLabel? = nil
local detailDescLabel: TextLabel? = nil
local detailTipLabel: TextLabel? = nil

-- Zustand
local isInventoryOpen = false
local isHoldingPrompt = false
local currentCategory = "All"
local CATEGORY_ORDER = { "All", "Weapons", "Cores", "Materials" }
local cachedInventory: InventoryData = {
	Weapons = { "RustySword" },
	Materials = {
		IronOre = 0,
		VoidCrystal = 0,
	},
	Cores = {},
}
local cachedGold = 0
local cachedCPS = 0
local currentDimensionName = "Oberwelt"

-- Hilfsfunktion: Fügt einen schwarzen Kontur-Stroke nach Check-UI Standard ein
local function addCheckUIStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness or 2.4
	stroke.Parent = parent
	return stroke
end

-- Hilfsfunktion: Tausendertrennzeichen formatieren
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

-- Aktualisiert die Responsive Scales aller aktiven Modalfenster
local function updateDeviceScales()
	local scale = CheckUIController.getDeviceScale()
	if invModalFrame then
		local sc = invModalFrame:FindFirstChild("WindowScale") :: UIScale?
		if sc and isInventoryOpen then
			sc.Scale = scale
		end
	end
	if itemDetailModal then
		local sc = itemDetailModal:FindFirstChild("WindowScale") :: UIScale?
		if sc and isDetailOpen then
			sc.Scale = scale
		end
	end
end

-- Aktualisiert den Hotkey-Hinweis je nach Eingabegerät (PC vs. Controller)
local function updateHotkeyLabel(lastInputType: Enum.UserInputType)
	local isGamepad = (lastInputType == Enum.UserInputType.Gamepad1
		or lastInputType == Enum.UserInputType.Gamepad2
		or lastInputType == Enum.UserInputType.Gamepad3
		or lastInputType == Enum.UserInputType.Gamepad4)

	if invBtnTitleLabel then
		invBtnTitleLabel.Text = if isGamepad then "Inventar  [Y]" else "Inventar  [E]"
	end

	if invCloseHintLabel then
		invCloseHintLabel.Text = if isGamepad then "[B] / [Y] Schließen" else "[E] Schließen"
	end

	if lbTabButton and rbTabButton then
		lbTabButton.Text = if isGamepad then "LB" else "◀"
		rbTabButton.Text = if isGamepad then "RB" else "▶"
	end
end

-- ==========================================
-- INVENTAR RENDERING
-- ==========================================

-- Zählt die Gesamtmenge der Gegenstände
local function getTotalItemCount(): number
	local count = #cachedInventory.Weapons + #cachedInventory.Cores
	if cachedInventory.Materials.IronOre > 0 then
		count += 1
	end
	if cachedInventory.Materials.VoidCrystal > 0 then
		count += 1
	end
	return count
end

-- Aktualisiert den Badge auf dem Inventar-Button
local function updateInventoryBadge()
	if invBadgeLabel then
		local count = getTotalItemCount()
		invBadgeLabel.Text = tostring(count)
		invBadgeLabel.Visible = count > 0
	end
end

-- Erstellt eine Item-Karte im Inventar-Grid nach Check-UI Standard
local function createItemCard(parent: Instance, itemId: string, count: number, _customCategory: string?)
	local itemInfo = ItemConfig[itemId]
	local displayName = if itemInfo then itemInfo.DisplayName else itemId
	local icon = if itemInfo then itemInfo.Icon else "📦"
	local statsText = if itemInfo then itemInfo.StatsText else ""
	local desc = if itemInfo then itemInfo.Description else ""
	local rarityColor = if itemInfo then itemInfo.RarityColor else Color3.fromRGB(189, 195, 199)

	local card = Instance.new("Frame")
	card.Name = "Item_" .. itemId
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	card.BackgroundTransparency = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = card

	local cardStrokeColor = if rarityColor == Color3.fromRGB(189, 195, 199) then CheckUITheme.Colors.CardHighlight else rarityColor
	local stroke = Instance.new("UIStroke")
	stroke.Color = cardStrokeColor
	stroke.Thickness = 1.6
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	-- Icon-Container (abgesetzter 3D-Container)
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.Size = UDim2.new(0, 50, 0, 50)
	iconBox.Position = UDim2.new(0, 10, 0.5, 0)
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	iconBox.BackgroundTransparency = 0
	iconBox.BorderSizePixel = 0
	iconBox.Parent = card

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 4)
	iconCorner.Parent = iconBox

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(0, 0, 0)
	iconStroke.Thickness = 1.8
	iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iconStroke.Parent = iconBox

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextSize = 28
	iconLabel.Font = CheckUITheme.Typography.Font
	iconLabel.Parent = iconBox

	-- Name des Gegenstands (strikt GothamBlack mit schwarzem Stroke)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, -74, 0, 20)
	nameLabel.Position = UDim2.new(0, 68, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = CheckUITheme.Typography.Font
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = displayName
	nameLabel.Parent = card
	addCheckUIStroke(nameLabel, 2.2)

	-- Stats / Kategorie Badge (GothamBlack)
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "Stats"
	statsLabel.Size = UDim2.new(1, -74, 0, 16)
	statsLabel.Position = UDim2.new(0, 68, 0, 29)
	statsLabel.BackgroundTransparency = 1
	statsLabel.TextColor3 = cardStrokeColor
	statsLabel.Font = CheckUITheme.Typography.Font
	statsLabel.TextSize = 11
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Text = statsText
	statsLabel.Parent = card
	addCheckUIStroke(statsLabel, 1.8)

	-- Beschreibung / Hinweis (GothamBlack)
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Desc"
	descLabel.Size = UDim2.new(1, -74, 0, 16)
	descLabel.Position = UDim2.new(0, 68, 0, 48)
	descLabel.BackgroundTransparency = 1
	descLabel.TextColor3 = Color3.fromRGB(180, 195, 215)
	descLabel.Font = CheckUITheme.Typography.Font
	descLabel.TextSize = 10
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Text = desc
	descLabel.Parent = card
	addCheckUIStroke(descLabel, 1.6)

	-- Mengenschild (wenn Anzahl > 1)
	if count > 1 then
		local countPill = Instance.new("Frame")
		countPill.Name = "CountPill"
		countPill.Size = UDim2.new(0, 30, 0, 20)
		countPill.Position = UDim2.new(1, -36, 0, 6)
		countPill.BackgroundColor3 = Color3.fromRGB(12, 20, 26)
		countPill.BorderSizePixel = 0
		countPill.Parent = card

		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(0, 4)
		pillCorner.Parent = countPill

		local pillStroke = Instance.new("UIStroke")
		pillStroke.Color = Color3.fromRGB(0, 0, 0)
		pillStroke.Thickness = 1.8
		pillStroke.Parent = countPill

		local pillText = Instance.new("TextLabel")
		pillText.Size = UDim2.new(1, 0, 1, 0)
		pillText.BackgroundTransparency = 1
		pillText.TextColor3 = Color3.fromRGB(255, 255, 255)
		pillText.Font = CheckUITheme.Typography.Font
		pillText.TextSize = 11
		pillText.Text = "x" .. tostring(count)
		pillText.Parent = countPill
		addCheckUIStroke(pillText, 1.8)
	end

	-- Hover-Animation & Klick-Erkennung
	local hoverDetector = Instance.new("TextButton")
	hoverDetector.Name = "HoverDetector"
	hoverDetector.Size = UDim2.new(1, 0, 1, 0)
	hoverDetector.BackgroundTransparency = 1
	hoverDetector.Text = ""
	hoverDetector.Parent = card

	hoverDetector.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(36, 60, 72),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 2.2,
		}):Play()
	end)

	hoverDetector.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = CheckUITheme.Colors.CardBackground,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 1.6,
		}):Play()
	end)

	hoverDetector.MouseButton1Click:Connect(function()
		HUDController.ShowItemDetails(itemId, count)
	end)
end

-- Baut das Grid im Inventar neu auf basierend auf aktuellem Filter
local function rebuildInventoryList()
	if not invGridFrame or not invEmptyLabel then
		return
	end

	-- Vorherige Einträge löschen (außer Layout-Elemente)
	for _, child in invGridFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local itemCount = 0

	-- 1. Waffen
	if currentCategory == "All" or currentCategory == "Weapons" then
		for _, weaponId in ipairs(cachedInventory.Weapons) do
			createItemCard(invGridFrame, weaponId, 1, "Weapon")
			itemCount += 1
		end
	end

	-- 2. Seelenkerne
	if currentCategory == "All" or currentCategory == "Cores" then
		local coreCounts: { [string]: number } = {}
		for _, coreId in ipairs(cachedInventory.Cores) do
			coreCounts[coreId] = (coreCounts[coreId] or 0) + 1
		end
		for coreId, count in pairs(coreCounts) do
			createItemCard(invGridFrame, coreId, count, "Core")
			itemCount += 1
		end
	end

	-- 3. Materialien
	if currentCategory == "All" or currentCategory == "Materials" then
		if cachedInventory.Materials.IronOre > 0 then
			createItemCard(invGridFrame, "IronOre", cachedInventory.Materials.IronOre, "Material")
			itemCount += 1
		end
		if cachedInventory.Materials.VoidCrystal > 0 then
			createItemCard(invGridFrame, "VoidCrystal", cachedInventory.Materials.VoidCrystal, "Material")
			itemCount += 1
		end
	end

	invEmptyLabel.Visible = (itemCount == 0)
end

-- Setzt die aktive Kategorie und aktualisiert die Tab-Stile
local function setCategory(category: string)
	currentCategory = category
	for tabCat, btn in pairs(invCategoryTabs) do
		local isActive = (tabCat == category)
		local targetBg = if isActive then Color3.fromRGB(160, 0, 255) else CheckUITheme.Colors.CardBackground
		local targetText = if isActive then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 200, 220)
		TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = targetBg,
			TextColor3 = targetText,
		}):Play()
	end
	rebuildInventoryList()
end

-- Schultertasten-Feedback Animation
local function animateShoulderPress(btn: TextButton?)
	if not btn then
		return
	end
	local grow = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = Color3.fromRGB(45, 80, 95),
	})
	local reset = TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundColor3 = CheckUITheme.Colors.CardBackground,
	})
	grow:Play()
	grow.Completed:Connect(function()
		reset:Play()
	end)
end

-- Wechselt den Reiter um direction (+1 = vorwärts / RB, -1 = rückwärts / LB)
local function switchCategoryTab(direction: number)
	local currentIndex = table.find(CATEGORY_ORDER, currentCategory) or 1
	local newIndex = currentIndex + direction
	if newIndex > #CATEGORY_ORDER then
		newIndex = 1
	elseif newIndex < 1 then
		newIndex = #CATEGORY_ORDER
	end

	if direction > 0 then
		animateShoulderPress(rbTabButton)
	else
		animateShoulderPress(lbTabButton)
	end

	setCategory(CATEGORY_ORDER[newIndex])
end

-- Öffnet das Inventar mit Check-UI zentrierter Bounce-Scale-Animation
function HUDController.OpenInventory()
	if not invModalFrame or not invBackdrop or isInventoryOpen then
		return
	end
	isInventoryOpen = true

	rebuildInventoryList()
	updateInventoryBadge()

	invBackdrop.Visible = true
	invModalFrame.Visible = true

	local windowScale = invModalFrame:FindFirstChild("WindowScale") :: UIScale?
	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		windowScale.Scale = targetScale * 0.75
		TweenService:Create(windowScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = targetScale,
		}):Play()
	end
end

-- Schließt das Inventar
function HUDController.CloseInventory()
	if not invModalFrame or not invBackdrop or not isInventoryOpen then
		return
	end
	isInventoryOpen = false
	HUDController.CloseItemDetails()

	local windowScale = invModalFrame:FindFirstChild("WindowScale") :: UIScale?
	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		local closeTween = TweenService:Create(windowScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Scale = targetScale * 0.70,
		})
		closeTween:Play()
		closeTween.Completed:Connect(function()
			if not isInventoryOpen and invModalFrame and invBackdrop then
				invModalFrame.Visible = false
				invBackdrop.Visible = false
				windowScale.Scale = targetScale
			end
		end)
	else
		invModalFrame.Visible = false
		invBackdrop.Visible = false
	end
end

-- Zeigt die Infobox für ein ausgewähltes Item an
function HUDController.ShowItemDetails(itemId: string, count: number)
	if not itemDetailModal then
		return
	end

	local itemInfo = ItemConfig[itemId]
	if not itemInfo then
		return
	end

	if detailIconText then
		detailIconText.Text = itemInfo.Icon
	end
	if detailTitleLabel then
		detailTitleLabel.Text = itemInfo.DisplayName
	end
	if detailRarityBadge then
		detailRarityBadge.Text = string.format("[%s]  •  %s", itemInfo.RarityLabel, itemInfo.TypeLabel)
		detailRarityBadge.TextColor3 = itemInfo.RarityColor
	end
	if detailStroke then
		detailStroke.Color = itemInfo.RarityColor
	end
	if detailIconStroke then
		detailIconStroke.Color = itemInfo.RarityColor
	end
	if detailStatsLabel then
		detailStatsLabel.Text = itemInfo.DetailedStats
		detailStatsLabel.TextColor3 = itemInfo.RarityColor
	end
	if detailDescLabel then
		detailDescLabel.Text = itemInfo.Description
	end
	if detailTipLabel then
		detailTipLabel.Text = "💡 " .. itemInfo.UsageTip
	end

	isDetailOpen = true
	itemDetailModal.Visible = true

	local windowScale = itemDetailModal:FindFirstChild("WindowScale") :: UIScale?
	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		windowScale.Scale = targetScale * 0.75
		TweenService:Create(windowScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = targetScale,
		}):Play()
	end
end

-- Schließt die Infobox
function HUDController.CloseItemDetails()
	if not itemDetailModal or not isDetailOpen then
		return
	end
	isDetailOpen = false

	local windowScale = itemDetailModal:FindFirstChild("WindowScale") :: UIScale?
	local targetScale = CheckUIController.getDeviceScale()
	if windowScale then
		local closeTween = TweenService:Create(windowScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Scale = targetScale * 0.70,
		})
		closeTween:Play()
		closeTween.Completed:Connect(function()
			if not isDetailOpen and itemDetailModal then
				itemDetailModal.Visible = false
				windowScale.Scale = targetScale
			end
		end)
	else
		itemDetailModal.Visible = false
	end
end

-- Schaltet das Inventar um (Öffnen / Schließen)
function HUDController.ToggleInventory()
	if isInventoryOpen then
		HUDController.CloseInventory()
	else
		HUDController.OpenInventory()
	end
end

-- ==========================================
-- HUD ERSTELLUNG & LAYOUT
-- ==========================================

local function createHUD()
	if screenGui then
		return
	end

	-- Haupt-ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RealmRaidersHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui
	screenGui = gui

	-- ----------------------------------------------------
	-- 1. BOSS HEALTH BAR (Oben zentriert)
	-- ----------------------------------------------------
	local bossFrame = Instance.new("Frame")
	bossFrame.Name = "BossBar"
	bossFrame.Size = UDim2.new(0, 380, 0, 42)
	bossFrame.Position = UDim2.new(0.5, 0, 0, 20)
	bossFrame.AnchorPoint = Vector2.new(0.5, 0)
	bossFrame.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	bossFrame.BorderSizePixel = 0
	bossFrame.Visible = false
	bossFrame.ZIndex = 5
	bossFrame.Parent = gui
	bossBarContainer = bossFrame

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 4)
	bCorner.Parent = bossFrame

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(12, 20, 26)
	bStroke.Thickness = 2.8
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = bossFrame

	local bFill = Instance.new("Frame")
	bFill.Name = "Fill"
	bFill.Size = UDim2.new(1, 0, 1, 0)
	bFill.BackgroundColor3 = Color3.fromRGB(208, 0, 32)
	bFill.BorderSizePixel = 0
	bFill.ZIndex = 6
	bFill.Parent = bossFrame
	bossBarFill = bFill

	local bFillCorner = Instance.new("UICorner")
	bFillCorner.CornerRadius = UDim.new(0, 4)
	bFillCorner.Parent = bFill

	local bBevel = Instance.new("Frame")
	bBevel.Size = UDim2.new(1, 0, 0, 3)
	bBevel.Position = UDim2.new(0, 0, 1, -3)
	bBevel.BackgroundColor3 = Color3.fromRGB(112, 0, 16)
	bBevel.BorderSizePixel = 0
	bBevel.ZIndex = 7
	bBevel.Parent = bFill

	local bTitle = Instance.new("TextLabel")
	bTitle.Name = "BossTitle"
	bTitle.Size = UDim2.new(1, 0, 1, 0)
	bTitle.BackgroundTransparency = 1
	bTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	bTitle.Font = CheckUITheme.Typography.Font
	bTitle.TextSize = 13
	bTitle.Text = "👹 Wald-Golem: 300 / 300 HP"
	bTitle.ZIndex = 8
	bTitle.Parent = bossFrame
	addCheckUIStroke(bTitle, 2.4)
	bossTitleLabel = bTitle

	-- ----------------------------------------------------
	-- 2. GELD & CPS KACHEL (Oben rechts)
	-- ----------------------------------------------------
	local goldCard = Instance.new("Frame")
	goldCard.Name = "GoldCard"
	goldCard.Size = UDim2.new(0, 240, 0, 50)
	goldCard.Position = UDim2.new(1, -260, 0, 12)
	goldCard.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	goldCard.BorderSizePixel = 0
	goldCard.ZIndex = 5
	goldCard.Parent = gui
	goldCardFrame = goldCard

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 4)
	cardCorner.Parent = goldCard

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(12, 20, 26)
	cardStroke.Thickness = 2.8
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardStroke.Parent = goldCard

	local cardHighlight = Instance.new("Frame")
	cardHighlight.Size = UDim2.new(1, -2, 1, -2)
	cardHighlight.Position = UDim2.new(0.5, 0, 0.5, 0)
	cardHighlight.AnchorPoint = Vector2.new(0.5, 0.5)
	cardHighlight.BackgroundTransparency = 1
	cardHighlight.BorderSizePixel = 0
	cardHighlight.ZIndex = 6
	cardHighlight.Parent = goldCard

	local chStroke = Instance.new("UIStroke")
	chStroke.Color = CheckUITheme.Colors.CardHighlight
	chStroke.Thickness = 1.2
	chStroke.Transparency = 0.3
	chStroke.Parent = cardHighlight

	-- Münzen Icon Badge
	local coinBadge = Instance.new("Frame")
	coinBadge.Name = "CoinBadge"
	coinBadge.Size = UDim2.new(0, 34, 0, 34)
	coinBadge.Position = UDim2.new(0, 8, 0.5, 0)
	coinBadge.AnchorPoint = Vector2.new(0, 0.5)
	coinBadge.BackgroundColor3 = Color3.fromRGB(255, 208, 0)
	coinBadge.BorderSizePixel = 0
	coinBadge.ZIndex = 7
	coinBadge.Parent = goldCard

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(0, 4)
	coinCorner.Parent = coinBadge

	local coinStroke = Instance.new("UIStroke")
	coinStroke.Color = Color3.fromRGB(12, 20, 26)
	coinStroke.Thickness = 2.0
	coinStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	coinStroke.Parent = coinBadge

	local coinIcon = Instance.new("TextLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.new(1, 0, 1, 0)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Text = "G"
	coinIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	coinIcon.Font = CheckUITheme.Typography.Font
	coinIcon.TextSize = 18
	coinIcon.ZIndex = 8
	coinIcon.Parent = coinBadge
	addCheckUIStroke(coinIcon, 2.2)
	goldCoinIcon = coinIcon

	-- Titel "SEELEN-GOLD"
	local goldHeader = Instance.new("TextLabel")
	goldHeader.Name = "Header"
	goldHeader.Size = UDim2.new(0, 95, 0, 14)
	goldHeader.Position = UDim2.new(0, 50, 0, 6)
	goldHeader.BackgroundTransparency = 1
	goldHeader.TextColor3 = Color3.fromRGB(255, 225, 120)
	goldHeader.Font = CheckUITheme.Typography.Font
	goldHeader.TextSize = 10
	goldHeader.TextXAlignment = Enum.TextXAlignment.Left
	goldHeader.Text = "SEELEN-GOLD"
	goldHeader.ZIndex = 7
	goldHeader.Parent = goldCard
	addCheckUIStroke(goldHeader, 1.8)

	-- Gold-Zahl
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldAmount"
	goldLabel.Size = UDim2.new(0, 110, 0, 22)
	goldLabel.Position = UDim2.new(0, 50, 0, 20)
	goldLabel.BackgroundTransparency = 1
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	goldLabel.Font = CheckUITheme.Typography.Font
	goldLabel.TextSize = 18
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Text = "0"
	goldLabel.ZIndex = 7
	goldLabel.Parent = goldCard
	addCheckUIStroke(goldLabel, 2.4)
	goldAmountLabel = goldLabel

	-- CPS Badge (Lime Green Button State Triad Style)
	local cpsBadge = Instance.new("Frame")
	cpsBadge.Name = "CPSBadge"
	cpsBadge.Size = UDim2.new(0, 66, 0, 26)
	cpsBadge.Position = UDim2.new(1, -74, 0.5, 0)
	cpsBadge.AnchorPoint = Vector2.new(0, 0.5)
	cpsBadge.BackgroundColor3 = Color3.fromRGB(105, 225, 0)
	cpsBadge.BorderSizePixel = 0
	cpsBadge.ZIndex = 7
	cpsBadge.Parent = goldCard

	local cpsCorner = Instance.new("UICorner")
	cpsCorner.CornerRadius = UDim.new(0, 4)
	cpsCorner.Parent = cpsBadge

	local cpsStroke = Instance.new("UIStroke")
	cpsStroke.Color = Color3.fromRGB(12, 20, 26)
	cpsStroke.Thickness = 2.0
	cpsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cpsStroke.Parent = cpsBadge

	local cpsBevel = Instance.new("Frame")
	cpsBevel.Size = UDim2.new(1, 0, 0, 2)
	cpsBevel.Position = UDim2.new(0, 0, 1, -2)
	cpsBevel.BackgroundColor3 = CheckUITheme.Colors.ClaimBevel
	cpsBevel.BorderSizePixel = 0
	cpsBevel.ZIndex = 8
	cpsBevel.Parent = cpsBadge

	local cpsText = Instance.new("TextLabel")
	cpsText.Name = "CPSText"
	cpsText.Size = UDim2.new(1, 0, 1, 0)
	cpsText.BackgroundTransparency = 1
	cpsText.TextColor3 = Color3.fromRGB(255, 255, 255)
	cpsText.Font = CheckUITheme.Typography.Font
	cpsText.TextSize = 12
	cpsText.Text = "+0 /s"
	cpsText.ZIndex = 9
	cpsText.Parent = cpsBadge
	addCheckUIStroke(cpsText, 2.2)
	cpsLabel = cpsText

	-- ----------------------------------------------------
	-- 3. INVENTAR-BUTTON (Kompakt unter GoldCard)
	-- ----------------------------------------------------
	local invBtn = Instance.new("TextButton")
	invBtn.Name = "InventoryButton"
	invBtn.Size = UDim2.new(0, 240, 0, 34)
	invBtn.Position = UDim2.new(1, -260, 0, 68)
	invBtn.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	invBtn.BorderSizePixel = 0
	invBtn.AutoButtonColor = false
	invBtn.Text = ""
	invBtn.ZIndex = 5
	invBtn.Parent = gui
	invButtonFrame = invBtn

	local invBtnCorner = Instance.new("UICorner")
	invBtnCorner.CornerRadius = UDim.new(0, 4)
	invBtnCorner.Parent = invBtn

	local invBtnStroke = Instance.new("UIStroke")
	invBtnStroke.Color = Color3.fromRGB(12, 20, 26)
	invBtnStroke.Thickness = 2.4
	invBtnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	invBtnStroke.Parent = invBtn

	local invBtnScale = Instance.new("UIScale")
	invBtnScale.Name = "ButtonScale"
	invBtnScale.Scale = 1
	invBtnScale.Parent = invBtn

	CheckUIController.bindButtonAnimations(invBtn, invBtnScale, 1.03, 0.96)

	local btnTitle = Instance.new("TextLabel")
	btnTitle.Size = UDim2.new(0, 160, 1, 0)
	btnTitle.Position = UDim2.new(0, 14, 0, 0)
	btnTitle.BackgroundTransparency = 1
	btnTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnTitle.Font = CheckUITheme.Typography.Font
	btnTitle.TextSize = 12
	btnTitle.TextXAlignment = Enum.TextXAlignment.Left
	btnTitle.Text = "Inventar  [E]"
	btnTitle.ZIndex = 6
	btnTitle.Parent = invBtn
	addCheckUIStroke(btnTitle, 2.0)
	invBtnTitleLabel = btnTitle

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 24, 0, 20)
	badge.Position = UDim2.new(1, -32, 0.5, 0)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	badge.BorderSizePixel = 0
	badge.ZIndex = 7
	badge.Parent = invBtn

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.fromRGB(0, 0, 0)
	badgeStroke.Thickness = 1.6
	badgeStroke.Parent = badge

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Size = UDim2.new(1, 0, 1, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	badgeLabel.Font = CheckUITheme.Typography.Font
	badgeLabel.TextSize = 11
	badgeLabel.Text = "1"
	badgeLabel.ZIndex = 8
	badgeLabel.Parent = badge
	addCheckUIStroke(badgeLabel, 1.8)
	invBadgeLabel = badgeLabel

	invBtn.MouseButton1Click:Connect(function()
		HUDController.ToggleInventory()
	end)

	-- ----------------------------------------------------
	-- 4. SPIELER-LEBENSANZEIGE (Unten links)
	-- ----------------------------------------------------
	local hpCard = Instance.new("Frame")
	hpCard.Name = "PlayerHealthCard"
	hpCard.Size = UDim2.new(0, 260, 0, 64)
	hpCard.Position = UDim2.new(0, 20, 1, -84)
	hpCard.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	hpCard.BorderSizePixel = 0
	hpCard.ZIndex = 5
	hpCard.Parent = gui
	healthCardFrame = hpCard

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 4)
	hpCorner.Parent = hpCard

	local hpCardStroke = Instance.new("UIStroke")
	hpCardStroke.Color = Color3.fromRGB(12, 20, 26)
	hpCardStroke.Thickness = 2.8
	hpCardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hpCardStroke.Parent = hpCard
	healthCardStroke = hpCardStroke

	-- Avatar Frame
	local avFrame = Instance.new("Frame")
	avFrame.Name = "AvatarFrame"
	avFrame.Size = UDim2.new(0, 48, 0, 48)
	avFrame.Position = UDim2.new(0, 8, 0.5, 0)
	avFrame.AnchorPoint = Vector2.new(0, 0.5)
	avFrame.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	avFrame.BorderSizePixel = 0
	avFrame.ZIndex = 6
	avFrame.Parent = hpCard

	local avCorner = Instance.new("UICorner")
	avCorner.CornerRadius = UDim.new(0, 4)
	avCorner.Parent = avFrame

	local avStroke = Instance.new("UIStroke")
	avStroke.Color = Color3.fromRGB(0, 0, 0)
	avStroke.Thickness = 2.0
	avStroke.Parent = avFrame

	local avImg = Instance.new("ImageLabel")
	avImg.Name = "AvatarHeadshot"
	avImg.Size = UDim2.new(1, 0, 1, 0)
	avImg.BackgroundTransparency = 1
	avImg.ScaleType = Enum.ScaleType.Fit
	avImg.Visible = false
	avImg.ZIndex = 7
	avImg.Parent = avFrame
	avatarImageLabel = avImg

	local avFallback = Instance.new("TextLabel")
	avFallback.Name = "FallbackIcon"
	avFallback.Size = UDim2.new(1, 0, 1, 0)
	avFallback.BackgroundTransparency = 1
	avFallback.Text = "👤"
	avFallback.TextSize = 26
	avFallback.ZIndex = 7
	avFallback.Parent = avFrame

	task.spawn(function()
		local content, isReady = Players:GetUserThumbnailAsync(
			LocalPlayer.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if isReady and avImg then
			avImg.Image = content
			avImg.Visible = true
			avFallback.Visible = false
		end
	end)

	-- Spieler-Name
	local pNameLabel = Instance.new("TextLabel")
	pNameLabel.Name = "PlayerName"
	pNameLabel.Size = UDim2.new(0, 110, 0, 16)
	pNameLabel.Position = UDim2.new(0, 66, 0, 10)
	pNameLabel.BackgroundTransparency = 1
	pNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pNameLabel.Font = CheckUITheme.Typography.Font
	pNameLabel.TextSize = 13
	pNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	pNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	pNameLabel.Text = LocalPlayer.DisplayName
	pNameLabel.ZIndex = 7
	pNameLabel.Parent = hpCard
	addCheckUIStroke(pNameLabel, 2.2)

	-- Dimensions-Tag
	local dimTag = Instance.new("TextLabel")
	dimTag.Name = "DimensionTag"
	dimTag.Size = UDim2.new(0, 95, 0, 14)
	dimTag.Position = UDim2.new(1, -100, 0, 11)
	dimTag.BackgroundTransparency = 1
	dimTag.TextColor3 = Color3.fromRGB(116, 185, 255)
	dimTag.Font = CheckUITheme.Typography.Font
	dimTag.TextSize = 10
	dimTag.TextXAlignment = Enum.TextXAlignment.Right
	dimTag.TextTruncate = Enum.TextTruncate.AtEnd
	dimTag.Text = "📍 " .. currentDimensionName
	dimTag.ZIndex = 7
	dimTag.Parent = hpCard
	addCheckUIStroke(dimTag, 1.8)
	playerDimLabel = dimTag

	-- Lebensbalken Hintergrund
	local barBg = Instance.new("Frame")
	barBg.Name = "HealthBarBg"
	barBg.Size = UDim2.new(1, -76, 0, 20)
	barBg.Position = UDim2.new(0, 66, 0, 34)
	barBg.BackgroundColor3 = CheckUITheme.Colors.ProgressTrough
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 6
	barBg.Parent = hpCard

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 4)
	barBgCorner.Parent = barBg

	local barBgStroke = Instance.new("UIStroke")
	barBgStroke.Color = CheckUITheme.Colors.ProgressBorder
	barBgStroke.Thickness = 2.0
	barBgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barBgStroke.Parent = barBg

	-- Roter Schadens-Verzögerungsbalken
	local damageBar = Instance.new("Frame")
	damageBar.Name = "DamageTrail"
	damageBar.Size = UDim2.new(1, 0, 1, 0)
	damageBar.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	damageBar.BorderSizePixel = 0
	damageBar.ZIndex = 7
	damageBar.Parent = barBg
	damageTrailBar = damageBar

	local dmgCorner = Instance.new("UICorner")
	dmgCorner.CornerRadius = UDim.new(0, 4)
	dmgCorner.Parent = damageBar

	-- Grüner Vordergrund-Lebensbalken
	local fillBar = Instance.new("Frame")
	fillBar.Name = "HealthFill"
	fillBar.Size = UDim2.new(1, 0, 1, 0)
	fillBar.BackgroundColor3 = Color3.fromRGB(105, 225, 0)
	fillBar.BorderSizePixel = 0
	fillBar.ZIndex = 8
	fillBar.Parent = barBg
	healthFillBar = fillBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fillBar

	local fillBevel = Instance.new("Frame")
	fillBevel.Size = UDim2.new(1, 0, 0, 2)
	fillBevel.Position = UDim2.new(0, 0, 1, -2)
	fillBevel.BackgroundColor3 = CheckUITheme.Colors.ClaimBevel
	fillBevel.BorderSizePixel = 0
	fillBevel.ZIndex = 9
	fillBevel.Parent = fillBar

	-- HP-Zahlenanzeige
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.Font = CheckUITheme.Typography.Font
	hpText.TextSize = 11
	hpText.Text = "100 / 100 HP"
	hpText.ZIndex = 10
	hpText.Parent = barBg
	addCheckUIStroke(hpText, 2.2)
	healthTextLabel = hpText

	-- ----------------------------------------------------
	-- 5. INVENTAR MODAL (Check-UI Standard Solid Slate Canvas)
	-- ----------------------------------------------------
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "InventoryBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = gui
	invBackdrop = backdrop

	backdrop.MouseButton1Click:Connect(function()
		HUDController.CloseInventory()
	end)

	-- Haupt-Inventarfenster (Solid Slate Canvas #3B5866, Center-Anchored)
	local modal = Instance.new("Frame")
	modal.Name = "InventoryModal"
	modal.Size = UDim2.new(0, 520, 0, 430)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = CheckUITheme.Colors.Canvas
	modal.BackgroundTransparency = 0
	modal.BorderSizePixel = 0
	modal.ClipsDescendants = true
	modal.Visible = false
	modal.ZIndex = 11
	modal.Parent = gui
	invModalFrame = modal

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 4)
	modalCorner.Parent = modal

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Name = "OuterStroke"
	modalStroke.Color = CheckUITheme.Colors.CanvasBorder
	modalStroke.Thickness = 3.5
	modalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	modalStroke.Parent = modal

	local windowScale = Instance.new("UIScale")
	windowScale.Name = "WindowScale"
	windowScale.Scale = CheckUIController.getDeviceScale()
	windowScale.Parent = modal

	-- Seamless Fading Damier Overlay (Check-UI Tenet 6)
	local damier = Instance.new("ImageLabel")
	damier.Name = "WindowDamier"
	damier.Size = UDim2.new(1, 0, 1, 0)
	damier.BackgroundTransparency = 1
	damier.Image = CheckUITheme.Assets.Checkerboard
	damier.ScaleType = Enum.ScaleType.Tile
	damier.TileSize = UDim2.new(0, 24, 0, 24)
	damier.ImageColor3 = Color3.fromRGB(0, 0, 0)
	damier.ZIndex = 11
	damier.Parent = modal

	local damierGrad = Instance.new("UIGradient")
	damierGrad.Rotation = 90
	damierGrad.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0.00, 1.00),
		NumberSequenceKeypoint.new(0.20, 0.85),
		NumberSequenceKeypoint.new(0.65, 0.40),
		NumberSequenceKeypoint.new(1.00, 0.12),
	}
	damierGrad.Parent = damier

	-- Kopfzeile mit 2-Tier 3D Drop-Shadow Divider & 3D Close Button [X]
	local headerFrame = CheckUIComponents.createHeader(modal, "INVENTAR & RELIKTE", CheckUITheme.HeaderThemes.Rebirth)
	headerFrame.ZIndex = 12

	local closeBtn = headerFrame:FindFirstChild("CloseButton") :: ImageButton?
	if closeBtn then
		closeBtn.MouseButton1Click:Connect(function()
			HUDController.CloseInventory()
		end)
	end

	-- Hotkey-Hinweis zum Schließen
	local closeHint = Instance.new("TextLabel")
	closeHint.Name = "CloseHint"
	closeHint.Size = UDim2.new(0, 140, 0, 24)
	closeHint.Position = UDim2.new(1, -68, 0.5, -2)
	closeHint.AnchorPoint = Vector2.new(1, 0.5)
	closeHint.BackgroundTransparency = 1
	closeHint.TextColor3 = Color3.fromRGB(224, 210, 255)
	closeHint.Font = CheckUITheme.Typography.Font
	closeHint.TextSize = 12
	closeHint.TextXAlignment = Enum.TextXAlignment.Right
	closeHint.Text = "[E] Schließen"
	closeHint.ZIndex = 15
	closeHint.Parent = headerFrame
	addCheckUIStroke(closeHint, 2.0)
	invCloseHintLabel = closeHint

	-- Kategorie-Reiter (TabBar mit LB & RB Schultertasten-Steuerung)
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -36, 0, 34)
	tabBar.Position = UDim2.new(0, 18, 0, 68)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 13
	tabBar.Parent = modal

	-- LB Button
	local lbBtn = Instance.new("TextButton")
	lbBtn.Name = "LB_Button"
	lbBtn.Size = UDim2.new(0, 36, 1, 0)
	lbBtn.Position = UDim2.new(0, 0, 0, 0)
	lbBtn.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	lbBtn.BorderSizePixel = 0
	lbBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbBtn.Font = CheckUITheme.Typography.Font
	lbBtn.TextSize = 12
	lbBtn.Text = "LB"
	lbBtn.ZIndex = 14
	lbBtn.Parent = tabBar
	lbTabButton = lbBtn

	local lbCorner = Instance.new("UICorner")
	lbCorner.CornerRadius = UDim.new(0, 4)
	lbCorner.Parent = lbBtn

	local lbStroke = Instance.new("UIStroke")
	lbStroke.Color = Color3.fromRGB(0, 0, 0)
	lbStroke.Thickness = 2.0
	lbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lbStroke.Parent = lbBtn

	lbBtn.MouseButton1Click:Connect(function()
		switchCategoryTab(-1)
	end)

	-- Tabs Container
	local tabsContainer = Instance.new("Frame")
	tabsContainer.Name = "TabsContainer"
	tabsContainer.Size = UDim2.new(1, -88, 1, 0)
	tabsContainer.Position = UDim2.new(0, 44, 0, 0)
	tabsContainer.BackgroundTransparency = 1
	tabsContainer.ZIndex = 13
	tabsContainer.Parent = tabBar

	local categories = {
		{ Id = "All", Label = "Alle" },
		{ Id = "Weapons", Label = "⚔️ Waffen" },
		{ Id = "Cores", Label = "🔮 Seelenkerne" },
		{ Id = "Materials", Label = "⛏️ Materialien" },
	}

	local totalTabWidth = 520 - 36 - 88
	local tabWidth = (totalTabWidth - ((#categories - 1) * 6)) / #categories
	for i, catData in ipairs(categories) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. catData.Id
		tabBtn.Size = UDim2.new(0, tabWidth, 1, 0)
		tabBtn.Position = UDim2.new(0, (i - 1) * (tabWidth + 6), 0, 0)
		tabBtn.BackgroundColor3 = if catData.Id == "All" then Color3.fromRGB(160, 0, 255) else CheckUITheme.Colors.CardBackground
		tabBtn.BorderSizePixel = 0
		tabBtn.TextColor3 = if catData.Id == "All" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 200, 220)
		tabBtn.Font = CheckUITheme.Typography.Font
		tabBtn.TextSize = 11
		tabBtn.Text = catData.Label
		tabBtn.ZIndex = 14
		tabBtn.Parent = tabsContainer

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 4)
		tabCorner.Parent = tabBtn

		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = Color3.fromRGB(0, 0, 0)
		tabStroke.Thickness = 2.0
		tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tabStroke.Parent = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			setCategory(catData.Id)
		end)

		invCategoryTabs[catData.Id] = tabBtn
	end

	-- RB Button
	local rbBtn = Instance.new("TextButton")
	rbBtn.Name = "RB_Button"
	rbBtn.Size = UDim2.new(0, 36, 1, 0)
	rbBtn.Position = UDim2.new(1, -36, 0, 0)
	rbBtn.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	rbBtn.BorderSizePixel = 0
	rbBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	rbBtn.Font = CheckUITheme.Typography.Font
	rbBtn.TextSize = 12
	rbBtn.Text = "RB"
	rbBtn.ZIndex = 14
	rbBtn.Parent = tabBar
	rbTabButton = rbBtn

	local rbCorner = Instance.new("UICorner")
	rbCorner.CornerRadius = UDim.new(0, 4)
	rbCorner.Parent = rbBtn

	local rbStroke = Instance.new("UIStroke")
	rbStroke.Color = Color3.fromRGB(0, 0, 0)
	rbStroke.Thickness = 2.0
	rbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rbStroke.Parent = rbBtn

	rbBtn.MouseButton1Click:Connect(function()
		switchCategoryTab(1)
	end)

	-- Scrolling Grid Container
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemGrid"
	scrollFrame.Size = UDim2.new(1, -36, 1, -118)
	scrollFrame.Position = UDim2.new(0, 18, 0, 108)
	scrollFrame.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(85, 140, 160)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.ZIndex = 13
	scrollFrame.Parent = modal
	invGridFrame = scrollFrame

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 4)
	sCorner.Parent = scrollFrame

	local sStroke = Instance.new("UIStroke")
	sStroke.Color = CheckUITheme.Colors.CanvasBorder
	sStroke.Thickness = 2.0
	sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sStroke.Parent = scrollFrame

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft = UDim.new(0, 8)
	scrollPad.PaddingRight = UDim.new(0, 12)
	scrollPad.PaddingTop = UDim.new(0, 8)
	scrollPad.PaddingBottom = UDim.new(0, 12)
	scrollPad.Parent = scrollFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 224, 0, 80)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
	gridLayout.Parent = scrollFrame

	-- Leerzustand Anzeige (Empty state)
	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyLabel"
	empty.Size = UDim2.new(1, -36, 0, 120)
	empty.Position = UDim2.new(0, 18, 0.52, -60)
	empty.BackgroundTransparency = 1
	empty.TextColor3 = Color3.fromRGB(240, 245, 255)
	empty.Font = CheckUITheme.Typography.Font
	empty.TextSize = 14
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextYAlignment = Enum.TextYAlignment.Center
	empty.TextWrapped = true
	empty.Text = "📦 Keine Gegenstände in dieser Kategorie.\nErkunde Ruinen und bezwinge Bosse für Beute!"
	empty.Visible = false
	empty.ZIndex = 15
	empty.Parent = modal
	addCheckUIStroke(empty, 2.4)
	invEmptyLabel = empty

	-- ----------------------------------------------------
	-- 6. ITEM DETAIL MODAL (Check-UI Standard Solid Slate Canvas)
	-- ----------------------------------------------------
	local detailFrame = Instance.new("Frame")
	detailFrame.Name = "ItemDetailModal"
	detailFrame.Size = UDim2.new(0, 360, 0, 350)
	detailFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	detailFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	detailFrame.BackgroundColor3 = CheckUITheme.Colors.Canvas
	detailFrame.BackgroundTransparency = 0
	detailFrame.BorderSizePixel = 0
	detailFrame.ClipsDescendants = true
	detailFrame.Visible = false
	detailFrame.ZIndex = 25
	detailFrame.Parent = gui
	itemDetailModal = detailFrame

	local dCorner = Instance.new("UICorner")
	dCorner.CornerRadius = UDim.new(0, 4)
	dCorner.Parent = detailFrame

	local dStroke = Instance.new("UIStroke")
	dStroke.Color = CheckUITheme.Colors.CanvasBorder
	dStroke.Thickness = 3.5
	dStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dStroke.Parent = detailFrame
	detailStroke = dStroke

	local dWindowScale = Instance.new("UIScale")
	dWindowScale.Name = "WindowScale"
	dWindowScale.Scale = CheckUIController.getDeviceScale()
	dWindowScale.Parent = detailFrame

	-- Fading Damier
	local dDamier = Instance.new("ImageLabel")
	dDamier.Name = "WindowDamier"
	dDamier.Size = UDim2.new(1, 0, 1, 0)
	dDamier.BackgroundTransparency = 1
	dDamier.Image = CheckUITheme.Assets.Checkerboard
	dDamier.ScaleType = Enum.ScaleType.Tile
	dDamier.TileSize = UDim2.new(0, 24, 0, 24)
	dDamier.ImageColor3 = Color3.fromRGB(0, 0, 0)
	dDamier.ZIndex = 25
	dDamier.Parent = detailFrame

	local dDamierGrad = Instance.new("UIGradient")
	dDamierGrad.Rotation = 90
	dDamierGrad.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0.00, 1.00),
		NumberSequenceKeypoint.new(0.20, 0.85),
		NumberSequenceKeypoint.new(0.65, 0.40),
		NumberSequenceKeypoint.new(1.00, 0.12),
	}
	dDamierGrad.Parent = dDamier

	-- Kopfzeile mit 2-Tier 3D Drop-Shadow & 3D Close Button [X]
	local dHeader = CheckUIComponents.createHeader(detailFrame, "GEGENSTAND DETAILS", CheckUITheme.HeaderThemes.Codes)
	dHeader.ZIndex = 26

	local dCloseBtn = dHeader:FindFirstChild("CloseButton") :: ImageButton?
	if dCloseBtn then
		dCloseBtn.MouseButton1Click:Connect(function()
			HUDController.CloseItemDetails()
		end)
	end

	-- Subheader Infozeile (Icon, Name, Seltenheit)
	local dInfoBox = Instance.new("Frame")
	dInfoBox.Name = "InfoBox"
	dInfoBox.Size = UDim2.new(1, -28, 0, 52)
	dInfoBox.Position = UDim2.new(0, 14, 0, 68)
	dInfoBox.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	dInfoBox.BorderSizePixel = 0
	dInfoBox.ZIndex = 27
	dInfoBox.Parent = detailFrame

	local dInfoCorner = Instance.new("UICorner")
	dInfoCorner.CornerRadius = UDim.new(0, 4)
	dInfoCorner.Parent = dInfoBox

	local dInfoStroke = Instance.new("UIStroke")
	dInfoStroke.Color = Color3.fromRGB(0, 0, 0)
	dInfoStroke.Thickness = 2.0
	dInfoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dInfoStroke.Parent = dInfoBox

	local dIconBox = Instance.new("Frame")
	dIconBox.Name = "IconBox"
	dIconBox.Size = UDim2.new(0, 42, 0, 42)
	dIconBox.Position = UDim2.new(0, 6, 0.5, 0)
	dIconBox.AnchorPoint = Vector2.new(0, 0.5)
	dIconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	dIconBox.BorderSizePixel = 0
	dIconBox.ZIndex = 28
	dIconBox.Parent = dInfoBox

	local dIconCorner = Instance.new("UICorner")
	dIconCorner.CornerRadius = UDim.new(0, 4)
	dIconCorner.Parent = dIconBox

	local dIconStroke = Instance.new("UIStroke")
	dIconStroke.Color = Color3.fromRGB(0, 0, 0)
	dIconStroke.Thickness = 1.8
	dIconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dIconStroke.Parent = dIconBox
	detailIconStroke = dIconStroke

	local dIconText = Instance.new("TextLabel")
	dIconText.Name = "IconText"
	dIconText.Size = UDim2.new(1, 0, 1, 0)
	dIconText.BackgroundTransparency = 1
	dIconText.Text = "⚔️"
	dIconText.TextSize = 24
	dIconText.Font = CheckUITheme.Typography.Font
	dIconText.ZIndex = 29
	dIconText.Parent = dIconBox
	detailIconText = dIconText

	local dTitle = Instance.new("TextLabel")
	dTitle.Name = "Title"
	dTitle.Size = UDim2.new(1, -60, 0, 20)
	dTitle.Position = UDim2.new(0, 54, 0, 7)
	dTitle.BackgroundTransparency = 1
	dTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	dTitle.Font = CheckUITheme.Typography.Font
	dTitle.TextSize = 14
	dTitle.TextXAlignment = Enum.TextXAlignment.Left
	dTitle.TextTruncate = Enum.TextTruncate.AtEnd
	dTitle.Text = "Item Name"
	dTitle.ZIndex = 28
	dTitle.Parent = dInfoBox
	addCheckUIStroke(dTitle, 2.2)
	detailTitleLabel = dTitle

	local dRarityBadge = Instance.new("TextLabel")
	dRarityBadge.Name = "RarityBadge"
	dRarityBadge.Size = UDim2.new(1, -60, 0, 16)
	dRarityBadge.Position = UDim2.new(0, 54, 0, 27)
	dRarityBadge.BackgroundTransparency = 1
	dRarityBadge.TextColor3 = Color3.fromRGB(150, 160, 185)
	dRarityBadge.Font = CheckUITheme.Typography.Font
	dRarityBadge.TextSize = 10
	dRarityBadge.TextXAlignment = Enum.TextXAlignment.Left
	dRarityBadge.Text = "[SELTEN]  •  Nahkampfwaffe"
	dRarityBadge.ZIndex = 28
	dRarityBadge.Parent = dInfoBox
	addCheckUIStroke(dRarityBadge, 1.8)
	detailRarityBadge = dRarityBadge

	-- Werte-Box (Detailed Stats)
	local dStatsBox = Instance.new("Frame")
	dStatsBox.Name = "StatsBox"
	dStatsBox.Size = UDim2.new(1, -28, 0, 34)
	dStatsBox.Position = UDim2.new(0, 14, 0, 126)
	dStatsBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	dStatsBox.BorderSizePixel = 0
	dStatsBox.ZIndex = 27
	dStatsBox.Parent = detailFrame

	local dStatsCorner = Instance.new("UICorner")
	dStatsCorner.CornerRadius = UDim.new(0, 4)
	dStatsCorner.Parent = dStatsBox

	local dStatsStroke = Instance.new("UIStroke")
	dStatsStroke.Color = CheckUITheme.Colors.RequirementsHighlight
	dStatsStroke.Thickness = 1.2
	dStatsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dStatsStroke.Parent = dStatsBox

	local dStatsText = Instance.new("TextLabel")
	dStatsText.Name = "StatsText"
	dStatsText.Size = UDim2.new(1, -16, 1, 0)
	dStatsText.Position = UDim2.new(0, 8, 0, 0)
	dStatsText.BackgroundTransparency = 1
	dStatsText.TextColor3 = Color3.fromRGB(46, 204, 113)
	dStatsText.Font = CheckUITheme.Typography.Font
	dStatsText.TextSize = 11
	dStatsText.TextXAlignment = Enum.TextXAlignment.Left
	dStatsText.Text = "25 HP Schaden  •  0.35s Cooldown"
	dStatsText.ZIndex = 28
	dStatsText.Parent = dStatsBox
	addCheckUIStroke(dStatsText, 2.0)
	detailStatsLabel = dStatsText

	-- Beschreibungs-Box (Fließtext)
	local dDescBox = Instance.new("Frame")
	dDescBox.Name = "DescBox"
	dDescBox.Size = UDim2.new(1, -28, 0, 78)
	dDescBox.Position = UDim2.new(0, 14, 0, 166)
	dDescBox.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	dDescBox.BorderSizePixel = 0
	dDescBox.ZIndex = 27
	dDescBox.Parent = detailFrame

	local dDescCorner = Instance.new("UICorner")
	dDescCorner.CornerRadius = UDim.new(0, 4)
	dDescCorner.Parent = dDescBox

	local dDescStroke = Instance.new("UIStroke")
	dDescStroke.Color = Color3.fromRGB(0, 0, 0)
	dDescStroke.Thickness = 1.6
	dDescStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dDescStroke.Parent = dDescBox

	local dDescText = Instance.new("TextLabel")
	dDescText.Name = "DescText"
	dDescText.Size = UDim2.new(1, -16, 1, -10)
	dDescText.Position = UDim2.new(0, 8, 0, 5)
	dDescText.BackgroundTransparency = 1
	dDescText.TextColor3 = Color3.fromRGB(210, 220, 235)
	dDescText.Font = CheckUITheme.Typography.Font
	dDescText.TextSize = 10
	dDescText.TextXAlignment = Enum.TextXAlignment.Left
	dDescText.TextYAlignment = Enum.TextYAlignment.Top
	dDescText.TextWrapped = true
	dDescText.Text = "Vollständige Beschreibung..."
	dDescText.ZIndex = 28
	dDescText.Parent = dDescBox
	addCheckUIStroke(dDescText, 1.6)
	detailDescLabel = dDescText

	-- Tipp-Box (Nutzungshinweis)
	local dTipBox = Instance.new("Frame")
	dTipBox.Name = "TipBox"
	dTipBox.Size = UDim2.new(1, -28, 0, 42)
	dTipBox.Position = UDim2.new(0, 14, 0, 250)
	dTipBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
	dTipBox.BorderSizePixel = 0
	dTipBox.ZIndex = 27
	dTipBox.Parent = detailFrame

	local dTipCorner = Instance.new("UICorner")
	dTipCorner.CornerRadius = UDim.new(0, 4)
	dTipCorner.Parent = dTipBox

	local dTipStroke = Instance.new("UIStroke")
	dTipStroke.Color = CheckUITheme.Colors.RequirementsHighlight
	dTipStroke.Thickness = 1.2
	dTipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dTipStroke.Parent = dTipBox

	local dTipText = Instance.new("TextLabel")
	dTipText.Name = "TipText"
	dTipText.Size = UDim2.new(1, -16, 1, -6)
	dTipText.Position = UDim2.new(0, 8, 0, 3)
	dTipText.BackgroundTransparency = 1
	dTipText.TextColor3 = Color3.fromRGB(140, 195, 255)
	dTipText.Font = CheckUITheme.Typography.Font
	dTipText.TextSize = 10
	dTipText.TextXAlignment = Enum.TextXAlignment.Left
	dTipText.TextYAlignment = Enum.TextYAlignment.Center
	dTipText.TextWrapped = true
	dTipText.Text = "💡 Tipp..."
	dTipText.ZIndex = 28
	dTipText.Parent = dTipBox
	addCheckUIStroke(dTipText, 1.8)
	detailTipLabel = dTipText

	-- Schließen-Button nach Studio-Verified Blueprint (Check-UI Tenet 11)
	local dBottomClose = Instance.new("ImageButton")
	dBottomClose.Name = "BottomCloseBtn"
	dBottomClose.Size = UDim2.new(1, -28, 0, 38)
	dBottomClose.Position = UDim2.new(0, 14, 0, 300)
	dBottomClose.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dBottomClose.BorderSizePixel = 0
	dBottomClose.AutoButtonColor = false
	dBottomClose.ClipsDescendants = true
	dBottomClose.ZIndex = 27
	dBottomClose.Parent = detailFrame

	local bCornerClose = Instance.new("UICorner")
	bCornerClose.CornerRadius = UDim.new(0, 4)
	bCornerClose.Parent = dBottomClose

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color = Color3.fromRGB(12, 20, 26)
	closeBtnStroke.Thickness = 2.8
	closeBtnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeBtnStroke.Parent = dBottomClose

	local closeBtnGrad = Instance.new("UIGradient")
	closeBtnGrad.Rotation = 90
	closeBtnGrad.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(216, 222, 228)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(148, 160, 176)),
	}
	closeBtnGrad.Parent = dBottomClose

	local closeBtnBevel = Instance.new("Frame")
	closeBtnBevel.Name = "Bevel"
	closeBtnBevel.Size = UDim2.new(1, 0, 0, 3)
	closeBtnBevel.Position = UDim2.new(0, 0, 1, -3)
	closeBtnBevel.BackgroundColor3 = Color3.fromRGB(72, 82, 96)
	closeBtnBevel.BorderSizePixel = 0
	closeBtnBevel.ZIndex = 28
	closeBtnBevel.Parent = dBottomClose

	local closeBtnLabel = Instance.new("TextLabel")
	closeBtnLabel.Name = "Label"
	closeBtnLabel.Size = UDim2.new(1, 0, 1, 0)
	closeBtnLabel.BackgroundTransparency = 1
	closeBtnLabel.Text = "SCHLIESSEN  [X]"
	closeBtnLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtnLabel.Font = CheckUITheme.Typography.Font
	closeBtnLabel.TextSize = 13
	closeBtnLabel.ZIndex = 29
	closeBtnLabel.Parent = dBottomClose
	addCheckUIStroke(closeBtnLabel, 2.6)

	local closeBtnScale = Instance.new("UIScale")
	closeBtnScale.Name = "ButtonScale"
	closeBtnScale.Scale = 1
	closeBtnScale.Parent = dBottomClose

	CheckUIController.bindButtonAnimations(dBottomClose, closeBtnScale, 1.03, 0.96)

	dBottomClose.MouseButton1Click:Connect(function()
		HUDController.CloseItemDetails()
	end)

	-- ----------------------------------------------------
	-- 7. TOAST-BENACHRICHTIGUNGEN (Oben zentriert)
	-- ----------------------------------------------------
	local toast = Instance.new("Frame")
	toast.Name = "ToastBanner"
	toast.Size = UDim2.new(0, 380, 0, 44)
	toast.Position = UDim2.new(0.5, 0, 0, 68)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	toast.BackgroundTransparency = 1
	toast.Visible = false
	toast.ZIndex = 20
	toast.Parent = gui
	toastFrame = toast

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 4)
	tCorner.Parent = toast

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(12, 20, 26)
	tStroke.Thickness = 2.4
	tStroke.Transparency = 1
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tStroke.Parent = toast
	toastStroke = tStroke

	local tIcon = Instance.new("TextLabel")
	tIcon.Name = "Icon"
	tIcon.Size = UDim2.new(0, 36, 1, 0)
	tIcon.Position = UDim2.new(0, 6, 0, 0)
	tIcon.BackgroundTransparency = 1
	tIcon.Text = "✅"
	tIcon.TextSize = 20
	tIcon.TextTransparency = 1
	tIcon.Font = CheckUITheme.Typography.Font
	tIcon.ZIndex = 21
	tIcon.Parent = toast
	toastIcon = tIcon

	local tLabel = Instance.new("TextLabel")
	tLabel.Name = "Message"
	tLabel.Size = UDim2.new(1, -50, 1, 0)
	tLabel.Position = UDim2.new(0, 44, 0, 0)
	tLabel.BackgroundTransparency = 1
	tLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	tLabel.Font = CheckUITheme.Typography.Font
	tLabel.TextSize = 12
	tLabel.TextXAlignment = Enum.TextXAlignment.Left
	tLabel.TextTransparency = 1
	tLabel.Text = ""
	tLabel.ZIndex = 21
	tLabel.Parent = toast
	addCheckUIStroke(tLabel, 2.0)
	toastText = tLabel

	-- Standard-Roblox Health CoreGui deaktivieren
	task.spawn(function()
		for _ = 1, 8 do
			local success = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
			if success then
				break
			end
			task.wait(0.5)
		end
	end)
end

-- ==========================================
-- AKTIONEN & UPDATE-HANDLER
-- ==========================================

-- Aktualisiert die Lebensanzeige des Spielers
function HUDController.UpdatePlayerHealth(health: number, maxHealth: number)
	if not healthFillBar or not healthTextLabel then
		return
	end

	local currentHealth = math.clamp(health, 0, maxHealth)
	local pct = if maxHealth > 0 then math.clamp(currentHealth / maxHealth, 0, 1) else 0

	healthTextLabel.Text = string.format("%d / %d HP", math.max(0, math.floor(currentHealth)), maxHealth)

	-- Vordergrundbalken sofort flüssig anpassen
	TweenService:Create(healthFillBar, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(pct, 0, 1, 0),
	}):Play()

	-- Dynamische Farbkodierung (Grün -> Gelb -> Rot)
	if pct > 0.5 then
		healthFillBar.BackgroundColor3 = Color3.fromRGB(105, 225, 0)
	elseif pct > 0.25 then
		healthFillBar.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
	else
		healthFillBar.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	end

	-- Roter Trail-Balken mit leichter Verzögerung hinterherziehen
	task.delay(0.22, function()
		if damageTrailBar then
			TweenService:Create(damageTrailBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(pct, 0, 1, 0),
			}):Play()
		end
	end)

	-- Kritische Lebenspunkte Pulse-Effekt (< 25% HP)
	if healthCardStroke then
		if pct <= 0.25 and currentHealth > 0 then
			healthCardStroke.Color = Color3.fromRGB(231, 76, 60)
			healthCardStroke.Thickness = 3.2
		else
			healthCardStroke.Color = Color3.fromRGB(12, 20, 26)
			healthCardStroke.Thickness = 2.8
		end
	end
end

-- Bindet Humanoid-Health-Events an
local function hookHumanoidHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	HUDController.UpdatePlayerHealth(humanoid.Health, humanoid.MaxHealth)

	humanoid.HealthChanged:Connect(function(newHealth: number)
		HUDController.UpdatePlayerHealth(newHealth, humanoid.MaxHealth)
	end)

	humanoid.Died:Connect(function()
		HUDController.UpdatePlayerHealth(0, humanoid.MaxHealth)
	end)
end

-- Aktualisiert den Boss-Lebensbalken
function HUDController.UpdateBossBar(name: string, health: number, maxHealth: number, isAlive: boolean)
	if not bossBarContainer or not bossBarFill or not bossTitleLabel then
		return
	end

	if isAlive and health > 0 then
		bossBarContainer.Visible = true
		local pct = math.clamp(health / maxHealth, 0, 1)
		TweenService:Create(bossBarFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(pct, 0, 1, 0) }):Play()
		bossTitleLabel.Text = string.format("👹 %s: %d / %d HP", name, math.max(0, math.floor(health)), maxHealth)
	else
		bossTitleLabel.Text = string.format("💀 %s: Besiegt!", name)
		task.delay(2.5, function()
			if bossBarContainer then
				bossBarContainer.Visible = false
			end
		end)
	end
end

-- Aktualisiert die angezeigte Dimension
function HUDController.SetDimension(dimensionName: string)
	currentDimensionName = dimensionName
	if playerDimLabel then
		playerDimLabel.Text = string.format("📍 %s", dimensionName)
	end
end

-- Zeigt Toast-Benachrichtigung an
function HUDController.ShowNotification(message: string, isError: boolean?)
	if not toastFrame or not toastText or not toastIcon or not toastStroke then
		return
	end

	if currentToastThread then
		task.cancel(currentToastThread)
		currentToastThread = nil
	end

	local accentColor = if isError then Color3.fromRGB(231, 76, 60) else Color3.fromRGB(105, 225, 0)
	local iconText = if isError then "⚠️" else "✅"

	toastText.Text = message
	toastIcon.Text = iconText
	toastStroke.Color = accentColor
	toastFrame.Visible = true

	TweenService:Create(toastFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(toastStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
	TweenService:Create(toastText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	TweenService:Create(toastIcon, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

	currentToastThread = task.delay(3.2, function()
		if not toastFrame or not toastText or not toastIcon or not toastStroke then
			return
		end
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

-- Aktualisiert den Gold- und CPS-Stand mit angenehmer Pop-Animation
function HUDController.UpdateGold(newGold: number, currentCPS: number?)
	cachedGold = newGold
	if currentCPS ~= nil then
		cachedCPS = currentCPS
	end

	if goldAmountLabel then
		goldAmountLabel.Text = formatNumber(newGold)
	end

	if cpsLabel and currentCPS ~= nil then
		cpsLabel.Text = string.format("+%s /s", formatNumber(currentCPS))
	end

	-- Dezente Pop-Animation für Gold-Card
	if goldCardFrame then
		local grow = TweenService:Create(
			goldCardFrame,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 244, 0, 52) }
		)
		local reset = TweenService:Create(
			goldCardFrame,
			TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 240, 0, 50) }
		)
		grow:Play()
		grow.Completed:Connect(function()
			reset:Play()
		end)
	end
end

-- Aktualisiert das Inventar
function HUDController.UpdateInventory(inventory: InventoryData)
	cachedInventory = inventory
	updateInventoryBadge()
	if isInventoryOpen then
		rebuildInventoryList()
	end
end

-- ==========================================
-- INITIALISIERUNG
-- ==========================================

function HUDController.Init()
	createHUD()

	-- Spieler-Charakter und Lebensbalken initial binden
	if LocalPlayer.Character then
		task.spawn(hookHumanoidHealth, LocalPlayer.Character)
	end
	LocalPlayer.CharacterAdded:Connect(hookHumanoidHealth)

	-- Multi-Device Responsive Scaling Engine (Check-UI Tenet 8)
	if Camera then
		Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateDeviceScales)
	end

	-- Eingabe-Art initial prüfen & dynamisch umschalten (PC vs. Controller)
	updateHotkeyLabel(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(updateHotkeyLabel)

	-- ProximityPrompt Schutz: Verhindert versehentliches Öffnen während Interaktionen
	ProximityPromptService.PromptButtonHoldBegan:Connect(function()
		isHoldingPrompt = true
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function()
		task.delay(0.12, function()
			isHoldingPrompt = false
		end)
	end)
	ProximityPromptService.PromptTriggered:Connect(function()
		task.delay(0.12, function()
			isHoldingPrompt = false
		end)
	end)

	-- Tastenkombinationen für PC (E, Tab, B, I) und Konsole / Gamepad (ButtonY, DPadUp, ButtonSelect)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		local code = input.KeyCode

		-- PC: [E] (Minecraft-Style / RPG-Standard), [Tab], [B], [I]
		local isPCInventoryKey = (code == Enum.KeyCode.E or code == Enum.KeyCode.Tab or code == Enum.KeyCode.B or code == Enum.KeyCode.I)

		-- Konsole / Gamepad: [ButtonY], [ButtonSelect], [DPadUp]
		local isConsoleInventoryKey = (code == Enum.KeyCode.ButtonY or code == Enum.KeyCode.ButtonSelect or code == Enum.KeyCode.DPadUp)

		if isPCInventoryKey or isConsoleInventoryKey then
			if isHoldingPrompt then
				return
			end
			HUDController.ToggleInventory()
			return
		end

		-- Wenn das Inventar geöffnet ist:
		if isInventoryOpen then
			-- Wenn Item-Detail-Infobox offen ist, schließe zuerst diese
			if isDetailOpen then
				if code == Enum.KeyCode.Escape or code == Enum.KeyCode.ButtonB or code == Enum.KeyCode.ButtonX then
					HUDController.CloseItemDetails()
					return
				end
			end

			-- Controller Tab-Wechsel mit LB/RB bzw. L1/R1
			if code == Enum.KeyCode.ButtonL1 then
				switchCategoryTab(-1)
				return
			elseif code == Enum.KeyCode.ButtonR1 then
				switchCategoryTab(1)
				return
			end

			-- Schließen mit Escape (PC) oder ButtonB (Xbox B / PlayStation Kreis)
			if code == Enum.KeyCode.Escape or code == Enum.KeyCode.ButtonB then
				HUDController.CloseInventory()
				return
			end
		end
	end)

	-- Server-Events verbinden
	GoldUpdated.OnClientEvent:Connect(function(newGold: number, currentCPS: number?)
		HUDController.UpdateGold(newGold, currentCPS)
	end)

	InventoryUpdated.OnClientEvent:Connect(function(inventory: InventoryData)
		HUDController.UpdateInventory(inventory)
	end)

	NotificationEvent.OnClientEvent:Connect(function(message: string, isError: boolean?)
		HUDController.ShowNotification(message, isError)
	end)

	DimensionChanged.OnClientEvent:Connect(function(name: string)
		HUDController.SetDimension(name)
	end)

	BossUpdated.OnClientEvent:Connect(function(name: string, health: number, maxHealth: number, isAlive: boolean)
		HUDController.UpdateBossBar(name, health, maxHealth, isAlive)
	end)

	-- Initialen Inventar-Sync vom Server anfordern
	task.defer(function()
		RequestInventory:FireServer()
	end)

	print("[HUDController] Initialisiert: Check-UI Design System HUD, GothamBlack Typografie & Responsive Engine aktiv.")
end

return HUDController
