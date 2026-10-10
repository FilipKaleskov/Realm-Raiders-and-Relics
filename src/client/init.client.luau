--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = Shared:WaitForChild("Events")
local GoldUpdated = Events:WaitForChild("GoldUpdated") :: RemoteEvent

GoldUpdated.OnClientEvent:Connect(function(newGold: number, currentCPS: number?)
	print(string.format("[Client] Gold aktualisiert: %d Gold (+%d/s)", newGold, currentCPS or 0))
end)

print("[Client] Realm Raiders Client initialisiert und mit GoldUpdated verbunden.")
