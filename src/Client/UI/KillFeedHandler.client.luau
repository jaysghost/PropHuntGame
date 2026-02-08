-- KillFeedClient.lua - Place in StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Import ViewportMethods
local ViewportMethods = require(ReplicatedStorage:WaitForChild("ViewportMethods"))

-- Get the single RemoteEvent that's used for all game communication
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local currentDeathScreen = nil

-- Find required UI elements
local clientGui = PlayerGui:WaitForChild("Client")
local hudFrame = clientGui:WaitForChild("HUD")

-- Template is in StarterGui.Templates

local killFeedConnection = nil

-- Constants
local DISPLAY_DURATION = 7  -- How long each kill feed stays visible
local TWEEN_IN_TIME = 0.5   -- Fade in time
local TWEEN_OUT_TIME = 0.2  -- Quick fade out time
local MOVE_TWEEN_TIME = 0.2 -- Time for entries to move up
local ENTRY_SPACING = 10    -- Spacing between stacked entries

-- Keep track of active entries and their Y positions
local activeEntries = {}

-- Function to find a descendant
local function findDescendant(parent, name)
	for _, child in ipairs(parent:GetDescendants()) do
		if child.Name == name then
			return child
		end
	end
	return nil
end


-- Custom function to tween UIGradient transparency
local function tweenGradientTransparency(gradient, startSequence, endSequence, duration, easingStyle, easingDirection, onComplete)
	-- Default parameters
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDirection = easingDirection or Enum.EasingDirection.Out

	-- Start the tween
	local startTime = tick()
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.clamp(elapsed / duration, 0, 1)

		-- Apply easing
		local easedAlpha
		if easingStyle == Enum.EasingStyle.Linear then
			easedAlpha = alpha
		elseif easingStyle == Enum.EasingStyle.Sine then
			if easingDirection == Enum.EasingDirection.Out then
				easedAlpha = math.sin(alpha * math.pi/2)
			elseif easingDirection == Enum.EasingDirection.In then
				easedAlpha = 1 - math.cos(alpha * math.pi/2)
			else -- InOut
				easedAlpha = -(math.cos(math.pi * alpha) - 1) / 2
			end
		else
			-- Default to linear if unsupported easing
			easedAlpha = alpha
		end

		-- Create interpolated sequence
		local newKeypoints = {}
		for i, startKp in ipairs(startSequence.Keypoints) do
			local endKp = endSequence.Keypoints[i]
			local value = (1 - easedAlpha) * startKp.Value + easedAlpha * endKp.Value
			table.insert(newKeypoints, NumberSequenceKeypoint.new(startKp.Time, value))
		end

		gradient.Transparency = NumberSequence.new(newKeypoints)

		if alpha >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	-- Return a function to cancel the tween if needed
	return function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

-- Calculate positions for all entries
local function repositionEntries()
	-- Sort entries by age (oldest first)
	table.sort(activeEntries, function(a, b)
		return a.creationTime < b.creationTime
	end)

	-- Position each entry
	for i, entryData in ipairs(activeEntries) do
		local entry = entryData.instance
		if entry and entry.Parent then
			-- Calculate new Y position (first entry at the original position)
			local newY = entryData.originalY
			if i > 1 then
				-- For subsequent entries, position them below previous entries
				local previousEntry = activeEntries[i-1].instance
				if previousEntry and previousEntry.Parent then
					newY = activeEntries[i-1].currentY + previousEntry.AbsoluteSize.Y + ENTRY_SPACING
				end
			end

			-- Tween to new position
			if newY ~= entryData.currentY then
				local newPosition = UDim2.new(
					entry.Position.X.Scale, 
					entry.Position.X.Offset,
					entry.Position.Y.Scale,
					newY
				)

				-- Use tween for smooth movement
				TweenService:Create(
					entry,
					TweenInfo.new(MOVE_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{Position = newPosition}
				):Play()

				-- Update stored Y position
				entryData.currentY = newY
			end
		end
	end
end

local function isPointInFrame(frame, pointX, pointY)
	local absPos = frame.AbsolutePosition
	local absSize = frame.AbsoluteSize

	return pointX >= absPos.X and pointX <= absPos.X + absSize.X and
		pointY >= absPos.Y and pointY <= absPos.Y + absSize.Y
end

local function setupFrameButton(frame, callback)
	-- Store original size
	local origSize = frame.Size

	-- Initialize hover state attribute
	frame:SetAttribute("isHovering", false)

	-- Create connections for events
	local connections = {}

	-- Create hover detection
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local mousePos = input.Position
			local isHovering = isPointInFrame(frame, mousePos.X, mousePos.Y)

			-- Handle hover state
			if isHovering and not frame:GetAttribute("isHovering") then
				frame:SetAttribute("isHovering", true)

				-- Play hover animation (expand)
				TweenService:Create(
					frame,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{Size = UDim2.new(
						origSize.X.Scale * 1.1, 
						origSize.X.Offset * 1.1,
						origSize.Y.Scale * 1.1, 
						origSize.Y.Offset * 1.1
						)}
				):Play()
			elseif not isHovering and frame:GetAttribute("isHovering") then
				frame:SetAttribute("isHovering", false)

				-- Play un-hover animation (return to normal)
				TweenService:Create(
					frame,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{Size = origSize}
				):Play()
			end
		end
	end))

	-- Create click detection
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mousePos = input.Position
			if isPointInFrame(frame, mousePos.X, mousePos.Y) then
				-- Execute callback function when clicked
				callback()
			end
		end
	end))

	-- Return function to disconnect all events
	return function()
		for _, connection in ipairs(connections) do
			if connection then
				connection:Disconnect()
			end
		end
	end
end

-- Function to handle kill feed events
local function handleKillFeed(killData)

	local templates = PlayerGui:FindFirstChild("Templates")
	
	if not templates then
		warn("Templates folder not found")
		return
	end
	
	local currentTemplate = templates:FindFirstChild("KillFeedTemplate")
	if not currentTemplate then
		warn("KillFeedTemplate not found")
		return
	end
	
	local killFeedEntry = currentTemplate:Clone()
	-- Store original size
	
	local function findUIGradientInStroke(instance)
		if not instance then return nil end

		for _, child in pairs(instance:GetDescendants()) do
			if child:IsA("UIStroke") then
				local gradient = child:FindFirstChildOfClass("UIGradient")
				if gradient then
					return gradient
				end
			end
		end
		return nil
	end
	
	local uiGradient = findUIGradientInStroke(killFeedEntry)
	local rotationTween = nil
	
	if uiGradient then
		-- Reset to 0 before starting
		uiGradient.Rotation = 0

		-- Create a self-perpetuating rotation system
		local function setupRotation()
			-- Create a new tween
			rotationTween = TweenService:Create(
				uiGradient,
				TweenInfo.new(3, Enum.EasingStyle.Linear),
				{Rotation = 360}
			)

			-- When completed, reset and restart
			rotationTween.Completed:Connect(function()
				if uiGradient and uiGradient.Parent then
					uiGradient.Rotation = 0
					setupRotation() -- Restart the rotation
				end
			end)

			rotationTween:Play()
		end

		-- Start the initial rotation
		setupRotation()

		-- Store the tween on the element itself for reference
		killFeedEntry:SetAttribute("hasRotationTween", true)
	end
	
	task.delay(DISPLAY_DURATION, function()
		-- Cancel any active rotation tween
		if killFeedEntry:GetAttribute("hasRotationTween") and rotationTween then
			rotationTween:Cancel()
		end

		-- Rest of your existing cleanup code...
	end)
	
	
	local originalSize = killFeedEntry.Size

	-- With AnchorPoint already at 0.5, 0.5, we can directly expand without position adjustments
	-- Set initial size to be 10% larger
	local expandedSize = UDim2.new(
		originalSize.X.Scale * 1.1, 
		originalSize.X.Offset * 1.1,
		originalSize.Y.Scale * 1.1, 
		originalSize.Y.Offset * 1.1
	)

	-- Apply the expanded size
	killFeedEntry.Size = expandedSize

	-- Determine position for this entry
	local basePosition = killFeedEntry.Position
	local yOffset = basePosition.Y.Offset

	-- If there are existing entries, position below the last one
	if #activeEntries > 0 then
		-- Find the lowest entry
		local lowestY = basePosition.Y.Offset
		for _, entryData in ipairs(activeEntries) do
			local entry = entryData.instance
			if entry and entry.Parent then
				local entryBottom = entryData.currentY + entry.AbsoluteSize.Y
				if entryBottom > lowestY then
					lowestY = entryBottom + ENTRY_SPACING
				end
			end
		end
		yOffset = lowestY
	end

	-- Collection to store original and target transparencies
	local elements = {}

	-- Function to cache original transparencies
	local function cacheTransparencies(instance)
		local data = {
			instance = instance,
			properties = {}
		}

		-- Store background transparency for all GuiObjects
		if instance:IsA("GuiObject") then
			data.properties.BackgroundTransparency = instance.BackgroundTransparency

			-- Store additional transparencies based on object type
			if instance:IsA("TextLabel") or instance:IsA("TextButton") then
				data.properties.TextTransparency = instance.TextTransparency
			end

			-- ViewportFrame has both BackgroundTransparency and ImageTransparency
			if instance:IsA("ViewportFrame") then
				data.properties.ImageTransparency = instance.ImageTransparency
				data.properties.ImageColor3 = instance.ImageColor3
			end

			-- ImageLabel has ImageTransparency
			if instance:IsA("ImageLabel") then
				data.properties.ImageTransparency = instance.ImageTransparency
			end

			table.insert(elements, data)
		end

		-- Handle UIStroke
		if instance:IsA("UIStroke") then
			data = {
				instance = instance,
				properties = {
					Transparency = instance.Transparency
				}
			}
			table.insert(elements, data)
		end

		-- Handle UIGradient - store the entire NumberSequence
		if instance:IsA("UIGradient") then
			-- Need to create a copy of the keypoints
			local originalKeypoints = {}
			for _, kp in ipairs(instance.Transparency.Keypoints) do
				table.insert(originalKeypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value))
			end

			data = {
				instance = instance,
				properties = {
					TransparencySequence = NumberSequence.new(originalKeypoints)
				}
			}
			table.insert(elements, data)
		end

		-- Process children
		for _, child in pairs(instance:GetChildren()) do
			cacheTransparencies(child)
		end
	end

	-- Cache all original transparencies
	cacheTransparencies(killFeedEntry)

	-- Update kill feed content - using descendant search
	local nameLabel = findDescendant(killFeedEntry, "NameLabel")
	local viewportFrame = findDescendant(killFeedEntry, "ViewportFrame")

	-- Find the Skull image inside ViewportFrame
	local skull = viewportFrame and viewportFrame:FindFirstChild("Skull")
	if skull then
		print('there is a skull')
	end
	-- Store original size of the skull if it exists
	local originalSkullSize
	if skull and skull:IsA("ImageLabel") then
		originalSkullSize = skull.Size

		-- Set initial size 10% larger (like our expansion effect)
		skull.Size = UDim2.new(
			originalSkullSize.X.Scale * 1.1,
			originalSkullSize.X.Offset * 1.1,
			originalSkullSize.Y.Scale * 1.1,
			originalSkullSize.Y.Offset * 1.1
		)

		-- Ensure it's fully transparent initially
		skull.ImageTransparency = 1
	end

	if nameLabel then
		-- Use the message provided by the server that only mentions the victim
		nameLabel.Text = killData.message or (killData.victimName .. " was caught lackin'")
	end

	-- Function to set all elements to fully transparent
	local function setFullyTransparent(element)
		if element.instance:IsA("UIGradient") then
			-- Create a fully transparent NumberSequence with same structure
			local transparentKeypoints = {}
			for _, kp in ipairs(element.properties.TransparencySequence.Keypoints) do
				table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
			end
			element.instance.Transparency = NumberSequence.new(transparentKeypoints)
		else
			-- For regular UI elements, set all transparency properties to 1
			for prop, _ in pairs(element.properties) do
				if string.find(prop, "Transparency") then
					element.instance[prop] = 1
				end
			end
		end
	end

	-- Set all elements to fully transparent initially
	for _, element in ipairs(elements) do
		setFullyTransparent(element)
	end

	-- Add victim model to the ViewportFrame
	if viewportFrame then
		ViewportMethods.CreateKillFeedViewport(viewportFrame, killData.victimName)
	end

	-- Set the position and parent to HUD
	killFeedEntry.Position = UDim2.new(
		basePosition.X.Scale,
		basePosition.X.Offset,
		basePosition.Y.Scale,
		yOffset
	)
	killFeedEntry.Parent = hudFrame

	-- Create entry data
	local entryData = {
		instance = killFeedEntry,
		creationTime = tick(),
		elements = elements,
		originalY = basePosition.Y.Offset,
		currentY = yOffset
	}

	-- Add to active entries
	table.insert(activeEntries, entryData)

	-- Create size animation tween - using Sine Out for a smooth landing effect
	local sizeTween = TweenService:Create(
		killFeedEntry,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{Size = originalSize}
	)

	-- Create tweens for fade-in
	local tweens = {}
	local gradientCancels = {}

	for _, element in ipairs(elements) do
		if element.instance:IsA("UIGradient") then
			-- For UIGradients, use custom tweening function

			-- Create fully transparent sequence
			local transparentKeypoints = {}
			for _, kp in ipairs(element.properties.TransparencySequence.Keypoints) do
				table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
			end
			local startSequence = NumberSequence.new(transparentKeypoints)

			-- Tween the gradient
			local cancel = tweenGradientTransparency(
				element.instance, 
				startSequence,                          -- Start: fully transparent
				element.properties.TransparencySequence, -- End: original transparency
				TWEEN_IN_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			)
			table.insert(gradientCancels, cancel)
		else
			-- For regular UI elements, use TweenService
			local tweenProps = {}

			for prop, value in pairs(element.properties) do
				-- Only tween transparency properties for initial fade-in
				if string.find(prop, "Transparency") then
					tweenProps[prop] = value
				end
			end

			if next(tweenProps) then  -- Only create tween if there are properties to tween
				local tween = TweenService:Create(
					element.instance,
					TweenInfo.new(TWEEN_IN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					tweenProps
				)
				table.insert(tweens, tween)
			end
		end
	end

	-- Play all tweens
	sizeTween:Play()  -- Play the size animation
	for _, tween in ipairs(tweens) do
		tween:Play()
	end

	-- Skull animation - will happen 1 second before the kill feed disappears
	task.delay(4, function()
		if not killFeedEntry.Parent then return end -- Safety check

		-- Animation for skull appearance
		if skull and skull:IsA("ImageLabel") and skull.Parent then
			-- Create tweens for the skull
			local skullTweens = {}

			-- Size tween (expansion to normal)
			table.insert(skullTweens, TweenService:Create(
				skull,
				TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{Size = originalSkullSize}
				))

			-- Transparency tween (invisible to visible)
			table.insert(skullTweens, TweenService:Create(
				skull,
				TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ImageTransparency = 0}
				))

			-- Play skull tweens
			for _, tween in ipairs(skullTweens) do
				tween:Play()
			end

			-- Create tweens for the viewport
			if viewportFrame and viewportFrame:IsA("ViewportFrame") and viewportFrame.Parent then
				-- Tween viewport to semi-transparent red
				TweenService:Create(
					viewportFrame,
					TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						ImageTransparency = 0.5,
						ImageColor3 = Color3.fromRGB(255, 0, 0)
					}
				):Play()
			end
		end
	end)

	-- Remove after display duration
	task.delay(DISPLAY_DURATION, function()
		-- Create fade-out tweens - make everything transparent
		local fadeOutTweens = {}
		local fadeOutGradientCancels = {}

		-- Also move the entry up slightly as it fades out
		local currentPosition = killFeedEntry.Position
		local fadeOutPosition = UDim2.new(
			currentPosition.X.Scale,
			currentPosition.X.Offset,
			currentPosition.Y.Scale, 
			currentPosition.Y.Offset - 20 -- Move up by 20 pixels
		)

		local positionTween = TweenService:Create(
			killFeedEntry,
			TweenInfo.new(TWEEN_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{Position = fadeOutPosition}
		)

		-- Add to fadeout tweens
		table.insert(fadeOutTweens, positionTween)

		for _, element in ipairs(elements) do
			if element.instance:IsA("UIGradient") then
				-- For UIGradients, use custom tweening function

				-- Create fully transparent sequence
				local transparentKeypoints = {}
				for _, kp in ipairs(element.properties.TransparencySequence.Keypoints) do
					table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
				end
				local endSequence = NumberSequence.new(transparentKeypoints)

				-- Tween the gradient
				local cancel = tweenGradientTransparency(
					element.instance, 
					element.properties.TransparencySequence, -- Start: original transparency
					endSequence,                          -- End: fully transparent
					TWEEN_OUT_TIME,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.In
				)
				table.insert(fadeOutGradientCancels, cancel)
			else
				-- For regular UI elements, use TweenService
				local tweenProps = {}

				for prop, _ in pairs(element.properties) do
					if string.find(prop, "Transparency") then
						tweenProps[prop] = 1  -- Set to fully transparent
					end
				end

				if next(tweenProps) then  -- Only create tween if there are properties to tween
					local tween = TweenService:Create(
						element.instance,
						TweenInfo.new(TWEEN_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
						tweenProps
					)
					table.insert(fadeOutTweens, tween)
				end
			end
		end

		-- Remove from active entries list
		for i, entry in ipairs(activeEntries) do
			if entry == entryData then
				table.remove(activeEntries, i)
				break
			end
		end

		-- Play fade-out tweens
		for _, tween in ipairs(fadeOutTweens) do
			tween:Play()
		end

		-- Reposition remaining entries
		repositionEntries()

		-- Remove after fade-out completes
		task.delay(TWEEN_OUT_TIME + 0.1, function()
			-- Cancel any running gradient tweens
			for _, cancel in ipairs(fadeOutGradientCancels) do
				cancel()
			end

			-- Destroy the entry
			killFeedEntry:Destroy()
		end)
	end)
end

-- Move these to a higher scope to be accessible across event handlers
local activeTweens = {}
local buttonCleanupFunctions = {}
local currentDeathScreen = nil
local referenceClone = nil

local function setupKillFeedSystem()
	-- CRITICAL FIX: Only create the connection if it doesn't already exist
	if not killFeedConnection then
		killFeedConnection = remoteEvent.OnClientEvent:Connect(function(eventName, data)
			if eventName == "KillFeed" then
				print("killfeed")
				handleKillFeed(data)
			elseif eventName == "ShowDeathScreen" then
				print('deathscreen')
				-- Find template and HUD
				local templates = Player.PlayerGui.Templates
				local deathScreenTemplate = templates:FindFirstChild("DeathScreen")
				if not deathScreenTemplate then 
					warn("DeathScreen template not found!")
					return 
				end

				local playerGui = Player:WaitForChild("PlayerGui")
				local client = playerGui:WaitForChild("Client")
				local hud = client:WaitForChild("HUD")

				-- Clean up existing death screen
				if currentDeathScreen and currentDeathScreen.Parent then
					-- First disable any existing tweens or effects
					if activeTweens then
						for element, tweenData in pairs(activeTweens) do
							if tweenData and tweenData.stop then
								tweenData.stop()
							end
						end
					end

					-- Clear button connections
					if buttonCleanupFunctions then
						for _, cleanupFn in pairs(buttonCleanupFunctions) do
							if cleanupFn then
								cleanupFn()
							end
						end
					end

					-- Reset camera if it was changed
					local camera = workspace.CurrentCamera
					if camera and camera.CameraType == Enum.CameraType.Scriptable then
						camera.CameraType = Enum.CameraType.Custom
					end

					-- Remove from parent (hide) but don't destroy
					currentDeathScreen.Parent = nil
				end

				-- Clear collections
				activeTweens = {}
				buttonCleanupFunctions = {}

				-- IMPORTANT: Keep a reference copy with original values
				if referenceClone then
					referenceClone:Destroy()
				end
				referenceClone = deathScreenTemplate:Clone()

				-- Create the actual screen to display
				currentDeathScreen = deathScreenTemplate:Clone()

				-- Get references to important elements
				local mainGradient = currentDeathScreen:FindFirstChild("UIGradient")
				local deathHolder = currentDeathScreen:FindFirstChild("DeathHolder")
				local deathSkull = currentDeathScreen:FindFirstChild("DeathSkull")
				local youDied = deathHolder and deathHolder:FindFirstChild("YouDied")
				local youLasted = deathHolder and deathHolder:FindFirstChild("YouLasted")
				local respawnButtonFrame = deathHolder and deathHolder:FindFirstChild("RespawnButtonFrame")
				local reviveButtonFrame = deathHolder and deathHolder:FindFirstChild("ReviveButtonFrame")

				-- Find text labels inside button frames
				local respawnTextLabel = respawnButtonFrame and respawnButtonFrame:FindFirstChild("RespawnTextLabel")
				local reviveTextLabel = reviveButtonFrame and reviveButtonFrame:FindFirstChild("ReviveTextLabel")

				-- Set survival time
				if youLasted then
					youLasted.Text = "you lasted " .. (data.survivalTime or 0) .. " seconds"
				end

				-- Store original position for DeathHolder
				local origHolderPos = nil
				if deathHolder then
					origHolderPos = deathHolder.Position

					-- Set initial lower position
					deathHolder.Position = UDim2.new(
						origHolderPos.X.Scale,
						origHolderPos.X.Offset,
						origHolderPos.Y.Scale,
						origHolderPos.Y.Offset + 50
					)
				end

				-- Store original sizes for hover effects
				local originalSizes = {}
				if respawnButtonFrame then originalSizes[respawnButtonFrame] = respawnButtonFrame.Size end
				if reviveButtonFrame then originalSizes[reviveButtonFrame] = reviveButtonFrame.Size end

				-- Make everything fully transparent initially
				local function makeTransparent(instance)
					if instance:IsA("GuiObject") then
						instance.BackgroundTransparency = 1
					end

					if instance:IsA("TextLabel") or instance:IsA("TextButton") then
						instance.TextTransparency = 1
					end

					if instance:IsA("ImageLabel") then
						instance.ImageTransparency = 1
					end

					if instance:IsA("UIStroke") then
						instance.Transparency = 1
					end

					if instance:IsA("UIGradient") then
						-- Create fully transparent keypoints with same structure
						local transparentKeypoints = {}
						for _, kp in ipairs(instance.Transparency.Keypoints) do
							table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
						end

						if #transparentKeypoints >= 2 then
							pcall(function()
								instance.Transparency = NumberSequence.new(transparentKeypoints)
							end)
						end
					end

					-- Process children
					for _, child in ipairs(instance:GetChildren()) do
						makeTransparent(child)
					end
				end

				-- Make everything transparent except the main gradient
				for _, child in ipairs(currentDeathScreen:GetChildren()) do
					if child ~= mainGradient then
						makeTransparent(child)
					end
				end

				-- Make main gradient transparent separately
				if mainGradient then
					local transparentKeypoints = {}
					for _, kp in ipairs(mainGradient.Transparency.Keypoints) do
						table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
					end

					if #transparentKeypoints >= 2 then
						pcall(function()
							mainGradient.Transparency = NumberSequence.new(transparentKeypoints)
						end)
					end
				end

				-- Now parent the screen to make it visible
				currentDeathScreen.Parent = hud

				-- Make sure data contains the killer's information
				if data.killerUserId then
					-- Delay the camera move by 3 seconds
					task.delay(3, function()
						-- Make sure the death screen is still showing
						if not currentDeathScreen or not currentDeathScreen.Parent then return end

						-- Find the killer by UserId
						local killer = nil
						for _, player in pairs(Players:GetPlayers()) do
							if player.UserId == data.killerUserId then
								killer = player
								break
							end
						end

						-- Make sure the killer is still in the game and has a character
						if killer and killer.Character and killer.Character:FindFirstChild("HumanoidRootPart") then
							local killerRoot = killer.Character.HumanoidRootPart
							local camera = workspace.CurrentCamera

							-- Store original camera properties for reset
							local originalCameraType = camera.CameraType
							local originalCameraSubject = camera.CameraSubject

							-- Switch to scriptable camera immediately
							camera.CameraType = Enum.CameraType.Scriptable

							-- Camera settings
							local cameraHeight = 5       -- Height above the killer
							local cameraDistance = 12    -- Distance from the killer
							local smoothness = 0.08      -- Lower = smoother (range 0.01-0.2)
							local orbitSpeed = 0.1       -- How fast the camera slowly circles

							-- Variables for smooth movement
							local currentCFrame = camera.CFrame
							local startTime = tick()
							local initialTransitionTime = 1.5 -- Time for initial smooth transition

							-- Function to follow the killer with a spectator-style camera
							local followConnection
							followConnection = RunService.RenderStepped:Connect(function()
								-- Safety check for killer existence
								if not killer or not killer.Character or not killer.Character:FindFirstChild("HumanoidRootPart") then
									if followConnection then
										followConnection:Disconnect()
									end
									return
								end

								local root = killer.Character.HumanoidRootPart
								local timePassed = tick() - startTime

								-- Calculate orbit angle - slowly circle around the player
								local orbitAngle = timePassed * orbitSpeed

								-- Create a spectator camera position (circular orbit)
								local offset = Vector3.new(
									math.sin(orbitAngle) * cameraDistance,
									cameraHeight,
									math.cos(orbitAngle) * cameraDistance
								)

								-- Calculate target camera CFrame
								local targetCFrame = CFrame.new(root.Position + offset, root.Position)

								-- Determine interpolation factor based on initial transition
								local lerpFactor = smoothness
								if timePassed < initialTransitionTime then
									-- More aggressive lerping during initial transition (0.01 to smoothness)
									lerpFactor = (timePassed / initialTransitionTime) * smoothness + 0.01
								end

								-- Smoothly interpolate to target position
								currentCFrame = currentCFrame:Lerp(targetCFrame, lerpFactor)
								camera.CFrame = currentCFrame
							end)

							-- Store in activeTweens for cleanup when respawning
							activeTweens["cameraFollow"] = {
								stop = function()
									if followConnection then
										followConnection:Disconnect()
										followConnection = nil
									end
									-- Restore original camera properties
									camera.CameraType = originalCameraType
									camera.CameraSubject = originalCameraSubject
								end
							}
						end
					end)
				end

				-- Function to create floating effect
				local function createSmoothFloatingEffect(element)
					if not element or not element:IsA("GuiObject") then return end

					-- Get original position
					local origPos = element.Position
					local startTime = tick()

					-- Create a continuous floating animation using RenderStepped
					local floatingConn
					floatingConn = RunService.RenderStepped:Connect(function()
						local elapsed = tick() - startTime

						-- Use sine wave for smooth, continuous floating
						-- Amplitude: 4 pixels, Frequency: Complete cycle every 1.5 seconds
						local offset = math.sin(elapsed * (math.pi * 2/1.5)) * 4

						-- Apply the new position
						element.Position = UDim2.new(
							origPos.X.Scale,
							origPos.X.Offset,
							origPos.Y.Scale,
							origPos.Y.Offset + offset
						)
					end)

					-- Store for cleanup
					activeTweens[element] = {
						stop = function()
							if floatingConn then
								floatingConn:Disconnect()
								floatingConn = nil

								-- Reset to original position when stopped
								element.Position = origPos
							end
						end
					}
				end

				-- Start main gradient animation immediately - 5 seconds
				if mainGradient then
					-- Get reference gradient to copy from
					local refGradient = referenceClone:FindFirstChild("UIGradient")
					if refGradient then
						-- Get original keypoints
						local originalKeypoints = {}
						for _, kp in ipairs(refGradient.Transparency.Keypoints) do
							table.insert(originalKeypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value))
						end

						local startTime = tick()
						local duration = 5 -- 5 seconds

						local gradConn
						gradConn = RunService.RenderStepped:Connect(function()
							local elapsed = tick() - startTime
							local alpha = math.clamp(elapsed / duration, 0, 1)
							local easedAlpha = math.sin(alpha * math.pi/2)

							-- Interpolate to original keypoints
							local newKeypoints = {}
							for _, origKp in ipairs(originalKeypoints) do
								local value = (1 - easedAlpha) * 1 + easedAlpha * origKp.Value
								table.insert(newKeypoints, NumberSequenceKeypoint.new(origKp.Time, value))
							end

							if #newKeypoints >= 2 then
								pcall(function()
									mainGradient.Transparency = NumberSequence.new(newKeypoints)
								end)
							end

							if alpha >= 1 and gradConn then
								gradConn:Disconnect()
								gradConn = nil
							end
						end)

						-- Store for cleanup
						activeTweens["mainGradient"] = {
							stop = function()
								if gradConn then
									gradConn:Disconnect()
									gradConn = nil
								end
							end
						}
					end
				end

				-- Function to directly copy properties from reference
				local function copyProperties(source, target)
					if not source or not target then return end

					-- Copy transparency properties based on instance type
					if target:IsA("GuiObject") and source:IsA("GuiObject") then
						target.BackgroundTransparency = source.BackgroundTransparency
					end

					if (target:IsA("TextLabel") or target:IsA("TextButton")) and 
						(source:IsA("TextLabel") or source:IsA("TextButton")) then
						target.TextTransparency = source.TextTransparency
					end

					if target:IsA("ImageLabel") and source:IsA("ImageLabel") then
						target.ImageTransparency = source.ImageTransparency
					end

					if target:IsA("UIStroke") and source:IsA("UIStroke") then
						target.Transparency = source.Transparency
					end

					if target:IsA("UIGradient") and source:IsA("UIGradient") then
						-- Copy gradient keypoints
						local keypoints = {}
						for _, kp in ipairs(source.Transparency.Keypoints) do
							table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value))
						end

						if #keypoints >= 2 then
							pcall(function()
								target.Transparency = NumberSequence.new(keypoints)
							end)
						end
					end
				end

				-- Delay other elements by 3 seconds
				task.delay(3, function()
					if not currentDeathScreen or not currentDeathScreen.Parent then 
						-- Clean up reference if needed
						if referenceClone then referenceClone:Destroy() end
						return 
					end

					-- For DeathHolder, tween position and copy properties
					if deathHolder then
						-- Create position tween
						TweenService:Create(
							deathHolder,
							TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
							{Position = origHolderPos}
						):Play()

						-- Find corresponding reference element
						local refDeathHolder = referenceClone:FindFirstChild("DeathHolder")

						-- For each element in DeathHolder, tween transparencies
						local function tweenElement(target, source)
							-- Create tween props based on source
							local tweenProps = {}

							if target:IsA("GuiObject") and source:IsA("GuiObject") then
								tweenProps.BackgroundTransparency = source.BackgroundTransparency
							end

							if (target:IsA("TextLabel") or target:IsA("TextButton")) and 
								(source:IsA("TextLabel") or source:IsA("TextButton")) then
								tweenProps.TextTransparency = source.TextTransparency
							end

							if target:IsA("ImageLabel") and source:IsA("ImageLabel") then
								tweenProps.ImageTransparency = source.ImageTransparency
							end

							if target:IsA("UIStroke") and source:IsA("UIStroke") then
								tweenProps.Transparency = source.Transparency
							end

							-- Create tween if we have properties to tween
							if next(tweenProps) then
								TweenService:Create(
									target,
									TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
									tweenProps
								):Play()
							end

							-- Handle any nested UIGradients
							if target:IsA("UIGradient") and source:IsA("UIGradient") then
								local gradStartTime = tick()
								local gradDuration = 0.5

								local sourceKeypoints = {}
								for _, kp in ipairs(source.Transparency.Keypoints) do
									table.insert(sourceKeypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value))
								end

								local gradConn
								gradConn = RunService.RenderStepped:Connect(function()
									local elapsed = tick() - gradStartTime
									local alpha = math.clamp(elapsed / gradDuration, 0, 1)
									local easedAlpha = math.sin(alpha * math.pi/2)

									-- Interpolate from 1 to source values
									local newKeypoints = {}
									for _, kp in ipairs(sourceKeypoints) do
										local value = (1 - easedAlpha) * 1 + easedAlpha * kp.Value
										table.insert(newKeypoints, NumberSequenceKeypoint.new(kp.Time, value))
									end

									if #newKeypoints >= 2 then
										pcall(function()
											target.Transparency = NumberSequence.new(newKeypoints)
										end)
									end

									if alpha >= 1 and gradConn then
										gradConn:Disconnect()
										gradConn = nil
									end
								end)

								-- Store for cleanup
								activeTweens[target] = {
									stop = function()
										if gradConn then
											gradConn:Disconnect()
											gradConn = nil
										end
									end
								}
							end

							-- Process children by finding matching source children
							for _, targetChild in ipairs(target:GetChildren()) do
								local sourceName = targetChild.Name
								local sourceChild = source:FindFirstChild(sourceName)

								if sourceChild then
									tweenElement(targetChild, sourceChild)
								end
							end
						end

						-- Start tweening from DeathHolder
						if refDeathHolder then
							tweenElement(deathHolder, refDeathHolder)
						end
					end

					-- Do the same for DeathSkull if needed
					if deathSkull then
						local refDeathSkull = referenceClone:FindFirstChild("DeathSkull")
						if refDeathSkull then
							-- Create tween props
							local tweenProps = {}

							if deathSkull:IsA("ImageLabel") and refDeathSkull:IsA("ImageLabel") then
								tweenProps.ImageTransparency = refDeathSkull.ImageTransparency
							end

							if deathSkull:IsA("GuiObject") and refDeathSkull:IsA("GuiObject") then
								tweenProps.BackgroundTransparency = refDeathSkull.BackgroundTransparency
							end

							-- Create tween
							if next(tweenProps) then
								TweenService:Create(
									deathSkull,
									TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
									tweenProps
								):Play()
							end

							-- Process children
							for _, targetChild in ipairs(deathSkull:GetChildren()) do
								local sourceName = targetChild.Name
								local sourceChild = refDeathSkull:FindFirstChild(sourceName)

								if sourceChild then
									copyProperties(sourceChild, targetChild)
								end
							end
						end
					end

					-- Start floating effects after a short delay when initial animations complete
					task.delay(0.7, function()
						if not currentDeathScreen or not currentDeathScreen.Parent then return end

						-- Apply smooth floating to elements
						if youDied then
							createSmoothFloatingEffect(youDied)
						end

						if youLasted then
							createSmoothFloatingEffect(youLasted)
						end

						if deathSkull then
							createSmoothFloatingEffect(deathSkull)
						end

						-- Function to animate the death screen closing
						local function animateDeathScreenClosing()
							-- Create a fade out animation for the main gradient
							local mainGradient = currentDeathScreen:FindFirstChild("UIGradient")
							if mainGradient then
								local transparentKeypoints = {}
								for _, kp in ipairs(mainGradient.Transparency.Keypoints) do
									table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
								end

								if #transparentKeypoints >= 2 then
									local gradStartTime = tick()
									local gradDuration = 0.5

									local gradConn
									gradConn = RunService.RenderStepped:Connect(function()
										local elapsed = tick() - gradStartTime
										local alpha = math.clamp(elapsed / gradDuration, 0, 1)
										local easedAlpha = math.sin(alpha * math.pi/2)

										-- Create interpolated keypoints
										local newKeypoints = {}
										for i, origKp in ipairs(mainGradient.Transparency.Keypoints) do
											local targetValue = 1 -- Fully transparent
											local value = (1 - easedAlpha) * origKp.Value + easedAlpha * targetValue
											table.insert(newKeypoints, NumberSequenceKeypoint.new(origKp.Time, value))
										end

										if #newKeypoints >= 2 then
											pcall(function()
												mainGradient.Transparency = NumberSequence.new(newKeypoints)
											end)
										end

										if alpha >= 1 and gradConn then
											gradConn:Disconnect()
											gradConn = nil
										end
									end)
								end
							end

							-- Stop any active camera following or other tweens
							for element, tweenData in pairs(activeTweens) do
								if tweenData.stop then
									tweenData.stop()
								end
							end

							-- Fade out all UI elements
							for _, element in ipairs(currentDeathScreen:GetDescendants()) do
								if element:IsA("TextLabel") or element:IsA("TextButton") then
									TweenService:Create(
										element,
										TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
										{TextTransparency = 1}
									):Play()
								elseif element:IsA("ImageLabel") then
									TweenService:Create(
										element,
										TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
										{ImageTransparency = 1}
									):Play()
								elseif element:IsA("Frame") and element ~= currentDeathScreen then
									TweenService:Create(
										element,
										TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
										{BackgroundTransparency = 1}
									):Play()
								end
							end
						end

						-- UPDATED RESPAWN BUTTON FUNCTIONALITY
						if respawnButtonFrame then
							local cleanup = setupFrameButton(respawnButtonFrame, function()
								-- Disable the button immediately to prevent multiple clicks
								if respawnButtonFrame:FindFirstChild("ClickDetector") then
									respawnButtonFrame:FindFirstChild("ClickDetector").Enabled = false
								end

								-- Play transition sound
								local transitionSound = Instance.new("Sound")
								transitionSound.SoundId = "rbxassetid://9119720505" -- Use your actual transition sound ID
								transitionSound.Volume = 0.7
								transitionSound.Parent = PlayerGui
								transitionSound:Play()

								-- Start the closing animation
								animateDeathScreenClosing()

								-- Clean up button connections
								for _, cleanupFn in pairs(buttonCleanupFunctions) do
									cleanupFn()
								end

								-- After animation completes, notify server that UI is closed
								task.delay(0.5, function()
									-- Send transition request AFTER UI is closed
									remoteEvent:FireServer("RequestPropToHunterTransition", {
										wasKilledBy = data.killerUserId,
										uiClosed = true -- Tell server UI is now closed
									})

									-- Remove the death screen from parent (hide it)
									if currentDeathScreen and currentDeathScreen.Parent then
										currentDeathScreen.Parent = nil
										currentDeathScreen = nil
									end

									-- Clean up reference
									if referenceClone then
										referenceClone:Destroy()
										referenceClone = nil
									end

									-- Clean up transition sound
									if transitionSound then
										transitionSound:Destroy()
									end
								end)
							end)

							-- Store cleanup function
							table.insert(buttonCleanupFunctions, cleanup)
						end

						-- Set up revive button frame if needed
						if reviveButtonFrame then
							local cleanup = setupFrameButton(reviveButtonFrame, function()
								-- Your revive functionality here
								remoteEvent:FireServer("RequestRevive", {})

								-- Clean up button connections
								for _, cleanupFn in pairs(buttonCleanupFunctions) do
									cleanupFn()
								end

								-- Hide the death screen
								if currentDeathScreen and currentDeathScreen.Parent then
									currentDeathScreen.Parent = nil
									currentDeathScreen = nil
								end

								-- Clean up reference
								if referenceClone then
									referenceClone:Destroy()
									referenceClone = nil
								end
							end)

							-- Store cleanup function
							table.insert(buttonCleanupFunctions, cleanup)
						end
					end)
				end)

				-- Clean up reference when done (in case respawn isn't clicked)
				task.delay(30, function()
					-- Safety check in case player has already respawned
					if not currentDeathScreen or not currentDeathScreen.Parent then
						return
					end

					if referenceClone then
						referenceClone:Destroy()
						referenceClone = nil
					end

					-- Clean up button connections if they exist
					for _, cleanupFn in pairs(buttonCleanupFunctions) do
						cleanupFn()
					end

					-- Force cleanup death screen if it's still around
					if currentDeathScreen and currentDeathScreen.Parent then
						-- Stop any active tweens
						for element, tweenData in pairs(activeTweens) do
							if tweenData.stop then
								tweenData.stop()
							end
						end

						-- Force respawn after timeout
						print("Timeout reached - forcing respawn")
						remoteEvent:FireServer("RequestRespawn", {})

						-- Hide the death screen
						currentDeathScreen.Parent = nil
						currentDeathScreen = nil
					end
				end)
			elseif eventName == "RoundEnding" then
				-- If player is on death screen, completely clean it up
				if currentDeathScreen and currentDeathScreen.Parent then
					-- CRITICAL: Reset camera FIRST before any animations to prevent it from following into lobby
					local camera = workspace.CurrentCamera
					camera.CameraType = Enum.CameraType.Custom

					-- Stop any active tweens
					for element, tweenData in pairs(activeTweens) do
						if tweenData and tweenData.stop then
							tweenData.stop()
						end
					end
					activeTweens = {}

					-- Clean up button connections
					for _, cleanupFn in pairs(buttonCleanupFunctions) do
						if cleanupFn then
							cleanupFn()
						end
					end
					buttonCleanupFunctions = {}

					-- Hide buttons immediately 
					local deathHolder = currentDeathScreen:FindFirstChild("DeathHolder")
					if deathHolder then
						local respawnButton = deathHolder:FindFirstChild("RespawnButtonFrame")
						if respawnButton then
							respawnButton.Visible = false
						end

						local reviveButton = deathHolder:FindFirstChild("ReviveButtonFrame")
						if reviveButton then
							reviveButton.Visible = false
						end
					end

					-- Fade out the death screen
					local mainGradient = currentDeathScreen:FindFirstChild("UIGradient")
					if mainGradient then
						local transparentKeypoints = {}
						for _, kp in ipairs(mainGradient.Transparency.Keypoints) do
							table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
						end

						if #transparentKeypoints >= 2 then
							pcall(function()
								mainGradient.Transparency = NumberSequence.new(transparentKeypoints)
							end)
						end
					end

					-- Fade out all UI elements quickly
					for _, element in ipairs(currentDeathScreen:GetDescendants()) do
						if element:IsA("TextLabel") or element:IsA("TextButton") then
							element.TextTransparency = 1
						elseif element:IsA("ImageLabel") then
							element.ImageTransparency = 1
						elseif element:IsA("Frame") and element ~= currentDeathScreen then
							element.BackgroundTransparency = 1
						end
					end

					-- Hide the death screen (don't destroy)
					currentDeathScreen.Parent = nil
					currentDeathScreen = nil

					-- Clean up reference
					if referenceClone then
						referenceClone:Destroy()
						referenceClone = nil
					end
				end
			elseif eventName == "ForceCloseDeathScreen" then
				-- Force close the death screen when round ends
				if currentDeathScreen and currentDeathScreen.Parent then
					-- CRITICAL: Reset camera IMMEDIATELY
					local camera = workspace.CurrentCamera
					camera.CameraType = Enum.CameraType.Custom

					-- Stop any active camera following or other tweens
					for element, tweenData in pairs(activeTweens) do
						if tweenData and tweenData.stop then
							tweenData.stop()
						end
					end
					activeTweens = {}

					-- Clean up button connections
					for _, cleanupFn in pairs(buttonCleanupFunctions) do
						if cleanupFn then
							cleanupFn()
						end
					end
					buttonCleanupFunctions = {}

					-- Hide buttons immediately to prevent clicks
					local deathHolder = currentDeathScreen:FindFirstChild("DeathHolder")
					if deathHolder then
						local respawnButton = deathHolder:FindFirstChild("RespawnButtonFrame")
						if respawnButton then
							respawnButton.Visible = false
						end

						local reviveButton = deathHolder:FindFirstChild("ReviveButtonFrame")
						if reviveButton then
							reviveButton.Visible = false
						end
					end

					-- Set all elements to transparent immediately (skip animation for forced close)
					for _, element in ipairs(currentDeathScreen:GetDescendants()) do
						if element:IsA("TextLabel") or element:IsA("TextButton") then
							element.TextTransparency = 1
						elseif element:IsA("ImageLabel") then
							element.ImageTransparency = 1
						elseif element:IsA("Frame") and element ~= currentDeathScreen then
							element.BackgroundTransparency = 1
						end

						if element:IsA("UIGradient") then
							local transparentKeypoints = {}
							for _, kp in ipairs(element.Transparency.Keypoints) do
								table.insert(transparentKeypoints, NumberSequenceKeypoint.new(kp.Time, 1))
							end

							if #transparentKeypoints >= 2 then
								pcall(function()
									element.Transparency = NumberSequence.new(transparentKeypoints)
								end)
							end
						end
					end

					-- Hide death screen without animation (don't destroy)
					currentDeathScreen.Parent = nil
					currentDeathScreen = nil

					-- Clean up reference
					if referenceClone then
						referenceClone:Destroy()
						referenceClone = nil
					end
				end
			end
		end)
	end
end


task.wait(3) -- Wait for other systems to initialize
setupKillFeedSystem()

Player.CharacterAdded:Connect(function(character)
	task.wait(3) -- Increased from 0.5 to give more time after respawn
	setupKillFeedSystem()
end)