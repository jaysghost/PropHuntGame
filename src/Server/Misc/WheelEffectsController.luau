-- WheelEffectsController.lua
-- Module to handle lighting and sound effects for the hunter selection wheel
-- Place in same folder as WheelSpinner or in the Misc folder

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration for effects
local WheelEffectsController = {
	-- References
	wheelCenter = nil,
	wheelLights = {},
	lightAngles = {}, -- Store each light's angle relative to center
	cleanupFunctions = {},
	soundsFolder = nil,

	-- Lighting effect settings
	idleColor = Color3.fromRGB(255, 255, 255),    -- White
	spinningColor = Color3.fromRGB(255, 215, 0),  -- Gold
	winnerColor = Color3.fromRGB(0, 255, 100),    -- Green

	-- Pattern settings
	pulseSpeed = 1.5,             -- Seconds per pulse cycle
	pulseMinBrightness = 0.7,     -- Transparency at dimmest (0-1)
	pulseMaxBrightness = 0,       -- Transparency at brightest (0-1)
	twinkleRate = 5,              -- Percentage of lights active at once during twinkle

	-- Spinning effect settings
	spinPulseSpeed = 0.5,         -- Seconds per pulse during spin
	spinnerFlashSpeed = 0.1,      -- Seconds per flash during final selection
	chaseSegments = 3,            -- Number of segments to light up during chase

	-- Sound effect settings
	spinStartSoundId = "rbxassetid://5204303410", -- Replace with desired sound
	spinLoopSoundId = "rbxassetid://142376088",   -- Replace with desired sound
	spinEndSoundId = "rbxassetid://3307930188",   -- Replace with desired sound

	-- State tracking
	isSpinning = false,
	isInitialized = false,
	activeEffects = {},
	sounds = {}
}

-- Calculate the angle of a part relative to the wheel center
local function calculateAngle(center, part)
	-- Get positions in XZ plane (ignoring Y since the wheel is vertical)
	local centerPos = Vector2.new(center.Position.X, center.Position.Z)
	local partPos = Vector2.new(part.Position.X, part.Position.Z)

	-- Calculate vector from center to part
	local vector = partPos - centerPos

	-- Calculate angle in radians
	local angle = math.atan2(vector.Y, vector.X)
	if angle < 0 then
		angle = angle + (2 * math.pi) -- Convert to 0-2π range
	end

	return angle
end

-- Sort parts by their angular position
local function sortPartsByAngle(center, parts)
	-- Calculate angles for all parts
	local partsWithAngles = {}
	for i, part in ipairs(parts) do
		local angle = calculateAngle(center, part)
		table.insert(partsWithAngles, {
			part = part,
			angle = angle
		})
	end

	-- Sort by angle
	table.sort(partsWithAngles, function(a, b)
		return a.angle < b.angle
	end)

	-- Return sorted parts and their angles
	local sortedParts = {}
	local angles = {}
	for i, data in ipairs(partsWithAngles) do
		table.insert(sortedParts, data.part)
		angles[data.part] = data.angle
	end

	return sortedParts, angles
end

-- Initialize the controller
function WheelEffectsController:Initialize()
	if self.isInitialized then return end

	-- Set up sounds folder if it doesn't exist
	if not ReplicatedStorage:FindFirstChild("WheelEffectSounds") then
		self.soundsFolder = Instance.new("Folder")
		self.soundsFolder.Name = "WheelEffectSounds"
		self.soundsFolder.Parent = ReplicatedStorage

		-- Create sound objects
		local spinStartSound = Instance.new("Sound")
		spinStartSound.Name = "SpinStartSound"
		spinStartSound.SoundId = self.spinStartSoundId
		spinStartSound.Volume = 0.8
		spinStartSound.Parent = self.soundsFolder

		local spinLoopSound = Instance.new("Sound")
		spinLoopSound.Name = "SpinLoopSound"
		spinLoopSound.SoundId = self.spinLoopSoundId
		spinLoopSound.Volume = 0.6
		spinLoopSound.Looped = true
		spinLoopSound.Parent = self.soundsFolder

		local spinEndSound = Instance.new("Sound")
		spinEndSound.Name = "SpinEndSound"
		spinEndSound.SoundId = self.spinEndSoundId
		spinEndSound.Volume = 1
		spinEndSound.Parent = self.soundsFolder
	else
		self.soundsFolder = ReplicatedStorage:FindFirstChild("WheelEffectSounds")
	end

	-- Find the wheel in workspace
	local wheel = workspace:FindFirstChild("Wheel")
	if not wheel then
		warn("Wheel not found in workspace!")
		return false
	end

	-- Find the wheel center
	local wheelCenter = wheel:FindFirstChild("WheelCenter")
	if not wheelCenter then
		warn("WheelCenter not found in Wheel!")
		return false
	end

	self.wheelCenter = wheelCenter

	-- Find all octagon light parts
	local lightParts = {}
	for _, child in pairs(wheel:GetDescendants()) do
		if child:IsA("BasePart") and child.Name == "OctagonPartAngled" then
			table.insert(lightParts, child)
		end
	end

	if #lightParts == 0 then
		warn("No OctagonPartAngled parts found in Wheel!")
		return false
	end

	print("Found " .. #lightParts .. " light parts in wheel")

	-- Sort parts by their angular position around the wheel
	self.wheelLights, self.lightAngles = sortPartsByAngle(wheelCenter, lightParts)

	-- Set up initial properties
	for _, light in ipairs(self.wheelLights) do
		light.Material = Enum.Material.Neon
		light.Transparency = 0.7  -- Dim by default
		light.Color = self.idleColor
	end

	-- Find the selector
	self.selector = wheel:FindFirstChild("Selector")

	self.isInitialized = true
	print("Wheel Effects Controller initialized with " .. #self.wheelLights .. " lights")

	-- Start idle animations
	self:StartIdleEffects()

	return true
end

-- Stop all running effects
function WheelEffectsController:StopAllEffects()
	-- Stop all running functions
	for _, stopFunc in pairs(self.cleanupFunctions) do
		if type(stopFunc) == "function" then
			stopFunc()
		end
	end
	self.cleanupFunctions = {}

	-- Stop any playing sounds
	for soundName, sound in pairs(self.sounds) do
		pcall(function()
			if sound and typeof(sound) == "Instance" and sound:IsA("Sound") then
				if sound.IsPlaying then
					sound:Stop()
				end
				sound:Destroy()
			end
		end)
	end
	self.sounds = {}

	-- Reset all lights to default state
	for _, light in ipairs(self.wheelLights) do
		light.Transparency = 0.7
		light.Color = self.idleColor
	end
end

-- Start idle effects for the wheel
function WheelEffectsController:StartIdleEffects()
	self:StopAllEffects()

	-- Start gentle pulse wave
	self:StartPulseEffect()

	-- Start random twinkle
	self:StartTwinkleEffect()

	print("Started idle wheel effects")
end

-- Create a gentle pulse effect on all lights
function WheelEffectsController:StartPulseEffect()
	local isRunning = true

	local thread = task.spawn(function()
		local startTime = os.clock()

		while isRunning do
			-- Calculate pulse value (0 to 1)
			local elapsedTime = os.clock() - startTime
			local pulseCycle = (elapsedTime / self.pulseSpeed) % 1
			local pulseValue = (math.cos(pulseCycle * math.pi * 2) + 1) / 2 -- 0 to 1

			-- Calculate transparency (blend between min and max brightness)
			local transparency = self.pulseMinBrightness + 
				(self.pulseMaxBrightness - self.pulseMinBrightness) * pulseValue

			-- Apply to all lights
			for _, light in ipairs(self.wheelLights) do
				light.Transparency = transparency
			end

			task.wait(0.05) -- Small step for smooth animation
		end
	end)

	-- Store cleanup function
	local cleanup = function()
		isRunning = false
	end

	table.insert(self.cleanupFunctions, cleanup)
end

-- Create a random twinkling effect
function WheelEffectsController:StartTwinkleEffect()
	local isRunning = true

	local thread = task.spawn(function()
		while isRunning do
			-- Determine how many lights to twinkle (percentage of total)
			local numToTwinkle = math.ceil(#self.wheelLights * (self.twinkleRate / 100))

			-- Select random lights to twinkle
			local lightIndices = {}
			for i = 1, numToTwinkle do
				local randomIndex
				repeat
					randomIndex = math.random(1, #self.wheelLights)
				until not lightIndices[randomIndex]
				lightIndices[randomIndex] = true
			end

			-- Twinkle the selected lights
			for index, _ in pairs(lightIndices) do
				local light = self.wheelLights[index]
				-- Save original transparency
				local originalTrans = light.Transparency

				-- Highlight briefly
				light.Transparency = 0
				light.Color = Color3.fromRGB(255, 255, 255) -- Pure white flash

				-- Restore after a short delay
				task.spawn(function()
					task.wait(0.1)
					if isRunning then -- Check if effect is still running
						light.Transparency = originalTrans
						light.Color = self.idleColor
					end
				end)
			end

			-- Wait before next twinkle
			task.wait(math.random(20, 40) / 100) -- 0.2 to 0.4 seconds
		end
	end)

	-- Store cleanup function
	local cleanup = function()
		isRunning = false
	end

	table.insert(self.cleanupFunctions, cleanup)
end

-- Start wheel spinning effects
function WheelEffectsController:StartSpinningEffects(initialSpeed)
	if not self.isInitialized then return end

	self:StopAllEffects()
	self.isSpinning = true

	-- Play spin start sound
	local startSound = self.soundsFolder:FindFirstChild("SpinStartSound"):Clone()
	startSound.Parent = self.wheelCenter
	--startSound:Play()
	self.sounds.start = startSound

	-- Set up looping spin sound (start after short delay)
	task.spawn(function()
		task.wait(0.7)
		if self.isSpinning then
			local loopSound = self.soundsFolder:FindFirstChild("SpinLoopSound"):Clone()
			loopSound.Parent = self.wheelCenter
			loopSound:Play()
			self.sounds.loop = loopSound
		end
	end)

	-- Apply chase lighting effect based on speed
	local isRunning = true
	local chaseSpeed = 0.08 -- Starting speed

	local thread = task.spawn(function()
		local chaseIndex = 1

		while isRunning do
			-- Reset all lights first
			for _, light in ipairs(self.wheelLights) do
				light.Transparency = 0.6
				light.Color = self.spinningColor
			end

			-- Calculate how many segments to light based on wheel speed
			local speedFactor = math.min(1, initialSpeed / 2)
			local numLights = math.max(1, math.floor(self.chaseSegments + (speedFactor * 5)))

			-- Light up the active segment and next few segments
			for i = 0, numLights - 1 do
				local index = ((chaseIndex + i - 1) % #self.wheelLights) + 1
				self.wheelLights[index].Transparency = 0
			end

			-- Increment chase position
			chaseIndex = (chaseIndex % #self.wheelLights) + 1

			-- Adjust chase speed based on wheel speed (simulate slowing down)
			chaseSpeed = math.max(0.02, chaseSpeed * 0.995)

			task.wait(chaseSpeed)
		end
	end)

	-- Store cleanup function
	local cleanup = function()
		isRunning = false

		-- Stop sounds
		for _, sound in pairs(self.sounds) do
			if sound and sound.IsPlaying then
				sound:Stop()
				sound:Destroy()
			end
		end
		self.sounds = {}
	end

	table.insert(self.cleanupFunctions, cleanup)
end

-- Handle finishing spin animation
function WheelEffectsController:FinishSpin(winningIndex)
	self.isSpinning = false

	-- Stop spin loop sound if playing
	if self.sounds.loop then
		-- Check if sound exists and has needed methods
		if typeof(self.sounds.loop) == "Instance" and self.sounds.loop:IsA("Sound") then
			-- Check if it's playing before trying to stop it
			if self.sounds.loop.IsPlaying then
				-- Fade out loop sound
				local fadeOut = TweenService:Create(
					self.sounds.loop,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Volume = 0
					}
				)
				fadeOut:Play()
			end

			task.spawn(function()
				task.wait(0.5)
				-- Double-check sound still exists before stopping it
				if self.sounds.loop and typeof(self.sounds.loop) == "Instance" and self.sounds.loop:IsA("Sound") then
					pcall(function()
						if self.sounds.loop.IsPlaying then
							self.sounds.loop:Stop()
						end
						self.sounds.loop:Destroy()
					end)
				end
				self.sounds.loop = nil
			end)
		else
			-- Not a valid sound object, just clean up the reference
			self.sounds.loop = nil
		end
	end

	-- Play end sound
	local endSound = self.soundsFolder:FindFirstChild("SpinEndSound"):Clone()
	endSound.Parent = self.wheelCenter
	endSound:Play()
	self.sounds["endSound"] = endSound  -- Using string key to avoid keyword

	task.spawn(function()
		task.wait(3)
		if self.sounds["endSound"] then
			self.sounds["endSound"]:Destroy()
			self.sounds["endSound"] = nil
		end
	end)

	-- Stop all current effects
	self:StopAllEffects()

	-- Flash winning section a few times
	local isRunning = true
	local flashCount = 0

	local thread = task.spawn(function()
		-- Determine which lights correspond to the winning segment
		-- Since we don't have direct segment-to-light mapping, approximate using angle ranges
		local segmentAngle = (2 * math.pi) / 16 -- Assuming 16 segments
		local winningAngle = (winningIndex - 1) * segmentAngle

		-- Find lights in the winning segment angle range
		local winningLights = {}
		for _, light in ipairs(self.wheelLights) do
			local angle = self.lightAngles[light]
			local angleDiff = math.abs(angle - winningAngle)
			if angleDiff <= segmentAngle / 2 or angleDiff >= (2 * math.pi - segmentAngle / 2) then
				table.insert(winningLights, light)
			end
		end

		-- If no winning lights found, flash all lights
		if #winningLights == 0 then
			winningLights = self.wheelLights
		end

		-- Flash the winning segment
		local isOn = false
		while flashCount < 10 and isRunning do
			isOn = not isOn

			-- Update all lights
			for _, light in ipairs(self.wheelLights) do
				if table.find(winningLights, light) then
					-- Winning section lights
					light.Transparency = isOn and 0 or 0.7
					light.Color = self.winnerColor
				else
					-- Non-winning section lights
					light.Transparency = 0.8
					light.Color = self.idleColor
				end
			end

			flashCount = flashCount + 1
			task.wait(self.spinnerFlashSpeed)
		end

		-- Final state - winning segment fully lit
		if isRunning then
			for _, light in ipairs(self.wheelLights) do
				if table.find(winningLights, light) then
					light.Transparency = 0
					light.Color = self.winnerColor
				else
					light.Transparency = 0.7
					light.Color = self.idleColor
				end
			end
		end
	end)

	-- Store cleanup function
	local cleanup = function()
		isRunning = false
	end

	table.insert(self.cleanupFunctions, cleanup)

	return cleanup
end

-- Integrate with WheelSpinner
function WheelEffectsController:IntegrateWithSpinner(wheelSpinner)
	-- Store original functions from wheel spinner
	local originalSpinWheel = wheelSpinner.SpinWheel

	-- Override SpinWheel to add effects
	wheelSpinner.SpinWheel = function(...)
		-- Add pre-spin effects
		self:StartSpinningEffects(wheelSpinner.INITIAL_SPEED or 2)

		-- Call original function
		local result = originalSpinWheel(...)

		-- Add post-spin effects
		local winningSegmentIndex = wheelSpinner.GetCurrentWinningSegment and 
			wheelSpinner.GetCurrentWinningSegment() or 1
		self:FinishSpin(winningSegmentIndex)

		-- Return original result
		return result
	end

	print("Integrated wheel effects with spinner")
end

-- Return the controller
return WheelEffectsController