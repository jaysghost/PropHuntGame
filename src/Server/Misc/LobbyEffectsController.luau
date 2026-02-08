-- LobbyEffectsController.lua
-- Module to handle lighting and sound effects for lobby elements
-- Place this in ServerScriptService or inside the same folder as VotingSystem

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration for effects
local LobbyEffectsController = {
	-- References
	lightsByVotePanel = {}, -- Will store {[1] = {lights for VoteOne}, [2] = {...}, [3] = {...}}
	cleanupConnections = {},
	soundsFolder = nil,

	-- Lighting effect settings
	idleColor = Color3.fromRGB(0, 170, 255),   -- Blue
	voteColor = Color3.fromRGB(255, 215, 0),   -- Gold
	winningColor = Color3.fromRGB(0, 255, 100), -- Green
	highlightColor = Color3.fromRGB(255, 0, 255), -- Pink

	-- Chase pattern settings
	chaseSpeed = 0.2,        -- Seconds per light
	chaseBrightness = 0,     -- 0 = full brightness

	-- Pulse pattern settings
	pulseSpeed = 1.5,        -- Seconds per pulse
	pulseMinBrightness = 0.7, -- Transparency at dimmest
	pulseMaxBrightness = 0,  -- Transparency at brightest

	-- Winning effect settings
	winFlashSpeed = 0.1,      -- Seconds per flash
	celebrationDuration = 5,  -- How long winning effects last

	-- Sound effect settings
	voteSoundId = "rbxassetid://6042583517", -- Replace with your desired sound ID
	winSoundId = "rbxassetid://6499273168",  -- Replace with your desired sound ID

	-- State tracking
	activePatterns = {},
	isInitialized = false
}

-- Helper to get random elements from a table
local function getRandomElement(tbl)
	if #tbl == 0 then return nil end
	return tbl[math.random(1, #tbl)]
end

-- Initialize the controller by finding all light parts
function LobbyEffectsController:Initialize()
	if self.isInitialized then return end

	-- Setup sounds folder if it doesn't exist
	if not ReplicatedStorage:FindFirstChild("LobbyEffectSounds") then
		self.soundsFolder = Instance.new("Folder")
		self.soundsFolder.Name = "LobbyEffectSounds"
		self.soundsFolder.Parent = ReplicatedStorage

		-- Create sound objects
		local voteSound = Instance.new("Sound")
		voteSound.Name = "VoteSound"
		voteSound.SoundId = self.voteSoundId
		voteSound.Volume = 0.5
		voteSound.Parent = self.soundsFolder

		local winSound = Instance.new("Sound")
		winSound.Name = "WinSound"
		winSound.SoundId = self.winSoundId
		winSound.Volume = 0.7
		winSound.Parent = self.soundsFolder
	else
		self.soundsFolder = ReplicatedStorage:FindFirstChild("LobbyEffectSounds")
	end

	-- Find all voting panels
	local votePanels = {
		workspace:FindFirstChild("VoteOne"),
		workspace:FindFirstChild("VoteTwo"),
		workspace:FindFirstChild("VoteThree")
	}

	-- Clear existing references (in case of reinitialization)
	self.lightsByVotePanel = {
		[1] = {},
		[2] = {},
		[3] = {}
	}

	-- Find all light parts for each panel
	for i, panel in ipairs(votePanels) do
		if panel then
			-- Get the model containing octagon lights
			local model = panel:FindFirstChild("Model")
			if model then
				-- Find all OctagonPartAngled objects
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name == "OctagonPartAngled" then
						table.insert(self.lightsByVotePanel[i], part)

						-- Set up initial properties
						part.Material = Enum.Material.Neon
						part.Transparency = 0.7  -- Dim by default
						part.Color = self.idleColor
					end
				end

				print("Found " .. #self.lightsByVotePanel[i] .. " lights for Vote Panel " .. i)
			end
		end
	end

	-- Mark as initialized
	self.isInitialized = true
	print("Lobby Effects Controller initialized")

	-- Start idle animations
	self:StartIdleEffects()
end

-- Clean up all running effects
function LobbyEffectsController:StopAllEffects()
	-- Stop all running threads using their stop functions
	for _, stopFunc in pairs(self.cleanupConnections) do
		if type(stopFunc) == "function" then
			stopFunc()
		elseif stopFunc then
			-- For backward compatibility, handle old-style connections
			pcall(function() stopFunc:Disconnect() end)
		end
	end
	self.cleanupConnections = {}

	-- Clear all active patterns
	self.activePatterns = {}

	-- Reset all lights to default state
	for i, lights in pairs(self.lightsByVotePanel) do
		for _, light in ipairs(lights) do
			light.Transparency = 0.7
			light.Color = self.idleColor
			light.Material = Enum.Material.Neon
		end
	end
end

-- Start idle animated effects for the voting panels
function LobbyEffectsController:StartIdleEffects()
	self:StopAllEffects()

	-- For each voting panel, create a random sparkle effect
	for panelIndex, lights in pairs(self.lightsByVotePanel) do
		if #lights > 0 then
			-- Start sparkle pattern
			self:StartSparkleEffect(panelIndex)
		end
	end

	print("Started idle sparkle effects for voting panels")
end

-- Create a random sparkle effect for a vote panel
function LobbyEffectsController:StartSparkleEffect(panelIndex)
	local lights = self.lightsByVotePanel[panelIndex]
	if #lights == 0 then return end

	local pattern = {}
	local isRunning = true

	pattern.thread = task.spawn(function()
		while isRunning do
			-- Determine how many lights to illuminate (around 10-15% of lights)
			local numToLight = math.ceil(#lights * (math.random(10, 15) / 100))

			-- Create a table of indices to light
			local indicesToLight = {}
			for i = 1, numToLight do
				local randomIndex
				repeat
					randomIndex = math.random(1, #lights)
				until not indicesToLight[randomIndex]
				indicesToLight[randomIndex] = true
			end

			-- Reset all lights to dim first
			for i, light in ipairs(lights) do
				light.Transparency = 0.7
				light.Color = self.idleColor
			end

			-- Illuminate the selected lights
			for index, _ in pairs(indicesToLight) do
				lights[index].Transparency = 0.2
			end

			-- Wait a randomized time before next update
			task.wait(math.random(15, 25) / 100) -- 0.15 to 0.25 seconds for a nice twinkle rate
		end
	end)

	-- Store the cleanup function
	pattern.stop = function() isRunning = false end
	table.insert(self.cleanupConnections, pattern.stop)
	table.insert(self.activePatterns, pattern)

	return pattern
end

-- Add occasional random flickering to some lights
function LobbyEffectsController:StartRandomFlickers(panelIndex)
	local lights = self.lightsByVotePanel[panelIndex]
	if #lights == 0 then return end

	local pattern = {}
	local isRunning = true

	pattern.thread = task.spawn(function()
		while isRunning do
			-- Select a random light
			local randomLight = getRandomElement(lights)
			if randomLight then
				-- Save original transparency
				local originalTrans = randomLight.Transparency

				-- Flicker effect
				randomLight.Transparency = 0.9
				task.wait(0.05)
				randomLight.Transparency = 0
				task.wait(0.05)
				randomLight.Transparency = 0.8
				task.wait(0.07)
				randomLight.Transparency = 0.2
				task.wait(0.05)
				randomLight.Transparency = originalTrans
			end

			-- Wait random time before next flicker
			task.wait(math.random(2, 5))
		end
	end)

	-- Store the cleanup function
	pattern.stop = function() isRunning = false end
	table.insert(self.cleanupConnections, pattern.stop)
	table.insert(self.activePatterns, pattern)

	return pattern
end

-- Highlight a voting panel when it receives a vote
function LobbyEffectsController:HighlightVotedPanel(panelIndex)
	local lights = self.lightsByVotePanel[panelIndex]
	if #lights == 0 then return end

	-- Play vote sound
	local sound = self.soundsFolder:FindFirstChild("VoteSound"):Clone()
	sound.Parent = workspace
	sound:Play()
	spawn(function()
		wait(2)
		sound:Destroy()
	end)

	-- Create a surge effect
	for _, light in ipairs(lights) do
		-- Animate to highlight color and full brightness
		local highlightTween = TweenService:Create(
			light,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Color = self.voteColor,
				Transparency = 0
			}
		)

		-- Animate back to normal
		local resetTween = TweenService:Create(
			light,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Color = self.idleColor,
				Transparency = 0.7
			}
		)

		-- Run the tweens in sequence
		highlightTween:Play()

		spawn(function()
			wait(0.3)
			resetTween:Play()
		end)
	end
end

-- Update all vote panels with the current vote counts
function LobbyEffectsController:UpdateVoteCounts(voteCounts)
	-- For each panel, adjust lighting intensity based on vote count
	for panelIndex, voteCount in pairs(voteCounts) do
		local lights = self.lightsByVotePanel[panelIndex]
		if #lights > 0 then
			-- Calculate percentage of lights to illuminate based on vote count
			-- For example: 0 votes = 15%, 5+ votes = 80%
			local maxVotes = 5 -- Assuming 5 is a good number for maximum effect
			local basePercentage = 15 -- Base percentage of lights lit with no votes
			local maxPercentage = 80 -- Maximum percentage with lots of votes

			local percentage = basePercentage + ((maxPercentage - basePercentage) * math.min(voteCount, maxVotes) / maxVotes)
			local lightsToIlluminate = math.ceil((percentage / 100) * #lights)

			-- Ensure we're not exceeding the total lights
			lightsToIlluminate = math.min(lightsToIlluminate, #lights)

			-- Create array of indices
			local indices = {}
			for i = 1, #lights do
				table.insert(indices, i)
			end

			-- Shuffle the indices to randomize which lights are lit
			for i = #indices, 2, -1 do
				local j = math.random(i)
				indices[i], indices[j] = indices[j], indices[i]
			end

			-- Reset all lights to dim first
			for _, light in ipairs(lights) do
				light.Transparency = 0.7
				light.Color = self.idleColor
			end

			-- Illuminate the selected percentage of lights
			for i = 1, lightsToIlluminate do
				local lightIndex = indices[i]
				-- Blend color between idle and vote color based on vote count
				local intensity = math.min(voteCount / maxVotes, 1)
				lights[lightIndex].Color = self.idleColor:Lerp(self.voteColor, intensity)
				lights[lightIndex].Transparency = 0.3 - (intensity * 0.3) -- Brighter with more votes
			end
		end
	end
end

-- Celebrate when a map is selected
function LobbyEffectsController:CelebrateWinningPanel(winningPanelIndex)
	self:StopAllEffects()

	local lights = self.lightsByVotePanel[winningPanelIndex]
	if #lights == 0 then return end

	-- Play winning sound from one of the voting panel parts for better spatial audio
	local voteParts = {
		workspace:FindFirstChild("VoteOne"),
		workspace:FindFirstChild("VoteTwo"),
		workspace:FindFirstChild("VoteThree")
	}

	local winningPart = voteParts[winningPanelIndex]
	if winningPart then
		local sound = self.soundsFolder:FindFirstChild("WinSound"):Clone()
		sound.Parent = winningPart
		sound.Volume = 1
		sound:Play()
		task.spawn(function()
			task.wait(5)
			sound:Destroy()
		end)
	else
		-- Fallback if part not found
		local sound = self.soundsFolder:FindFirstChild("WinSound"):Clone()
		sound.Parent = workspace
		sound.Volume = 1
		sound:Play()
		task.spawn(function()
			task.wait(5)
			sound:Destroy()
		end)
	end

	-- Celebration light patterns that work with random octagon arrangements
	local pattern = {}
	local isRunning = true

	pattern.thread = task.spawn(function()
		local startTime = os.clock()

		-- Flash for celebration duration
		while os.clock() - startTime < self.celebrationDuration and isRunning do
			-- Phase 1: All lights synchronously flash
			for i = 1, 5 do -- 5 quick blinks
				-- Turn all lights on
				for _, light in ipairs(lights) do
					light.Color = self.winningColor
					light.Transparency = 0
				end
				task.wait(0.12)

				-- Turn all lights off
				for _, light in ipairs(lights) do
					light.Transparency = 0.9
				end
				task.wait(0.06)
			end

			-- Phase 2: Intensity wave (percentage of lights on changes over time)
			local intensity = 0
			local direction = 1 -- 1 = increasing, -1 = decreasing

			for j = 1, 10 do -- 10 steps in the wave
				-- Calculate percentage of lights to illuminate
				intensity = intensity + (0.1 * direction)
				if intensity >= 1 then
					intensity = 1
					direction = -1
				elseif intensity <= 0 then
					intensity = 0
					direction = 1
				end

				-- Pick random lights based on intensity
				local numToLight = math.ceil(#lights * intensity)

				-- Reset all lights
				for _, light in ipairs(lights) do
					light.Transparency = 0.8
				end

				-- Create an array of indices and shuffle it
				local indices = {}
				for k = 1, #lights do
					table.insert(indices, k)
				end

				for k = #indices, 2, -1 do
					local l = math.random(k)
					indices[k], indices[l] = indices[l], indices[k]
				end

				-- Light up the randomly selected lights
				for k = 1, numToLight do
					local lightIndex = indices[k]
					lights[lightIndex].Color = self.winningColor
					lights[lightIndex].Transparency = 0
				end

				task.wait(0.15)
			end

			-- Phase 3: Accelerating random flash pattern
			local flashInterval = 0.2
			for m = 1, 8 do -- 8 flashes with decreasing interval
				-- Pick a random set of lights (30%-70% of total)
				local percentToLight = math.random(30, 70) / 100
				local numToLight = math.ceil(#lights * percentToLight)

				-- Reset all lights
				for _, light in ipairs(lights) do
					light.Transparency = 0.8
				end

				-- Light random selection
				for n = 1, numToLight do
					local randomIndex = math.random(1, #lights)
					lights[randomIndex].Color = self.winningColor
					lights[randomIndex].Transparency = 0
				end

				-- Decrease interval each time (accelerating effect)
				flashInterval = flashInterval * 0.8
				task.wait(flashInterval)
			end

			-- Make non-winning panels dim
			for panelIndex, panelLights in pairs(self.lightsByVotePanel) do
				if panelIndex ~= winningPanelIndex then
					for _, light in ipairs(panelLights) do
						light.Transparency = 0.9
						light.Color = self.idleColor
					end
				end
			end
		end

		-- Final state: All winning panel lights on
		for _, light in ipairs(lights) do
			light.Color = self.winningColor
			light.Transparency = 0
		end

		-- Finished celebration
		print("Winning celebration complete")
	end)

	-- Store the cleanup function
	pattern.stop = function() isRunning = false end
	table.insert(self.cleanupConnections, pattern.stop)
	table.insert(self.activePatterns, pattern)

	return pattern
end

-- Return the controller
return LobbyEffectsController