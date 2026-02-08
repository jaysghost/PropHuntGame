local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local BlasterUtilities = require(ReplicatedStorage.Blaster.BlasterUtilities)
local BlasterVisuals = require(script.Parent.BlasterVisuals)
local BlasterUI = require(script.Parent.BlasterUI)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
-- Single RemoteEvent for all game communication
local remoteEvent = ReplicatedStorage.RemoteEvent

local random = Random.new()
local activeBlasters = {}

local BlasterController = {}
BlasterController.__index = BlasterController

function BlasterController.new(blaster)
	-- Check if a controller already exists for this blaster
	if activeBlasters[blaster] then
		return activeBlasters[blaster]
	end

	local visuals = BlasterVisuals.new(blaster)
	local ui = BlasterUI.new(blaster)

	local self = {
		blaster = blaster,
		visuals = visuals,
		ui = ui,
		activated = false,
		equipped = false,
		shooting = false,
		ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE),
		reloading = blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE),
		connections = {},
		propCache = {}, -- NEW: Add prop parts cache
	}
	setmetatable(self, BlasterController)

	self:initialize()
	activeBlasters[blaster] = self
	return self
end

function BlasterController:isHumanoidAlive()
    return self.humanoid and self.humanoid.Health > 0
end

function BlasterController:canShoot()
    return self:isHumanoidAlive() and self.equipped and self.ammo > 0 and not self.reloading
end

function BlasterController:canReload()
    local magazineSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
    return self:isHumanoidAlive() and self.equipped and self.ammo < magazineSize and not self.reloading
end

function BlasterController:recoil()
    local recoilMin = self.blaster:GetAttribute(Constants.RECOIL_MIN_ATTRIBUTE)
    local recoilMax = self.blaster:GetAttribute(Constants.RECOIL_MAX_ATTRIBUTE)

    local xDif = recoilMax.X - recoilMin.X
    local yDif = recoilMax.Y - recoilMin.Y
    local x = recoilMin.X + random:NextNumber() * xDif
    local y = recoilMin.Y + random:NextNumber() * yDif

    local recoil = Vector2.new(math.rad(-x), math.rad(y))

    BlasterUtilities.applyRecoil(recoil)
end

function BlasterController:shoot()
	local spread = self.blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = self.blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = self.blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = self.blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)

	self.visuals:playShootAnimation()
	self:recoil()

	-- REMOVED: self.ammo -= 1
	-- Let the server handle ammo decrement

	-- Still update UI with current value for responsiveness
	self.ui:setAmmo(self.ammo)

	local now = Workspace:GetServerTimeNow()
	local origin = camera.CFrame

	local rayDirections = BlasterUtilities.getRayDirections(origin, raysPerShot, math.rad(spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	local rayResults = BlasterUtilities.castRays(player, origin.Position, rayDirections, rayRadius)

	-- Build tagged humanoids list
	local tagged = {}
	local didTag = false
	for index, rayResult in rayResults do
		if rayResult.taggedHumanoid then
			tagged[tostring(index)] = rayResult.taggedHumanoid
			didTag = true
		end
	end

	if didTag then
		self.ui:showHitmarker()
	end

	-- Use the SINGLE RemoteEvent with event name pattern
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	remoteEvent:FireServer("Shoot", {
		timestamp = now,
		blaster = self.blaster,
		origin = origin,
		tagged = tagged
	})

	-- The server will update the ammo attribute, which we'll detect via the attribute changed listener

	local muzzlePosition = self.visuals:getMuzzlePosition()
	self.visuals:drawRayResults(muzzlePosition, rayResults)
end

function BlasterController:startShooting()
    -- If the player tries to shoot without any ammo, reload instead
    if self.ammo == 0 then
        self:reload()
        return
    end

    if not self:canShoot() then
        return
    end

    if self.shooting then
        return
    end

    local fireMode = self.blaster:GetAttribute(Constants.FIRE_MODE_ATTRIBUTE)
    local rateOfFire = self.blaster:GetAttribute(Constants.RATE_OF_FIRE_ATTRIBUTE)

    if fireMode == Constants.FIRE_MODE.SEMI then
        self.shooting = true
        self:shoot()
        task.delay(60 / rateOfFire, function()
            self.shooting = false

            if self.ammo == 0 then
                self:reload()
            end
        end)
    elseif fireMode == Constants.FIRE_MODE.AUTO then
        task.spawn(function()
            self.shooting = true
            while self.activated and self:canShoot() do
                self:shoot()
                task.wait(60 / rateOfFire)
            end
            self.shooting = false

            if self.ammo == 0 then
                self:reload()
            end
        end)
    end
end

function BlasterController:reload()
	if not self:canReload() then
		return
	end

	local reloadTime = self.blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)
	local magazineSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)

	self.visuals:playReloadAnimation(reloadTime)

	self.reloading = true
	self.ui:setReloading(self.reloading)

	-- Use the SINGLE RemoteEvent with event name pattern
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	remoteEvent:FireServer("Reload", {
		blaster = self.blaster
	})

	self.reloadTask = task.delay(reloadTime, function()
		self.ammo = magazineSize
		self.reloading = false
		self.reloadTask = nil
		self.ui:setAmmo(self.ammo)
		self.ui:setReloading(self.reloading)
	end)
end

function BlasterController:activate()
    if self.activated then
        return
    end
    self.activated = true

    self:startShooting()
end

function BlasterController:deactivate()
    if not self.activated then
        return
    end
    self.activated = false
end

function BlasterController:equip()
	if self.equipped then
		return
	end
	self.equipped = true

	-- IMPORTANT: Get the current server state
	self.ammo = self.blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	self.reloading = self.blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)

	-- Enable view model
	self.visuals:enable()

	-- Enable GUI
	self.ui:setAmmo(self.ammo)
	self.ui:setReloading(self.reloading)
	self.ui:enable()

	-- Set the reload callback for touch controls
	self.ui:setReloadCallback(function()
		self:reload()
	end)

	-- Keep track of the humanoid in the character currently equipping the blaster.
	-- We need this to make sure the player can't shoot while dead.
	self.humanoid = self.blaster.Parent:FindFirstChildOfClass("Humanoid")
end

function BlasterController:unequip()
	if not self.equipped then
		return
	end

	-- Store the equipped state before changing it
	local wasEquipped = self.equipped
	self.equipped = false

	-- Force deactivate when unequipping
	self:deactivate()

	-- Cancel reload task if active
	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end

	-- Only call these if we were actually equipped
	if wasEquipped then
		self.visuals:disable()
		self.ui:disable()
	end
end

function BlasterController:setupRemoteEventListener()
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

	remoteEvent.OnClientEvent:Connect(function(eventName, data)
		if eventName == "ReplicateShot" then
			print("Received ReplicateShot event")

			-- Draw visual effects for other players' shots
			if data and data.position and data.rayResults then
				print("Drawing replicated shot from player: " .. (data.playerName or "Unknown"))

				-- Add debug info
				for i, result in ipairs(data.rayResults) do
					print("Ray", i, "hit:", result.position)
				end

				-- Use BlasterVisuals directly rather than through self
				-- This ensures we're not checking self.blaster which might not match
				BlasterVisuals.drawRayResultsStatic(data.position, data.rayResults)
			else
				warn("Missing data in ReplicateShot event")
			end
		elseif eventName == "PropHit" then
			self:handlePropHitEffect(data)
		elseif eventName == "PropRestore" then
			self:handlePropRestoreEffect(data)
		elseif eventName == "AmmoUpdate" then
			if data.blaster == self.blaster then
				self.ammo = data.ammo
				self.ui:setAmmo(self.ammo)
			end
		end
	end)
end


function BlasterController:initialize()
	-- Connect to tool events
	table.insert(
		self.connections,
		self.blaster.Equipped:Connect(function()
			self:equip()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Unequipped:Connect(function()
			self:unequip()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Activated:Connect(function()
			self:activate()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Deactivated:Connect(function()
			self:deactivate()
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(inputObject, processed)
			if processed then
				return
			end

			if
				inputObject.KeyCode == Constants.KEYBOARD_RELOAD_KEY_CODE
				or inputObject.KeyCode == Constants.GAMEPAD_RELOAD_KEY_CODE
			then
				self:reload()
			end
		end)
	)

	-- Listen for ammo changes from server
	table.insert(
		self.connections,
		self.blaster:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(function()
			self.ammo = self.blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
			self.ui:setAmmo(self.ammo)
		end)
	)

	-- Listen for reload state changes
	table.insert(
		self.connections,
		self.blaster:GetAttributeChangedSignal(Constants.RELOADING_ATTRIBUTE):Connect(function()
			self.reloading = self.blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)
			self.ui:setReloading(self.reloading)
		end)
	)

	-- Set up touch controls reload callback
	self.ui:setReloadCallback(function()
		self:reload()
	end)

	-- Set up RemoteEvent listener
	self:setupRemoteEventListener()
end

function BlasterController:handlePropHitEffect(data)
	local propId = data.propId
	local propPath = data.propPath
	local position = data.position

	if not position then
		warn("CLIENT: Missing hit position in PropHit event")
		-- Assign a default position if missing
		position = workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 10
	end

	-- Try multiple methods to find the prop
	local targetProp = nil
	local findMethod = "none"

	-- Method 1: Search within ActiveMap by ID (primary method)
	local activeMap = workspace:FindFirstChild("ActiveMap")
	if propId and activeMap then
		for _, model in ipairs(activeMap:GetDescendants()) do
			if model.Name == "Prop" and model:GetAttribute("PropId") == propId then
				targetProp = model
				findMethod = "activeMap_id"
				break
			end
		end
	end

	-- Method 2: Search entire workspace by ID (if ActiveMap search failed)
	if not targetProp and propId then
		for _, model in ipairs(workspace:GetDescendants()) do
			if model.Name == "Prop" and model:GetAttribute("PropId") == propId then
				targetProp = model
				findMethod = "workspace_id"
				break
			end
		end
	end

	-- Method 3: Find by path (if ID methods failed)
	if not targetProp and propPath then
		local pathSegments = string.split(propPath, ".")
		local current = game

		for i, segment in ipairs(pathSegments) do
			if i == 1 and segment == "Workspace" then
				current = workspace  -- Optimization for common case
			else
				current = current:FindFirstChild(segment)
			end

			if not current then
				print("CLIENT: Path traversal failed at segment", i, segment)
				break
			end
		end

		if current and current.Name == "Prop" then
			targetProp = current
			findMethod = "path"
			print("CLIENT: Found prop using path:", propPath)

			-- Set ID for future reference
			if propId and not targetProp:GetAttribute("PropId") then
				targetProp:SetAttribute("PropId", propId)
			end
		end
	end

	-- Method 4: Find by proximity to hit position (smarter fallback)
	if not targetProp and position then
		local closestProp = nil
		local closestDistance = 15 -- Maximum search radius

		-- First check ActiveMap
		if activeMap then
			for _, model in ipairs(activeMap:GetDescendants()) do
				if model.Name == "Prop" then
					local propPosition = model:GetPivot().Position
					local distance = (propPosition - position).Magnitude

					if distance < closestDistance then
						closestProp = model
						closestDistance = distance
						findMethod = "activeMap_position"
					end
				end
			end
		end

		-- If no prop found in ActiveMap, try workspace
		if not closestProp then
			for _, model in ipairs(workspace:GetDescendants()) do
				if model.Name == "Prop" then
					local propPosition = model:GetPivot().Position
					local distance = (propPosition - position).Magnitude

					if distance < closestDistance then
						closestProp = model
						closestDistance = distance
						findMethod = "workspace_position"
					end
				end
			end
		end

		-- Only use if reasonably close
		if closestDistance < 15 then
			targetProp = closestProp
			print("CLIENT: Found prop by proximity, distance:", closestDistance)

			-- Set ID for future reference
			if propId and targetProp and not targetProp:GetAttribute("PropId") then
				targetProp:SetAttribute("PropId", propId)
			end
		end
	end

	if not targetProp then
		warn("CLIENT: Could not find target prop with any method. PropId:", propId, "Position:", position)
		return
	end

	print("CLIENT: Prop found using method:", findMethod, "PropId:", propId)

	-- NEW: Tag the prop locally with the same CollectionService tag used on server
	local CollectionService = game:GetService("CollectionService")
	if not CollectionService:HasTag(targetProp, "DisabledProp") then
		CollectionService:AddTag(targetProp, "DisabledProp")

		-- Remove tag after restoration is complete (matching server timing)
		task.delay(5.7, function() -- 5s delay + 0.7s for tween and buffer
			if targetProp and targetProp.Parent then
				CollectionService:RemoveTag(targetProp, "DisabledProp")
			end
		end)
	end

	-- Store which prop we're working with for restoration
	targetProp:SetAttribute("LastHitId", propId)

	-- NEW: Only collect visible parts and cache them immediately
	local allParts = {}
	local allDecals = {}

	for _, child in ipairs(targetProp:GetDescendants()) do
		-- Handle BaseParts
		if child:IsA("BasePart") and child.Transparency < 1 then
			table.insert(allParts, child)
			-- Store original transparency
			child:SetAttribute("OriginalTransparency", child.Transparency)
		end

		-- ADDED: Handle Decals
		if child:IsA("Decal") and child.Transparency < 1 then
			table.insert(allDecals, child)
			-- Store original transparency
			child:SetAttribute("OriginalTransparency", child.Transparency)
		end
	end

	-- Cache the parts and decals for this prop
	self.propCache[propId] = {
		parts = allParts,
		decals = allDecals
	}

	-- Tween all parts to transparent
	local TweenService = game:GetService("TweenService")
	local disappearInfo = TweenInfo.new(
		0.5,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out
	)

	local tweenedItems = 0

	-- Tween BaseParts
	for _, part in ipairs(allParts) do
		-- Create and play tween
		local tween = TweenService:Create(part, disappearInfo, {
			Transparency = 1
		})
		tween:Play()
		tweenedItems = tweenedItems + 1
	end

	-- ADDED: Tween Decals
	for _, decal in ipairs(allDecals) do
		-- Create and play tween
		local tween = TweenService:Create(decal, disappearInfo, {
			Transparency = 1
		})
		tween:Play()
		tweenedItems = tweenedItems + 1
	end

	-- Create visual hit effect
	local effect = Instance.new("Part")
	effect.Size = Vector3.new(0.5, 0.5, 0.5)
	effect.Transparency = 1
	effect.CanCollide = false
	effect.Anchored = true
	effect.Position = position
	effect.Parent = workspace

	-- Add particle effect
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://6101261295"  -- Wood particle texture
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)  -- This replaces the invalid 'Spread' property
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 0
	emitter.Parent = effect

	-- Emit particles once
	emitter:Emit(20)

	-- Add sound effect
	local hitSound = Instance.new("Sound")
	hitSound.SoundId = "rbxassetid://72256209857936"  -- Breaking sound
	hitSound.Volume = 0.2
	hitSound.Parent = effect
	hitSound:Play()

	-- Clean up effect after 2 seconds
	task.delay(2, function()
		effect:Destroy()
	end)
end

function BlasterController:handlePropRestoreEffect(data)
	local propId = data.propId
	local propPath = data.propPath

	-- First try to use the cached parts if available
	local cache = self.propCache[propId]
	local targetProp = nil
	local findMethod = "none"

	-- If we have a cache, find the prop using it
	if cache then
		local partsCache = cache.parts
		local decalsCache = cache.decals

		if partsCache and #partsCache > 0 and partsCache[1].Parent then
			local firstPart = partsCache[1]
			local possibleProp = firstPart

			-- Traverse up to find the prop model
			while possibleProp and possibleProp ~= workspace and possibleProp.Name ~= "Prop" do
				possibleProp = possibleProp.Parent
			end

			if possibleProp and possibleProp.Name == "Prop" then
				targetProp = possibleProp
				findMethod = "cachedParts"
			end
		elseif decalsCache and #decalsCache > 0 and decalsCache[1].Parent then
			local firstDecal = decalsCache[1]
			local possibleProp = firstDecal.Parent

			-- Traverse up to find the prop model
			while possibleProp and possibleProp ~= workspace and possibleProp.Name ~= "Prop" do
				possibleProp = possibleProp.Parent
			end

			if possibleProp and possibleProp.Name == "Prop" then
				targetProp = possibleProp
				findMethod = "cachedDecals"
			end
		end
	end

	-- If we couldn't find it from the cache, try the normal methods
	if not targetProp then
		-- Method 1: Search by LastHitId attribute (most reliable for restoration)
		for _, model in ipairs(workspace:GetDescendants()) do
			if model.Name == "Prop" and model:GetAttribute("LastHitId") == propId then
				targetProp = model
				findMethod = "lastHitId"
				break
			end
		end

		-- Method 2: Search within ActiveMap by ID
		if not targetProp then
			local activeMap = workspace:FindFirstChild("ActiveMap")
			if propId and activeMap then
				for _, model in ipairs(activeMap:GetDescendants()) do
					if model.Name == "Prop" and model:GetAttribute("PropId") == propId then
						targetProp = model
						findMethod = "activeMap_id"
						break
					end
				end
			end
		end

		-- Method 3: Search entire workspace by ID
		if not targetProp and propId then
			for _, model in ipairs(workspace:GetDescendants()) do
				if model.Name == "Prop" and model:GetAttribute("PropId") == propId then
					targetProp = model
					findMethod = "workspace_id"
					break
				end
			end
		end

		-- Method 4: Find by path
		if not targetProp and propPath then
			local pathSegments = string.split(propPath, ".")
			local current = game

			for i, segment in ipairs(pathSegments) do
				if i == 1 and segment == "Workspace" then
					current = workspace
				else
					current = current:FindFirstChild(segment)
				end

				if not current then
					print("CLIENT RESTORE: Path traversal failed at segment", i, segment)
					break
				end
			end

			if current and current.Name == "Prop" then
				targetProp = current
				findMethod = "path"
			end
		end
	end

	if not targetProp then
		warn("CLIENT RESTORE: Could not find prop to restore. PropId:", propId)
		return
	end

	print("CLIENT RESTORE: Found prop using method:", findMethod, "PropId:", propId)

	-- NEW: Keep CollectionService tag during restoration to prevent additional hits
	local CollectionService = game:GetService("CollectionService")
	if not CollectionService:HasTag(targetProp, "DisabledProp") then
		-- Re-tag to ensure consistency (in case tags got out of sync with server)
		CollectionService:AddTag(targetProp, "DisabledProp")
	end

	-- Use cached items if available, otherwise fall back to search
	local partsToRestore = {}
	local decalsToRestore = {}

	if cache then
		partsToRestore = cache.parts or {}
		decalsToRestore = cache.decals or {}
	end

	-- Fallback to search if cache is not available or empty
	if not cache or (#partsToRestore == 0 and #decalsToRestore == 0) then
		print("Cache miss for prop", propId, "- falling back to search")

		for _, child in ipairs(targetProp:GetDescendants()) do
			-- Find BaseParts with OriginalTransparency attribute
			if child:IsA("BasePart") and child:GetAttribute("OriginalTransparency") ~= nil then
				table.insert(partsToRestore, child)
			end

			-- ADDED: Find Decals with OriginalTransparency attribute
			if child:IsA("Decal") and child:GetAttribute("OriginalTransparency") ~= nil then
				table.insert(decalsToRestore, child)
			end
		end
	end

	-- Create tween info for reappearing
	local TweenService = game:GetService("TweenService")
	local reappearInfo = TweenInfo.new(
		0.5,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.In
	)

	-- Restore all parts
	local restoredItems = 0

	-- Restore BaseParts
	for _, part in ipairs(partsToRestore) do
		-- Get original transparency
		local originalTransparency = part:GetAttribute("OriginalTransparency")

		-- Tween back to original transparency
		local tween = TweenService:Create(part, reappearInfo, {
			Transparency = originalTransparency
		})
		tween:Play()
		restoredItems = restoredItems + 1

		-- Clear the stored attribute as it's no longer needed
		task.delay(0.6, function()
			part:SetAttribute("OriginalTransparency", nil)
		end)
	end

	-- ADDED: Restore Decals
	for _, decal in ipairs(decalsToRestore) do
		-- Get original transparency
		local originalTransparency = decal:GetAttribute("OriginalTransparency")

		-- Tween back to original transparency
		local tween = TweenService:Create(decal, reappearInfo, {
			Transparency = originalTransparency
		})
		tween:Play()
		restoredItems = restoredItems + 1

		-- Clear the stored attribute as it's no longer needed
		task.delay(0.6, function()
			decal:SetAttribute("OriginalTransparency", nil)
		end)
	end

	-- Clear the last hit ID attribute
	targetProp:SetAttribute("LastHitId", nil)

	-- Clear the cache for this prop
	self.propCache[propId] = nil

	-- NEW: Synchronize tag removal with server timing
	task.delay(0.7, function() -- 0.5s tween + 0.2s buffer
		if targetProp and targetProp.Parent then
			CollectionService:RemoveTag(targetProp, "DisabledProp")
			print("CLIENT: Removed DisabledProp tag after restoration completed")
		end
	end)

	print("Restored", restoredItems, "items in prop")
end

function BlasterController:destroy()
	self:unequip()
	BlasterUtilities.disconnectAndClear(self.connections)
	self.visuals:destroy()
	self.ui:destroy()
	activeBlasters[self.blaster] = nil
end

-- Initialize camera recoil system
BlasterUtilities.initializeRecoil()

return BlasterController