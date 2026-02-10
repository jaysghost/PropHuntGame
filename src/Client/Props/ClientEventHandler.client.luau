local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local LocalPlayer = Players.LocalPlayer

local ViewportMethods = require(ReplicatedStorage:WaitForChild("ViewportMethods"))
local WeaponData = require(ReplicatedStorage.Data.WeaponData)
ViewportMethods.InitPlayerBillboards()

local cameraRotation = CFrame.new()  -- Tracks camera-based rotation
local propRotation = 0  -- Tracks just the Q/E rotations
local isRotating = false
local ROTATION_INCREMENT = math.rad(360 / 8)
local ROTATION_DURATION = 0.25

local isFrozen = false
local frozenPosition = nil
local frozenCameraDirection = nil

local isZoomTweening = false
local isFirstPerson = false

local tauntCooldown = false
local TAUNT_COOLDOWN_TIME = 5 -- seconds

-- Add duplicate ability variables
local isDuplicateReady = true

-- Add player role tracking
local currentRole = "None"  -- Default to None until role is assigned

-- Function to disable/enable prop transformation prompts based on role


local function isInPropState()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("PropModel")
end

local function toggleFreeze()
	if not isInPropState() then return end

	local character = LocalPlayer.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if isFrozen == false then
		isFrozen = true
		rootPart.Anchored = true
		frozenPosition = rootPart.Position
		local lookVector = workspace.CurrentCamera.CFrame.LookVector
		frozenCameraDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	elseif isFrozen == true then
		isFrozen = false
		rootPart.Anchored = false
		frozenPosition = nil
		frozenCameraDirection = nil
	end
end

local function updatePropTransform()
	local character = LocalPlayer.Character
	if not character then return end

	local propModel = character:FindFirstChild("PropModel")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")

	if not propModel or not rootPart or not humanoid then return end
	if isFrozen then return end

	humanoid.AutoRotate = false
	local currentPos = rootPart.Position

	-- Update camera rotation
	local lookVector = workspace.CurrentCamera.CFrame.LookVector
	local flatLookVector = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	cameraRotation = CFrame.lookAt(currentPos, currentPos + flatLookVector)

	-- Apply both rotations - camera direction first, then Q/E rotation
	local targetCFrame = cameraRotation * CFrame.Angles(0, propRotation, 0)

	propModel:PivotTo(targetCFrame)
	rootPart.CFrame = CFrame.new(currentPos) * (targetCFrame - targetCFrame.Position)
end

local function rotateProp(character, direction)
	if not isInPropState() or isRotating then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local propModel = character:FindFirstChild("PropModel")
	if not rootPart or not propModel then return end

	isRotating = true
	local startAngle = propRotation
	local targetAngle = startAngle + direction * ROTATION_INCREMENT

	local startTime = tick()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsedTime = tick() - startTime
		local alpha = math.min(elapsedTime / ROTATION_DURATION, 1)
		local easedAlpha = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		propRotation = (1 - easedAlpha) * startAngle + easedAlpha * targetAngle

		if isFrozen and frozenPosition and frozenCameraDirection then
			local baseCFrame = CFrame.lookAt(frozenPosition, frozenPosition + frozenCameraDirection)
			local rotationCFrame = baseCFrame * CFrame.Angles(0, propRotation, 0)
			rootPart.CFrame = CFrame.new(frozenPosition) * (rotationCFrame - rotationCFrame.Position)
		end

		if alpha == 1 then
			connection:Disconnect()
			isRotating = false
		end
	end)
end

-- Add duplicate ability visual effects
local function playDuplicateEffect(model)
	if not model or not model.PrimaryPart then return end

	-- Create particle effect
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://6101261905"  -- Placeholder: replace with your particle texture
	emitter.Rate = 50
	emitter.Lifetime = NumberRange.new(0.5)
	emitter.Speed = NumberRange.new(5)
	emitter.SpreadAngle = Vector2.new(180, 180)  -- This replaces the invalid 'Spread' property
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	emitter.Parent = model.PrimaryPart

	-- Play sound effect
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://6042053626" -- Placeholder: replace with your sound
	sound.Volume = 0.5
	sound.Parent = model.PrimaryPart
	sound:Play()

	-- Clean up after effect
	task.delay(0.5, function()
		emitter:Destroy()
		sound:Destroy()
	end)
end

-- Create cooldown UI feedback
local function createCooldownUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DuplicateAbilityUI"

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 50, 0, 50)
	frame.Position = UDim2.new(0.9, 0, 0.8, 0)
	frame.BackgroundTransparency = 0.5
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.Parent = screenGui

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.1, 0, 0.1, 0)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://6031280882" -- Placeholder: replace with your ability icon
	icon.Parent = frame

	local cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	cooldownOverlay.BackgroundTransparency = 0.7
	cooldownOverlay.Visible = false
	cooldownOverlay.Parent = frame

	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return {
		frame = frame,
		icon = icon,
		cooldownOverlay = cooldownOverlay
	}
end

local function enableFirstPerson()
	if isFirstPerson then return end

	print("Enabling first-person mode")

	-- Make character transparent to avoid blocking view
	local character = LocalPlayer.Character
	if character then
		for _, part in pairs(character:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "Head" then
				if part.Name == "HumanoidRootPart" or part.Name == "Handle" then
					part.Transparency = 1
				else
					part.Transparency = 0.5
				end
			end
		end
	end

	-- Lock character into first-person mode
	LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

	isFirstPerson = true
end

local function disableFirstPerson()
	if not isFirstPerson then return end

	print("Disabling first-person mode")

	-- Reset character transparency
	local character = LocalPlayer.Character
	if character then
		for _, part in pairs(character:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "Head" then
				part.Transparency = 0
			end
		end
	end

	-- Unlock camera
	LocalPlayer.CameraMode = Enum.CameraMode.Classic

	isFirstPerson = false
end

local function createTransformHighlight(propModel)
	if not propModel then 
		print("No PropModel for highlight!")
		return 
	end

	print("Creating transform highlight for", propModel:GetFullName())

	-- Always create a new temporary highlight for the transform effect
	local highlight = Instance.new("Highlight")
	highlight.Name = "TransformHighlight" -- Different name to avoid conflicts

	-- Set properties
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 0
	highlight.Parent = propModel

	print("Transform highlight applied to:", propModel:GetFullName())

	-- Make the highlight flash with a longer duration
	local highlightTween = TweenService:Create(
		highlight, 
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			FillTransparency = 1,
			OutlineTransparency = 1
		}
	)

	-- Play tween
	highlightTween:Play()

	-- Clean up after animation
	highlightTween.Completed:Connect(function()
		if highlight and highlight.Parent then
			highlight:Destroy()
			print("Transform highlight destroyed")
		end
	end)
end

local function adjustCameraZoom(propModel)
	if not propModel then return end

	-- Safety check if player settings exist
	if not LocalPlayer.CameraMinZoomDistance or not LocalPlayer.CameraMaxZoomDistance then 
		return 
	end

	-- Calculate desired zoom based on prop size
	local propSize = propModel:GetExtentsSize().Magnitude

	-- Store original zoom settings
	local originalMinZoom = LocalPlayer.CameraMinZoomDistance
	local originalMaxZoom = LocalPlayer.CameraMaxZoomDistance

	-- Set target zoom based on prop size
	-- Larger props need more distance to be visible
	local targetZoom = math.clamp(propSize * 1.5, 10, 20)

	-- Flag that we're controlling zoom
	isZoomTweening = true

	-- Gradually change the zoom limits
	local zoomTween = TweenService:Create(
		LocalPlayer, 
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			CameraMinZoomDistance = targetZoom * 0.7, -- Allow some zoom in
			CameraMaxZoomDistance = targetZoom * 1.3  -- Allow some zoom out
		}
	)

	zoomTween:Play()

	-- Listen for player input during zoom effect
	local inputConnection
	inputConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel or
			input.UserInputType == Enum.UserInputType.Touch then
			-- Player is trying to manually zoom, cancel our effect
			zoomTween:Cancel()
			isZoomTweening = false
			inputConnection:Disconnect()
		end
	end)

	-- Clean up after tween finishes
	zoomTween.Completed:Connect(function()
		isZoomTweening = false
		inputConnection:Disconnect()

		-- Start a timer to reset to original values if player doesn't zoom
		local resetTimer = 1 -- seconds
		task.delay(resetTimer, function()
			if not isZoomTweening then
				-- Only reset if another effect isn't running
				TweenService:Create(
					LocalPlayer, 
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						CameraMinZoomDistance = originalMinZoom,
						CameraMaxZoomDistance = originalMaxZoom
					}
				):Play()
			end
		end)
	end)
end

local function playTransformSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://100759232197550" 
	sound.Volume = 0.5
	sound.PlaybackSpeed = 1
	sound.Parent = LocalPlayer.Character or workspace

	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function onPlayerTransformed(player)
	-- Only apply effects if it's the local player
	if player ~= LocalPlayer then return end

	local character = player.Character
	if not character then return end

	local propModel = character:FindFirstChild("PropModel")
	if not propModel then return end

	-- Add this line back
	createTransformHighlight(propModel)

	-- Other effects
	adjustCameraZoom(propModel)
	playTransformSound()
end


-- Add this function after other utility functions like createCooldownUI
local function createMobileTauntButton()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TauntButtonGui"

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 60, 0, 60)
	button.Position = UDim2.new(0.05, 0, 0.9, 0)  -- Bottom left corner
	button.Text = "Taunt"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = Color3.new(0.3, 0.3, 0.3)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.Visible = false  -- Only show for props during gameplay
	button.Parent = screenGui

	-- Only show button on mobile devices
	if UserInputService.TouchEnabled then
		button.Visible = currentRole == "Prop"
	end

	button.Activated:Connect(function()
		if currentRole == "Prop" and isInPropState() and not tauntCooldown then
			RemoteEvent:FireServer("PlayTaunt")
			tauntCooldown = true

			-- Visual feedback (slight color change)
			local originalColor = button.BackgroundColor3
			button.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)

			task.delay(TAUNT_COOLDOWN_TIME, function() 
				tauntCooldown = false 
				button.BackgroundColor3 = originalColor
			end)
		end
	end)

	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return button
end

local cooldownUI = createCooldownUI()

local tauntButton = createMobileTauntButton()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if isInPropState() then
		if input.KeyCode == Enum.KeyCode.Q then
			RemoteEvent:FireServer("PropRotationEvent", -1)
		elseif input.KeyCode == Enum.KeyCode.E then
			RemoteEvent:FireServer("PropRotationEvent", 1)
		elseif input.KeyCode == Enum.KeyCode.R then
			toggleFreeze()
		elseif input.KeyCode == Enum.KeyCode.F and isDuplicateReady then
			RemoteEvent:FireServer("DuplicateAbility")
			-- Add taunt functionality with T key
		elseif input.KeyCode == Enum.KeyCode.T and not tauntCooldown and currentRole == "Prop" then
			RemoteEvent:FireServer("PlayTaunt")
			tauntCooldown = true
			task.delay(TAUNT_COOLDOWN_TIME, function() 
				tauntCooldown = false 
			end)
		end
	end

	-- Controller support for taunting (Y button)
	if input.UserInputType == Enum.UserInputType.Gamepad1 then
		if input.KeyCode == Enum.KeyCode.ButtonY and isInPropState() and currentRole == "Prop" and not tauntCooldown then
			RemoteEvent:FireServer("PlayTaunt")
			tauntCooldown = true
			task.delay(TAUNT_COOLDOWN_TIME, function() 
				tauntCooldown = false 
			end)
		end
	end
end)

RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "ResetRotation" then
		propRotation = 0
		cameraRotation = CFrame.new()
		isFrozen = false
		frozenPosition = nil
		frozenCameraDirection = nil

	elseif eventName == "PropRotationEvent" then
		local player, rotationDirection = ...
		local character = player.Character
		if character and character:FindFirstChild("PropModel") then
			rotateProp(character, rotationDirection)
		end

	elseif eventName == "DuplicateSpawned" then
		local duplicateModel = ...
		playDuplicateEffect(duplicateModel)

	elseif eventName == "DuplicateCooldown" then
		local cooldownTime = ...
		isDuplicateReady = false
		cooldownUI.cooldownOverlay.Visible = true

		-- Animate cooldown
		local tween = TweenService:Create(cooldownUI.cooldownOverlay, 
			TweenInfo.new(cooldownTime, Enum.EasingStyle.Linear),
			{BackgroundTransparency = 1}
		)
		tween:Play()

		tween.Completed:Connect(function()
			cooldownUI.cooldownOverlay.BackgroundTransparency = 0.7
			cooldownUI.cooldownOverlay.Visible = false
		end)

	elseif eventName == "DuplicateReady" then
		isDuplicateReady = true
		cooldownUI.cooldownOverlay.Visible = false

	elseif eventName == "PlayerTransformed" then
		local transformedPlayer = ...
		onPlayerTransformed(transformedPlayer)
		ViewportMethods.RemovePlayerBillboard(transformedPlayer)

		task.delay(0.5,function()
			ViewportMethods.CreatePlayerBillboard(transformedPlayer)
		end)

	elseif eventName == "EnableFirstPerson" then
		enableFirstPerson()
	elseif eventName == "DisableFirstPerson" then
		disableFirstPerson()
	elseif eventName == "RoleAssigned" then
		local role = ...
		-- Store the player's role
		currentRole = role

		-- Update taunt button visibility for mobile
		if UserInputService.TouchEnabled and tauntButton then
			tauntButton.Visible = (role == "Prop")
		end

		-- Handle first-person mode
		if role == "Hunter" then
			enableFirstPerson()
		else
			disableFirstPerson()
		end

		-- Handle taunt cooldown event
	elseif eventName == "TauntCooldownStarted" then
		tauntCooldown = true
		task.delay(TAUNT_COOLDOWN_TIME, function()
			tauntCooldown = false
		end)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	updatePropTransform()
end)

local function setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	if isInPropState() then
		humanoid.AutoRotate = false
	else
		humanoid.AutoRotate = true
	end

	propRotation = 0
	cameraRotation = CFrame.new()
	isFrozen = false
	frozenPosition = nil
	frozenCameraDirection = nil

	task.delay(0.5, function()
		ViewportMethods.CreatePlayerBillboard(LocalPlayer)
	end)

	-- Update prompts when character is added
	--updatePropPrompts()
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)
if LocalPlayer.Character then
	setupCharacter(LocalPlayer.Character)
end

-- ============================================================================
-- PROP UI CONTROLLER - Deferred Initialization System
-- ============================================================================

-- Declare PropUI variables at module scope
local propUIHolder
local leftButton
local rightButton
local lockButton
local propUIInitialized = false

-- Lock button images
local LOCK_OPEN_IMAGE = "rbxassetid://125553596095193"
local LOCK_CLOSED_IMAGE = "rbxassetid://101126695739586"

-- Sound effect IDs
local ROTATION_SOUND_ID = "rbxassetid://110425630984487"
local LOCK_SOUND_ID = "rbxassetid://133653146417279"

-- Sound debounce system
local soundDebounce = {
	rotation = false,
	lock = false
}
local SOUND_DEBOUNCE_TIME = 0.1
local animatingButtons = {}

-- Function to play sound effects with debounce
local function playPropSound(soundType)
	if soundDebounce[soundType] then return end

	soundDebounce[soundType] = true

	local sound = Instance.new("Sound")
	sound.SoundId = soundType == "rotation" and ROTATION_SOUND_ID or LOCK_SOUND_ID
	sound.Volume = 0.5
	sound.Parent = workspace

	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)

	task.delay(SOUND_DEBOUNCE_TIME, function()
		soundDebounce[soundType] = false
	end)
end

-- Function to animate button presses
local function animateButtonPress(button)
	if not button or animatingButtons[button] then return end

	animatingButtons[button] = true
	local originalSize = button.Size
	local expandedSize = UDim2.new(
		originalSize.X.Scale * 1.2,
		originalSize.X.Offset * 1.2,
		originalSize.Y.Scale * 1.2,
		originalSize.Y.Offset * 1.2
	)

	local expandTween = TweenService:Create(
		button,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = expandedSize}
	)
	expandTween:Play()

	task.delay(0.15, function()
		if button and button.Parent then
			local contractTween = TweenService:Create(
				button,
				TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Size = originalSize}
			)
			contractTween:Play()
			contractTween.Completed:Connect(function()
				animatingButtons[button] = nil
			end)
		else
			animatingButtons[button] = nil
		end
	end)
end

-- Function to update UI visibility based on role and state
local function updatePropUIVisibility()
	if not propUIInitialized or not propUIHolder then return end

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChild("Humanoid")

	if humanoid and humanoid.Health <= 0 then
		propUIHolder.Visible = false
		return
	end

	local shouldBeVisible = (currentRole == "Prop" and isInPropState())
	propUIHolder.Visible = shouldBeVisible

	if shouldBeVisible and lockButton then
		lockButton.Image = isFrozen and LOCK_CLOSED_IMAGE or LOCK_OPEN_IMAGE
	end
end

-- Function to create click detectors for ImageLabels
local function createClickDetector(imageLabel, callback)
	local existingDetector = imageLabel:FindFirstChild("ClickDetector")
	if existingDetector then
		existingDetector:Destroy()
	end

	local button = Instance.new("TextButton")
	button.Name = "ClickDetector"
	button.Size = UDim2.fromScale(1, 1)
	button.Position = UDim2.fromScale(0, 0)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 10
	button.Parent = imageLabel

	button.MouseButton1Click:Connect(callback)
	return button
end

-- Override rotateProp to add sound and animation
local originalRotateProp = rotateProp
rotateProp = function(character, direction)
	if not isInPropState() or isRotating then 
		return originalRotateProp(character, direction)
	end

	if character == LocalPlayer.Character then
		playPropSound("rotation")

		if propUIInitialized and propUIHolder.Visible then
			local buttonToAnimate = direction < 0 and leftButton or rightButton
			animateButtonPress(buttonToAnimate)
		end
	end

	return originalRotateProp(character, direction)
end

-- Override toggleFreeze to add sound and animation
local originalToggleFreeze = toggleFreeze
toggleFreeze = function()
	local wasFrozen = isFrozen
	originalToggleFreeze()

	if wasFrozen ~= isFrozen then
		playPropSound("lock")

		if propUIInitialized and propUIHolder.Visible and lockButton then
			lockButton.Image = isFrozen and LOCK_CLOSED_IMAGE or LOCK_OPEN_IMAGE
			animateButtonPress(lockButton)
		end
	end
end

-- Main PropUI initialization function
local function initializePropUI()
	if propUIInitialized then
		return true
	end

	print("[PropUI] Starting initialization...")

	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not PlayerGui then
		warn("[PropUI] PlayerGui failed to load!")
		return false
	end

	local clientUI = PlayerGui:WaitForChild("Client", 10)
	if not clientUI then
		warn("[PropUI] Client UI failed to load!")
		return false
	end

	local HUD = clientUI:WaitForChild("HUD", 10)
	if not HUD then
		warn("[PropUI] HUD failed to load!")
		return false
	end

	propUIHolder = HUD:WaitForChild("PropUIHolder", 30)
	if not propUIHolder then
		warn("[PropUI] PropUIHolder failed to load!")
		return false
	end

	leftButton = propUIHolder:WaitForChild("Left", 5)
	rightButton = propUIHolder:WaitForChild("Right", 5)
	lockButton = propUIHolder:WaitForChild("Lock", 5)

	if not leftButton or not rightButton or not lockButton then
		warn("[PropUI] Failed to find UI buttons!")
		return false
	end

	-- Hide UI initially
	propUIHolder.Visible = false
	lockButton.Image = LOCK_OPEN_IMAGE

	-- Set up click detectors
	createClickDetector(leftButton, function()
		if currentRole == "Prop" and isInPropState() then
			animateButtonPress(leftButton)
			RemoteEvent:FireServer("PropRotationEvent", -1)
		end
	end)

	createClickDetector(rightButton, function()
		if currentRole == "Prop" and isInPropState() then
			animateButtonPress(rightButton)
			RemoteEvent:FireServer("PropRotationEvent", 1)
		end
	end)

	createClickDetector(lockButton, function()
		if currentRole == "Prop" and isInPropState() then
			toggleFreeze()
		end
	end)

	propUIInitialized = true
	print("[PropUI] Successfully initialized!")
	return true
end

-- Additional input handler for keyboard button animations
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not propUIInitialized then return end
	if not (isInPropState() and currentRole == "Prop") then return end

	if input.KeyCode == Enum.KeyCode.Q then
		animateButtonPress(leftButton)
	elseif input.KeyCode == Enum.KeyCode.E then
		animateButtonPress(rightButton) 
	elseif input.KeyCode == Enum.KeyCode.R then
		animateButtonPress(lockButton)
	end
end)

-- PropUI-specific RemoteEvent handler
RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "RoleAssigned" then
		task.delay(0.1, updatePropUIVisibility)
	elseif eventName == "PlayerTransformed" then
		local transformedPlayer = ...
		if transformedPlayer == LocalPlayer then
			task.delay(0.1, updatePropUIVisibility)
		end
	elseif eventName == "RoundEnding" or eventName == "WaitingForPlayers" or eventName == "ShowDeathScreen" then
		if propUIInitialized and propUIHolder then
			propUIHolder.Visible = false
		end
	elseif eventName == "PlayerRoleChanged" then
		local playerName, newRole = ...
		if playerName == LocalPlayer.Name then
			currentRole = newRole
			if newRole == "Hunter" and propUIInitialized and propUIHolder then
				propUIHolder.Visible = false

				local transitionSound = Instance.new("Sound")
				transitionSound.SoundId = "rbxassetid://9119720505"
				transitionSound.Volume = 1
				transitionSound.Parent = LocalPlayer.PlayerGui
				transitionSound:Play()

				local screenGui = Instance.new("ScreenGui")
				screenGui.Name = "TransitionEffect"
				screenGui.Parent = LocalPlayer.PlayerGui

				local flash = Instance.new("Frame")
				flash.Size = UDim2.fromScale(1, 1)
				flash.BackgroundColor3 = Color3.new(1, 0, 0)
				flash.BackgroundTransparency = 0.7
				flash.Parent = screenGui

				TweenService:Create(
					flash,
					TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{BackgroundTransparency = 1}
				):Play()

				game:GetService("StarterGui"):SetCore("SendNotification", {
					Title = "Role Changed",
					Text = "You are now a Hunter!",
					Duration = 5
				})

				task.delay(1, function()
					screenGui:Destroy()
				end)
			end
		end
	end
end)

-- Character-specific PropUI updates
LocalPlayer.CharacterAdded:Connect(function(character)
	task.delay(0.5, updatePropUIVisibility)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if propUIInitialized and propUIHolder then
			propUIHolder.Visible = false
		end
	end)
end)

-- ============================================================================
-- DEFERRED PROP UI INITIALIZATION WITH RETRY LOGIC
-- ============================================================================
task.spawn(function()
	local MAX_RETRIES = 3
	local RETRY_DELAYS = {0.5, 2, 5}  -- Increasing delays: 0.5s, 2s, 5s
	local attempt = 0
	local success = false

	while attempt < MAX_RETRIES and not success do
		attempt = attempt + 1

		-- Wait before this attempt
		local delay = RETRY_DELAYS[attempt] or 5
		task.wait(delay)

		print(string.format("[PropUI] Initialization attempt %d/%d", attempt, MAX_RETRIES))

		-- Try to initialize
		success = initializePropUI()

		if success then
			print("[PropUI] Successfully initialized on attempt " .. attempt)
			updatePropUIVisibility()
			break
		else
			if attempt < MAX_RETRIES then
				warn(string.format("[PropUI] Attempt %d failed, retrying in %d seconds...", attempt, RETRY_DELAYS[attempt + 1] or 5))
			else
				warn("[PropUI] All initialization attempts failed - PropUI will be disabled for this player")
				warn("[PropUI] Game is still playable, but PropUI buttons (Q/E/R) won't be visible")
			end
		end
	end
end)

print("[ClientEventHandler] Script loaded successfully")