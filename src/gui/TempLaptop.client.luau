--[[
	TempLaptop — temporary code-built laptop GUI for prototyping GDD v8.1.
	Self-contained: creates its own ScreenGui and wires every laptop remote.

	Opens via:
	  - Pressing L (or any key bound in TOGGLE_KEY)
	  - The existing Workspace Laptop proximity prompt (LaptopOpened BindableEvent)

	Tabs: Jobs / Direct Offers / Toolbox / Shop / Talkogram / Daily Contracts.

	NOTE: The original Studio-built LaptopGui ScreenGui should be disabled
	or deleted. The old per-tab scripts live inside it and will go inert.
]]

local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local UserInputService       = game:GetService("UserInputService")
local RunService             = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService             = game:GetService("GuiService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("LaptopRemotes")

local SFX      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))
local ShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))

local TOGGLE_KEY = Enum.KeyCode.L

-- Remote handles
local RequestJobs         = Remotes:WaitForChild("RequestJobs")
local AcceptJob           = Remotes:WaitForChild("AcceptJob")
local JobBoardRefresh     = Remotes:WaitForChild("JobBoardRefresh")
local RequestPerkInventory= Remotes:WaitForChild("RequestPerkInventory")
local RequestLoadout      = Remotes:WaitForChild("RequestLoadout")
local EquipPerk           = Remotes:WaitForChild("EquipPerk")
local UnequipPerk         = Remotes:WaitForChild("UnequipPerk")
local LoadoutChanged      = Remotes:WaitForChild("LoadoutChanged")
local RequestShopCatalog  = Remotes:WaitForChild("RequestShopCatalog")
local PurchasePerk        = Remotes:WaitForChild("PurchasePerk")
local PurchaseResult      = Remotes:WaitForChild("PurchaseResult")
local RequestDirectOffers = Remotes:WaitForChild("RequestDirectOffers")
local AcceptDirectOffer   = Remotes:WaitForChild("AcceptDirectOffer")
local DirectOffersChanged = Remotes:WaitForChild("DirectOffersChanged")
local HotJobCountdown     = Remotes:WaitForChild("HotJobCountdown")
local RequestDailyContracts = Remotes:WaitForChild("RequestDailyContracts")
local ClaimDailyReward      = Remotes:WaitForChild("ClaimDailyReward")
local DailyContractsChanged = Remotes:WaitForChild("DailyContractsChanged")
local RequestFeed         = Remotes:WaitForChild("RequestFeed")
local RequestLocationsByTier = Remotes:WaitForChild("RequestLocationsByTier")

-- ── State ──────────────────────────────────────────────────────────────────

local _locationsByTier = {}
local _currentTab = "Jobs"

-- ── Helpers ────────────────────────────────────────────────────────────────

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function clearChildren(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
			and not c:IsA("UIPadding") and not c:IsA("UICorner")
			and not c:IsA("UIStroke") then
			c:Destroy()
		end
	end
end

local function splitCamel(s)
	return (s:gsub("(%l)(%u)", "%1 %2"))
end

local function fmtTime(secs)
	secs = math.max(0, math.floor(secs))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local TIER_COLOR = {
	Starter   = Color3.fromRGB(180, 180, 180),
	Mid       = Color3.fromRGB(100, 200, 100),
	Premium   = Color3.fromRGB(80,  160, 220),
	Prestige  = Color3.fromRGB(160, 80,  220),
	Exclusive = Color3.fromRGB(220, 160, 40),
	Elite     = Color3.fromRGB(220, 60,  60),
	Special   = Color3.fromRGB(220, 120, 220),
}

-- ── Build root GUI ─────────────────────────────────────────────────────────

local gui = make("ScreenGui", {
	Name           = "TempLaptopGui",
	ResetOnSpawn   = false,
	IgnoreGuiInset = true,
	DisplayOrder   = 50,
	Enabled        = false,
}, playerGui)

local root = make("Frame", {
	Size              = UDim2.new(0, 880, 0, 560),
	Position          = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint       = Vector2.new(0.5, 0.5),
	BackgroundColor3  = Color3.fromRGB(24, 26, 32),
	BorderSizePixel   = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, root)
make("UIStroke", { Color = Color3.fromRGB(60, 65, 75), Thickness = 1.5 }, root)

-- Title bar
local titleBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = Color3.fromRGB(15, 17, 22),
	BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, titleBar)

local titleLabel = make("TextLabel", {
	Size = UDim2.new(0, 200, 1, 0),
	Position = UDim2.fromOffset(16, 0),
	BackgroundTransparency = 1,
	Text = "UPHOLSTERY!",
	TextColor3 = Color3.fromRGB(245, 230, 200),
	Font = Enum.Font.SourceSansBold,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local statsLabel = make("TextLabel", {
	Size = UDim2.new(0, 460, 1, 0),
	Position = UDim2.new(1, -510, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(220, 220, 220),
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
}, titleBar)

local closeBtn = make("TextButton", {
	Size = UDim2.fromOffset(36, 28),
	Position = UDim2.new(1, -44, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(180, 60, 60),
	Text = "X",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.SourceSansBold,
	TextSize = 14,
	BorderSizePixel = 0,
}, titleBar)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
closeBtn.Activated:Connect(function() gui.Enabled = false end)

-- Tab strip
local tabStrip = make("Frame", {
	Size = UDim2.new(1, 0, 0, 36),
	Position = UDim2.fromOffset(0, 44),
	BackgroundColor3 = Color3.fromRGB(28, 30, 38),
	BorderSizePixel = 0,
}, root)

local tabLayout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabStrip)
make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, tabStrip)

-- Content area
local content = make("Frame", {
	Size = UDim2.new(1, -24, 1, -120),
	Position = UDim2.fromOffset(12, 88),
	BackgroundTransparency = 1,
}, root)

-- Hot job countdown banner
local hotBanner = make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 28),
	Position = UDim2.new(0, 12, 1, -34),
	BackgroundColor3 = Color3.fromRGB(220, 160, 40),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.SourceSansBold,
	TextSize = 14,
	TextColor3 = Color3.new(0, 0, 0),
	Visible = false,
	BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, hotBanner)

-- ── Tab management ────────────────────────────────────────────────────────

local tabs = {}    -- [name] = Frame
local tabButtons = {}  -- [name] = TextButton

local function selectTab(name)
	_currentTab = name
	for tname, frame in pairs(tabs) do
		frame.Visible = (tname == name)
	end
	for tname, btn in pairs(tabButtons) do
		btn.BackgroundColor3 = (tname == name)
			and Color3.fromRGB(70, 110, 180)
			or Color3.fromRGB(45, 50, 60)
	end
end

local function addTab(name, label, builder)
	local btn = make("TextButton", {
		Size = UDim2.fromOffset(110, 28),
		BackgroundColor3 = Color3.fromRGB(45, 50, 60),
		Text = label,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 13,
		BorderSizePixel = 0,
		LayoutOrder = #tabButtons + 1,
	}, tabStrip)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)

	local frame = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, content)
	builder(frame)

	tabs[name] = frame
	tabButtons[name] = btn
	btn.Activated:Connect(function()
		selectTab(name)
		if name == "Jobs"    and jobsRefresh    then task.spawn(jobsRefresh)    end
		if name == "Offers"  and offersRefresh  then task.spawn(offersRefresh)  end
		if name == "Toolbox" and toolboxRefresh then task.spawn(toolboxRefresh) end
		if name == "Shop"    and shopRefresh    then task.spawn(shopRefresh)    end
		if name == "Talko"   and talkoRefresh   then task.spawn(talkoRefresh)   end
		if name == "Daily"   and dailyRefresh   then task.spawn(dailyRefresh)   end
	end)
end

-- ── Stats refresh ─────────────────────────────────────────────────────────

local function refreshStats()
	local pd = player:FindFirstChild("PlayerData")
	if not pd then return end
	local usd  = pd:FindFirstChild("usd")        and pd.usd.Value or 0
	local foll = pd:FindFirstChild("followers")  and pd.followers.Value or 0
	local rep  = pd:FindFirstChild("reputation") and pd.reputation.Value or 0
	local slots= pd:FindFirstChild("toolboxSlots") and pd.toolboxSlots.Value or 0
	statsLabel.Text = string.format("$%d  ·  %d followers  ·  rep %.2f  ·  toolbox %d/5",
		usd, foll, rep, slots)
end

task.spawn(function()
	while true do
		refreshStats()
		task.wait(0.5)
	end
end)

-- ============================================================================
-- TAB 1: Jobs
-- ============================================================================

local jobsRefresh
addTab("Jobs", "Job Board", function(frame)
	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	jobsRefresh = function()
		clearChildren(scroll)
		_locationsByTier = RequestLocationsByTier:InvokeServer() or {}
		local jobs = RequestJobs:InvokeServer() or {}
		for i, job in ipairs(jobs) do
			local card = make("Frame", {
				Size = UDim2.new(1, -12, 0, 72),
				BackgroundColor3 = Color3.fromRGB(36, 40, 50),
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, scroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			local stroke = make("UIStroke", {
				Color = job.isHotJob and Color3.fromRGB(220, 160, 40) or (TIER_COLOR[job.tier] or Color3.fromRGB(120,120,120)),
				Thickness = job.isHotJob and 3 or 1.5,
			}, card)
			local _ = stroke

			local locName
			if job.locationOverride then
				locName = splitCamel(job.locationOverride)
			else
				local locs = _locationsByTier[job.tier] or {}
				local names = {}
				for _, n in ipairs(locs) do table.insert(names, splitCamel(n)) end
				locName = #names > 0 and table.concat(names, " / ") or job.name
			end

			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 22),
				Position = UDim2.fromOffset(12, 6),
				BackgroundTransparency = 1,
				Text = (job.isHotJob and "🔥 HOT  " or "") .. locName,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 16),
				Position = UDim2.fromOffset(12, 26),
				BackgroundTransparency = 1,
				Text = job.details or "",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 16),
				Position = UDim2.fromOffset(12, 46),
				BackgroundTransparency = 1,
				Text = string.format("%s · $%d · +%d followers · %d minigame(s)",
					job.tier or "?", job.pay or 0, job.followers or 0, #(job.minigames or {})),
				TextColor3 = TIER_COLOR[job.tier] or Color3.fromRGB(180, 180, 180),
				Font = Enum.Font.SourceSansSemibold,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)

			local acceptBtn = make("TextButton", {
				Size = UDim2.fromOffset(96, 60),
				Position = UDim2.new(1, -106, 0, 6),
				BackgroundColor3 = Color3.fromRGB(80, 160, 100),
				Text = "ACCEPT",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				BorderSizePixel = 0,
			}, card)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, acceptBtn)
			acceptBtn.Activated:Connect(function()
				AcceptJob:FireServer(job.id)
				gui.Enabled = false
			end)
		end
	end
	jobsRefresh()
end)

JobBoardRefresh.OnClientEvent:Connect(function()
	if jobsRefresh and gui.Enabled then jobsRefresh() end
end)

-- ============================================================================
-- TAB 2: Direct Offers
-- ============================================================================

local offersRefresh
local _offerCountdownLabels = {}  -- [offerCard] = {label, expiresAt}

addTab("Offers", "Direct Offers", function(frame)
	local emptyLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "No direct offers. Reach reputation 1.0 to start receiving them.",
		TextColor3 = Color3.fromRGB(180, 180, 180),
		Font = Enum.Font.SourceSansItalic,
		TextSize = 13,
		Visible = false,
	}, frame)

	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	offersRefresh = function()
		clearChildren(scroll)
		_offerCountdownLabels = {}
		local offers = RequestDirectOffers:InvokeServer() or {}
		emptyLabel.Visible = (#offers == 0)
		scroll.Visible = (#offers > 0)

		for i, offer in ipairs(offers) do
			local card = make("Frame", {
				Size = UDim2.new(1, -12, 0, 72),
				BackgroundColor3 = Color3.fromRGB(38, 36, 50),
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, scroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			make("UIStroke", { Color = TIER_COLOR[offer.tier] or Color3.fromRGB(120,120,120), Thickness = 1.5 }, card)

			make("TextLabel", {
				Size = UDim2.new(1, -200, 0, 22),
				Position = UDim2.fromOffset(12, 6),
				BackgroundTransparency = 1,
				Text = "📧 " .. (offer.name or "Direct Offer"),
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -200, 0, 16),
				Position = UDim2.fromOffset(12, 26),
				BackgroundTransparency = 1,
				Text = offer.details or "",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -200, 0, 16),
				Position = UDim2.fromOffset(12, 46),
				BackgroundTransparency = 1,
				Text = string.format("%s · $%d · +%d followers", offer.tier or "?", offer.pay or 0, offer.followers or 0),
				TextColor3 = TIER_COLOR[offer.tier] or Color3.fromRGB(180, 180, 180),
				Font = Enum.Font.SourceSansSemibold,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)

			local timer = make("TextLabel", {
				Size = UDim2.fromOffset(80, 16),
				Position = UDim2.new(1, -190, 0, 6),
				BackgroundTransparency = 1,
				Text = "—:—",
				TextColor3 = Color3.fromRGB(220, 180, 80),
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, card)
			_offerCountdownLabels[card] = { label = timer, expiresAt = offer.expiresAt }

			local acceptBtn = make("TextButton", {
				Size = UDim2.fromOffset(96, 60),
				Position = UDim2.new(1, -106, 0, 6),
				BackgroundColor3 = Color3.fromRGB(140, 90, 200),
				Text = "ACCEPT",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				BorderSizePixel = 0,
			}, card)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, acceptBtn)
			acceptBtn.Activated:Connect(function()
				AcceptDirectOffer:FireServer(offer.id)
				gui.Enabled = false
			end)
		end
	end
	offersRefresh()
end)

DirectOffersChanged.OnClientEvent:Connect(function()
	if offersRefresh and gui.Enabled then offersRefresh() end
end)

-- Countdown ticker
task.spawn(function()
	while true do
		local now = os.time()
		for card, info in pairs(_offerCountdownLabels) do
			if card.Parent then
				info.label.Text = fmtTime(info.expiresAt - now)
			end
		end
		task.wait(1)
	end
end)

-- ============================================================================
-- TAB 3: Toolbox
-- ============================================================================

local toolboxRefresh
local _selectedSlot = 1
local _maxSlots     = 0  -- updated each refresh; accessible to drag handlers
local _loadout      = {} -- updated each refresh; accessible to drag handlers

addTab("Toolbox", "Toolbox", function(frame)
	-- Ghost ScreenGui for drag preview (lives on top of everything)
	local dragGui = Instance.new("ScreenGui")
	dragGui.Name           = "ToolboxDragGhost"
	dragGui.DisplayOrder   = 60
	dragGui.IgnoreGuiInset = true
	dragGui.ResetOnSpawn   = false
	dragGui.Parent         = playerGui

	-- Top: 5 slot buttons
	local slotRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	}, frame)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, slotRow)

	local slotButtons  = {}
	local _activeDrag  = false  -- guard against concurrent drags

	-- ── Drag helpers ──────────────────────────────────────────────────────────

	local function getSlotUnderCursor(screenPos)
		local objects = GuiService:GetGuiObjectsAtPosition(screenPos.X, screenPos.Y)
		for _, obj in ipairs(objects) do
			for i, btn in ipairs(slotButtons) do
				if obj == btn and i <= _maxSlots then
					return i
				end
			end
		end
		return nil
	end

	local function setSlotHighlight(hoverSlot)
		for i, btn in ipairs(slotButtons) do
			local stroke = btn:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				if i == hoverSlot then
					stroke.Color     = Color3.fromRGB(100, 220, 120)
					stroke.Thickness = 2.5
				else
					stroke.Color     = Color3.fromRGB(90, 100, 130)
					stroke.Thickness = 1.5
				end
			end
		end
	end

	-- Starts a drag. On drop over a slot, fires EquipPerk.
	-- Uses RenderStepped polling so mouse position updates every frame reliably.
	-- originCard: inventory TextButton to dim during drag (nil when dragging from a slot).
	local function startPerkDrag(perkId, displayName, originCard)
		if _activeDrag then return end
		_activeDrag = true

		local DRAG_THRESHOLD = 6
		local startPos   = UserInputService:GetMouseLocation()
		local dragging   = false
		local ghost      = nil
		local hoverSlot  = nil

		local renderConn = RunService.RenderStepped:Connect(function()
			local pos = UserInputService:GetMouseLocation()

			if not dragging then
				local dx, dy = pos.X - startPos.X, pos.Y - startPos.Y
				if (dx * dx + dy * dy) > (DRAG_THRESHOLD * DRAG_THRESHOLD) then
					dragging = true
					ghost = make("Frame", {
						Size                   = UDim2.fromOffset(190, 44),
						BackgroundColor3       = Color3.fromRGB(60, 100, 170),
						BackgroundTransparency = 0.05,
						BorderSizePixel        = 0,
						Position               = UDim2.fromOffset(pos.X - 95, pos.Y - 22),
						ZIndex                 = 10,
					}, dragGui)
					make("UICorner", { CornerRadius = UDim.new(0, 6) }, ghost)
					make("UIStroke", { Color = Color3.fromRGB(160, 210, 255), Thickness = 2 }, ghost)
					make("TextLabel", {
						Size               = UDim2.new(1, -10, 1, 0),
						BackgroundTransparency = 1,
						Text               = displayName,
						TextColor3         = Color3.new(1, 1, 1),
						Font               = Enum.Font.SourceSansBold,
						TextSize           = 12,
						TextXAlignment     = Enum.TextXAlignment.Left,
						Position           = UDim2.fromOffset(6, 0),
						ZIndex             = 11,
					}, ghost)
					if originCard then originCard.BackgroundTransparency = 0.55 end
				end
			else
				ghost.Position = UDim2.fromOffset(pos.X - 95, pos.Y - 22)
				local newHover = getSlotUnderCursor(pos)
				if newHover ~= hoverSlot then
					hoverSlot = newHover
					setSlotHighlight(hoverSlot)
				end
			end
		end)

		local upConn
		upConn = UserInputService.InputEnded:Connect(function(inp)
			if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			renderConn:Disconnect()
			upConn:Disconnect()
			_activeDrag = false

			-- Final snapshot: catches the slot even if RenderStepped missed the last frame
			if dragging then
				local finalSlot = getSlotUnderCursor(UserInputService:GetMouseLocation())
				if finalSlot then hoverSlot = finalSlot end
			end

			if ghost then ghost:Destroy(); ghost = nil end
			if originCard then originCard.BackgroundTransparency = 0 end
			setSlotHighlight(nil)

			if dragging and hoverSlot then
				EquipPerk:FireServer(hoverSlot, perkId)
			end
		end)
	end

	-- ── Slot buttons ──────────────────────────────────────────────────────────

	for i = 1, 5 do
		local btn = make("TextButton", {
			Size             = UDim2.fromOffset(140, 64),
			BackgroundColor3 = Color3.fromRGB(50, 55, 70),
			Text             = "Slot " .. i .. "\n(empty)",
			TextColor3       = Color3.fromRGB(220, 220, 220),
			Font             = Enum.Font.SourceSansSemibold,
			TextSize         = 12,
			BorderSizePixel  = 0,
			LayoutOrder      = i,
		}, slotRow)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
		make("UIStroke", { Color = Color3.fromRGB(90, 100, 130), Thickness = 1.5 }, btn)
		slotButtons[i] = btn

		-- Click to unequip
		btn.Activated:Connect(function()
			_selectedSlot = i
			UnequipPerk:FireServer(i)
		end)

		-- Drag equipped perk to rearrange
		btn.MouseButton1Down:Connect(function()
			local equippedId = _loadout[i] or ""
			if equippedId == "" then return end
			local perk = ShopData.GetById(equippedId)
			if not perk then return end
			startPerkDrag(equippedId, perk.name .. " " .. perk.grade, nil)
		end)
	end

	local hint = make("TextLabel", {
		Size               = UDim2.new(1, 0, 0, 20),
		Position           = UDim2.fromOffset(0, 86),
		BackgroundTransparency = 1,
		Text               = "Drag a perk onto a slot  ·  Click a filled slot to unequip",
		TextColor3         = Color3.fromRGB(160, 160, 160),
		Font               = Enum.Font.SourceSansItalic,
		TextSize           = 12,
	}, frame)
	local _ = hint

	-- ── Inventory grid ────────────────────────────────────────────────────────

	local invScroll = make("ScrollingFrame", {
		Size               = UDim2.new(1, 0, 1, -112),
		Position           = UDim2.fromOffset(0, 112),
		BackgroundTransparency = 1,
		BorderSizePixel    = 0,
		ScrollBarThickness = 6,
		CanvasSize         = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	local grid = make("UIGridLayout", {
		CellSize    = UDim2.fromOffset(200, 70),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder   = Enum.SortOrder.LayoutOrder,
	}, invScroll)
	local _ = grid

	toolboxRefresh = function()
		local inv    = RequestPerkInventory:InvokeServer() or {}
		local charges = inv.charges or {}
		_maxSlots    = inv.slots or 0
		_loadout     = RequestLoadout:InvokeServer() or {}

		for i = 1, 5 do
			local btn        = slotButtons[i]
			local equippedId = _loadout[i] or ""
			if i > _maxSlots then
				btn.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
				btn.TextColor3       = Color3.fromRGB(110, 110, 110)
				btn.Text             = "Slot " .. i .. "\n(locked)"
				btn.AutoButtonColor  = false
			else
				btn.AutoButtonColor = true
				if equippedId ~= "" then
					local perk    = ShopData.GetById(equippedId)
					local perkName = perk and (perk.name .. " " .. perk.grade) or equippedId
					btn.BackgroundColor3 = Color3.fromRGB(70, 110, 180)
					btn.TextColor3       = Color3.new(1, 1, 1)
					btn.Text             = "Slot " .. i .. "\n" .. perkName .. " ×" .. (charges[equippedId] or 0)
				else
					btn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
					btn.TextColor3       = Color3.fromRGB(220, 220, 220)
					btn.Text             = "Slot " .. i .. "\n(empty)"
				end
			end
		end

		clearChildren(invScroll)
		local ownedSorted = {}
		for perkId, qty in pairs(charges) do
			if qty > 0 then
				local perk = ShopData.GetById(perkId)
				if perk then table.insert(ownedSorted, { perk = perk, qty = qty }) end
			end
		end
		table.sort(ownedSorted, function(a, b) return a.perk.name < b.perk.name end)

		for idx, entry in ipairs(ownedSorted) do
			local perk = entry.perk
			local card = make("TextButton", {
				BackgroundColor3 = Color3.fromRGB(40, 45, 55),
				Text             = "",
				BorderSizePixel  = 0,
				LayoutOrder      = idx,
			}, invScroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			make("UIStroke", {
				Color     = perk.grade == "Bespoke" and Color3.fromRGB(220, 160, 40) or Color3.fromRGB(120, 130, 150),
				Thickness = 1.5,
			}, card)
			make("TextLabel", {
				Size               = UDim2.new(1, -10, 0, 18),
				Position           = UDim2.fromOffset(6, 4),
				BackgroundTransparency = 1,
				Text               = perk.name .. " — " .. perk.grade,
				TextColor3         = Color3.new(1, 1, 1),
				Font               = Enum.Font.SourceSansBold,
				TextSize           = 12,
				TextXAlignment     = Enum.TextXAlignment.Left,
			}, card)
			make("TextLabel", {
				Size               = UDim2.new(1, -10, 0, 16),
				Position           = UDim2.fromOffset(6, 22),
				BackgroundTransparency = 1,
				Text               = perk.description,
				TextColor3         = Color3.fromRGB(200, 200, 200),
				Font               = Enum.Font.Gotham,
				TextSize           = 10,
				TextXAlignment     = Enum.TextXAlignment.Left,
				TextWrapped        = true,
			}, card)
			make("TextLabel", {
				Size               = UDim2.new(1, -10, 0, 14),
				Position           = UDim2.fromOffset(6, 50),
				BackgroundTransparency = 1,
				Text               = "×" .. entry.qty .. " charges",
				TextColor3         = Color3.fromRGB(220, 180, 80),
				Font               = Enum.Font.SourceSansSemibold,
				TextSize           = 11,
				TextXAlignment     = Enum.TextXAlignment.Left,
			}, card)

			-- Click: equip to next open slot (or _selectedSlot as fallback)
			card.Activated:Connect(function()
				local target = nil
				for i = 1, _maxSlots do
					if (_loadout[i] or "") == "" then target = i; break end
				end
				if not target then target = _selectedSlot end
				if target then EquipPerk:FireServer(target, perk.id) end
			end)

			-- Drag: equip to whichever slot the player drops onto
			card.MouseButton1Down:Connect(function()
				startPerkDrag(perk.id, perk.name .. " " .. perk.grade, card)
			end)
		end
	end
	toolboxRefresh()
end)

LoadoutChanged.OnClientEvent:Connect(function()
	if toolboxRefresh and gui.Enabled then toolboxRefresh() end
end)

-- ============================================================================
-- TAB 4: Shop
-- ============================================================================

local shopRefresh
local _shopCategory = nil  -- nil = all

addTab("Shop", "Shop", function(frame)
	-- Category filter row
	local catRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	}, frame)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, catRow)

	local productsScroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -38),
		Position = UDim2.fromOffset(0, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	local _ = make("UIGridLayout", {
		CellSize = UDim2.fromOffset(270, 96),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, productsScroll)

	local catalog = RequestShopCatalog:InvokeServer() or {}

	local function renderProducts()
		clearChildren(productsScroll)
		local inv = RequestPerkInventory:InvokeServer() or {}
		local charges = inv.charges or {}
		local pd = player:FindFirstChild("PlayerData")
		local usd = pd and pd:FindFirstChild("usd") and pd.usd.Value or 0
		local rep = pd and pd:FindFirstChild("reputation") and pd.reputation.Value or 0

		local sorted = {}
		for _, p in ipairs(catalog) do
			if not _shopCategory or p.category == _shopCategory then
				table.insert(sorted, p)
			end
		end
		table.sort(sorted, function(a, b)
			if a.name ~= b.name then return a.name < b.name end
			return a.grade < b.grade
		end)

		for idx, perk in ipairs(sorted) do
			local card = make("Frame", {
				BackgroundColor3 = Color3.fromRGB(40, 45, 55),
				BorderSizePixel = 0,
				LayoutOrder = idx,
			}, productsScroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			make("UIStroke", {
				Color = perk.grade == "Bespoke" and Color3.fromRGB(220, 160, 40) or Color3.fromRGB(120, 130, 150),
				Thickness = 1.5,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.fromOffset(6, 4),
				BackgroundTransparency = 1,
				Text = perk.name .. " — " .. perk.grade,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -10, 0, 28),
				Position = UDim2.fromOffset(6, 22),
				BackgroundTransparency = 1,
				Text = perk.description,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(0, 100, 0, 14),
				Position = UDim2.fromOffset(6, 76),
				BackgroundTransparency = 1,
				Text = "Owned: ×" .. (charges[perk.id] or 0),
				TextColor3 = Color3.fromRGB(180, 220, 180),
				Font = Enum.Font.SourceSansSemibold,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)

			local canAfford = usd >= perk.price
			local meetsRep  = not perk.requiresRep or rep >= perk.requiresRep
			local btnLabel = string.format("BUY $%d", perk.price)
			if not meetsRep then
				btnLabel = string.format("Rep %.1f needed", perk.requiresRep)
			end
			local buyBtn = make("TextButton", {
				Size = UDim2.fromOffset(110, 26),
				Position = UDim2.new(1, -116, 1, -32),
				BackgroundColor3 = (canAfford and meetsRep) and Color3.fromRGB(80, 160, 100) or Color3.fromRGB(80, 80, 90),
				Text = btnLabel,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 12,
				BorderSizePixel = 0,
				AutoButtonColor = canAfford and meetsRep,
			}, card)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, buyBtn)
			buyBtn.Activated:Connect(function()
				PurchasePerk:FireServer(perk.id)
			end)
		end
	end

	local function addCatBtn(label, value)
		local btn = make("TextButton", {
			Size = UDim2.fromOffset(110, 26),
			BackgroundColor3 = Color3.fromRGB(45, 50, 60),
			Text = label,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 11,
			BorderSizePixel = 0,
		}, catRow)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
		btn.Activated:Connect(function()
			_shopCategory = value
			renderProducts()
		end)
	end
	addCatBtn("All", nil)
	for _, cat in ipairs(ShopData.GetCategories()) do
		addCatBtn(cat, cat)
	end

	shopRefresh = renderProducts
	renderProducts()
end)

PurchaseResult.OnClientEvent:Connect(function(ok, msg)
	if shopRefresh and gui.Enabled then shopRefresh() end
	print(("[Shop] %s: %s"):format(ok and "OK" or "FAIL", msg or ""))
end)

-- ============================================================================
-- TAB 5: Talkogram
-- ============================================================================

local talkoRefresh
addTab("Talko", "Talkogram", function(frame)
	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	talkoRefresh = function()
		clearChildren(scroll)
		local feed = nil
		pcall(function() feed = RequestFeed:InvokeServer("Server") end)
		feed = feed or {}
		for i, post in ipairs(feed) do
			local card = make("Frame", {
				Size = UDim2.new(1, -12, 0, 60),
				BackgroundColor3 = Color3.fromRGB(36, 40, 50),
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, scroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			make("TextLabel", {
				Size = UDim2.new(1, -12, 0, 18),
				Position = UDim2.fromOffset(6, 4),
				BackgroundTransparency = 1,
				Text = "@" .. (post.author or "?"),
				TextColor3 = Color3.fromRGB(220, 180, 80),
				Font = Enum.Font.SourceSansBold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			make("TextLabel", {
				Size = UDim2.new(1, -12, 0, 32),
				Position = UDim2.fromOffset(6, 22),
				BackgroundTransparency = 1,
				Text = post.title or "",
				TextColor3 = Color3.fromRGB(220, 220, 220),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			}, card)
		end
	end
	talkoRefresh()
end)

-- ============================================================================
-- TAB 6: Daily Contracts
-- ============================================================================

local dailyRefresh
addTab("Daily", "Daily Contracts", function(frame)
	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	dailyRefresh = function()
		clearChildren(scroll)
		local contracts = RequestDailyContracts:InvokeServer() or {}
		for i, c in ipairs(contracts) do
			local card = make("Frame", {
				Size = UDim2.new(1, -12, 0, 90),
				BackgroundColor3 = Color3.fromRGB(36, 40, 50),
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, scroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
			make("UIStroke", { Color = c.claimed and Color3.fromRGB(80, 160, 100) or Color3.fromRGB(120, 130, 150), Thickness = 1.5 }, card)
			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 22),
				Position = UDim2.fromOffset(12, 6),
				BackgroundTransparency = 1,
				Text = c.description,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}, card)
			local goalCount = c.goal.count or c.goal.amount or 1
			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 18),
				Position = UDim2.fromOffset(12, 32),
				BackgroundTransparency = 1,
				Text = string.format("Progress: %d / %d", math.min(c.progress, goalCount), goalCount),
				TextColor3 = Color3.fromRGB(200, 200, 200),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			local rewardText = c.reward.kind == "usd"
				and ("Reward: $" .. c.reward.amount)
				or ("Reward: " .. (c.reward.qty or 1) .. "× " .. (c.reward.perkId or "?"))
			make("TextLabel", {
				Size = UDim2.new(1, -120, 0, 18),
				Position = UDim2.fromOffset(12, 52),
				BackgroundTransparency = 1,
				Text = rewardText,
				TextColor3 = Color3.fromRGB(220, 180, 80),
				Font = Enum.Font.SourceSansSemibold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)

			local meets = c.progress >= goalCount
			local btn = make("TextButton", {
				Size = UDim2.fromOffset(96, 60),
				Position = UDim2.new(1, -106, 0, 14),
				BackgroundColor3 = c.claimed and Color3.fromRGB(80, 80, 90)
					or (meets and Color3.fromRGB(80, 160, 100) or Color3.fromRGB(60, 65, 75)),
				Text = c.claimed and "CLAIMED" or (meets and "CLAIM" or "—"),
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				BorderSizePixel = 0,
				AutoButtonColor = not c.claimed and meets,
			}, card)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
			if not c.claimed and meets then
				btn.Activated:Connect(function()
					ClaimDailyReward:FireServer(c.id)
				end)
			end
		end
	end
	dailyRefresh()
end)

DailyContractsChanged.OnClientEvent:Connect(function()
	if dailyRefresh and gui.Enabled then dailyRefresh() end
end)

-- ============================================================================
-- Hot Job countdown overlay
-- ============================================================================

HotJobCountdown.OnClientEvent:Connect(function(durationSec, tier)
	hotBanner.Visible = true
	hotBanner.BackgroundTransparency = 0.05
	for t = durationSec, 1, -1 do
		hotBanner.Text = ("🔥 HOT JOB INCOMING — %s tier — %ds"):format(tier or "?", t)
		task.wait(1)
	end
	hotBanner.Text = "🔥 HOT JOB AVAILABLE NOW — open Job Board!"
	task.wait(3)
	hotBanner.Visible = false
end)

-- ============================================================================
-- Open / close + refresh on open
-- ============================================================================

local function openLaptop()
	gui.Enabled = true
	selectTab(_currentTab)
	-- Always background-refresh Toolbox so depleted perks clear even if Jobs tab is active
	if toolboxRefresh then task.spawn(toolboxRefresh) end
	-- Refresh whichever tab is currently visible (Toolbox already spawned above)
	if _currentTab == "Jobs"    and jobsRefresh    then jobsRefresh()    end
	if _currentTab == "Offers"  and offersRefresh  then offersRefresh()  end
	if _currentTab == "Shop"    and shopRefresh    then shopRefresh()    end
	if _currentTab == "Talko"   and talkoRefresh   then talkoRefresh()   end
	if _currentTab == "Daily"   and dailyRefresh   then dailyRefresh()   end
end

selectTab("Jobs")

-- ── Proximity prompt setup ────────────────────────────────────────────────
-- Scans Workspace for "Laptop" models, attaches a ProximityPrompt to each
-- "Screen" BasePart, and calls openLaptop() on trigger.
-- Fully replaces LaptopInteraction.client.luau — disable LaptopGui in Studio.

local _screenParts = {}   -- BasePart refs tracked for the distance-close check
local _isOpening   = false -- debounce against rapid re-triggers

local function setupLaptop(laptopModel)
	local screenPart = laptopModel:FindFirstChild("Screen", true)
	if not screenPart or not screenPart:IsA("BasePart") then
		local conn
		conn = laptopModel.DescendantAdded:Connect(function(desc)
			if desc.Name == "Screen" and desc:IsA("BasePart") then
				conn:Disconnect()
				setupLaptop(laptopModel)
			end
		end)
		return
	end

	table.insert(_screenParts, screenPart)

	local prompt = screenPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.MaxActivationDistance = 4
		prompt.Parent                = screenPart
	end
	prompt.ActionText          = "Use"
	prompt.ObjectText          = "Laptop"
	prompt.HoldDuration        = 0
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity         = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Style               = Enum.ProximityPromptStyle.Custom

	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player then return end
		if _isOpening then return end
		_isOpening = true
		SFX.Play("LaptopOpen")
		openLaptop()
		task.delay(2.5, function() _isOpening = false end)
	end)
end

for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "Laptop" then setupLaptop(child) end
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Laptop" then setupLaptop(child) end
end)

-- ── Distance check: close GUI if player walks away ────────────────────────

local _lastDistCheck = 0
RunService.Heartbeat:Connect(function()
	if not gui.Enabled then return end
	local now = os.clock()
	if now - _lastDistCheck < 1.5 then return end
	_lastDistCheck = now

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local i = 1
	while i <= #_screenParts do
		if _screenParts[i].Parent then i = i + 1 else table.remove(_screenParts, i) end
	end

	for _, screen in ipairs(_screenParts) do
		if (hrp.Position - screen.Position).Magnitude <= 16 then return end
	end
	SFX.Play("LaptopClose")
	gui.Enabled = false
end)

-- ── Suppress other proximity prompts while the GUI is open ───────────────

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	ProximityPromptService.Enabled = not gui.Enabled
end)

-- ── L key as dev fallback (toggle without needing the laptop model) ───────

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == TOGGLE_KEY then
		if gui.Enabled then
			SFX.Play("LaptopClose")
			gui.Enabled = false
		else
			openLaptop()
		end
	end
end)
