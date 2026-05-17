-- Developer admin panel — toggle with F12.

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("ReplicatedStorage")

local player     = Players.LocalPlayer
local remotes    = RS:WaitForChild("LaptopRemotes")
local GameConfig = require(RS:WaitForChild("Shared"):WaitForChild("GameConfig"))

local AdminSpawnJob        = remotes:WaitForChild("AdminSpawnJob")
local AdminRequestLocations = remotes:WaitForChild("AdminRequestLocations")

-- Tiers pulled from GameConfig in a fixed display order
local TIER_ORDER = { "Starter", "Mid", "Premium", "Prestige", "Exclusive", "Elite", "Special" }
local TIERS = {}
for _, tier in ipairs(TIER_ORDER) do
	if GameConfig.JobTierRarity[tier] then
		table.insert(TIERS, tier)
	end
end

-- Location names pulled from the server (ServerStorage scan)
local LOCATIONS = { "Any" }
local serverNames = AdminRequestLocations:InvokeServer()
if serverNames then
	for _, name in ipairs(serverNames) do
		table.insert(LOCATIONS, name)
	end
end

local C = {
	bg      = Color3.fromRGB(12, 12, 18),
	surface = Color3.fromRGB(20, 22, 30),
	border  = Color3.fromRGB(40, 45, 60),
	text    = Color3.fromRGB(210, 218, 235),
	sub     = Color3.fromRGB(110, 120, 150),
	btn     = Color3.fromRGB(50, 80, 160),
	green   = Color3.fromRGB(60, 190, 90),
	title   = Color3.fromRGB(18, 20, 30),
}

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(r, p) make("UICorner", { CornerRadius = UDim.new(0, r) }, p) end

-- ── Root ──────────────────────────────────────────────────────────────────

local gui = make("ScreenGui", {
	Name           = "AdminPanel",
	DisplayOrder   = 99,
	ResetOnSpawn   = false,
	IgnoreGuiInset = true,
}, player:WaitForChild("PlayerGui"))

local panel = make("Frame", {
	Size             = UDim2.new(0, 270, 0, 210),
	Position         = UDim2.new(0, 14, 0, 14),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
	Visible          = true,
}, gui)
corner(8, panel)
make("UIStroke", { Color = C.border, Thickness = 1 }, panel)

-- ── Title bar ─────────────────────────────────────────────────────────────

local titleBar = make("Frame", {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.title,
	BorderSizePixel  = 0,
}, panel)
corner(8, titleBar)
make("Frame", {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = C.title,
	BorderSizePixel  = 0,
}, titleBar)
make("TextLabel", {
	Size                 = UDim2.new(1, -10, 1, 0),
	Position             = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1,
	Text                 = "DEV PANEL  •  F12",
	TextColor3           = C.sub,
	Font                 = Enum.Font.GothamBold,
	TextSize             = 11,
	TextXAlignment       = Enum.TextXAlignment.Left,
}, titleBar)

-- ── Body ──────────────────────────────────────────────────────────────────

local body = make("Frame", {
	Size                 = UDim2.new(1, -20, 1, -44),
	Position             = UDim2.new(0, 10, 0, 36),
	BackgroundTransparency = 1,
}, panel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder     = Enum.SortOrder.LayoutOrder,
	Padding       = UDim.new(0, 8),
}, body)

-- ── Dropdown builder ──────────────────────────────────────────────────────

local function makeDropdown(parent, labelText, options, order)
	local row = make("Frame", {
		Size                 = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder          = order,
	}, parent)
	make("UIListLayout", {
		FillDirection     = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder         = Enum.SortOrder.LayoutOrder,
		Padding           = UDim.new(0, 6),
	}, row)

	make("TextLabel", {
		Size                 = UDim2.new(0, 68, 1, 0),
		BackgroundTransparency = 1,
		Text                 = labelText,
		TextColor3           = C.sub,
		Font                 = Enum.Font.Gotham,
		TextSize             = 12,
		TextXAlignment       = Enum.TextXAlignment.Left,
		LayoutOrder          = 1,
	}, row)

	local box = make("Frame", {
		Size             = UDim2.new(1, -74, 1, 0),
		BackgroundColor3 = C.surface,
		BorderSizePixel  = 0,
		LayoutOrder      = 2,
	}, row)
	corner(5, box)
	make("UIStroke", { Color = C.border, Thickness = 1 }, box)

	local valLabel = make("TextLabel", {
		Size                 = UDim2.new(1, -52, 1, 0),
		Position             = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text                 = options[1],
		TextColor3           = C.text,
		Font                 = Enum.Font.GothamMedium,
		TextSize             = 12,
		TextXAlignment       = Enum.TextXAlignment.Left,
	}, box)

	local btnUp = make("TextButton", {
		Size             = UDim2.new(0, 20, 0, 18),
		Position         = UDim2.new(1, -44, 0.5, -9),
		BackgroundColor3 = C.border,
		BorderSizePixel  = 0,
		Text             = "▲",
		TextColor3       = C.text,
		Font             = Enum.Font.GothamBold,
		TextSize         = 9,
	}, box)
	corner(3, btnUp)

	local btnDown = make("TextButton", {
		Size             = UDim2.new(0, 20, 0, 18),
		Position         = UDim2.new(1, -22, 0.5, -9),
		BackgroundColor3 = C.border,
		BorderSizePixel  = 0,
		Text             = "▼",
		TextColor3       = C.text,
		Font             = Enum.Font.GothamBold,
		TextSize         = 9,
	}, box)
	corner(3, btnDown)

	local index = 1
	btnUp.Activated:Connect(function()
		index = (index - 2) % #options + 1
		valLabel.Text = options[index]
	end)
	btnDown.Activated:Connect(function()
		index = index % #options + 1
		valLabel.Text = options[index]
	end)

	return function() return options[index] end
end

local getTier     = makeDropdown(body, "Tier",     TIERS,     1)
local getLocation = makeDropdown(body, "Location", LOCATIONS, 2)

-- ── Divider ───────────────────────────────────────────────────────────────

make("Frame", {
	Size             = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.border,
	BorderSizePixel  = 0,
	LayoutOrder      = 3,
}, body)

-- ── Spawn button ──────────────────────────────────────────────────────────

local spawnBtn = make("TextButton", {
	Size             = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = C.btn,
	BorderSizePixel  = 0,
	Text             = "SPAWN JOB",
	TextColor3       = Color3.new(1, 1, 1),
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	LayoutOrder      = 4,
}, body)
corner(6, spawnBtn)

local statusLabel = make("TextLabel", {
	Size                 = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text                 = "",
	TextColor3           = C.green,
	Font                 = Enum.Font.Gotham,
	TextSize             = 11,
	TextXAlignment       = Enum.TextXAlignment.Left,
	LayoutOrder          = 5,
}, body)

-- ── Spawn handler ─────────────────────────────────────────────────────────

local _cooldown = false
spawnBtn.Activated:Connect(function()
	if _cooldown then return end
	_cooldown = true
	spawnBtn.BackgroundColor3 = C.border

	local tier   = getTier()
	local loc    = getLocation()
	local locArg = (loc == "Any") and nil or loc

	AdminSpawnJob:FireServer(tier, locArg)
	statusLabel.Text = "✓ " .. tier .. (locArg and (" → " .. locArg) or "  (any slot)")

	task.wait(0.8)
	spawnBtn.BackgroundColor3 = C.btn
	_cooldown = false
end)

-- ── F12 toggle ────────────────────────────────────────────────────────────

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F12 then
		panel.Visible = not panel.Visible
	end
end)
