-- ProceduralCheckerboard.lua - Optimized Version
-- Place this LocalScript inside your TransitionFrame

local TransitionFrame = script.Parent
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TweenMethods = require(ReplicatedStorage:WaitForChild("TweenMethods"))
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer



-- Configuration
local Config = {
	-- Checkerboard configuration
	checkSize = 120,            -- Size of each checker square in pixels
	scrollSpeed = 100,           -- Pixels per second

	-- THEME COLORS
	loadingLightColor = Color3.fromRGB(255, 144, 144),  -- Original light color for loading
	loadingDarkColor = Color3.fromRGB(220, 83, 83),   -- Original dark color for loading

	hunterLightColor = Color3.fromRGB(96, 165, 250),  -- Light blue (#60A5FA)
	hunterDarkColor = Color3.fromRGB(30, 58, 138),   -- Dark blue (#1E3A8A)

	-- Animation timings
	fadeTime = 0.3,              -- General fade in/out time
	colorTweenTime = 0.15,        -- Time to tween between color schemes
	dotAnimationSpeed = 0.4,     -- Time between dot updates

	-- PVH Animation Configuration
	pvhFrameDuration = 0.25,     -- Time each frame displays (quarter second)
	pvhFrames = {
		"rbxassetid://112550502692214", -- Replace with actual AssetIDs
		"rbxassetid://70944963483580",
		"rbxassetid://118561655382993",
		"rbxassetid://107119674770715"
	},

	-- Minimum display time for transition
	minTransitionTime = 2.5     -- Minimum time the transition must display before hiding
}

-- Active connections tracker
local Connections = {
	scroll = nil,
	loadingText = nil,
	pvhAnimation = nil,
	countdownTimer = nil
}

-- UI Elements references
local Elements = {
	pvhImage = nil,
	loadingText = nil,
	digitOne = nil,
	digitTwo = nil,
	checkerboardContainer = nil,
	panelA = nil,
	panelB = nil,
	backgroundFills = {},
	checkerSquares = {}
}

-- State tracking
local State = {
	isActive = false,
	currentMode = "loading",
	transitionStartTime = 0,
	allowHiding = false,
	currentPVHFrame = 1
}

-- Function to safely disconnect a connection
local function SafeDisconnect(connectionName)
	if Connections[connectionName] then
		Connections[connectionName]:Disconnect()
		Connections[connectionName] = nil
	end
end

-- Helper function to animate digit change (define this early as it's called by other functions)
local function AnimateDigitChange(digitLabel, newValue)
	if not digitLabel then return end

	-- Get current position
	local currentYScale = digitLabel.Position.Y.Scale
	local currentYOffset = digitLabel.Position.Y.Offset

	-- Define positions
	local standardPosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, currentYScale, currentYOffset)
	local belowPosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, currentYScale + 0.1, currentYOffset)
	local abovePosition = UDim2.new(digitLabel.Position.X.Scale, digitLabel.Position.X.Offset, currentYScale - 0.1, currentYOffset)

	-- Clean up old animations
	for _, child in pairs(digitLabel.Parent:GetChildren()) do
		if child.Name == "OldDigit" then
			child:Destroy()
		end
	end

	-- Create clone for old value
	local oldDigit = digitLabel:Clone()
	oldDigit.Name = "OldDigit"
	oldDigit.Position = standardPosition
	oldDigit.Parent = digitLabel.Parent

	-- Set new value
	digitLabel.Text = tostring(newValue)
	digitLabel.Position = belowPosition
	digitLabel.TextTransparency = 0.8

	-- Create tweens
	local oldTween = TweenService:Create(
		oldDigit,
		TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Position = abovePosition,
			TextTransparency = 1
		}
	)

	local newTween = TweenService:Create(
		digitLabel,
		TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Position = standardPosition,
			TextTransparency = 0
		}
	)

	-- Play tweens
	oldTween:Play()
	newTween:Play()

	-- Clean up
	oldTween.Completed:Connect(function()
		if oldDigit and oldDigit.Parent then
			oldDigit:Destroy()
		end
	end)
end

-- SECTION: UI CREATION FUNCTIONS
-- These run once during initialization

-- Create the checker pattern
local function CreateCheckerPattern()
	-- Get the UI elements that already exist in the TransitionFrame
	Elements.pvhImage = TransitionFrame:WaitForChild("pvh")
	Elements.loadingText = TransitionFrame:WaitForChild("LoadingText")
	Elements.digitOne = TransitionFrame:WaitForChild("DigitOne")
	Elements.digitTwo = TransitionFrame:WaitForChild("DigitTwo")

	-- Initialize all elements to be invisible
	Elements.pvhImage.Visible = true
	Elements.pvhImage.ImageTransparency = 1
	Elements.pvhImage.ZIndex = 10

	Elements.loadingText.Visible = true
	Elements.loadingText.TextTransparency = 1
	Elements.loadingText.RichText = true
	Elements.loadingText.ZIndex = 10

	Elements.digitOne.Visible = true
	Elements.digitOne.TextTransparency = 1

	Elements.digitTwo.Visible = true
	Elements.digitTwo.TextTransparency = 1

	-- Create container for the checkerboard
	Elements.checkerboardContainer = Instance.new("Frame")
	Elements.checkerboardContainer.Name = "CheckerboardContainer"
	Elements.checkerboardContainer.BackgroundTransparency = 1
	Elements.checkerboardContainer.Size = UDim2.new(1, 0, 1, 0)
	Elements.checkerboardContainer.ClipsDescendants = true
	Elements.checkerboardContainer.ZIndex = 1
	Elements.checkerboardContainer.Parent = TransitionFrame

	-- IMPORTANT: Replace these AssetIDs with your uploaded image IDs
	-- Upload checkerboard_dark.png and checkerboard_light.png to Roblox
	-- Then paste the AssetIDs here
	local DARK_SQUARES_ASSET = "rbxassetid://88303973260711"
	local LIGHT_SQUARES_ASSET = "rbxassetid://94902360211550"

	-- Create both panels for seamless scrolling
	local panelWidth = 2  -- Double width for infinite scroll

	-- PANEL A
	Elements.panelA = Instance.new("Frame")
	Elements.panelA.Name = "PanelA"
	Elements.panelA.Size = UDim2.new(panelWidth, 0, 1, 0)
	Elements.panelA.Position = UDim2.new(0, 0, 0, 0)
	Elements.panelA.BackgroundTransparency = 1
	Elements.panelA.BorderSizePixel = 0
	Elements.panelA.ZIndex = 1
	Elements.panelA.Parent = Elements.checkerboardContainer

	-- PANEL B
	Elements.panelB = Instance.new("Frame")
	Elements.panelB.Name = "PanelB"
	Elements.panelB.Size = UDim2.new(panelWidth, 0, 1, 0)
	Elements.panelB.Position = UDim2.new(panelWidth, 0, 0, 0)
	Elements.panelB.BackgroundTransparency = 1
	Elements.panelB.BorderSizePixel = 0
	Elements.panelB.ZIndex = 1
	Elements.panelB.Parent = Elements.checkerboardContainer

	-- Track panel positions for scrolling
	Elements.panelA:SetAttribute("PosX", 0)
	Elements.panelB:SetAttribute("PosX", panelWidth)

	-- Create the tiled checker patterns for each panel
	for panelIndex, panel in pairs({Elements.panelA, Elements.panelB}) do
		-- LIGHT SQUARES LAYER (bottom layer)
		local lightLayer = Instance.new("ImageLabel")
		lightLayer.Name = "LightSquares"
		lightLayer.Size = UDim2.new(1, 0, 1, 0)
		lightLayer.Position = UDim2.new(0, 0, 0, 0)
		lightLayer.BackgroundTransparency = 1
		lightLayer.BorderSizePixel = 0
		lightLayer.ZIndex = 1

		-- Tiling configuration
		lightLayer.Image = LIGHT_SQUARES_ASSET
		lightLayer.ScaleType = Enum.ScaleType.Tile
		lightLayer.TileSize = UDim2.new(0, 120, 0, 120)  -- Each square is 120px

		-- Initial color (loading theme)
		lightLayer.ImageColor3 = Config.loadingLightColor
		lightLayer.ImageTransparency = 1  -- Start invisible

		lightLayer.Parent = panel

		-- DARK SQUARES LAYER (top layer)
		local darkLayer = Instance.new("ImageLabel")
		darkLayer.Name = "DarkSquares"
		darkLayer.Size = UDim2.new(1, 0, 1, 0)
		darkLayer.Position = UDim2.new(0, 0, 0, 0)
		darkLayer.BackgroundTransparency = 1
		darkLayer.BorderSizePixel = 0
		darkLayer.ZIndex = 2

		-- Tiling configuration
		darkLayer.Image = DARK_SQUARES_ASSET
		darkLayer.ScaleType = Enum.ScaleType.Tile
		darkLayer.TileSize = UDim2.new(0, 120, 0, 120)

		-- Initial color (loading theme)
		darkLayer.ImageColor3 = Config.loadingDarkColor
		darkLayer.ImageTransparency = 1  -- Start invisible

		darkLayer.Parent = panel

		-- Store references for color tweening
		table.insert(Elements.backgroundFills, lightLayer)
		table.insert(Elements.checkerSquares, darkLayer)
	end

	-- Make transition frame invisible initially
	TransitionFrame.BackgroundTransparency = 1
	TransitionFrame.Visible = false
end

-- SECTION: ANIMATION CONTROL FUNCTIONS

-- Start scrolling the checkerboard
local function StartScrollingCheckerboard()
	-- Disconnect any existing scroll connection
	SafeDisconnect("scroll")

	-- Get the actual screen width for scrolling calculations
	local screenWidth = Elements.checkerboardContainer.AbsoluteSize.X
	local panelWidth = screenWidth * 2  -- Each panel is double width

	-- Create new scroll connection
	Connections.scroll = RunService.RenderStepped:Connect(function(deltaTime)
		-- Update panel positions
		local posA = Elements.panelA:GetAttribute("PosX")
		posA = posA - (Config.scrollSpeed * deltaTime)

		local posB = Elements.panelB:GetAttribute("PosX")
		posB = posB - (Config.scrollSpeed * deltaTime)

		-- Check boundaries for seamless looping
		if posA <= -panelWidth then
			posA = posB + panelWidth
		end

		if posB <= -panelWidth then
			posB = posA + panelWidth
		end

		-- Apply positions
		Elements.panelA.Position = UDim2.new(0, math.floor(posA), 0, 0)
		Elements.panelB.Position = UDim2.new(0, math.floor(posB), 0, 0)

		-- Store positions
		Elements.panelA:SetAttribute("PosX", posA)
		Elements.panelB:SetAttribute("PosX", posB)
	end)
end

-- Stop scrolling the checkerboard
local function StopScrollingCheckerboard()
	SafeDisconnect("scroll")

	-- Reset panel positions to starting locations
	if Elements.panelA and Elements.panelB and Elements.checkerboardContainer then
		-- Get screen width for calculations
		local screenWidth = Elements.checkerboardContainer.AbsoluteSize.X
		local panelWidth = screenWidth * 2

		-- Reset to starting positions
		Elements.panelA.Position = UDim2.new(0, 0, 0, 0)
		Elements.panelB.Position = UDim2.new(0, panelWidth, 0, 0)  -- Start off-screen to the right

		-- Reset position attributes
		Elements.panelA:SetAttribute("PosX", 0)
		Elements.panelB:SetAttribute("PosX", panelWidth)

		print("[TransitionScreen] Checkerboard positions reset")
	end
end

-- Start PVH logo animation
local function StartPVHAnimation()

	-- Disconnect any existing animation
	SafeDisconnect("pvhAnimation")

	-- Reset to first frame
	State.currentPVHFrame = 1
	Elements.pvhImage.Image = Config.pvhFrames[State.currentPVHFrame]

	-- Start animation cycle
	local frameTimer = 0
	Connections.pvhAnimation = RunService.Heartbeat:Connect(function(delta)
		frameTimer = frameTimer + delta

		if frameTimer >= Config.pvhFrameDuration then
			frameTimer = 0
			State.currentPVHFrame = (State.currentPVHFrame % #Config.pvhFrames) + 1
			Elements.pvhImage.Image = Config.pvhFrames[State.currentPVHFrame]
		end
	end)
end

-- Stop PVH logo animation
local function StopPVHAnimation()

	SafeDisconnect("pvhAnimation")
end

-- Start loading text animation
local function StartLoadingTextAnimation(mode)


	-- Disconnect any existing animation
	SafeDisconnect("loadingText")

	-- Set base text based on mode
	local baseText = mode == "hunterWaiting" and "Props are hiding" or "loading"
	local dots = 0
	local timer = 0

	-- Start animation
	Connections.loadingText = RunService.Heartbeat:Connect(function(delta)
		timer = timer + delta

		if timer >= Config.dotAnimationSpeed then
			timer = 0
			dots = (dots + 1) % 4

			-- Create dot animation with rich text
			local dotText = ""
			local colors = {
				"rgb(255,255,255)", -- White
				"rgb(200,200,200)", -- Light gray
				"rgb(150,150,150)"  -- Medium gray
			}

			for i = 1, 3 do
				if i <= dots then
					local colorIndex = math.min(i, #colors)
					dotText = dotText .. string.format('<font color="%s"> .</font>', colors[colorIndex])
				else
					dotText = dotText .. "  "
				end
			end

			-- Update text
			Elements.loadingText.Text = string.format('<font color="rgb(255,255,255)">%s</font>%s', baseText, dotText)
		end
	end)
end

-- Stop loading text animation
local function StopLoadingTextAnimation()

	SafeDisconnect("loadingText")
end

-- Start countdown timer
local function StartCountdownTimer(duration)

	-- Disconnect any existing timer
	SafeDisconnect("countdownTimer")

	-- Initial setup
	local timeRemaining = duration
	local lastTens = math.floor(duration / 10)
	local lastOnes = duration % 10

	-- Set initial digits
	Elements.digitOne.Text = tostring(lastTens)
	Elements.digitTwo.Text = tostring(lastOnes)

	-- Start countdown
	Connections.countdownTimer = RunService.Heartbeat:Connect(function(delta)
		if timeRemaining <= 0 then return end

		timeRemaining = timeRemaining - delta
		local currentSeconds = math.ceil(timeRemaining)

		local newTens = math.floor(currentSeconds / 10)
		local newOnes = currentSeconds % 10

		-- Update digits that changed
		if newTens ~= lastTens then
			AnimateDigitChange(Elements.digitOne, newTens)
			lastTens = newTens
		end

		if newOnes ~= lastOnes then
			AnimateDigitChange(Elements.digitTwo, newOnes)
			lastOnes = newOnes
		end
	end)
end

-- Stop countdown timer
local function StopCountdownTimer()

	SafeDisconnect("countdownTimer")
end

-- SECTION: VISIBILITY CONTROL

-- Show all UI elements
local function FadeInAllElements(mode)
	-- Fade in checkerboard elements (now ImageLabels)
	for _, lightLayer in ipairs(Elements.backgroundFills) do
		TweenMethods.CreateTweenAsync(lightLayer, TweenMethods.ReturnSineData(Config.fadeTime), {
			ImageTransparency = 0  -- Changed from BackgroundTransparency
		})
	end

	for _, darkLayer in ipairs(Elements.checkerSquares) do
		TweenMethods.CreateTweenAsync(darkLayer, TweenMethods.ReturnSineData(Config.fadeTime), {
			ImageTransparency = 0  -- Changed from BackgroundTransparency
		})
	end

	-- Fade in PVH
	TweenMethods.CreateTweenAsync(Elements.pvhImage, TweenMethods.ReturnSineData(Config.fadeTime), {
		ImageTransparency = 0
	})

	-- Fade in loading text
	TweenMethods.CreateTweenAsync(Elements.loadingText, TweenMethods.ReturnSineData(Config.fadeTime), {
		TextTransparency = 0
	})

	-- Only fade in digits for hunter waiting mode
	if mode == "hunterWaiting" then
		TweenMethods.CreateTweenAsync(Elements.digitOne, TweenMethods.ReturnSineData(Config.fadeTime), {
			TextTransparency = 0
		})

		TweenMethods.CreateTweenAsync(Elements.digitTwo, TweenMethods.ReturnSineData(Config.fadeTime), {
			TextTransparency = 0
		})
	else
		-- Hide digits for other modes
		TweenMethods.CreateTweenAsync(Elements.digitOne, TweenMethods.ReturnSineData(Config.fadeTime), {
			TextTransparency = 1
		})

		TweenMethods.CreateTweenAsync(Elements.digitTwo, TweenMethods.ReturnSineData(Config.fadeTime), {
			TextTransparency = 1
		})
	end
end

-- Hide all UI elements
local function FadeOutAllElements()
	-- Fade out checkerboard elements (now ImageLabels)
	for _, lightLayer in ipairs(Elements.backgroundFills) do
		TweenMethods.CreateTweenAsync(lightLayer, TweenMethods.ReturnSineData(Config.fadeTime), {
			ImageTransparency = 1  -- Changed from BackgroundTransparency
		})
	end

	for _, darkLayer in ipairs(Elements.checkerSquares) do
		TweenMethods.CreateTweenAsync(darkLayer, TweenMethods.ReturnSineData(Config.fadeTime), {
			ImageTransparency = 1  -- Changed from BackgroundTransparency
		})
	end

	-- Fade out PVH
	TweenMethods.CreateTweenAsync(Elements.pvhImage, TweenMethods.ReturnSineData(Config.fadeTime), {
		ImageTransparency = 1
	})

	-- Fade out loading text
	TweenMethods.CreateTweenAsync(Elements.loadingText, TweenMethods.ReturnSineData(Config.fadeTime), {
		TextTransparency = 1
	})

	-- Fade out digits
	TweenMethods.CreateTweenAsync(Elements.digitOne, TweenMethods.ReturnSineData(Config.fadeTime), {
		TextTransparency = 1
	})

	TweenMethods.CreateTweenAsync(Elements.digitTwo, TweenMethods.ReturnSineData(Config.fadeTime), {
		TextTransparency = 1
	})
end

-- Update colors based on mode
local function TweenColorsForMode(mode)
	-- Determine target colors
	local lightColor = mode == "hunterWaiting" and Config.hunterLightColor or Config.loadingLightColor
	local darkColor = mode == "hunterWaiting" and Config.hunterDarkColor or Config.loadingDarkColor

	-- Tween light squares (backgroundFills contains light layers)
	for _, lightLayer in ipairs(Elements.backgroundFills) do
		TweenMethods.CreateTweenAsync(lightLayer, TweenMethods.ReturnSineData(Config.colorTweenTime), {
			ImageColor3 = lightColor
		})
	end

	-- Tween dark squares (checkerSquares contains dark layers)
	for _, darkLayer in ipairs(Elements.checkerSquares) do
		TweenMethods.CreateTweenAsync(darkLayer, TweenMethods.ReturnSineData(Config.colorTweenTime), {
			ImageColor3 = darkColor
		})
	end
end

-- SECTION: MAIN CONTROL FUNCTIONS

-- Show transition screen
local function ShowTransitionScreen(mode, duration)


	-- Setup mode
	mode = mode or "loading"
	State.currentMode = mode
	State.isActive = true
	State.allowHiding = false
	State.transitionStartTime = os.time()

	-- Make frame visible
	TransitionFrame.Visible = true

	-- Tween frame background
	TweenMethods.CreateTweenAsync(TransitionFrame, TweenMethods.ReturnSineData(Config.fadeTime), {
		BackgroundTransparency = 0.2
	})

	-- Tween elements to correct colors
	TweenColorsForMode(mode)

	-- Fade in elements
	FadeInAllElements(mode)
	
	local TransitionSound = Instance.new("Sound")
	TransitionSound.Parent = TransitionFrame
	TransitionSound.SoundId = 'rbxassetid://73679547923340'
	TransitionSound:Play()
	TransitionSound.Ended:Connect(function()
		TransitionSound:Destroy()
	end)

	-- Start animations
	StartScrollingCheckerboard()
	StartPVHAnimation()
	StartLoadingTextAnimation(mode)

	-- Start countdown if appropriate
	if mode == "hunterWaiting" and duration then
		StartCountdownTimer(duration)
	end

	-- Set timer for minimum display time
	task.delay(Config.minTransitionTime, function()
		State.allowHiding = true
	end)
end

-- Hide transition screen
local function HideTransitionScreen()


	if not State.isActive then return end

	-- Check minimum display time
	local elapsedTime = os.time() - State.transitionStartTime
	if not State.allowHiding and elapsedTime < Config.minTransitionTime then
		-- Delay hiding

		task.delay(Config.minTransitionTime - elapsedTime, function()
			HideTransitionScreen()
		end)
		return
	end

	State.isActive = false

	-- Stop animations
	StopLoadingTextAnimation()
	StopCountdownTimer()
	StopPVHAnimation()
	StopScrollingCheckerboard()

	-- Fade out elements
	FadeOutAllElements()

	-- Fade out frame
	TweenMethods.CreateTweenAsync(TransitionFrame, TweenMethods.ReturnSineData(Config.fadeTime), {
		BackgroundTransparency = 1
	})

	-- Hide frame after fade completes
	task.delay(Config.fadeTime, function()
		TransitionFrame.Visible = false

	end)
end

-- SECTION: REMOTE EVENT HANDLING
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")


RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "StartTeleportTransition" then

		ShowTransitionScreen("loading")
	elseif eventName == "GracePeriodStarted" then
		local gracePeriodTime = ...


		if LocalPlayer:GetAttribute("Role") == "Hunter" then

			ShowTransitionScreen("hunterWaiting", gracePeriodTime)
		else
			HideTransitionScreen()
		end
	elseif eventName == "HunterFrozen" then
		local gracePeriodTime = ...

		if LocalPlayer:GetAttribute("Role") == "Hunter" then
			ShowTransitionScreen("hunterWaiting", gracePeriodTime)
		else
			print("Player is not Hunter - not showing waiting screen")
		end
	elseif eventName == "HunterUnfrozen" or eventName == "MainRoundStarted" then
		HideTransitionScreen()
	elseif eventName == "RoundEnding" then
		ShowTransitionScreen("loading")
	elseif eventName == "WaitingForPlayers" then
		HideTransitionScreen()
	elseif eventName == "ReturnedToLobby" then
		HideTransitionScreen()
	elseif eventName == "RoleAssigned" then
		local role = ...
	end
end)

-- SECTION: EXPORTED API
local TransitionScreenAPI = {
	Show = function(mode, duration)
		ShowTransitionScreen(mode, duration)
	end,

	Hide = HideTransitionScreen,

	SetScrollSpeed = function(speed)
		Config.scrollSpeed = speed
	end,

	SetCheckSize = function(size)
		-- This would require recreation of the pattern, not implemented
	end,

	SetCheckColors = function(lightColor, darkColor, mode)
		if mode == "loading" or not mode then
			Config.loadingLightColor = lightColor
			Config.loadingDarkColor = darkColor
		elseif mode == "hunterWaiting" then
			Config.hunterLightColor = lightColor
			Config.hunterDarkColor = darkColor
		end
	end,

	SetFadeTime = function(time)
		Config.fadeTime = time
	end,

	SetDotAnimationSpeed = function(speed)
		Config.dotAnimationSpeed = speed
	end,

	SetMinTransitionTime = function(time)
		Config.minTransitionTime = time
	end,

	SetPVHFrames = function(frameAssetIds)
		if type(frameAssetIds) == "table" and #frameAssetIds > 0 then
			Config.pvhFrames = frameAssetIds
		end
	end,

	SetPVHFrameDuration = function(duration)
		Config.pvhFrameDuration = duration
	end
}

-- Initialize by creating all UI elements once
CreateCheckerPattern()

return TransitionScreenAPI