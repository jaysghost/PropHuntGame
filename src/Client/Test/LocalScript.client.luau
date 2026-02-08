-- CurrencyClient.lua (LocalScript in StarterPlayerScripts)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

-- Get RemoteEvent
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Create currency UI
local function createCurrencyUI()
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "CurrencyUI"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.Parent = Player.PlayerGui

	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(0, 200, 0, 50)
	Frame.Position = UDim2.new(1, -210, 0, 10)
	Frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	Frame.BorderSizePixel = 0
	Frame.BackgroundTransparency = 0.3
	Frame.Parent = ScreenGui

	local UICorner = Instance.new("UICorner")
	UICorner.CornerRadius = UDim.new(0, 8)
	UICorner.Parent = Frame

	local IconLabel = Instance.new("TextLabel")
	IconLabel.Size = UDim2.new(0, 30, 0, 30)
	IconLabel.Position = UDim2.new(0, 10, 0, 10)
	IconLabel.BackgroundTransparency = 1
	IconLabel.Text = "C$"
	IconLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	IconLabel.TextSize = 20
	IconLabel.Font = Enum.Font.GothamBold
	IconLabel.Parent = Frame

	local CurrencyLabel = Instance.new("TextLabel")
	CurrencyLabel.Name = "CurrencyLabel"
	CurrencyLabel.Size = UDim2.new(1, -50, 1, 0)
	CurrencyLabel.Position = UDim2.new(0, 40, 0, 0)
	CurrencyLabel.BackgroundTransparency = 1
	CurrencyLabel.Text = "Loading..."
	CurrencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	CurrencyLabel.TextSize = 18
	CurrencyLabel.Font = Enum.Font.RobotoMono
	CurrencyLabel.TextXAlignment = Enum.TextXAlignment.Left
	CurrencyLabel.Parent = Frame

	return ScreenGui
end

-- Set up command bar for testing
local function setupCommandBar()
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "CommandBarUI"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.Parent = Player.PlayerGui

	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(0, 300, 0, 40)
	Frame.Position = UDim2.new(0.5, -150, 0, 10)
	Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	Frame.BorderSizePixel = 0
	Frame.BackgroundTransparency = 0.2
	Frame.Visible = false
	Frame.Parent = ScreenGui

	local UICorner = Instance.new("UICorner")
	UICorner.CornerRadius = UDim.new(0, 8)
	UICorner.Parent = Frame

	local TextBox = Instance.new("TextBox")
	TextBox.Size = UDim2.new(1, -20, 1, -10)
	TextBox.Position = UDim2.new(0, 10, 0, 5)
	TextBox.BackgroundTransparency = 1
	TextBox.Text = ""
	TextBox.PlaceholderText = "Type command: /addcredits [amount]"
	TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
	TextBox.TextSize = 14
	TextBox.Font = Enum.Font.Gotham
	TextBox.ClearTextOnFocus = true
	TextBox.Parent = Frame

	-- Toggle command bar with / key
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Slash then
			Frame.Visible = true
			TextBox:CaptureFocus()
		end
	end)

	TextBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local text = TextBox.Text

			-- Process commands
			if text:sub(1, 11) == "/addcredits" then
				local amount = tonumber(text:sub(13)) or 0
				if amount > 0 then
					-- Send request to server to add currency
					RemoteEvent:FireServer("AddCurrency", amount)
				end
			end
		end

		Frame.Visible = false
		TextBox.Text = ""
	end)

	return ScreenGui
end

-- Update currency display
local function updateCurrencyDisplay(amount)
	local currencyUI = Player.PlayerGui:FindFirstChild("CurrencyUI")
	if currencyUI then
		local currencyLabel = currencyUI.Frame.CurrencyLabel
		currencyLabel.Text = tostring(amount)
	end
end

-- Handle RemoteEvent messages
RemoteEvent.OnClientEvent:Connect(function(eventName, ...)
	if eventName == "PlayerDataReady" then
		-- Initial data received
		local currency = ...

		-- Create UIs
		local currencyUI = createCurrencyUI()
		local commandBar = setupCommandBar()

		-- Update currency display
		updateCurrencyDisplay(currency)
		print("Player data ready, currency: " .. currency)

	elseif eventName == "UpdateCurrency" then
		-- Currency update
		local newAmount = ...
		updateCurrencyDisplay(newAmount)
		print("Currency updated: " .. newAmount)

	elseif eventName == "CurrencyResponse" then
		-- Response to a GetCurrency request
		local amount = ...
		updateCurrencyDisplay(amount)
	end
end)

-- Request initial currency after a short delay
task.spawn(function()
	task.wait(1)
	RemoteEvent:FireServer("GetCurrency")
end)

print("Currency Client initialized")