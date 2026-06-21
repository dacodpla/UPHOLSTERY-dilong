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

local RequestInventory        = remotesFolder:WaitForChild("RequestInventory")
local PurchaseTool            = remotesFolder:WaitForChild("PurchaseTool")
local AdminRequestLocations   = remotesFolder:WaitForChild("AdminRequestLocations")
local RequestLocationsByTier  = remotesFolder:WaitForChild("RequestLocationsByTier")

RequestInventory.OnServerInvoke = function(_player)
	return {}
end

PurchaseTool.OnServerEvent:Connect(function(player, toolName)
	print("[LaptopData] PurchaseTool from", player.Name, "tool =", toolName)
end)

AdminRequestLocations.OnServerInvoke = function(_player)
	return LocationManager.GetLocationNames()
end

RequestLocationsByTier.OnServerInvoke = function(_player)
	return LocationManager.GetLocationsByTier()
end

local AdminSetStat = remotesFolder:WaitForChild("AdminSetStat")
AdminSetStat.OnServerEvent:Connect(function(player, statName, value)
	if type(statName) ~= "string" or type(value) ~= "number" then return end
	local pd = player:FindFirstChild("PlayerData")
	if not pd then return end
	if statName == "reputation" then
		local rv = pd:FindFirstChild("reputation")
		if rv then
			rv.Value = math.clamp(value, 0, 5)
		end
	elseif statName == "usd" then
		local uv = pd:FindFirstChild("usd")
		if uv then uv.Value = math.max(0, uv.Value + math.floor(value)) end
	end
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
