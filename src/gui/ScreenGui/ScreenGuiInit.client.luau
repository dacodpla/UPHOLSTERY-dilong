local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local MoneyFrame      = ScreenGui:WaitForChild("MoneyFrame")
local FollowersFrame  = ScreenGui:WaitForChild("FollowersFrame")
local ReputationFrame = ScreenGui:WaitForChild("ReputationFrame")

local laptopOpen = false
local inJob      = false

local function refreshVisibility()
	local show = not laptopOpen and not inJob
	MoneyFrame.Visible      = show
	FollowersFrame.Visible  = show
	ReputationFrame.Visible = show
end

ScreenGui.Enabled = true
refreshVisibility()

-- Laptop: hide HUD whenever the laptop UI is open
local LaptopGui = PlayerGui:WaitForChild("LaptopGui", 15)
if LaptopGui then
	LaptopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		laptopOpen = LaptopGui.Enabled
		refreshVisibility()
	end)
end

-- Job: hide HUD for the entire duration of a job
local Remotes = ReplicatedStorage:WaitForChild("LaptopRemotes")

Remotes:WaitForChild("TeleportToLocation").OnClientEvent:Connect(function()
	inJob      = true
	laptopOpen = false  -- laptop is always closed before a job teleport
	refreshVisibility()
end)

Remotes:WaitForChild("TeleportToHub").OnClientEvent:Connect(function()
	inJob = false
	refreshVisibility()
end)
