--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Shared Abhängigkeiten
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local BossConfigModule = ConfigFolder:WaitForChild("BossConfig") :: ModuleScript
local BossConfig = require(BossConfigModule)

-- Server Abhängigkeiten
local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

local RaidService = nil
local function getRaidService(): any
	if not RaidService then
		local mod = Services:WaitForChild("RaidService") :: ModuleScript
		RaidService = require(mod)
	end
	return RaidService
end

local DefenseService = nil
local function getDefenseService(): any
	if not DefenseService then
		local mod = Services:WaitForChild("DefenseService") :: ModuleScript
		DefenseService = require(mod)
	end
	return DefenseService
end

-- Events vorbereiten
local function getOrCreateEventsFolder(): Folder
	local events = Shared:FindFirstChild("Events")
	if not events then
		local newEvents = Instance.new("Folder")
		newEvents.Name = "Events"
		newEvents.Parent = Shared
		return newEvents
	end
	return events :: Folder
end

local function getOrCreateRemoteEvent(parent: Folder, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = name
	newRemote.Parent = parent
	return newRemote
end

local EventsFolder = getOrCreateEventsFolder()
local GoldUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "GoldUpdated")
local NotificationEvent = getOrCreateRemoteEvent(EventsFolder, "ShowNotification")
local PlotStatusUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "PlotStatusUpdated")
local ClaimPlotIntentEvent = getOrCreateRemoteEvent(EventsFolder, "ClaimPlotIntent")
local RequestPlotStatusEvent = getOrCreateRemoteEvent(EventsFolder, "RequestPlotStatus")

local function notifyPlayer(player: Player, message: string, isError: boolean?)
	NotificationEvent:FireClient(player, message, isError or false)
end

local PlotService = {}

local PlayerPlots: { [Player]: Model } = {}
local isInitialized = false

function PlotService.GetPlayerPlot(player: Player): Model?
	return PlayerPlots[player]
end

-- Erstellt einen visuellen Text-Indikator
local function createBillboard(parent: Instance, text: string, offset: Vector3): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlotInfo"
	billboard.Size = UDim2.new(0, 160, 0, 40)
	billboard.StudsOffset = offset
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(24, 30, 34)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.4
	stroke.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	return billboard
end

-- Liefert den Haupt-BasePart eines Sockels (egal ob Part, MeshPart oder Model)
local function getPedestalRootPart(pedestal: Instance?): BasePart?
	if not pedestal then
		return nil
	end
	if pedestal:IsA("BasePart") then
		return pedestal
	elseif pedestal:IsA("Model") then
		return pedestal.PrimaryPart or (pedestal:FindFirstChildWhichIsA("BasePart") :: BasePart?)
	end
	return nil
end

-- Sucht nach einem 3D-Sockel-Modell (z.B. aus Blender importiertes DungeonPedestal)
local function getCustomPedestalTemplate(): Instance?
	local sharedAssets = Shared:FindFirstChild("Assets")
	if sharedAssets then
		local models = sharedAssets:FindFirstChild("Models")
		if models then
			local template = models:FindFirstChild("DungeonPedestal")
			if template then
				return template
			end
		end
	end
	local repTemplate = ReplicatedStorage:FindFirstChild("DungeonPedestal")
	if repTemplate then
		return repTemplate
	end
	local wsTemplate = Workspace:FindFirstChild("DungeonPedestal")
	if wsTemplate then
		return wsTemplate
	end
	return nil
end

-- Erstellt einen detailreichen 3D-Dungeon-Sockel rein programmgesteuert (kein externer Import nötig)
local function buildProceduralDungeonPedestal(slotIndex: number, targetPosition: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Sockel_" .. slotIndex
	model:SetAttribute("SlotIndex", slotIndex)

	-- 1. Unsichtbarer Root-Part für exakte Pivot- & Attachment-Kompatibilität
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 2, 4)
	root.Position = targetPosition
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	-- 2. Untere Basis-Stufe (Massives antikes Schiefer-Fundament)
	local basePlinth = Instance.new("Part")
	basePlinth.Name = "BasePlinth"
	basePlinth.Size = Vector3.new(5.6, 0.6, 5.6)
	basePlinth.Position = targetPosition - Vector3.new(0, 0.7, 0)
	basePlinth.Color = Color3.fromRGB(36, 40, 44)
	basePlinth.Material = Enum.Material.Slate
	basePlinth.Anchored = true
	basePlinth.CanCollide = true
	basePlinth.Parent = model

	-- 3. Mittlerer gestufter Säulenkörper (Verwittertes Dungeon-Pflaster)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4.6, 1.4, 4.6)
	body.Position = targetPosition + Vector3.new(0, 0.1, 0)
	body.Color = Color3.fromRGB(54, 60, 66)
	body.Material = Enum.Material.Cobblestone
	body.Anchored = true
	body.CanCollide = true
	body.Parent = model

	-- 4. Vier markante Eckpfeiler (Dungeon-Strebepfeiler mit Zierkanten)
	local cornerOffsets = {
		Vector3.new(-2.15, 0.1, -2.15),
		Vector3.new(2.15, 0.1, -2.15),
		Vector3.new(-2.15, 0.1, 2.15),
		Vector3.new(2.15, 0.1, 2.15),
	}
	for i, cOffset in ipairs(cornerOffsets) do
		local pillar = Instance.new("Part")
		pillar.Name = "CornerPillar_" .. i
		pillar.Size = Vector3.new(1.0, 1.8, 1.0)
		pillar.Position = targetPosition + cOffset
		pillar.Color = Color3.fromRGB(44, 48, 52)
		pillar.Material = Enum.Material.Slate
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Parent = model
	end

	-- 5. Obere Altar-Platte (Opfertisch-Ebene)
	local topSlab = Instance.new("Part")
	topSlab.Name = "TopSlab"
	topSlab.Size = Vector3.new(5.0, 0.4, 5.0)
	topSlab.Position = targetPosition + Vector3.new(0, 0.95, 0)
	topSlab.Color = Color3.fromRGB(48, 54, 58)
	topSlab.Material = Enum.Material.Slate
	topSlab.Anchored = true
	topSlab.CanCollide = true
	topSlab.Parent = model

	-- 6. Eingelassene leuchtende Magie-Rune (Smaragdgrün/Teal)
	local runeDisc = Instance.new("Part")
	runeDisc.Name = "RuneCore"
	runeDisc.Size = Vector3.new(3.0, 0.08, 3.0)
	runeDisc.Position = targetPosition + Vector3.new(0, 1.18, 0)
	runeDisc.Color = Color3.fromRGB(0, 230, 180)
	runeDisc.Material = Enum.Material.Neon
	runeDisc.Anchored = true
	runeDisc.CanCollide = false
	runeDisc.Parent = model

	-- 7. Mystisches Umgebungslicht
	local light = Instance.new("PointLight")
	light.Name = "RuneLight"
	light.Color = Color3.fromRGB(0, 230, 180)
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = true
	light.Parent = runeDisc

	-- 8. Feine schwebende Magie-Partikel
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "RuneParticles"
	particles.Rate = 2.5
	particles.Lifetime = NumberRange.new(2.0, 3.2)
	particles.Speed = NumberRange.new(0.4, 1.0)
	particles.SpreadAngle = Vector2.new(15, 15)
	particles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	}
	particles.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 1.0),
	}
	particles.Color = ColorSequence.new(Color3.fromRGB(0, 230, 180))
	particles.LightEmission = 0.8
	particles.Parent = runeDisc

	return model
end

-- Erzeugt eine Sockel-Instanz (bevorzugt das 3D-Blender-Modell, sonst proceduralen Dungeon-Sockel)
local function createPedestalInstance(slotIndex: number, targetPosition: Vector3): Instance
	local template = getCustomPedestalTemplate()
	if template then
		local clone = template:Clone()
		clone.Name = "Sockel_" .. slotIndex
		clone:SetAttribute("SlotIndex", slotIndex)

		if clone:IsA("BasePart") then
			clone.Position = targetPosition
			clone.Anchored = true
			clone.CanCollide = true
			return clone
		elseif clone:IsA("Model") then
			local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			if root then
				clone.PrimaryPart = root
				clone:PivotTo(CFrame.new(targetPosition))
				for _, part in clone:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = true
					end
				end
				return clone
			end
		end
	end

	-- Proceduraler Dungeon-Sockel (3D-Modell mit Stufen, Eckpfeilern, leuchtender Rune & Partikeln)
	return buildProceduralDungeonPedestal(slotIndex, targetPosition)
end

-- Hilfsfunktion: Ruft ein Attachment ab oder erstellt es mit lokalem Offset
local function getOrCreateAttachment(parent: BasePart, name: string, localPos: Vector3): Attachment
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		existing.Position = localPos
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = localPos
	att.Parent = parent
	return att
end

-- Erstellt die detaillierte Statue eines Seelenkerns (Mini-Wald-Golem mit Stufen-Runen & Mossy Facelift)
local function buildStatueOnPedestal(pedestal: BasePart, coreId: string, level: number): Model
	-- Alten Inhalt aufräumen
	for _, child in pedestal:GetChildren() do
		if child.Name == "StatueModel" or child.Name == "CoreModel" then
			child:Destroy()
		end
	end

	local statue = Instance.new("Model")
	statue.Name = "StatueModel"
	statue:SetAttribute("CoreId", coreId)
	statue:SetAttribute("Level", level)
	statue.Parent = pedestal

	-- 1. Sockel-Platte (Plinth) mit graviertem Schiefer-Look
	local plinth = Instance.new("Part")
	plinth.Name = "Plinth"
	plinth.Size = Vector3.new(3.4, 0.6, 3.4)
	plinth.Position = pedestal.Position + Vector3.new(0, 1.3, 0)
	plinth.Color = Color3.fromRGB(48, 54, 50)
	plinth.Material = Enum.Material.Slate
	plinth.Anchored = true
	plinth.CanCollide = false
	plinth.Parent = statue

	-- 2. Torso (Massiver alter Felsstein)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2.6, 3.4, 2.0)
	torso.Position = pedestal.Position + Vector3.new(0, 3.3, 0)
	torso.Color = Color3.fromRGB(75, 80, 70)
	torso.Material = Enum.Material.Slate
	torso.Anchored = true
	torso.CanCollide = false
	torso.Parent = statue

	-- Moos-Rücken/Spine der Statue
	local spine = Instance.new("Part")
	spine.Name = "SpineMoss"
	spine.Size = Vector3.new(1.4, 3.0, 0.6)
	spine.Position = torso.Position + Vector3.new(0, 0, 1.1)
	spine.Color = Color3.fromRGB(46, 120, 50)
	spine.Material = Enum.Material.Grass
	spine.Anchored = true
	spine.CanCollide = false
	spine.Parent = statue

	-- 3. Leuchtender Seelenkern im Torso mit Partikel-Aura
	local core = Instance.new("Part")
	core.Name = "CoreModel"
	core.Size = Vector3.new(1.6, 1.6, 1.2)
	core.Position = pedestal.Position + Vector3.new(0, 3.4, -0.65)
	core.Color = Color3.fromRGB(46, 204, 113)
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = statue

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(46, 204, 113)
	light.Range = 10 + (level * 2)
	light.Brightness = 2.2 + (level * 0.6)
	light.Parent = core

	-- Feine Seelen-Aura-Partikel um den Kern
	local coreAtt = Instance.new("Attachment")
	coreAtt.Name = "CoreAtt"
	coreAtt.Parent = core

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "StatueAura"
	aura.Rate = 4 + (level * 3)
	aura.Lifetime = NumberRange.new(1.5, 2.5)
	aura.Speed = NumberRange.new(0.5, 1.2)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	}
	aura.Color = ColorSequence.new(Color3.fromRGB(80, 255, 160))
	aura.LightEmission = 0.9
	aura.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.4, 0.2),
		NumberSequenceKeypoint.new(1, 1.0),
	}
	aura.Parent = coreAtt

	-- 4. Kopf mit GELBEN Leuchtaugen (wie beim Boss!) & Kinn-Felsen
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8, 1.5, 1.8)
	head.Position = pedestal.Position + Vector3.new(0, 5.3, 0)
	head.Color = Color3.fromRGB(80, 85, 75)
	head.Material = Enum.Material.Cobblestone
	head.Anchored = true
	head.CanCollide = false
	head.Parent = statue

	-- Fels-Kinn / Zähne
	local chin = Instance.new("Part")
	chin.Name = "Chin"
	chin.Size = Vector3.new(1.2, 0.4, 0.8)
	chin.Position = head.Position + Vector3.new(0, -0.65, -0.7)
	chin.Color = Color3.fromRGB(60, 65, 58)
	chin.Material = Enum.Material.Slate
	chin.Anchored = true
	chin.CanCollide = false
	chin.Parent = statue

	-- Gelb leuchtende Augen mit PointLight
	local eyeL = Instance.new("Part")
	eyeL.Name = "EyeL"
	eyeL.Size = Vector3.new(0.32, 0.32, 0.25)
	eyeL.Position = head.Position + Vector3.new(-0.42, 0.1, -0.95)
	eyeL.Color = Color3.fromRGB(255, 230, 40)
	eyeL.Material = Enum.Material.Neon
	eyeL.Anchored = true
	eyeL.CanCollide = false
	eyeL.Parent = statue

	local eyeR = Instance.new("Part")
	eyeR.Name = "EyeR"
	eyeR.Size = Vector3.new(0.32, 0.32, 0.25)
	eyeR.Position = head.Position + Vector3.new(0.42, 0.1, -0.95)
	eyeR.Color = Color3.fromRGB(255, 230, 40)
	eyeR.Material = Enum.Material.Neon
	eyeR.Anchored = true
	eyeR.CanCollide = false
	eyeR.Parent = statue

	local eyeLight = Instance.new("PointLight")
	eyeLight.Color = Color3.fromRGB(255, 220, 50)
	eyeLight.Range = 6
	eyeLight.Brightness = 2.0
	eyeLight.Parent = eyeL

	-- 5. Moos-Schulterpolster (Grass-Material, wie im Pitch-Video)
	local mossShoulderL = Instance.new("Part")
	mossShoulderL.Name = "MossShoulderL"
	mossShoulderL.Size = Vector3.new(1.3, 0.65, 1.3)
	mossShoulderL.Position = torso.Position + Vector3.new(-1.85, 1.4, 0)
	mossShoulderL.Color = Color3.fromRGB(46, 120, 50)
	mossShoulderL.Material = Enum.Material.Grass
	mossShoulderL.Anchored = true
	mossShoulderL.CanCollide = false
	mossShoulderL.Parent = statue

	local mossShoulderR = Instance.new("Part")
	mossShoulderR.Name = "MossShoulderR"
	mossShoulderR.Size = Vector3.new(1.3, 0.65, 1.3)
	mossShoulderR.Position = torso.Position + Vector3.new(1.85, 1.4, 0)
	mossShoulderR.Color = Color3.fromRGB(46, 120, 50)
	mossShoulderR.Material = Enum.Material.Grass
	mossShoulderR.Anchored = true
	mossShoulderR.CanCollide = false
	mossShoulderR.Parent = statue

	-- 6. Riesige Stein-Arme
	local armL = Instance.new("Part")
	armL.Name = "ArmL"
	armL.Size = Vector3.new(1.1, 2.9, 1.1)
	armL.Position = pedestal.Position + Vector3.new(-1.85, 3.0, 0)
	armL.Color = Color3.fromRGB(70, 75, 65)
	armL.Material = Enum.Material.Cobblestone
	armL.Anchored = true
	armL.CanCollide = false
	armL.Parent = statue

	local armR = Instance.new("Part")
	armR.Name = "ArmR"
	armR.Size = Vector3.new(1.1, 2.9, 1.1)
	armR.Position = pedestal.Position + Vector3.new(1.85, 3.0, 0)
	armR.Color = Color3.fromRGB(70, 75, 65)
	armR.Material = Enum.Material.Cobblestone
	armR.Anchored = true
	armR.CanCollide = false
	armR.Parent = statue

	-- 7. Bonus-Effekte für höhere Stufen:
	-- Stufe 2+: Goldene Runen auf den Moos-Schultern
	if level >= 2 then
		local runeL = Instance.new("Part")
		runeL.Name = "RuneL"
		runeL.Size = Vector3.new(0.8, 0.25, 0.8)
		runeL.Position = mossShoulderL.Position + Vector3.new(0, 0.4, 0)
		runeL.Color = Color3.fromRGB(255, 215, 0)
		runeL.Material = Enum.Material.Neon
		runeL.Anchored = true
		runeL.CanCollide = false
		runeL.Parent = statue

		local runeR = Instance.new("Part")
		runeR.Name = "RuneR"
		runeR.Size = Vector3.new(0.8, 0.25, 0.8)
		runeR.Position = mossShoulderR.Position + Vector3.new(0, 0.4, 0)
		runeR.Color = Color3.fromRGB(255, 215, 0)
		runeR.Material = Enum.Material.Neon
		runeR.Anchored = true
		runeR.CanCollide = false
		runeR.Parent = statue
	end

	-- Stufe 3+: 3 schwebende Runen-Kristalle um die Statue
	if level >= 3 then
		for angleIdx = 1, 3 do
			local rad = (angleIdx / 3) * math.pi * 2
			local orbitPos = torso.Position + Vector3.new(math.cos(rad) * 2.8, 0.6, math.sin(rad) * 2.8)
			local orbitCrystal = Instance.new("Part")
			orbitCrystal.Name = "OrbitCrystal_" .. angleIdx
			orbitCrystal.Size = Vector3.new(0.5, 1.0, 0.5)
			orbitCrystal.Position = orbitPos
			orbitCrystal.Color = Color3.fromRGB(0, 230, 180)
			orbitCrystal.Material = Enum.Material.Neon
			orbitCrystal.Anchored = true
			orbitCrystal.CanCollide = false
			orbitCrystal.Parent = statue
		end
	end

	return statue
end

-- Richtet die ProximityPrompts für Sockel ein (Platzieren, Upgraden, Entfernen)
local function setupPedestalPrompts(pedestal: Instance, player: Player, slotIndex: number, slotData: any)
	local pedestalPart = getPedestalRootPart(pedestal)
	if not pedestalPart then
		return
	end

	-- Bestehende Prompts bereinigen (auch in Attachments)
	for _, desc in pedestal:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end

	-- Attachments für getrennte 3D-Positionen (Links = Upgraden, Rechts = Entfernen, Mitte = Platzieren)
	local leftAtt = getOrCreateAttachment(pedestalPart, "PromptLeftAtt", Vector3.new(-2.2, 0.8, 0))
	local rightAtt = getOrCreateAttachment(pedestalPart, "PromptRightAtt", Vector3.new(2.2, 0.8, 0))
	local centerAtt = getOrCreateAttachment(pedestalPart, "PromptCenterAtt", Vector3.new(0, 0.8, 0))

	if slotData and slotData.CoreId then
		local bossInfo = BossConfig[slotData.CoreId]
		local level = slotData.Level or 1
		local upgradeCost = 50 * level
		local bonusCPS = if bossInfo then bossInfo.BaseCPS else 5

		-- Prompt 1: Upgraden ([E]) - Links vom Sockel
		local upgradePrompt = Instance.new("ProximityPrompt")
		upgradePrompt.Name = "UpgradePrompt"
		upgradePrompt.ActionText = string.format("Upgraden (%d Gold)", upgradeCost)
		upgradePrompt.ObjectText = string.format("Stufe %d -> %d (+%d Gold/s)", level, level + 1, bonusCPS)
		upgradePrompt.KeyboardKeyCode = Enum.KeyCode.E
		upgradePrompt.HoldDuration = 0.5
		upgradePrompt.MaxActivationDistance = 12
		upgradePrompt.RequiresLineOfSight = false
		upgradePrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		upgradePrompt:SetAttribute("OwnerUserId", player.UserId)
		upgradePrompt.Parent = leftAtt

		upgradePrompt.Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer ~= player then
				notifyPlayer(triggeringPlayer, "Dieser Sockel gehört " .. player.DisplayName .. "!", true)
				return
			end

			local char = triggeringPlayer.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if not root or (root.Position - pedestalPart.Position).Magnitude > 16 then
				return
			end

			local success = DataManager.UpgradeSlot(player, slotIndex, upgradeCost)
			if success then
				PlotService.UpdatePlotVisuals(player)
				local updatedData = DataManager.Get(player)
				if updatedData then
					GoldUpdatedEvent:FireClient(player, updatedData.Gold, PlotService.CalculateCPS(player))
				end
				notifyPlayer(player, string.format("Sockel %d auf Stufe %d aufgewertet!", slotIndex, level + 1), false)
			else
				notifyPlayer(player, string.format("Nicht genug Gold! Du benötigst %d Gold.", upgradeCost), true)
			end
		end)

		-- Prompt 2: Kern entfernen ([R]) - Rechts vom Sockel
		local removePrompt = Instance.new("ProximityPrompt")
		removePrompt.Name = "RemovePrompt"
		removePrompt.ActionText = "Kern entfernen"
		removePrompt.ObjectText = "Ins Inventar legen"
		removePrompt.KeyboardKeyCode = Enum.KeyCode.R
		removePrompt.HoldDuration = 1.0
		removePrompt.MaxActivationDistance = 12
		removePrompt.RequiresLineOfSight = false
		removePrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		removePrompt:SetAttribute("OwnerUserId", player.UserId)
		removePrompt.Parent = rightAtt

		removePrompt.Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer ~= player then
				notifyPlayer(triggeringPlayer, "Dieser Sockel gehört " .. player.DisplayName .. "!", true)
				return
			end

			local char = triggeringPlayer.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if not root or (root.Position - pedestalPart.Position).Magnitude > 16 then
				return
			end

			local coreId = slotData.CoreId
			local coreLevel = slotData.Level or 1
			DataManager.SetSlot(player, slotIndex, nil)
			DataManager.AddCore(player, coreId, coreLevel)

			PlotService.UpdatePlotVisuals(player)
			local updatedData = DataManager.Get(player)
			if updatedData then
				GoldUpdatedEvent:FireClient(player, updatedData.Gold, PlotService.CalculateCPS(player))
			end

			local name = if bossInfo then bossInfo.DisplayName else coreId
			notifyPlayer(player, string.format("%s (Stufe %d) ins Inventar zurückgelegt.", name, coreLevel), false)
		end)

		-- Prompt 3: Seelenkern stehlen ([E] - 3.5s) für Raids durch fremde Spieler (Besitzer sieht ihn gar nicht!)
		local stealPrompt = Instance.new("ProximityPrompt")
		stealPrompt.Name = "StealPrompt"
		stealPrompt.ActionText = "Seelenkern stehlen"
		stealPrompt.ObjectText = string.format("Plot von %s (Sockel %d)", player.DisplayName, slotIndex)
		stealPrompt.KeyboardKeyCode = Enum.KeyCode.E
		stealPrompt.HoldDuration = 3.5
		stealPrompt.MaxActivationDistance = 12
		stealPrompt.RequiresLineOfSight = false
		stealPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		stealPrompt:SetAttribute("OwnerUserId", player.UserId)
		stealPrompt.Parent = centerAtt

		stealPrompt.Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				return
			end

			local char = triggeringPlayer.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			local hum = if char then char:FindFirstChild("Humanoid") :: Humanoid? else nil
			if not root or not hum or hum.Health <= 0 or (root.Position - pedestalPart.Position).Magnitude > 16 then
				return
			end

			-- Prüfe, ob der Dieb bereits einen Kern trägt
			if triggeringPlayer:GetAttribute("CarryingCore") ~= nil then
				notifyPlayer(triggeringPlayer, "Du trägst bereits einen Seelenkern! Sichere ihn zuerst in deiner Basis.", true)
				return
			end

			-- Führe Diebstahl über RaidService aus (mit exakter Stufe!)
			local coreLevel = slotData.Level or 1
			getRaidService().StartTheft(triggeringPlayer, player, slotIndex, slotData.CoreId, coreLevel)
		end)
	else
		-- Prompt: Kern platzieren ([E]) - Mittig auf dem Sockel
		local placePrompt = Instance.new("ProximityPrompt")
		placePrompt.Name = "PlacePrompt"
		placePrompt.ActionText = "Seelenkern platzieren"
		placePrompt.ObjectText = string.format("Sockel %d", slotIndex)
		placePrompt.KeyboardKeyCode = Enum.KeyCode.E
		placePrompt.HoldDuration = 0.5
		placePrompt.MaxActivationDistance = 12
		placePrompt.RequiresLineOfSight = false
		placePrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		placePrompt:SetAttribute("OwnerUserId", player.UserId)
		placePrompt.Parent = centerAtt

		placePrompt.Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer ~= player then
				notifyPlayer(triggeringPlayer, "Dieser Sockel gehört " .. player.DisplayName .. "!", true)
				return
			end

			local char = triggeringPlayer.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if not root or (root.Position - pedestalPart.Position).Magnitude > 16 then
				return
			end

			local data = DataManager.Get(player)
			if not data or not data.Inventory or #data.Inventory.Cores == 0 then
				notifyPlayer(player, "Kein Seelenkern im Inventar! Besiege Bosse, um Kerne zu erhalten.", true)
				return
			end

			-- Wähle den besten Seelenkern (höchste Stufe) aus dem Inventar
			local bestIndex = 1
			local bestLevel = -1
			for i, entry in ipairs(data.Inventory.Cores) do
				local lvl = if typeof(entry) == "table" then (entry.Level or 1) else 1
				if lvl > bestLevel then
					bestLevel = lvl
					bestIndex = i
				end
			end

			local chosenEntry = data.Inventory.Cores[bestIndex]
			local coreId = if typeof(chosenEntry) == "table" then chosenEntry.CoreId else chosenEntry
			local chosenLevel = if typeof(chosenEntry) == "table" then chosenEntry.Level else 1
			local removed, coreLevel = DataManager.RemoveCore(player, coreId, chosenLevel)
			if removed then
				DataManager.SetSlot(player, slotIndex, coreId, coreLevel)
				PlotService.UpdatePlotVisuals(player)

				local updatedData = DataManager.Get(player)
				if updatedData then
					GoldUpdatedEvent:FireClient(player, updatedData.Gold, PlotService.CalculateCPS(player))
				end

				local bossInfo = BossConfig[coreId]
				local name = if bossInfo then bossInfo.DisplayName else coreId
				notifyPlayer(player, string.format("%s (Stufe %d) auf Sockel %d platziert!", name, coreLevel, slotIndex), false)
			end
		end)
	end
end

-- Aktualisiert die optische Anzeige auf den Statuen-Sockeln eines Plots
function PlotService.UpdatePlotVisuals(player: Player)
	local plot = PlayerPlots[player]
	if not plot then
		return
	end

	local data = DataManager.Get(player)
	if not data or not data.BaseData or not data.BaseData.Slots then
		return
	end

	local pedestalsFolder = plot:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return
	end

	for slotIndex = 1, 3 do
		local pedestal = pedestalsFolder:FindFirstChild("Sockel_" .. slotIndex)
		local pedestalPart = getPedestalRootPart(pedestal)
		if pedestal and pedestalPart then
			local slotData = data.BaseData.Slots[slotIndex]
			local coreModel = pedestal:FindFirstChild("CoreModel") or pedestalPart:FindFirstChild("CoreModel")

			local billboard = pedestalPart:FindFirstChild("PlotInfo") :: BillboardGui? or (pedestal:FindFirstChild("PlotInfo") :: BillboardGui?)
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil

			if slotData and slotData.CoreId then
				local bossInfo = BossConfig[slotData.CoreId]
				local displayName = if bossInfo then bossInfo.DisplayName else slotData.CoreId
				local level = slotData.Level or 1
				local cps = if bossInfo then bossInfo.BaseCPS * level else 0

				if label then
					label.Text = string.format("Slot %d: %s (Stufe %d)\n(+%d Gold/s)", slotIndex, displayName, level, cps)
					label.TextColor3 = Color3.fromRGB(46, 204, 113)
				end
				if billboard then
					billboard.StudsOffset = Vector3.new(0, 6.8, 0)
				end

				-- Detaillierte Statue auf dem Sockel aufbauen
				local existingStatue = pedestal:FindFirstChild("StatueModel") or pedestalPart:FindFirstChild("StatueModel")
				if not existingStatue 
					or existingStatue:GetAttribute("CoreId") ~= slotData.CoreId 
					or existingStatue:GetAttribute("Level") ~= level then
					buildStatueOnPedestal(pedestalPart, slotData.CoreId, level)
				end
			else
				if label then
					label.Text = string.format("Slot %d: [Leer]", slotIndex)
					label.TextColor3 = Color3.fromRGB(180, 180, 180)
				end
				if billboard then
					billboard.StudsOffset = Vector3.new(0, 2.8, 0)
				end
				local existingStatue = pedestal:FindFirstChild("StatueModel") or pedestalPart:FindFirstChild("StatueModel")
				if existingStatue then
					existingStatue:Destroy()
				end
				local existingCore = pedestal:FindFirstChild("CoreModel") or pedestalPart:FindFirstChild("CoreModel")
				if existingCore then
					existingCore:Destroy()
				end
			end

			-- Prompts für diesen Sockel aktualisieren
			setupPedestalPrompts(pedestal, player, slotIndex, slotData)
		end
	end
end

-- Setzt die Sockel eines Plots auf den Leerzustand zurück
local function clearPlotVisuals(plot: Model)
	local pedestalsFolder = plot:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return
	end

	for slotIndex = 1, 3 do
		local pedestal = pedestalsFolder:FindFirstChild("Sockel_" .. slotIndex)
		local pedestalPart = getPedestalRootPart(pedestal)
		if pedestal and pedestalPart then
			local coreModel = pedestal:FindFirstChild("CoreModel") or pedestalPart:FindFirstChild("CoreModel")
			if coreModel then
				coreModel:Destroy()
			end

			local statueModel = pedestal:FindFirstChild("StatueModel") or pedestalPart:FindFirstChild("StatueModel")
			if statueModel then
				statueModel:Destroy()
			end

			-- Prompts entfernen
			for _, desc in pedestal:GetDescendants() do
				if desc:IsA("ProximityPrompt") then
					desc:Destroy()
				end
			end

			local billboard = pedestalPart:FindFirstChild("PlotInfo") :: BillboardGui? or (pedestal:FindFirstChild("PlotInfo") :: BillboardGui?)
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
			if label then
				label.Text = string.format("Slot %d: [Leer]", slotIndex)
				label.TextColor3 = Color3.fromRGB(180, 180, 180)
			end
			if billboard then
				billboard.StudsOffset = Vector3.new(0, 3.0, 0)
			end
		end
	end
end

-- Entfernt den Claim-Prompt von einem Plot-Schild
local function removeClaimPromptFromSignPost(signPost: BasePart)
	for _, child in signPost:GetChildren() do
		if child:IsA("ProximityPrompt") and child.Name == "ClaimPlotPrompt" then
			child:Destroy()
		end
	end
end

-- Befestigt einen Claim-Prompt an einem freien Plot-Schild
local function attachClaimPromptToSignPost(signPost: BasePart, plotIndex: number)
	removeClaimPromptFromSignPost(signPost)

	local claimPrompt = Instance.new("ProximityPrompt")
	claimPrompt.Name = "ClaimPlotPrompt"
	claimPrompt.ActionText = "Plot beanspruchen"
	claimPrompt.ObjectText = string.format("Plot %d [Frei]", plotIndex)
	claimPrompt.KeyboardKeyCode = Enum.KeyCode.E
	claimPrompt.HoldDuration = 0.5
	claimPrompt.MaxActivationDistance = 14
	claimPrompt.RequiresLineOfSight = false
	claimPrompt.Parent = signPost

	claimPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		PlotService.ClaimPlot(triggeringPlayer, plotIndex)
	end)
end

-- Erstellt einen einzelnen Plot
local function createPlotModel(plotIndex: number, position: Vector3): Model
	local plot = Instance.new("Model")
	plot.Name = "Plot_" .. plotIndex
	plot:SetAttribute("PlotIndex", plotIndex)
	plot:SetAttribute("OwnerUserId", 0)
	plot:SetAttribute("OwnerName", "")

	-- Bodenplatte
	local floor = Instance.new("Part")
	floor.Name = "PlotFloor"
	floor.Size = Vector3.new(40, 1, 40)
	floor.Position = position
	floor.Anchored = true
	floor.CanCollide = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(45, 52, 54)
	floor.Parent = plot

	-- Plot Schild
	local signPost = Instance.new("Part")
	signPost.Name = "SignPost"
	signPost.Size = Vector3.new(1, 4, 1)
	signPost.Position = position + Vector3.new(0, 2.5, -18)
	signPost.Anchored = true
	signPost.CanCollide = false
	signPost.Material = Enum.Material.Wood
	signPost.Color = Color3.fromRGB(108, 92, 231)
	signPost.Parent = plot

	createBillboard(signPost, string.format("Plot %d - [Frei]", plotIndex), Vector3.new(0, 3, 0))
	if plotIndex ~= 2 then
		attachClaimPromptToSignPost(signPost, plotIndex)
	end

	-- Sockel-Ordner
	local pedestalsFolder = Instance.new("Folder")
	pedestalsFolder.Name = "Pedestals"
	pedestalsFolder.Parent = plot

	local pedestalOffsets = {
		Vector3.new(-10, 1.5, 0),
		Vector3.new(0, 1.5, 0),
		Vector3.new(10, 1.5, 0),
	}

	for slotIndex = 1, 3 do
		local pedestal = createPedestalInstance(slotIndex, position + pedestalOffsets[slotIndex])
		pedestal.Parent = pedestalsFolder

		local pedestalPart = getPedestalRootPart(pedestal)
		if pedestalPart then
			createBillboard(pedestalPart, string.format("Slot %d: [Leer]", slotIndex), Vector3.new(0, 2.5, 0))
		end
	end

	getDefenseService().SetupPlotDefenses(plot, 0)

	return plot
end

-- Richtet einen reservierten NPC-Plot (Plot 2) mit einer stehlbaren Wald-Golem Statue für Testzwecke ein
local function setupTestRaidPlot(plot: Model)
	plot:SetAttribute("OwnerUserId", 999999)
	plot:SetAttribute("OwnerName", "Rivale (Test-NPC)")
	getDefenseService().SetupPlotDefenses(plot, 999999)

	-- Schild aktualisieren
	local signPost = plot:FindFirstChild("SignPost")
	if signPost then
		local billboard = signPost:FindFirstChild("PlotInfo") :: BillboardGui?
		local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
		if label then
			label.Text = "Plot 2\nBesitzer: Rivale (Test-NPC)"
			label.TextColor3 = Color3.fromRGB(255, 99, 71)
		end
	end

	local pedestalsFolder = plot:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return
	end

	local pedestal1 = pedestalsFolder:FindFirstChild("Sockel_1")
	local pedestalPart = getPedestalRootPart(pedestal1)
	if not pedestal1 or not pedestalPart then
		return
	end

	-- Funktion zum Aufbauen / Respawn der Test-Statue
	local function buildTestStatue()
		-- Alten Inhalt aufräumen
		for _, child in pedestal1:GetChildren() do
			if child.Name == "StatueModel" or child.Name == "CoreModel" then
				child:Destroy()
			end
		end
		if pedestalPart ~= pedestal1 then
			for _, child in pedestalPart:GetChildren() do
				if child.Name == "StatueModel" or child.Name == "CoreModel" then
					child:Destroy()
				end
			end
		end

		for _, desc in pedestal1:GetDescendants() do
			if desc:IsA("ProximityPrompt") then
				desc:Destroy()
			end
		end

		local centerAtt = getOrCreateAttachment(pedestalPart, "PromptCenterAtt", Vector3.new(0, 0.8, 0))

		-- 1. Visuelles Modell der Statue (Mini-Wald-Golem auf dem Sockel mit Stufe 2)
		local statue = buildStatueOnPedestal(pedestalPart, "ForestGolemCore", 2)

		-- Billboard
		local billboard = pedestalPart:FindFirstChild("PlotInfo") :: BillboardGui? or (pedestal1:FindFirstChild("PlotInfo") :: BillboardGui?)
		local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
		if label then
			label.Text = "Slot 1: Wald-Golem Statue (Stufe 2)\n(+10 Gold/s)"
			label.TextColor3 = Color3.fromRGB(46, 204, 113)
		end
		if billboard then
			billboard.StudsOffset = Vector3.new(0, 6.8, 0)
		end

		-- 2. Steal-Prompt anbringen
		local stealPrompt = Instance.new("ProximityPrompt")
		stealPrompt.Name = "StealPrompt"
		stealPrompt.ActionText = "Seelenkern stehlen"
		stealPrompt.ObjectText = "Plot 2 (Rivale NPC)"
		stealPrompt.KeyboardKeyCode = Enum.KeyCode.E
		stealPrompt.HoldDuration = 3.5
		stealPrompt.MaxActivationDistance = 14
		stealPrompt.RequiresLineOfSight = false
		stealPrompt:SetAttribute("OwnerUserId", 999999)
		stealPrompt.Parent = centerAtt

		stealPrompt.Triggered:Connect(function(triggeringPlayer: Player)
			local char = triggeringPlayer.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			local hum = if char then char:FindFirstChild("Humanoid") :: Humanoid? else nil
			if not root or not hum or hum.Health <= 0 or (root.Position - pedestalPart.Position).Magnitude > 18 then
				return
			end

			if triggeringPlayer:GetAttribute("CarryingCore") ~= nil then
				notifyPlayer(triggeringPlayer, "Du trägst bereits einen Seelenkern! Sichere ihn zuerst in deiner Basis.", true)
				return
			end

			-- Statue optisch entfernen
			statue:Destroy()
			stealPrompt:Destroy()

			if label then
				label.Text = "Slot 1: [GESTOHLEN!]\n(Respawn in 45s)"
				label.TextColor3 = Color3.fromRGB(231, 76, 60)
			end
			if billboard then
				billboard.StudsOffset = Vector3.new(0, 2.8, 0)
			end

			-- Mock-Victim an RaidService übergeben (mit Stufe 2!)
			local mockVictim = {
				UserId = 999999,
				DisplayName = "Rivale (Test-NPC)",
				Name = "RivaleNPC",
			}
			getRaidService().StartTheft(triggeringPlayer, mockVictim, 1, "ForestGolemCore", 2)

			-- Automatisch nach 45s respawnen zum erneuten Testen (ohne störenden Broadcast)
			task.delay(45, function()
				buildTestStatue()
			end)
		end)
	end

	buildTestStatue()
end

-- Stellt sicher, dass 4-6 Test-Plots in Workspace.Plots existieren
local function ensurePlotsExist(): Folder
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder or not plotsFolder:IsA("Folder") then
		plotsFolder = Instance.new("Folder")
		plotsFolder.Name = "Plots"
		plotsFolder.Parent = Workspace
	end

	local existingPlots = plotsFolder:GetChildren()
	if #existingPlots < 4 then
		for _, child in existingPlots do
			child:Destroy()
		end

		local plotPositions = {
			Vector3.new(-55, 0.5, -45),
			Vector3.new(0, 0.5, -45),
			Vector3.new(55, 0.5, -45),
			Vector3.new(-55, 0.5, 45),
			Vector3.new(0, 0.5, 45),
			Vector3.new(55, 0.5, 45),
		}

		for index, pos in ipairs(plotPositions) do
			local plot = createPlotModel(index, pos)
			plot.Parent = plotsFolder
			if index == 2 then
				setupTestRaidPlot(plot)
			end
		end
		print("[PlotService] 6 Test-Plots generiert (Plot 2 als Rivale reserviert).")
	else
		print(string.format("[PlotService] %d bestehende Plots in Workspace.Plots gefunden.", #existingPlots))
		for _, child in existingPlots do
			if child:IsA("Model") then
				-- Veraltete flache Sockel-Blöcke automatisch durch die neuen 3D-Dungeon-Sockel ersetzen
				local pedestalsFolder = child:FindFirstChild("Pedestals")
				if pedestalsFolder then
					for slotIndex = 1, 3 do
						local ped = pedestalsFolder:FindFirstChild("Sockel_" .. slotIndex)
						if ped and ped:IsA("Part") and not ped:FindFirstChild("Root") then
							local oldPos = ped.Position
							ped:Destroy()
							local newPed = createPedestalInstance(slotIndex, oldPos)
							newPed.Parent = pedestalsFolder
							local pedPart = getPedestalRootPart(newPed)
							if pedPart then
								createBillboard(pedPart, string.format("Slot %d: [Leer]", slotIndex), Vector3.new(0, 2.5, 0))
							end
						end
					end
				end

				local idx = child:GetAttribute("PlotIndex") or 0
				local ownerId = child:GetAttribute("OwnerUserId") or 0
				getDefenseService().SetupPlotDefenses(child, ownerId)

				if idx == 2 then
					setupTestRaidPlot(child)
				elseif ownerId == 0 then
					local sign = child:FindFirstChild("SignPost") :: BasePart?
					if sign then
						attachClaimPromptToSignPost(sign, idx)
					end
				end
			end
		end
	end

	return plotsFolder :: Folder
end

-- Baut die 6 Plots dauerhaft in Workspace (z.B. für Edit-Modus / Studio Command Bar)
-- Bei forceRebuild = true werden bestehende Plots durch die neuesten 3D-Modelle ersetzt
function PlotService.BuildPlotsInStudio(forceRebuild: boolean?): Folder
	if forceRebuild == true then
		local oldPlots = Workspace:FindFirstChild("Plots")
		if oldPlots then
			oldPlots:Destroy()
		end
	end
	return ensurePlotsExist()
end

-- Berechnet das aktuelle CPS eines Spielers
function PlotService.CalculateCPS(player: Player): number
	local data = DataManager.Get(player)
	if not data or not data.BaseData or not data.BaseData.Slots then
		return 0
	end

	local totalCPS = 0
	for _, slot in pairs(data.BaseData.Slots) do
		if slot and slot.CoreId then
			local bossInfo = BossConfig[slot.CoreId]
			if bossInfo then
				local level = slot.Level or 1
				totalCPS += bossInfo.BaseCPS * level
			end
		end
	end

	return totalCPS
end

export type PlotStatus = {
	PlotIndex: number,
	OwnerUserId: number,
	OwnerName: string,
	IsRival: boolean,
}

-- Liefert den Status aller 6 Plots für die interaktive Plot-Auswahl
function PlotService.GetAllPlotsStatus(): { [number]: PlotStatus }
	local plotsFolder = Workspace:FindFirstChild("Plots")
	local statusList: { [number]: PlotStatus } = {}
	if not plotsFolder then
		return statusList
	end

	for slotIndex = 1, 6 do
		local plot = plotsFolder:FindFirstChild("Plot_" .. slotIndex) :: Model?
		if plot then
			local ownerId = (plot:GetAttribute("OwnerUserId") :: number?) or 0
			local ownerName = (plot:GetAttribute("OwnerName") :: string?) or ""
			local isRival = (slotIndex == 2 or ownerId == 999999)
			statusList[slotIndex] = {
				PlotIndex = slotIndex,
				OwnerUserId = ownerId,
				OwnerName = ownerName,
				IsRival = isRival,
			}
		end
	end

	return statusList
end

-- Beansprucht einen bestimmten Plot für einen Spieler (oder den ersten freien Plot bei 0/nil)
function PlotService.ClaimPlot(player: Player, plotIndex: number?): boolean
	if PlayerPlots[player] then
		local currentPlot = PlayerPlots[player]
		local currentIndex = currentPlot:GetAttribute("PlotIndex") or "?"
		notifyPlayer(player, string.format("Du besitzt bereits Plot %s!", tostring(currentIndex)), true)
		return false
	end

	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then
		return false
	end

	-- Automatische Schnellwahl des ersten freien Plots
	local targetIndex = plotIndex
	if targetIndex == nil or targetIndex == 0 then
		for candidateIndex = 1, 6 do
			if candidateIndex ~= 2 then
				local p = plotsFolder:FindFirstChild("Plot_" .. candidateIndex) :: Model?
				if p and ((p:GetAttribute("OwnerUserId") :: number?) or 0) == 0 then
					targetIndex = candidateIndex
					break
				end
			end
		end
	end

	if not targetIndex or targetIndex < 1 or targetIndex > 6 then
		notifyPlayer(player, "Kein freier Plot verfügbar!", true)
		return false
	end

	if targetIndex == 2 then
		notifyPlayer(player, "Plot 2 ist für den Test-Rivalen reserviert!", true)
		return false
	end

	local plot = plotsFolder:FindFirstChild("Plot_" .. targetIndex) :: Model?
	if not plot then
		notifyPlayer(player, "Plot existiert nicht!", true)
		return false
	end

	local currentOwner = (plot:GetAttribute("OwnerUserId") :: number?) or 0
	if currentOwner ~= 0 then
		notifyPlayer(player, string.format("Plot %d ist bereits vergeben!", targetIndex), true)
		PlotStatusUpdatedEvent:FireClient(player, PlotService.GetAllPlotsStatus(), false)
		return false
	end

	-- Plot erfolgreich zuweisen
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("OwnerName", player.DisplayName)
	PlayerPlots[player] = plot

	-- Schild aktualisieren & Claim-Prompt entfernen
	local signPost = plot:FindFirstChild("SignPost") :: BasePart?
	if signPost then
		removeClaimPromptFromSignPost(signPost)
		local billboard = signPost:FindFirstChild("PlotInfo") :: BillboardGui?
		local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
		if label then
			label.Text = string.format("Plot %d\nBesitzer: %s", targetIndex, player.DisplayName)
			label.TextColor3 = Color3.fromRGB(116, 185, 255)
		end
	end

	-- Spieler zur Mitte des Plots teleportieren
	local floor = plot:FindFirstChild("PlotFloor") :: BasePart?
	local char = player.Character
	if char and floor then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			char:PivotTo(CFrame.new(floor.Position + Vector3.new(0, 3.5, 0)))
		end
	end

	print(string.format("[PlotService] %s hat Plot %d beansprucht.", player.Name, targetIndex))

	-- Nach dem Laden der Daten Sockel-Visuals und Erst-Goldstand übermitteln
	task.spawn(function()
		local data = nil
		for _ = 1, 15 do
			data = DataManager.Get(player)
			if data then
				break
			end
			task.wait(0.5)
		end

		if data and player:IsDescendantOf(Players) then
			PlotService.UpdatePlotVisuals(player)
			GoldUpdatedEvent:FireClient(player, data.Gold, PlotService.CalculateCPS(player))
			DataManager.SyncInventory(player)
		end
	end)

	getDefenseService().SetupPlotDefenses(plot, player.UserId)

	-- Broadcast an alle Spieler: Plot-Status aktualisieren!
	local allStatus = PlotService.GetAllPlotsStatus()
	for _, p in Players:GetPlayers() do
		local hasPlot = (PlayerPlots[p] ~= nil)
		PlotStatusUpdatedEvent:FireClient(p, allStatus, hasPlot)
	end

	-- Erfolgs-Toast erst kurz nach dem schnellen Ausblenden der Infobox anzeigen
	task.delay(0.28, function()
		if player:IsDescendantOf(Players) then
			notifyPlayer(player, string.format("Plot %d erfolgreich beansprucht! Willkommen in deiner Basis.", targetIndex), false)
		end
	end)
	return true
end

-- Gibt den Plot frei, wenn der Spieler den Server verlässt
local function releasePlayerPlot(player: Player)
	local plot = PlayerPlots[player]
	if plot then
		local plotIndex = (plot:GetAttribute("PlotIndex") :: number?) or 1
		plot:SetAttribute("OwnerUserId", 0)
		plot:SetAttribute("OwnerName", "")

		-- Schild zurücksetzen & Claim-Prompt wieder anbringen
		local signPost = plot:FindFirstChild("SignPost") :: BasePart?
		if signPost then
			local billboard = signPost:FindFirstChild("PlotInfo") :: BillboardGui?
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
			if label then
				label.Text = string.format("Plot %d - [Frei]", plotIndex)
				label.TextColor3 = Color3.fromRGB(240, 240, 240)
			end
			if plotIndex ~= 2 then
				attachClaimPromptToSignPost(signPost, plotIndex)
			end
		end

		clearPlotVisuals(plot)
		getDefenseService().SetupPlotDefenses(plot, 0)
		PlayerPlots[player] = nil
		print(string.format("[PlotService] Plot von %s freigegeben.", player.Name))

		-- Status-Update an verbleibende Spieler senden
		local allStatus = PlotService.GetAllPlotsStatus()
		for _, p in Players:GetPlayers() do
			local hasPlot = (PlayerPlots[p] ~= nil)
			PlotStatusUpdatedEvent:FireClient(p, allStatus, hasPlot)
		end
	end
end

-- Liefert den zugewiesenen Plot eines Spielers
function PlotService.GetPlayerPlot(player: Player): Model?
	return PlayerPlots[player]
end

-- Zentrale CPS-Schleife (1-Sekunden-Tick)
local function startCPSLoop()
	task.spawn(function()
		while true do
			task.wait(1)

			for _, player in Players:GetPlayers() do
				local data = DataManager.Get(player)
				if not data or not data.BaseData or not data.BaseData.Slots then
					continue
				end

				local totalCPS = 0
				for _, slot in pairs(data.BaseData.Slots) do
					if slot and slot.CoreId then
						local bossInfo = BossConfig[slot.CoreId]
						if bossInfo then
							local level = slot.Level or 1
							totalCPS += bossInfo.BaseCPS * level
						end
					end
				end

				if totalCPS > 0 then
					local success = DataManager.AddGold(player, totalCPS)
					if success then
						local currentData = DataManager.Get(player)
						if currentData then
							GoldUpdatedEvent:FireClient(player, currentData.Gold, totalCPS)
						end
					end
				end
			end
		end
	end)
end

-- Service-Initialisierung
function PlotService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	ensurePlotsExist()

	-- Remote-Events anbinden
	ClaimPlotIntentEvent.OnServerEvent:Connect(function(player: Player, plotIndex: any)
		if typeof(plotIndex) == "number" then
			PlotService.ClaimPlot(player, math.floor(plotIndex))
		end
	end)

	RequestPlotStatusEvent.OnServerEvent:Connect(function(player: Player)
		local hasPlot = (PlayerPlots[player] ~= nil)
		PlotStatusUpdatedEvent:FireClient(player, PlotService.GetAllPlotsStatus(), hasPlot)
	end)

	local function onPlayerJoined(player: Player)
		task.delay(1.0, function()
			if player:IsDescendantOf(Players) and not PlayerPlots[player] then
				-- Hat noch keinen Plot -> Auswahl-Fenster auf dem Client öffnen!
				PlotStatusUpdatedEvent:FireClient(player, PlotService.GetAllPlotsStatus(), false)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerJoined, player)
	end

	Players.PlayerAdded:Connect(onPlayerJoined)
	Players.PlayerRemoving:Connect(releasePlayerPlot)

	startCPSLoop()

	print("[PlotService] Initialisiert: Interaktive Plot-Auswahl und CPS-Loop aktiv.")
end

return PlotService
