-- RespawnHandler.lua (Server Script)
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local connections = {} -- Store outside any function to maintain persistence
local BLASTER_DEATH_DELAY = 6  -- Longer delay for ragdoll effect
local NORMAL_DEATH_DELAY = 3   -- Standard 3-second respawn time

-- Add a debounce mechanism to prevent multiple death processing
local recentDeaths = {}
local DEATH_DEBOUNCE_TIME = 1 -- 1 second debounce

-- Add serverEvent connection
local serverEvent = ServerScriptService:WaitForChild("Event")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- DEBUGGING: Add more detailed debug logs
local DEBUG_MODE = true
local function debugLog(message)
	if DEBUG_MODE then
		print("📝 [RespawnHandler] " .. message)
	end
end

-- Inside RespawnHandler.lua
local function onPlayerDied(player)
	-- Check if this death was recently processed
	local playerId = player.UserId
	local now = os.time()
	if recentDeaths[playerId] and (now - recentDeaths[playerId]) < DEATH_DEBOUNCE_TIME then
		debugLog("⚠️ Ignoring duplicate death for " .. player.Name)
		return
	end

	-- Mark this death as processed
	recentDeaths[playerId] = now

	debugLog("⚰️ onPlayerDied called for " .. player.Name)
	debugLog("   PendingHunterTransition = " .. tostring(player:GetAttribute("PendingHunterTransition")))
	debugLog("   ManualRespawn = " .. tostring(player:GetAttribute("ManualRespawn")))
	debugLog("   Role = " .. tostring(player:GetAttribute("Role")))

	-- CRITICAL FIX: Check PendingHunterTransition attribute FIRST
	-- This must be the very first check so these players never auto-respawn
	if player:GetAttribute("PendingHunterTransition") then
		debugLog("🔄 Player is marked for future Hunter transition: " .. player.Name)

		-- Ensure ManualRespawn is set to prevent auto-respawn
		player:SetAttribute("ManualRespawn", true)

		-- Get the character's killer if available
		local character = player.Character
		local killerUserId = nil
		if character and character:GetAttribute("KilledBy") then
			killerUserId = character:GetAttribute("KilledBy")
		end

		-- Show death screen
		debugLog("Showing death screen for transitioning player")
		RemoteEvent:FireClient(player, "ShowDeathScreen", {
			survivalTime = os.time() - (player:GetAttribute("JoinTime") or os.time()),
			killerUserId = killerUserId
		})

		-- CRITICAL: Do not continue with normal respawn logic
		-- Player stays on death screen until they click respawn button
		return
	end

	-- Secondary check: if player is a prop, we should mark them for transition
	-- This handles cases where the elimination event comes in after death
	if player:GetAttribute("Role") == "Prop" then
		debugLog("🎭 Prop player died without transition flag: " .. player.Name .. " - Setting flag now")

		-- Set pending transition flag
		player:SetAttribute("PendingHunterTransition", true)

		-- Ensure ManualRespawn is set to prevent auto-respawn
		player:SetAttribute("ManualRespawn", true)

		-- Get the character's killer if available
		local character = player.Character
		local killerUserId = nil
		if character and character:GetAttribute("KilledBy") then
			killerUserId = character:GetAttribute("KilledBy")
		end

		-- Show death screen
		debugLog("Showing death screen for prop player")
		RemoteEvent:FireClient(player, "ShowDeathScreen", {
			survivalTime = os.time() - (player:GetAttribute("JoinTime") or os.time()),
			killerUserId = killerUserId
		})

		-- CRITICAL: Do not continue with normal respawn logic
		return
	end

	-- Check if player's character has elimination attributes (backup method)
	local character = player.Character
	if character and character:GetAttribute("KilledBy") then
		local killerUserId = character:GetAttribute("KilledBy")

		-- IMPROVED: Always ensure ManualRespawn is set for eliminated players
		if not player:GetAttribute("ManualRespawn") then
			debugLog("⚠️ Character has KilledBy but ManualRespawn not set! Setting now...")
			player:SetAttribute("ManualRespawn", true)

			-- Fire death screen event
			RemoteEvent:FireClient(player, "ShowDeathScreen", {
				survivalTime = os.time() - (player:GetAttribute("JoinTime") or os.time()),
				killerUserId = killerUserId
			})

			-- Return to prevent auto-respawn
			return
		end
	end

	-- Check if player is marked for manual respawn via DeathScreen
	if player:GetAttribute("ManualRespawn") then
		debugLog("Manual respawn enabled for " .. player.Name .. " - Skipping auto-respawn")
		return
	end

	-- Continue with original respawn logic for other cases
	if player:GetAttribute("BlasterDeath") then
		debugLog("Blaster death for " .. player.Name .. " - Delayed respawn")
		player:SetAttribute("BlasterDeath", nil)
		task.delay(BLASTER_DEATH_DELAY, function()
			if player and player:IsDescendantOf(game) then
				debugLog("Respawning after blaster death: " .. player.Name)
				player:LoadCharacter()
			end
		end)
	else
		debugLog("Normal death for " .. player.Name .. " - Standard respawn")
		-- New 3-second delay for normal deaths
		task.delay(NORMAL_DEATH_DELAY, function()
			if player and player:IsDescendantOf(game) then
				debugLog("Respawning after normal death: " .. player.Name)
				player:LoadCharacter()
			end
		end)
	end
end

-- Setup character death handling
local function setupCharacter(player, character)
	debugLog("Setting up character for " .. player.Name)
	local humanoid = character:WaitForChild("Humanoid")
	-- Store connection
	if connections[player.UserId] and connections[player.UserId].died then
		connections[player.UserId].died:Disconnect()
	end
	connections[player.UserId] = connections[player.UserId] or {}
	connections[player.UserId].died = humanoid.Died:Connect(function()
		onPlayerDied(player)
	end)
end

-- Handle new players
Players.PlayerAdded:Connect(function(player)
	debugLog("Player joined: " .. player.Name)
	-- First set up the CharacterAdded connection
	connections[player.UserId] = connections[player.UserId] or {}
	connections[player.UserId].characterAdded = player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	player:LoadCharacter()
end)

-- Handle existing players when the script starts
for _, player in ipairs(Players:GetPlayers()) do
	debugLog("Setting up existing player: " .. player.Name)
	-- Connect to CharacterAdded
	connections[player.UserId] = connections[player.UserId] or {}
	connections[player.UserId].characterAdded = player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	-- If they already have a character, set it up
	if player.Character then
		setupCharacter(player, player.Character)
	else
		-- If they don't have a character, spawn one
		player:LoadCharacter()
	end
end

-- Connect to the unified elimination event
serverEvent.Event:Connect(function(eventName, data)
	if eventName == "Player_Eliminated" then
		-- This will be a backup for cases where the event fires after death
		-- The main prop transition handling happens in onPlayerDied
		if data and data.victim then
			local victim = data.victim
			if victim:GetAttribute("Role") == "Prop" then
				debugLog("Setting PendingHunterTransition flag for eliminated prop: " .. victim.Name)

				-- Use PendingHunterTransition to mark for future transition
				victim:SetAttribute("PendingHunterTransition", true)

				-- Ensure ManualRespawn is set to prevent auto-respawn
				victim:SetAttribute("ManualRespawn", true)
			end
		end
	end
end)

-- Add RemoteEvent handler for respawn button click
RemoteEvent.OnServerEvent:Connect(function(player, functionName, ...)
	if functionName == "RequestPropToHunterTransition" then
		local args = ...

		-- Only process if player is marked as pending transition
		if player:GetAttribute("PendingHunterTransition") then
			debugLog("Received transition request from " .. player.Name)

			-- Only proceed if UI confirms it's closed
			if args and args.uiClosed then
				debugLog("⚡ Processing hunter transition for " .. player.Name .. " after UI closed")

				-- Remove pending flag
				player:SetAttribute("PendingHunterTransition", false)

				-- Set the transition flag - this will be used by CharacterAdded in VotingSystem
				player:SetAttribute("TransitionToHunter", true)

				-- Clear ManualRespawn to allow respawn
				player:SetAttribute("ManualRespawn", false)

				-- Now spawn the character
				debugLog("Spawning player as hunter")
				player:LoadCharacter()
			else
				debugLog("Waiting for UI confirmation from " .. player.Name)
			end
		else
			debugLog("⚠️ Received transition request from player not marked for transition: " .. player.Name)
		end
	end
end)

-- Add a function to clean up debounce data to prevent memory bloat
local function cleanupDebounceData()
	while true do
		task.wait(60) -- Run every minute
		local now = os.time()
		local count = 0

		for playerId, timestamp in pairs(recentDeaths) do
			if now - timestamp > DEATH_DEBOUNCE_TIME * 2 then
				recentDeaths[playerId] = nil
				count = count + 1
			end
		end

		if count > 0 then
			debugLog("Cleaned up " .. count .. " old death debounce entries")
		end
	end
end

-- Start cleanup task
task.spawn(cleanupDebounceData)

-- Export any functions needed by other modules
return {
	onPlayerDied = onPlayerDied,
	setupCharacter = setupCharacter
}