--[[
	LaptopData
	Entry point for the laptop server system.
	Creates LaptopRemotes in ReplicatedStorage, then delegates to:
	    JobPool         – job board, acceptance, results, abandonment
	    TalkogramHandler – social feed, posts, comments
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- Sub-modules (siblings in the Laptop folder)
local TalkogramHandler = require(script.Parent:WaitForChild("TalkogramHandler"))
local JobPool          = require(script.Parent:WaitForChild("JobPool"))

local RadiantJobGenerator = require(script.Parent.Parent:WaitForChild("RadiantJobGenerator", 10)
	or error("[LaptopData] RadiantJobGenerator not found in ServerScriptService — did Rojo sync?"))

-- ── Remote setup ──────────────────────────────────────────────────────────

local remotesFolder = Instance.new("Folder")
remotesFolder.Name   = "LaptopRemotes"
remotesFolder.Parent = ReplicatedStorage

local function makeRemote(name)
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = remotesFolder
	return re
end

local function makeRemoteFunction(name)
	local rf = Instance.new("RemoteFunction")
	rf.Name   = name
	rf.Parent = remotesFolder
	return rf
end

-- Job board
makeRemoteFunction("RequestJobs")
makeRemote("AcceptJob")
makeRemote("SubmitJobResult")
makeRemote("AbandonJob")
makeRemote("JobBoardRefresh")

-- Talkogram feed
makeRemoteFunction("RequestFeed")
makeRemoteFunction("RequestPost")
makeRemote("PostComment")
makeRemote("LikePost")

-- Shop / inventory
local RequestInventory = makeRemoteFunction("RequestInventory")
local PurchaseTool     = makeRemote("PurchaseTool")

-- Admin
makeRemote("AdminSpawnJob")
local AdminRequestLocations = makeRemoteFunction("AdminRequestLocations")

-- Teleport events (used by LocationManager)
makeRemote("TeleportToLocation")
makeRemote("TeleportToHub")
makeRemote("LocationFull")
makeRemote("FurniturePieceRepaired")
makeRemote("StartMinigame")

-- ── LocationManager ───────────────────────────────────────────────────────
-- Required after remotes are created so LocationManager can WaitForChild on them.
local LocationManager = require(script.Parent.Parent:WaitForChild("LocationManager", 10)
	or error("[LaptopData] LocationManager ModuleScript not found in ServerScriptService — did Rojo sync?"))

-- ── Init sub-modules ──────────────────────────────────────────────────────

TalkogramHandler.Init(remotesFolder)
JobPool.Init(remotesFolder, LocationManager, RadiantJobGenerator, TalkogramHandler.SavePost)

-- ── Stub handlers ─────────────────────────────────────────────────────────

RequestInventory.OnServerInvoke = function(_player)
	return {}
end

PurchaseTool.OnServerEvent:Connect(function(player, toolName)
	print("[LaptopData] PurchaseTool from", player.Name, "tool =", toolName)
end)

AdminRequestLocations.OnServerInvoke = function(_player)
	return LocationManager.GetLocationNames()
end

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
