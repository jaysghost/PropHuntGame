local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Melee.Constants)
local MeleeUtilities = require(ReplicatedStorage.Melee.MeleeUtilities)

local camera = Workspace.CurrentCamera
local viewModels = ReplicatedStorage.Melee.ViewModels
local audioTarget = SoundService.Audio.Busses.World.AudioCompressor

local MeleeVisuals = {}
MeleeVisuals.__index = MeleeVisuals

-- VIEW MODEL CONTROLLER
function MeleeVisuals.new(melee)
	-- View Model Controller
	local handle = melee:WaitForChild("Handle")
	local sounds = melee:WaitForChild("Sounds")

	local viewModelName = melee:GetAttribute(Constants.VIEW_MODEL_ATTRIBUTE)
	local viewModelTemplate = viewModels[viewModelName]

	local viewModel = viewModelTemplate:Clone()

	-- Check if this weapon should have trails
	local hasTrail = melee:GetAttribute("hasTrail") or false

	-- Only look for attachments if weapon has trails
	local bladeTip = nil
	local bladeRoot = nil

	if hasTrail then
		bladeTip = viewModel:FindFirstChild("BladeTipAttachment", true)
		bladeRoot = viewModel:FindFirstChild("BladeRootAttachment", true)

		-- If we're supposed to have trails but missing attachments, warn instead of error
		if not bladeTip or not bladeRoot then
			warn(`{viewModel.Name} is missing blade attachments but hasTrail is true. Trails won't be created.`)
		end
	end

	local animator = viewModel.AnimationController.Animator
	local animationsFolder = viewModel.Animations

	-- The viewModel needs to be parented to the DataModel in order to load animations
	viewModel.Parent = ReplicatedStorage

	local animations = {}
	for _, animation in animationsFolder:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		animations[animation.Name] = animationTrack

		-- Sounds will all be driven by animation events
		MeleeUtilities.bindSoundsToAnimationEvents(animationTrack, sounds, audioTarget)
	end

	-- Character animations
	local characterAnimations = {}
	local characterAnimationsLoaded = false

	local self = {
		enabled = false,
		melee = melee,
		handle = handle,
		model = viewModel,
		bladeTip = bladeTip,
		bladeRoot = bladeRoot,
		hasTrail = hasTrail,
		animations = animations,
		characterAnimations = characterAnimations,
		characterAnimationsLoaded = characterAnimationsLoaded,
		toolInstances = {},
		connections = {},
		trailActive = false,
		trailParts = {},
		stride = 0,           -- For bobbing animation
		bobbing = 0,          -- For bobbing intensity
	}
	setmetatable(self, MeleeVisuals)

	-- Create trail effect only if we have the required attachments
	if hasTrail and bladeTip and bladeRoot then
		self:createTrailEffect()
	end

	return self
end

function MeleeVisuals:createTrailEffect()
	-- Create attachment points for the trail
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailAttachment0"
	a0.Parent = self.model:FindFirstChild("Handle", true)

	local a1 = Instance.new("Attachment") 
	a1.Name = "TrailAttachment1"
	a1.Parent = self.model:FindFirstChild("Handle", true)

	-- Position attachments to match weapon blade
	a0.WorldPosition = self.bladeRoot.WorldPosition
	a1.WorldPosition = self.bladeTip.WorldPosition

	-- Create trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Constants.SWING_TRAIL_COLOR)
	trail.Transparency = NumberSequence.new(Constants.SWING_TRAIL_TRANSPARENCY)
	trail.WidthScale = NumberSequence.new(1)
	trail.Lifetime = Constants.SWING_TRAIL_DURATION
	trail.Enabled = false
	trail.Parent = self.model

	-- Store references
	self.trailAttachment0 = a0
	self.trailAttachment1 = a1
	self.trail = trail
end

function MeleeVisuals:activateTrail()
	if not self.hasTrail or not self.trail then return end

	self.trail.Enabled = true
	self.trailActive = true

	-- Deactivate trail after a short duration
	task.delay(Constants.SWING_TRAIL_DURATION * 2, function()
		if self.trail then
			self.trail.Enabled = false
			self.trailActive = false
		end
	end)
end

function MeleeVisuals:update(deltaTime)
	-- Hide tool instances
	for _, instance in self.toolInstances do
		instance.LocalTransparencyModifier = 1
	end

	-- View model bobbing animation (same as in BlasterVisuals)
	local moveSpeed = (self.handle.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	local bobbingSpeed = moveSpeed * Constants.VIEW_MODEL_BOBBING_SPEED
	local bobbing = math.min(bobbingSpeed, 1)

	self.stride = (self.stride + bobbingSpeed * deltaTime) % (math.pi * 2)
	self.bobbing = MeleeUtilities.lerp(self.bobbing, bobbing, math.min(deltaTime * Constants.VIEW_MODEL_BOBBING_TRANSITION_SPEED, 1))

	local x = math.sin(self.stride)
	local y = math.sin(self.stride * 2)
	local bobbingOffset = Vector3.new(x, y, 0) * Constants.VIEW_MODEL_BOBBING_AMOUNT * self.bobbing
	local bobbingCFrame = CFrame.new(bobbingOffset)

	-- Update view model position with bobbing
	self.model:PivotTo(camera.CFrame * Constants.VIEW_MODEL_OFFSET * bobbingCFrame)

	-- Update trail attachment positions if they exist
	if self.hasTrail and self.trailAttachment0 and self.trailAttachment1 and
		self.bladeRoot and self.bladeTip then
		self.trailAttachment0.WorldPosition = self.bladeRoot.WorldPosition
		self.trailAttachment1.WorldPosition = self.bladeTip.WorldPosition
	end
end

function MeleeVisuals:checkForToolInstance(instance)
	if not (instance:IsA("BasePart") or instance:IsA("Decal")) then
		return
	end

	local tool = instance:FindFirstAncestorOfClass("Tool")
	if not tool then
		return
	end

	table.insert(self.toolInstances, instance)
end

function MeleeVisuals:hideToolInstances()
	local character = self.melee.Parent

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

function MeleeVisuals:stopHidingToolInstances()
	table.clear(self.toolInstances)
	MeleeUtilities.disconnectAndClear(self.connections)
end

-- VFX Functions
function MeleeVisuals:createHitEffect(position, normal, isCharacter)
	local impactTemplate = isCharacter 
		and ReplicatedStorage.Melee.Objects.CharacterImpact 
		or ReplicatedStorage.Melee.Objects.EnvironmentImpact

	local impact = impactTemplate:Clone()
	impact.CFrame = CFrame.lookAlong(position, normal)
	impact.Parent = Workspace

	-- Emit particles
	for _, emitter in pairs(impact:GetChildren()) do
		if emitter:IsA("ParticleEmitter") then
			emitter:Emit(emitter.Rate)
		end
	end

	-- Clean up after effect finishes
	task.delay(2, function()
		impact:Destroy()
	end)
end

-- Static version for replication
function MeleeVisuals.drawSwingEffectStatic(startPos, endPos, hitInfo)
	-- Create a temporary part for the swing effect
	local distance = (startPos - endPos).Magnitude
	local midPoint = startPos:Lerp(endPos, 0.5)
	local direction = (endPos - startPos).Unit

	-- Create swing arc visualization
	local swingArc = Instance.new("Part")
	swingArc.Size = Vector3.new(0.1, 0.1, distance)
	swingArc.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance/2)
	swingArc.Anchored = true
	swingArc.CanCollide = false
	swingArc.Transparency = 1
	swingArc.Parent = Workspace

	-- Create trail effect
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, distance/2)
	a0.Parent = swingArc

	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -distance/2)
	a1.Parent = swingArc

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Constants.SWING_TRAIL_COLOR)
	trail.Transparency = NumberSequence.new(Constants.SWING_TRAIL_TRANSPARENCY)
	trail.Lifetime = Constants.SWING_TRAIL_DURATION
	trail.Parent = swingArc

	-- Create hit effect if there was a hit
	if hitInfo and hitInfo.hit then
		local hitPos = hitInfo.position
		local hitNormal = hitInfo.normal or direction * -1

		-- Create impact effect
		local impactTemplate = hitInfo.isCharacter 
			and ReplicatedStorage.Melee.Objects.CharacterImpact 
			or ReplicatedStorage.Melee.Objects.EnvironmentImpact

		local impact = impactTemplate:Clone()
		impact.CFrame = CFrame.lookAlong(hitPos, hitNormal)
		impact.Parent = Workspace

		-- Emit particles
		for _, emitter in pairs(impact:GetChildren()) do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter.Rate)
			end
		end

		-- Clean up impact after effect
		task.delay(1, function()
			impact:Destroy()
		end)
	end

	-- Clean up swing arc
	task.delay(Constants.SWING_TRAIL_DURATION, function()
		swingArc:Destroy()
	end)
end

-- Animation Functions
function MeleeVisuals:playAttackAnimation(animationName)
	-- Stop other attack animations
	if self.animations[Constants.ANIMATION_NAMES.ATTACK1] then
		self.animations[Constants.ANIMATION_NAMES.ATTACK1]:Stop(0.1)
	end
	if self.animations[Constants.ANIMATION_NAMES.ATTACK2] then
		self.animations[Constants.ANIMATION_NAMES.ATTACK2]:Stop(0.1)
	end

	-- Play requested animation
	if self.animations[animationName] then
		self.animations[animationName]:Play(0.1)

		-- Activate trail effect
		self:activateTrail()

		-- Play character animation
		if self.characterAnimationsLoaded and self.characterAnimations[animationName] then
			self.characterAnimations[animationName]:Play(0.1)
		end
	end
end

-- Character Animation Functions
function MeleeVisuals:loadCharacterAnimations()
	if self.characterAnimationsLoaded then
		return
	end

	self.characterAnimationsLoaded = true
	local animationsFolder = self.melee:FindFirstChild("Animations")

	-- Check if animations folder exists
	if not animationsFolder then
		warn("Melee weapon is missing Animations folder for third-person animations")
		self.characterAnimations = {}
		return
	end

	-- This should only be called when the melee has been equipped
	local humanoid = self.melee.Parent:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("Melee weapon is not equipped to a character with Humanoid")
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
function MeleeVisuals:enable()
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
	self.animations[Constants.ANIMATION_NAMES.IDLE]:Play()
	self.animations[Constants.ANIMATION_NAMES.EQUIP]:Play(0)

	-- Load character animations if needed
	if not self.characterAnimationsLoaded then
		self:loadCharacterAnimations()
	end

	-- Play character idle animation
	if self.characterAnimationsLoaded and self.characterAnimations[Constants.ANIMATION_NAMES.IDLE] then
		self.characterAnimations[Constants.ANIMATION_NAMES.IDLE]:Play()
	end
end

function MeleeVisuals:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	RunService:UnbindFromRenderStep(Constants.VIEW_MODEL_BIND_NAME)
	self.model.Parent = nil
	self:stopHidingToolInstances()

	-- Stop trail effect if active
	if self.trail then
		self.trail.Enabled = false
		self.trailActive = false
	end

	-- Stop all animations
	for _, animation in self.animations do
		animation:Stop(0)
	end

	-- Stop character animations
	if self.characterAnimationsLoaded then
		for _, animation in self.characterAnimations do
			pcall(function() animation:Stop() end)
		end
	end
end

function MeleeVisuals:destroy()
	MeleeUtilities.disconnectAndClear(self.connections)
	self:disable()

	if self.model then
		self.model:Destroy()
	end

	-- Clear animation tables for garbage collection
	table.clear(self.characterAnimations)
end

return MeleeVisuals