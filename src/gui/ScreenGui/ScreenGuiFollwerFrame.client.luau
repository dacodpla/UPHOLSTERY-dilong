local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local FollowersFrame = ScreenGui:WaitForChild("FollowersFrame")
local FollowersLabel = FollowersFrame:WaitForChild("Value")

local PlayerData = Player:WaitForChild("PlayerData")
local followers = PlayerData:WaitForChild("followers")

local function formatFollowers(amount)
	local digits    = tostring(math.abs(math.floor(amount)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	formatted       = formatted:gsub("^%.", "")
	if amount < 0 then
		formatted = "-" .. formatted
	end
	return formatted
end

local function updateLabel()
	FollowersLabel.Text = formatFollowers(followers.Value)
end

updateLabel()
followers.Changed:Connect(updateLabel)