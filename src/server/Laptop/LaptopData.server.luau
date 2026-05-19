--[[
	LaptopData
	Entry point for the laptop server system.
	Wires handlers and delegates to:
	    JobPool          – job board, acceptance, results, abandonment
	    TalkogramHandler  – social feed, posts, comments
	Remotes are created by LaptopRemotes.server.luau; fetched here via WaitForChild.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local remotesFolder = ReplicatedStorage:WaitForChild("LaptopRemotes")

-- Sub-modules (siblings in the Laptop folder)
local TalkogramHandler = require(script.Parent:WaitForChild("TalkogramHandler"))
local JobPool          = require(script.Parent:WaitForChild("JobPool"))

local RadiantJobGenerator = require(script.Parent.Parent:WaitForChild("RadiantJobGenerator", 10)
	or error("[LaptopData] RadiantJobGenerator not found in ServerScriptService — did Rojo sync?"))

-- ── LocationManager ───────────────────────────────────────────────────────
-- Required after LaptopRemotes so LocationManager can WaitForChild on them.
local LocationManager = require(script.Parent.Parent:WaitForChild("LocationManager", 10)
	or error("[LaptopData] LocationManager ModuleScript not found in ServerScriptService — did Rojo sync?"))

-- ── Init sub-modules ──────────────────────────────────────────────────────

TalkogramHandler.Init(remotesFolder)
JobPool.Init(remotesFolder, LocationManager, RadiantJobGenerator, TalkogramHandler.SavePost)

-- ── Stub handlers ─────────────────────────────────────────────────────────

local RequestInventory      = remotesFolder:WaitForChild("RequestInventory")
local PurchaseTool          = remotesFolder:WaitForChild("PurchaseTool")
local AdminRequestLocations = remotesFolder:WaitForChild("AdminRequestLocations")

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
