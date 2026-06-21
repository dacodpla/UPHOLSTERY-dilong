--[[
	LaptopRemotes
	Creates every RemoteEvent and RemoteFunction under LaptopRemotes in
	ReplicatedStorage. Nothing else — no handlers, no state.
	Other scripts get the remotes via WaitForChild on ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name   = "LaptopRemotes"
folder.Parent = ReplicatedStorage

local function remote(name)
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = folder
end

local function remoteFunction(name)
	local rf = Instance.new("RemoteFunction")
	rf.Name   = name
	rf.Parent = folder
end

-- Job board
remoteFunction("RequestJobs")
remote("AcceptJob")
remote("SubmitJobResult")
remote("AbandonJob")
remote("JobBoardRefresh")
remote("JobRewardNotify")   -- server → client after every job end (success/fail/abandon)

-- Talkogram feed
remoteFunction("RequestFeed")
remoteFunction("RequestPost")
remote("PostComment")
remote("LikePost")

-- Shop / inventory
remoteFunction("RequestInventory")
remote("PurchaseTool")

-- Job board metadata (public)
remoteFunction("RequestLocationsByTier")

-- Admin
remote("AdminSpawnJob")
remoteFunction("AdminRequestLocations")

-- Teleport (used by LocationManager)
remote("TeleportToLocation")
remote("TeleportToHub")
remote("LocationFull")
remote("FurniturePieceRepaired")
remote("StartMinigame")

-- Perks / Toolbox (Phase 3)
remoteFunction("RequestPerkInventory")
remoteFunction("RequestLoadout")
remoteFunction("RequestActiveEffects")
remote("EquipPerk")
remote("UnequipPerk")
remote("LoadoutChanged")

-- Shop (Phase 4)
remoteFunction("RequestShopCatalog")
remote("PurchasePerk")
remote("PurchaseResult")

-- Direct Offers (Phase 5)
remoteFunction("RequestDirectOffers")
remote("AcceptDirectOffer")
remote("DirectOffersChanged")

-- Hot Jobs (Phase 6)
remote("HotJobCountdown")

-- Daily Contracts (Phase 7)
remoteFunction("RequestDailyContracts")
remote("ClaimDailyReward")
remote("DailyContractsChanged")
