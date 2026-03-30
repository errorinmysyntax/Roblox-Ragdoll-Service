local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SimpleRagdollService = require(ReplicatedStorage:WaitForChild("SimpleRagdollService"))
local ragdollService = SimpleRagdollService.new()

local remote = ReplicatedStorage:FindFirstChild("RagdollMe")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RagdollMe"
	remote.Parent = ReplicatedStorage
end

local cooldownSeconds = 2
local nextAllowedByPlayer = {}

Players.PlayerRemoving:Connect(function(player)
	nextAllowedByPlayer[player] = nil
end)

remote.OnServerEvent:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	
	local now = os.clock()
	local nextAllowed = nextAllowedByPlayer[player]
	if nextAllowed and now < nextAllowed then
		return
	end
	nextAllowedByPlayer[player] = now + cooldownSeconds
	
	local character = player.Character
	if not character or character.Parent == nil then
		return
	end
	
	ragdollService:Toggle(character)
end)
