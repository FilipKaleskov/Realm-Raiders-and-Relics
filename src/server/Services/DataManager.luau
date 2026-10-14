--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Shared Abhängigkeiten
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataFolder = Shared:WaitForChild("Data")
local PlayerDataTemplateModule = DataFolder:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataTemplateModule)

export type PlayerData = PlayerDataTemplate.PlayerData
export type BaseSlot = PlayerDataTemplate.BaseSlot

-- Packages & ProfileService
local Server = ServerScriptService:WaitForChild("Server")
local Packages = Server:WaitForChild("Packages")
local ProfileServiceModule = Packages:WaitForChild("ProfileService") :: ModuleScript
local ProfileService = require(ProfileServiceModule)

-- Typen für ProfileService-Schnittstelle
type Profile = {
	Data: PlayerData,
	MetaData: { [string]: any },
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	ListenToRelease: (self: Profile, callback: () -> ()) -> any,
	Release: (self: Profile) -> (),
	IsActive: (self: Profile) -> boolean,
}

type ProfileStore = {
	LoadProfileAsync: (self: ProfileStore, profileKey: string) -> Profile?,
}

-- Initialisierung des ProfileStores
local ProfileStore: ProfileStore = (ProfileService :: any).GetProfileStore(
	"PlayerData_v1",
	PlayerDataTemplate
)

-- Events Folder & Remotes
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

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = name
	newRemote.Parent = parent
	return newRemote
end

local ConfigFolder = Shared:WaitForChild("Config")
local ItemConfigModule = ConfigFolder:WaitForChild("ItemConfig") :: ModuleScript
local ItemConfig = require(ItemConfigModule)

local EventsFolder = getOrCreateEventsFolder()
local InventoryUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "InventoryUpdated")
local RequestInventoryEvent = getOrCreateRemoteEvent(EventsFolder, "RequestInventory")
local GoldUpdatedEvent = getOrCreateRemoteEvent(EventsFolder, "GoldUpdated")
local ShowNotificationEvent = getOrCreateRemoteEvent(EventsFolder, "ShowNotification")
local BuyWeaponIntentEvent = getOrCreateRemoteEvent(EventsFolder, "BuyWeaponIntent")
local EquipWeaponIntentEvent = getOrCreateRemoteEvent(EventsFolder, "EquipWeaponIntent")
local UnlockSlotIntentEvent = getOrCreateRemoteEvent(EventsFolder, "UnlockSlotIntent")
local BuyDefenseIntentEvent = getOrCreateRemoteEvent(EventsFolder, "BuyDefenseIntent")

local function getPlotService()
	return require(ServerScriptService.Server.Services.PlotService)
end

local function getDefenseService()
	return require(ServerScriptService.Server.Services.DefenseService)
end

local Profiles: { [Player]: Profile } = {}
local isInitialized = false

local DataManager = {}

-- Intern: Wenn ein Spieler beitritt
local function onPlayerAdded(player: Player)
	local profileKey = "Player_" .. player.UserId
	local profile = ProfileStore:LoadProfileAsync(profileKey)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick("Dein Profil wurde auf einem anderen Server geladen oder die Sitzung wurde beendet.")
		end)

		if player:IsDescendantOf(Players) then
			-- Reconcile für neue Schema-Eigenschaften
			local data = profile.Data
			if data.Inventory then
				if data.Inventory.EquippedWeapon == nil then
					data.Inventory.EquippedWeapon = if data.Inventory.Weapons and data.Inventory.Weapons[1]
						then data.Inventory.Weapons[1]
						else "RustySword"
				end
			end
			if data.BaseData then
				if data.BaseData.UnlockedSlots == nil then
					data.BaseData.UnlockedSlots = {
						[1] = true,
						[2] = false,
						[3] = false,
					}
				end
			end

			Profiles[player] = profile
			print(string.format("[DataManager] Profil erfolgreich geladen für %s (%d)", player.Name, player.UserId))
			task.defer(function()
				DataManager.SyncInventory(player)
			end)
		else
			-- Spieler hat den Server während des Ladens bereits verlassen
			profile:Release()
		end
	else
		-- Profil konnte nicht geladen werden (z. B. DataStore-Ausfall oder Session-Lock)
		player:Kick("Spielerdaten konnten nicht geladen werden. Bitte trete dem Server erneut bei.")
	end
end

-- Intern: Wenn ein Spieler den Server verlässt
local function onPlayerRemoving(player: Player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
		Profiles[player] = nil
		print(string.format("[DataManager] Profil freigegeben für %s (%d)", player.Name, player.UserId))
	end
end

-- Öffentliche API: Liest die Profildaten des Spielers
function DataManager.Get(player: Player): PlayerData?
	local profile = Profiles[player]
	if profile ~= nil and profile:IsActive() then
		return profile.Data
	end
	return nil
end

-- Öffentliche API: Fügt Gold hinzu oder zieht Gold ab (thread-sicher & validiert)
function DataManager.AddGold(player: Player, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	local data = profile.Data
	if amount < 0 and (data.Gold + amount < 0) then
		return false -- Nicht ausreichend Gold vorhanden
	end

	data.Gold = math.max(0, data.Gold + amount)
	return true
end

-- Öffentliche API: Setzt oder leert einen Statuen-Sockel (1 bis 3) mit optionaler Stufe
function DataManager.SetSlot(player: Player, slotIndex: number, coreId: string?, level: number?): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	if slotIndex < 1 or slotIndex > 3 or math.floor(slotIndex) ~= slotIndex then
		return false -- Ungültiger Sockel-Index
	end

	local data = profile.Data
	if data.BaseData == nil or data.BaseData.Slots == nil then
		return false
	end

	if coreId ~= nil then
		data.BaseData.Slots[slotIndex] = {
			CoreId = coreId,
			Level = level or 1,
		}
	else
		data.BaseData.Slots[slotIndex] = nil
	end

	return true
end

-- Öffentliche API: Synchronisiert das Inventar eines Spielers mit dessen Client
function DataManager.SyncInventory(player: Player)
	local profile = Profiles[player]
	if profile ~= nil and profile:IsActive() then
		InventoryUpdatedEvent:FireClient(player, profile.Data.Inventory)
	end
end

-- Öffentliche API: Fügt einen Kern mit Stufe zum Inventar hinzu
function DataManager.AddCore(player: Player, coreId: string, level: number?): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	table.insert(profile.Data.Inventory.Cores, {
		CoreId = coreId,
		Level = level or 1,
	} :: any)
	DataManager.SyncInventory(player)
	return true
end

-- Öffentliche API: Entfernt einen bestimmten Kern aus dem Inventar und liefert dessen Stufe zurück
function DataManager.RemoveCore(player: Player, coreId: string, preferredLevel: number?): (boolean, number)
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, 1
	end

	local cores = profile.Data.Inventory.Cores
	-- 1. Pass: Wenn preferredLevel angegeben ist, suche nach exakter Übereinstimmung
	if preferredLevel ~= nil then
		for i, entry in ipairs(cores) do
			local cId = if typeof(entry) == "table" then (entry :: any).CoreId else entry
			local cLevel = if typeof(entry) == "table" then ((entry :: any).Level or 1) else 1
			if cId == coreId and cLevel == preferredLevel then
				table.remove(cores, i)
				DataManager.SyncInventory(player)
				return true, cLevel
			end
		end
	end

	-- 2. Pass: Erste passende CoreId
	for i, entry in ipairs(cores) do
		local cId = if typeof(entry) == "table" then (entry :: any).CoreId else entry
		local cLevel = if typeof(entry) == "table" then ((entry :: any).Level or 1) else 1
		if cId == coreId then
			table.remove(cores, i)
			DataManager.SyncInventory(player)
			return true, cLevel
		end
	end
	return false, 1
end

-- Öffentliche API: Fügt eine Waffe zum Inventar hinzu
function DataManager.AddWeapon(player: Player, weaponId: string): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	table.insert(profile.Data.Inventory.Weapons, weaponId)
	DataManager.SyncInventory(player)
	return true
end

-- Öffentliche API: Modifiziert Materialmenge im Inventar
function DataManager.AddMaterial(player: Player, materialKey: "IronOre" | "VoidCrystal", amount: number): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	local current = profile.Data.Inventory.Materials[materialKey] or 0
	if current + amount < 0 then
		return false
	end

	profile.Data.Inventory.Materials[materialKey] = current + amount
	DataManager.SyncInventory(player)
	return true
end

-- Öffentliche API: Wertet einen Sockel auf und zieht die Kosten ab
function DataManager.UpgradeSlot(player: Player, slotIndex: number, cost: number): boolean
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	local data = profile.Data
	local slot = data.BaseData.Slots[slotIndex]
	if not slot or not slot.CoreId then
		return false
	end

	if data.Gold < cost then
		return false -- Nicht genügend Gold
	end

	data.Gold -= cost
	slot.Level += 1
	return true
end

-- Öffentliche API: Rüstet eine Waffe aus, falls der Spieler sie besitzt
function DataManager.EquipWeapon(player: Player, weaponId: string): (boolean, string)
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, "Profil nicht aktiv"
	end

	local weapons = profile.Data.Inventory.Weapons
	if not table.find(weapons, weaponId) then
		return false, "Du besitzt diese Waffe nicht!"
	end

	profile.Data.Inventory.EquippedWeapon = weaponId
	DataManager.SyncInventory(player)
	local itemInfo = ItemConfig[weaponId]
	local name = if itemInfo then itemInfo.DisplayName else weaponId
	return true, string.format("🗡️ %s ausgerüstet!", name)
end

-- Öffentliche API: Kauft und schmiedet eine Waffe
function DataManager.BuyWeapon(player: Player, weaponId: string): (boolean, string)
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, "Profil nicht aktiv"
	end

	local itemInfo = ItemConfig[weaponId]
	if not itemInfo or itemInfo.Category ~= "Weapon" then
		return false, "Ungültige Waffe!"
	end

	local data = profile.Data
	if table.find(data.Inventory.Weapons, weaponId) then
		-- Wenn bereits gekauft, rüste sie direkt aus
		return DataManager.EquipWeapon(player, weaponId)
	end

	local costGold = itemInfo.CostGold or 0
	if data.Gold < costGold then
		return false, string.format("Nicht genug Gold! Du benötigst %d Gold.", costGold)
	end

	local costMats = itemInfo.CostMaterials or {}
	for matKey, requiredAmount in pairs(costMats) do
		local currentAmount = data.Inventory.Materials[matKey] or 0
		if currentAmount < requiredAmount then
			local matInfo = ItemConfig[matKey]
			local matName = if matInfo then matInfo.DisplayName else matKey
			return false, string.format("Nicht genug %s! Benötigt: %d (Du hast: %d)", matName, requiredAmount, currentAmount)
		end
	end

	-- Transaktion durchführen
	data.Gold -= costGold
	for matKey, requiredAmount in pairs(costMats) do
		data.Inventory.Materials[matKey] = (data.Inventory.Materials[matKey] or 0) - requiredAmount
	end

	table.insert(data.Inventory.Weapons, weaponId)
	data.Inventory.EquippedWeapon = weaponId

	DataManager.SyncInventory(player)
	GoldUpdatedEvent:FireClient(player, data.Gold)

	return true, string.format("🎉 %s erfolgreich geschmiedet und ausgerüstet!", itemInfo.DisplayName)
end

-- Öffentliche API: Schaltet einen gesperrten Statuen-Sockel auf der Basis frei
function DataManager.UnlockSlot(player: Player, slotIndex: number): (boolean, string)
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, "Profil nicht aktiv"
	end

	if slotIndex < 2 or slotIndex > 3 then
		return false, "Ungültiger Sockel-Index"
	end

	local data = profile.Data
	if data.BaseData.UnlockedSlots and data.BaseData.UnlockedSlots[slotIndex] == true then
		return false, "Dieser Sockel ist bereits freigeschaltet!"
	end

	local shopConfig = (ItemConfig :: any).Shop
	local unlockInfo = if shopConfig and shopConfig.SlotUnlocks then shopConfig.SlotUnlocks[slotIndex] else nil
	local cost = if unlockInfo then unlockInfo.CostGold else (if slotIndex == 2 then 500 else 2000)

	if data.Gold < cost then
		return false, string.format("Nicht genug Gold! Freischaltung kostet %d Gold.", cost)
	end

	data.Gold -= cost
	if not data.BaseData.UnlockedSlots then
		data.BaseData.UnlockedSlots = { [1] = true, [2] = false, [3] = false }
	end
	data.BaseData.UnlockedSlots[slotIndex] = true

	-- Plot visualisieren & CPS updaten
	local plotService = getPlotService()
	plotService.UpdatePlotVisuals(player)
	GoldUpdatedEvent:FireClient(player, data.Gold, plotService.CalculateCPS(player))

	return true, string.format("🏰 Sockel %d erfolgreich freigeschaltet!", slotIndex)
end

-- Öffentliche API: Kauft Basis-Verteidigung (Stachelfallen oder Wächter-Minions)
function DataManager.BuyDefense(player: Player, defenseType: "Spikes" | "Guards"): (boolean, string)
	local profile = Profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, "Profil nicht aktiv"
	end

	local shopConfig = (ItemConfig :: any).Shop
	local defInfo = if shopConfig and shopConfig.Defenses then shopConfig.Defenses[defenseType] else nil
	if not defInfo then
		return false, "Ungültiger Verteidigungs-Typ"
	end

	local data = profile.Data
	local currentCount = data.BaseData.Defenses[defenseType] or 0
	if currentCount >= defInfo.MaxCount then
		return false, string.format("Maximale Anzahl an %s erreicht! (Max: %d)", defInfo.DisplayName, defInfo.MaxCount)
	end

	if data.Gold < defInfo.CostGold then
		return false, string.format("Nicht genug Gold! Kostet %d Gold.", defInfo.CostGold)
	end

	for matKey, requiredAmount in pairs(defInfo.CostMaterials) do
		local currentAmount = data.Inventory.Materials[matKey] or 0
		if currentAmount < requiredAmount then
			local matInfo = ItemConfig[matKey]
			local matName = if matInfo then matInfo.DisplayName else matKey
			return false, string.format("Nicht genug %s! Benötigt: %d (Du hast: %d)", matName, requiredAmount, currentAmount)
		end
	end

	-- Transaktion
	data.Gold -= defInfo.CostGold
	for matKey, requiredAmount in pairs(defInfo.CostMaterials) do
		data.Inventory.Materials[matKey] = (data.Inventory.Materials[matKey] or 0) - requiredAmount
	end

	data.BaseData.Defenses[defenseType] = currentCount + 1

	-- Defenses auf Plot sofort neu aufbauen
	local plotService = getPlotService()
	local plot = plotService.GetPlayerPlot(player)
	if plot then
		local defenseService = getDefenseService()
		defenseService.SetupPlotDefenses(plot, player.UserId)
	end

	DataManager.SyncInventory(player)
	GoldUpdatedEvent:FireClient(player, data.Gold, plotService.CalculateCPS(player))

	return true, string.format("🛡️ %s erfolgreich aufgestellt! (%d/%d)", defInfo.DisplayName, currentCount + 1, defInfo.MaxCount)
end

local requestInventoryCooldowns: { [Player]: number } = {}

-- Intern: Wenn ein Spieler den Server verlässt (mit Cooldown-Bereinigung)
local function handlePlayerRemoving(player: Player)
	requestInventoryCooldowns[player] = nil
	onPlayerRemoving(player)
end

-- Initialisiert den DataManager und bindet die Player-Events an
function DataManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)

	-- Client-Anfrage für Inventar-Sync mit Rate-Limiting (SE-5 Schutz vor Flooding)
	RequestInventoryEvent.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		local lastReq = requestInventoryCooldowns[player] or 0
		if now - lastReq < 0.5 then
			return
		end
		requestInventoryCooldowns[player] = now
		DataManager.SyncInventory(player)
	end)

	local shopActionCooldowns: { [Player]: number } = {}

	-- Waffe schmieden / kaufen
	BuyWeaponIntentEvent.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if typeof(weaponId) ~= "string" then return end
		local now = os.clock()
		if now - (shopActionCooldowns[player] or 0) < 0.25 then return end
		shopActionCooldowns[player] = now

		local success, message = DataManager.BuyWeapon(player, weaponId)
		ShowNotificationEvent:FireClient(player, message, not success)
	end)

	-- Waffe ausrüsten
	EquipWeaponIntentEvent.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if typeof(weaponId) ~= "string" then return end
		local now = os.clock()
		if now - (shopActionCooldowns[player] or 0) < 0.25 then return end
		shopActionCooldowns[player] = now

		local success, message = DataManager.EquipWeapon(player, weaponId)
		ShowNotificationEvent:FireClient(player, message, not success)
	end)

	-- Sockel freischalten
	UnlockSlotIntentEvent.OnServerEvent:Connect(function(player: Player, slotIndex: any)
		if typeof(slotIndex) ~= "number" then return end
		local now = os.clock()
		if now - (shopActionCooldowns[player] or 0) < 0.25 then return end
		shopActionCooldowns[player] = now

		local success, message = DataManager.UnlockSlot(player, slotIndex)
		ShowNotificationEvent:FireClient(player, message, not success)
	end)

	-- Verteidigung kaufen
	BuyDefenseIntentEvent.OnServerEvent:Connect(function(player: Player, defenseType: any)
		if defenseType ~= "Spikes" and defenseType ~= "Guards" then return end
		local now = os.clock()
		if now - (shopActionCooldowns[player] or 0) < 0.25 then return end
		shopActionCooldowns[player] = now

		local success, message = DataManager.BuyDefense(player, defenseType)
		ShowNotificationEvent:FireClient(player, message, not success)
	end)

	-- Server-Shutdown Absicherung (SE-6: BindToClose Timeout - paralleles Freigeben aller Profile)
	game:BindToClose(function()
		local activePlayers = Players:GetPlayers()
		if #activePlayers == 0 then
			return
		end

		local completed = 0
		local total = #activePlayers
		for _, player in activePlayers do
			task.spawn(function()
				local profile = Profiles[player]
				if profile ~= nil then
					profile:Release()
					Profiles[player] = nil
				end
				completed += 1
			end)
		end

		local deadline = os.clock() + 15
		while completed < total and os.clock() < deadline do
			task.wait(0.1)
		end
		print(string.format("[DataManager] BindToClose abgeschlossen: %d/%d Profile freigegeben.", completed, total))
	end)

	print("[DataManager] Initialisiert und an Players gebunden.")
end

return DataManager
