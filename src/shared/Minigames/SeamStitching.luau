--[[
	Seam Stitching Minigame
	Interface: Start(container, config) → yields | GetResult() | Cleanup()

	Mechanic:
	  A dotted zig-zag path is drawn across fabric. Drag the needle from the
	  green start marker to the red end marker, following the path as closely
	  as possible. The needle tracks your cursor freely — no snap-back.
	  A colored trail shows where you've been (green = on path, red = off).
	  A deviation meter on the right shows current closeness to the path.
	  Reach each segment's endpoint to advance. Segment count and waypoints
	  are randomly generated each run.

	config = { fragile = bool, toolBonus = number }
	Result = "Fail" | "Pass" | "Good" | "Perfect"
]]

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

local function disconnect()
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}
end

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_PILL_BG   = Color3.fromRGB(0, 0, 0)
local COL_GOLD      = Color3.fromRGB(210, 170, 60)
local COL_WHITE     = Color3.fromRGB(255, 255, 255)
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

-- ── Path generation ───────────────────────────────────────────────────────
-- Produces a zig-zag path that alternates direction each segment for clear,
-- challenging curves spread across the full canvas width.

local function generatePath(segCount)
	local waypoints = {}
	local startY    = math.random() * 0.28 + 0.36  -- start in middle third
	table.insert(waypoints, { x = 0.06, y = startY })

	local prevY    = startY
	local firstDir = math.random() < 0.5 and 1 or -1  -- randomise first swing direction

	for i = 1, segCount do
		local nextX    = 0.06 + i * (0.88 / segCount)
		local dir      = (i % 2 == 0) and firstDir or -firstDir
		local amp      = math.random() * 0.22 + 0.18   -- 0.18–0.40 per segment
		local nextY    = math.clamp(prevY + dir * amp, 0.10, 0.88)
		table.insert(waypoints, { x = nextX, y = nextY })
		prevY = nextY
	end

	local segs = {}
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		table.insert(segs, { a.x, a.y, b.x, b.y })
	end
	return segs
end

local function closestPointOnSegment(ax, ay, bx, by, px, py)
	local dx, dy = bx - ax, by - ay
	local lenSq  = dx * dx + dy * dy
	if lenSq < 1e-9 then return ax, ay, math.sqrt((px-ax)^2+(py-ay)^2), 0 end
	local t  = math.clamp(((px-ax)*dx+(py-ay)*dy) / lenSq, 0, 1)
	local cx = ax + t * dx
	local cy = ay + t * dy
	return cx, cy, math.sqrt((px-cx)^2+(py-cy)^2), t
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
	local timerPill = makePill(container, 100, 48, 0.03, 0.03, 0, 0)
	local timerLabel = makeLabel(timerPill, "--s", 30, COL_WHITE)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local titlePill = makePill(container, 240, 40, 0.5, 0.03, 0.5, 0)
	makeLabel(titlePill, "STITCH THE SEAM", 17, COL_GOLD)

	local segPill = makePill(container, 130, 48, 0.97, 0.03, 1, 0)
	local segLabel = makeLabel(segPill, "1 / " .. segCount, 22, COL_GOLD)
	segLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Canvas
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.new(0.88, 0, 0.82, 0)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.48, 0.54)
	canvas.BackgroundColor3 = COL_CANVAS
	canvas.BackgroundTransparency = 0.28
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
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

	return canvas, needle, segLabel, timerLabel, meterFill
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

	local segCount     = math.random(cfg.segmentCountMin, cfg.segmentCountMax)
	local pathSegments = generatePath(segCount)
	local totalTime    = segCount * cfg.timePerSegment
	local tolerance    = cfg.deviationTolerance + config.toolBonus * cfg.deviationTolerance

	if config.fragile then tolerance = tolerance * mgCfg.fragileMultiplier end

	local canvas, needle, segLabel, timerLabel, meterFill =
		buildUI(container, pathSegments, segCount)

	local isDragging       = false
	local segmentIndex     = 1
	local totalDeviation   = 0
	local deviationSamples = 0
	local everDragged      = false
	local finished         = false
	local lastStitchSfx    = 0

	timerLabel.Text = tostring(totalTime) .. "s"
	segLabel.Text   = "1 / " .. segCount

	local function finishGame()
		if finished then return end
		finished = true
		disconnect()
		local avgFrac = deviationSamples > 0
			and (totalDeviation / deviationSamples) / tolerance or 0
		if not everDragged then
			_result = "Fail"
		elseif avgFrac <= cfg.perfectMaxDeviationFrac then
			_result = "Perfect"
		elseif avgFrac <= cfg.goodMaxDeviationFrac then
			_result = "Good"
		else
			_result = "Pass"
		end
		if _done then _done:Fire() end
	end

	local function advanceSegment()
		segmentIndex = segmentIndex + 1
		if segmentIndex > #pathSegments then
			finishGame()
		else
			segLabel.Text = segmentIndex .. " / " .. segCount
			SFX.Play("StitchComplete")
			highlightSegment(canvas, segmentIndex)
			-- Flash needle green
			TweenService:Create(needle, TweenInfo.new(0.12), {
				BackgroundColor3 = Color3.fromRGB(80, 220, 110)
			}):Play()
			task.delay(0.20, function() needle.BackgroundColor3 = COL_NEEDLE end)
		end
	end

	-- Global countdown timer
	task.spawn(function()
		local remaining = totalTime
		while remaining > 0 and not finished do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = remaining .. "s"
			if remaining <= math.min(10, totalTime * 0.2) then
				timerLabel.TextColor3 = COL_DANGER
			end
		end
		if not finished then finishGame() end
	end)

	-- Mouse / touch move — needle follows cursor freely, no snap
	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if finished or not isDragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		local canvasAbs  = canvas.AbsolutePosition
		local canvasSize = canvas.AbsoluteSize
		local sx = math.clamp((input.Position.X - canvasAbs.X) / canvasSize.X, 0.01, 0.99)
		local sy = math.clamp((input.Position.Y - canvasAbs.Y) / canvasSize.Y, 0.01, 0.99)

		local seg = pathSegments[segmentIndex]
		if not seg then return end

		local ax, ay, bx, by = seg[1], seg[2], seg[3], seg[4]
		local _, _, distScale, _ = closestPointOnSegment(ax, ay, bx, by, sx, sy)
		local distPx = distScale * math.sqrt(canvasSize.X^2 + canvasSize.Y^2)

		everDragged      = true
		totalDeviation   = totalDeviation + distPx
		deviationSamples = deviationSamples + 1

		-- Deviation meter
		local deviRatio = math.clamp(distPx / tolerance, 0, 1)
		TweenService:Create(meterFill, TweenInfo.new(0.07), {
			Size = UDim2.fromScale(1, deviRatio),
			BackgroundColor3 = deviRatio < 0.55 and COL_METER_OK or COL_METER_BAD,
		}):Play()

		-- Trail dot
		local onPath = distPx <= tolerance
		addTrailDot(canvas, sx, sy, onPath)

		-- Needle follows cursor — no snap
		needle.Position = UDim2.fromScale(sx, sy)
		needle.BackgroundColor3 = onPath and COL_NEEDLE or COL_TRAIL_BAD

		-- Throttled stitch ambient sound (every 0.14s while dragging)
		local now = os.clock()
		if now - lastStitchSfx >= 0.14 then
			lastStitchSfx = now
			SFX.Play("StitchThread")
		end

		-- Advance when cursor reaches the segment endpoint
		local endDist = math.sqrt((sx - bx)^2 + (sy - by)^2)
		if endDist < 0.055 then
			advanceSegment()
		end
	end)
	table.insert(_connections, moveConn)

	local downConn = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
		end
	end)
	table.insert(_connections, downConn)

	local upConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
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

return SeamStitching
