local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")

local ReputationFrame = ScreenGui:WaitForChild("ReputationFrame")
local FullFrame       = ReputationFrame:WaitForChild("FullFrame")
local FullStar        = FullFrame:WaitForChild("FullStar")

local PlayerData = Player:WaitForChild("PlayerData")
local reputation = PlayerData:WaitForChild("reputation")

local UINotif = require(script.Parent:WaitForChild("UINotif"))

local GREEN   = Color3.fromRGB(85, 185, 65)
local RED     = Color3.fromRGB(210, 60, 60)
local MAX_REP = 5

local gradient = FullStar:FindFirstChildWhichIsA("UIGradient")
if not gradient then
	gradient = Instance.new("UIGradient")
	gradient.Parent = FullStar
end

local function buildTransparency(ratio: number): NumberSequence
	if ratio <= 0.001 then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	if ratio >= 0.999 then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(ratio - 0.001, 0),
		NumberSequenceKeypoint.new(ratio, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local displayedRatio = math.clamp(reputation.Value / MAX_REP, 0, 1)
local targetRatio    = displayedRatio
local previousRep    = reputation.Value

gradient.Transparency = buildTransparency(displayedRatio)

RunService.Heartbeat:Connect(function(dt: number)
	if math.abs(displayedRatio - targetRatio) < 0.0005 then
		return
	end
	displayedRatio        = displayedRatio + (targetRatio - displayedRatio) * math.min(1, dt * 8)
	gradient.Transparency = buildTransparency(displayedRatio)
end)

reputation.Changed:Connect(function(rep: number)
	local delta  = rep - previousRep
	previousRep  = rep
	targetRatio  = math.clamp(rep / MAX_REP, 0, 1)

	if math.abs(delta) >= 0.001 then
		local text = string.format("%+.2f", delta)
		UINotif.spawn(ScreenGui, ReputationFrame, text, delta > 0 and GREEN or RED)
	end
end)
