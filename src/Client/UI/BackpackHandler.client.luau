local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Constants
local DEFAULT_FOV = 35
local EQUIPPED_FOV = 25
local TWEEN_TIME = 0.2          -- General UI tweens
local FOV_TWEEN_TIME = 1        -- Field of view transition time
local ROTATION_TWEEN_TIME = 1   -- Model rotation animation time
local INPUT_DEBOUNCE_TIME = 0.1
local CAMERA_DISTANCE = 5
local DEFAULT_GRADIENT_COLOR = Color3.fromRGB(255, 255, 255)
local EQUIPPED_GRADIENT_COLOR = Color3.fromRGB(255, 0, 0)


-- Floating animation settings
local DEBUG_FLOATING = false    -- Enable debug prints for floating animation
local FLOAT_HEIGHT = 0.2        -- How high the model floats
local FLOAT_CYCLE_TIME = 2.0    -- Time for a complete up-down cycle

-- Variables
local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")
local character = player.Character or player.CharacterAdded:Wait()
local backpackUIs = {} 
local isUpdating = false
local currentlyEquippedTool = nil
local inputDebounce = false
local originalSizes = {} 
local viewportTweens = {}
local pendingToolUpdates = {}  -- Queue for tool updates that are waiting for animations
local floatingAnimations = {}  -- Table to store floating animation connections
local viewportOriginalCFrames = {}

-- Animation tracking
local activeAnimations = {}
local animationCounter = 0
local animationCompletedEvent = Instance.new("BindableEvent")

-- Template references
local templatesFolder = StarterGui:WaitForChild("Templates")
local backpackTemplate = templatesFolder:WaitForChild("BackpackTemplate")

-- Forward declarations
local setupUIClickDetection
local animateBackpack
local initializeBackpack
local rebuildBackpackUI
local updateBackpack
local animateModelRotation
local registerAnimation
local completeAnimation
local startFloatingAnimation
local stopFloatingAnimation

-- Disable default Roblox backpack
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Function to register an animation that is starting
registerAnimation = function(toolName)
	animationCounter = animationCounter + 1
	local animationId = animationCounter
	activeAnimations[animationId] = toolName
	return animationId
end

-- Function to mark an animation as completed
completeAnimation = function(animationId)
	if activeAnimations[animationId] then
		local toolName = activeAnimations[animationId]
		activeAnimations[animationId] = nil

		-- Check if this was the last animation for this tool
		local hasActiveAnimations = false
		for _, name in pairs(activeAnimations) do
			if name == toolName then
				hasActiveAnimations = true
				break
			end
		end

		-- If no more animations for this tool, fire the event
		if not hasActiveAnimations then
			animationCompletedEvent:Fire(toolName)
		end
	end
end

-- Check if a tool has active animations
local function hasActiveAnimation(toolName)
	for _, name in pairs(activeAnimations) do
		if name == toolName then
			return true
		end
	end
	return false
end

-- Tween-based floating implementation
startFloatingAnimation = function(viewportFrame, toolName)
	if DEBUG_FLOATING then print("FLOAT: Starting for", toolName) end

	if not viewportFrame then return end
	local worldModel = viewportFrame:FindFirstChild("WorldModel")
	if not worldModel then return end

	local model = worldModel:FindFirstChildOfClass("Model") or 
		worldModel:FindFirstChildOfClass("BasePart") or 
		worldModel:FindFirstChildOfClass("MeshPart")
	if not model then return end

	-- Stop any existing animation
	stopFloatingAnimation(toolName)

	-- Create a simple offsetValue to track the vertical position
	local offsetValue = Instance.new("NumberValue")
	offsetValue.Value = 0

	-- Get initial position
	local initialPosition = model:IsA("Model") and model:GetPivot().Position or model.Position

	-- Store the floatData
	local floatData = {
		offsetValue = offsetValue,
		initialPosition = initialPosition,
		model = model,
		isModel = model:IsA("Model"),
		tween = nil
	}

	-- Create tween info with looping configuration
	local tweenInfo = TweenInfo.new(
		FLOAT_CYCLE_TIME,       -- Time for complete cycle
		Enum.EasingStyle.Sine,  -- Sine easing for smooth movement
		Enum.EasingDirection.InOut,
		-1,                     -- Repeat infinitely (-1)
		true,                   -- Reverse/ping-pong
		0                       -- No delay
	)

	-- Connect the value changed event
	offsetValue.Changed:Connect(function()
		if not model or not model.Parent then return end

		local yOffset = offsetValue.Value * FLOAT_HEIGHT

		if floatData.isModel then
			-- Store the current CFrame
			local currentCFrame = model:GetPivot()

			-- Create a new CFrame that ONLY changes the Y position
			-- This preserves ALL orientation information exactly
			local newCFrame = CFrame.new(
				currentCFrame.X,
				initialPosition.Y + yOffset,
				currentCFrame.Z
			) * currentCFrame.Rotation

			-- Apply the new CFrame
			model:PivotTo(newCFrame)
		else
			-- For MeshPart/BasePart, just update Y
			model.Position = Vector3.new(
				model.Position.X,
				initialPosition.Y + yOffset,
				model.Position.Z
			)
		end
	end)

	-- Create and play the tween
	local tween = TweenService:Create(offsetValue, tweenInfo, {Value = 1})
	tween:Play()

	-- Store the tween in floatData
	floatData.tween = tween
	floatingAnimations[toolName] = floatData
end

-- Function to stop floating animation
stopFloatingAnimation = function(toolName)
	local floatData = floatingAnimations[toolName]
	if not floatData then return end

	if DEBUG_FLOATING then print("FLOAT: Stopping for", toolName) end

	-- Cancel and clean up tween
	if floatData.tween then
		floatData.tween:Cancel()
		floatData.tween = nil
	end

	-- Clean up offset value
	if floatData.offsetValue then
		floatData.offsetValue:Destroy()
	end

	-- Reset to initial position
	if floatData.model and floatData.model.Parent then
		if floatData.isModel then
			local currentPivot = floatData.model:GetPivot()
			floatData.model:PivotTo(CFrame.new(
				floatData.initialPosition.X,
				floatData.initialPosition.Y,
				floatData.initialPosition.Z
				) * CFrame.fromMatrix(
					Vector3.new(0, 0, 0),
					currentPivot.RightVector,
					currentPivot.UpVector,
					currentPivot.LookVector
				))
		else
			floatData.model.Position = floatData.initialPosition
		end
	end

	-- Clear animation data
	floatingAnimations[toolName] = nil
end

-- Function to find or create the player's HUD
local function findPlayerHUD()
	local playerGui = player:WaitForChild("PlayerGui")
	local playerClient = playerGui:FindFirstChild("Client") or Instance.new("Folder", playerGui)
	playerClient.Name = "Client"

	local playerHUD = playerClient:FindFirstChild("HUD") or Instance.new("Folder", playerClient)
	playerHUD.Name = "HUD"

	return playerHUD
end

-- Find/create player HUD
local hudGui = findPlayerHUD()

-- Function to create a click effect
local function createClickEffect(ui)
	if not ui or not ui.Parent then return end

	local flash = Instance.new("Frame")
	flash.Name = "ClickFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.Position = UDim2.fromScale(0, 0)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.7
	flash.BorderSizePixel = 0
	flash.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = flash

	flash.Parent = ui

	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(flash, tweenInfo, {BackgroundTransparency = 1})
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		flash:Destroy()
	end)
end

-- Helper function to update gradient color
local function updateGradientColor(uiGradient, targetColor, duration)
	if not uiGradient then return end

	local currentKeypoints = uiGradient.Color.Keypoints
	local currentColor = currentKeypoints[1].Value

	local existingThread = uiGradient:GetAttribute("animThread")
	if existingThread then
		task.cancel(existingThread)
	end

	local thread = task.spawn(function()
		local startTime = tick()
		local endTime = startTime + duration

		while tick() < endTime do
			local alpha = (tick() - startTime) / duration
			local r = currentColor.R + (targetColor.R - currentColor.R) * alpha
			local g = currentColor.G + (targetColor.G - currentColor.G) * alpha
			local b = currentColor.B + (targetColor.B - currentColor.B) * alpha
			local newColor = Color3.new(r, g, b)

			local newKeypoints = {}
			for i, keypoint in ipairs(currentKeypoints) do
				table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, newColor))
			end
			uiGradient.Color = ColorSequence.new(newKeypoints)
			task.wait()
		end

		local finalKeypoints = {}
		for i, keypoint in ipairs(currentKeypoints) do
			table.insert(finalKeypoints, ColorSequenceKeypoint.new(keypoint.Time, targetColor))
		end
		uiGradient.Color = ColorSequence.new(finalKeypoints)
	end)

	uiGradient:SetAttribute("animThread", thread)
end

-- Function to animate viewport FOV
local function animateViewportFOV(viewportFrame, expand, toolName)
	if not viewportFrame then return end

	local camera = viewportFrame.CurrentCamera
	if not camera then return end

	if viewportTweens[viewportFrame] then
		viewportTweens[viewportFrame]:Cancel()
		viewportTweens[viewportFrame] = nil
	end

	-- Use dedicated FOV tween time for smoother camera transitions
	local tweenInfo = TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.InOut)

	-- Register this animation
	local animId = registerAnimation(toolName)

	if expand then
		local expandGoal = {FieldOfView = DEFAULT_FOV}
		local expandTween = TweenService:Create(camera, tweenInfo, expandGoal)
		viewportTweens[viewportFrame] = expandTween
		expandTween:Play()

		expandTween.Completed:Connect(function()
			completeAnimation(animId)
		end)
	else
		local contractGoal = {FieldOfView = EQUIPPED_FOV}
		local contractTween = TweenService:Create(camera, tweenInfo, contractGoal)
		viewportTweens[viewportFrame] = contractTween
		contractTween:Play()

		contractTween.Completed:Connect(function()
			completeAnimation(animId)
		end)
	end
end

-- Function to animate model rotation 360 degrees
animateModelRotation = function(viewportFrame, equipping, toolName)
	if not viewportFrame then return end

	local worldModel = viewportFrame:FindFirstChild("WorldModel")
	if not worldModel then return end

	local model = worldModel:FindFirstChildOfClass("Model") or worldModel:FindFirstChildOfClass("BasePart") or worldModel:FindFirstChildOfClass("MeshPart")
	if not model then return end

	-- Register this animation
	local animId = registerAnimation(toolName)

	-- Find all visible parts to rotate
	local partsToRotate = {}
	local originPart = nil

	if model:IsA("Model") then
		-- Get all descendant parts
		local allParts = model:GetDescendants()
		for _, part in ipairs(allParts) do
			if part:IsA("BasePart") or part:IsA("MeshPart") then
				table.insert(partsToRotate, part)

				-- Try to find a primary part as the rotation origin
				if not originPart and (part.Name == "Handle" or part.Name == "Main" or part.Name == "Primary") then
					originPart = part
				end
			end
		end

		-- If no specific origin part found, use the first part
		if not originPart and #partsToRotate > 0 then
			originPart = partsToRotate[1]
		end
	else
		-- The model itself is a part
		table.insert(partsToRotate, model)
		originPart = model
	end

	if #partsToRotate == 0 then
		-- Complete the animation early since we have nothing to rotate
		completeAnimation(animId)
		return
	end

	-- Store original CFrames
	local originalCFrames = {}
	local storedOriginals = viewportOriginalCFrames[toolName]

	if storedOriginals and storedOriginals.parts then
		-- Use stored originals for parts we can find
		for _, part in ipairs(partsToRotate) do
			if storedOriginals.parts[part] then
				originalCFrames[part] = storedOriginals.parts[part]
			else
				originalCFrames[part] = part.CFrame
			end
		end
	else
		-- Fallback to current CFrames if no stored originals
		for _, part in ipairs(partsToRotate) do
			originalCFrames[part] = part.CFrame
		end
	end

	-- Calculate the origin CFrame (center of rotation)
	local originCFrame = originPart and originPart.CFrame or CFrame.new(0, 0, 0)

	-- Set up tween info
	local tweenInfo = TweenInfo.new(
		ROTATION_TWEEN_TIME,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	-- Calculate rotation amount - USING Y-AXIS FOR SIDEWAYS ROTATION
	local rotationAmount = equipping and 360 or -360 -- Clockwise for equip, counter-clockwise for unequip

	-- Create a single value to track rotation progress
	local progressValue = Instance.new("NumberValue")
	progressValue.Value = 0

	-- Connect to the Changed event
	progressValue.Changed:Connect(function()
		local progress = progressValue.Value

		-- Using Y-axis rotation for turning sideways (like a turntable)
		local rotationCFrame = CFrame.Angles(0, math.rad(progress * rotationAmount), 0)

		for _, part in ipairs(partsToRotate) do
			if part and part.Parent then
				local originalCF = originalCFrames[part]
				if originalCF then
					-- Calculate part position relative to origin
					local relativeCF = originCFrame:ToObjectSpace(originalCF)

					-- Apply rotation in origin's space
					local rotatedCF = originCFrame * rotationCFrame * relativeCF

					-- Set the new CFrame
					part.CFrame = rotatedCF
				end
			end
		end
	end)

	-- Create and play the tween
	local tween = TweenService:Create(progressValue, tweenInfo, {Value = 1})

	-- Play the tween
	tween:Play()

	-- When complete, reset and clean up
	tween.Completed:Connect(function()
		-- Ensure we've reached the full rotation
		progressValue.Value = 1

		-- Reset parts to original orientation with slight delay
		task.delay(0.05, function()
			for _, part in ipairs(partsToRotate) do
				if part and part.Parent then
					local originalCF = originalCFrames[part]
					if originalCF then
						part.CFrame = originalCF
					end
				end
			end

			progressValue:Destroy()

			-- Start floating if equipping
			if equipping then
				-- Delay the start of floating animation
				task.delay(0.5, function()
					if currentlyEquippedTool and currentlyEquippedTool.Name == toolName then
						startFloatingAnimation(viewportFrame, toolName)
					end
				end)
			end

			-- Signal animation completion
			completeAnimation(animId)
		end)
	end)
end

-- Function to animate the backpack UI
animateBackpack = function(backpackUI, expand)
	if not backpackUI then return end

	local uiStroke = backpackUI:FindFirstChildOfClass("UIStroke")
	local uiGradient = uiStroke and uiStroke:FindFirstChildOfClass("UIGradient")
	local toolName = backpackUI:GetAttribute("displayedTool")

	if not toolName then return end

	if not originalSizes[backpackUI] then
		originalSizes[backpackUI] = backpackUI.Size
	end

	local tweenInfo = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Register UI animation
	local animId = registerAnimation(toolName)

	if expand then
		local expandGoal = {Size = originalSizes[backpackUI] + UDim2.new(0, 6, 0, 6)}

		if uiStroke then
			local strokeGoal = {Thickness = 3}
			local strokeTween = TweenService:Create(uiStroke, tweenInfo, strokeGoal)
			strokeTween:Play()
		end

		if uiGradient then
			updateGradientColor(uiGradient, EQUIPPED_GRADIENT_COLOR, TWEEN_TIME)
		end

		local expandTween = TweenService:Create(backpackUI, tweenInfo, expandGoal)
		expandTween:Play()

		expandTween.Completed:Connect(function()
			completeAnimation(animId)
		end)

		local viewportFrame = backpackUI:FindFirstChild("ViewportFrame", true)
		if viewportFrame then
			animateViewportFOV(viewportFrame, false, toolName)
			animateModelRotation(viewportFrame, true, toolName)
		end
	else
		local contractGoal = {Size = originalSizes[backpackUI]}

		if uiStroke then
			local strokeGoal = {Thickness = 2}
			local strokeTween = TweenService:Create(uiStroke, tweenInfo, strokeGoal)
			strokeTween:Play()
		end

		if uiGradient then
			updateGradientColor(uiGradient, DEFAULT_GRADIENT_COLOR, TWEEN_TIME)
		end

		local contractTween = TweenService:Create(backpackUI, tweenInfo, contractGoal)
		contractTween:Play()

		contractTween.Completed:Connect(function()
			completeAnimation(animId)
		end)

		local viewportFrame = backpackUI:FindFirstChild("ViewportFrame", true)
		if viewportFrame then
			stopFloatingAnimation(toolName)
			animateViewportFOV(viewportFrame, true, toolName)
			animateModelRotation(viewportFrame, false, toolName)
		end
	end
end

-- Enhanced click detection function
setupUIClickDetection = function(backpackUI)
	if not backpackUI then return end

	-- Try to fix existing click detector if present
	local existingButton = backpackUI:FindFirstChild("ClickDetector")
	if existingButton then
		existingButton:Destroy()
		backpackUI:SetAttribute("clickDetectionSetup", false)
	end

	-- Create a new button
	local button = Instance.new("TextButton")
	button.Name = "ClickDetector"
	button.Size = UDim2.fromScale(1, 1)
	button.Position = UDim2.fromScale(0, 0)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 10 

	-- Connect the button click event
	button.MouseButton1Click:Connect(function()
		if inputDebounce then return end

		-- Start debounce
		inputDebounce = true

		-- Visual feedback
		createClickEffect(backpackUI)

		local toolIndex = backpackUI:GetAttribute("toolIndex")
		if not toolIndex then
			inputDebounce = false
			return
		end

		local targetToolName = backpackUI:GetAttribute("displayedTool")
		if not targetToolName then
			inputDebounce = false
			return
		end

		-- Find the actual tool
		local foundTool = nil
		if character then
			foundTool = character:FindFirstChild(targetToolName)
		end

		if not foundTool then
			foundTool = player.Backpack:FindFirstChild(targetToolName)
		end

		if not foundTool then
			inputDebounce = false
			return
		end

		-- Handle tool equipping/unequipping
		if currentlyEquippedTool == foundTool then
			currentlyEquippedTool = nil
			foundTool.Parent = player.Backpack
			animateBackpack(backpackUI, false)
		else
			if currentlyEquippedTool then
				local oldUI = nil
				for _, ui in pairs(backpackUIs) do
					if ui:GetAttribute("displayedTool") == currentlyEquippedTool.Name then
						oldUI = ui
						break
					end
				end

				currentlyEquippedTool.Parent = player.Backpack
				currentlyEquippedTool = nil

				if oldUI then
					animateBackpack(oldUI, false)
				end

				task.wait(0.05)
			end

			foundTool.Parent = character
			currentlyEquippedTool = foundTool
			animateBackpack(backpackUI, true)
		end

		-- End debounce after delay
		task.delay(INPUT_DEBOUNCE_TIME, function()
			inputDebounce = false
		end)
	end)

	button.Parent = backpackUI
	backpackUI:SetAttribute("clickDetectionSetup", true)
end

-- Function to create and set up the backpack UI for a specific tool
local function setupViewportFrame(tool, index, totalTools)
	local vpmodelName = tool:GetAttribute("vpmodel") or (tool.Name .. "_Default")
	tool:SetAttribute("vpmodel", vpmodelName)

	-- Find the model
	local weaponModelPath = ReplicatedStorage:FindFirstChild("ViewportModels")
	if not weaponModelPath then return false end

	local weaponsFolder = weaponModelPath:FindFirstChild("Weapons")
	if not weaponsFolder then return false end

	local weaponModel = weaponsFolder:FindFirstChild(vpmodelName)
	if not weaponModel then return false end

	-- Create or reuse UI for this tool
	local backpackUI = nil
	for _, ui in pairs(backpackUIs) do
		if ui:GetAttribute("displayedTool") == tool.Name then
			backpackUI = ui
			break
		end
	end

	-- Create new UI if needed
	if not backpackUI then
		backpackUI = backpackTemplate:Clone()

		-- Calculate position
		local xPosition = 0.5
		if totalTools > 1 then
			local spacing = 0.075
			local startX = 0.5 - (spacing * (totalTools - 1) / 2)
			xPosition = startX + (spacing * (index - 1))
		end

		backpackUI.Position = UDim2.new(xPosition, 0, backpackUI.Position.Y.Scale, backpackUI.Position.Y.Offset)

		-- Check HUD reference
		if not hudGui or not hudGui.Parent then
			hudGui = findPlayerHUD()
		end

		backpackUI.Parent = hudGui
		backpackUI.Visible = true
		table.insert(backpackUIs, backpackUI)
	end

	-- Skip viewport updates if an animation is in progress for this tool
	if hasActiveAnimation(tool.Name) then
		return true
	end

	-- Setup viewport
	local viewportFrame = backpackUI:FindFirstChild("ViewportFrame", true)
	if not viewportFrame then return false end

	-- Clear viewport
	for _, child in pairs(viewportFrame:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	-- Create WorldModel
	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewportFrame

	-- Clone model
	local modelClone = weaponModel:Clone()
	modelClone.Parent = worldModel

	-- Store original CFrames
	local toolName = tool.Name
	if modelClone:IsA("Model") then
		local originalPartCFrames = {}
		for _, part in pairs(modelClone:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("MeshPart") then
				originalPartCFrames[part] = part.CFrame
			end
		end
		viewportOriginalCFrames[toolName] = {
			whole = modelClone:GetPivot(),
			parts = originalPartCFrames
		}
	else
		viewportOriginalCFrames[toolName] = {
			whole = modelClone.CFrame
		}
	end

	-- Create camera
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	-- Set FOV
	local initialFOV = DEFAULT_FOV
	if currentlyEquippedTool and currentlyEquippedTool.Name == tool.Name then
		initialFOV = EQUIPPED_FOV
	end
	camera.FieldOfView = initialFOV

	-- Find CameraRef for positioning
	local refPart = nil
	if modelClone:IsA("Model") then
		refPart = modelClone:FindFirstChild("CameraRef", true)
	else
		refPart = modelClone:FindFirstChild("CameraRef")
	end

	if refPart and refPart:IsA("BasePart") then
		local cameraPosition = refPart.Position + 
			Vector3.new(CAMERA_DISTANCE * 0.7, CAMERA_DISTANCE * 0.1, CAMERA_DISTANCE * 0.7)
		camera.CFrame = CFrame.new(cameraPosition, refPart.Position)
	else
		if modelClone:IsA("Model") then
			modelClone:PivotTo(CFrame.new(0, 0, 0))
		else
			modelClone.CFrame = CFrame.new(0, 0, 0)
		end

		camera.CFrame = CFrame.new(
			Vector3.new(CAMERA_DISTANCE * 0.7, CAMERA_DISTANCE * 0.1, CAMERA_DISTANCE * 0.7),
			Vector3.new(0, 0, 0)
		)
	end

	-- Store attributes
	backpackUI:SetAttribute("displayedTool", tool.Name)
	backpackUI:SetAttribute("toolIndex", index)

	-- Set up click detection
	setupUIClickDetection(backpackUI)

	return true
end

-- Update backpack UI display
updateBackpack = function()
	if isUpdating then return end
	isUpdating = true

	-- Ensure HUD reference is valid
	if not hudGui or not hudGui.Parent then
		hudGui = findPlayerHUD()
	end

	-- Update character reference if needed
	if not character or not character.Parent then
		character = player.Character
	end

	-- Collect all tools
	local allTools = {}

	-- From character
	if character then
		for _, item in pairs(character:GetChildren()) do
			if item:IsA("Tool") then
				table.insert(allTools, item)
			end
		end
	end

	-- From backpack
	for _, item in pairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") then
			table.insert(allTools, item)
		end
	end

	-- Sort tools
	table.sort(allTools, function(a, b)
		return a.Name < b.Name
	end)

	-- Remove UIs for tools that no longer exist
	local toRemove = {}
	for i, ui in pairs(backpackUIs) do
		local toolName = ui:GetAttribute("displayedTool")
		local stillExists = false

		for _, tool in pairs(allTools) do
			if tool.Name == toolName then
				stillExists = true
				break
			end
		end

		if not stillExists then
			ui:Destroy()
			table.insert(toRemove, i)
		end
	end

	for i = #toRemove, 1, -1 do
		table.remove(backpackUIs, toRemove[i])
	end

	-- Set up UIs for each tool
	local toolCount = #allTools
	for i, tool in ipairs(allTools) do
		setupViewportFrame(tool, i, toolCount)
	end

	-- Update visibility
	if #allTools == 0 then
		for _, ui in pairs(backpackUIs) do
			ui.Visible = false
		end
	else
		for _, ui in pairs(backpackUIs) do
			ui.Visible = true
		end
	end

	isUpdating = false
	return #backpackUIs > 0
end

-- Initialize the backpack
initializeBackpack = function()
	-- Refresh HUD reference
	hudGui = findPlayerHUD()

	-- Update backpack UI
	local success = updateBackpack()

	if not success then
		task.delay(2, rebuildBackpackUI)
	end

	return success
end

-- Force a complete rebuild
rebuildBackpackUI = function()
	-- Clear all existing UIs
	for _, ui in pairs(backpackUIs) do
		if ui and ui.Parent then
			ui:Destroy()
		end
	end

	-- Reset tracking tables
	table.clear(backpackUIs)
	table.clear(originalSizes)
	table.clear(viewportTweens)

	-- Reset state
	inputDebounce = false

	-- Refresh HUD reference
	hudGui = findPlayerHUD()

	-- Reinitialize
	return updateBackpack()
end

-- Function to handle tool changes
local function onToolChange(changedTool)
	-- Skip if no changedTool info provided
	if not changedTool then return end

	-- Update backpack reference if needed
	local directBackpack = player.Backpack
	if directBackpack ~= backpack then
		backpack = directBackpack
	end

	-- Check if we need to wait for animations to complete
	if hasActiveAnimation(changedTool.Name) then
		-- Add to pending updates
		pendingToolUpdates[changedTool.Name] = true

		-- Set up a connection to wait for this animation to complete
		local connection
		connection = animationCompletedEvent.Event:Connect(function(completedToolName)
			if completedToolName == changedTool.Name then
				-- Animation is done, update the backpack
				updateBackpack()
				-- Remove from pending
				pendingToolUpdates[changedTool.Name] = nil
				-- Disconnect this handler
				connection:Disconnect()
			end
		end)
	else
		-- No animations active, update immediately
		updateBackpack()
	end
end

-- Setup key bindings
local function setupKeyBindings()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or inputDebounce then return end

		-- Only handle number keys 1-9
		local keyNumber = nil
		if input.KeyCode == Enum.KeyCode.One then keyNumber = 1
		elseif input.KeyCode == Enum.KeyCode.Two then keyNumber = 2
		elseif input.KeyCode == Enum.KeyCode.Three then keyNumber = 3
		elseif input.KeyCode == Enum.KeyCode.Four then keyNumber = 4
		elseif input.KeyCode == Enum.KeyCode.Five then keyNumber = 5
		elseif input.KeyCode == Enum.KeyCode.Six then keyNumber = 6
		elseif input.KeyCode == Enum.KeyCode.Seven then keyNumber = 7
		elseif input.KeyCode == Enum.KeyCode.Eight then keyNumber = 8
		elseif input.KeyCode == Enum.KeyCode.Nine then keyNumber = 9
		else
			return -- Not a number key we care about
		end

		-- Start debounce
		inputDebounce = true

		-- Find tool with this index
		local targetToolName = nil
		local targetUI = nil

		for _, ui in pairs(backpackUIs) do
			if ui:GetAttribute("toolIndex") == keyNumber then
				targetToolName = ui:GetAttribute("displayedTool")
				targetUI = ui
				break
			end
		end

		if not targetToolName then
			inputDebounce = false
			return
		end

		-- Find the tool
		local foundTool = nil
		if character then
			foundTool = character:FindFirstChild(targetToolName)
		end
		if not foundTool then
			foundTool = player.Backpack:FindFirstChild(targetToolName)
		end
		if not foundTool then
			inputDebounce = false
			return
		end

		-- Simulate click effect
		if targetUI then
			createClickEffect(targetUI)
		end

		-- Handle tool equipping/unequipping
		if currentlyEquippedTool == foundTool then
			currentlyEquippedTool = nil
			foundTool.Parent = player.Backpack
			animateBackpack(targetUI, false)
		else
			if currentlyEquippedTool then
				local oldToolName = currentlyEquippedTool.Name

				local oldUI = nil
				for _, ui in pairs(backpackUIs) do
					if ui:GetAttribute("displayedTool") == oldToolName then
						oldUI = ui
						break
					end
				end

				currentlyEquippedTool.Parent = player.Backpack
				currentlyEquippedTool = nil

				if oldUI then
					animateBackpack(oldUI, false)
				end

				task.wait(0.05)
			end

			foundTool.Parent = character
			currentlyEquippedTool = foundTool
			animateBackpack(targetUI, true)
		end

		-- End debounce after delay
		task.delay(INPUT_DEBOUNCE_TIME, function()
			inputDebounce = false
		end)
	end)
end

-- Helper function to clean up animations
local function cleanupAnimations()
	-- Clean floating animations
	for toolName, floatData in pairs(floatingAnimations) do
		if type(floatData) == "table" then
			if floatData.tween then
				floatData.tween:Cancel()
			end
			if floatData.offsetValue then
				floatData.offsetValue:Destroy()
			end
		elseif typeof(floatData) == "RBXScriptConnection" then
			floatData:Disconnect()
		end
	end
	table.clear(floatingAnimations)
end

-- Handle character changes
local function setupCharacterConnections(char)
	if not char then return end

	-- Tool events
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolChange(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolChange(child)
		end
	end)

	-- Reset equipped tool
	currentlyEquippedTool = nil

	-- Update reference
	character = char

	-- ADD THE NEW CODE BELOW THIS LINE:

	-- Set up equipped listeners for all tools that get added to the character
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			-- Set up an Equipped listener
			child.Equipped:Connect(function()
				-- Find UI for this tool
				local targetUI = nil
				for _, ui in pairs(backpackUIs) do
					if ui:GetAttribute("displayedTool") == child.Name then
						targetUI = ui
						break
					end
				end

				-- Update equipped state and animate if not already equipped
				if targetUI and currentlyEquippedTool ~= child then
					-- If there's already an equipped tool, unequip it first
					if currentlyEquippedTool then
						local oldToolName = currentlyEquippedTool.Name
						local oldUI = nil

						for _, ui in pairs(backpackUIs) do
							if ui:GetAttribute("displayedTool") == oldToolName then
								oldUI = ui
								break
							end
						end

						if oldUI then
							animateBackpack(oldUI, false)
						end
					end

					-- Update tracking and animate
					currentlyEquippedTool = child
					animateBackpack(targetUI, true)
					print("Backpack updated for equipped tool: " .. child.Name)
				end
			end)

			-- Also handle Unequipped events
			child.Unequipped:Connect(function()
				-- Only process if this is the current equipped tool
				if currentlyEquippedTool == child then
					-- Find UI for this tool
					local targetUI = nil
					for _, ui in pairs(backpackUIs) do
						if ui:GetAttribute("displayedTool") == child.Name then
							targetUI = ui
							break
						end
					end

					if targetUI then
						-- Update tracking and animate
						currentlyEquippedTool = nil
						animateBackpack(targetUI, false)
						print("Backpack updated for unequipped tool: " .. child.Name)
					end
				end
			end)
		end
	end)

	-- Set up listeners for any tools already in the character
	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Tool") then
			-- Set up Equipped listener (same as above)
			child.Equipped:Connect(function()
				local targetUI = nil
				for _, ui in pairs(backpackUIs) do
					if ui:GetAttribute("displayedTool") == child.Name then
						targetUI = ui
						break
					end
				end

				if targetUI and currentlyEquippedTool ~= child then
					if currentlyEquippedTool then
						local oldToolName = currentlyEquippedTool.Name
						local oldUI = nil

						for _, ui in pairs(backpackUIs) do
							if ui:GetAttribute("displayedTool") == oldToolName then
								oldUI = ui
								break
							end
						end

						if oldUI then
							animateBackpack(oldUI, false)
						end
					end

					currentlyEquippedTool = child
					animateBackpack(targetUI, true)
					print("Backpack updated for equipped tool: " .. child.Name)
				end
			end)

			-- Also set up Unequipped listener
			child.Unequipped:Connect(function()
				if currentlyEquippedTool == child then
					local targetUI = nil
					for _, ui in pairs(backpackUIs) do
						if ui:GetAttribute("displayedTool") == child.Name then
							targetUI = ui
							break
						end
					end

					if targetUI then
						currentlyEquippedTool = nil
						animateBackpack(targetUI, false)
						print("Backpack updated for unequipped tool: " .. child.Name)
					end
				end
			end)
		end
	end
end

-- When player respawns
player.CharacterAdded:Connect(function(newChar)
	-- Reset state
	currentlyEquippedTool = nil
	inputDebounce = false

	-- Clear UIs
	for i, ui in pairs(backpackUIs) do
		if ui and ui.Parent then
			ui:Destroy()
		end
	end

	-- Reset tables
	table.clear(backpackUIs)
	table.clear(originalSizes)
	table.clear(viewportTweens)
	table.clear(activeAnimations)
	table.clear(pendingToolUpdates)

	-- Clean up animations
	cleanupAnimations()

	-- Setup new character
	character = newChar
	setupCharacterConnections(newChar)

	-- Refresh HUD reference
	hudGui = findPlayerHUD()

	-- Schedule initialization
	task.wait(0.5)
	task.spawn(initializeBackpack)

	-- Additional safety check
	task.delay(2, function()
		if #backpackUIs == 0 then
			rebuildBackpackUI()
		end
	end)
end)

-- When player dies
player.CharacterRemoving:Connect(function()
	-- Reset equipped tool
	currentlyEquippedTool = nil

	-- Reset UI states
	for _, ui in pairs(backpackUIs) do
		animateBackpack(ui, false)
	end

	-- Clean up animations
	cleanupAnimations()
end)

-- Connect to backpack changes
backpack.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		onToolChange(child)
	end
end)

backpack.ChildRemoved:Connect(function(child)
	if child:IsA("Tool") then
		onToolChange(child)
	end
end)

-- Set up connections for current character
setupCharacterConnections(character)

-- Set up key bindings
setupKeyBindings()

task.wait(5) -- Wait longer before initial setup
initializeBackpack()

-- Keep the backup check
local lastCheckTime = 0
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastCheckTime < 5 then return end
	lastCheckTime = now

	if #backpackUIs == 0 then
		print("Backup initialization triggered for backpack UI")
		rebuildBackpackUI()
	end
end)

print("Backpack system initialized with optimized floating animation.")