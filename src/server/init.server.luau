--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local PlayerDataModule = Data:WaitForChild("PlayerDataTemplate") :: ModuleScript
local PlayerDataTemplate = require(PlayerDataModule)

print("Realm Raiders Framework initialisiert")
print(string.format(
	"[Init] Start-Gold: %d, Start-Gems: %d, Start-Waffe: %s",
	PlayerDataTemplate.Gold,
	PlayerDataTemplate.Gems,
	PlayerDataTemplate.Inventory.Weapons[1] or "Keine"
))
