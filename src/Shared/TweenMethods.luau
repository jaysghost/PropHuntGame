--// to be called by client


local TS = game:GetService("TweenService")

local TweenMethods = {}



TweenMethods.HalfSecondSineData =  TweenInfo.new(
	0.5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

TweenMethods.PointOneSecondSineData =  TweenInfo.new(
	0.1,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

TweenMethods.FiveSecondSineData = TweenInfo.new(
	5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0


)


TweenMethods.PointOneSecondQuadData = TweenInfo.new(
	0.1,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

TweenMethods.TenSecondSineData = TweenInfo.new(
	10,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

TweenMethods.TwoFiveQuadData = TweenInfo.new(
	.25,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

function TweenMethods.ReturnSineData(timer)
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

function TweenMethods.ReturnQuadData(timer)
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

TweenMethods.FiveSecondBounceData = TweenInfo.new(
	5,
	Enum.EasingStyle.Bounce,
	Enum.EasingDirection.Out,
	0,
	false,
	0
)

function TweenMethods.CreateTweenAsync(instance, data, goals)
	if not instance then return end

	local success, tween = pcall(function()
		return TS:Create(instance, data, goals)
	end)

	if success then
		tween:Play()
	else
		warn("Tween creation failed for", instance:GetFullName())
	end
end


function TweenMethods.CreateSineTween(instance,tweenData,goals) -- synchronous
	local Tween = TS:Create(instance,tweenData,goals)
	Tween:Play()
	Tween.Completed:Wait()
	return true
end

function TweenMethods.CreateSyncTween(instance,tweenData,goals) -- synchronous
	local Tween = TS:Create(instance,tweenData,goals)
	Tween:Play()
	Tween.Completed:Wait()
	return true
end

return TweenMethods

