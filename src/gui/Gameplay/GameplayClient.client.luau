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
local UserInputService  = game:GetService("UserInputService")
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
local SubmitJobResult             = Remotes:WaitForChild("SubmitJobResult")
local AbandonJob                  = Remotes:WaitForChild("AbandonJob")
local StartMinigame               = Remotes:WaitForChild("StartMinigame")
local BurnPerkCharges             = Remotes:WaitForChild("BurnPerkCharges")
local SofaStateChanged            = Remotes:WaitForChild("SofaStateChanged")
local ReportPhysicsMinigameResult = Remotes:WaitForChild("ReportPhysicsMinigameResult")
local PhysicsJobGrade             = Remotes:WaitForChild("PhysicsJobGrade")

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

local _pieceResults     = {}   -- [pieceIndex] = result string once that piece is repaired (legacy)
local _repairedCount    = 0    -- how many pieces have been marked Complete by SofaStateChanged
local _totalPieces      = 0    -- total pieces for the current job
local _highlights       = {}   -- Highlight instances indexed by piece number
local _currentJob       = nil  -- job table for the current active assignment
local _locationName     = "?"  -- display name of the current job location
local _multiPiece       = false
local _minigameActive   = false  -- guard: only one minigame runs at a time
local _firstHubTeleport = true   -- loading screen covers the first arrival; skip irisClose
local _slotModel        = nil    -- parent of cloneList[1]; used for door highlight
local _doorHighlight    = nil
local _physicsGrade     = nil    -- grade string received from PhysicsJobGrade; used as final result
local _cloneList          = {}   -- furniture clones for the current job
local _pieceBillboards    = {}   -- [pieceIndex] = BillboardGui floating above each piece
local _hoveredPieceIndex  = nil  -- which piece the mouse is currently over (for billboard visibility)
local _furnitureRayParams = nil  -- RaycastParams that includes only _cloneList descendants

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
	if _doorHighlight then
		_doorHighlight:Destroy()
		_doorHighlight = nil
	end
end

-- ── Piece-state BillboardGuis ─────────────────────────────────────────────
-- Each furniture piece gets a floating label showing what the player needs to do next.
-- Labels appear when the player is within 30 studs and update automatically.

local BILLBOARD_STATE_TEXT = {
	NeedsTacks  = "▸ Remove Tacks",
	NeedsSponge = "▸ Apply Foam",
	NeedsCloth  = "▸ Apply Fabric",
	NeedsFinish = "▸ Stitch / Staple",
	Complete    = "✓ Done",
}
local BILLBOARD_STATE_COLOR = {
	NeedsTacks  = Color3.fromRGB(255, 175, 50),
	NeedsSponge = Color3.fromRGB(255, 175, 50),
	NeedsCloth  = Color3.fromRGB(255, 175, 50),
	NeedsFinish = Color3.fromRGB(255, 175, 50),
	Complete    = Color3.fromRGB(80,  220, 110),
}

local function buildPieceBillboards(cloneList)
	for _, bb in ipairs(_pieceBillboards) do
		if bb and bb.Parent then bb:Destroy() end
	end
	_pieceBillboards    = {}
	_hoveredPieceIndex  = nil

	-- Determine the correct first state from the job's workflow type.
	-- "full" jobs start with tack removal; "half" jobs skip to fabric.
	local initialState = (_currentJob and _currentJob.workflow == "half")
		and "NeedsCloth" or "NeedsTacks"

	-- Build an Include raycast filter so hover-detection only hits furniture.
	local includeList = {}
	for _, clone in ipairs(cloneList or {}) do
		if clone and clone.Parent then table.insert(includeList, clone) end
	end
	if #includeList > 0 then
		_furnitureRayParams = RaycastParams.new()
		_furnitureRayParams.FilterType = Enum.RaycastFilterType.Include
		_furnitureRayParams.FilterDescendantsInstances = includeList
	else
		_furnitureRayParams = nil
	end

	for i, clone in ipairs(cloneList or {}) do
		if clone and clone.Parent then
			local bb = Instance.new("BillboardGui")
			bb.Name        = "PieceState_" .. i
			bb.Adornee     = clone
			bb.Size        = UDim2.new(0, 190, 0, 36)
			bb.StudsOffset = Vector3.new(0, 3.5, 0)
			bb.MaxDistance = 60   -- large distance; Enabled controls visibility
			bb.AlwaysOnTop = false
			bb.Enabled     = false  -- hidden until player hovers this piece
			bb.Parent      = player.PlayerGui

			local bg = Instance.new("Frame")
			bg.Size                   = UDim2.fromScale(1, 1)
			bg.BackgroundColor3       = Color3.fromRGB(10, 8, 18)
			bg.BackgroundTransparency = 0.15
			bg.BorderSizePixel        = 0
			bg.Parent                 = bb
			Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 8)

			local lbl = Instance.new("TextLabel")
			lbl.Name                   = "StateLabel"
			lbl.Size                   = UDim2.fromScale(1, 1)
			lbl.BackgroundTransparency = 1
			lbl.Text                   = BILLBOARD_STATE_TEXT[initialState] or "—"
			lbl.TextColor3             = BILLBOARD_STATE_COLOR[initialState]
				or Color3.fromRGB(255, 175, 50)
			lbl.Font                   = Enum.Font.GothamBold
			lbl.TextSize               = 13
			lbl.Parent                 = bg

			_pieceBillboards[i] = bb
		end
	end
end

local function updatePieceBillboard(pieceIndex, stateName)
	local bb = _pieceBillboards[pieceIndex]
	if not bb then return end
	local lbl = bb:FindFirstChild("StateLabel", true)
	if not lbl then return end
	lbl.Text       = BILLBOARD_STATE_TEXT[stateName]  or stateName
	lbl.TextColor3 = BILLBOARD_STATE_COLOR[stateName] or Color3.fromRGB(200, 190, 170)
	if stateName == "Complete" then
		task.delay(1.5, function()
			if bb and bb.Parent then bb:Destroy() end
		end)
		_pieceBillboards[pieceIndex] = nil
	end
end

-- ── GrabController bridge ─────────────────────────────────────────────────
-- GrabController is a separate LocalScript in the same folder; communicate
-- via a BindableEvent that GrabController creates in PlayerGui.

local function setGrabEnabled(val)
	local bridge = player.PlayerGui:FindFirstChild("GrabControllerBridge")
	if bridge then bridge:Fire(val) end
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
		_physicsGrade  = nil
		_totalPieces   = #(cloneList or {})
		_currentJob    = job
		_locationName  = locationName and locationName:gsub("(%l)(%u)", "%1 %2") or (job.name or "?")
		_multiPiece    = _totalPieces > 1
		clearAllHighlights()
		_cloneList = cloneList or {}
		_slotModel = cloneList and cloneList[1] and cloneList[1].Parent
		buildPieceBillboards(cloneList)
		moveCharacter(cframe)
		RunService.Heartbeat:Wait()

		irisOpen()
		SFX.Play("LocationArrive")
		PPS.MaxPromptsVisible = 1

		-- Now visible: show HUD and highlights
		showHUD("📍 " .. _locationName .. "  |  unpack the toolbox")

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
				-- Only submit if ALL pieces are Complete; partial = abandon
				if _repairedCount >= _totalPieces and _totalPieces > 0 then
					-- Physics workflow: grade comes from server speed measurement.
					-- Fall back to "Pass" if the grade event hasn't arrived yet.
					local finalResult = _physicsGrade or "Pass"
					SFX.Play("JobSubmit")
					SubmitJobResult:FireServer(_currentJob.id, finalResult)
				else
					SFX.Play("JobAbandon")
					AbandonJob:FireServer()
				end
				_pieceResults   = {}
				_repairedCount  = 0
				_physicsGrade   = nil
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

-- Server fires this when a tool drop triggers a GUI minigame (TackRemoval or finish minigame).
-- Args: pieceIndex (number), minigameName (string), params (table — built server-side by SlotPhysicsService).
-- After the run, we report back; state always advances unconditionally.
StartMinigame.OnClientEvent:Connect(function(pieceIndex, minigameName, params)
	if not _currentJob then return end
	if _minigameActive then return end
	_minigameActive = true

	setGrabEnabled(false)
	showHUD("🔧 " .. _locationName .. "  |  repair in progress...")

	local char     = player.Character
	local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
	local hrp      = char and char:FindFirstChild("HumanoidRootPart")
	local savedWalkSpeed  = humanoid and humanoid.WalkSpeed  or 16
	local savedJumpHeight = humanoid and humanoid.JumpHeight or 7.2
	if humanoid then humanoid.WalkSpeed = 0; humanoid.JumpHeight = 0 end
	if hrp      then hrp.AssemblyLinearVelocity = Vector3.zero end

	BurnPerkCharges:FireServer({ minigameName })

	MinigameRunner.Run(minigameName, params or {})

	if humanoid then humanoid.WalkSpeed = savedWalkSpeed; humanoid.JumpHeight = savedJumpHeight end
	setGrabEnabled(true)
	_minigameActive = false

	-- Report result to server regardless of outcome — state advances unconditionally.
	-- SofaStateChanged will arrive shortly and update _repairedCount + checklist HUD.
	ReportPhysicsMinigameResult:FireServer(pieceIndex)
	showHUD("📍 " .. _locationName .. "  |  drop items onto the furniture")
end)

-- ── Physics state updates ──────────────────────────────────────────────────

SofaStateChanged.OnClientEvent:Connect(function(pieceIndex, stateName)
	updatePieceBillboard(pieceIndex, stateName)
	if stateName ~= "Complete" then return end

	_repairedCount += 1
	SFX.Play("FurnitureFixed")
	if _highlights[pieceIndex] then
		_highlights[pieceIndex]:Destroy()
		_highlights[pieceIndex] = nil
	end

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
		showHUD("📍 " .. _locationName .. "  |  " .. (_totalPieces - _repairedCount) .. " piece(s) left")
	end
end)

PhysicsJobGrade.OnClientEvent:Connect(function(grade)
	_physicsGrade = grade
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
		for _, bb in ipairs(_pieceBillboards) do
			if bb and bb.Parent then bb:Destroy() end
		end
		_pieceBillboards    = {}
		_cloneList          = {}
		_hoveredPieceIndex  = nil
		_furnitureRayParams = nil
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

-- ── Furniture hover detection ─────────────────────────────────────────────────
-- Show the piece-state billboard only when the mouse cursor is over that piece.
-- Runs every render frame so the label appears and disappears instantly on hover.

RunService.RenderStepped:Connect(function()
	if not _furnitureRayParams or not _currentJob then
		-- Not in a job — ensure all piece billboards are hidden.
		if _hoveredPieceIndex then
			_hoveredPieceIndex = nil
			for _, bb in ipairs(_pieceBillboards) do
				if bb and bb.Parent then bb.Enabled = false end
			end
		end
		return
	end

	local camera   = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	local result   = workspace:Raycast(ray.Origin, ray.Direction.Unit * 80, _furnitureRayParams)

	local hitIndex = nil
	if result then
		for i, clone in ipairs(_cloneList) do
			if clone and clone.Parent and result.Instance:IsDescendantOf(clone) then
				hitIndex = i
				break
			end
		end
	end

	if hitIndex ~= _hoveredPieceIndex then
		_hoveredPieceIndex = hitIndex
		for i, bb in ipairs(_pieceBillboards) do
			if bb and bb.Parent then
				bb.Enabled = (i == hitIndex)
			end
		end
	end
end)
