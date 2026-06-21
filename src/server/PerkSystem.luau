--[[
	PerkSystem
	ModuleScript — required by LaptopData.

	Manages per-player:
	  - Toolbox slot count (3-5, scales with reputation)
	  - Loadout (slot -> equipped perkId or "")
	  - Perk charge inventory (perkId -> charge count)
	  - Active effect lookup (merged effects from currently equipped perks)
	  - Charge burn on minigame run (and compound burn on Fail)

	Data lives on player.PlayerData:
	  toolboxSlots (IntValue)
	  loadout      (Folder of StringValues Slot_1..Slot_5)
	  perkCharges  (Folder of IntValues, child name = perkId)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ShopData   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("ShopData"))

local PerkSystem = {}

local _loadoutChangedRE = nil  -- set in Init

-- ── Helpers ────────────────────────────────────────────────────────────────

local function getPD(player)
	return player:FindFirstChild("PlayerData")
end

local function getLoadoutFolder(player)
	local pd = getPD(player); if not pd then return nil end
	return pd:FindFirstChild("loadout")
end

local function getChargesFolder(player)
	local pd = getPD(player); if not pd then return nil end
	return pd:FindFirstChild("perkCharges")
end

local function fireLoadoutChanged(player)
	if _loadoutChangedRE then _loadoutChangedRE:FireClient(player) end
end

-- ── Slot count from reputation ─────────────────────────────────────────────

function PerkSystem.RefreshSlotCount(player)
	local pd = getPD(player); if not pd then return end
	local rep = (pd:FindFirstChild("reputation") and pd.reputation.Value) or 0
	local thresholds = GameConfig.Reputation.slotUnlockRep
	local slots = 0
	for i, minRep in ipairs(thresholds) do
		if rep >= minRep then slots = i end
	end
	local slotsVal = pd:FindFirstChild("toolboxSlots")
	if slotsVal then slotsVal.Value = slots end
end

-- ── Loadout management ────────────────────────────────────────────────────

function PerkSystem.GetLoadout(player)
	local loadout = getLoadoutFolder(player)
	local out = {}
	if not loadout then return out end
	for i = 1, 5 do
		local sv = loadout:FindFirstChild("Slot_" .. i)
		out[i] = sv and sv.Value or ""
	end
	return out
end

function PerkSystem.GetCharges(player)
	local folder = getChargesFolder(player)
	local out = {}
	if not folder then return out end
	for _, iv in ipairs(folder:GetChildren()) do
		if iv:IsA("IntValue") then out[iv.Name] = iv.Value end
	end
	return out
end

function PerkSystem.GrantCharge(player, perkId, qty)
	if not ShopData.GetById(perkId) then return false end
	qty = qty or 1
	local folder = getChargesFolder(player); if not folder then return false end
	local iv = folder:FindFirstChild(perkId)
	if not iv then
		iv = Instance.new("IntValue")
		iv.Name   = perkId
		iv.Value  = 0
		iv.Parent = folder
	end
	iv.Value += qty
	fireLoadoutChanged(player)
	return true
end

function PerkSystem.Equip(player, slotIndex, perkId)
	local pd = getPD(player); if not pd then return false end
	local slotsVal = pd:FindFirstChild("toolboxSlots")
	local maxSlots = slotsVal and slotsVal.Value or 0
	if slotIndex < 1 or slotIndex > maxSlots then return false end

	-- Must own at least 1 charge of this perk
	local charges = getChargesFolder(player); if not charges then return false end
	local iv = charges:FindFirstChild(perkId)
	if not iv or iv.Value <= 0 then return false end

	-- Don't allow same perk in two slots
	local loadout = getLoadoutFolder(player); if not loadout then return false end
	for i = 1, 5 do
		local sv = loadout:FindFirstChild("Slot_" .. i)
		if sv and sv.Value == perkId and i ~= slotIndex then
			sv.Value = ""  -- unequip from previous slot
		end
	end

	local target = loadout:FindFirstChild("Slot_" .. slotIndex)
	if target then target.Value = perkId end
	fireLoadoutChanged(player)
	return true
end

function PerkSystem.Unequip(player, slotIndex)
	local loadout = getLoadoutFolder(player); if not loadout then return end
	local target = loadout:FindFirstChild("Slot_" .. slotIndex)
	if target then target.Value = "" end
	fireLoadoutChanged(player)
end

-- ── Effects ────────────────────────────────────────────────────────────────

function PerkSystem.GetActiveEffects(player)
	local loadout = PerkSystem.GetLoadout(player)
	local merged = {}
	for _, perkId in ipairs(loadout) do
		if perkId ~= "" then
			local perk = ShopData.GetById(perkId)
			if perk and perk.effect then
				for k, v in pairs(perk.effect) do
					if type(v) == "number" and merged[k] then
						merged[k] = merged[k] + v  -- numeric effects stack
					else
						merged[k] = v
					end
				end
				if perk.condition then
					merged._conditions = merged._conditions or {}
					merged._conditions[perkId] = perk.condition
				end
			end
		end
	end
	return merged
end

-- ── Charge burn ────────────────────────────────────────────────────────────

function PerkSystem.BurnCharges(player, count)
	count = count or 1
	local loadout = getLoadoutFolder(player); if not loadout then return end
	local charges = getChargesFolder(player); if not charges then return end
	for i = 1, 5 do
		local sv = loadout:FindFirstChild("Slot_" .. i)
		local perkId = sv and sv.Value or ""
		if perkId ~= "" then
			local iv = charges:FindFirstChild(perkId)
			if iv then
				iv.Value = math.max(0, iv.Value - count)
				if iv.Value <= 0 then
					sv.Value = ""  -- auto-unequip when out of charges
				end
			end
		end
	end
	fireLoadoutChanged(player)
end

-- ── Bootstrap per-player data ──────────────────────────────────────────────

function PerkSystem.SetupPlayerData(player, saved)
	local pd = getPD(player); if not pd then return end

	local slots = Instance.new("IntValue")
	slots.Name   = "toolboxSlots"
	slots.Value  = 3
	slots.Parent = pd

	local loadout = Instance.new("Folder")
	loadout.Name   = "loadout"
	loadout.Parent = pd
	for i = 1, 5 do
		local sv = Instance.new("StringValue")
		sv.Name   = "Slot_" .. i
		sv.Value  = ""
		sv.Parent = loadout
	end

	local charges = Instance.new("Folder")
	charges.Name   = "perkCharges"
	charges.Parent = pd

	-- Restore from saved DataStore
	if saved then
		if saved.loadout then
			for i = 1, 5 do
				local sv = loadout:FindFirstChild("Slot_" .. i)
				if sv and saved.loadout[i] then sv.Value = saved.loadout[i] end
			end
		end
		if saved.perkCharges then
			for perkId, qty in pairs(saved.perkCharges) do
				if type(qty) == "number" and qty > 0 then
					local iv = Instance.new("IntValue")
					iv.Name   = perkId
					iv.Value  = qty
					iv.Parent = charges
				end
			end
		end
	end

	PerkSystem.RefreshSlotCount(player)
end

function PerkSystem.SerializeForSave(player)
	local loadout = {}
	local lf = getLoadoutFolder(player)
	if lf then
		for i = 1, 5 do
			local sv = lf:FindFirstChild("Slot_" .. i)
			loadout[i] = sv and sv.Value or ""
		end
	end
	local charges = {}
	local cf = getChargesFolder(player)
	if cf then
		for _, iv in ipairs(cf:GetChildren()) do
			if iv:IsA("IntValue") and iv.Value > 0 then charges[iv.Name] = iv.Value end
		end
	end
	return loadout, charges
end

function PerkSystem.Init(remotes)
	_loadoutChangedRE = remotes:WaitForChild("LoadoutChanged")
end

return PerkSystem
