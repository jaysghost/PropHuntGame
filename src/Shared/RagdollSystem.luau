-- RagdollSystem.lua
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RagdollSystem = {}

function RagdollSystem.applyRagdoll(character)
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Find PropModel if it exists
	local propModel = character:FindFirstChild("PropModel")
	local isPropPlayer = (propModel ~= nil)

	-- Special handling for prop players
	if isPropPlayer then
		-- Step 1: Detach prop from character by removing all welds
		for _, part in pairs(propModel:GetDescendants()) do
			if part:IsA("BasePart") then
				-- Find and remove all welds connecting to HumanoidRootPart
				for _, weld in pairs(part:GetChildren()) do
					if weld:IsA("WeldConstraint") and weld.Part0 and 
						weld.Part0.Name == "HumanoidRootPart" then
						weld:Destroy()
					end
				end

				-- Save original position for visual effects
				part:SetAttribute("OriginalCFrame", part.CFrame)
				part.Anchored = true -- Temporarily anchor to maintain position
			end
		end

		-- Step 2: Make character parts visible again (needed for proper ragdolling)
		for _, part in pairs(character:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("MeshPart")) and 
				part.Name ~= "HumanoidRootPart" and 
				not part:IsDescendantOf(propModel) then
				part.Transparency = 0 -- Make character visible for physics
			end
		end

		-- Step 3: Clone the prop model for visual effects
		local visualPropModel = propModel:Clone()
		visualPropModel.Name = "VisualPropModel"

		-- Make the clone non-collidable and detached from character physics
		for _, part in pairs(visualPropModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = true

				-- Make sure it maintains its position relative to workspace
				if propModel:FindFirstChild(part.Name) and 
					propModel[part.Name]:IsA("BasePart") then
					part.CFrame = propModel[part.Name].CFrame
				end
			end
		end

		visualPropModel.Parent = workspace -- Parent to workspace so it stays when character is removed

		-- Schedule cleanup of the visual model
		task.delay(5, function()
			if visualPropModel and visualPropModel:IsDescendantOf(game) then
				visualPropModel:Destroy()
			end
		end)

		-- Step 4: Create visual "breaking apart" effect for the prop
		task.spawn(function()
			-- Wait a tiny bit for ragdoll to start
			task.wait(0.1)

			-- For each part in the visual model, apply random forces
			for _, part in pairs(visualPropModel:GetDescendants()) do
				if part:IsA("BasePart") then
					-- Random offset for "breaking apart" effect
					local randomOffset = Vector3.new(
						math.random(-20, 20) / 10,
						math.random(-5, 15) / 10, -- Slight upward bias
						math.random(-20, 20) / 10
					)

					-- Random rotation
					local randomAngleX = math.rad(math.random(-30, 30))
					local randomAngleY = math.rad(math.random(-30, 30))
					local randomAngleZ = math.rad(math.random(-30, 30))

					-- Create target position
					local startCFrame = part.CFrame
					local targetCFrame = startCFrame * 
						CFrame.new(randomOffset) * 
						CFrame.Angles(randomAngleX, randomAngleY, randomAngleZ)

					-- Animate the part "breaking off"
					local tween = TweenService:Create(
						part,
						TweenInfo.new(
							0.5 + (math.random() * 0.5), -- Random duration for natural look
							Enum.EasingStyle.Bounce,
							Enum.EasingDirection.Out
						),
						{CFrame = targetCFrame}
					)
					tween:Play()

					-- After movement, fade out
					task.delay(0.5 + (math.random() * 0.5), function()
						if part and part:IsDescendantOf(game) then
							local fadeTween = TweenService:Create(
								part,
								TweenInfo.new(1, Enum.EasingStyle.Sine),
								{Transparency = 1}
							)
							fadeTween:Play()
						end
					end)
				end
			end
		end)

		-- Now remove the original prop model to allow proper ragdolling
		propModel:Destroy()
	end

	-- Apply standard ragdoll - by this point, the prop has been detached
	-- and we're working with a normal character

	-- Basic ragdoll setup
	humanoid.BreakJointsOnDeath = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Make the ragdoll more lifeless with subtle changes
	for _, joint in pairs(character:GetDescendants()) do
		if joint:IsA("Motor6D") then
			if joint.Name == "Neck" then
				-- Create a weld for the head - keeps head from wobbling
				local weld = Instance.new("WeldConstraint")
				pcall(function()
					weld.Part0 = joint.Part0
					weld.Part1 = joint.Part1
					weld.Parent = joint.Parent
					joint.Enabled = false
				end)
			elseif joint.Name ~= "Root" and joint.Name ~= "RootJoint" then
				-- Create ball socket for limbs with more restrictive movement
				pcall(function()
					local socket = Instance.new("BallSocketConstraint")
					local a1 = Instance.new("Attachment")
					local a2 = Instance.new("Attachment")
					a1.Parent = joint.Part0
					a2.Parent = joint.Part1
					a1.CFrame = joint.C0
					a2.CFrame = joint.C1

					-- More restrictive angle for less movement
					socket.Attachment0 = a1
					socket.Attachment1 = a2
					socket.LimitsEnabled = true
					socket.UpperAngle = 30

					-- Add twist limits for more restricted motion
					socket.TwistLimitsEnabled = true
					socket.TwistLowerAngle = -20
					socket.TwistUpperAngle = 20

					socket.Parent = joint.Parent
					joint.Enabled = false
				end)
			end
		end
	end

	-- Make HumanoidRootPart non-collidable
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.CanCollide = false
	end

	-- Add damping to reduce jitter
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			-- Increase mass slightly and add high friction for more stability
			pcall(function()
				part.CustomPhysicalProperties = PhysicalProperties.new(
					part.CustomPhysicalProperties and part.CustomPhysicalProperties.Density or 0.7,
					0.05,  -- Very low elasticity
					0.95,  -- High friction
					1,
					1
				)

				-- Add a damping object to reduce oscillation
				local damper = Instance.new("LinearVelocity")
				damper.VectorVelocity = Vector3.new(0, 0, 0)
				damper.MaxForce = 1000
				damper.RelativeTo = Enum.ActuatorRelativeTo.World
				damper.Attachment0 = Instance.new("Attachment")
				damper.Attachment0.Parent = part
				damper.P = 200  -- Lower value = more damping
				damper.Parent = part
			end)
		end
	end

	-- If this was not a prop player, fade out normally
	if not isPropPlayer then
		-- Delay character parts tween
		task.delay(3, function()
			if character and character:IsDescendantOf(game) then
				for _, part in pairs(character:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						-- Delayed tween for character parts
						local charTween = TweenService:Create(
							part,
							TweenInfo.new(1, Enum.EasingStyle.Sine),
							{Transparency = 1}
						)
						charTween:Play()
					end
				end
			end
		end)
	else
		-- For prop players, fade the character more quickly
		task.delay(3, function()
			if character and character:IsDescendantOf(game) then
				for _, part in pairs(character:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						local charTween = TweenService:Create(
							part,
							TweenInfo.new(0.5, Enum.EasingStyle.Sine),
							{Transparency = 1}
						)
						charTween:Play()
					end
				end
			end
		end)
	end

	return true
end

return RagdollSystem