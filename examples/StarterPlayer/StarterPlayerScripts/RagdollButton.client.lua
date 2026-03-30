local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("RagdollMe")

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollTestGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "RagdollMeButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.fromScale(0.98, 0.95)
button.Size = UDim2.fromOffset(180, 56)
button.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
button.BorderSizePixel = 0
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "Ragdoll Me"
button.TextScaled = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Thickness = 2
stroke.Transparency = 0.3
stroke.Parent = button

local inCooldown = false

local function tryToggleRagdoll()
	if inCooldown then
		return
	end

	inCooldown = true
	button.Text = "Toggling..."
	remote:FireServer()

	task.delay(2, function()
		inCooldown = false
		button.Text = "Press R to Toggle"
	end)
end

button.Activated:Connect(function()
	tryToggleRagdoll()
end)

button.Text = "Press R to Toggle"

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		tryToggleRagdoll()
	end
end)
