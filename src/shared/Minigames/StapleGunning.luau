--[[
	Staple Gunning Minigame  (multi-zone)
	Interface: Start(container, config) → yields | GetResult() | Cleanup()

	Mechanic:
	  A bar bounces left-right across a track. Multiple zone pairs are randomly
	  scattered across the track, each with:
	    - A narrow green  "Good"    zone  (1 pt)
	    - A tiny  gold    "Perfect" zone  (2 pts) centered inside the good zone
	  Tap FIRE when the bar overlaps any zone. Outside all zones = miss (0 pts).
	  The bar is fast and speeds up with each successful staple.

	config = { fragile = bool, toolBonus = number }
	Result = "Fail" | "Pass" | "Good" | "Perfect"
]]

local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GameConfig   = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX          = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg   = GameConfig.StapleGunning
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

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_PILL_BG   = Color3.fromRGB(0, 0, 0)
local COL_GOLD      = Color3.fromRGB(210, 170, 60)
local COL_WHITE     = Color3.fromRGB(255, 255, 255)
local COL_TRACK     = Color3.fromRGB(20, 15, 30)
local COL_GOOD_ZONE = Color3.fromRGB(60, 190, 90)
local COL_PERF_ZONE = Color3.fromRGB(230, 200, 60)
local COL_BAR       = Color3.fromRGB(235, 225, 210)
local COL_BTN       = Color3.fromRGB(160, 40, 40)
local COL_BTN_FLASH = Color3.fromRGB(215, 70, 70)
local COL_HIT_PERF  = Color3.fromRGB(255, 220, 70)
local COL_HIT_GOOD  = Color3.fromRGB(80, 220, 120)
local COL_MISS      = Color3.fromRGB(220, 70, 70)
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

local function showFeedback(label, text, color)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end)
end

-- ── Zone generation ───────────────────────────────────────────────────────
-- Returns an array of zone centres spread randomly across the track (0–1 scale).
-- Centres are evenly spaced with jitter so zones never heavily overlap.

local function generateZones(count, goodW)
	local zones   = {}
	local usable  = 0.82  -- leave margins at each end
	local step    = usable / count
	for i = 1, count do
		local base   = 0.09 + (i - 0.5) * step
		local jitter = (math.random() - 0.5) * step * 0.45
		local center = math.clamp(base + jitter, goodW / 2 + 0.03, 1 - goodW / 2 - 0.03)
		table.insert(zones, center)
	end
	return zones
end

-- ── UI builder ────────────────────────────────────────────────────────────

local function buildUI(container, zones, goodW, perfW, stapleCount)
	-- HUD
	local timerPill = makePill(container, 100, 48, 0.03, 0.03, 0, 0)
	local timerLabel = makeLabel(timerPill, tostring(cfg.timeLimit) .. "s", 30, COL_WHITE)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local titlePill = makePill(container, 300, 40, 0.5, 0.03, 0.5, 0)
	makeLabel(titlePill, "FIRE THE STAPLE GUN", 17, COL_GOLD)

	local scorePill = makePill(container, 120, 48, 0.97, 0.03, 1, 0)
	local scoreLabel = makeLabel(scorePill, "0 / " .. stapleCount, 26, COL_GOLD)
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(0.84, 0, 0, 60)
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.37)
	track.BackgroundColor3 = COL_TRACK
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = container
	table.insert(_instances, track)
	Instance.new("UICorner", track).CornerRadius = UDim.new(0.5, 0)

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.fromRGB(55, 42, 82)
	trackStroke.Thickness = 1.5
	trackStroke.Parent = track

	-- Render each zone pair
	for _, center in ipairs(zones) do
		-- Good zone (outer, green)
		local gZone = Instance.new("Frame")
		gZone.Size = UDim2.new(goodW, 0, 1, 0)
		gZone.AnchorPoint = Vector2.new(0.5, 0)
		gZone.Position = UDim2.fromScale(center, 0)
		gZone.BackgroundColor3 = COL_GOOD_ZONE
		gZone.BackgroundTransparency = 0.42
		gZone.BorderSizePixel = 0
		gZone.ZIndex = 2
		gZone.Parent = track

		-- Perfect zone (inner, gold)
		local pZone = Instance.new("Frame")
		pZone.Size = UDim2.new(perfW, 0, 1, 0)
		pZone.AnchorPoint = Vector2.new(0.5, 0)
		pZone.Position = UDim2.fromScale(center, 0)
		pZone.BackgroundColor3 = COL_PERF_ZONE
		pZone.BackgroundTransparency = 0.22
		pZone.BorderSizePixel = 0
		pZone.ZIndex = 3
		pZone.Parent = track

		-- Star label on perfect zone
		local star = Instance.new("TextLabel")
		star.Size = UDim2.fromScale(1, 0.9)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(0.5, 0.5)
		star.BackgroundTransparency = 1
		star.Text = "★"
		star.TextColor3 = COL_PERF_ZONE
		star.Font = Enum.Font.GothamBold
		star.TextSize = 14
		star.TextTransparency = 0.15
		star.ZIndex = 4
		star.Parent = pZone
	end

	-- Moving bar
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 8, 1, -8)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.BackgroundColor3 = COL_BAR
	bar.BorderSizePixel = 0
	bar.ZIndex = 6
	bar.Parent = track
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)

	-- FIRE button
	local fireBtn = Instance.new("TextButton")
	fireBtn.Size = UDim2.new(0, 188, 0, 70)
	fireBtn.AnchorPoint = Vector2.new(0.5, 0)
	fireBtn.Position = UDim2.fromScale(0.5, 0.54)
	fireBtn.BackgroundColor3 = COL_BTN
	fireBtn.TextColor3 = Color3.fromRGB(255, 245, 220)
	fireBtn.Font = Enum.Font.GothamBold
	fireBtn.TextSize = 30
	fireBtn.Text = "FIRE"
	fireBtn.BorderSizePixel = 0
	fireBtn.ZIndex = 2
	fireBtn.Parent = container
	table.insert(_instances, fireBtn)
	Instance.new("UICorner", fireBtn).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", fireBtn).Color = Color3.fromRGB(200, 55, 55)

	-- Feedback label
	local feedback = Instance.new("TextLabel")
	feedback.Size = UDim2.new(0, 170, 0, 38)
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Position = UDim2.fromScale(0.5, 0.82)
	feedback.BackgroundTransparency = 1
	feedback.Text = ""
	feedback.TextColor3 = COL_GOLD
	feedback.Font = Enum.Font.GothamBold
	feedback.TextSize = 28
	feedback.TextTransparency = 1
	feedback.Parent = container
	table.insert(_instances, feedback)

	return bar, fireBtn, scoreLabel, timerLabel, feedback
end

-- ── Public interface ──────────────────────────────────────────────────────

local StapleGunning = {}

function StapleGunning.Start(container, config)
	_result      = "Pass"
	_connections = {}
	_instances   = {}
	_done        = Instance.new("BindableEvent")

	local stapleCount = math.random(cfg.stapleCountMin, cfg.stapleCountMax)
	local goodW       = cfg.goodZoneWidth
	local perfW       = cfg.perfectZoneWidth
	local timeLimit   = cfg.timeLimit

	if config.fragile then
		goodW = goodW * mgCfg.fragileMultiplier
		perfW = perfW * mgCfg.fragileMultiplier
	end

	-- Generate random zone positions for this run
	local zones = generateZones(cfg.zoneCount, goodW)

	local bar, fireBtn, scoreLabel, timerLabel, feedback =
		buildUI(container, zones, goodW, perfW, stapleCount)

	-- Randomise bar start
	local barPos       = math.random() * 0.8 + 0.1
	local direction    = math.random() < 0.5 and 1 or -1
	local currentSpeed = cfg.barSpeed
	local staplesFired = 0
	local score        = 0
	local maxScore     = stapleCount * 2
	local finished     = false

	local lastTime = os.clock()
	local hbConn = RunService.Heartbeat:Connect(function()
		if finished then return end
		local now = os.clock()
		local dt  = now - lastTime
		lastTime  = now
		barPos = barPos + direction * currentSpeed * dt
		if barPos >= 1 then barPos = 1; direction = -1
		elseif barPos <= 0 then barPos = 0; direction = 1 end
		bar.Position = UDim2.fromScale(barPos, 0.5)
	end)
	table.insert(_connections, hbConn)

	local function resolveResult()
		local ratio = maxScore > 0 and (score / maxScore) or 0
		if score == 0 then
			_result = "Fail"
		elseif ratio >= cfg.perfectMinRatio then
			_result = "Perfect"
		elseif ratio >= cfg.goodMinRatio then
			_result = "Good"
		else
			_result = "Pass"
		end
	end

	local function finishGame()
		if finished then return end
		finished = true
		disconnect()
		resolveResult()
		task.wait(0.4)
		if _done then _done:Fire() end
	end

	local fireConn = fireBtn.Activated:Connect(function()
		if finished then return end

		-- Check all zones: perfect takes priority over good
		local pts = 0
		local feedText, feedCol

		for _, center in ipairs(zones) do
			if barPos >= center - perfW / 2 and barPos <= center + perfW / 2 then
				pts = 2; feedText = "PERFECT!"; feedCol = COL_HIT_PERF
				break
			end
		end
		if pts == 0 then
			for _, center in ipairs(zones) do
				if barPos >= center - goodW / 2 and barPos <= center + goodW / 2 then
					pts = 1; feedText = "GOOD"; feedCol = COL_HIT_GOOD
					break
				end
			end
		end
		if pts == 0 then
			feedText = "MISS"; feedCol = COL_MISS
		end

		score        = score + pts
		staplesFired = staplesFired + 1
		scoreLabel.Text = staplesFired .. " / " .. stapleCount
		showFeedback(feedback, feedText, feedCol)

		-- SFX
		if pts == 2 then
			SFX.Play("StaplePerfect")
			currentSpeed = currentSpeed + cfg.barSpeedRampUp
		elseif pts == 1 then
			SFX.Play("StapleGood")
			currentSpeed = currentSpeed + cfg.barSpeedRampUp * 0.5
		else
			SFX.Play("StapleMiss")
		end

		-- Button flash
		TweenService:Create(fireBtn, TweenInfo.new(0.06), { BackgroundColor3 = COL_BTN_FLASH }):Play()
		task.delay(0.07, function()
			TweenService:Create(fireBtn, TweenInfo.new(0.14), { BackgroundColor3 = COL_BTN }):Play()
		end)

		if staplesFired >= stapleCount then
			finished = true
			disconnect()
			resolveResult()
			task.wait(0.5)
			if _done then _done:Fire() end
		end
	end)
	table.insert(_connections, fireConn)

	-- Global timer
	task.spawn(function()
		local remaining = timeLimit
		while remaining > 0 and not finished do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = remaining .. "s"
			if remaining <= 7 then timerLabel.TextColor3 = COL_DANGER end
		end
		if not finished then finishGame() end
	end)

	_done.Event:Wait()
	_done:Destroy()
	_done = nil
end

function StapleGunning.GetResult()
	return _result
end

function StapleGunning.Cleanup()
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

return StapleGunning
