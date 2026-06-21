local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ScreenGui")
local State     = require(script.Parent:WaitForChild("ScreenGuiState"))

local MoneyFrame      = ScreenGui:WaitForChild("MoneyFrame")
local FollowersFrame  = ScreenGui:WaitForChild("FollowersFrame")
local ReputationFrame = ScreenGui:WaitForChild("ReputationFrame")
local FRAMES = { MoneyFrame, FollowersFrame, ReputationFrame }

-- Cache each frame's studio position so we can animate relative to it.
local _nat = {}
for _, f in ipairs(FRAMES) do _nat[f] = f.Position end

-- Slide 60px to the right when hiding; slide in from the right when showing.
-- Adjust SLIDE_X if your HUD is on the left side of the screen (use -60).
local SLIDE_X   = 60
local SHOW_TIME = 0.3
local HIDE_TIME = 0.12
local SHOW_INFO = TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_INFO = TweenInfo.new(HIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local _tweens     = {}
local _hudVisible = false

local function cancelTweens()
	for _, t in ipairs(_tweens) do t:Cancel() end
	_tweens = {}
end

local function shifted(f, dx)
	local p = _nat[f]
	return UDim2.new(p.X.Scale, p.X.Offset + dx, p.Y.Scale, p.Y.Offset)
end

local function showHUD()
	if _hudVisible then return end
	_hudVisible = true
	cancelTweens()
	for _, f in ipairs(FRAMES) do
		f.Position = shifted(f, SLIDE_X)
		f.Visible  = true
		local t = TweenService:Create(f, SHOW_INFO, { Position = _nat[f] })
		t:Play()
		table.insert(_tweens, t)
	end
end

local function hideHUD(instant)
	if not _hudVisible then return end
	_hudVisible = false
	cancelTweens()
	if instant then
		for _, f in ipairs(FRAMES) do
			f.Visible  = false
			f.Position = _nat[f]
		end
		return
	end
	for _, f in ipairs(FRAMES) do
		local t = TweenService:Create(f, HIDE_INFO, { Position = shifted(f, SLIDE_X) })
		t:Play()
		table.insert(_tweens, t)
	end
	task.delay(HIDE_TIME, function()
		if _hudVisible then return end  -- a showHUD fired before the delay completed
		for _, f in ipairs(FRAMES) do
			f.Visible  = false
			f.Position = _nat[f]
		end
	end)
end

-- ── Visibility logic ──────────────────────────────────────────────────────

local laptopOpen = false
local inJob      = false

local function refreshVisibility()
	if laptopOpen or inJob then
		hideHUD(inJob)   -- instant during job (iris covers the screen), animated otherwise
	else
		showHUD()
	end
end

-- ── Laptop detection ──────────────────────────────────────────────────────
-- Using ChildAdded instead of WaitForChild so there is no timeout risk, and
-- the handler reconnects automatically if LaptopGui is ever recreated.

local function watchLaptopGui(gui)
	laptopOpen = gui.Enabled
	refreshVisibility()
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		laptopOpen = gui.Enabled
		refreshVisibility()
	end)
end

local existing = PlayerGui:FindFirstChild("LaptopGui")
if existing then
	watchLaptopGui(existing)
else
	local conn
	conn = PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "LaptopGui" then
			conn:Disconnect()
			watchLaptopGui(child)
		end
	end)
end

-- ── Job remotes ───────────────────────────────────────────────────────────

local Remotes = ReplicatedStorage:WaitForChild("LaptopRemotes")

Remotes:WaitForChild("TeleportToLocation").OnClientEvent:Connect(function()
	inJob      = true
	laptopOpen = false  -- laptop is always closed before a teleport
	State.BeginDeferred()
	refreshVisibility()
end)

Remotes:WaitForChild("TeleportToHub").OnClientEvent:Connect(function()
	-- Keep inJob=true (HUD stays hidden) while the iris animation plays and the
	-- player settles at home (~1.35s). After that, slide the HUD in, then flush
	-- the pending stat changes once the frames have finished sliding (SHOW_TIME).
	task.delay(1.5, function()
		inJob = false
		refreshVisibility()
		task.delay(SHOW_TIME, function()
			State.Flush()
		end)
	end)
end)

-- ── Initial state ─────────────────────────────────────────────────────────

ScreenGui.Enabled = true
refreshVisibility()
