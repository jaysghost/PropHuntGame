--// to be called by client

local Players = game:GetService("Players")
local TS = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenMethods = require(ReplicatedStorage.UIMethods)

local Player = Players.LocalPlayer
local PlayerUI = Players.LocalPlayer.PlayerGui

--local MainUI = PlayerUI.Client.MainUI
local Camera = workspace.CurrentCamera

local Debounces = {}

local ClientMethods = {}

function ClientMethods.RenderPromptHighlight(ThePrompt) --prompt shown
	local HostModel = ThePrompt.Parent.Parent
	local BillboardUI = HostModel.Trigger:FindFirstChild("BillboardGui")
	local ContentUI = HostModel:FindFirstChild("ContentGui")

	-- DYNAMICALLY CREATE highlight
	local Highlight = HostModel:FindFirstChild("HighlightTemp")
	if not Highlight then
		Highlight = Instance.new("Highlight")
		Highlight.Name = "HighlightTemp"

		-- Copy properties from the original highlight if it exists
		local originalHighlight = HostModel:FindFirstChild("Highlight")
		if originalHighlight then
			Highlight.FillColor = originalHighlight.FillColor
			Highlight.OutlineColor = originalHighlight.OutlineColor
			Highlight.DepthMode = originalHighlight.DepthMode
			-- Copy any other properties as needed
		else
			-- Default properties
			Highlight.FillColor = Color3.fromRGB(255, 255, 255)
			Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		end

		-- Start with full transparency
		Highlight.OutlineTransparency = 1
		Highlight.FillTransparency = 1

		Highlight.Parent = HostModel
	end

	-- Tween the highlight
	TweenMethods.CreateTweenAsync(Highlight, TweenMethods.PointOneSecondQuadData, {OutlineTransparency = 0})
	TweenMethods.CreateTweenAsync(Highlight, TweenMethods.PointOneSecondQuadData, {FillTransparency = 0.7})

	-- Handle Billboard UI
	BillboardUI.Holder.Size = UDim2.new(0.1, 0, 0.1, 0)
	BillboardUI.Holder.PressE.ImageTransparency = 1
	wait()
	BillboardUI.Enabled = true

	-- Handle Content UI if it exists
	if ContentUI then
		ContentUI.Enabled = true
		TweenMethods.CreateTweenAsync(ContentUI.Holder.ContentIcon, TweenMethods.ReturnSineData(0.15), {ImageTransparency = 0})
	end

	-- Animate BillboardUI
	TweenMethods.CreateTweenAsync(BillboardUI.Holder, TweenMethods.ReturnSineData(0.15), {Size = UDim2.new(1, 0, 1, 0)})
	TweenMethods.CreateTweenAsync(BillboardUI.Holder.PressE, TweenMethods.ReturnSineData(0.15), {ImageTransparency = 0})
end

function ClientMethods.ClosePromptHighlight(ThePrompt) -- prompt closed
	local HostModel = ThePrompt.Parent.Parent
	local Highlight = HostModel:FindFirstChild("HighlightTemp")
	local BillboardUI = HostModel.Trigger:FindFirstChild("BillboardGui")
	local ContentUI = HostModel:FindFirstChild("ContentGui")

	-- Tween out highlight if it exists
	if Highlight then
		TweenMethods.CreateTweenAsync(Highlight, TweenMethods.PointOneSecondQuadData, {OutlineTransparency = 1})
		TweenMethods.CreateTweenAsync(Highlight, TweenMethods.PointOneSecondQuadData, {FillTransparency = 1})

		-- Destroy highlight after tween completes
		task.delay(0.15, function()
			if Highlight and Highlight.Parent then
				Highlight:Destroy()
			end
		end)
	end

	-- Handle Billboard UI
	TweenMethods.CreateTweenAsync(BillboardUI.Holder, TweenMethods.ReturnSineData(0.15), {Size = UDim2.new(0.1, 0, 0.1, 0)})
	TweenMethods.CreateSyncTween(BillboardUI.Holder.PressE, TweenMethods.ReturnSineData(0.15), {ImageTransparency = 1})

	-- Handle Content UI if it exists
	if ContentUI then
		TweenMethods.CreateSyncTween(ContentUI.Holder.ContentIcon, TweenMethods.ReturnSineData(0.15), {ImageTransparency = 1})
		ContentUI.Enabled = false
	end

	BillboardUI.Enabled = false
end

function ClientMethods.PromptHoldBegan(ThePrompt)
	local HostModel = ThePrompt.Parent.Parent
	local Highlight = HostModel:FindFirstChild("Highlight")
	local BillboardUI = HostModel.Trigger:FindFirstChild("BillboardGui")
	
	BillboardUI.Holder.LoadingBar.BackgroundTransparency = 0
	
	TweenMethods.CreateTweenAsync(BillboardUI.Holder.LoadingBar,TweenMethods.ReturnSineData(ThePrompt.HoldDuration),{Size = UDim2.new(0.5,0,-0.56,0)})
	TweenMethods.CreateTweenAsync(BillboardUI.Holder,TweenMethods.ReturnSineData(.25),{Size = UDim2.new(0.8,0,0.8,0)})
end

function ClientMethods.PromptHoldEnded(ThePrompt)
	local HostModel = ThePrompt.Parent.Parent
	local Highlight = HostModel:FindFirstChild("Highlight")
	local BillboardUI = HostModel.Trigger:FindFirstChild("BillboardGui")
	
	TweenMethods.CreateTweenAsync(BillboardUI.Holder.LoadingBar,TweenMethods.ReturnSineData(1),{Size = UDim2.new(0.5,0,0.12,0)})
	TweenMethods.CreateTweenAsync(BillboardUI.Holder,TweenMethods.ReturnSineData(.25),{Size = UDim2.new(1,0,1,0)})
end

function ClientMethods.PromptTriggered(ThePrompt)
	print('triggered')
	local HostModel = ThePrompt.Parent.Parent
	local Highlight = HostModel:FindFirstChild("Highlight")
	local BillboardUI = HostModel.Trigger:FindFirstChild("BillboardGui")
	local ContentUI = HostModel:FindFirstChild("ContentGui")
	
	TweenMethods.CreateTweenAsync(BillboardUI.Holder.LoadingBar,TweenMethods.ReturnSineData(.25),{BackgroundTransparency = 1})
	TweenMethods.CreateSyncTween(BillboardUI,TweenMethods.ReturnSineData(.25),{Size = UDim2.new(2.4,0,2.4,0)})
	TweenMethods.CreateSyncTween(BillboardUI,TweenMethods.ReturnSineData(.25),{Size = UDim2.new(2,0,2,0)})
end

function ClientMethods.DoorAction(HostPart)
	local Hinge = HostPart.Parent.Hinge
	local Door = HostPart.Parent
	
	if HostPart:GetAttribute("DoorOpen") == true then -- if the door is open
		TweenMethods.CreateTweenAsync(Hinge,TweenMethods.ReturnSineData(1),{CFrame = Hinge.CFrame * CFrame.Angles(2,0,0)})
		Door._DoorOpen:Play()
	elseif HostPart:GetAttribute("DoorOpen") == false then -- if it's closed
		TweenMethods.CreateTweenAsync(Hinge,TweenMethods.ReturnSineData(1),{CFrame = Hinge.CFrame * CFrame.Angles(-2,0,0)})
	end
end


return ClientMethods