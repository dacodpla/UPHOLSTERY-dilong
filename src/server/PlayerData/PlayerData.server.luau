local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v2")

local PerkSystem = require(ServerScriptService:WaitForChild("PerkSystem"))

local function savePlayerData(player)
	local pd = player:FindFirstChild("PlayerData")
	if not pd then return end
	local loadout, perkCharges = PerkSystem.SerializeForSave(player)
	local data = {
		usd         = (pd:FindFirstChild("usd")        or { Value = 0   }).Value,
		followers   = (pd:FindFirstChild("followers")  or { Value = 0   }).Value,
		reputation  = (pd:FindFirstChild("reputation") or { Value = 0.0 }).Value,
		loadout     = loadout,
		perkCharges = perkCharges,
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

	local ok, saved = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)
	if ok and saved then
		if saved.usd        then usd.Value        = saved.usd        end
		if saved.followers  then followers.Value   = saved.followers  end
		if saved.reputation then reputation.Value  = saved.reputation end
	elseif not ok then
		warn("[PlayerData] Load failed for", player.Name, ":", saved)
		saved = nil
	end

	-- Bootstrap perk/toolbox data using restored saved values (or fresh if none)
	PerkSystem.SetupPlayerData(player, saved)

	-- Watch reputation for slot unlocks
	reputation.Changed:Connect(function()
		PerkSystem.RefreshSlotCount(player)
	end)
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
