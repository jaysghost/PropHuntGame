local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Constants = require(ReplicatedStorage.Blaster.Constants)

local BlasterValidation = {}

-- TYPE VALIDATION SECTION --

function BlasterValidation.validateNumber(number)
	-- Make sure this is actually a number
	if typeof(number) ~= "number" then
		return false
	end
	-- Make sure the number is not NaN
	if number ~= number then
		return false
	end
	return true
end

function BlasterValidation.validateVector3(vector3)
	-- Make sure this is actually a Vector3
	if typeof(vector3) ~= "Vector3" then
		return false
	end
	-- Make sure the vector3 does not contain any NaN components
	if vector3 ~= vector3 then
		return false
	end
	return true
end

function BlasterValidation.validateCFrame(cframe)
	-- Make sure this is actually a CFrame
	if typeof(cframe) ~= "CFrame" then
		return false
	end
	if not BlasterValidation.validateVector3(cframe.Position) then
		return false
	end
	if not BlasterValidation.validateVector3(cframe.LookVector) then
		return false
	end
	return true
end

function BlasterValidation.validateInstance(instance, expectedClass)
	if typeof(instance) ~= "Instance" then
		return false
	end
	return instance:IsA(expectedClass)
end

function BlasterValidation.validateSimpleTable(tbl, keyType, validator)
	-- Make sure this is actually a table
	if typeof(tbl) ~= "table" then
		return false
	end
	-- Validate all keys and values
	for key, value in tbl do
		if typeof(key) ~= keyType then
			return false
		end
		if not validator(value) then
			return false
		end
	end
	return true
end

-- GAME VALIDATION SECTION --

-- Constants for validation buffers
local TIMESTAMP_BUFFER_CONSTANT = 1
local POSITION_BUFFER_CONSTANT = 5
local POSITION_BUFFER_FACTOR = 0.4
local DIRECTION_BUFFER_CONSTANT = 10
local WALL_DISTANCE_BUFFER_CONSTANT = 5

function BlasterValidation.validateShootArguments(timestamp, blaster, origin, tagged)
	if not BlasterValidation.validateNumber(timestamp) then
		return false
	end
	if not BlasterValidation.validateInstance(blaster, "Tool") then
		return false
	end
	if not BlasterValidation.validateCFrame(origin) then
		return false
	end

	local function taggedValidator(instance)
		return BlasterValidation.validateInstance(instance, "Humanoid")
	end

	if not BlasterValidation.validateSimpleTable(tagged, "string", taggedValidator) then
		return false
	end
	return true
end

function BlasterValidation.validateShot(player, timestamp, blaster, origin)

	-- Validate timestamp
	local now = Workspace:GetServerTimeNow()
	if timestamp > now then
		print("VALIDATION FAILED: Timestamp from future", timestamp, ">", now)
		return false
	end

	if timestamp < now - TIMESTAMP_BUFFER_CONSTANT then
		print("VALIDATION FAILED: Timestamp too old", timestamp, "<", now - TIMESTAMP_BUFFER_CONSTANT)
		return false
	end

	-- Make sure the character exists, is alive, and has a PrimaryPart
	local character = player.Character
	if not character then
		print("VALIDATION FAILED: No character")
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		print("VALIDATION FAILED: No humanoid")
		return false
	end

	if humanoid.Health <= 0 then
		print("VALIDATION FAILED: Humanoid dead")
		return false
	end

	local primaryPart = character.PrimaryPart
	if not primaryPart then
		print("VALIDATION FAILED: No primary part")
		return false
	end

	-- Make sure the blaster is equipped
	if blaster.Parent ~= character then
		print("VALIDATION FAILED: Blaster not equipped", blaster.Parent and blaster.Parent:GetFullName() or "nil", "≠", character:GetFullName())
		return false
	end

	-- Make sure the blaster is not being reloaded
	local isReloading = blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)
	if isReloading then
		return false
	end

	-- Make sure the blaster has enough ammo
	local ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	if ammo <= 0 then
		print("VALIDATION FAILED: No ammo left")
		return false
	end

	-- Make sure the origin position is within a reasonable distance from the character
	local distance = (primaryPart.Position - origin.Position).Magnitude
	local maxDistance = POSITION_BUFFER_CONSTANT + primaryPart.AssemblyLinearVelocity.Magnitude * POSITION_BUFFER_FACTOR
	if distance > maxDistance then
		print("VALIDATION FAILED: Position too far", distance, ">", maxDistance)
		return false
	end

	return true
end
function BlasterValidation.validateTag(player, taggedHumanoid, position, direction, rayResult)
	local canPlayerDamageHumanoid = require(ReplicatedStorage.Blaster.BlasterUtilities).canPlayerDamageHumanoid
	-- Make sure the player is actually allowed to damage this humanoid
	if not canPlayerDamageHumanoid(player, taggedHumanoid) then
		return false
	end

	local character = taggedHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	local pivot = character:GetPivot()
	local characterOffset = pivot.Position - position
	local characterDistance = characterOffset.Magnitude
	local rayDistance = (position - rayResult.position).Magnitude

	-- If the server's ray hits static geometry before the player, then we know the shot
	-- the client reported could not be made
	if rayDistance < characterDistance - WALL_DISTANCE_BUFFER_CONSTANT then
		return false
	end

-- Check angle between ray direction and character direction
	local maxAngle = math.atan(DIRECTION_BUFFER_CONSTANT / characterDistance)
	local angle = characterOffset:Angle(direction)
	if angle > maxAngle then
		return false
	end

	return true
end


function BlasterValidation.validateReload(player, blaster)
	local character = player.Character
	if not character then
		return false
	end

	if blaster.Parent ~= character then
		return false
	end

	if blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
		return false
	end

	return true
end

return BlasterValidation