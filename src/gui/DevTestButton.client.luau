--[[
	DEV ONLY — MinigameRunner test harness.
	Delete this file before shipping.

	Shows a small panel in the corner with buttons to launch each minigame.
	Also lets you toggle the Fragile modifier to test tighter precision windows.
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Only show in Studio
if not RunService:IsStudio() then
	return
end

local MinigameRunner = require(Players.LocalPlayer:WaitForChild("PlayerScripts")
	:WaitForChild("Client")
	:WaitForChild("Minigames")
	:WaitForChild("MinigameRunner"))

-- ── Build the dev panel ──────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevMinigamePanel"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 220, 0, 0)  -- height auto-grows via UIListLayout
panel.Position = UDim2.new(0, 12, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(25, 22, 35)
panel.BorderSizePixel = 0
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop    = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft   = UDim.new(0, 8)
padding.PaddingRight  = UDim.new(0, 8)
padding.Parent = panel

-- ── Helper: make a button ────────────────────────────────────────────────────

local function makeButton(labelText: string, layoutOrder: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = labelText
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = Color3.fromRGB(70, 60, 110)
	btn.TextColor3 = Color3.fromRGB(245, 238, 220)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.Text = labelText
	btn.LayoutOrder = layoutOrder
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = btn

	btn.Parent = panel
	return btn
end

-- ── Header label ─────────────────────────────────────────────────────────────

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 20)
header.BackgroundTransparency = 1
header.Text = "🛠 MINIGAME TESTER"
header.TextColor3 = Color3.fromRGB(200, 170, 80)
header.Font = Enum.Font.GothamBold
header.TextSize = 12
header.LayoutOrder = 0
header.Parent = panel

-- ── Fragile toggle ───────────────────────────────────────────────────────────

local fragileOn = false
local fragileBtn = makeButton("Fragile modifier: OFF", 1)
fragileBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 70)

fragileBtn.Activated:Connect(function()
	fragileOn = not fragileOn
	fragileBtn.Text = "Fragile modifier: " .. (fragileOn and "ON" or "OFF")
	fragileBtn.BackgroundColor3 = fragileOn
		and Color3.fromRGB(150, 50, 50)
		or  Color3.fromRGB(50, 45, 70)
end)

-- ── Separator ────────────────────────────────────────────────────────────────

local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(80, 70, 100)
sep.BorderSizePixel = 0
sep.LayoutOrder = 2
sep.Parent = panel

-- ── Minigame buttons ─────────────────────────────────────────────────────────

local MINIGAMES = {
	{ name = "TackRemoval",   label = "Tack Removal",   order = 3 },
	{ name = "StapleGunning", label = "Staple Gunning", order = 4 },
	{ name = "SeamStitching", label = "Seam Stitching", order = 5 },
	{ name = "FoamPadding",   label = "Foam Padding",   order = 6 },
}

-- Track whether a minigame is currently running so buttons can be locked
local running = false

local function runMinigame(name: string)
	if running then return end
	running = true

	local config: MinigameRunner.MinigameConfig = {
		fragile   = fragileOn,
		toolBonus = 0,
	}

	-- task.spawn so we don't block the button callback thread
	task.spawn(function()
		local ok, result = pcall(function()
			return MinigameRunner.Run(name, config)
		end)

		if ok then
			print(("[DEV] %s finished → %s"):format(name, result))
		else
			warn(("[DEV] %s errored: %s"):format(name, tostring(result)))
		end

		running = false
	end)
end

for _, entry in ipairs(MINIGAMES) do
	local btn = makeButton(entry.label, entry.order)
	btn.Activated:Connect(function()
		runMinigame(entry.name)
	end)
end

-- ── Chain test button ─────────────────────────────────────────────────────────

local sepChain = Instance.new("Frame")
sepChain.Size = UDim2.new(1, 0, 0, 1)
sepChain.BackgroundColor3 = Color3.fromRGB(80, 70, 100)
sepChain.BorderSizePixel = 0
sepChain.LayoutOrder = 7
sepChain.Parent = panel

local chainBtn = makeButton("Chain: Tack → Staple", 8)
chainBtn.Activated:Connect(function()
	if running then return end
	running = true

	local config: MinigameRunner.MinigameConfig = {
		fragile   = fragileOn,
		toolBonus = 0,
	}

	task.spawn(function()
		local ok, results = pcall(function()
			return MinigameRunner.RunChain({"TackRemoval", "StapleGunning"}, config)
		end)

		if ok then
			local overall = MinigameRunner.CollapseChainResult(results :: any)
			print(("[DEV] Chain finished → %s (individual: %s)"):format(
				overall,
				table.concat(results :: any, ", ")
			))
		else
			warn(("[DEV] Chain errored: %s"):format(tostring(results)))
		end

		running = false
	end)
end)

-- ── F8 toggle to show/hide the panel ──────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.F8 then
		screenGui.Enabled = not screenGui.Enabled
	end
end)
