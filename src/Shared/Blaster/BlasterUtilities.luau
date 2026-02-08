local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Camera recoil
local recoil = Vector2.new()
local zoom = 0

local Constants = require(ReplicatedStorage.Blaster.Constants)
local CameraFOVManager = require(ReplicatedStorage.CameraFOVManager)

local BlasterUtilities = {}

-- Input categorization
BlasterUtilities.InputCategory = {
	KeyboardAndMouse = "KeyboardAndMouse",
	Gamepad = "Gamepad",
	Touch = "Touch",
	Unknown = "Unknown",
}

local lastInputCategoryChangedEvent = Instance.new("BindableEvent")
BlasterUtilities.lastInputCategoryChanged = lastInputCategoryChangedEvent.Event
local _lastInputCategory = BlasterUtilities.InputCategory.Unknown

-- Return the last input category
function BlasterUtilities.getLastInputCategory()
	return _lastInputCategory
end

-- If *lastInputCategory and inputCategory are different, set *lastInputCategory and fire lastInputCategoryChanged
function BlasterUtilities._setLastInputCategory(inputCategory)
	if _lastInputCategory ~= inputCategory then
		_lastInputCategory = inputCategory
		lastInputCategoryChangedEvent:Fire(inputCategory)
	end
end

-- Return an InputCategory based on the UserInputType
function BlasterUtilities._getCategoryOfInputType(inputType)
	if string.find(inputType.Name, "Gamepad") then
		return BlasterUtilities.InputCategory.Gamepad
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return BlasterUtilities.InputCategory.KeyboardAndMouse
	elseif inputType == Enum.UserInputType.Touch then
		return BlasterUtilities.InputCategory.Touch
	else
		return BlasterUtilities.InputCategory.Unknown
	end
end

function BlasterUtilities.initializeInputCategorizer()
	local UserInputService = game:GetService("UserInputService")

	-- Update the last category when the last inputType changes
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local inputCategory = BlasterUtilities._getCategoryOfInputType(inputType)
		if inputCategory ~= BlasterUtilities.InputCategory.Unknown then
			BlasterUtilities._setLastInputCategory(inputCategory)
		end
	end)

	-- Set the starting input category
	local lastInputType = UserInputService:GetLastInputType()
	local lastInputCategory = BlasterUtilities._getCategoryOfInputType(lastInputType)

	if lastInputCategory ~= BlasterUtilities.InputCategory.Unknown then
		BlasterUtilities._setLastInputCategory(lastInputCategory)
	elseif UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		BlasterUtilities._setLastInputCategory(BlasterUtilities.InputCategory.KeyboardAndMouse)
	elseif UserInputService.TouchEnabled then
		BlasterUtilities._setLastInputCategory(BlasterUtilities.InputCategory.Touch)
	elseif UserInputService.GamepadEnabled then
		BlasterUtilities._setLastInputCategory(BlasterUtilities.InputCategory.Gamepad)
	else
		warn("No input devices detected!")
		BlasterUtilities._setLastInputCategory(BlasterUtilities.InputCategory.Unknown)
	end
end

-- Utility functions
function BlasterUtilities.disconnectAndClear(connections)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function BlasterUtilities.lerp(a, b, t)
	return a + (b - a) * t
end

function BlasterUtilities.applyRecoil(recoilAmount)
	zoom = 1
	recoil += recoilAmount
	CameraFOVManager.setRecoilOffset(zoom)
end

function BlasterUtilities.initializeRecoil()
	local camera = Workspace.CurrentCamera
	local baseFOV = nil  -- We'll store the FOV when recoil starts
	local isActiveRecoil = false

	RunService:BindToRenderStep(Constants.RECOIL_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		-- Apply camera rotation from recoil
		camera.CFrame *= CFrame.Angles(recoil.Y * deltaTime, recoil.X * deltaTime, 0)

		-- FOV management
		if zoom > 0.01 then
			-- Starting recoil or continuing recoil
			if not isActiveRecoil then
				-- Only store base FOV when recoil begins
				baseFOV = camera.FieldOfView
				isActiveRecoil = true
			end

			-- Apply zoom as a modifier to the base FOV
			camera.FieldOfView = baseFOV + zoom
		else
			-- Reset active recoil flag when zoom is nearly zero
			isActiveRecoil = false
		end

		-- Reduce recoil and zoom over time
		recoil = recoil:Lerp(Vector2.zero, math.min(deltaTime * Constants.RECOIL_STOP_SPEED, 1))
		zoom = BlasterUtilities.lerp(zoom, 0, math.min(deltaTime * Constants.RECOIL_ZOOM_RETURN_SPEED, 1))
	end)
end

-- Raycasting functions
function BlasterUtilities.getRayDirections(origin, numberOfRays, spreadAngle, seed)
	-- Random seeds are ints. Since we'll generally be passing in a timestamp as the seed,
	-- we need to multiply it to make sure it isn't the same for an entire second.
	local random = Random.new(seed * 100_000)
	local rays = {}
	for _ = 1, numberOfRays do
		local roll = random:NextNumber() * math.pi * 2
		local pitch = random:NextNumber() * spreadAngle
		local rayCFrame = origin * CFrame.Angles(0, 0, roll) * CFrame.Angles(pitch, 0, 0)
		table.insert(rays, rayCFrame.LookVector)
	end
	return rays
end

function BlasterUtilities.castRays(player, position, directions, radius, staticOnly)
	local exclude = CollectionService:GetTagged(Constants.RAY_EXCLUDE_TAG)

	if staticOnly then
		local nonStatic = CollectionService:GetTagged(Constants.NON_STATIC_TAG)
		-- Append nonStatic to exclude
		table.move(nonStatic, 1, #nonStatic, #exclude + 1, exclude)
	end

	-- Always include the player's character in the exclude list
	if player.Character then
		table.insert(exclude, player.Character)
	end

	-- NEW: Add all disabled props to the exclude list to prevent hits while disabled or restoring
	local disabledProps = CollectionService:GetTagged("DisabledProp")
	for _, disabledProp in ipairs(disabledProps) do
		table.insert(exclude, disabledProp)
	end

	local collisionGroup = nil
	-- If the player is on a team, use that team's collision group to ensure the ray passes through
	-- characters and forcefields on that team.
	if player.Team and not player.Neutral then
		collisionGroup = player.Team.Name
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = exclude
	if collisionGroup then
		params.CollisionGroup = collisionGroup
	end

	local rayResults = {}
	for _, direction in directions do
		-- In order to provide a simple form of bullet magnetism, we use spherecasts with a small radius instead of raycasts.
		-- This allows closely grazing shots to register as hits, making blasters feel a bit more accurate and improving the 'game feel'.
		local raycastResult = Workspace:Spherecast(position, radius, direction, params)
		local rayResult = {
			position = position + direction,
			normal = direction.Unit,
		}

		if raycastResult then
			rayResult.position = raycastResult.Position
			rayResult.normal = raycastResult.Normal
			rayResult.instance = raycastResult.Instance

			-- First, check if we hit an accessory or accessory part
			local hitPart = raycastResult.Instance
			local accessory = hitPart:FindFirstAncestorWhichIsA("Accessory")

			if accessory then
				-- We hit an accessory, find its character
				local character = accessory:FindFirstAncestorWhichIsA("Model")
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and BlasterUtilities.canPlayerDamageHumanoid(player, humanoid) then
						rayResult.taggedHumanoid = humanoid
						print("HIT ACCESSORY: Found humanoid through accessory")
					end
				end
			else
				-- Normal humanoid check (direct parent)
				local humanoid = raycastResult.Instance.Parent:FindFirstChildOfClass("Humanoid")
				if humanoid and BlasterUtilities.canPlayerDamageHumanoid(player, humanoid) then
					rayResult.taggedHumanoid = humanoid
				end

				-- Secondary check for humanoid (two levels up)
				if not rayResult.taggedHumanoid and raycastResult.Instance.Parent and raycastResult.Instance.Parent.Parent then
					local humanoid = raycastResult.Instance.Parent.Parent:FindFirstChildOfClass("Humanoid")
					if humanoid and BlasterUtilities.canPlayerDamageHumanoid(player, humanoid) then
						rayResult.taggedHumanoid = humanoid
					end
				end

				-- Prop check (only if we didn't find a humanoid)
				if not rayResult.taggedHumanoid then
					local propModel = hitPart

					-- Traverse up to find PropModel
					while propModel and propModel ~= workspace and propModel.Name ~= "PropModel" do
						propModel = propModel.Parent
					end

					-- If we found a PropModel, check if it's attached to a player
					if propModel and propModel.Name == "PropModel" then
						local playerCharacter = propModel.Parent

						-- Check if the parent is a player character
						if playerCharacter then
							local propOwnerHumanoid = playerCharacter:FindFirstChildOfClass("Humanoid")

							if propOwnerHumanoid and BlasterUtilities.canPlayerDamageHumanoid(player, propOwnerHumanoid) then
								-- Found a prop attached to a player character that we can damage
								rayResult.taggedHumanoid = propOwnerHumanoid
								rayResult.hitProp = true  -- Flag that we hit a prop (useful for effects)
								print("HIT PROP ATTACHED TO PLAYER:", playerCharacter:GetFullName())
							end
						end
					end
				end		
			end
		end

					table.insert(rayResults, rayResult)
end

return rayResults
end

function BlasterUtilities.canPlayerDamageHumanoid(player, taggedHumanoid)
	-- Keep existing death check
	if taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent
	local taggedPlayer = Players:GetPlayerFromCharacter(taggedCharacter)

	-- Keep non-player check
	if not taggedPlayer then
		return true
	end

	-- NEW CODE: Check for Hunter-on-Hunter damage
	local attackerRole = player:GetAttribute("Role")
	local targetRole = taggedPlayer:GetAttribute("Role") 

	-- Prevent Hunter-on-Hunter damage
	if attackerRole == "Hunter" and targetRole == "Hunter" then
		return false
	end

	-- Keep existing team check for other cases
	if player.Neutral or taggedPlayer.Neutral then
		return true
	else
		return player.Team ~= taggedPlayer.Team
	end
end

-- Sound utilities
function BlasterUtilities.playSoundFromSource(playerTemplate, target)
	local audioPlayer = playerTemplate:Clone()
	audioPlayer.Parent = target
	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = target
	wire.Parent = audioPlayer
	audioPlayer:Play()
	audioPlayer.Ended:Once(function()
		audioPlayer:Destroy()
	end)
end

function BlasterUtilities.playRandomSoundFromSource(soundTemplates, target)
	local random = Random.new()
	local sounds = soundTemplates:GetChildren()
	local sound = sounds[random:NextInteger(1, #sounds)]
	BlasterUtilities.playSoundFromSource(sound, target)
end

function BlasterUtilities.bindSoundsToAnimationEvents(animation, sounds, target)
	local SOUND_EVENT = "Sound"
	local RANDOM_SOUND_EVENT = "RandomSound"

	animation:GetMarkerReachedSignal(SOUND_EVENT):Connect(function(param)
		local sound = sounds:FindFirstChild(param)
		if not sound then
			return
		end
		BlasterUtilities.playSoundFromSource(sound, target)
	end)

	-- For repetitive sounds like shooting, we'll play a random sound variation from a selection, rather than playing the same sound over and over.
	animation:GetMarkerReachedSignal(RANDOM_SOUND_EVENT):Connect(function(param)
		local folder = sounds:FindFirstChild(param)
		if not folder then
			return
		end
		BlasterUtilities.playRandomSoundFromSource(folder, target)
	end)
end

-- Initialize input categorizer
BlasterUtilities.initializeInputCategorizer()

return BlasterUtilities