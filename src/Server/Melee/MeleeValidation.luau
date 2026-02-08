local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Constants = require(ReplicatedStorage.Melee.Constants)

local MeleeValidation = {}

-- TYPE VALIDATION SECTION --

function MeleeValidation.validateNumber(number)
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

function MeleeValidation.validateVector3(vector3)
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

function MeleeValidation.validateCFrame(cframe)
	-- Make sure this is actually a CFrame
	if typeof(cframe) ~= "CFrame" then
		return false
	end
	if not MeleeValidation.validateVector3(cframe.Position) then
		return false
	end
	if not MeleeValidation.validateVector3(cframe.LookVector) then
		return false
	end
	return true
end

function MeleeValidation.validateInstance(instance, expectedClass)
	if typeof(instance) ~= "Instance" then
		return false
	end
	return instance:IsA(expectedClass)
end

-- GAME VALIDATION SECTION --

-- Constants for validation buffers
local TIMESTAMP_BUFFER_CONSTANT = 1
local POSITION_BUFFER_CONSTANT = 10  -- Melee needs a larger buffer than guns
local POSITION_BUFFER_FACTOR = 0.5

function MeleeValidation.validateAttackArguments(melee, attackType, origin, timestamp)
	if not MeleeValidation.validateInstance(melee, "Tool") then
		return false
	end

	if not (attackType == Constants.ATTACK_TYPE.PRIMARY or attackType == Constants.ATTACK_TYPE.SECONDARY) then
		return false
	end

	if not MeleeValidation.validateCFrame(origin) then
		return false
	end

	if not MeleeValidation.validateNumber(timestamp) then
		return false
	end

	return true
end

function MeleeValidation.validateAttack(player, melee, timestamp)
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

	-- Make sure the melee weapon is equipped
	if melee.Parent ~= character then
		print("VALIDATION FAILED: Melee weapon not equipped", melee.Parent and melee.Parent:GetFullName() or "nil", "≠", character:GetFullName())
		return false
	end

	-- Validate that the melee weapon's attributes are set
	local weaponType = melee:GetAttribute(Constants.WEAPON_TYPE_ATTRIBUTE)
	if weaponType ~= "Melee" then
		print("VALIDATION FAILED: Not a melee weapon type:", weaponType)
		return false
	end

	return true
end

return MeleeValidation