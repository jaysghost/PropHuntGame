-- PlayerDataServer.lua (ServerScript in ServerScriptService)
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get PlayerManager module
local PlayerManager = require(ServerScriptService.Player.PlayerManager)

-- Get RemoteEvent
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Handle RemoteEvent messages
RemoteEvent.OnServerEvent:Connect(function(player, eventName, ...)
	local playerData = PlayerManager.ActivePlayers[player]
	if not playerData then return end

	if eventName == "GetCurrency" then
		-- Client requesting currency
		RemoteEvent:FireClient(player, "CurrencyResponse", playerData:GetCurrency())

	elseif eventName == "AddCurrency" then
		-- For testing: Add currency
		local amount = ...
		playerData:AddCurrency(amount)
		print(player.Name .. " added " .. amount .. " currency. New total: " .. playerData:GetCurrency())

		-- === WEAPON HANDLERS ===
	elseif eventName == "PurchaseWeapon" then
		-- Extract parameters
		local weaponId, price = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then 
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Player data not found", weaponId)
			return 
		end

		-- Validate weapon data on server-side (security measure)
		local weaponData = require(ReplicatedStorage.Data.WeaponData)[weaponId]
		if not weaponData then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Invalid weapon", weaponId)
			return
		end

		-- Check if already owned
		if playerData.Profile.Data.OwnedWeapons and playerData.Profile.Data.OwnedWeapons[weaponId] then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Already owned", weaponId)
			return
		end

		-- Verify price (server authority)
		local serverPrice = weaponData.price

		-- Check if player has enough currency
		if playerData.Profile.Data.Currency < serverPrice then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Insufficient funds", weaponId)
			return
		end

		-- Process purchase
		playerData.Profile.Data.Currency = playerData.Profile.Data.Currency - serverPrice

		-- Initialize OwnedWeapons if it doesn't exist
		if not playerData.Profile.Data.OwnedWeapons then
			playerData.Profile.Data.OwnedWeapons = {}
		end

		-- Add weapon to owned weapons
		playerData.Profile.Data.OwnedWeapons[weaponId] = true

		-- Notify client of success and update currency display
		RemoteEvent:FireClient(player, "UpdateCurrency", playerData.Profile.Data.Currency)
		RemoteEvent:FireClient(player, "PurchaseResponse", true, "Purchase successful", weaponId)

		-- Log purchase for debugging
		print(player.Name .. " purchased " .. weaponId .. " for " .. serverPrice)

	elseif eventName == "CheckWeaponOwnership" then
		local weaponId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if player owns the weapon
		local isOwned = false
		if playerData.Profile.Data.OwnedWeapons and 
			playerData.Profile.Data.OwnedWeapons[weaponId] then
			isOwned = true
		end

		-- Check if this is the active weapon
		local isActive = playerData.Profile.Data.ActiveWeapon == weaponId

		-- Respond to client with ownership status
		RemoteEvent:FireClient(player, "WeaponOwnershipResponse", weaponId, isOwned, isActive)

	elseif eventName == "GetOwnedWeapons" then
		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Send the owned weapons to client
		RemoteEvent:FireClient(player, "OwnedWeaponsResponse", playerData.Profile.Data.OwnedWeapons)

	elseif eventName == "CheckActiveWeapon" then
		local weaponId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if this is the active weapon
		local isActive = playerData.Profile.Data.ActiveWeapon == weaponId

		-- Respond to client with active status
		RemoteEvent:FireClient(player, "ActiveWeaponResponse", weaponId, isActive)

	elseif eventName == "SetActiveWeapon" then
		local weaponId = ...

		print("DEBUG - SetActiveWeapon request received for: " .. tostring(weaponId))

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then 
			print("DEBUG - Player data not found")
			return 
		end

		-- Check current active weapon
		print("DEBUG - Current active weapon: " .. tostring(playerData.Profile.Data.ActiveWeapon))

		-- Verify player owns this weapon
		if not playerData.Profile.Data.OwnedWeapons then
			print("DEBUG - OwnedWeapons is nil")
			return
		end

		print("DEBUG - Owned weapons:")
		for id, _ in pairs(playerData.Profile.Data.OwnedWeapons) do
			print("  " .. id)
		end

		if not playerData.Profile.Data.OwnedWeapons[weaponId] then
			print("DEBUG - Player doesn't own weapon: " .. tostring(weaponId))
			return -- Player doesn't own this weapon
		end

		-- Set as active weapon
		print("DEBUG - Setting active weapon to: " .. weaponId)
		playerData.Profile.Data.ActiveWeapon = weaponId

		-- Notify client
		RemoteEvent:FireClient(player, "WeaponEquipped", weaponId)
		print("DEBUG - Sent WeaponEquipped event with ID: " .. weaponId)

		-- === MELEE WEAPON HANDLERS ===
	elseif eventName == "PurchaseMeleeWeapon" then
		-- Extract parameters
		local weaponId, price = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then 
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Player data not found", weaponId)
			return 
		end

		-- Validate melee weapon data on server-side (security measure)
		local weaponData = require(ReplicatedStorage.Data.MeleeWeaponData)[weaponId]
		if not weaponData then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Invalid melee weapon", weaponId)
			return
		end

		-- Check if already owned
		if playerData.Profile.Data.OwnedMeleeWeapons and playerData.Profile.Data.OwnedMeleeWeapons[weaponId] then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Already owned", weaponId)
			return
		end

		-- Verify price (server authority)
		local serverPrice = weaponData.price

		-- Check if player has enough currency
		if playerData.Profile.Data.Currency < serverPrice then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Insufficient funds", weaponId)
			return
		end

		-- Process purchase
		playerData.Profile.Data.Currency = playerData.Profile.Data.Currency - serverPrice

		-- Initialize OwnedMeleeWeapons if it doesn't exist
		if not playerData.Profile.Data.OwnedMeleeWeapons then
			playerData.Profile.Data.OwnedMeleeWeapons = {}
		end

		-- Add melee weapon to owned melee weapons
		playerData.Profile.Data.OwnedMeleeWeapons[weaponId] = true

		-- Notify client of success and update currency display
		RemoteEvent:FireClient(player, "UpdateCurrency", playerData.Profile.Data.Currency)
		RemoteEvent:FireClient(player, "PurchaseResponse", true, "Purchase successful", weaponId)

		-- Log purchase for debugging
		print(player.Name .. " purchased melee weapon " .. weaponId .. " for " .. serverPrice)

	elseif eventName == "CheckMeleeWeaponOwnership" then
		local weaponId = ...

		if not weaponId then
			warn('received checkmeleeweaponownership request with nil weaponId from '.. player.Name)
			return
		end

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if player owns the melee weapon
		local isOwned = false
		if playerData.Profile.Data.OwnedMeleeWeapons and 
			playerData.Profile.Data.OwnedMeleeWeapons[weaponId] then
			isOwned = true
		end

		-- Check if this is the active melee weapon
		local isActive = playerData.Profile.Data.ActiveMeleeWeapon == weaponId

		-- Respond to client with ownership status
		RemoteEvent:FireClient(player, "MeleeWeaponOwnershipResponse", weaponId, isOwned, isActive)

	elseif eventName == "GetOwnedMeleeWeapons" then
		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Send the owned melee weapons to client
		RemoteEvent:FireClient(player, "OwnedMeleeWeaponsResponse", playerData.Profile.Data.OwnedMeleeWeapons)

	elseif eventName == "CheckActiveMeleeWeapon" then
		local weaponId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if this is the active melee weapon
		local isActive = playerData.Profile.Data.ActiveMeleeWeapon == weaponId

		-- Respond to client with active status
		RemoteEvent:FireClient(player, "ActiveMeleeWeaponResponse", weaponId, isActive)

	elseif eventName == "SetActiveMeleeWeapon" then
		local weaponId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Verify player owns this melee weapon
		if not playerData.Profile.Data.OwnedMeleeWeapons or 
			not playerData.Profile.Data.OwnedMeleeWeapons[weaponId] then
			return -- Player doesn't own this melee weapon
		end

		-- Set as active melee weapon
		playerData.Profile.Data.ActiveMeleeWeapon = weaponId

		-- Notify client
		RemoteEvent:FireClient(player, "MeleeWeaponEquipped", weaponId)

		-- === DEATH SOUND HANDLERS ===
	elseif eventName == "PurchaseDeathSound" then
		-- Extract parameters
		local soundId, price = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then 
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Player data not found", soundId)
			return 
		end

		-- Validate sound data on server-side (security measure)
		local soundData = require(ReplicatedStorage.Data.DeathSoundData)[soundId]
		if not soundData then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Invalid death sound", soundId)
			return
		end

		-- Check if already owned
		if playerData.Profile.Data.OwnedDeathSounds and playerData.Profile.Data.OwnedDeathSounds[soundId] then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Already owned", soundId)
			return
		end

		-- Verify price (server authority)
		local serverPrice = soundData.price

		-- Check if player has enough currency
		if playerData.Profile.Data.Currency < serverPrice then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Insufficient funds", soundId)
			return
		end

		-- Process purchase
		playerData.Profile.Data.Currency = playerData.Profile.Data.Currency - serverPrice

		-- Initialize OwnedDeathSounds if it doesn't exist
		if not playerData.Profile.Data.OwnedDeathSounds then
			playerData.Profile.Data.OwnedDeathSounds = {}
		end

		-- Add death sound to owned sounds
		playerData.Profile.Data.OwnedDeathSounds[soundId] = true

		-- Set as active death sound if this is their first one
		if not playerData.Profile.Data.ActiveDeathSound then
			playerData.Profile.Data.ActiveDeathSound = soundId
		end

		-- Notify client of success and update currency display
		RemoteEvent:FireClient(player, "UpdateCurrency", playerData.Profile.Data.Currency)
		RemoteEvent:FireClient(player, "PurchaseResponse", true, "Purchase successful", soundId)

		-- Log purchase for debugging
		print(player.Name .. " purchased death sound " .. soundId .. " for " .. serverPrice)

	elseif eventName == "CheckDeathSoundOwnership" then
		local soundId = ...

		if not soundId then
			warn('received checkdeathsoundownership request with nil soundid from '.. player.Name)
			return
		end

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if player owns the death sound
		local isOwned = false
		if playerData.Profile.Data.OwnedDeathSounds and 
			playerData.Profile.Data.OwnedDeathSounds[soundId] then
			isOwned = true
		end

		-- Check if this is the active death sound
		local isActive = playerData.Profile.Data.ActiveDeathSound == soundId

		-- Respond to client with ownership status
		RemoteEvent:FireClient(player, "DeathSoundOwnershipResponse", soundId, isOwned, isActive)

	elseif eventName == "GetOwnedDeathSounds" then
		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Send the owned death sounds to client
		RemoteEvent:FireClient(player, "OwnedDeathSoundsResponse", playerData.Profile.Data.OwnedDeathSounds)

	elseif eventName == "SetActiveDeathSound" then
		local soundId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Verify player owns this sound
		if not playerData.Profile.Data.OwnedDeathSounds or 
			not playerData.Profile.Data.OwnedDeathSounds[soundId] then
			return -- Player doesn't own this sound
		end

		-- Set as active death sound
		playerData.Profile.Data.ActiveDeathSound = soundId

		-- Notify client
		RemoteEvent:FireClient(player, "DeathSoundActivated", soundId)

		-- Log for debugging
		print(player.Name .. " set active death sound to " .. soundId)

		-- === TAUNT HANDLERS ===
	elseif eventName == "PurchaseTaunt" then
		-- Extract parameters
		local tauntId, price = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then 
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Player data not found", tauntId)
			return 
		end

		-- Validate taunt data on server-side (security measure)
		local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
		if not tauntData then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Invalid taunt", tauntId)
			return
		end

		-- Check if already owned
		if playerData.Profile.Data.OwnedTaunts and playerData.Profile.Data.OwnedTaunts[tauntId] then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Already owned", tauntId)
			return
		end

		-- Verify price (server authority)
		local serverPrice = tauntData.price

		-- Check if player has enough currency
		if playerData.Profile.Data.Currency < serverPrice then
			RemoteEvent:FireClient(player, "PurchaseResponse", false, "Insufficient funds", tauntId)
			return
		end

		-- Process purchase
		playerData.Profile.Data.Currency = playerData.Profile.Data.Currency - serverPrice

		-- Initialize OwnedTaunts if it doesn't exist
		if not playerData.Profile.Data.OwnedTaunts then
			playerData.Profile.Data.OwnedTaunts = {}
		end

		-- Add taunt to owned taunts
		playerData.Profile.Data.OwnedTaunts[tauntId] = true

		-- Set as active taunt if this is their first one
		if not playerData.Profile.Data.ActiveTaunt then
			playerData.Profile.Data.ActiveTaunt = tauntId
		end

		-- Notify client of success and update currency display
		RemoteEvent:FireClient(player, "UpdateCurrency", playerData.Profile.Data.Currency)
		RemoteEvent:FireClient(player, "PurchaseResponse", true, "Purchase successful", tauntId)

		-- Log purchase for debugging
		print(player.Name .. " purchased taunt " .. tauntId .. " for " .. serverPrice)

	elseif eventName == "CheckTauntOwnership" then
		local tauntId = ...

		if not tauntId then
			warn('received checktauntownership request with nil tauntId from '.. player.Name)
			return
		end

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Check if player owns the taunt
		local isOwned = false
		if playerData.Profile.Data.OwnedTaunts and 
			playerData.Profile.Data.OwnedTaunts[tauntId] then
			isOwned = true
		end

		-- Check if this is the active taunt
		local isActive = playerData.Profile.Data.ActiveTaunt == tauntId

		-- Respond to client with ownership status
		RemoteEvent:FireClient(player, "TauntOwnershipResponse", tauntId, isOwned, isActive)

	elseif eventName == "GetOwnedTaunts" then
		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Send the owned taunts to client
		RemoteEvent:FireClient(player, "OwnedTauntsResponse", playerData.Profile.Data.OwnedTaunts)

	elseif eventName == "SetActiveTaunt" then
		local tauntId = ...

		-- Get player data
		local playerData = PlayerManager.ActivePlayers[player]
		if not playerData then return end

		-- Verify player owns this taunt
		if not playerData.Profile.Data.OwnedTaunts or 
			not playerData.Profile.Data.OwnedTaunts[tauntId] then
			return -- Player doesn't own this taunt
		end

		-- Set as active taunt
		playerData.Profile.Data.ActiveTaunt = tauntId

		-- Notify client
		RemoteEvent:FireClient(player, "TauntActivated", tauntId)

		-- Log for debugging
		print(player.Name .. " set active taunt to " .. tauntId)
	end
end)

-- Player joining
Players.PlayerAdded:Connect(function(player)
	PlayerManager.new(player)
end)

-- Player leaving
Players.PlayerRemoving:Connect(function(player)
	local playerData = PlayerManager.ActivePlayers[player]
	if playerData then
		playerData:ReleaseProfile()
	end
end)