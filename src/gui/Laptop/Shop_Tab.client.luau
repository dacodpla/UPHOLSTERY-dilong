local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")
local LaptopScreen = LaptopGui:WaitForChild("LaptopScreen")

local Apps     = LaptopScreen:WaitForChild("Apps")
local Shop_Tab = Apps:WaitForChild("Shop_Tab")

local ShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))

local ScrollingFrame  = Shop_Tab:WaitForChild("ScrollingFrame")
local ProductTemplate = ScrollingFrame:WaitForChild("ProductTemplate")
ProductTemplate.Visible = false

local categories = {
    ShopData.Tools,
    ShopData.JobManagement,
    ShopData.Efficiency,
    ShopData.Reputation,
}

for _, category in ipairs(categories) do
    for _, product in ipairs(category) do
        local card = ProductTemplate:Clone()
        card.Name = product.id
        card.ProductImg.Image = product.icon
        card.ProductText.Text = product.price .. " Cash"
        card.Visible = true
        card.Parent = ScrollingFrame
    end
end
