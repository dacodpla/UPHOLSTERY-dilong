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

-- ── PerkSystem ────────────────────────────────────────────────────────────
local PerkSystem = require(script.Parent.Parent:WaitForChild("PerkSystem", 10)
	or error("[LaptopData] PerkSystem ModuleScript not found in ServerScriptService"))

-- ── GrabHandler ───────────────────────────────────────────────────────────
-- Must be initialised before any slot is registered so collision groups and
-- player hooks are active from the first job assignment.
local GrabHandler = require(script.Parent.Parent:WaitForChild("GrabHandler", 10)
	or error("[LaptopData] GrabHandler ModuleScript not found in ServerScriptService"))
GrabHandler.Init()

-- ── Init sub-modules ──────────────────────────────────────────────────────

TalkogramHandler.Init(remotesFolder)
JobPool.Init(remotesFolder, LocationManager, RadiantJobGenerator, TalkogramHandler.SavePost)

-- ── Stub handlers ─────────────────────────────────────────────────────────

local RequestInventory        = remotesFolder:WaitForChild("RequestInventory")
local PurchaseTool            = remotesFolder:WaitForChild("PurchaseTool")
local AdminRequestLocations   = remotesFolder:WaitForChild("AdminRequestLocations")
local RequestLocationsByTier  = remotesFolder:WaitForChild("RequestLocationsByTier")

-- Returns perk inventory: {[perkId] = chargeCount}
RequestInventory.OnServerInvoke = function(player)
	return PerkSystem.GetCharges(player)
end

PurchaseTool.OnServerEvent:Connect(function(player, toolName)
	print("[LaptopData] PurchaseTool from", player.Name, "tool =", toolName)
end)

-- ── Perk / Toolbox remote handlers ───────────────────────────────────────

local GetLoadout       = remotesFolder:WaitForChild("GetLoadout")
local GetActiveEffects = remotesFolder:WaitForChild("GetActiveEffects")
local EquipPerk        = remotesFolder:WaitForChild("EquipPerk")
local UnequipPerk      = remotesFolder:WaitForChild("UnequipPerk")
local LoadoutChanged   = remotesFolder:WaitForChild("LoadoutChanged")
local BurnPerkCharges  = remotesFolder:WaitForChild("BurnPerkCharges")

local function fireLoadoutChanged(player)
	LoadoutChanged:FireClient(player, PerkSystem.GetLoadout(player), PerkSystem.GetCharges(player))
end

GetLoadout.OnServerInvoke = function(player)
	local pd = player:FindFirstChild("PlayerData")
	local ts = pd and pd:FindFirstChild("toolboxSlots")
	local maxSlots = ts and ts.Value or 3
	return PerkSystem.GetLoadout(player), PerkSystem.GetCharges(player), maxSlots
end

GetActiveEffects.OnServerInvoke = function(player)
	return PerkSystem.GetActiveEffects(player)
end

EquipPerk.OnServerEvent:Connect(function(player, slotIndex, perkId)
	local ok = PerkSystem.Equip(player, slotIndex, perkId)
	if ok then
		fireLoadoutChanged(player)
	end
end)

UnequipPerk.OnServerEvent:Connect(function(player, slotIndex)
	PerkSystem.Unequip(player, slotIndex)
	fireLoadoutChanged(player)
end)

BurnPerkCharges.OnServerEvent:Connect(function(player, minigameNames)
	PerkSystem.BurnCharges(player, type(minigameNames) == "table" and minigameNames or nil)
	fireLoadoutChanged(player)
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
