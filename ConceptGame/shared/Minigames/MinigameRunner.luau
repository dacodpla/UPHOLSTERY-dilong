--[[
	MinigameRunner
	Client-side orchestrator for all minigames.

	Usage (single minigame):
	  local result = MinigameRunner.Run("TackRemoval", { fragile = false, toolBonus = 0 })

	Usage (Prestige chain):
	  local results = MinigameRunner.RunChain(
	      { "TackRemoval", "SeamStitching" },
	      { fragile = true, toolBonus = 0.2 }
	  )
	  local overall = MinigameRunner.CollapseChainResult(results)

	config = { fragile = bool, toolBonus = number (0.0–0.2) }
	result = "Fail" | "Pass" | "Good" | "Perfect"
]]

local MinigameRunner = {}

local TweenService  = game:GetService("TweenService")
local Lighting      = game:GetService("Lighting")
local Players       = game:GetService("Players")
local SFX           = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))
local GameConfig    = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))

-- ── Module registry ───────────────────────────────────────────────────────
-- Pre-require all modules now so their module-level PreloadAsync calls run behind
-- the loading screen, not on the first minigame trigger.
local MINIGAME_MODULES = {
	TackRemoval   = require(script.Parent.TackRemoval),
	StapleGunning = require(script.Parent.StapleGunning),
	SeamStitching = require(script.Parent.SeamStitching),
	FoamPadding   = require(script.Parent.FoamPadding),
}

local RESULT_COLORS = {
	Fail    = Color3.fromRGB(120, 50, 50),
	Pass    = Color3.fromRGB(160, 140, 120),
	Good    = Color3.fromRGB(90, 180, 220),
	Perfect = Color3.fromRGB(255, 210, 60),
}

local RESULT_LABELS = {
	Fail    = "FAIL",
	Pass    = "PASS",
	Good    = "GOOD",
	Perfect = "PERFECT!",
}

-- ── Cancellation state ───────────────────────────────────────────────────
local _activeMinigame = nil
local _isCancelling   = false

-- ── Blur management ───────────────────────────────────────────────────────

local _blur = nil

local function addBlur()
	if _blur then return end
	SFX.Play("MinigameStart")
	_blur = Instance.new("BlurEffect")
	_blur.Size = 0
	_blur.Parent = Lighting
	TweenService:Create(_blur, TweenInfo.new(0.3), { Size = 24 }):Play()
end

local function removeBlur()
	if not _blur then return end
	local b = _blur
	_blur = nil
	TweenService:Create(b, TweenInfo.new(0.25), { Size = 0 }):Play()
	task.delay(0.3, function() b:Destroy() end)
end

-- ── GUI builder ───────────────────────────────────────────────────────────
-- No card or scrim — just a transparent full-screen container over the blur.

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MinigameGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = gui

	return gui, container
end

local function showGui(gui)
	gui.Parent = Players.LocalPlayer.PlayerGui
end

-- ── Result overlay ────────────────────────────────────────────────────────

local function showResultOverlay(container, result)
	SFX.Play("Result" .. result)   -- e.g. ResultPerfect, ResultGood, ResultPass, ResultFail
	local col   = RESULT_COLORS[result]  or Color3.fromRGB(200, 200, 200)
	local label = RESULT_LABELS[result]  or result:upper()

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 100
	overlay.Parent = container

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Size = UDim2.new(0, 260, 0, 90)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	badge.ZIndex = 101
	badge.Parent = overlay
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 16)

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = col
	badgeStroke.Thickness = 2.5
	badgeStroke.Transparency = 1
	badgeStroke.Parent = badge

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = label
	textLabel.TextColor3 = col
	textLabel.TextTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 40
	textLabel.ZIndex = 102
	textLabel.Parent = badge

	-- Fade in
	TweenService:Create(overlay,     TweenInfo.new(0.20), { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(badge,       TweenInfo.new(0.20), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(badgeStroke, TweenInfo.new(0.20), { Transparency = 0 }):Play()
	TweenService:Create(textLabel,   TweenInfo.new(0.20), { TextTransparency = 0 }):Play()

	task.wait(1.1)
end

-- ── Perk effect applicator ────────────────────────────────────────────────
-- Applies active perk effects onto an already-built params table in-place.

local function applyPerkEffects(params, minigameName, activeEffects)
	if not activeEffects then return end
	if minigameName == "TackRemoval" then
		if activeEffects.approachTimeBonus then
			params.approachTime = params.approachTime + activeEffects.approachTimeBonus
		end
		if activeEffects.perfectMinProgressReduction then
			params.perfectMinProgress = math.max(0.05,
				params.perfectMinProgress - activeEffects.perfectMinProgressReduction)
		end
	elseif minigameName == "StapleGunning" then
		if activeEffects.zoneWidthMultiplier then
			params.goodZoneWidth    = params.goodZoneWidth    * activeEffects.zoneWidthMultiplier
			params.perfectZoneWidth = params.perfectZoneWidth * activeEffects.zoneWidthMultiplier
		end
		if activeEffects.barSpeedReduction then
			params.barSpeed = math.max(0.15, params.barSpeed - activeEffects.barSpeedReduction)
		end
	elseif minigameName == "SeamStitching" then
		if activeEffects.deviationToleranceBonus then
			params.deviationTolerance = params.deviationTolerance
				* (1 + activeEffects.deviationToleranceBonus)
		end
		if activeEffects.missBudgetBonus then
			params.missBudget = params.missBudget + activeEffects.missBudgetBonus
		end
	elseif minigameName == "FoamPadding" then
		if activeEffects.pieceCountReduction then
			params.pieceCount = math.max(1,
				params.pieceCount - activeEffects.pieceCountReduction)
		end
		if activeEffects.timeLimitBonus then
			params.timeLimit = params.timeLimit + activeEffects.timeLimitBonus
		end
	end
end

-- ── Difficulty param merger ───────────────────────────────────────────────
-- Merges GameConfig[minigameName] + difficulty overrides + perk effects into
-- config.params. Returns config unchanged only when none of these apply.

local function buildParams(minigameName, config)
	local difficulty    = config.difficulty
	local activeEffects = config.activeEffects

	-- If nothing modifies base values, let minigames use cfg directly (no allocation)
	if not difficulty and not activeEffects then return config end

	local overrides
	if type(difficulty) == "string" then
		local preset = GameConfig.DifficultyPresets[difficulty]
		if not preset then
			warn("[MinigameRunner] Unknown difficulty preset: '" .. difficulty .. "'")
		else
			overrides = preset[minigameName]
		end
	elseif type(difficulty) == "table" then
		overrides = difficulty[minigameName]
	end

	-- Build a mutable params table from base config
	local base   = GameConfig[minigameName]
	local params = {}
	for k, v in pairs(base) do params[k] = v end
	if overrides then
		for k, v in pairs(overrides) do params[k] = v end
	end

	applyPerkEffects(params, minigameName, activeEffects)

	local merged = {}
	for k, v in pairs(config) do merged[k] = v end
	merged.params = params
	return merged
end

-- ── Internal helpers ──────────────────────────────────────────────────────

local function requireModule(name)
	local m = MINIGAME_MODULES[name]
	assert(m, "MinigameRunner: unknown minigame '" .. name .. "'")
	return m
end

-- ── Public API ────────────────────────────────────────────────────────────

function MinigameRunner.IsRunning()
	return _activeMinigame ~= nil
end

function MinigameRunner.Cancel()
	if not _activeMinigame then return end
	_isCancelling = true
	_activeMinigame.Cancel()
end

function MinigameRunner.Run(minigameName, config)
	local merged = buildParams(minigameName, config)
	local gui, container = buildGui()
	addBlur()
	showGui(gui)
	local minigame = requireModule(minigameName)
	_activeMinigame = minigame
	_isCancelling   = false

	minigame.Start(container, merged)

	local wasCancelled = _isCancelling
	local result = minigame.GetResult()
	if not wasCancelled then
		showResultOverlay(container, result)
	end
	minigame.Cleanup()
	removeBlur()
	gui:Destroy()
	_activeMinigame = nil
	_isCancelling   = false

	return wasCancelled and nil or result
end

function MinigameRunner.RunChain(minigameNames, config)
	local gui, container = buildGui()
	addBlur()
	showGui(gui)
	local results = {}

	for _, name in ipairs(minigameNames) do
		for _, child in ipairs(container:GetChildren()) do
			child:Destroy()
		end

		local minigame = requireModule(name)
		local merged   = buildParams(name, config)
		_activeMinigame = minigame
		_isCancelling   = false

		minigame.Start(container, merged)

		local wasCancelled = _isCancelling
		local result = minigame.GetResult()
		minigame.Cleanup()
		_activeMinigame = nil
		_isCancelling   = false

		if wasCancelled then
			removeBlur()
			gui:Destroy()
			return nil
		end

		table.insert(results, result)
		showResultOverlay(container, result)
		task.wait(0.35)
	end

	removeBlur()
	gui:Destroy()
	return results
end

-- Collapse results into one job outcome.
-- Perfect rule: no failures AND at least ceil(2/3) of results are Perfect → job is Perfect.
-- Otherwise: worst result wins (Fail < Pass < Good < Perfect).
function MinigameRunner.CollapseChainResult(results)
	local ORDER = { Fail = 0, Pass = 1, Good = 2, Perfect = 3 }
	local n = #results
	if n == 0 then return "Pass" end

	local perfectCount = 0
	local hasFailure   = false
	local lowest       = 3

	for _, r in ipairs(results) do
		local rank = ORDER[r] or 1
		if rank < lowest then lowest = rank end
		if r == "Perfect" then
			perfectCount = perfectCount + 1
		elseif r == "Fail" then
			hasFailure = true
		end
	end

	-- 2/3 Perfect rule: no fails, and at least ceil(n * 2/3) results are Perfect
	if not hasFailure and perfectCount >= math.ceil(n * (2 / 3)) then
		return "Perfect"
	end

	-- Worst-result fallback
	for tier, rank in pairs(ORDER) do
		if rank == lowest then return tier end
	end
	return "Pass"
end

return MinigameRunner
