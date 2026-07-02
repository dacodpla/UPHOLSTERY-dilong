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
local RunService   = game:GetService("RunService")
local GameConfig   = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local SFX          = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local cfg = GameConfig.TackRemoval

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

-- ── Sizes (pixels) ────────────────────────────────────────────────────────
local TACK_D  = 52   -- tack circle diameter
local RING_D  = 130  -- approach ring starting diameter

-- ── Colours ───────────────────────────────────────────────────────────────
local COL_TACK_BG      = Color3.fromRGB(22, 17, 32)
local COL_RING         = Color3.fromRGB(210, 175, 60)
local COL_HIT_PERFECT  = Color3.fromRGB(80, 220, 120)
local COL_HIT_GOOD     = Color3.fromRGB(90, 180, 230)
local COL_HIT_OK       = Color3.fromRGB(180, 180, 180)
local COL_MISS         = Color3.fromRGB(220, 60, 60)
local COL_GOLD         = Color3.fromRGB(210, 170, 60)
local COL_WARN         = Color3.fromRGB(230, 170, 50)
local COL_WHITE        = Color3.fromRGB(255, 255, 255)

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
	_finished    = false

	local p = config.params or cfg

	local tackCount   = math.random(p.tackCountMin, p.tackCountMax)
	local approachTime = p.approachTime
	local spawnGap    = p.tackSpawnGap

	local score    = 0
	local maxScore = tackCount * 3
	local hits     = 0

	local totalDuration = (tackCount - 1) * spawnGap + approachTime + 0.6

	-- Compact centred HUD pill
	local hudBar = Instance.new("Frame")
	hudBar.Size               = UDim2.new(0.62, 0, 0, 40)
	hudBar.AnchorPoint        = Vector2.new(0.5, 0)
	hudBar.Position           = UDim2.new(0.5, 0, 0, 140)
	hudBar.BackgroundColor3   = Color3.fromRGB(0, 0, 0)
	hudBar.BackgroundTransparency = 0.18
	hudBar.BorderSizePixel    = 0
	hudBar.Parent             = container
	table.insert(_instances, hudBar)
	Instance.new("UICorner", hudBar).CornerRadius = UDim.new(1, 0)

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size               = UDim2.new(0, 48, 1, 0)
	timerLabel.Position           = UDim2.new(0, 10, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text               = tostring(math.ceil(totalDuration))
	timerLabel.TextColor3         = COL_WHITE
	timerLabel.Font               = Enum.Font.GothamBold
	timerLabel.TextSize           = 19
	timerLabel.TextXAlignment     = Enum.TextXAlignment.Center
	timerLabel.Parent             = hudBar

	local timerTrack = Instance.new("Frame")
	timerTrack.Size             = UDim2.new(1, -142, 0, 7)
	timerTrack.Position         = UDim2.new(0, 66, 0.5, -3)
	timerTrack.BackgroundColor3 = Color3.fromRGB(45, 40, 60)
	timerTrack.BorderSizePixel  = 0
	timerTrack.Parent           = hudBar
	Instance.new("UICorner", timerTrack).CornerRadius = UDim.new(1, 0)

	local timerBar = Instance.new("Frame")
	timerBar.Size             = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3 = COL_WHITE
	timerBar.BorderSizePixel  = 0
	timerBar.Parent           = timerTrack
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(1, 0)

	local hitsLabel = Instance.new("TextLabel")
	hitsLabel.Size               = UDim2.new(0, 64, 1, 0)
	hitsLabel.Position           = UDim2.new(1, -72, 0, 0)
	hitsLabel.BackgroundTransparency = 1
	hitsLabel.Text               = "0 / " .. tackCount
	hitsLabel.TextColor3         = COL_GOLD
	hitsLabel.Font               = Enum.Font.GothamBold
	hitsLabel.TextSize           = 18
	hitsLabel.TextXAlignment     = Enum.TextXAlignment.Center
	hitsLabel.Parent             = hudBar

	local startClock = os.clock()
	local barConn = RunService.Heartbeat:Connect(function()
		if _finished then return end
		local ratio = math.max(0, 1 - (os.clock() - startClock) / totalDuration)
		timerBar.Size = UDim2.fromScale(ratio, 1)
	end)
	table.insert(_connections, barConn)

	local vignette = Instance.new("Frame")
	vignette.Size                   = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.ZIndex                 = 1
	vignette.BorderSizePixel        = 0
	vignette.Parent                 = container
	table.insert(_instances, vignette)

	local function finishGame()
		if _finished then return end
		_finished = true
		disconnect()
		local ratio = maxScore > 0 and (score / maxScore) or 0
		if hits == 0 then
			_result = "Fail"
		elseif ratio >= p.perfectMinScore then
			_result = "Perfect"
		elseif ratio >= p.goodMinScore then
			_result = "Good"
		else
			_result = "Pass"
		end
		if _done then _done:Fire() end
	end

	task.spawn(function()
		local timeLeft = totalDuration
		while timeLeft > 0 and not _finished do
			task.wait(1)
			timeLeft = timeLeft - 1
			timerLabel.Text = tostring(math.ceil(timeLeft))
			local ratio = timeLeft / totalDuration
			local col = ratio > 0.5 and COL_WHITE or ratio > 0.25 and COL_WARN or COL_MISS
			timerLabel.TextColor3     = col
			timerBar.BackgroundColor3 = col
		end
	end)

	-- Spawn tacks with staggered delays
	for i = 1, tackCount do
		task.delay((i - 1) * spawnGap, function()
			if _finished then return end

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

			-- Tack button (clickable) — styled as a metal nail head viewed from above
			local tack = Instance.new("TextButton")
			tack.Size = UDim2.new(0, TACK_D, 0, TACK_D)
			tack.AnchorPoint = Vector2.new(0.5, 0.5)
			tack.Position = UDim2.fromScale(px, py)
			tack.BackgroundColor3 = Color3.fromRGB(80, 80, 88)
			tack.BackgroundTransparency = 0
			tack.Text = ""
			tack.BorderSizePixel = 0
			tack.AutoButtonColor = false
			tack.ZIndex = 10
			tack.Parent = container
			Instance.new("UICorner", tack).CornerRadius = UDim.new(1, 0)
			-- Diagonal metallic gradient: light upper-left → dark lower-right
			local tackGrad = Instance.new("UIGradient")
			tackGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(165, 165, 178)),
				ColorSequenceKeypoint.new(0.42, Color3.fromRGB(88,  88,  98)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(22,  22,  28)),
			})
			tackGrad.Rotation = 135
			tackGrad.Parent = tack
			-- Raised nail-dome highlight at center
			local nailHead = Instance.new("Frame")
			nailHead.Size = UDim2.fromOffset(13, 13)
			nailHead.AnchorPoint = Vector2.new(0.5, 0.5)
			nailHead.Position = UDim2.fromScale(0.5, 0.5)
			nailHead.BackgroundColor3 = Color3.fromRGB(215, 218, 230)
			nailHead.BorderSizePixel = 0
			nailHead.ZIndex = 11
			nailHead.Parent = tack
			Instance.new("UICorner", nailHead).CornerRadius = UDim.new(1, 0)
			local headGrad = Instance.new("UIGradient")
			headGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(252, 252, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 148, 162)),
			})
			headGrad.Rotation = 135
			headGrad.Parent = nailHead
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
				TweenService:Create(hitsLabel, TweenInfo.new(0.07), { TextSize = 24 }):Play()
				task.delay(0.09, function()
					TweenService:Create(hitsLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back), { TextSize = 18 }):Play()
				end)

				local pts, flashCol, qualLabel
				if progress >= p.perfectMinProgress then
					pts = 3
					flashCol   = COL_HIT_PERFECT
					qualLabel  = "PERFECT"
				elseif progress >= p.goodMinProgress then
					pts = 2
					flashCol   = COL_HIT_GOOD
					qualLabel  = "GOOD"
				else
					pts = 1
					flashCol   = COL_HIT_OK
					qualLabel  = "OK"
				end
				score = score + pts

				do
					local vigCol = pts == 3 and Color3.fromRGB(230, 190, 60)
					           or pts == 2 and Color3.fromRGB(90, 180, 230)
					           or              Color3.fromRGB(140, 160, 210)
					local vigTransp = pts == 3 and 0.70 or pts == 2 and 0.78 or 0.90
					vignette.BackgroundColor3       = vigCol
					vignette.BackgroundTransparency = vigTransp
					TweenService:Create(vignette, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				end

				if pts == 3 then
					SFX.Play("TackPerfect")
				else
					SFX.Play("TackGood")
				end

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

				SFX.Play("TackMiss")
				vignette.BackgroundColor3       = Color3.fromRGB(210, 60, 60)
				vignette.BackgroundTransparency = 0.75
				TweenService:Create(vignette, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
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

function TackRemoval.Cancel()
	_finished = true
	if _done then _done:Fire() end
end

return TackRemoval
