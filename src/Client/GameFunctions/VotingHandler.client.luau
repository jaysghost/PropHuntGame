-- Place this in StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local SoundService = game:GetService("SoundService")

-- Reference to the RemoteEvent
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Import the TweenMethods module
local TweenMethods = require(ReplicatedStorage:WaitForChild("TweenMethods"))

local pendingTimerUpdate = nil

-- Client state
local ClientState = {
	currentVote = nil, -- The option the player has voted for
	voteInfo = {}, -- Information about the vote options
	timerUI = nil, -- Reference to timer UI
	gameMode = "Waiting" -- Current game mode: "Waiting", "Intermission", or "Playing"
}

-- NEW: Storage for ping notification animation
local pingOriginalPosition = nil
local pingOriginalSize = nil
local isShaking = false
local shakingThread = nil

-- Function to initialize ping notification
local function InitializePingNotification()
	-- Find ping notification icon in SubtextHolder
	local clientUI = PlayerGui:WaitForChild("Client", 10)
	if not clientUI then return end

	local HUD = clientUI:WaitForChild("HUD", 10)
	if not HUD then return end

	local subtextHolder = HUD:WaitForChild("SubtextHolder", 10)
	if not subtextHolder then return end

	local pingNotif = subtextHolder:WaitForChild("PingNotif", 5)
	if not pingNotif then return end

	-- Store original properties
	pingOriginalPosition = pingNotif.Position
	pingOriginalSize = pingNotif.Size

	-- Ensure it's initially hidden
	pingNotif.Visible = false
	pingNotif.ImageTransparency = 1

	return pingNotif
end

local rippleElements = {}
local rippleThread = nil

-- Helper function to find subtextHolder and pingNotif
local function findPingNotif()
	local clientUI = PlayerGui:FindFirstChild("Client")
	if not clientUI then return nil end

	local HUD = clientUI:FindFirstChild("HUD")
	if not HUD then return nil end

	local subtextHolder = HUD:FindFirstChild("SubtextHolder")
	if not subtextHolder then return nil end

	return subtextHolder:FindFirstChild("PingNotif")
end

-- Replace your ShowPingNotification function with this
local function ShowPingNotification(secondsUntilPing)
	-- Get reference to ping notification
	local pingNotif = findPingNotif()
	if not pingNotif then return end

	-- Store original properties
	if not pingOriginalSize then
		pingOriginalSize = pingNotif.Size
	end

	-- Make visible but fully transparent
	pingNotif.Visible = true
	pingNotif.ImageTransparency = 1

	-- Tween from transparent to visible
	local fadeInTween = TweenService:Create(
		pingNotif,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ImageTransparency = 0}
	)
	fadeInTween:Play()

	-- Clean up any existing ripples
	if rippleThread then
		task.cancel(rippleThread)
	end

	for _, ripple in pairs(rippleElements) do
		if ripple and ripple.Parent then
			ripple:Destroy()
		end
	end
	rippleElements = {}

	-- Create a container frame for ripples, positioned directly over the PingNotif
	local rippleContainer = Instance.new("Frame")
	rippleContainer.Name = "RippleContainer"
	rippleContainer.BackgroundTransparency = 1 -- Fully transparent
	rippleContainer.Size = UDim2.new(1, 0, 1, 0) -- Same size as PingNotif
	rippleContainer.Position = UDim2.new(0, 0, 0, 0) -- Same position as PingNotif
	rippleContainer.ZIndex = pingNotif.ZIndex + 1 -- Make sure ripples appear above PingNotif
	rippleContainer.Parent = pingNotif

	-- Store for cleanup
	table.insert(rippleElements, rippleContainer)

	-- Start ripple animation thread
	rippleThread = task.spawn(function()
		local startTime = tick()
		local nextRippleTime = startTime

		while tick() - startTime < secondsUntilPing do
			-- Calculate progress
			local progress = (tick() - startTime) / secondsUntilPing

			-- Spawn ripples more frequently as we approach ping time
			local initialInterval = 1.0 -- 1 second between ripples at start
			local finalInterval = 0.3 -- 0.3 seconds between ripples at end
			local currentInterval = initialInterval - (initialInterval - finalInterval) * progress

			-- Check if it's time for a new ripple
			if tick() >= nextRippleTime then
				-- Create ripple circle
				local ripple = Instance.new("Frame")
				ripple.BackgroundTransparency = 0.7
				ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				ripple.BorderSizePixel = 0
				ripple.AnchorPoint = Vector2.new(0.5, 0.5)
				ripple.ZIndex = rippleContainer.ZIndex

				-- Make it circular
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = ripple

				-- Position at center of container
				ripple.Position = UDim2.new(0.5, 0, 0.5, 0)

				-- Start small
				ripple.Size = UDim2.new(0.1, 0, 0.1, 0)

				-- Add to ripple container
				ripple.Parent = rippleContainer
				table.insert(rippleElements, ripple)

				-- Calculate max size based on progress
				local maxSizeScale = 1.5 + progress -- Gets larger as time passes

				-- Animate ripple expansion
				TweenService:Create(
					ripple,
					TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						Size = UDim2.new(maxSizeScale, 0, maxSizeScale, 0),
						BackgroundTransparency = 1
					}
				):Play()

				-- Remove from tracking after animation
				task.delay(1.0, function()
					if ripple and ripple.Parent then
						-- Find in table
						for i, element in pairs(rippleElements) do
							if element == ripple then
								table.remove(rippleElements, i)
								break
							end
						end

						ripple:Destroy()
					end
				end)

				-- Schedule next ripple
				nextRippleTime = tick() + currentInterval
			end

			task.wait(0.03)
		end
	end)
end

-- Replace your ExecutePingEffect function with this
local function ExecutePingEffect()
	-- Get reference to ping notification
	local pingNotif = findPingNotif()
	if not pingNotif then return end

	-- Cancel ripple thread
	if rippleThread then
		task.cancel(rippleThread)
		rippleThread = nil
	end

	-- Get reference to ripple container
	local rippleContainer = nil
	for _, element in pairs(rippleElements) do
		if element and element.Parent and element.Name == "RippleContainer" then
			rippleContainer = element
			break
		end
	end

	-- Create ripple container if it doesn't exist
	if not rippleContainer then
		rippleContainer = Instance.new("Frame")
		rippleContainer.Name = "RippleContainer"
		rippleContainer.BackgroundTransparency = 1
		rippleContainer.Size = UDim2.new(1, 0, 1, 0)
		rippleContainer.Position = UDim2.new(0, 0, 0, 0)
		rippleContainer.ZIndex = pingNotif.ZIndex + 1
		rippleContainer.Parent = pingNotif
		table.insert(rippleElements, rippleContainer)
	end

	-- Clean up existing ripples
	for _, ripple in pairs(rippleElements) do
		if ripple and ripple.Parent and ripple ~= rippleContainer then
			ripple:Destroy()
		end
	end
	rippleElements = {rippleContainer} -- Keep only the container

	-- Play ping sound
	local pingSound = Instance.new("Sound")
	pingSound.SoundId = "rbxassetid://81286199430297"
	pingSound.Volume = 1
	pingSound.Parent = PlayerGui
	pingSound:Play()

	-- Clean up sound when done
	pingSound.Ended:Connect(function()
		pingSound:Destroy()
	end)

	-- Create final burst ripples
	-- Create 3 staggered ripples for final effect
	for i = 1, 3 do
		local finalRipple = Instance.new("Frame")
		finalRipple.BackgroundTransparency = 0.5
		finalRipple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		finalRipple.BorderSizePixel = 0
		finalRipple.AnchorPoint = Vector2.new(0.5, 0.5)
		finalRipple.Position = UDim2.new(0.5, 0, 0.5, 0)
		finalRipple.Size = UDim2.new(0.1, 0, 0.1, 0)
		finalRipple.ZIndex = rippleContainer.ZIndex

		-- Make circular
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = finalRipple

		finalRipple.Parent = rippleContainer
		table.insert(rippleElements, finalRipple)

		-- Stagger animations slightly
		task.delay(i * 0.05, function()
			-- Expand and fade out
			TweenService:Create(
				finalRipple,
				TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Size = UDim2.new(2.5, 0, 2.5, 0),
					BackgroundTransparency = 1
				}
			):Play()

			-- Clean up after animation
			task.delay(0.8, function()
				if finalRipple and finalRipple.Parent then
					finalRipple:Destroy()
				end
			end)
		end)
	end

	-- Create size expansion animation for the icon
	local expandTween = TweenService:Create(
		pingNotif,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = UDim2.new(
			pingOriginalSize.X.Scale * 1.2,
			pingOriginalSize.X.Offset * 1.2,
			pingOriginalSize.Y.Scale * 1.2,
			pingOriginalSize.Y.Offset * 1.2
			)}
	)

	-- Return to original size
	local shrinkTween = TweenService:Create(
		pingNotif,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = pingOriginalSize}
	)

	-- Fade out
	local fadeTween = TweenService:Create(
		pingNotif,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ImageTransparency = 1}
	)

	-- Sequence the animations
	expandTween:Play()
	expandTween.Completed:Connect(function()
		shrinkTween:Play()
		fadeTween:Play()

		fadeTween.Completed:Connect(function()
			pingNotif.Visible = false
		end)
	end)

	-- Clean up ripples after final effect
	task.delay(1.0, function()
		for _, ripple in pairs(rippleElements) do
			if ripple and ripple.Parent then
				ripple:Destroy()
			end
		end
		rippleElements = {}
	end)
end

local function CleanupPingEffects()
	print("[VotingHandler] Cleaning up ping effects")

	-- Cancel ripple thread FIRST
	if rippleThread then
		task.cancel(rippleThread)
		rippleThread = nil
		print("[VotingHandler] Cancelled ripple thread")
	end

	-- Remove ALL ripple elements
	for _, ripple in pairs(rippleElements) do
		if ripple and ripple.Parent then
			ripple:Destroy()
		end
	end
	rippleElements = {}

	-- Get reference to ping notification
	local pingNotif = findPingNotif()
	if not pingNotif then 
		print("[VotingHandler] No ping notif found during cleanup")
		return 
	end

	-- IMMEDIATELY hide and make transparent (no fade animation)
	pingNotif.Visible = false
	pingNotif.ImageTransparency = 1

	-- Reset size and position to original
	if pingOriginalSize then
		pingNotif.Size = pingOriginalSize
	end

	if pingOriginalPosition then
		pingNotif.Position = pingOriginalPosition
	end

	print("[VotingHandler] Ping notification fully cleaned up")
end

-- Function to initialize prop counter label
local function InitializePropCounter()
	-- Find prop counter label in SubtextHolder
	local clientUI = PlayerGui:WaitForChild("Client", 10)
	if not clientUI then return end

	local HUD = clientUI:WaitForChild("HUD", 10)
	if not HUD then return end

	local subtextHolder = HUD:WaitForChild("SubtextHolder", 10)
	if not subtextHolder then return end

	local propCounter = subtextHolder:WaitForChild("DescriptionLabel", 5)
	if not propCounter then return end

	-- Ensure it's initially hidden
	propCounter.Visible = false

	return propCounter
end

-- Function to update prop count with animation
local function UpdatePropCount(count)
	local propCounter = InitializePropCounter()
	if not propCounter then return end

	-- If not visible yet, set up fade-in animation
	if not propCounter.Visible then
		propCounter.Visible = true
		propCounter.TextTransparency = 1
		propCounter.Text = count .. " props left"

		-- Tween from transparent to visible
		TweenService:Create(
			propCounter,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{TextTransparency = 0}
		):Play()
	else
		-- If already visible, create a nice transition effect
		-- Store current text
		local oldText = propCounter.Text

		-- Create a temporary label for the animation
		local tempLabel = propCounter:Clone()
		tempLabel.Name = "TempPropCounter"
		tempLabel.Position = propCounter.Position
		tempLabel.TextTransparency = 0
		tempLabel.Parent = propCounter.Parent

		-- Set new text on the main counter but make it transparent
		propCounter.Text = count .. " props left"
		propCounter.TextTransparency = 1

		-- Animate the old text up and fade out
		TweenService:Create(
			tempLabel,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					tempLabel.Position.X.Scale,
					tempLabel.Position.X.Offset,
					tempLabel.Position.Y.Scale - 0.05,
					tempLabel.Position.Y.Offset
				),
				TextTransparency = 1
			}
		):Play()

		-- Animate the new text from below and fade in
		propCounter.Position = UDim2.new(
			propCounter.Position.X.Scale,
			propCounter.Position.X.Offset,
			propCounter.Position.Y.Scale + 0.05,
			propCounter.Position.Y.Offset
		)

		-- Tween to the original position and fade in
		TweenService:Create(
			propCounter,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					propCounter.Position.X.Scale,
					propCounter.Position.X.Offset,
					propCounter.Position.Y.Scale - 0.05,
					propCounter.Position.Y.Offset
				),
				TextTransparency = 0
			}
		):Play()

		-- Clean up temporary label after animation
		task.delay(0.35, function()
			if tempLabel and tempLabel.Parent then
				tempLabel:Destroy()
			end
		end)
	end
end

-- Function to hide prop counter
local function HidePropCounter()
	local propCounter = InitializePropCounter()
	if not propCounter then return end

	-- Only animate if currently visible
	if propCounter.Visible then
		-- Fade out animation
		local fadeOutTween = TweenService:Create(
			propCounter,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{TextTransparency = 1}
		)

		fadeOutTween:Play()

		-- Hide after animation completes
		fadeOutTween.Completed:Connect(function()
			propCounter.Visible = false
		end)
	end
end

local function GetNotificationHolder()
	local clientUI = PlayerGui:FindFirstChild("Client")
	if not clientUI then 
		warn("Client UI not found")
		return nil 
	end

	local HUD = clientUI:FindFirstChild("HUD")
	if not HUD then 
		warn("HUD not found")
		return nil 
	end

	local notificationHolder = HUD:FindFirstChild("NotificationHolder")
	if not notificationHolder then 
		warn("NotificationHolder not found")
		return nil 
	end

	return notificationHolder
end

local function HideGracePeriodNotification()
	local notificationHolder = GetNotificationHolder()
	if not notificationHolder or not notificationHolder.Visible then return end

	for _, element in pairs(notificationHolder:GetDescendants()) do
		if element:IsA("TextLabel") then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{TextTransparency = 1})
		elseif element:IsA("ImageLabel") then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{ImageTransparency = 1})
		elseif element:IsA("Frame") and element ~= notificationHolder then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{BackgroundTransparency = 1})
		end

		if element:IsA("UIGradient") then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{Transparency = NumberSequence.new(1)})
		end
	end

	-- Hide after animation
	task.delay(0.5, function()
		if notificationHolder then
			notificationHolder.Visible = false
		end
	end)
end

-- Function to show the Grace Period notification with sound
local function ShowGracePeriodNotification()
	local notificationHolder = GetNotificationHolder()
	if not notificationHolder then
		-- Retry once after a short delay
		task.delay(0.5, function()
			notificationHolder = GetNotificationHolder()
			if notificationHolder then
				ShowGracePeriodNotification()
			else
				warn("NotificationHolder not found after retry")
			end
		end)
		return
	end

	notificationHolder.Visible = false

	-- Play notification sound
	local notificationSound = Instance.new("Sound")
	notificationSound.SoundId = "rbxassetid://81286199430297"
	notificationSound.Volume = 1
	notificationSound.Parent = notificationHolder
	notificationSound:Play()

	notificationSound.Ended:Connect(function()
		notificationSound:Destroy()
	end)

	-- Store original position
	local originalPosition = notificationHolder.Position

	-- Set initial position (slightly lower)
	notificationHolder.Position = originalPosition - UDim2.new(0, 0, 0.1, 0)

	-- DIRECT ACCESS to specific UI elements
	local glow = notificationHolder:FindFirstChild("glow")
	local icon = notificationHolder:FindFirstChild("Icon")
	local stripes = notificationHolder:FindFirstChild("Stripes")
	local titleLabel = notificationHolder:FindFirstChild("TitleLabel")
	local descriptionLabel = notificationHolder:FindFirstChild("DescriptionLabel")

	-- Set initial transparency for specific elements
	if glow then glow.ImageTransparency = 1 end
	if icon then icon.ImageTransparency = 1 end
	if stripes then 
		stripes.ImageTransparency = 1
		-- Handle UIGradient inside stripes
		local gradient = stripes:FindFirstChild("UIGradient")
		if gradient then
			gradient.Transparency = NumberSequence.new(1)
		end
	end
	if titleLabel then titleLabel.TextTransparency = 1 end
	if descriptionLabel then descriptionLabel.TextTransparency = 1 end

	-- Also loop through all other descendants for any elements we missed
	for _, element in pairs(notificationHolder:GetDescendants()) do
		if element:IsA("TextLabel") then
			element.TextTransparency = 1
		elseif element:IsA("ImageLabel") and element ~= glow and element ~= icon and element ~= stripes then
			element.ImageTransparency = 1
		elseif element:IsA("Frame") and element ~= notificationHolder then
			element.BackgroundTransparency = 1
		end
	end

	-- NOW make it visible after all properties are set
	notificationHolder.Visible = true

	-- Create tweens using TweenMethods
	TweenMethods.CreateTweenAsync(notificationHolder, 
		TweenMethods.ReturnSineData(0.5), 
		{Position = originalPosition})

	-- EXPLICIT tweens for specific elements
	if glow then 
		TweenMethods.CreateTweenAsync(glow, 
			TweenMethods.ReturnSineData(0.5), 
			{ImageTransparency = 0.3}) -- Adjust value as needed
	end

	if icon then 
		TweenMethods.CreateTweenAsync(icon, 
			TweenMethods.ReturnSineData(0.5), 
			{ImageTransparency = 0})
	end

	if stripes then 
		TweenMethods.CreateTweenAsync(stripes, 
			TweenMethods.ReturnSineData(0.5), 
			{ImageTransparency = 0})

		-- Handle UIGradient
		local gradient = stripes:FindFirstChild("UIGradient")
		if gradient then
			TweenMethods.CreateTweenAsync(gradient, 
				TweenMethods.ReturnSineData(0.5), 
				{Transparency = NumberSequence.new(0.2)})
		end
	end

	if titleLabel then 
		TweenMethods.CreateTweenAsync(titleLabel, 
			TweenMethods.ReturnSineData(0.5), 
			{TextTransparency = 0})
	end

	if descriptionLabel then 
		TweenMethods.CreateTweenAsync(descriptionLabel, 
			TweenMethods.ReturnSineData(0.5), 
			{TextTransparency = 0})
	end

	-- Also tween any elements we might have missed
	for _, element in pairs(notificationHolder:GetDescendants()) do
		if element:IsA("TextLabel") and element ~= titleLabel and element ~= descriptionLabel then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{TextTransparency = 0})
		elseif element:IsA("ImageLabel") and element ~= glow and element ~= icon and element ~= stripes then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{ImageTransparency = 0})
		elseif element:IsA("Frame") and element ~= notificationHolder then
			TweenMethods.CreateTweenAsync(element, 
				TweenMethods.ReturnSineData(0.5), 
				{BackgroundTransparency = 0.2})
		end
	end
end

-- Find and setup UI references with more reliable waiting
local function SetupUI()
	-- Get correct path: PlayerGui -> Client -> HUD
	local clientUI = PlayerGui:WaitForChild("Client", 10)
	if not clientUI then 
		warn("Client UI not found")
		return nil
	end

	local HUD = clientUI:WaitForChild("HUD", 10)
	if not HUD then 
		warn("HUD not found")
		return nil
	end

	-- Get timer reference
	local timer = HUD:WaitForChild("Timer", 10)
	if not timer then 
		warn("Timer not found")
		return nil
	end

	-- Use WaitForChild to ensure elements exist
	local firstDigit = timer:WaitForChild("FirstDigit", 5)
	local colon = timer:WaitForChild("Colon", 5)
	local secondDigit = timer:WaitForChild("SecondDigit", 5)
	local thirdDigit = timer:WaitForChild("ThirdDigit", 5)

	if not firstDigit or not colon or not secondDigit or not thirdDigit then
		warn("Some timer components are missing")
		return nil
	end

	local result = {
		firstDigit = firstDigit,
		colon = colon,
		secondDigit = secondDigit,
		thirdDigit = thirdDigit,
		timerFrame = timer
	}

	return result
end

-- Function to animate a digit changing with the rolling effect
local function AnimateDigitChange(digitLabel, newValue)
	if not digitLabel then 
		warn("Cannot animate nil digit label")
		return 
	end

	-- Define standard positions with absolute coordinates
	local standardPosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, 0.5, 0)
	local belowPosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, 0.8, 0)
	local abovePosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, 0.2, 0)

	-- Remove any previous animation artifacts that might be lingering
	for _, child in pairs(digitLabel.Parent:GetChildren()) do
		if child.Name == "OldDigit" then
			child:Destroy()
		end
	end

	-- Create a copy of the current digit that will animate up and fade out
	local oldDigit = digitLabel:Clone()
	oldDigit.Name = "OldDigit"
	oldDigit.Position = standardPosition  -- Start from standard position
	oldDigit.Parent = digitLabel.Parent

	-- Set the current digit label to the new value and position it below
	digitLabel.Text = tostring(newValue)
	digitLabel.Position = belowPosition  -- Always start from below
	digitLabel.TextTransparency = 0.8

	-- Create a tween for the old digit to move up and fade out
	local oldTween = TweenService:Create(
		oldDigit,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Position = abovePosition,
			TextTransparency = 1
		}
	)

	-- Create a tween for the new digit to move to standard position and fade in
	local newTween = TweenService:Create(
		digitLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Position = standardPosition,
			TextTransparency = 0
		}
	)

	-- Play both tweens
	oldTween:Play()
	newTween:Play()

	-- Clean up after animation completes
	oldTween.Completed:Connect(function()
		oldDigit:Destroy()
	end)
end

-- Function to update timer display with new animation effects
local function UpdateTimerDisplay(seconds)
	-- Verify we have timer UI before proceeding
	if not ClientState.timerUI or 
		not ClientState.timerUI.firstDigit or 
		not ClientState.timerUI.secondDigit or 
		not ClientState.timerUI.thirdDigit then

		-- Try to set up UI again
		ClientState.timerUI = SetupUI()

		-- If still not ready, schedule a delayed retry
		if not ClientState.timerUI or 
			not ClientState.timerUI.firstDigit or 
			not ClientState.timerUI.secondDigit or 
			not ClientState.timerUI.thirdDigit then

			warn("Timer UI still not ready, scheduling delayed retry")

			-- Store this time value for delayed retry
			task.delay(0.5, function()
				UpdateTimerDisplay(seconds)
			end)
			return
		end
	end

	-- Make timer visible
	if ClientState.timerUI.timerFrame then
		ClientState.timerUI.timerFrame.Visible = true
	end

	-- Ensure seconds is not negative
	seconds = math.max(0, seconds)

	-- Calculate minutes and seconds
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60

	-- Format as separate digits
	local firstDigit = tostring(minutes)
	local secondDigit = math.floor(remainingSeconds / 10)
	local thirdDigit = remainingSeconds % 10

	-- Check if digits have changed before animating
	local hasMinuteChanged = (ClientState.timerUI.firstDigit.Text ~= firstDigit)
	local hasSecondDigitChanged = (ClientState.timerUI.secondDigit.Text ~= tostring(secondDigit))
	local hasThirdDigitChanged = (ClientState.timerUI.thirdDigit.Text ~= tostring(thirdDigit))

	-- Update minutes with animation if changed
	if hasMinuteChanged then
		AnimateDigitChange(ClientState.timerUI.firstDigit, firstDigit)
	end

	-- Update second digit (tens place of seconds) with animation if changed
	if hasSecondDigitChanged then
		AnimateDigitChange(ClientState.timerUI.secondDigit, secondDigit)
	end

	-- Update third digit (ones place of seconds) with animation if changed
	if hasThirdDigitChanged then
		AnimateDigitChange(ClientState.timerUI.thirdDigit, thirdDigit)
	end

	-- Ensure colon is visible
	if ClientState.timerUI.colon then
		ClientState.timerUI.colon.Visible = true
	end
end

-- Animate vote counter
local function AnimateVoteCounter(voteIndex, oldValue, newValue)
	-- Map numeric index to correct name format
	local voteNames = {
		[1] = "VoteOne",
		[2] = "VoteTwo",
		[3] = "VoteThree"
	}

	-- Get the correct vote part name
	local voteName = voteNames[voteIndex]
	if not voteName then 
		return 
	end

	-- Find the vote part using the correct name
	local votePart = workspace:FindFirstChild(voteName)
	if not votePart then 
		return 
	end

	-- Rest of your animation code...
	local TouchPart = votePart.TouchPart
	if not TouchPart then return end

	local voteAmount = TouchPart:FindFirstChild("VoteAmount")
	if not voteAmount then return end

	local voteAmountFrame = voteAmount:FindFirstChild("VoteAmountFrame")
	if not voteAmountFrame then return end

	local voteAmountLabel = voteAmountFrame:FindFirstChild("VoteAmountLabel")
	if not voteAmountLabel then return end

	-- Save original properties
	local originalPosition = voteAmountLabel.Position
	local originalSize = voteAmountLabel.Size
	local originalTransparency = voteAmountLabel.TextTransparency

	-- Create a copy of the label for the animation
	local flyingLabel = voteAmountLabel:Clone()
	flyingLabel.Name = "FlyingLabel"
	flyingLabel.Text = tostring(oldValue)
	flyingLabel.Parent = voteAmountFrame

	-- Temporarily hide the original label
	voteAmountLabel.TextTransparency = 1

	-- Create another label for the new value
	local newLabel = voteAmountLabel:Clone()
	newLabel.Name = "NewLabel"
	newLabel.Text = tostring(newValue)
	newLabel.Position = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset, 
		originalPosition.Y.Scale + 0.5, originalPosition.Y.Offset)
	newLabel.TextTransparency = 1
	newLabel.Parent = voteAmountFrame

	-- Animate the flying label upward and fade out
	TweenMethods.CreateTweenAsync(
		flyingLabel, 
		TweenMethods.TwoFiveQuadData, 
		{
			Position = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset, 
				originalPosition.Y.Scale - 0.5, originalPosition.Y.Offset),
			TextTransparency = 1
		}
	)

	-- Animate the new label upward and fade in
	TweenMethods.CreateTweenAsync(
		newLabel, 
		TweenMethods.TwoFiveQuadData, 
		{
			Position = originalPosition,
			TextTransparency = 0
		}
	)

	-- Clean up after animations (after 0.3 seconds)
	task.delay(0.3, function()
		flyingLabel:Destroy()
		voteAmountLabel.Text = tostring(newValue)
		voteAmountLabel.TextTransparency = 0
		newLabel:Destroy()
	end)
end

-- Initialize UI references
task.spawn(function()
	ClientState.timerUI = SetupUI()

	-- Initialize ping notification and prop counter
	InitializePingNotification()
	InitializePropCounter()
end)

-- Handle RemoteEvent messages
RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "StartIntermission" then
		local mapInfo, time = ...

		-- Update game mode
		ClientState.gameMode = "Intermission"

		-- Store map info for later use
		ClientState.voteInfo = mapInfo

		-- Reset player's vote
		ClientState.currentVote = nil

		-- Apply any pending timer update or use the initial time
		if pendingTimerUpdate then
			UpdateTimerDisplay(pendingTimerUpdate)
			pendingTimerUpdate = nil
		else
			-- Use the initial time if no pending update
			UpdateTimerDisplay(time)
		end

	elseif eventName == "UpdateTimer" then
		local seconds = ...

		-- Force intermission mode if we're getting timer updates during the first game
		if ClientState.gameMode == "Waiting" then
			ClientState.gameMode = "Intermission"
		end

		-- Only update if we're in intermission mode (which we should be now)
		if ClientState.gameMode == "Intermission" then
			UpdateTimerDisplay(seconds)
		end

	elseif eventName == "UpdateRoundTimer" then
		local seconds = ...

		-- Only update if we're in playing mode
		if ClientState.gameMode == "Playing" then
			UpdateTimerDisplay(seconds)
		end

	elseif eventName == "GracePeriodStarted" then
		local gracePeriodTime = ...

		-- Update game mode to grace period
		ClientState.gameMode = "GracePeriod"

		-- Update timer display
		UpdateTimerDisplay(gracePeriodTime)

		-- Check player role before showing notification
		if LocalPlayer:GetAttribute("Role") == "Prop" then
			-- Show notification with sound effect
			ShowGracePeriodNotification()
		end

	elseif eventName == "UpdateGracePeriodTimer" then
		local seconds = ...

		-- Only update if we're in grace period mode
		if ClientState.gameMode == "GracePeriod" then
			UpdateTimerDisplay(seconds)
		end

	elseif eventName == "MainRoundStarted" then
		local roundTime = ...

		-- Update game mode
		ClientState.gameMode = "Playing"

		-- Hide notification if it's showing
		HideGracePeriodNotification()

		-- Update timer display
		UpdateTimerDisplay(roundTime)

	elseif eventName == "UpdateVotes" then
		local votes = ...

		-- Simply print the current vote count
		print("Vote Counts Updated: Vote1=" .. votes[1] .. ", Vote2=" .. votes[2] .. ", Vote3=" .. votes[3])

	elseif eventName == "AnimateVoteCounter" then
		local voteIndex, oldValue, newValue = ...

		-- Animate the vote counter
		AnimateVoteCounter(voteIndex, oldValue, newValue)

	elseif eventName == "PlayerVoted" then
		local voteIndex = ...

		-- Just update the client state to reflect player's vote
		ClientState.currentVote = voteIndex

	elseif eventName == "MapSelected" then
		local mapKey, mapName = ...

		-- Just print the selected map to output
		print("Map Selected: " .. mapName .. " (Key: " .. mapKey .. ")")

	elseif eventName == "StartGame" then
		-- Update game mode
		ClientState.gameMode = "Playing"

		-- Reset state
		ClientState.currentVote = nil
		ClientState.voteInfo = {}

	elseif eventName == "UpdatePropCount" then
		-- Update prop counter with animation
		local count = ...
		UpdatePropCount(count)

	elseif eventName == "PingNotification" then
		-- Start ping notification with shake effect
		local secondsUntilPing = ...
		ShowPingNotification(secondsUntilPing)

	elseif eventName == "PingExecute" then
		-- Execute ping effect (sound, animation, etc.)
		ExecutePingEffect()

	elseif eventName == "RoundEnding" then
		-- Update game mode
		ClientState.gameMode = "Waiting"

		-- Hide the timer
		if ClientState.timerUI and ClientState.timerUI.timerFrame then
			ClientState.timerUI.timerFrame.Visible = false
		end

		-- Hide prop counter and ping notification
		HidePropCounter()
		CleanupPingEffects()

		print("Round ended, returning to lobby")

	elseif eventName == "WaitingForPlayers" then
		-- Update game mode
		ClientState.gameMode = "Waiting"

		-- Hide the timer
		if ClientState.timerUI and ClientState.timerUI.timerFrame then
			ClientState.timerUI.timerFrame.Visible = false
		end

		-- Hide prop counter and ping notification
		HidePropCounter()
		CleanupPingEffects()

		print("Waiting for more players to join...")

	elseif eventName == "RoundAnnouncement" then
		local message = ...
		print("ANNOUNCEMENT: " .. message)
		-- You can add UI for announcements here

	elseif eventName == "RoleAssigned" then
		local role = ...
		-- Store player's role as an attribute for easier access
		LocalPlayer:SetAttribute("Role", role)
		print("Assigned role:", role)
	end
end)