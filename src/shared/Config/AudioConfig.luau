--!strict
-- AudioConfig.luau
-- Zentrales Audio-Verzeichnis für "Realm Raiders & Relics" (Phase 2: Audio, Combat Juice & Game Feel).
--
-- Enthält:
--   1. Getaggte Sound-IDs + Standard-Lautstärken (alle offizielle Roblox-Assets: rbxassetid://...)
--   2. Universellen AudioHelper mit Pitch-Randomisierung (PlaybackSpeed 92%-108%) gegen "Ear Fatigue"
--   3. Garantiertes Memory-Management: Jeder temporäre Sound wird nach Abspielen restlos entfernt
--      (Ended-Callback + Debris:AddItem-Sicherheitsnetz).

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

export type SoundTag =
	"SwordSwing"
	| "SwordHitFlesh"
	| "SwordHitStone"
	| "DashWhoosh"
	| "CoinGain"
	| "AltarMeltSuccess"
	| "RaidAlarmSiren"
	| "BossRoar"
	| "BossSlamImpact"

export type SoundDefinition = {
	Id: string, -- Offizielles Roblox-Asset (rbxassetid://...)
	Volume: number, -- Standard-Lautstärke (0-10)
	PitchVariance: number, -- Maximale Pitch-Abweichung (0.08 = 92%-108% PlaybackSpeed)
	RollOffMinDistance: number?, -- Nur für 3D-Sounds (Distanzdämpfung)
	RollOffMaxDistance: number?, -- Nur für 3D-Sounds (Distanzdämpfung)
}

-- Die hier gebaute Tabelle ist der universelle AudioHelper. Da die Datei AudioConfig.luau heißt,
-- ist der Helfer nach dem require als `AudioConfig.PlaySound(...)` / `AudioConfig.PlayTag(...)` verfügbar.
local AudioHelper = {}

-- ====================================================
-- 1. GETAGGTE SOUND-REGISTRY
-- ====================================================
local Sounds: { [SoundTag]: SoundDefinition } = {
	-- Klingen-Whoosh beim Schlagen
	SwordSwing = {
		Id = "rbxassetid://9114223171",
		Volume = 0.55,
		PitchVariance = 0.08,
	},
	-- Wuchtiger Treffersound bei Gegnern (Fleisch/Knochen)
	SwordHitFlesh = {
		Id = "rbxassetid://566593606",
		Volume = 0.75,
		PitchVariance = 0.06,
	},
	-- Golem-/Steintreffer (harter Prall auf Fels & Rinde)
	SwordHitStone = {
		Id = "rbxassetid://3932505023",
		Volume = 0.8,
		PitchVariance = 0.06,
	},
	-- Windstoß / Energie-Zischen beim Dash
	DashWhoosh = {
		Id = "rbxassetid://134012322",
		Volume = 0.7,
		PitchVariance = 0.1,
	},
	-- Fröhliches, helles Münzklingeln beim Kassieren
	CoinGain = {
		Id = "rbxassetid://5153734608",
		Volume = 0.7,
		PitchVariance = 0.12,
	},
	-- Majestätischer Gold-Gong / Magie-Burst beim Einschmelzen am Altar
	AltarMeltSuccess = {
		Id = "rbxassetid://6895079853",
		Volume = 0.9,
		PitchVariance = 0.04,
	},
	-- Schrilles Warnhorn / Sirene beim Opfer eines Raubs (Walk of Shame)
	RaidAlarmSiren = {
		Id = "rbxassetid://9069609267",
		Volume = 0.85,
		PitchVariance = 0.02,
	},
	-- Tiefes Monsterbrüllen (3D mit Distanzdämpfung, weithin hörbar im Wald-Ruinen-Areal)
	BossRoar = {
		Id = "rbxassetid://9069608465",
		Volume = 1.0,
		PitchVariance = 0.08,
		RollOffMinDistance = 18,
		RollOffMaxDistance = 420,
	},
	-- Erdbebenartiger Basstreffer beim AoE-Aufschlag des Golems
	BossSlamImpact = {
		Id = "rbxassetid://138090596",
		Volume = 1.0,
		PitchVariance = 0.06,
		RollOffMinDistance = 12,
		RollOffMaxDistance = 240,
	},
}

AudioHelper.Sounds = Sounds

-- ====================================================
-- 2. UNIVERS-HELPER (AudioHelper)
-- ====================================================

-- Erzeugt & spielt einen Sound mit Pitch-Randomisierung und garantiertem Memory-Cleanup.
--   soundId        = "rbxassetid://..." (Pflicht)
--   volume         = Lautstärke 0-10 (Standard: 0.8)
--   pitchVariance  = z.B. 0.08 -> PlaybackSpeed = math.random(92, 108) / 100 (Standard: 0.08)
--   parentPart     = nil  -> 2D-Sound (SoundService, immer hörbar)
--                    BasePart -> 3D-positionierter Sound mit Distanzdämpfung
function AudioHelper.PlaySound(
	soundId: string,
	volume: number?,
	pitchVariance: number?,
	parentPart: Instance?,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = math.clamp(volume or 0.8, 0, 10)

	-- Pitch-Randomisierung: Verhindert repetitive Ermüdung ("Ear Fatigue") bei
	-- wiederkehrenden Aktionen wie Schwertschwüngen, Treffern oder Münzen.
	local variance = math.clamp(pitchVariance or 0.08, 0, 0.9)
	local jitter = math.floor(variance * 100)
	local playbackPercent = math.random(100 - jitter, 100 + jitter)
	sound.PlaybackSpeed = playbackPercent / 100

	if parentPart and parentPart:IsA("BasePart") then
		-- 3D-Distanzdämpfung für räumliches Audio
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = rollOffMinDistance or 10
		sound.RollOffMaxDistance = rollOffMaxDistance or 250
		sound.Parent = parentPart
	else
		-- 2D-Sound (nicht positioniert) - z.B. UI-Feedback & eigene Combat-Sounds
		sound.Parent = parentPart or SoundService
	end

	sound:Play()

	-- Memory-Management: Nach Ablauf des Sounds restlos entfernen (Ended-Callback),
	-- zusätzlich Debris-Sicherheitsnetz, falls das Asset nicht (rechtzeitig) lädt.
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	local length = sound.TimeLength
	local lifetime = if length > 0
		then (length / math.max(sound.PlaybackSpeed, 0.05)) + 1.5
		else 6
	Debris:AddItem(sound, lifetime)

	return sound
end

-- Spielt einen Sound-Tag aus der Registry mit allen hinterlegten Standardwerten
-- (Lautstärke, Pitch-Varianz & optionaler 3D-Distanzdämpfung).
function AudioHelper.PlayTag(tag: SoundTag, parentPart: Instance?): Sound
	local definition = Sounds[tag]
	return AudioHelper.PlaySound(
		definition.Id,
		definition.Volume,
		definition.PitchVariance,
		parentPart,
		definition.RollOffMinDistance,
		definition.RollOffMaxDistance
	)
end

return AudioHelper
