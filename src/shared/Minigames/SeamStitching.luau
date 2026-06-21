--[[
	Seam Stitching Minigame
	Interface: Start(container, config) → yields | GetResult() | Cleanup()

	Mechanic:
	  A dotted zig-zag path is drawn across fabric. Drag the needle from the
	  green start marker to the red end marker, following the path as closely
	  as possible. The needle tracks your cursor freely — no snap-back.
	  A colored trail shows where you've been (green = on path, red = off).
	  A meter on the right fills as your total inaccuracy adds up over the run;
	  if it reaches the limit the run fails — a single far-off moment is fine as
	  long as the accumulated error stays under budget.
	  Reach each segment's endpoint to advance. Segment count and waypoints
	  are randomly generated each run.

	config = { fragile = bool, toolBonus = number }
	Result = "Fail" | "Pass" | "Good" | "Perfect"
]]

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local GameConfig       = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX              = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg   = GameConfig.SeamStitching
local mgCfg = GameConfig.Minigame

-- ── Module state ──────────────────────────────────────────────────────────
local _result      = "Pass"
local _connections = {}
local _instances   = {}
local _trail       = {}
local _done        = nil
local _finished    = false

local function disconnect()
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}
end

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_GOLD      = Color3.fromRGB(210, 170, 60)
local COL_WHITE     = Color3.fromRGB(255, 255, 255)
local COL_WARN      = Color3.fromRGB(230, 170, 50)
local COL_HUD_BG    = Color3.fromRGB(20, 16, 30)
local COL_MUTED     = Color3.fromRGB(160, 150, 170)
local COL_CANVAS    = Color3.fromRGB(55, 32, 44)
local COL_DOT       = Color3.fromRGB(220, 185, 110)
local COL_DOT_DIM   = Color3.fromRGB(160, 130, 70)
local COL_START     = Color3.fromRGB(80, 220, 120)
local COL_END_MK    = Color3.fromRGB(220, 80, 80)
local COL_NEEDLE    = Color3.fromRGB(235, 230, 220)
local COL_THREAD    = Color3.fromRGB(120, 75, 200)
local COL_TRAIL_OK  = Color3.fromRGB(70, 210, 110)
local COL_TRAIL_BAD = Color3.fromRGB(210, 70, 70)
local COL_METER_OK  = Color3.fromRGB(70, 200, 100)
local COL_METER_BAD = Color3.fromRGB(210, 70, 70)
local COL_DANGER    = Color3.fromRGB(220, 80, 80)


-- ── Path generation ───────────────────────────────────────────────────────
-- Picks one of several path "models" at random so every run feels unique:
-- zig-zag, smooth wave, chaotic random walk, or a stair-step. All run left to
-- right across the full canvas width.

local START_X = 0.06
local SPAN_X  = 0.88
local MIN_Y   = 0.10
local MAX_Y   = 0.88

local function segsFromWaypoints(waypoints)
	local segs = {}
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		table.insert(segs, { a.x, a.y, b.x, b.y })
	end
	return segs
end

local function generatePath(segCount)
	local style   = math.random(1, 4)
	local startY  = math.random() * 0.28 + 0.36  -- start in middle third
	local waypoints = { { x = START_X, y = startY } }
	local stepX   = SPAN_X / segCount

	if style == 1 then
		-- Alternating zig-zag (sharp swings, classic seam)
		local prevY    = startY
		local firstDir = math.random() < 0.5 and 1 or -1
		for i = 1, segCount do
			local dir   = (i % 2 == 0) and firstDir or -firstDir
			local amp   = math.random() * 0.22 + 0.18  -- 0.18–0.40
			local nextY = math.clamp(prevY + dir * amp, MIN_Y, MAX_Y)
			table.insert(waypoints, { x = START_X + i * stepX, y = nextY })
			prevY = nextY
		end

	elseif style == 2 then
		-- Smooth sine wave (flowing curve)
		local phase = math.random() * math.pi * 2
		local freq  = math.random() * 1.5 + 1.5
		local amp   = math.random() * 0.18 + 0.20
		local midY  = math.clamp(startY, 0.30, 0.55)
		for i = 1, segCount do
			local nextY = math.clamp(
				midY + math.sin(phase + (i / segCount) * math.pi * freq) * amp,
				MIN_Y, MAX_Y)
			table.insert(waypoints, { x = START_X + i * stepX, y = nextY })
		end

	elseif style == 3 then
		-- Chaotic random walk (unpredictable jitter)
		local prevY = startY
		for i = 1, segCount do
			local delta = (math.random() - 0.5) * 0.5
			local nextY = math.clamp(prevY + delta, MIN_Y, MAX_Y)
			table.insert(waypoints, { x = START_X + i * stepX, y = nextY })
			prevY = nextY
		end

	else
		-- Stair-step (long glides then sudden jumps, bounces off edges)
		local prevY = startY
		local dir   = math.random() < 0.5 and 1 or -1
		for i = 1, segCount do
			local amp   = (i % 2 == 0) and (math.random() * 0.10 + 0.05)
				or (math.random() * 0.25 + 0.20)
			local nextY = math.clamp(prevY + dir * amp, MIN_Y, MAX_Y)
			if nextY <= MIN_Y or nextY >= MAX_Y then dir = -dir end
			table.insert(waypoints, { x = START_X + i * stepX, y = nextY })
			prevY = nextY
		end
	end

	return segsFromWaypoints(waypoints)
end

-- csx/csy are canvas pixel dimensions so projection and distance are in true pixel space.
-- The canvas is wider than it is tall, so scale-space geometry would distort both the
-- "closest point" projection (wrong t) and the returned distance (wrong magnitude).
local function closestPointOnSegment(ax, ay, bx, by, px, py, csx, csy)
	local dx = (bx - ax) * csx
	local dy = (by - ay) * csy
	local qx = (px - ax) * csx
	local qy = (py - ay) * csy
	local lenSq = dx * dx + dy * dy
	if lenSq < 1e-9 then return ax, ay, math.sqrt(qx*qx + qy*qy), 0 end
	local t  = math.clamp((qx*dx + qy*dy) / lenSq, 0, 1)
	local cx = ax + t * (bx - ax)
	local cy = ay + t * (by - ay)
	local ex = (px - cx) * csx
	local ey = (py - cy) * csy
	return cx, cy, math.sqrt(ex*ex + ey*ey), t
end

-- ── Trail management ──────────────────────────────────────────────────────

local function addTrailDot(canvas, sx, sy, good)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 5, 0, 5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(sx, sy)
	dot.BackgroundColor3 = good and COL_TRAIL_OK or COL_TRAIL_BAD
	dot.BackgroundTransparency = 0.1
	dot.BorderSizePixel = 0
	dot.ZIndex = 3
	dot.Parent = canvas
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	table.insert(_instances, dot)
	table.insert(_trail, dot)

	while #_trail > cfg.trailLength do
		local old = table.remove(_trail, 1)
		if old and old.Parent then old:Destroy() end
	end
end

-- ── Deviation meter ───────────────────────────────────────────────────────

local function buildDeviationMeter(parent)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(0, 12, 0.62, 0)
	bg.AnchorPoint = Vector2.new(0, 0.5)
	bg.Position = UDim2.fromScale(0.95, 0.5)
	bg.BackgroundColor3 = Color3.fromRGB(28, 18, 38)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.ZIndex = 10
	bg.ClipsDescendants = true
	bg.Parent = parent
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)
	table.insert(_instances, bg)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 0)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COL_METER_OK
	fill.BorderSizePixel = 0
	fill.ZIndex = 11
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 30, 0, 16)
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0, -4)
	lbl.BackgroundTransparency = 1
	lbl.Text = "DEV"
	lbl.TextColor3 = COL_MUTED
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 9
	lbl.Parent = bg

	return fill
end

-- ── UI builder ────────────────────────────────────────────────────────────

local function buildUI(container, pathSegments, segCount)
	-- Compact centered HUD pill
	local hudBar = Instance.new("Frame")
	hudBar.Size                   = UDim2.new(0.62, 0, 0, 40)
	hudBar.AnchorPoint            = Vector2.new(0.5, 0)
	hudBar.Position               = UDim2.new(0.5, 0, 0, 140)
	hudBar.BackgroundColor3       = COL_HUD_BG
	hudBar.BackgroundTransparency = 0.18
	hudBar.BorderSizePixel        = 0
	hudBar.Parent                 = container
	table.insert(_instances, hudBar)
	Instance.new("UICorner", hudBar).CornerRadius = UDim.new(0, 10)

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size                   = UDim2.new(0, 48, 1, 0)
	timerLabel.Position               = UDim2.new(0, 10, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text                   = "--"
	timerLabel.TextColor3             = COL_WHITE
	timerLabel.Font                   = Enum.Font.GothamBold
	timerLabel.TextSize               = 19
	timerLabel.TextXAlignment         = Enum.TextXAlignment.Center
	timerLabel.Parent                 = hudBar

	local timerTrack = Instance.new("Frame")
	timerTrack.Size               = UDim2.new(1, -142, 0, 7)
	timerTrack.Position           = UDim2.new(0, 66, 0.5, -3)
	timerTrack.BackgroundColor3   = Color3.fromRGB(45, 40, 60)
	timerTrack.BackgroundTransparency = 0
	timerTrack.BorderSizePixel    = 0
	timerTrack.Parent             = hudBar
	Instance.new("UICorner", timerTrack).CornerRadius = UDim.new(0, 3)

	local timerBar = Instance.new("Frame")
	timerBar.Size               = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3   = COL_WHITE
	timerBar.BorderSizePixel    = 0
	timerBar.Parent             = timerTrack
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0, 3)

	local segLabel = Instance.new("TextLabel")
	segLabel.Size                   = UDim2.new(0, 64, 1, 0)
	segLabel.AnchorPoint            = Vector2.new(1, 0)
	segLabel.Position               = UDim2.new(1, -8, 0, 0)
	segLabel.BackgroundTransparency = 1
	segLabel.Text                   = "1 / " .. segCount
	segLabel.TextColor3             = COL_GOLD
	segLabel.Font                   = Enum.Font.GothamBold
	segLabel.TextSize               = 18
	segLabel.TextXAlignment         = Enum.TextXAlignment.Center
	segLabel.Parent                 = hudBar

	-- Canvas
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.new(0.88, 0, 0.76, 0)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.48, 0.60)
	canvas.BackgroundColor3 = COL_CANVAS
	canvas.BackgroundTransparency = 0.28
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.ZIndex           = 2
	canvas.Parent = container
	table.insert(_instances, canvas)
	Instance.new("UICorner", canvas).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 55, 70)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = canvas

	-- Fabric weave lines
	for i = 1, 7 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, i / 8)
		line.BackgroundColor3 = Color3.fromRGB(38, 20, 30)
		line.BackgroundTransparency = 0.55
		line.BorderSizePixel = 0
		line.Parent = canvas
	end

	-- Path dots (current segment = bright, future = dim)
	for si, seg in ipairs(pathSegments) do
		local ax, ay, bx, by = seg[1], seg[2], seg[3], seg[4]
		local dotCount = 22  -- more dots for dense, clear path
		for j = 0, dotCount do
			local t   = j / dotCount
			local dot = Instance.new("Frame")
			dot.Name  = "PathDot_" .. si
			dot.Size  = UDim2.new(0, si == 1 and 6 or 5, 0, si == 1 and 6 or 5)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(ax + (bx-ax)*t, ay + (by-ay)*t)
			dot.BackgroundColor3 = si == 1 and COL_DOT or COL_DOT_DIM
			dot.BackgroundTransparency = si == 1 and 0.05 or 0.45
			dot.BorderSizePixel = 0
			dot.ZIndex = 2
			dot.Parent = canvas
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
			table.insert(_instances, dot)
		end
	end

	-- Start marker
	local s = pathSegments[1]
	local startMark = Instance.new("Frame")
	startMark.Size = UDim2.new(0, 22, 0, 22)
	startMark.AnchorPoint = Vector2.new(0.5, 0.5)
	startMark.Position = UDim2.fromScale(s[1], s[2])
	startMark.BackgroundColor3 = COL_START
	startMark.BorderSizePixel = 0; startMark.ZIndex = 4
	startMark.Parent = canvas
	Instance.new("UICorner", startMark).CornerRadius = UDim.new(1, 0)
	table.insert(_instances, startMark)

	-- End marker
	local e = pathSegments[#pathSegments]
	local endMark = Instance.new("Frame")
	endMark.Size = UDim2.new(0, 22, 0, 22)
	endMark.AnchorPoint = Vector2.new(0.5, 0.5)
	endMark.Position = UDim2.fromScale(e[3], e[4])
	endMark.BackgroundColor3 = COL_END_MK
	endMark.BorderSizePixel = 0; endMark.ZIndex = 4
	endMark.Parent = canvas
	Instance.new("UICorner", endMark).CornerRadius = UDim.new(1, 0)
	table.insert(_instances, endMark)

	-- Needle
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.Size = UDim2.new(0, 24, 0, 24)
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromScale(s[1], s[2])
	needle.BackgroundColor3 = COL_NEEDLE
	needle.BorderSizePixel = 0; needle.ZIndex = 6
	needle.Parent = canvas
	Instance.new("UICorner", needle).CornerRadius = UDim.new(1, 0)
	table.insert(_instances, needle)

	local threadDot = Instance.new("Frame")
	threadDot.Size = UDim2.fromScale(0.38, 0.38)
	threadDot.AnchorPoint = Vector2.new(0.5, 0.5)
	threadDot.Position = UDim2.fromScale(0.5, 0.5)
	threadDot.BackgroundColor3 = COL_THREAD
	threadDot.BorderSizePixel = 0
	threadDot.Parent = needle
	Instance.new("UICorner", threadDot).CornerRadius = UDim.new(1, 0)

	local meterFill = buildDeviationMeter(canvas)

	return canvas, needle, segLabel, timerLabel, meterFill, timerBar
end

-- ── Brighten path dots for the current segment ────────────────────────────

local function highlightSegment(canvas, segmentIndex)
	for _, dot in ipairs(canvas:GetChildren()) do
		if dot:IsA("Frame") and dot.Name:find("PathDot_") then
			local idx = tonumber(dot.Name:match("PathDot_(%d+)"))
			if idx then
				if idx == segmentIndex then
					dot.BackgroundColor3 = COL_DOT
					dot.BackgroundTransparency = 0.05
				elseif idx < segmentIndex then
					dot.BackgroundTransparency = 0.80  -- fade out completed segments
				end
			end
		end
	end
end

-- ── Public interface ──────────────────────────────────────────────────────

local SeamStitching = {}

function SeamStitching.Start(container, config)
	_result      = "Pass"
	_connections = {}
	_instances   = {}
	_trail       = {}
	_done        = Instance.new("BindableEvent")
	_finished    = false

	local p = config.params or cfg

	local segCount     = math.random(p.segmentCountMin, p.segmentCountMax)
	local pathSegments = generatePath(segCount)
	local totalTime    = segCount * p.timePerSegment
	local tolerance    = p.deviationTolerance + config.toolBonus * p.deviationTolerance

	if config.fragile then tolerance = tolerance * mgCfg.fragileMultiplier end

	-- Failure is based on how much the player strays OFF the seam over the whole
	-- run, not a single far-off moment. The bar fills only while the needle is
	-- past the tolerance band, faster the further off it is; staying on the line
	-- adds nothing. MISS_BUDGET is roughly how many seconds you may sit one full
	-- tolerance beyond the edge before the bar maxes out and the run fails —
	-- higher = more forgiving. A partly-filled bar at the end still passes.
	local MISS_BUDGET = p.missBudget or 2.5

	local canvas, needle, segLabel, timerLabel, meterFill, timerBar =
		buildUI(container, pathSegments, segCount)

	local isDragging    = false
	local segmentIndex  = 1
	local accumError    = 0   -- total accumulated inaccuracy so far (px·s)
	local everDragged   = false
	local lastStitchSfx = 0
	local lastMoveClock = 0   -- os.clock() of the previous move sample, for dt
	local vigOnPath     = true

	timerLabel.Text = tostring(totalTime)
	segLabel.Text   = "1 / " .. segCount

	local function finishGame(failByDeviation)
		if _finished then return end
		_finished = true
		disconnect()
		SFX.Stop("StitchLoop")
		if failByDeviation then
			-- Error budget used up: too much total inaccuracy → fail.
			_result = "Fail"
		else
			-- Grade by how full the miss budget got (0 = never strayed = flawless).
			local budgetFrac = MISS_BUDGET > 0 and (accumError / MISS_BUDGET) or 0
			if not everDragged then
				_result = "Fail"
			elseif budgetFrac >= 1 then
				_result = "Fail"
			elseif budgetFrac <= p.perfectMaxDeviationFrac then
				_result = "Perfect"
			elseif budgetFrac <= p.goodMaxDeviationFrac then
				_result = "Good"
			else
				_result = "Pass"
			end
		end
		-- On a clean finish, never leave the needle/meter stuck on red.
		if _result ~= "Fail" then
			needle.BackgroundColor3 = COL_NEEDLE
			meterFill.BackgroundColor3 = COL_METER_OK
		end
		SFX.Play("StitchComplete")
		if _done then _done:Fire() end
	end

	local function advanceSegment()
		segmentIndex = segmentIndex + 1
		if segmentIndex > #pathSegments then
			finishGame()
		else
			segLabel.Text = segmentIndex .. " / " .. segCount
			TweenService:Create(segLabel, TweenInfo.new(0.07), { TextSize = 24 }):Play()
			task.delay(0.09, function()
				TweenService:Create(segLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back), { TextSize = 18 }):Play()
			end)
			SFX.Play("StitchSegment")
			highlightSegment(canvas, segmentIndex)
			-- Flash needle green
			TweenService:Create(needle, TweenInfo.new(0.12), {
				BackgroundColor3 = Color3.fromRGB(80, 220, 110)
			}):Play()
			task.delay(0.20, function() needle.BackgroundColor3 = COL_NEEDLE end)
		end
	end

	-- Heartbeat bar depletion
	local startClock = os.clock()
	local barConn = RunService.Heartbeat:Connect(function()
		if _finished then return end
		local ratio = math.max(0, 1 - (os.clock() - startClock) / totalTime)
		timerBar.Size = UDim2.fromScale(ratio, 1)
	end)
	table.insert(_connections, barConn)

	local COL_VIG_GREEN = Color3.fromRGB(70, 210, 90)
	local COL_VIG_RED   = Color3.fromRGB(210, 70, 70)

	local vignette = Instance.new("Frame")
	vignette.Size                   = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3       = COL_VIG_GREEN
	vignette.BackgroundTransparency = 1
	vignette.ZIndex                 = 1
	vignette.BorderSizePixel        = 0
	vignette.Parent                 = container
	table.insert(_instances, vignette)

	local vigRatio = 0
	local vigTransp = 1
	local vigConn = RunService.Heartbeat:Connect(function(dt)
		if _finished then return end
		local targetRatio  = (isDragging and not vigOnPath) and 1 or 0
		vigRatio  = vigRatio  + (targetRatio  - vigRatio)  * math.min(1, dt * 6)
		local targetTransp = isDragging and (0.88 - vigRatio * 0.16) or 1
		vigTransp = vigTransp + (targetTransp - vigTransp) * math.min(1, dt * 4)
		vignette.BackgroundColor3       = COL_VIG_GREEN:Lerp(COL_VIG_RED, vigRatio)
		vignette.BackgroundTransparency = vigTransp
	end)
	table.insert(_connections, vigConn)

	-- Global countdown timer
	task.spawn(function()
		local remaining = totalTime
		while remaining > 0 and not _finished do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = tostring(remaining)
			local ratio = remaining / totalTime
			local col = ratio > 0.5 and COL_WHITE or ratio > 0.25 and COL_WARN or COL_DANGER
			timerLabel.TextColor3     = col
			timerBar.BackgroundColor3 = col
		end
		if not _finished then finishGame() end
	end)

	-- Mouse / touch move — needle follows cursor freely, no snap
	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if _finished or not isDragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		local canvasAbs  = canvas.AbsolutePosition
		local canvasSize = canvas.AbsoluteSize
		local sx = math.clamp((input.Position.X - canvasAbs.X) / canvasSize.X, 0.01, 0.99)
		local sy = math.clamp((input.Position.Y - canvasAbs.Y) / canvasSize.Y, 0.01, 0.99)

		local seg = pathSegments[segmentIndex]
		if not seg then return end

		local ax, ay, bx, by = seg[1], seg[2], seg[3], seg[4]
		local _, _, distPx, t = closestPointOnSegment(ax, ay, bx, by, sx, sy, canvasSize.X, canvasSize.Y)

		local onPath = distPx <= tolerance
		vigOnPath    = onPath

		-- Fill the bar only when the needle MISSES the seam (past the tolerance
		-- band). The amount added scales with how far off you are and how long
		-- you stay there (dt → frame-rate independent); on the line adds nothing.
		local now = os.clock()
		local dt  = everDragged and math.clamp(now - lastMoveClock, 0, 0.1) or 0
		lastMoveClock = now
		everDragged   = true
		if not onPath then
			accumError = accumError + ((distPx - tolerance) / tolerance) * dt
		end

		-- Right-side bar = how full the miss budget is so far.
		local budgetFrac = math.clamp(accumError / MISS_BUDGET, 0, 1)
		TweenService:Create(meterFill, TweenInfo.new(0.07), {
			Size = UDim2.fromScale(1, budgetFrac),
			BackgroundColor3 = budgetFrac < 0.7 and COL_METER_OK or COL_METER_BAD,
		}):Play()

		-- Bar full → too many/large misses → fail and stop.
		if budgetFrac >= 1 then
			needle.Position = UDim2.fromScale(sx, sy)
			needle.BackgroundColor3 = COL_TRAIL_BAD
			finishGame(true)
			return
		end

		-- Trail dot
		addTrailDot(canvas, sx, sy, onPath)

		-- Needle follows cursor — no snap
		needle.Position = UDim2.fromScale(sx, sy)
		needle.BackgroundColor3 = onPath and COL_NEEDLE or COL_TRAIL_BAD

		-- Throttled stitch ambient sound (every 0.14s while dragging)
		if now - lastStitchSfx >= 0.14 then
			lastStitchSfx = now
			SFX.Play("StitchThread")
		end

		-- Advance when cursor projection has reached the endpoint (t=1 means the
		-- cursor is at or past the endpoint in pixel space). Using t avoids the
		-- old early-trigger bug where endDist < 0.055 (scale) fired ~85px before
		-- the endpoint, then the next segment immediately read the cursor as "off
		-- path" because it was still behind the new segment's start.
		if t >= 1 then
			advanceSegment()
		end
	end)
	table.insert(_connections, moveConn)

	local downConn = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			SFX.PlayLooping("StitchLoop")
		end
	end)
	table.insert(_connections, downConn)

	local upConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
			SFX.Stop("StitchLoop")
		end
	end)
	table.insert(_connections, upConn)

	_done.Event:Wait()
	_done:Destroy()
	_done = nil
end

function SeamStitching.GetResult()
	return _result
end

function SeamStitching.Cleanup()
	disconnect()
	for _, inst in ipairs(_instances) do
		if inst and inst.Parent then inst:Destroy() end
	end
	_instances = {}
	_trail     = {}
	if _done then
		_done:Destroy()
		_done = nil
	end
end

function SeamStitching.Cancel()
	_finished = true
	if _done then _done:Fire() end
end

return SeamStitching
