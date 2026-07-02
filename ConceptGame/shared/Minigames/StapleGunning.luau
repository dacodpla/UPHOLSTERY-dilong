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

local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX        = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg   = GameConfig.StapleGunning
local mgCfg = GameConfig.Minigame

-- ── Module state ──────────────────────────────────────────────────────────
local _result      = "Pass"
local _connections = {}
local _instances   = {}
local _done        = nil
local _finished    = false

local function disconnect()
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}
end

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_GOLD       = Color3.fromRGB(210, 170,  60)
local COL_WHITE      = Color3.fromRGB(255, 255, 255)
local COL_TRACK      = Color3.fromRGB( 20,  15,  30)
local COL_GOOD_ZONE  = Color3.fromRGB( 60, 190,  90)
local COL_PERF_ZONE  = Color3.fromRGB(230, 200,  60)
local COL_BAR        = Color3.fromRGB(235, 225, 210)
local COL_BTN        = Color3.fromRGB(160,  40,  40)
local COL_BTN_FLASH  = Color3.fromRGB(215,  70,  70)
local COL_HIT_PERF   = Color3.fromRGB(255, 220,  70)
local COL_HIT_GOOD   = Color3.fromRGB( 80, 220, 120)
local COL_MISS       = Color3.fromRGB(220,  70,  70)
local COL_DANGER     = Color3.fromRGB(220,  80,  80)
local COL_WARN       = Color3.fromRGB(230, 170,  50)
local COL_HUD_BG     = Color3.fromRGB(  0,   0,   0)
local COL_BAR_TRACK  = Color3.fromRGB( 45,  40,  60)

-- ── Feedback label helper ─────────────────────────────────────────────────

local function showFeedback(label, text, color)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end)
end

-- ── Zone generation ───────────────────────────────────────────────────────

local function generateZones(count, goodW)
	local zones  = {}
	local usable = 0.82
	local step   = usable / count
	for i = 1, count do
		local base   = 0.09 + (i - 0.5) * step
		local jitter = (math.random() - 0.5) * step * 0.45
		local center = math.clamp(base + jitter, goodW / 2 + 0.03, 1 - goodW / 2 - 0.03)
		table.insert(zones, center)
	end
	return zones
end

-- ── UI builder ────────────────────────────────────────────────────────────

local function buildUI(container, zones, goodW, perfW, stapleCount, timeLimit)

	-- Full-screen flash vignette (above everything, normally invisible)
	local vignette = Instance.new("Frame")
	vignette.Size                   = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3       = COL_MISS
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel        = 0
	vignette.ZIndex                 = 1
	vignette.Parent                 = container
	table.insert(_instances, vignette)

	-- ── Compact centred HUD pill ──────────────────────────────────────────
	-- Centred horizontally, pushed below Roblox's own top bar (~36 px).
	-- Layout inside the pill:  [  27  |████████░░░|  0/3  ]
	local hudBar = Instance.new("Frame")
	hudBar.Size                 = UDim2.new(0.62, 0, 0, 40)
	hudBar.AnchorPoint          = Vector2.new(0.5, 0)
	hudBar.Position             = UDim2.new(0.5, 0, 0, 140)
	hudBar.BackgroundColor3     = COL_HUD_BG
	hudBar.BackgroundTransparency = 0.18
	hudBar.BorderSizePixel      = 0
	hudBar.Parent               = container
	table.insert(_instances, hudBar)
	Instance.new("UICorner", hudBar).CornerRadius = UDim.new(1, 0)

	-- Timer number (left side of pill)
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size                 = UDim2.new(0, 48, 1, 0)
	timerLabel.Position             = UDim2.new(0, 10, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text                 = tostring(timeLimit)
	timerLabel.TextColor3           = COL_WHITE
	timerLabel.Font                 = Enum.Font.GothamBold
	timerLabel.TextSize             = 19
	timerLabel.TextXAlignment       = Enum.TextXAlignment.Center
	timerLabel.Parent               = hudBar

	-- Progress bar track (fills the centre span of the pill)
	local timerTrack = Instance.new("Frame")
	timerTrack.Size             = UDim2.new(1, -142, 0, 7)
	timerTrack.Position         = UDim2.new(0, 66, 0.5, -3)
	timerTrack.BackgroundColor3 = COL_BAR_TRACK
	timerTrack.BorderSizePixel  = 0
	timerTrack.Parent           = hudBar
	Instance.new("UICorner", timerTrack).CornerRadius = UDim.new(1, 0)

	local timerBar = Instance.new("Frame")
	timerBar.Size             = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3 = COL_WHITE
	timerBar.BorderSizePixel  = 0
	timerBar.Parent           = timerTrack
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(1, 0)

	-- Score (right side of pill)
	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Size                 = UDim2.new(0, 64, 1, 0)
	scoreLabel.Position             = UDim2.new(1, -72, 0, 0)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Text                 = "0 / " .. stapleCount
	scoreLabel.TextColor3           = COL_GOLD
	scoreLabel.Font                 = Enum.Font.GothamBold
	scoreLabel.TextSize             = 18
	scoreLabel.TextXAlignment       = Enum.TextXAlignment.Center
	scoreLabel.Parent               = hudBar

	-- ── Track ─────────────────────────────────────────────────────────────
	local track = Instance.new("Frame")
	track.Name             = "Track"
	track.Size             = UDim2.new(0.84, 0, 0, 60)
	track.AnchorPoint      = Vector2.new(0.5, 0.5)
	track.Position         = UDim2.fromScale(0.5, 0.37)
	track.BackgroundColor3 = COL_TRACK
	track.BorderSizePixel  = 0
	track.ClipsDescendants = true
	track.Parent           = container
	table.insert(_instances, track)
	-- Instance.new("UICorner", track).CornerRadius = UDim.new(0.5, 0)

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color     = Color3.fromRGB(55, 42, 82)
	trackStroke.Thickness = 1.5
	trackStroke.Parent    = track


	-- Zone pairs
	for _, center in ipairs(zones) do
		local gZone = Instance.new("Frame")
		gZone.Size                  = UDim2.new(goodW, 0, 1, 0)
		gZone.AnchorPoint           = Vector2.new(0.5, 0)
		gZone.Position              = UDim2.fromScale(center, 0)
		gZone.BackgroundColor3      = COL_GOOD_ZONE
		gZone.BackgroundTransparency = 0.42
		gZone.BorderSizePixel       = 0
		gZone.ZIndex                = 2
		gZone.Parent                = track

		local pZone = Instance.new("Frame")
		pZone.Size                  = UDim2.new(perfW, 0, 1, 0)
		pZone.AnchorPoint           = Vector2.new(0.5, 0)
		pZone.Position              = UDim2.fromScale(center, 0)
		pZone.BackgroundColor3      = COL_PERF_ZONE
		pZone.BackgroundTransparency = 0.22
		pZone.BorderSizePixel       = 0
		pZone.ZIndex                = 3
		pZone.Parent                = track

		local star = Instance.new("TextLabel")
		star.Size                = UDim2.fromScale(1, 0.9)
		star.AnchorPoint         = Vector2.new(0.5, 0.5)
		star.Position            = UDim2.fromScale(0.5, 0.5)
		star.BackgroundTransparency = 1
		star.Text                = "★"
		star.TextColor3          = COL_PERF_ZONE
		star.Font                = Enum.Font.GothamBold
		star.TextSize            = 14
		star.TextTransparency    = 0.15
		star.ZIndex              = 4
		star.Parent              = pZone
	end

	-- Staple gun placeholder (moves left-right above the track)
	local gun = Instance.new("Frame")
	gun.Size             = UDim2.fromOffset(24, 52)
	gun.AnchorPoint      = Vector2.new(0.5, 0.5)
	gun.Position         = UDim2.new(0.08, 0, 0.37, 0)
	gun.BackgroundColor3 = Color3.fromRGB(90, 85, 100)
	gun.BorderSizePixel  = 0
	gun.ZIndex           = 7
	gun.Parent           = container
	Instance.new("UICorner", gun).CornerRadius = UDim.new(0, 5)
	table.insert(_instances, gun)

	-- ── FIRE button ───────────────────────────────────────────────────────
	local fireBtn = Instance.new("TextButton")
	fireBtn.Size             = UDim2.new(0, 188, 0, 70)
	fireBtn.AnchorPoint      = Vector2.new(0.5, 0)
	fireBtn.Position         = UDim2.fromScale(0.5, 0.54)
	fireBtn.BackgroundColor3 = COL_BTN
	fireBtn.TextColor3       = Color3.fromRGB(255, 245, 220)
	fireBtn.Font             = Enum.Font.GothamBold
	fireBtn.TextSize         = 30
	fireBtn.Text             = "FIRE"
	fireBtn.BorderSizePixel  = 0
	fireBtn.ZIndex           = 2
	fireBtn.Parent           = container
	table.insert(_instances, fireBtn)
	Instance.new("UICorner", fireBtn).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", fireBtn).Color = Color3.fromRGB(200, 55, 55)

	-- Feedback label (below fire button)
	local feedback = Instance.new("TextLabel")
	feedback.Size              = UDim2.new(0, 170, 0, 38)
	feedback.AnchorPoint       = Vector2.new(0.5, 0)
	feedback.Position          = UDim2.fromScale(0.5, 0.82)
	feedback.BackgroundTransparency = 1
	feedback.Text              = ""
	feedback.TextColor3        = COL_GOLD
	feedback.Font              = Enum.Font.GothamBold
	feedback.TextSize          = 28
	feedback.TextTransparency  = 1
	feedback.Parent            = container
	table.insert(_instances, feedback)

	return gun, fireBtn, scoreLabel, timerLabel, timerBar, feedback, vignette, track
end

-- ── Public interface ──────────────────────────────────────────────────────

local StapleGunning = {}

function StapleGunning.Start(container, config)
	_result      = "Pass"
	_connections = {}
	_instances   = {}
	_done        = Instance.new("BindableEvent")
	_finished    = false

	local p = config.params or cfg

	local stapleCount = math.random(p.stapleCountMin, p.stapleCountMax)
	local goodW       = p.goodZoneWidth
	local perfW       = p.perfectZoneWidth
	local timeLimit   = p.timeLimit

	if config.fragile then
		goodW = goodW * mgCfg.fragileMultiplier
		perfW = perfW * mgCfg.fragileMultiplier
	end

	local zones = generateZones(p.zoneCount, goodW)

	local gun, fireBtn, scoreLabel, timerLabel, timerBar, feedback, vignette, track =
		buildUI(container, zones, goodW, perfW, stapleCount, timeLimit)

	local startClock = os.clock()
	local barPos     = math.random() * 0.8 + 0.1
	local direction    = math.random() < 0.5 and 1 or -1
	local currentSpeed = p.barSpeed
	local staplesFired = 0
	local score        = 0
	local maxScore     = stapleCount * 2

	local lastTime = os.clock()
	local hbConn = RunService.Heartbeat:Connect(function()
		if _finished then return end
		local now = os.clock()
		local dt  = now - lastTime
		lastTime  = now
		barPos = barPos + direction * currentSpeed * dt
		if barPos >= 1 then barPos = 1; direction = -1
		elseif barPos <= 0 then barPos = 0; direction = 1 end
		gun.Position = UDim2.new(0.08 + barPos * 0.84, 0, 0.37, 0)
	end)
	table.insert(_connections, hbConn)

	local function resolveResult()
		local ratio = maxScore > 0 and (score / maxScore) or 0
		if score == 0 then
			_result = "Fail"
		elseif ratio >= p.perfectMinRatio then
			_result = "Perfect"
		elseif ratio >= p.goodMinRatio then
			_result = "Good"
		else
			_result = "Pass"
		end
	end

	local function finishGame()
		if _finished then return end
		_finished = true
		disconnect()
		resolveResult()
		task.wait(0.4)
		if _done then _done:Fire() end
	end

	local function onFire()
		if _finished then return end

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

		-- Score pop: briefly bump TextSize then settle back
		TweenService:Create(scoreLabel, TweenInfo.new(0.07), { TextSize = 30 }):Play()
		task.delay(0.09, function()
			TweenService:Create(scoreLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back), { TextSize = 22 }):Play()
		end)

		-- Screen vignette flash: colour encodes the result
		local vigCol = pts == 2 and COL_HIT_PERF or pts == 1 and COL_HIT_GOOD or COL_MISS
		vignette.BackgroundColor3      = vigCol
		vignette.BackgroundTransparency = 0.78
		TweenService:Create(vignette, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()

		-- SFX
		if pts == 2 then
			SFX.Play("StaplePerfect")
			currentSpeed = currentSpeed + p.barSpeedRampUp
		elseif pts == 1 then
			SFX.Play("StapleGood")
			currentSpeed = currentSpeed + p.barSpeedRampUp * 0.5
		else
			SFX.Play("StapleMiss")
		end

		-- Button flash
		TweenService:Create(fireBtn, TweenInfo.new(0.06), { BackgroundColor3 = COL_BTN_FLASH }):Play()
		task.delay(0.07, function()
			TweenService:Create(fireBtn, TweenInfo.new(0.14), { BackgroundColor3 = COL_BTN }):Play()
		end)

		-- Staple marker: drop a [ or ] glyph (alternating) at the fire position
		local staple = Instance.new("TextLabel")
		staple.Size                 = UDim2.fromOffset(18, 28)
		staple.AnchorPoint          = Vector2.new(0.5, 0.5)
		staple.Position             = UDim2.fromScale(barPos, 0.5)
		staple.BackgroundTransparency = 1
		staple.Text                 = staplesFired % 2 == 1 and "[" or "]"
		staple.TextColor3           = Color3.new(0, 0, 0)
		staple.Font                 = Enum.Font.Code
		staple.TextSize             = 17
		staple.TextTransparency     = 0.5
		staple.ZIndex               = 5
		staple.Parent               = track
		TweenService:Create(staple, TweenInfo.new(0.12, Enum.EasingStyle.Back), { TextTransparency = 0 }):Play()
		table.insert(_instances, staple)

		if staplesFired >= stapleCount then
			_finished = true
			disconnect()
			resolveResult()
			task.wait(0.5)
			if _done then _done:Fire() end
		end
	end

	-- Fire on mouse down (not Activated/release) for zero input lag
	local fireConn  = fireBtn.MouseButton1Down:Connect(onFire)
	-- Spacebar / Enter for keyboard players
	local inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
			onFire()
		end
	end)
	table.insert(_connections, fireConn)
	table.insert(_connections, inputConn)

	-- Bar depletes smoothly every frame — no jumps, no loops.
	local barConn = RunService.Heartbeat:Connect(function()
		if _finished then return end
		local ratio = math.max(0, 1 - (os.clock() - startClock) / (timeLimit))
		timerBar.Size = UDim2.fromScale(ratio, 1)
	end)
	table.insert(_connections, barConn)

	-- Number + colour update every second.
	task.spawn(function()
		local remaining = timeLimit
		while remaining > 0 and not _finished do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = tostring(remaining)
			local ratio = remaining / timeLimit
			local col = ratio > 0.5 and COL_WHITE or ratio > 0.25 and COL_WARN or COL_DANGER
			timerLabel.TextColor3     = col
			timerBar.BackgroundColor3 = col
		end
		if not _finished then finishGame() end
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

function StapleGunning.Cancel()
	_finished = true
	if _done then _done:Fire() end
end

return StapleGunning
