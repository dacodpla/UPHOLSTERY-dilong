--[[
	Foam Padding Minigame  (random shapes)
	Interface: Start(container, config) → yields | GetResult() | Cleanup()

	Mechanic:
	  A canvas shows numbered slot outlines. 3 foam pieces (randomly selected
	  from a pool of 6 shapes, with random colors and initial rotations) start
	  on the left side. Drag each piece onto its matching numbered slot; tap
	  the ↻ button to rotate 90°. Pieces snap when their centre is within
	  snapTolerance pixels of the slot centre.

	config = { fragile = bool, toolBonus = number }
	Result = "Fail" | "Pass" | "Good" | "Perfect"
]]

local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local GameConfig       = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX              = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg   = GameConfig.FoamPadding
local mgCfg = GameConfig.Minigame

-- ── Module state ──────────────────────────────────────────────────────────
local _result      = "Pass"
local _connections = {}
local _instances   = {}
local _done        = nil

local function disconnect()
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}
end

-- ── Shape pool ────────────────────────────────────────────────────────────
-- Each shape is { w, h } in canvas scale units (0–1).
local SHAPE_POOL = {
	{ w = 0.36, h = 0.14 },   -- wide flat
	{ w = 0.13, h = 0.34 },   -- tall thin
	{ w = 0.24, h = 0.24 },   -- square
	{ w = 0.42, h = 0.11 },   -- long narrow
	{ w = 0.17, h = 0.28 },   -- medium tall
	{ w = 0.28, h = 0.16 },   -- medium wide
}

local COLOR_POOL = {
	Color3.fromRGB(200, 145, 55),
	Color3.fromRGB(65, 160, 105),
	Color3.fromRGB(75, 115, 205),
	Color3.fromRGB(185, 75, 115),
	Color3.fromRGB(140, 95, 205),
	Color3.fromRGB(195, 125, 55),
}

-- ── Helpers ───────────────────────────────────────────────────────────────

-- Fisher-Yates shuffle (returns a shuffled copy of indices)
local function shuffledIndices(n)
	local idx = {}
	for i = 1, n do idx[i] = i end
	for i = n, 2, -1 do
		local j = math.random(i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	return idx
end

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_PILL_BG   = Color3.fromRGB(0, 0, 0)
local COL_GOLD      = Color3.fromRGB(210, 170, 60)
local COL_WHITE     = Color3.fromRGB(255, 255, 255)
local COL_MUTED     = Color3.fromRGB(160, 150, 170)
local COL_CANVAS    = Color3.fromRGB(30, 22, 44)
local COL_SLOT_BG   = Color3.fromRGB(48, 36, 65)
local COL_SLOT_BRD  = Color3.fromRGB(100, 78, 140)
local COL_SLOT_NUM  = Color3.fromRGB(120, 100, 155)
local COL_SNAP      = Color3.fromRGB(80, 205, 110)
local COL_DANGER    = Color3.fromRGB(220, 80, 80)

-- ── HUD helpers ───────────────────────────────────────────────────────────

local function makePill(parent, w, h, posX, posY, anchorX, anchorY)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, w, 0, h)
	f.Position = UDim2.fromScale(posX, posY)
	f.AnchorPoint = Vector2.new(anchorX or 0, anchorY or 0)
	f.BackgroundColor3 = COL_PILL_BG
	f.BackgroundTransparency = 0.38
	f.BorderSizePixel = 0
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
	table.insert(_instances, f)
	return f
end

local function makeLabel(parent, text, size, color, xAlign)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or COL_WHITE
	l.Font = Enum.Font.GothamBold
	l.TextSize = size or 18
	if xAlign then l.TextXAlignment = xAlign end
	l.Parent = parent
	return l
end

-- ── UI builder ────────────────────────────────────────────────────────────

local function buildUI(container, pieceCount, shapes, colors)
	-- HUD
	local timerPill = makePill(container, 100, 48, 0.03, 0.03, 0, 0)
	local timerLabel = makeLabel(timerPill, "--s", 30, COL_WHITE)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local titlePill = makePill(container, 220, 40, 0.5, 0.03, 0.5, 0)
	makeLabel(titlePill, "PAD THE FOAM", 17, COL_GOLD)

	local progPill = makePill(container, 160, 48, 0.97, 0.03, 1, 0)
	local progressLabel = makeLabel(progPill, "0 / " .. pieceCount .. " placed", 16, COL_GOLD)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Canvas
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.new(0.90, 0, 0.82, 0)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.54)
	canvas.BackgroundColor3 = COL_CANVAS
	canvas.BackgroundTransparency = 0.22
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.Parent = container
	table.insert(_instances, canvas)
	Instance.new("UICorner", canvas).CornerRadius = UDim.new(0, 12)

	local canvasStroke = Instance.new("UIStroke")
	canvasStroke.Color = Color3.fromRGB(70, 52, 100)
	canvasStroke.Thickness = 1.5
	canvasStroke.Transparency = 0.5
	canvasStroke.Parent = canvas

	-- Divider line between staging area and play area
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Position = UDim2.fromScale(0.22, 0)
	divider.BackgroundColor3 = Color3.fromRGB(80, 60, 110)
	divider.BackgroundTransparency = 0.4
	divider.BorderSizePixel = 0
	divider.Parent = canvas

	-- Generate random slot positions in right portion of canvas
	-- Distribute slots so they don't overlap (simple grid in right 70%)
	local slotPositions = {}
	local slotCols = 2
	local slotRows = math.ceil(pieceCount / slotCols)
	local startX = 0.28
	local cellW  = (0.68) / slotCols
	local cellH  = 0.88  / slotRows
	for i = 1, pieceCount do
		local col = ((i - 1) % slotCols)
		local row = math.floor((i - 1) / slotCols)
		local bx  = startX + col * cellW + cellW * 0.5
		local by  = 0.08 + row * cellH + cellH * 0.5
		-- Small random jitter
		local jx = (math.random() - 0.5) * cellW * 0.30
		local jy = (math.random() - 0.5) * cellH * 0.30
		table.insert(slotPositions, {
			x = math.clamp(bx + jx, startX + 0.04, 0.94),
			y = math.clamp(by + jy, 0.08, 0.90),
		})
	end

	-- Slot outlines
	local slots = {}
	for i = 1, pieceCount do
		local sh  = shapes[i]
		local pos = slotPositions[i]
		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(sh.w, 0, sh.h, 0)
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = UDim2.fromScale(pos.x, pos.y)
		slot.BackgroundColor3 = COL_SLOT_BG
		slot.BorderSizePixel = 2
		slot.BorderColor3 = COL_SLOT_BRD
		slot.ZIndex = 1
		slot.Parent = canvas
		Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)

		local slotNum = Instance.new("TextLabel")
		slotNum.Size = UDim2.fromScale(1, 1)
		slotNum.BackgroundTransparency = 1
		slotNum.Text = tostring(i)
		slotNum.TextColor3 = COL_SLOT_NUM
		slotNum.Font = Enum.Font.GothamBold
		slotNum.TextSize = 18
		slotNum.Parent = slot

		table.insert(slots, slot)
		table.insert(_instances, slot)
	end

	-- Foam pieces in staging area (left 22% of canvas)
	local pieces = {}
	local stagingStep = 0.85 / pieceCount
	for i = 1, pieceCount do
		local sh     = shapes[i]
		local col    = colors[i]
		-- Stack pieces vertically in the staging column
		local baseY  = 0.10 + (i - 1) * stagingStep + stagingStep * 0.4
		local startRot = math.random(0, 1) * 90

		local piece = Instance.new("Frame")
		piece.Name = "Piece_" .. i
		piece.Size = UDim2.new(sh.w, 0, sh.h, 0)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.11, baseY)
		piece.Rotation = startRot
		piece.BackgroundColor3 = col
		piece.BorderSizePixel = 2
		piece.BorderColor3 = Color3.fromRGB(20, 14, 32)
		piece.ZIndex = 10 + i
		piece.Parent = canvas
		Instance.new("UICorner", piece).CornerRadius = UDim.new(0, 6)

		-- Number
		local numLbl = Instance.new("TextLabel")
		numLbl.Size = UDim2.fromScale(1, 0.7)
		numLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		numLbl.Position = UDim2.fromScale(0.5, 0.44)
		numLbl.BackgroundTransparency = 1
		numLbl.Text = tostring(i)
		numLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		numLbl.Font = Enum.Font.GothamBold
		numLbl.TextSize = 16
		numLbl.Parent = piece

		-- Rotate button
		local rotBtn = Instance.new("TextButton")
		rotBtn.Name = "RotateBtn"
		rotBtn.Size = UDim2.new(0, 26, 0, 26)
		rotBtn.AnchorPoint = Vector2.new(1, 0)
		rotBtn.Position = UDim2.new(1, -2, 0, 2)
		rotBtn.BackgroundColor3 = Color3.fromRGB(18, 12, 28)
		rotBtn.TextColor3 = COL_GOLD
		rotBtn.Font = Enum.Font.GothamBold
		rotBtn.TextSize = 14
		rotBtn.Text = "↻"
		rotBtn.BorderSizePixel = 0
		rotBtn.ZIndex = piece.ZIndex + 1
		rotBtn.Parent = piece
		Instance.new("UICorner", rotBtn).CornerRadius = UDim.new(0, 4)

		table.insert(pieces, piece)
		table.insert(_instances, piece)
	end

	return canvas, slots, pieces, timerLabel, progressLabel
end

-- ── Public interface ──────────────────────────────────────────────────────

local FoamPadding = {}

function FoamPadding.Start(container, config)
	_result      = "Pass"
	_connections = {}
	_instances   = {}
	_done        = Instance.new("BindableEvent")

	local pieceCount = cfg.pieceCount
	local timeLimit  = cfg.timeLimit
	local snapTol    = cfg.snapTolerance + config.toolBonus * cfg.snapTolerance
	if config.fragile then snapTol = snapTol * mgCfg.fragileMultiplier end

	-- Pick pieceCount random shapes and colors from pools (no repeats)
	local shapeIdx = shuffledIndices(#SHAPE_POOL)
	local colorIdx = shuffledIndices(#COLOR_POOL)
	local shapes = {}
	local colors = {}
	for i = 1, pieceCount do
		table.insert(shapes, SHAPE_POOL[shapeIdx[i]])
		table.insert(colors, COLOR_POOL[colorIdx[i]])
	end

	local canvas, slots, pieces, timerLabel, progressLabel =
		buildUI(container, pieceCount, shapes, colors)

	local snappedCount = 0
	local snapped      = {}
	local finished     = false

	local function updateProgress()
		progressLabel.Text = snappedCount .. " / " .. pieceCount .. " placed"
	end

	local function finishGame()
		if finished then return end
		finished = true
		disconnect()
		local ratio = snappedCount / pieceCount
		if snappedCount == 0 then
			_result = "Fail"
		elseif ratio >= cfg.perfectMinRatio then
			_result = "Perfect"
		elseif ratio >= cfg.goodMinRatio then
			_result = "Good"
		else
			_result = "Pass"
		end
		if _done then _done:Fire() end
	end

	local function trySnap(idx, piece)
		if snapped[idx] then return end
		local slot     = slots[idx]
		local slotAbs  = slot.AbsolutePosition + slot.AbsoluteSize / 2
		local pieceAbs = piece.AbsolutePosition + piece.AbsoluteSize / 2
		if (slotAbs - pieceAbs).Magnitude <= snapTol then
			snapped[idx]       = true
			snappedCount       = snappedCount + 1
			piece.Position     = slot.Position
			piece.Size         = slot.Size
			piece.Rotation     = 0
			piece.BorderColor3 = COL_SNAP
			piece.ZIndex       = 2
			TweenService:Create(piece, TweenInfo.new(0.14, Enum.EasingStyle.Back), {
				BackgroundTransparency = 0.22,
			}):Play()
			updateProgress()
			if snappedCount >= pieceCount then
				task.delay(0.4, finishGame)
			end
		end
	end

	-- Wire drag and rotate for each piece
	for i, piece in ipairs(pieces) do
		local dragOffset = Vector2.zero
		local isDragging = false

		local downConn = piece.InputBegan:Connect(function(input)
			if snapped[i] then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				isDragging = true
				piece.ZIndex = 20 + i
				local mp = UserInputService:GetMouseLocation()
				local pc = piece.AbsolutePosition + piece.AbsoluteSize / 2
				dragOffset = Vector2.new(mp.X - pc.X, mp.Y - pc.Y)
			end
		end)
		table.insert(_connections, downConn)

		local upConn = UserInputService.InputEnded:Connect(function(input)
			if not isDragging then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				isDragging = false
				piece.ZIndex = 10 + i
				trySnap(i, piece)
			end
		end)
		table.insert(_connections, upConn)

		local moveConn = UserInputService.InputChanged:Connect(function(input)
			if not isDragging or snapped[i] then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local mp         = UserInputService:GetMouseLocation()
			local canvasAbs  = canvas.AbsolutePosition
			local canvasSize = canvas.AbsoluteSize
			local sx = math.clamp((mp.X - dragOffset.X - canvasAbs.X) / canvasSize.X, 0.01, 0.99)
			local sy = math.clamp((mp.Y - dragOffset.Y - canvasAbs.Y) / canvasSize.Y, 0.01, 0.99)
			piece.Position = UDim2.fromScale(sx, sy)
		end)
		table.insert(_connections, moveConn)

		local rotBtn = piece:FindFirstChild("RotateBtn")
		if rotBtn then
			local rotConn = rotBtn.Activated:Connect(function()
				if snapped[i] then return end
				TweenService:Create(piece, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
					Rotation = piece.Rotation + 90,
				}):Play()
			end)
			table.insert(_connections, rotConn)
		end
	end

	-- Countdown timer
	task.spawn(function()
		local remaining = timeLimit
		while remaining > 0 and not finished do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = remaining .. "s"
			if remaining <= 8 then
				timerLabel.TextColor3 = COL_DANGER
			end
		end
		if not finished then finishGame() end
	end)

	_done.Event:Wait()
	_done:Destroy()
	_done = nil
end

function FoamPadding.GetResult()
	return _result
end

function FoamPadding.Cleanup()
	disconnect()
	for _, inst in ipairs(_instances) do
		if inst and inst.Parent then inst:Destroy() end
	end
	_instances = {}
	if _done then
		_done:Destroy()
		_done = nil
	end
end

return FoamPadding
