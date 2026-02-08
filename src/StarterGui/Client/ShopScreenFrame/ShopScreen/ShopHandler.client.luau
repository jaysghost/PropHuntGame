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
local currentVisibleBuyButton, currentSelectedSoundTemplate, currentSelectedSound, currentSoundInstance = nil, nil, nil, nil
local floatingAnimations, viewportTweens, activeTweens, soundPreviewStates, UICache = {}, {}, {}, {}, {}
local currentSelectedTauntTemplate, currentSelectedTaunt, currentTauntSoundInstance = nil, nil, nil
local currentVisibleTauntBuyButton = nil
local tauntPreviewStates = {}
local shopState = {isOpen = false, currentPanel = nil}
local originalShopHeaderValues = {gradientColors = nil, text = nil}


local function cacheShopHeaderValues(shopScreen)
	if originalShopHeaderValues.gradientColors then return end
	local shopNameHolder = shopScreen:FindFirstChild("ShopNameHolder")
	if not shopNameHolder then return end
	local shopName = shopNameHolder:FindFirstChild("ShopName")
	if not shopName then return end
	originalShopHeaderValues.text = shopName.Text
	local gradient = shopName:FindFirstChildOfClass("UIGradient")
	if gradient then originalShopHeaderValues.gradientColors = gradient.Color end
end

local function updateShopHeader(shopScreen, panelName, tweenOut)
	local shopNameHolder = shopScreen:FindFirstChild("ShopNameHolder")
	if not shopNameHolder then return end
	local shopName = shopNameHolder:FindFirstChild("ShopName")
	if not shopName then return end
	local gradient = shopName:FindFirstChildOfClass("UIGradient")
	if not gradient then return end
	cacheShopHeaderValues(shopScreen)
	if tweenOut then return end

	if panelName == "weapons" then
		shopName.Text = "weapons"
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
		shopName.Text = "death sounds"
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
		shopName.Text = "taunts"
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
	elseif panelName == "money" then
		shopName.Text = "money"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(255, 215, 0)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "meleeweapons" then
		shopName.Text = "melee weapons"
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
	elseif panelName == "passes" then
		shopName.Text = "game passes"
		if gradient then
			local keypoints = gradient.Color.Keypoints
			local newKeypoints = {}
			for i, keypoint in ipairs(keypoints) do
				if i <= 2 then
					table.insert(newKeypoints, ColorSequenceKeypoint.new(keypoint.Time, Color3.fromRGB(0, 200, 255)))
				else
					table.insert(newKeypoints, keypoint)
				end
			end
			gradient.Color = ColorSequence.new(newKeypoints)
		end
	elseif panelName == "main" or panelName == "options" then
		shopName.Text = originalShopHeaderValues.text or "shop"
		if gradient and originalShopHeaderValues.gradientColors then
			gradient.Color = originalShopHeaderValues.gradientColors
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
	local shopScreenFrame = client:FindFirstChild("ShopScreenFrame")
	local shopScreen = shopScreenFrame:FindFirstChild("ShopScreen")
	local weaponsShopHolder = shopScreen:FindFirstChild("WeaponsShopHolder")

	if not weaponsShopHolder then return end

	if currentSelectedWeapon then
		stopFloatingAnimation("detail_" .. currentSelectedWeapon)
	end

	currentSelectedWeapon = weaponId

	local dropShadowHolder = weaponsShopHolder:FindFirstChild("DropShadowHolder", true)
	local dropShadow = dropShadowHolder and dropShadowHolder:FindFirstChild("DropShadow")

	local elementsToAnimate = {
		dropShadowHolder,
		weaponsShopHolder:FindFirstChild("WeaponViewport", true),
		weaponsShopHolder:FindFirstChild("BuyButtonFrame", true),
		weaponsShopHolder.BuyButtonFrame:FindFirstChild("Price", true),
		weaponsShopHolder:FindFirstChild("DescriptionLabel", true),
		weaponsShopHolder:FindFirstChild("ItemClass", true),
		weaponsShopHolder:FindFirstChild("ItemName", true)
	}

	local templateFolder = game:GetService("StarterGui"):FindFirstChild("Templates")
	local isRare = weaponData.rarity and string.lower(weaponData.rarity) == "rare"

	local itemClass = weaponsShopHolder:FindFirstChild("ItemClass", true)
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
	local itemDescriptionHolder = weaponsShopHolder:FindFirstChild("ItemDescriptionHolder")
	if itemDescriptionHolder then
		viewportFrame = itemDescriptionHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if not viewportFrame then
		viewportFrame = weaponsShopHolder:FindFirstChildWhichIsA("ViewportFrame", true)
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

	local priceLabel = weaponsShopHolder:FindFirstChild("Price", true)
	if priceLabel then priceLabel.Text = "C$ " .. weaponData.price end

	for name, value in pairs(elements) do
		local element = weaponsShopHolder:FindFirstChild(name, true)
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

	weaponsShopHolder:SetAttribute("SelectedWeaponId", weaponId)
end



local function setupWeaponBuyButtonInteraction(buyButtonFrame, weaponId, template)
	if not buyButtonFrame then return end
	if weaponId == nil then return end

	local priceLabel = buyButtonFrame:FindFirstChild("Price")
	local uiStroke = buyButtonFrame:FindFirstChildOfClass("UIStroke")

	if not buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", buyButtonFrame.Position.X.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", buyButtonFrame.Position.X.Offset)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", buyButtonFrame.Position.Y.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", buyButtonFrame.Position.Y.Offset)
	end

	local originalSize = buyButtonFrame.Size

	if uiStroke then
		if not buyButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			buyButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	buyButtonFrame:SetAttribute("WeaponId", weaponId)

	if priceLabel then
		local weaponData = WeaponData[weaponId]
		if weaponData and weaponData.price then
			priceLabel.Text = "C$ " .. weaponData.price
		end
	end

	local clickDetector = buyButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = buyButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = buyButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(buyButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
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

		buyButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				buyButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		buyButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		-- Find the weaponsShopHolder parent
		local parent = buyButtonFrame.Parent
		while parent and parent.Name ~= "WeaponsShopHolder" do
			parent = parent.Parent
		end

		-- Get the currently selected weapon ID
		local currentWeaponId = weaponId -- Default to original ID
		if parent and parent:GetAttribute("SelectedWeaponId") then
			currentWeaponId = parent:GetAttribute("SelectedWeaponId")
		end

		-- Debug output
		print("Click purchase for weapon ID: " .. currentWeaponId)

		if priceLabel and priceLabel.Text == "Owned" then
			-- If owned, set this as the active weapon
			RemoteEvent:FireServer("SetActiveWeapon", currentWeaponId)
			return
		end

		local weaponData = WeaponData[currentWeaponId]
		if not weaponData then return end

		playSoundByName(buyButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if priceLabel then priceLabel.Text = "..." end

		RemoteEvent:FireServer("PurchaseWeapon", currentWeaponId, weaponData.price)
	end)

	local trueOriginalPosition = UDim2.new(
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or buyButtonFrame.Position.X.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or buyButtonFrame.Position.X.Offset,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or buyButtonFrame.Position.Y.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or buyButtonFrame.Position.Y.Offset
	)

	buyButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	buyButtonFrame.Visible = false
	setElementTransparency(buyButtonFrame, true)

	RemoteEvent:FireServer("CheckWeaponOwnership", weaponId)
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

local function animateBuyButton(buyButtonFrame, show)
	if not buyButtonFrame then return end

	if activeTweens[buyButtonFrame] then
		activeTweens[buyButtonFrame]:Cancel()
		activeTweens[buyButtonFrame] = nil
	end

	local originalPosition = UDim2.new(
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or 0,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or 0,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or 0,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or 0
	)

	local showPosition = originalPosition
	local hidePosition = originalPosition + UDim2.new(0, 0, 0.2, 0)

	local uiStroke = buyButtonFrame:FindFirstChildOfClass("UIStroke")

	if show then
		buyButtonFrame.Visible = true

		if buyButtonFrame.Position ~= hidePosition then
			buyButtonFrame.Position = hidePosition
		end

		if uiStroke then
			local originalColor = Color3.new(
				buyButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)
			uiStroke.Color = originalColor
		end

		local positionTween = TweenService:Create(
			buyButtonFrame, 
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = showPosition}
		)
		positionTween:Play()

		activeTweens[buyButtonFrame] = positionTween
		setElementTransparency(buyButtonFrame, false, TweenMethods.HalfSecondSineData)
	else
		local positionTween = TweenService:Create(
			buyButtonFrame, 
			TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = hidePosition}
		)
		positionTween:Play()

		activeTweens[buyButtonFrame] = positionTween
		setElementTransparency(buyButtonFrame, true, TweenMethods.ReturnSineData(0.2))

		task.delay(0.2, function()
			if not buyButtonFrame:GetAttribute("StayVisible") then
				buyButtonFrame.Visible = false
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

	if currentVisibleBuyButton and currentVisibleBuyButton.Parent then
		animateBuyButton(currentVisibleBuyButton, false)
	end
	currentVisibleBuyButton = nil

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

			local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
			if buyButtonFrame then
				buyButtonFrame.Visible = false
				setElementTransparency(buyButtonFrame, true)
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
	local shopScreenFrame = client:FindFirstChild("ShopScreenFrame")
	local shopScreen = shopScreenFrame:FindFirstChild("ShopScreen")
	local deathSoundsShopHolder = shopScreen:FindFirstChild("DeathSoundsShopHolder")

	if not deathSoundsShopHolder then return end

	local deathSoundsHolder = deathSoundsShopHolder:FindFirstChild("DeathSoundsHolder")
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

	deathSoundsShopHolder:SetAttribute("SelectedSoundId", soundId)

	if visualizerFrame then enhanceExistingVisualizer(visualizerFrame) end
end

local function setupBuyButtonInteraction(buyButtonFrame, soundId, template)
	if not buyButtonFrame then return end

	if soundId == nil then return end

	local priceLabel = buyButtonFrame:FindFirstChild("Price")
	local uiStroke = buyButtonFrame:FindFirstChildOfClass("UIStroke")

	if not buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", buyButtonFrame.Position.X.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", buyButtonFrame.Position.X.Offset)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", buyButtonFrame.Position.Y.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", buyButtonFrame.Position.Y.Offset)
	end

	local originalSize = buyButtonFrame.Size

	if uiStroke then
		if not buyButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			buyButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	buyButtonFrame:SetAttribute("SoundId", soundId)

	if priceLabel then
		local soundData = DeathSoundData[soundId]
		if soundData and soundData.price then
			priceLabel.Text = "C$ " .. soundData.price
		end
	end

	local clickDetector = buyButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = buyButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = buyButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(buyButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
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

		buyButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				buyButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		buyButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		if priceLabel and priceLabel.Text == "Owned" then
			local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
			RemoteEvent:FireServer("SetActiveDeathSound", soundId)
			return
		end

		local soundData = DeathSoundData[soundId]
		if not soundData then return end

		playSoundByName(buyButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if priceLabel then priceLabel.Text = "..." end

		local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
		RemoteEvent:FireServer("PurchaseDeathSound", soundId, soundData.price)
	end)

	local trueOriginalPosition = UDim2.new(
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or buyButtonFrame.Position.X.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or buyButtonFrame.Position.X.Offset,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or buyButtonFrame.Position.Y.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or buyButtonFrame.Position.Y.Offset
	)

	buyButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	buyButtonFrame.Visible = false
	setElementTransparency(buyButtonFrame, true)

	local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
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

	local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
	if buyButtonFrame then
		setupBuyButtonInteraction(buyButtonFrame, soundId, template)
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

		local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")

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

			if currentVisibleBuyButton then
				animateBuyButton(currentVisibleBuyButton, false)
			end
		end

		currentSelectedSoundTemplate = template

		if buyButtonFrame then
			buyButtonFrame:SetAttribute("StayVisible", true)
			animateBuyButton(buyButtonFrame, true)
			currentVisibleBuyButton = buyButtonFrame

			task.delay(0.5, function()
				buyButtonFrame:SetAttribute("StayVisible", false)
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

local function checkSoundOwnership(soundId, template)
	if soundId == nil then return end

	local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
	if not buyButtonFrame then return end

	local priceLabel = buyButtonFrame:FindFirstChild("Price")
	if not priceLabel then return end

	local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	RemoteEvent:FireServer("CheckDeathSoundOwnership", soundId)
end

local function updateMainMeleeWeaponViewport(weaponId, weaponData)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	local client = playerGui:FindFirstChild("Client")
	local shopScreenFrame = client:FindFirstChild("ShopScreenFrame")
	local shopScreen = shopScreenFrame:FindFirstChild("ShopScreen")
	
	print(weaponId)
	local meleeWeaponsShopHolder = shopScreen:FindFirstChild("MeleeWeaponsShopHolder")

	if not meleeWeaponsShopHolder then return end

	if currentSelectedWeapon then
		stopFloatingAnimation("detail_" .. currentSelectedWeapon)
	end

	currentSelectedWeapon = weaponId

	local dropShadowHolder = meleeWeaponsShopHolder:FindFirstChild("DropShadowHolder", true)
	local dropShadow = dropShadowHolder and dropShadowHolder:FindFirstChild("DropShadow")

	local elementsToAnimate = {
		dropShadowHolder,
		meleeWeaponsShopHolder:FindFirstChild("MeleeWeaponViewport", true),
		meleeWeaponsShopHolder:FindFirstChild("BuyButtonFrame", true),
		meleeWeaponsShopHolder.BuyButtonFrame:FindFirstChild("Price", true),
		meleeWeaponsShopHolder:FindFirstChild("DescriptionLabel", true),
		meleeWeaponsShopHolder:FindFirstChild("ItemClass", true),
		meleeWeaponsShopHolder:FindFirstChild("ItemName", true)
	}

	local templateFolder = game:GetService("StarterGui"):FindFirstChild("Templates")
	local isRare = weaponData.rarity and string.lower(weaponData.rarity) == "rare"
	local isUncommon = weaponData.rarity and string.lower(weaponData.rarity) == "uncommon"

	local itemClass = meleeWeaponsShopHolder:FindFirstChild("ItemClass", true)
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
	local itemDescriptionHolder = meleeWeaponsShopHolder:FindFirstChild("ItemDescriptionHolder")
	if itemDescriptionHolder then
		viewportFrame = itemDescriptionHolder:FindFirstChildWhichIsA("ViewportFrame", true)
	end

	if not viewportFrame then
		viewportFrame = meleeWeaponsShopHolder:FindFirstChildWhichIsA("ViewportFrame", true)
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

	local priceLabel = meleeWeaponsShopHolder:FindFirstChild("Price", true)
	if priceLabel then priceLabel.Text = "C$ " .. weaponData.price end

	for name, value in pairs(elements) do
		local element = meleeWeaponsShopHolder:FindFirstChild(name, true)
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

	meleeWeaponsShopHolder:SetAttribute("SelectedWeaponId", weaponId)
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

local function setupMeleeWeaponBuyButtonInteraction(buyButtonFrame, weaponId, template)
	if not buyButtonFrame then return end
	if weaponId == nil then return end

	local priceLabel = buyButtonFrame:FindFirstChild("Price")
	local uiStroke = buyButtonFrame:FindFirstChildOfClass("UIStroke")

	if not buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", buyButtonFrame.Position.X.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", buyButtonFrame.Position.X.Offset)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", buyButtonFrame.Position.Y.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", buyButtonFrame.Position.Y.Offset)
	end

	local originalSize = buyButtonFrame.Size

	if uiStroke then
		if not buyButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			buyButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	buyButtonFrame:SetAttribute("MeleeWeaponId", weaponId)

	if priceLabel then
		local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
		local weaponData = MeleeWeaponData[weaponId]
		if weaponData and weaponData.price then
			priceLabel.Text = "C$ " .. weaponData.price
		end
	end

	local clickDetector = buyButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = buyButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = buyButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(buyButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
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

		buyButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				buyButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		buyButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		if priceLabel and priceLabel.Text == "Owned" then
			-- If owned, you might want to equip the melee weapon here
			-- RemoteEvent:FireServer("SetActiveMeleeWeapon", weaponId)
			return
		end

		local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
		local weaponData = MeleeWeaponData[weaponId]
		if not weaponData then return end

		playSoundByName(buyButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if priceLabel then priceLabel.Text = "..." end

		RemoteEvent:FireServer("PurchaseMeleeWeapon", weaponId, weaponData.price)
	end)

	local trueOriginalPosition = UDim2.new(
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or buyButtonFrame.Position.X.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or buyButtonFrame.Position.X.Offset,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or buyButtonFrame.Position.Y.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or buyButtonFrame.Position.Y.Offset
	)

	buyButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	buyButtonFrame.Visible = false
	setElementTransparency(buyButtonFrame, true)

	RemoteEvent:FireServer("CheckMeleeWeaponOwnership", weaponId)
end

local function populateMeleeWeaponsShop(meleeWeaponsShopHolder)
	local meleeWeaponsHolder = meleeWeaponsShopHolder:FindFirstChild("MeleeWeaponsHolder")
	if not meleeWeaponsHolder then return end

	local scrollFrameHolder = meleeWeaponsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	local standardTemplate = templateFolder:FindFirstChild("WeaponTemplate")
	local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")
	local uncommonTemplate = templateFolder:FindFirstChild("UncommonWeaponTemplate")

	if not standardTemplate then return end
	if not rareTemplate then rareTemplate = standardTemplate end
	if not uncommonTemplate then uncommonTemplate = standardTemplate end

	for _, child in pairs(scrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") then child:Destroy() end
	end

	local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
	if not MeleeWeaponData then
		print("Error: MeleeWeaponData not found!")
		return
	end

	for weaponId, data in pairs(MeleeWeaponData) do
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
		newWeapon:SetAttribute("Price", data.price)
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

		setupMeleeWeaponTemplateEffects(newWeapon, weaponId)  -- Use our new function here
		newWeapon.Parent = scrollingFrame
	end

	local grid = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	if grid then
		task.delay(0.2, function()
			local absoluteContentSize = grid.AbsoluteContentSize
			local canvasHeight = math.max(absoluteContentSize.Y + grid.CellPadding.Y.Offset, scrollingFrame.AbsoluteSize.Y * 2)
			scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
		end)
	end

	-- Display first melee weapon
	local firstWeaponId, firstWeaponData = next(MeleeWeaponData)
	if firstWeaponId then
		updateMainMeleeWeaponViewport(firstWeaponId, firstWeaponData)
		local buyButtonFrame = meleeWeaponsShopHolder:FindFirstChild("BuyButtonFrame")
		if buyButtonFrame and firstWeaponId then
			setupMeleeWeaponBuyButtonInteraction(buyButtonFrame, firstWeaponId, nil)  -- We'll need this function too
		end
	end
end

local function populateWeaponsShop(weaponsShopHolder)
	local weaponsHolder = weaponsShopHolder:FindFirstChild("WeaponsHolder")
	if not weaponsHolder then return end

	local scrollFrameHolder = weaponsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	local standardTemplate = templateFolder:FindFirstChild("WeaponTemplate")
	local rareTemplate = templateFolder:FindFirstChild("RareWeaponTemplate")

	if not standardTemplate then return end
	if not rareTemplate then rareTemplate = standardTemplate end

	for _, child in pairs(scrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") then child:Destroy() end
	end

	for weaponId, data in pairs(WeaponData) do
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
		newWeapon:SetAttribute("Price", data.price)
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

		setupWeaponTemplateEffects(newWeapon, weaponId)
		newWeapon.Parent = scrollingFrame
	end

	local grid = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	if grid then
		task.delay(0.2, function()
			local absoluteContentSize = grid.AbsoluteContentSize
			local canvasHeight = math.max(absoluteContentSize.Y + grid.CellPadding.Y.Offset, scrollingFrame.AbsoluteSize.Y * 2)
			scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
		end)
	end

	local firstWeaponId, firstWeaponData = next(WeaponData)
	if firstWeaponId then
		updateMainWeaponViewport(firstWeaponId, firstWeaponData)
		local buyButtonFrame = weaponsShopHolder:FindFirstChild("BuyButtonFrame")
		if buyButtonFrame and firstWeaponId then
			setupWeaponBuyButtonInteraction(buyButtonFrame, firstWeaponId, nil)
		end
	end
end

local function populateDeathSoundsShop(deathSoundsShopHolder)
	local deathSoundsHolder = deathSoundsShopHolder:FindFirstChild("DeathSoundsHolder")
	if not deathSoundsHolder then return end

	local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
	if not scrollFrameHolder then return end

	local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
	if not soundScrollingFrame then return end

	local templateFolder = game:GetService("StarterGui").Templates.ShopTemplates
	if not templateFolder then return end

	local soundTemplate = templateFolder:FindFirstChild("DeathSoundTemplate")
	if not soundTemplate then return end

	for _, child in pairs(soundScrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	for soundId, data in pairs(DeathSoundData) do
		local newSound = soundTemplate:Clone()
		newSound.Name = "DeathSoundTemplate_" .. soundId
		newSound.Visible = true

		newSound:SetAttribute("SoundId", soundId)
		newSound:SetAttribute("DisplayName", data.displayName)
		newSound:SetAttribute("Price", data.price)
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

		local buyButtonFrame = newSound:FindFirstChild("BuyButtonFrame")
		if buyButtonFrame then
			buyButtonFrame.Visible = false
			setElementTransparency(buyButtonFrame, true)
		end

		setupDeathSoundTemplateEffects(newSound, soundId)
		newSound.Parent = soundScrollingFrame
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

	currentVisibleBuyButton = nil
end

local function cleanupShopAnimations()
	for id, floatData in pairs(floatingAnimations) do
		if floatData.tween then floatData.tween:Cancel() end
		if floatData.offsetValue then floatData.offsetValue:Destroy() end
	end

	table.clear(floatingAnimations)
	table.clear(viewportTweens)

	currentSelectedWeapon = nil
end

local function previewTauntSound(tauntId, template)
	if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
		currentTauntSoundInstance:Stop()
	end

	local soundData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
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
	local shopScreenFrame = client:FindFirstChild("ShopScreenFrame")
	local shopScreen = shopScreenFrame:FindFirstChild("ShopScreen")
	local tauntsShopHolder = shopScreen:FindFirstChild("TauntsShopHolder")

	if not tauntsShopHolder then return end

	local tauntsHolder = tauntsShopHolder:FindFirstChild("TauntsHolder")
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

	tauntsShopHolder:SetAttribute("SelectedTauntId", tauntId)

	if visualizerFrame then enhanceExistingVisualizer(visualizerFrame) end

	RemoteEvent:FireServer("CheckTauntOwnership", tauntId)
	-- REMOVED: previewTauntSound(tauntId, nil)
end

local function setupTauntBuyButtonInteraction(buyButtonFrame, tauntId, template)
	if not buyButtonFrame then return end
	if tauntId == nil then return end

	local priceLabel = buyButtonFrame:FindFirstChild("Price")
	local uiStroke = buyButtonFrame:FindFirstChildOfClass("UIStroke")

	if not buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") then
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Scale", buyButtonFrame.Position.X.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_X_Offset", buyButtonFrame.Position.X.Offset)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Scale", buyButtonFrame.Position.Y.Scale)
		buyButtonFrame:SetAttribute("TrueOriginalPosition_Y_Offset", buyButtonFrame.Position.Y.Offset)
	end

	local originalSize = buyButtonFrame.Size

	if uiStroke then
		if not buyButtonFrame:GetAttribute("OriginalStrokeColor_R") then
			buyButtonFrame:SetAttribute("OriginalStrokeColor_R", uiStroke.Color.R)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_G", uiStroke.Color.G)
			buyButtonFrame:SetAttribute("OriginalStrokeColor_B", uiStroke.Color.B)
		end
	end

	buyButtonFrame:SetAttribute("TauntId", tauntId)

	if priceLabel then
		local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
		if tauntData and tauntData.price then
			priceLabel.Text = "C$ " .. tauntData.price
		end
	end

	local clickDetector = buyButtonFrame:FindFirstChild("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("TextButton")
		clickDetector.Name = "ClickDetector"
		clickDetector.BackgroundTransparency = 1
		clickDetector.Text = ""
		clickDetector.Size = UDim2.new(1, 0, 1, 0)
		clickDetector.Position = UDim2.new(0, 0, 0, 0)
		clickDetector.ZIndex = buyButtonFrame.ZIndex + 1
		clickDetector.AutoButtonColor = false
		clickDetector.Parent = buyButtonFrame
	end

	clickDetector.MouseEnter:Connect(function()
		playSoundByName(buyButtonFrame, "Hover")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
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

		buyButtonFrame:SetAttribute("IsHovered", true)
	end)

	clickDetector.MouseLeave:Connect(function()
		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
			Size = originalSize
		})

		if uiStroke then
			local originalColor = Color3.new(
				buyButtonFrame:GetAttribute("OriginalStrokeColor_R") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_G") or 0,
				buyButtonFrame:GetAttribute("OriginalStrokeColor_B") or 0
			)

			TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
				Color = originalColor
			})
		end

		buyButtonFrame:SetAttribute("IsHovered", false)
	end)

	clickDetector.MouseButton1Click:Connect(function()
		if priceLabel and priceLabel.Text == "Owned" then
			RemoteEvent:FireServer("SetActiveTaunt", tauntId)
			return
		end

		local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
		if not tauntData then return end

		playSoundByName(buyButtonFrame, "ButtonClick")

		TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.ReturnQuadData(0.1), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.95, 
				originalSize.X.Offset * 0.95,
				originalSize.Y.Scale * 0.95, 
				originalSize.Y.Offset * 0.95
			)
		})

		task.delay(0.1, function()
			TweenMethods.CreateTweenAsync(buyButtonFrame, TweenMethods.PointOneSecondSineData, {
				Size = originalSize
			})
		end)

		if priceLabel then priceLabel.Text = "..." end

		RemoteEvent:FireServer("PurchaseTaunt", tauntId, tauntData.price)
	end)

	local trueOriginalPosition = UDim2.new(
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Scale") or buyButtonFrame.Position.X.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_X_Offset") or buyButtonFrame.Position.X.Offset,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Scale") or buyButtonFrame.Position.Y.Scale,
		buyButtonFrame:GetAttribute("TrueOriginalPosition_Y_Offset") or buyButtonFrame.Position.Y.Offset
	)

	buyButtonFrame.Position = trueOriginalPosition + UDim2.new(0, 0, 0.2, 0)
	buyButtonFrame.Visible = false
	setElementTransparency(buyButtonFrame, true)

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

	local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
	if buyButtonFrame then
		setupTauntBuyButtonInteraction(buyButtonFrame, tauntId, template)
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

		local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")

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

			if currentVisibleTauntBuyButton then
				animateBuyButton(currentVisibleTauntBuyButton, false)
			end
		end

		currentSelectedTauntTemplate = template

		if buyButtonFrame then
			buyButtonFrame:SetAttribute("StayVisible", true)
			animateBuyButton(buyButtonFrame, true)
			currentVisibleTauntBuyButton = buyButtonFrame

			task.delay(0.5, function()
				buyButtonFrame:SetAttribute("StayVisible", false)
			end)
		end

		TweenMethods.CreateTweenAsync(uiStroke, TweenMethods.PointOneSecondSineData, {
			Thickness = originalStrokeThickness[template] + 2,
			Color = Color3.new(1, 1, 1),
			Transparency = 0
		})

		previewTauntSound(tauntId, template)

		local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
		if tauntData then updateMainTauntView(tauntId, tauntData) end
	end)
end

local function populateTauntsShop(tauntsShopHolder)
	local tauntsHolder = tauntsShopHolder:FindFirstChild("TauntsHolder")
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

	local tauntTemplate = templateFolder:FindFirstChild("TauntTemplate")
	if not tauntTemplate then 
		print("Taunts: TauntTemplate not found!")
		return 
	end

	-- Clear existing templates
	for _, child in pairs(tauntsScrollingFrame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local TauntSoundData = require(ReplicatedStorage.Data.TauntSoundData)

	-- Create a counter for debug purposes
	local tauntCount = 0

	for tauntId, data in pairs(TauntSoundData) do
		local newTaunt = tauntTemplate:Clone()
		newTaunt.Name = "TauntTemplate_" .. tauntId
		newTaunt.Visible = true

		newTaunt:SetAttribute("TauntId", tauntId)
		newTaunt:SetAttribute("DisplayName", data.displayName)
		newTaunt:SetAttribute("Price", data.price)
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

		local buyButtonFrame = newTaunt:FindFirstChild("BuyButtonFrame")
		if buyButtonFrame then
			buyButtonFrame.Visible = false
			setElementTransparency(buyButtonFrame, true)
		end

		setupTauntTemplateEffects(newTaunt, tauntId)
		newTaunt.Parent = tauntsScrollingFrame
		tauntCount = tauntCount + 1
	end

	print("Populated taunt shop with", tauntCount, "taunts")

	local layout = tauntsScrollingFrame:FindFirstChildOfClass("UIGridLayout") or tauntsScrollingFrame:FindFirstChildOfClass("UIListLayout")

	if layout then
		task.delay(0.2, function()
			local absoluteContentSize = layout.AbsoluteContentSize
			local canvasHeight = math.max(absoluteContentSize.Y + (layout.CellPadding and layout.CellPadding.Y.Offset or 0), 
				tauntsScrollingFrame.AbsoluteSize.Y * 2)
			tauntsScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
		end)
	else
		print("Taunts: No layout found in tauntsScrollingFrame")
	end

	currentVisibleTauntBuyButton = nil

	-- Display first taunt if available
	local firstTauntId, firstTauntData = next(TauntSoundData)
	if firstTauntId then
		print("Setting first taunt:", firstTauntId)
		updateMainTauntView(firstTauntId, firstTauntData)
	else
		print("No taunts found in TauntSoundData")
	end
end

local function resetAllTauntTemplates()
	currentSelectedTauntTemplate = nil

	if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
		currentTauntSoundInstance:Stop()
		currentTauntSoundInstance = nil
	end

	if currentVisibleTauntBuyButton and currentVisibleTauntBuyButton.Parent then
		animateBuyButton(currentVisibleTauntBuyButton, false)
	end
	currentVisibleTauntBuyButton = nil

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

			local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
			if buyButtonFrame then
				buyButtonFrame.Visible = false
				setElementTransparency(buyButtonFrame, true)
			end
		end
	end
end

local function transitionPanels(fromPanel, toPanel)
	local fromPanelName = "options"
	local toPanelName = "options"

	if fromPanel.Name == "WeaponsShopHolder" then 
		fromPanelName = "weapons"
	elseif fromPanel.Name == "DeathSoundsShopHolder" then
		fromPanelName = "deathsounds"
	elseif fromPanel.Name == "TauntsShopHolder" then
		fromPanelName = "taunts"
	elseif fromPanel.Name == "MeleeWeaponsShopHolder" then
		fromPanelName = "meleeweapons"
	end

	if toPanel.Name == "WeaponsShopHolder" then
		toPanelName = "weapons"
	elseif toPanel.Name == "DeathSoundsShopHolder" then
		toPanelName = "deathsounds"
	elseif toPanel.Name == "TauntsShopHolder" then
		toPanelName = "taunts"
	elseif toPanel.Name == "MeleeWeaponsShopHolder" then
		toPanelName = "meleeweapons"
	end

	if fromPanel.Name == "WeaponsShopHolder" then
		resetAllWeaponTemplates()
		cleanupShopAnimations()
	elseif fromPanel.Name == "DeathSoundsShopHolder" then
		resetAllDeathSoundTemplates()

		if currentSoundInstance and currentSoundInstance.IsPlaying then
			currentSoundInstance:Stop()
			currentSoundInstance = nil
		end
	elseif fromPanel.Name == "TauntsShopHolder" then
		resetAllTauntTemplates()

		if currentTauntSoundInstance and currentTauntSoundInstance.IsPlaying then
			currentTauntSoundInstance:Stop()
			currentTauntSoundInstance = nil
		end
	elseif fromPanel.Name == "MeleeWeaponsShopHolder" then
		resetAllWeaponTemplates()
		cleanupShopAnimations()
	end

	playSoundByName(fromPanel, "ShopOpen")

	local shopScreen = fromPanel.Parent
	while shopScreen and shopScreen.Name ~= "ShopScreen" do
		shopScreen = shopScreen.Parent
	end

	local shopNameHolder = shopScreen and shopScreen:FindFirstChild("ShopNameHolder")

	if fromPanel.Name == "OptionsHolder" and (toPanel.Name == "WeaponsShopHolder" or toPanel.Name == "DeathSoundsShopHolder" or toPanel.Name == "TauntsShopHolder" or toPanel.Name == "MeleeWeaponsShopHolder") then
		local shopHolder = fromPanel.Parent
		if shopHolder then
			local shopScreen = shopHolder.Parent
			local mainReturnButton = shopScreen and shopScreen:FindFirstChild("ReturnButton")

			if mainReturnButton then animatePanel(mainReturnButton, "out") end

			if shopNameHolder then
				animatePanel(shopNameHolder, "out", function()
					updateShopHeader(shopScreen, toPanelName, false)
				end)
			end

			animatePanel(shopHolder, "out", function()
				animatePanel(toPanel, "in")

				if shopNameHolder then animatePanel(shopNameHolder, "in") end

				shopState.currentPanel = toPanelName

				if toPanel.Name == "WeaponsShopHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateWeaponsShop(toPanel)
					end)
				elseif toPanel.Name == "DeathSoundsShopHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateDeathSoundsShop(toPanel)
					end)
				elseif toPanel.Name == "TauntsShopHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateTauntsShop(toPanel)
					end)
				elseif toPanel.Name == "MeleeWeaponsShopHolder" then
					task.spawn(function()
						task.wait(0.1)
						populateMeleeWeaponsShop(toPanel)
					end)
				end
			end)
		end
	elseif (fromPanel.Name == "WeaponsShopHolder" or fromPanel.Name == "DeathSoundsShopHolder" or fromPanel.Name == "TauntsShopHolder" or fromPanel.Name == "MeleeWeaponsShopHolder") and toPanel.Name == "OptionsHolder" then
		local shopHolder = toPanel.Parent
		if shopHolder then
			if shopNameHolder then
				animatePanel(shopNameHolder, "out", function()
					updateShopHeader(shopScreen, "main", false)
				end)
			end

			animatePanel(fromPanel, "out", function()
				animatePanel(shopHolder, "in")

				if shopNameHolder then animatePanel(shopNameHolder, "in") end

				local shopScreen = shopHolder.Parent
				local mainReturnButton = shopScreen and shopScreen:FindFirstChild("ReturnButton")

				if mainReturnButton then animatePanel(mainReturnButton, "in") end

				shopState.currentPanel = "options"
			end)
		end
	else
		if shopNameHolder then
			animatePanel(shopNameHolder, "out", function()
				updateShopHeader(shopScreen, toPanelName, false)
			end)
		end

		animatePanel(fromPanel, "out", function()
			animatePanel(toPanel, "in")

			if shopNameHolder then animatePanel(shopNameHolder, "in") end

			if toPanel.Name == "OptionsHolder" then
				shopState.currentPanel = "options"
			elseif toPanel.Name == "WeaponsShopHolder" then
				shopState.currentPanel = "weapons"

				task.spawn(function()
					task.wait(0.1)
					populateWeaponsShop(toPanel)
				end)
			elseif toPanel.Name == "DeathSoundsShopHolder" then
				shopState.currentPanel = "deathsounds"

				task.spawn(function()
					task.wait(0.1)
					populateDeathSoundsShop(toPanel)
				end)
			elseif toPanel.Name == "TauntsShopHolder" then
				shopState.currentPanel = "taunts"

				task.spawn(function()
					task.wait(0.1)
					populateTauntsShop(toPanel)
				end)
			elseif toPanel.Name == "MeleeWeaponsShopHolder" then
				shopState.currentPanel = "meleeweapons"

				task.spawn(function()
					task.wait(0.1)
					populateMeleeWeaponsShop(toPanel)
				end)
			end
		end)
	end
end

local function openShopScreen(shopScreen)
	cacheShopHeaderValues(shopScreen)

	shopState.isOpen = true
	shopState.currentPanel = "options"

	playSoundByName(shopScreen, "ShopOpen")
	toggleCameraEffects(true)

	local elementsToAnimate = {
		shopScreen:FindFirstChild("ReturnButton"),
		shopScreen:FindFirstChild("ShopNameHolder"),
		shopScreen:FindFirstChild("ShopHolder")
	}

	shopScreen.Visible = true

	-- Debug which elements are being animated
	for _, element in ipairs(elementsToAnimate) do
		if element then
			print("Animating:", element.Name)
			element.Visible = true
			-- Ensure we have original positions stored
			if not trueOriginalPositions[element] then
				trueOriginalPositions[element] = element.Position
			end
			animatePanel(element, "in")
		else
			print("Element not found in elementsToAnimate")
		end
	end

	local weaponsShopHolder = shopScreen:FindFirstChild("WeaponsShopHolder")
	if weaponsShopHolder then weaponsShopHolder.Visible = false end

	local deathSoundsShopHolder = shopScreen:FindFirstChild("DeathSoundsShopHolder") 
	if deathSoundsShopHolder then deathSoundsShopHolder.Visible = false end

	local tauntsShopHolder = shopScreen:FindFirstChild("TauntsShopHolder")
	if tauntsShopHolder then tauntsShopHolder.Visible = false end

	local meleeWeaponsShopHolder = shopScreen:FindFirstChild("MeleeWeaponsShopHolder")
	if meleeWeaponsShopHolder then meleeWeaponsShopHolder.Visible = false end
end

local function closeShopScreen(shopScreen)
	resetAllWeaponTemplates()
	cleanupShopAnimations()

	shopState.isOpen = false
	shopState.currentPanel = nil

	playSoundByName(shopScreen, "ShopClose")
	toggleCameraEffects(false)

	local elementsToAnimate = {
		shopScreen:FindFirstChild("ReturnButton"),
		shopScreen:FindFirstChild("ShopNameHolder"),
		shopScreen:FindFirstChild("ShopHolder")
	}

	local weaponsShopHolder = shopScreen:FindFirstChild("WeaponsShopHolder")
	if weaponsShopHolder and weaponsShopHolder.Visible then
		table.insert(elementsToAnimate, weaponsShopHolder)
	end

	local deathSoundsShopHolder = shopScreen:FindFirstChild("DeathSoundsShopHolder")
	if deathSoundsShopHolder and deathSoundsShopHolder.Visible then
		table.insert(elementsToAnimate, deathSoundsShopHolder)
	end

	local tauntsShopHolder = shopScreen:FindFirstChild("TauntsShopHolder")
	if tauntsShopHolder and tauntsShopHolder.Visible then
		table.insert(elementsToAnimate, tauntsShopHolder)
	end

	local meleeWeaponsShopHolder = shopScreen:FindFirstChild("MeleeWeaponsShopHolder")
	if meleeWeaponsShopHolder and meleeWeaponsShopHolder.Visible then
		table.insert(elementsToAnimate, meleeWeaponsShopHolder)
	end

	for _, element in ipairs(elementsToAnimate) do
		if element then animatePanel(element, "out") end
	end

	task.delay(0.2, function() shopScreen.Visible = false end)
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

local function setupFrames(shopHolder)
	originalProperties = {}
	shopHolder.Visible = true

	local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
	if not optionsHolder then return end

	local shopFrames = {}

	-- Instead of explicitly listing frames, get all frames that could be shop options
	for _, frame in ipairs(optionsHolder:GetChildren()) do
		if frame:IsA("Frame") and 
			(frame.Name:find("Frame") or frame.Name:find("frame")) and
			not frame:FindFirstChild("UIListLayout") and
			not frame:FindFirstChild("UIGridLayout") then
			table.insert(shopFrames, frame)
		end
	end

	-- Apply effects to all found frames
	for _, frame in ipairs(shopFrames) do
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
-- Complete setupUI function (corrected)
local function setupUI()
	local player = Players.LocalPlayer
	if not player then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local client = playerGui:FindFirstChild("Client")
	if not client then return end

	local shopScreenFrame = client:FindFirstChild("ShopScreenFrame")
	if not shopScreenFrame then return end

	local shopScreen = shopScreenFrame:FindFirstChild("ShopScreen")
	if not shopScreen then return end

	UICache.shopScreen = shopScreen
	UICache.shopScreenFrame = shopScreenFrame

	local shopButton = shopScreenFrame:FindFirstChild("ShopButton") or shopScreenFrame:FindFirstChild("ShopButton", true)
	if shopButton then
		setupButton(shopButton, Color3.new(
			math.min(shopButton.ImageColor3.R * 1.2, 1),
			math.min(shopButton.ImageColor3.G * 1.2, 1),
			math.min(shopButton.ImageColor3.B * 1.2, 1)
			), function()
				if not shopState.isOpen then
					openShopScreen(shopScreen)
				else
					closeShopScreen(shopScreen)
				end
			end)
	end

	setupButton(shopScreen:FindFirstChild("ReturnButton"), Color3.fromRGB(255, 0, 0), function()
		playSoundByName(shopScreen, "ShopClose")
		closeShopScreen(shopScreen)
	end)

	local weaponsShopHolder = shopScreen:FindFirstChild("WeaponsShopHolder")
	if weaponsShopHolder then
		local returnButton = weaponsShopHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local shopHolder = shopScreen:FindFirstChild("ShopHolder")
				if shopHolder then
					local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(weaponsShopHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local deathSoundsShopHolder = shopScreen:FindFirstChild("DeathSoundsShopHolder")
	if deathSoundsShopHolder then
		local returnButton = deathSoundsShopHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local shopHolder = shopScreen:FindFirstChild("ShopHolder")
				if shopHolder then
					local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(deathSoundsShopHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local tauntsShopHolder = shopScreen:FindFirstChild("TauntsShopHolder")
	if tauntsShopHolder then
		local returnButton = tauntsShopHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				print("Taunt return button clicked")
				playSoundByName(returnButton, "ShopClose")

				local shopHolder = shopScreen:FindFirstChild("ShopHolder")
				if shopHolder then
					local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(tauntsShopHolder, optionsHolder)
					end
				end
			end)
		else
			-- Try to create a return button if it doesn't exist
			local existingButton = deathSoundsShopHolder and deathSoundsShopHolder:FindFirstChild("ReturnButton")
			if existingButton then
				local newReturnButton = existingButton:Clone()
				newReturnButton.Parent = tauntsShopHolder
				setupButton(newReturnButton, Color3.fromRGB(255, 0, 0), function()
					playSoundByName(newReturnButton, "ShopClose")
					local shopHolder = shopScreen:FindFirstChild("ShopHolder")
					if shopHolder then
						local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
						if optionsHolder then
							transitionPanels(tauntsShopHolder, optionsHolder)
						end
					end
				end)
				print("Created missing return button for taunts shop")
			end
		end
	end

	-- Add setup for MeleeWeaponsShopHolder
	local meleeWeaponsShopHolder = shopScreen:FindFirstChild("MeleeWeaponsShopHolder")
	if meleeWeaponsShopHolder then
		local returnButton = meleeWeaponsShopHolder:FindFirstChild("ReturnButton")
		if returnButton then
			setupButton(returnButton, Color3.fromRGB(255, 0, 0), function()
				playSoundByName(returnButton, "ShopClose")

				local shopHolder = shopScreen:FindFirstChild("ShopHolder")
				if shopHolder then
					local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
					if optionsHolder then
						transitionPanels(meleeWeaponsShopHolder, optionsHolder)
					end
				end
			end)
		end
	end

	local shopHolder = shopScreen:FindFirstChild("ShopHolder")
	if shopHolder then
		local optionsHolder = shopHolder:FindFirstChild("OptionsHolder")
		if optionsHolder then
			local weaponsFrame = optionsHolder:FindFirstChild("WeaponsFrame")
			if weaponsFrame and weaponsShopHolder then
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
					transitionPanels(optionsHolder, weaponsShopHolder)
				end)
			end

			local deathSoundsFrame = optionsHolder:FindFirstChild("DeathSoundsFrame")
			if deathSoundsFrame and deathSoundsShopHolder then
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
					transitionPanels(optionsHolder, deathSoundsShopHolder)
				end)
			end

			local tauntsFrame = optionsHolder:FindFirstChild("TauntsFrame") or optionsHolder:FindFirstChild("TauntFrame")
			if tauntsFrame and tauntsShopHolder then
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
					print("Taunts frame clicked in options")
					playSoundByName(tauntsFrame, "ButtonClick")
					transitionPanels(optionsHolder, tauntsShopHolder)
				end)
			end else
			print("WARNING: TauntsFrame not found in options or TauntsShopHolder not found")
		end

		-- Setup for MeleeWeapons frame in options panel
		local meleeWeaponsFrame = optionsHolder:FindFirstChild("MeleeWeaponsFrame")
		if meleeWeaponsFrame and meleeWeaponsShopHolder then
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
				transitionPanels(optionsHolder, meleeWeaponsShopHolder)
			end)
		end

		-- Setup for Money frame in options panel
		local moneyFrame = optionsHolder:FindFirstChild("MoneyFrame")
		if moneyFrame then
			local clickDetector = Instance.new("TextButton")
			clickDetector.Name = "ClickDetector"
			clickDetector.BackgroundTransparency = 1
			clickDetector.Text = ""
			clickDetector.Size = UDim2.new(1, 0, 1, 0)
			clickDetector.Position = UDim2.new(0, 0, 0, 0)
			clickDetector.ZIndex = moneyFrame.ZIndex + 1
			clickDetector.AutoButtonColor = false
			clickDetector.Parent = moneyFrame

			clickDetector.MouseButton1Click:Connect(function()
				playSoundByName(moneyFrame, "ButtonClick")
				-- When MoneyShopHolder is created:
				-- transitionPanels(optionsHolder, moneyShopHolder)
				print("Money frame clicked - ready for MoneyShopHolder implementation")
			end)
		end

		-- Setup for Passes frame in options panel
		local passesFrame = optionsHolder:FindFirstChild("PassesFrame")
		if passesFrame then
			local clickDetector = Instance.new("TextButton")
			clickDetector.Name = "ClickDetector"
			clickDetector.BackgroundTransparency = 1
			clickDetector.Text = ""
			clickDetector.Size = UDim2.new(1, 0, 1, 0)
			clickDetector.Position = UDim2.new(0, 0, 0, 0)
			clickDetector.ZIndex = passesFrame.ZIndex + 1
			clickDetector.AutoButtonColor = false
			clickDetector.Parent = passesFrame

			clickDetector.MouseButton1Click:Connect(function()
				playSoundByName(passesFrame, "ButtonClick")
				-- When PassesShopHolder is created:
				-- transitionPanels(optionsHolder, passesShopHolder)
				print("Passes frame clicked - ready for PassesShopHolder implementation")
			end)
		end

		setupFrames(shopHolder)
	end

	shopScreen.Visible = false
	shopState.isOpen = false
	shopState.currentPanel = nil

	if weaponsShopHolder and weaponsShopHolder.Visible then
	populateWeaponsShop(weaponsShopHolder)
end

if deathSoundsShopHolder and deathSoundsShopHolder.Visible then
	populateDeathSoundsShop(deathSoundsShopHolder)
end

if tauntsShopHolder and tauntsShopHolder.Visible then
	populateTauntsShop(tauntsShopHolder)
end

if meleeWeaponsShopHolder and meleeWeaponsShopHolder.Visible then
	populateMeleeWeaponsShop(meleeWeaponsShopHolder)
end
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
			if child.Name == "ShopScreenFrame" then
				task.wait(2) -- Increased from 0.1
				setupUI()
			end
		end)
	end
end


task.spawn(function()
	task.wait(2) -- Delay initialization in a separate thread
	init()
end)

RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "PurchaseResponse" then
		local success, message, itemId = ...
		print(message)
		print(itemId)
		if not itemId then return end

		local ShopScreen = Players.LocalPlayer.PlayerGui.Client.ShopScreenFrame.ShopScreen

		-- Check for specific item types by prefix
		if string.find(itemId, "DeathSound_") then
			if success then
				playSoundByName(ShopScreen, "Purchase")

				local deathSoundsShopHolder = ShopScreen:FindFirstChild("DeathSoundsShopHolder")
				if deathSoundsShopHolder then
					local deathSoundsHolder = deathSoundsShopHolder:FindFirstChild("DeathSoundsHolder")
					if deathSoundsHolder then
						local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
						if scrollFrameHolder then
							local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
							if soundScrollingFrame and itemId then
								local template = soundScrollingFrame:FindFirstChild("DeathSoundTemplate_" .. itemId)
								if template then
									local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
									if buyButtonFrame then
										local priceLabel = buyButtonFrame:FindFirstChild("Price")
										if priceLabel then
											priceLabel.Text = "Owned"
											if priceLabel:IsA("TextLabel") then
												priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
											end
										end
									end
								end
							end
						end
					end
				end
			else
				playSoundByName(ShopScreen, "PurchaseDenied")
			end
		elseif string.find(itemId, "TauntSound_") then
			if success then
				playSoundByName(ShopScreen, "Purchase")

				local tauntsShopHolder = ShopScreen:FindFirstChild("TauntsShopHolder")
				if tauntsShopHolder then
					local tauntsHolder = tauntsShopHolder:FindFirstChild("TauntsHolder")
					if tauntsHolder then
						local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
						if tauntsFrameHolder then
							local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
							if tauntsScrollingFrame and itemId then
								local template = tauntsScrollingFrame:FindFirstChild("TauntTemplate_" .. itemId)
								if template then
									local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
									if buyButtonFrame then
										local priceLabel = buyButtonFrame:FindFirstChild("Price")
										if priceLabel then
											priceLabel.Text = "Owned"
											if priceLabel:IsA("TextLabel") then
												priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
											end
										end
									end
								end
							end
						end
					end
				end
			else
				playSoundByName(ShopScreen, "PurchaseDenied")
			end
		elseif string.find(itemId, "MeleeWeapon_") then
			if success then
				playSoundByName(ShopScreen, "Purchase")

				local meleeWeaponsShopHolder = ShopScreen:FindFirstChild("MeleeWeaponsShopHolder")
				if meleeWeaponsShopHolder then
					local buyButtonFrame = meleeWeaponsShopHolder:FindFirstChild("BuyButtonFrame")
					if buyButtonFrame then
						local priceLabel = buyButtonFrame:FindFirstChild("Price")
						if priceLabel then
							priceLabel.Text = "Owned"
							if priceLabel:IsA("TextLabel") then
								priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
							end
						end
					end

					-- Also update the template in the scrolling frame
					local meleeWeaponsHolder = meleeWeaponsShopHolder:FindFirstChild("MeleeWeaponsHolder")
					if meleeWeaponsHolder then
						local scrollFrameHolder = meleeWeaponsHolder:FindFirstChild("ScrollFrameHolder")
						if scrollFrameHolder then
							local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
							if scrollingFrame then
								local template = scrollingFrame:FindFirstChild("MeleeWeaponTemplate_" .. itemId)
								if template then
									local templateBuyButton = template:FindFirstChild("BuyButtonFrame")
									if templateBuyButton then
										local templatePriceLabel = templateBuyButton:FindFirstChild("Price")
										if templatePriceLabel then
											templatePriceLabel.Text = "Owned"
											if templatePriceLabel:IsA("TextLabel") then
												templatePriceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
											end
										end
									end
								end
							end
						end
					end
				end
			else
				playSoundByName(ShopScreen, "PurchaseDenied")
			end
		else
			-- For standard weapons, check if it exists in WeaponData
			local WeaponData = require(ReplicatedStorage.Data.WeaponData)
			if WeaponData[itemId] then
				if success then
					playSoundByName(ShopScreen,"Purchase")

					local weaponsShopHolder = ShopScreen:FindFirstChild("WeaponsShopHolder")
					if weaponsShopHolder then
						-- Update main buy button
						local buyButtonFrame = weaponsShopHolder:FindFirstChild("BuyButtonFrame")
						if buyButtonFrame then
							local priceLabel = buyButtonFrame:FindFirstChild("Price")
							if priceLabel then
								priceLabel.Text = "Owned"
								if priceLabel:IsA("TextLabel") then
									priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
								end
							end
						end

						-- Update the template in scrolling frame if it exists
						local weaponsHolder = weaponsShopHolder:FindFirstChild("WeaponsHolder")
						if weaponsHolder then
							local scrollFrameHolder = weaponsHolder:FindFirstChild("ScrollFrameHolder")
							if scrollFrameHolder then
								local scrollingFrame = scrollFrameHolder:FindFirstChild("ScrollingFrame")
								if scrollingFrame then
									local template = scrollingFrame:FindFirstChild("WeaponTemplate_" .. itemId)
									if template then
										local templateBuyButton = template:FindFirstChild("BuyButtonFrame")
										if templateBuyButton then
											local templatePriceLabel = templateBuyButton:FindFirstChild("Price")
											if templatePriceLabel then
												templatePriceLabel.Text = "Owned"
												if templatePriceLabel:IsA("TextLabel") then
													templatePriceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
												end
											end
										end
									end
								end
							end
						end
					end
				else
					playSoundByName(ShopScreen,"PurchaseDenied")
				end
			end
		end
	elseif eventName == "WeaponOwnershipResponse" then
		local weaponId, isOwned = ...
		if not weaponId then return end

		local shopScreen = Players.LocalPlayer.PlayerGui.Client.ShopScreenFrame.ShopScreen
		local weaponsShopHolder = shopScreen:FindFirstChild("WeaponsShopHolder")

		if weaponsShopHolder and weaponsShopHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local priceLabel = weaponsShopHolder:FindFirstChild("Price", true)
			if priceLabel then
				if isOwned then
					priceLabel.Text = "Owned"
					if priceLabel:IsA("TextLabel") then
						priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					local weaponData = WeaponData[weaponId]
					if weaponData then
						priceLabel.Text = "C$ " .. weaponData.price
						if priceLabel:IsA("TextLabel") then
							priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
						end
					end
				end
			end
		end
	elseif eventName == "MeleeWeaponOwnershipResponse" then
		local weaponId, isOwned = ...
		if not weaponId then return end

		local shopScreen = Players.LocalPlayer.PlayerGui.Client.ShopScreenFrame.ShopScreen
		local meleeWeaponsShopHolder = shopScreen:FindFirstChild("MeleeWeaponsShopHolder")

		if meleeWeaponsShopHolder and meleeWeaponsShopHolder:GetAttribute("SelectedWeaponId") == weaponId then
			local priceLabel = meleeWeaponsShopHolder:FindFirstChild("Price", true)
			if priceLabel then
				if isOwned then
					priceLabel.Text = "Owned"
					if priceLabel:IsA("TextLabel") then
						priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
					end
				else
					local MeleeWeaponData = require(ReplicatedStorage.Data.MeleeWeaponData)
					local weaponData = MeleeWeaponData[weaponId]
					if weaponData then
						priceLabel.Text = "C$ " .. weaponData.price
						if priceLabel:IsA("TextLabel") then
							priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
						end
					end
				end
			end
		end
	elseif eventName == "DeathSoundOwnershipResponse" then
		local soundId, isOwned, isActive = ...
		if not soundId then return end

		local shopScreen = Players.LocalPlayer.PlayerGui.Client.ShopScreenFrame.ShopScreen
		local deathSoundsShopHolder = shopScreen:FindFirstChild("DeathSoundsShopHolder")

		if deathSoundsShopHolder then
			local deathSoundsHolder = deathSoundsShopHolder:FindFirstChild("DeathSoundsHolder")
			if deathSoundsHolder then
				local scrollFrameHolder = deathSoundsHolder:FindFirstChild("ScrollFrameHolder")
				if scrollFrameHolder then
					local soundScrollingFrame = scrollFrameHolder:FindFirstChild("SoundScrollingFrame")
					if soundScrollingFrame and soundId then
						local template = soundScrollingFrame:FindFirstChild("DeathSoundTemplate_" .. soundId)
						if template then
							local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
							if buyButtonFrame then
								local priceLabel = buyButtonFrame:FindFirstChild("Price")
								if priceLabel then
									if isOwned then
										priceLabel.Text = "Owned"
										if priceLabel:IsA("TextLabel") then
											priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
										end
									else
										local soundData = DeathSoundData[soundId]
										if soundData then
											priceLabel.Text = "C$ " .. soundData.price
											if priceLabel:IsA("TextLabel") then
												priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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
	elseif eventName == "TauntOwnershipResponse" then
		local tauntId, isOwned, isActive = ...
		if not tauntId then 
			print("TauntOwnershipResponse received with nil tauntId")
			return 
		end

		local shopScreen = Players.LocalPlayer.PlayerGui.Client.ShopScreenFrame.ShopScreen
		local tauntsShopHolder = shopScreen:FindFirstChild("TauntsShopHolder")

		if tauntsShopHolder then
			-- Check if we have a buyButtonFrame directly in the tauntsShopHolder (for the main display)
			local mainBuyButtonFrame = tauntsShopHolder:FindFirstChild("BuyButtonFrame", true)
			if mainBuyButtonFrame and tauntsShopHolder:GetAttribute("SelectedTauntId") == tauntId then
				local priceLabel = mainBuyButtonFrame:FindFirstChild("Price")
				if priceLabel then
					if isOwned then
						priceLabel.Text = "Owned"
						if priceLabel:IsA("TextLabel") then
							priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
						end
					else
						local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
						if tauntData then
							priceLabel.Text = "C$ " .. tauntData.price
							if priceLabel:IsA("TextLabel") then
								priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
							end
						end
					end
				end
			end

			-- Also update the template in the scrolling frame
			local tauntsHolder = tauntsShopHolder:FindFirstChild("TauntsHolder")
			if tauntsHolder then
				local tauntsFrameHolder = tauntsHolder:FindFirstChild("TauntsFrameHolder")
				if tauntsFrameHolder then
					local tauntsScrollingFrame = tauntsFrameHolder:FindFirstChild("TauntsScrollingFrame")
					if tauntsScrollingFrame then
						local template = tauntsScrollingFrame:FindFirstChild("TauntTemplate_" .. tauntId)
						if template then
							local buyButtonFrame = template:FindFirstChild("BuyButtonFrame")
							if buyButtonFrame then
								local priceLabel = buyButtonFrame:FindFirstChild("Price")
								if priceLabel then
									if isOwned then
										priceLabel.Text = "Owned"
										if priceLabel:IsA("TextLabel") then
											priceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
										end
									else
										local tauntData = require(ReplicatedStorage.Data.TauntSoundData)[tauntId]
										if tauntData then
											priceLabel.Text = "C$ " .. tauntData.price
											if priceLabel:IsA("TextLabel") then
												priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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
	elseif eventName == "DeathSoundActivated" then
		local soundId = ...
		if not soundId then return end
	elseif eventName == "TauntActivated" then
		local tauntId = ...
		if not tauntId then return end
		print("Taunt activated:", tauntId)
	elseif eventName == "UpdateCurrency" then
		local currency = ...
		if currency then end
	elseif eventName == "PlayerDataReady" then
		local currency = ...
		if currency then end
	end
end)