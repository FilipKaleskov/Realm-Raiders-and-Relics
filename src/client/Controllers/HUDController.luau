--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = Shared:WaitForChild("Events")
local ConfigFolder = Shared:WaitForChild("Config")
local DataFolder = Shared:WaitForChild("Data")

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

-- Erstellt eine Item-Karte im Inventar-Grid
local function createItemCard(parent: Instance, itemId: string, count: number, customCategory: string?)
	local itemInfo = ItemConfig[itemId]
	local displayName = if itemInfo then itemInfo.DisplayName else itemId
	local icon = if itemInfo then itemInfo.Icon else "📦"
	local statsText = if itemInfo then itemInfo.StatsText else ""
	local desc = if itemInfo then itemInfo.Description else ""
	local rarityColor = if itemInfo then itemInfo.RarityColor else Color3.fromRGB(189, 195, 199)

	local card = Instance.new("Frame")
	card.Name = "Item_" .. itemId
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(28, 33, 46)
	card.BackgroundTransparency = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local cardStrokeColor = if rarityColor == Color3.fromRGB(189, 195, 199) then Color3.fromRGB(115, 128, 155) else rarityColor
	local stroke = Instance.new("UIStroke")
	stroke.Color = cardStrokeColor
	stroke.Thickness = 1.6
	stroke.Transparency = 0.08
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	local cardGrad = Instance.new("UIGradient")
	cardGrad.Color = ColorSequence.new(Color3.fromRGB(36, 42, 58), Color3.fromRGB(24, 28, 40))
	cardGrad.Rotation = 90
	cardGrad.Parent = card

	-- Icon-Container
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.Size = UDim2.new(0, 52, 0, 52)
	iconBox.Position = UDim2.new(0, 10, 0.5, -26)
	iconBox.BackgroundColor3 = Color3.fromRGB(18, 21, 30)
	iconBox.BackgroundTransparency = 0
	iconBox.Parent = card

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = iconBox

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(50, 60, 80)
	iconStroke.Thickness = 1
	iconStroke.Transparency = 0.2
	iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iconStroke.Parent = iconBox

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextSize = 28
	iconLabel.Parent = iconBox

	-- Name des Gegenstands
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, -74, 0, 20)
	nameLabel.Position = UDim2.new(0, 68, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = displayName
	nameLabel.Parent = card

	-- Stats / Kategorie Badge
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "Stats"
	statsLabel.Size = UDim2.new(1, -74, 0, 16)
	statsLabel.Position = UDim2.new(0, 68, 0, 31)
	statsLabel.BackgroundTransparency = 1
	statsLabel.TextColor3 = cardStrokeColor
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 11
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Text = statsText
	statsLabel.Parent = card

	-- Beschreibung / Hinweis
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Desc"
	descLabel.Size = UDim2.new(1, -74, 0, 16)
	descLabel.Position = UDim2.new(0, 68, 0, 49)
	descLabel.BackgroundTransparency = 1
	descLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 10
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Text = desc
	descLabel.Parent = card

	-- Mengenschild (wenn Anzahl > 1)
	if count > 1 then
		local countPill = Instance.new("Frame")
		countPill.Name = "CountPill"
		countPill.Size = UDim2.new(0, 26, 0, 18)
		countPill.Position = UDim2.new(1, -32, 0, 6)
		countPill.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
		countPill.BackgroundTransparency = 0.2
		countPill.Parent = card

		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(0, 6)
		pillCorner.Parent = countPill

		local pillText = Instance.new("TextLabel")
		pillText.Size = UDim2.new(1, 0, 1, 0)
		pillText.BackgroundTransparency = 1
		pillText.TextColor3 = Color3.fromRGB(255, 255, 255)
		pillText.Font = Enum.Font.GothamBold
		pillText.TextSize = 10
		pillText.Text = "x" .. tostring(count)
		pillText.Parent = countPill
	end

	-- Hover-Animation
	local hoverDetector = Instance.new("TextButton")
	hoverDetector.Name = "HoverDetector"
	hoverDetector.Size = UDim2.new(1, 0, 1, 0)
	hoverDetector.BackgroundTransparency = 1
	hoverDetector.Text = ""
	hoverDetector.Parent = card

	hoverDetector.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(38, 46, 64),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0,
			Thickness = 2.0,
		}):Play()
	end)

	hoverDetector.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(28, 33, 46),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.08,
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
		local weaponCounts: { [string]: number } = {}
		for _, wId in cachedInventory.Weapons do
			weaponCounts[wId] = (weaponCounts[wId] or 0) + 1
		end
		for wId, count in pairs(weaponCounts) do
			createItemCard(invGridFrame, wId, count, "Weapon")
			itemCount += 1
		end
	end

	-- 2. Seelenkerne
	if currentCategory == "All" or currentCategory == "Cores" then
		local coreCounts: { [string]: number } = {}
		for _, cId in cachedInventory.Cores do
			coreCounts[cId] = (coreCounts[cId] or 0) + 1
		end
		for cId, count in pairs(coreCounts) do
			createItemCard(invGridFrame, cId, count, "Core")
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

-- Aktualisiert die Tab-Optik
local function setCategory(category: string)
	currentCategory = category
	for tabCat, btn in pairs(invCategoryTabs) do
		local isActive = (tabCat == category)
		local targetBg = if isActive then Color3.fromRGB(52, 73, 94) else Color3.fromRGB(24, 27, 36)
		local targetText = if isActive then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(150, 155, 170)
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
		BackgroundColor3 = Color3.fromRGB(60, 75, 105),
	})
	local reset = TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundColor3 = Color3.fromRGB(30, 35, 48),
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

-- Öffnet das Inventar mit flüssiger Animation
function HUDController.OpenInventory()
	if not invModalFrame or not invBackdrop or isInventoryOpen then
		return
	end
	isInventoryOpen = true

	rebuildInventoryList()
	updateInventoryBadge()

	invBackdrop.Visible = true
	invModalFrame.Visible = true

	invModalFrame.Size = UDim2.new(0, 480, 0, 390)
	invModalFrame.Position = UDim2.new(0.5, -240, 0.5, -195)
	invModalFrame.BackgroundTransparency = 0.5

	TweenService:Create(invModalFrame, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 510, 0, 420),
		Position = UDim2.new(0.5, -255, 0.5, -210),
		BackgroundTransparency = 0.08,
	}):Play()
end

-- Schließt das Inventar
function HUDController.CloseInventory()
	if not invModalFrame or not invBackdrop or not isInventoryOpen then
		return
	end
	isInventoryOpen = false
	HUDController.CloseItemDetails()

	local closeTween = TweenService:Create(invModalFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 470, 0, 380),
		Position = UDim2.new(0.5, -235, 0.5, -190),
		BackgroundTransparency = 1,
	})
	closeTween:Play()
	closeTween.Completed:Connect(function()
		if not isInventoryOpen and invModalFrame and invBackdrop then
			invModalFrame.Visible = false
			invBackdrop.Visible = false
		end
	end)
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
	itemDetailModal.Size = UDim2.new(0, 330, 0, 280)
	itemDetailModal.Position = UDim2.new(0.5, -165, 0.5, -140)
	itemDetailModal.BackgroundTransparency = 0.3

	TweenService:Create(itemDetailModal, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 350, 0, 305),
		Position = UDim2.new(0.5, -175, 0.5, -152),
		BackgroundTransparency = 0.05,
	}):Play()
end

-- Schließt die Infobox
function HUDController.CloseItemDetails()
	if not itemDetailModal or not isDetailOpen then
		return
	end
	isDetailOpen = false

	local closeTween = TweenService:Create(itemDetailModal, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 330, 0, 280),
		Position = UDim2.new(0.5, -165, 0.5, -140),
		BackgroundTransparency = 1,
	})
	closeTween:Play()
	closeTween.Completed:Connect(function()
		if not isDetailOpen and itemDetailModal then
			itemDetailModal.Visible = false
		end
	end)
end

-- Schaltet das Inventar um (Toggle)
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
	bossFrame.Size = UDim2.new(0, 360, 0, 38)
	bossFrame.Position = UDim2.new(0.5, -180, 0, 15)
	bossFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	bossFrame.BackgroundTransparency = 0.2
	bossFrame.Visible = false
	bossFrame.Parent = gui
	bossBarContainer = bossFrame

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 8)
	bCorner.Parent = bossFrame

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(231, 76, 60)
	bStroke.Thickness = 1.4
	bStroke.Parent = bossFrame

	local bFill = Instance.new("Frame")
	bFill.Name = "Fill"
	bFill.Size = UDim2.new(1, 0, 1, 0)
	bFill.BackgroundColor3 = Color3.fromRGB(192, 57, 43)
	bFill.BorderSizePixel = 0
	bFill.Parent = bossFrame
	bossBarFill = bFill

	local bFillCorner = Instance.new("UICorner")
	bFillCorner.CornerRadius = UDim.new(0, 8)
	bFillCorner.Parent = bFill

	local bTitle = Instance.new("TextLabel")
	bTitle.Name = "BossTitle"
	bTitle.Size = UDim2.new(1, 0, 1, 0)
	bTitle.BackgroundTransparency = 1
	bTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	bTitle.Font = Enum.Font.GothamBold
	bTitle.TextSize = 13
	bTitle.Text = "👹 Wald-Golem: 300 / 300 HP"
	bTitle.Parent = bossFrame
	bossTitleLabel = bTitle

	-- ----------------------------------------------------
	-- 2. GELD & CPS KACHEL (Oben rechts, kompakt & nach oben versetzt)
	-- ----------------------------------------------------
	local goldCard = Instance.new("Frame")
	goldCard.Name = "GoldCard"
	goldCard.Size = UDim2.new(0, 236, 0, 48)
	goldCard.Position = UDim2.new(1, -258, 0, 8)
	goldCard.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	goldCard.BackgroundTransparency = 0.15
	goldCard.Parent = gui
	goldCardFrame = goldCard

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = goldCard

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(241, 196, 15)
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.35
	cardStroke.Parent = goldCard

	-- Münzen Icon Badge (goldener Coin-Emblem)
	local coinBadge = Instance.new("Frame")
	coinBadge.Name = "CoinBadge"
	coinBadge.Size = UDim2.new(0, 32, 0, 32)
	coinBadge.Position = UDim2.new(0, 8, 0.5, -16)
	coinBadge.BackgroundColor3 = Color3.fromRGB(243, 156, 18)
	coinBadge.BackgroundTransparency = 0.1
	coinBadge.Parent = goldCard

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(1, 0)
	coinCorner.Parent = coinBadge

	local coinStroke = Instance.new("UIStroke")
	coinStroke.Color = Color3.fromRGB(255, 215, 0)
	coinStroke.Thickness = 1.5
	coinStroke.Parent = coinBadge

	local coinGrad = Instance.new("UIGradient")
	coinGrad.Color = ColorSequence.new(Color3.fromRGB(255, 225, 60), Color3.fromRGB(215, 135, 10))
	coinGrad.Rotation = 45
	coinGrad.Parent = coinBadge

	local coinIcon = Instance.new("TextLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.new(1, 0, 1, 0)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Text = "G"
	coinIcon.TextColor3 = Color3.fromRGB(255, 255, 235)
	coinIcon.Font = Enum.Font.GothamBlack
	coinIcon.TextSize = 16
	coinIcon.Parent = coinBadge
	goldCoinIcon = coinIcon

	-- Titel "SEELEN-GOLD"
	local goldHeader = Instance.new("TextLabel")
	goldHeader.Name = "Header"
	goldHeader.Size = UDim2.new(0, 90, 0, 13)
	goldHeader.Position = UDim2.new(0, 48, 0, 6)
	goldHeader.BackgroundTransparency = 1
	goldHeader.TextColor3 = Color3.fromRGB(150, 155, 170)
	goldHeader.Font = Enum.Font.GothamBold
	goldHeader.TextSize = 10
	goldHeader.TextXAlignment = Enum.TextXAlignment.Left
	goldHeader.Text = "SEELEN-GOLD"
	goldHeader.Parent = goldCard

	-- Gold-Zahl
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldAmount"
	goldLabel.Size = UDim2.new(0, 105, 0, 22)
	goldLabel.Position = UDim2.new(0, 48, 0, 18)
	goldLabel.BackgroundTransparency = 1
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	goldLabel.Font = Enum.Font.GothamBlack
	goldLabel.TextSize = 17
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Text = "0"
	goldLabel.Parent = goldCard
	goldAmountLabel = goldLabel

	-- CPS Badge
	local cpsBadge = Instance.new("Frame")
	cpsBadge.Name = "CPSBadge"
	cpsBadge.Size = UDim2.new(0, 64, 0, 24)
	cpsBadge.Position = UDim2.new(1, -74, 0.5, -12)
	cpsBadge.BackgroundColor3 = Color3.fromRGB(39, 174, 96)
	cpsBadge.BackgroundTransparency = 0.2
	cpsBadge.Parent = goldCard

	local cpsCorner = Instance.new("UICorner")
	cpsCorner.CornerRadius = UDim.new(0, 7)
	cpsCorner.Parent = cpsBadge

	local cpsText = Instance.new("TextLabel")
	cpsText.Name = "CPSText"
	cpsText.Size = UDim2.new(1, 0, 1, 0)
	cpsText.BackgroundTransparency = 1
	cpsText.TextColor3 = Color3.fromRGB(255, 255, 255)
	cpsText.Font = Enum.Font.GothamBold
	cpsText.TextSize = 12
	cpsText.Text = "+0 /s"
	cpsText.Parent = cpsBadge
	cpsLabel = cpsText

	-- ----------------------------------------------------
	-- 3. INVENTAR-BUTTON (Kompakt direkt unter GoldCard, 6px Abstand)
	-- ----------------------------------------------------
	local invBtn = Instance.new("TextButton")
	invBtn.Name = "InventoryButton"
	invBtn.Size = UDim2.new(0, 236, 0, 30)
	invBtn.Position = UDim2.new(1, -258, 0, 62)
	invBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
	invBtn.BackgroundTransparency = 0.2
	invBtn.Text = ""
	invBtn.Parent = gui
	invButtonFrame = invBtn

	local invBtnCorner = Instance.new("UICorner")
	invBtnCorner.CornerRadius = UDim.new(0, 8)
	invBtnCorner.Parent = invBtn

	local invBtnStroke = Instance.new("UIStroke")
	invBtnStroke.Color = Color3.fromRGB(60, 65, 80)
	invBtnStroke.Thickness = 1.2
	invBtnStroke.Transparency = 0.4
	invBtnStroke.Parent = invBtn

	local btnTitle = Instance.new("TextLabel")
	btnTitle.Size = UDim2.new(0, 155, 1, 0)
	btnTitle.Position = UDim2.new(0, 14, 0, 0)
	btnTitle.BackgroundTransparency = 1
	btnTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
	btnTitle.Font = Enum.Font.GothamBold
	btnTitle.TextSize = 12
	btnTitle.TextXAlignment = Enum.TextXAlignment.Left
	btnTitle.Text = "Inventar  [E]"
	btnTitle.Parent = invBtn
	invBtnTitleLabel = btnTitle

	local badgePill = Instance.new("Frame")
	badgePill.Name = "BadgePill"
	badgePill.Size = UDim2.new(0, 28, 0, 18)
	badgePill.Position = UDim2.new(1, -34, 0.5, -9)
	badgePill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	badgePill.BackgroundTransparency = 0.15
	badgePill.Parent = invBtn

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = badgePill

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Size = UDim2.new(1, 0, 1, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.TextSize = 11
	badgeLabel.Text = "0"
	badgeLabel.Parent = badgePill
	invBadgeLabel = badgeLabel

	-- Hover & Click für Inventar-Button
	invBtn.MouseEnter:Connect(function()
		TweenService:Create(invBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(32, 36, 48),
		}):Play()
		TweenService:Create(invBtnStroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Color = Color3.fromRGB(116, 185, 255),
			Transparency = 0.2,
		}):Play()
	end)

	invBtn.MouseLeave:Connect(function()
		TweenService:Create(invBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(22, 25, 33),
		}):Play()
		TweenService:Create(invBtnStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Color = Color3.fromRGB(60, 65, 80),
			Transparency = 0.4,
		}):Play()
	end)

	invBtn.MouseButton1Click:Connect(function()
		HUDController.ToggleInventory()
	end)

	-- ----------------------------------------------------
	-- 4. SPIELER-LEBENSANZEIGE & BASIS-INFO (Unten links)
	-- ----------------------------------------------------
	local hpCard = Instance.new("Frame")
	hpCard.Name = "PlayerHealthCard"
	hpCard.Size = UDim2.new(0, 270, 0, 72)
	hpCard.Position = UDim2.new(0, 24, 1, -96)
	hpCard.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	hpCard.BackgroundTransparency = 0.15
	hpCard.Parent = gui
	healthCardFrame = hpCard

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 12)
	hpCorner.Parent = hpCard

	local hpStroke = Instance.new("UIStroke")
	hpStroke.Color = Color3.fromRGB(50, 56, 70)
	hpStroke.Thickness = 1.3
	hpStroke.Transparency = 0.3
	hpStroke.Parent = hpCard
	healthCardStroke = hpStroke

	-- Avatar / Profil Icon
	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "AvatarFrame"
	avatarFrame.Size = UDim2.new(0, 48, 0, 48)
	avatarFrame.Position = UDim2.new(0, 12, 0.5, -24)
	avatarFrame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	avatarFrame.BackgroundTransparency = 0.2
	avatarFrame.Parent = hpCard

	local avCorner = Instance.new("UICorner")
	avCorner.CornerRadius = UDim.new(1, 0)
	avCorner.Parent = avatarFrame

	local avStroke = Instance.new("UIStroke")
	avStroke.Color = Color3.fromRGB(46, 204, 113)
	avStroke.Thickness = 1.5
	avStroke.Parent = avatarFrame

	local avImg = Instance.new("ImageLabel")
	avImg.Name = "AvatarImage"
	avImg.Size = UDim2.new(1, 0, 1, 0)
	avImg.BackgroundTransparency = 1
	avImg.Visible = false
	avImg.Parent = avatarFrame
	avatarImageLabel = avImg

	local avImgCorner = Instance.new("UICorner")
	avImgCorner.CornerRadius = UDim.new(1, 0)
	avImgCorner.Parent = avImg

	local avFallback = Instance.new("TextLabel")
	avFallback.Name = "FallbackIcon"
	avFallback.Size = UDim2.new(1, 0, 1, 0)
	avFallback.BackgroundTransparency = 1
	avFallback.Text = "❤️"
	avFallback.TextSize = 24
	avFallback.Parent = avatarFrame

	-- Spieler-Avatar Headshot asynchron laden
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

	-- Spieler-Name & Titel
	local pNameLabel = Instance.new("TextLabel")
	pNameLabel.Name = "PlayerName"
	pNameLabel.Size = UDim2.new(0, 110, 0, 16)
	pNameLabel.Position = UDim2.new(0, 68, 0, 9)
	pNameLabel.BackgroundTransparency = 1
	pNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pNameLabel.Font = Enum.Font.GothamBold
	pNameLabel.TextSize = 13
	pNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	pNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	pNameLabel.Text = LocalPlayer.DisplayName
	pNameLabel.Parent = hpCard

	-- Dimensions-Tag
	local dimTag = Instance.new("TextLabel")
	dimTag.Name = "DimensionTag"
	dimTag.Size = UDim2.new(0, 85, 0, 14)
	dimTag.Position = UDim2.new(1, -95, 0, 10)
	dimTag.BackgroundTransparency = 1
	dimTag.TextColor3 = Color3.fromRGB(116, 185, 255)
	dimTag.Font = Enum.Font.GothamMedium
	dimTag.TextSize = 10
	dimTag.TextXAlignment = Enum.TextXAlignment.Right
	dimTag.TextTruncate = Enum.TextTruncate.AtEnd
	dimTag.Text = "📍 " .. currentDimensionName
	dimTag.Parent = hpCard
	playerDimLabel = dimTag

	-- Lebensbalken Hintergrund
	local barBg = Instance.new("Frame")
	barBg.Name = "HealthBarBg"
	barBg.Size = UDim2.new(1, -80, 0, 18)
	barBg.Position = UDim2.new(0, 68, 0, 34)
	barBg.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
	barBg.BorderSizePixel = 0
	barBg.Parent = hpCard

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 6)
	barBgCorner.Parent = barBg

	-- Roter Schadens-Verzögerungsbalken (Damage Trail Effect)
	local damageBar = Instance.new("Frame")
	damageBar.Name = "DamageTrail"
	damageBar.Size = UDim2.new(1, 0, 1, 0)
	damageBar.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	damageBar.BorderSizePixel = 0
	damageBar.Parent = barBg
	damageTrailBar = damageBar

	local dmgCorner = Instance.new("UICorner")
	dmgCorner.CornerRadius = UDim.new(0, 6)
	dmgCorner.Parent = damageBar

	-- Grüner Vordergrund-Lebensbalken
	local fillBar = Instance.new("Frame")
	fillBar.Name = "HealthFill"
	fillBar.Size = UDim2.new(1, 0, 1, 0)
	fillBar.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	fillBar.BorderSizePixel = 0
	fillBar.Parent = barBg
	healthFillBar = fillBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fillBar

	-- HP-Zahlenanzeige
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 11
	hpText.Text = "100 / 100 HP"
	hpText.Parent = barBg
	healthTextLabel = hpText

	-- ----------------------------------------------------
	-- 5. INVENTAR MODAL / LISTE (Zentriertes Fenster)
	-- ----------------------------------------------------
	-- Dunkler Klick-Hintergrund zum Schließen
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

	-- Haupt-Inventarfenster
	local modal = Instance.new("Frame")
	modal.Name = "InventoryModal"
	modal.Size = UDim2.new(0, 510, 0, 420)
	modal.Position = UDim2.new(0.5, -255, 0.5, -210)
	modal.BackgroundColor3 = Color3.fromRGB(16, 18, 25)
	modal.BackgroundTransparency = 0.08
	modal.Visible = false
	modal.ZIndex = 11
	modal.Parent = gui
	invModalFrame = modal

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 16)
	modalCorner.Parent = modal

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Color3.fromRGB(65, 75, 100)
	modalStroke.Thickness = 1.6
	modalStroke.Transparency = 0.3
	modalStroke.Parent = modal

	-- Kopfzeile
	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "Header"
	headerFrame.Size = UDim2.new(1, 0, 0, 48)
	headerFrame.BackgroundTransparency = 1
	headerFrame.ZIndex = 12
	headerFrame.Parent = modal

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Size = UDim2.new(0, 240, 1, 0)
	headerTitle.Position = UDim2.new(0, 20, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextSize = 15
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Text = "INVENTAR & RELIKTE"
	headerTitle.ZIndex = 12
	headerTitle.Parent = headerFrame

	-- Hotkey-Hinweis zum Schließen
	local closeHint = Instance.new("TextLabel")
	closeHint.Name = "CloseHint"
	closeHint.Size = UDim2.new(0, 120, 0, 20)
	closeHint.Position = UDim2.new(1, -170, 0.5, -10)
	closeHint.BackgroundTransparency = 1
	closeHint.TextColor3 = Color3.fromRGB(140, 145, 160)
	closeHint.Font = Enum.Font.GothamMedium
	closeHint.TextSize = 11
	closeHint.TextXAlignment = Enum.TextXAlignment.Right
	closeHint.Text = "[E] Schließen"
	closeHint.ZIndex = 12
	closeHint.Parent = headerFrame
	invCloseHintLabel = closeHint

	-- Schließen Button [X]
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -44, 0.5, -16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
	closeBtn.BackgroundTransparency = 0.2
	closeBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 13
	closeBtn.Text = "X"
	closeBtn.ZIndex = 12
	closeBtn.Parent = headerFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(231, 76, 60),
			TextColor3 = Color3.fromRGB(255, 255, 255),
		}):Play()
	end)

	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(28, 32, 42),
			TextColor3 = Color3.fromRGB(200, 205, 220),
		}):Play()
	end)

	closeBtn.MouseButton1Click:Connect(function()
		HUDController.CloseInventory()
	end)

	-- Trennlinie
	local divLine = Instance.new("Frame")
	divLine.Size = UDim2.new(1, -36, 0, 1)
	divLine.Position = UDim2.new(0, 18, 0, 48)
	divLine.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	divLine.BorderSizePixel = 0
	divLine.ZIndex = 12
	divLine.Parent = modal

	-- Kategorie-Reiter (TabBar mit LB & RB Schultertasten-Steuerung)
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -36, 0, 32)
	tabBar.Position = UDim2.new(0, 18, 0, 56)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 12
	tabBar.Parent = modal

	-- LB Button (Linke Schultertaste)
	local lbBtn = Instance.new("TextButton")
	lbBtn.Name = "LB_Button"
	lbBtn.Size = UDim2.new(0, 34, 1, 0)
	lbBtn.Position = UDim2.new(0, 0, 0, 0)
	lbBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
	lbBtn.BackgroundTransparency = 0.2
	lbBtn.TextColor3 = Color3.fromRGB(180, 190, 215)
	lbBtn.Font = Enum.Font.GothamBold
	lbBtn.TextSize = 11
	lbBtn.Text = "LB"
	lbBtn.ZIndex = 12
	lbBtn.Parent = tabBar
	lbTabButton = lbBtn

	local lbCorner = Instance.new("UICorner")
	lbCorner.CornerRadius = UDim.new(0, 7)
	lbCorner.Parent = lbBtn

	local lbStroke = Instance.new("UIStroke")
	lbStroke.Color = Color3.fromRGB(55, 65, 85)
	lbStroke.Thickness = 1
	lbStroke.Transparency = 0.3
	lbStroke.Parent = lbBtn

	lbBtn.MouseButton1Click:Connect(function()
		switchCategoryTab(-1)
	end)

	-- Mittlerer Container für die 4 Tabs
	local tabsContainer = Instance.new("Frame")
	tabsContainer.Name = "TabsContainer"
	tabsContainer.Size = UDim2.new(1, -84, 1, 0)
	tabsContainer.Position = UDim2.new(0, 42, 0, 0)
	tabsContainer.BackgroundTransparency = 1
	tabsContainer.ZIndex = 12
	tabsContainer.Parent = tabBar

	local categories = {
		{ Id = "All", Label = "Alle" },
		{ Id = "Weapons", Label = "⚔️ Waffen" },
		{ Id = "Cores", Label = "🔮 Seelenkerne" },
		{ Id = "Materials", Label = "⛏️ Materialien" },
	}

	local totalTabWidth = 510 - 36 - 84
	local tabWidth = (totalTabWidth - ((#categories - 1) * 6)) / #categories
	for i, catData in ipairs(categories) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. catData.Id
		tabBtn.Size = UDim2.new(0, tabWidth, 1, 0)
		tabBtn.Position = UDim2.new(0, (i - 1) * (tabWidth + 6), 0, 0)
		tabBtn.BackgroundColor3 = if catData.Id == "All" then Color3.fromRGB(52, 73, 94) else Color3.fromRGB(24, 27, 36)
		tabBtn.BackgroundTransparency = 0.2
		tabBtn.TextColor3 = if catData.Id == "All" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(150, 155, 170)
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.TextSize = 11
		tabBtn.Text = catData.Label
		tabBtn.ZIndex = 12
		tabBtn.Parent = tabsContainer

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 7)
		tabCorner.Parent = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			setCategory(catData.Id)
		end)

		invCategoryTabs[catData.Id] = tabBtn
	end

	-- RB Button (Rechte Schultertaste)
	local rbBtn = Instance.new("TextButton")
	rbBtn.Name = "RB_Button"
	rbBtn.Size = UDim2.new(0, 34, 1, 0)
	rbBtn.Position = UDim2.new(1, -34, 0, 0)
	rbBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
	rbBtn.BackgroundTransparency = 0.2
	rbBtn.TextColor3 = Color3.fromRGB(180, 190, 215)
	rbBtn.Font = Enum.Font.GothamBold
	rbBtn.TextSize = 11
	rbBtn.Text = "RB"
	rbBtn.ZIndex = 12
	rbBtn.Parent = tabBar
	rbTabButton = rbBtn

	local rbCorner = Instance.new("UICorner")
	rbCorner.CornerRadius = UDim.new(0, 7)
	rbCorner.Parent = rbBtn

	local rbStroke = Instance.new("UIStroke")
	rbStroke.Color = Color3.fromRGB(55, 65, 85)
	rbStroke.Thickness = 1
	rbStroke.Transparency = 0.3
	rbStroke.Parent = rbBtn

	rbBtn.MouseButton1Click:Connect(function()
		switchCategoryTab(1)
	end)

	-- Scrolling Grid für Gegenstände mit Innenabstand (verhindert Rand-Clipping)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemGrid"
	scrollFrame.Size = UDim2.new(1, -36, 1, -106)
	scrollFrame.Position = UDim2.new(0, 18, 0, 96)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 80, 105)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.ZIndex = 12
	scrollFrame.Parent = modal
	invGridFrame = scrollFrame

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft = UDim.new(0, 6)
	scrollPad.PaddingRight = UDim.new(0, 10)
	scrollPad.PaddingTop = UDim.new(0, 6)
	scrollPad.PaddingBottom = UDim.new(0, 10)
	scrollPad.Parent = scrollFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 222, 0, 80)
	gridLayout.CellPadding = UDim2.new(0, 14, 0, 12)
	gridLayout.Parent = scrollFrame

	-- Leerzustand Anzeige (Empty state, zentriert im modalen Hauptfenster)
	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyLabel"
	empty.Size = UDim2.new(1, -36, 0, 120)
	empty.Position = UDim2.new(0, 18, 0.52, -60)
	empty.BackgroundTransparency = 1
	empty.TextColor3 = Color3.fromRGB(160, 165, 185)
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 14
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextYAlignment = Enum.TextYAlignment.Center
	empty.TextWrapped = true
	empty.Text = "📦 Keine Gegenstände in dieser Kategorie.\nErkunde Ruinen und bezwinge Bosse für Beute!"
	empty.Visible = false
	empty.ZIndex = 15
	empty.Parent = modal
	invEmptyLabel = empty

	-- ----------------------------------------------------
	-- 6. ITEM DETAIL MODAL (Infobox bei Klick auf Gegenstand)
	-- ----------------------------------------------------
	local detailFrame = Instance.new("Frame")
	detailFrame.Name = "ItemDetailModal"
	detailFrame.Size = UDim2.new(0, 350, 0, 305)
	detailFrame.Position = UDim2.new(0.5, -175, 0.5, -152)
	detailFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	detailFrame.BackgroundTransparency = 0.05
	detailFrame.Visible = false
	detailFrame.ZIndex = 25
	detailFrame.Parent = gui
	itemDetailModal = detailFrame

	local dCorner = Instance.new("UICorner")
	dCorner.CornerRadius = UDim.new(0, 14)
	dCorner.Parent = detailFrame

	local dStroke = Instance.new("UIStroke")
	dStroke.Color = Color3.fromRGB(70, 80, 105)
	dStroke.Thickness = 1.6
	dStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dStroke.Parent = detailFrame
	detailStroke = dStroke

	-- Kopfzeile
	local dHeader = Instance.new("Frame")
	dHeader.Name = "Header"
	dHeader.Size = UDim2.new(1, 0, 0, 62)
	dHeader.BackgroundTransparency = 1
	dHeader.ZIndex = 26
	dHeader.Parent = detailFrame

	local dIconBox = Instance.new("Frame")
	dIconBox.Name = "IconBox"
	dIconBox.Size = UDim2.new(0, 46, 0, 46)
	dIconBox.Position = UDim2.new(0, 14, 0, 8)
	dIconBox.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
	dIconBox.ZIndex = 26
	dIconBox.Parent = dHeader

	local dIconCorner = Instance.new("UICorner")
	dIconCorner.CornerRadius = UDim.new(0, 9)
	dIconCorner.Parent = dIconBox

	local dIconStroke = Instance.new("UIStroke")
	dIconStroke.Color = Color3.fromRGB(60, 70, 95)
	dIconStroke.Thickness = 1.2
	dIconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dIconStroke.Parent = dIconBox
	detailIconStroke = dIconStroke

	local dIconText = Instance.new("TextLabel")
	dIconText.Name = "IconText"
	dIconText.Size = UDim2.new(1, 0, 1, 0)
	dIconText.BackgroundTransparency = 1
	dIconText.Text = "⚔️"
	dIconText.TextSize = 26
	dIconText.ZIndex = 26
	dIconText.Parent = dIconBox
	detailIconText = dIconText

	local dTitle = Instance.new("TextLabel")
	dTitle.Name = "Title"
	dTitle.Size = UDim2.new(1, -114, 0, 20)
	dTitle.Position = UDim2.new(0, 68, 0, 10)
	dTitle.BackgroundTransparency = 1
	dTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	dTitle.Font = Enum.Font.GothamBold
	dTitle.TextSize = 14
	dTitle.TextXAlignment = Enum.TextXAlignment.Left
	dTitle.TextTruncate = Enum.TextTruncate.AtEnd
	dTitle.Text = "Item Name"
	dTitle.ZIndex = 26
	dTitle.Parent = dHeader
	detailTitleLabel = dTitle

	local dRarityBadge = Instance.new("TextLabel")
	dRarityBadge.Name = "RarityBadge"
	dRarityBadge.Size = UDim2.new(1, -114, 0, 16)
	dRarityBadge.Position = UDim2.new(0, 68, 0, 31)
	dRarityBadge.BackgroundTransparency = 1
	dRarityBadge.TextColor3 = Color3.fromRGB(150, 160, 185)
	dRarityBadge.Font = Enum.Font.GothamBold
	dRarityBadge.TextSize = 10
	dRarityBadge.TextXAlignment = Enum.TextXAlignment.Left
	dRarityBadge.Text = "[SELTEN]  •  Nahkampfwaffe"
	dRarityBadge.ZIndex = 26
	dRarityBadge.Parent = dHeader
	detailRarityBadge = dRarityBadge

	local dCloseBtn = Instance.new("TextButton")
	dCloseBtn.Name = "CloseBtn"
	dCloseBtn.Size = UDim2.new(0, 28, 0, 28)
	dCloseBtn.Position = UDim2.new(1, -38, 0, 10)
	dCloseBtn.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	dCloseBtn.BackgroundTransparency = 0.2
	dCloseBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
	dCloseBtn.Font = Enum.Font.GothamBold
	dCloseBtn.TextSize = 13
	dCloseBtn.Text = "X"
	dCloseBtn.ZIndex = 26
	dCloseBtn.Parent = dHeader

	local dCloseCorner = Instance.new("UICorner")
	dCloseCorner.CornerRadius = UDim.new(0, 7)
	dCloseCorner.Parent = dCloseBtn

	dCloseBtn.MouseButton1Click:Connect(function()
		HUDController.CloseItemDetails()
	end)

	-- Trennstrich
	local dLine = Instance.new("Frame")
	dLine.Size = UDim2.new(1, -28, 0, 1)
	dLine.Position = UDim2.new(0, 14, 0, 64)
	dLine.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
	dLine.BorderSizePixel = 0
	dLine.ZIndex = 26
	dLine.Parent = detailFrame

	-- Werte-Box (Detailed Stats)
	local dStatsBox = Instance.new("Frame")
	dStatsBox.Name = "StatsBox"
	dStatsBox.Size = UDim2.new(1, -28, 0, 34)
	dStatsBox.Position = UDim2.new(0, 14, 0, 74)
	dStatsBox.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	dStatsBox.ZIndex = 26
	dStatsBox.Parent = detailFrame

	local dStatsCorner = Instance.new("UICorner")
	dStatsCorner.CornerRadius = UDim.new(0, 8)
	dStatsCorner.Parent = dStatsBox

	local dStatsText = Instance.new("TextLabel")
	dStatsText.Name = "StatsText"
	dStatsText.Size = UDim2.new(1, -16, 1, 0)
	dStatsText.Position = UDim2.new(0, 8, 0, 0)
	dStatsText.BackgroundTransparency = 1
	dStatsText.TextColor3 = Color3.fromRGB(46, 204, 113)
	dStatsText.Font = Enum.Font.GothamBold
	dStatsText.TextSize = 11
	dStatsText.TextXAlignment = Enum.TextXAlignment.Left
	dStatsText.Text = "25 HP Schaden  •  0.35s Cooldown"
	dStatsText.ZIndex = 26
	dStatsText.Parent = dStatsBox
	detailStatsLabel = dStatsText

	-- Beschreibungs-Box (Fließtext)
	local dDescBox = Instance.new("Frame")
	dDescBox.Name = "DescBox"
	dDescBox.Size = UDim2.new(1, -28, 0, 84)
	dDescBox.Position = UDim2.new(0, 14, 0, 116)
	dDescBox.BackgroundColor3 = Color3.fromRGB(20, 23, 33)
	dDescBox.ZIndex = 26
	dDescBox.Parent = detailFrame

	local dDescCorner = Instance.new("UICorner")
	dDescCorner.CornerRadius = UDim.new(0, 8)
	dDescCorner.Parent = dDescBox

	local dDescText = Instance.new("TextLabel")
	dDescText.Name = "DescText"
	dDescText.Size = UDim2.new(1, -16, 1, -10)
	dDescText.Position = UDim2.new(0, 8, 0, 5)
	dDescText.BackgroundTransparency = 1
	dDescText.TextColor3 = Color3.fromRGB(180, 185, 200)
	dDescText.Font = Enum.Font.Gotham
	dDescText.TextSize = 11
	dDescText.TextXAlignment = Enum.TextXAlignment.Left
	dDescText.TextYAlignment = Enum.TextYAlignment.Top
	dDescText.TextWrapped = true
	dDescText.Text = "Vollständige Beschreibung..."
	dDescText.ZIndex = 26
	dDescText.Parent = dDescBox
	detailDescLabel = dDescText

	-- Tipp-Box (Nutzungshinweis)
	local dTipBox = Instance.new("Frame")
	dTipBox.Name = "TipBox"
	dTipBox.Size = UDim2.new(1, -28, 0, 42)
	dTipBox.Position = UDim2.new(0, 14, 0, 208)
	dTipBox.BackgroundColor3 = Color3.fromRGB(20, 30, 46)
	dTipBox.ZIndex = 26
	dTipBox.Parent = detailFrame

	local dTipCorner = Instance.new("UICorner")
	dTipCorner.CornerRadius = UDim.new(0, 8)
	dTipCorner.Parent = dTipBox

	local dTipStroke = Instance.new("UIStroke")
	dTipStroke.Color = Color3.fromRGB(45, 75, 115)
	dTipStroke.Thickness = 1
	dTipStroke.Transparency = 0.3
	dTipStroke.Parent = dTipBox

	local dTipText = Instance.new("TextLabel")
	dTipText.Name = "TipText"
	dTipText.Size = UDim2.new(1, -16, 1, -6)
	dTipText.Position = UDim2.new(0, 8, 0, 3)
	dTipText.BackgroundTransparency = 1
	dTipText.TextColor3 = Color3.fromRGB(140, 195, 255)
	dTipText.Font = Enum.Font.GothamMedium
	dTipText.TextSize = 10
	dTipText.TextXAlignment = Enum.TextXAlignment.Left
	dTipText.TextYAlignment = Enum.TextYAlignment.Center
	dTipText.TextWrapped = true
	dTipText.Text = "💡 Tipp..."
	dTipText.ZIndex = 26
	dTipText.Parent = dTipBox
	detailTipLabel = dTipText

	-- Schließen-Button
	local dBottomClose = Instance.new("TextButton")
	dBottomClose.Name = "BottomCloseBtn"
	dBottomClose.Size = UDim2.new(1, -28, 0, 30)
	dBottomClose.Position = UDim2.new(0, 14, 0, 258)
	dBottomClose.BackgroundColor3 = Color3.fromRGB(32, 38, 52)
	dBottomClose.TextColor3 = Color3.fromRGB(220, 225, 240)
	dBottomClose.Font = Enum.Font.GothamBold
	dBottomClose.TextSize = 11
	dBottomClose.Text = "Schließen  [X]"
	dBottomClose.ZIndex = 26
	dBottomClose.Parent = detailFrame

	local dBottomCorner = Instance.new("UICorner")
	dBottomCorner.CornerRadius = UDim.new(0, 8)
	dBottomCorner.Parent = dBottomClose

	dBottomClose.MouseButton1Click:Connect(function()
		HUDController.CloseItemDetails()
	end)

	-- ----------------------------------------------------
	-- 7. TOAST-BENACHRICHTIGUNGEN (Oben zentriert)
	-- ----------------------------------------------------
	local toast = Instance.new("Frame")
	toast.Name = "ToastBanner"
	toast.Size = UDim2.new(0, 360, 0, 42)
	toast.Position = UDim2.new(0.5, -180, 0, 65)
	toast.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	toast.BackgroundTransparency = 1
	toast.Visible = false
	toast.ZIndex = 20
	toast.Parent = gui
	toastFrame = toast

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 10)
	tCorner.Parent = toast

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(46, 204, 113)
	tStroke.Thickness = 1.4
	tStroke.Transparency = 1
	tStroke.Parent = toast
	toastStroke = tStroke

	local tIcon = Instance.new("TextLabel")
	tIcon.Name = "Icon"
	tIcon.Size = UDim2.new(0, 34, 1, 0)
	tIcon.Position = UDim2.new(0, 8, 0, 0)
	tIcon.BackgroundTransparency = 1
	tIcon.Text = "✅"
	tIcon.TextSize = 18
	tIcon.TextTransparency = 1
	tIcon.ZIndex = 21
	tIcon.Parent = toast
	toastIcon = tIcon

	local tLabel = Instance.new("TextLabel")
	tLabel.Name = "Message"
	tLabel.Size = UDim2.new(1, -50, 1, 0)
	tLabel.Position = UDim2.new(0, 42, 0, 0)
	tLabel.BackgroundTransparency = 1
	tLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
	tLabel.Font = Enum.Font.GothamBold
	tLabel.TextSize = 12
	tLabel.TextXAlignment = Enum.TextXAlignment.Left
	tLabel.TextTransparency = 1
	tLabel.Text = ""
	tLabel.ZIndex = 21
	tLabel.Parent = toast
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
		healthFillBar.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
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
			healthCardStroke.Transparency = 0.1
		else
			healthCardStroke.Color = Color3.fromRGB(50, 56, 70)
			healthCardStroke.Transparency = 0.3
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

	local accentColor = if isError then Color3.fromRGB(231, 76, 60) else Color3.fromRGB(46, 204, 113)
	local iconText = if isError then "⚠️" else "✅"

	toastText.Text = message
	toastIcon.Text = iconText
	toastStroke.Color = accentColor
	toastFrame.Visible = true

	TweenService:Create(toastFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(toastStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.2 }):Play()
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
			{ Size = UDim2.new(0, 240, 0, 50) }
		)
		local reset = TweenService:Create(
			goldCardFrame,
			TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 236, 0, 48) }
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

		-- Konsole / Gamepad: [ButtonY] (Xbox Y / PlayStation Dreieck - Standard in Minecraft/Skyrim), [ButtonSelect] (View/Touchpad), [DPadUp]
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

	print("[HUDController] Initialisiert: Modernes HUD, Lebensanzeige und Inventarsystem aktiv.")
end

return HUDController
