-- BlasterClient.lua - Place in StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Keep track of Hunter status
local isHunter = false
-- Add a flag to track if initial equip has occurred for this round
local initialEquipDone = false

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
local BlasterControllerPath = ReplicatedStorage:FindFirstChild("Blaster"):FindFirstChild("Scripts"):FindFirstChild("BlasterController")
if not BlasterControllerPath then
	return
end

-- Try to require the BlasterController
local BlasterController = checkAndRequireModule(BlasterControllerPath)
if not BlasterController then
	return
end

-- Function to set up a blaster with comprehensive error handling
local function setupBlaster(blaster)
	-- Check if it's actually a blaster
	local viewModelAttribute = blaster:GetAttribute("viewModel")
	if not viewModelAttribute then
		warn("Blaster missing viewModel attribute: " .. blaster:GetFullName())
		return
	end

	-- Try to create controller with error handling
	local success, controller = pcall(function()
		return BlasterController.new(blaster)
	end)
	if not success then
		warn("Failed to create controller: " .. tostring(controller))
		return
	end

	-- Listen for when blaster is destroyed
	blaster.AncestryChanged:Connect(function()
		if not blaster:IsDescendantOf(game) then
			pcall(function() controller:destroy() end)
		end
	end)

	return controller
end

-- Function to check for blasters in a container
local function checkForBlasters(container)
	if not container then return end

	for _, item in pairs(container:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("viewModel") and item:GetAttribute("isBlaster") then
			setupBlaster(item)
		end
	end
end

-- Function to try to auto-equip a blaster for Hunters
local function tryAutoEquipBlaster()
	if not isHunter then return end
	if not player.Character then return end
	if initialEquipDone then return end -- Skip if already equipped for this round

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Find a blaster in the backpack
	for _, item in pairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and 
			(item:GetAttribute("viewModel") or item:GetAttribute("isBlaster")) then
			-- Equip it using the standard method
			humanoid:EquipTool(item)
			print("Auto-equipped blaster for Hunter: " .. item.Name)
			initialEquipDone = true -- Mark initial equip as done
			return true
		end
	end

	return false
end

-- Listen for tool additions to backpack
player.Backpack.ChildAdded:Connect(function(item)
	if item:IsA("Tool") and item:GetAttribute("viewModel") and item:GetAttribute("isBlaster") then
		setupBlaster(item)

		-- Only auto-equip if this is the initial equip for the round
		if isHunter and not initialEquipDone then
			task.delay(0.5, function()
				-- Make sure it's still in the backpack
				if item.Parent == player.Backpack then
					local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:EquipTool(item)
						print("Auto-equipped new blaster: " .. item.Name)
						initialEquipDone = true
					end
				end
			end)
		end
	end
end)

-- Listen for character changes
player.CharacterAdded:Connect(function(character)
	character.ChildAdded:Connect(function(item)
		if item:IsA("Tool") and item:GetAttribute("viewModel") and item:GetAttribute("isBlaster") then
			setupBlaster(item)
		end
	end)

	-- Check existing items
	checkForBlasters(character)

	-- Only auto-equip if we haven't done the initial equip for this round
	if isHunter and not initialEquipDone then
		task.delay(1, function()
			tryAutoEquipBlaster()
		end)
	end
end)

-- Listen for role assignment - Reset the initialEquipDone flag when role is assigned
RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "RoleAssigned" then
		local role = ...
		isHunter = (role == "Hunter")
		initialEquipDone = false -- Reset flag when role is assigned (new round)

		if isHunter then
			-- Try to auto-equip a blaster
			task.delay(1, function()
				tryAutoEquipBlaster()
			end)
		end
	end
end)

-- Initialize on script load
if player.Character then
	checkForBlasters(player.Character)
end
checkForBlasters(player.Backpack)

print("Enhanced BlasterClient initialized with Hunter auto-equip")