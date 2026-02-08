-- VotingSystem with Round Timer Addition
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Get the existing RemoteEvent
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Use the existing MapRepository
local MapRepository = require(script.Parent.Parent.Misc.MapRepository)
local WheelSpinner = require(script.Parent.Parent.Misc.WheelSpinner)
local PropSystem = require(script.Parent.Parent.PropSystem)
local PlayerManager = require(script.Parent.Parent.Player.PlayerManager)
local LobbyEffectsController = require(script.Parent.Parent.Misc.LobbyEffectsController)
local WheelEffectsController = require(script.Parent.Parent.Misc.WheelEffectsController)
local EnvironmentalPropHealthSystem = require(script.Parent.Parent.Misc.EnvironmentalPropHealth)

PropSystem.init()
WheelEffectsController:Initialize()
LobbyEffectsController:Initialize()
WheelEffectsController:IntegrateWithSpinner(WheelSpinner)

-- Configuration
local INTERMISSION_TIME = 10 -- Seconds for voting period
local MIN_PLAYERS_TO_START =  1 -- Minimum players needed
local ROUND_TIME = 60 -- Seconds for round time (1 minute)
local GRACE_PERIOD_TIME = 10 -- Seconds for grace period
local TRANSITION_DELAY = 0.5 -- Delay after UI closes before respawning

-- Player role constants
local ROLE_HUNTER = "Hunter"
local ROLE_PROP = "Prop"

-- Player role tracking
local PlayerRoles = {}

-- Game State
local GameState = {
	currentState = "Waiting", -- "Waiting", "Intermission", "GracePeriod", "Playing"
	isEnding = false,
	intermissionTime = INTERMISSION_TIME,
	roundTime = ROUND_TIME,
	gracePeriodTime = GRACE_PERIOD_TIME,
	voteOptions = {},
	votes = {
		[1] = 0,
		[2] = 0,
		[3] = 0
	},
	playerVotes = {}, -- {[playerId] = voteIndex}
	selectedHunter = nil,
	timerActive = false,
	pendingTransitions = {} -- Track players waiting for UI confirmation
}

local PropPingSystem = {
	enabled = true,
	pingIntervals = {20, 40}, -- Seconds into the round when pings occur
	lastPingTime = 0,
	nextPingTime = nil,
	notificationSent = false
}

-- Get all map keys
local function GetAllMapKeys()
	local keys = {}
	for key, _ in pairs(MapRepository) do
		table.insert(keys, key)
	end
	return keys
end

-- Randomly select map options
local function SelectRandomMapOptions()
	local allMaps = GetAllMapKeys()
	local selectedMaps = {}
	local usedIndices = {}

	-- Make sure we have enough maps in repository
	if #allMaps < 3 then
		warn("Not enough maps in repository! Adding duplicates.")
		while #allMaps < 3 do
			table.insert(allMaps, allMaps[1])
		end
	end

	-- Select 3 unique random maps
	while #selectedMaps < 3 do
		local randomIndex = math.random(1, #allMaps)
		if not table.find(usedIndices, randomIndex) then
			table.insert(usedIndices, randomIndex)
			table.insert(selectedMaps, allMaps[randomIndex])
		end
	end

	return selectedMaps
end

-- Update vote amount labels on the physical vote parts
function UpdateVoteAmountLabels()
	-- Find the vote parts
	local voteOne = workspace:FindFirstChild("VoteOne")
	local voteTwo = workspace:FindFirstChild("VoteTwo")
	local voteThree = workspace:FindFirstChild("VoteThree")

	local voteParts = {
		[1] = voteOne,
		[2] = voteTwo,
		[3] = voteThree
	}

	-- Update labels
	for index, votePart in pairs(voteParts) do
		if votePart then
			local TouchPart = votePart.TouchPart
			local voteAmount = TouchPart:FindFirstChild("VoteAmount")
			if voteAmount then
				local voteAmountLabel = voteAmount:FindFirstChild("VoteAmountFrame"):FindFirstChild("VoteAmountLabel")
				if voteAmountLabel then
					-- Just update the text directly on the server
					voteAmountLabel.Text = tostring(GameState.votes[index])

					-- Only trigger animation if the vote count actually changed (not during initialization)
					if GameState.votes[index] > 0 then
						-- Tell clients to animate this specific vote counter
						-- Include the previous value and new value for the animation
						local oldValue = GameState.votes[index] - 1
						if oldValue < 0 then oldValue = 0 end

						print("Sending AnimateVoteCounter for " .. votePart.Name .. ": " .. oldValue .. " -> " .. GameState.votes[index])
						RemoteEvent:FireAllClients("AnimateVoteCounter", index, oldValue, GameState.votes[index])
					end

					print("Updated " .. votePart.Name .. " vote count to " .. GameState.votes[index])
				else
					warn("VoteAmountLabel not found in " .. votePart.Name)
				end
			else
				warn("VoteAmount not found in " .. votePart.Name)
			end
		end
	end

	-- Update lighting based on current vote counts
	LobbyEffectsController:UpdateVoteCounts(GameState.votes)
end


-- Function to update map visuals
local function UpdateMapVisuals()
	-- Get vote spots in the workspace
	local voteOne = workspace:FindFirstChild("VoteOne")
	local voteTwo = workspace:FindFirstChild("VoteTwo")
	local voteThree = workspace:FindFirstChild("VoteThree")

	if not voteOne or not voteTwo or not voteThree then
		warn("Vote spots not found in workspace")
		return
	end

	-- Update each vote spot with map info
	for i, mapKey in ipairs(GameState.voteOptions) do
		local voteSpot = workspace:FindFirstChild("Vote" .. i)
		if voteSpot then
			local mapInfo = MapRepository[mapKey]
			if mapInfo then
				-- Update map image
				local mapHolder = voteSpot:FindFirstChild("MapHolder")
				if mapHolder and mapHolder:FindFirstChild("MapHolderUI") then
					local mapVoteHolder = mapHolder.MapHolderUI:FindFirstChild("MapVoteHolder")
					if mapVoteHolder then
						local imageLabel = mapVoteHolder:FindFirstChild("ImageLabel")
						if imageLabel then
							imageLabel.Image = mapInfo.imageid
						end

						local nameLabel = mapVoteHolder:FindFirstChild("NameLabel")
						if nameLabel then
							nameLabel.Text = mapInfo.displayName
						end
					end
				end
			end
		end
	end

	-- Reset vote amounts
	GameState.votes = {0, 0, 0}
	GameState.playerVotes = {}
	UpdateVoteAmountLabels()
end

function StartIntermission()
	-- Cancel any active timer first
	GameState.timerActive = false
	wait(0.1)  -- Brief delay to ensure any running timer loop exits

	GameState.currentState = "Intermission"
	GameState.intermissionTime = INTERMISSION_TIME
	GameState.voteOptions = SelectRandomMapOptions()
	GameState.timerActive = true  -- Set flag to true before starting new timer

	-- Update map visuals in workspace
	UpdateMapVisuals()

	-- Create map info for client
	local mapInfo = {}
	for i, mapKey in ipairs(GameState.voteOptions) do
		local map = MapRepository[mapKey]
		mapInfo[i] = {
			displayName = map.displayName,
			imageid = map.imageid,
			mapKey = mapKey
		}
	end

	for i, mapKey in ipairs(GameState.voteOptions) do
		--print("  " .. i .. ": " .. MapRepository[mapKey].displayName)
	end

	-- Notify all clients of intermission start using your RemoteEvent pattern
	RemoteEvent:FireAllClients("StartIntermission", mapInfo, INTERMISSION_TIME)

	-- Start intermission timer with flag check
	spawn(function()
		local isThisTimerActive = true  -- Local flag for this specific timer instance

		-- Initial timer update
		RemoteEvent:FireAllClients("UpdateTimer", GameState.intermissionTime)

		-- Timer loop with double safety check
		while GameState.intermissionTime > 0 and 
			GameState.currentState == "Intermission" and
			GameState.timerActive and
			isThisTimerActive do

			-- Check if timer was deactivated by another call
			if not GameState.timerActive then
				isThisTimerActive = false
				break
			end

			wait(1)
			GameState.intermissionTime = GameState.intermissionTime - 1
			RemoteEvent:FireAllClients("UpdateTimer", GameState.intermissionTime)
		end

		-- Only end intermission if this is still the active timer
		if GameState.currentState == "Intermission" and isThisTimerActive then
			EndIntermission()
		end
	end)

	-- Start the voting panel lighting effects
	LobbyEffectsController:StartIdleEffects()

	-- Start wheel idle effects too
	WheelEffectsController:StartIdleEffects()
end

-- Function to load a map from repository
local function LoadMap(mapKey)
	local mapData = MapRepository[mapKey]
	if not mapData then
		warn("Map not found in repository: " .. mapKey)
		return false
	end


	-- Remove any existing active map
	local existingMap = workspace:FindFirstChild("ActiveMap")
	if existingMap then
		existingMap:Destroy()
	end

	EnvironmentalPropHealthSystem.clearAllHealthData()

	-- Clone the map from storage to workspace
	local mapModel = mapData.mapPath:Clone()
	mapModel.Parent = workspace
	mapModel.Name = "ActiveMap"

	return mapModel
end

-- Function to assign player roles
local function AssignPlayerRoles(hunter)
	-- Reset roles
	PlayerRoles = {}

	-- Assign hunter role to the selected player
	PlayerRoles[hunter.UserId] = ROLE_HUNTER
	hunter:SetAttribute("Role", "Hunter")  -- Set attribute on server

	-- Assign prop role to all other players
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= hunter then
			PlayerRoles[player.UserId] = ROLE_PROP
			player:SetAttribute("Role", "Prop")  -- Set attribute on server
		end
	end

	-- Print out the roles
	print("=== PLAYER ROLES ===")
	for userId, role in pairs(PlayerRoles) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			print(player.Name .. ": " .. role)
		end
	end
	print("====================")

	-- Notify clients about their roles
	for _, player in ipairs(Players:GetPlayers()) do
		local role = PlayerRoles[player.UserId]
		if role then
			RemoteEvent:FireClient(player, "RoleAssigned", role)
		end
	end
end

-- Function to teleport players to spawn
local function TeleportPlayersToSpawn()
	-- Find the player_spawn part in the active map
	local activeMap = workspace:FindFirstChild("ActiveMap")
	if not activeMap then
		warn("No active map found for teleportation")
		return
	end

	local spawnPoint = activeMap:FindFirstChild("player_spawn")
	if not spawnPoint then
		warn("player_spawn not found in active map")
		return
	end

	-- Teleport all players to the spawn point
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			character:SetPrimaryPartCFrame(spawnPoint.CFrame + Vector3.new(0, 3, 0))
		end
	end
end

-- Function to handle players with pending transitions when round ends
local function HandlePendingTransitions()
	-- Called when round ends to handle any players with pending transitions
	for playerId, data in pairs(GameState.pendingTransitions) do
		local player = Players:GetPlayerByUserId(playerId)
		if player then
			-- Player started transition but round ended before completion
			-- Reset flags and respawn to lobby
			player:SetAttribute("TransitionToHunter", false)
			player:SetAttribute("ManualRespawn", false)

			-- Remove from pending transitions
			GameState.pendingTransitions[playerId] = nil

			-- Respawn the player in the lobby
			if player.Character == nil or player.Character.Parent == nil then
				print("loading char")
				player:LoadCharacter()
			end
		end
	end
end

function EndRound(hunterWon)
	-- Set the ending flag immediately to prevent new transitions
	GameState.isEnding = true

	-- Show transition screen FIRST before any other changes
	RemoteEvent:FireAllClients("RoundEnding")

	-- Add delay to ensure transition screen has time to appear
	task.wait(1)

	-- Determine who won and announce it after screen appears
	if hunterWon ~= nil then
		local winMessage = hunterWon and "Hunter wins!" or "Props win!"
		print(winMessage)
		RemoteEvent:FireAllClients("RoundEndAnnouncement", winMessage)
	end

	-- Handle any players who were in the middle of transitioning
	HandlePendingTransitions()

	-- Reset all players (respawn them to lobby)
	for _, player in ipairs(Players:GetPlayers()) do
		-- Clear any transition flags
		if player:GetAttribute("TransitionToHunter") then
			player:SetAttribute("TransitionToHunter", false)
		end

		-- Reset ManualRespawn flag to allow LoadCharacter to work
		if player:GetAttribute("ManualRespawn") then
			player:SetAttribute("ManualRespawn", false)
		end

		-- Use LoadCharacter to reset the player
		player:LoadCharacter()

		-- Make sure they're in the default waiting state
		RemoteEvent:FireClient(player, "DisableFirstPerson")
	end

	-- Give time for respawns to complete
	task.wait(0.5)

	-- Clean up any existing map AFTER players have respawned
	local existingMap = workspace:FindFirstChild("ActiveMap")
	if existingMap then
		existingMap:Destroy()
	end

	-- Reset roles
	PlayerRoles = {}
	GameState.selectedHunter = nil

	-- Change state to a transitional state first to prevent GameLoop from interfering
	GameState.currentState = "EndingRound"

	-- Reset any active timers
	GameState.timerActive = false

	-- Keep transition screen showing a bit longer to ensure smooth experience
	task.wait(1)

	-- Tell clients to hide the transition screen now that players are in lobby
	RemoteEvent:FireAllClients("ReturnedToLobby")

	-- Check if we have enough players to start a new round
	if #Players:GetPlayers() >= MIN_PLAYERS_TO_START then
		-- Start a new intermission after a short delay
		wait(3)
		StartIntermission()
	else
		print("Waiting for more players to join...")
		-- Only now change to "Waiting" if we're not starting a new round
		GameState.currentState = "Waiting"
		RemoteEvent:FireAllClients("WaitingForPlayers")
	end

	-- Reset the ending flag
	GameState.isEnding = false
end


local function FreezeHunter(hunter, freeze)
	if not hunter or not hunter.Character then return end

	local humanoid = hunter.Character:FindFirstChild("Humanoid")
	local rootPart = hunter.Character:FindFirstChild("HumanoidRootPart")

	if humanoid and rootPart then
		if freeze then
			-- Store original speed for later
			rootPart:SetAttribute("OriginalWalkSpeed", humanoid.WalkSpeed)
			rootPart:SetAttribute("OriginalJumpPower", humanoid.JumpPower)

			-- Freeze movement
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0

			-- Notify the client they're frozen
			RemoteEvent:FireClient(hunter, "HunterFrozen", GRACE_PERIOD_TIME)
		else
			-- Restore movement
			local originalWalkSpeed = rootPart:GetAttribute("OriginalWalkSpeed") or 16
			local originalJumpPower = rootPart:GetAttribute("OriginalJumpPower") or 50

			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.JumpPower = originalJumpPower

			-- Notify the client they're unfrozen
			RemoteEvent:FireClient(hunter, "HunterUnfrozen")
		end
	end
end

local function updatePropCount()
	local propsCount = 0
	for userId, role in pairs(PlayerRoles) do
		if role == ROLE_PROP then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				propsCount = propsCount + 1
			end
		end
	end

	-- Broadcast prop count to all clients
	RemoteEvent:FireAllClients("UpdatePropCount", propsCount)
end

local function checkPropPing(currentTime)
	if not PropPingSystem.enabled then return end

	-- Don't ping during grace period
	if GameState.currentState ~= "Playing" then 
		PropPingSystem.nextPingTime = nil
		PropPingSystem.notificationSent = false
		return 
	end

	-- Calculate how many seconds into the round we are
	local roundElapsedTime = ROUND_TIME - currentTime

	-- Find the next ping time if not already set
	if PropPingSystem.nextPingTime == nil then
		for _, pingTime in ipairs(PropPingSystem.pingIntervals) do
			if roundElapsedTime <= pingTime then
				PropPingSystem.nextPingTime = pingTime
				PropPingSystem.notificationSent = false
				break
			end
		end
	end

	-- If next ping time is set, check if we need to notify
	if PropPingSystem.nextPingTime ~= nil then
		-- Check if we're 5 seconds before the ping and haven't notified yet
		if math.abs(roundElapsedTime - PropPingSystem.nextPingTime) <= 5 and
			math.abs(roundElapsedTime - PropPingSystem.nextPingTime) > 4 and
			not PropPingSystem.notificationSent then
			-- Notify clients that a ping is coming
			RemoteEvent:FireAllClients("PingNotification", 5)
			PropPingSystem.notificationSent = true
		end

		-- Check if we just crossed this ping interval
		if math.abs(roundElapsedTime - PropPingSystem.nextPingTime) < 1 and 
			os.time() - PropPingSystem.lastPingTime > 5 then
			-- Update last ping time
			PropPingSystem.lastPingTime = os.time()

			-- Reset tracking for next ping
			PropPingSystem.nextPingTime = nil
			PropPingSystem.notificationSent = false

			-- Call the ping function from PropHealthSystem
			local PropHealthSystem = require(script.Parent.Parent.PropHealthSystem)
			PropHealthSystem.pingAllProps()

			-- Notify players about ping execution
			RemoteEvent:FireAllClients("PingExecute")
		end
	end
end

local function StartRoundTimer()
	-- Start with grace period
	GameState.currentState = "GracePeriod"
	GameState.gracePeriodTime = GRACE_PERIOD_TIME

	-- Freeze the hunter
	if GameState.selectedHunter then
		FreezeHunter(GameState.selectedHunter, true)
	end

	-- Notify all clients that grace period has started
	RemoteEvent:FireAllClients("GracePeriodStarted", GRACE_PERIOD_TIME)

	-- Start grace period timer
	spawn(function()
		-- Initial timer update
		RemoteEvent:FireAllClients("UpdateGracePeriodTimer", GameState.gracePeriodTime)

		-- Timer loop
		while GameState.gracePeriodTime > 0 and GameState.currentState == "GracePeriod" do
			wait(1)
			GameState.gracePeriodTime = GameState.gracePeriodTime - 1

			-- Update clients
			RemoteEvent:FireAllClients("UpdateGracePeriodTimer", GameState.gracePeriodTime)

			-- Broadcast announcements at specific times
			if GameState.gracePeriodTime == 10 then
				RemoteEvent:FireAllClients("RoundAnnouncement", "10 seconds until hunters are released!")
			elseif GameState.gracePeriodTime <= 5 and GameState.gracePeriodTime > 0 then
				RemoteEvent:FireAllClients("RoundAnnouncement", tostring(GameState.gracePeriodTime))
			end
		end

		-- If we're still in grace period state when timer ends
		if GameState.currentState == "GracePeriod" then
			EndGracePeriod()
		end
	end)
end


function EndIntermission()
	-- Find the winning map
	local highestVotes = 0
	local winningMapIndex = 1

	for i, votes in ipairs(GameState.votes) do
		if votes > highestVotes then
			highestVotes = votes
			winningMapIndex = i
		end
	end

	-- Celebrate the winning panel
	LobbyEffectsController:CelebrateWinningPanel(winningMapIndex)

	-- Wait for celebration to finish before continuing
	wait(2)

	-- In case of a tie, the selection stays as is (first highest wins)
	local winningMapKey = GameState.voteOptions[winningMapIndex]
	local winningMap = MapRepository[winningMapKey]

	-- Notify clients about the selected map
	RemoteEvent:FireAllClients("MapSelected", winningMapKey, winningMap.displayName)

	-- End the intermission
	GameState.currentState = "GracePeriod" 

	-- Signal clients about game start
	RemoteEvent:FireAllClients("StartGame")

	-- Spin the wheel to select a hunter - PLAYERS SHOULD SEE THIS
	wait(3) -- Keep original delay to ensure wheel is visible
	local selectedHunter = WheelSpinner.SpinWheel()

	if not selectedHunter then
		print("No hunter selected from wheel spin!")
		-- Fallback: select random player
		local players = Players:GetPlayers()
		if #players > 0 then
			selectedHunter = players[math.random(1, #players)]
			print("Randomly selected hunter: " .. selectedHunter.Name)
		else
			warn("No players available to be hunter!")
			return
		end
	else
		print("Selected hunter: " .. selectedHunter.Name)
	end

	-- Store selected hunter in GameState
	GameState.selectedHunter = selectedHunter

	-- NOW show transition screen AFTER wheel is done spinning
	RemoteEvent:FireAllClients("StartTeleportTransition")

	-- Short delay to ensure transition screen appears
	wait(1)

	-- LOAD THE MAP while transition screen is active
	local mapModel = LoadMap(winningMapKey)
	if not mapModel then
		warn("Failed to load map: " .. winningMapKey)
		return
	end

	-- ASSIGN ROLES while transition screen is active
	AssignPlayerRoles(selectedHunter)

	-- Shorter delay since we're loading with transition screen
	wait(2) -- Reduced from 5 seconds

	-- TELEPORT PLAYERS
	TeleportPlayersToSpawn()

	-- Allow time for players to orient themselves before prop transformation
	task.delay(3, function()
		print("Starting auto-transformation of props...")
		local transformedCount = PropSystem.autoTransformAllProps(PlayerRoles)
		print("Successfully transformed " .. transformedCount .. " players into props")
	end)

	-- Start grace period timer
	StartRoundTimer()

	print("Game has officially started with grace period!")
end


function EndGracePeriod()
	print("Grace period ended - releasing hunter!")

	-- Unfreeze the hunter
	if GameState.selectedHunter then
		FreezeHunter(GameState.selectedHunter, false)
	end

	-- Now set up hunter's weapons
	if GameState.selectedHunter then
		SetupHunterLoadout(GameState.selectedHunter)
	end

	-- Update game state
	GameState.currentState = "Playing"

	-- Notify all clients that the main round has started
	RemoteEvent:FireAllClients("MainRoundStarted", ROUND_TIME)

	-- NEW: Send initial prop count
	updatePropCount()

	-- Start main round timer
	GameState.roundTime = ROUND_TIME

	-- Start timer thread
	GameState.roundTime = ROUND_TIME

	-- Start timer thread
	spawn(function()
		-- Initial timer update
		RemoteEvent:FireAllClients("UpdateRoundTimer", GameState.roundTime)

		-- Timer loop
		while GameState.roundTime > 0 and GameState.currentState == "Playing" do
			wait(1)
			GameState.roundTime = GameState.roundTime - 1

			-- Format time as MM:SS
			local minutes = math.floor(GameState.roundTime / 60)
			local seconds = GameState.roundTime % 60
			local formattedTime = string.format("%01d:%02d", minutes, seconds)

			-- Update clients
			RemoteEvent:FireAllClients("UpdateRoundTimer", GameState.roundTime, formattedTime)

			-- Broadcast announcements at specific times
			if GameState.roundTime == 30 then
				RemoteEvent:FireAllClients("RoundAnnouncement", "30 seconds remaining!")
			elseif GameState.roundTime == 10 then
				RemoteEvent:FireAllClients("RoundAnnouncement", "10 seconds remaining!")
			elseif GameState.roundTime <= 5 and GameState.roundTime > 0 then
				RemoteEvent:FireAllClients("RoundAnnouncement", tostring(GameState.roundTime))
			end

			-- Check for prop pings at every tick
			checkPropPing(GameState.roundTime)
		end

		-- If we're still in playing state when timer ends
		if GameState.currentState == "Playing" then
			-- Set ending flag first
			GameState.isEnding = true

			-- End the round with Props win condition
			local hunterWon = false
			EndRound(hunterWon)
		end
	end)
end


-- Handle player voting
function HandleVote(player, voteIndex)
	-- Validate vote
	if GameState.currentState ~= "Intermission" then 
		return 
	end

	if not voteIndex or voteIndex < 1 or voteIndex > 3 then 
		print(player.Name .. " attempted to vote with invalid index: " .. tostring(voteIndex))
		return 
	end

	local playerId = player.UserId
	local mapKey = GameState.voteOptions[voteIndex]

	-- Check if player is voting for the same option they already voted for
	if GameState.playerVotes[playerId] == voteIndex then
		print(player.Name .. " tried to vote for the same option again - ignoring")
		return -- Skip processing this vote since it's the same as their current vote
	end

	-- If player already voted for a different option, remove their previous vote
	if GameState.playerVotes[playerId] then
		local previousVote = GameState.playerVotes[playerId]
		GameState.votes[previousVote] = GameState.votes[previousVote] - 1
		print(player.Name .. " changed vote from option " .. previousVote .. " to option " .. voteIndex)
	else
		print(player.Name .. " voted for option " .. voteIndex .. " (" .. MapRepository[mapKey].displayName .. ")")
	end

	-- Record new vote
	GameState.playerVotes[playerId] = voteIndex
	GameState.votes[voteIndex] = GameState.votes[voteIndex] + 1

	-- Print current vote totals
	print("Current vote totals: " .. GameState.votes[1] .. ", " .. GameState.votes[2] .. ", " .. GameState.votes[3])

	-- Update vote amount labels
	UpdateVoteAmountLabels()

	-- Update all clients with new vote counts
	RemoteEvent:FireAllClients("UpdateVotes", GameState.votes)

	-- Notify the player specifically about their vote
	RemoteEvent:FireClient(player, "PlayerVoted", voteIndex)

	-- Then highlight the voted panel
	LobbyEffectsController:HighlightVotedPanel(voteIndex)

	-- Update all panels based on vote counts
	LobbyEffectsController:UpdateVoteCounts(GameState.votes)
end

-- Setup TouchPart voting
local function SetupTouchParts()
	-- Wait for the vote parts to be available in workspace
	local voteOne = workspace:WaitForChild("VoteOne", 10)
	local voteTwo = workspace:WaitForChild("VoteTwo", 10)
	local voteThree = workspace:WaitForChild("VoteThree", 10)

	local voteParts = {
		[voteOne] = 1,
		[voteTwo] = 2,
		[voteThree] = 3
	}

	-- Connect touch events for each part
	for votePart, voteIndex in pairs(voteParts) do
		local touchPart = votePart:FindFirstChild("TouchPart")
		if touchPart then

			-- Use a debounce system to prevent multiple votes from one touch
			local touching = {}

			touchPart.Touched:Connect(function(hit)
				-- Check if a player touched the part
				local character = hit.Parent
				local player = Players:GetPlayerFromCharacter(character)
				if player and GameState.currentState == "Intermission" and not touching[player.UserId] then
					touching[player.UserId] = true

					-- Print debug info
					print(player.Name .. " touched " .. votePart.Name)

					-- Process the vote
					HandleVote(player, voteIndex)

					-- Reset after a short delay
					spawn(function()
						wait(1)
						touching[player.UserId] = nil
					end)
				end
			end)
		else
			warn("TouchPart not found in " .. votePart.Name)
		end
	end
end

function TransitionPlayerToHunter(player)
	-- Update roles
	PlayerRoles[player.UserId] = ROLE_HUNTER
	player:SetAttribute("Role", "Hunter")

	-- Notify all clients about the role change
	RemoteEvent:FireAllClients("PlayerRoleChanged", player.Name, ROLE_HUNTER)

	-- Setup hunter loadout
	SetupHunterLoadout(player)

	-- Enable first-person mode for the player
	RemoteEvent:FireClient(player, "EnableFirstPerson")

	-- Update prop count for all clients
	updatePropCount()

	print("Player " .. player.Name .. " transitioned from Prop to Hunter")
end

-- Process a player's transition from prop to hunter
local function ProcessPropToHunterTransition(player)
	-- Only process if game is still in playing state and not ending
	if GameState.currentState == "Playing" and not GameState.isEnding then
		-- Set transition flag on the player
		player:SetAttribute("TransitionToHunter", true)
		player:SetAttribute("ManualRespawn", false)

		-- Add short delay before spawning to allow client to prepare
		task.delay(TRANSITION_DELAY, function()
			-- Make sure game is still in playing state
			if GameState.currentState == "Playing" and not GameState.isEnding then
				-- Remove from pending transitions list
				GameState.pendingTransitions[player.UserId] = nil

				-- Spawn character with new role
				print("loading char")
				player:LoadCharacter()
			else
				-- Game ended during delay, reset flags
				player:SetAttribute("TransitionToHunter", false)
				player:SetAttribute("ManualRespawn", false)
				GameState.pendingTransitions[player.UserId] = nil

				-- Just respawn to lobby
				print("loading char")
				player:LoadCharacter()
			end
		end)
	else
		-- Just do normal respawn if not in playing state
		-- This will respawn to lobby as intended
		player:SetAttribute("ManualRespawn", false)
		player:SetAttribute("TransitionToHunter", false)
		print("loading char")
		player:LoadCharacter()
	end
end

-- Function to update role for a newly joined player
local function UpdatePlayerRole(player)
	if GameState.currentState == "Playing" and PlayerRoles[player.UserId] then
		RemoteEvent:FireClient(player, "RoleAssigned", PlayerRoles[player.UserId])

		-- If the map is loaded, teleport them to spawn
		local activeMap = workspace:FindFirstChild("ActiveMap")
		if activeMap then
			local spawnPoint = activeMap:FindFirstChild("player_spawn")
			if spawnPoint and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				player.Character:SetPrimaryPartCFrame(spawnPoint.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end
end

function SetupHunterLoadout(player)
	--print("Setting up Hunter loadout for " .. player.Name)

	-- Get player manager instance for this player
	local playerManager = PlayerManager.ActivePlayers[player]
	if not playerManager then
		warn("PlayerManager not found for " .. player.Name)
		return
	end

	-- Get active weapons from PlayerManager
	local activeWeaponId = playerManager:GetActiveWeapon()
	local activeMeleeWeaponId = playerManager:GetActiveMeleeWeapon()


	-- Get the weapon models from ServerStorage
	local ServerStorage = game:GetService("ServerStorage")
	local weaponsFolder = ServerStorage:FindFirstChild("Weapons")

	if not weaponsFolder then
		warn("Weapons folder not found in ServerStorage")
		return
	end

	-- Clear existing weapons from backpack
	if player.Backpack then
		for _, item in pairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") then
				item:Destroy()
			end
		end
	end

	-- Also remove weapons from character if equipped
	if player.Character then
		for _, item in pairs(player.Character:GetChildren()) do
			if item:IsA("Tool") then
				item:Destroy()
			end
		end
	end

	-- Function to equip a weapon to the player's backpack
	local function equipWeapon(weaponId)
		if not weaponId then return end

		local weaponModel = weaponsFolder:FindFirstChild(weaponId)
		if not weaponModel then
			warn("Weapon not found: " .. weaponId)
			return
		end

		-- Clone the weapon model - make sure it's a Tool
		local weaponClone = weaponModel:Clone()

		-- If weapon is not already a Tool, ensure it's properly configured
		if not weaponClone:IsA("Tool") then
			warn("Weapon " .. weaponId .. " is not a Tool. Skipping.")
			return
		end

		-- Add to player's backpack
		weaponClone.Parent = player.Backpack


		-- Return the equipped weapon for further setup
		return weaponClone
	end

	-- Equip primary and melee weapons
	local primaryWeapon = equipWeapon(activeWeaponId)
	local meleeWeapon = equipWeapon(activeMeleeWeaponId)

	-- Lock into first-person mode
	RemoteEvent:FireClient(player, "EnableFirstPerson")

	-- Return weapons for any additional setup
	return primaryWeapon, meleeWeapon
end

local function HandlePropElimination(hunter, prop)
	if GameState.currentState ~= "Playing" then return end

	-- Make sure the players have valid roles
	if PlayerRoles[hunter.UserId] ~= ROLE_HUNTER or PlayerRoles[prop.UserId] ~= ROLE_PROP then
		return
	end

	-- Notify all clients about the elimination
	RemoteEvent:FireAllClients("PropEliminated", prop.Name)

	-- Flag for transition instead of immediately changing role
	prop:SetAttribute("TransitionToHunter", true)

	-- Check if all props are eliminated or transitioning
	local propsRemaining = 0
	for userId, role in pairs(PlayerRoles) do
		if role == ROLE_PROP then
			local player = Players:GetPlayerByUserId(userId)
			if player and player ~= prop and not player:GetAttribute("TransitionToHunter") then
				propsRemaining = propsRemaining + 1
			end
		end
	end

	-- Update the prop count for all clients
	RemoteEvent:FireAllClients("UpdatePropCount", propsRemaining)

	-- If no props remain, hunter wins
	if propsRemaining <= 0 then
		-- End the round with Hunter win condition
		local hunterWon = true
		EndRound(hunterWon)
	end
end

RemoteEvent.OnServerEvent:Connect(function(player, functionName, ...)
	local args = {...}

	-- Route function calls based on the function name
	if functionName == "Vote" then
		HandleVote(player, args[1])
	elseif functionName == "GetPlayerRole" then
		local role = PlayerRoles[player.UserId] or "None"
		RemoteEvent:FireClient(player, "PlayerRole", role)
	elseif functionName == "EliminateProp" then
		local propPlayer = args[1]
		if propPlayer and typeof(propPlayer) == "Instance" and propPlayer:IsA("Player") then
			HandlePropElimination(player, propPlayer)
		end
	elseif functionName == "RequestPropToHunterTransition" then
		-- Check if client has confirmed that UI is closed
		if args[1] and args[1].uiClosed then
			-- Mark player as pending transition and process it
			GameState.pendingTransitions[player.UserId] = {
				timestamp = tick(),
				player = player
			}

			-- Process the transition with built-in delay
			ProcessPropToHunterTransition(player)
		else
			-- Just store in pending transitions, waiting for UI confirmation
			GameState.pendingTransitions[player.UserId] = {
				timestamp = tick(),
				player = player,
				waitingForUI = true
			}

			-- Notify client that server is waiting for UI confirmation
			RemoteEvent:FireClient(player, "AwaitingUIConfirmation")
		end
	elseif functionName == "RequestRespawn" then
		-- Check if player is a prop and the game is in Playing state
		if GameState.currentState == "Playing" and not GameState.isEnding and
			PlayerRoles[player.UserId] == ROLE_PROP then

			-- Mark for transition to Hunter
			print("Timeout respawn - transitioning " .. player.Name .. " to Hunter")
			player:SetAttribute("TransitionToHunter", true)
			player:SetAttribute("ManualRespawn", false)

			-- Add to pending transitions
			GameState.pendingTransitions[player.UserId] = {
				timestamp = tick(),
				player = player
			}

			-- Process the transition with built-in delay
			ProcessPropToHunterTransition(player)
		else
			-- Just do a normal respawn if not in Playing state or not a prop
			player:SetAttribute("ManualRespawn", false)
			player:LoadCharacter()
		end
	end
	-- Add other function handlers as needed
end)

Players.PlayerAdded:Connect(function(player)
	-- Existing code to connect to character added event
	player.CharacterAdded:Connect(function(character)
		-- Check if this is a transition spawn
		if player:GetAttribute("TransitionToHunter") then
			wait(0.5) -- Short delay to ensure character is fully loaded

			-- Find player_spawn in active map
			local activeMap = workspace:FindFirstChild("ActiveMap")
			if activeMap and character:FindFirstChild("HumanoidRootPart") then
				local spawnPoint = activeMap:FindFirstChild("player_spawn")
				if spawnPoint then
					character:SetPrimaryPartCFrame(spawnPoint.CFrame + Vector3.new(0, 3, 0))
				end
			end

			-- Complete the transition
			TransitionPlayerToHunter(player)
			player:SetAttribute("TransitionToHunter", false)
		end

		-- If game is in progress, teleport them to spawn
		if GameState.currentState == "Playing" and PlayerRoles[player.UserId] then
			RemoteEvent:FireClient(player, "RoleAssigned", PlayerRoles[player.UserId])

			-- If the map is loaded, teleport them to spawn
			local activeMap = workspace:FindFirstChild("ActiveMap")
			if activeMap then
				local spawnPoint = activeMap:FindFirstChild("player_spawn")
				if spawnPoint and player.Character and character:FindFirstChild("HumanoidRootPart") then
					character:SetPrimaryPartCFrame(spawnPoint.CFrame + Vector3.new(0, 3, 0))
				end
			end
		end
	end)

	-- If we're in intermission, update the new player with current state
	if GameState.currentState == "Intermission" then
		-- Create map info for client
		local mapInfo = {}
		for i, mapKey in ipairs(GameState.voteOptions) do
			local map = MapRepository[mapKey]
			mapInfo[i] = {
				displayName = map.displayName,
				imageid = map.imageid,
				mapKey = mapKey
			}
		end

		RemoteEvent:FireClient(player, "StartIntermission", mapInfo, GameState.intermissionTime)
		RemoteEvent:FireClient(player, "UpdateVotes", GameState.votes)
	elseif GameState.currentState == "Waiting" then
		-- Check if we have enough players to start now
		if #Players:GetPlayers() >= MIN_PLAYERS_TO_START then
			StartIntermission()
		end
	elseif GameState.currentState == "Playing" then
		-- If game is in progress, assign a role and update the player
		UpdatePlayerRole(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local playerId = player.UserId

	-- If player voted, remove their vote
	if GameState.playerVotes[playerId] then
		local voteIndex = GameState.playerVotes[playerId]
		GameState.votes[voteIndex] = GameState.votes[voteIndex] - 1
		GameState.playerVotes[playerId] = nil

		-- Update vote labels
		UpdateVoteAmountLabels()

		-- Update clients with new vote count
		RemoteEvent:FireAllClients("UpdateVotes", GameState.votes)
	end

	-- Remove player from role tracking
	if PlayerRoles[playerId] then
		PlayerRoles[playerId] = nil
	end

	-- Remove from pending transitions if present
	if GameState.pendingTransitions[playerId] then
		GameState.pendingTransitions[playerId] = nil
	end

	-- If the hunter left and the game is in progress, select a new hunter
	if GameState.currentState == "Playing" and GameState.selectedHunter and 
		GameState.selectedHunter.UserId == playerId then
		print("Hunter left the game, selecting a new hunter...")

		-- Get remaining players with prop role
		local remainingProps = {}
		for userId, role in pairs(PlayerRoles) do
			if role == ROLE_PROP then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					table.insert(remainingProps, player)
				end
			end
		end

		-- Select a new hunter if there are any props left
		if #remainingProps > 0 then
			local newHunter = remainingProps[math.random(1, #remainingProps)]
			GameState.selectedHunter = newHunter

			-- Update roles
			PlayerRoles[newHunter.UserId] = ROLE_HUNTER

			-- Notify all players about the role change
			RemoteEvent:FireAllClients("HunterChanged", newHunter.Name)
			RemoteEvent:FireClient(newHunter, "RoleAssigned", ROLE_HUNTER)

			print("New hunter selected: " .. newHunter.Name)
		else
			print("No remaining players to select as hunter")
		end
	end

	-- Check if we need to end the round due to not enough players
	if GameState.currentState == "Playing" then
		if #Players:GetPlayers() < MIN_PLAYERS_TO_START then
			print("Not enough players to continue the round")
			EndRound()
		end
	end
end)

function GameLoop()
	-- Monitor for changes to "Waiting" state
	task.spawn(function()
		while true do
			-- If game state changes to "Waiting", reset effects
			if GameState.currentState == "Waiting" then
				LobbyEffectsController:StopAllEffects()
			end
			task.wait(1)
		end
	end)

	-- Original game loop functionality
	while true do
		-- Check if we have enough players to start
		if GameState.currentState == "Waiting" and #Players:GetPlayers() >= MIN_PLAYERS_TO_START then
			wait(3)
			StartIntermission()
		end

		wait(1)
	end
end


-- Initialize
local function Initialize()
	wait(2) -- Give time for everything to load
	SetupTouchParts()
	spawn(GameLoop)
end

Initialize()

-- Export functions
return {
	StartIntermission = StartIntermission,
	HandleVote = HandleVote,
	GameState = GameState,
	PlayerRoles = PlayerRoles,
	EndRound = EndRound
}