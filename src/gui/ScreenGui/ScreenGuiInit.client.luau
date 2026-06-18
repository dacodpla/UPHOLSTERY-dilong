local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local MoneyFrame = ScreenGui:WaitForChild("MoneyFrame")
local FollowersFrame = ScreenGui:WaitForChild("FollowersFrame")

--cuma buat init aja
ScreenGui.Enabled = true
MoneyFrame.Visible = true
FollowersFrame.Visible = true