local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local ClientMethods = require(ReplicatedStorage.ClientMethods)
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Debounce system to prevent multiple updates running at once
local updateDebounce = false
local needsUpdate = false

-- Targeted prompt disabling based on role
local function updatePromptsBasedOnRole()
	-- Prevent multiple updates running simultaneously
	if updateDebounce then
		needsUpdate = true
		return
	end

	updateDebounce = true

	-- Check player's current role
	local playerRole = LocalPlayer:GetAttribute("Role")
	local isHunter = (playerRole == "Hunter")

	-- Rather than scanning entire workspace, find ActiveMap
	local activeMap = workspace:FindFirstChild("ActiveMap")
	if activeMap then
		-- Get all props in the active map using :GetChildren() not :GetDescendants()
		local props = {}

		-- Find all props efficiently without recursion
		for _, container in ipairs(activeMap:GetChildren()) do
			if container:IsA("Model") then
				for _, item in ipairs(container:GetChildren()) do
					if item.Name == "Prop" then
						table.insert(props, item)
					end
				end
			elseif container.Name == "Prop" then
				table.insert(props, container)
			end
		end

		-- Process only the props we found
		for _, prop in ipairs(props) do
			local trigger = prop:FindFirstChild("Trigger")
			if trigger then
				local prompt = trigger:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					-- Disable prompts for hunters, enable for props
					prompt.Enabled = not isHunter
				end
			end
		end
	end

	-- Release debounce with slight delay to prevent rapid repeated calls
	task.delay(0.1, function()
		updateDebounce = false
		if needsUpdate then
			needsUpdate = false
			updatePromptsBasedOnRole()
		end
	end)
end

-- Only update on role change
LocalPlayer:GetAttributeChangedSignal("Role"):Connect(updatePromptsBasedOnRole)

-- Update when a new map loads
workspace.ChildAdded:Connect(function(child)
	if child.Name == "ActiveMap" then
		-- Wait a moment for map to fully load before updating prompts
		task.delay(1, updatePromptsBasedOnRole)
	end
end)

-- PROMPT EVENT HANDLERS

PPS.PromptShown:Connect(function(ThePrompt)
	-- Check if this is a prop trigger and the player is a hunter
	local playerRole = LocalPlayer:GetAttribute("Role")
	local isHunter = (playerRole == "Hunter")

	-- If this is a prop trigger and player is a hunter, disable it
	if isHunter and ThePrompt.Parent and 
		ThePrompt.Parent.Name == "Trigger" and 
		ThePrompt.Parent.Parent and 
		ThePrompt.Parent.Parent.Name == "Prop" then

		ThePrompt.Enabled = false
		return
	end

	ClientMethods.RenderPromptHighlight(ThePrompt)
end)

PPS.PromptHidden:Connect(function(ThePrompt)
	ClientMethods.ClosePromptHighlight(ThePrompt)
end)

PPS.PromptButtonHoldBegan:Connect(function(ThePrompt)
	local playerRole = LocalPlayer:GetAttribute("Role")
	if playerRole == "Hunter" and isPropPrompt(ThePrompt) then return end
	ClientMethods.PromptHoldBegan(ThePrompt)
end)

PPS.PromptButtonHoldEnded:Connect(function(ThePrompt)
	local playerRole = LocalPlayer:GetAttribute("Role")
	if playerRole == "Hunter" and isPropPrompt(ThePrompt) then return end
	ClientMethods.PromptHoldEnded(ThePrompt)
end)

PPS.PromptTriggered:Connect(function(ThePrompt)
	local playerRole = LocalPlayer:GetAttribute("Role")
	if playerRole == "Hunter" and isPropPrompt(ThePrompt) then return end
	ClientMethods.PromptTriggered(ThePrompt)
end)

-- Helper function to check if prompt is for prop transformation
function isPropPrompt(prompt)
	return prompt.Parent and 
		prompt.Parent.Name == "Trigger" and 
		prompt.Parent.Parent and 
		prompt.Parent.Parent.Name == "Prop"
end

-- Initial update when the script first runs
task.spawn(function()
	-- Wait for role assignment
	for _ = 1, 10 do  -- Try for 1 second max
		if LocalPlayer:GetAttribute("Role") then
			updatePromptsBasedOnRole()
			break
		end
		task.wait(0.1)
	end
end)