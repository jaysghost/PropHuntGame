local Players = game:GetService("Players")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Player = Players.LocalPlayer
local PlayerUI = Players.LocalPlayer.PlayerGui

local ViewportMethods = {}

---------------------------------------------------------

function ViewportMethods.CreateTweenAsync(instance,data,goals) -- asynchronous
	local Tween = TS:Create(instance,data,goals)
	Tween:Play()
end

ViewportMethods.HalfSecondSineData =  TweenInfo.new(
	0.5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

---------------------------------------------------------------

-- Function to calculate character height including any accessories
function ViewportMethods.CalculateCharacterHeight(character)
	-- Default offset if all calculations fail
	local DEFAULT_HEIGHT = 4

	-- Find the highest point relative to HumanoidRootPart
	local highestPoint = 0
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart then
		local baseY = rootPart.Position.Y

		-- Examine all parts including accessories
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local topOfPart = part.Position.Y + (part.Size.Y / 2)
				if topOfPart > baseY then
					highestPoint = math.max(highestPoint, topOfPart - baseY)
				end
			end
		end
	end

	-- If we found a reasonable height, use it
	if highestPoint > 0 then
		-- Add a buffer above the highest point
		local height = highestPoint + 1.5  -- 1.5 stud buffer

		-- Clamp to reasonable values
		return math.clamp(height, 3.5, 8)
	end

	-- If calculation failed, use default
	return DEFAULT_HEIGHT
end

-- Creates billboards for all players including local player
function ViewportMethods.SetupPlayerBillboards()
	-- Set up for all existing players
	for _, player in pairs(Players:GetPlayers()) do
		ViewportMethods.CreatePlayerBillboard(player)
	end

	-- Set up for new players joining
	Players.PlayerAdded:Connect(function(player)
		-- Wait for character to load
		if player.Character then
			ViewportMethods.CreatePlayerBillboard(player)
		end

		player.CharacterAdded:Connect(function(character)
			ViewportMethods.CreatePlayerBillboard(player)
		end)
	end)

	-- Handle player removal
	Players.PlayerRemoving:Connect(function(player)
		ViewportMethods.RemovePlayerBillboard(player)
	end)
end

-- Initialize player billboards with better timing and error handling
function ViewportMethods.InitPlayerBillboards()
	-- Ensure ViewportModels folder exists in ReplicatedStorage
	local viewportModelsFolder = ReplicatedStorage:FindFirstChild("ViewportModels")
	if not viewportModelsFolder then
		viewportModelsFolder = Instance.new("Folder")
		viewportModelsFolder.Name = "ViewportModels"
		viewportModelsFolder.Parent = ReplicatedStorage
		print("Created ViewportModels folder in ReplicatedStorage")
	end

	-- Function to handle a player (creates billboard when character and model are ready)
	local function handlePlayer(player)
		-- Skip for LocalPlayer if desired
		if player == Player then return end

		-- Check if character already exists
		if player.Character then
			-- Ensure model exists in ReplicatedStorage
			local modelExists = viewportModelsFolder:FindFirstChild(player.Name)

			if modelExists then
				-- Both character and model exist, create billboard
				print("Creating billboard for existing player:", player.Name)
				ViewportMethods.CreatePlayerBillboard(player)
			else
				-- Character exists but no model, wait briefly for model
				print("Character exists but waiting for model:", player.Name)
				task.delay(2, function()
					if player.Character and viewportModelsFolder:FindFirstChild(player.Name) then
						ViewportMethods.CreatePlayerBillboard(player)
					end
				end)
			end
		end

		-- Connect to CharacterAdded for future spawns
		player.CharacterAdded:Connect(function(character)
			print("Character added for player:", player.Name)

			-- Wait a moment for model to be stored in ReplicatedStorage
			task.delay(1.5, function()
				if character.Parent and viewportModelsFolder:FindFirstChild(player.Name) then
					print("Model found, creating billboard for:", player.Name)
					ViewportMethods.CreatePlayerBillboard(player)
				else
					print("Still waiting for model after character spawn:", player.Name)
					-- One more attempt after a longer delay
					task.delay(3, function()
						if character.Parent and player.Character == character then
							print("Final attempt to create billboard for:", player.Name)
							ViewportMethods.CreatePlayerBillboard(player)
						end
					end)
				end
			end)
		end)
	end

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		handlePlayer(player)
	end

	-- Handle new players
	Players.PlayerAdded:Connect(handlePlayer)

	-- Listen for new models appearing in ViewportModels
	viewportModelsFolder.ChildAdded:Connect(function(child)
		-- Find matching player
		local modelPlayer = Players:FindFirstChild(child.Name)
		if modelPlayer and modelPlayer.Character and modelPlayer ~= Player then
			print("Creating billboard due to new model:", child.Name)
			ViewportMethods.CreatePlayerBillboard(modelPlayer)
		end
	end)
end

-- Update the CreatePlayerBillboard function with final adjustments
function ViewportMethods.CreatePlayerBillboard(player)
	local character = player.Character
	if not character then return end

	-- Skip if trying to create billboard for LocalPlayer
	if player == Player then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	-- Remove existing billboard if present
	ViewportMethods.RemovePlayerBillboard(player)

	-- Generate a unique name for this billboard
	local billboardName = "PlayerViewportBillboard_" .. player.UserId

	-- Calculate the character's height for proper positioning
	local characterHeight = ViewportMethods.CalculateCharacterHeight(character)

	-- Create new BillboardGui with a 15% increase in height
	local billboard = Instance.new("BillboardGui")
	billboard.Name = billboardName
	billboard.Size = UDim2.new(3, 0, 4.6, 0)  -- Increased by 15% from 4.0 to 4.6
	billboard.Adornee = humanoidRootPart
	billboard.StudsOffset = Vector3.new(0, characterHeight, 0)  -- Dynamic height based on character
	billboard.MaxDistance = 100
	billboard.AlwaysOnTop = true
	billboard.Active = true
	billboard.ClipsDescendants = true
	billboard.Enabled = false  -- Start disabled, will enable based on visibility

	-- Create a container frame to hold both viewport and name
	local containerFrame = Instance.new("Frame")
	containerFrame.Name = "ContainerFrame"
	containerFrame.Size = UDim2.new(1, 0, 1, 0)
	containerFrame.BackgroundTransparency = 1
	containerFrame.Parent = billboard

	-- Clone the IconTemplate
	local iconTemplate = PlayerUI.Templates.IconTemplate:Clone()
	iconTemplate.Size = UDim2.new(1, 0, 0.75, 0)  -- 75% of container height
	iconTemplate.Position = UDim2.new(0, 0, 0, 0)  -- Position at the top
	iconTemplate.BackgroundTransparency = 1
	iconTemplate.Parent = containerFrame

	-- Start with ViewportFrame fully transparent
	local viewportFrame = iconTemplate.ViewportFrame
	viewportFrame.ImageTransparency = 1

	-- Clone the NameHolder
	local nameHolder = PlayerUI.Templates.NameHolder:Clone()
	nameHolder.Size = UDim2.new(1, 0, 0.25, 0)  -- 25% of container height
	nameHolder.Position = UDim2.new(0, 0, 0.75, 0)  -- Position at the bottom
	nameHolder.BackgroundTransparency = 1
	nameHolder.Parent = containerFrame

	-- Make name text larger
	local nameLabel = nameHolder:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = player.Name
		nameLabel.TextSize = 24  -- Increased font size further
		nameLabel.TextTransparency = 1  -- Start transparent for fading

		-- Remove any UIStroke if it exists
		local textStroke = nameLabel:FindFirstChild("UIStroke")
		if textStroke then
			textStroke:Destroy()
		end
	end

	-- Set up viewport
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame

	-- Get stored model from ReplicatedStorage.ViewportModels if available
	local viewportModel
	local viewportModelsFolder = ReplicatedStorage:FindFirstChild("ViewportModels")

	if viewportModelsFolder and viewportModelsFolder:FindFirstChild(player.Name) then
		-- Use the stored model
		local success
		success, viewportModel = pcall(function()
			return viewportModelsFolder[player.Name]:Clone()
		end)

		if not success or not viewportModel then
			print("Failed to clone stored model for player:", player.Name)
			viewportModel = nil
		end
	else
		print("No stored model found for player:", player.Name)
		viewportModel = nil
	end

	-- Skip rendering if no model available
	if not viewportModel then
		-- Just display name without model
		if nameLabel then
			nameLabel.Text = player.Name
			nameLabel.TextTransparency = 0
		end
		return billboard
	end

	viewportModel.Parent = worldModel

	-- Create camera exactly as in working code
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 25

	-- Direct access to Head
	if viewportModel:FindFirstChild("Head") then
		viewportCamera.CFrame = CFrame.new(
			(viewportModel.Head.CFrame * CFrame.new(0, 0, -5)).Position + Vector3.new(3, 0, 0), 
			viewportModel.Head.Position
		)
	end

	-- Set CurrentCamera without parenting
	viewportFrame.CurrentCamera = viewportCamera

	-- Parent billboard to PlayerGUI
	billboard.Parent = PlayerUI

	-- Visibility state tracking
	local isVisible = false
	local tweenDuration = 0.3

	-- Function to fade in the billboard
	local function fadeInBillboard()
		if not isVisible then
			isVisible = true
			billboard.Enabled = true

			-- Tween viewportFrame and nameLabel simultaneously
			ViewportMethods.CreateTweenAsync(viewportFrame, TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {ImageTransparency = 0})

			-- Tween nameLabel if it exists
			if nameLabel then
				ViewportMethods.CreateTweenAsync(nameLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {TextTransparency = 0})
			end
		end
	end

	-- Function to fade out the billboard
	local function fadeOutBillboard()
		if isVisible then
			isVisible = false

			-- Tween viewportFrame
			local fadeTween = TS:Create(viewportFrame, TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {ImageTransparency = 1})
			fadeTween:Play()

			-- Tween nameLabel if it exists
			if nameLabel then
				ViewportMethods.CreateTweenAsync(nameLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {TextTransparency = 1})
			end

			-- Disable billboard after fade completes
			fadeTween.Completed:Connect(function()
				if billboard and billboard.Parent and not isVisible then
					billboard.Enabled = false
				end
			end)
		end
	end

	-- Set up visibility check using RunService
	local MAX_VISIBILITY_DISTANCE = 40 -- Maximum distance in studs for billboard visibility
	local UPDATE_FREQUENCY = 5 -- Check visibility every 5 frames to reduce performance impact
	local frameCounter = 0

	local visibilityConnection
	visibilityConnection = RS.RenderStepped:Connect(function()
		-- Skip frames to reduce performance impact
		frameCounter = frameCounter + 1
		if frameCounter < UPDATE_FREQUENCY then return end
		frameCounter = 0

		-- Check if both characters exist
		local localCharacter = Player.Character
		if not localCharacter or not character or not character.Parent then
			fadeOutBillboard()
			return
		end

		local localHumanoidRootPart = localCharacter:FindFirstChild("HumanoidRootPart")
		if not localHumanoidRootPart or not humanoidRootPart or not humanoidRootPart.Parent then
			fadeOutBillboard()
			return
		end

		-- Check distance (quick early out for performance)
		local distance = (localHumanoidRootPart.Position - humanoidRootPart.Position).Magnitude
		if distance > MAX_VISIBILITY_DISTANCE then
			fadeOutBillboard()
			return
		end

		-- Check if target is in camera view
		local camera = workspace.CurrentCamera
		local _, onScreen = camera:WorldToScreenPoint(humanoidRootPart.Position)
		if not onScreen then
			fadeOutBillboard()
			return
		end

		-- Check line of sight (with performance optimization)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {localCharacter, character} -- Exclude both characters

		local cameraPosition = camera.CFrame.Position
		local direction = (humanoidRootPart.Position - cameraPosition).Unit
		local rayResult = workspace:Raycast(cameraPosition, direction * distance, raycastParams)

		-- If ray hits something, it means there's an obstacle
		if rayResult then
			fadeOutBillboard()
		else
			fadeInBillboard()
		end
	end)

	-- Handle cleanup when character changes
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			if visibilityConnection then
				visibilityConnection:Disconnect()
			end

			local existingBillboard = PlayerUI:FindFirstChild(billboardName)
			if existingBillboard then
				existingBillboard:Destroy()
			end
		end
	end)

	-- Clean up on death
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if visibilityConnection then
				visibilityConnection:Disconnect()
			end

			local existingBillboard = PlayerUI:FindFirstChild(billboardName)
			if existingBillboard then
				existingBillboard:Destroy()
			end
		end)
	end

	-- Debug calculation
	print("Character height for", player.Name, "calculated as", characterHeight, "studs")

	return billboard
end

-- Updated to remove billboards and clean up connections
function ViewportMethods.RemovePlayerBillboard(player)
	local billboardName = "PlayerViewportBillboard_" .. player.UserId
	local existingBillboard = PlayerUI:FindFirstChild(billboardName)

	if existingBillboard then
		existingBillboard:Destroy()
	end
end

-- Add/replace this function in your ViewportMethods module

-- Function to create character viewport for kill feed with better framing
-- Function to create character viewport for kill feed with preservation of special elements
function ViewportMethods.CreateKillFeedViewport(viewportFrame, playerName)
	-- Save any elements we want to preserve (like the skull)
	local skullElement = viewportFrame:FindFirstChild("Skull")
	if skullElement then
		skullElement.Parent = nil  -- Temporarily remove from hierarchy to prevent destruction
	end

	-- Clear other existing content
	for _, child in pairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	-- Create WorldModel
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame

	-- Get stored model from ReplicatedStorage.ViewportModels
	local viewportModelsFolder = ReplicatedStorage:FindFirstChild("ViewportModels")
	if not viewportModelsFolder or not viewportModelsFolder:FindFirstChild(playerName) then
		print("No stored model found for player:", playerName)

		-- Re-parent preserved elements before returning
		if skullElement then
			skullElement.Parent = viewportFrame
		end
		return false
	end

	-- Clone the stored model
	local success, viewportModel
	success, viewportModel = pcall(function()
		return viewportModelsFolder[playerName]:Clone()
	end)

	if not success or not viewportModel then
		print("Failed to clone stored model for player:", playerName)

		-- Re-parent preserved elements before returning
		if skullElement then
			skullElement.Parent = viewportFrame
		end
		return false
	end

	-- Parent model to WorldModel
	viewportModel.Parent = worldModel

	-- Create camera
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 25

	-- Position camera to frame the head better
	if viewportModel:FindFirstChild("Head") then
		viewportCamera.CFrame = CFrame.new(
			(viewportModel.Head.CFrame * CFrame.new(0, 0, -5)).Position + Vector3.new(3, 0, 0), 
			viewportModel.Head.Position
		)
	end

	-- Set viewport camera
	viewportFrame.CurrentCamera = viewportCamera

	-- Re-parent preserved elements
	if skullElement then
		skullElement.Parent = viewportFrame
	end

	return true
end

return ViewportMethods