local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local FollowersFrame = ScreenGui:WaitForChild("FollowersFrame")
local FollowersLabel = FollowersFrame:WaitForChild("Value")

local PlayerData = Player:WaitForChild("PlayerData")
local followers  = PlayerData:WaitForChild("followers")

local UINotif = require(script.Parent:WaitForChild("UINotif"))
local State   = require(script.Parent:WaitForChild("ScreenGuiState"))

local GREEN = Color3.fromRGB(85, 185, 65)
local RED   = Color3.fromRGB(210, 60, 60)

local function formatFollowers(amount: number): string
	local digits    = tostring(math.abs(math.floor(amount)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	formatted       = formatted:gsub("^%.", "")
	if amount < 0 then formatted = "-" .. formatted end
	return formatted
end

local displayedValue = followers.Value
local targetValue    = displayedValue
local previousValue  = displayedValue
local pendingTarget  = nil

FollowersLabel.Text = formatFollowers(displayedValue)

RunService.Heartbeat:Connect(function(dt: number)
	if math.abs(displayedValue - targetValue) < 0.5 then
		if displayedValue ~= targetValue then
			displayedValue      = targetValue
			FollowersLabel.Text = formatFollowers(targetValue)
		end
		return
	end
	displayedValue      = displayedValue + (targetValue - displayedValue) * math.min(1, dt * 8)
	FollowersLabel.Text = formatFollowers(math.round(displayedValue))
end)

State.FlushEvent.Event:Connect(function()
	if pendingTarget == nil then return end
	local delta    = pendingTarget - displayedValue
	targetValue    = pendingTarget
	pendingTarget  = nil
	if math.abs(delta) >= 0.5 then
		local sign = delta > 0 and "+" or ""
		UINotif.spawn(ScreenGui, FollowersFrame, sign .. formatFollowers(delta), delta > 0 and GREEN or RED)
	end
end)

followers.Changed:Connect(function(newValue: number)
	local delta    = newValue - previousValue
	previousValue  = newValue
	if State.deferred then
		pendingTarget = newValue
	else
		targetValue = newValue
		if delta ~= 0 then
			local sign = delta > 0 and "+" or ""
			UINotif.spawn(ScreenGui, FollowersFrame, sign .. formatFollowers(delta), delta > 0 and GREEN or RED)
		end
	end
end)
