--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local ConfigFolder = Shared:WaitForChild("Config")

-- Check-UI Bibliotheken
local CheckUIFolder = Shared:WaitForChild("CheckUI")
local CheckUITheme = require(CheckUIFolder:WaitForChild("CheckUITheme") :: ModuleScript)
local CheckUIComponents = require(CheckUIFolder:WaitForChild("CheckUIComponents") :: ModuleScript)
local CheckUIController = require(CheckUIFolder:WaitForChild("CheckUIController") :: ModuleScript)

-- Konfiguration
local ItemConfigModule = ConfigFolder:WaitForChild("ItemConfig") :: ModuleScript
local ItemConfig = require(ItemConfigModule)

-- RemoteEvents
local OpenShopWindowEvent = EventsFolder:WaitForChild("OpenShopWindow") :: RemoteEvent
local BuyWeaponIntent = EventsFolder:WaitForChild("BuyWeaponIntent") :: RemoteEvent
local EquipWeaponIntent = EventsFolder:WaitForChild("EquipWeaponIntent") :: RemoteEvent
local UnlockSlotIntent = EventsFolder:WaitForChild("UnlockSlotIntent") :: RemoteEvent
local BuyDefenseIntent = EventsFolder:WaitForChild("BuyDefenseIntent") :: RemoteEvent
local InventoryUpdated = EventsFolder:WaitForChild("InventoryUpdated") :: RemoteEvent
local GoldUpdated = EventsFolder:WaitForChild("GoldUpdated") :: RemoteEvent

local ShopController = {}
local isInitialized = false

-- Gecachte Daten
local cachedGold = 0
local cachedInventory: any = {
	Weapons = { "RustySword" },
	EquippedWeapon = "RustySword",
	Materials = { IronOre = 0, VoidCrystal = 0 },
	Cores = {},
}
local cachedBaseData: any = {
	Slots = {},
	UnlockedSlots = { [1] = true, [2] = false, [3] = false },
	Defenses = { Spikes = 2, Guards = 1 },
}

-- UI Instanzen
local shopGui: ScreenGui? = nil
local shopBackdrop: TextButton? = nil
local shopWindow: Frame? = nil
local windowScale: UIScale? = nil
local contentScroll: ScrollingFrame? = nil
local currentTab = "Weapons" -- "Weapons" | "Defenses" | "Slots"
local tabButtons: { [string]: TextButton } = {}

-- Schließt das Shop-Fenster
function ShopController.CloseShop()
	if not shopWindow or not shopWindow.Visible then
		return
	end

	if shopBackdrop then
		shopBackdrop.Modal = false
		shopBackdrop.Visible = false
	end

	if windowScale then
		local closeTween = TweenService:Create(
			windowScale,
			TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = CheckUIController.getDeviceScale() * 0.70 }
		)
		closeTween:Play()
		closeTween.Completed:Connect(function()
			if not (shopBackdrop and shopBackdrop.Visible) and shopWindow then
				shopWindow.Visible = false
			end
		end)
	else
		shopWindow.Visible = false
	end
end

-- Baut die Liste der Items im aktiven Tab auf
local function renderTabContent()
	if not contentScroll then
		return
	end

	-- Vorherige Elemente löschen
	for _, child in contentScroll:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local shopConfig = (ItemConfig :: any).Shop
	if not shopConfig then
		return
	end

	local yOffset = 0
	-- Einheitliches Karten-Layout aller Tabs: 3 Info-Zeilen (Titel / Details / Kosten),
	-- wobei die Detailzeile über 2 Zeilen umbrechen darf statt abgeschnitten zu werden.
	local CARD_HEIGHT = 92
	local CARD_SPACING = 8

	-- Info-Block-Geometrie: Der Text beginnt bei x=84 und darf den Platz bis kurz vor dem
	-- rechten Action-Button (Breite 150px) nutzen - kein hartes Abschneiden mehr.
	local INFO_X = 84
	local INFO_WIDTH_OFFSET = 242 -- 84 (links) + 150 (Action-Button) + 8 (Abstand)

	-- =========================================================
	-- TAB 1: WAFFEN
	-- =========================================================
	if currentTab == "Weapons" then
		local weaponIds = shopConfig.WeaponOrder or { "RustySword", "IronSword", "AmethystBlade", "VoidScythe" }

		for _, weaponId in ipairs(weaponIds) do
			local itemInfo = ItemConfig[weaponId]
			if not itemInfo then
				continue
			end

			local isOwned = table.find(cachedInventory.Weapons, weaponId) ~= nil
			local isEquipped = (cachedInventory.EquippedWeapon == weaponId)
			local costGold = itemInfo.CostGold or 0
			local costMats = itemInfo.CostMaterials or {}

			-- Prüfe Bezahlbarkeit
			local hasEnoughGold = (cachedGold >= costGold)
			local hasEnoughMats = true
			local costTextParts = {}
			if costGold > 0 then
				table.insert(costTextParts, string.format("💰 %d Gold", costGold))
			end
			for matKey, reqAmount in pairs(costMats) do
				local currentAmt = cachedInventory.Materials[matKey] or 0
				local matInfo = ItemConfig[matKey]
				local matName = if matInfo then matInfo.DisplayName else matKey
				if currentAmt < reqAmount then
					hasEnoughMats = false
					table.insert(costTextParts, string.format("❌ %d/%d %s", currentAmt, reqAmount, matName))
				else
					table.insert(costTextParts, string.format("✓ %d %s", reqAmount, matName))
				end
			end
			local canAfford = hasEnoughGold and hasEnoughMats

			-- Karten-Container
			local card = Instance.new("Frame")
			card.Name = "WeaponCard_" .. weaponId
			card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
			card.Position = UDim2.new(0, 4, 0, yOffset)
			card.BackgroundColor3 = CheckUITheme.Colors.CardBackground
			card.BorderSizePixel = 0
			card.Parent = contentScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = if isEquipped then Color3.fromRGB(46, 204, 113) else CheckUITheme.Colors.CardHighlight
			cardStroke.Thickness = if isEquipped then 2 else 1.2
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			-- Icon Box
			local iconBox = Instance.new("Frame")
			iconBox.Name = "IconBox"
			iconBox.Size = UDim2.new(0, 64, 0, 64)
			iconBox.Position = UDim2.new(0, 10, 0.5, 0)
			iconBox.AnchorPoint = Vector2.new(0, 0.5)
			iconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
			iconBox.BorderSizePixel = 0
			iconBox.Parent = card

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 6)
			iconCorner.Parent = iconBox

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Size = UDim2.new(1, 0, 1, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Text = itemInfo.Icon or "⚔️"
			iconLabel.TextSize = 34
			iconLabel.Parent = iconBox

			-- Info Block (Titel & Seltenheit)
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "WeaponName"
			nameLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 22)
			nameLabel.Position = UDim2.new(0, INFO_X, 0, 12)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = itemInfo.DisplayName
			nameLabel.Font = Enum.Font.GothamBlack
			nameLabel.TextSize = 16
			nameLabel.TextColor3 = itemInfo.RarityColor or Color3.fromRGB(255, 255, 255)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = card

			-- Stats & Cooldown (bricht bei langen Werten um, statt abgeschnitten zu werden)
			local statsLabel = Instance.new("TextLabel")
			statsLabel.Name = "Stats"
			statsLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 28)
			statsLabel.Position = UDim2.new(0, INFO_X, 0, 34)
			statsLabel.BackgroundTransparency = 1
			statsLabel.Text = string.format("💥 %s", itemInfo.DetailedStats or itemInfo.StatsText)
			statsLabel.Font = Enum.Font.GothamMedium
			statsLabel.TextSize = 12
			statsLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
			statsLabel.TextXAlignment = Enum.TextXAlignment.Left
			statsLabel.TextYAlignment = Enum.TextYAlignment.Top
			statsLabel.TextWrapped = true
			statsLabel.Parent = card

			-- Kosten-Zeile
			local costLabel = Instance.new("TextLabel")
			costLabel.Name = "CostLabel"
			costLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 18)
			costLabel.Position = UDim2.new(0, INFO_X, 0, 64)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = if isOwned then "✓ Bereits freigeschaltet" else table.concat(costTextParts, "  •  ")
			costLabel.Font = Enum.Font.GothamBold
			costLabel.TextSize = 11
			costLabel.TextColor3 = if isOwned then Color3.fromRGB(46, 204, 113) else (if canAfford then Color3.fromRGB(255, 215, 60) else Color3.fromRGB(255, 100, 100))
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.TextTruncate = Enum.TextTruncate.AtEnd
			costLabel.Parent = card

			-- Action Button (Rechts)
			local actionBtn = Instance.new("TextButton")
			actionBtn.Name = "ActionBtn"
			actionBtn.Size = UDim2.new(0, 140, 0, 42)
			actionBtn.Position = UDim2.new(1, -150, 0.5, 0)
			actionBtn.AnchorPoint = Vector2.new(0, 0.5)
			actionBtn.AutoButtonColor = false
			actionBtn.BorderSizePixel = 0
			actionBtn.Font = Enum.Font.GothamBlack
			actionBtn.TextSize = 13
			actionBtn.Parent = card

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = actionBtn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Thickness = 1.5
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Parent = actionBtn

			local btnScale = Instance.new("UIScale")
			btnScale.Parent = actionBtn

			if isEquipped then
				actionBtn.Text = "AUSGERÜSTET ✓"
				actionBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 45)
				actionBtn.TextColor3 = Color3.fromRGB(200, 255, 200)
				btnStroke.Color = Color3.fromRGB(80, 220, 90)
			elseif isOwned then
				actionBtn.Text = "AUSRÜSTEN"
				actionBtn.BackgroundColor3 = Color3.fromRGB(30, 90, 160)
				actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				btnStroke.Color = Color3.fromRGB(80, 180, 255)
				CheckUIController.bindButtonAnimations(actionBtn, btnScale, 1.04, 0.96)
				actionBtn.MouseButton1Click:Connect(function()
					EquipWeaponIntent:FireServer(weaponId)
				end)
			elseif canAfford then
				actionBtn.Text = "SCHMIEDEN"
				actionBtn.BackgroundColor3 = Color3.fromRGB(15, 140, 20)
				actionBtn.TextColor3 = Color3.fromRGB(240, 255, 140)
				btnStroke.Color = Color3.fromRGB(180, 255, 40)
				CheckUIController.bindButtonAnimations(actionBtn, btnScale, 1.04, 0.96)
				actionBtn.MouseButton1Click:Connect(function()
					BuyWeaponIntent:FireServer(weaponId)
				end)
			else
				actionBtn.Text = "ZU WENIG ERZ"
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 60)
				actionBtn.TextColor3 = Color3.fromRGB(130, 140, 150)
				btnStroke.Color = Color3.fromRGB(30, 35, 40)
			end

			yOffset += CARD_HEIGHT + CARD_SPACING
		end

	-- =========================================================
	-- TAB 2: VERTEIDIGUNG
	-- =========================================================
	elseif currentTab == "Defenses" then
		local defTypes = { "Spikes", "Guards" }

		for _, defKey in ipairs(defTypes) do
			local defInfo = shopConfig.Defenses[defKey]
			if not defInfo then
				continue
			end

			local currentCount = cachedBaseData.Defenses[defKey] or 0
			local isMax = currentCount >= defInfo.MaxCount
			local costGold = defInfo.CostGold
			local costMats = defInfo.CostMaterials or {}

			local hasEnoughGold = (cachedGold >= costGold)
			local hasEnoughMats = true
			local costTextParts = { string.format("💰 %d Gold", costGold) }
			for matKey, reqAmount in pairs(costMats) do
				local currentAmt = cachedInventory.Materials[matKey] or 0
				local matInfo = ItemConfig[matKey]
				local matName = if matInfo then matInfo.DisplayName else matKey
				if currentAmt < reqAmount then
					hasEnoughMats = false
					table.insert(costTextParts, string.format("❌ %d/%d %s", currentAmt, reqAmount, matName))
				else
					table.insert(costTextParts, string.format("✓ %d %s", reqAmount, matName))
				end
			end
			local canAfford = hasEnoughGold and hasEnoughMats

			local card = Instance.new("Frame")
			card.Name = "DefenseCard_" .. defKey
			card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
			card.Position = UDim2.new(0, 4, 0, yOffset)
			card.BackgroundColor3 = CheckUITheme.Colors.CardBackground
			card.BorderSizePixel = 0
			card.Parent = contentScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = CheckUITheme.Colors.CardHighlight
			cardStroke.Thickness = 1.2
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			-- Icon Box
			local iconBox = Instance.new("Frame")
			iconBox.Size = UDim2.new(0, 64, 0, 64)
			iconBox.Position = UDim2.new(0, 10, 0.5, 0)
			iconBox.AnchorPoint = Vector2.new(0, 0.5)
			iconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
			iconBox.BorderSizePixel = 0
			iconBox.Parent = card

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 6)
			iconCorner.Parent = iconBox

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Size = UDim2.new(1, 0, 1, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Text = defInfo.Icon
			iconLabel.TextSize = 34
			iconLabel.Parent = iconBox

			-- Info Block
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 22)
			nameLabel.Position = UDim2.new(0, INFO_X, 0, 12)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = string.format("%s (%d/%d)", defInfo.DisplayName, currentCount, defInfo.MaxCount)
			nameLabel.Font = Enum.Font.GothamBlack
			nameLabel.TextSize = 16
			nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = card

			local statsLabel = Instance.new("TextLabel")
			statsLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 28)
			statsLabel.Position = UDim2.new(0, INFO_X, 0, 34)
			statsLabel.BackgroundTransparency = 1
			statsLabel.Text = defInfo.StatsText
			statsLabel.Font = Enum.Font.GothamMedium
			statsLabel.TextSize = 12
			statsLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
			statsLabel.TextXAlignment = Enum.TextXAlignment.Left
			statsLabel.TextYAlignment = Enum.TextYAlignment.Top
			statsLabel.TextWrapped = true
			statsLabel.Parent = card

			local costLabel = Instance.new("TextLabel")
			costLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 18)
			costLabel.Position = UDim2.new(0, INFO_X, 0, 64)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = if isMax then "✓ Maximum auf Basis erreicht" else table.concat(costTextParts, "  •  ")
			costLabel.Font = Enum.Font.GothamBold
			costLabel.TextSize = 11
			costLabel.TextColor3 = if isMax then Color3.fromRGB(46, 204, 113) else (if canAfford then Color3.fromRGB(255, 215, 60) else Color3.fromRGB(255, 100, 100))
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.TextTruncate = Enum.TextTruncate.AtEnd
			costLabel.Parent = card

			-- Button
			local actionBtn = Instance.new("TextButton")
			actionBtn.Size = UDim2.new(0, 140, 0, 42)
			actionBtn.Position = UDim2.new(1, -150, 0.5, 0)
			actionBtn.AnchorPoint = Vector2.new(0, 0.5)
			actionBtn.AutoButtonColor = false
			actionBtn.BorderSizePixel = 0
			actionBtn.Font = Enum.Font.GothamBlack
			actionBtn.TextSize = 12
			actionBtn.Parent = card

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = actionBtn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Thickness = 1.5
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Parent = actionBtn

			local btnScale = Instance.new("UIScale")
			btnScale.Parent = actionBtn

			if isMax then
				actionBtn.Text = "MAXIMALANZAHL"
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 60)
				actionBtn.TextColor3 = Color3.fromRGB(140, 145, 150)
				btnStroke.Color = Color3.fromRGB(30, 35, 40)
			elseif canAfford then
				actionBtn.Text = "KAUFEN & BAUEN"
				actionBtn.BackgroundColor3 = Color3.fromRGB(15, 140, 20)
				actionBtn.TextColor3 = Color3.fromRGB(240, 255, 140)
				btnStroke.Color = Color3.fromRGB(180, 255, 40)
				CheckUIController.bindButtonAnimations(actionBtn, btnScale, 1.04, 0.96)
				actionBtn.MouseButton1Click:Connect(function()
					BuyDefenseIntent:FireServer(defKey)
				end)
			else
				actionBtn.Text = "NICHT GENUG GOLD"
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 60)
				actionBtn.TextColor3 = Color3.fromRGB(130, 140, 150)
				btnStroke.Color = Color3.fromRGB(30, 35, 40)
			end

			yOffset += CARD_HEIGHT + CARD_SPACING
		end

	-- =========================================================
	-- TAB 3: BASIS-SOCKEL
	-- =========================================================
	elseif currentTab == "Slots" then
		for slotIndex = 2, 3 do
			local unlockInfo = shopConfig.SlotUnlocks[slotIndex]
			local isUnlocked = (cachedBaseData.UnlockedSlots and cachedBaseData.UnlockedSlots[slotIndex] == true)
			local costGold = if unlockInfo then unlockInfo.CostGold else (if slotIndex == 2 then 500 else 2000)
			local canAfford = (cachedGold >= costGold)

			local card = Instance.new("Frame")
			card.Name = "SlotCard_" .. slotIndex
			card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
			card.Position = UDim2.new(0, 4, 0, yOffset)
			card.BackgroundColor3 = CheckUITheme.Colors.CardBackground
			card.BorderSizePixel = 0
			card.Parent = contentScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = if isUnlocked then Color3.fromRGB(46, 204, 113) else CheckUITheme.Colors.CardHighlight
			cardStroke.Thickness = 1.2
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			-- Icon Box
			local iconBox = Instance.new("Frame")
			iconBox.Size = UDim2.new(0, 64, 0, 64)
			iconBox.Position = UDim2.new(0, 10, 0.5, 0)
			iconBox.AnchorPoint = Vector2.new(0, 0.5)
			iconBox.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
			iconBox.BorderSizePixel = 0
			iconBox.Parent = card

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 6)
			iconCorner.Parent = iconBox

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Size = UDim2.new(1, 0, 1, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Text = if isUnlocked then "🏰" else "🔒"
			iconLabel.TextSize = 34
			iconLabel.Parent = iconBox

			-- Info Block
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 20)
			nameLabel.Position = UDim2.new(0, INFO_X, 0, 12)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = string.format("Statuen-Sockel %d", slotIndex)
			nameLabel.Font = Enum.Font.GothamBlack
			nameLabel.TextSize = 16
			nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = card

			-- Beschreibung: bricht über zwei Zeilen um, statt am Rand abgeschnitten zu werden
			local descLabel = Instance.new("TextLabel")
			descLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 28)
			descLabel.Position = UDim2.new(0, INFO_X, 0, 34)
			descLabel.BackgroundTransparency = 1
			descLabel.Text = if unlockInfo then unlockInfo.Description else "Zusätzlicher Platz für Boss-Statuen"
			descLabel.Font = Enum.Font.GothamMedium
			descLabel.TextSize = 11
			descLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextYAlignment = Enum.TextYAlignment.Top
			descLabel.TextWrapped = true
			descLabel.Parent = card

			local costLabel = Instance.new("TextLabel")
			costLabel.Size = UDim2.new(1, -INFO_WIDTH_OFFSET, 0, 18)
			costLabel.Position = UDim2.new(0, INFO_X, 0, 64)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = if isUnlocked then "✓ Aktiv auf deiner Basis" else string.format("Kosten: 💰 %d Gold", costGold)
			costLabel.Font = Enum.Font.GothamBold
			costLabel.TextSize = 11
			costLabel.TextColor3 = if isUnlocked then Color3.fromRGB(46, 204, 113) else (if canAfford then Color3.fromRGB(255, 215, 60) else Color3.fromRGB(255, 100, 100))
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.TextTruncate = Enum.TextTruncate.AtEnd
			costLabel.Parent = card

			-- Button
			local actionBtn = Instance.new("TextButton")
			actionBtn.Size = UDim2.new(0, 140, 0, 42)
			actionBtn.Position = UDim2.new(1, -150, 0.5, 0)
			actionBtn.AnchorPoint = Vector2.new(0, 0.5)
			actionBtn.AutoButtonColor = false
			actionBtn.BorderSizePixel = 0
			actionBtn.Font = Enum.Font.GothamBlack
			actionBtn.TextSize = 12
			actionBtn.Parent = card

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = actionBtn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Thickness = 1.5
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Parent = actionBtn

			local btnScale = Instance.new("UIScale")
			btnScale.Parent = actionBtn

			if isUnlocked then
				actionBtn.Text = "FREIGESCHALTET ✓"
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 60)
				actionBtn.TextColor3 = Color3.fromRGB(140, 145, 150)
				btnStroke.Color = Color3.fromRGB(30, 35, 40)
			elseif canAfford then
				actionBtn.Text = "FREISCHALTEN"
				actionBtn.BackgroundColor3 = Color3.fromRGB(15, 140, 20)
				actionBtn.TextColor3 = Color3.fromRGB(240, 255, 140)
				btnStroke.Color = Color3.fromRGB(180, 255, 40)
				CheckUIController.bindButtonAnimations(actionBtn, btnScale, 1.04, 0.96)
				actionBtn.MouseButton1Click:Connect(function()
					UnlockSlotIntent:FireServer(slotIndex)
				end)
			else
				actionBtn.Text = "ZU WENIG GOLD"
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 60)
				actionBtn.TextColor3 = Color3.fromRGB(130, 140, 150)
				btnStroke.Color = Color3.fromRGB(30, 35, 40)
			end

			yOffset += CARD_HEIGHT + CARD_SPACING
		end
	end

	contentScroll.CanvasSize = UDim2.new(0, 0, 0, yOffset + 12)
end

-- Aktualisiert das optische Tab-Highlighting
local function setTab(tabName: string)
	currentTab = tabName

	for name, btn in pairs(tabButtons) do
		local isSelected = (name == tabName)
		btn.BackgroundColor3 = if isSelected then CheckUITheme.Colors.CardBackground else CheckUITheme.Colors.RequirementsBox
		btn.TextColor3 = if isSelected then Color3.fromRGB(255, 220, 80) else Color3.fromRGB(160, 175, 190)
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if isSelected then Color3.fromRGB(255, 215, 60) else CheckUITheme.Colors.CardHighlight
			stroke.Thickness = if isSelected then 2 else 1
		end
	end

	renderTabContent()
end

-- Öffnet das Shop-Fenster
function ShopController.OpenShop(initialTab: string?)
	if not shopWindow then
		return
	end

	if initialTab then
		currentTab = initialTab
	end

	setTab(currentTab)

	-- 1. Modal aktivieren & Maus in Egoperspektive / First-Person freigeben!
	if shopBackdrop then
		shopBackdrop.Modal = true
		shopBackdrop.Visible = true
	end

	shopWindow.Visible = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	if windowScale then
		local targetScale = CheckUIController.getDeviceScale()
		windowScale.Scale = targetScale * 0.75
		local openTween = TweenService:Create(
			windowScale,
			TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = targetScale }
		)
		openTween:Play()
	end
end

-- Prüft, ob der Shop geöffnet ist
function ShopController.IsOpen(): boolean
	return shopWindow ~= nil and shopWindow.Visible
end

-- Schaltet das Shop-Fenster um
function ShopController.ToggleShop()
	if shopWindow and shopWindow.Visible then
		ShopController.CloseShop()
	else
		ShopController.OpenShop()
	end
end

-- Erstellt das gesamte Shop-UI (Window, Header, Tabs, Content & HUD-Button)
local function createShopUI()
	local screenGui = PlayerGui:FindFirstChild("RealmRaidersUI") :: ScreenGui?
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "RealmRaidersUI"
		screenGui.ResetOnSpawn = false
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = PlayerGui
	end
	shopGui = screenGui

	-- 0. Modaler Backdrop (Gibt in der Egoperspektive die Maus frei & schließt Shop bei Klick außerhalb)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ShopBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Text = ""
	backdrop.Modal = true -- WICHTIG: Gibt in der First-Person die Maus frei!
	backdrop.Visible = false
	backdrop.ZIndex = 25
	backdrop.Parent = screenGui
	shopBackdrop = backdrop

	backdrop.MouseButton1Click:Connect(function()
		ShopController.CloseShop()
	end)

	-- 1. Modales Hauptfenster
	local window = CheckUIComponents.createWindow({
		Name = "BlacksmithShopWindow",
		Size = UDim2.new(0, 600, 0, 470),
		Parent = screenGui,
		ZIndex = 30,
	})
	shopWindow = window
	windowScale = window:FindFirstChild("WindowScale") :: UIScale?

	-- 2. Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 52)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundColor3 = Color3.fromRGB(42, 64, 76)
	header.BorderSizePixel = 0
	header.ZIndex = window.ZIndex + 1
	header.Parent = window

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 4)
	headerCorner.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Size = UDim2.new(1, -60, 1, 0)
	headerTitle.Position = UDim2.new(0, 16, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "⚔️ WAFFEN-SCHMIEDE & SHOP"
	headerTitle.Font = Enum.Font.GothamBlack
	headerTitle.TextSize = 20
	headerTitle.TextColor3 = Color3.fromRGB(255, 225, 80)
	headerTitle.TextStrokeTransparency = 0.3
	headerTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = header.ZIndex + 1
	headerTitle.Parent = header

	-- 3D Square Close Button [X]
	local closeBtn = CheckUIComponents.createCloseButton(header)
	closeBtn.Position = UDim2.new(1, -44, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(0, 0.5)
	closeBtn.ZIndex = header.ZIndex + 2
	-- Phase 3 (Mobile): Mindest-Touchfläche von 44x44px auf Touch-Geräten
	if UserInputService.TouchEnabled and closeBtn.Size.Y.Offset < 44 then
		closeBtn.Size = UDim2.new(0, 44, 0, 44)
	end
	closeBtn.MouseButton1Click:Connect(function()
		ShopController.CloseShop()
	end)

	-- 2-Tier Header Divider Line
	local divider = Instance.new("Frame")
	divider.Name = "HeaderDivider"
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.Position = UDim2.new(0, 0, 1, -2)
	divider.BackgroundColor3 = Color3.fromRGB(20, 32, 40)
	divider.BorderSizePixel = 0
	divider.ZIndex = header.ZIndex + 1
	divider.Parent = header

	-- 3. Tab-Leiste (Waffen, Verteidigung, Sockel)
	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "TabContainer"
	tabContainer.Size = UDim2.new(1, -24, 0, 38)
	tabContainer.Position = UDim2.new(0, 12, 0, 60)
	tabContainer.BackgroundTransparency = 1
	tabContainer.ZIndex = window.ZIndex + 1
	tabContainer.Parent = window

	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabList.Padding = UDim.new(0, 8)
	tabList.Parent = tabContainer

	local tabsData = {
		{ Id = "Weapons", Label = "🗡️ Waffen" },
		{ Id = "Defenses", Label = "🛡️ Verteidigung" },
		{ Id = "Slots", Label = "🏰 Sockel" },
	}

	for _, tData in ipairs(tabsData) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tData.Id
		tabBtn.Size = UDim2.new(0, 130, 1, 0)
		tabBtn.BackgroundColor3 = CheckUITheme.Colors.RequirementsBox
		tabBtn.BorderSizePixel = 0
		tabBtn.Font = Enum.Font.GothamBlack
		tabBtn.TextSize = 13
		tabBtn.TextColor3 = Color3.fromRGB(160, 175, 190)
		tabBtn.Text = tData.Label
		tabBtn.AutoButtonColor = false
		tabBtn.ZIndex = tabContainer.ZIndex + 1
		tabBtn.Parent = tabContainer

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, 6)
		tCorner.Parent = tabBtn

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = CheckUITheme.Colors.CardHighlight
		tStroke.Thickness = 1
		tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tStroke.Parent = tabBtn

		local tScale = Instance.new("UIScale")
		tScale.Parent = tabBtn
		CheckUIController.bindButtonAnimations(tabBtn, tScale, 1.04, 0.96)

		tabBtn.MouseButton1Click:Connect(function()
			setTab(tData.Id)
		end)

		tabButtons[tData.Id] = tabBtn
	end

	-- 4. Scroll-Bereich für Inhalte
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ContentScroll"
	scroll.Size = UDim2.new(1, -24, 1, -112)
	scroll.Position = UDim2.new(0, 12, 0, 104)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 140)
	scroll.ZIndex = window.ZIndex + 1
	scroll.Parent = window
	contentScroll = scroll

	-- 5. Schnellzugriff-Button im HUD (unter dem Inventar-Button)
	local hudFrame = screenGui:FindFirstChild("MainHUD") or screenGui
	local shopHudBtn = Instance.new("TextButton")
	shopHudBtn.Name = "ShopHUDButton"
	shopHudBtn.Size = UDim2.new(0, 240, 0, 34)
	shopHudBtn.Position = UDim2.new(1, -260, 0, 108)
	shopHudBtn.BackgroundColor3 = CheckUITheme.Colors.CardBackground
	shopHudBtn.BorderSizePixel = 0
	shopHudBtn.AutoButtonColor = false
	shopHudBtn.Text = ""
	shopHudBtn.ZIndex = 15
	shopHudBtn.Parent = hudFrame

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 6)
	sCorner.Parent = shopHudBtn

	local sStroke = Instance.new("UIStroke")
	sStroke.Color = Color3.fromRGB(255, 215, 60)
	sStroke.Thickness = 1.5
	sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sStroke.Parent = shopHudBtn

	local sLabel = Instance.new("TextLabel")
	sLabel.Size = UDim2.new(1, 0, 1, 0)
	sLabel.BackgroundTransparency = 1
	sLabel.Text = "⚔️ SCHMIEDE & SHOP  [B]"
	sLabel.Font = Enum.Font.GothamBlack
	sLabel.TextSize = 13
	sLabel.TextColor3 = Color3.fromRGB(255, 225, 80)
	sLabel.Parent = shopHudBtn

	local sScale = Instance.new("UIScale")
	sScale.Parent = shopHudBtn
	CheckUIController.bindButtonAnimations(shopHudBtn, sScale, 1.03, 0.96)

	shopHudBtn.MouseButton1Click:Connect(function()
		ShopController.ToggleShop()
	end)

	-- Hotkey [B] für schnelles Öffnen/Schließen
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.B then
			ShopController.ToggleShop()
		end
	end)
end

function ShopController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	createShopUI()

	-- RemoteEvents anbinden
	OpenShopWindowEvent.OnClientEvent:Connect(function()
		ShopController.OpenShop("Weapons")
	end)

	InventoryUpdated.OnClientEvent:Connect(function(newInv: any)
		if newInv then
			cachedInventory = newInv
			if shopWindow and shopWindow.Visible then
				renderTabContent()
			end
		end
	end)

	GoldUpdated.OnClientEvent:Connect(function(newGold: number)
		cachedGold = newGold
		if shopWindow and shopWindow.Visible then
			renderTabContent()
		end
	end)

	print("[ShopController] Initialisiert: Waffen-Schmiede, Verteidigungs-Kauf & Sockel-Upgrades aktiv.")
end

return ShopController
