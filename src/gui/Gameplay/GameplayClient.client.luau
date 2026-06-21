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

local SFX      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))
local ShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))

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
local RequestActiveEffects   = Remotes:WaitForChild("RequestActiveEffects")
local JobRewardNotify        = Remotes:WaitForChild("JobRewardNotify")

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
local _jobStartTime  = nil   -- os.clock() when TeleportToLocation fires
local _pendingReward = nil   -- data from JobRewardNotify; shown after iris opens at hub

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

-- ── Debrief overlay ──────────────────────────────────────────────────────

local DEBRIEF_COLORS = {
	Perfect = Color3.fromRGB(255, 210,  60),
	Good    = Color3.fromRGB( 90, 180, 220),
	Pass    = Color3.fromRGB(160, 140, 120),
	Fail    = Color3.fromRGB(180,  60,  60),
	Abandon = Color3.fromRGB(200, 130,  50),
}

local _debriefGui = Instance.new("ScreenGui")
_debriefGui.Name         = "JobDebrief"
_debriefGui.DisplayOrder = 18
_debriefGui.ResetOnSpawn = false
_debriefGui.Parent       = player:WaitForChild("PlayerGui")

local _debriefCard = nil

local function fmtTime(secs)
	secs = math.max(0, math.floor(secs))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function showDebrief(data, durationSec)
	if _debriefCard then _debriefCard:Destroy(); _debriefCard = nil end

	local col = DEBRIEF_COLORS[data.result] or Color3.fromRGB(200, 200, 200)

	local card = Instance.new("Frame")
	card.Size                   = UDim2.new(0, 320, 0, 10)  -- height grows with rows
	card.AnchorPoint            = Vector2.new(0.5, 0.5)
	card.Position               = UDim2.new(0.5, 0, 0.5, 0)
	card.BackgroundColor3       = Color3.fromRGB(14, 16, 22)
	card.BackgroundTransparency = 1
	card.BorderSizePixel        = 0
	card.Parent                 = _debriefGui
	_debriefCard = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color     = col
	stroke.Thickness = 2
	stroke.Parent    = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder        = Enum.SortOrder.LayoutOrder
	layout.Padding          = UDim.new(0, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 20)
	pad.PaddingRight  = UDim.new(0, 20)
	pad.PaddingTop    = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.Parent = card

	local function row(text, color, size, order, bold)
		local lbl = Instance.new("TextLabel")
		lbl.Size               = UDim2.new(1, 0, 0, size + 6)
		lbl.BackgroundTransparency = 1
		lbl.Text               = text
		lbl.TextColor3         = color or Color3.new(1, 1, 1)
		lbl.Font               = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		lbl.TextSize           = size
		lbl.TextXAlignment     = Enum.TextXAlignment.Left
		lbl.LayoutOrder        = order
		lbl.Parent             = card
		return lbl
	end

	local function divider(order)
		local f = Instance.new("Frame")
		f.Size             = UDim2.new(1, 0, 0, 1)
		f.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
		f.BorderSizePixel  = 0
		f.LayoutOrder      = order
		f.Parent           = card
	end

	-- Result badge
	local resultLabels = {
		Perfect = "✦  PERFECT!",
		Good    = "✓  GOOD",
		Pass    = "✓  PASS",
		Fail    = "✗  FAIL",
		Abandon = "—  ABANDONED",
	}
	row(resultLabels[data.result] or data.result:upper(), col, 22, 1, true)
	row(data.jobName or "?", Color3.fromRGB(200, 200, 200), 13, 2, false)

	divider(3)

	-- Stats: sequential LayoutOrder counter so variable perk rows don't break layout
	local ord = 4

	-- Pay: show base → boosted when perk multiplier applied
	local pay     = data.pay or 0
	local payBonus = data.payBonus or 0
	if payBonus > 0 then
		row(string.format("$%d  base pay", pay - payBonus), Color3.fromRGB(130, 130, 130), 12, ord, false); ord += 1
		row(string.format("$%d  earned  ★", pay), Color3.fromRGB(120, 220, 120), 14, ord, false); ord += 1
	elseif pay > 0 then
		row(string.format("$%d  earned", pay), Color3.fromRGB(120, 220, 120), 14, ord, false); ord += 1
	else
		row("$0  earned", Color3.fromRGB(140, 140, 140), 14, ord, false); ord += 1
	end

	-- Followers: show base → boosted when perk multiplier applied
	local followers = data.followers or 0
	local follBonus = data.followerBonus or 0
	if follBonus > 0 then
		row(string.format("+%d  base followers", followers - follBonus), Color3.fromRGB(130, 130, 130), 12, ord, false); ord += 1
		row(string.format("+%d  followers  ★", followers), Color3.fromRGB(100, 180, 240), 14, ord, false); ord += 1
	else
		local follColor = followers > 0 and Color3.fromRGB(100, 180, 240) or Color3.fromRGB(140, 140, 140)
		row(string.format("+%d  followers", followers), follColor, 14, ord, false); ord += 1
	end

	-- Rep change (already reflects perk repBonus via applyRewards)
	if data.repDelta then
		local repColor = data.repDelta >= 0 and Color3.fromRGB(220, 180, 80) or Color3.fromRGB(200, 100, 100)
		row(string.format("Rep  %+.2f", data.repDelta), repColor, 14, ord, false); ord += 1
	end

	-- Time
	row("⏱  " .. fmtTime(durationSec), Color3.fromRGB(180, 180, 180), 13, ord, false); ord += 1

	-- Active perks with remaining charge status
	if data.perkIds and #data.perkIds > 0 then
		divider(ord); ord += 1
		for _, perkId in ipairs(data.perkIds) do
			local perk      = ShopData.GetById(perkId)
			local perkName  = perk and (perk.name .. " " .. (perk.grade or "")) or perkId
			local remaining = data.perkChargesAfter and data.perkChargesAfter[perkId]
			local chargeText, chargeCol
			if remaining == nil then
				chargeText = perkName
				chargeCol  = Color3.fromRGB(220, 160, 40)
			elseif remaining == 0 then
				chargeText = perkName .. "  DEPLETED"
				chargeCol  = Color3.fromRGB(200, 80, 80)
			else
				chargeText = perkName .. "  ×" .. remaining .. " left"
				chargeCol  = Color3.fromRGB(120, 200, 120)
			end
			row(chargeText, chargeCol, 12, ord, false); ord += 1
		end
	end

	divider(ord); ord += 1

	-- Continue button
	local btn = Instance.new("TextButton")
	btn.Size               = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3   = col
	btn.Text               = "Continue"
	btn.TextColor3         = Color3.fromRGB(10, 10, 15)
	btn.Font               = Enum.Font.GothamBold
	btn.TextSize           = 14
	btn.BorderSizePixel    = 0
	btn.LayoutOrder        = ord
	btn.AutoButtonColor    = true
	btn.Parent             = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	-- Resize card to fit content
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		card.Size = UDim2.new(0, 320, 0, layout.AbsoluteContentSize.Y + 32)
	end)
	card.Size = UDim2.new(0, 320, 0, layout.AbsoluteContentSize.Y + 32)

	-- Fade in
	TweenService:Create(card, TweenInfo.new(0.2), { BackgroundTransparency = 0.08 }):Play()

	btn.Activated:Connect(function()
		if _debriefCard then _debriefCard:Destroy(); _debriefCard = nil end
	end)
end

JobRewardNotify.OnClientEvent:Connect(function(data)
	_pendingReward = data
end)

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
		_jobStartTime  = os.clock()
		_locationName  = locationName and locationName:gsub("(%l)(%u)", "%1 %2") or (job.name or "?")
		_multiPiece    = _totalPieces > 1
		clearAllHighlights()
		_slotModel = cloneList and cloneList[1] and cloneList[1].Parent
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

	local activeEffects = nil
	pcall(function() activeEffects = RequestActiveEffects:InvokeServer() end)
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
	_minigameActive = false

	-- nil result means the minigame was cancelled via the door — don't count this piece
	if result == nil then return end

	_pieceResults[pieceIndex] = result
	_repairedCount += 1
	SFX.Play("FurnitureFixed")
	FurniturePieceRepaired:FireServer(pieceIndex)

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
		-- Show debrief if a reward notification arrived during the job
		if _pendingReward then
			local duration   = _jobStartTime and math.floor(os.clock() - _jobStartTime) or 0
			_jobStartTime    = nil
			local reward     = _pendingReward
			_pendingReward   = nil
			showDebrief(reward, duration)
		end
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
