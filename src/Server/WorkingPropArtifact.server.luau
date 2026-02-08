local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Function to find the absolute ground level
local function findAbsoluteGroundLevel(character)
	local rootPart = character.HumanoidRootPart
	local ray = Ray.new(rootPart.Position, Vector3.new(0, -10, 0))
	local part, position = workspace:FindPartOnRay(ray, character)

	if part then
		return position.Y
	end

	return rootPart.Position.Y
end

-- Function to create ProximityPrompts for all props
local function setupPropPrompts()
	local props = workspace:GetChildren()

	for _, prop in ipairs(props) do
		if prop.Name == "Prop" then
			local trigger = prop:FindFirstChild("Trigger")
			if trigger and trigger:IsA("BasePart") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ObjectText = "Transform into " .. prop.Name
				prompt.ActionText = "Hold to Transform"
				prompt.HoldDuration = 0.5
				prompt.RequiresLineOfSight = true
				prompt.MaxActivationDistance = 10
				prompt.Parent = trigger
			end
		end
	end
end

-- Function to transform player into prop
local function transformPlayer(player, prop)
	local character = player.Character
	if not character then return end

	-- Get original orientations and positions
	local rootPart = character.HumanoidRootPart
	local originalRootCFrame = rootPart.CFrame
	local originalPropCFrame = prop:GetPivot()

	-- Hide character parts and accessories
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 1
		end

		if part:IsA("Accessory") or part:IsA("Hat") then
			if part:FindFirstChild("Handle") then
				part.Handle.Transparency = 1
				local mesh = part.Handle:FindFirstChild("Mesh") or part.Handle:FindFirstChild("SpecialMesh")
				if mesh and mesh:IsA("SpecialMesh") then
					pcall(function()
						mesh.Transparency = 1
					end)
				end
			end
		end
	end

	-- Remove any existing prop model
	local existingProp = character:FindFirstChild("PropModel")
	if existingProp then
		existingProp:Destroy()
	end

	-- Clone and set up the new prop
	local propModel = prop:Clone()
	propModel.Name = "PropModel"

	-- Remove trigger
	local trigger = propModel:FindFirstChild("Trigger")
	if trigger then
		trigger:Destroy()
	end

	-- Set up all parts in the prop model
	for _, part in ipairs(propModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
		end
	end

	-- Parent the model
	propModel.Parent = character

	-- Get the original orientation of the prop
	local propX, _, propZ = originalPropCFrame:ToEulerAnglesXYZ()

	-- Get character Y rotation
	local _, charY, _ = originalRootCFrame:ToEulerAnglesXYZ()

	-- Find the Base part
	local base = propModel:FindFirstChild("Base")
	if not base then return end

	-- Find the absolute ground level
	local absoluteGroundLevel = findAbsoluteGroundLevel(character)

	-- Calculate ground position
	-- Raise by half the base height to ensure it sits flat on the floor
	local newCFrame = CFrame.new(rootPart.Position.X, absoluteGroundLevel + (base.Size.Y / 2), rootPart.Position.Z) * 
		CFrame.fromEulerAnglesXYZ(propX, charY, propZ)

	-- Position the model
	propModel:PivotTo(newCFrame)

	-- Create weld for each part to HumanoidRootPart
	for _, part in ipairs(propModel:GetDescendants()) do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.HumanoidRootPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	-- Apply a small correction for mesh-based props
	local hasMesh = false
	for _, desc in ipairs(propModel:GetDescendants()) do
		if desc:IsA("MeshPart") or desc:IsA("SpecialMesh") then
			hasMesh = true
			break
		end
	end

	if hasMesh then
		propModel:PivotTo(newCFrame * CFrame.new(0, -0.1, 0))
	end
end

-- Function to handle prompt triggers
local function onPromptTriggered(prompt, player)
	local trigger = prompt.Parent
	if trigger and trigger.Name == "Trigger" then
		local prop = trigger.Parent
		if prop and prop.Name == "Prop" then
			transformPlayer(player, prop)
		end
	end
end

-- Setup when server starts
local function init()
	setupPropPrompts()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Prop" then
			task.wait()
			setupPropPrompts()
		end
	end)
end

init()