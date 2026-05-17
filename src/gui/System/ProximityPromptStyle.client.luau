--[[
	ProximityPromptStyle
	Custom renderer for all ProximityPrompts with Style = Custom.

	Single-row gold pill:  [E]  Action text
]]

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService           = game:GetService("TweenService")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name           = "ProximityPromptGui"
gui.DisplayOrder   = 15
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = player:WaitForChild("PlayerGui")

-- ── Colours ───────────────────────────────────────────────────────────────

local COL_GOLD   = Color3.fromRGB(215, 175, 55)
local COL_WHITE  = Color3.fromRGB(255, 255, 255)
local COL_BG     = Color3.fromRGB(0,   0,   0)

local CARD_W, CARD_H = 164, 40

-- ── Helpers ───────────────────────────────────────────────────────────────

local function getKeyText(prompt)
	local raw = tostring(prompt.KeyboardKeyCode):gsub("Enum%.KeyCode%.", "")
	return raw:sub(1, 3)   -- "E", "F", etc.
end

local _bills = {}

-- ── Show ──────────────────────────────────────────────────────────────────

ProximityPromptService.PromptShown:Connect(function(prompt)
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then return end

	local bill = Instance.new("BillboardGui")
	bill.Size        = UDim2.fromOffset(CARD_W, CARD_H)
	bill.StudsOffset = Vector3.new(0, 0, 0)
	bill.AlwaysOnTop = true
	bill.Adornee     = adornee
	bill.Parent      = gui

	-- Card
	local card = Instance.new("Frame")
	card.Size                   = UDim2.fromScale(1, 1)
	card.BackgroundColor3       = COL_BG
	card.BackgroundTransparency = 1
	card.BorderSizePixel        = 0
	card.Parent                 = bill
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color       = COL_GOLD
	stroke.Thickness   = 1
	stroke.Transparency = 1
	stroke.Parent      = card

	-- Key hint  "[E]"
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size               = UDim2.fromOffset(30, CARD_H)
	keyLabel.Position           = UDim2.fromOffset(6, 0)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text               = "[" .. getKeyText(prompt) .. "]"
	keyLabel.TextColor3         = COL_GOLD
	keyLabel.TextTransparency   = 1
	keyLabel.Font               = Enum.Font.GothamBold
	keyLabel.TextSize           = 13
	keyLabel.Parent             = card

	-- Action text
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Size             = UDim2.new(1, -42, 1, 0)
	actionLabel.Position         = UDim2.fromOffset(40, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Text             = prompt.ActionText
	actionLabel.TextColor3       = COL_WHITE
	actionLabel.TextTransparency = 1
	actionLabel.Font             = Enum.Font.GothamBold
	actionLabel.TextSize         = 14
	actionLabel.TextXAlignment   = Enum.TextXAlignment.Left
	actionLabel.TextTruncate     = Enum.TextTruncate.AtEnd
	actionLabel.Parent           = card

	-- Fade in
	local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
	TweenService:Create(card,        ti, { BackgroundTransparency = 0.62 }):Play()
	TweenService:Create(stroke,      ti, { Transparency           = 0.20 }):Play()
	TweenService:Create(keyLabel,    ti, { TextTransparency       = 0    }):Play()
	TweenService:Create(actionLabel, ti, { TextTransparency       = 0    }):Play()

	_bills[prompt] = bill
end)

-- ── Hide ──────────────────────────────────────────────────────────────────

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local bill = _bills[prompt]
	if not bill then return end
	_bills[prompt] = nil

	local card = bill:FindFirstChildWhichIsA("Frame")
	if not card then bill:Destroy(); return end

	local ti = TweenInfo.new(0.10, Enum.EasingStyle.Quad)
	local stroke = card:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		TweenService:Create(stroke, ti, { Transparency = 1 }):Play()
	end
	TweenService:Create(card, ti, { BackgroundTransparency = 1 }):Play()
	for _, child in ipairs(card:GetDescendants()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, ti, { TextTransparency = 1 }):Play()
		end
	end

	task.delay(0.12, function()
		if bill and bill.Parent then bill:Destroy() end
	end)
end)
