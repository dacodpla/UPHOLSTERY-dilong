--[[
	Toolbox
	Standalone floating panel — press G to open/close.
	Completely independent of the laptop system.

	Layout (280×380 panel, screen-centre):
	  ┌──────────────────────────────┐
	  │ TOOLBOX              [G] [×] │
	  ├──────────────────────────────┤
	  │  [ Slot 1 ] [ Slot 2 ] [ Slot 3 ]  ← active slots
	  │       [ Slot 4 ] [ Slot 5 ]
	  ├──────────────────────────────┤
	  │ Owned Tools and Perks        │
	  │  Curved Needle Bolt ×2 [Eq] │  ← scrollable
	  │  Foam Press Kit Bolt ×1 [Eq]│
	  └──────────────────────────────┘

	Equip: click [Eq] → equips to first free unlocked slot
	Unequip: click an occupied slot card → clears it
	Locked slots (beyond maxSlots) are greyed out
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS              = game:GetService("UserInputService")

local Player = Players.LocalPlayer

local ShopData = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Data")
		:WaitForChild("ShopData")
)

local Remotes          = ReplicatedStorage:WaitForChild("LaptopRemotes")
local GetLoadout       = Remotes:WaitForChild("GetLoadout")
local EquipPerk        = Remotes:WaitForChild("EquipPerk")
local UnequipPerk      = Remotes:WaitForChild("UnequipPerk")
local LoadoutChanged   = Remotes:WaitForChild("LoadoutChanged")

-- ── Colours ───────────────────────────────────────────────────────────────────

local C_BG       = Color3.fromRGB(14, 12, 22)
local C_PANEL    = Color3.fromRGB(22, 19, 34)
local C_CARD     = Color3.fromRGB(32, 28, 46)
local C_CARD_ON  = Color3.fromRGB(50, 40, 72)
local C_LOCKED   = Color3.fromRGB(20, 18, 28)
local C_GOLD     = Color3.fromRGB(255, 210, 60)
local C_TEAL     = Color3.fromRGB(70, 195, 195)
local C_RED      = Color3.fromRGB(200, 70, 70)
local C_WHITE    = Color3.fromRGB(230, 225, 240)
local C_MUTED    = Color3.fromRGB(115, 108, 140)
local C_BTN      = Color3.fromRGB(55, 45, 82)
local C_BTN_HOV  = Color3.fromRGB(78, 64, 112)
local C_CLOSE    = Color3.fromRGB(90, 40, 40)
local C_STROKE   = Color3.fromRGB(50, 44, 70)

-- ── State ─────────────────────────────────────────────────────────────────────

local _loadout  = { "", "", "", "", "" }
local _charges  = {}
local _maxSlots = 3

-- ── Build ScreenGui ───────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name            = "ToolboxGui"
gui.DisplayOrder    = 15
gui.ResetOnSpawn    = false
gui.IgnoreGuiInset  = true
gui.Enabled         = false
gui.Parent          = Player:WaitForChild("PlayerGui")

-- Panel (280 × 390, centred slightly above middle)
local panel = Instance.new("Frame")
panel.Size             = UDim2.new(0, 280, 0, 390)
panel.Position         = UDim2.new(0.5, -140, 0.5, -210)
panel.BackgroundColor3 = C_BG
panel.BorderSizePixel  = 0
panel.Parent           = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent       = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = C_STROKE
panelStroke.Thickness = 1.5
panelStroke.Parent    = panel

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function lbl(props, parent)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextScaled = false
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function btn(props, parent)
	local b = Instance.new("TextButton")
	b.BorderSizePixel  = 0
	b.AutoButtonColor  = false
	b.TextScaled       = false
	for k, v in pairs(props) do b[k] = v end
	b.Parent = parent
	return b
end

local function corner(r, parent)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function hline(y, parent)
	local d = Instance.new("Frame")
	d.Size             = UDim2.new(1, -16, 0, 1)
	d.Position         = UDim2.new(0, 8, 0, y)
	d.BackgroundColor3 = C_STROKE
	d.BorderSizePixel  = 0
	d.Parent           = parent
end

-- ── Header ────────────────────────────────────────────────────────────────────

local HEADER_H = 36
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
header.BorderSizePixel  = 0
header.Parent           = panel
corner(10, header)
-- mask bottom corners of header so only top is rounded
local headerMask = Instance.new("Frame")
headerMask.Size             = UDim2.new(1, 0, 0.5, 0)
headerMask.Position         = UDim2.new(0, 0, 0.5, 0)
headerMask.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
headerMask.BorderSizePixel  = 0
headerMask.Parent           = header

lbl({
	Size           = UDim2.new(0, 160, 1, 0),
	Position       = UDim2.new(0, 12, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text           = "TOOLBOX",
	Font           = Enum.Font.GothamBold,
	TextSize       = 14,
	TextColor3     = C_GOLD,
}, header)

local slotsInfoLbl = lbl({
	Size           = UDim2.new(0, 60, 1, 0),
	Position       = UDim2.new(0, 160, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text           = "3 / 5 slots",
	Font           = Enum.Font.Gotham,
	TextSize       = 10,
	TextColor3     = C_MUTED,
}, header)

-- Close button
local closeBtn = btn({
	Size             = UDim2.new(0, 28, 0, 22),
	Position         = UDim2.new(1, -34, 0.5, -11),
	BackgroundColor3 = C_CLOSE,
	Text             = "×",
	Font             = Enum.Font.GothamBold,
	TextSize         = 16,
	TextColor3       = Color3.fromRGB(220, 140, 140),
}, header)
corner(5, closeBtn)
closeBtn.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

-- ── Slots section ─────────────────────────────────────────────────────────────

local SLOTS_Y  = HEADER_H + 6
local SLOT_W   = 72
local SLOT_H   = 54
local SLOT_PAD = 6
local SLOTS_H  = SLOT_H * 2 + SLOT_PAD + 18   -- two rows + padding

local _slotCards = {}

local function buildSlot(index, xAbs, yAbs)
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, SLOT_W, 0, SLOT_H)
	card.Position         = UDim2.new(0, xAbs, 0, yAbs)
	card.BackgroundColor3 = C_CARD
	card.BorderSizePixel  = 0
	card.Parent           = panel
	corner(7, card)

	lbl({
		Size           = UDim2.new(1, 0, 0, 14),
		Position       = UDim2.new(0, 0, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text           = "Slot " .. index,
		Font           = Enum.Font.Gotham,
		TextSize       = 9,
		TextColor3     = C_MUTED,
	}, card)

	local nameLbl = lbl({
		Size           = UDim2.new(1, -4, 0, 22),
		Position       = UDim2.new(0, 2, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped    = true,
		Text           = "—",
		Font           = Enum.Font.GothamBold,
		TextSize       = 10,
		TextColor3     = C_MUTED,
	}, card)

	local chargeLbl = lbl({
		Size           = UDim2.new(1, 0, 0, 12),
		Position       = UDim2.new(0, 0, 1, -14),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text           = "",
		Font           = Enum.Font.GothamBold,
		TextSize       = 9,
		TextColor3     = C_TEAL,
	}, card)

	-- detect button (invisible, on top)
	local hitBtn = btn({
		Size             = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text             = "",
	}, card)
	hitBtn.MouseButton1Click:Connect(function()
		if index > _maxSlots then return end
		if _loadout[index] and _loadout[index] ~= "" then
			UnequipPerk:FireServer(index)
		end
	end)
	hitBtn.MouseEnter:Connect(function()
		if index <= _maxSlots and _loadout[index] ~= "" then
			card.BackgroundColor3 = Color3.fromRGB(70, 55, 95)
		end
	end)
	hitBtn.MouseLeave:Connect(function()
		-- refresh will reset colour; just nudge slightly
		if _loadout[index] and _loadout[index] ~= "" then
			card.BackgroundColor3 = C_CARD_ON
		else
			card.BackgroundColor3 = C_CARD
		end
	end)

	_slotCards[index] = { frame = card, nameLbl = nameLbl, chargeLbl = chargeLbl }
end

-- 5 slots in 3+2 layout (all absolute positions inside panel, left-aligned with 8px margin)
local MARGIN  = 8
local ROW1_Y  = SLOTS_Y + 6
local ROW2_Y  = ROW1_Y + SLOT_H + SLOT_PAD
-- Row 1: 3 slots starting at MARGIN
for i = 1, 3 do
	buildSlot(i, MARGIN + (i - 1) * (SLOT_W + SLOT_PAD), ROW1_Y)
end
-- Row 2: 2 slots, centred (panel width 280 - 2*MARGIN = 264; 2 slots = 2*72+6 = 150; indent = (264-150)/2 = 57)
local ROW2_INDENT = MARGIN + math.floor((264 - (SLOT_W * 2 + SLOT_PAD)) / 2)
buildSlot(4, ROW2_INDENT, ROW2_Y)
buildSlot(5, ROW2_INDENT + SLOT_W + SLOT_PAD, ROW2_Y)

local DIV1_Y = SLOTS_Y + SLOTS_H + 2
hline(DIV1_Y, panel)

-- ── Inventory section ─────────────────────────────────────────────────────────

local INV_LBL_Y = DIV1_Y + 6
local INV_LBL_H = 20

lbl({
	Size           = UDim2.new(1, -16, 0, INV_LBL_H),
	Position       = UDim2.new(0, 10, 0, INV_LBL_Y),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text           = "Owned Tools and Perks",
	Font           = Enum.Font.GothamBold,
	TextSize       = 11,
	TextColor3     = C_WHITE,
}, panel)

local SCROLL_Y = INV_LBL_Y + INV_LBL_H + 4
local SCROLL_H = 390 - SCROLL_Y - 8

local scroll = Instance.new("ScrollingFrame")
scroll.Size                = UDim2.new(1, -16, 0, SCROLL_H)
scroll.Position            = UDim2.new(0, 8, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel     = 0
scroll.ScrollBarThickness  = 3
scroll.ScrollBarImageColor3 = C_MUTED
scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent              = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding   = UDim.new(0, 4)
listLayout.Parent    = scroll

local _invRows = {}
local ROW_H    = 40

local function buildInvRow(perkId, product)
	local row = Instance.new("Frame")
	row.Size             = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = C_CARD
	row.BorderSizePixel  = 0
	row.Parent           = scroll
	corner(6, row)

	lbl({
		Size           = UDim2.new(0.47, -4, 1, -6),
		Position       = UDim2.new(0, 8, 0, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped    = true,
		Text           = product.name,
		Font           = Enum.Font.GothamBold,
		TextSize       = 10,
		TextColor3     = C_WHITE,
	}, row)

	lbl({
		Size           = UDim2.new(0.3, 0, 0, 13),
		Position       = UDim2.new(0.47, 0, 0.5, -6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text           = product.minigame or "",
		Font           = Enum.Font.Gotham,
		TextSize       = 8,
		TextColor3     = C_MUTED,
	}, row)

	local countLbl = lbl({
		Size           = UDim2.new(0, 24, 1, -6),
		Position       = UDim2.new(0.77, -2, 0, 3),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text           = "×0",
		Font           = Enum.Font.GothamBold,
		TextSize       = 13,
		TextColor3     = C_TEAL,
	}, row)

	local equipBtn = btn({
		Size             = UDim2.new(0, 38, 0, 24),
		Position         = UDim2.new(1, -44, 0.5, -12),
		BackgroundColor3 = C_BTN,
		Text             = "Eq",
		Font             = Enum.Font.GothamBold,
		TextSize         = 10,
		TextColor3       = C_WHITE,
	}, row)
	corner(5, equipBtn)

	equipBtn.MouseEnter:Connect(function() equipBtn.BackgroundColor3 = C_BTN_HOV end)
	equipBtn.MouseLeave:Connect(function() equipBtn.BackgroundColor3 = C_BTN end)

	equipBtn.MouseButton1Click:Connect(function()
		-- Equip to first free unlocked slot; fall back to slot 1 if all full
		for i = 1, _maxSlots do
			if not _loadout[i] or _loadout[i] == "" then
				EquipPerk:FireServer(i, perkId)
				return
			end
		end
		EquipPerk:FireServer(1, perkId)
	end)

	_invRows[perkId] = { row = row, countLbl = countLbl }
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

local function refreshSlots()
	slotsInfoLbl.Text = _maxSlots .. " / 5 slots"
	for i = 1, 5 do
		local c = _slotCards[i]
		if not c then continue end
		local locked   = i > _maxSlots
		local perkId   = _loadout[i] or ""
		local occupied = perkId ~= ""
		if locked then
			c.frame.BackgroundColor3 = C_LOCKED
			c.nameLbl.Text           = "Locked"
			c.nameLbl.TextColor3     = Color3.fromRGB(50, 46, 65)
			c.chargeLbl.Text         = ""
		elseif occupied then
			local product = ShopData.GetById(perkId)
			c.frame.BackgroundColor3 = C_CARD_ON
			c.nameLbl.Text           = product and product.name or perkId
			c.nameLbl.TextColor3     = C_GOLD
			local n = _charges[perkId] or 0
			c.chargeLbl.Text         = "×" .. n
			c.chargeLbl.TextColor3   = n > 0 and C_TEAL or C_RED
		else
			c.frame.BackgroundColor3 = C_CARD
			c.nameLbl.Text           = "—"
			c.nameLbl.TextColor3     = C_MUTED
			c.chargeLbl.Text         = ""
		end
	end
end

local function refreshInventory()
	-- Remove rows for depleted perks
	for perkId, data in pairs(_invRows) do
		if (_charges[perkId] or 0) <= 0 then
			data.row:Destroy()
			_invRows[perkId] = nil
		else
			data.countLbl.Text = "×" .. _charges[perkId]
		end
	end
	-- Add new rows
	local order = 1
	for perkId, count in pairs(_charges) do
		if count > 0 then
			local product = ShopData.GetById(perkId)
			if product and product.minigame then
				if not _invRows[perkId] then
					buildInvRow(perkId, product)
				end
				if _invRows[perkId] then
					_invRows[perkId].row.LayoutOrder = order
					_invRows[perkId].countLbl.Text   = "×" .. count
				end
				order += 1
			end
		end
	end
	-- Empty state
	local hasAny  = next(_invRows) ~= nil
	local emptyLbl = scroll:FindFirstChild("_empty")
	if not hasAny then
		if not emptyLbl then
			emptyLbl = lbl({
				Name           = "_empty",
				Size           = UDim2.new(1, 0, 0, 36),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped    = true,
				Text           = "No perks owned — buy bolt tools from the Shop!",
				Font           = Enum.Font.Gotham,
				TextSize       = 10,
				TextColor3     = C_MUTED,
			}, scroll)
		end
	elseif emptyLbl then
		emptyLbl:Destroy()
	end
end

local function refresh()
	refreshSlots()
	refreshInventory()
end

-- ── Data fetch ────────────────────────────────────────────────────────────────

local function fetchData()
	local ok, loadout, charges, maxSlots = pcall(function()
		return GetLoadout:InvokeServer()
	end)
	if ok and loadout then
		_loadout  = loadout
		_charges  = charges or {}
		_maxSlots = maxSlots or 3
	end
	refresh()
end

-- ── Toggle (G key) ────────────────────────────────────────────────────────────

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.G then
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			task.spawn(fetchData)
		end
	end
end)

-- ── Server-pushed loadout updates ─────────────────────────────────────────────

LoadoutChanged.OnClientEvent:Connect(function(loadout, charges)
	_loadout = loadout or _loadout
	_charges = charges or _charges
	if gui.Enabled then refresh() end
end)
