-- Server Script to store character models in ReplicatedStorage
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Default UserId for Studio testing
local DEFAULT_STUDIO_USERID = 2605061756

-- Ensure ViewportModels folder exists
local viewportModelsFolder = ReplicatedStorage:FindFirstChild("ViewportModels")
if not viewportModelsFolder then
	viewportModelsFolder = Instance.new("Folder")
	viewportModelsFolder.Name = "ViewportModels"
	viewportModelsFolder.Parent = ReplicatedStorage
	print("Created ViewportModels folder in ReplicatedStorage")
end

-- Create a temp folder in workspace for character setup
local ServerStorage = game:GetService("ServerStorage")
local function getTempFolder()
	local tempFolder = ServerStorage:FindFirstChild("__TempViewportSetup")
	if not tempFolder then
		tempFolder = Instance.new("Folder")
		tempFolder.Name = "__TempViewportSetup"
		tempFolder.Parent = ServerStorage
	end
	return tempFolder
end
-- Ensure we have an R15Template to use
local function ensureR15TemplateExists()
	-- Check if R15Template already exists
	local r15Template = viewportModelsFolder:FindFirstChild("R15Template")
	if not r15Template then
		print("Creating R15Template in ViewportModels...")

		-- Create a simple dummy model
		r15Template = Instance.new("Model")
		r15Template.Name = "R15Template"

		-- Add humanoid with R15 rig type
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.Parent = r15Template

		-- Add animation controller for ViewportFrame animations
		local animController = Instance.new("AnimationController")
		local animator = Instance.new("Animator")
		animator.Parent = animController
		animController.Parent = r15Template

		-- Add HumanoidRootPart
		local rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 1)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.Parent = r15Template

		-- Apply default appearance (optional)
		pcall(function()
			-- Create in temp workspace folder first
			local tempFolder = getTempFolder()
			r15Template.Parent = tempFolder

			local description = Players:GetHumanoidDescriptionFromUserId(DEFAULT_STUDIO_USERID)
			humanoid:ApplyDescription(description)

			-- Move back to ReplicatedStorage
			r15Template.Parent = viewportModelsFolder
		end)

		if r15Template.Parent ~= viewportModelsFolder then
			r15Template.Parent = viewportModelsFolder
		end

		print("Created R15Template successfully")
	end

	return r15Template
end

-- Make sure we have a template
local r15Template = ensureR15TemplateExists()

-- Function to store a player's character model using the R15Template
local function storePlayerAppearance(player)

	-- Remove any existing model
	local existingModel = viewportModelsFolder:FindFirstChild(player.Name)
	if existingModel then
		existingModel:Destroy()
		print("Removed existing model for:", player.Name)
	end

	-- Create a temporary workspace location
	local tempFolder = getTempFolder()

	-- Clone the R15Template
	local success, dummy
	success, dummy = pcall(function()
		return r15Template:Clone()
	end)

	if not success or not dummy then
		warn("Failed to clone R15Template for player:", player.Name)
		return false
	end

	-- Rename to player's name
	dummy.Name = player.Name

	-- THE KEY STEP: Parent temporarily to WORKSPACE
	dummy.Parent = tempFolder

	-- Find the humanoid
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No humanoid found in cloned template for player:", player.Name)
		dummy:Destroy()
		return false
	end

	-- Try multiple methods to get appearance
	local descriptSuccess = false

	-- Method 1: Try to get from current character
	if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
		local success, errorMsg = pcall(function()
			local characterHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
			local description = characterHumanoid:GetAppliedDescription()
			humanoid:ApplyDescription(description)
		end)

		if success then
			descriptSuccess = true
		else
			warn("Error applying character description:", errorMsg)
		end
	end

	-- Method 2: Try to get from UserId
	if not descriptSuccess and player.UserId > 0 then
		local success, errorMsg = pcall(function()
			local description = Players:GetHumanoidDescriptionFromUserId(player.UserId)
			humanoid:ApplyDescription(description)
		end)

		if success then
			descriptSuccess = true
		else
			warn("Error applying UserId description:", errorMsg)
		end
	end

	-- Method 3: Use default UserId for Studio testing
	if not descriptSuccess and RunService:IsStudio() then
		local success, errorMsg = pcall(function()
			print("Using default studio UserId for:", player.Name)
			local description = Players:GetHumanoidDescriptionFromUserId(DEFAULT_STUDIO_USERID)
			humanoid:ApplyDescription(description)
		end)

		if success then
			descriptSuccess = true
			print("Applied default description for:", player.Name)
		else
			warn("Error applying default description:", errorMsg)
		end
	end

	if descriptSuccess then
		-- Set attributes
		dummy:SetAttribute("Name", player.Name)
		dummy:SetAttribute("UserId", player.UserId)
		dummy:SetAttribute("ViewportModel", true)

		-- NOW move to ReplicatedStorage after setup is complete
		dummy.Parent = viewportModelsFolder

		-- Clean up temp folder if empty
		if #tempFolder:GetChildren() == 0 then
			tempFolder:Destroy()
		end

		return true
	else
		dummy:Destroy()
		warn("Failed to apply any description to the dummy for player:", player.Name)

		-- Create a fallback model with default appearance
		local fallbackModel = Instance.new("Model")
		fallbackModel.Name = player.Name

		-- Add humanoid
		local fallbackHumanoid = Instance.new("Humanoid")
		fallbackHumanoid.Parent = fallbackModel

		-- Add a head so viewport camera knows where to look
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1, 1, 1)
		head.BrickColor = BrickColor.new("Light orange")
		head.TopSurface = Enum.SurfaceType.Smooth
		head.BottomSurface = Enum.SurfaceType.Smooth
		head.Parent = fallbackModel

		-- Add torso
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Size = Vector3.new(2, 2, 1)
		torso.BrickColor = BrickColor.new("Bright blue")
		torso.TopSurface = Enum.SurfaceType.Smooth
		torso.BottomSurface = Enum.SurfaceType.Smooth
		torso.Parent = fallbackModel

		-- Add animation controller for viewport animation
		local animController = Instance.new("AnimationController")
		local animator = Instance.new("Animator")
		animator.Parent = animController
		animController.Parent = fallbackModel

		-- Add HumanoidRootPart
		local rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 1)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.Parent = fallbackModel

		-- Set attributes
		fallbackModel:SetAttribute("Name", player.Name)
		fallbackModel:SetAttribute("UserId", player.UserId)
		fallbackModel:SetAttribute("IsFallback", true)

		fallbackModel.Parent = viewportModelsFolder
		print("Created fallback model for player:", player.Name)

		return true
	end
end

-- Handle existing players
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		if player.Character then
			storePlayerAppearance(player)
		end

		player.CharacterAdded:Connect(function(character)
			-- Small delay to ensure character is fully loaded
			task.wait(1)
			storePlayerAppearance(player)
		end)
	end)
end

-- Handle new players joining
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- Initial store attempt in case they already have a character
		if player.Character then
			storePlayerAppearance(player)
		end

		-- Connect to CharacterAdded for future character loads
		player.CharacterAdded:Connect(function(character)
			-- Small delay to ensure character is fully loaded
			task.wait(1)
			storePlayerAppearance(player)
		end)
	end)
end)

-- Handle players leaving (cleanup)
Players.PlayerRemoving:Connect(function(player)
	local existingModel = viewportModelsFolder:FindFirstChild(player.Name)
	if existingModel then
		existingModel:Destroy()
		print("Removed model for player:", player.Name)
	end
end)