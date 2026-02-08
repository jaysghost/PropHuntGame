-- WheelEffectsController.lua - FIXED VERSION
-- This version syncs lighting effects with the actual wheel rotation

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WheelEffectsController = {
	-- References
	wheelCenter = nil,
	wheelLights = {},
	lightAngles = {},
	wheelPieces = {}, -- NEW: Store wheel pieces for mapping
	cleanupFunctions = {},
	soundsFolder = nil,
	wheelSpinner = nil, -- NEW: Reference to WheelSpinner

	-- Lighting effect settings
	idleColor = Color3.fromRGB(255, 255, 255),
	spinningColor = Color3.fromRGB(255, 215, 0),
	winnerColor = Color3.fromRGB(0, 255, 100),

	-- Pattern settings
	pulseSpeed = 1.5,
	pulseMinBrightness = 0.7,
	pulseMaxBrightness = 0,
	twinkleRate = 5,

	-- Spinning effect settings
	spinPulseSpeed = 0.5,
	spinnerFlashSpeed = 0.1,
	chaseSegments = 3,

	-- Sound effect settings
	spinStartSoundId = "rbxassetid://5204303410",
	spinLoopSoundId = "rbxassetid://142376088",
	spinEndSoundId = "rbxassetid://3307930188",

	-- State tracking
	isSpinning = false,
	isInitialized = false,
	activeEffects = {},
	sounds = {}
}

-- Calculate the angle of a part relative to the wheel center
local function calculateAngle(center, part)
	local centerPos = Vector2.new(center.Position.X, center.Position.Z)
	local partPos = Vector2.new(part.Position.X, part.Position.Z)
	local vector = partPos - centerPos
	local angle = math.atan2(vector.Y, vector.X)
	if angle < 0 then
		angle = angle + (2 * math.pi)
	end
	return angle
end

-- Sort parts by their angular position
local function sortPartsByAngle(center, parts)
	local partsWithAngles = {}
	for i, part in ipairs(parts) do
		local angle = calculateAngle(center, part)
		table.insert(partsWithAngles, {
			part = part,
			angle = angle
		})
	end

	table.sort(partsWithAngles, function(a, b)
		return a.angle < b.angle
	end)

	local sortedParts = {}
	local angles = {}
	for i, data in ipairs(partsWithAngles) do
		table.insert(sortedParts, data.part)
		angles[data.part] = data.angle
	end

	return sortedParts, angles
end

-- NEW: Map light index to wheel piece segment
local function getLightForSegment(self, segmentIndex)
	-- Each segment has lights nearby
	-- We need to find which lights correspond to which segments

	-- If we have 16 segments and multiple lights per segment,
	-- calculate which lights belong to this segment
	local lightsPerSegment = #self.wheelLights / 16
	local startLight = math.floor((segmentIndex - 1) * lightsPerSegment) + 1
	local endLight = math.floor(segmentIndex * lightsPerSegment)

	local lights = {}
	for i = startLight, endLight do
		if self.wheelLights[i] then
			table.insert(lights, self.wheelLights[i])
		end
	end

	return lights
end

-- Initialize the controller
function WheelEffectsController:Initialize()
	if self.isInitialized then return end

	-- Set up sounds folder
	if not ReplicatedStorage:FindFirstChild("WheelEffectSounds") then
		self.soundsFolder = Instance.new("Folder")
		self.soundsFolder.Name = "WheelEffectSounds"
		self.soundsFolder.Parent = ReplicatedStorage

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

	-- Sort lights by angle for proper mapping
	self.wheelLights, self.lightAngles = sortPartsByAngle(wheelCenter, lightParts)

	-- NEW: Find all wheel pieces
	local wheelPieces = {}
	for _, child in pairs(wheel:GetDescendants()) do
		if child:IsA("BasePart") and child.Name == "WheelPiece" then
			table.insert(wheelPieces, child)
		end
	end
	self.wheelPieces = wheelPieces

	print("WheelEffectsController initialized with " .. #self.wheelLights .. " lights and " .. #self.wheelPieces .. " pieces")

	self.isInitialized = true
	return true
end

-- Stop all active effects
function WheelEffectsController:StopAllEffects()
	for _, cleanup in ipairs(self.cleanupFunctions) do
		cleanup()
	end
	self.cleanupFunctions = {}

	-- Reset all lights to idle state
	for _, light in ipairs(self.wheelLights) do
		light.Transparency = 0.7
		light.Color = self.idleColor
	end
end

-- Start idle effects (pulse)
function WheelEffectsController:StartIdleEffects()
	if not self.isInitialized then return end

	self:StopAllEffects()

	local isRunning = true

	local thread = task.spawn(function()
		local startTime = tick()

		while isRunning do
			local elapsed = tick() - startTime
			local pulseValue = (math.sin(elapsed * (2 * math.pi / self.pulseSpeed)) + 1) / 2
			local transparency = self.pulseMinBrightness + 
				(self.pulseMaxBrightness - self.pulseMinBrightness) * pulseValue

			for _, light in ipairs(self.wheelLights) do
				light.Transparency = transparency
			end

			task.wait(0.05)
		end
	end)

	local cleanup = function()
		isRunning = false
	end

	table.insert(self.cleanupFunctions, cleanup)
end

-- NEW: Start wheel spinning effects WITH SYNC
function WheelEffectsController:StartSpinningEffects(wheelSpinnerModule)
	if not self.isInitialized then return end

	self:StopAllEffects()
	self.isSpinning = true
	self.wheelSpinner = wheelSpinnerModule

	-- Play spin start sound
	local startSound = self.soundsFolder:FindFirstChild("SpinStartSound"):Clone()
	startSound.Parent = self.wheelCenter
	--startSound:Play()
	self.sounds.start = startSound

	-- Set up looping spin sound
	task.spawn(function()
		task.wait(0.7)
		if self.isSpinning then
			local loopSound = self.soundsFolder:FindFirstChild("SpinLoopSound"):Clone()
			loopSound.Parent = self.wheelCenter
			loopSound:Play()
			self.sounds.loop = loopSound
		end
	end)

	-- FIXED: Sync lighting to wheel rotation via Heartbeat
	local isRunning = true

	local thread = task.spawn(function()
		-- Connect to RunService to sync with wheel rotation
		local connection = RunService.Heartbeat:Connect(function()
			if not isRunning or not self.isSpinning then
				return
			end

			-- Get current winning segment from WheelSpinner
			local currentSegment = self.wheelSpinner.GetCurrentWinningSegment 
				and self.wheelSpinner.GetCurrentWinningSegment() 
				or 1

			-- Reset all lights to dim
			for _, light in ipairs(self.wheelLights) do
				light.Transparency = 0.7
				light.Color = self.spinningColor
			end

			-- Light up the current segment's lights
			local segmentLights = getLightForSegment(self, currentSegment)
			for _, light in ipairs(segmentLights) do
				light.Transparency = 0
				light.Color = self.spinningColor
			end
		end)

		-- Store cleanup that disconnects the connection
		table.insert(self.cleanupFunctions, function()
			connection:Disconnect()
		end)
	end)

	-- Store main cleanup function
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
		if typeof(self.sounds.loop) == "Instance" and self.sounds.loop:IsA("Sound") then
			if self.sounds.loop.IsPlaying then
				local fadeOut = TweenService:Create(
					self.sounds.loop,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Volume = 0 }
				)
				fadeOut:Play()
			end

			task.spawn(function()
				task.wait(0.5)
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
			self.sounds.loop = nil
		end
	end

	-- Play end sound
	local endSound = self.soundsFolder:FindFirstChild("SpinEndSound"):Clone()
	endSound.Parent = self.wheelCenter
	endSound:Play()
	self.sounds["endSound"] = endSound

	task.spawn(function()
		task.wait(3)
		if self.sounds["endSound"] then
			self.sounds["endSound"]:Destroy()
			self.sounds["endSound"] = nil
		end
	end)

	-- Stop all current effects
	self:StopAllEffects()

	-- Flash winning section
	local isRunning = true
	local flashCount = 0

	local thread = task.spawn(function()
		-- Get lights for winning segment
		local winningLights = getLightForSegment(self, winningIndex)

		if #winningLights == 0 then
			winningLights = self.wheelLights
		end

		-- Flash the winning segment
		local isOn = false
		while flashCount < 10 and isRunning do
			isOn = not isOn

			for _, light in ipairs(self.wheelLights) do
				if table.find(winningLights, light) then
					light.Transparency = isOn and 0 or 0.7
					light.Color = self.winnerColor
				else
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

	local cleanup = function()
		isRunning = false
	end

	table.insert(self.cleanupFunctions, cleanup)

	return cleanup
end

-- NEW: Integrate with WheelSpinner (FIXED VERSION)
function WheelEffectsController:IntegrateWithSpinner(wheelSpinner)
	local originalSpinWheel = wheelSpinner.SpinWheel

	-- Override SpinWheel to add effects
	wheelSpinner.SpinWheel = function(...)
		-- FIXED: Pass wheelSpinner module reference for GetCurrentWinningSegment access
		self:StartSpinningEffects(wheelSpinner)

		-- Call original function
		local result = originalSpinWheel(...)

		-- Add post-spin effects
		local winningSegmentIndex = wheelSpinner.GetCurrentWinningSegment 
			and wheelSpinner.GetCurrentWinningSegment() 
			or 1
		self:FinishSpin(winningSegmentIndex)

		return result
	end

	print("Integrated wheel effects with spinner (SYNCED VERSION)")
end

return WheelEffectsController
