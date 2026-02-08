-- WeaponSpeedController.lua
-- Place this in StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Speed configuration
local SPEED_SETTINGS = {
	DEFAULT = 20,       -- Base speed when no weapon is equipped
	BLASTER = 20,       -- Speed when holding a blaster
	MELEE = 22,         -- Boosted speed when holding a melee weapon
}

local currentSpeed = SPEED_SETTINGS.DEFAULT
local equipped = nil

-- Function to check weapon type and update speed
local function updateSpeed()
	if not humanoid then return end

	-- Apply the appropriate speed
	humanoid.WalkSpeed = currentSpeed
end

-- Function to identify weapon type from a tool
local function getWeaponType(tool)
	if not tool then return "NONE" end

	-- Check for melee weapon
	if tool:GetAttribute("weaponType") == "Melee" then
		return "MELEE"
	end

	-- Check for blaster weapon (using attributes from your system)
	if tool:GetAttribute("isBlaster") or tool:GetAttribute("viewModel") then
		return "BLASTER"
	end

	-- Default case - unknown weapon type
	return "DEFAULT"
end

-- Handle tool equip/unequip
local function onChildAdded(child)
	if child:IsA("Tool") then
		equipped = child

		-- Determine weapon type and set appropriate speed
		local weaponType = getWeaponType(child)

		if weaponType == "MELEE" then
			currentSpeed = SPEED_SETTINGS.MELEE
		elseif weaponType == "BLASTER" then
			currentSpeed = SPEED_SETTINGS.BLASTER
		else
			currentSpeed = SPEED_SETTINGS.DEFAULT
		end

		updateSpeed()
	end
end

local function onChildRemoved(child)
	if child:IsA("Tool") and child == equipped then
		equipped = nil
		currentSpeed = SPEED_SETTINGS.DEFAULT
		updateSpeed()
	end
end

-- Setup character connections
local function setupCharacter(char)
	character = char
	humanoid = character:WaitForChild("Humanoid")

	-- Reset to default speed when character spawns
	currentSpeed = SPEED_SETTINGS.DEFAULT
	updateSpeed()

	-- Connect to tool equip/unequip events
	character.ChildAdded:Connect(onChildAdded)
	character.ChildRemoved:Connect(onChildRemoved)

	-- Check for any already equipped tools
	for _, child in pairs(character:GetChildren()) do
		if child:IsA("Tool") then
			onChildAdded(child)
			break
		end
	end
end

-- Handle character respawning
player.CharacterAdded:Connect(setupCharacter)

-- Setup the current character if it exists
if character then
	setupCharacter(character)
end

print("Weapon Speed Controller initialized")