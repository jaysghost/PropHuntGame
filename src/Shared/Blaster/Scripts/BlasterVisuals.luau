local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local BlasterUtilities = require(ReplicatedStorage.Blaster.BlasterUtilities)

local camera = Workspace.CurrentCamera
local viewModels = ReplicatedStorage.Blaster.ViewModels
local audioTarget = SoundService.Audio.Busses.World.AudioCompressor

local BlasterVisuals = {}
BlasterVisuals.__index = BlasterVisuals

-- VIEW MODEL CONTROLLER
function BlasterVisuals.new(blaster)
	-- View Model Controller
	local handle = blaster:WaitForChild("Handle")
	local sounds = blaster:WaitForChild("Sounds")

	local viewModelName = blaster:GetAttribute(Constants.VIEW_MODEL_ATTRIBUTE)
	local viewModelTemplate = viewModels[viewModelName]

	local viewModel = viewModelTemplate:Clone()
	local muzzle = viewModel:FindFirstChild("MuzzleAttachment", true)
	assert(muzzle, `{viewModel} is missing MuzzleAttachment!`)

	local animator = viewModel.AnimationController.Animator
	local animationsFolder = viewModel.Animations

	-- The viewModel needs to be parented to the DataModel in order to load animations, otherwise it will throw an error
	viewModel.Parent = ReplicatedStorage

	local animations = {}
	for _, animation in animationsFolder:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		animations[animation.Name] = animationTrack

		-- Sounds will all be driven by animation events
		BlasterUtilities.bindSoundsToAnimationEvents(animationTrack, sounds, audioTarget)
	end

	-- Character animations
	local characterAnimations = {}
	local characterAnimationsLoaded = false

	local self = {
		enabled = false,
		blaster = blaster,
		handle = handle,
		model = viewModel,
		muzzle = muzzle,
		animations = animations,
		characterAnimations = characterAnimations,
		characterAnimationsLoaded = characterAnimationsLoaded,
		toolInstances = {},
		connections = {},
		stride = 0,
		bobbing = 0,
	}
	setmetatable(self, BlasterVisuals)

	return self
end

function BlasterVisuals:update(deltaTime)
	-- Hide tool instances
	for _, instance in self.toolInstances do
		instance.LocalTransparencyModifier = 1
	end

	-- View model bobbing animation
	local moveSpeed = (self.handle.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	local bobbingSpeed = moveSpeed * Constants.VIEW_MODEL_BOBBING_SPEED
	local bobbing = math.min(bobbingSpeed, 1)

	self.stride = (self.stride + bobbingSpeed * deltaTime) % (math.pi * 2)
	self.bobbing = BlasterUtilities.lerp(self.bobbing, bobbing, math.min(deltaTime * Constants.VIEW_MODEL_BOBBING_TRANSITION_SPEED, 1))

	local x = math.sin(self.stride)
	local y = math.sin(self.stride * 2)
	local bobbingOffset = Vector3.new(x, y, 0) * Constants.VIEW_MODEL_BOBBING_AMOUNT * self.bobbing
	local bobbingCFrame = CFrame.new(bobbingOffset)

	self.model:PivotTo(camera.CFrame * Constants.VIEW_MODEL_OFFSET * bobbingCFrame)
end

-- Add this helper function at the beginning of BlasterVisuals
function BlasterVisuals:safePlayAnimation(animationTable, animName, ...)
	if animationTable and animationTable[animName] then
		return animationTable[animName]:Play(...)
	else
		-- Silent handling of missing animations
		return nil
	end
end

function BlasterVisuals:safeStopAnimation(animationTable, animName, ...)
	if animationTable and animationTable[animName] then
		return animationTable[animName]:Stop(...)
	end
end

function BlasterVisuals:checkForToolInstance(instance)
	if not (instance:IsA("BasePart") or instance:IsA("Decal")) then
		return
	end

	local tool = instance:FindFirstAncestorOfClass("Tool")
	if not tool then
		return
	end

	table.insert(self.toolInstances, instance)
end

function BlasterVisuals:hideToolInstances()
	local character = self.blaster.Parent

	table.insert(
		self.connections,
		character.DescendantAdded:Connect(function(descendant)
			self:checkForToolInstance(descendant)
		end)
	)

	table.insert(
		self.connections,
		character.DescendantRemoving:Connect(function(descendant)
			local index = table.find(self.toolInstances, descendant)
			if index then
				table.remove(self.toolInstances, index)
			end
		end)
	)

	for _, descendant in character:GetDescendants() do
		self:checkForToolInstance(descendant)
	end
end

function BlasterVisuals:stopHidingToolInstances()
	table.clear(self.toolInstances)
	BlasterUtilities.disconnectAndClear(self.connections)
end

function BlasterVisuals:getMuzzlePosition()
	return self.muzzle.WorldPosition
end

-- VFX Functions
function BlasterVisuals:laserBeamEffect(startPosition, endPosition)
	local distance = (startPosition - endPosition).Magnitude
	local tweenTime = distance / Constants.LASER_BEAM_VISUAL_SPEED
	local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

	local laserBeamTemplate = ReplicatedStorage.Blaster.Objects.LaserBeam
	local laser = laserBeamTemplate:Clone()
	laser.CFrame = CFrame.lookAt(startPosition, endPosition)
	laser.StartAttachment.Position = Vector3.zero
	laser.EndAttachment.Position = Vector3.new(0, 0, -distance)
	laser.Parent = Workspace

	local tween = TweenService:Create(laser.StartAttachment, tweenInfo, { Position = laser.EndAttachment.Position })
	tween:Play()
	tween.Completed:Once(function()
		laser:Destroy()
	end)
end

function BlasterVisuals:impactEffect(position, normal, isCharacter)
	local environmentImpactTemplate = ReplicatedStorage.Blaster.Objects.EnvironmentImpact
	local characterImpactTemplate = ReplicatedStorage.Blaster.Objects.CharacterImpact

	local impact
	if isCharacter then
		impact = characterImpactTemplate:Clone()
		impact.CFrame = CFrame.lookAlong(position, normal)
		impact.Parent = Workspace
		impact.SparkEmitter:Emit(10)
		impact.CircleEmitter:Emit(2)
	else
		impact = environmentImpactTemplate:Clone()
		impact.CFrame = CFrame.lookAlong(position, normal)
		impact.Parent = Workspace
		impact.SparkEmitter:Emit(10)
		impact.CircleEmitter:Emit(2)
	end

	task.delay(0.5, function()
		impact:Destroy()
	end)
end

function BlasterVisuals:drawRayResults(position, rayResults)
	local range = self.blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)

	for i, rayResult in ipairs(rayResults) do
		local endPosition

		if rayResult.instance then
			-- Hit something - use the hit position
			endPosition = rayResult.position
		else
			-- Didn't hit anything - need to extend to maximum range
			-- Calculate a direction vector from the camera's look vector
			local direction = camera.CFrame.LookVector

			-- Calculate the end position
			endPosition = position + (direction * range)
		end

		self:laserBeamEffect(position, endPosition)

		if rayResult.instance then
			self:impactEffect(rayResult.position, rayResult.normal, rayResult.taggedHumanoid ~= nil)
		end
	end
end

function BlasterVisuals.drawRayResultsStatic(position, rayResults)
	-- Create a copy that doesn't require "self"
	for i, rayResult in ipairs(rayResults) do
		local endPosition = rayResult.position

		-- Create laser beam effect
		local laserBeamTemplate = ReplicatedStorage.Blaster.Objects.LaserBeam
		local distance = (position - endPosition).Magnitude
		local tweenTime = distance / Constants.LASER_BEAM_VISUAL_SPEED
		local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

		local laser = laserBeamTemplate:Clone()
		laser.CFrame = CFrame.lookAt(position, endPosition)
		laser.StartAttachment.Position = Vector3.zero
		laser.EndAttachment.Position = Vector3.new(0, 0, -distance)
		laser.Parent = Workspace

		local tween = TweenService:Create(laser.StartAttachment, tweenInfo, {Position = laser.EndAttachment.Position})
		tween:Play()
		tween.Completed:Once(function()
			laser:Destroy()
		end)

		-- Create impact effect if applicable
		if rayResult.instance then
			local impactTemplate = rayResult.taggedHumanoid 
				and ReplicatedStorage.Blaster.Objects.CharacterImpact 
				or ReplicatedStorage.Blaster.Objects.EnvironmentImpact

			local impact = impactTemplate:Clone()
			impact.CFrame = CFrame.lookAlong(rayResult.position, rayResult.normal)
			impact.Parent = Workspace
			impact.SparkEmitter:Emit(10)
			impact.CircleEmitter:Emit(2)

			task.delay(0.5, function()
				impact:Destroy()
			end)
		end
	end
end

function BlasterVisuals:showPropHitEffect(prop, position)
	-- Create a simple hit effect (particles, sound, etc.)
	local effect = Instance.new("Part")
	effect.Size = Vector3.new(0.5, 0.5, 0.5)
	effect.Transparency = 1  -- Invisible part, just for the effect
	effect.CanCollide = false
	effect.Anchored = true
	effect.Position = position
	effect.Parent = workspace

	-- Add particle emitter for hit effect
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://6101261295"  -- Wood particle texture
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 0
	emitter.Parent = effect

	-- Emit particles once
	emitter:Emit(20)

	-- Clean up after effect finishes
	task.delay(2, function()
		effect:Destroy()
	end)

	-- Play hit sound
	local hitSound = Instance.new("Sound")
	hitSound.SoundId = "rbxassetid://142082167"  -- Wood hit sound
	hitSound.Volume = 0.5
	hitSound.Parent = effect
	hitSound:Play()
	hitSound.Ended:Connect(function()
		hitSound:Destroy()
	end)
end

-- Animation Functions
function BlasterVisuals:playShootAnimation()
	self.animations.Shoot:Play(0)
	self.muzzle.FlashEmitter:Emit(1)
	self.muzzle.CircleEmitter:Emit(1)

	-- Character animation with safety
	self:safePlayAnimation(self.characterAnimations, "Shoot", 0)
end

function BlasterVisuals:playReloadAnimation(reloadTime)
	self.animations.Shoot:Stop()
	local speed = self.animations.Reload.Length / reloadTime
	self.animations.Reload:Play(Constants.VIEW_MODEL_RELOAD_FADE_TIME, 1, speed)

	-- Character animation with safety
	if self.characterAnimationsLoaded then
		-- Get character reload animation
		local reloadAnim = self.characterAnimations.Reload
		if reloadAnim then
			local charSpeed = reloadAnim.Length / reloadTime
			reloadAnim:Play(0.1, 1, charSpeed)
		end
	end
end

-- Character Animation Functions
function BlasterVisuals:loadCharacterAnimations()
	if self.characterAnimationsLoaded then
		return
	end

	self.characterAnimationsLoaded = true
	local animationsFolder = self.blaster:FindFirstChild("Animations")

	-- Check if animations folder exists
	if not animationsFolder then
		warn("Blaster is missing Animations folder for third-person animations")
		self.characterAnimations = {}
		return
	end

	-- This should only be called when the blaster has been equipped
	local humanoid = self.blaster.Parent:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("Blaster is not equipped to a character with Humanoid")
		self.characterAnimations = {}
		return
	end

	local animator = humanoid.Animator
	local animationTracks = {}

	for _, animation in animationsFolder:GetChildren() do
		local success, animationTrack = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if success and animationTrack then
			animationTracks[animation.Name] = animationTrack
		else
			warn("Failed to load character animation: " .. animation.Name)
		end
	end

	self.characterAnimations = animationTracks
end

-- Main Functions
function BlasterVisuals:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	RunService:BindToRenderStep(
		Constants.VIEW_MODEL_BIND_NAME,
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaTime)
			self:update(deltaTime)
		end
	)
	self.model.Parent = Workspace
	self:hideToolInstances()

	-- Play first-person animations
	self.animations.Idle:Play()
	self.animations.Equip:Play(0)

	-- Load character animations if needed
	if not self.characterAnimationsLoaded then
		self:loadCharacterAnimations()
	end

	-- Safely play character animations
	self:safePlayAnimation(self.characterAnimations, "Idle")
end

function BlasterVisuals:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	RunService:UnbindFromRenderStep(Constants.VIEW_MODEL_BIND_NAME)
	self.model.Parent = nil
	self:stopHidingToolInstances()

	for _, animation in self.animations do
		animation:Stop(0)
	end

	-- Safely stop character animations
	if self.characterAnimationsLoaded then
		for _, animation in self.characterAnimations do
			pcall(function() animation:Stop() end)
		end
	end
end

function BlasterVisuals:destroy()
	BlasterUtilities.disconnectAndClear(self.connections)
	self:disable()
	self.model:Destroy()

	-- Clear animation tables for garbage collection
	table.clear(self.characterAnimations)
end

return BlasterVisuals