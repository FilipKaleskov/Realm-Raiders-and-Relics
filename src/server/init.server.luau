--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local PlayerDataModule = Data:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataModule)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local DataManagerModule = Services:WaitForChild("DataManager") :: ModuleScript
local DataManager = require(DataManagerModule)

-- Services initialisieren
DataManager.Init()

print("Realm Raiders Framework initialisiert")
print(string.format(
	"[Init] Start-Gold: %d, Start-Gems: %d, Start-Waffe: %s",
	PlayerDataTemplate.Gold,
	PlayerDataTemplate.Gems,
	PlayerDataTemplate.Inventory.Weapons[1] or "Keine"
))
