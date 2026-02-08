--// to be called by client

local Players = game:GetService("Players")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
--local UISounds = SoundService.UI


local Player = Players.LocalPlayer
local PlayerUI = Players.LocalPlayer.PlayerGui

--local DifferentFrames = PlayerUI.Client.DifferentFrames
--local MainUI = PlayerUI.Client.MainUI
local Camera = workspace.CurrentCamera

local ConnectionTable = {
	["HoveringLeave"] = false
}

local UIMethods = {}

--[[task.spawn(function()
	while task.wait(5) do
		local RandomDifNumber = math.random(-25,25)
		print('doin it')
		UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.UIGradient,UIMethods.ReturnSineData(3),{Rotation = DifferentFrames.PlayerQueueFrame.UIGradient.Rotation + RandomDifNumber})
	end
end)--]]

--[[task.spawn(function()
	while task.wait(5) do
		local NewSequence = ColorSequence.new{
			ColorSequenceKeypoint.new(0,Color3.fromRGB(math.random(0,255),math.random(0,255),math.random(0,255))),
			ColorSequenceKeypoint.new(0.5,Color3.fromRGB(math.random(0,255),math.random(0,255),math.random(0,255))),
			ColorSequenceKeypoint.new(1,Color3.fromRGB(math.random(0,255),math.random(0,255),math.random(0,255)))}
		local RandomColorSequence
		print('doin it')
		UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.UIGradient,UIMethods.ReturnSineData(3),{Color = NewSequence})
	end
end)--]]


UIMethods.HalfSecondSineData =  TweenInfo.new(
	0.5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

UIMethods.PointOneSecondSineData =  TweenInfo.new(
	0.1,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

UIMethods.FiveSecondSineData = TweenInfo.new(
	5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
	
	
)


UIMethods.PointOneSecondQuadData = TweenInfo.new(
	0.1,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

UIMethods.TenSecondSineData = TweenInfo.new(
	10,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

UIMethods.TwoFiveQuadData = TweenInfo.new(
	.25,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

function UIMethods.ReturnSineData(timer)
	local Data = TweenInfo.new(
		timer,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out,
		0,
		false,
		0
	)
	
	return Data
end

function UIMethods.ReturnQuadData(timer)
	local Data = TweenInfo.new(
		timer,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out,
		0,
		false,
		0
	)

	return Data
end

UIMethods.FiveSecondBounceData = TweenInfo.new(
	5,
	Enum.EasingStyle.Bounce,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

function UIMethods.CreateTweenAsync(instance,data,goals) -- asynchronous
	local Tween = TS:Create(instance,data,goals)
	Tween:Play()
end

function UIMethods.TransitionTween(WaitTime) -- Method takes in a waiting time inbetween on/off
	
	local success, err = pcall(function()
		local TransitionTweenOn = TS:Create(DifferentFrames.BlackTransition,UIMethods.HalfSecondSineData,{BackgroundTransparency = 0})
		local TransitionTweenOff = TS:Create(DifferentFrames.BlackTransition,UIMethods.HalfSecondSineData,{BackgroundTransparency = 1})
	
		TransitionTweenOn:Play()
	
		TransitionTweenOn.Completed:Wait()
		wait(WaitTime)
		TransitionTweenOff:Play()
		TransitionTweenOff.Completed:Wait()
	end)
	if err then
		warn(err)
	end
	return true
end

function UIMethods.CreateSineTween(instance,tweenData,goals) -- synchronous
	local Tween = TS:Create(instance,tweenData,goals)
	Tween:Play()
	Tween.Completed:Wait()
	return true
end

function UIMethods.CreateSyncTween(instance,tweenData,goals) -- synchronous
	local Tween = TS:Create(instance,tweenData,goals)
	Tween:Play()
	Tween.Completed:Wait()
	return true
end

 --[[ function UIMethods.RaisePlayerUI(PlrTable) -- raises UI, adds all current plrs
	print('raising')
	
	local QueuePlayers = RemoteFunctions.RetrieveQueue:InvokeServer()
	
	for i,Player in pairs(QueuePlayers) do
		for i,VPModel in pairs(ReplicatedStorage.VPModels:GetChildren()) do
			if VPModel.Name == Player.Name then
				UIMethods.AddViewport(VPModel,PlrTable)
			end
		end
	end
	
	local currentPos = UDim2.new(0.5,0,0.4,0)
	
	DifferentFrames.PlayerQueueFrame.Holder.Position -= UDim2.new(0,0,.1,0)
	wait()
	
	local difPos = DifferentFrames.PlayerQueueFrame.Holder.Position
	
	for i,v in pairs(DifferentFrames.PlayerQueueFrame.Holder:GetChildren()) do
		if v:IsA("TextButton") or v:IsA("TextLabel") then
			v.TextTransparency = 1
		elseif v:IsA("ImageLabel") then
			v.ImageTransparency = 1
		elseif v:IsA("Frame") then
			v.BackgroundTransparency = 1
		end
	end
	
	DifferentFrames.PlayerQueueFrame.Visible = true
	
	UIMethods.CreateTweenAsync(Lighting.Blur,UIMethods.PointOneSecondQuadData,{Size = 12})
	UIMethods.CreateTweenAsync(Camera,UIMethods.HalfSecondSineData,{FieldOfView = 50})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame,UIMethods.HalfSecondSineData,{BackgroundTransparency = 0.5})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.HalfSecondSineData,{BackgroundTransparency = 0, TextTransparency = 0, Active = true})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder,UIMethods.HalfSecondSineData,{Position = currentPos})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.Title,UIMethods.PointOneSecondQuadData,{TextTransparency = 0})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.SubTitle,UIMethods.PointOneSecondQuadData,{TextTransparency = 0})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes,UIMethods.PointOneSecondQuadData,{ImageTransparency = 0.8})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes,UIMethods.PointOneSecondQuadData,{BackgroundTransparency = 0.5})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes.UIStroke,UIMethods.PointOneSecondQuadData,{Transparency = 0.6})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.glow,UIMethods.PointOneSecondQuadData,{ImageTransparency = 0.9})
	
	
	DifferentFrames.PlayerQueueFrame.Holder.LeaveButton.MouseEnter:Connect(function()
		if ConnectionTable["HoveringLeave"] == false then
			ConnectionTable["HoveringLeave"] = true
			UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.PointOneSecondQuadData,{Size = UDim2.new(1.3,0,0.13,0)})
			UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.PointOneSecondQuadData,{BackgroundColor3 = Color3.fromRGB(255, 33, 33)})
			ConnectionTable["HoveringLeave"] = false
		end
	end)
		
	DifferentFrames.PlayerQueueFrame.Holder.LeaveButton.MouseLeave:Connect(function()
		UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.PointOneSecondQuadData,{Size = UDim2.new(1,0,0.13,0)})
		UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.PointOneSecondQuadData,{BackgroundColor3 = Color3.fromRGB(255, 101, 101)})
	end)

	DifferentFrames.PlayerQueueFrame.Holder.LeaveButton.MouseButton1Click:Connect(function()
		UISounds._PlayerLeft:Play()
		RemoteEvents.Queue.LeaveQueue:FireServer()
		UIMethods.ClosePlayerUI()
	end)

	
	ConnectionTable["BounceQueueUI"] = true
	--UIMethods.BounceQueueUI(difPos,currentPos)
	
	
	--RS:BindToRenderStep("BOUNCE",Enum.RenderPriority.First.Value,TweenMethods.BounceQueueUI(difPos,currentPos))
	
end --]]

function UIMethods.ClosePlayerUI()
	
	local difPos = DifferentFrames.PlayerQueueFrame.Holder.Position + UDim2.new(0,0,.05,0)
	
	ConnectionTable["BounceQueueUI"] = false
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame,UIMethods.HalfSecondSineData,{BackgroundTransparency = 1})
	UIMethods.CreateTweenAsync(Lighting.Blur,UIMethods.PointOneSecondQuadData,{Size = 0})
	UIMethods.CreateTweenAsync(Camera,UIMethods.HalfSecondSineData,{FieldOfView = 70})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.LeaveButton,UIMethods.HalfSecondSineData,{BackgroundTransparency = 1, TextTransparency = 1, Active = false})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder,UIMethods.HalfSecondSineData,{Position = difPos})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.Title,UIMethods.PointOneSecondQuadData,{TextTransparency = 1})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.SubTitle,UIMethods.PointOneSecondQuadData,{TextTransparency = 1})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes,UIMethods.PointOneSecondQuadData,{ImageTransparency = 1})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes,UIMethods.PointOneSecondQuadData,{BackgroundTransparency = 1})
	UIMethods.CreateTweenAsync(DifferentFrames.PlayerQueueFrame.Holder.stripes.UIStroke,UIMethods.PointOneSecondQuadData,{Transparency = 1})
	UIMethods.CreateSyncTween(DifferentFrames.PlayerQueueFrame.Holder.glow,UIMethods.PointOneSecondQuadData,{ImageTransparency = 1})
	
	DifferentFrames.PlayerQueueFrame.Visible = true
	
	for i,v in pairs(DifferentFrames.PlayerQueueFrame.Holder.PlayerList:GetChildren()) do
		if v:IsA("Frame") then
			v:Destroy()
		end
	end
end

function UIMethods.AddViewport(model) -- adds latest player to queue UI

	
	local NewIconTemplate = PlayerUI.Templates.IconTemplate:Clone()
	
	NewIconTemplate.ViewportFrame.ImageTransparency = 1
	NewIconTemplate.BackgroundTransparency = 1
	
	NewIconTemplate.Parent = PlayerList
	NewIconTemplate.Name = tostring(model:GetAttribute("Name"))
	NewIconTemplate.PlayerInfoHolder.PlayerNameLabel.Text = NewIconTemplate.Name
	
	local NewViewportFrame = NewIconTemplate.ViewportFrame
	local NewWorldModel = Instance.new("WorldModel")
	NewWorldModel.Parent = NewViewportFrame
	
	local ViewportModel = model:Clone()
	
	ViewportModel.Parent = NewWorldModel
	local ViewportCamera = Instance.new("Camera")
	ViewportCamera.FieldOfView = 25
	ViewportCamera.CFrame = CFrame.new((ViewportModel.Head.CFrame * CFrame.new(0,0,-5)).Position + Vector3.new(3,0,0), ViewportModel.Head.Position)
	NewViewportFrame.CurrentCamera = ViewportCamera
	
	print(NewIconTemplate.Name.. 'has been created')
	
	UIMethods.CreateTweenAsync(NewIconTemplate,UIMethods.HalfSecondSineData,{BackgroundTransparency = 0})
	UIMethods.CreateTweenAsync(NewIconTemplate.ViewportFrame,UIMethods.HalfSecondSineData,{ImageTransparency = 0})
	
end

function UIMethods.RemoveViewport(plr,PlrTable)
	local IconTable = PlayerUI.Client.DifferentFrames.PlayerQueueFrame.Holder.PlayerList
	local Arrow = IconTable.Parent.Arrow
	
	Arrow.Position = UDim2.new(1.2,0,-0.262,0)
	Arrow.ImageTransparency = 0
	Arrow.Image = ReplicatedStorage.Assets.Decals._DownArrow.Texture
	
	for i,PlayerFrame in pairs(IconTable:GetChildren()) do
		if PlayerFrame.Name == plr.Name then
			PlayerFrame:Destroy()
			UIMethods.CreateTweenAsync(Arrow,UIMethods.HalfSecondSineData,{Position = Arrow.Position + UDim2.new(0,0,0.100,0),ImageTransparency = 1})
			PlayerUI.Client.DifferentFrames.PlayerQueueFrame.Holder.SubTitle.Text = tostring(#PlrTable).."/12"
		end
	end
end

function UIMethods.BounceQueueUI(difPos,currentPos) -- bouncing animation
	if difPos == nil then print('not here') return end

	UIMethods.CreateSyncTween(DifferentFrames.PlayerQueueFrame.Holder,UIMethods.FiveSecondSineData,{Position = difPos})
	UIMethods.CreateSyncTween(DifferentFrames.PlayerQueueFrame.Holder,UIMethods.FiveSecondSineData,{Position = currentPos})
	
	if ConnectionTable["BounceQueueUI"] == true then
	UIMethods.BounceQueueUI(difPos,currentPos)
	else
		return
	end
end


return UIMethods

