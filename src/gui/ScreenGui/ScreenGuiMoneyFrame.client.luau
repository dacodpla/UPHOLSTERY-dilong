local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local MoneyFrame = ScreenGui:WaitForChild("MoneyFrame")
local MoneyLabel = MoneyFrame:WaitForChild("Value")

local PlayerData = Player:WaitForChild("PlayerData")
local usd        = PlayerData:WaitForChild("usd")

local function formatMoney(amount)
	local digits    = tostring(math.abs(math.floor(amount)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	formatted       = formatted:gsub("^%.", "")
	if amount < 0 then
		formatted = "-" .. formatted
	end
	return formatted
end

local function updateLabel()
	MoneyLabel.Text = formatMoney(usd.Value)
end

updateLabel()
usd.Changed:Connect(updateLabel)