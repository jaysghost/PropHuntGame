local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Melee.Constants)
local MeleeUtilities = require(ReplicatedStorage.Melee.MeleeUtilities)
local MeleeVisuals = require(script.Parent.MeleeVisuals)
local MeleeUI = require(script.Parent.MeleeUI)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
-- Single RemoteEvent for all game communication
local remoteEvent = ReplicatedStorage.RemoteEvent

local activeMeleeWeapons = {}

local MeleeController = {}
MeleeController.__index = MeleeController

function MeleeController.new(melee)
	-- Check if a controller already exists for this melee weapon
	if activeMeleeWeapons[melee] then
		return activeMeleeWeapons[melee]
	end

	local visuals = MeleeVisuals.new(melee)
	local ui = MeleeUI.new(melee)

	local self = {
		melee = melee,
		visuals = visuals,
		ui = ui,
		equipped = false,
		attacking = false,
		comboPhase = 0,
		lastAttackTime = 0,
		inputHeld = false,        -- Track if input is being held
		attackCycleActive = false, -- Track if attack cycle is running
		connections = {},
		propCache = {}, -- NEW: Add prop parts cache
	}
	setmetatable(self, MeleeController)

	self:initialize()
	activeMeleeWeapons[melee] = self
	return self
end
function MeleeController:isHumanoidAlive()
	return self.humanoid and self.humanoid.Health > 0
end

function MeleeController:canAttack()
	if not self:isHumanoidAlive() or not self.equipped then
		return false
	end

	if self.attacking then
		return false
	end

	local now = tick()
	if now - self.lastAttackTime < Constants.ATTACK_COOLDOWN then
		return false
	end

	return true
end

function MeleeController:performAttack(attackType)
	if not self:canAttack() then
		return
	end

	self.attacking = true
	local now = Workspace:GetServerTimeNow() -- Use synchronized server time
	self.lastAttackTime = tick() -- Still use tick() for local time tracking

	-- Update combo phase (simplified - just alternate attacks with each press)
	if attackType == Constants.ATTACK_TYPE.PRIMARY then
		-- Always advance combo phase (1 or 2)
		self.comboPhase = (self.comboPhase % 2) + 1
	else
		-- Secondary attack is always the same
		self.comboPhase = 0
	end

	-- Determine which animation to play
	local animationName = (attackType == Constants.ATTACK_TYPE.PRIMARY) 
		and (self.comboPhase == 1 and Constants.ANIMATION_NAMES.ATTACK1 or Constants.ANIMATION_NAMES.ATTACK2)
		or Constants.ANIMATION_NAMES.ATTACK2

	-- Play attack animation
	self.visuals:playAttackAnimation(animationName)

	-- Determine hitbox parameters based on weapon configuration
	local range = self.melee:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local hitboxSize = self.melee:GetAttribute(Constants.HITBOX_SIZE_ATTRIBUTE) or Vector3.new(3, 1, 4)
	local hitboxOffset = self.melee:GetAttribute(Constants.HITBOX_OFFSET_ATTRIBUTE) or Vector3.new(0, 0, -2)

	-- Send attack event to server
	local origin = camera.CFrame
	remoteEvent:FireServer("MeleeAttack", {
		melee = self.melee,
		attackType = attackType,
		comboPhase = self.comboPhase,
		origin = origin,
		timestamp = now,
		hitboxSize = hitboxSize,
		hitboxOffset = hitboxOffset
	})

	-- End attack state after animation
	local attackRate = self.melee:GetAttribute(Constants.ATTACK_RATE_ATTRIBUTE) or 1
	local attackDuration = 1 / attackRate

	task.delay(attackDuration, function()
		self.attacking = false

		-- If input is still held, continue attack cycle
		if self.inputHeld and self.equipped and self.attackCycleActive then
			self:continueAttackCycle()
		end
	end)
end

function MeleeController:primaryAttack()
	-- Start attack cycle for continuous attacks
	if not self.attackCycleActive then
		self.inputHeld = true
		self.attackCycleActive = true
		self:performAttack(Constants.ATTACK_TYPE.PRIMARY)
	end
end

function MeleeController:secondaryAttack()
	self:performAttack(Constants.ATTACK_TYPE.SECONDARY)
end

function MeleeController:continueAttackCycle()
	-- Only continue if input is still held
	if self.inputHeld and self.equipped and not self.attacking then
		self:performAttack(Constants.ATTACK_TYPE.PRIMARY)
	else
		self.attackCycleActive = false
	end
end

function MeleeController:stopAttackCycle()
	self.inputHeld = false
	self.attackCycleActive = false

	-- Let combo phase naturally reset via combo reset timer
end

function MeleeController:equip()
	if self.equipped then
		return
	end
	self.equipped = true

	-- Enable view model
	self.visuals:enable()

	-- Enable GUI
	self.ui:enable()

	-- Keep track of the humanoid in the character currently equipping the melee weapon.
	-- We need this to make sure the player can't attack while dead.
	self.humanoid = self.melee.Parent:FindFirstChildOfClass("Humanoid")
end

function MeleeController:unequip()
	if not self.equipped then
		return
	end
	self.equipped = false

	-- Reset attack state
	self.comboPhase = 0
	self.attacking = false
	self.inputHeld = false
	self.attackCycleActive = false

	-- Disable visuals and UI
	self.visuals:disable()
	self.ui:disable()

	-- Clear humanoid reference
	self.humanoid = nil
end

function MeleeController:setupRemoteEventListener()
	local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

	remoteEvent.OnClientEvent:Connect(function(eventName, data)
		if eventName == "ReplicateMeleeAttack" then
			-- Draw visual effects for other players' attacks
			if data and data.playerName and data.position and data.hitPosition then
				MeleeVisuals.drawSwingEffectStatic(
					data.position, 
					data.hitPosition, 
					data.hitResult
				)
			end
		elseif eventName == "MeleeHitConfirm" then
			-- Show hit marker and play hit sound
			if data.hit then
				self.ui:showHitmarker()
			end
		elseif eventName == "PropHit" then
			-- Handle prop hit visual effect
			self:handlePropHitEffect(data)
		elseif eventName == "PropRestore" then
			-- Handle prop restoration
			self:handlePropRestoreEffect(data)
		end
	end)
end

function MeleeController:handlePropHitEffect(data)
	local propId = data.propId
	local propPath = data.propPath
	local position = data.position

	if not position then
		warn("CLIENT: Missing hit position in PropHit event")
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

	-- NEW: Only collect visible parts and decals and cache them immediately
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

	-- Tween BaseParts
	for _, part in ipairs(allParts) do
		-- Create and play tween
		local tween = TweenService:Create(part, disappearInfo, {
			Transparency = 1
		})
		tween:Play()
	end

	-- ADDED: Tween Decals
	for _, decal in ipairs(allDecals) do
		-- Create and play tween
		local tween = TweenService:Create(decal, disappearInfo, {
			Transparency = 1
		})
		tween:Play()
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
	emitter.SpreadAngle = Vector2.new(180, 180)
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

function MeleeController:handlePropRestoreEffect(data)
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

function MeleeController:initialize()
	-- Connect to tool events
	table.insert(
		self.connections,
		self.melee.Equipped:Connect(function()
			self:equip()
		end)
	)
	table.insert(
		self.connections,
		self.melee.Unequipped:Connect(function()
			self:unequip()
		end)
	)

	-- Connect primary attack input (left mouse click/R1)
	table.insert(
		self.connections,
		self.melee.Activated:Connect(function()
			self:primaryAttack()
		end)
	)

	-- Connect deactivation to stop attack cycle
	table.insert(
		self.connections,
		self.melee.Deactivated:Connect(function()
			self:stopAttackCycle()
		end)
	)

	-- Connect secondary attack input (right mouse click/R2)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(inputObject, processed)
			if processed then
				return
			end

			if self.equipped then
				if inputObject.UserInputType == Constants.KEYBOARD_ATTACK2_KEY_CODE or
					inputObject.KeyCode == Constants.GAMEPAD_ATTACK2_KEY_CODE then
					self:secondaryAttack()
				end
			end
		end)
	)

	-- Listen for input ended to stop attack cycle for keyboard/mouse
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(inputObject)
			if self.equipped then
				if (inputObject.UserInputType == Enum.UserInputType.MouseButton1 or
					inputObject.KeyCode == Constants.GAMEPAD_ATTACK_KEY_CODE) and
					self.attackCycleActive then
					self:stopAttackCycle()
				end
			end
		end)
	)

	-- Set up RemoteEvent listener
	self:setupRemoteEventListener()
end

function MeleeController:checkHit()
	-- Get the player's character and weapon
	local character = self.player.Character
	if not character or not self.equipped then return end

	-- Get weapon properties
	local hitboxSize = self.melee:GetAttribute(Constants.HITBOX_SIZE_ATTRIBUTE) or Vector3.new(3, 1, 4)
	local hitboxOffset = self.melee:GetAttribute(Constants.HITBOX_OFFSET_ATTRIBUTE) or Vector3.new(0, 0, -2)

	-- Calculate hitbox position based on character orientation
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local hitboxCFrame = rootPart.CFrame * CFrame.new(hitboxOffset)

	-- Set up overlap parameters
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}

	-- Check for overlapping parts
	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)

	-- Process results
	local hitResults = {}
	local processedModels = {}

	for _, part in ipairs(parts) do
		-- Find the model this part belongs to
		local model = part
		while model and model ~= workspace and not model:IsA("Model") do
			model = model.Parent
		end

		-- Skip if already processed this model
		if model and not processedModels[model] then
			processedModels[model] = true

			-- Check if it's a prop
			if model.Name == "Prop" then
				-- Add explicit CollectionService tag check
				local CollectionService = game:GetService("CollectionService")
				if CollectionService:HasTag(model, "DisabledProp") then
					-- Skip this prop - it's disabled
					continue
				end

				-- Valid prop hit
				table.insert(hitResults, {
					model = model,
					position = part.Position,
					part = part
				})
			elseif model:FindFirstChildOfClass("Humanoid") then
				-- It's a character - add to results
				table.insert(hitResults, {
					model = model,
					position = part.Position,
					humanoid = model:FindFirstChildOfClass("Humanoid"),
					part = part
				})
			end
		end
	end

	-- Process hits (props and characters)
	if #hitResults > 0 then
		self:processHitResults(hitResults)
	end

	return hitResults
end

function MeleeController:destroy()
	self:unequip()
	MeleeUtilities.disconnectAndClear(self.connections)
	self.visuals:destroy()
	self.ui:destroy()
	activeMeleeWeapons[self.melee] = nil
end

return MeleeController