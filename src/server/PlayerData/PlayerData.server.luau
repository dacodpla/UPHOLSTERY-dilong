local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ShopData        = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

local function savePlayerData(player)
	local pd = player:FindFirstChild("PlayerData")
	if not pd then return end

	-- inventory disimpan sebagai map aduh beb sakit perut akyuh
	local inventory = {}
	local inv = pd:FindFirstChild("Inventory")
	if inv then
		for _, item in ipairs(inv:GetChildren()) do
			inventory[item.Name] = item.Value
		end
	end

	local data = {
		usd        = (pd:FindFirstChild("usd")        or { Value = 0   }).Value,
		followers  = (pd:FindFirstChild("followers")  or { Value = 0   }).Value,
		reputation = (pd:FindFirstChild("reputation") or { Value = 0.0 }).Value,
		Inventory  = inventory,
	}
	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. player.UserId, data)
	end)
	if not ok then
		warn("[PlayerData] Save failed for", player.Name, ":", err)
	end
end

Players.PlayerAdded:Connect(function(player)
	local playerData = Instance.new("Folder")
	playerData.Name   = "PlayerData"
	playerData.Parent = player

	local usd = Instance.new("IntValue")
	usd.Name   = "usd"
	usd.Value  = 0
	usd.Parent = playerData

	local followers = Instance.new("IntValue")
	followers.Name   = "followers"
	followers.Value  = 0
	followers.Parent = playerData

	local reputation = Instance.new("NumberValue")
	reputation.Name   = "reputation"
	reputation.Value  = 0.0
	reputation.Parent = playerData

	local Inventory = Instance.new("Folder")
	Inventory.Name   = "Inventory"
	Inventory.Parent = playerData

	local ok, saved = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)
	if ok and saved then
		if saved.usd        then usd.Value        = saved.usd        end
		if saved.followers  then followers.Value   = saved.followers  end
		if saved.reputation then reputation.Value  = saved.reputation end
		if saved.Inventory then
			for id, qty in pairs(saved.Inventory) do
				local item = Instance.new("IntValue")
				item.Name   = id
				item.Value  = qty
				item.Parent = Inventory
			end
		end
	elseif not ok then
		warn("[PlayerData] Load failed for", player.Name, ":", saved)
	end
end)

local function handleBuy(player, productId)
	if type(productId) ~= "string" then
		return false, "Permintaan tidak valid"
	end

	local product = ShopData.GetById(productId)
	if not product then
		return false, "Produk tidak ditemukan"
	end

	local pd = player:FindFirstChild("PlayerData")
	if not pd then return false, "Data belum siap" end

	local usd = pd:FindFirstChild("usd")
	local inv = pd:FindFirstChild("Inventory")
	if not usd or not inv then return false, "Data belum siap" end

	local existing = inv:FindFirstChild(productId)

	if not product.oneTimeUse and existing then
		return false, "Sudah dimiliki"
	end

	if usd.Value < product.price then
		return false, "Uang tidak cukup"
	end

	usd.Value = usd.Value - product.price
	if existing then
		existing.Value += 1
	else
		local item = Instance.new("IntValue")
		item.Name   = productId
		item.Value  = 1
		item.Parent = inv
	end

	savePlayerData(player)
	return true, "Berhasil membeli " .. product.name
end

task.spawn(function()
	local BuyItem = ReplicatedStorage:WaitForChild("BuyItem", 15)
	if not BuyItem then
		warn("[PlayerData] RemoteFunction 'BuyItem' belum ada di ReplicatedStorage — pembelian dinonaktifkan sedih banget dehhh :(.")
		return
	end
	BuyItem.OnServerInvoke = handleBuy
end)

Players.PlayerRemoving:Connect(savePlayerData)

task.spawn(function()
	while true do
		task.wait(300)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerData(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)
