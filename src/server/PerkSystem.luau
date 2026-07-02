--[[
	PerkSystem
	Server ModuleScript — manages perk loadout slots, inventory charges,
	effect merging, and charge burning.

	Public API:
	  PerkSystem.Equip(player, slotIndex, perkId)  → bool
	  PerkSystem.Unequip(player, slotIndex)
	  PerkSystem.GetLoadout(player)                → {[1..5] = perkId|""}
	  PerkSystem.GetCharges(player)                → {[perkId] = count}
	  PerkSystem.GetActiveEffects(player)          → merged flat effect table
	  PerkSystem.BurnCharges(player)               → decrements all equipped perks by 1
	  PerkSystem.RefreshSlotCount(player)          → updates toolboxSlots from rep
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopData = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Data")
		:WaitForChild("ShopData")
)

local PerkSystem = {}

-- ── Private helpers ───────────────────────────────────────────────────────────

local function getPlayerData(player)
	return player:FindFirstChild("PlayerData")
end

local function getLoadoutFolder(player)
	local pd = getPlayerData(player)
	return pd and pd:FindFirstChild("loadout")
end

local function getInventoryFolder(player)
	local pd = getPlayerData(player)
	return pd and pd:FindFirstChild("Inventory")
end

local function getSlotCount(player)
	local pd = getPlayerData(player)
	local ts = pd and pd:FindFirstChild("toolboxSlots")
	return ts and ts.Value or 3
end

local function getChargesFor(player, perkId)
	local inv = getInventoryFolder(player)
	if not inv then return 0 end
	local item = inv:FindFirstChild(perkId)
	return item and item.Value or 0
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PerkSystem.Equip(player, slotIndex, perkId)
	if type(slotIndex) ~= "number" then return false end
	slotIndex = math.floor(slotIndex)
	if slotIndex < 1 or slotIndex > 5 then return false end
	if type(perkId) ~= "string" or perkId == "" then return false end

	-- Validate product exists and is a perk (has minigame field)
	local product = ShopData.GetById(perkId)
	if not product or not product.minigame then return false end

	-- Slot must be unlocked
	if slotIndex > getSlotCount(player) then return false end

	-- Must have at least 1 charge in inventory
	if getChargesFor(player, perkId) <= 0 then return false end

	local ld = getLoadoutFolder(player)
	if not ld then return false end
	local slot = ld:FindFirstChild("Slot_" .. slotIndex)
	if not slot then return false end

	slot.Value = perkId
	return true
end

function PerkSystem.Unequip(player, slotIndex)
	if type(slotIndex) ~= "number" then return end
	slotIndex = math.floor(slotIndex)
	local ld = getLoadoutFolder(player)
	if not ld then return end
	local slot = ld:FindFirstChild("Slot_" .. slotIndex)
	if slot then slot.Value = "" end
end

function PerkSystem.GetLoadout(player)
	local ld = getLoadoutFolder(player)
	local result = {}
	for i = 1, 5 do
		local slot = ld and ld:FindFirstChild("Slot_" .. i)
		result[i] = (slot and slot.Value ~= "") and slot.Value or ""
	end
	return result
end

function PerkSystem.GetCharges(player)
	local inv = getInventoryFolder(player)
	if not inv then return {} end
	local result = {}
	for _, item in ipairs(inv:GetChildren()) do
		if item:IsA("IntValue") and item.Value > 0 then
			-- Only include items that are actually bolt perks
			local product = ShopData.GetById(item.Name)
			if product and product.minigame then
				result[item.Name] = item.Value
			end
		end
	end
	return result
end

function PerkSystem.GetActiveEffects(player)
	local ld  = getLoadoutFolder(player)
	if not ld then return {} end
	local inv = getInventoryFolder(player)
	local merged = {}

	for i = 1, 5 do
		local slot = ld:FindFirstChild("Slot_" .. i)
		if slot and slot.Value ~= "" then
			local perkId    = slot.Value
			local chargeVal = inv and inv:FindFirstChild(perkId)
			if not chargeVal or chargeVal.Value <= 0 then
				slot.Value = ""
			else
				local product = ShopData.GetById(perkId)
				if product and product.effect then
					for k, v in pairs(product.effect) do
						if type(v) == "number" and type(merged[k]) == "number" then
							merged[k] = merged[k] + v
						else
							merged[k] = v
						end
					end
				end
			end
		end
	end

	return merged
end

-- minigameNames: array of minigame name strings that were actually played this run.
-- A perk is only burned if its minigame field is in that list.
-- Pass nil to burn all (legacy / fallback).
function PerkSystem.BurnCharges(player, minigameNames)
	local ld  = getLoadoutFolder(player)
	local inv = getInventoryFolder(player)
	if not ld or not inv then return end

	local matchSet = nil
	if minigameNames then
		matchSet = {}
		for _, name in ipairs(minigameNames) do
			matchSet[name] = true
		end
	end

	for i = 1, 5 do
		local slot = ld:FindFirstChild("Slot_" .. i)
		if slot and slot.Value ~= "" then
			local perkId  = slot.Value
			local product = ShopData.GetById(perkId)

			local skip = matchSet and product and product.minigame
				and not matchSet[product.minigame]

			if not skip then
				local chargeVal = inv:FindFirstChild(perkId)
				if chargeVal then
					chargeVal.Value = math.max(0, chargeVal.Value - 1)
					if chargeVal.Value <= 0 then
						slot.Value = ""
					end
				else
					slot.Value = ""
				end
			end
		end
	end
end

function PerkSystem.RefreshSlotCount(player)
	local pd = getPlayerData(player)
	if not pd then return end
	local repVal = pd:FindFirstChild("reputation")
	local tsVal  = pd:FindFirstChild("toolboxSlots")
	if not repVal or not tsVal then return end

	local rep = repVal.Value
	if rep >= 3.0 then
		tsVal.Value = 5
	elseif rep >= 1.5 then
		tsVal.Value = 4
	else
		tsVal.Value = 3
	end
end

return PerkSystem
