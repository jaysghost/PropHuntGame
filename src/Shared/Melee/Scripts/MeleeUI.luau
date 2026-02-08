local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Melee.Constants)
local MeleeUtilities = require(ReplicatedStorage.Melee.MeleeUtilities)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local reticleGuiTemplate = script.ReticleGui
local touchGuiTemplate = script.MeleeTouchGui
local hitmarkerSound = script.Hitmarker
local audioTarget = SoundService.Audio.Busses.UI.AudioCompressor

-- Get reference to Client and HUD
local client = playerGui:WaitForChild("Client")
local hud = client:WaitForChild("HUD")

local MeleeUI = {}
MeleeUI.__index = MeleeUI

function MeleeUI.new(melee)
	-- Clone the reticle GUI
	local reticleGui = reticleGuiTemplate:Clone()
	reticleGui.Enabled = false
	reticleGui.Parent = playerGui

	-- Clone the touch GUI for mobile controls
	local touchGui = touchGuiTemplate:Clone()
	touchGui.Enabled = false
	touchGui.Parent = playerGui

	-- Set up hitmarker animations
	local scaleTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local transparencyTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local hitmarkerScaleTween = TweenService:Create(reticleGui.Hitmarker.UIScale, scaleTweenInfo, { Scale = 1 })
	local hitmarkerTransparencyTween = TweenService:Create(reticleGui.Hitmarker, transparencyTweenInfo, { GroupTransparency = 1 })

	local self = {
		melee = melee,
		reticleGui = reticleGui,
		touchGui = touchGui,
		hitmarkerScaleTween = hitmarkerScaleTween,
		hitmarkerTransparencyTween = hitmarkerTransparencyTween,
		enabled = false,
		touchEnabled = false,
		connections = {},
	}
	setmetatable(self, MeleeUI)
	self:initialize()
	return self
end

function MeleeUI:initialize()
	-- Connect to InputChanged for detecting input method
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType)
			self:onInputTypeChanged(inputType)
		end)
	)

	-- Add input ended listener for touch controls
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(inputObject)
			self:onInputEnded(inputObject)
		end)
	)

	-- Check initial input type
	self:onInputTypeChanged(UserInputService:GetLastInputType())
end

function MeleeUI:onInputTypeChanged(inputType)
	-- Determine input category
	local inputCategory
	if string.find(inputType.Name, "Gamepad") then
		inputCategory = "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		inputCategory = "KeyboardAndMouse"
	elseif inputType == Enum.UserInputType.Touch then
		inputCategory = "Touch"
	else
		inputCategory = "Unknown"
	end

	-- Call our existing handler
	self:onLastInputCategoryChanged(inputCategory)
end

function MeleeUI:showHitmarker()
	-- Slightly delay the hitmarker sound
	task.delay(Constants.HIT_SOUND_DELAY, function()
		MeleeUtilities.playSoundFromSource(hitmarkerSound, audioTarget)
	end)

	-- Reset any ongoing hitmarker animations
	if self.hitmarkerScaleTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerScaleTween:Cancel()
	end
	if self.hitmarkerTransparencyTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerTransparencyTween:Cancel()
	end

	-- Set initial state for hitmarker
	self.reticleGui.Hitmarker.GroupTransparency = 0
	self.reticleGui.Hitmarker.UIScale.Scale = 2

	-- Play hitmarker animations
	self.hitmarkerScaleTween:Play()
	self.hitmarkerTransparencyTween:Play()
end

-- Touch input methods
function MeleeUI:enableTouchInput()
	if self.touchEnabled then
		return
	end

	self.touchEnabled = true
	self.touchGui.Enabled = true

	-- Set the tool to use manual activation (controlled by our GUI buttons)
	self.melee.ManualActivationOnly = true

	-- Connect button inputs
	table.insert(
		self.connections,
		self.touchGui.Buttons.PrimaryAttackButton.InputBegan:Connect(function(inputObject)
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onPrimaryAttackButtonInput(inputObject)
		end)
	)

	table.insert(
		self.connections,
		self.touchGui.Buttons.SecondaryAttackButton.InputBegan:Connect(function(inputObject)
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onSecondaryAttackButtonInput(inputObject)
		end)
	)
end

function MeleeUI:disableTouchInput()
	if not self.touchEnabled then
		return
	end

	self.touchEnabled = false
	self.touchGui.Enabled = false
	self.melee.ManualActivationOnly = false
end

function MeleeUI:onPrimaryAttackButtonInput(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Save input object for tracking touch held state
	self.primaryTouchInput = inputObject

	-- Forward the input to the tool's Activated event
	self.melee:Activate()
end

function MeleeUI:onSecondaryAttackButtonInput(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Secondary attacks are handled via a custom event since they can't use the tool's Activated event
	UserInputService:FireSecondary()
end

function MeleeUI:onInputEnded(inputObject)
	-- Check if this is our tracked touch input
	if inputObject == self.primaryTouchInput then
		self.primaryTouchInput = nil
		self.melee:Deactivate()
	end
end

function MeleeUI:onLastInputCategoryChanged(lastInputCategory)
	if lastInputCategory == MeleeUtilities.InputCategory.Touch then
		self:enableTouchInput()
	else
		self:disableTouchInput()
	end
end

-- Main UI methods
function MeleeUI:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	-- Enable reticle
	self.reticleGui.Enabled = true

	-- Initialize touch input if needed
	local lastInputCategory = MeleeUtilities.getLastInputCategory and MeleeUtilities.getLastInputCategory()
	if lastInputCategory == MeleeUtilities.InputCategory.Touch then
		self:enableTouchInput()
	end

	-- Hide mouse cursor
	UserInputService.MouseIconEnabled = false
end

function MeleeUI:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	-- Disable reticle
	self.reticleGui.Enabled = false

	-- Disable touch controls
	self:disableTouchInput()

	-- Show mouse cursor
	UserInputService.MouseIconEnabled = true
end

function MeleeUI:destroy()
	self:disable()
	MeleeUtilities.disconnectAndClear(self.connections)

	-- Clean up UI elements
	if self.reticleGui then
		self.reticleGui:Destroy()
	end
	if self.touchGui then
		self.touchGui:Destroy()
	end
end

return MeleeUI