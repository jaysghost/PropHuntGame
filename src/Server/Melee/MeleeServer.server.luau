local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Melee.Constants)
local MeleeValidation = require(script.Parent.MeleeValidation)
local MeleeUtilities = require(ReplicatedStorage.Melee.MeleeUtilities)
local RagdollSystem = require(ReplicatedStorage.RagdollSystem)
local DamageTracker = require(script.Parent.Parent.DamageTracker)
local EnvironmentalPropHealthSystem = require(script.Parent.Parent.Misc.EnvironmentalPropHealth)

-- Single RemoteEvent for all game communication
local remoteEvent = ReplicatedStorage.RemoteEvent

-- Single BindableEvent for all server events
local serverEvent = ServerScriptService.Event

-- Hit debounce tracking
local hitDebounce = {}
local activeDeathConnections = {}

local MeleeServer = {}

function MeleeServer.checkPropHit(player, hitboxCFrame, hitboxSize)
	-- Debug print to track execution
	print("MELEE checkPropHit called")

	-- Get CollectionService for tagging
	local CollectionService = game:GetService("CollectionService")

	-- Cast a region to find props
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Create exclusion list with player and disabled props
	local exclusions = {player.Character}

	-- Add all disabled props to exclude list
	local disabledProps = CollectionService:GetTagged("DisabledProp")
	for _, disabledProp in ipairs(disabledProps) do
		table.insert(exclusions, disabledProp)
	end

	params.FilterDescendantsInstances = exclusions

	local parts = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)
	local propHit = false

	for _, part in ipairs(parts) do
		-- Look for props
		local prop = part
		while prop and prop ~= workspace and prop.Name ~= "Prop" do
			prop = prop.Parent
		end

		if prop and prop.Name == "Prop" then
			print("MELEE found prop: " .. prop:GetFullName())

			local propId = prop:GetAttribute("PropId")
			if not propId then
				propId = game:GetService("HttpService"):GenerateGUID(false)
				prop:SetAttribute("PropId", propId)
			end

			-- Skip if prop is already physically hit/destroyed
			if prop:GetAttribute("IsHit") or CollectionService:HasTag(prop, "DisabledProp") then
				print("MELEE: Prop already destroyed, skipping: " .. prop:GetFullName())
				continue
			end

			-- Get damage value from melee weapon
			local melee = player.Character and player.Character:FindFirstChildOfClass("Tool")
			local damage = melee and melee:GetAttribute(Constants.DAMAGE_ATTRIBUTE) or 20

			print("MELEE: Applying " .. damage .. " damage to prop")

			-- Apply damage and check if prop should be destroyed
			local shouldDestroy, previousHealth = EnvironmentalPropHealthSystem.applyDamage(prop, damage)

			print("MELEE: shouldDestroy=" .. tostring(shouldDestroy) .. ", previousHealth=" .. tostring(previousHealth))

			-- If prop shouldn't be destroyed yet, send partial damage event and continue
			if not shouldDestroy then
				-- Send partial damage event to clients
				remoteEvent:FireAllClients("PropDamage", {
					propId = propId,
					propPath = prop:GetFullName(),
					position = part.Position,
					currentHealth = prop:GetAttribute("CurrentHealth"),
					maxHealth = prop:GetAttribute("MaxHealth") or EnvironmentalPropHealthSystem.DEFAULT_PROP_HEALTH,
					previousHealth = previousHealth,
					damageAmount = damage
				})
				print("MELEE: Prop damaged but not destroyed")
				propHit = true
				continue
			end

			-- Mark that we've had a prop hit
			propHit = true

			print("MELEE: Prop should be destroyed now")

			-- Mark prop as hit
			prop:SetAttribute("IsHit", true)

			-- Tag for exclusion
			CollectionService:AddTag(prop, "DisabledProp")

			-- Find trigger and proximity prompt
			local trigger = prop:FindFirstChild("Trigger")
			local proximityPrompt = trigger and trigger:FindFirstChildOfClass("ProximityPrompt")

			-- Disable proximity prompt
			if proximityPrompt then
				proximityPrompt.Enabled = false
			end

			-- Handle collision on server directly
			for _, propPart in ipairs(prop:GetDescendants()) do
				if propPart:IsA("BasePart") then
					propPart.CanCollide = false
				end
			end

			-- Send event to all clients
			remoteEvent:FireAllClients("PropHit", {
				propId = propId,
				propPath = prop:GetFullName(),
				position = part.Position
			})

			-- Restore after 5 seconds - BUT keep protection until clients finish tweens
			task.delay(5, function()
				-- Re-enable collision
				for _, propPart in ipairs(prop:GetDescendants()) do
					if propPart:IsA("BasePart") then
						propPart.CanCollide = true
					end
				end

				-- Re-enable ProximityPrompt
				if proximityPrompt then
					proximityPrompt.Enabled = true
				end

				-- Reset health when prop is restored
				EnvironmentalPropHealthSystem.resetHealth(prop)

				-- Tell clients to restore, but DON'T reset hit state yet
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
	end

			return propHit
end

function MeleeServer.handleAttack(player, data)
	local melee = data.melee
	local attackType = data.attackType
	local comboPhase = data.comboPhase
	local origin = data.origin
	local timestamp = data.timestamp
	local clientHitboxSize = data.hitboxSize
	local clientHitboxOffset = data.hitboxOffset

	-- Validate the received arguments
	if not MeleeValidation.validateAttackArguments(melee, attackType, origin, timestamp) then
		return
	end

	-- Validate that the player can attack
	if not MeleeValidation.validateAttack(player, melee, timestamp) then
		return
	end

	-- Get server-set attributes or fall back to defaults (more secure)
	-- SECURITY: Get attributes from server-side instance, not client data
	local hitboxSize = melee:GetAttribute(Constants.HITBOX_SIZE_ATTRIBUTE) or Vector3.new(3, 1, 4)
	local hitboxOffset = melee:GetAttribute(Constants.HITBOX_OFFSET_ATTRIBUTE) or Vector3.new(0, 0, -2)

	-- Apply maximum limits to prevent exploits
	local MAX_HITBOX_WIDTH = 6
	local MAX_HITBOX_HEIGHT = 3
	local MAX_HITBOX_REACH = 20

	-- Clamp dimensions to maximum allowed values
	local clampedHitboxSize = Vector3.new(
		math.min(hitboxSize.X, MAX_HITBOX_WIDTH),
		math.min(hitboxSize.Y, MAX_HITBOX_HEIGHT),
		math.min(hitboxSize.Z, MAX_HITBOX_REACH)
	)

	-- Update hitboxSize to the clamped value
	hitboxSize = clampedHitboxSize

	-- Calculate hitbox position and orientation based on player's look direction
	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		return
	end

	-- Get damage value from weapon
	local damage = melee:GetAttribute(Constants.DAMAGE_ATTRIBUTE) or 20

	-- Create hitbox at the position and orientation of the attack
	local hitboxCFrame = origin * CFrame.new(hitboxOffset)

	-- Visual debugging of hitbox if enabled
	if Constants.HITBOX_VISUALIZATION then
		MeleeServer.visualizeHitbox(hitboxCFrame, hitboxSize)
	end

	-- Check for environment props first
	local propHit = MeleeServer.checkPropHit(player, hitboxCFrame, hitboxSize)

	-- Perform hit detection for characters
	local hitResults = MeleeServer.performHitDetection(player, hitboxCFrame, hitboxSize)

	-- Process hits
	local anyHits = false
	for _, hitResult in ipairs(hitResults) do
		local hitHumanoid = hitResult.humanoid
		local hitPosition = hitResult.position

		-- Skip if this humanoid was recently hit (debounce)
		local humanoidKey = tostring(hitHumanoid) .. "_" .. tostring(hitHumanoid:GetFullName())
		if hitDebounce[humanoidKey] and tick() - hitDebounce[humanoidKey] < Constants.HIT_DEBOUNCE_TIME then
			continue
		end

		-- Set debounce
		hitDebounce[humanoidKey] = tick()

		-- Apply damage
		if hitHumanoid.Health > 0 then
			anyHits = true

			-- Get the victim player
			local hitPlayer = Players:GetPlayerFromCharacter(hitHumanoid.Parent)

			-- Record damage before applying it
			if hitPlayer then
				local weaponName = melee and melee.Name or "Melee Weapon"
				DamageTracker:recordDamage(hitPlayer, player, weaponName, damage)
				DamageTracker:registerHit(hitPlayer, player, weaponName)
			end

			if hitHumanoid.Health <= damage then
				hitHumanoid.Health = 0
			else
				hitHumanoid:TakeDamage(damage)
			end
		end
	end

	-- Confirm hit to attacker
	remoteEvent:FireClient(player, "MeleeHitConfirm", {
		hit = anyHits
	})

	-- Replicate attack to other clients
	local hitResult = hitResults[1] -- Just take the first hit for visual effect
	local hitPosition = hitResult and hitResult.position or (hitboxCFrame * CFrame.new(0, 0, -hitboxSize.Z/2)).Position

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			remoteEvent:FireClient(otherPlayer, "ReplicateMeleeAttack", {
				playerName = player.Name,
				position = origin.Position,
				hitPosition = hitPosition,
				hitResult = hitResult and {
					hit = true,
					position = hitResult.position,
					normal = hitResult.normal,
					isCharacter = true
				} or nil
			})
		end
	end
end

function MeleeServer.performHitDetection(player, hitboxCFrame, hitboxSize)
	local canPlayerDamageHumanoid = MeleeUtilities.canPlayerDamageHumanoid
	local results = {}

	-- Cast a region to check for potential hits
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Get CollectionService for accessing tagged props
	local CollectionService = game:GetService("CollectionService")

	-- Create exclusion list with player and disabled props
	local exclusions = {player.Character}

	-- Add all disabled props to exclude list
	local disabledProps = CollectionService:GetTagged("DisabledProp")
	for _, disabledProp in ipairs(disabledProps) do
		table.insert(exclusions, disabledProp)
	end

	params.FilterDescendantsInstances = exclusions

	local parts = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)

	-- Process found parts
	local hitHumanoids = {}
	local anyHits = false

	for _, part in ipairs(parts) do
		-- Try to find the model this part belongs to
		local currentModel = part

		-- Keep moving up until we find a Humanoid or hit workspace
		while currentModel and currentModel ~= workspace do
			-- If this is a PropModel, check its parent for a Humanoid
			if currentModel.Name == "PropModel" then
				local characterModel = currentModel.Parent
				if characterModel and characterModel:IsA("Model") then
					local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
					if humanoid then
						if humanoid.Health > 0 and not hitHumanoids[humanoid] then
							-- Check if player can damage this humanoid
							if canPlayerDamageHumanoid(player, humanoid) then
								-- Skip if this humanoid was recently hit (debounce)
								local humanoidKey = tostring(humanoid) .. "_" .. tostring(humanoid:GetFullName())
								if not (hitDebounce[humanoidKey] and tick() - hitDebounce[humanoidKey] < Constants.HIT_DEBOUNCE_TIME) then
									-- Add to results
									table.insert(results, {
										humanoid = humanoid,
										model = characterModel,
										position = part.Position,
										normal = (hitboxCFrame.Position - part.Position).Unit,
										part = part
									})

									-- Mark this humanoid as hit so we don't add it again
									hitHumanoids[humanoid] = true
									anyHits = true
								end
							end
						end
					end

					-- Break out of the while loop since we've checked this PropModel's parent
					break
				else
					break
				end
			end

			-- Also check if this model directly has a Humanoid (for regular players)
			if currentModel:IsA("Model") then
				local humanoid = currentModel:FindFirstChildOfClass("Humanoid")
				if humanoid then
					if humanoid.Health > 0 and not hitHumanoids[humanoid] then
						-- Check if player can damage this humanoid
						if canPlayerDamageHumanoid(player, humanoid) then
							-- Skip if this humanoid was recently hit (debounce)
							local humanoidKey = tostring(humanoid) .. "_" .. tostring(humanoid:GetFullName())
							if not (hitDebounce[humanoidKey] and tick() - hitDebounce[humanoidKey] < Constants.HIT_DEBOUNCE_TIME) then
								-- Add to results
								table.insert(results, {
									humanoid = humanoid,
									model = currentModel,
									position = part.Position,
									normal = (hitboxCFrame.Position - part.Position).Unit,
									part = part
								})

								-- Mark this humanoid as hit
								hitHumanoids[humanoid] = true
								anyHits = true
							end
						end
					end

					-- Break out of the while loop since we've checked this model for a humanoid
					break
				end
			end

			-- Move up to the parent for the next iteration
			currentModel = currentModel.Parent
		end
	end

	return results
end

function MeleeServer.visualizeHitbox(hitboxCFrame, hitboxSize)
	-- Create a part to visualize the hitbox
	local hitboxPart = Instance.new("Part")
	hitboxPart.Size = hitboxSize
	hitboxPart.CFrame = hitboxCFrame
	hitboxPart.Anchored = true
	hitboxPart.CanCollide = false
	hitboxPart.Material = Enum.Material.SmoothPlastic
	hitboxPart.Color = Constants.HITBOX_COLOR
	hitboxPart.Transparency = Constants.HITBOX_TRANSPARENCY
	hitboxPart.Parent = Workspace

	-- Remove the visualization after a brief moment
	task.delay(0.5, function()
		hitboxPart:Destroy()
	end)
end

function MeleeServer.handlePlayerDeath(humanoid)
	local character = humanoid.Parent
	if not character then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Mark this as a melee death
	player:SetAttribute("MeleeDeath", true)

	-- Apply ragdoll to create the visual effect
	RagdollSystem.applyRagdoll(character)

	-- The respawn is handled by RespawnHandler via the died event
end

function MeleeServer.initialize()
	-- Get the single RemoteEvent
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

	-- Connect to the ONE RemoteEvent and route based on event name
	remoteEvent.OnServerEvent:Connect(function(player, eventName, data)
		if eventName == "MeleeAttack" then
			MeleeServer.handleAttack(player, data)
		end
	end)

	-- Connect to the server's bindable event for player elimination
	local serverEvent = ServerScriptService:WaitForChild("Event")
	serverEvent.Event:Connect(function(eventName, data)
		if eventName == "Player_Eliminated" then
			-- Only handle deaths from melee weapons
			if data.weaponName and not string.find(data.weaponName, "Blaster") then
				MeleeServer.handlePlayerDeath(data.humanoid)
			end
		end
	end)

	-- Clear hit debounce periodically to prevent memory buildup
	task.spawn(function()
		while true do
			task.wait(30) -- Every 30 seconds

			-- Clear old entries
			local now = tick()
			local removedCount = 0
			for humanoidId, lastHitTime in pairs(hitDebounce) do
				if now - lastHitTime > 10 then -- If older than 10 seconds
					hitDebounce[humanoidId] = nil
					removedCount = removedCount + 1
				end
			end
		end
	end)
end

MeleeServer.initialize()

return MeleeServer