-- Manggil Variabel yang diperlukan doang beb <3
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")
local EventsFolder = ReplicatedStorage:WaitForChild("Events")

local LoadingScreen = LaptopGui:WaitForChild("LoadingScreen")
local LaptopScreen  = LaptopGui:WaitForChild("LaptopScreen")

local BOOT_DURATION = 2.2

-- Method untuk menampilkan loading screen dengan progress bar yang terisi selama proses booting berlangsung, lalu menampilkan laptop screen setelah selesai
local function playBootSequence()
	LaptopScreen.Visible  = false
	LoadingScreen.Visible = true

	local progressBar = LoadingScreen:FindFirstChild("ProgressBar")
	local fill        = progressBar and progressBar:FindFirstChild("Fill")

	if fill then
		fill.Size = UDim2.fromScale(0, 1)
		TweenService:Create(
			fill,
			TweenInfo.new(BOOT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(1, 1) }
		):Play()
	end

	task.wait(BOOT_DURATION)

	if not LaptopGui.Enabled then return end

	LoadingScreen.Visible = false
	LaptopScreen.Visible  = true
end

-- LaptopBrowser listens for the "LaptopOpened" event to start the boot sequence and show the UI
-- Logic ketika event di trigger, quote random akan muncul, dan laptop screen akan muncul setelah loading screen
local QuoteLabel = LaptopScreen:WaitForChild("Desktop"):WaitForChild("QuoteLabel")

local QUOTES = {
	"every cushion tells a story",
	"stitch by stitch, greatness is sewn",
	"the foam is always greener on the other side",
	"a tack a day keeps the sagging away",
	"measure twice, staple once",
	"fame is just followers. craft is forever",
	"start the grind",
	"who gonna carry the logs bro",
	"the hustle never sleeps, and neither do the deadlines",
	"a perfect staple is a perfect life",
	"you vs the sofa she told you not to worry about",
	"no days off when the fabric calls",
	"prestige jobs don't do themselves",
}

local openedEvent = EventsFolder:WaitForChild("LaptopOpened")

openedEvent.Event:Connect(function()
	LaptopGui.Enabled = true
	QuoteLabel.Text = QUOTES[math.random(#QUOTES)]
	playBootSequence()
end)