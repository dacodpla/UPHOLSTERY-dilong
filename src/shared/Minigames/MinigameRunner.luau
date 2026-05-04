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

local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local Players      = game:GetService("Players")
local SFX          = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SFXPlayer"))

-- ── Module registry ───────────────────────────────────────────────────────
local MINIGAME_MODULES = {
	TackRemoval   = script.Parent.TackRemoval,
	StapleGunning = script.Parent.StapleGunning,
	SeamStitching = script.Parent.SeamStitching,
	FoamPadding   = script.Parent.FoamPadding,
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

-- ── Blur management ───────────────────────────────────────────────────────

local _blur = nil

local function addBlur()
	if _blur then return end
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

-- ── Internal helpers ──────────────────────────────────────────────────────

local function requireModule(name)
	local moduleRef = MINIGAME_MODULES[name]
	assert(moduleRef, "MinigameRunner: unknown minigame '" .. name .. "'")
	return require(moduleRef)
end

-- ── Public API ────────────────────────────────────────────────────────────

function MinigameRunner.Run(minigameName, config)
	local gui, container = buildGui()
	addBlur()
	showGui(gui)
	local minigame = requireModule(minigameName)

	minigame.Start(container, config)

	local result = minigame.GetResult()
	showResultOverlay(container, result)
	minigame.Cleanup()
	removeBlur()
	gui:Destroy()

	return result
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
		minigame.Start(container, config)
		local result = minigame.GetResult()
		table.insert(results, result)
		showResultOverlay(container, result)
		minigame.Cleanup()

		task.wait(0.35)
	end

	removeBlur()
	gui:Destroy()
	return results
end

-- Collapse chain: worst result wins. Fail < Pass < Good < Perfect.
function MinigameRunner.CollapseChainResult(results)
	local ORDER = { Fail = 0, Pass = 1, Good = 2, Perfect = 3 }
	local lowest = 3
	for _, r in ipairs(results) do
		local rank = ORDER[r]
		if rank ~= nil and rank < lowest then
			lowest = rank
		end
	end
	for tier, rank in pairs(ORDER) do
		if rank == lowest then
			return tier
		end
	end
	return "Pass"
end

return MinigameRunner
