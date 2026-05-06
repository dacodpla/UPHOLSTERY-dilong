--[[
	GameplayClient
	Handles everything that happens after a job is accepted:
	  1. TeleportToLocation  → move character, highlight furniture, show HUD
	  2. RepairPrompt        → player walks to furniture and triggers the minigame
	  3. DoorPrompt          → player exits (submits result or abandons)
	  4. TeleportToHub       → move character back to hub, hide HUD
	  5. LocationFull        → show a brief notification toast
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local MinigameRunner = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Minigames")
		:WaitForChild("MinigameRunner")
)

-- ── Remotes ───────────────────────────────────────────────────────────────

local Remotes            = ReplicatedStorage:WaitForChild("LaptopRemotes")
local TeleportToLocation = Remotes:WaitForChild("TeleportToLocation")
local TeleportToHub      = Remotes:WaitForChild("TeleportToHub")
local LocationFull       = Remotes:WaitForChild("LocationFull")
local SubmitJobResult    = Remotes:WaitForChild("SubmitJobResult")
local AbandonJob         = Remotes:WaitForChild("AbandonJob")

-- ── Dev HUD ───────────────────────────────────────────────────────────────

local hudGui = Instance.new("ScreenGui")
hudGui.Name            = "LocationHUD"
hudGui.ResetOnSpawn    = false
hudGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
hudGui.Parent          = player:WaitForChild("PlayerGui")

local hudLabel = Instance.new("TextLabel")
hudLabel.Size                   = UDim2.new(0, 420, 0, 36)
hudLabel.Position               = UDim2.new(0.5, -210, 0, 10)
hudLabel.AnchorPoint            = Vector2.new(0, 0)
hudLabel.BackgroundColor3       = Color3.fromRGB(20, 20, 30)
hudLabel.BackgroundTransparency = 0.25
hudLabel.TextColor3             = Color3.fromRGB(240, 230, 200)
hudLabel.Font                   = Enum.Font.GothamBold
hudLabel.TextSize               = 14
hudLabel.Text                   = ""
hudLabel.Visible                = false
hudLabel.Parent                 = hudGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 8)
hudCorner.Parent       = hudLabel

-- ── State ─────────────────────────────────────────────────────────────────

local _currentResult = nil  -- set after minigame completes; sent to server on door exit
local _jobHighlight  = nil  -- client-side Highlight adorning the furniture clone

-- ── Helpers ───────────────────────────────────────────────────────────────

local function showHUD(text)
	hudLabel.Text    = text
	hudLabel.Visible = true
end

local function hideHUD()
	hudLabel.Visible = false
end

local function moveCharacter(cframe)
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:FindFirstChild("HumanoidRootPart")
		or char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		char:PivotTo(cframe)
	end
end

local function clearHighlight()
	if _jobHighlight then
		_jobHighlight:Destroy()
		_jobHighlight = nil
	end
end

-- ── Remote handlers ───────────────────────────────────────────────────────

TeleportToLocation.OnClientEvent:Connect(function(cframe, job, furnitureClone)
	_currentResult = nil
	clearHighlight()
	moveCharacter(cframe)
	showHUD("📍 " .. (job.name or "?") .. "  |  walk to the furniture to begin")

	-- Highlight the furniture so the player can find it easily (client-side only)
	if furnitureClone and furnitureClone.Parent then
		_jobHighlight = Instance.new("Highlight")
		_jobHighlight.Adornee             = furnitureClone
		_jobHighlight.FillColor           = Color3.fromRGB(255, 210, 60)
		_jobHighlight.FillTransparency    = 0.75
		_jobHighlight.OutlineColor        = Color3.fromRGB(255, 210, 60)
		_jobHighlight.OutlineTransparency = 0
		_jobHighlight.Parent              = player.PlayerGui
	end

	local slotModel = furnitureClone and furnitureClone.Parent

	-- Find the prompts added by LocationManager (replicated from server)
	local repairPrompt, doorPrompt

	if furnitureClone then
		for _, desc in ipairs(furnitureClone:GetDescendants()) do
			if desc:IsA("ProximityPrompt") and desc.Name == "RepairPrompt" then
				repairPrompt = desc
				break
			end
		end
	end

	if slotModel then
		for _, desc in ipairs(slotModel:GetDescendants()) do
			if desc:IsA("ProximityPrompt") and desc.Name == "DoorPrompt" then
				doorPrompt = desc
				break
			end
		end
	end

	-- Player walks to furniture and triggers the minigame
	if repairPrompt then
		repairPrompt.Triggered:Connect(function()
			if _currentResult ~= nil then return end  -- already completed
			repairPrompt.Enabled = false
			clearHighlight()

			showHUD("🔧 " .. (job.name or "?") .. "  |  repair in progress...")

			local config = { fragile = false, toolBonus = 0 }
			local result

			if #job.minigames > 1 then
				local results = MinigameRunner.RunChain(job.minigames, config)
				result = MinigameRunner.CollapseChainResult(results)
			else
				result = MinigameRunner.Run(job.minigames[1], config)
			end

			_currentResult = result
			showHUD("✅ " .. (job.name or "?") .. "  |  " .. tostring(result) .. "  ·  use the door to leave")
		end)
	else
		warn("[GameplayClient] RepairPrompt not found — minigame cannot start")
	end

	-- Player uses the door to finish or abandon
	if doorPrompt then
		doorPrompt.Triggered:Connect(function()
			if _currentResult then
				SubmitJobResult:FireServer(job.id, _currentResult)
			else
				AbandonJob:FireServer()
			end
			_currentResult = nil
			-- TeleportToHub fires from server after LocationManager.Release
		end)
	else
		warn("[GameplayClient] DoorPrompt not found — player cannot exit this slot")
	end
end)

TeleportToHub.OnClientEvent:Connect(function(cframe)
	clearHighlight()
	moveCharacter(cframe)
	task.wait(0.5)
	hideHUD()
end)

LocationFull.OnClientEvent:Connect(function()
	showHUD("⚠️  All client slots are full — try again in a moment")
	task.delay(3, function()
		if not hudLabel.Visible then return end
		hideHUD()
	end)
end)
