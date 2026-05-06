--[[
	DEV ONLY — Job acceptance test panel.
	Delete this file before shipping.

	Shows a panel with one button per job. Clicking fires AcceptJob to the server,
	which triggers the full loop: teleport → minigame → post → return.

	Toggle panel visibility: F7
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer

-- Wait for LaptopRemotes to exist (created by LaptopData on server start)
local Remotes   = ReplicatedStorage:WaitForChild("LaptopRemotes", 10)
local AcceptJob = Remotes and Remotes:WaitForChild("AcceptJob", 5)

-- ── Job list (mirrors STUB_JOBS in LaptopData) ────────────────────────────

local JOBS = {
	{ id = 1, name = "Two Seater Sofa",      tier = "Starter"  },
	{ id = 2, name = "Velvet Loveseat",      tier = "Mid"      },
	{ id = 3, name = "Ottoman Suite",        tier = "Premium"  },
	{ id = 4, name = "Bar Stool Set ×4",     tier = "Mid"      },
	{ id = 5, name = "Antique Armchair",     tier = "Premium"  },
}

local TIER_COLORS = {
	Starter  = Color3.fromRGB(80,  140, 80),
	Mid      = Color3.fromRGB(60,  110, 180),
	Premium  = Color3.fromRGB(160, 80,  180),
	Prestige = Color3.fromRGB(200, 150, 40),
}

-- ── Build GUI ─────────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "DevJobPanel"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name              = "Panel"
panel.Size              = UDim2.new(0, 240, 0, 0)
panel.Position          = UDim2.new(1, -252, 0, 12)
panel.BackgroundColor3  = Color3.fromRGB(25, 22, 35)
panel.BorderSizePixel   = 0
panel.AutomaticSize     = Enum.AutomaticSize.Y
panel.Parent            = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding   = UDim.new(0, 4)
layout.Parent    = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop    = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft   = UDim.new(0, 8)
padding.PaddingRight  = UDim.new(0, 8)
padding.Parent        = panel

-- Header
local header = Instance.new("TextLabel")
header.Size                 = UDim2.new(1, 0, 0, 20)
header.BackgroundTransparency = 1
header.Text                 = "🛠 JOB TESTER"
header.TextColor3           = Color3.fromRGB(200, 170, 80)
header.Font                 = Enum.Font.GothamBold
header.TextSize             = 12
header.LayoutOrder          = 0
header.Parent               = panel

local hint = Instance.new("TextLabel")
hint.Size                   = UDim2.new(1, 0, 0, 16)
hint.BackgroundTransparency = 1
hint.Text                   = "F7 to hide  •  full loop test"
hint.TextColor3             = Color3.fromRGB(120, 110, 140)
hint.Font                   = Enum.Font.Gotham
hint.TextSize               = 10
hint.LayoutOrder            = 1
hint.Parent                 = panel

local sep = Instance.new("Frame")
sep.Size             = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(80, 70, 100)
sep.BorderSizePixel  = 0
sep.LayoutOrder      = 2
sep.Parent           = panel

-- ── Job buttons ───────────────────────────────────────────────────────────

local _busy = false  -- block double-accepts while a job is running

for i, job in ipairs(JOBS) do
	local tierColor = TIER_COLORS[job.tier] or Color3.fromRGB(80, 80, 80)

	local row = Instance.new("Frame")
	row.Name             = "JobRow_" .. job.id
	row.Size             = UDim2.new(1, 0, 0, 46)
	row.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
	row.BorderSizePixel  = 0
	row.LayoutOrder      = i + 2
	row.Parent           = panel
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	-- Tier colour strip on left
	local strip = Instance.new("Frame")
	strip.Name             = "TierStrip"
	strip.Size             = UDim2.new(0, 4, 1, 0)
	strip.BackgroundColor3 = tierColor
	strip.BorderSizePixel  = 0
	strip.Parent           = row
	Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 4)

	-- Job name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                 = UDim2.new(1, -70, 0, 20)
	nameLabel.Position             = UDim2.new(0, 12, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                 = job.name
	nameLabel.TextColor3           = Color3.fromRGB(240, 235, 220)
	nameLabel.Font                 = Enum.Font.GothamMedium
	nameLabel.TextSize             = 11
	nameLabel.TextXAlignment       = Enum.TextXAlignment.Left
	nameLabel.TextTruncate         = Enum.TextTruncate.AtEnd
	nameLabel.Parent               = row

	-- Tier label
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size                 = UDim2.new(1, -12, 0, 14)
	tierLabel.Position             = UDim2.new(0, 12, 0, 24)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text                 = job.tier
	tierLabel.TextColor3           = tierColor
	tierLabel.Font                 = Enum.Font.Gotham
	tierLabel.TextSize             = 10
	tierLabel.TextXAlignment       = Enum.TextXAlignment.Left
	tierLabel.Parent               = row

	-- Accept button
	local btn = Instance.new("TextButton")
	btn.Name             = "AcceptBtn"
	btn.Size             = UDim2.new(0, 54, 0, 28)
	btn.Position         = UDim2.new(1, -62, 0.5, -14)
	btn.BackgroundColor3 = tierColor
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.Font             = Enum.Font.GothamBold
	btn.TextSize         = 11
	btn.Text             = "Accept"
	btn.BorderSizePixel  = 0
	btn.AutoButtonColor  = true
	btn.Parent           = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	local jobId = job.id

	btn.Activated:Connect(function()
		if _busy then return end
		if not AcceptJob then
			warn("[DevJobPanel] AcceptJob remote not found")
			return
		end

		_busy = true
		btn.Text             = "..."
		btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)

		AcceptJob:FireServer(jobId)

		-- Re-enable after a delay so we can accept another job after the loop
		task.delay(4, function()
			_busy = false
			btn.Text             = "Accept"
			btn.BackgroundColor3 = tierColor
		end)
	end)
end

-- ── F7 toggle ─────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.F7 then
		screenGui.Enabled = not screenGui.Enabled
	end
end)
