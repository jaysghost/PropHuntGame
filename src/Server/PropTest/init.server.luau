local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local CollectionService = game:GetService("CollectionService")
local Constants = require(ReplicatedStorage.Blaster.Constants)

-- Import the DuplicateManager module
local DuplicateManager = require(script.DuplicateManager)
local PropHealthSystem = require(script.Parent.PropHealthSystem)

-- Store the last initial direction for each player
local playerInitialDirections = {}

-- Create an instance of the DuplicateManager
local duplicateManagerInstance = DuplicateManager.new()

-- Function to find absolute ground level (PROP-SPECIFIC UTILITY)
local function findAbsoluteGroundLevel(character)
	local rootPart = character.HumanoidRootPart
	local ray = Ray.new(rootPart.Position, Vector3.new(0, -10, 0))
	local part, position = workspace:FindPartOnRay(ray, character)

	if part then
		return position.Y
	end

	return rootPart.Position.Y
end

-- Function to handle prop transformation
local function transformPlayer(player, prop)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Clean up any existing transform first
	local function cleanupTransform()
		if not character then return end

		local currentHumanoid = character:FindFirstChild("Humanoid")
		if currentHumanoid then
			currentHumanoid.AutoRotate = true  -- Re-enable default rotation
		end

		-- Restore character visibility
		for _, part in ipairs(character:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			end

			if part:IsA("Accessory") or part:IsA("Hat") then
				if part:FindFirstChild("Handle") then
					part.Handle.Transparency = 0
					local mesh = part.Handle:FindFirstChild("Mesh") or part.Handle:FindFirstChild("SpecialMesh")
					if mesh and mesh:IsA("SpecialMesh") then
						pcall(function()
							mesh.Transparency = 0
						end)
					end
				end
			end
		end

		-- Remove prop model
		local propModel = character:FindFirstChild("PropModel")
		if propModel then
			propModel:Destroy()
		end
	end

	-- Call cleanup first
	cleanupTransform()

	-- Get original positions
	local rootPart = character.HumanoidRootPart

	-- Hide character parts and accessories
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 1
		end
		if part:IsA("Accessory") or part:IsA("Hat") then
			if part:FindFirstChild("Handle") then
				part.Handle.Transparency = 1
				part.Handle.CanCollide = false
				if not CollectionService:HasTag(part.Handle, Constants.RAY_EXCLUDE_TAG) then
					CollectionService:AddTag(part.Handle, Constants.RAY_EXCLUDE_TAG)
				end
				local mesh = part.Handle:FindFirstChild("Mesh") or part.Handle:FindFirstChild("SpecialMesh")
				if mesh and mesh:IsA("SpecialMesh") then
					pcall(function()
						mesh.Transparency = 1
					end)
				end
			end
		end
	end

	-- Clone and set up the new prop
	local propModel = prop:Clone()
	propModel.Name = "PropModel"

	-- Remove trigger
	local trigger = propModel:FindFirstChild("Trigger")
	if trigger then
		trigger:Destroy()
	end

	-- Get the base for initial positioning
	local base = propModel:FindFirstChild("Base")
	if not base then return end

	-- Find the absolute ground level
	local absoluteGroundLevel = findAbsoluteGroundLevel(character)

	-- Calculate initial transform using base part
	local newPropCFrame = CFrame.new(
		rootPart.Position.X, 
		absoluteGroundLevel + (base.Size.Y / 2), 
		rootPart.Position.Z
	) * (base.CFrame - base.CFrame.Position)

	propModel:PivotTo(newPropCFrame)
	rootPart.CFrame = CFrame.new(rootPart.Position) * (base.CFrame - base.CFrame.Position)

	-- Now remove the base part
	base:Destroy()

	-- Parent the model after positioning
	propModel.Parent = character

	-- Create welds for remaining parts
	for _, part in ipairs(propModel:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Remove any existing welds
			for _, weld in ipairs(part:GetChildren()) do
				if weld:IsA("WeldConstraint") and weld.Part0 == character.HumanoidRootPart then
					weld:Destroy()
				end
			end

			-- Create new weld
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.HumanoidRootPart
			weld.Part1 = part
			weld.Parent = part
			part.CanCollide = false
			part.Anchored = false
		end
	end
	
	PropHealthSystem.createHighlight(character)
	-- Reset rotation index
	RemoteEvent:FireClient(player, "ResetRotation")
	RemoteEvent:FireAllClients("PlayerTransformed", player)
end

-- Function to handle prop rotation
local function handlePropRotation(player, rotationDirection)
	-- Broadcast rotation event to all clients
	RemoteEvent:FireAllClients("PropRotationEvent", player, rotationDirection)
end

-- Main event handler
RemoteEvent.OnServerEvent:Connect(function(player, eventName, ...)
	if eventName == "PropInitialDirection" then
		local direction = ...
		playerInitialDirections[player.UserId] = direction
	elseif eventName == "PropRotationEvent" then
		handlePropRotation(player, ...)
	elseif eventName == "DuplicateAbility" then
		duplicateManagerInstance:HandleDuplicateAbility(player, RemoteEvent)
	end
end)

-- Initial server setup
local function init()
	-- Initialize the duplicate manager
	duplicateManagerInstance:InitializeServer(Players, RemoteEvent)

	-- Connect to prompt triggered events
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local trigger = prompt.Parent
		if trigger and trigger.Name == "Trigger" then
			local prop = trigger.Parent
			if prop and prop.Name == "Prop" then
				transformPlayer(player, prop)
			end
		end
	end)
end

init()