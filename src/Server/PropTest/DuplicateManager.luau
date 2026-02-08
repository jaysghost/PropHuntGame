local PhysicsService = game:GetService("PhysicsService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local DuplicateManager = {}
DuplicateManager.__index = DuplicateManager

-- Constants
local DUPLICATE_LIFETIME = 4
local DUPLICATE_COOLDOWN = 10

-- Collision Group Management
function DuplicateManager.SetupCollisionGroups()
	local function createGroupIfNotExists(name)
		pcall(function()
			PhysicsService:CreateCollisionGroup(name)
		end)
	end

	createGroupIfNotExists("Players")
	createGroupIfNotExists("Duplicates")

	-- Set up collision rules
	PhysicsService:CollisionGroupSetCollidable("Players", "Duplicates", false)
end

-- Utility function to set collision group for all parts in a model
function DuplicateManager.SetModelCollisionGroup(model, groupName)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

-- Modified GetRandomDestination to get a closer point
function DuplicateManager.GetRandomDestination(origin, minDist, maxDist)
	-- Get random angle and distance for X/Z plane
	local angle = math.random() * math.pi * 2
	local distance = minDist + math.random() * (maxDist - minDist)

	-- Calculate the X and Z offsets
	local xOffset = math.cos(angle) * distance
	local zOffset = math.sin(angle) * distance

	-- Calculate initial target point
	local targetPoint = Vector3.new(
		origin.X + xOffset,
		origin.Y + 50, -- Start higher to ensure we find ground
		origin.Z + zOffset
	)

	-- Cast a ray downward to find ground
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {workspace:FindFirstChild("Duplicates")} -- Ignore other duplicates

	-- Cast a longer ray from high up
	local raycastResult = workspace:Raycast(
		targetPoint, -- Start from higher point
		Vector3.new(0, -100, 0), -- Cast much further down
		raycastParams
	)

	if raycastResult then
		-- Found ground - return point slightly above it
		return raycastResult.Position + Vector3.new(0, 2, 0)
	end

	-- If no ground found, try at current Y level
	return Vector3.new(targetPoint.X, origin.Y, targetPoint.Z)
end

-- Simulates realistic player camera rotation for duplicates
function DuplicateManager.UpdateDuplicateOrientation(duplicate)
	local humanoid = duplicate:FindFirstChild("Humanoid")
	local rootPart = duplicate:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then return end

	-- Only apply if we have a movement direction
	if humanoid.MoveDirection.Magnitude > 0.1 then
		-- Get current position
		local currentPos = rootPart.Position

		-- Use the humanoid's MoveDirection directly - this is already calculated by Roblox
		local moveDir = humanoid.MoveDirection

		-- Create a target look-at point (we're not modifying position, just making rootPart "look" at this point)
		local targetPoint = currentPos + moveDir

		-- Calculate a new CFrame that looks in the movement direction
		-- We preserve the current Y-rotation to avoid tilting, and only modify the "yaw" (Y-axis rotation)
		local currentRotation = rootPart.CFrame - rootPart.Position
		local _, currentY, _ = currentRotation:ToEulerAnglesYXZ()

		-- Get target Y rotation from movement direction
		local targetY = math.atan2(-moveDir.X, -moveDir.Z)

		-- Smoothly interpolate rotation (only Y axis)
		local smoothFactor = 0.1 -- Lower = smoother/slower rotation
		local newY = currentY + (targetY - currentY) * smoothFactor

		-- Create and apply the new rotation (only changing Y rotation)
		local newRotation = CFrame.Angles(0, newY, 0)

		-- IMPORTANT: Only set the orientation, NOT position
		rootPart.CFrame = CFrame.new(rootPart.Position) * newRotation
	end
end

-- Simplified random looking function for duplicates
function DuplicateManager.SimulateRandomLooking(duplicate)
	local humanoid = duplicate:FindFirstChild("Humanoid")
	local rootPart = duplicate:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then return end

	-- How often the duplicate looks around (in seconds)
	local MIN_LOOK_INTERVAL = 1.5
	local MAX_LOOK_INTERVAL = 4

	-- How much it can turn (in radians)
	local MAX_LOOK_ANGLE = math.rad(45)

	-- Start a continuous process
	task.spawn(function()
		while duplicate and duplicate.Parent do
			-- Random wait time
			local waitTime = MIN_LOOK_INTERVAL + math.random() * (MAX_LOOK_INTERVAL - MIN_LOOK_INTERVAL)
			task.wait(waitTime)

			if not duplicate or not duplicate.Parent then return end

			-- Only do random looking if not actively moving
			if humanoid.MoveDirection.Magnitude < 0.05 then
				-- Get current orientation
				local currentRotation = rootPart.CFrame - rootPart.Position
				local _, currentY, _ = currentRotation:ToEulerAnglesYXZ()

				-- Generate random angle to look
				local randomAngle = currentY + (math.random() * 2 - 1) * MAX_LOOK_ANGLE

				-- Smooth rotation
				local startY = currentY
				local targetY = randomAngle

				for t = 0, 1, 0.05 do
					if not duplicate or not duplicate.Parent then return end
					if humanoid.MoveDirection.Magnitude > 0.05 then break end -- Stop if we start moving

					local newY = startY + (targetY - startY) * t
					rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, newY, 0)
					task.wait(0.02)
				end
			end
		end
	end)
end

function DuplicateManager.StartContinuousPathfinding(duplicate, startPos)
	local humanoid = duplicate:FindFirstChild("Humanoid")
	local rootPart = duplicate:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	-- Create path configuration optimized for maze navigation
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5,  -- Keeps good maze navigation
		AgentHeight = 3,
		AgentCanJump = true,
		WaypointSpacing = 2,  -- Balanced spacing
		Costs = {
			Water = math.huge,
			Ramps = 0.8
		}
	})

	-- Initialize tracking variables
	local finalDestination = DuplicateManager.GetRandomDestination(startPos, 40, 50)
	local failedAttempts = 0
	local MAX_ATTEMPTS = 5
	local isStuck = false
	local stuckTimer = 0
	local lastPosition = rootPart.Position
	local isNavigating = false  -- Track if we're currently navigating to avoid overlap

	-- Set a faster walk speed
	humanoid.WalkSpeed = 18

	-- Forward declare functions to avoid circular reference
	local computeAndFollowPath
	local navigateWaypoints

	-- Function to create visual waypoint marker
	local function createWaypointMarker(position, color, size)
		local marker = Instance.new("Part")
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(size, size, size)
		marker.Position = position
		marker.Anchored = true
		marker.CanCollide = false
		marker.Transparency = 0.7
		marker.BrickColor = BrickColor.new(color)
		marker.Parent = workspace
		task.delay(1.5, function() marker:Destroy() end)
		return marker
	end

	-- Function to check if path is possible to point
	local function canPathToPoint(from, to)
		local success, _ = pcall(function()
			path:ComputeAsync(from, to)
		end)
		return success and path.Status == Enum.PathStatus.Success
	end

	-- Function to find valid destinations
	local function findValidDestination(origin, attempts)
		for i = 1, attempts do
			local destination = DuplicateManager.GetRandomDestination(origin, 20, 40)
			if canPathToPoint(origin, destination) then
				return destination
			end
		end

		for angle = 0, 330, 30 do
			local rad = math.rad(angle)
			local exploreDistance = 12
			local testPoint = Vector3.new(
				origin.X + math.cos(rad) * exploreDistance,
				origin.Y,
				origin.Z + math.sin(rad) * exploreDistance
			)

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {duplicate}

			local rayResult = workspace:Raycast(
				testPoint + Vector3.new(0, 10, 0),
				Vector3.new(0, -20, 0),
				rayParams
			)

			if rayResult then
				local groundPoint = rayResult.Position + Vector3.new(0, 2, 0)
				if canPathToPoint(origin, groundPoint) then
					return groundPoint
				end
			end
		end

		local nearbyAngles = {0, 45, 90, 135, 180, 225, 270, 315}
		for _, angle in ipairs(nearbyAngles) do
			local rad = math.rad(angle)
			local nearPoint = Vector3.new(
				origin.X + math.cos(rad) * 5,
				origin.Y,
				origin.Z + math.sin(rad) * 5
			)

			if canPathToPoint(origin, nearPoint) then
				return nearPoint
			end
		end

		return nil
	end

	-- Smart stuckness detection
	local function checkIfStuck()
		local currentPos = rootPart.Position
		local distance = (currentPos - lastPosition).Magnitude

		if distance < 0.5 then
			stuckTimer = stuckTimer + 1
			if stuckTimer > 3 then
				isStuck = true
			end
		else
			stuckTimer = 0
			isStuck = false
		end

		lastPosition = currentPos
	end

	-- The key improvement: Continuous movement through waypoints without stops
	navigateWaypoints = function(waypoints)
		if isNavigating then return end
		isNavigating = true

		-- Create merged waypoints list to reduce stops
		local mergedWaypoints = {}

		-- Only keep significant waypoints (changes in direction)
		for i = 2, #waypoints do
			if i == 2 or i == #waypoints then
				-- Always include first and last waypoints
				table.insert(mergedWaypoints, waypoints[i])
			else
				-- Check if this waypoint represents a change in direction
				local prev = waypoints[i-1].Position
				local curr = waypoints[i].Position
				local next = waypoints[i+1].Position

				local dir1 = (curr - prev).Unit
				local dir2 = (next - curr).Unit

				-- If direction changes significantly or it's a jump point, keep it
				if dir1:Dot(dir2) < 0.9 or waypoints[i].Action == Enum.PathWaypointAction.Jump then
					table.insert(mergedWaypoints, waypoints[i])
				end
			end
		end

		-- Simplified pathing with less pauses
		local targetIndex = 1

		-- Move directly to the final destination with targets as guidance
		local function moveToNextTarget()
			if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then
				isNavigating = false
				return
			end

			-- If we've processed all points, start new path
			if targetIndex > #mergedWaypoints then
				isNavigating = false
				task.delay(0.1, function() -- Tiny delay to prevent recalculation spam
					task.spawn(computeAndFollowPath)
				end)
				return
			end

			local target = mergedWaypoints[targetIndex]

			-- Handle jump
			if target.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end

			-- Move to target
			humanoid:MoveTo(target.Position)

			-- Update orientation immediately
			DuplicateManager.UpdateDuplicateOrientation(duplicate)

			-- Much faster check interval (almost no delay)
			local function checkWaypointProgress()
				if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then
					isNavigating = false
					return
				end

				-- Distance check to target
				local distance = (target.Position - rootPart.Position).Magnitude

				-- Very liberal distance threshold (treat as arrived sooner)
				if distance < 4 then
					targetIndex = targetIndex + 1
					moveToNextTarget() -- Immediately move to next, no delay
					return
				else
					-- Update orientation again
					DuplicateManager.UpdateDuplicateOrientation(duplicate)

					-- Continue checking but with minimal delay
					task.delay(0.01, checkWaypointProgress)
				end
			end

			-- Start checking progress with minimal delay
			task.delay(0.01, checkWaypointProgress)
		end

		-- Start moving
		moveToNextTarget()
	end

	-- Path computation function
	computeAndFollowPath = function()
		if isNavigating then return end
		if not humanoid.Parent or not rootPart.Parent then return end

		-- Check for stuck state occasionally
		if tick() % 2 < 0.1 then 
			checkIfStuck()
		end

		local currentPos = rootPart.Position

		-- Handle stuck state
		if isStuck then
			isStuck = false
			stuckTimer = 0

			local escapePoint = findValidDestination(currentPos, 10)
			if escapePoint then
				finalDestination = escapePoint
			else
				local randomAngle = math.random() * math.pi * 2
				local escapeVector = Vector3.new(
					math.cos(randomAngle) * 3,
					0,
					math.sin(randomAngle) * 3
				)

				humanoid:MoveTo(currentPos + escapeVector)
				task.wait(0.2)
				task.spawn(computeAndFollowPath)
				return
			end
		end

		-- Try to compute path
		local pathSuccess = false
		pcall(function()
			path:ComputeAsync(currentPos, finalDestination)
			pathSuccess = (path.Status == Enum.PathStatus.Success)
		end)

		-- Find new destination if needed
		if not pathSuccess then
			local newDest = findValidDestination(currentPos, 6)
			if newDest then
				finalDestination = newDest
				pcall(function()
					path:ComputeAsync(currentPos, finalDestination)
					pathSuccess = (path.Status == Enum.PathStatus.Success)
				end)
			else
				task.wait(0.2)
				task.spawn(computeAndFollowPath)
				return
			end
		end

		-- Process successful path
		if path.Status == Enum.PathStatus.Success then
			failedAttempts = 0
			local waypoints = path:GetWaypoints()

			-- Visualize path (minimal to reduce overhead)
			for i = 2, #waypoints, 3 do -- Show every third waypoint
				local color = "Bright blue"
				if waypoints[i].Action == Enum.PathWaypointAction.Jump then
					color = "Lime green"
				end
				createWaypointMarker(waypoints[i].Position, color, 0.5)
			end

			-- Navigate waypoints without stops
			navigateWaypoints(waypoints)
		else
			-- Path computation failed
			failedAttempts = failedAttempts + 1

			if failedAttempts >= MAX_ATTEMPTS then
				local newDest = findValidDestination(currentPos, 8)
				if newDest then
					finalDestination = newDest
				end
				failedAttempts = 0
			end

			task.wait(0.2)
			task.spawn(computeAndFollowPath)
		end
	end

	-- Start the pathfinding process
	task.spawn(computeAndFollowPath)
end

-- Create a new Motor6D between two parts
function DuplicateManager.CreateMotor6D(name, part0, part1)
	-- Find the original joint to copy properties from
	local originalJoint = nil
	local character = part0.Parent
	for _, joint in ipairs(character:GetDescendants()) do
		if joint:IsA("Motor6D") and joint.Name == name then
			originalJoint = joint
			break
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1

	-- Copy properties from original joint if found
	if originalJoint then
		motor.C0 = originalJoint.C0
		motor.C1 = originalJoint.C1
		motor.CurrentAngle = originalJoint.CurrentAngle
		motor.DesiredAngle = originalJoint.DesiredAngle
		motor.MaxVelocity = originalJoint.MaxVelocity
	else
		motor.C0 = CFrame.new()
		motor.C1 = CFrame.new()
	end

	motor.Parent = part0
	return motor
end

-- Destroy all Motor6Ds and WeldConstraints in a model
function DuplicateManager.DestroyAllJoints(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("Motor6D") or item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end
end

-- Recreate character joints based on rig type
function DuplicateManager.RecreateCharacterJoints(model)
	local humanoid = model:FindFirstChild("Humanoid")
	if not humanoid then return end

	local rigType = humanoid.RigType
	local root = model:FindFirstChild("HumanoidRootPart")

	local function createMotor6D(name, part0, part1)
		return DuplicateManager.CreateMotor6D(name, part0, part1)
	end

	if rigType == Enum.HumanoidRigType.R15 then
		local upperTorso = model:FindFirstChild("UpperTorso")
		local lowerTorso = model:FindFirstChild("LowerTorso")
		local head = model:FindFirstChild("Head")
		local leftUpperArm = model:FindFirstChild("LeftUpperArm")
		local leftLowerArm = model:FindFirstChild("LeftLowerArm")
		local leftHand = model:FindFirstChild("LeftHand")
		local rightUpperArm = model:FindFirstChild("RightUpperArm")
		local rightLowerArm = model:FindFirstChild("RightLowerArm")
		local rightHand = model:FindFirstChild("RightHand")
		local leftUpperLeg = model:FindFirstChild("LeftUpperLeg")
		local leftLowerLeg = model:FindFirstChild("LeftLowerLeg")
		local leftFoot = model:FindFirstChild("LeftFoot")
		local rightUpperLeg = model:FindFirstChild("RightUpperLeg")
		local rightLowerLeg = model:FindFirstChild("RightLowerLeg")
		local rightFoot = model:FindFirstChild("RightFoot")

		if root and lowerTorso then createMotor6D("Root", root, lowerTorso) end
		if lowerTorso and upperTorso then createMotor6D("Waist", lowerTorso, upperTorso) end
		if upperTorso and head then createMotor6D("Neck", upperTorso, head) end
		if upperTorso and leftUpperArm then createMotor6D("LeftShoulder", upperTorso, leftUpperArm) end
		if leftUpperArm and leftLowerArm then createMotor6D("LeftElbow", leftUpperArm, leftLowerArm) end
		if leftLowerArm and leftHand then createMotor6D("LeftWrist", leftLowerArm, leftHand) end
		if upperTorso and rightUpperArm then createMotor6D("RightShoulder", upperTorso, rightUpperArm) end
		if rightUpperArm and rightLowerArm then createMotor6D("RightElbow", rightUpperArm, rightLowerArm) end
		if rightLowerArm and rightHand then createMotor6D("RightWrist", rightLowerArm, rightHand) end
		if lowerTorso and leftUpperLeg then createMotor6D("LeftHip", lowerTorso, leftUpperLeg) end
		if leftUpperLeg and leftLowerLeg then createMotor6D("LeftKnee", leftUpperLeg, leftLowerLeg) end
		if leftLowerLeg and leftFoot then createMotor6D("LeftAnkle", leftLowerLeg, leftFoot) end
		if lowerTorso and rightUpperLeg then createMotor6D("RightHip", lowerTorso, rightUpperLeg) end
		if rightUpperLeg and rightLowerLeg then createMotor6D("RightKnee", rightUpperLeg, rightLowerLeg) end
		if rightLowerLeg and rightFoot then createMotor6D("RightAnkle", rightLowerLeg, rightFoot) end
	else
		-- R6 joints
		local torso = model:FindFirstChild("Torso")
		local head = model:FindFirstChild("Head")
		local leftArm = model:FindFirstChild("Left Arm")
		local rightArm = model:FindFirstChild("Right Arm")
		local leftLeg = model:FindFirstChild("Left Leg")
		local rightLeg = model:FindFirstChild("Right Leg")

		if root and torso then createMotor6D("RootJoint", root, torso) end
		if torso and head then createMotor6D("Neck", torso, head) end
		if torso and leftArm then createMotor6D("Left Shoulder", torso, leftArm) end
		if torso and rightArm then createMotor6D("Right Shoulder", torso, rightArm) end
		if torso and leftLeg then createMotor6D("Left Hip", torso, leftLeg) end
		if torso and rightLeg then createMotor6D("Right Hip", torso, rightLeg) end
	end
end

-- Create a new instance of DuplicateManager
function DuplicateManager.new()
	local self = setmetatable({}, DuplicateManager)
	self.PlayerCooldowns = {}
	self.DUPLICATE_COOLDOWN = DUPLICATE_COOLDOWN
	return self
end

-- Create a duplicate
function DuplicateManager.CreateDuplicate(player, remoteEvent)
	local character = player.Character
	if not character then return end

	-- Create new model for duplicate
	local duplicate = Instance.new("Model")
	duplicate.Name = "Duplicate_" .. character.Name
	duplicate.Parent = workspace
	DuplicateManager.SetModelCollisionGroup(duplicate, "Duplicates")

	-- Clone HumanoidRootPart and maintain its orientation
	local originalRoot = character:FindFirstChild("HumanoidRootPart")
	if not originalRoot then return end

	local newRoot = originalRoot:Clone()
	newRoot.CFrame = originalRoot.CFrame
	newRoot.Parent = duplicate
	newRoot.CollisionGroup = "Duplicates"

	-- Clone Humanoid and copy properties
	local originalHumanoid = character:FindFirstChild("Humanoid")
	if not originalHumanoid then return end

	local newHumanoid = Instance.new("Humanoid")
	-- Copy important humanoid properties
	newHumanoid.HipHeight = originalHumanoid.HipHeight
	newHumanoid.AutoRotate = false
	newHumanoid.WalkSpeed = 18  -- Set to standard Roblox speed
	newHumanoid.JumpPower = originalHumanoid.JumpPower
	newHumanoid.MaxHealth = originalHumanoid.MaxHealth
	newHumanoid.Health = originalHumanoid.Health
	newHumanoid.DisplayDistanceType = originalHumanoid.DisplayDistanceType
	newHumanoid.RigType = originalHumanoid.RigType -- Preserve R6/R15 state
	newHumanoid.Parent = duplicate

	-- Clone character parts
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("MeshPart")) then
			if part.Name ~= "HumanoidRootPart" and not part:IsDescendantOf(character:FindFirstChild("PropModel")) then
				pcall(function()
					local newPart = part:Clone()
					newPart.CanCollide = false
					newPart.CollisionGroup = "Duplicates" 
					newPart.Parent = duplicate
				end)
			end
		end
	end

	-- Destroy all joints in duplicate
	DuplicateManager.DestroyAllJoints(duplicate)

	-- Recreate character joints
	DuplicateManager.RecreateCharacterJoints(duplicate)

	-- Handle PropModel
	local propModel = character:FindFirstChild("PropModel")
	if propModel then
		pcall(function()
			local newPropModel = propModel:Clone()

			-- Clear existing joints
			DuplicateManager.DestroyAllJoints(newPropModel)

			newPropModel.Parent = duplicate

			-- Create welds to root for prop parts
			for _, part in ipairs(newPropModel:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CollisionGroup = "Duplicates"
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = newRoot
					weld.Part1 = part
					weld.Parent = part
					part.CanCollide = false
				end
			end
		end)
	end

	-- Disable scripts in the duplicate
	pcall(function()
		for _, script in ipairs(duplicate:GetDescendants()) do
			if script:IsA("LocalScript") or script:IsA("Script") then
				script.Disabled = true
			end
		end
	end)

	-- Get the Humanoid and RootPart
	local humanoid = duplicate:FindFirstChild("Humanoid")
	local rootPart = duplicate:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then 
		warn("No humanoid or rootPart in duplicate")
		duplicate:Destroy()
		return
	end

	if humanoid and rootPart then
		DuplicateManager.StartContinuousPathfinding(duplicate, rootPart.Position)

		-- Start the random looking behavior
		DuplicateManager.SimulateRandomLooking(duplicate)
	end

	-- Set up fade out tween after lifetime
	task.delay(DUPLICATE_LIFETIME, function()
		if duplicate and duplicate.Parent then
			-- Tween all parts to transparent
			for _, part in pairs(duplicate:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("MeshPart") then
					TweenService:Create(part, 
						TweenInfo.new(0.5, Enum.EasingStyle.Linear),
						{Transparency = 1}
					):Play()
				end
			end

			-- Destroy after fade
			task.delay(0.5, function()
				if duplicate and duplicate.Parent then
					duplicate:Destroy()
				end
			end)
		end
	end)

	-- Play spawn effect
	if remoteEvent then
		remoteEvent:FireAllClients("DuplicateSpawned", duplicate)
	end

	return duplicate
end

-- Handle duplicate ability
function DuplicateManager:HandleDuplicateAbility(player, remoteEvent)
	if self.PlayerCooldowns[player.UserId] then return end

	-- Create two duplicates
	DuplicateManager.CreateDuplicate(player, remoteEvent)
	DuplicateManager.CreateDuplicate(player, remoteEvent)

	-- Set cooldown
	self.PlayerCooldowns[player.UserId] = true
	if remoteEvent then
		remoteEvent:FireClient(player, "DuplicateCooldown", self.DUPLICATE_COOLDOWN)
	end

	task.delay(self.DUPLICATE_COOLDOWN, function()
		self.PlayerCooldowns[player.UserId] = nil
		if remoteEvent then
			remoteEvent:FireClient(player, "DuplicateReady")
		end
	end)
end

-- Clean up when players leave
function DuplicateManager:CleanupPlayer(player)
	self.PlayerCooldowns[player.UserId] = nil
end

-- Setup for server initialization
function DuplicateManager:InitializeServer(players, remoteEvent)
	-- Setup collision groups
	DuplicateManager.SetupCollisionGroups()

	-- Connect to player added events
	players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			DuplicateManager.SetModelCollisionGroup(character, "Players")
			character:WaitForChild("Humanoid").Died:Connect(function()
				-- Optional: Add specific cleanup logic here if needed
			end)
		end)
	end)

	-- Set up existing players
	for _, player in ipairs(players:GetPlayers()) do
		if player.Character then
			DuplicateManager.SetModelCollisionGroup(player.Character, "Players")
		end
	end

	-- Connect player removal cleanup
	players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayer(player)
	end)
end

-- Return the module for use
return DuplicateManager