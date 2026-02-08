-- ServerEventHandler.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PropHealthSystem = require(script.Parent.PropHealthSystem)
local KillMessageRepository = require(script.Parent.Misc.KillMessageRepository)
local serverEvent = ServerScriptService.Event
local Players = game:GetService("Players")
local RemoteEvent = ReplicatedStorage.RemoteEvent

-- Debug flag
local DEBUG_MODE = true
local function debugLog(message)
	if DEBUG_MODE then
		print("🔍 [ServerEventHandler] " .. message)
	end
end

-- Function to play death sound
function PlayDeathSound(killer, victim)
	-- Get the PlayerManager instance for the killer
	local PlayerManager = require(script.Parent.Player.PlayerManager)
	local killerManager = PlayerManager.ActivePlayers[killer]

	if not killerManager then
		warn("PlayerManager not found for killer: " .. killer.Name)
		return
	end

	-- Get active death sound from killer's loadout
	local activeDeathSound = killerManager:GetActiveDeathSound()
	if not activeDeathSound then
		warn("No active death sound found for " .. killer.Name)
		return
	end

	-- Create sound in workspace at victim's position
	local sound = Instance.new("Sound")

	-- Try to get the sound from ReplicatedStorage
	print(activeDeathSound)
	local deathSounds = ReplicatedStorage:FindFirstChild("Sounds")
	if deathSounds and deathSounds:FindFirstChild("DeathSounds") and 
		deathSounds.DeathSounds:FindFirstChild(activeDeathSound) then
		sound.SoundId = deathSounds.DeathSounds[activeDeathSound].SoundId
	else
		-- Fallback to a default sound if the specific death sound isn't found
		sound.SoundId = "rbxassetid://5665642891" -- Replace with appropriate fallback sound ID
	end

	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 100

	-- Attach sound to victim's character for proper 3D positioning
	if victim.Character then
		if victim.Character:FindFirstChild("HumanoidRootPart") then
			sound.Parent = victim.Character.HumanoidRootPart
		else
			sound.Parent = workspace
			sound.Position = victim.Character:GetPivot().Position
		end
	end

	-- Play the sound
	sound:Play()

	-- Cleanup when done
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

serverEvent.Event:Connect(function(eventName, data)
	if DEBUG_MODE then
		debugLog("Received event: " .. eventName)
	end

	-- Handle legacy hit events (for backward compatibility)
	if eventName == "Blaster_Tagged" then
		local player = data.player
		local humanoid = data.humanoid
		local damage = data.damage

		-- Get the player who was hit
		local hitPlayer = Players:GetPlayerFromCharacter(data.humanoid.Parent)
		if hitPlayer then
			-- Make their health highlight flash
			print('hit')
			PropHealthSystem.onPlayerHit(hitPlayer.UserId)
		end

		print(player.Name .. " tagged a target for " .. damage .. " damage")
	elseif eventName == "Melee_Tagged" then
		local player = data.player
		local humanoid = data.humanoid
		local damage = data.damage

		-- Get the player who was hit
		local hitPlayer = Players:GetPlayerFromCharacter(data.humanoid.Parent)
		if hitPlayer then
			-- Make their health highlight flash
			print('melee hit')
			PropHealthSystem.onPlayerHit(hitPlayer.UserId)
		end

		print(player.Name .. " melee tagged a target for " .. damage .. " damage")

		-- New unified player hit event
	elseif eventName == "Player_Hit" then
		local victim = data.victim
		local attacker = data.attacker

		if not victim or not attacker then return end

		-- Visual effects for hit
		PropHealthSystem.onPlayerHit(victim.UserId)

		print(attacker.Name .. " hit " .. victim.Name .. " with " .. (data.weaponName or "unknown weapon"))

		-- New unified elimination event
	elseif eventName == "Player_Eliminated" then
		if DEBUG_MODE then
			debugLog("Processing Player_Eliminated event")
		end

		local victim = data.victim
		local killer = data.killer
		local weaponName = data.weaponName
		local victimHumanoid = data.humanoid

		if not victim or not killer or not victimHumanoid then
			if DEBUG_MODE then debugLog("❌ Missing data in Player_Eliminated event") end
			return
		end

		if DEBUG_MODE then
			debugLog("👤 Victim: " .. victim.Name .. ", Killer: " .. killer.Name .. ", Weapon: " .. (weaponName or "Unknown"))
		end

		-- CRITICAL FIX: Set PendingHunterTransition FIRST before everything else
		-- This ensures the death handler knows not to auto-respawn this player
		if victim:GetAttribute("Role") == "Prop" then
			debugLog("🎭 Setting PendingHunterTransition flag FIRST for: " .. victim.Name)
			victim:SetAttribute("PendingHunterTransition", true)
			victim:SetAttribute("ManualRespawn", true)
		end

		-- Get victim character
		local victimCharacter = victimHumanoid.Parent

		-- Mark character with elimination info (backup)
		if victimCharacter then
			victimCharacter:SetAttribute("KilledBy", killer.UserId)
			victimCharacter:SetAttribute("KilledWith", weaponName or "Unknown")
		end

		-- Get random kill message
		local killMessage = KillMessageRepository.GetRandomKillMessage(victim.Name)
		local killData = {
			victimName = victim.Name,
			weaponName = weaponName or "Unknown",
			message = killMessage
		}

		-- Send kill feed to all clients
		for _, player in ipairs(Players:GetPlayers()) do
			RemoteEvent:FireClient(player, "KillFeed", killData)
		end

		-- Calculate survival time for the victim
		local joinTime = victim:GetAttribute("JoinTime") or os.time()
		local survivalTime = math.floor(os.time() - joinTime)

		-- Send death screen event ONLY to the victim
		RemoteEvent:FireClient(victim, "ShowDeathScreen", {
			survivalTime = survivalTime,
			killerUserId = killer.UserId
		})

		if DEBUG_MODE then
			debugLog("✅ Fired ShowDeathScreen to " .. victim.Name)
		end

		-- Play death sound
		PlayDeathSound(killer, victim)

		-- Handle legacy elimination events (for backward compatibility)
		-- These should eventually be removed once everything uses the new system
	elseif eventName == "Blaster_Eliminated" then
		-- Deprecated - use Player_Eliminated instead
		if DEBUG_MODE then debugLog("⚠️ Using deprecated Blaster_Eliminated event") end
	elseif eventName == "Melee_Eliminated" then
		-- Deprecated - use Player_Eliminated instead
		if DEBUG_MODE then debugLog("⚠️ Using deprecated Melee_Eliminated event") end

		-- Other event types
	elseif eventName == "Economy_Purchase" then
		-- Handle economy events
	elseif eventName == "Round_Start" then
		-- Handle round events
	end
end)