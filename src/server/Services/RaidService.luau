--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventsFolder = Shared:WaitForChild("Events")
local ConfigFolder = Shared:WaitForChild("Config")

local BossConfigModule = ConfigFolder:WaitForChild("BossConfig") :: ModuleScript
local BossConfig = require(BossConfigModule)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

local NotificationEvent = EventsFolder:WaitForChild("ShowNotification") :: RemoteEvent
local GoldUpdatedEvent = EventsFolder:WaitForChild("GoldUpdated") :: RemoteEvent

local RaidService = {}
local isInitialized = false

-- Typ-Definitionen
export type ActiveRaid = {
	Thief: Player,
	VictimUserId: number,
	VictimDisplayName: string,
	CoreId: string,
	StartTime: number,
}

local activeRaids: { [Player]: ActiveRaid } = {}
local droppedCoresFolder: Folder? = nil
local PlotService: any = nil

local function getOrCreateDroppedFolder(): Folder
	local existing = Workspace:FindFirstChild("DroppedCores")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "DroppedCores"
	f.Parent = Workspace
	return f
end

-- Erzeugt visuellen schwebenden Kern über dem Kopf/Rücken des Diebes + weithin sichtbaren Signalstrahl
local function attachCarrierVisuals(player: Player, coreId: string)
	local char = player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChild("Humanoid") :: Humanoid?
	if not root or not hum then
		return
	end

	-- Vorhandene Visuals bereinigen
	local existingRelic = char:FindFirstChild("CarriedCoreRelic")
	if existingRelic then existingRelic:Destroy() end
	local existingBeamAnchor = char:FindFirstChild("BeaconSkyAnchor")
	if existingBeamAnchor then existingBeamAnchor:Destroy() end
	local existingHighlight = char:FindFirstChild("TheftHighlight")
	if existingHighlight then existingHighlight:Destroy() end
	local existingBillboard = root:FindFirstChild("TheftBillboard")
	if existingBillboard then existingBillboard:Destroy() end

	-- 1. Restriktion: WalkSpeed drosseln
	hum.WalkSpeed = 10

	-- Kern-Optik
	local bossInfo = BossConfig[coreId]
	local coreColor = Color3.fromRGB(46, 204, 113) -- Wald-Golem Smaragd
	local coreName = if bossInfo then bossInfo.DisplayName else coreId

	-- 2. Schwebender Relikt-Kern
	local relic = Instance.new("Part")
	relic.Name = "CarriedCoreRelic"
	relic.Size = Vector3.new(2.2, 2.2, 2.2)
	relic.CFrame = root.CFrame * CFrame.new(0, 3.2, 0.4)
	relic.Material = Enum.Material.Neon
	relic.Color = coreColor
	relic.CanCollide = false
	relic.Anchored = false
	relic.Parent = char

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = relic
	weld.Parent = relic

	local light = Instance.new("PointLight")
	light.Color = coreColor
	light.Range = 16
	light.Brightness = 2.5
	light.Parent = relic

	-- 3. Weithin sichtbarer roter Leuchtstrahl (Beacon) in den Himmel
	local skyAnchor = Instance.new("Part")
	skyAnchor.Name = "BeaconSkyAnchor"
	skyAnchor.Size = Vector3.new(1, 1, 1)
	skyAnchor.CFrame = root.CFrame * CFrame.new(0, 220, 0)
	skyAnchor.Transparency = 1
	skyAnchor.CanCollide = false
	skyAnchor.Anchored = false
	skyAnchor.Parent = char

	local skyWeld = Instance.new("WeldConstraint")
	skyWeld.Part0 = root
	skyWeld.Part1 = skyAnchor
	skyWeld.Parent = skyAnchor

	local att0 = Instance.new("Attachment")
	att0.Name = "BeaconAttBottom"
	att0.Position = Vector3.new(0, 2, 0)
	att0.Parent = relic

	local att1 = Instance.new("Attachment")
	att1.Name = "BeaconAttTop"
	att1.Position = Vector3.new(0, 0, 0)
	att1.Parent = skyAnchor

	local beam = Instance.new("Beam")
	beam.Name = "TheftBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(Color3.fromRGB(240, 45, 45))
	beam.Width0 = 3.5
	beam.Width1 = 3.5
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.25)
	beam.Parent = relic

	-- 4. Rote Kontur / Highlight um den Dieb
	local highlight = Instance.new("Highlight")
	highlight.Name = "TheftHighlight"
	highlight.FillColor = Color3.fromRGB(231, 76, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.55
	highlight.Parent = char

	-- 5. Overhead-Warnung
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TheftBillboard"
	billboard.Size = UDim2.new(0, 180, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 5.0, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	label.TextColor3 = Color3.fromRGB(255, 75, 75)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = string.format("🚨 KERN-DIEB 🚨\n%s", coreName)
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.4
	stroke.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
end

-- Entfernt die Diebes-Visuals und setzt normale Geschwindigkeit zurück
local function clearCarrierVisuals(player: Player)
	local char = player.Character
	if char then
		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		if hum then
			hum.WalkSpeed = 16
		end

		local relic = char:FindFirstChild("CarriedCoreRelic")
		if relic then relic:Destroy() end
		local skyAnchor = char:FindFirstChild("BeaconSkyAnchor")
		if skyAnchor then skyAnchor:Destroy() end
		local highlight = char:FindFirstChild("TheftHighlight")
		if highlight then highlight:Destroy() end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local bb = root:FindFirstChild("TheftBillboard")
			if bb then bb:Destroy() end
		end
	end
end

-- Startet den Diebstahl eines Seelenkerns von einem fremden Plot (unterstützt Stufen)
function RaidService.StartTheft(thief: Player, victim: any, slotIndex: number, coreId: string, level: number?)
	if thief:GetAttribute("CarryingCore") ~= nil then
		NotificationEvent:FireClient(thief, "Du trägst bereits einen Seelenkern!", true)
		return
	end

	local coreLevel = level or 1
	local bossInfo = BossConfig[coreId]
	local coreName = if bossInfo then bossInfo.DisplayName else coreId

	local isRealPlayer = typeof(victim) == "Instance" and victim:IsA("Player")
	local victimUserId = if isRealPlayer then victim.UserId else (victim.UserId or 999999)
	local victimName = if isRealPlayer then victim.DisplayName else (victim.DisplayName or "Rivale (Test-NPC)")

	-- 1. Kern serverseitig vom Opfer entfernen (nur bei echten Spielern)
	if isRealPlayer then
		DataManager.SetSlot(victim, slotIndex, nil)
		if PlotService then
			PlotService.UpdatePlotVisuals(victim)
			local vData = DataManager.Get(victim)
			if vData then
				GoldUpdatedEvent:FireClient(victim, vData.Gold, PlotService.CalculateCPS(victim))
			end
		end
		NotificationEvent:FireClient(victim, string.format("🚨 ALARM: %s stiehlt deinen %s (Stufe %d)!", thief.DisplayName, coreName, coreLevel), true)
	end

	-- 2. Attribute auf dem Dieb setzen (inklusive Stufe!)
	thief:SetAttribute("CarryingCore", coreId)
	thief:SetAttribute("CarryingCoreLevel", coreLevel)
	thief:SetAttribute("StolenFromUserId", victimUserId)
	thief:SetAttribute("StolenFromName", victimName)

	-- 3. Visuals & Slow anwenden
	attachCarrierVisuals(thief, coreId)

	activeRaids[thief] = {
		Thief = thief,
		VictimUserId = victimUserId,
		VictimDisplayName = victimName,
		CoreId = coreId,
		StartTime = os.clock(),
	}

	-- 4. Benachrichtigungen & Alarme
	NotificationEvent:FireClient(thief, string.format("⚠️ Du trägst den %s! Entkomme zu deiner Basis!", coreName), false)
	NotificationEvent:FireAllClients(string.format("🚨 RAID: %s überfällt den Plot von %s!", thief.DisplayName, victimName), false)

	print(string.format("[RaidService] %s hat %s von %s (Slot %d) gestohlen!", thief.Name, coreId, victimName, slotIndex))
end

-- Schließt die Flucht erfolgreich ab: Kern wird dauerhaft in der eigenen Basis gesichert
function RaidService.CompleteDelivery(thief: Player)
	local coreId = thief:GetAttribute("CarryingCore") :: string?
	if not coreId then
		return
	end

	local coreLevel = (thief:GetAttribute("CarryingCoreLevel") :: number?) or 1
	local victimUserId = thief:GetAttribute("StolenFromUserId") :: number?
	local bossInfo = BossConfig[coreId]
	local coreName = if bossInfo then bossInfo.DisplayName else coreId

	-- 1. Status zurücksetzen
	thief:SetAttribute("CarryingCore", nil)
	thief:SetAttribute("CarryingCoreLevel", nil)
	thief:SetAttribute("StolenFromUserId", nil)
	thief:SetAttribute("StolenFromName", nil)
	clearCarrierVisuals(thief)
	activeRaids[thief] = nil

	-- 2. Kern mit exakter Stufe in das Inventar des Diebes übertragen
	DataManager.AddCore(thief, coreId, coreLevel)

	-- 3. Benachrichtigungen
	NotificationEvent:FireClient(thief, string.format("🏆 RAID ERFOLGREICH! Du hast den %s (Stufe %d) in deiner Basis gesichert!", coreName, coreLevel), false)

	if victimUserId then
		for _, p in Players:GetPlayers() do
			if p.UserId == victimUserId then
				NotificationEvent:FireClient(p, string.format("💀 %s hat deinen %s erfolgreich in seiner Basis gesichert!", thief.DisplayName, coreName), true)
				break
			end
		end
	end

	NotificationEvent:FireAllClients(string.format("🏆 %s hat den Raubzug erfolgreich abgeschlossen!", thief.DisplayName), false)
	print(string.format("[RaidService] %s hat %s erfolgreich in eigener Basis gesichert!", thief.Name, coreId))
end

-- Lässt den Kern als interaktives Physik-Objekt mit Server Network Ownership fallen
function RaidService.DropCore(player: Player)
	local coreId = player:GetAttribute("CarryingCore") :: string?
	if not coreId then
		return
	end

	local coreLevel = (player:GetAttribute("CarryingCoreLevel") :: number?) or 1
	local stolenFrom = player:GetAttribute("StolenFromUserId") :: number?
	local bossInfo = BossConfig[coreId]
	local coreName = if bossInfo then bossInfo.DisplayName else coreId

	-- Status bereinigen
	player:SetAttribute("CarryingCore", nil)
	player:SetAttribute("CarryingCoreLevel", nil)
	player:SetAttribute("StolenFromUserId", nil)
	player:SetAttribute("StolenFromName", nil)
	clearCarrierVisuals(player)
	activeRaids[player] = nil

	local char = player.Character
	local dropPos = Vector3.new(0, 3, 0)
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			dropPos = root.Position + Vector3.new(0, 1.5, 0)
		end
	end

	-- Dropped Core erstellen
	local folder = getOrCreateDroppedFolder()
	local droppedCore = Instance.new("Part")
	droppedCore.Name = "DroppedCore_" .. coreId
	droppedCore.Size = Vector3.new(2.4, 2.4, 2.4)
	droppedCore.Position = dropPos
	droppedCore.Material = Enum.Material.Neon
	droppedCore.Color = Color3.fromRGB(46, 204, 113)
	droppedCore.CanCollide = true
	droppedCore.Anchored = false
	droppedCore:SetAttribute("CoreLevel", coreLevel)
	droppedCore.Parent = folder

	-- KRITISCH (Server-Autorität / Exploit-Schutz): Server-Network-Ownership!
	droppedCore:SetNetworkOwner(nil)

	-- Visuelle Effekte
	local light = Instance.new("PointLight")
	light.Color = droppedCore.Color
	light.Range = 18
	light.Brightness = 3
	light.Parent = droppedCore

	local highlight = Instance.new("Highlight")
	highlight.FillColor = droppedCore.Color
	highlight.OutlineColor = Color3.fromRGB(255, 230, 100)
	highlight.FillTransparency = 0.4
	highlight.Parent = droppedCore

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 160, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = droppedCore

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(25, 30, 25)
	label.TextColor3 = Color3.fromRGB(255, 230, 100)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = string.format("💎 %s\n[E] Aufheben", coreName)
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.2
	stroke.Parent = label

	-- ProximityPrompt zum Aufheben
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpCorePrompt"
	prompt.ActionText = "Seelenkern aufheben"
	prompt.ObjectText = coreName
	prompt.HoldDuration = 1.0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = droppedCore

	prompt.Triggered:Connect(function(picker: Player)
		if picker:GetAttribute("CarryingCore") ~= nil then
			NotificationEvent:FireClient(picker, "Du trägst bereits einen Seelenkern!", true)
			return
		end

		local pChar = picker.Character
		local pHum = if pChar then pChar:FindFirstChild("Humanoid") :: Humanoid? else nil
		local pRoot = if pChar then pChar:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not pHum or not pRoot or pHum.Health <= 0 then
			return
		end

		local savedLevel = (droppedCore:GetAttribute("CoreLevel") :: number?) or 1
		droppedCore:Destroy()

		if stolenFrom and picker.UserId == stolenFrom then
			-- Ursprünglicher Besitzer rettet seinen Kern!
			DataManager.AddCore(picker, coreId, savedLevel)
			NotificationEvent:FireClient(picker, string.format("🛡️ Du hast deinen %s (Stufe %d) gerettet!", coreName, savedLevel), false)
			NotificationEvent:FireAllClients(string.format("🛡️ %s hat seinen Seelenkern gerettet!", picker.DisplayName), false)
		else
			-- Neuer Träger nimmt den Kern auf (Walk of Shame beginnt!)
			RaidService.PickUpCore(picker, coreId, stolenFrom or 0, savedLevel)
		end
	end)

	-- Sicherheits-Timer: Nach 150s ohne Aufheben zurück an Besitzer
	task.delay(150, function()
		if droppedCore and droppedCore.Parent then
			local savedLevel = (droppedCore:GetAttribute("CoreLevel") :: number?) or 1
			droppedCore:Destroy()
			if stolenFrom then
				for _, p in Players:GetPlayers() do
					if p.UserId == stolenFrom then
						DataManager.AddCore(p, coreId, savedLevel)
						NotificationEvent:FireClient(p, "🛡️ Dein verlorener Seelenkern wurde automatisch zurückgesendet.", false)
						break
					end
				end
			end
		end
	end)

	NotificationEvent:FireAllClients(string.format("⚠️ Ein %s wurde fallengelassen!", coreName), false)
	print(string.format("[RaidService] %s hat %s fallengelassen!", player.Name, coreId))
end

-- Nimmt einen am Boden liegenden Kern auf
function RaidService.PickUpCore(player: Player, coreId: string, originalVictimUserId: number, level: number?)
	if player:GetAttribute("CarryingCore") ~= nil then
		return
	end

	local coreLevel = level or 1
	local bossInfo = BossConfig[coreId]
	local coreName = if bossInfo then bossInfo.DisplayName else coreId

	player:SetAttribute("CarryingCore", coreId)
	player:SetAttribute("CarryingCoreLevel", coreLevel)
	player:SetAttribute("StolenFromUserId", originalVictimUserId)

	attachCarrierVisuals(player, coreId)

	activeRaids[player] = {
		Thief = player,
		VictimUserId = originalVictimUserId,
		VictimDisplayName = "Besitzer",
		CoreId = coreId,
		StartTime = os.clock(),
	}

	NotificationEvent:FireClient(player, string.format("⚠️ Du hast den %s aufgenommen! Bringe ihn zu deiner Basis!", coreName), false)
	NotificationEvent:FireAllClients(string.format("🚨 %s hat den verlorenen Seelenkern aufgenommen!", player.DisplayName), false)
end

function RaidService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	droppedCoresFolder = getOrCreateDroppedFolder()
	PlotService = require(Services:WaitForChild("PlotService") :: ModuleScript)

	-- Spieler-Todes- & Disconnect-Listener
	local function bindPlayer(player: Player)
		local function bindChar(char: Model)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					if player:GetAttribute("CarryingCore") ~= nil then
						RaidService.DropCore(player)
					end
				end)
			end
		end

		if player.Character then
			bindChar(player.Character)
		end
		player.CharacterAdded:Connect(bindChar)
	end

	for _, p in Players:GetPlayers() do
		bindPlayer(p)
	end
	Players.PlayerAdded:Connect(bindPlayer)

	Players.PlayerRemoving:Connect(function(player: Player)
		if player:GetAttribute("CarryingCore") ~= nil then
			RaidService.DropCore(player)
		end
		activeRaids[player] = nil
	end)

	-- Überwachungs-Schleife: WalkSpeed erzwingen & Basis-Erreichung prüfen
	task.spawn(function()
		while true do
			task.wait(0.25)

			for thief, raid in pairs(activeRaids) do
				if not thief:IsDescendantOf(Players) then
					activeRaids[thief] = nil
					continue
				end

				local char = thief.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChild("Humanoid") :: Humanoid?

				if hum and hum.Health > 0 and root then
					-- WalkSpeed auf 10 halten (Walk of Shame)
					if hum.WalkSpeed ~= 10 then
						hum.WalkSpeed = 10
					end

					-- Basis-Erreichungs-Prüfung
					if PlotService then
						local myPlot = PlotService.GetPlayerPlot(thief)
						if myPlot then
							local floor = myPlot:FindFirstChild("PlotFloor") :: BasePart?
							if floor then
								local dist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(floor.Position.X, floor.Position.Z)).Magnitude
								if dist <= 20 and math.abs(root.Position.Y - floor.Position.Y) <= 8 then
									-- Eigene Basis erreicht!
									RaidService.CompleteDelivery(thief)
								end
							end
						end
					end
				end
			end
		end
	end)

	print("[RaidService] Steal-&-Defend-System erfolgreich initialisiert.")
end

return RaidService
