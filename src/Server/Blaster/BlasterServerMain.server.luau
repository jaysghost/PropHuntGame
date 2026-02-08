local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local BlasterValidation = require(script.Parent.BlasterValidation)
local BlasterUtilities = require(ReplicatedStorage.Blaster.BlasterUtilities)
local PropHealthSystem = require(script.Parent.Parent.PropHealthSystem)
local RagdollSystem = require(ReplicatedStorage.RagdollSystem)
local DamageTracker = require(script.Parent.Parent.DamageTracker)
local EnvironmentalPropHealthSystem = require(script.Parent.Parent.Misc.EnvironmentalPropHealth)
local getRayDirections = BlasterUtilities.getRayDirections
local castRays = BlasterUtilities.castRays

-- Single RemoteEvent for all game communication
local remoteEvent = ReplicatedStorage.RemoteEvent

-- Single BindableEvent for all server events
local serverEvent = ServerScriptService.Event
local activeDeathConnections = {}

local BlasterServer = {}

function BlasterServer.handleShoot(player, data)
	local timestamp = data.timestamp
	local blaster = data.blaster
	local origin = data.origin
	local tagged = data.tagged

	-- Track blaster by its key
	local blasterKey = tostring(blaster)

	-- Make sure ammoCache exists
	if not BlasterServer.ammoCache then
		BlasterServer.ammoCache = {}
	end

	-- Initialize ammo if not in cache
	if not BlasterServer.ammoCache[blasterKey] then
		local magazineSize = blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE) or 12
		BlasterServer.ammoCache[blasterKey] = magazineSize
	end

	-- Get current ammo from cache
	local currentAmmo = BlasterServer.ammoCache[blasterKey]

	-- Ensure ammo attribute is synced
	blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, currentAmmo)

	-- Validate the received arguments
	if not BlasterValidation.validateShootArguments(timestamp, blaster, origin, tagged) then
		return
	end

	-- Custom ammo check instead of using validateShot
	if currentAmmo <= 0 then
		print("SERVER: Player out of ammo")

		-- Get the single RemoteEvent
		local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

		-- Inform client of ammo state
		remoteEvent:FireClient(player, "AmmoUpdate", {
			ammo = 0, 
			blaster = blaster
		})
		return
	end

	-- Validate other aspects of the shot
	if not BlasterValidation.validateShot(player, timestamp, blaster, origin) then
		return
	end

	local spread = blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)
	local damage = blaster:GetAttribute(Constants.DAMAGE_ATTRIBUTE)

	-- Decrement ammo in our cache
	BlasterServer.ammoCache[blasterKey] = currentAmmo - 1
	local newAmmo = BlasterServer.ammoCache[blasterKey]

	-- Update attribute for compatibility
	blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, newAmmo)

	-- Send direct update to client
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	remoteEvent:FireClient(player, "AmmoUpdate", {
		ammo = newAmmo,
		blaster = blaster
	})

	-- Continue with ray casting
	local spreadAngle = math.rad(spread)
	local rayDirections = getRayDirections(origin, raysPerShot, spreadAngle, timestamp)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	-- Setup raycast parameters with CollectionService-based exclusion
	local CollectionService = game:GetService("CollectionService")
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Start with the player's character
	local exclusions = {player.Character}

	-- Add all disabled props to the exclude list
	local disabledProps = CollectionService:GetTagged("DisabledProp")
	for _, disabledProp in ipairs(disabledProps) do
		table.insert(exclusions, disabledProp)
	end

	raycastParams.FilterDescendantsInstances = exclusions

	-- Raycast against geometry with our updated parameters
	local rayResults = castRays(player, origin.Position, rayDirections, rayRadius, raycastParams)

	-- First, collect information about humanoid hits to track which rays hit players
	local rayHitPlayers = {}
	for indexString, taggedHumanoid in tagged do
		local index = tonumber(indexString)
		if index and rayResults[index] then
			rayHitPlayers[index] = true

			-- Get the victim player
			local victim = Players:GetPlayerFromCharacter(taggedHumanoid.Parent)

			-- Record damage before applying it, to ensure proper tracking
			if victim then
				DamageTracker:recordDamage(victim, player, blaster.Name, damage)
				DamageTracker:registerHit(victim, player, blaster.Name)
			end

			-- Process the humanoid hit as you normally would
			if taggedHumanoid.Health <= damage then
				taggedHumanoid.Health = 0
			else
				taggedHumanoid:TakeDamage(damage)
			end
		end
	end

	for i, rayResult in ipairs(rayResults) do
		-- Skip this ray entirely if it hit a player
		if rayHitPlayers[i] then
			continue
		end

		-- Process prop hit as normal
		if rayResult.instance then
			local hitPart = rayResult.instance

			-- Search for prop
			local prop = hitPart
			while prop and prop ~= workspace and prop.Name ~= "Prop" do
				prop = prop.Parent
			end

			if prop and prop.Name == "Prop" then
				local propId = prop:GetAttribute("PropId")
				if not propId then
					propId = game:GetService("HttpService"):GenerateGUID(false)
					prop:SetAttribute("PropId", propId)
				end

				BlasterServer.handlePropHit(player, prop, rayResult.position, propId)
			end
		end
	end

	-- Validate humanoid hits
	for indexString, taggedHumanoid in tagged do
		-- Convert index string to number
		local index = tonumber(indexString)
		if not index or not rayResults[index] or not rayDirections[index] then
			continue
		end

		local rayResult = rayResults[index]
		local rayDirection = rayDirections[index]

		-- Validate that the player is able to tag this humanoid based on the server raycast
		if not BlasterValidation.validateTag(player, taggedHumanoid, origin.Position, rayDirection, rayResult) then
			continue
		end

		rayResult.taggedHumanoid = taggedHumanoid

		-- Align the rayResult position to the tagged humanoid. This is necessary so that when we replicate
		-- this shot to the other clients they don't see lasers going through characters they should be hitting.
		local model = taggedHumanoid:FindFirstAncestorOfClass("Model")
		if model then
			local modelPosition = model:GetPivot().Position
			local distance = (modelPosition - origin.Position).Magnitude
			rayResult.position = origin.Position + rayDirection.Unit * distance
		end

		-- IMPORTANT: Skip already dead humanoids
		if taggedHumanoid.Health <= 0 then
			continue
		end
	end

	-- Apply physics impulse
	local force = blaster:GetAttribute(Constants.UNANCHORED_IMPULSE_FORCE_ATTRIBUTE)
	if force ~= 0 then
		for index, rayResult in rayResults do
			-- We don't want to apply impulses to characters, so we'll skip if we tagged a humanoid
			if rayResult.taggedHumanoid then
				continue
			end

			if rayResult.instance and rayResult.instance:IsA("BasePart") and not rayResult.instance.Anchored then
				local direction = rayDirections[index]
				local impulse = direction * force
				rayResult.instance:ApplyImpulseAtPosition(impulse, rayResult.position)
			end
		end
	end

	-- Replicate shot to other players using the SINGLE RemoteEvent
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end

		remoteEvent:FireClient(otherPlayer, "ReplicateShot", {
			blaster = blaster,
			position = origin.Position,
			rayResults = rayResults,
			playerName = player.Name  -- Add player name for debugging
		})
	end
end

function BlasterServer.handleReload(player, data)
	local blaster = data.blaster

	-- Validate the received argument
	if not BlasterValidation.validateInstance(blaster, "Tool") then
		return
	end

	-- Make sure the player is able to reload this blaster
	if not BlasterValidation.validateReload(player, blaster) then
		return
	end

	local reloadTime = blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)
	local magazineSize = blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	local blasterKey = tostring(blaster)

	-- Make sure ammoCache exists
	if not BlasterServer.ammoCache then
		BlasterServer.ammoCache = {}
	end

	-- Mark as reloading on the server
	blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, true)

	local character = player.Character

	local reloadTask
	local ancestryChangedConnection

	reloadTask = task.delay(reloadTime, function()
		-- Set ammo to full in both cache and attribute
		BlasterServer.ammoCache[blasterKey] = magazineSize
		blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, magazineSize)
		blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)

		-- Disconnect ancestry watcher
		if ancestryChangedConnection then
			ancestryChangedConnection:Disconnect()
		end

		-- Get the single RemoteEvent
		local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

		-- Send direct update to client
		remoteEvent:FireClient(player, "AmmoUpdate", {
			ammo = magazineSize,
			blaster = blaster
		})
	end)

	ancestryChangedConnection = blaster.AncestryChanged:Connect(function()
		if blaster.Parent ~= character then
			-- Cancel reload if blaster unequipped
			blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)

			if reloadTask then
				task.cancel(reloadTask)
				reloadTask = nil
			end

			if ancestryChangedConnection then
				ancestryChangedConnection:Disconnect()
				ancestryChangedConnection = nil
			end
		end
	end)
end

function BlasterServer.handlePropHit(player, prop, hitPosition, propId)
	-- Debug print to track execution
	print("BLASTER hit prop: " .. prop:GetFullName() .. " with ID: " .. (propId or "none"))

	-- Get CollectionService for tagging
	local CollectionService = game:GetService("CollectionService")

	-- Validate the prop
	if not prop or not prop:IsA("Model") or prop.Name ~= "Prop" then
		print("BLASTER: Invalid prop")
		return
	end

	-- Skip if the prop is already physically hit/destroyed
	if prop:GetAttribute("IsHit") or CollectionService:HasTag(prop, "DisabledProp") then
		print("BLASTER: Prop already destroyed, skipping: " .. prop:GetFullName())
		return
	end

	-- Get damage value from the weapon that hit the prop
	local blaster = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local damage = blaster and blaster:GetAttribute(Constants.DAMAGE_ATTRIBUTE) or 20

	print("BLASTER: Applying " .. damage .. " damage to prop")

	-- Apply damage and check if prop should be destroyed
	local shouldDestroy, previousHealth = EnvironmentalPropHealthSystem.applyDamage(prop, damage)

	print("BLASTER: shouldDestroy=" .. tostring(shouldDestroy) .. ", previousHealth=" .. tostring(previousHealth))

	-- If prop shouldn't be destroyed yet, send partial damage event and RETURN
	if not shouldDestroy then
		-- Send partial damage event to clients
		remoteEvent:FireAllClients("PropDamage", {
			propId = propId,
			propPath = prop:GetFullName(),
			position = hitPosition,
			currentHealth = prop:GetAttribute("CurrentHealth"),
			maxHealth = prop:GetAttribute("MaxHealth") or EnvironmentalPropHealthSystem.DEFAULT_PROP_HEALTH,
			previousHealth = previousHealth,
			damageAmount = damage
		})
		print("BLASTER: Prop damaged but not destroyed")
		return
	end

	-- IMPORTANT: Only continue if shouldDestroy is true
	print("BLASTER: Prop should be destroyed now")

	-- Mark prop as hit
	prop:SetAttribute("IsHit", true)

	-- Add to CollectionService for raycast exclusion
	CollectionService:AddTag(prop, "DisabledProp")

	-- Find trigger and proximity prompt
	local trigger = prop:FindFirstChild("Trigger")
	local proximityPrompt = trigger and trigger:FindFirstChildOfClass("ProximityPrompt")

	-- Disable proximity prompt on server
	if proximityPrompt then
		proximityPrompt.Enabled = false
	end

	-- Handle collision on server directly
	for i, part in ipairs(prop:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end

	-- Send event to all clients with BOTH prop ID and path
	remoteEvent:FireAllClients("PropHit", {
		propId = propId,
		propPath = prop:GetFullName(),
		position = hitPosition
	})

	-- Restore after 5 seconds - BUT keep protection until clients finish tweens
	task.delay(5, function()
		-- Re-enable collision
		for _, part in ipairs(prop:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end

		-- Re-enable ProximityPrompt
		if proximityPrompt then
			proximityPrompt.Enabled = true
		end

		-- Reset health when prop is restored
		EnvironmentalPropHealthSystem.resetHealth(prop)

		-- Tell clients to restore using the same ID, but DON'T reset hit state yet
		remoteEvent:FireAllClients("PropRestore", {
			propId = propId,
			propPath = prop:GetFullName()
		})

		-- CRITICAL: Wait for client-side restoration tween to complete before removing protection
		task.delay(0.7, function() -- 0.5s tween + 0.2s buffer
			-- Reset hit state
			prop:SetAttribute("IsHit", false)

			-- Remove from disabled collection
			CollectionService:RemoveTag(prop, "DisabledProp")

			print("SERVER: Prop fully restored and protection removed: " .. prop:GetFullName())
		end)
	end)
end

function BlasterServer.handlePlayerDeath(humanoid)
	local character = humanoid.Parent
	if not character then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Mark this as a blaster death
	player:SetAttribute("BlasterDeath", true)

	-- Apply ragdoll to create the visual effect
	RagdollSystem.applyRagdoll(character)
	PropHealthSystem.transferToCorporse(player.UserId, character)
	-- The respawn is handled by RespawnHandler via the died event
	-- No manual LoadCharacter call needed here
end


function BlasterServer.initializeTagging()
	local CollectionService = game:GetService("CollectionService")

	local function tagPart(part)
		-- Tag all character parts as NON_STATIC, so they can be ignored when casting against static geometry
		part:AddTag(Constants.NON_STATIC_TAG)
		-- Tag parts in accessories and tools with RAY_EXCLUDE_TAG so they can be ignored by raycasts
		local accessory = part:FindFirstAncestorWhichIsA("Accessory")
		local tool = part:FindFirstAncestorWhichIsA("Tool")
		if accessory or tool then
			part:AddTag(Constants.RAY_EXCLUDE_TAG)
		end
	end

	local function onCharacterAdded(character)
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		character.DescendantAdded:Connect(function(instance)
			if instance:IsA("BasePart") then
				tagPart(instance)
			end
		end)

		for _, instance in character:GetDescendants() do
			if instance:IsA("BasePart") then
				tagPart(instance)
			end
		end
	end

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end

	-- Initialize existing players
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Connect to new players
	Players.PlayerAdded:Connect(onPlayerAdded)
end

function BlasterServer.initialize()
	-- Initialize ammo cache
	BlasterServer.ammoCache = {}

	-- Reset state of all blasters in the game
	for _, player in ipairs(Players:GetPlayers()) do
		for _, item in ipairs(player:GetDescendants()) do
			if item:IsA("Tool") and item:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE) then
				-- Reset ammo to full magazine
				local magazineSize = item:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
				local blasterKey = tostring(item)

				-- Update both cache and attribute
				BlasterServer.ammoCache[blasterKey] = magazineSize
				item:SetAttribute(Constants.AMMO_ATTRIBUTE, magazineSize)
				item:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)

				print("RESET TOOL:", item:GetFullName(), "SET AMMO TO", magazineSize)
			end
		end
	end

	-- Connect to player added for new players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Wait a bit for tools to be added
			task.wait(1)

			-- Reset any tools the character has
			for _, item in ipairs(character:GetDescendants()) do
				if item:IsA("Tool") and item:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE) then
					local magazineSize = item:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
					local blasterKey = tostring(item)

					BlasterServer.ammoCache[blasterKey] = magazineSize
					item:SetAttribute(Constants.AMMO_ATTRIBUTE, magazineSize)
					item:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)

					print("NEW PLAYER TOOL RESET:", item:GetFullName(), "SET AMMO TO", magazineSize)
				end
			end
		end)
	end)

	-- Get the single RemoteEvent
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

	-- Connect to the ONE RemoteEvent and route based on event name
	remoteEvent.OnServerEvent:Connect(function(player, eventName, data)
		if eventName == "Shoot" then
			BlasterServer.handleShoot(player, data)
		elseif eventName == "Reload" then
			BlasterServer.handleReload(player, data)
		elseif eventName == "RequestRespawn" then
			-- Handle manual respawn request
			if player:GetAttribute("ManualRespawn") then
				print("Processing manual respawn for", player.Name)
				player:SetAttribute("ManualRespawn", false)
				player:LoadCharacter()
			end
		end
	end)

	-- Initialize other server systems
	BlasterServer.initializeTagging()

	-- Connect to the server's bindable event for player elimination
	serverEvent.Event:Connect(function(eventName, data)
		if eventName == "Player_Eliminated" then
			-- Only handle deaths from blaster weapons
			if data.weaponName and (data.weaponName == "Blaster" or string.find(data.weaponName, "Blaster")) then
				BlasterServer.handlePlayerDeath(data.humanoid)
			end
		end
	end)
end

BlasterServer.initialize()

return BlasterServer