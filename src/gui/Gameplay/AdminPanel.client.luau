-- Developer admin panel — toggle with F5.
-- Spawn jobs by location · set rep · grant USD.

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("ReplicatedStorage")

local player     = Players.LocalPlayer
local remotes    = RS:WaitForChild("LaptopRemotes")
local GameConfig = require(RS:WaitForChild("Shared"):WaitForChild("GameConfig"))

local AdminSpawnJob           = remotes:WaitForChild("AdminSpawnJob")
local AdminRequestLocations   = remotes:WaitForChild("AdminRequestLocations")
local RequestLocationsByTier  = remotes:WaitForChild("RequestLocationsByTier")
local AdminSetStat            = remotes:WaitForChild("AdminSetStat")

-- Location list and tier lookup both sourced from server (Tier attribute is authoritative)
local locationTier = {}
local LOCATIONS    = { "Any" }
local serverNames  = AdminRequestLocations:InvokeServer()
if serverNames then
	for _, n in ipairs(serverNames) do table.insert(LOCATIONS, n) end
end
local byTier = RequestLocationsByTier:InvokeServer()
if byTier then
	for tier, names in pairs(byTier) do
		for _, n in ipairs(names) do locationTier[n] = tier end
	end
end

-- ── Colors ────────────────────────────────────────────────────────────────

local C = {
	bg      = Color3.fromRGB(12, 12, 18),
	surface = Color3.fromRGB(20, 22, 30),
	hover   = Color3.fromRGB(32, 36, 50),
	border  = Color3.fromRGB(40, 45, 60),
	text    = Color3.fromRGB(210, 218, 235),
	sub     = Color3.fromRGB(110, 120, 150),
	btn     = Color3.fromRGB(50, 80, 160),
	green   = Color3.fromRGB(60, 190, 90),
	red     = Color3.fromRGB(200, 70, 70),
	title   = Color3.fromRGB(18, 20, 30),
}

-- ── Helpers ───────────────────────────────────────────────────────────────

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
	Size             = UDim2.fromOffset(280, 226),
	Position         = UDim2.new(1, -14, 1, -14),
	AnchorPoint      = Vector2.new(1, 1),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
	Visible          = true,
}, gui)
corner(8, panel)
make("UIStroke", { Color = C.border, Thickness = 1 }, panel)

-- Title bar
local titleBar = make("Frame", {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.title,
	BorderSizePixel  = 0,
}, panel)
corner(8, titleBar)
make("Frame", {  -- cover rounded bottom corners
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = C.title,
	BorderSizePixel  = 0,
}, titleBar)
make("TextLabel", {
	Size               = UDim2.new(1, -10, 1, 0),
	Position           = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Text               = "DEV PANEL  •  F5",
	TextColor3         = C.sub,
	Font               = Enum.Font.GothamBold,
	TextSize           = 11,
	TextXAlignment     = Enum.TextXAlignment.Left,
}, titleBar)

-- Body frame (UIListLayout child)
local body = make("Frame", {
	Size               = UDim2.new(1, -20, 1, -44),
	Position           = UDim2.fromOffset(10, 36),
	BackgroundTransparency = 1,
}, panel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder     = Enum.SortOrder.LayoutOrder,
	Padding       = UDim.new(0, 6),
}, body)
make("UIPadding", {
	PaddingTop    = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
}, body)

-- Forward declaration — makeStatRow callbacks reference this after creation
local statusLabel

-- ── Dropdown ──────────────────────────────────────────────────────────────
-- Overlay is a direct child of `panel` so its ZIndex beats body siblings.

local function makeDropdown(options, layoutOrder)
	local wrapper = make("Frame", {
		Size               = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder        = layoutOrder,
	}, body)

	local btn = make("TextButton", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.surface,
		BorderSizePixel  = 0,
		Text             = "",
		ZIndex           = 2,
	}, wrapper)
	corner(5, btn)
	make("UIStroke", { Color = C.border, Thickness = 1 }, btn)

	local valueLabel = make("TextLabel", {
		Size               = UDim2.new(1, -28, 1, 0),
		Position           = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text               = options[1],
		TextColor3         = C.text,
		Font               = Enum.Font.GothamMedium,
		TextSize           = 12,
		TextXAlignment     = Enum.TextXAlignment.Left,
		ZIndex             = 3,
	}, btn)

	make("TextLabel", {
		Size               = UDim2.fromOffset(18, 18),
		Position           = UDim2.new(1, -22, 0.5, -9),
		BackgroundTransparency = 1,
		Text               = "▼",
		TextColor3         = C.sub,
		Font               = Enum.Font.GothamBold,
		TextSize           = 9,
		ZIndex             = 3,
	}, btn)

	-- Overlay: child of panel, not body, so it renders above body siblings
	local ITEM_H   = 24
	local visCount = math.min(#options, 5)
	local overlay  = make("Frame", {
		Size             = UDim2.fromOffset(260, visCount * ITEM_H),
		BackgroundColor3 = C.surface,
		BorderSizePixel  = 0,
		Visible          = false,
		ZIndex           = 8,
		ClipsDescendants = true,
	}, panel)
	corner(5, overlay)
	make("UIStroke", { Color = C.border, Thickness = 1 }, overlay)

	local scroll = make("ScrollingFrame", {
		Size                 = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel      = 0,
		ScrollBarThickness   = 4,
		ScrollBarImageColor3 = C.border,
		CanvasSize           = UDim2.fromOffset(0, #options * ITEM_H),
		ZIndex               = 8,
	}, overlay)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	local selected  = options[1]
	local closeConn

	local function closeOverlay()
		overlay.Visible = false
		if closeConn then closeConn:Disconnect(); closeConn = nil end
	end

	for idx, opt in ipairs(options) do
		local item = make("TextButton", {
			Size             = UDim2.new(1, 0, 0, ITEM_H),
			BackgroundColor3 = C.surface,
			BorderSizePixel  = 0,
			Text             = "  " .. opt,
			TextColor3       = C.text,
			Font             = Enum.Font.Gotham,
			TextSize         = 12,
			TextXAlignment   = Enum.TextXAlignment.Left,
			LayoutOrder      = idx,
			ZIndex           = 9,
		}, scroll)
		item.MouseEnter:Connect(function() item.BackgroundColor3 = C.hover end)
		item.MouseLeave:Connect(function() item.BackgroundColor3 = C.surface end)
		item.Activated:Connect(function()
			selected = opt
			valueLabel.Text = opt
			closeOverlay()
		end)
	end

	btn.Activated:Connect(function()
		if overlay.Visible then closeOverlay(); return end

		local bp = btn.AbsolutePosition
		local pp = panel.AbsolutePosition
		overlay.Position = UDim2.fromOffset(bp.X - pp.X, bp.Y - pp.Y + btn.AbsoluteSize.Y + 2)
		overlay.Visible = true

		closeConn = UIS.InputBegan:Connect(function(inp)
			if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			task.wait()  -- let item.Activated fire before the outside-click check
			if not overlay.Visible then return end
			local mp = UIS:GetMouseLocation()
			local op, os = overlay.AbsolutePosition, overlay.AbsoluteSize
			if mp.X < op.X or mp.X > op.X + os.X or mp.Y < op.Y or mp.Y > op.Y + os.Y then
				closeOverlay()
			end
		end)
	end)

	return function() return selected end
end

-- ── Stat input row ────────────────────────────────────────────────────────

local function makeStatRow(labelText, placeholder, btnText, btnColor, layoutOrder, onSubmit)
	local row = make("Frame", {
		Size               = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder        = layoutOrder,
	}, body)
	make("UIListLayout", {
		FillDirection     = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding           = UDim.new(0, 6),
	}, row)

	make("TextLabel", {
		Size               = UDim2.fromOffset(32, 28),
		BackgroundTransparency = 1,
		Text               = labelText,
		TextColor3         = C.sub,
		Font               = Enum.Font.Gotham,
		TextSize           = 12,
		TextXAlignment     = Enum.TextXAlignment.Left,
		LayoutOrder        = 1,
	}, row)

	local box = make("TextBox", {
		Size              = UDim2.new(1, -110, 1, 0),
		BackgroundColor3  = C.surface,
		BorderSizePixel   = 0,
		Text              = "",
		PlaceholderText   = placeholder,
		TextColor3        = C.text,
		PlaceholderColor3 = C.sub,
		Font              = Enum.Font.Gotham,
		TextSize          = 12,
		ClearTextOnFocus  = false,
		LayoutOrder       = 2,
	}, row)
	corner(5, box)
	make("UIStroke", { Color = C.border, Thickness = 1 }, box)

	local submitBtn = make("TextButton", {
		Size             = UDim2.fromOffset(66, 26),
		BackgroundColor3 = btnColor,
		BorderSizePixel  = 0,
		Text             = btnText,
		TextColor3       = Color3.new(1, 1, 1),
		Font             = Enum.Font.GothamBold,
		TextSize         = 11,
		LayoutOrder      = 3,
	}, row)
	corner(5, submitBtn)

	local function submit()
		local val = tonumber(box.Text)
		if val then
			onSubmit(val)
			box.Text = ""
		else
			if statusLabel then
				statusLabel.TextColor3 = C.red
				statusLabel.Text = "✗ enter a number"
			end
		end
	end

	submitBtn.Activated:Connect(submit)
	box.FocusLost:Connect(function(enter) if enter then submit() end end)
end

-- ── Controls ──────────────────────────────────────────────────────────────

local getLocation = makeDropdown(LOCATIONS, 1)

local spawnBtn = make("TextButton", {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.btn,
	BorderSizePixel  = 0,
	Text             = "SPAWN JOB",
	TextColor3       = Color3.new(1, 1, 1),
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	LayoutOrder      = 2,
}, body)
corner(6, spawnBtn)

make("Frame", {  -- divider
	Size             = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.border,
	BorderSizePixel  = 0,
	LayoutOrder      = 3,
}, body)

makeStatRow("Rep", "0 – 5", "SET REP", Color3.fromRGB(60, 140, 80), 4, function(val)
	val = math.clamp(val, 0, 5)
	AdminSetStat:FireServer("reputation", val)
	if statusLabel then
		statusLabel.TextColor3 = C.green
		statusLabel.Text = string.format("✓ rep → %.2f", val)
	end
end)

makeStatRow("USD", "amount", "GRANT $", Color3.fromRGB(140, 100, 30), 5, function(val)
	val = math.max(0, math.floor(val))
	AdminSetStat:FireServer("usd", val)
	if statusLabel then
		statusLabel.TextColor3 = C.green
		statusLabel.Text = string.format("✓ +$%d granted", val)
	end
end)

make("Frame", {  -- divider
	Size             = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.border,
	BorderSizePixel  = 0,
	LayoutOrder      = 6,
}, body)

statusLabel = make("TextLabel", {
	Size               = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Text               = "",
	TextColor3         = C.green,
	Font               = Enum.Font.Gotham,
	TextSize           = 11,
	TextXAlignment     = Enum.TextXAlignment.Left,
	LayoutOrder        = 7,
}, body)

-- ── Spawn handler ─────────────────────────────────────────────────────────

local _cooldown = false
spawnBtn.Activated:Connect(function()
	if _cooldown then return end
	_cooldown = true
	spawnBtn.BackgroundColor3 = C.border

	local loc    = getLocation()
	local locArg = (loc == "Any") and nil or loc
	local tier   = (locArg and locationTier[locArg]) or "Starter"

	AdminSpawnJob:FireServer(tier, locArg)
	if statusLabel then
		statusLabel.TextColor3 = C.green
		statusLabel.Text = "✓ " .. tier .. " job" .. (locArg and (" @ " .. locArg) or " (any)")
	end

	task.wait(0.8)
	spawnBtn.BackgroundColor3 = C.btn
	_cooldown = false
end)

-- ── F5 toggle ─────────────────────────────────────────────────────────────

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F5 then
		panel.Visible = not panel.Visible
	end
end)
