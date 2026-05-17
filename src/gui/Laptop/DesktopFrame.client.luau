-- Manggil Variabel yang diperlukan doang beb UwU
local Players      = game:GetService("Players")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")

local LaptopScreen  = LaptopGui:WaitForChild("LaptopScreen")
local Desktop = LaptopScreen:WaitForChild("Desktop")

-- ===
-- Buat Logic untuk tombol shutdown, ketika di klik, laptop GUI akan hilang dan kembali ke tampilan utama
-- ===

-- Variabel untuk tombol shutdown di panel kiri desktop
local ShutdownButton = Desktop:WaitForChild("LeftPanel"):WaitForChild("ShutdownButton")

-- Event listener untuk tombol shutdown, ketika di klik, laptop GUI akan hilang dan kembali ke tampilan utama
ShutdownButton.MouseButton1Click:Connect(function()
    LaptopGui.Enabled = false
    LaptopScreen.Visible = false
end)

-- ===
-- Buat Logic untuk buka browsah
-- ===

-- Variabel untuk tombol browsah di panel kiri atas desktop euyyy
local BrowsahButton = Desktop:WaitForChild("BrowsahButton")
local Apps = LaptopScreen:WaitForChild("Apps")
local Browsah_Tab = Apps:WaitForChild("Browsah_Tab")

BrowsahButton.MouseButton1Click:Connect(function()
    Apps.Visible = not Apps.Visible
    Browsah_Tab.Visible = not Browsah_Tab.Visible
end)