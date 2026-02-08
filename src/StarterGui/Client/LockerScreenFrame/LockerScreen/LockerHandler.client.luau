local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvent = ReplicatedStorage.RemoteEvent
local TweenMethods = require(ReplicatedStorage:WaitForChild("TweenMethods"))
local WeaponData = require(ReplicatedStorage.Data.WeaponData)
local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
local DeathSoundData = require(ReplicatedStorage.Data.DeathSoundData)
local TauntSoundData = require(ReplicatedStorage.Data.TauntSoundData)

local SCALE_FACTOR, FLOAT_HEIGHT, FLOAT_CYCLE_TIME = 1.03, 0.2, 2.0
local DEFAULT_FOV, SELECTED_FOV, ROTATION_TWEEN_TIME, CAMERA_DISTANCE = 35, 25, 0.5, 5

local originalProperties, trueOriginalPositions, originalStrokeThickness = {}, {}, {}
local originalCameraFOV, cameraFOVMonitor, currentFOVTween, currentSelectedTemplate, currentSelectedWeapon = nil, nil, nil, nil, nil
local currentVisibleEquipButton, currentSelectedSoundTemplate, currentSelectedSound, currentSoundInstance = nil, nil, nil, nil
local floatingAnimations, viewportTweens, activeTweens, soundPreviewStates, UICache = {}, {}, {}, {}, {}
local currentSelectedTauntTemplate, currentSelectedTaunt, currentTauntSoundInstance = nil, nil, nil
local currentVisibleTauntEquipButton = nil
local tauntPreviewStates = {}
local lockerState = {isOpen = false, currentPanel = nil}
local originalLockerHeaderValues = {gradientColors = nil, text = nil}


local function cacheLockerHeaderValues(lockerScreen)
	if originalLockerHeaderValues.gradientColors then return end
	local lockerNameHolder = lockerScreen:FindFirstChild("LockerNameHolder")
	if not lockerNameHolder then return end
	local lockerName = lockerNameHolder:FindFirstChild("LockerName")
	if not lockerName then return end
	originalLockerHeaderValues.text = lockerName.Text
	local gradient = lockerName:FindFirstChildOfClass("UIGradient")
	if gradient then originalLockerHeaderValues.gradientColors = gradient.Color end
end

local function updateLockerHeader(lockerScreen, panelName, tweenOut)
	local lockerNameHolder = lockerScreen:FindFirstChild("LockerNameHolder")
	if not lockerNameHolder then return end
	local lockerName = lockerNameHolder:FindFirstChild("LockerName")
	if not lockerName then return end
	local gradient = lockerName:FindFirstChildOfClass("UIGradient")
	if not gradient then return end
	cacheLockerHeaderValues(lockerScreen)
	if tweenOut then return end

	if panelName == "weapons" then
		lockerName.Text = "weapons"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(255, 0, 0)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "deathsounds" then
		lockerName.Text = "death sounds"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(0, 170, 0)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "taunts" then
		lockerName.Text = "taunts"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(0, 170, 255)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "meleeweapons" then
		lockerName.Text = "melee weapons"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(255, 85, 0)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "main" or panelName == "options" then
		lockerName.Text = originalLockerHeaderValues.text or "locker"
		if gradient and originalLockerHeaderValues.gradientColors then
			gradient.Color = originalLockerHeaderValues.gradientColors
		end
	end
end

local function findUI(parent, name, recursive)
	return recursive and parent:FindFirstChild(name, true) or parent:FindFirstChild(name)
end

local function copyGradientProperties(sourceGradient, targetGradient)
	if not sourceGradient or not targetGradient then return end
	targetGradient.Color = sourceGradient.Color
	targetGradient.Transparency = sourceGradient.Transparency
	targetGradient.Rotation = sourceGradient.Rotation
	targetGradient.Offset = sourceGradient.Offset
	targetGradient.Enabled = sourceGradient.Enabled
end

local function applyGradientToElement(sourceGradient, targetElement, gradientName)
	if not sourceGradient or not targetElement then return end
	local targetGradient = targetElement:FindFirstChild(gradientName)
	if not targetGradient then
		targetGradient = Instance.new("UIGradient")
		targetGradient.Name = gradientName
		targetGradient.Parent = targetElement
	end
	copyGradientProperties(sourceGradient, targetGradient)
end

local function playSoundByName(element, soundName)
	local sound = element:FindFirstChild(soundName, true)
	if not sound then
		local player = Players.LocalPlayer
		if player and player.PlayerGui then
			sound = player.PlayerGui:FindFirstChild(soundName, true)
		end
	end
	if sound and sound:IsA("Sound") then
		if sound.IsPlaying then sound:Stop() end
		sound:Play()
		return true
	end
	return false
end

local function setElementTransparency(element, transparent, tweenInfo)
	local transparencyProps = {"BackgroundTransparency", "TextTransparency", "ImageTransparency"}
	for _, prop in ipairs(transparencyProps) do
		if pcall(function() return element[prop] ~= nil end) then
			if transparent and not element:GetAttribute("Original" .. prop) then
				element:SetAttribute("Original" .. prop, element[prop])
			end
			if tweenInfo then
				TweenMethods.CreateTweenAsync(element, tweenInfo, {
					[prop] = transparent and 1 or element:GetAttribute("Original" .. prop) or 0
				})
			else
				element[prop] = transparent and 1 or element:GetAttribute("Original" .. prop) or 0
			end
		end
	end

	local stroke = element:FindFirstChildOfClass("UIStroke")
	if stroke then
		if transparent and not stroke:GetAttribute("OriginalTransparency") then
			stroke:SetAttribute("OriginalTransparency", stroke.Transparency)
		end
		if transparent and not stroke:GetAttribute("OriginalThickness") then
			stroke:SetAttribute("OriginalThickness", stroke.Thickness)
		end
		if tweenInfo then
			TweenMethods.CreateTweenAsync(stroke, tweenInfo, {
				Transparency = transparent and 1 or stroke:GetAttribute("OriginalTransparency") or 0,
				Thickness = transparent and 0 or stroke:GetAttribute("OriginalThickness") or 1
			})
		else
			stroke.Transparency = transparent and 1 or stroke:GetAttribute("OriginalTransparency") or 0
			stroke.Thickness = transparent and 0 or stroke:GetAttribute("OriginalThickness") or 1
		end
	end

	for _, child in ipairs(element:GetChildren()) do
		setElementTransparency(child, transparent, tweenInfo)
	end
end

local function setupCameraEffects()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if not originalCameraFOV then originalCameraFOV = camera.FieldOfView end
	local dof = camera:FindFirstChildOfClass("DepthOfFieldEffect")
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Enabled = false
		dof.FarIntensity = 0
		dof.FocusDistance = 0.05
		dof.InFocusRadius = 10
		dof.NearIntensity = 0
		dof.Parent = camera
	end
	return dof
end

local function toggleCameraEffects(enable)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if cameraFOVMonitor then cameraFOVMonitor:Disconnect(); cameraFOVMonitor = nil end
	if not originalCameraFOV then originalCameraFOV = camera.FieldOfView end
	local dof = camera:FindFirstChildOfClass("DepthOfFieldEffect") or setupCameraEffects()

	if enable then
		dof.Enabled = true
		TweenMethods.CreateTweenAsync(dof, TweenMethods.HalfSecondSineData, {
			InFocusRadius = 0, FarIntensity = 1
		})
		local targetFOV = originalCameraFOV - 10
		TweenMethods.CreateTweenAsync(camera, TweenMethods.HalfSecondSineData, {
			FieldOfView = targetFOV
		})
		task.delay(0.5, function()
			if cameraFOVMonitor then cameraFOVMonitor:Disconnect() end
			cameraFOVMonitor = RunService.RenderStepped:Connect(function()
				if camera.FieldOfView ~= targetFOV then camera.FieldOfView = targetFOV end
			end)
		end)
	else
		if currentFOVTween then currentFOVTween:Cancel(); currentFOVTween = nil end
		if cameraFOVMonitor then cameraFOVMonitor:Disconnect(); cameraFOVMonitor = nil end
		if originalCameraFOV then
			TweenMethods.CreateTweenAsync(camera, TweenMethods.ReturnSineData(0.2), {
				FieldOfView = originalCameraFOV
			})
		end
		if dof then
			TweenMethods.CreateTweenAsync(dof, TweenMethods.ReturnSineData(0.2), {
				InFocusRadius = 10, FarIntensity = 0
			})
			task.delay(0.2, function() dof.Enabled = false end)
		end
	end
end

local function setupWeaponViewport(viewportFrame, weaponId)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if not child:IsA("Camera") then child:Destroy() end
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewportFrame

	local weaponModelPath = game:GetService("ReplicatedStorage"):FindFirstChild("ViewportModels")
	if not weaponModelPath then return false end
	local weaponsFolder = weaponModelPath:FindFirstChild("Weapons")
	if not weaponsFolder then return false end
	local weaponModel = weaponsFolder:FindFirstChild(weaponId)
	if not weaponModel then return false end

	local modelClone = weaponModel:Clone()
	modelClone.Parent = worldModel

	if not viewportFrame.CurrentCamera then
		local camera = Instance.new("Camera")
		camera.FieldOfView = 25
		viewportFrame.CurrentCamera = camera
		camera.Parent = viewportFrame
	else
		viewportFrame.CurrentCamera.FieldOfView = DEFAULT_FOV
	end

	local refPart = nil
	if modelClone:IsA("Model") then
		refPart = modelClone:FindFirstChild("CameraRef", true)
	else
		refPart = modelClone:FindFirstChild("CameraRef")
	end

	if refPart and refPart:IsA("BasePart") then
		local cameraPosition = refPart.Position + Vector3.new(CAMERA_DISTANCE * 0.7, CAMERA_DISTANCE * 0.1, CAMERA_DISTANCE * 0.7)
		viewportFrame.CurrentCamera.CFrame = CFrame.new(cameraPosition, refPart.Position)
	else
		if modelClone:IsA("Model") then
			modelClone:PivotTo(CFrame.new(0, 0, 0))
		else
			modelClone.CFrame = CFrame.new(0, 0, 0)
		end

		viewportFrame.CurrentCamera.CFrame = CFrame.new(
			Vector3.new(CAMERA_DISTANCE * 0.7, CAMERA_DISTANCE * 0.1, CAMERA_DISTANCE * 0.7),
			Vector3.new(0, 0, 0)
		)
	end

	return true
end

local function startFloatingAnimation(viewportFrame, templateId)
	if not viewportFrame then return end
	local worldModel = viewportFrame:FindFirstChild("WorldModel")
	if not worldModel then return end
	local model = worldModel:FindFirstChildOfClass("Model") or worldModel:FindFirstChildOfClass("BasePart") or worldModel:FindFirstChildOfClass("MeshPart")
	if not model then return end

	if floatingAnimations[templateId] then
		if floatingAnimations[templateId].tween then floatingAnimations[templateId].tween:Cancel() end
		if floatingAnimations[templateId].offsetValue then floatingAnimations[templateId].offsetValue:Destroy() end
		floatingAnimations[templateId] = nil
	end

	local offsetValue = Instance.new("NumberValue")
	offsetValue.Value = 0
	local initialPosition = model:IsA("Model") and model:GetPivot().Position or model.Position
	local floatData = {offsetValue = offsetValue, initialPosition = initialPosition, model = model, isModel = model:IsA("Model"), tween = nil}

	local tweenInfo = TweenInfo.new(FLOAT_CYCLE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)

	offsetValue.Changed:Connect(function()
		if not model or not model.Parent then return end
		local yOffset = offsetValue.Value * FLOAT_HEIGHT

		if floatData.isModel then
			local currentCFrame = model:GetPivot()
			local newCFrame = CFrame.new(currentCFrame.X, initialPosition.Y + yOffset, currentCFrame.Z) * currentCFrame.Rotation
			model:PivotTo(newCFrame)
		else
			model.Position = Vector3.new(model.Position.X, initialPosition.Y + yOffset, model.Position.Z)
		end
	end)

	local tween = TweenService:Create(offsetValue, tweenInfo, {Value = 1})
	tween:Play()
	floatData.tween = tween
	floatingAnimations[templateId] = floatData
end

local function stopFloatingAnimation(templateId)
	local floatData = floatingAnimations[templateId]
	if not floatData then return end

	if floatData.tween then floatData.tween:Cancel() end
	if floatData.offsetValue then floatData.offsetValue:Destroy() end

	if floatData.model and floatData.model.Parent then
		if floatData.isModel then
			local currentPivot = floatData.model:GetPivot()
			floatData.model:PivotTo(CFrame.new(floatData.initialPosition.X, floatData.initialPosition.Y, floatData.initialPosition.Z) * currentPivot.Rotation)
		else
			floatData.model.Position = floatData.initialPosition
		end
	end

	floatingAnimations[templateId] = nil
end

local function animateModelRotation(viewportFrame, weaponId)
	if not viewportFrame then return end
	local worldModel = viewportFrame:FindFirstChild("WorldModel")
	if not worldModel then return end
	local model = worldModel:FindFirstChildOfClass("Model") or worldModel:FindFirstChildOfClass("BasePart") or worldModel:FindFirstChildOfClass("MeshPart")
	if not model then return end

	local originalCFrames, partsToRotate, originPart = {}, {}, nil

	if model:IsA("Model") then
		local allParts = model:GetDescendants()
		for _, part in ipairs(allParts) do
			if part:IsA("BasePart") or part:IsA("MeshPart") then
				table.insert(partsToRotate, part)
				originalCFrames[part] = part.CFrame

				if not originPart and (part.Name == "Handle" or part.Name == "Main" or part.Name == "Primary") then
					originPart = part
				end
			end
		end

		if not originPart and #partsToRotate > 0 then originPart = partsToRotate[1] end
	else
		table.insert(partsToRotate, model)
		originalCFrames[model] = model.CFrame
		originPart = model
	end

	if #partsToRotate == 0 then return end
	local originCFrame = originPart and originPart.CFrame or CFrame.new(0, 0, 0)
	local progressValue = Instance.new("NumberValue")
	progressValue.Value = 0

	progressValue.Changed:Connect(function()
		local progress = progressValue.Value
		local rotationCFrame = CFrame.Angles(0, math.rad(progress * 360), 0)

		for _, part in ipairs(partsToRotate) do
			if part and part.Parent then
				local originalCF = originalCFrames[part]
				if originalCF then
					local relativeCF = originCFrame:ToObjectSpace(originalCF)
					local rotatedCF = originCFrame * rotationCFrame * relativeCF
					part.CFrame = rotatedCF
				end
			end
		end
	end)

	local tween = TweenService:Create(progressValue, TweenInfo.new(ROTATION_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Value = 1})
	tween:Play()

	tween.Completed:Connect(function()
		progressValue.Value = 1

		task.delay(0.05, function()
			for _, part in ipairs(partsToRotate) do
				if part and part.Parent then
					local originalCF = originalCFrames[part]
					if originalCF then part.CFrame = originalCF end
				end
			end

			progressValue:Destroy()
			startFloatingAnimation(viewportFrame, "detail_" .. weaponId)
		end)
	end)
end

local function animateViewportFOV(viewportFrame, zoom)
	if not viewportFrame or not viewportFrame.CurrentCamera then return end

	if viewportTweens[viewportFrame] then
		viewportTweens[viewportFrame]:Cancel()
		viewportTweens[viewportFrame] = nil
	end

	local fovGoal = {FieldOfView = zoom and SELECTED_FOV or DEFAULT_FOV}
	local fovTween = TweenService:Create(viewportFrame.CurrentCamera, TweenInfo.new(0.75, Enum.EasingStyle.Back, Enum.EasingDirection.InOut), fovGoal)
	viewportTweens[viewportFrame] = fovTween
	fovTween:Play()
end

local function animatePanel(panel, direction, callback)
	if direction == "in" then
		panel.Visible = true

		if not trueOriginalPositions[panel] then
			trueOriginalPositions[panel] = panel.Position
		end

		panel.Position = trueOriginalPositions[panel] + UDim2.new(0, 0, 0.05, 0)
		setElementTransparency(panel, true)

		TweenMethods.CreateTweenAsync(panel, TweenMethods.HalfSecondSineData, {
			Position = trueOriginalPositions[panel]
		})

		setElementTransparency(panel, false, TweenMethods.HalfSecondSineData)

		if callback then task.delay(0.5, callback) end
	else
		if not trueOriginalPositions[panel] then
			trueOriginalPositions[panel] = panel.Position
		end

		TweenMethods.CreateTweenAsync(panel, TweenMethods.ReturnSineData(0.2), {
			Position = trueOriginalPositions[panel] + UDim2.new(0, 0, 0.05, 0)
		})

		setElementTransparency(panel, true, TweenMethods.ReturnSineData(0.2))

		task.delay(0.2, function()
			panel.Visible = false
			if callback then callback() end
		end)
	end

	return true
end

local function startGradientRotation(frame)
	local gradientData = originalProperties[frame]
	if gradientData and gradientData.Gradient then
		if gradientData.RotationConnection then
			gradientData.RotationConnection:Disconnect()
			gradientData.RotationConnection = nil
		end

		gradientData.RotationConnection = RunService.RenderStepped:Connect(function(deltaTime)
			gradientData.Gradient.Rotation = (gradientData.Gradient.Rotation + 120 * deltaTime) % 360
		end)
	end
end

local function stopGradientRotation(frame)
	local gradientData = originalProperties[frame]
	if gradientData and gradientData.RotationConnection then
		gradientData.RotationConnection:Disconnect()
		gradientData.RotationConnection = nil

		if gradientData.Gradient then
			TweenMethods.CreateTweenAsync(gradientData.Gradient, TweenMethods.PointOneSecondSineData, {
				Rotation = gradientData.GradientRotation
			})
		end
	end
end

local function onMouseEnter(frame)
	local data = originalProperties[frame]
	if not data then return end

	playSoundByName(frame, "Hover")
	startGradientRotation(frame)

	local originalSize = data.Size
	TweenMethods.CreateTweenAsync(frame, TweenMethods.PointOneSecondSineData, {
		Size = UDim2.new(
			originalSize.X.Scale * SCALE_FACTOR, 
			originalSize.X.Offset * SCALE_FACTOR,
			originalSize.Y.Scale * SCALE_FACTOR, 
			originalSize.Y.Offset * SCALE_FACTOR
		),
		Position = data.Position
	})

	if data.ImageLabel and data.ImageLabelSize then
		local originalImageSize = data.ImageLabelSize
		TweenMethods.CreateTweenAsync(data.ImageLabel, TweenMethods.PointOneSecondSineData, {
			Size = UDim2.new(
				originalImageSize.X.Scale * 1.1, 
				originalImageSize.X.Offset * 1.1,
				originalImageSize.Y.Scale * 1.1, 
				originalImageSize.Y.Offset * 1.1
			)
		})
	end

	if data.Description and data.DescriptionPosition then
		if data.LevitationTween then
			data.LevitationTween:Cancel()
			data.LevitationTween = nil
		end

		data.Description.Position = data.DescriptionPosition + UDim2.new(0, 0, 0.1, 0)

		TweenMethods.CreateTweenAsync(data.Description, TweenMethods.ReturnSineData(0.3), {
			Position = data.DescriptionPosition,
			TextTransparency = 0
		})

		task.delay(0.3, function()
			if data.LevitationTween == nil then
				local levitationTweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)
				local levitationTween = TweenService:Create(data.Description, levitationTweenInfo, 
					{Position = data.DescriptionPosition + UDim2.new(0, 0, -0.02, 0)})
				levitationTween:Play()
				data.LevitationTween = levitationTween
			end
		end)
	end
end

local function onMouseLeave(frame)
	local data = originalProperties[frame]
	if not data then return end

	stopGradientRotation(frame)

	TweenMethods.CreateTweenAsync(frame, TweenMethods.PointOneSecondSineData, {
		Size = data.Size,
		Position = data.Position
	})

	if data.ImageLabel and data.ImageLabelSize then
		TweenMethods.CreateTweenAsync(data.ImageLabel, TweenMethods.PointOneSecondSineData, {
			Size = data.ImageLabelSize
		})
	end

	if data.Description and data.DescriptionPosition then
		if data.LevitationTween then
			data.LevitationTween:Cancel()
			data.LevitationTween = nil
		end

		TweenMethods.CreateTweenAsync(data.Description, TweenMethods.ReturnSineData(0.3), {
			Position = data.DescriptionPosition,
			TextTransparency = 1
		})
	end
end

local function updateMainWeaponViewport(weaponId, weaponData)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	local client = playerGui:FindFirstChild("Client")
	local lockerScreenFrame = client:FindFirstChild("LockerScreenFrame")
	local lockerScreen = lockerScreenFrame:FindFirstChild("LockerScreen")
	local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")

	if not weaponsLockerHolder then return end

	if currentSelectedWeapon then
		stopFloatingAnimation("detail_" .. currentSelectedWeapon)
	end

	currentSelectedWeapon = weaponId

	local dropShadowHolder = weaponsLockerHolder:FindFirstChild("DropShadowHolder", true)
	local dropShadow = dropShadowHolder and dropShadowHolder:FindFirstChild("DropShadow")

	local elementsToAnimate = {
		dropShadowHolder,
		weaponsLockerHolder:FindFirstChild("WeaponViewport", true),
		weaponsLockerHolder:FindFirstChild("EquipButtonFrame", true),
		weaponsLockerHolder:FindFirstChild("Equipped", true),
		weaponsLockerHolder:FindFirstChild("DescriptionLabel", true),
		weaponsLockerHolder:FindFirstChild("ItemClass", true),
		weaponsLockerHolder:FindFirstChild("ItemName", true)
	}

	local templateFolder = game:GetService("StarterGui"):FindFirstChild("Templates")
	local isRare = weaponData.rarity and string.lower(weaponData.rarity) == "rare"

	local itemClass = weaponsLockerHolder:FindFirstChild("ItemClass", true)
	if itemClass then itemClass.Text = weaponData.rarity or "Common" end

	if dropShadow then
		local existingGradient = dropShadow:FindFirstChildWhichIsA("UIGradient")
		if existingGradient then existingGradient:Destroy() end

		if not isRare then dropShadow.ImageColor3 = Color3.new(0, 0, 0) end
	end

	if dropShadowHolder then
		local existingHolderGradient = dropShadowHolder:FindFirstChild("RarityGradient")
		if existingHolderGradient then existingHolderGradient:Destroy() end

		local dropShadowStroke = dropShadowHolder:FindFirstChildWhichIsA("UIStroke")
		if dropShadowStroke then
			local existingStrokeGradient = dropShadowStroke:FindFirstChild("RarityStrokeGradient")
			if existingStrokeGradient then existingStrokeGradient:Destroy() end
		end
	end

	if isRare and templateFolder and dropShadowHolder then
		local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")
		if rareTemplate then
			local sourceGradient = rareTemplate:FindFirstChildWhichIsA("UIGradient")
			if sourceGradient and dropShadow then
				dropShadow.ImageColor3 = Color3.new(1, 1, 1)

				local shadowGradient = Instance.new("UIGradient")
				shadowGradient.Name = "RarityGradient"
				copyGradientProperties(sourceGradient, shadowGradient)
				shadowGradient.Transparency = NumberSequence.new(0,0)
				shadowGradient.Parent = dropShadow
			end

			local templateStroke = rareTemplate:FindFirstChildWhichIsA("UIStroke")
			local dropShadowStroke = dropShadowHolder:FindFirstChildWhichIsA("UIStroke")

			if templateStroke and dropShadowStroke then
				local strokeGradient = templateStroke:FindFirstChildWhichIsA("UIGradient")
				if strokeGradient then
					applyGradientToElement(strokeGradient, dropShadowStroke, "RarityStrokeGradient")
				end
			end
		end
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end

			element.Position = trueOriginalPositions[element] + UDim2.new(0, 0, 0.1, 0)
			setElementTransparency(element, true)
			element.Visible = true
		end
	end

	local viewportFrame = nil
	local itemDescriptionHolder = weaponsLockerHolder:FindFirstChild("ItemDescriptionHolder")
	if itemDescriptionHolder then
		viewportFrame = itemDescriptionHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if not viewportFrame then
		viewportFrame = weaponsLockerHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if viewportFrame then
		setupWeaponViewport(viewportFrame, weaponId)
		animateModelRotation(viewportFrame, weaponId)
		animateViewportFOV(viewportFrame, true)
	end

	local elements = {
		ItemName = weaponData.displayName,
		ItemRarity = weaponData.rarity,
		DescriptionLabel = weaponData.description
	}

	RemoteEvent:FireServer("CheckWeaponOwnership", weaponId)

	-- Change BuyButton to EquipButton
	local equipText = weaponsLockerHolder:FindFirstChild("Equipped", true)
	if equipText then 
		-- We'll set the text when we get response from server about active status
		equipText.Text = "Loading..."
	end

	for name, value in pairs(elements) do
		local element = weaponsLockerHolder:FindFirstChild(name, true)
		if element then element.Text = value end
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			TweenMethods.CreateTweenAsync(element, TweenMethods.HalfSecondSineData, {
				Position = trueOriginalPositions[element]
			})

			setElementTransparency(element, false, TweenMethods.HalfSecondSineData)
		end
	end

	-- IMPORTANT: Store the selected weapon ID in the holder
	weaponsLockerHolder:SetAttribute("SelectedWeaponId", weaponId)

	-- Get the equip button and set up interaction with the correct weapon ID
	local equipButtonFrame = weaponsLockerHolder:FindFirstChild("EquipButtonFrame", true)
	if equipButtonFrame then
		-- Make sure the equip button has the current weapon ID stored
		equipButtonFrame:SetAttribute("WeaponId", weaponId)

		-- Replace existing click detectors to ensure correct ID is used
		local oldClickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
		if oldClickDetector then oldClickDetector:Destroy() end

		setupWeaponEquipButtonInteraction(equipButtonFrame, weaponId, nil)
	end
end

function setupWeaponEquipButtonInteraction(equipButtonFrame, weaponId, template)
	if not equipButtonFrame then return end
	if weaponId == nil then return end

	-- Store weaponId as an attribute on the button frame for reliable access
	equipButtonFrame:SetAttribute("WeaponId", weaponId)

	-- Get the equipped label for this weapon
	local equipLabel = equipButtonFrame:FindFirstChild("Equipped") or equipButtonFrame.Parent:FindFirstChild("Equipped", true)

	-- Request ownership and active status from server
	RemoteEvent:FireServer("CheckWeaponOwnership", weaponId)
	RemoteEvent:FireServer("CheckActiveWeapon", weaponId)

	local clickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = equipButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = equipButtonFrame
	end

	clickDetector.MouseButton1Click:Connect(function()
		-- Check if the weapon is already equipped
		if equipLabel and equipLabel.Text == "Equipped" then
			-- Already equipped, do nothing
			return
		end

		playSoundByName(equipButtonFrame, "ButtonClick")

		-- Set text to show loading
		if equipLabel then equipLabel.Text = "..." end

		-- FIXED: Get weaponId from attribute to ensure correct ID is sent
		local weaponToEquip = equipButtonFrame:GetAttribute("WeaponId")
		print("Attempting to equip weapon: " .. tostring(weaponToEquip))

		-- Send equip request to server
		RemoteEvent:FireServer("SetActiveWeapon", weaponToEquip)
	end)
end

local function setupWeaponTemplateEffects(template, weaponId)
	if template:GetAttribute("EffectsInitialized") then return end
	template:SetAttribute("EffectsInitialized", true)

	local uiStroke = template:FindFirstChildOfClass("UIStroke")
	if not uiStroke then return end

	originalStrokeThickness[template] = uiStroke.Thickness

	local clickDetector = Instance.new("TextButton")
	clickDetector.Name = "ClickDetector"
	clickDetector.BackgroundTransparency = 1
	clickDetector.Text = ""
	clickDetector.Size = UDim2.new(1, 0, 1, 0)
	clickDetector.Position = UDim2.new(0, 0, 0, 0)
	clickDetector.ZIndex = 10
	clickDetector.AutoButtonColor = false
	clickDetector.Parent = template

	clickDetector.MouseEnter:Connect(function()
		if template == currentSelectedTemplate then return end

		playSoundByName(template, "Hover")

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = 4
		})
	end)

	clickDetector.MouseLeave:Connect(function()
		if template == currentSelectedTemplate then return end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template]
		})
	end)

	clickDetector.MouseButton1Click:Connect(function()
		playSoundByName(template, "ButtonClick")

		if currentSelectedTemplate and currentSelectedTemplate ~= template then
			local prevStroke = currentSelectedTemplate:FindFirstChildOfClass("UIStroke")
			if prevStroke then
				TweenMethods.CreateTweenAsync(prevStroke, TweenMethods.PointOneSecondSineData, {
					Thickness = originalStrokeThickness[currentSelectedTemplate] or 3
				})
			end
		end

		currentSelectedTemplate = template

		local weaponData = WeaponData[weaponId]
		if weaponData then updateMainWeaponViewport(weaponId, weaponData) end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = 5
		})
	end)
end

local function animateTemplateVisualizer(visualizerFrame, startAnimation)
	if not visualizerFrame then return end

	local bars = {}
	for _, child in ipairs(visualizerFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name == "VisualizerBar" then
			table.insert(bars, child)
		end
	end

	if #bars == 0 then return end

	for _, bar in ipairs(bars) do
		if not bar:GetAttribute("OriginalSize_Y") then
			bar:SetAttribute("OriginalSize_Y", bar.Size.Y.Scale)
			bar:SetAttribute("OriginalSize_Offset", bar.Size.Y.Offset)
		end
	end

	for _, bar in ipairs(bars) do
		if bar:GetAttribute("CurrentTween") then
			local tween = bar:GetAttribute("CurrentTween")
			if typeof(tween) == "Instance" and tween:IsA("Tween") then tween:Cancel() end
			bar:SetAttribute("CurrentTween", nil)
		end
	end

	if startAnimation then
		for i, bar in ipairs(bars) do
			local randomHeight = math.random(30, 80) / 100
			local randomDuration = (math.random(20, 40) / 10)

			local tween = TweenService:Create(
				bar,
				TweenInfo.new(randomDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0),
				{Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, randomHeight, 0)}
			)

			tween:Play()
			bar:SetAttribute("IsAnimating", true)
		end
	else
		for _, bar in ipairs(bars) do
			local originalScaleY = bar:GetAttribute("OriginalSize_Y") or 0.1
			local originalOffsetY = bar:GetAttribute("OriginalSize_Offset") or 0

			TweenMethods.CreateTweenAsync(bar, TweenMethods.ReturnSineData(0.2), {
				Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, originalScaleY, originalOffsetY)
			})

			bar:SetAttribute("IsAnimating", false)
		end
	end
end

local function animateEquipButton(equipButtonFrame, show)
	if not equipButtonFrame then return end

	if activeTweens[equipButtonFrame] then
		activeTweens[equipButtonFrame]:Cancel()
		activeTweens[equipButtonFrame] = nil
	end

	local originalPosition = UDim2.new(
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or 0,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or 0,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or 0,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or 0
	)

	local showPosition = originalPosition
	local hidePosition = originalPosition + UDim2.new(0, 0, 0.2, 0)

	local uiStroke = equipButtonFrame:FindFirstChildOfClass("UIStroke")

	if show then
		equipButtonFrame.Visible = true

		if equipButtonFrame.Position ~= hidePosition then
			equipButtonFrame.Position = hidePosition
		end

		if uiStroke then
			local originalColor = Color3.new(
				equipButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)
			uiStroke.Color = originalColor
		end

		local positionTween = TweenService:Create(
			equipButtonFrame, 
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = showPosition}
		)
		positionTween:Play()

		activeTweens[equipButtonFrame] = positionTween
		setElementTransparency(equipButtonFrame, false, TweenMethods.HalfSecondSineData)
	else
		local positionTween = TweenService:Create(
			equipButtonFrame, 
			TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = hidePosition}
		)
		positionTween:Play()

		activeTweens[equipButtonFrame] = positionTween
		setElementTransparency(equipButtonFrame, true, TweenMethods.ReturnSineData(0.2))

		task.delay(0.2, function()
			if not equipButtonFrame:GetAttribute("StayVisible") then
				equipButtonFrame.Visible = false
			end
		end)
	end
end

local function resetAllDeathSoundTemplates()
	currentSelectedSoundTemplate = nil

	if currentSoundInstance and currentSoundInstance.IsPlaying then
		currentSoundInstance:Stop()
		currentSoundInstance = nil
	end

	if currentVisibleEquipButton and currentVisibleEquipButton.Parent then
		animateEquipButton(currentVisibleEquipButton, false)
	end
	currentVisibleEquipButton = nil

	for template, originalThickness in pairs(originalStrokeThickness) do
		if template and template:IsDescendantOf(game) and template.Name:find("DeathSoundTemplate_") then
			local uiStroke = template:FindFirstChildOfClass("UIStroke")
			if not uiStroke then
				local nameFrame = template:FindFirstChild("DeathSoundNameFrame")
				if nameFrame then uiStroke = nameFrame:FindFirstChildOfClass("UIStroke") end
			end

			if uiStroke then
				local originalColor = Color3.new(
					template:GetAttribute("OriginalStrokeColor_R") or 0,
					template:GetAttribute("OriginalStrokeColor_G") or 0,
					template:GetAttribute("OriginalStrokeColor_B") or 0
				)

				uiStroke.Thickness = originalThickness
				uiStroke.Color = originalColor
				uiStroke.Transparency = template:GetAttribute("OriginalStrokeTransparency") or 0
			end

			local visualizerFrame = template:FindFirstChild("VisualizerFrame", true)
			if visualizerFrame then animateTemplateVisualizer(visualizerFrame, false) end

			local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
			if equipButtonFrame then
				equipButtonFrame.Visible = false
				setElementTransparency(equipButtonFrame, true)
			end
		end
	end
end

local function resetAllWeaponTemplates()
	currentSelectedTemplate = nil

	for template, originalThickness in pairs(originalStrokeThickness) do
		if template and template:IsDescendantOf(game) then
			local uiStroke = template:FindFirstChildOfClass("UIStroke")
			if uiStroke then uiStroke.Thickness = originalThickness end
		end
	end
end

local function enhanceExistingVisualizer(visualizerFrame)
	local bars = {}
	for _, child in ipairs(visualizerFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name == "VisualizerBar" then
			table.insert(bars, child)
		end
	end

	if #bars == 0 then return end

	for _, bar in ipairs(bars) do
		if not bar:GetAttribute("OriginalSize_Y") then
			bar:SetAttribute("OriginalSize_Y", bar.Size.Y.Scale)
		end
	end
end

local function previewDeathSound(soundId, template)
	if currentSoundInstance and currentSoundInstance.IsPlaying then
		currentSoundInstance:Stop()
	end

	local soundData = DeathSoundData[soundId]
	if not soundData then return end

	local player = game:GetService("Players").LocalPlayer
	if not player or not player.PlayerGui then return end

	local existingSoundInstance = player.PlayerGui:FindFirstChild("DeathSoundPreview_" .. soundId)
	local soundInstance = existingSoundInstance

	if not soundInstance then
		soundInstance = Instance.new("Sound")
		soundInstance.SoundId = soundData.soundId
		soundInstance.Volume = 1
		soundInstance.Name = "DeathSoundPreview_" .. soundId
		soundInstance.Parent = player.PlayerGui
	else
		if soundInstance.IsPlaying then soundInstance:Stop() end
	end

	currentSoundInstance = soundInstance

	local visualizerFrame = nil
	if template then
		visualizerFrame = template:FindFirstChild("VisualizerFrame", true)
	end

	soundInstance:Play()

	if visualizerFrame then
		animateTemplateVisualizer(visualizerFrame, true)

		soundInstance.Ended:Connect(function()
			animateTemplateVisualizer(visualizerFrame, false)

			soundInstance:Destroy()
			if currentSoundInstance == soundInstance then
				currentSoundInstance = nil
			end
		end)
	else
		soundInstance.Ended:Connect(function()
			soundInstance:Destroy()
			if currentSoundInstance == soundInstance then
				currentSoundInstance = nil
			end
		end)
	end
end

local function updateMainSoundView(soundId, soundData)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	local client = playerGui:FindFirstChild("Client")
	local lockerScreenFrame = client:FindFirstChild("LockerScreenFrame")
	local lockerScreen = lockerScreenFrame:FindFirstChild("LockerScreen")
	local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")

	if not deathSoundsLockerHolder then return end

	local deathSoundsHolder = deathSoundsLockerHolder:FindFirstChild("DeathSoundsHolder")
	if not deathSoundsHolder then return end

	currentSelectedSound = soundId

	local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
	local nameLabel, descriptionLabel, visualizerFrame

	for _, child in ipairs(deathSoundsHolder:GetChildren()) do
		if child ~= scrollFrameHolder then
			if child:IsA("Frame") and child.Name ~= "DropShadowHolder" then
				local name = child:FindFirstChild("DeathSoundName", true)
				local desc = child:FindFirstChild("DeathSoundDescription", true)
				local vis = child:FindFirstChild("VisualizerFrame", true)

				if name and not string.find(name:GetFullName(), "Template") then
					nameLabel = name
				end

				if desc and not string.find(desc:GetFullName(), "Template") then
					descriptionLabel = desc
				end

				if vis and not string.find(vis:GetFullName(), "Template") then
					visualizerFrame = vis
				end

				if nameLabel and descriptionLabel and visualizerFrame then break end
			end
		end
	end

	if not (nameLabel and descriptionLabel and visualizerFrame) then
		local allDescendants = deathSoundsHolder:GetDescendants()

		for _, descendant in ipairs(allDescendants) do
			local isInScrollFrame = false
			local parent = descendant.Parent
			while parent and parent ~= deathSoundsHolder do
				if parent == scrollFrameHolder then
					isInScrollFrame = true
					break
				end
				parent = parent.Parent
			end

			if not isInScrollFrame then
				if not nameLabel and descendant.Name == "DeathSoundName" and 
					not string.find(descendant:GetFullName(), "Template") then
					nameLabel = descendant
				end

				if not descriptionLabel and descendant.Name == "DeathSoundDescription" and 
					not string.find(descendant:GetFullName(), "Template") then
					descriptionLabel = descendant
				end

				if not visualizerFrame and descendant.Name == "VisualizerFrame" and 
					not string.find(descendant:GetFullName(), "Template") then
					visualizerFrame = descendant
				end
			end
		end
	end

	local elementsToAnimate = {}
	if visualizerFrame then table.insert(elementsToAnimate, visualizerFrame) end
	if descriptionLabel then table.insert(elementsToAnimate, descriptionLabel) end
	if nameLabel then table.insert(elementsToAnimate, nameLabel) end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end

			element.Position = trueOriginalPositions[element] + UDim2.new(0, 0, 0.1, 0)
			setElementTransparency(element, true)
			element.Visible = true
		end
	end

	if nameLabel then nameLabel.Text = soundData.displayName end
	if descriptionLabel then descriptionLabel.Text = soundData.description end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			TweenMethods.CreateTweenAsync(element, TweenMethods.HalfSecondSineData, {
				Position = trueOriginalPositions[element]
			})

			setElementTransparency(element, false, TweenMethods.HalfSecondSineData)
		end
	end

	deathSoundsLockerHolder:SetAttribute("SelectedSoundId", soundId)

	if visualizerFrame then enhanceExistingVisualizer(visualizerFrame) end
end

local function setupEquipButtonInteraction(equipButtonFrame, soundId, template)
	if not equipButtonFrame then return end
	if soundId == nil then return end

	local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
	local uiStroke = equipButtonFrame:FindFirstChildOfClass("UIStroke")

	if not equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", equipButtonFrame.Position.X.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", equipButtonFrame.Position.X.Offset)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", equipButtonFrame.Position.Y.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", equipButtonFrame.Position.Y.Offset)
	end

	local originalSize = equipButtonFrame.Size

	if uiStroke then
		if not equipButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			equipButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	equipButtonFrame:SetAttribute("SoundId", soundId)

	if equipLabel then
		-- Check if this sound is currently equipped
		RemoteEvent:FireServer("CheckDeathSoundOwnership", soundId)
	end

	local clickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = equipButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = equipButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(equipButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = UDim2.new(
				originalSize.X.Scale * 1.05, 
				originalSize.X.Offset * 1.05,
				originalSize.Y.Scale * 1.05, 
				originalSize.Y.Offset * 1.05
			)
		})

		if uiStroke then
			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = Color3.new(1, 1, 1)
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				equipButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		if equipLabel and equipLabel.Text == "Equipped" then
			-- Already equipped, do nothing
			return
		end

		local soundData = DeathSoundData[soundId]
		if not soundData then return end

		playSoundByName(equipButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if equipLabel then equipLabel.Text = "..." end

		local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
		RemoteEvent:FireServer("SetActiveDeathSound", soundId)
	end)

	local trueOriginalPosition = UDim2.new(
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or equipButtonFrame.Position.X.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or equipButtonFrame.Position.X.Offset,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or equipButtonFrame.Position.Y.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or equipButtonFrame.Position.Y.Offset
	)

	equipButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	equipButtonFrame.Visible = false
	setElementTransparency(equipButtonFrame, true)

	RemoteEvent:FireServer("CheckDeathSoundOwnership", soundId)
end

local function setupDeathSoundTemplateEffects(template, soundId)
	if template:GetAttribute("EffectsInitialized") then return end
	template:SetAttribute("EffectsInitialized", true)

	local uiStroke = nil
	uiStroke = template:FindFirstChildOfClass("UIStroke")

	if not uiStroke then
		local nameFrame = template:FindFirstChild("DeathSoundNameFrame")
		if nameFrame then uiStroke = nameFrame:FindFirstChildOfClass("UIStroke") end
	end

	if not uiStroke then
		uiStroke = Instance.new("UIStroke")
		uiStroke.Color = Color3.new(0, 0, 0)
		uiStroke.Thickness = 2
		uiStroke.Transparency = 0
		uiStroke.Parent = template
	end

	originalStrokeThickness[template] = uiStroke.Thickness
	template:SetAttribute("OriginalStrokeTransparency", uiStroke.Transparency)
	template:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
	template:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
	template:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)

	-- Rename BuyButtonFrame to EquipButtonFrame if needed
	local equipButtonFrame = template:FindFirstChild("EquipButtonFrame") or template:FindFirstChild("BuyButtonFrame")
	if equipButtonFrame and equipButtonFrame.Name == "BuyButtonFrame" then
		equipButtonFrame.Name = "EquipButtonFrame"
	end

	if equipButtonFrame then
		setupEquipButtonInteraction(equipButtonFrame, soundId, template)
	end

	local clickDetector = Instance.new("TextButton")
	clickDetector.Name = "ClickDetector"
	clickDetector.BackgroundTransparency = 1
	clickDetector.Text = ""
	clickDetector.Size = UDim2.new(1, 0, 1, 0)
	clickDetector.Position = UDim2.new(0, 0, 0, 0)
	clickDetector.ZIndex = 10
	clickDetector.AutoButtonColor = false
	clickDetector.Parent = template

	clickDetector.MouseEnter:Connect(function()
		if template == currentSelectedSoundTemplate then return end

		playSoundByName(template, "Hover")

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template] + 1,
			Color = Color3.new(1, 1, 1),
			Transparency = 0
		})
	end)

	clickDetector.MouseLeave:Connect(function()
		if template == currentSelectedSoundTemplate then return end

		local originalColor = Color3.new(
			template:GetAttribute("OriginalStrokeColor_R") or 0,
			template:GetAttribute("OriginalStrokeColor_G") or 0,
			template:GetAttribute("OriginalStrokeColor_B") or 0
		)

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template],
			Color = originalColor,
			Transparency = template:GetAttribute("OriginalStrokeTransparency") or 0
		})
	end)

	clickDetector.MouseButton1Click:Connect(function()
		playSoundByName(template, "ButtonClick")

		local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")

		if currentSelectedSoundTemplate and currentSelectedSoundTemplate ~= template then
			local prevStroke = nil
			prevStroke = currentSelectedSoundTemplate:FindFirstChildOfClass("UIStroke")

			if not prevStroke then
				local prevNameFrame = currentSelectedSoundTemplate:FindFirstChild("DeathSoundNameFrame")
				if prevNameFrame then prevStroke = prevNameFrame:FindFirstChildOfClass("UIStroke") end
			end

			if prevStroke then
				local originalColor = Color3.new(
					currentSelectedSoundTemplate:GetAttribute("OriginalStrokeColor_R") or 0,
					currentSelectedSoundTemplate:GetAttribute("OriginalStrokeColor_G") or 0,
					currentSelectedSoundTemplate:GetAttribute("OriginalStrokeColor_B") or 0
				)

				TweenMethods.CreateTweenAsync(prevStroke, TweenMethods.PointOneSecondSineData, {
					Thickness = originalStrokeThickness[currentSelectedSoundTemplate] or 2,
					Color = originalColor,
					Transparency = currentSelectedSoundTemplate:GetAttribute("OriginalStrokeTransparency") or 0
				})
			end

			if currentVisibleEquipButton then
				animateEquipButton(currentVisibleEquipButton, false)
			end
		end

		currentSelectedSoundTemplate = template

		if equipButtonFrame then
			equipButtonFrame:SetAttribute("StayVisible", true)
			animateEquipButton(equipButtonFrame, true)
			currentVisibleEquipButton = equipButtonFrame

			task.delay(0.5, function()
				equipButtonFrame:SetAttribute("StayVisible", false)
			end)
		end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template] + 2,
			Color = Color3.new(1, 1, 1),
			Transparency = 0
		})

		previewDeathSound(soundId, template)
	end)
end

local function updateMainMeleeWeaponViewport(weaponId, weaponData)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	local client = playerGui:FindFirstChild("Client")
	local lockerScreenFrame = client:FindFirstChild("LockerScreenFrame")
	local lockerScreen = lockerScreenFrame:FindFirstChild("LockerScreen")

	local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")

	if not meleeWeaponsLockerHolder then return end

	if currentSelectedWeapon then
		stopFloatingAnimation("detail_" .. currentSelectedWeapon)
	end

	currentSelectedWeapon = weaponId

	local dropShadowHolder = meleeWeaponsLockerHolder:FindFirstChild("DropShadowHolder", true)
	local dropShadow = dropShadowHolder and dropShadowHolder:FindFirstChild("DropShadow")

	local elementsToAnimate = {
		dropShadowHolder,
		meleeWeaponsLockerHolder:FindFirstChild("MeleeWeaponViewport", true),
		meleeWeaponsLockerHolder:FindFirstChild("EquipButtonFrame", true),
		meleeWeaponsLockerHolder:FindFirstChild("Equipped", true),
		meleeWeaponsLockerHolder:FindFirstChild("DescriptionLabel", true),
		meleeWeaponsLockerHolder:FindFirstChild("ItemClass", true),
		meleeWeaponsLockerHolder:FindFirstChild("ItemName", true)
	}

	local templateFolder = game:GetService("StarterGui"):FindFirstChild("Templates")
	local isRare = weaponData.rarity and string.lower(weaponData.rarity) == "rare"
	local isUncommon = weaponData.rarity and string.lower(weaponData.rarity) == "uncommon"

	local itemClass = meleeWeaponsLockerHolder:FindFirstChild("ItemClass", true)
	if itemClass then itemClass.Text = weaponData.rarity or "Common" end

	if dropShadow then
		local existingGradient = dropShadow:FindFirstChildWhichIsA("UIGradient")
		if existingGradient then existingGradient:Destroy() end

		if not isRare and not isUncommon then dropShadow.ImageColor3 = Color3.new(0, 0, 0) end
	end

	if dropShadowHolder then
		local existingHolderGradient = dropShadowHolder:FindFirstChild("RarityGradient")
		if existingHolderGradient then existingHolderGradient:Destroy() end

		local dropShadowStroke = dropShadowHolder:FindFirstChildWhichIsA("UIStroke")
		if dropShadowStroke then
			local existingStrokeGradient = dropShadowStroke:FindFirstChild("RarityStrokeGradient")
			if existingStrokeGradient then existingStrokeGradient:Destroy() end
		end
	end

	if isRare and templateFolder and dropShadowHolder then
		local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")
		if rareTemplate then
			local sourceGradient = rareTemplate:FindFirstChildWhichIsA("UIGradient")
			if sourceGradient and dropShadow then
				dropShadow.ImageColor3 = Color3.new(1, 1, 1)

				local shadowGradient = Instance.new("UIGradient")
				shadowGradient.Name = "RarityGradient"
				copyGradientProperties(sourceGradient, shadowGradient)
				shadowGradient.Transparency = NumberSequence.new(0,0)
				shadowGradient.Parent = dropShadow
			end

			local templateStroke = rareTemplate:FindFirstChildWhichIsA("UIStroke")
			local dropShadowStroke = dropShadowHolder:FindFirstChildWhichIsA("UIStroke")

			if templateStroke and dropShadowStroke then
				local strokeGradient = templateStroke:FindFirstChildWhichIsA("UIGradient")
				if strokeGradient then
					applyGradientToElement(strokeGradient, dropShadowStroke, "RarityStrokeGradient")
				end
			end
		end
	elseif isUncommon and templateFolder and dropShadowHolder then
		local uncommonTemplate = templateFolder:FindFirstChild("UncommonWeaponTemplate")
		if uncommonTemplate then
			local sourceGradient = uncommonTemplate:FindFirstChildWhichIsA("UIGradient")
			if sourceGradient and dropShadow then
				dropShadow.ImageColor3 = Color3.new(1, 1, 1)

				local shadowGradient = Instance.new("UIGradient")
				shadowGradient.Name = "RarityGradient"
				copyGradientProperties(sourceGradient, shadowGradient)
				shadowGradient.Transparency = NumberSequence.new(0,0)
				shadowGradient.Parent = dropShadow
			end

			local templateStroke = uncommonTemplate:FindFirstChildWhichIsA("UIStroke")
			local dropShadowStroke = dropShadowHolder:FindFirstChildWhichIsA("UIStroke")

			if templateStroke and dropShadowStroke then
				local strokeGradient = templateStroke:FindFirstChildWhichIsA("UIGradient")
				if strokeGradient then
					applyGradientToElement(strokeGradient, dropShadowStroke, "RarityStrokeGradient")
				end
			end
		end
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end

			element.Position = trueOriginalPositions[element] + UDim2.new(0, 0, 0.1, 0)
			setElementTransparency(element, true)
			element.Visible = true
		end
	end

	local viewportFrame = nil
	local itemDescriptionHolder = meleeWeaponsLockerHolder:FindFirstChild("ItemDescriptionHolder")
	if itemDescriptionHolder then
		viewportFrame = itemDescriptionHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if not viewportFrame then
		viewportFrame = meleeWeaponsLockerHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if viewportFrame then
		setupWeaponViewport(viewportFrame, weaponId)
		animateModelRotation(viewportFrame, weaponId)
		animateViewportFOV(viewportFrame, true)
	end

	local elements = {
		ItemName = weaponData.displayName,
		ItemRarity = weaponData.rarity,
		DescriptionLabel = weaponData.description
	}

	RemoteEvent:FireServer("CheckMeleeWeaponOwnership", weaponId)

	local equipButton = meleeWeaponsLockerHolder:FindFirstChild("Equipped", true)
	if equipButton then 
		equipButton.Text = "Loading..."
	end

	for name, value in pairs(elements) do
		local element = meleeWeaponsLockerHolder:FindFirstChild(name, true)
		if element then element.Text = value end
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			TweenMethods.CreateTweenAsync(element, TweenMethods.HalfSecondSineData, {
				Position = trueOriginalPositions[element]
			})

			setElementTransparency(element, false, TweenMethods.HalfSecondSineData)
		end
	end

	-- IMPORTANT: Store the selected weapon ID in the holder
	meleeWeaponsLockerHolder:SetAttribute("SelectedWeaponId", weaponId)

	-- Get the equip button and set up interaction with the correct weapon ID
	local equipButtonFrame = meleeWeaponsLockerHolder:FindFirstChild("EquipButtonFrame", true)
	if equipButtonFrame then
		-- Make sure the equip button has the current weapon ID stored
		equipButtonFrame:SetAttribute("MeleeWeaponId", weaponId)

		-- Replace existing click detectors to ensure correct ID is used
		local oldClickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
		if oldClickDetector then oldClickDetector:Destroy() end

		setupMeleeWeaponEquipButtonInteraction(equipButtonFrame, weaponId, nil)
	end
end

	local function setupMeleeWeaponTemplateEffects(template, weaponId)
	if template:GetAttribute("EffectsInitialized") then return end
	template:SetAttribute("EffectsInitialized", true)

	local uiStroke = template:FindFirstChildOfClass("UIStroke")
	if not uiStroke then return end

	originalStrokeThickness[template] = uiStroke.Thickness

	local clickDetector = Instance.new("TextButton")
	clickDetector.Name = "ClickDetector"
	clickDetector.BackgroundTransparency = 1
	clickDetector.Text = ""
	clickDetector.Size = UDim2.new(1, 0, 1, 0)
	clickDetector.Position = UDim2.new(0, 0, 0, 0)
	clickDetector.ZIndex = 10
	clickDetector.AutoButtonColor = false
	clickDetector.Parent = template

	clickDetector.MouseEnter:Connect(function()
		if template == currentSelectedTemplate then return end

		playSoundByName(template, "Hover")

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = 4
		})
	end)

	clickDetector.MouseLeave:Connect(function()
		if template == currentSelectedTemplate then return end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template]
		})
	end)

	clickDetector.MouseButton1Click:Connect(function()
		playSoundByName(template, "ButtonClick")

		if currentSelectedTemplate and currentSelectedTemplate ~= template then
			local prevStroke = currentSelectedTemplate:FindFirstChildOfClass("UIStroke")
			if prevStroke then
				TweenMethods.CreateTweenAsync(prevStroke, TweenMethods.PointOneSecondSineData, {
					Thickness = originalStrokeThickness[currentSelectedTemplate] or 3
				})
			end
		end

		currentSelectedTemplate = template

		local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
		local weaponData = MeleeWeaponData[weaponId]
		if weaponData then updateMainMeleeWeaponViewport(weaponId, weaponData) end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = 5
		})
	end)
end

function setupMeleeWeaponEquipButtonInteraction(equipButtonFrame, weaponId, template)
	if not equipButtonFrame then return end
	if weaponId == nil then return end

	-- Store weaponId as an attribute on the button frame for reliable access
	equipButtonFrame:SetAttribute("MeleeWeaponId", weaponId)

	local equipLabel = equipButtonFrame:FindFirstChild("Equipped") or equipButtonFrame.Parent:FindFirstChild("Equipped", true)
	local uiStroke = equipButtonFrame:FindFirstChildOfClass("UIStroke")

	if not equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", equipButtonFrame.Position.X.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", equipButtonFrame.Position.X.Offset)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", equipButtonFrame.Position.Y.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", equipButtonFrame.Position.Y.Offset)
	end

	local originalSize = equipButtonFrame.Size

	if uiStroke then
		if not equipButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			equipButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	-- Request ownership and active status from server
	RemoteEvent:FireServer("CheckMeleeWeaponOwnership", weaponId)
	RemoteEvent:FireServer("CheckActiveMeleeWeapon", weaponId)

	local clickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = equipButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = equipButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(equipButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = UDim2.new(
				originalSize.X.Scale * 1.05, 
				originalSize.X.Offset * 1.05,
				originalSize.Y.Scale * 1.05, 
				originalSize.Y.Offset * 1.05
			)
		})

		if uiStroke then
			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = Color3.new(1, 1, 1)
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				equipButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		-- Check if the weapon is already equipped
		if equipLabel and equipLabel.Text == "Equipped" then
			-- Already equipped, do nothing
			return
		end

		playSoundByName(equipButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if equipLabel then equipLabel.Text = "..." end

		-- FIXED: Get weaponId from attribute to ensure correct ID is sent
		local weaponToEquip = equipButtonFrame:GetAttribute("MeleeWeaponId")
		print("Attempting to equip melee weapon: " .. tostring(weaponToEquip))

		RemoteEvent:FireServer("SetActiveMeleeWeapon", weaponToEquip)
	end)

	local trueOriginalPosition = UDim2.new(
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or equipButtonFrame.Position.X.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or equipButtonFrame.Position.X.Offset,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or equipButtonFrame.Position.Y.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or equipButtonFrame.Position.Y.Offset
	)

	equipButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
end


local function populateMeleeWeaponsLocker(meleeWeaponsLockerHolder)
	local meleeWeaponsHolder = meleeWeaponsLockerHolder:FindFirstChild("MeleeWeaponsHolder")
	if not meleeWeaponsHolder then return end

	local scrollFrameHolder = meleeWeaponsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	-- Clear existing templates
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") then child:Destroy() end
	end

	-- Add loading indicator
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Text = "Loading items..."
	loadingLabel.Name = "LoadingIndicator"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.Position = UDim2.new(0, 0, 0, 0)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.TextColor3 = Color3.new(1, 1, 1)
	loadingLabel.Font = Enum.Font.GothamBold
	loadingLabel.TextSize = 18
	loadingLabel.Parent = scrollingFrame

	-- Request owned melee weapons from server
	RemoteEvent:FireServer("GetOwnedMeleeWeapons")

	-- Wait for server response to populate with real data
end

local function populateWeaponsLocker(weaponsLockerHolder)
	local weaponsHolder = weaponsLockerHolder:FindFirstChild("WeaponsHolder")
	if not weaponsHolder then return end

	local scrollFrameHolder = weaponsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	-- Clear existing templates
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") then child:Destroy() end
	end

	-- Add loading indicator
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Text = "Loading items..."
	loadingLabel.Name = "LoadingIndicator"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.Position = UDim2.new(0, 0, 0, 0)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.TextColor3 = Color3.new(1, 1, 1)
	loadingLabel.Font = Enum.Font.GothamBold
	loadingLabel.TextSize = 18
	loadingLabel.Parent = scrollingFrame

	-- Request owned weapons from server
	RemoteEvent:FireServer("GetOwnedWeapons")

	-- We do NOT populate with placeholder data here
	-- We wait for the server response to populate with real data
end


local function populateDeathSoundsLocker(deathSoundsLockerHolder)
	local deathSoundsHolder = deathSoundsLockerHolder:FindFirstChild("DeathSoundsHolder")
	if not deathSoundsHolder then return end

	local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
	if not soundScrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	-- Clear existing templates
	for _, child in pairs(soundScrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	-- Add loading indicator
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Text = "Loading items..."
	loadingLabel.Name = "LoadingIndicator"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.Position = UDim2.new(0, 0, 0, 0)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.TextColor3 = Color3.new(1, 1, 1)
	loadingLabel.Font = Enum.Font.GothamBold
	loadingLabel.TextSize = 18
	loadingLabel.Parent = soundScrollingFrame

	-- Request owned death sounds from server
	RemoteEvent:FireServer("GetOwnedDeathSounds")

	-- Wait for server response to populate with real data
	currentVisibleEquipButton = nil
end

local function previewTauntSound(tauntId, template)
	if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
		currentTauntSoundInstance:Stop()
	end

	local soundData = TauntSoundData[tauntId]
	if not soundData then return end

	local player = game:GetService("Players").LocalPlayer
	if not player or not player.PlayerGui then return end

	local existingSoundInstance = player.PlayerGui:FindFirstChild("TauntSoundPreview_" .. tauntId)
	local soundInstance = existingSoundInstance

	if not soundInstance then
		soundInstance = Instance.new("Sound")
		soundInstance.SoundId = soundData.soundId
		soundInstance.Volume = 1
		soundInstance.Name = "TauntSoundPreview_" .. tauntId
		soundInstance.Parent = player.PlayerGui
	else
		if soundInstance.IsPlaying then soundInstance:Stop() end
	end

	currentTauntSoundInstance = soundInstance

	local visualizerFrame = nil
	if template then
		visualizerFrame = template:FindFirstChild("VisualizerFrame", true)
	end

	soundInstance:Play()

	if visualizerFrame then
		animateTemplateVisualizer(visualizerFrame, true)

		soundInstance.Ended:Connect(function()
			animateTemplateVisualizer(visualizerFrame, false)

			soundInstance:Destroy()
			if currentTauntSoundInstance == soundInstance then
				currentTauntSoundInstance = nil
			end
		end)
	else
		soundInstance.Ended:Connect(function()
			soundInstance:Destroy()
			if currentTauntSoundInstance == soundInstance then
				currentTauntSoundInstance = nil
			end
		end)
	end
end

local function updateMainTauntView(tauntId, soundData)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	local client = playerGui:FindFirstChild("Client")
	local lockerScreenFrame = client:FindFirstChild("LockerScreenFrame")
	local lockerScreen = lockerScreenFrame:FindFirstChild("LockerScreen")
	local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")

	if not tauntsLockerHolder then return end

	local tauntsHolder = tauntsLockerHolder:FindFirstChild("TauntsHolder")
	if not tauntsHolder then return end

	currentSelectedTaunt = tauntId

	local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
	local nameLabel, descriptionLabel, visualizerFrame

	for _, child in ipairs(tauntsHolder:GetChildren()) do
		if child ~= tauntsFrameHolder then
			if child:IsA("Frame") and child.Name ~= "DropShadowHolder" then
				local name = child:FindFirstChild("TauntName", true)
				local desc = child:FindFirstChild("TauntDescription", true)
				local vis = child:FindFirstChild("VisualizerFrame", true)

				if name and not string.find(name:GetFullName(), "Template") then
					nameLabel = name
				end

				if desc and not string.find(desc:GetFullName(), "Template") then
					descriptionLabel = desc
				end

				if vis and not string.find(vis:GetFullName(), "Template") then
					visualizerFrame = vis
				end

				if nameLabel and descriptionLabel and visualizerFrame then break end
			end
		end
	end

	if not (nameLabel and descriptionLabel and visualizerFrame) then
		local allDescendants = tauntsHolder:GetDescendants()

		for _, descendant in ipairs(allDescendants) do
			local isInScrollFrame = false
			local parent = descendant.Parent
			while parent and parent ~= tauntsHolder do
				if parent == tauntsFrameHolder then
					isInScrollFrame = true
					break
				end
				parent = parent.Parent
			end

			if not isInScrollFrame then
				if not nameLabel and descendant.Name == "TauntName" and 
					not string.find(descendant:GetFullName(), "Template") then
					nameLabel = descendant
				end

				if not descriptionLabel and descendant.Name == "TauntDescription" and 
					not string.find(descendant:GetFullName(), "Template") then
					descriptionLabel = descendant
				end

				if not visualizerFrame and descendant.Name == "VisualizerFrame" and 
					not string.find(descendant:GetFullName(), "Template") then
					visualizerFrame = descendant
				end
			end
		end
	end

	local elementsToAnimate = {}
	if visualizerFrame then table.insert(elementsToAnimate, visualizerFrame) end
	if descriptionLabel then table.insert(elementsToAnimate, descriptionLabel) end
	if nameLabel then table.insert(elementsToAnimate, nameLabel) end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end

			element.Position = trueOriginalPositions[element] + UDim2.new(0, 0, 0.1, 0)
			setElementTransparency(element, true)
			element.Visible = true
		end
	end

	if nameLabel then nameLabel.Text = soundData.displayName end
	if descriptionLabel then descriptionLabel.Text = soundData.description end

	for _, element in ipairs(elementsToAnimate) do
		if element then
			TweenMethods.CreateTweenAsync(element, TweenMethods.HalfSecondSineData, {
				Position = trueOriginalPositions[element]
			})

			setElementTransparency(element, false, TweenMethods.HalfSecondSineData)
		end
	end

	tauntsLockerHolder:SetAttribute("SelectedTauntId", tauntId)

	if visualizerFrame then enhanceExistingVisualizer(visualizerFrame) end

	RemoteEvent:FireServer("CheckTauntOwnership", tauntId)
end

local function setupTauntEquipButtonInteraction(equipButtonFrame, tauntId, template)
	if not equipButtonFrame then return end
	if tauntId == nil then return end

	local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
	local uiStroke = equipButtonFrame:FindFirstChildOfClass("UIStroke")

	if not equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", equipButtonFrame.Position.X.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", equipButtonFrame.Position.X.Offset)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", equipButtonFrame.Position.Y.Scale)
		equipButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", equipButtonFrame.Position.Y.Offset)
	end

	local originalSize = equipButtonFrame.Size

	if uiStroke then
		if not equipButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			equipButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			equipButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	equipButtonFrame:SetAttribute("TauntId", tauntId)

	if equipLabel then
		-- Check if this taunt is currently equipped
		RemoteEvent:FireServer("CheckTauntOwnership", tauntId)
	end

	local clickDetector = equipButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = equipButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = equipButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(equipButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = UDim2.new(
				originalSize.X.Scale * 1.05, 
				originalSize.X.Offset * 1.05,
				originalSize.Y.Scale * 1.05, 
				originalSize.Y.Offset * 1.05
			)
		})

		if uiStroke then
			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = Color3.new(1, 1, 1)
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				equipButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				equipButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		equipButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		if equipLabel and equipLabel.Text == "Equipped" then
			-- Already equipped, do nothing
			return
		end

		local tauntData = TauntSoundData[tauntId]
		if not tauntData then return end

		playSoundByName(equipButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(equipButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if equipLabel then equipLabel.Text = "..." end

		RemoteEvent:FireServer("SetActiveTaunt", tauntId)
	end)

	local trueOriginalPosition = UDim2.new(
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or equipButtonFrame.Position.X.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or equipButtonFrame.Position.X.Offset,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or equipButtonFrame.Position.Y.Scale,
		equipButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or equipButtonFrame.Position.Y.Offset
	)

	equipButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	equipButtonFrame.Visible = false
	setElementTransparency(equipButtonFrame, true)

	RemoteEvent:FireServer("CheckTauntOwnership", tauntId)
end

	local function setupTauntTemplateEffects(template, tauntId)
	if template:GetAttribute("EffectsInitialized") then return end
	template:SetAttribute("EffectsInitialized", true)

	local uiStroke = nil
	uiStroke = template:FindFirstChildOfClass("UIStroke")

	if not uiStroke then
		local nameFrame = template:FindFirstChild("TauntNameFrame")
		if nameFrame then uiStroke = nameFrame:FindFirstChildOfClass("UIStroke") end
	end

	if not uiStroke then
		uiStroke = Instance.new("UIStroke")
		uiStroke.Color = Color3.new(0, 0, 0)
		uiStroke.Thickness = 2
		uiStroke.Transparency = 0
		uiStroke.Parent = template
	end

	originalStrokeThickness[template] = uiStroke.Thickness
	template:SetAttribute("OriginalStrokeTransparency", uiStroke.Transparency)
	template:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
	template:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
	template:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)

	-- Rename BuyButtonFrame to EquipButtonFrame if needed
	local equipButtonFrame = template:FindFirstChild("EquipButtonFrame") or template:FindFirstChild("BuyButtonFrame")
	if equipButtonFrame and equipButtonFrame.Name == "BuyButtonFrame" then
		equipButtonFrame.Name = "EquipButtonFrame"
		local priceLabel = equipButtonFrame:FindFirstChild("Price")
		if priceLabel then
			priceLabel.Name = "EquipText"
			priceLabel.Text = "Equip"
		end
	end

	if equipButtonFrame then
		setupTauntEquipButtonInteraction(equipButtonFrame, tauntId, template)
	end

	local clickDetector = Instance.new("TextButton")
	clickDetector.Name = "ClickDetector"
	clickDetector.BackgroundTransparency = 1
	clickDetector.Text = ""
	clickDetector.Size = UDim2.new(1, 0, 1, 0)
	clickDetector.Position = UDim2.new(0, 0, 0, 0)
	clickDetector.ZIndex = 10
	clickDetector.AutoButtonColor = false
	clickDetector.Parent = template

	clickDetector.MouseEnter:Connect(function()
		if template == currentSelectedTauntTemplate then return end

		playSoundByName(template, "Hover")

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template] + 1,
			Color = Color3.new(1, 1, 1),
			Transparency = 0
		})
	end)

	clickDetector.MouseLeave:Connect(function()
		if template == currentSelectedTauntTemplate then return end

		local originalColor = Color3.new(
			template:GetAttribute("OriginalStrokeColor_R") or 0,
			template:GetAttribute("OriginalStrokeColor_G") or 0,
			template:GetAttribute("OriginalStrokeColor_B") or 0
		)

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template],
			Color = originalColor,
			Transparency = template:GetAttribute("OriginalStrokeTransparency") or 0
		})
	end)

	clickDetector.MouseButton1Click:Connect(function()
		playSoundByName(template, "ButtonClick")

		local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")

		if currentSelectedTauntTemplate and currentSelectedTauntTemplate ~= template then
			local prevStroke = nil
			prevStroke = currentSelectedTauntTemplate:FindFirstChildOfClass("UIStroke")

			if not prevStroke then
				local prevNameFrame = currentSelectedTauntTemplate:FindFirstChild("TauntNameFrame")
				if prevNameFrame then prevStroke = prevNameFrame:FindFirstChildOfClass("UIStroke") end
			end

			if prevStroke then
				local originalColor = Color3.new(
					currentSelectedTauntTemplate:GetAttribute("OriginalStrokeColor_R") or 0,
					currentSelectedTauntTemplate:GetAttribute("OriginalStrokeColor_G") or 0,
					currentSelectedTauntTemplate:GetAttribute("OriginalStrokeColor_B") or 0
				)

				TweenMethods.CreateTweenAsync(prevStroke, TweenMethods.PointOneSecondSineData, {
					Thickness = originalStrokeThickness[currentSelectedTauntTemplate] or 2,
					Color = originalColor,
					Transparency = currentSelectedTauntTemplate:GetAttribute("OriginalStrokeTransparency") or 0
				})
			end

			if currentVisibleTauntEquipButton then
				animateEquipButton(currentVisibleTauntEquipButton, false)
			end
		end

		currentSelectedTauntTemplate = template

		if equipButtonFrame then
			equipButtonFrame:SetAttribute("StayVisible", true)
			animateEquipButton(equipButtonFrame, true)
			currentVisibleTauntEquipButton = equipButtonFrame

			task.delay(0.5, function()
				equipButtonFrame:SetAttribute("StayVisible", false)
			end)
		end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template] + 2,
			Color = Color3.new(1, 1, 1),
			Transparency = 0
		})

		previewTauntSound(tauntId, template)
	end)
end

local function populateTauntsLocker(tauntsLockerHolder)
	local tauntsHolder = tauntsLockerHolder:FindFirstChild("TauntsHolder")
	if not tauntsHolder then 
		print("Taunts: TauntsHolder not found!")
		return 
	end

	local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
	if not tauntsFrameHolder then 
		print("Taunts: TauntsFrameHolder not found!")
		return 
	end

	local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
	if not tauntsScrollingFrame then 
		print("Taunts: TauntsScrollingFrame not found!")
		return 
	end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then 
		print("Taunts: Template folder not found!")
		return 
	end

	-- Clear existing templates
	for _, child in pairs(tauntsScrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	-- Add loading indicator
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Text = "Loading items..."
	loadingLabel.Name = "LoadingIndicator"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.Position = UDim2.new(0, 0, 0, 0)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.TextColor3 = Color3.new(1, 1, 1)
	loadingLabel.Font = Enum.Font.GothamBold
	loadingLabel.TextSize = 18
	loadingLabel.Parent = tauntsScrollingFrame

	-- Request owned taunts from server
	RemoteEvent:FireServer("GetOwnedTaunts")

	-- Wait for server response to populate with real data
	currentVisibleTauntEquipButton = nil
end

local function cleanupLockerAnimations()
	for id, floatData in pairs(floatingAnimations) do
		if floatData.tween then floatData.tween:Cancel() end
		if floatData.offsetValue then floatData.offsetValue:Destroy() end
	end

	table.clear(floatingAnimations)
	table.clear(viewportTweens)

	currentSelectedWeapon = nil
end

	local function resetAllTauntTemplates()
	currentSelectedTauntTemplate = nil

	if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
		currentTauntSoundInstance:Stop()
		currentTauntSoundInstance = nil
	end

	if currentVisibleTauntEquipButton and currentVisibleTauntEquipButton.Parent then
		animateEquipButton(currentVisibleTauntEquipButton, false)
	end
	currentVisibleTauntEquipButton = nil

	for template, originalThickness in pairs(originalStrokeThickness) do
		if template and template:IsDescendantOf(game) and template.Name:find("TauntTemplate_") then
			local uiStroke = template:FindFirstChildOfClass("UIStroke")
			if not uiStroke then
				local nameFrame = template:FindFirstChild("TauntNameFrame")
				if nameFrame then uiStroke = nameFrame:FindFirstChildOfClass("UIStroke") end
			end

			if uiStroke then
				local originalColor = Color3.new(
					template:GetAttribute("OriginalStrokeColor_R") or 0,
					template:GetAttribute("OriginalStrokeColor_G") or 0,
					template:GetAttribute("OriginalStrokeColor_B") or 0
				)

				uiStroke.Thickness = originalThickness
				uiStroke.Color = originalColor
				uiStroke.Transparency = template:GetAttribute("OriginalStrokeTransparency") or 0
			end

			local visualizerFrame = template:FindFirstChild("VisualizerFrame", true)
			if visualizerFrame then animateTemplateVisualizer(visualizerFrame, false) end

			local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
			if equipButtonFrame then
				equipButtonFrame.Visible = false
				setElementTransparency(equipButtonFrame, true)
			end
		end
	end
end

	local function transitionPanels(fromPanel, toPanel)
	local fromPanelName = "options"
	local toPanelName = "options"

	if fromPanel.Name == "WeaponsLockerHolder" then 
		fromPanelName = "weapons"
	elseif fromPanel.Name == "DeathSoundsLockerHolder" then
		fromPanelName = "deathsounds"
	elseif fromPanel.Name == "TauntsLockerHolder" then
		fromPanelName = "taunts"
	elseif fromPanel.Name == "MeleeWeaponsLockerHolder" then
		fromPanelName = "meleeweapons"
	end

	if toPanel.Name == "WeaponsLockerHolder" then
		toPanelName = "weapons"
	elseif toPanel.Name == "DeathSoundsLockerHolder" then
		toPanelName = "deathsounds"
	elseif toPanel.Name == "TauntsLockerHolder" then
		toPanelName = "taunts"
	elseif toPanel.Name == "MeleeWeaponsLockerHolder" then
		toPanelName = "meleeweapons"
	end

	if fromPanel.Name == "WeaponsLockerHolder" then
		resetAllWeaponTemplates()
		cleanupLockerAnimations()
	elseif fromPanel.Name == "DeathSoundsLockerHolder" then
		resetAllDeathSoundTemplates()

		if currentSoundInstance and currentSoundInstance.IsPlaying then
			currentSoundInstance:Stop()
			currentSoundInstance = nil
		end
	elseif fromPanel.Name == "TauntsLockerHolder" then
		resetAllTauntTemplates()

		if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
			currentTauntSoundInstance:Stop()
			currentTauntSoundInstance = nil
		end
	elseif fromPanel.Name == "MeleeWeaponsLockerHolder" then
		resetAllWeaponTemplates()
		cleanupLockerAnimations()
	end

	playSoundByName(fromPanel, "ShopOpen")

	local lockerScreen = fromPanel.Parent
	while lockerScreen and lockerScreen.Name ~= "LockerScreen" do
		lockerScreen = lockerScreen.Parent
	end

	local lockerNameHolder = lockerScreen and lockerScreen:FindFirstChild("LockerNameHolder")

	if fromPanel.Name == "OptionsHolder" and (toPanel.Name == "WeaponsLockerHolder" or toPanel.Name == "DeathSoundsLockerHolder" or toPanel.Name == "TauntsLockerHolder" or toPanel.Name == "MeleeWeaponsLockerHolder") then
		local lockerHolder = fromPanel.Parent
		if lockerHolder then
			local lockerScreen = lockerHolder.Parent
			local mainReturnButton = lockerScreen and lockerScreen:FindFirstChild("ReturnButton")

			if mainReturnButton then animatePanel(mainReturnButton, "out") end

			if lockerNameHolder then
				animatePanel(lockerNameHolder, "out", function()
					updateLockerHeader(lockerScreen, toPanelName, false)
				end)
			end

			animatePanel(lockerHolder, "out", function()
				animatePanel(toPanel, "in")

				if lockerNameHolder then animatePanel(lockerNameHolder, "in") end

				lockerState.currentPanel = toPanelName

				if toPanel.Name == "WeaponsLockerHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateWeaponsLocker(toPanel)
					end)
				elseif toPanel.Name == "DeathSoundsLockerHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateDeathSoundsLocker(toPanel)
					end)
				elseif toPanel.Name == "TauntsLockerHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateTauntsLocker(toPanel)
					end)
				elseif toPanel.Name == "MeleeWeaponsLockerHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateMeleeWeaponsLocker(toPanel)
					end)
				end
			end)
		end
	elseif (fromPanel.Name == "WeaponsLockerHolder" or fromPanel.Name == "DeathSoundsLockerHolder" or fromPanel.Name == "TauntsLockerHolder" or fromPanel.Name == "MeleeWeaponsLockerHolder") and toPanel.Name == "OptionsHolder" then
		local lockerHolder = toPanel.Parent
		if lockerHolder then
			if lockerNameHolder then
				animatePanel(lockerNameHolder, "out", function()
					updateLockerHeader(lockerScreen, "main", false)
				end)
			end

			animatePanel(fromPanel, "out", function()
				animatePanel(lockerHolder, "in")

				if lockerNameHolder then animatePanel(lockerNameHolder, "in") end

				local lockerScreen = lockerHolder.Parent
				local mainReturnButton = lockerScreen and lockerScreen:FindFirstChild("ReturnButton")

				if mainReturnButton then animatePanel(mainReturnButton, "in") end

				lockerState.currentPanel = "options"
			end)
		end
	else
		if lockerNameHolder then
			animatePanel(lockerNameHolder, "out", function()
				updateLockerHeader(lockerScreen, toPanelName, false)
			end)
		end

		animatePanel(fromPanel, "out", function()
			animatePanel(toPanel, "in")

			if lockerNameHolder then animatePanel(lockerNameHolder, "in") end

			if toPanel.Name == "OptionsHolder" then
				lockerState.currentPanel = "options"
			elseif toPanel.Name == "WeaponsLockerHolder" then
				lockerState.currentPanel = "weapons"

				task.spawn(function()
					task.wait(0.1)
					populateWeaponsLocker(toPanel)
				end)
			elseif toPanel.Name == "DeathSoundsLockerHolder" then
				lockerState.currentPanel = "deathsounds"

				task.spawn(function()
					task.wait(0.1)
					populateDeathSoundsLocker(toPanel)
				end)
			elseif toPanel.Name == "TauntsLockerHolder" then
				lockerState.currentPanel = "taunts"

				task.spawn(function()
					task.wait(0.1)
					populateTauntsLocker(toPanel)
				end)
			elseif toPanel.Name == "MeleeWeaponsLockerHolder" then
				lockerState.currentPanel = "meleeweapons"

				task.spawn(function()
					task.wait(0.1)
					populateMeleeWeaponsLocker(toPanel)
				end)
			end
		end)
	end
end

	local function openLockerScreen(lockerScreen)
	cacheLockerHeaderValues(lockerScreen)

	lockerState.isOpen = true
	lockerState.currentPanel = "options"

	playSoundByName(lockerScreen, "ShopOpen")
	toggleCameraEffects(true)

	local elementsToAnimate = {
		lockerScreen:FindFirstChild("ReturnButton"),
		lockerScreen:FindFirstChild("LockerNameHolder"),
		lockerScreen:FindFirstChild("LockerHolder")
	}

	lockerScreen.Visible = true

	for _, element in ipairs(elementsToAnimate) do
		if element then
			element.Visible = true
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end
			animatePanel(element, "in")
		else
			print("Element not found in elementsToAnimate")
		end
	end

	local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")
	if weaponsLockerHolder then weaponsLockerHolder.Visible = false end

	local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder") 
	if deathSoundsLockerHolder then deathSoundsLockerHolder.Visible = false end

	local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")
	if tauntsLockerHolder then tauntsLockerHolder.Visible = false end

	local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")
	if meleeWeaponsLockerHolder then meleeWeaponsLockerHolder.Visible = false end
end

	local function closeLockerScreen(lockerScreen)
	resetAllWeaponTemplates()
	cleanupLockerAnimations()

	lockerState.isOpen = false
	lockerState.currentPanel = nil

	playSoundByName(lockerScreen, "ShopClose")
	toggleCameraEffects(false)

	local elementsToAnimate = {
		lockerScreen:FindFirstChild("ReturnButton"),
		lockerScreen:FindFirstChild("LockerNameHolder"),
		lockerScreen:FindFirstChild("LockerHolder")
	}

	local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")
	if weaponsLockerHolder and weaponsLockerHolder.Visible then
		table.insert(elementsToAnimate, weaponsLockerHolder)
	end

	local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")
	if deathSoundsLockerHolder and deathSoundsLockerHolder.Visible then
		table.insert(elementsToAnimate, deathSoundsLockerHolder)
	end

	local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")
	if tauntsLockerHolder and tauntsLockerHolder.Visible then
		table.insert(elementsToAnimate, tauntsLockerHolder)
	end

	local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")
	if meleeWeaponsLockerHolder and meleeWeaponsLockerHolder.Visible then
		table.insert(elementsToAnimate, meleeWeaponsLockerHolder)
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then animatePanel(element, "out") end
	end

	task.delay(0.2, function() lockerScreen.Visible = false end)
end

	local function setupButton(button, hoverColor, clickHandler)
	local originalColor = button.ImageColor3

	button.MouseEnter:Connect(function()
		playSoundByName(button, "Hover")
		TweenMethods.CreateTweenAsync(button, TweenMethods.PointOneSecondSineData, {
			ImageColor3 = hoverColor or Color3.fromRGB(255, 0, 0)
		})
	end)

	button.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(button, TweenMethods.PointOneSecondSineData, {
			ImageColor3 = originalColor
		})
	end)

	if clickHandler then button.MouseButton1Click:Connect(clickHandler) end

	return button
end

	local function setupFrames(lockerHolder)
	originalProperties = {}
	lockerHolder.Visible = true

	local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
	if not optionsHolder then return end

	local lockerFrames = {}

	-- Get all frames that could be locker options
	for _, frame in ipairs(optionsHolder:GetChildren()) do
		if frame:IsA("Frame") and 
			(frame.Name:find("Frame") or frame.Name:find("frame")) and
			not frame:FindFirstChild("UIListLayout") and
			not frame:FindFirstChild("UIGridLayout") then
			table.insert(lockerFrames, frame)
		end
	end

	-- Apply effects to all found frames
	for _, frame in ipairs(lockerFrames) do
		if frame then
			frame.Active = true

			local uiStroke = frame:FindFirstChildOfClass("UIStroke")
			local uiGradient = nil
			local gradientRotation = 0

			if uiStroke then
				uiGradient = uiStroke:FindFirstChildOfClass("UIGradient")
				if uiGradient and pcall(function() return uiGradient.Rotation end) then
					gradientRotation = uiGradient.Rotation
				end
			end

			local descriptionLabel = frame:FindFirstChild("DescriptionLabel")
			local descriptionPosition = nil
			if descriptionLabel and pcall(function() return descriptionLabel.Position end) then
				descriptionPosition = descriptionLabel.Position
			end

			local imageLabel = frame:FindFirstChildOfClass("ImageLabel")
			local imageLabelSize = nil
			if imageLabel and pcall(function() return imageLabel.Size end) then
				imageLabelSize = imageLabel.Size
			end

			originalProperties[frame] = {
				Size = frame.Size,
				Position = frame.Position,
				Stroke = uiStroke,
				Gradient = uiGradient,
				Description = descriptionLabel,
				DescriptionPosition = descriptionPosition,
				GradientRotation = gradientRotation,
				ImageLabel = imageLabel,
				ImageLabelSize = imageLabelSize,
				RotationConnection = nil,
				LevitationTween = nil
			}

			if descriptionLabel then descriptionLabel.TextTransparency = 1 end

			frame.MouseEnter:Connect(function() onMouseEnter(frame) end)
			frame.MouseLeave:Connect(function() onMouseLeave(frame) end)
		end
	end
end

	local function setupUI()
	local player = Players.LocalPlayer
	if not player then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local client = playerGui:FindFirstChild("Client")
	if not client then return end

	local lockerScreenFrame = client:FindFirstChild("LockerScreenFrame")
	if not lockerScreenFrame then return end

	local lockerScreen = lockerScreenFrame:FindFirstChild("LockerScreen")
	if not lockerScreen then return end

	UICache.lockerScreen = lockerScreen
	UICache.lockerScreenFrame = lockerScreenFrame

	local lockerButton = lockerScreenFrame:FindFirstChild("LockerButton") or lockerScreenFrame:FindFirstChild("LockerButton", true)
	if lockerButton then
		setupButton(lockerButton, Color3.new(
			math.min(lockerButton.ImageColor3.R * 1.2, 1),
			math.min(lockerButton.ImageColor3.G * 1.2, 1),
			math.min(lockerButton.ImageColor3.B * 1.2, 1)
			), function()
				if not lockerState.isOpen then
					openLockerScreen(lockerScreen)
				else
					closeLockerScreen(lockerScreen)
				end
			end)
	end

	setupButton(lockerScreen:FindFirstChild("ReturnButton"), Color3.fromRGB(255, 0, 0), function()
		playSoundByName(lockerScreen, "ShopClose")
		closeLockerScreen(lockerScreen)
	end)

	local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")
	if weaponsLockerHolder then
		local returnButton = weaponsLockerHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
				if lockerHolder then
					local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(weaponsLockerHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")
	if deathSoundsLockerHolder then
		local returnButton = deathSoundsLockerHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
				if lockerHolder then
					local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(deathSoundsLockerHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")
	if tauntsLockerHolder then
		local returnButton = tauntsLockerHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
				if lockerHolder then
					local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(tauntsLockerHolder, optionsHolder)
					end
				end
			end)
		else
			-- Try to create a return button if it doesn't exist
			local existingButton = deathSoundsLockerHolder and deathSoundsLockerHolder:FindFirstChild("ReturnButton")
			if existingButton then
				local newReturnButton = existingButton:Clone()
				newReturnButton.Parent = tauntsLockerHolder
				setupButton(newReturnButton, Color3.fromRGB(255, 0, 0), function()
					playSoundByName(newReturnButton, "ShopClose")
					local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
					if lockerHolder then
						local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
						if optionsHolder then
							transitionPanels(tauntsLockerHolder, optionsHolder)
						end
					end
				end)
			end
		end
	end

	local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")
	if meleeWeaponsLockerHolder then
		local returnButton = meleeWeaponsLockerHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
				if lockerHolder then
					local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(meleeWeaponsLockerHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local lockerHolder = lockerScreen:FindFirstChild("LockerHolder")
	if lockerHolder then
		local optionsHolder = lockerHolder:FindFirstChild("OptionsHolder")
		if optionsHolder then
			local weaponsFrame = optionsHolder:FindFirstChild("WeaponsFrame")
			if weaponsFrame and weaponsLockerHolder then
				local clickDetector = Instance.new("TextButton")
				clickDetector.Name = "ClickDetector"
				clickDetector.BackgroundTransparency = 1
				clickDetector.Text = ""
				clickDetector.Size = UDim2.new(1, 0, 1, 0)
				clickDetector.Position = UDim2.new(0, 0, 0, 0)
				clickDetector.ZIndex = weaponsFrame.ZIndex + 1
				clickDetector.AutoButtonColor = false
				clickDetector.Parent = weaponsFrame

				clickDetector.MouseButton1Click:Connect(function()
					playSoundByName(weaponsFrame, "ButtonClick")
					transitionPanels(optionsHolder, weaponsLockerHolder)
				end)
			end

			local deathSoundsFrame = optionsHolder:FindFirstChild("DeathSoundsFrame")
			if deathSoundsFrame and deathSoundsLockerHolder then
				local clickDetector = Instance.new("TextButton")
				clickDetector.Name = "ClickDetector"
				clickDetector.BackgroundTransparency = 1
				clickDetector.Text = ""
				clickDetector.Size = UDim2.new(1, 0, 1, 0)
				clickDetector.Position = UDim2.new(0, 0, 0, 0)
				clickDetector.ZIndex = deathSoundsFrame.ZIndex + 1
				clickDetector.AutoButtonColor = false
				clickDetector.Parent = deathSoundsFrame

				clickDetector.MouseButton1Click:Connect(function()
					playSoundByName(deathSoundsFrame, "ButtonClick")
					transitionPanels(optionsHolder, deathSoundsLockerHolder)
				end)
			end

			local tauntsFrame = optionsHolder:FindFirstChild("TauntsFrame") or optionsHolder:FindFirstChild("TauntFrame")
			if tauntsFrame and tauntsLockerHolder then
				local clickDetector = Instance.new("TextButton")
				clickDetector.Name = "ClickDetector"
				clickDetector.BackgroundTransparency = 1
				clickDetector.Text = ""
				clickDetector.Size = UDim2.new(1, 0, 1, 0)
				clickDetector.Position = UDim2.new(0, 0, 0, 0)
				clickDetector.ZIndex = tauntsFrame.ZIndex + 1
				clickDetector.AutoButtonColor = false
				clickDetector.Parent = tauntsFrame

				clickDetector.MouseButton1Click:Connect(function()
					playSoundByName(tauntsFrame, "ButtonClick")
					transitionPanels(optionsHolder, tauntsLockerHolder)
				end)
			end

			local meleeWeaponsFrame = optionsHolder:FindFirstChild("MeleeWeaponsFrame")
			if meleeWeaponsFrame and meleeWeaponsLockerHolder then
				local clickDetector = Instance.new("TextButton")
				clickDetector.Name = "ClickDetector"
				clickDetector.BackgroundTransparency = 1
				clickDetector.Text = ""
				clickDetector.Size = UDim2.new(1, 0, 1, 0)
				clickDetector.Position = UDim2.new(0, 0, 0, 0)
				clickDetector.ZIndex = meleeWeaponsFrame.ZIndex + 1
				clickDetector.AutoButtonColor = false
				clickDetector.Parent = meleeWeaponsFrame

				clickDetector.MouseButton1Click:Connect(function()
					playSoundByName(meleeWeaponsFrame, "ButtonClick")
					transitionPanels(optionsHolder, meleeWeaponsLockerHolder)
				end)
			end
		end

		setupFrames(lockerHolder)
	end

	lockerScreen.Visible = false
	lockerState.isOpen = false
	lockerState.currentPanel = nil
end

local function init()
	task.wait(6) -- Wait for all other systems first
	setupCameraEffects()

	local player = Players.LocalPlayer
	if not player then player = Players.PlayerAdded:Wait() end

	local playerGui = player:FindFirstChild("PlayerGui")
	while not playerGui do
		player.ChildAdded:Wait()
		playerGui = player:FindFirstChild("PlayerGui")
	end

	task.wait(1) -- Extra wait after finding PlayerGui
	setupUI()

	local client = playerGui:FindFirstChild("Client")
	if client then
		client.ChildAdded:Connect(function(child)
			if child.Name == "LockerScreenFrame" then
				task.wait(2) -- Increased from 0.1
				setupUI()
			end
		end)
	end
end

task.spawn(function()
	task.wait(3) -- Delay initialization even more than ShopUI
	init()
end)

-- Handle remote events
-- Handle remote events
-- Handle remote events
RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "WeaponOwnershipResponse" then
		local weaponId, isOwned, isActive = ...
		if not weaponId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")

		if weaponsLockerHolder and weaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local equipLabel = weaponsLockerHolder:FindFirstChild("Equipped", true)
			if equipLabel then
				if isActive then
					equipLabel.Text = "Equipped"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					equipLabel.Text = "Equip"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
			end
		end
	elseif eventName == "ActiveWeaponResponse" then
		local weaponId, isActive = ...
		if not weaponId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")

		if weaponsLockerHolder and weaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local equipLabel = weaponsLockerHolder:FindFirstChild("Equipped", true)
			if equipLabel then
				if isActive then
					equipLabel.Text = "Equipped"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					equipLabel.Text = "Equip"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
			end
		end
	elseif eventName == "MeleeWeaponOwnershipResponse" then
		local weaponId, isOwned, isActive = ...
		if not weaponId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")

		if meleeWeaponsLockerHolder and meleeWeaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local equipLabel = meleeWeaponsLockerHolder:FindFirstChild("Equipped", true)
			if equipLabel then
				if isActive then
					equipLabel.Text = "Equipped"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					equipLabel.Text = "Equip"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
			end
		end
	elseif eventName == "ActiveMeleeWeaponResponse" then
		local weaponId, isActive = ...
		if not weaponId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")

		if meleeWeaponsLockerHolder and meleeWeaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local equipLabel = meleeWeaponsLockerHolder:FindFirstChild("Equipped", true)
			if equipLabel then
				if isActive then
					equipLabel.Text = "Equipped"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					equipLabel.Text = "Equip"
					if equipLabel:IsA("TextLabel") then
						equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
			end
		end
	elseif eventName == "DeathSoundOwnershipResponse" then
		local soundId, isOwned, isActive = ...
		if not soundId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")

		if deathSoundsLockerHolder then
			local deathSoundsHolder = deathSoundsLockerHolder:FindFirstChild("DeathSoundsHolder")
			if deathSoundsHolder then
				local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
				if scrollFrameHolder then
					local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
					if soundScrollingFrame and soundId then
						local template = soundScrollingFrame:FindFirstChild("DeathSoundTemplate_" .. soundId)
						if template then
							local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
							if equipButtonFrame then
								local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
								if equipLabel then
									if isActive then
										equipLabel.Text = "Equipped"
										if equipLabel:IsA("TextLabel") then
											equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
										end
									else
										equipLabel.Text = "Equip"
										if equipLabel:IsA("TextLabel") then
											equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	elseif eventName == "TauntOwnershipResponse" then
		local tauntId, isOwned, isActive = ...
		if not tauntId then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")

		if tauntsLockerHolder then
			-- For the main display
			if tauntsLockerHolder:GetAttribute("SelectedTauntId") == tauntId then
				local equipButtonFrame = tauntsLockerHolder:FindFirstChild("EquipButtonFrame", true)
				if equipButtonFrame then
					local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
					if equipLabel then
						if isActive then
							equipLabel.Text = "Equipped"
							if equipLabel:IsA("TextLabel") then
								equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
							end
						else
							equipLabel.Text = "Equip"
							if equipLabel:IsA("TextLabel") then
								equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
							end
						end
					end
				end
			end

			-- For the template in the scrolling frame
			local tauntsHolder = tauntsLockerHolder:FindFirstChild("TauntsHolder")
			if tauntsHolder then
				local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
				if tauntsFrameHolder then
					local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
					if tauntsScrollingFrame then
						local template = tauntsScrollingFrame:FindFirstChild("TauntTemplate_" .. tauntId)
						if template then
							local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
							if equipButtonFrame then
								local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
								if equipLabel then
									if isActive then
										equipLabel.Text = "Equipped"
										if equipLabel:IsA("TextLabel") then
											equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
										end
									else
										equipLabel.Text = "Equip"
										if equipLabel:IsA("TextLabel") then
											equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	elseif eventName == "DeathSoundActivated" then
		local soundId = ...
		if not soundId then return end

		-- Update all death sound templates to show the activated one
		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")
		if deathSoundsLockerHolder then
			local deathSoundsHolder = deathSoundsLockerHolder:FindFirstChild("DeathSoundsHolder")
			if deathSoundsHolder then
				local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
				if scrollFrameHolder then
					local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
					if soundScrollingFrame then
						for _, template in ipairs(soundScrollingFrame:GetChildren()) do
							if template:IsA("Frame") and template.Name:find("DeathSoundTemplate_") then
								local templateSoundId = template:GetAttribute("SoundId")
								local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
								if equipButtonFrame then
									local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
									if equipLabel then
										if templateSoundId == soundId then
											equipLabel.Text = "Equipped"
											if equipLabel:IsA("TextLabel") then
												equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
											end
										else
											equipLabel.Text = "Equip"
											if equipLabel:IsA("TextLabel") then
												equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	elseif eventName == "TauntActivated" then
		local tauntId = ...
		if not tauntId then return end

		-- Update all taunt templates to show the activated one
		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")
		if tauntsLockerHolder then
			local tauntsHolder = tauntsLockerHolder:FindFirstChild("TauntsHolder")
			if tauntsHolder then
				local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
				if tauntsFrameHolder then
					local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
					if tauntsScrollingFrame then
						for _, template in ipairs(tauntsScrollingFrame:GetChildren()) do
							if template:IsA("Frame") and template.Name:find("TauntTemplate_") then
								local templateTauntId = template:GetAttribute("TauntId")
								local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
								if equipButtonFrame then
									local equipLabel = equipButtonFrame:FindFirstChild("EquipText")
									if equipLabel then
										if templateTauntId == tauntId then
											equipLabel.Text = "Equipped"
											if equipLabel:IsA("TextLabel") then
												equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
											end
										else
											equipLabel.Text = "Equip"
											if equipLabel:IsA("TextLabel") then
												equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	elseif eventName == "WeaponEquipped" or eventName == "MeleeWeaponEquipped" then
		local weaponId = ...
		if not weaponId then return end

		local player = Players.LocalPlayer
		if player and player.PlayerGui then
			local notification = Instance.new("ScreenGui")
			notification.Name = "DebugNotification"
			notification.Parent = player.PlayerGui

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(0, 400, 0, 100)
			frame.Position = UDim2.new(0.5, -200, 0.2, 0)
			frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			frame.BackgroundTransparency = 0.5
			frame.BorderSizePixel = 0
			frame.Parent = notification

			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.new(1, 0, 1, 0)
			textLabel.BackgroundTransparency = 1
			textLabel.Font = Enum.Font.GothamBold
			textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			textLabel.TextSize = 14
			textLabel.Text = "DEBUG: WeaponEquipped event received for: " .. weaponId
			textLabel.Parent = frame

			-- Auto-remove after 5 seconds
			task.delay(5, function() notification:Destroy() end)
		end
			
		-- Notify the player that the weapon was equipped
		local player = Players.LocalPlayer
		if player and player.PlayerGui then
			local notification = Instance.new("ScreenGui")
			notification.Name = "EquipNotification"
			notification.Parent = player.PlayerGui

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(0, 300, 0, 50)
			frame.Position = UDim2.new(0.5, -150, 0.8, 0)
			frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			frame.BackgroundTransparency = 0.5
			frame.BorderSizePixel = 0
			frame.Parent = notification

			local uiCorner = Instance.new("UICorner")
			uiCorner.CornerRadius = UDim.new(0, 8)
			uiCorner.Parent = frame

			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.new(1, 0, 1, 0)
			textLabel.Position = UDim2.new(0, 0, 0, 0)
			textLabel.BackgroundTransparency = 1
			textLabel.Font = Enum.Font.GothamBold
			textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			textLabel.TextSize = 18
			textLabel.Text = "Weapon equipped!"
			textLabel.Parent = frame

			-- Tween the notification in and then out
			frame.Position = UDim2.new(0.5, -150, 1.1, 0)
			TweenMethods.CreateTweenAsync(frame, TweenMethods.HalfSecondSineData, {
				Position = UDim2.new(0.5, -150, 0.8, 0)
			})

			task.delay(2, function()
				TweenMethods.CreateTweenAsync(frame, TweenMethods.HalfSecondSineData, {
					Position = UDim2.new(0.5, -150, 1.1, 0)
				})

				task.delay(0.5, function()
					notification:Destroy()
				end)
			end)
		end

		-- NEW CODE: Update all weapon/melee weapon templates based on equipped status
		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen

		if eventName == "WeaponEquipped" then
			local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")
			if weaponsLockerHolder then
				-- Update detail view if selected
				if weaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
					local equipLabel = weaponsLockerHolder:FindFirstChild("Equipped", true)
					if equipLabel then
						equipLabel.Text = "Equipped"
						if equipLabel:IsA("TextLabel") then
							equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
						end
					end
				end

				-- Update all templates in grid
				local weaponsHolder = weaponsLockerHolder:FindFirstChild("WeaponsHolder")
				if weaponsHolder then
					local scrollFrameHolder = weaponsHolder:FindFirstChild("ScrollFrameHolder")
					if scrollFrameHolder then
						local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
						if scrollingFrame then
							for _, template in ipairs(scrollingFrame:GetChildren()) do
								if template:IsA("Frame") and template.Name:find("WeaponTemplate_") then
									local templateWeaponId = template:GetAttribute("WeaponId")
									local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
									if equipButtonFrame then
										local equipLabel = equipButtonFrame:FindFirstChild("EquipText") or equipButtonFrame:FindFirstChild("Equipped")
										if equipLabel then
											if templateWeaponId == weaponId then
												equipLabel.Text = "Equipped"
												if equipLabel:IsA("TextLabel") then
													equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
												end
											else
												equipLabel.Text = "Equip"
												if equipLabel:IsA("TextLabel") then
													equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		elseif eventName == "MeleeWeaponEquipped" then
			local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")
			if meleeWeaponsLockerHolder then
				-- Update detail view if selected
				if meleeWeaponsLockerHolder:GetAttribute("SelectedWeaponId") == weaponId then
					local equipLabel = meleeWeaponsLockerHolder:FindFirstChild("Equipped", true)
					if equipLabel then
						equipLabel.Text = "Equipped"
						if equipLabel:IsA("TextLabel") then
							equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
						end
					end
				end

				-- Update all templates in grid
				local meleeWeaponsHolder = meleeWeaponsLockerHolder:FindFirstChild("MeleeWeaponsHolder")
				if meleeWeaponsHolder then
					local scrollFrameHolder = meleeWeaponsHolder:FindFirstChild("ScrollFrameHolder")
					if scrollFrameHolder then
						local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
						if scrollingFrame then
							for _, template in ipairs(scrollingFrame:GetChildren()) do
								if template:IsA("Frame") and template.Name:find("MeleeWeaponTemplate_") then
									local templateWeaponId = template:GetAttribute("WeaponId")
									local equipButtonFrame = template:FindFirstChild("EquipButtonFrame")
									if equipButtonFrame then
										local equipLabel = equipButtonFrame:FindFirstChild("EquipText") or equipButtonFrame:FindFirstChild("Equipped")
										if equipLabel then
											if templateWeaponId == weaponId then
												equipLabel.Text = "Equipped"
												if equipLabel:IsA("TextLabel") then
													equipLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
												end
											else
												equipLabel.Text = "Equip"
												if equipLabel:IsA("TextLabel") then
													equipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	elseif eventName == "OwnedWeaponsResponse" then
		local ownedWeapons = ...
		if typeof(ownedWeapons) ~= "table" then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local weaponsLockerHolder = lockerScreen:FindFirstChild("WeaponsLockerHolder")
		if not weaponsLockerHolder then return end

		local weaponsHolder = weaponsLockerHolder:FindFirstChild("WeaponsHolder")
		if not weaponsHolder then return end

		local scrollFrameHolder = weaponsHolder:FindFirstChild("ScrollFrameHolder")
		if not scrollFrameHolder then return end

		local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then return end

		-- Remove loading indicator if it exists
		local loadingIndicator = scrollingFrame:FindFirstChild("LoadingIndicator")
		if loadingIndicator then loadingIndicator:Destroy() end

		-- Get template references
		local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
		if not templateFolder then return end

		local standardTemplate = templateFolder:FindFirstChild("WeaponTemplate")
		local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")

		if not standardTemplate then return end
		if not rareTemplate then rareTemplate = standardTemplate end

		-- Populate UI with owned weapons
		local WeaponData = require(ReplicatedStorage.Data.WeaponData)

		-- Track if we found at least one weapon to display
		local foundWeapon = false
		local firstWeaponId, firstWeaponData

		for weaponId, data in pairs(WeaponData) do
			if ownedWeapons[weaponId] then
				local templateToUse = standardTemplate
				if data.rarity and string.lower(data.rarity) == "rare" then
					templateToUse = rareTemplate
				end

				local newWeapon = templateToUse:Clone()
				newWeapon.Name = "WeaponTemplate_" .. weaponId
				newWeapon.Visible = true

				newWeapon:SetAttribute("WeaponId", weaponId)
				newWeapon:SetAttribute("DisplayName", data.displayName)
				newWeapon:SetAttribute("Rarity", data.rarity)
				newWeapon:SetAttribute("Description", data.description)

				if newWeapon:GetAttribute("EffectsInitialized") then
					newWeapon:SetAttribute("EffectsInitialized", false)
				end

				local nameLabel = newWeapon:FindFirstChild("ItemName")
				if nameLabel then nameLabel.Text = data.displayName end

				local rarityLabel = newWeapon:FindFirstChild("ItemRarity")
				if rarityLabel then rarityLabel.Text = data.rarity end

				local classLabel = newWeapon:FindFirstChild("ItemClass")
				if classLabel then classLabel.Text = data.rarity end

				local viewportFrame = newWeapon:FindFirstChildWhichIsA("ViewportFrame")
				if viewportFrame then
					setupWeaponViewport(viewportFrame, weaponId)
					startFloatingAnimation(viewportFrame, "template_" .. weaponId)
				end

				-- Rename BuyButton to EquipButton if needed
				local buyButtonFrame = newWeapon:FindFirstChild("BuyButtonFrame")
				if buyButtonFrame then
					buyButtonFrame.Name = "EquipButtonFrame"
					local priceLabel = buyButtonFrame:FindFirstChild("Price")
					if priceLabel then
						priceLabel.Name = "EquipText"
						priceLabel.Text = "Equip"
					end
				end

				setupWeaponTemplateEffects(newWeapon, weaponId)
				newWeapon.Parent = scrollingFrame

				if not foundWeapon then
					foundWeapon = true
					firstWeaponId = weaponId
					firstWeaponData = data
				end
			end
		end

		-- Setup grid layout
		local grid = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
		if grid then
			task.delay(0.2, function()
				local absoluteContentSize = grid.AbsoluteContentSize
				local canvasHeight = math.max(absoluteContentSize.Y + grid.CellPadding.Y.Offset, scrollingFrame.AbsoluteSize.Y * 2)
				scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
			end)
		end

		-- Display first weapon
		if firstWeaponId then
			updateMainWeaponViewport(firstWeaponId, firstWeaponData)
			local equipButtonFrame = weaponsLockerHolder:FindFirstChild("EquipButtonFrame")
			if equipButtonFrame and firstWeaponId then
				setupWeaponEquipButtonInteraction(equipButtonFrame, firstWeaponId, nil)
			end
		end

	elseif eventName == "OwnedMeleeWeaponsResponse" then
		local ownedMeleeWeapons = ...
		if typeof(ownedMeleeWeapons) ~= "table" then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local meleeWeaponsLockerHolder = lockerScreen:FindFirstChild("MeleeWeaponsLockerHolder")
		if not meleeWeaponsLockerHolder then return end

		local meleeWeaponsHolder = meleeWeaponsLockerHolder:FindFirstChild("MeleeWeaponsHolder")
		if not meleeWeaponsHolder then return end

		local scrollFrameHolder = meleeWeaponsHolder:FindFirstChild("ScrollFrameHolder")
		if not scrollFrameHolder then return end

		local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then return end

		-- Remove loading indicator if it exists
		local loadingIndicator = scrollingFrame:FindFirstChild("LoadingIndicator")
		if loadingIndicator then loadingIndicator:Destroy() end

		-- Get template references
		local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
		if not templateFolder then return end

		local standardTemplate = templateFolder:FindFirstChild("WeaponTemplate")
		local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")
		local uncommonTemplate = templateFolder:FindFirstChild("UncommonWeaponTemplate")

		if not standardTemplate then return end
		if not rareTemplate then rareTemplate = standardTemplate end
		if not uncommonTemplate then uncommonTemplate = standardTemplate end

		-- Populate UI with owned melee weapons
		local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)

		-- Track if we found at least one weapon to display
		local foundWeapon = false
		local firstWeaponId, firstWeaponData

		for weaponId, data in pairs(MeleeWeaponData) do
			if ownedMeleeWeapons[weaponId] then
				local templateToUse = standardTemplate
				if data.rarity then
					if string.lower(data.rarity) == "rare" then
						templateToUse = rareTemplate
					elseif string.lower(data.rarity) == "uncommon" then
						templateToUse = uncommonTemplate
					end
				end

				local newWeapon = templateToUse:Clone()
				newWeapon.Name = "MeleeWeaponTemplate_" .. weaponId
				newWeapon.Visible = true

				newWeapon:SetAttribute("WeaponId", weaponId)
				newWeapon:SetAttribute("DisplayName", data.displayName)
				newWeapon:SetAttribute("Rarity", data.rarity)
				newWeapon:SetAttribute("Description", data.description)

				if newWeapon:GetAttribute("EffectsInitialized") then
					newWeapon:SetAttribute("EffectsInitialized", false)
				end

				local nameLabel = newWeapon:FindFirstChild("ItemName")
				if nameLabel then nameLabel.Text = data.displayName end

				local rarityLabel = newWeapon:FindFirstChild("ItemRarity")
				if rarityLabel then rarityLabel.Text = data.rarity end

				local classLabel = newWeapon:FindFirstChild("ItemClass")
				if classLabel then classLabel.Text = data.rarity end

				local viewportFrame = newWeapon:FindFirstChildWhichIsA("ViewportFrame")
				if viewportFrame then
					setupWeaponViewport(viewportFrame, weaponId)
					startFloatingAnimation(viewportFrame, "template_" .. weaponId)
				end

				-- Rename BuyButton to EquipButton if needed
				local buyButtonFrame = newWeapon:FindFirstChild("BuyButtonFrame")
				if buyButtonFrame then
					buyButtonFrame.Name = "EquipButtonFrame"
					local priceLabel = buyButtonFrame:FindFirstChild("Price")
					if priceLabel then
						priceLabel.Name = "EquipText"
						priceLabel.Text = "Equip"
					end
				end

				setupMeleeWeaponTemplateEffects(newWeapon, weaponId)
				newWeapon.Parent = scrollingFrame

				if not foundWeapon then
					foundWeapon = true
					firstWeaponId = weaponId
					firstWeaponData = data
				end
			end
		end

		-- Setup grid layout
		local grid = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
		if grid then
			task.delay(0.2, function()
				local absoluteContentSize = grid.AbsoluteContentSize
				local canvasHeight = math.max(absoluteContentSize.Y + grid.CellPadding.Y.Offset, scrollingFrame.AbsoluteSize.Y * 2)
				scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
			end)
		end

		-- Display first weapon
		if firstWeaponId then
			updateMainMeleeWeaponViewport(firstWeaponId, firstWeaponData)
			local equipButtonFrame = meleeWeaponsLockerHolder:FindFirstChild("EquipButtonFrame")
			if equipButtonFrame and firstWeaponId then
				setupMeleeWeaponEquipButtonInteraction(equipButtonFrame, firstWeaponId, nil)
			end
		end

	elseif eventName == "OwnedDeathSoundsResponse" then
		local ownedDeathSounds = ...
		if typeof(ownedDeathSounds) ~= "table" then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local deathSoundsLockerHolder = lockerScreen:FindFirstChild("DeathSoundsLockerHolder")
		if not deathSoundsLockerHolder then return end

		local deathSoundsHolder = deathSoundsLockerHolder:FindFirstChild("DeathSoundsHolder")
		if not deathSoundsHolder then return end

		local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
		if not scrollFrameHolder then return end

		local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
		if not soundScrollingFrame then return end

		-- Remove loading indicator if it exists
		local loadingIndicator = soundScrollingFrame:FindFirstChild("LoadingIndicator")
		if loadingIndicator then loadingIndicator:Destroy() end

		-- Get template references
		local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
		if not templateFolder then return end

		local soundTemplate = templateFolder:FindFirstChild("DeathSoundTemplate")
		if not soundTemplate then return end

		-- Populate UI with owned death sounds
		local DeathSoundData = require(ReplicatedStorage.Data.DeathSoundData)

		for soundId, data in pairs(DeathSoundData) do
			if ownedDeathSounds[soundId] then
				local newSound = soundTemplate:Clone()
				newSound.Name = "DeathSoundTemplate_" .. soundId
				newSound.Visible = true

				newSound:SetAttribute("SoundId", soundId)
				newSound:SetAttribute("DisplayName", data.displayName)
				newSound:SetAttribute("Description", data.description)
				newSound:SetAttribute("RbxSoundId", data.soundId)

				if newSound:GetAttribute("EffectsInitialized") then
					newSound:SetAttribute("EffectsInitialized", false)
				end

				local nameFrame = newSound:FindFirstChild("DeathSoundNameFrame")
				if nameFrame then
					local nameLabel = nameFrame:FindFirstChild("DeathSoundName")
					if nameLabel then nameLabel.Text = data.displayName end

					local descriptionLabel = nameFrame:FindFirstChild("DeathSoundDescription")
					if descriptionLabel then descriptionLabel.Text = data.description end
				end

				-- Rename BuyButtonFrame to EquipButtonFrame if needed
				local buyButtonFrame = newSound:FindFirstChild("BuyButtonFrame")
				if buyButtonFrame then
					buyButtonFrame.Name = "EquipButtonFrame"
					local priceLabel = buyButtonFrame:FindFirstChild("Price")
					if priceLabel then
						priceLabel.Name = "EquipText"
						priceLabel.Text = "Equip"
					end
					buyButtonFrame.Visible = false
					setElementTransparency(buyButtonFrame, true)
				end

				setupDeathSoundTemplateEffects(newSound, soundId)
				newSound.Parent = soundScrollingFrame
			end
		end

		local layout = soundScrollingFrame:FindFirstChildOfClass("UIGridLayout") or soundScrollingFrame:FindFirstChildOfClass("UIListLayout")

		if layout then
			task.delay(0.2, function()
				local absoluteContentSize = layout.AbsoluteContentSize
				local canvasHeight = math.max(absoluteContentSize.Y + (layout.CellPadding and layout.CellPadding.Y.Offset or 0), 
					soundScrollingFrame.AbsoluteSize.Y * 2)
				soundScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
			end)
		end

		currentVisibleEquipButton = nil

	elseif eventName == "OwnedTauntsResponse" then
		local ownedTaunts = ...
		if typeof(ownedTaunts) ~= "table" then return end

		local lockerScreen = Players.LocalPlayer.PlayerGui.Client.LockerScreenFrame.LockerScreen
		local tauntsLockerHolder = lockerScreen:FindFirstChild("TauntsLockerHolder")
		if not tauntsLockerHolder then return end

		local tauntsHolder = tauntsLockerHolder:FindFirstChild("TauntsHolder")
		if not tauntsHolder then return end

		local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
		if not tauntsFrameHolder then return end

		local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
		if not tauntsScrollingFrame then return end

		-- Remove loading indicator if it exists
		local loadingIndicator = tauntsScrollingFrame:FindFirstChild("LoadingIndicator")
		if loadingIndicator then loadingIndicator:Destroy() end

		-- Get template references
		local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
		if not templateFolder then return end

		local tauntTemplate = templateFolder:FindFirstChild("TauntTemplate")
		if not tauntTemplate then return end

		-- Populate UI with owned taunts
		local TauntSoundData = require(ReplicatedStorage.Data.TauntSoundData)
		local tauntCount = 0

		-- Track if we found at least one taunt to display
		local firstTauntId, firstTauntData

		for tauntId, data in pairs(TauntSoundData) do
			if ownedTaunts[tauntId] then
				local newTaunt = tauntTemplate:Clone()
				newTaunt.Name = "TauntTemplate_" .. tauntId
				newTaunt.Visible = true

				newTaunt:SetAttribute("TauntId", tauntId)
				newTaunt:SetAttribute("DisplayName", data.displayName)
				newTaunt:SetAttribute("Description", data.description)
				newTaunt:SetAttribute("SoundId", data.soundId)

				if newTaunt:GetAttribute("EffectsInitialized") then
					newTaunt:SetAttribute("EffectsInitialized", false)
				end

				local nameFrame = newTaunt:FindFirstChild("TauntNameFrame")
				if nameFrame then
					local nameLabel = nameFrame:FindFirstChild("TauntName")
					if nameLabel then nameLabel.Text = data.displayName end

					local descriptionLabel = nameFrame:FindFirstChild("TauntDescription")
					if descriptionLabel then descriptionLabel.Text = data.description end
				end

				-- Rename BuyButtonFrame to EquipButtonFrame if needed
				local buyButtonFrame = newTaunt:FindFirstChild("BuyButtonFrame")
				if buyButtonFrame then
					buyButtonFrame.Name = "EquipButtonFrame"
					local priceLabel = buyButtonFrame:FindFirstChild("Price")
					if priceLabel then
						priceLabel.Name = "EquipText"
						priceLabel.Text = "Equip"
					end
					buyButtonFrame.Visible = false
					setElementTransparency(buyButtonFrame, true)
				end

				setupTauntTemplateEffects(newTaunt, tauntId)
				newTaunt.Parent = tauntsScrollingFrame
				tauntCount = tauntCount + 1

				if not firstTauntId then
					firstTauntId = tauntId
					firstTauntData = data
				end
			end
		end

		-- Setup layout
		local layout = tauntsScrollingFrame:FindFirstChildOfClass("UIGridLayout") or tauntsScrollingFrame:FindFirstChildOfClass("UIListLayout")

		if layout then
			task.delay(0.2, function()
				local absoluteContentSize = layout.AbsoluteContentSize
				local canvasHeight = math.max(absoluteContentSize.Y + (layout.CellPadding and layout.CellPadding.Y.Offset or 0), 
					tauntsScrollingFrame.AbsoluteSize.Y * 2)
				tauntsScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
			end)
		end

		currentVisibleTauntEquipButton = nil

		-- Display first taunt if available
		if firstTauntId then
			updateMainTauntView(firstTauntId, firstTauntData)
		end
	end
end)
