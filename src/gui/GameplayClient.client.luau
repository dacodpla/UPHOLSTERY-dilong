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

local Remotes                = ReplicatedStorage:WaitForChild("LaptopRemotes")
local TeleportToLocation     = Remotes:WaitForChild("TeleportToLocation")
local TeleportToHub          = Remotes:WaitForChild("TeleportToHub")
local LocationFull           = Remotes:WaitForChild("LocationFull")
local SubmitJobResult        = Remotes:WaitForChild("SubmitJobResult")
local AbandonJob             = Remotes:WaitForChild("AbandonJob")
local FurniturePieceRepaired = Remotes:WaitForChild("FurniturePieceRepaired")
local StartMinigame          = Remotes:WaitForChild("StartMinigame")

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

local _pieceResults  = {}   -- [pieceIndex] = result string once that piece is repaired
local _repairedCount = 0    -- how many pieces have been repaired this job
local _totalPieces   = 0    -- total pieces for the current job
local _highlights    = {}   -- Highlight instances indexed by piece number
local _currentJob    = nil  -- job table for the current active assignment
local _multiPiece    = false

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

local function clearAllHighlights()
	for _, hl in ipairs(_highlights) do
		if hl and hl.Parent then hl:Destroy() end
	end
	_highlights = {}
end

-- ── Remote handlers ───────────────────────────────────────────────────────

TeleportToLocation.OnClientEvent:Connect(function(cframe, job, cloneList)
	-- Reset per-job state
	_pieceResults  = {}
	_repairedCount = 0
	_totalPieces   = #(cloneList or {})
	_currentJob    = job
	_multiPiece    = _totalPieces > 1
	clearAllHighlights()
	moveCharacter(cframe)

	if _multiPiece then
		showHUD("📍 " .. (job.name or "?") .. "  |  repair all " .. _totalPieces .. " pieces, then use the door")
	else
		showHUD("📍 " .. (job.name or "?") .. "  |  walk to the furniture to begin")
	end

	-- Highlight every piece (Highlight adorns the Model so it works even before parts replicate)
	for i, clone in ipairs(cloneList or {}) do
		if clone and clone.Parent then
			local hl = Instance.new("Highlight")
			hl.Adornee             = clone
			hl.FillColor           = Color3.fromRGB(255, 210, 60)
			hl.FillTransparency    = 0.75
			hl.OutlineColor        = Color3.fromRGB(255, 210, 60)
			hl.OutlineTransparency = 0
			hl.Parent              = player.PlayerGui
			_highlights[i]         = hl
		end
	end

	-- DoorPrompt is dynamic (added by server) so search after a short replication delay
	local slotModel = cloneList and cloneList[1] and cloneList[1].Parent
	task.spawn(function()
		task.wait(0.5)
		if not slotModel then return end
		for _, desc in ipairs(slotModel:GetDescendants()) do
			if desc:IsA("ProximityPrompt") and desc.Name == "DoorPrompt" then
				desc.Triggered:Connect(function()
					if _repairedCount > 0 then
						local resultList = {}
						for idx = 1, _totalPieces do
							if _pieceResults[idx] then
								table.insert(resultList, _pieceResults[idx])
							end
						end
						local finalResult = #resultList == 1
							and resultList[1]
							or MinigameRunner.CollapseChainResult(resultList)
						SubmitJobResult:FireServer(_currentJob.id, finalResult)
					else
						AbandonJob:FireServer()
					end
					_pieceResults  = {}
					_repairedCount = 0
				end)
				return
			end
		end
		warn("[GameplayClient] DoorPrompt not found after wait — player cannot exit this slot")
	end)
end)

-- Server fires this when a RepairPrompt is triggered (avoids client-side replication race)
StartMinigame.OnClientEvent:Connect(function(pieceIndex)
	if not _currentJob then return end
	if _pieceResults[pieceIndex] ~= nil then return end  -- already repaired

	if _highlights[pieceIndex] then
		_highlights[pieceIndex]:Destroy()
		_highlights[pieceIndex] = nil
	end

	showHUD("🔧 " .. (_currentJob.name or "?") .. "  |  repair in progress...")

	local config = { fragile = false, toolBonus = 0 }
	local result

	if not _multiPiece then
		-- Single piece: run the full minigame chain
		if #_currentJob.minigames > 1 then
			local results = MinigameRunner.RunChain(_currentJob.minigames, config)
			result = MinigameRunner.CollapseChainResult(results)
		else
			result = MinigameRunner.Run(_currentJob.minigames[1], config)
		end
	else
		-- Multi-piece: run just this piece's assigned minigame
		local minigameName = _currentJob.minigames[pieceIndex] or _currentJob.minigames[1]
		result = MinigameRunner.Run(minigameName, config)
	end

	_pieceResults[pieceIndex] = result
	_repairedCount += 1
	FurniturePieceRepaired:FireServer(pieceIndex)

	if _repairedCount >= _totalPieces then
		showHUD("✅ " .. (_currentJob.name or "?") .. "  |  all done!  ·  use the door to leave")
	else
		showHUD("✅ Piece " .. pieceIndex .. " done  ·  " .. (_totalPieces - _repairedCount) .. " left — keep going!")
	end
end)

TeleportToHub.OnClientEvent:Connect(function(cframe)
	clearAllHighlights()
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
