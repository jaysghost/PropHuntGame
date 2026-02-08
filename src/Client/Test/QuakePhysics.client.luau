local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CameraFOVManager = require(ReplicatedStorage.CameraFOVManager)

-- Jump parameters
local JUMP_POWER = 30  -- Reduced jump power for lower initial lift
local HORIZONTAL_AIR_CONTROL = 20  -- Moderate air control
local MAX_AIR_SPEED = 100  -- Reasonable max air speed
local GRAVITY = 70
local HORIZONTAL_VELOCITY_FACTOR = 2  -- Directly match current velocity

-- Walkspeed acceleration parameters
local BASE_WALKSPEED = 18
local MAX_WALKSPEED = 24
local DEFAULT_FOV = 70
local MAX_FOV = 90

-- FOV Transition Parameters
local FOV_TRANSITION_SPEED = 3  -- How quickly FOV changes
local RESET_FOV_SPEED = 10      -- How quickly FOV resets when not moving

local ACCELERATION_TIME = 5  -- Time to reach max speed
local currentAccelerationTime = 0
local isAccelerating = false

-- State tracking
local isCustomPhysicsEnabled = true
local isClimbing = false
local lastClimbingState = false
local climbingTransitionTimer = 0
local POST_CLIMBING_DELAY = 0.5  -- Wait time after climbing before re-enabling custom physics

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local isJumping = false
local jumpVelocity = Vector3.new()
local forceJumpEnd = false

local function calculateFOV(currentSpeed)
	-- Normalize speed between base and max walkspeed
	local speedRatio = math.clamp(
		(currentSpeed - BASE_WALKSPEED) / (MAX_WALKSPEED - BASE_WALKSPEED), 
		0, 
		1
	)

	-- Use exponential curve for more dramatic FOV change
	local fovOffset = speedRatio ^ 2 * (MAX_FOV - DEFAULT_FOV)

	return DEFAULT_FOV + fovOffset
end

local function updateCameraFOV(dt)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Get current horizontal speed
	local velocity = character:FindFirstChild("HumanoidRootPart") and 
		character:FindFirstChild("HumanoidRootPart").Velocity or Vector3.new(0, 0, 0)
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- Calculate target FOV
	local targetFOV = DEFAULT_FOV  -- Default to 70

	if horizontalSpeed > BASE_WALKSPEED then
		-- Normalize speed between base and max walkspeed
		local speedRatio = math.clamp(
			(horizontalSpeed - BASE_WALKSPEED) / (MAX_WALKSPEED - BASE_WALKSPEED), 
			0, 
			1
		)

		-- Use exponential curve for more dramatic FOV change
		local fovOffset = speedRatio ^ 2 * (MAX_FOV - DEFAULT_FOV)
		targetFOV = DEFAULT_FOV + fovOffset
	end

	-- Check if another system is controlling FOV (like the blaster)
	-- Only check if we'd be increasing FOV, let other systems decrease it
	local shouldUpdateFOV = targetFOV > DEFAULT_FOV

	if shouldUpdateFOV then
		-- Smoothly interpolate FOV
		local currentFOV = camera.FieldOfView
		local speedFactor = horizontalSpeed > BASE_WALKSPEED 
			and FOV_TRANSITION_SPEED 
			or RESET_FOV_SPEED

		-- Use Lerp to gradually change FOV
		local newFOV = math.lerp(
			currentFOV, 
			targetFOV, 
			dt * speedFactor
		)

		-- Apply the FOV change
		camera.FieldOfView = newFOV
	end
end

local function checkForwardMovement()
	local moveDirection = humanoid.MoveDirection

	-- Check if moving forward in either positive or negative X or Z direction
	return moveDirection.Magnitude > 0 and 
		(math.abs(moveDirection.X) > math.abs(moveDirection.Z) or math.abs(moveDirection.Z) > math.abs(moveDirection.X)) and
		math.abs(moveDirection.X) > math.abs(moveDirection.Y) and
		math.abs(moveDirection.Z) > math.abs(moveDirection.Y)
end

-- Check if character is currently climbing
local function updateClimbingState(dt)
	local currentState = humanoid:GetState()
	isClimbing = currentState == Enum.HumanoidStateType.Climbing

	-- Handle transition from climbing to not climbing
	if lastClimbingState and not isClimbing then
		-- Just stopped climbing, wait before re-enabling custom physics
		isCustomPhysicsEnabled = false
		climbingTransitionTimer = POST_CLIMBING_DELAY
		
	elseif not lastClimbingState and isClimbing then
		-- Just started climbing
		isCustomPhysicsEnabled = false
		
	end

	-- Update timer for transition period
	if climbingTransitionTimer > 0 then
		climbingTransitionTimer = climbingTransitionTimer - dt
		if climbingTransitionTimer <= 0 then
			isCustomPhysicsEnabled = true
			
		end
	end

	-- If still climbing, ensure custom physics stays disabled
	if isClimbing then
		isCustomPhysicsEnabled = false
		climbingTransitionTimer = 0
	end

	lastClimbingState = isClimbing
end

local function onJumpRequest()
	if forceJumpEnd or not isCustomPhysicsEnabled then return end

	if not isJumping and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		isJumping = true
		local currentVelocity = rootPart.Velocity
		local walkSpeed = humanoid.WalkSpeed

		-- Directly match current horizontal velocity
		local horizontalVelocity = Vector3.new(
			currentVelocity.X * 0.9,  -- Slightly reduce horizontal momentum for stability
			JUMP_POWER,              -- Consistent vertical jump power
			currentVelocity.Z * 0.9   -- Slightly reduce horizontal momentum for stability
		)

		jumpVelocity = horizontalVelocity
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
end

local function updateJump(dt)
	if not rootPart then return end

	-- Update climbing state and transitions
	updateClimbingState(dt)

	-- If custom physics is disabled (climbing or post-climbing), don't apply any physics
	if not isCustomPhysicsEnabled then
		return
	end

	if isJumping then
		local moveDirection = humanoid.MoveDirection

		-- Mid-air directional control
		if moveDirection.Magnitude > 0 then
			-- Calculate desired velocity based on move direction
			local desiredVelocity = moveDirection * humanoid.WalkSpeed

			-- Smoothly interpolate current velocity towards desired velocity
			local horizontalVelocity = Vector3.new(jumpVelocity.X, 0, jumpVelocity.Z)
			local newHorizontalVelocity = horizontalVelocity:Lerp(
				desiredVelocity, 
				dt * HORIZONTAL_AIR_CONTROL
			)

			-- Limit speed
			if newHorizontalVelocity.Magnitude > MAX_AIR_SPEED then
				newHorizontalVelocity = newHorizontalVelocity.Unit * MAX_AIR_SPEED
			end

			-- Update jump velocity while maintaining vertical velocity
			jumpVelocity = Vector3.new(
				newHorizontalVelocity.X, 
				jumpVelocity.Y, 
				newHorizontalVelocity.Z
			)
		end

		-- Apply reduced gravity
		jumpVelocity = jumpVelocity - Vector3.new(0, GRAVITY * dt, 0)

		-- Apply velocity with safeguards
		if not forceJumpEnd then
			-- Apply impulse instead of directly setting velocity
			local currentVel = rootPart.Velocity
			local targetVel = jumpVelocity

			-- Blend between current and target (safer transition)
			local blendedVel = currentVel:Lerp(targetVel, 0.7)
			rootPart.Velocity = blendedVel
		end

		-- Check if the jump has ended
		if forceJumpEnd or humanoid:GetState() == Enum.HumanoidStateType.Landed then
			isJumping = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	elseif humanoid:GetState() == Enum.HumanoidStateType.Freefall and 
		humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
		-- Handle freefall (like when walking off ledges)
		-- This provides some air control even when not explicitly jumping
		local moveDirection = humanoid.MoveDirection

		if moveDirection.Magnitude > 0 then
			local currentVel = rootPart.Velocity
			local airControl = moveDirection * HORIZONTAL_AIR_CONTROL * 0.5 * dt

			-- Apply a small amount of air control
			local newVel = Vector3.new(
				currentVel.X + airControl.X,
				currentVel.Y,  -- Don't modify Y velocity
				currentVel.Z + airControl.Z
			)

			-- Limit horizontal speed
			local horizontalVel = Vector3.new(newVel.X, 0, newVel.Z)
			if horizontalVel.Magnitude > MAX_AIR_SPEED then
				horizontalVel = horizontalVel.Unit * MAX_AIR_SPEED
				newVel = Vector3.new(horizontalVel.X, newVel.Y, horizontalVel.Z)
			end

			rootPart.Velocity = newVel
		end
	end
end

local function updateWalkspeedAcceleration(dt)
	-- Do nothing if custom physics are disabled (climbing)
	if not isCustomPhysicsEnabled then
		return
	end

	if checkForwardMovement() then
		if not isAccelerating then
			isAccelerating = true
			currentAccelerationTime = 0
		end

		-- Increase acceleration time
		currentAccelerationTime = math.min(currentAccelerationTime + dt, ACCELERATION_TIME)

		-- Calculate exponential walkspeed
		local t = currentAccelerationTime / ACCELERATION_TIME
		local acceleratedSpeed = BASE_WALKSPEED + (MAX_WALKSPEED - BASE_WALKSPEED) * (1 - math.exp(-5 * t))

		humanoid.WalkSpeed = acceleratedSpeed
	else
		-- Reset to base speed when not moving forward
		if isAccelerating then
			isAccelerating = false
			currentAccelerationTime = 0
			humanoid.WalkSpeed = BASE_WALKSPEED
		end
	end
end

-- Connect state changes
humanoid.StateChanged:Connect(function(oldState, newState)
	-- Monitor state changes for climbing
	if oldState == Enum.HumanoidStateType.Climbing or newState == Enum.HumanoidStateType.Climbing then
	end

	if newState == Enum.HumanoidStateType.Jumping and isCustomPhysicsEnabled then
		onJumpRequest()
	elseif newState == Enum.HumanoidStateType.Landed then
		isJumping = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)

-- Connect to RunService to update jump and walkspeed
RunService.Heartbeat:Connect(function(dt)
	if not rootPart or not rootPart.Parent then
		-- Get updated references if they're invalid
		if player.Character then
			character = player.Character
			humanoid = character:FindFirstChild("Humanoid")
			rootPart = character:FindFirstChild("HumanoidRootPart")
		end
		return
	end

	updateJump(dt)
	updateWalkspeedAcceleration(dt)
end)

-- Handle character respawning
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	isJumping = false
	forceJumpEnd = false
	isCustomPhysicsEnabled = true
	isClimbing = false
	lastClimbingState = false
	climbingTransitionTimer = 0

	-- Reset walkspeed when character spawns
	humanoid.WalkSpeed = BASE_WALKSPEED

	humanoid.StateChanged:Connect(function(oldState, newState)
		-- Monitor state changes for climbing
		if oldState == Enum.HumanoidStateType.Climbing or newState == Enum.HumanoidStateType.Climbing then
			
		end

		if newState == Enum.HumanoidStateType.Jumping and isCustomPhysicsEnabled then
			onJumpRequest()
		elseif newState == Enum.HumanoidStateType.Landed then
			isJumping = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end)
end)

RunService.RenderStepped:Connect(updateCameraFOV)