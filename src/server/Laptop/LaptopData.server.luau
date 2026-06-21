--[[
	LaptopData
	Entry point for the laptop server system.
	Wires the laptop sub-modules and per-feature handlers.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ShopData   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))

local remotesFolder = ReplicatedStorage:WaitForChild("LaptopRemotes")

-- Sub-modules
local TalkogramHandler      = require(script.Parent:WaitForChild("TalkogramHandler"))
local JobPool               = require(script.Parent:WaitForChild("JobPool"))
local DirectOfferGenerator  = require(script.Parent:WaitForChild("DirectOfferGenerator"))
local HotJobManager         = require(script.Parent:WaitForChild("HotJobManager"))
local DailyContractManager  = require(ServerScriptService:WaitForChild("DailyContractManager"))
local PerkSystem            = require(ServerScriptService:WaitForChild("PerkSystem"))

local RadiantJobGenerator = require(script.Parent.Parent:WaitForChild("RadiantJobGenerator", 10)
	or error("[LaptopData] RadiantJobGenerator not found"))
local LocationManager     = require(script.Parent.Parent:WaitForChild("LocationManager", 10)
	or error("[LaptopData] LocationManager not found"))

-- ── Init sub-modules ──────────────────────────────────────────────────────

PerkSystem.Init(remotesFolder)
TalkogramHandler.Init(remotesFolder)
DailyContractManager.Init()
JobPool.Init(remotesFolder, LocationManager, RadiantJobGenerator, TalkogramHandler.SavePost,
	PerkSystem, DailyContractManager, DirectOfferGenerator)

local HotJobCountdownRE   = remotesFolder:WaitForChild("HotJobCountdown")
local DirectOffersChanged = remotesFolder:WaitForChild("DirectOffersChanged")

DirectOfferGenerator.Init(RadiantJobGenerator, function(player)
	DirectOffersChanged:FireClient(player)
end)

HotJobManager.Init(RadiantJobGenerator, JobPool.InjectJob, HotJobCountdownRE)

-- ── Standard remotes ──────────────────────────────────────────────────────

local AdminRequestLocations  = remotesFolder:WaitForChild("AdminRequestLocations")
local RequestLocationsByTier = remotesFolder:WaitForChild("RequestLocationsByTier")

AdminRequestLocations.OnServerInvoke = function(_player)
	return LocationManager.GetLocationNames()
end

RequestLocationsByTier.OnServerInvoke = function(_player)
	return LocationManager.GetLocationsByTier()
end

-- ── Perk / Toolbox remotes ────────────────────────────────────────────────

local RequestPerkInventory = remotesFolder:WaitForChild("RequestPerkInventory")
local RequestLoadout       = remotesFolder:WaitForChild("RequestLoadout")
local RequestActiveEffects = remotesFolder:WaitForChild("RequestActiveEffects")
local EquipPerk            = remotesFolder:WaitForChild("EquipPerk")
local UnequipPerk          = remotesFolder:WaitForChild("UnequipPerk")

RequestPerkInventory.OnServerInvoke = function(player)
	local pd = player:FindFirstChild("PlayerData")
	local slots = pd and pd:FindFirstChild("toolboxSlots") and pd.toolboxSlots.Value or 0
	return { charges = PerkSystem.GetCharges(player), slots = slots }
end

RequestLoadout.OnServerInvoke = function(player)
	return PerkSystem.GetLoadout(player)
end

RequestActiveEffects.OnServerInvoke = function(player)
	return PerkSystem.GetActiveEffects(player)
end

EquipPerk.OnServerEvent:Connect(function(player, slotIndex, perkId)
	if type(slotIndex) ~= "number" or type(perkId) ~= "string" then return end
	PerkSystem.Equip(player, slotIndex, perkId)
end)

UnequipPerk.OnServerEvent:Connect(function(player, slotIndex)
	if type(slotIndex) ~= "number" then return end
	PerkSystem.Unequip(player, slotIndex)
end)

-- ── Shop remotes ──────────────────────────────────────────────────────────

local RequestShopCatalog = remotesFolder:WaitForChild("RequestShopCatalog")
local PurchasePerk       = remotesFolder:WaitForChild("PurchasePerk")
local PurchaseResult     = remotesFolder:WaitForChild("PurchaseResult")

RequestShopCatalog.OnServerInvoke = function(_player)
	local list = {}
	for _, perk in pairs(ShopData.All) do
		table.insert(list, perk)
	end
	return list
end

PurchasePerk.OnServerEvent:Connect(function(player, perkId)
	local perk = ShopData.GetById(perkId)
	if not perk then
		PurchaseResult:FireClient(player, false, "Unknown perk")
		return
	end
	local pd = player:FindFirstChild("PlayerData"); if not pd then return end
	local usd = pd:FindFirstChild("usd"); if not usd then return end
	local rep = pd:FindFirstChild("reputation") and pd.reputation.Value or 0
	if perk.requiresRep and rep < perk.requiresRep then
		PurchaseResult:FireClient(player, false, "Reputation too low")
		return
	end
	if usd.Value < perk.price then
		PurchaseResult:FireClient(player, false, "Insufficient funds")
		return
	end
	usd.Value -= perk.price
	PerkSystem.GrantCharge(player, perk.id, 1)
	PurchaseResult:FireClient(player, true, "Purchased " .. perk.name)
end)

-- ── Direct Offer remotes ──────────────────────────────────────────────────

local RequestDirectOffers = remotesFolder:WaitForChild("RequestDirectOffers")
local AcceptDirectOffer   = remotesFolder:WaitForChild("AcceptDirectOffer")

RequestDirectOffers.OnServerInvoke = function(player)
	return DirectOfferGenerator.GetOffers(player)
end

AcceptDirectOffer.OnServerEvent:Connect(function(player, offerId)
	if type(offerId) ~= "number" then return end
	local offer = DirectOfferGenerator.FindOffer(player, offerId)
	if not offer then return end
	-- Route through JobPool as if it were a board job
	JobPool.InjectActiveJobForPlayer(player, offer)
	local ok = LocationManager.Assign(player, offer)
	if not ok then
		JobPool.ClearActiveJobForPlayer(player)
		return
	end
	DirectOfferGenerator.ConsumeOffer(player, offerId)
end)

-- ── Daily Contract remotes ────────────────────────────────────────────────

local RequestDailyContracts  = remotesFolder:WaitForChild("RequestDailyContracts")
local ClaimDailyReward       = remotesFolder:WaitForChild("ClaimDailyReward")
local DailyContractsChanged  = remotesFolder:WaitForChild("DailyContractsChanged")

RequestDailyContracts.OnServerInvoke = function(player)
	return DailyContractManager.GetPlayerStatus(player)
end

ClaimDailyReward.OnServerEvent:Connect(function(player, contractId)
	if type(contractId) ~= "string" then return end
	local ok = DailyContractManager.ClaimReward(player, contractId)
	if ok then DailyContractsChanged:FireClient(player) end
end)

-- ── Player cleanup ────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	JobPool.CleanupPlayer(player)
end)

-- ── Initial pool + periodic refresh ──────────────────────────────────────

JobPool.GeneratePool()

task.spawn(function()
	while true do
		local cfg = GameConfig.JobBoard
		task.wait(math.random(cfg.replenishMin, cfg.replenishMax))
		JobPool.GeneratePool()
	end
end)
