local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Melee.Constants)

local MeleeUtilities = {}

-- Utility functions
function MeleeUtilities.disconnectAndClear(connections)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function MeleeUtilities.lerp(a, b, t)
	return a + (b - a) * t
end

function MeleeUtilities.canPlayerDamageHumanoid(player, taggedHumanoid)
	-- Keep existing death check
	if taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent
	local taggedPlayer = Players:GetPlayerFromCharacter(taggedCharacter)

	-- Keep non-player check
	if not taggedPlayer then
		return true
	end

	-- NEW CODE: Check for Hunter-on-Hunter damage
	local attackerRole = player:GetAttribute("Role")
	local targetRole = taggedPlayer:GetAttribute("Role") 

	-- Prevent Hunter-on-Hunter damage
	if attackerRole == "Hunter" and targetRole == "Hunter" then
		return false
	end

	-- Keep existing team check for other cases
	if player.Neutral or taggedPlayer.Neutral then
		return true
	else
		return player.Team ~= taggedPlayer.Team
	end
end

-- Sound utilities
function MeleeUtilities.playSoundFromSource(playerTemplate, target)
	local audioPlayer = playerTemplate:Clone()
	audioPlayer.Parent = target
	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = target
	wire.Parent = audioPlayer
	audioPlayer:Play()
	audioPlayer.Ended:Once(function()
		audioPlayer:Destroy()
	end)
end

function MeleeUtilities.playRandomSoundFromSource(soundTemplates, target)
	local random = Random.new()
	local sounds = soundTemplates:GetChildren()
	local sound = sounds[random:NextInteger(1, #sounds)]
	MeleeUtilities.playSoundFromSource(sound, target)
end

function MeleeUtilities.bindSoundsToAnimationEvents(animation, sounds, target)
	local SOUND_EVENT = "Sound"
	local RANDOM_SOUND_EVENT = "RandomSound"

	animation:GetMarkerReachedSignal(SOUND_EVENT):Connect(function(param)
		local sound = sounds:FindFirstChild(param)
		if not sound then
			return
		end
		MeleeUtilities.playSoundFromSource(sound, target)
	end)

	animation:GetMarkerReachedSignal(RANDOM_SOUND_EVENT):Connect(function(param)
		local folder = sounds:FindFirstChild(param)
		if not folder then
			return
		end
		MeleeUtilities.playRandomSoundFromSource(folder, target)
	end)
end

-- Input categorization (shared with BlasterUtilities)
MeleeUtilities.InputCategory = {
	KeyboardAndMouse = "KeyboardAndMouse",
	Gamepad = "Gamepad",
	Touch = "Touch",
	Unknown = "Unknown",
}

return MeleeUtilities