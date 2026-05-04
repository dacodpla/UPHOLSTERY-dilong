--[[
	LaptopInteraction
	Detects when the player uses the laptop prop in Workspace and triggers the
	browser UI boot sequence.

	Requires:
	  - A Part (or Model) named "Laptop" in Workspace
	  - A BindableEvent named "LaptopOpened" inside LaptopGui (StarterGui)
	    → LaptopBrowser listens to this event and starts the boot sequence
]]

local Players      = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Wait for LaptopGui and its BindableEvent (created in Studio)
local LaptopGui    = PlayerGui:WaitForChild("LaptopGui", 15)
local openedEvent  = PlayerGui:WaitForChild("LaptopOpened", 10)

-- Wait for the laptop prop in workspace
local laptopModel = workspace:WaitForChild("Laptop", 30)

if not laptopModel or not openedEvent then
	warn("[LaptopInteraction] Missing Laptop prop or LaptopOpened event — laptop UI disabled")
	return
end

-- Find or create the ProximityPrompt on the laptop's Screen part
local screenPart = laptopModel:WaitForChild("Screen", 15)
local prompt = screenPart and screenPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt and screenPart then
	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText  = "Use"
	prompt.ObjectText  = "Laptop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 4
	prompt.Parent = screenPart
end

if not prompt then
	warn("[LaptopInteraction] Could not attach ProximityPrompt to Laptop prop")
	return
end

-- Open laptop on prompt trigger
prompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer ~= player then return end
	openedEvent:Fire()
end)

-- Also close the laptop if the player walks too far away while it's open
-- (optional quality-of-life: prevents floating OS screen)
local function checkDistance()
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local laptopPart = laptopModel:FindFirstChild("Screen", true)

	if laptopPart then
		local dist = (root.Position - laptopPart.Position).Magnitude
		if dist > 14 and LaptopGui.Enabled then
			LaptopGui.Enabled = false
		end
	end
end

-- Throttled distance check using heartbeat
local _lastCheck = 0
game:GetService("RunService").Heartbeat:Connect(function()
	local now = os.clock()
	if now - _lastCheck >= 1.5 then
		_lastCheck = now
		checkDistance()
	end
end)
