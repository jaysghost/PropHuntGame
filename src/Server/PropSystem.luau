-- PropSystem.lua (ModuleScript in ServerScriptService)
local PropSystem = {}

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Constants = require(ReplicatedStorage.Blaster.Constants)

-- Dependency on PropHealthSystem
local PropHealthSystem = require(script.Parent.PropHealthSystem)

-- Module state
local initialized = false

-- Map to track which player is using which original prop
local playerProps = {}

-- Function to find absolute ground level (PROP-SPECIFIC UTILITY)
function PropSystem.findAbsoluteGroundLevel(character)
	local rootPart = character.HumanoidRootPart
	local ray = Ray.new(rootPart.Position, Vector3.new(0, -10, 0))
	local part, position = workspace:FindPartOnRay(ray, character)

	if part then
		return position.Y
	end

	return rootPart.Position.Y
end

-- Add this function to PropSystem.lua after the other prop functions

-- Function to handle player taunts
function PropSystem.playTaunt(player)
	local character = player.Character
	if not character then return end

	-- Verify player is in prop state
	if not character:FindFirstChild("PropModel") then
		print(player.Name .. " attempted to taunt but is not in prop form")
		return
	end

	-- Check player's role attribute
	local playerRole = player:GetAttribute("Role")
	if playerRole ~= "Prop" then
		print(player.Name .. " attempted to taunt but does not have Prop role")
		return
	end

	-- Get player manager instance for this player to access their selected taunt
	local PlayerManager = require(script.Parent.Player.PlayerManager)
	local playerManager = PlayerManager.ActivePlayers[player]
	if not playerManager then
		warn("PlayerManager not found for " .. player.Name)
		return
	end

	-- Get active taunt sound from player's loadout
	local activeTaunt = playerManager:GetActiveTaunt()
	if not activeTaunt then
		warn("No active taunt found for " .. player.Name)
		return
	end

	print(player.Name .. " is taunting with sound: " .. activeTaunt)

	-- Create sound in workspace
	local sound = Instance.new("Sound")

	-- Try to get the sound from ReplicatedStorage
	local tauntSounds = game:GetService("ReplicatedStorage"):FindFirstChild("Sounds")
	if tauntSounds and tauntSounds:FindFirstChild("Taunts") and tauntSounds.Taunts:FindFirstChild(activeTaunt) then
		sound.SoundId = tauntSounds.Taunts[activeTaunt].SoundId
	else
		-- Fallback to a default sound if the specific taunt isn't found
		sound.SoundId = "rbxassetid://170765130" -- Replace with appropriate sound ID
	end

	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 100

	-- Attach sound to player's character for proper 3D positioning
	if character:FindFirstChild("HumanoidRootPart") then
		sound.Parent = character.HumanoidRootPart
	else
		sound.Parent = workspace
		sound.Position = character:GetPivot().Position
	end

	-- Play the sound
	sound:Play()

	-- Cleanup when done
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Function to hide the original prop
function PropSystem.hideOriginalProp(prop)
	if not prop then return end

	-- Tag the entire model for exclusion from raycasts
	if not CollectionService:HasTag(prop, "ClaimedProp") then
		CollectionService:AddTag(prop, "ClaimedProp")
	end

	-- Disable proximity prompt
	local trigger = prop:FindFirstChild("Trigger")
	if trigger then
		local proximityPrompt = trigger:FindFirstChildOfClass("ProximityPrompt")
		if proximityPrompt then
			proximityPrompt.Enabled = false
		end
	end

	-- Hide and disable all parts and decals
	for _, descendant in ipairs(prop:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Store original transparency for later restoration
			descendant:SetAttribute("OriginalTransparency", descendant.Transparency)

			-- Hide and disable collision
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanQuery = false  -- Makes it ignored by raycasts
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			-- Store original transparency for decals/textures
			descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
			descendant.Transparency = 1
		elseif descendant:IsA("SpecialMesh") or descendant:IsA("MeshPart") then
			-- Some meshes have transparency properties
			pcall(function()
				if descendant:GetAttribute("OriginalTransparency") == nil then
					descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
				end
				descendant.Transparency = 1
			end)
		end
	end
end

-- Function to restore the original prop with tweening
function PropSystem.restoreOriginalProp(prop)
	if not prop then return end

	local allTweensComplete = false
	local completedTweens = 0
	local totalTweenables = 0

	-- Count total items that need tweening
	for _, descendant in ipairs(prop:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("Decal") or 
			descendant:IsA("Texture") or descendant:IsA("SpecialMesh") or 
			descendant:IsA("MeshPart")) and 
			descendant:GetAttribute("OriginalTransparency") ~= nil then
			totalTweenables = totalTweenables + 1
		end
	end

	-- If no items to restore, exit early
	if totalTweenables == 0 then return end

	local function checkAllTweensComplete()
		if completedTweens >= totalTweenables then
			allTweensComplete = true

			-- Re-enable functionality after all tweens are done
			for _, descendant in ipairs(prop:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = true
					descendant.CanQuery = true
					descendant:SetAttribute("OriginalTransparency", nil) -- Clean up attribute
				elseif descendant:IsA("Decal") or descendant:IsA("Texture") or 
					descendant:IsA("SpecialMesh") or descendant:IsA("MeshPart") then
					-- Clean up attributes for other elements
					descendant:SetAttribute("OriginalTransparency", nil)
				end
			end

			-- Re-enable proximity prompt
			local trigger = prop:FindFirstChild("Trigger")
			if trigger then
				local proximityPrompt = trigger:FindFirstChildOfClass("ProximityPrompt")
				if proximityPrompt then
					proximityPrompt.Enabled = true
				end
			end

			-- Remove exclusion tag
			CollectionService:RemoveTag(prop, "ClaimedProp")
		end
	end

	-- Start tweens for all items
	for _, descendant in ipairs(prop:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("Decal") or 
			descendant:IsA("Texture") or descendant:IsA("SpecialMesh") or 
			descendant:IsA("MeshPart")) and 
			descendant:GetAttribute("OriginalTransparency") ~= nil then

			local origTransparency = descendant:GetAttribute("OriginalTransparency")

			-- Create tween back to original state
			local tween = TweenService:Create(
				descendant,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Transparency = origTransparency
				}
			)

			tween:Play()

			-- Track tween completion
			tween.Completed:Connect(function()
				completedTweens = completedTweens + 1
				checkAllTweensComplete()
			end)
		end
	end
end

-- Function to handle prop transformation with correct hip height alignment
function PropSystem.transformPlayer(player, prop)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- If player is already a prop, restore their old prop
	local oldProp = playerProps[player.UserId]
	if oldProp and oldProp.Parent then
		PropSystem.restoreOriginalProp(oldProp)
	end

	-- FIXED ORDER: Clone the prop FIRST (while it's still visible)
	local propModel = prop:Clone()
	propModel.Name = "PropModel"

	-- THEN hide the original prop that the player is transforming into
	PropSystem.hideOriginalProp(prop)

	-- Track the new prop with the player
	playerProps[player.UserId] = prop

	-- Clean up any existing transform first
	PropSystem.cleanupTransform(character)

	-- Hide character parts and accessories
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 1
		end
		if part:IsA("Accessory") or part:IsA("Hat") then
			if part:FindFirstChild("Handle") then
				part.Handle.Transparency = 1
				part.Handle.CanCollide = false
				if not CollectionService:HasTag(part.Handle, Constants.RAY_EXCLUDE_TAG) then
					CollectionService:AddTag(part.Handle, Constants.RAY_EXCLUDE_TAG)
				end
				local mesh = part.Handle:FindFirstChild("Mesh") or part.Handle:FindFirstChild("SpecialMesh")
				if mesh and mesh:IsA("SpecialMesh") then
					pcall(function()
						mesh.Transparency = 1
					end)
				end
			end
		end
	end

	-- Handle the highlight correctly - IMPORTANT FIX
	if propModel:FindFirstChild("Highlight") then
		local highlight = propModel:FindFirstChild("Highlight")

		-- Store original properties
		local originalFillTransparency = highlight.FillTransparency
		local originalOutlineTransparency = highlight.OutlineTransparency

		-- Flash the highlight
		highlight.FillTransparency = 0
		highlight.OutlineTransparency = 0

		-- Tween back to original state
		game:GetService("TweenService"):Create(
			highlight,
			TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				FillTransparency = originalFillTransparency,
				OutlineTransparency = originalOutlineTransparency
			}
		):Play()
	end

	-- Remove trigger
	local trigger = propModel:FindFirstChild("Trigger")
	if trigger then
		trigger:Destroy()
	end

	-- Get the base for initial positioning
	local base = propModel:FindFirstChild("Base")
	if not base then return end

	-- Get the exact hip height (distance from HumanoidRootPart center to feet)
	local hipHeight = humanoid.HipHeight

	-- Calculate the position of character's feet/bottom
	local rootPosition = rootPart.Position
	local characterBottomPosition = rootPosition - Vector3.new(0, hipHeight, 0)

	-- Apply an offset to fix the consistent floating (adjust this value based on testing)
	local GROUND_OFFSET = 0.95 -- Start with this and adjust as needed
	characterBottomPosition = characterBottomPosition - Vector3.new(0, GROUND_OFFSET, 0)

	-- Position prop with its base aligned to character bottom
	local newPropCFrame = CFrame.new(
		rootPosition.X, 
		characterBottomPosition.Y + (base.Size.Y / 2), -- Align base center with character bottom
		rootPosition.Z
	) * (base.CFrame - base.CFrame.Position)

	-- Apply the positioning
	propModel:PivotTo(newPropCFrame)
	rootPart.CFrame = CFrame.new(rootPart.Position) * (base.CFrame - base.CFrame.Position)

	-- Now remove the base part
	base:Destroy()

	-- Parent the model after positioning
	propModel.Parent = character

	-- Create welds for remaining parts
	for _, part in ipairs(propModel:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Remove any existing welds
			for _, weld in ipairs(part:GetChildren()) do
				if weld:IsA("WeldConstraint") and weld.Part0 == rootPart then
					weld:Destroy()
				end
			end

			-- Create new weld
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = part
			weld.Parent = part
			part.CanCollide = false
			part.Anchored = false
		end
	end

	PropHealthSystem.createHighlight(character)
	-- Reset rotation index
	RemoteEvent:FireClient(player, "ResetRotation")
	RemoteEvent:FireAllClients("PlayerTransformed", player)

	return true
end

-- Helper function to clean up transforms
function PropSystem.cleanupTransform(character)
	if not character then return end

	local currentHumanoid = character:FindFirstChild("Humanoid")
	if currentHumanoid then
		currentHumanoid.AutoRotate = true  -- Re-enable default rotation
	end

	-- Restore character visibility
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 0
		end

		if part:IsA("Accessory") or part:IsA("Hat") then
			if part:FindFirstChild("Handle") then
				part.Handle.Transparency = 0
				local mesh = part.Handle:FindFirstChild("Mesh") or part.Handle:FindFirstChild("SpecialMesh")
				if mesh and mesh:IsA("SpecialMesh") then
					pcall(function()
						mesh.Transparency = 0
					end)
				end
			end
		end
	end

	-- Remove prop model
	local propModel = character:FindFirstChild("PropModel")
	if propModel then
		propModel:Destroy()
	end
end

-- Function to handle prop rotation
function PropSystem.handlePropRotation(player, rotationDirection)
	-- Broadcast rotation event to all clients
	RemoteEvent:FireAllClients("PropRotationEvent", player, rotationDirection)
end

-- Find all available props in the workspace
function PropSystem.findAvailableProps()
	local availableProps = {}

	-- Look for props in the active map
	local activeMap = workspace:FindFirstChild("ActiveMap")
	if activeMap then
		for _, obj in pairs(activeMap:GetDescendants()) do
			if obj.Name == "Prop" then
				table.insert(availableProps, obj)
			end
		end
	end

	-- If no active map or no props found, look in workspace
	if #availableProps == 0 then
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj.Name == "Prop" then
				table.insert(availableProps, obj)
			end
		end
	end

	return availableProps
end

-- Select a random prop
function PropSystem.getRandomProp()
	local availableProps = PropSystem.findAvailableProps()
	if #availableProps > 0 then
		return availableProps[math.random(1, #availableProps)]
	end
	return nil
end

-- Auto-transform a player into a random prop
function PropSystem.autoTransformPlayer(player)
	local randomProp = PropSystem.getRandomProp()
	if randomProp then
		PropSystem.transformPlayer(player, randomProp)
		return true
	end
	return false
end

-- Auto-transform all players with the "Prop" role
function PropSystem.autoTransformAllProps(playerRoles)
	local transformed = 0

	for userId, role in pairs(playerRoles) do
		if role == "Prop" then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local success = PropSystem.autoTransformPlayer(player)
				if success then
					transformed = transformed + 1
				end
			end
		end
	end

	return transformed
end

-- Cleanup when a player leaves to restore their prop
function PropSystem.onPlayerLeaving(player)
	local prop = playerProps[player.UserId]
	if prop and prop.Parent then
		PropSystem.restoreOriginalProp(prop)
	end

	-- Clean up tracking
	playerProps[player.UserId] = nil
end

-- Handle player death - restore their prop
function PropSystem.onPlayerDeath(player)
	local prop = playerProps[player.UserId]
	if prop and prop.Parent then
		PropSystem.restoreOriginalProp(prop)
		playerProps[player.UserId] = nil
	end
end

-- Initialize the PropSystem
function PropSystem.init()
	if initialized then return end

	-- Connect to prompt triggered events
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local trigger = prompt.Parent
		if trigger and trigger.Name == "Trigger" then
			local prop = trigger.Parent
			if prop and prop.Name == "Prop" then
				PropSystem.transformPlayer(player, prop)
			end
		end
	end)

	-- Connect to RemoteEvent for rotation and taunt
	RemoteEvent.OnServerEvent:Connect(function(player, eventName, ...)
		if eventName == "PropRotationEvent" then
			PropSystem.handlePropRotation(player, ...)
		elseif eventName == "PlayTaunt" then
			PropSystem.playTaunt(player)
		elseif eventName == "DuplicateAbility" then
			-- Existing DuplicateAbility code if present
		end
	end)

	-- Connect to player leaving to restore their prop
	Players.PlayerRemoving:Connect(function(player)
		PropSystem.onPlayerLeaving(player)
	end)

	-- Connect to character death
	for _, player in ipairs(Players:GetPlayers()) do
		PropSystem.connectPlayerDeathEvents(player)
	end

	Players.PlayerAdded:Connect(function(player)
		PropSystem.connectPlayerDeathEvents(player)
	end)

	initialized = true
end

-- Set up player death connections
function PropSystem.connectPlayerDeathEvents(player)
	local function onCharacterAdded(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			PropSystem.onPlayerDeath(player)
		end)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
end

-- Function to manually update raycast properties of all claimed props
-- Call this if you modify your raycast system
function PropSystem.updateRaycastExclusions()
	for _, prop in ipairs(CollectionService:GetTagged("ClaimedProp")) do
		for _, part in ipairs(prop:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanQuery = false
			end
		end
	end
end

return PropSystem