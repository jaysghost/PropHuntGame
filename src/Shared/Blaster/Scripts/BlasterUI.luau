local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local BlasterUtilities = require(ReplicatedStorage.Blaster.BlasterUtilities)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local reticleGuiTemplate = script.ReticleGui
local touchGuiTemplate = script.BlasterTouchGui
local hitmarkerSound = script.Hitmarker
local audioTarget = SoundService.Audio.Busses.UI.AudioCompressor

-- Get reference to Client and HUD based on proper hierarchy
local client = playerGui:WaitForChild("Client")
local hud = client:WaitForChild("HUD")
local templates = game:GetService("StarterGui"):WaitForChild("Templates")
local ammoFrameTemplate = templates:WaitForChild("Ammo")

local BlasterUI = {}
BlasterUI.__index = BlasterUI

-- Add restoreOriginalProperties method to the BlasterUI table
BlasterUI.restoreOriginalProperties = function(self)
	if not self.originalProperties then return end

	-- Restore frame properties
	if self.originalProperties.frame then
		self.ammoFrame.BackgroundColor3 = self.originalProperties.frame.BackgroundColor3
		self.ammoFrame.BackgroundTransparency = self.originalProperties.frame.BackgroundTransparency
		self.ammoFrame.Position = self.originalProperties.frame.Position
	end

	-- Restore ammo label properties
	if self.ammoLabel and self.originalProperties.ammoLabel then
		self.ammoLabel.TextColor3 = self.originalProperties.ammoLabel.TextColor3
		self.ammoLabel.TextTransparency = self.originalProperties.ammoLabel.TextTransparency
		self.ammoLabel.TextSize = self.originalProperties.ammoLabel.TextSize
	end

	-- Restore magazine label properties
	if self.magazineLabel and self.originalProperties.magazineLabel then
		self.magazineLabel.TextColor3 = self.originalProperties.magazineLabel.TextColor3
		self.magazineLabel.TextTransparency = self.originalProperties.magazineLabel.TextTransparency
		self.magazineLabel.TextSize = self.originalProperties.magazineLabel.TextSize
	end

	-- Restore divider properties
	if self.divider and self.originalProperties.divider then
		self.divider.BackgroundColor3 = self.originalProperties.divider.BackgroundColor3
		self.divider.BackgroundTransparency = self.originalProperties.divider.BackgroundTransparency
	end

	-- Restore all descendant properties
	if self.originalProperties.descendants then
		for element, properties in pairs(self.originalProperties.descendants) do
			if element and element:IsDescendantOf(self.ammoFrame) then
				for property, value in pairs(properties) do
					element[property] = value
				end
			end
		end
	end
end

function BlasterUI.new(blaster)
	local magazineSize = blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)

	-- Clone the ammo frame from templates and add it to HUD
	local ammoFrame = ammoFrameTemplate:Clone()
	ammoFrame.Visible = false -- Start hidden
	ammoFrame.Parent = hud

	local reticleGui = reticleGuiTemplate:Clone()
	reticleGui.Enabled = false
	reticleGui.Parent = playerGui

	local touchGui = touchGuiTemplate:Clone()
	touchGui.Enabled = false
	touchGui.Parent = playerGui

	local scaleTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local transparencyTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local hitmarkerScaleTween = TweenService:Create(reticleGui.Hitmarker.UIScale, scaleTweenInfo, { Scale = 1 })
	local hitmarkerTransparencyTween = TweenService:Create(reticleGui.Hitmarker, transparencyTweenInfo, { GroupTransparency = 1 })

	local self = {
		blaster = blaster,
		ammoFrame = ammoFrame,
		ammoLabel = ammoFrame:FindFirstChild("AmmoLabel"),
		magazineLabel = ammoFrame:FindFirstChild("MagazineLabel"),
		divider = ammoFrame:FindFirstChild("Divider"),
		magazineSize = magazineSize,
		reticleGui = reticleGui,
		touchGui = touchGui,
		hitmarkerScaleTween = hitmarkerScaleTween,
		hitmarkerTransparencyTween = hitmarkerTransparencyTween,
		enabled = false,
		touchEnabled = false,
		ammo = 0,
		reloading = false,
		shootInputObject = nil,
		reloadCallback = nil,
		connections = {},
		originalProperties = {}, -- Will store original properties of UI elements
	}
	setmetatable(self, BlasterUI)
	self:initialize()
	return self
end

function BlasterUI:initialize()
	-- Set initial magazine size text
	if self.magazineLabel then
		self.magazineLabel.Text = tostring(self.magazineSize)
	end

	-- Initialize the originalProperties table if it doesn't exist
	self.originalProperties = self.originalProperties or {}
	self.originalProperties.frame = {}
	self.originalProperties.ammoLabel = {}
	self.originalProperties.magazineLabel = {}
	self.originalProperties.divider = {}
	self.originalProperties.descendants = {}

	-- Cache all original properties for restoration
	self:cacheOriginalProperties()

	table.insert(
		self.connections,
		BlasterUtilities.lastInputCategoryChanged:Connect(function(lastInputCategory)
			self:onLastInputCategoryChanged(lastInputCategory)
		end)
	)
end

function BlasterUI:cacheOriginalProperties()
	-- Ensure tables are initialized
	self.originalProperties = self.originalProperties or {}
	self.originalProperties.frame = self.originalProperties.frame or {}
	self.originalProperties.descendants = self.originalProperties.descendants or {}

	-- Cache frame properties
	if self.ammoFrame then
		self.originalProperties.frame = {
			BackgroundColor3 = self.ammoFrame.BackgroundColor3,
			BackgroundTransparency = self.ammoFrame.BackgroundTransparency,
			Position = self.ammoFrame.Position
		}
	end

	-- Cache ammo label properties
	if self.ammoLabel then
		self.originalProperties.ammoLabel = {
			TextColor3 = self.ammoLabel.TextColor3,
			TextTransparency = self.ammoLabel.TextTransparency,
			TextSize = self.ammoLabel.TextSize
		}
	end

	-- Cache magazine label properties
	if self.magazineLabel then
		self.originalProperties.magazineLabel = {
			TextColor3 = self.magazineLabel.TextColor3,
			TextTransparency = self.magazineLabel.TextTransparency,
			TextSize = self.magazineLabel.TextSize
		}
	end

	-- Cache divider properties
	if self.divider then
		self.originalProperties.divider = {
			BackgroundColor3 = self.divider.BackgroundColor3,
			BackgroundTransparency = self.divider.BackgroundTransparency
		}
	end

	-- Cache properties for all descendant UI elements
	if self.ammoFrame then
		for _, element in pairs(self.ammoFrame:GetDescendants()) do
			if element:IsA("GuiObject") then
				local properties = {
					BackgroundColor3 = element.BackgroundColor3,
					BackgroundTransparency = element.BackgroundTransparency
				}

				if element:IsA("TextLabel") or element:IsA("TextButton") then
					properties.TextColor3 = element.TextColor3
					properties.TextTransparency = element.TextTransparency
					properties.TextSize = element.TextSize
				end

				if element:IsA("ImageLabel") or element:IsA("ImageButton") then
					properties.ImageColor3 = element.ImageColor3
					properties.ImageTransparency = element.ImageTransparency
				end

				self.originalProperties.descendants[element] = properties
			end
		end
	end
end

function BlasterUI:updateAmmoText()
	if self.ammoLabel then
		if self.reloading then
			self.ammoLabel.Text = "--"
			-- Visual reload indicator animation
			self:playReloadAnimation()
		else
			-- Get the previous ammo value for comparison
			local oldAmmo = self.previousAmmo or self.ammo
			self.ammoLabel.Text = tostring(self.ammo)

			-- Only do pulse animation if ammo actually changed and decreased
			if self.ammo < oldAmmo then
				self:playAmmoPulseAnimation()
			end

			-- Store the current ammo for next comparison
			self.previousAmmo = self.ammo

			-- Update color based on ammo percentage
			self:updateAmmoColor()
		end
	end
end

function BlasterUI:updateAmmoColor()
	if not self.ammoLabel then return end

	-- Calculate ammo percentage
	local percentage = self.ammo / self.magazineSize

	-- Color gradient: white -> yellow -> orange -> red
	local color
	if percentage > 0.5 then
		-- White to yellow (100% to 50%)
		local t = (1 - percentage) * 2 -- 0 to 1
		color = Color3.new(1, 1, 1):Lerp(Color3.new(1, 1, 0), t)
	else
		-- Yellow to red (50% to 0%)
		local t = (0.5 - percentage) * 2 -- 0 to 1
		color = Color3.new(1, 1, 0):Lerp(Color3.new(1, 0, 0), t)
	end

	-- Create color tween
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tween = TweenService:Create(self.ammoLabel, tweenInfo, {
		TextColor3 = color
	})
	tween:Play()
end

function BlasterUI:playAmmoPulseAnimation()
	if not self.ammoLabel then return end

	-- Get original size, with fallbacks
	local originalSize = 18 -- Default fallback size
	if self.originalProperties and self.originalProperties.ammoLabel then
		originalSize = self.originalProperties.ammoLabel.TextSize or self.ammoLabel.TextSize
	elseif self.ammoLabel then
		originalSize = self.ammoLabel.TextSize
	end

	-- Make sure we have a valid size
	if originalSize <= 0 then originalSize = 18 end

	-- Calculate pulse size
	local pulseSize = originalSize * 1.3

	-- Make the pulse more dramatic at low ammo
	local percentage = self.ammo / self.magazineSize
	if percentage <= 0.25 then
		pulseSize = originalSize * 1.5
	end

	-- Create pulse in tween
	local inTween = TweenService:Create(self.ammoLabel, 
		TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{TextSize = pulseSize}
	)

	-- Create pulse out tween
	local outTween = TweenService:Create(self.ammoLabel, 
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{TextSize = originalSize}
	)


	-- Play tweens in sequence
	inTween:Play()
	inTween.Completed:Connect(function()
		outTween:Play()
	end)
end

function BlasterUI:playReloadAnimation()
	if not self.ammoLabel then return end

	-- Safety check for originalProperties
	if not self.originalProperties or not self.originalProperties.ammoLabel then return end

	-- Cancel any existing reload animation
	if self.reloadAnimationTask then
		task.cancel(self.reloadAnimationTask)
		self.reloadAnimationTask = nil
	end

	local dots = 1
	local originalColor = self.originalProperties.ammoLabel.TextColor3 or Color3.new(1, 1, 1)

	-- Pulsing blue color during reload
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local colorTween = TweenService:Create(self.ammoLabel, tweenInfo, {
		TextColor3 = Color3.new(0.4, 0.6, 1)
	})
	colorTween:Play()

	-- Animated dots to show progress
	self.reloadAnimationTask = task.spawn(function()
		while self.reloading do
			dots = (dots % 3) + 1
			self.ammoLabel.Text = string.rep("-", dots)
			task.wait(0.3)
		end

		-- Reset color when done reloading
		local resetColorTween = TweenService:Create(self.ammoLabel, tweenInfo, {
			TextColor3 = originalColor
		})
		resetColorTween:Play()
	end)
end

function BlasterUI:setAmmo(ammo)
	self.ammo = ammo
	self:updateAmmoText()
end

function BlasterUI:setReloading(reloading)
	self.reloading = reloading
	self:updateAmmoText()
end

function BlasterUI:showHitmarker()
	-- Slightly delay the hitmarker sound so it doesn't overlap the shooting sound
	task.delay(Constants.HITMARKER_SOUND_DELAY, function()
		BlasterUtilities.playSoundFromSource(hitmarkerSound, audioTarget)
	end)

	if self.hitmarkerScaleTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerScaleTween:Cancel()
	end
	if self.hitmarkerTransparencyTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerTransparencyTween:Cancel()
	end

	self.reticleGui.Hitmarker.GroupTransparency = 0
	self.reticleGui.Hitmarker.UIScale.Scale = 2

	self.hitmarkerScaleTween:Play()
	self.hitmarkerTransparencyTween:Play()
end

-- Touch input methods
function BlasterUI:enableTouchInput()
	if self.touchEnabled then
		return
	end

	self.touchEnabled = true
	self.touchGui.Enabled = true

	-- Since we're going to be manually activating the blaster with a gui button, we disable the default tool activation
	self.blaster.ManualActivationOnly = true

	-- Connect button inputs
	table.insert(
		self.connections,
		self.touchGui.Buttons.ShootButton.InputBegan:Connect(function(inputObject)
			-- Change events will fire even though we're listening to InputBegan, we need to ignore those
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onShootButtonInput(inputObject)
		end)
	)

	table.insert(
		self.connections,
		self.touchGui.Buttons.ReloadButton.InputBegan:Connect(function(inputObject)
			-- Change events will fire even though we're listening to InputBegan, we need to ignore those
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onReloadButtonInput(inputObject)
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(inputObject)
			self:onInputEnded(inputObject)
		end)
	)
end

function BlasterUI:disableTouchInput()
	if not self.touchEnabled then
		return
	end

	self.touchEnabled = false
	self.touchGui.Enabled = false
	self.blaster.ManualActivationOnly = false
end

function BlasterUI:onReloadButtonInput(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if self.reloadCallback then
		self.reloadCallback()
	end
end

function BlasterUI:onShootButtonInput(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Save this inputObject as the current object being held to shoot. InputObjects are persistent as long
	-- as the user's finger stays down, so we can check later to see if this input has stopped.
	self.shootInputObject = inputObject
	self.blaster:Activate()
end

function BlasterUI:onInputEnded(inputObject)
	if self.shootInputObject == inputObject then
		self.shootInputObject = nil
		self.blaster:Deactivate()
	end
end

function BlasterUI:setReloadCallback(callback)
	self.reloadCallback = callback
end

function BlasterUI:onLastInputCategoryChanged(lastInputCategory)
	if lastInputCategory == BlasterUtilities.InputCategory.Touch then
		self:enableTouchInput()
	else
		self:disableTouchInput()
	end
end

-- Main UI methods
function BlasterUI:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	-- First restore original properties to ensure clean state
	if self.restoreOriginalProperties then
		self:restoreOriginalProperties()
	end

	-- Make visible first
	self.ammoFrame.Visible = true
	self.reticleGui.Enabled = true

	-- Make sure text is visible
	if self.ammoLabel then
		self.ammoLabel.TextTransparency = 0
	end
	if self.magazineLabel then
		self.magazineLabel.TextTransparency = 0
	end

	-- Make sure divider is visible but transparent
	if self.divider then
		self.divider.BackgroundTransparency = 1
	end

	-- Ensure ammo text is updated
	self:updateAmmoText()

	-- Store original position
	local originalPosition = self.ammoFrame.Position
	if self.originalProperties and self.originalProperties.frame and self.originalProperties.frame.Position then
		originalPosition = self.originalProperties.frame.Position
	end

	-- Set initial position slightly lower
	self.ammoFrame.Position = originalPosition + UDim2.new(0, 0, 0, 10)

	-- Create and play tween to animate upward
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tween = TweenService:Create(self.ammoFrame, tweenInfo, {
		Position = originalPosition
	})
	tween:Play()

	-- Initialize touch input if needed
	local lastInputCategory = BlasterUtilities.getLastInputCategory()
	if lastInputCategory == BlasterUtilities.InputCategory.Touch then
		self:enableTouchInput()
	end

	UserInputService.MouseIconEnabled = false

	-- Force an ammo update to ensure text is displayed
	self:setAmmo(self.ammo)
end

function BlasterUI:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	-- Create fade out tween for the frame
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	local frameTween = TweenService:Create(self.ammoFrame, tweenInfo, {
		BackgroundTransparency = 1
	})

	-- Create tweens for label transparencies
	if self.ammoLabel then
		local ammoLabelTween = TweenService:Create(self.ammoLabel, tweenInfo, {
			TextTransparency = 1
		})
		ammoLabelTween:Play()
	end

	if self.magazineLabel then
		local magazineLabelTween = TweenService:Create(self.magazineLabel, tweenInfo, {
			TextTransparency = 1
		})
		magazineLabelTween:Play()
	end

	-- Fade out divider
	if self.divider then
		local dividerTween = TweenService:Create(self.divider, tweenInfo, {
			BackgroundTransparency = 1
		})
		dividerTween:Play()
	end

	-- Get all UI elements and tween their transparency
	if self.ammoFrame then
		for _, element in pairs(self.ammoFrame:GetDescendants()) do
			if element:IsA("GuiObject") then
				local tweenProps = {}

				if element:IsA("GuiObject") then
					tweenProps.BackgroundTransparency = 1
				end

				if element:IsA("TextLabel") or element:IsA("TextButton") then
					tweenProps.TextTransparency = 1
				end

				if element:IsA("ImageLabel") or element:IsA("ImageButton") then
					tweenProps.ImageTransparency = 1
				end

				if next(tweenProps) then
					local elementTween = TweenService:Create(element, tweenInfo, tweenProps)
					elementTween:Play()
				end
			end
		end
	end

	-- Hide after tween completes
	frameTween.Completed:Connect(function()
		self.ammoFrame.Visible = false

		-- Restore all original properties to ensure clean state for next enable
		if self.restoreOriginalProperties then
			self:restoreOriginalProperties()
		end
	end)

	frameTween:Play()

	self.reticleGui.Enabled = false
	self:disableTouchInput()

	UserInputService.MouseIconEnabled = true
end

function BlasterUI:destroy()
	self:disable()
	BlasterUtilities.disconnectAndClear(self.connections)

	-- Cancel any ongoing animations
	if self.reloadAnimationTask then
		task.cancel(self.reloadAnimationTask)
		self.reloadAnimationTask = nil
	end

	-- Clean up UI elements
	if self.ammoFrame then
		self.ammoFrame:Destroy()
	end
	if self.reticleGui then
		self.reticleGui:Destroy()
	end
	if self.touchGui then
		self.touchGui:Destroy()
	end
end

return BlasterUI