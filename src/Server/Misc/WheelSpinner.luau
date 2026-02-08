-- Hunter Selection Wheel
-- Place this in ServerScriptService.Misc.WheelSpinner

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Configuration
local WHEEL_PARENT_NAME = "Wheel" -- Parent container in workspace
local WHEEL_CENTER_NAME = "WheelCenter"
local WHEEL_PIECE_NAME = "WheelPiece"
local WHEEL_BORDER_NAME = "WheelBorder"
local SELECTOR_NAME = "Selector"

-- Speed control parameters
local INITIAL_SPEED = 2 -- Initial rotation speed in radians per second (HIGHER = FASTER)
local DECELERATION = 0.25 -- How quickly the wheel slows down (HIGHER = FASTER STOP)
local MIN_ROTATION_TIME = 5 -- Minimum seconds the wheel spins
local TOTAL_SPIN_TIME = 8 -- Maximum spin duration

-- Dynamic name update
local NAME_UPDATE_INTERVAL = 2 -- Seconds between automatic name updates

-- State
local WheelState = {
	initialized = false,
	wheelCenter = nil,
	wheelPieces = {},
	wheelBorders = {},
	spinning = false,
	votingOver = false,
	segmentAngle = 22.5, -- 360 / 16 segments
	playerMap = {}, -- Maps segment index to player
	nameUpdateConnection = nil, -- Connection for auto-updating names
	highlightedSegment = nil, -- Currently highlighted segment index
	defaultMaterial = Enum.Material.SmoothPlastic, -- Default wheel piece material
	selector = nil, -- Reference to the selector part
	raycastParams = nil -- Pre-configured raycast parameters
}

-- NEW: Raycast-based segment detection (ACCURATE!)
local function GetCurrentWinningSegmentByRay()
	-- Make sure we have the selector reference
	if not WheelState.selector then
		-- Try to find it if we don't have it yet
		local wheelParent = workspace:FindFirstChild(WHEEL_PARENT_NAME)
		if wheelParent then
			WheelState.selector = wheelParent:FindFirstChild(SELECTOR_NAME)
		end

		-- If still not found, fall back to mathematical method
		if not WheelState.selector then
			warn("Selector not found, falling back to math method")
			return GetCurrentWinningSegment()
		end
	end

	-- Initialize raycast parameters if needed
	if not WheelState.raycastParams then
		WheelState.raycastParams = RaycastParams.new()
		WheelState.raycastParams.FilterType = Enum.RaycastFilterType.Include

		-- Create whitelist of only wheel pieces
		local wheelPiecesInstances = {}
		for _, piece in ipairs(WheelState.wheelPieces) do
			table.insert(wheelPiecesInstances, piece)
		end
		WheelState.raycastParams.FilterDescendantsInstances = wheelPiecesInstances
	end

	-- Cast ray from selector downward into the wheel
	local selectorCFrame = WheelState.selector.CFrame
	local rayOrigin = selectorCFrame.Position
	local rayDirection = Vector3.new(-15, 0, 0) -- Pointing in -X direction (into wheel)

	local rayResult = workspace:Raycast(rayOrigin, rayDirection, WheelState.raycastParams)

	-- If we hit a wheel piece, find its index
	if rayResult and rayResult.Instance then
		for i, piece in ipairs(WheelState.wheelPieces) do
			if rayResult.Instance == piece then
				return i
			end
		end
	end

	-- Fallback to the mathematical method if raycast fails
	return GetCurrentWinningSegment()
end

-- Calculate the winning segment based on current wheel rotation (FALLBACK)
local function GetCurrentWinningSegment()
	-- Get the current rotation on X axis (pitch) from the CFrame
	local _, rotation = WheelState.wheelCenter.CFrame:ToEulerAnglesXYZ()

	-- Convert to degrees and normalize to 0-360
	local degrees = math.deg(rotation) % 360

	-- Each segment is 22.5 degrees (360 / 16)
	-- Calculate which segment is at the top (under the selector)
	local segmentIndex = math.floor(degrees / WheelState.segmentAngle) + 1

	-- Adjust for clockwise rotation
	segmentIndex = 17 - segmentIndex

	-- Handle wrap-around
	if segmentIndex > 16 then
		segmentIndex = segmentIndex - 16
	elseif segmentIndex <= 0 then
		segmentIndex = segmentIndex + 16
	end

	return segmentIndex
end

-- Highlight the current segment and reset previous one
local function UpdateHighlightedSegment(segmentIndex)
	-- If same segment, no change needed
	if WheelState.highlightedSegment == segmentIndex then
		return
	end

	-- Reset previous highlighted segment
	if WheelState.highlightedSegment and WheelState.wheelPieces[WheelState.highlightedSegment] then
		WheelState.wheelPieces[WheelState.highlightedSegment].Material = WheelState.defaultMaterial
	end

	-- Highlight new segment
	if segmentIndex and WheelState.wheelPieces[segmentIndex] then
		WheelState.wheelPieces[segmentIndex].Material = Enum.Material.Neon
		WheelState.highlightedSegment = segmentIndex
	else
		WheelState.highlightedSegment = nil
	end
end

-- Create winner celebration effect (blinking)
local function CelebrateWinner(segmentIndex)
	if not segmentIndex or not WheelState.wheelPieces[segmentIndex] then
		return
	end

	local winnerPiece = WheelState.wheelPieces[segmentIndex]

	-- Blink 10 times
	for i = 1, 10 do
		-- Toggle material
		if i % 2 == 0 then
			winnerPiece.Material = WheelState.defaultMaterial
		else
			winnerPiece.Material = Enum.Material.Neon
		end

		-- Wait 0.5 seconds
		wait(0.5)
	end

	-- Set final state to Neon
	winnerPiece.Material = Enum.Material.Neon
end

-- Initialize the wheel by finding parts and creating welds
local function InitializeWheel()
	-- Find the wheel parent container
	local wheelParent = workspace:FindFirstChild(WHEEL_PARENT_NAME)
	if not wheelParent then
		warn("Wheel parent container not found in Workspace!")
		return false
	end

	-- Find the wheel center within the parent
	local wheelCenter = wheelParent:FindFirstChild(WHEEL_CENTER_NAME)
	if not wheelCenter then
		warn("WheelCenter not found in " .. WHEEL_PARENT_NAME .. "!")
		return false
	end

	-- Find the selector
	local selector = wheelParent:FindFirstChild(SELECTOR_NAME)
	if not selector then
		warn("Selector not found in " .. WHEEL_PARENT_NAME .. "!")
		-- Continue anyway, we'll use mathematical method as fallback
	else
		WheelState.selector = selector
	end

	-- Find all wheel pieces in the parent
	local wheelPieces = {}
	local wheelBorders = {}

	for _, child in pairs(wheelParent:GetDescendants()) do
		if child:IsA("BasePart") then
			if child.Name == WHEEL_PIECE_NAME then
				table.insert(wheelPieces, child)
			elseif child.Name == WHEEL_BORDER_NAME then
				table.insert(wheelBorders, child)
			end
		end
	end

	-- Store original CFrames and anchored states
	local originalStates = {}

	-- Remember the original state of the wheel center
	originalStates[wheelCenter] = {
		CFrame = wheelCenter.CFrame,
		Anchored = wheelCenter.Anchored
	}

	-- Store states of all pieces
	for _, piece in pairs(wheelPieces) do
		originalStates[piece] = {
			CFrame = piece.CFrame,
			Anchored = piece.Anchored
		}
	end

	-- Store states of all borders
	for _, border in pairs(wheelBorders) do
		originalStates[border] = {
			CFrame = border.CFrame,
			Anchored = border.Anchored
		}
	end

	-- Temporarily unanchor everything for welding
	wheelCenter.Anchored = false

	-- Create welds for all wheel pieces
	for i, piece in ipairs(wheelPieces) do
		piece.Anchored = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = wheelCenter
		weld.Part1 = piece
		weld.Parent = wheelCenter
		weld.Name = "Weld_Piece_" .. i
	end

	-- Create welds for all wheel borders
	for i, border in ipairs(wheelBorders) do
		border.Anchored = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = wheelCenter
		weld.Part1 = border
		weld.Parent = wheelCenter
		weld.Name = "Weld_Border_" .. i
	end

	-- Restore original positions
	for part, state in pairs(originalStates) do
		part.CFrame = state.CFrame
	end

	-- Re-anchor the center (all welded parts will move with it)
	wheelCenter.Anchored = true

	-- Store wheel state
	WheelState.wheelCenter = wheelCenter
	WheelState.wheelPieces = wheelPieces
	WheelState.wheelBorders = wheelBorders
	WheelState.initialized = true

	-- Start dynamic name updates
	StartDynamicNameUpdates()

	print("Wheel successfully initialized with " .. #wheelPieces .. " segments")
	return true
end

-- Update player names on the wheel
local function UpdateWheelNames()
	-- If voting is over, don't update names
	if WheelState.votingOver then
		return
	end

	local currentPlayers = Players:GetPlayers()

	-- If no players, nothing to do
	if #currentPlayers == 0 then
		return
	end

	-- Clear current player mappings
	WheelState.playerMap = {}

	-- Distribute players evenly across the 16 segments
	local playersPerSegment = math.floor(16 / #currentPlayers)
	local remainingSegments = 16 % #currentPlayers

	local segmentIndex = 1
	for i, player in ipairs(currentPlayers) do
		local segmentsForThisPlayer = playersPerSegment
		if i <= remainingSegments then
			segmentsForThisPlayer = segmentsForThisPlayer + 1
		end

		for j = 1, segmentsForThisPlayer do
			WheelState.playerMap[segmentIndex] = player
			segmentIndex = segmentIndex + 1
		end
	end

	-- Update the name labels on the wheel pieces
	for i, piece in ipairs(WheelState.wheelPieces) do
		local surfaceGui = piece:FindFirstChild("SurfaceGui")
		if surfaceGui then
			local nameHolder = surfaceGui:FindFirstChild("NameHolder")
			if nameHolder then
				local nameLabel = nameHolder:FindFirstChild("NameLabel")
				if nameLabel then
					local playerForSegment = WheelState.playerMap[i]
					if playerForSegment then
						nameLabel.Text = playerForSegment.Name
					else
						nameLabel.Text = "???"
					end
				end
			end
		end
	end
end

-- Start periodic name updates
function StartDynamicNameUpdates()
	-- Clear any existing connection
	if WheelState.nameUpdateConnection then
		WheelState.nameUpdateConnection:Disconnect()
		WheelState.nameUpdateConnection = nil
	end

	-- Create a new update loop with a timer
	local lastUpdate = 0
	WheelState.nameUpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Don't update if spinning or if voting is over
		if WheelState.spinning or WheelState.votingOver then
			return
		end

		-- Only update periodically to save performance
		lastUpdate = lastUpdate + deltaTime
		if lastUpdate >= NAME_UPDATE_INTERVAL then
			UpdateWheelNames()
			lastUpdate = 0
		end
	end)
end

-- Stop dynamic name updates
local function StopDynamicNameUpdates()
	if WheelState.nameUpdateConnection then
		WheelState.nameUpdateConnection:Disconnect()
		WheelState.nameUpdateConnection = nil
		print("Stopped dynamic name updates")
	end
end

-- Set the voting status
local function SetVotingOver(isOver)
	WheelState.votingOver = isOver

	-- If voting is over, ensure names are finalized
	if isOver then
		UpdateWheelNames()
	end
end

-- Spin the wheel with manual speed control
local function SpinWheel()
	if not WheelState.initialized then
		warn("Wheel not initialized! Cannot spin.")
		return nil
	end

	if WheelState.spinning then
		print("Wheel is already spinning!")
		return nil
	end

	-- Mark voting as over to freeze names during spin
	SetVotingOver(true)
	WheelState.spinning = true

	-- Final update of names before spinning
	UpdateWheelNames()

	print("Starting wheel spin with initial speed " .. INITIAL_SPEED .. " radians/sec")

	-- Set up spinning with manual control
	local startTime = tick()
	local currentSpeed = INITIAL_SPEED
	local totalRotation = 0
	local lastTick = startTime

	-- Connection for the spinning animation
	local spinConnection
	spinConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local elapsed = currentTime - startTime
		local deltaTime = currentTime - lastTick
		lastTick = currentTime

		-- Calculate current speed based on deceleration
		if elapsed < MIN_ROTATION_TIME then
			-- Maintain top speed for minimum time
			currentSpeed = INITIAL_SPEED
		else
			-- Decelerate using cosine-based formula for smooth deceleration
			local timeRatio = (elapsed - MIN_ROTATION_TIME) / (TOTAL_SPIN_TIME - MIN_ROTATION_TIME)
			currentSpeed = INITIAL_SPEED * math.cos(timeRatio * math.pi/2)
		end

		-- Apply rotation for this frame
		local rotationThisFrame = currentSpeed * deltaTime
		totalRotation = totalRotation + rotationThisFrame

		-- Update wheel position
		WheelState.wheelCenter.CFrame = WheelState.wheelCenter.CFrame * CFrame.Angles(rotationThisFrame, 0, 0)

		-- ✅ FIXED: Use raycast method for accurate segment detection
		local currentSegment = GetCurrentWinningSegmentByRay()
		UpdateHighlightedSegment(currentSegment)

		-- Check if we're done spinning
		if elapsed >= TOTAL_SPIN_TIME then
			spinConnection:Disconnect()

			-- Determine winner using raycast
			local winningSegmentIndex = GetCurrentWinningSegmentByRay()
			local winner = WheelState.playerMap[winningSegmentIndex]

			if winner then
				print("------------------------")
				print("WHEEL SPIN RESULTS:")
				print("Winner selected: " .. winner.Name)
				print("Segment Index: " .. winningSegmentIndex)
				print("Total rotation: " .. string.format("%.2f", totalRotation) .. " radians (" .. 
					string.format("%.2f", totalRotation / (2 * math.pi)) .. " rotations)")
				print("------------------------")
			else
				warn("No winner found for segment " .. winningSegmentIndex)
			end

			-- Celebrate the winner with blinking effect
			spawn(function()
				CelebrateWinner(winningSegmentIndex)
			end)

			WheelState.spinning = false

			-- Signal completion
			WheelState.spinComplete = true
		end
	end)

	-- Wait for spin to complete
	while not WheelState.spinComplete do
		wait(0.1)
	end
	WheelState.spinComplete = false

	-- Return the winner using raycast
	local winningSegmentIndex = GetCurrentWinningSegmentByRay()
	return WheelState.playerMap[winningSegmentIndex]
end

-- Initialize wheel when script runs
wait(2) -- Wait for everything to load
InitializeWheel()

-- Export functions
return {
	InitializeWheel = InitializeWheel,
	SpinWheel = SpinWheel,
	SetVotingOver = SetVotingOver,
	GetCurrentWinningSegmentByRay = GetCurrentWinningSegmentByRay -- For debugging
}
