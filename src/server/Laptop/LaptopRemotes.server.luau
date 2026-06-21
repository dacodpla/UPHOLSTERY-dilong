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
remote("AdminSetStat")   -- dev: ("reputation"|"usd", value)

-- Teleport (used by LocationManager)
remote("TeleportToLocation")
remote("TeleportToHub")
remote("LocationFull")
remote("FurniturePieceRepaired")
remote("StartMinigame")
