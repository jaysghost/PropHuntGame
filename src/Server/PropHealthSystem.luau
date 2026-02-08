-- Modified PropHealthSystem.lua

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PropHealthSystem = {}
PropHealthSystem.highlights = {} -- Track all active highlights

-- Color mapping for health values
local function getHealthColor(health, maxHealth)
	local healthPercent = health / maxHealth

	-- Smooth transition from green to red
	if healthPercent >= 1.0 then
		-- Full health: pure green
		return Color3.fromRGB(0, 255, 0)
	elseif healthPercent <= 0 then
		-- No health: pure red
		return Color3.fromRGB(255, 0, 0)
	else
		-- Smooth transition
		-- Green decreases linearly from 255 to 0
		-- Red increases linearly from 0 to 255
		local greenValue = math.floor(255 * healthPercent)
		local redValue = math.floor(255 * (1 - healthPercent))

		return Color3.fromRGB(redValue, greenValue, 0)
	end
end

function PropHealthSystem.createHighlight(character)
	-- Get the PropModel
	local propModel = character:FindFirstChild("PropModel")
	if not propModel then return nil end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return nil end

	-- Clean up existing highlight if any
	PropHealthSystem.removeHighlight(character)

	-- Create new highlight (invisible by default)
	local highlight = Instance.new("Highlight")
	highlight.Name = "HealthHighlight"
	highlight.FillTransparency = 1 -- Completely invisible fill
	highlight.OutlineTransparency = 1 -- Completely invisible outline
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- Default: only visible when not behind walls
	highlight.Adornee = propModel
	highlight.Parent = propModel

	-- Store initial health color based on player health
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local healthPercent = humanoid.Health / humanoid.MaxHealth
		local healthColor = getHealthColor(humanoid.Health, humanoid.MaxHealth)
		highlight.FillColor = healthColor
		highlight.OutlineColor = healthColor
	end

	-- Store reference
	PropHealthSystem.highlights[player.UserId] = {
		highlight = highlight,
		character = character,
		tweening = false,
		lastHitTime = 0
	}

	-- Connect to health changed event
	if humanoid then
		humanoid.HealthChanged:Connect(function(newHealth)
			PropHealthSystem.updateHighlightHealth(player.UserId, newHealth, humanoid.MaxHealth)
		end)
	end

	return highlight
end

-- Update highlight based on health change
function PropHealthSystem.updateHighlightHealth(userId, health, maxHealth)
	local highlightData = PropHealthSystem.highlights[userId]
	if not highlightData then return end

	local highlight = highlightData.highlight
	if not highlight or not highlight.Parent then return end

	-- Update color based on health
	local healthColor = getHealthColor(health, maxHealth)

	-- Update the colors (the highlight might be invisible, but we always keep colors updated)
	highlight.FillColor = healthColor
	highlight.OutlineColor = healthColor
end

function PropHealthSystem.onPlayerHit(userId)
	local highlightData = PropHealthSystem.highlights[userId]
	if not highlightData then return end
	local highlight = highlightData.highlight
	if not highlight or not highlight.Parent then return end

	-- Prevent multiple hit effects in quick succession
	local currentTime = tick()
	if currentTime - highlightData.lastHitTime < 0.2 then return end
	highlightData.lastHitTime = currentTime

	-- IMPORTANT: Cancel any active tweens
	if highlightData.activeTweens then
		for _, tween in pairs(highlightData.activeTweens) do
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween:Cancel()
			end
		end
	end

	-- Initialize/reset tween tracking
	highlightData.activeTweens = {}

	-- Calculate current health color
	local humanoid = highlightData.character:FindFirstChildOfClass("Humanoid")
	local healthColor = getHealthColor(humanoid.Health, humanoid.MaxHealth)

	-- Ensure damage highlight is Occluded (doesn't show through walls)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	-- Flash effect (quickly become more visible)
	local flashTween = TweenService:Create(highlight,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			FillTransparency = 0.5, -- Adjusted per your request
			OutlineTransparency = 0,
			FillColor = healthColor,
			OutlineColor = healthColor
		}
	)

	-- Store reference to active tween
	highlightData.activeTweens.flash = flashTween

	-- Fade out effect
	local fadeOutTween = TweenService:Create(highlight,
		TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{
			FillTransparency = 1,
			OutlineTransparency = 1
		}
	)

	-- Store reference to active tween
	highlightData.activeTweens.fadeOut = fadeOutTween

	-- Sequence the tweens
	flashTween.Completed:Connect(function()
		if highlight and highlight.Parent then
			-- Only play fadeOut if it's still the active fadeOut tween
			if highlightData.activeTweens and 
				highlightData.activeTweens.fadeOut == fadeOutTween then
				fadeOutTween:Play()
			end
		end
	end)

	-- Start sequence
	flashTween:Play()
end

-- Transfer highlight to corpse
function PropHealthSystem.transferToCorporse(userId, corpse)
	local highlightData = PropHealthSystem.highlights[userId]
	if not highlightData or not highlightData.highlight then return end

	local highlight = highlightData.highlight

	-- Find the prop model in the corpse
	local propModel = corpse and corpse:FindFirstChild("PropModel")
	if not propModel then return end

	-- Transfer highlight to corpse
	highlight.Adornee = propModel

	-- Cancel any ongoing tweens
	if highlightData.tweening then
		if highlightData.currentTween then
			highlightData.currentTween:Cancel()
		end
		if highlightData.fadeOutTween then
			highlightData.fadeOutTween:Cancel()
		end
	end

	-- Make the highlight visible for the death effect
	highlight.FillTransparency = 0.5  -- Less intense fill (more transparent)
	highlight.OutlineTransparency = 0

	-- Fade out gradually
	local fadeTween = TweenService:Create(highlight,
		TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{
			FillTransparency = 1,
			OutlineTransparency = 1
		}
	)

	fadeTween.Completed:Connect(function()
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
		PropHealthSystem.highlights[userId] = nil
	end)

	fadeTween:Play()
end

-- Remove highlight
function PropHealthSystem.removeHighlight(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local highlightData = PropHealthSystem.highlights[player.UserId]
	if not highlightData then return end

	if highlightData.highlight and highlightData.highlight.Parent then
		highlightData.highlight:Destroy()
	end

	PropHealthSystem.highlights[player.UserId] = nil
end

function PropHealthSystem.pingProp(userId)
	local highlightData = PropHealthSystem.highlights[userId]
	if not highlightData then return end

	local highlight = highlightData.highlight
	if not highlight or not highlight.Parent then return end

	-- Cancel any active tweens to prevent conflicts
	if highlightData.activeTweens then
		for _, tween in pairs(highlightData.activeTweens) do
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween:Cancel()
			end
		end
	end

	-- Initialize/reset tween tracking
	highlightData.activeTweens = highlightData.activeTweens or {}

	-- Save current properties to restore after ping
	local originalFillTransparency = highlight.FillTransparency
	local originalOutlineTransparency = highlight.OutlineTransparency
	local originalDepthMode = highlight.DepthMode

	-- Change to AlwaysOnTop for the ping effect (visible through walls)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

	-- Flash effect - make highlight fully visible
	local flashTween = TweenService:Create(highlight,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			FillTransparency = 0.3, -- More visible than damage highlight
			OutlineTransparency = 0
		}
	)

	-- Store reference to active tween
	highlightData.activeTweens.pingFlash = flashTween

	-- Fade out effect over 3 seconds
	local fadeOutTween = TweenService:Create(highlight,
		TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{
			FillTransparency = originalFillTransparency,
			OutlineTransparency = originalOutlineTransparency
		}
	)

	-- Store reference to active tween
	highlightData.activeTweens.pingFadeOut = fadeOutTween

	-- Sequence the tweens
	flashTween.Completed:Connect(function()
		if highlight and highlight.Parent then
			-- Only play fadeOut if it's still the active fadeOut tween
			if highlightData.activeTweens and 
				highlightData.activeTweens.pingFadeOut == fadeOutTween then
				fadeOutTween:Play()
			end
		end
	end)

	-- When fadeout completes, restore original DepthMode
	fadeOutTween.Completed:Connect(function()
		if highlight and highlight.Parent then
			-- Restore original DepthMode when ping effect is done
			highlight.DepthMode = originalDepthMode
		end
	end)

	-- Start sequence
	flashTween:Play()

	-- Safety fallback - ensure DepthMode gets restored even if tween is interrupted
	task.delay(3.5, function()
		if highlight and highlight.Parent and highlight.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop then
			highlight.DepthMode = originalDepthMode
		end
	end)
end

-- Also modify pingAllProps to remove client RemoteEvent if not implementing client side yet
function PropHealthSystem.pingAllProps()
	-- Print debug info
	print("Pinging all props!")

	-- Go through all tracked highlights and ping them
	for userId, _ in pairs(PropHealthSystem.highlights) do
		PropHealthSystem.pingProp(userId)
	end

	-- Use existing announcement system instead of a new client event
	local RemoteEvent = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")
	RemoteEvent:FireAllClients("RoundAnnouncement", "Prop Ping!")

	-- Uncomment this when client implementation is ready:
	-- RemoteEvent:FireAllClients("PropPingEffect")
end

return PropHealthSystem