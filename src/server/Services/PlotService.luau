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

local PlotService = {}

local PlayerPlots: { [Player]: Model } = {}
local isInitialized = false

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
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return billboard
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
		if pedestal and pedestal:IsA("BasePart") then
			local slotData = data.BaseData.Slots[slotIndex]
			local coreModel = pedestal:FindFirstChild("CoreModel")

			local billboard = pedestal:FindFirstChild("PlotInfo") :: BillboardGui?
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil

			if slotData and slotData.CoreId then
				local bossInfo = BossConfig[slotData.CoreId]
				local displayName = if bossInfo then bossInfo.DisplayName else slotData.CoreId
				local cps = if bossInfo then bossInfo.BaseCPS * (slotData.Level or 1) else 0

				if label then
					label.Text = string.format("Slot %d: %s\n(+%d Gold/s)", slotIndex, displayName, cps)
					label.TextColor3 = Color3.fromRGB(46, 204, 113)
				end

				-- Visueller Kern (leuchtender Part), falls noch nicht vorhanden
				if not coreModel then
					local corePart = Instance.new("Part")
					corePart.Name = "CoreModel"
					corePart.Size = Vector3.new(2.5, 2.5, 2.5)
					corePart.Position = pedestal.Position + Vector3.new(0, 3, 0)
					corePart.Anchored = true
					corePart.CanCollide = false
					corePart.Material = Enum.Material.Neon
					corePart.Color = Color3.fromRGB(46, 204, 113)
					corePart.Parent = pedestal
				end
			else
				if label then
					label.Text = string.format("Slot %d: [Leer]", slotIndex)
					label.TextColor3 = Color3.fromRGB(180, 180, 180)
				end
				if coreModel then
					coreModel:Destroy()
				end
			end
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
		if pedestal and pedestal:IsA("BasePart") then
			local coreModel = pedestal:FindFirstChild("CoreModel")
			if coreModel then
				coreModel:Destroy()
			end

			local billboard = pedestal:FindFirstChild("PlotInfo") :: BillboardGui?
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
			if label then
				label.Text = string.format("Slot %d: [Leer]", slotIndex)
				label.TextColor3 = Color3.fromRGB(180, 180, 180)
			end
		end
	end
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
		local pedestal = Instance.new("Part")
		pedestal.Name = "Sockel_" .. slotIndex
		pedestal.Size = Vector3.new(4, 2, 4)
		pedestal.Position = position + pedestalOffsets[slotIndex]
		pedestal.Anchored = true
		pedestal.CanCollide = true
		pedestal.Material = Enum.Material.Cobblestone
		pedestal.Color = Color3.fromRGB(99, 110, 114)
		pedestal:SetAttribute("SlotIndex", slotIndex)
		pedestal.Parent = pedestalsFolder

		createBillboard(pedestal, string.format("Slot %d: [Leer]", slotIndex), Vector3.new(0, 2.5, 0))
	end

	return plot
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
		end
		print("[PlotService] 6 Test-Plots erfolgreich in Workspace.Plots generiert.")
	else
		print(string.format("[PlotService] %d bestehende Plots in Workspace.Plots gefunden.", #existingPlots))
	end

	return plotsFolder :: Folder
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

-- Weist einem beitretenden Spieler einen freien Plot zu
local function assignPlotToPlayer(player: Player)
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then
		return
	end

	for _, child in plotsFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == 0 then
			child:SetAttribute("OwnerUserId", player.UserId)
			child:SetAttribute("OwnerName", player.Name)
			PlayerPlots[player] = child

			-- Schild aktualisieren
			local signPost = child:FindFirstChild("SignPost")
			if signPost then
				local billboard = signPost:FindFirstChild("PlotInfo") :: BillboardGui?
				local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
				if label then
					label.Text = string.format("Plot %d\nBesitzer: %s", child:GetAttribute("PlotIndex") or 1, player.DisplayName)
					label.TextColor3 = Color3.fromRGB(116, 185, 255)
				end
			end

			print(string.format("[PlotService] %s wurde %s zugewiesen.", player.Name, child.Name))

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
				end
			end)

			return
		end
	end

	warn(string.format("[PlotService] Kein freier Plot für %s verfügbar!", player.Name))
end

-- Gibt den Plot frei, wenn der Spieler den Server verlässt
local function releasePlayerPlot(player: Player)
	local plot = PlayerPlots[player]
	if plot then
		plot:SetAttribute("OwnerUserId", 0)
		plot:SetAttribute("OwnerName", "")

		-- Schild zurücksetzen
		local signPost = plot:FindFirstChild("SignPost")
		if signPost then
			local billboard = signPost:FindFirstChild("PlotInfo") :: BillboardGui?
			local label = if billboard then billboard:FindFirstChild("Label") :: TextLabel? else nil
			if label then
				label.Text = string.format("Plot %d - [Frei]", plot:GetAttribute("PlotIndex") or 1)
				label.TextColor3 = Color3.fromRGB(240, 240, 240)
			end
		end

		clearPlotVisuals(plot)
		PlayerPlots[player] = nil
		print(string.format("[PlotService] Plot von %s freigegeben.", player.Name))
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

	for _, player in Players:GetPlayers() do
		task.spawn(assignPlotToPlayer, player)
	end

	Players.PlayerAdded:Connect(assignPlotToPlayer)
	Players.PlayerRemoving:Connect(releasePlayerPlot)

	startCPSLoop()

	print("[PlotService] Initialisiert: Plot-Zuweisung und CPS-Loop aktiv.")
end

return PlotService
