-- besok aku lanjutin lagi sekarang mau turu dulu <<33

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SFX               = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")
local LaptopScreen = LaptopGui:WaitForChild("LaptopScreen")

local Apps = LaptopScreen:WaitForChild("Apps")
local Browsah_Tab = Apps:WaitForChild("Browsah_Tab")
local MoneyMaker_Tab = Apps:WaitForChild("MoneyMaker_Tab")
local Shop_Tab = Apps:WaitForChild("Shop_Tab")
local Talkogram_Tab = Apps:WaitForChild("Talkogram_Tab")

-- panggil bookmark button browsah tab

local bookmarkTalkogram = Browsah_Tab:WaitForChild("BookmarkTalkogram")
local bookmarkMoneyMaker = Browsah_Tab:WaitForChild("BookmarkMoneyMaker")
local bookmarkStore = Browsah_Tab:WaitForChild("BookmarkShop")

-- buat logic ketika bookmark di klik, tab yang sesuai akan muncul dan tab lainnya akan hilang

local function resetTabs()
    Talkogram_Tab.Visible = false
    MoneyMaker_Tab.Visible = false
    Shop_Tab.Visible = false
    Browsah_Tab.Visible = false
end

bookmarkTalkogram.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    resetTabs()
    Talkogram_Tab.Visible = true
end)

bookmarkMoneyMaker.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    resetTabs()
    MoneyMaker_Tab.Visible = true
end)

bookmarkStore.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    resetTabs()
    Shop_Tab.Visible = true
end)

local closeButton = Apps:WaitForChild("Miscellaneous"):WaitForChild("NonFunctional")

closeButton.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    resetTabs()
    Browsah_Tab.Visible = true
end)

local CloseBrowsahButton = Apps:WaitForChild("Miscellaneous"):WaitForChild("CloseButton")
local Miscellaneous = Apps:WaitForChild("Miscellaneous")

CloseBrowsahButton.MouseButton1Click:Connect(function()
    SFX.Play("UIClick")
    Apps.Visible = false
    Miscellaneous.Visible = false
    resetTabs()
end)
