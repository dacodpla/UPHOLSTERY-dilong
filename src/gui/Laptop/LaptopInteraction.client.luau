--[[
	LaptopInteraction
	Handles all Laptop models in Workspace (one per player house).

	Requires:
	  - One or more Models named "Laptop" as direct children of Workspace,
	    each containing a Part named "Screen" (with or without a ProximityPrompt)
	  - A BindableEvent named "LaptopOpened" in PlayerGui
	    → LaptopBrowser listens to this and starts the boot sequence
]]

-- ini create variable

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local EventsFolder = ReplicatedStorage:WaitForChild("Events")

local LaptopGui   = PlayerGui:WaitForChild("LaptopGui", 15)
local openedEvent = EventsFolder:WaitForChild("LaptopOpened", 10)

if not openedEvent then
	warn("[LaptopInteraction] LaptopOpened BindableEvent not found in EventsFolder — laptop UI disabled")
	return
end

-- ── Track all laptop Screen parts for the distance check ─────────────────

local _screenParts = {}  -- list of Screen BaseParts across all Laptop models
local _isOpening   = false  -- debounce: prevent overlapping open requests

local function setupLaptop(laptopModel)
	local screenPart = laptopModel:FindFirstChild("Screen", true)  -- recursive
	if not screenPart or not screenPart:IsA("BasePart") then
		-- Screen hasn't streamed in yet — listen for it
		local conn
		conn = laptopModel.DescendantAdded:Connect(function(desc)
			if desc.Name == "Screen" and desc:IsA("BasePart") then
				conn:Disconnect()
				setupLaptop(laptopModel)
			end
		end)
		return
	end

	table.insert(_screenParts, screenPart)

	local prompt = screenPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.MaxActivationDistance = 4
		prompt.Parent                = screenPart
	end

	-- Ensure consistent prompt settings regardless of what was placed in the model
	prompt.ActionText            = "Use"
	prompt.ObjectText            = "Laptop"
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Exclusivity           = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Style                 = Enum.ProximityPromptStyle.Custom

	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player then return end
		if _isOpening then return end  -- debounce: ignore rapid re-triggers
		_isOpening = true
		openedEvent:Fire()
		-- Keep debounce active for the boot-sequence duration so overlapping
		-- triggers can't start a second boot animation.
		task.delay(2.5, function()
			_isOpening = false
		end)
	end)
end

-- Hook up any Laptop already in Workspace
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "Laptop" then
		setupLaptop(child)
	end
end

-- Also catch Laptops added after this script runs (streaming / late load)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Laptop" then
		setupLaptop(child)
	end
end)

-- ── Suppress all proximity prompts while the laptop UI is open ───────────

LaptopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	ProximityPromptService.Enabled = not LaptopGui.Enabled
end)

-- ── Distance check: close UI if player walks away from ALL laptops ────────

local function isNearAnyLaptop()
	local character = player.Character
	if not character then return true end  -- don't close during respawn
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return true end

	-- Clean up stale references while we iterate
	local i = 1
	while i <= #_screenParts do
		if _screenParts[i].Parent then
			i = i + 1
		else
			table.remove(_screenParts, i)
		end
	end

	for _, screen in ipairs(_screenParts) do
		if (root.Position - screen.Position).Magnitude <= 16 then
			return true
		end
	end
	return false
end

local _lastCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - _lastCheck < 1.5 then return end
	_lastCheck = now

	if LaptopGui and LaptopGui.Enabled and not isNearAnyLaptop() then
		LaptopGui.Enabled = false
	end
end)
