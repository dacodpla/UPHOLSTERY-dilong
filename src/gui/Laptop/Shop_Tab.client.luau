local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")
local LaptopScreen = LaptopGui:WaitForChild("LaptopScreen")

local Apps     = LaptopScreen:WaitForChild("Apps")
local Shop_Tab = Apps:WaitForChild("Shop_Tab"):WaitForChild("Body")

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

local showDetail = nil

for _, category in ipairs(categories) do
	for _, product in ipairs(category) do
		local card = ProductTemplate:Clone()
		card.Name = product.id

		local imageButton = card:FindFirstChild("ImageButton")

		if imageButton then
			imageButton.Image = product.icon
			imageButton.MouseButton1Click:Connect(function()
				if showDetail then
					showDetail(product)
				end
			end)

			local productText = imageButton:FindFirstChild("ProductText")
			if productText then
				productText.Text = product.price .. " Cash"
			else
				warn("[Shop_Tab] ImageButton tidak punya 'ProductText' — harga dilewati untuk", product.id)
			end
		else
			warn("[Shop_Tab] ProductTemplate tidak punya 'ImageButton' — gambar/klik/harga dilewati untuk", product.id)
		end

		card.Visible = true
		card.Parent  = ScrollingFrame
	end
end

local ItemDetail = Shop_Tab:WaitForChild("itemDetail", 5)
if not ItemDetail then
	warn("[Shop_Tab] 'itemDetail' tidak ditemukan di Body — panel detail dinonaktifkan (produk tetap tampil).")
	return
end

local BuyButton = ItemDetail:FindFirstChild("buyButton", true)
local ItemImage = ItemDetail:FindFirstChild("itemImage", true)
local ItemDes   = ItemDetail:FindFirstChild("itemDes", true)
local ItemName  = ItemDetail:FindFirstChild("itemName", true)

for name, inst in pairs({ BuyButton = BuyButton, itemImage = ItemImage, itemDes = ItemDes, itemName = ItemName }) do
	if not inst then
		warn("[Shop_Tab] itemDetail tidak punya '" .. name .. "' — field ini dilewati.")
	end
end

ItemDetail.Visible = false

local SCROLL_SIZE_COLLAPSED = UDim2.new(0.964, 0, 0.972, 0)
local SCROLL_SIZE_EXPANDED  = UDim2.new(0.771, 0, 0.972, 0)

local function syncScrollSize()
	ScrollingFrame.Size = ItemDetail.Visible and SCROLL_SIZE_EXPANDED or SCROLL_SIZE_COLLAPSED
end
syncScrollSize()
ItemDetail:GetPropertyChangedSignal("Visible"):Connect(syncScrollSize)

local selectedProduct = nil

showDetail = function(product)
	if ItemDetail.Visible and selectedProduct == product then
		selectedProduct    = nil
		ItemDetail.Visible = false
		return
	end

	selectedProduct = product
	if ItemName  then ItemName.Text   = product.name        end
	if ItemDes   then ItemDes.Text    = product.description end
	if ItemImage then ItemImage.Image = product.icon        end
	if BuyButton then BuyButton.Text  = product.price .. " Cash" end
	ItemDetail.Visible = true
end

-- ============================================================
--  PEMBELIAN — klik BuyButton -> minta server beli produk terpilih
--  >>> BUAT MANUAL: RemoteFunction "BuyItem" di ReplicatedStorage <<<
-- ============================================================
if BuyButton then
	local BuyItem = ReplicatedStorage:WaitForChild("BuyItem", 15)
	if not BuyItem then
		warn("[Shop_Tab] RemoteFunction 'BuyItem' belum ada di ReplicatedStorage — tombol beli nonaktif.")
	else
		local buying = false
		BuyButton.MouseButton1Click:Connect(function()
			if buying or not selectedProduct then return end
			buying = true
			BuyButton.Active = false

			local product = selectedProduct
			local ok, success, message = pcall(function()
				return BuyItem:InvokeServer(product.id)
			end)

			if ok then
				print("[Shop_Tab] beli", product.id, "->", success, message)
			else
				warn("[Shop_Tab] gagal memanggil BuyItem:", success)
			end

			BuyButton.Active = true
			buying = false
		end)
	end
end
