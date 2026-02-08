-- PlayerManager.lua (ModuleScript in ServerScriptService)
local PlayerManager = {}
PlayerManager.__index = PlayerManager
PlayerManager.ActivePlayers = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Load ProfileService
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))

-- Get RemoteEvent
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Profile Store setup
local ProfileStore = ProfileService.GetProfileStore(
	"PlayerData_v1",
	{
		Currency = 0,  -- Starting currency
		OwnedWeapons = {},  -- Weapons owned by player
		OwnedMeleeWeapons = {},  -- Melee weapons owned by player
		OwnedDeathSounds = {},  -- Death sounds owned by player
		OwnedTaunts = {},  -- Taunts owned by player
		ActiveWeapon = nil,  -- Currently equipped weapon
		ActiveMeleeWeapon = nil,  -- Currently equipped melee weapon
		ActiveDeathSound = nil,  -- Currently equipped death sound
		ActiveTaunt = nil,  -- Currently equipped taunt
		Stats = {
			PlayTime = 0,
			LastLogin = 0
		}
	}
)

function PlayerManager.new(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- Fill in missing data

		local self = setmetatable({
			Player = player,
			Profile = profile
		}, PlayerManager)

		-- Handle profile release
		profile:ListenToRelease(function()
			self:Cleanup()
			player:Kick("Your data is being accessed elsewhere. Please rejoin.")
		end)

		if player:IsDescendantOf(Players) then
			-- Player still in game, set up
			PlayerManager.ActivePlayers[player] = self
			self:Initialize()
			return self
		else
			-- Player left, release profile
			profile:Release()
		end
	else
		-- Failed to load profile
		player:Kick("Unable to load your data. Please try again later.")
	end

	return nil
end

function PlayerManager:Initialize()
	-- Set last login time
	self.Profile.Data.Stats.LastLogin = os.time()

	-- Initialize OwnedWeapons if it doesn't exist
	if not self.Profile.Data.OwnedWeapons then
		self.Profile.Data.OwnedWeapons = {}
		-- Give them a default weapon if desired
		self.Profile.Data.OwnedWeapons["Blaster_Default"] = true
	end

	-- Set default active weapon if none is set
	if not self.Profile.Data.ActiveWeapon and 
		self.Profile.Data.OwnedWeapons["Blaster_Default"] then
		self.Profile.Data.ActiveWeapon = "Blaster_Default"
	end

	-- Initialize OwnedDeathSounds if it doesn't exist
	if not self.Profile.Data.OwnedDeathSounds then
		self.Profile.Data.OwnedDeathSounds = {}
		-- Give them the default death sound for free
		self.Profile.Data.OwnedDeathSounds["DeathSound_wilhelm"] = true
	end

	-- Set default active death sound if none is set
	if not self.Profile.Data.ActiveDeathSound and 
		self.Profile.Data.OwnedDeathSounds["DeathSound_wilhelm"] then
		self.Profile.Data.ActiveDeathSound = "DeathSound_wilhelm"
	end

	-- Initialize OwnedTaunts if it doesn't exist
	if not self.Profile.Data.OwnedTaunts then
		self.Profile.Data.OwnedTaunts = {}
		-- Give them the basic fart taunt for free
		self.Profile.Data.OwnedTaunts["TauntSound_fart"] = true
	end

	-- Set default active taunt if none is set
	if not self.Profile.Data.ActiveTaunt and 
		self.Profile.Data.OwnedTaunts["TauntSound_fart"] then
		self.Profile.Data.ActiveTaunt = "TauntSound_fart"
	end

	-- Initialize OwnedMeleeWeapons if it doesn't exist
	if not self.Profile.Data.OwnedMeleeWeapons then
		self.Profile.Data.OwnedMeleeWeapons = {}
		self.Profile.Data.OwnedMeleeWeapons["Knife_Default"] = true
	end

	-- Set default active melee weapon if none is set
	if not self.Profile.Data.ActiveMeleeWeapon and 
		self.Profile.Data.OwnedMeleeWeapons["Knife_Default"] then
		self.Profile.Data.ActiveMeleeWeapon = "Knife_Default"
	end

	-- Make sure default knife is always owned (as a fallback)
	self.Profile.Data.OwnedMeleeWeapons["Knife_Default"] = true
	self.Profile.Data.OwnedWeapons["Blaster_Default"] = true
	self.Profile.Data.OwnedDeathSounds["DeathSound_wilhelm"] = true


	-- Notify client that data is ready
	RemoteEvent:FireClient(self.Player, "PlayerDataReady", self.Profile.Data.Currency)

	-- Log initialization
	print("Player data initialized for " .. self.Player.Name .. " (UserID: " .. self.Player.UserId .. ")")
end

function PlayerManager:GetCurrency()
	return self.Profile.Data.Currency
end

function PlayerManager:SetCurrency(amount)
	self.Profile.Data.Currency = amount
	self:UpdateCurrencyUI()
end

function PlayerManager:AddCurrency(amount)
	self.Profile.Data.Currency = self.Profile.Data.Currency + amount
	self:UpdateCurrencyUI()
end

function PlayerManager:UpdateCurrencyUI()
	-- Notify client about currency update
	RemoteEvent:FireClient(self.Player, "UpdateCurrency", self.Profile.Data.Currency)
end

function PlayerManager:GetOwnedWeapons()
	return self.Profile.Data.OwnedWeapons
end

function PlayerManager:GetOwnedMeleeWeapons()
	return self.Profile.Data.OwnedMeleeWeapons
end

function PlayerManager:GetOwnedDeathSounds()
	return self.Profile.Data.OwnedDeathSounds
end

function PlayerManager:GetOwnedTaunts()
	return self.Profile.Data.OwnedTaunts
end

function PlayerManager:GetActiveWeapon()
	return self.Profile.Data.ActiveWeapon
end

function PlayerManager:GetActiveMeleeWeapon()
	return self.Profile.Data.ActiveMeleeWeapon
end

function PlayerManager:GetActiveDeathSound()
	return self.Profile.Data.ActiveDeathSound
end

function PlayerManager:GetActiveTaunt()
	return self.Profile.Data.ActiveTaunt
end

function PlayerManager:SetActiveWeapon(weaponId)
	if self.Profile.Data.OwnedWeapons and self.Profile.Data.OwnedWeapons[weaponId] then
		self.Profile.Data.ActiveWeapon = weaponId
		return true
	end
	return false
end

function PlayerManager:SetActiveMeleeWeapon(weaponId)
	if self.Profile.Data.OwnedMeleeWeapons and self.Profile.Data.OwnedMeleeWeapons[weaponId] then
		self.Profile.Data.ActiveMeleeWeapon = weaponId
		return true
	end
	return false
end

function PlayerManager:SetActiveDeathSound(soundId)
	if self.Profile.Data.OwnedDeathSounds and self.Profile.Data.OwnedDeathSounds[soundId] then
		self.Profile.Data.ActiveDeathSound = soundId
		return true
	end
	return false
end

function PlayerManager:SetActiveTaunt(tauntId)
	if self.Profile.Data.OwnedTaunts and self.Profile.Data.OwnedTaunts[tauntId] then
		self.Profile.Data.ActiveTaunt = tauntId
		return true
	end
	return false
end

function PlayerManager:Cleanup()
	PlayerManager.ActivePlayers[self.Player] = nil
	-- Additional cleanup if needed
end

function PlayerManager:ReleaseProfile()
	if self.Profile ~= nil then
		self.Profile:Release()
	end
end

return PlayerManager