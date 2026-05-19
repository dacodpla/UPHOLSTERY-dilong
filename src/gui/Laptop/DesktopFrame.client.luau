-- Manggil Variabel yang diperlukan doang beb UwU
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SFX               = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")

local LaptopScreen  = LaptopGui:WaitForChild("LaptopScreen")
local Desktop = LaptopScreen:WaitForChild("Desktop")
local Apps = LaptopScreen:WaitForChild("Apps")
local Browsah_Tab = Apps:WaitForChild("Browsah_Tab")
local MoneyMaker_Tab = Apps:WaitForChild("MoneyMaker_Tab")
local Shop_Tab = Apps:WaitForChild("Shop_Tab")
local Talkogram_Tab = Apps:WaitForChild("Talkogram_Tab")
local Miscellaneous = Apps:WaitForChild("Miscellaneous")

local function resetUI()
	Apps.Visible = false
	Browsah_Tab.Visible = false
	MoneyMaker_Tab.Visible = false
	Shop_Tab.Visible = false
	Talkogram_Tab.Visible = false
    Miscellaneous.Visible = false
end

-- ===
-- Buat Logic untuk tombol shutdown, ketika di klik, laptop GUI akan hilang dan kembali ke tampilan utama
-- ===

-- Variabel untuk tombol shutdown di panel kiri desktop
local ShutdownButton = Desktop:WaitForChild("LeftPanel"):WaitForChild("ShutdownButton")

-- Event listener untuk tombol shutdown, ketika di klik, laptop GUI akan hilang dan kembali ke tampilan utama
ShutdownButton.MouseButton1Click:Connect(function()
    SFX.Play("LaptopClose")
	LaptopGui.Enabled = false
	resetUI()
	LaptopScreen.Visible = false
end)

-- ===
-- Buat Logic untuk buka browsah
-- ===

-- Variabel untuk tombol browsah di panel kiri atas desktop euyyy
local BrowsahButton = Desktop:WaitForChild("BrowsahButton")

BrowsahButton.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    Apps.Visible = not Apps.Visible
    Browsah_Tab.Visible = not Browsah_Tab.Visible
    Miscellaneous.Visible = not Miscellaneous.Visible
end)