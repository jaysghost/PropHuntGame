-- DamageTracker.lua - Place in ServerScriptService
local DamageTracker = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverEvent = ServerScriptService.Event
local DAMAGE_RECORD_EXPIRY = 10 -- Seconds to keep damage records

-- Module state
DamageTracker.playerDamageLog = {} -- Format: [victimUserId] = { {player=Player, weapon=name, damage=amount, timestamp=time}, ... }
DamageTracker.activeConnections = {} -- Format: [humanoidKey] = connection
DamageTracker.initialized = false
DamageTracker.DEBUG = false

-- Create a unique key for humanoid tracking
local function createHumanoidKey(humanoid)
	return tostring(humanoid) .. "_" .. tostring(humanoid:GetFullName())
end

-- Record damage dealt to a player
function DamageTracker:recordDamage(victim, attacker, weaponName, damage)
	-- Safety checks
	if not victim or not victim:IsA("Player") or not attacker or not attacker:IsA("Player") then
		if self.DEBUG then print("⚠️ Invalid victim or attacker in recordDamage") end
		return
	end

	local victimId = victim.UserId
	local humanoid = victim.Character and victim.Character:FindFirstChild("Humanoid")
	if not humanoid then
		if self.DEBUG then print("⚠️ No humanoid found for victim:", victim.Name) end
		return
	end

	-- Initialize damage log for this victim if needed
	if not self.playerDamageLog[victimId] then
		self.playerDamageLog[victimId] = {}
	end

	-- Record this damage instance
	table.insert(self.playerDamageLog[victimId], {
		player = attacker,
		weapon = weaponName,
		damage = damage,
		timestamp = os.time()
	})

	-- Monitor victim for death if not already monitoring
	local humanoidKey = createHumanoidKey(humanoid)
	if not self.activeConnections[humanoidKey] then
		if self.DEBUG then print("📡 Setting up death monitor for:", victim.Name) end

		local connection = humanoid.Died:Connect(function()
			self:handlePlayerDeath(victim, humanoid)
		end)

		self.activeConnections[humanoidKey] = connection
	end
end

-- Handle player death and attribute kill
function DamageTracker:handlePlayerDeath(victim, humanoid)
	if self.DEBUG then print("💀 Processing death for:", victim.Name) end

	local victimId = victim.UserId
	local damageLog = self.playerDamageLog[victimId]
	local humanoidKey = createHumanoidKey(humanoid)

	-- Clean up connection
	if self.activeConnections[humanoidKey] then
		self.activeConnections[humanoidKey]:Disconnect()
		self.activeConnections[humanoidKey] = nil
	end

	-- If no damage was recorded, we can't attribute the kill
	if not damageLog or #damageLog == 0 then
		if self.DEBUG then print("⚠️ No damage record for:", victim.Name, "- Cannot attribute kill") end
		return
	end

	-- Determine killing blow (most recent damage)
	table.sort(damageLog, function(a, b) return a.timestamp > b.timestamp end)
	local killingBlow = damageLog[1]

	-- Get killer information
	local killer = killingBlow.player
	local weaponName = killingBlow.weapon

	if self.DEBUG then
		print("🔫 Kill attributed to:", killer.Name)
		print("🔪 Weapon:", weaponName)
	end

	-- Fire unified elimination event
	serverEvent:Fire("Player_Eliminated", {
		victim = victim,
		killer = killer,
		weaponName = weaponName,
		humanoid = humanoid,
		damageLog = damageLog -- For possible kill assists
	})

	-- Clear damage log for this victim
	self.playerDamageLog[victimId] = nil
end

-- Register hit (without necessarily dealing damage)
function DamageTracker:registerHit(victim, attacker, weaponName)
	-- Find the player from character if needed
	if not victim:IsA("Player") then
		local character = victim
		if victim:IsA("Humanoid") then
			character = victim.Parent
		end

		if character then
			victim = Players:GetPlayerFromCharacter(character)
		end
	end

	if not victim then return end

	-- Fire hit event (for visual effects, sounds, etc.)
	serverEvent:Fire("Player_Hit", {
		victim = victim,
		attacker = attacker,
		weaponName = weaponName
	})

	-- Make health highlight flash or other hit effects
	local PropHealthSystem = require(script.Parent.PropHealthSystem)
	PropHealthSystem.onPlayerHit(victim.UserId)
end

-- Clean up expired damage records periodically
function DamageTracker:startCleanupTask()
	task.spawn(function()
		while true do
			wait(30) -- Run every 30 seconds
			local now = os.time()
			local count = 0

			for victimId, damageLog in pairs(self.playerDamageLog) do
				-- Filter out expired damage records
				local newLog = {}
				for _, record in ipairs(damageLog) do
					if now - record.timestamp < DAMAGE_RECORD_EXPIRY then
						table.insert(newLog, record)
					else
						count = count + 1
					end
				end

				-- Update or remove the log
				if #newLog > 0 then
					self.playerDamageLog[victimId] = newLog
				else
					self.playerDamageLog[victimId] = nil
				end
			end

			if self.DEBUG and count > 0 then
				print("🧹 Cleaned up", count, "expired damage records")
			end
		end
	end)
end

-- Clean up player when they leave
function DamageTracker:onPlayerLeaving(player)
	if not player then return end

	local playerId = player.UserId

	-- Clear damage log
	if self.playerDamageLog[playerId] then
		self.playerDamageLog[playerId] = nil
	end

	-- Clean up any connections related to this player
	for humanoidKey, connection in pairs(self.activeConnections) do
		if string.find(humanoidKey, player.Name) then
			connection:Disconnect()
			self.activeConnections[humanoidKey] = nil
		end
	end
end

-- Initialize the system
function DamageTracker:initialize()
	if self.initialized then return end

	-- Set up player leaving handler
	Players.PlayerRemoving:Connect(function(player)
		self:onPlayerLeaving(player)
	end)

	-- Start cleanup task
	self:startCleanupTask()

	self.initialized = true
	if self.DEBUG then print("🚀 DamageTracker system initialized") end
end

-- Initialize automatically
DamageTracker:initialize()

return DamageTracker