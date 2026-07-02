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
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local PPS               = game:GetService("ProximityPromptService")

local SFX = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))

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
local GetActiveEffects       = Remotes:WaitForChild("GetActiveEffects")
local BurnPerkCharges        = Remotes:WaitForChild("BurnPerkCharges")

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

-- ── Iris transition ───────────────────────────────────────────────────────

local _irisGui = Instance.new("ScreenGui")
_irisGui.Name           = "IrisTransition"
_irisGui.DisplayOrder   = 20
_irisGui.IgnoreGuiInset = true
_irisGui.ResetOnSpawn   = false
_irisGui.Parent         = player:WaitForChild("PlayerGui")

local _irisFrame = Instance.new("Frame")
_irisFrame.BackgroundColor3      = Color3.new(0, 0, 0)
_irisFrame.BackgroundTransparency = 0
_irisFrame.BorderSizePixel       = 0
_irisFrame.AnchorPoint           = Vector2.new(0.5, 0.5)
_irisFrame.Position              = UDim2.new(0.5, 0, 0.5, 0)
_irisFrame.Size                  = UDim2.fromOffset(0, 0)
_irisFrame.Parent                = _irisGui

local _irisCorner = Instance.new("UICorner")
_irisCorner.CornerRadius = UDim.new(0.5, 0)
_irisCorner.Parent       = _irisFrame

local IRIS_TIME = 0.35

local function irisFullSize()
	local vp = workspace.CurrentCamera.ViewportSize
	local d  = math.ceil(math.sqrt(vp.X ^ 2 + vp.Y ^ 2)) + 4
	return UDim2.fromOffset(d, d)
end

local function irisClose()
	SFX.Play("IrisClose")
	_irisFrame.Size = UDim2.fromOffset(0, 0)
	local t = TweenService:Create(_irisFrame,
		TweenInfo.new(IRIS_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = irisFullSize() })
	t:Play(); t.Completed:Wait()
end

local function irisOpen()
	_irisFrame.Size = irisFullSize()
	local t = TweenService:Create(_irisFrame,
		TweenInfo.new(IRIS_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(0, 0) })
	t:Play(); t.Completed:Wait()
	SFX.Play("IrisOpen")
end

-- ── State ─────────────────────────────────────────────────────────────────

local _pieceResults    = {}   -- [pieceIndex] = result string once that piece is repaired
local _repairedCount   = 0    -- how many pieces have been repaired this job
local _totalPieces     = 0    -- total pieces for the current job
local _highlights      = {}   -- Highlight instances indexed by piece number
local _currentJob      = nil  -- job table for the current active assignment
local _locationName    = "?"  -- display name of the current job location
local _multiPiece      = false
local _minigameActive  = false  -- guard: only one minigame runs at a time
local _firstHubTeleport = true  -- loading screen covers the first arrival; skip irisClose
local _slotModel     = nil   -- parent of cloneList[1]; used for door highlight
local _doorHighlight = nil
local _cloneList     = {}   -- furniture Model refs for the current job (indexed by pieceIndex)

-- ── Helpers ───────────────────────────────────────────────────────────────

local function showHUD(text)
	hudLabel.Text    = text
	hudLabel.Visible = true
end

local function hideHUD()
	hudLabel.Visible = false
end

local function spawnPoof(model)
	local cf, sz
	pcall(function() cf, sz = model:GetBoundingBox() end)
	if not cf then cf = model:GetPivot(); sz = Vector3.new(2, 1, 2) end
	local center  = cf.Position
	local maxDim  = math.max(sz.X, sz.Y, sz.Z)
	local minDim  = math.min(sz.X, sz.Y, sz.Z)
	local rng     = Random.new()

	local COLORS = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(200, 235, 255),
		Color3.fromRGB(255, 235, 160),
		Color3.fromRGB(180, 255, 200),
		Color3.fromRGB(255, 200, 230),
	}

	-- Neon white flash that swells to engulf the whole model then vanishes
	local flash = Instance.new("Part")
	flash.Shape        = Enum.PartType.Ball
	flash.Size         = Vector3.new(minDim * 0.3, minDim * 0.3, minDim * 0.3)
	flash.Anchored     = true
	flash.CanCollide   = false
	flash.CastShadow   = false
	flash.Material     = Enum.Material.Neon
	flash.Color        = Color3.fromRGB(255, 255, 255)
	flash.Transparency = 0.1
	flash.Position     = center
	flash.Parent       = workspace
	TweenService:Create(flash,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(maxDim * 3, maxDim * 3, maxDim * 3), Transparency = 1 }
	):Play()
	task.delay(0.25, function() if flash.Parent then flash:Destroy() end end)

	-- 14 puff balls scattered across the full furniture footprint
	for i = 1, 14 do
		local p = Instance.new("Part")
		p.Shape        = Enum.PartType.Ball
		p.Size         = Vector3.new(minDim * 0.25, minDim * 0.25, minDim * 0.25)
		p.Anchored     = true
		p.CanCollide   = false
		p.CastShadow   = false
		p.Material     = Enum.Material.SmoothPlastic
		p.Color        = COLORS[(i - 1) % #COLORS + 1]
		p.Transparency = 0.05
		p.Position     = center + Vector3.new(
			rng:NextNumber(-sz.X * 0.55, sz.X * 0.55),
			rng:NextNumber(-sz.Y * 0.3,  sz.Y * 0.5),
			rng:NextNumber(-sz.Z * 0.55, sz.Z * 0.55)
		)
		p.Parent = workspace
		local finalSize = maxDim * rng:NextNumber(0.8, 1.1)
		local drift = Vector3.new(
			rng:NextNumber(-sz.X * 0.7, sz.X * 0.7),
			rng:NextNumber(sz.Y * 0.9,  sz.Y * 2.2),
			rng:NextNumber(-sz.Z * 0.7, sz.Z * 0.7)
		)
		TweenService:Create(p,
			TweenInfo.new(rng:NextNumber(0.45, 0.65), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(finalSize, finalSize, finalSize), Transparency = 1, Position = p.Position + drift }
		):Play()
		task.delay(0.7, function() if p.Parent then p:Destroy() end end)
	end
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
	if _doorHighlight then
		_doorHighlight:Destroy()
		_doorHighlight = nil
	end
end

-- ── Remote handlers ───────────────────────────────────────────────────────

TeleportToLocation.OnClientEvent:Connect(function(cframe, job, cloneList, locationName)
	task.spawn(function()
		local laptopGui = player.PlayerGui:FindFirstChild("LaptopGui")
		if laptopGui then laptopGui.Enabled = false end

		irisClose()

		-- Reset per-job state and move while screen is black
		_pieceResults  = {}
		_repairedCount = 0
		_totalPieces   = #(cloneList or {})
		_currentJob    = job
		_locationName  = locationName and locationName:gsub("(%l)(%u)", "%1 %2") or (job.name or "?")
		_multiPiece    = _totalPieces > 1
		clearAllHighlights()
		_slotModel  = cloneList and cloneList[1] and cloneList[1].Parent
		_cloneList  = cloneList or {}
		moveCharacter(cframe)
		RunService.Heartbeat:Wait()

		irisOpen()
		SFX.Play("LocationArrive")
		PPS.MaxPromptsVisible = 1

		-- Now visible: show HUD and highlights
		if _multiPiece then
			showHUD("📍 " .. _locationName .. "  |  repair all " .. _totalPieces .. " pieces, then use the door")
		else
			showHUD("📍 " .. _locationName .. "  |  walk to the furniture to begin")
		end

		-- Highlight every piece (Highlight adorns the Model so it works even before parts replicate)
		for i, clone in ipairs(cloneList or {}) do
			if clone and clone.Parent then
				local hl = Instance.new("Highlight")
				hl.Adornee             = clone
				hl.FillTransparency    = 1
				hl.OutlineColor        = Color3.fromRGB(255, 210, 60)
				hl.OutlineTransparency = 0
				hl.Parent              = player.PlayerGui
				_highlights[i]         = hl
			end
		end

		-- DoorPrompt is dynamic (added by server) so search after a short replication delay.
		-- All DoorPrompts in the slot are connected — supports locations with multiple exits.
		local slotModel = cloneList and cloneList[1] and cloneList[1].Parent
		task.spawn(function()
			task.wait(0.5)
			if not slotModel then return end

			local _doorUsed = false  -- guard: only the first exit trigger fires
			local function onDoorTriggered()
				if _doorUsed then return end
				_doorUsed = true
				-- Cancel any in-progress minigame before exiting
				if MinigameRunner.IsRunning() then
					MinigameRunner.Cancel()
					task.wait()  -- yield so the cancelled coroutine can clean up
				end
				-- Only submit if ALL pieces are repaired; partial completion = abandon
				if _repairedCount >= _totalPieces and _totalPieces > 0 then
					local resultList = {}
					for idx = 1, _totalPieces do
						if _pieceResults[idx] then
							table.insert(resultList, _pieceResults[idx])
						end
					end
					local finalResult = #resultList == 1
						and resultList[1]
						or MinigameRunner.CollapseChainResult(resultList)
					SFX.Play("JobSubmit")
					SubmitJobResult:FireServer(_currentJob.id, finalResult)
				else
					SFX.Play("JobAbandon")
					AbandonJob:FireServer()
				end
				_pieceResults   = {}
				_repairedCount  = 0
				_minigameActive = false
			end

			local found = 0
			for _, desc in ipairs(slotModel:GetDescendants()) do
				if desc:IsA("ProximityPrompt") and desc.Name == "DoorPrompt" then
					desc.Triggered:Connect(onDoorTriggered)
					found += 1
				end
			end
			if found == 0 then
				warn("[GameplayClient] DoorPrompt not found after wait — player cannot exit this slot")
			end
		end)
	end)
end)

-- Server fires this when a RepairPrompt is triggered (avoids client-side replication race)
StartMinigame.OnClientEvent:Connect(function(pieceIndex)
	if not _currentJob then return end
	if _pieceResults[pieceIndex] ~= nil then return end  -- already repaired
	if _minigameActive then return end                   -- another minigame is running
	_minigameActive = true
	PPS.MaxPromptsVisible = 0

	if _highlights[pieceIndex] then
		_highlights[pieceIndex]:Destroy()
		_highlights[pieceIndex] = nil
	end

	showHUD("🔧 " .. _locationName .. "  |  repair in progress...")

	-- Freeze character for the duration of the minigame
	local char     = player.Character
	local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
	local hrp      = char and char:FindFirstChild("HumanoidRootPart")
	local savedWalkSpeed  = humanoid and humanoid.WalkSpeed  or 16
	local savedJumpHeight = humanoid and humanoid.JumpHeight or 7.2
	if humanoid then humanoid.WalkSpeed = 0; humanoid.JumpHeight = 0 end
	if hrp      then hrp.AssemblyLinearVelocity = Vector3.zero end

	-- Determine which minigames will actually run this trigger
	local minigamesToRun
	if not _multiPiece then
		minigamesToRun = _currentJob.minigames
	else
		local mg = _currentJob.minigames[pieceIndex] or _currentJob.minigames[1]
		minigamesToRun = { mg }
	end

	-- Capture perk effects BEFORE burning (pre-burn state = what the player equipped)
	local activeEffects = nil
	local ok, effects = pcall(function() return GetActiveEffects:InvokeServer() end)
	if ok and type(effects) == "table" then activeEffects = effects end
	-- Burn charges only for perks that match the minigames being played
	BurnPerkCharges:FireServer(minigamesToRun)

	local config = {
		fragile       = _currentJob.fragile == true,
		toolBonus     = 0,
		difficulty    = _currentJob.difficulty,
		activeEffects = activeEffects,
	}
	local result

	if not _multiPiece then
		-- Single piece: run the full minigame chain
		if #_currentJob.minigames > 1 then
			local results = MinigameRunner.RunChain(_currentJob.minigames, config)
			result = results and MinigameRunner.CollapseChainResult(results) or nil
		else
			result = MinigameRunner.Run(_currentJob.minigames[1], config)
		end
	else
		-- Multi-piece: run just this piece's assigned minigame
		local minigameName = _currentJob.minigames[pieceIndex] or _currentJob.minigames[1]
		result = MinigameRunner.Run(minigameName, config)
	end

	-- Restore movement
	if humanoid then humanoid.WalkSpeed = savedWalkSpeed; humanoid.JumpHeight = savedJumpHeight end
	PPS.MaxPromptsVisible = 1
	_minigameActive = false

	-- nil result means the minigame was cancelled via the door — don't count this piece
	if result == nil then return end

	_pieceResults[pieceIndex] = result
	_repairedCount += 1
	SFX.Play("FurnitureFixed")
	local poofModel = _cloneList[pieceIndex]
	FurniturePieceRepaired:FireServer(pieceIndex)
	if poofModel and poofModel.Parent then spawnPoof(poofModel) end

	if _repairedCount >= _totalPieces then
		showHUD("✅ " .. _locationName .. "  |  all done!  ·  use the door to leave")
		if _slotModel and not _doorHighlight then
			local doorPart = _slotModel:FindFirstChild("Door", true)
			if doorPart then
				local doorTarget = doorPart:IsA("BasePart") and doorPart
					or doorPart:FindFirstChildWhichIsA("BasePart")
				if doorTarget then
					_doorHighlight = Instance.new("Highlight")
					_doorHighlight.Adornee             = doorTarget.Parent or doorTarget
					_doorHighlight.FillTransparency    = 1
					_doorHighlight.OutlineTransparency = 0
					_doorHighlight.OutlineColor        = Color3.fromRGB(100, 255, 100)
					_doorHighlight.Parent              = player.PlayerGui
				end
			end
		end
	else
		showHUD("✅ Piece " .. pieceIndex .. " done  ·  " .. (_totalPieces - _repairedCount) .. " left — keep going!")
	end
end)

TeleportToHub.OnClientEvent:Connect(function(cframe)
	task.spawn(function()
		PPS.MaxPromptsVisible = 10
		if _firstHubTeleport then
			-- Loading screen is covering everything — skip iris close.
			-- Wait to match LoadingScreen's text-fade before moving the character.
			_firstHubTeleport = false
			task.wait(0.3)
			moveCharacter(cframe)
		else
			irisClose()
			clearAllHighlights()
			moveCharacter(cframe)
			task.wait(0.15)
			irisOpen()
		end
		task.wait(0.5)
		hideHUD()
	end)
end)

LocationFull.OnClientEvent:Connect(function()
	SFX.Play("LocationFull")
	showHUD("⚠️  All client slots are full — try again in a moment")
	task.delay(3, function()
		if not hudLabel.Visible then return end
		hideHUD()
	end)
end)
