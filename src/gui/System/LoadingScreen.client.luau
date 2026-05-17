local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local ContentProvider   = game:GetService("ContentProvider")

local player = Players.LocalPlayer

-- Preload fonts while the black screen is up so text never pops in
local _fontDummies = {}
for _, font in ipairs({ Enum.Font.Gotham, Enum.Font.GothamBold, Enum.Font.GothamBlack }) do
	local l = Instance.new("TextLabel")
	l.Font = font
	l.Text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	table.insert(_fontDummies, l)
end
ContentProvider:PreloadAsync(_fontDummies)
for _, l in ipairs(_fontDummies) do l:Destroy() end

-- ── Build GUI ─────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "LoadingScreen"
gui.DisplayOrder   = 50        -- above HUD and iris (iris is 20)
gui.IgnoreGuiInset = true
gui.ResetOnSpawn   = false
gui.Parent         = player:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size             = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BorderSizePixel  = 0
bg.Parent           = gui

local title = Instance.new("TextLabel")
title.Size                = UDim2.new(0, 500, 0, 60)
title.Position            = UDim2.new(0.5, -250, 0.5, -70)
title.BackgroundTransparency = 1
title.TextColor3          = Color3.fromRGB(240, 230, 200)
title.Font                = Enum.Font.GothamBlack
title.TextSize            = 42
title.Text                = "UPHOLSTERY!"
title.TextXAlignment      = Enum.TextXAlignment.Center
title.Parent              = bg

local subtitle = Instance.new("TextLabel")
subtitle.Size                = UDim2.new(0, 400, 0, 30)
subtitle.Position            = UDim2.new(0.5, -200, 0.5, 10)
subtitle.BackgroundTransparency = 1
subtitle.TextColor3          = Color3.fromRGB(160, 150, 135)
subtitle.Font                = Enum.Font.Gotham
subtitle.TextSize            = 16
subtitle.Text                = "Setting up your workshop\u{2026}"
subtitle.TextXAlignment      = Enum.TextXAlignment.Center
subtitle.Parent              = bg

-- ── Hide on first TeleportToHub ───────────────────────────────────────────
-- GameplayClient skips irisClose on the first hub teleport so the loading
-- screen provides the cover. We fade out in two stages to match its timing:
--   0.0 s  → fade text (0.2 s)
--   0.3 s  → fade background (0.5 s)   ← character is moved during this window
--   0.8 s  → gui destroyed

local TeleportToHub = ReplicatedStorage
	:WaitForChild("LaptopRemotes")
	:WaitForChild("TeleportToHub")

local conn
conn = TeleportToHub.OnClientEvent:Connect(function()
	conn:Disconnect()

	TweenService:Create(title,    TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()

	task.wait(0.3)

	local bgTween = TweenService:Create(bg,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 })
	bgTween:Play()
	bgTween.Completed:Wait()

	gui:Destroy()
end)
