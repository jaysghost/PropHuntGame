-- MeleeClient.lua - Place in StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Check if all required modules exist before requiring them
local function checkAndRequireModule(path)
	local success, result = pcall(function()
		return require(path)
	end)
	if success then
		return result
	else
		warn("Failed to load module: " .. path:GetFullName() .. " - Error: " .. tostring(result))
		return nil
	end
end

-- Check module paths
local MeleeControllerPath = ReplicatedStorage:FindFirstChild("Melee"):FindFirstChild("Scripts"):FindFirstChild("MeleeController")
if not MeleeControllerPath then
	warn("MeleeController module not found.")
	return
end

-- Try to require the MeleeController
local MeleeController = checkAndRequireModule(MeleeControllerPath)
if not MeleeController then
	return
end

-- Function to set up a melee weapon with comprehensive error handling
local function setupMelee(weapon)
	-- Check if it's actually a melee weapon by checking its weaponType attribute
	local weaponType = weapon:GetAttribute("weaponType")
	if not weaponType or weaponType ~= "Melee" then
		return
	end

	-- Check for view model attribute
	local viewModelAttribute = weapon:GetAttribute("viewModel")
	if not viewModelAttribute then
		warn("Melee weapon missing viewModel attribute: " .. weapon:GetFullName())
		return
	end

	-- Try to create controller with error handling
	local success, controller = pcall(function()
		return MeleeController.new(weapon)
	end)
	if not success then
		warn("Failed to create melee controller: " .. tostring(controller))
		return
	end

	-- Listen for when weapon is destroyed
	weapon.AncestryChanged:Connect(function()
		if not weapon:IsDescendantOf(game) then
			pcall(function() controller:destroy() end)
		end
	end)

	return controller
end

-- Function to check for melee weapons in a container
local function checkForMeleeWeapons(container)
	if not container then return end

	for _, item in pairs(container:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("weaponType") == "Melee" then
			setupMelee(item)
		end
	end
end

-- Listen for tool additions to backpack
player.Backpack.ChildAdded:Connect(function(item)
	if item:IsA("Tool") and item:GetAttribute("weaponType") == "Melee" then
		setupMelee(item)
	end
end)

-- Listen for character changes
player.CharacterAdded:Connect(function(character)
	character.ChildAdded:Connect(function(item)
		if item:IsA("Tool") and item:GetAttribute("weaponType") == "Melee" then
			setupMelee(item)
		end
	end)

	-- Check existing items
	checkForMeleeWeapons(character)
end)

-- Check existing character and backpack
if player.Character then
	checkForMeleeWeapons(player.Character)
end

checkForMeleeWeapons(player.Backpack)

print("MeleeClient initialized successfully")