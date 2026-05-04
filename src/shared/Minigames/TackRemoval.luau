--[[
	Tack Removal Minigame  (osu!-style)
	Interface: Start(container, config) → yields | GetResult() | Cleanup()

	Mechanic:
	  Tacks appear one at a time at random screen positions, each with a large
	  approach ring that shrinks down to the tack. Click/tap the tack before
	  the ring finishes to score. Timing determines quality:
	    - Late click (ring almost reached): Perfect (3 pts)
	    - Mid click:                        Good    (2 pts)
	    - Early click:                      OK      (1 pt)
	    - No click (ring finishes):         Miss    (0 pts)

	config = { fragile = bool, toolBonus = number }
	Result = "Fail" | "Pass" | "Good" | "Perfect"
]]

local TweenService = game:GetService("TweenService")
local GameConfig   = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX          = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg = GameConfig.TackRemoval

-- ── Module state ──────────────────────────────────────────────────────────
local _result      = "Pass"
local _connections = {}
local _instances   = {}
local _done        = nil

local function disconnect()
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}
end

-- ── Sizes (pixels) ────────────────────────────────────────────────────────
local TACK_D  = 52   -- tack circle diameter
local RING_D  = 130  -- approach ring starting diameter

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_TACK_IDLE    = Color3.fromRGB(210, 175, 60)
local COL_TACK_BG      = Color3.fromRGB(22, 17, 32)
local COL_RING         = Color3.fromRGB(210, 175, 60)
local COL_HIT_PERFECT  = Color3.fromRGB(80, 220, 120)
local COL_HIT_GOOD     = Color3.fromRGB(90, 180, 230)
local COL_HIT_OK       = Color3.fromRGB(180, 180, 180)
local COL_MISS         = Color3.fromRGB(220, 60, 60)
local COL_GOLD         = Color3.fromRGB(210, 170, 60)
local COL_WHITE        = Color3.fromRGB(255, 255, 255)
local COL_PILL_BG      = Color3.fromRGB(0, 0, 0)
local COL_MUTED        = Color3.fromRGB(160, 150, 170)

-- ── HUD pill builder ──────────────────────────────────────────────────────

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

local function makeLabel(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or COL_WHITE
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size or 18
	l.Parent = parent
	return l
end

-- ── Floating hit-quality text ──────────────────────────────────────────────

local function showHitText(container, posX, posY, text, color)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 120, 0, 32)
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.fromScale(posX, posY)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 20
	lbl.TextTransparency = 0
	lbl.ZIndex = 20
	lbl.Parent = container
	TweenService:Create(lbl, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(posX, posY - 0.06),
		TextTransparency = 1,
	}):Play()
	task.delay(0.65, function()
		if lbl.Parent then lbl:Destroy() end
	end)
end

-- ── Public interface ──────────────────────────────────────────────────────

local TackRemoval = {}

function TackRemoval.Start(container, config)
	_result      = "Pass"
	_connections = {}
	_instances   = {}
	_done        = Instance.new("BindableEvent")

	local tackCount   = math.random(cfg.tackCountMin, cfg.tackCountMax)
	local approachTime = cfg.approachTime
	local spawnGap    = cfg.tackSpawnGap

	-- HUD
	local timerPill = makePill(container, 100, 48, 0.03, 0.03, 0, 0)
	local timerLabel = makeLabel(timerPill, "—", 30, COL_WHITE)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local titlePill = makePill(container, 240, 40, 0.5, 0.03, 0.5, 0)
	makeLabel(titlePill, "PULL THE TACKS", 17, COL_GOLD)

	local hitsLabel = makeLabel(
		makePill(container, 120, 48, 0.97, 0.03, 1, 0),
		"0 / " .. tackCount, 26, COL_GOLD
	)

	local score    = 0
	local maxScore = tackCount * 3
	local hits     = 0
	local finished = false
	local elapsed  = 0

	-- Time display: total game duration based on how many tacks there are
	local totalDuration = (tackCount - 1) * spawnGap + approachTime + 0.6
	timerLabel.Text = math.ceil(totalDuration) .. "s"

	local function finishGame()
		if finished then return end
		finished = true
		disconnect()
		local ratio = maxScore > 0 and (score / maxScore) or 0
		if hits == 0 then
			_result = "Fail"
		elseif ratio >= cfg.perfectMinScore then
			_result = "Perfect"
		elseif ratio >= cfg.goodMinScore then
			_result = "Good"
		else
			_result = "Pass"
		end
		if _done then _done:Fire() end
	end

	-- Countdown display
	task.spawn(function()
		local timeLeft = totalDuration
		while timeLeft > 0 and not finished do
			task.wait(1)
			timeLeft = timeLeft - 1
			timerLabel.Text = math.ceil(timeLeft) .. "s"
			if timeLeft <= 5 then
				timerLabel.TextColor3 = COL_MISS
			end
		end
	end)

	-- Spawn tacks with staggered delays
	for i = 1, tackCount do
		task.delay((i - 1) * spawnGap, function()
			if finished then return end

			local px        = math.random() * 0.76 + 0.12
			local py        = math.random() * 0.66 + 0.17
			local startTime = os.clock()
			local hitDone   = false

			-- Approach ring (large hollow circle shrinking to tack size)
			local ring = Instance.new("Frame")
			ring.Size = UDim2.new(0, RING_D, 0, RING_D)
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(px, py)
			ring.BackgroundTransparency = 1
			ring.BorderSizePixel = 0
			ring.ZIndex = 8
			ring.Parent = container
			Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
			local ringStroke = Instance.new("UIStroke")
			ringStroke.Thickness = 4
			ringStroke.Color = COL_RING
			ringStroke.Transparency = 0.05
			ringStroke.Parent = ring
			table.insert(_instances, ring)

			-- Number label behind the tack (visible through transparent tack bg briefly)
			local bgCircle = Instance.new("Frame")
			bgCircle.Size = UDim2.new(0, TACK_D, 0, TACK_D)
			bgCircle.AnchorPoint = Vector2.new(0.5, 0.5)
			bgCircle.Position = UDim2.fromScale(px, py)
			bgCircle.BackgroundColor3 = COL_TACK_BG
			bgCircle.BackgroundTransparency = 0.2
			bgCircle.BorderSizePixel = 0
			bgCircle.ZIndex = 9
			bgCircle.Parent = container
			Instance.new("UICorner", bgCircle).CornerRadius = UDim.new(1, 0)
			table.insert(_instances, bgCircle)

			-- Tack button (clickable)
			local tack = Instance.new("TextButton")
			tack.Size = UDim2.new(0, TACK_D, 0, TACK_D)
			tack.AnchorPoint = Vector2.new(0.5, 0.5)
			tack.Position = UDim2.fromScale(px, py)
			tack.BackgroundColor3 = COL_TACK_IDLE
			tack.BackgroundTransparency = 0.08
			tack.Text = tostring(i)
			tack.TextColor3 = Color3.fromRGB(18, 14, 26)
			tack.Font = Enum.Font.GothamBold
			tack.TextSize = 20
			tack.BorderSizePixel = 0
			tack.AutoButtonColor = false
			tack.ZIndex = 10
			tack.Parent = container
			Instance.new("UICorner", tack).CornerRadius = UDim.new(1, 0)
			table.insert(_instances, tack)

			-- Ring shrink tween
			local ringTween = TweenService:Create(
				ring,
				TweenInfo.new(approachTime, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(0, TACK_D + 6, 0, TACK_D + 6) }
			)
			ringTween:Play()

			local function destroyTack()
				if tack.Parent   then tack:Destroy()     end
				if bgCircle.Parent then bgCircle:Destroy() end
				if ring.Parent   then ring:Destroy()     end
			end

			local hitConn
			hitConn = tack.Activated:Connect(function()
				if hitDone then return end
				hitDone = true
				hitConn:Disconnect()
				ringTween:Cancel()

				local progress = math.clamp((os.clock() - startTime) / approachTime, 0, 1)
				hits = hits + 1
				hitsLabel.Text = hits .. " / " .. tackCount

				local pts, flashCol, qualLabel
				if progress >= cfg.perfectMinProgress then
					pts = 3
					flashCol   = COL_HIT_PERFECT
					qualLabel  = "PERFECT"
				elseif progress >= cfg.goodMinProgress then
					pts = 2
					flashCol   = COL_HIT_GOOD
					qualLabel  = "GOOD"
				else
					pts = 1
					flashCol   = COL_HIT_OK
					qualLabel  = "OK"
				end
				score = score + pts

				showHitText(container, px, py - 0.03, qualLabel, flashCol)

				tack.BackgroundColor3 = flashCol
				TweenService:Create(tack, TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					Size = UDim2.new(0, 0, 0, 0),
				}):Play()
				TweenService:Create(ring, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
				task.delay(0.22, destroyTack)
			end)
			table.insert(_connections, hitConn)

			-- Miss: when ring finishes shrinking
			ringTween.Completed:Connect(function()
				if hitDone then return end
				hitDone = true
				hitConn:Disconnect()

				tack.BackgroundColor3 = COL_MISS
				showHitText(container, px, py - 0.03, "MISS", COL_MISS)
				TweenService:Create(tack, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(ring, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
				task.delay(0.4, destroyTack)
			end)
		end)
	end

	-- End the game after all tacks have had time to resolve
	task.delay((tackCount - 1) * spawnGap + approachTime + 0.9, finishGame)

	_done.Event:Wait()
	_done:Destroy()
	_done = nil
end

function TackRemoval.GetResult()
	return _result
end

function TackRemoval.Cleanup()
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

return TackRemoval
