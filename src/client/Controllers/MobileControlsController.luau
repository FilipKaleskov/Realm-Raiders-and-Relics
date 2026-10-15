--!strict
--[[
	MobileControlsController.luau
	Phase 3 (Mobile & Touch-Support) für "Realm Raiders & Relics"

	Aufgaben:
	  1. "Mobile Action Cluster" in der unteren rechten Ecke (ergonomischer Daumen-Bogen):
	       - ⚔️ Primärer Angriffs-Button (68x68)  -> CombatController.TriggerAttack()
	       - ⚡ Combat-Dash-Button     (58x58)  -> CombatController.TriggerDash() + Cooldown-Maske
	       - 🏃 Sprint-Toggle-Button   (52x52)  -> MovementController.ToggleSprint()
	     Alle Buttons im Check-UI Design-Standard: 3D-Bevel-Extrusion an der Unterseite,
	     dicker schwarzer UIStroke (3.0px), knallige UIGradient-Farbverläufe, Damier-Textur,
	     zentrierte GothamBlack-Typografie und HD-Icons (CheckUIIcons-Registry).

	  2. UIScale-Engine: Skaliert die komplette Button-Gruppe anhand von Camera.ViewportSize.Y
	     (Baseline 400px, geklemmt zwischen 0.85 und 1.25) -> Smartphones & Tablets.

	  3. Sprungkopf-Schutz: Die Gruppe wird dynamisch so verschoben, dass sie NIEMALS mit dem
	     Roblox-Standard-Sprungknopf (untere rechte Ecke) kollidiert.

	  4. Touch-optimierte ProximityPrompts: Statt des winzigen Welt-Prompts erscheint auf
	     Touch-Geräten ein großer, daumenfreundlicher Check-UI-Aktions-Button (inkl. Halte-
	     Fortschrittsbalken für Halte-Prompts wie dem Seelenkern-Diebstahl).

	  5. Plattform-Erkennung: Ohne Touchscreen wird NICHTS erstellt (Desktop bleibt zu 100 %
	     unberührt). Auf Hybrid-Geräten (Touch-Laptops) folgt die Sichtbarkeit dem Roblox-
	     Touch-Controls-Status, sodass Maus/Tastatur und Finger nahtlos parallel funktionieren.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- ==========================================
-- CHECK-UI DESIGN SYSTEM
-- ==========================================
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CheckUIFolder = Shared:WaitForChild("CheckUI")
local CheckUITheme = require(CheckUIFolder:WaitForChild("CheckUITheme") :: ModuleScript)
local CheckUIIcons = require(CheckUIFolder:WaitForChild("CheckUIIcons") :: ModuleScript)

-- Bestehende Controller (Nahkampf, Dash & Sprint)
local ControllersFolder = script.Parent
local CombatController = require(ControllersFolder:WaitForChild("CombatController") :: ModuleScript)
local MovementController = require(ControllersFolder:WaitForChild("MovementController") :: ModuleScript)

local MobileControlsController = {}
local isInitialized = false

-- ==========================================
-- 1. KONSTANTEN: SCREEN-GUI, SKALIERUNG & LAYOUT
-- ==========================================
local SCREEN_GUI_NAME = "RealmRaidersMobileGui"
local MOBILE_GUI_DISPLAY_ORDER = 15

-- UIScale-Engine: Baseline 400px Höhe (typisches Smartphone im Landscape),
-- geklemmt zwischen 0.85 (kleine Geräte) und 1.25 (Tablets).
local SCALE_BASELINE_HEIGHT = 400
local SCALE_MIN = 0.85
local SCALE_MAX = 1.25

-- 3D-Druck-Tween: Button senkt sich beim Drücken um 3px und federt per Back-Easing zurück
local PRESS_DEPTH = 3
local PRESS_TWEEN_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Ergonomischer Daumen-Bogen (Offsets von der unteren rechten Bildschirmecke @ Scale 1.0)
-- Entspricht exakt den Phase-3-Positionsvorgaben (Mittelpunkt-Angabe -> Kanten-Offset):
--   Angriff 68x68 @ (1, -95,  1, -165) -> rechte Kante 61px & untere Kante 131px vom Rand
--   Dash    58x58 @ (1, -170, 1, -145) -> rechte Kante 141px & untere Kante 116px vom Rand
--   Sprint  52x52 @ (1, -155, 1, -220) -> rechte Kante 129px & untere Kante 194px vom Rand
type ButtonLayout = {
	Size: number, -- Kantenlänge in Pixeln (@ Scale 1.0)
	RightInset: number, -- Abstand der rechten Buttonkante zum rechten Bildschirmrand
	BottomInset: number, -- Abstand der unteren Buttonkante zum unteren Bildschirmrand
}

local ATTACK_LAYOUT: ButtonLayout = { Size = 68, RightInset = 61, BottomInset = 131 }
local DASH_LAYOUT: ButtonLayout = { Size = 58, RightInset = 141, BottomInset = 116 }
local SPRINT_LAYOUT: ButtonLayout = { Size = 52, RightInset = 129, BottomInset = 194 }

-- Roblox-Standard-Sprungknopf: Roblox rendert seine Touch-Controls in zwei Größenklassen
-- (kleine Screens ~70px, Tablets ~120px). Der Sprungkopf hängt fest in der unteren rechten
-- Ecke – genau dort sitzt auch unser Cluster, deshalb reservieren wir diesen Bereich und
-- schieben die Gruppe bei Bedarf geschlossen nach oben (siehe computeLayout).
local JUMP_SMALL_MIN_DIMENSION = 500 -- min(Viewport.X, Viewport.Y) darunter = Smartphone
local JUMP_SMALL_SIZE = 70
local JUMP_SMALL_RIGHT_INSET = 25
local JUMP_SMALL_BOTTOM_INSET = 20
local JUMP_LARGE_SIZE = 120
local JUMP_LARGE_RIGHT_INSET = 50
local JUMP_LARGE_BOTTOM_INSET = 90
local JUMP_CLEARANCE = 18 -- Sicherheitsabstand zusätzlich zum Sprungkopf

-- Touch-Prompt-UI (ersetzt auf Touch-Geräten die winzige Welt-Prompt-Anzeige).
-- Der Abstand zum unteren Rand hält die HUD-Lebensanzeige (unten links) frei.
local PROMPT_BASE_WIDTH = 268
local PROMPT_BASE_HEIGHT = 66
local PROMPT_BOTTOM_INSET = 104

-- ==========================================
-- 2. CHECK-UI FARBWELT (Knallige Verläufe)
-- ==========================================
local COLORS = {
	-- ⚔️ Primärangriff: Karminrot/Orange
	AttackGradientTop = Color3.fromRGB(255, 96, 32),
	AttackGradientBottom = Color3.fromRGB(200, 0, 40),
	AttackBevel = Color3.fromRGB(120, 15, 15),
	AttackHighlight = Color3.fromRGB(255, 190, 150),
	AttackDamier = Color3.fromRGB(150, 0, 20),
	AttackEmojiFallback = "⚔️",

	-- ⚡ Combat-Dash: Cyan/Elektroblau
	DashGradientTop = Color3.fromRGB(0, 205, 255),
	DashGradientBottom = Color3.fromRGB(0, 120, 245),
	DashBevel = Color3.fromRGB(0, 62, 140),
	DashHighlight = Color3.fromRGB(180, 240, 255),
	DashDamier = Color3.fromRGB(0, 75, 150),
	DashEmojiFallback = "⚡",

	-- 🏃 Sprint: Schiefer (inaktiv) / Limettengrün (aktiv) / Grau (gesperrt)
	SprintIdleTop = Color3.fromRGB(46, 72, 84),
	SprintIdleBottom = Color3.fromRGB(26, 44, 52),
	SprintIdleBevel = Color3.fromRGB(14, 24, 30),
	SprintIdleDamier = Color3.fromRGB(30, 52, 62),
	SprintActiveTop = Color3.fromRGB(180, 255, 25),
	SprintActiveBottom = Color3.fromRGB(105, 225, 0),
	SprintActiveBevel = Color3.fromRGB(15, 120, 15),
	SprintActiveDamier = Color3.fromRGB(40, 160, 20),
	SprintLockedTop = Color3.fromRGB(120, 128, 136),
	SprintLockedBottom = Color3.fromRGB(72, 82, 96),
	SprintLockedBevel = Color3.fromRGB(40, 46, 54),
	SprintLockedDamier = Color3.fromRGB(60, 66, 74),
	SprintEmojiFallback = "🏃",

	-- Gemeinsame Farben
	Black = Color3.fromRGB(0, 0, 0),
	SprintIdleStroke = Color3.fromRGB(105, 225, 0),
	SprintLockedStroke = Color3.fromRGB(148, 160, 176),
	Countdown = Color3.fromRGB(255, 255, 255),

	-- Touch-Prompt (Gold/Bernstein aus der Check-UI "Skip"-Familie)
	PromptGradientTop = Color3.fromRGB(255, 208, 0),
	PromptGradientBottom = Color3.fromRGB(255, 140, 0),
	PromptBevel = Color3.fromRGB(153, 76, 0),
	PromptHighlight = Color3.fromRGB(255, 240, 160),
	PromptDamier = Color3.fromRGB(176, 96, 0),
}

-- HD-Icons aus der Check-UI Registry (1022 Icons) + Emoji-Fallback, falls ein Asset nicht lädt.
-- Hinweis: Die 3-Argument-Variante von CheckUIIcons.Get arbeitet mit den ROHEN Tabellen-Keys
-- (Unterstriche), nicht mit den FlatMap-Anzeigenamen ("Sword 1st Outline").
local ICONS = {
	Attack = CheckUIIcons.Get("Item", "Sword", "Sword_1st_Outline"),
	Dash = CheckUIIcons.Get("Main", "Lighting", "Lighting_1st_Outline"),
	Sprint = CheckUIIcons.Get("Item", "Shoe", "Yellow_Shoe_1st_Outline"),
	Lock = CheckUIIcons.Get("Item", "Lock", "Lock_White"),
	Prompt = CheckUIIcons.Get("UI", "Checkmark_Button", "Checkmark_Button_White"),
}

-- ==========================================
-- 3. TYPEN & ZUSTAND
-- ==========================================
type ButtonVisuals = {
	Kind: string,
	Button: ImageButton,
	Scale: UIScale, -- UIScale-Engine (Layout-Skalierung)
	IconScale: UIScale, -- eigener Icon-Pop beim Drücken
	Icon: ImageLabel,
	Emoji: TextLabel,
	Gradient: UIGradient,
	OuterStroke: UIStroke,
	InnerStroke: UIStroke,
	Bevel: Frame,
	Damier: ImageLabel,
	Mask: Frame,
	Countdown: TextLabel,
	LockBadge: ImageLabel,
	RestPosition: UDim2,
	ActiveInput: InputObject?,
	PressedTween: Tween?,
}

type Cluster = { Attack: ButtonVisuals, Dash: ButtonVisuals, Sprint: ButtonVisuals }

type ButtonPlacement = {
	Scale: number,
	RightInset: number,
	BottomInset: number,
	TopEdge: number,
}

type ComputedLayout = { Attack: ButtonPlacement, Dash: ButtonPlacement, Sprint: ButtonPlacement }

type PromptUi = {
	Root: ImageButton,
	Scale: UIScale,
	Gradient: UIGradient,
	Icon: ImageLabel,
	ObjectLabel: TextLabel,
	ActionLabel: TextLabel,
	HoldTrough: Frame,
	HoldFill: Frame,
	Flash: Frame,
}

local screenGui: ScreenGui? = nil
local buttons: Cluster? = nil
local promptUi: PromptUi? = nil

-- Hybrid-Geräte: Roblox schaltet seine Touch-Controls dynamisch ein/aus, wenn zwischen
-- Maus/Tastatur und Finger gewechselt wird. Wir folgen diesem Signal, aber erst nachdem
-- es sich mindestens einmal geändert hat -> auf echten Smartphones kann es nie ausblenden.
local hybridSignalObserved = false

-- Check-UI Menüs (Shop/Inventar/Infobox) verdecken das Cluster & das Touch-Prompt
local MENU_WINDOW_NAMES: { [string]: boolean } = {
	InventoryModal = true,
	ItemDetailModal = true,
	BlacksmithShopWindow = true,
}
local menuWindows: { [GuiObject]: RBXScriptConnection } = {}
local isMenuWindowVisible = false

-- Touch-Prompt-Zustand
local shownPrompts: { ProximityPrompt } = {}
local activePrompt: ProximityPrompt? = nil
local isHoldingPrompt = false
local holdStartClock = 0
local holdInputObject: InputObject? = nil
local promptDrainConnection: RBXScriptConnection? = nil

-- Dash-Cooldown-Visualisierung
local dashMaskTween: Tween? = nil
local dashCountdownConnection: RBXScriptConnection? = nil

-- Sprint-Puls (leuchtender Highlight-Stroke im aktiven Zustand)
local sprintPulseTween: Tween? = nil

-- ==========================================
-- 4. HILFSFUNKTIONEN
-- ==========================================

-- Aktuelle Viewport-Größe (mit sicherem Fallback, falls die Kamera kurz fehlt)
local function getViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

-- Roblox-Standard-Sprungknopf: Reservierter Bereich in der unteren rechten Ecke
-- (x/y = Abstand der linken bzw. unteren Sprungkopf-Kante von der unteren rechten Ecke)
local function computeJumpZone(viewport: Vector2): { x0: number, x1: number, y0: number, y1: number }
	local minDimension = math.min(viewport.X, viewport.Y)

	local size: number
	local rightInset: number
	local bottomInset: number
	if minDimension < JUMP_SMALL_MIN_DIMENSION then
		size = JUMP_SMALL_SIZE
		rightInset = JUMP_SMALL_RIGHT_INSET
		bottomInset = JUMP_SMALL_BOTTOM_INSET
	else
		size = JUMP_LARGE_SIZE
		rightInset = JUMP_LARGE_RIGHT_INSET
		bottomInset = JUMP_LARGE_BOTTOM_INSET
	end

	return {
		x0 = rightInset,
		x1 = rightInset + size,
		y0 = bottomInset,
		y1 = bottomInset + size,
	}
end

-- UIScale-Engine + Sprungkopf-Schutz: berechnet Skalierung und Endpositionen der Gruppe
local function computeLayout(viewport: Vector2): ComputedLayout
	-- 1. UIScale-Engine (Baseline 400px Höhe)
	local scale = math.clamp(viewport.Y / SCALE_BASELINE_HEIGHT, SCALE_MIN, SCALE_MAX)

	local function placementOf(base: ButtonLayout): ButtonPlacement
		return {
			Scale = scale,
			RightInset = base.RightInset * scale,
			BottomInset = base.BottomInset * scale,
			TopEdge = (base.BottomInset + base.Size) * scale,
		}
	end

	local attack = placementOf(ATTACK_LAYOUT)
	local dash = placementOf(DASH_LAYOUT)
	local sprint = placementOf(SPRINT_LAYOUT)

	-- 2. Sprungkopf-Schutz: Überlappt ein Button horizontal UND vertikal mit dem reservierten
	--    Sprungkopf-Bereich (untere rechte Ecke), schieben wir die ganze Gruppe nach oben.
	local jumpZone = computeJumpZone(viewport)
	local shift = 0
	for _, placement in { attack, dash, sprint } do
		local overlapsHorizontally = placement.RightInset < (jumpZone.x1 + JUMP_CLEARANCE)
		local overlapsVertically = placement.BottomInset < (jumpZone.y1 + JUMP_CLEARANCE)
		if overlapsHorizontally and overlapsVertically then
			local needed = (jumpZone.y1 + JUMP_CLEARANCE) - placement.BottomInset
			if needed > shift then
				shift = needed
			end
		end
	end

	if shift > 0 then
		attack.BottomInset += shift
		dash.BottomInset += shift
		sprint.BottomInset += shift
	end

	return { Attack = attack, Dash = dash, Sprint = sprint }
end

-- Erzeugt einen Farbverlauf (90°, oben -> unten) im Check-UI-Stil
local function makeGradient(parent: Instance, topColor: Color3, bottomColor: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "ButtonGradient"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new {
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	}
	gradient.Parent = parent
	return gradient
end

-- Setzt einen Farbverlauf (ohne Neuerzeugung) neu
local function setGradient(gradient: UIGradient, topColor: Color3, bottomColor: Color3)
	gradient.Color = ColorSequence.new {
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	}
end

-- Seamless Fading Damier (Check-UI Tenet: subtile Schachbrett-Textur)
local function makeDamier(parent: Instance, zIndex: number, color: Color3): ImageLabel
	local damier = Instance.new("ImageLabel")
	damier.Name = "Checkerboard"
	damier.Size = UDim2.new(1, 0, 1, 0)
	damier.Position = UDim2.new(0, 0, 0, 0)
	damier.BackgroundTransparency = 1
	damier.Image = CheckUITheme.Assets.Checkerboard
	damier.ScaleType = Enum.ScaleType.Tile
	damier.TileSize = UDim2.new(0, 18, 0, 18)
	damier.ImageColor3 = color
	damier.ImageTransparency = 0.3
	damier.ZIndex = zIndex
	damier.Parent = parent

	local damierGrad = Instance.new("UIGradient")
	damierGrad.Rotation = 90
	damierGrad.Transparency = NumberSequence.new {
		NumberSequenceKeypoint.new(0, 1.00),
		NumberSequenceKeypoint.new(0.30, 0.82),
		NumberSequenceKeypoint.new(0.70, 0.35),
		NumberSequenceKeypoint.new(1, 0.10),
	}
	damierGrad.Parent = damier

	return damier
end

-- Prüft, ob ein HD-Icon tatsächlich geladen wurde (Emoji-Fallback sonst)
local function bindIconFallback(state: ButtonVisuals)
	task.delay(1, function()
		if not state.Button.Parent then
			return
		end
		local ok, loaded = pcall(function()
			return state.Icon.IsLoaded
		end)
		if ok and loaded == true then
			return
		end
		-- Asset (noch) nicht geladen -> Emoji-Fallback zeigen
		state.Icon.Visible = false
		state.Emoji.Visible = true
	end)

	pcall(function()
		state.Icon:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			local ok, loaded = pcall(function()
				return state.Icon.IsLoaded
			end)
			if ok and loaded == true then
				state.Icon.Visible = true
				state.Emoji.Visible = false
			end
		end)
	end)
end

-- ==========================================
-- 5. BUTTON-BAU (Check-UI Standard)
-- ==========================================
local function createActionButton(props: {
	Kind: string,
	Name: string,
	Size: number,
	IconAsset: string,
	EmojiFallback: string,
	GradientTop: Color3,
	GradientBottom: Color3,
	BevelColor: Color3,
	HighlightColor: Color3,
	DamierColor: Color3,
	DamierTransparency: number?,
	TextSize: number?,
}): ButtonVisuals
	local size = props.Size

	local button = Instance.new("ImageButton")
	button.Name = props.Name
	button.Size = UDim2.fromOffset(size, size)
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -size, 1, -size)
	button.BackgroundColor3 = props.GradientBottom
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.ClipsDescendants = true
	button.ZIndex = MOBILE_GUI_DISPLAY_ORDER

	-- Comic-Runde Ecken (Check-UI 3D-Beveled-Optik)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.26, 0)
	corner.Parent = button

	-- Dicker schwarzer UIStroke (3.0px) – Check-UI Standard
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name = "OuterStroke"
	outerStroke.Color = COLORS.Black
	outerStroke.Thickness = 3.0
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Parent = button

	-- Knalliger Farbverlauf
	local gradient = makeGradient(button, props.GradientTop, props.GradientBottom)

	-- 3D-Bevel-Extrusion an der Unterseite (tastbarer Cartoon-Druck-Effekt)
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.Size = UDim2.new(1, 0, 0, 4)
	bevel.Position = UDim2.new(0, 0, 1, -4)
	bevel.BackgroundColor3 = props.BevelColor
	bevel.BorderSizePixel = 0
	bevel.ZIndex = button.ZIndex + 1
	bevel.Parent = button

	-- Innere Highlight-Kontur (Specular-Feeling)
	local innerHighlight = Instance.new("Frame")
	innerHighlight.Name = "InnerHighlight"
	innerHighlight.Size = UDim2.new(1, -5, 1, -5)
	innerHighlight.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerHighlight.AnchorPoint = Vector2.new(0.5, 0.5)
	innerHighlight.BackgroundTransparency = 1
	innerHighlight.BorderSizePixel = 0
	innerHighlight.ZIndex = button.ZIndex + 1
	innerHighlight.Parent = button

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Name = "InnerStroke"
	innerStroke.Color = props.HighlightColor
	innerStroke.Thickness = 1.6
	innerStroke.Transparency = 0.25
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = innerHighlight

	-- Damier-Textur
	local damier = makeDamier(button, button.ZIndex + 2, props.DamierColor)
	damier.ImageTransparency = props.DamierTransparency or 0.3

	-- HD-Icon (mit eigenem UIScale für den Icon-Pop)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(0.58, 0.58)
	icon.Position = UDim2.new(0.5, 0, 0.5, -1)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = props.IconAsset
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = button.ZIndex + 3
	icon.Parent = button

	local iconScale = Instance.new("UIScale")
	iconScale.Name = "IconScale"
	iconScale.Scale = 1
	iconScale.Parent = icon

	-- Emoji-Fallback (GothamBlack + schwarze Kontur), falls das HD-Asset nicht lädt
	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.Size = UDim2.new(1, 0, 1, -2)
	emoji.Position = UDim2.new(0.5, 0, 0.5, -1)
	emoji.AnchorPoint = Vector2.new(0.5, 0.5)
	emoji.BackgroundTransparency = 1
	emoji.Text = props.EmojiFallback
	emoji.Font = CheckUITheme.Typography.Font
	emoji.TextSize = props.TextSize or math.floor(size * 0.42)
	emoji.TextColor3 = Color3.fromRGB(255, 255, 255)
	emoji.Visible = false
	emoji.ZIndex = button.ZIndex + 3
	emoji.Parent = button

	local emojiStroke = Instance.new("UIStroke")
	emojiStroke.Color = COLORS.Black
	emojiStroke.Thickness = 2.0
	emojiStroke.Parent = emoji

	-- Cooldown-Maske (dunkle, halbtransparente Verdunklung) + Countdown-Text
	local mask = Instance.new("Frame")
	mask.Name = "CooldownMask"
	mask.AnchorPoint = Vector2.new(0, 1)
	mask.Position = UDim2.new(0, 0, 1, 0)
	mask.Size = UDim2.new(1, 0, 1, 0)
	mask.BackgroundColor3 = COLORS.Black
	mask.BackgroundTransparency = 0.4
	mask.BorderSizePixel = 0
	mask.Visible = false
	mask.ZIndex = button.ZIndex + 4
	mask.Parent = button

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.Size = UDim2.new(1, 0, 1, 0)
	countdown.Position = UDim2.new(0.5, 0, 0.5, 0)
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.BackgroundTransparency = 1
	countdown.Text = ""
	countdown.TextColor3 = COLORS.Countdown
	countdown.Font = CheckUITheme.Typography.Font
	countdown.TextSize = math.floor(size * 0.3)
	countdown.Visible = false
	countdown.ZIndex = button.ZIndex + 5
	countdown.Parent = button

	local countdownStroke = Instance.new("UIStroke")
	countdownStroke.Color = COLORS.Black
	countdownStroke.Thickness = 2.4
	countdownStroke.Parent = countdown

	-- Schloss-Symbol (nur im gesperrten Walk-of-Shame-Zustand sichtbar)
	local lockBadge = Instance.new("ImageLabel")
	lockBadge.Name = "LockBadge"
	lockBadge.Size = UDim2.fromOffset(math.floor(size * 0.42), math.floor(size * 0.42))
	lockBadge.Position = UDim2.new(1, -4, 0, 4)
	lockBadge.AnchorPoint = Vector2.new(1, 0)
	lockBadge.BackgroundTransparency = 1
	lockBadge.Image = ICONS.Lock
	lockBadge.ScaleType = Enum.ScaleType.Fit
	lockBadge.Visible = false
	lockBadge.ZIndex = button.ZIndex + 6
	lockBadge.Parent = button

	-- UIScale-Engine (Layout-Skalierung) – EIN UIScale pro Objekt
	local scale = Instance.new("UIScale")
	scale.Name = "ButtonScale"
	scale.Scale = 1
	scale.Parent = button

	button.Parent = screenGui

	local state: ButtonVisuals = {
		Kind = props.Kind,
		Button = button,
		Scale = scale,
		IconScale = iconScale,
		Icon = icon,
		Emoji = emoji,
		Gradient = gradient,
		OuterStroke = outerStroke,
		InnerStroke = innerStroke,
		Bevel = bevel,
		Damier = damier,
		Mask = mask,
		Countdown = countdown,
		LockBadge = lockBadge,
		RestPosition = button.Position,
		ActiveInput = nil,
		PressedTween = nil,
	}

	bindIconFallback(state)
	return state
end

-- 3D-Druck: Button senkt sich um 3px, das Bevel flacht ab, das Icon poppt kurz auf
local function playPressDown(state: ButtonVisuals)
	local rest = state.RestPosition
	if state.PressedTween then
		state.PressedTween:Cancel()
	end

	state.PressedTween = TweenService:Create(
		state.Button,
		PRESS_TWEEN_INFO,
		{ Position = rest + UDim2.fromOffset(0, PRESS_DEPTH) }
	)
	state.PressedTween:Play()

	TweenService:Create(
		state.Bevel,
		TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1) }
	):Play()

	TweenService:Create(
		state.IconScale,
		TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1.12 }
	):Play()
end

-- Federnder Rückstoß (Back-Easing) beim Loslassen
local function playPressRelease(state: ButtonVisuals)
	if state.PressedTween then
		state.PressedTween:Cancel()
		state.PressedTween = nil
	end

	TweenService:Create(state.Button, RELEASE_TWEEN_INFO, { Position = state.RestPosition }):Play()
	TweenService:Create(
		state.Bevel,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4) }
	):Play()
	TweenService:Create(
		state.IconScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

-- "Blockiert"-Feedback (z. B. Dash noch im Cooldown): kurzer seitlicher Ruck
local function playDeniedFeedback(state: ButtonVisuals)
	local rest = state.RestPosition
	task.spawn(function()
		for _ = 1, 2 do
			TweenService:Create(state.Button, TweenInfo.new(0.045, Enum.EasingStyle.Linear), {
				Position = rest + UDim2.fromOffset(5, PRESS_DEPTH),
			}):Play()
			task.wait(0.05)
			TweenService:Create(state.Button, TweenInfo.new(0.045, Enum.EasingStyle.Linear), {
				Position = rest + UDim2.fromOffset(0, PRESS_DEPTH),
			}):Play()
			task.wait(0.05)
		end
		TweenService:Create(state.Button, RELEASE_TWEEN_INFO, { Position = state.RestPosition }):Play()
	end)
end

-- ==========================================
-- 6. DASH-COOLDOWN-VISUALISIERUNG (Maske + Countdown)
-- ==========================================
local function stopDashCooldownVisual()
	if dashCountdownConnection then
		dashCountdownConnection:Disconnect()
		dashCountdownConnection = nil
	end
	if dashMaskTween then
		dashMaskTween:Cancel()
		dashMaskTween = nil
	end

	local cluster = buttons
	if not cluster then
		return
	end
	cluster.Dash.Mask.Visible = false
	cluster.Dash.Countdown.Visible = false
	cluster.Dash.Icon.ImageTransparency = 0
end

local function startDashCooldownVisual()
	local cluster = buttons
	if not cluster then
		return
	end

	local state = cluster.Dash
	local duration = CombatController.GetDashCooldownDuration()
	local remaining = CombatController.GetDashCooldownProgress()

	stopDashCooldownVisual()

	if remaining <= 0 then
		return
	end

	-- Dunkle, halbtransparente Maske: startet voll bedeckt und klingt von oben nach unten ab
	state.Mask.Visible = true
	state.Mask.Size = UDim2.new(1, 0, remaining, 0)
	state.Countdown.Visible = true
	state.Countdown.Text = string.format("%.1fs", remaining * duration)
	state.Icon.ImageTransparency = 0.45

	dashMaskTween = TweenService:Create(
		state.Mask,
		TweenInfo.new(remaining * duration, Enum.EasingStyle.Linear),
		{ Size = UDim2.new(1, 0, 0, 0) }
	)
	dashMaskTween:Play()

	dashCountdownConnection = RunService.RenderStepped:Connect(function()
		local progress = CombatController.GetDashCooldownProgress()
		if progress <= 0 then
			stopDashCooldownVisual()
			return
		end

		-- Nur der Text-Countdown wird pro Frame aktualisiert; die Maske übernimmt der Tween
		local activeButtons = buttons
		if activeButtons then
			activeButtons.Dash.Countdown.Text = string.format("%.1fs", progress * duration)
		end
	end)
end

-- ==========================================
-- 7. SPRINT-ZUSTAND (Inaktiv / Aktiv / Gesperrt)
-- ==========================================
local function stopSprintPulse(state: ButtonVisuals)
	if sprintPulseTween then
		sprintPulseTween:Cancel()
		sprintPulseTween = nil
	end
	state.InnerStroke.Transparency = 0.25
	state.InnerStroke.Thickness = 1.6
end

local function applySprintState(isSprinting: boolean, isLocked: boolean)
	local cluster = buttons
	if not cluster then
		return
	end

	local state = cluster.Sprint

	if isLocked then
		-- Walk of Shame: ausgegraut + Schloss-Symbol, Eingaben werden ignoriert
		stopSprintPulse(state)
		setGradient(state.Gradient, COLORS.SprintLockedTop, COLORS.SprintLockedBottom)
		state.Button.BackgroundColor3 = COLORS.SprintLockedBottom
		state.Bevel.BackgroundColor3 = COLORS.SprintLockedBevel
		state.Damier.ImageColor3 = COLORS.SprintLockedDamier
		state.InnerStroke.Color = COLORS.SprintLockedStroke
		state.InnerStroke.Transparency = 0.45
		state.Icon.ImageTransparency = 0.55
		state.Emoji.TextTransparency = 0.55
		state.LockBadge.Visible = true
	elseif isSprinting then
		-- Aktiv: leuchtendes Limettengrün + pulsierender Highlight-Stroke
		setGradient(state.Gradient, COLORS.SprintActiveTop, COLORS.SprintActiveBottom)
		state.Button.BackgroundColor3 = COLORS.SprintActiveBottom
		state.Bevel.BackgroundColor3 = COLORS.SprintActiveBevel
		state.Damier.ImageColor3 = COLORS.SprintActiveDamier
		state.InnerStroke.Color = Color3.fromRGB(235, 255, 130)
		state.InnerStroke.Transparency = 0
		state.Icon.ImageTransparency = 0
		state.Emoji.TextTransparency = 0
		state.LockBadge.Visible = false

		stopSprintPulse(state)
		sprintPulseTween = TweenService:Create(
			state.InnerStroke,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.65, Thickness = 3.4 }
		)
		sprintPulseTween:Play()
	else
		-- Inaktiv: dunkler Schiefer-Hintergrund mit dezent grünem Rand
		stopSprintPulse(state)
		setGradient(state.Gradient, COLORS.SprintIdleTop, COLORS.SprintIdleBottom)
		state.Button.BackgroundColor3 = COLORS.SprintIdleBottom
		state.Bevel.BackgroundColor3 = COLORS.SprintIdleBevel
		state.Damier.ImageColor3 = COLORS.SprintIdleDamier
		state.InnerStroke.Color = COLORS.SprintIdleStroke
		state.InnerStroke.Transparency = 0.35
		state.Icon.ImageTransparency = 0
		state.Emoji.TextTransparency = 0
		state.LockBadge.Visible = false
	end
end

-- ==========================================
-- 8. SICHTBARKEIT (Plattform, Hybrid-Geräte & Menü-Überdeckung)
-- ==========================================
local function isTouchControlsActive(): boolean
	-- Erst nach dem ersten echten Umschalten des Roblox-Touch-Controls-Status folgen wir dem
	-- Signal (Hybrid-Geräte). Vorher bleibt das Cluster immer sichtbar -> Smartphone-sicher.
	if not hybridSignalObserved then
		return true
	end

	local ok, value = pcall(function()
		return GuiService.TouchControlsEnabled
	end)
	if ok and typeof(value) == "boolean" then
		return value
	end
	return true
end

local function updateVisibility()
	local visible = isTouchControlsActive() and not isMenuWindowVisible

	if screenGui then
		screenGui.Enabled = visible
	end
	if promptUi then
		promptUi.Root.Visible = visible and (activePrompt ~= nil)
	end
end

local function refreshMenuWindowState()
	local anyVisible = false
	for window in pairs(menuWindows) do
		if window.Visible then
			anyVisible = true
			break
		end
	end
	if anyVisible ~= isMenuWindowVisible then
		isMenuWindowVisible = anyVisible

		-- Menü öffnet sich während eines Halte-Prompts -> Halten sauber abbrechen
		if anyVisible and isHoldingPrompt then
			local prompt = activePrompt
			if prompt then
				pcall(function()
					prompt:InputHoldEnd()
				end)
			end
			isHoldingPrompt = false
			holdInputObject = nil
		end

		updateVisibility()
	end
end

local function registerMenuWindow(candidate: Instance)
	if not candidate:IsA("GuiObject") then
		return
	end
	if not MENU_WINDOW_NAMES[candidate.Name] then
		return
	end

	local window = candidate :: GuiObject
	if menuWindows[window] then
		return
	end

	local connection = window:GetPropertyChangedSignal("Visible"):Connect(function()
		refreshMenuWindowState()
	end)
	menuWindows[window] = connection

	-- Sorgt dafür, dass die Gruppierung der Buttons möglichst ohne Flackern geschieht,
	-- wenn ein Fenster entfernt wird
	window.Destroying:Once(function()
		local stored = menuWindows[window]
		if stored then
			stored:Disconnect()
		end
		menuWindows[window] = nil
		refreshMenuWindowState()
	end)

	refreshMenuWindowState()
end

local function hookMenuWindows()
	-- Bestehende Check-UI Fenster (Shop, Inventar, Infobox) beobachten ...
	for _, descendant in PlayerGui:GetDescendants() do
		registerMenuWindow(descendant)
	end

	-- ... und alle, die später erstellt werden (z. B. wenn der Shop zum ersten Mal öffnet)
	PlayerGui.DescendantAdded:Connect(registerMenuWindow)
end

-- ==========================================
-- 9. TOUCH-OPTIMIERTE PROXIMITYPROMPTS
-- ==========================================
local function releasePromptHold()
	if not isHoldingPrompt then
		return
	end

	local prompt = activePrompt
	if prompt then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end

	isHoldingPrompt = false
	holdInputObject = nil

	if promptUi then
		promptUi.HoldFill.Size = UDim2.new(0, 0, 1, 0)
	end
end

local function renderActivePrompt()
	local ui = promptUi
	if not ui then
		return
	end

	local prompt = activePrompt
	if not prompt then
		ui.Root.Visible = false
		releasePromptHold()
		return
	end

	ui.ObjectLabel.Text = prompt.ObjectText
	ui.ActionLabel.Text = prompt.ActionText
	ui.HoldTrough.Visible = prompt.HoldDuration > 0
	ui.HoldFill.Size = UDim2.new(0, 0, 1, 0)
	ui.Root.Visible = not isMenuWindowVisible and isTouchControlsActive()

	-- Pop-in Animation (wächst vom unteren Rand nach oben auf)
	ui.Root.Size = UDim2.fromOffset(PROMPT_BASE_WIDTH, math.floor(PROMPT_BASE_HEIGHT * 0.8))
	TweenService:Create(
		ui.Root,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(PROMPT_BASE_WIDTH, PROMPT_BASE_HEIGHT) }
	):Play()
end

local function setActivePrompt(prompt: ProximityPrompt?)
	activePrompt = prompt
	renderActivePrompt()
end

local function removeShownPrompt(prompt: ProximityPrompt)
	local index = table.find(shownPrompts, prompt)
	if index then
		table.remove(shownPrompts, index)
	end

	-- Roblox-Standard-Prompt-Anzeige wiederherstellen (falls unser UI nicht greift)
	pcall(function()
		if prompt.Parent and prompt.Style == Enum.ProximityPromptStyle.Custom then
			prompt.Style = Enum.ProximityPromptStyle.Default
		end
	end)

	if activePrompt == prompt then
		releasePromptHold()
		setActivePrompt(shownPrompts[#shownPrompts])
	else
		renderActivePrompt()
	end
end

local function hookPrompts()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		-- Sicherheitsnetz: wichtige Weltobjekte (Amboss, Sockel, Altar ...) müssen auf
		-- Touch-Geräten per Daumentipp antippbar sein
		if not prompt.ClickablePrompt then
			prompt.ClickablePrompt = true
		end

		-- Winzige Welt-Prompt-Anzeige durch unser großes Touch-Ziel ersetzen
		pcall(function()
			prompt.Style = Enum.ProximityPromptStyle.Custom
		end)

		if not table.find(shownPrompts, prompt) then
			table.insert(shownPrompts, prompt)
		end
		setActivePrompt(prompt)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		removeShownPrompt(prompt)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local ui = promptUi
		if not ui or activePrompt ~= prompt then
			return
		end
		-- Bestätigungs-Blitz
		ui.Flash.BackgroundTransparency = 0.55
		TweenService:Create(
			ui.Flash,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
end

local function createPromptUi()
	local root = Instance.new("ImageButton")
	root.Name = "TouchPromptButton"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -PROMPT_BOTTOM_INSET)
	root.Size = UDim2.fromOffset(PROMPT_BASE_WIDTH, PROMPT_BASE_HEIGHT)
	root.BackgroundColor3 = COLORS.PromptGradientBottom
	root.BorderSizePixel = 0
	root.AutoButtonColor = false
	root.ClipsDescendants = true
	root.Visible = false
	root.ZIndex = MOBILE_GUI_DISPLAY_ORDER + 20
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = root

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name = "OuterStroke"
	outerStroke.Color = COLORS.Black
	outerStroke.Thickness = 3.0
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Parent = root

	local gradient = makeGradient(root, COLORS.PromptGradientTop, COLORS.PromptGradientBottom)

	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.Size = UDim2.new(1, 0, 0, 4)
	bevel.Position = UDim2.new(0, 0, 1, -4)
	bevel.BackgroundColor3 = COLORS.PromptBevel
	bevel.BorderSizePixel = 0
	bevel.ZIndex = root.ZIndex + 1
	bevel.Parent = root

	local innerHighlight = Instance.new("Frame")
	innerHighlight.Name = "InnerHighlight"
	innerHighlight.Size = UDim2.new(1, -6, 1, -6)
	innerHighlight.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerHighlight.AnchorPoint = Vector2.new(0.5, 0.5)
	innerHighlight.BackgroundTransparency = 1
	innerHighlight.BorderSizePixel = 0
	innerHighlight.ZIndex = root.ZIndex + 1
	innerHighlight.Parent = root

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = COLORS.PromptHighlight
	innerStroke.Thickness = 1.4
	innerStroke.Transparency = 0.15
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = innerHighlight

	makeDamier(root, root.ZIndex + 2, COLORS.PromptDamier).ImageTransparency = 0.45

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(34, 34)
	icon.Position = UDim2.new(0, 14, 0.5, -2)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = ICONS.Prompt
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = root.ZIndex + 3
	icon.Parent = root

	local objectLabel = Instance.new("TextLabel")
	objectLabel.Name = "ObjectLabel"
	objectLabel.Size = UDim2.new(1, -76, 0, 16)
	objectLabel.Position = UDim2.new(0, 58, 0, 10)
	objectLabel.BackgroundTransparency = 1
	objectLabel.TextColor3 = Color3.fromRGB(255, 250, 220)
	objectLabel.Font = CheckUITheme.Typography.Font
	objectLabel.TextSize = 12
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectLabel.TextTruncate = Enum.TextTruncate.AtEnd
	objectLabel.Text = ""
	objectLabel.ZIndex = root.ZIndex + 3
	objectLabel.Parent = root

	local objectStroke = Instance.new("UIStroke")
	objectStroke.Color = COLORS.Black
	objectStroke.Thickness = 2.0
	objectStroke.Parent = objectLabel

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -76, 0, 24)
	actionLabel.Position = UDim2.new(0, 58, 0, 26)
	actionLabel.BackgroundTransparency = 1
	actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionLabel.Font = CheckUITheme.Typography.Font
	actionLabel.TextSize = 17
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	actionLabel.Text = ""
	actionLabel.ZIndex = root.ZIndex + 3
	actionLabel.Parent = root

	local actionStroke = Instance.new("UIStroke")
	actionStroke.Color = COLORS.Black
	actionStroke.Thickness = 2.6
	actionStroke.Parent = actionLabel

	-- Halte-Fortschrittsbalken (z. B. für den 3.5s Seelenkern-Diebstahl)
	local holdTrough = Instance.new("Frame")
	holdTrough.Name = "HoldTrough"
	holdTrough.Size = UDim2.new(1, -24, 0, 6)
	holdTrough.Position = UDim2.new(0, 12, 1, -12)
	holdTrough.BackgroundColor3 = Color3.fromRGB(20, 30, 36)
	holdTrough.BorderSizePixel = 0
	holdTrough.Visible = false
	holdTrough.ZIndex = root.ZIndex + 3
	holdTrough.Parent = root

	local holdTroughCorner = Instance.new("UICorner")
	holdTroughCorner.CornerRadius = UDim.new(0, 3)
	holdTroughCorner.Parent = holdTrough

	local holdFill = Instance.new("Frame")
	holdFill.Name = "HoldFill"
	holdFill.Size = UDim2.new(0, 0, 1, 0)
	holdFill.BackgroundColor3 = Color3.fromRGB(105, 225, 0)
	holdFill.BorderSizePixel = 0
	holdFill.ZIndex = root.ZIndex + 4
	holdFill.Parent = holdTrough

	local holdFillCorner = Instance.new("UICorner")
	holdFillCorner.CornerRadius = UDim.new(0, 3)
	holdFillCorner.Parent = holdFill

	-- Bestätigungs-Blitz
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = root.ZIndex + 6
	flash.Parent = root

	-- UIScale-Engine (Geräte-Skalierung)
	local scale = Instance.new("UIScale")
	scale.Name = "ButtonScale"
	scale.Scale = 1
	scale.Parent = root

	promptUi = {
		Root = root,
		Scale = scale,
		Gradient = gradient,
		Icon = icon,
		ObjectLabel = objectLabel,
		ActionLabel = actionLabel,
		HoldTrough = holdTrough,
		HoldFill = holdFill,
		Flash = flash,
	}
end

-- Halte-Fortschritt aktualisieren, solange der Daumen auf dem Prompt-Button liegt
local function startPromptHoldProgress(prompt: ProximityPrompt)
	if promptDrainConnection then
		promptDrainConnection:Disconnect()
		promptDrainConnection = nil
	end

	local duration = prompt.HoldDuration
	if duration <= 0 then
		return
	end

	promptDrainConnection = RunService.RenderStepped:Connect(function()
		local ui = promptUi
		if not ui or not isHoldingPrompt or not activePrompt then
			if promptDrainConnection then
				promptDrainConnection:Disconnect()
				promptDrainConnection = nil
			end
			return
		end

		local elapsed = os.clock() - holdStartClock
		local progress = math.clamp(elapsed / math.max(duration, 0.01), 0, 1)
		ui.HoldFill.Size = UDim2.new(progress, 0, 1, 0)

		if progress >= 1 then
			isHoldingPrompt = false
			if promptDrainConnection then
				promptDrainConnection:Disconnect()
				promptDrainConnection = nil
			end
		end
	end)
end

local function onPromptTouchBegan(input: InputObject)
	local prompt = activePrompt
	if not prompt or isHoldingPrompt then
		return
	end
	if isMenuWindowVisible then
		return
	end

	isHoldingPrompt = true
	holdInputObject = input
	holdStartClock = os.clock()

	pcall(function()
		if prompt.ClickablePrompt then
			prompt:InputHoldBegin()
		end
	end)

	local ui = promptUi
	if ui then
		ui.HoldTrough.Visible = prompt.HoldDuration > 0
		ui.HoldFill.Size = UDim2.new(0, 0, 1, 0)
	end
	startPromptHoldProgress(prompt)
end

local function onPromptTouchEnded(input: InputObject)
	if not isHoldingPrompt then
		return
	end
	if holdInputObject ~= nil and input ~= holdInputObject then
		return
	end

	local prompt = activePrompt
	if prompt then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end

	isHoldingPrompt = false
	holdInputObject = nil

	if promptDrainConnection then
		promptDrainConnection:Disconnect()
		promptDrainConnection = nil
	end

	local ui = promptUi
	if ui then
		ui.HoldFill.Size = UDim2.new(0, 0, 1, 0)
	end
end

-- ==========================================
-- 10. LAYOUT ANWENDEN (UIScale-Engine + Sprungkopf-Schutz)
-- ==========================================
local function applyLayout()
	if not buttons then
		return
	end

	local viewport = getViewportSize()
	local layout = computeLayout(viewport)

	local function place(state: ButtonVisuals, placement: ButtonPlacement)
		if state.PressedTween then
			state.PressedTween:Cancel()
			state.PressedTween = nil
		end
		state.Scale.Scale = placement.Scale
		state.RestPosition = UDim2.new(1, -placement.RightInset, 1, -placement.BottomInset)
		state.Button.Position = state.RestPosition
	end

	place(buttons.Attack, layout.Attack)
	place(buttons.Dash, layout.Dash)
	place(buttons.Sprint, layout.Sprint)

	if promptUi then
		local scale = math.clamp(viewport.Y / SCALE_BASELINE_HEIGHT, SCALE_MIN, SCALE_MAX)
		promptUi.Scale.Scale = scale
		promptUi.Root.Position = UDim2.new(0.5, 0, 1, -PROMPT_BOTTOM_INSET * scale)
	end
end

local function bindViewportListener()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
end

-- ==========================================
-- 11. EINGABE-VERARBEITUNG (Touch-Eingaben der Buttons)
-- ==========================================
local function onAttackPressed()
	-- Nahkampf: Cooldown-Check, Klingen-Whoosh, Slash-Trail & AttackIntent:FireServer()
	CombatController.TriggerAttack()
end

local function onDashPressed()
	local cluster = buttons
	if not cluster then
		return
	end

	-- Bei noch aktivem Cooldown wird die Eingabe ignoriert (nur dezentes Ruck-Feedback)
	if not CombatController.IsDashReady() then
		playDeniedFeedback(cluster.Dash)
		return
	end

	if CombatController.TriggerDash() then
		startDashCooldownVisual()
	else
		playDeniedFeedback(cluster.Dash)
	end
end

local function onSprintPressed()
	local cluster = buttons
	if not cluster then
		return
	end

	if MovementController.IsSprintLocked() then
		-- Walk of Shame: gesperrt (Lock-Badge ist bereits sichtbar)
		playDeniedFeedback(cluster.Sprint)
		return
	end

	MovementController.ToggleSprint()
end

local function bindButtonInput(state: ButtonVisuals, onPressed: () -> ())
	state.Button.InputBegan:Connect(function(input: InputObject)
		if not screenGui or not screenGui.Enabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		state.ActiveInput = input
		playPressDown(state)
		onPressed()
	end)

	state.Button.InputEnded:Connect(function(input: InputObject)
		if state.ActiveInput ~= nil and input ~= state.ActiveInput then
			return
		end
		state.ActiveInput = nil
		playPressRelease(state)
	end)
end

-- Globales Sicherheitsnetz: Endet ein Touch außerhalb des Buttons (Finger rutscht weg),
-- setzen wir den Druck-Zustand garantiert zurück.
local function bindGlobalInputRelease()
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local cluster = buttons
		if cluster then
			for _, state in { cluster.Attack, cluster.Dash, cluster.Sprint } do
				if state.ActiveInput == input then
					state.ActiveInput = nil
					playPressRelease(state)
				end
			end
		end

		onPromptTouchEnded(input)
	end)
end

-- ==========================================
-- 12. AUFBAU & INITIALISIERUNG
-- ==========================================
local function createScreenGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = SCREEN_GUI_NAME
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = MOBILE_GUI_DISPLAY_ORDER
	gui.Enabled = false

	-- Notch-/Home-Indicator-sichere Ränder (revidiert IgnoreGuiInset, falls verfügbar)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)

	gui.Parent = PlayerGui
	screenGui = gui
end

local function createActionCluster()
	if not screenGui then
		return
	end

	local attackState = createActionButton({
		Kind = "Attack",
		Name = "MobileAttackButton",
		Size = ATTACK_LAYOUT.Size,
		IconAsset = ICONS.Attack,
		EmojiFallback = COLORS.AttackEmojiFallback,
		GradientTop = COLORS.AttackGradientTop,
		GradientBottom = COLORS.AttackGradientBottom,
		BevelColor = COLORS.AttackBevel,
		HighlightColor = COLORS.AttackHighlight,
		DamierColor = COLORS.AttackDamier,
	})

	local dashState = createActionButton({
		Kind = "Dash",
		Name = "MobileDashButton",
		Size = DASH_LAYOUT.Size,
		IconAsset = ICONS.Dash,
		EmojiFallback = COLORS.DashEmojiFallback,
		GradientTop = COLORS.DashGradientTop,
		GradientBottom = COLORS.DashGradientBottom,
		BevelColor = COLORS.DashBevel,
		HighlightColor = COLORS.DashHighlight,
		DamierColor = COLORS.DashDamier,
	})

	local sprintState = createActionButton({
		Kind = "Sprint",
		Name = "MobileSprintButton",
		Size = SPRINT_LAYOUT.Size,
		IconAsset = ICONS.Sprint,
		EmojiFallback = COLORS.SprintEmojiFallback,
		GradientTop = COLORS.SprintIdleTop,
		GradientBottom = COLORS.SprintIdleBottom,
		BevelColor = COLORS.SprintIdleBevel,
		HighlightColor = COLORS.SprintIdleStroke,
		DamierColor = COLORS.SprintIdleDamier,
	})

	buttons = {
		Attack = attackState,
		Dash = dashState,
		Sprint = sprintState,
	}

	bindButtonInput(attackState, onAttackPressed)
	bindButtonInput(dashState, onDashPressed)
	bindButtonInput(sprintState, onSprintPressed)

	-- Sprint-Visuals an den echten Controller-Zustand koppeln (inkl. Walk-of-Shame-Sperre)
	MovementController.ObserveSprintState(function(isSprinting: boolean, isLocked: boolean)
		applySprintState(isSprinting, isLocked)
	end)

	applyLayout()
end

local function bindTouchControlsChanged()
	pcall(function()
		GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(function()
			hybridSignalObserved = true
			updateVisibility()
		end)
	end)
end

local function onCharacterAdded()
	-- Frischer Charakter: Cooldown-Anzeige & Sprint-Zustand zurücksetzen
	stopDashCooldownVisual()

	local cluster = buttons
	if cluster then
		applySprintState(MovementController.IsSprinting(), MovementController.IsSprintLocked())
		for _, state in { cluster.Attack, cluster.Dash, cluster.Sprint } do
			state.ActiveInput = nil
			playPressRelease(state)
		end
	end

	releasePromptHold()
	updateVisibility()
end

function MobileControlsController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Plattform-Erkennung: Ohne Touchscreen wird KEIN Touch-UI erstellt!
	-- Auf PC (Maus & Tastatur) bleiben Steuerung (Linksklick, F, Q, Shift) & HUD unverändert.
	if not UserInputService.TouchEnabled then
		print("[MobileControlsController] Kein Touchscreen erkannt – Mobile-UI wird nicht erstellt (PC/Desktop unberührt).")
		return
	end

	createScreenGui()
	createActionCluster()
	createPromptUi()

	bindViewportListener()
	bindGlobalInputRelease()
	bindTouchControlsChanged()
	hookMenuWindows()
	hookPrompts()

	-- Prompt-Button: Halten beginnt mit dem Daumen, endet beim Loslassen
	if promptUi then
		promptUi.Root.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			onPromptTouchBegan(input)

			-- 3D-Druck-Feedback
			local ui = promptUi
			if ui then
				TweenService:Create(
					ui.Root,
					TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(PROMPT_BASE_WIDTH, PROMPT_BASE_HEIGHT - 3) }
				):Play()
			end
		end)

		promptUi.Root.InputEnded:Connect(function(input: InputObject)
			onPromptTouchEnded(input)
			local ui = promptUi
			if ui then
				TweenService:Create(
					ui.Root,
					TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(PROMPT_BASE_WIDTH, PROMPT_BASE_HEIGHT) }
				):Play()
			end
		end)
	end

	if LocalPlayer.Character then
		onCharacterAdded()
	end
	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

	updateVisibility()

	print(
		string.format(
			"[MobileControlsController] Initialisiert: Touch-UI aktiv (%s), UIScale-Engine (0.85 – 1.25, Baseline 400px), Sprungkopf-Schutz, Angriff/Dash/Sprint-Cluster & Touch-Prompts aktiv.",
			SCREEN_GUI_NAME
		)
	)
end

return MobileControlsController
