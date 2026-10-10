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
			Profiles[player] = profile
			print(string.format("[DataManager] Profil erfolgreich geladen für %s (%d)", player.Name, player.UserId))
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

-- Öffentliche API: Setzt oder leert einen Statuen-Sockel (1 bis 3)
function DataManager.SetSlot(player: Player, slotIndex: number, coreId: string?): boolean
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
			Level = 1,
		}
	else
		data.BaseData.Slots[slotIndex] = nil
	end

	return true
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
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	print("[DataManager] Initialisiert und an Players gebunden.")
end

return DataManager
