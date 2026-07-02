--[[
	RadiantJobGenerator
	Server-side procedural job generator for the global job board.

	All players in the server share the same job pool — no per-player gating.
	Tier distribution is controlled by GameConfig.JobTierRarity weights.
	Higher tiers (Exclusive, Elite, Special) are rarer but accessible to everyone.

	Furniture: scans ServerStorage.FurnitureModels at require time.
	  Each subfolder must have a "Tier" string attribute.
	  DisplayName attribute is optional; falls back to CamelCase splitting.

	Content data (damage types, flavor text, tier rules) lives in GameConfig —
	edit it there without touching this file.

	Usage:
	  local jobs = RadiantJobGenerator.Generate(count)
	  local jobs = RadiantJobGenerator.Generate(count, allowedTiers)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- Pull content tables from GameConfig so designers edit data, not logic.
local TIER_ORDER  = GameConfig.JobTierOrder
local DAMAGE_POOL = GameConfig.JobDamagePool
local FLAVOR_POOL = GameConfig.JobFlavorPool
local TIER_CONFIG = GameConfig.JobTierConfig

-- Maps job tier → JobFlavorPool sub-table key.
local FLAVOR_GROUP = {
	Starter   = "Casual",
	Mid       = "Casual",
	Premium   = "Upscale",
	Prestige  = "Upscale",
	Exclusive = "Elite",
	Elite     = "Elite",
	Special   = "Elite",
}

-- ── Furniture pool ────────────────────────────────────────────────────────
-- Built once at require time by scanning ServerStorage.FurnitureModels.
-- Each subfolder needs a "Tier" string attribute; "Category" is optional.

local _furniturePool       = {}  -- [tier]          = { key, ... }
local _furnitureByCategory = {}  -- [category][tier] = { key, ... }
local _furnitureDisplay    = {}  -- [key]            = display name string

-- "BarStool" → "Bar Stool"
local function toDisplayName(key)
	return key:gsub("(%l)(%u)", "%1 %2")
end

local function buildFurniturePool()
	local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
	if not furnitureFolder then
		warn("[RadiantJobGenerator] ServerStorage.FurnitureModels not found — job board will have no furniture")
		return
	end

	for _, child in ipairs(furnitureFolder:GetChildren()) do
		if not child:IsA("Folder") then continue end

		local tier = child:GetAttribute("Tier") or "Starter"

		if not _furniturePool[tier] then
			_furniturePool[tier] = {}
		end
		table.insert(_furniturePool[tier], child.Name)
		_furnitureDisplay[child.Name] = child:GetAttribute("DisplayName") or toDisplayName(child.Name)

		local category = child:GetAttribute("Category")
		if category then
			if not _furnitureByCategory[category] then
				_furnitureByCategory[category] = {}
			end
			if not _furnitureByCategory[category][tier] then
				_furnitureByCategory[category][tier] = {}
			end
			table.insert(_furnitureByCategory[category][tier], child.Name)
		end
	end

	for tier, keys in pairs(_furniturePool) do
		if #keys > 0 then
			print(("[RadiantJobGenerator] %s furniture: %s"):format(tier, table.concat(keys, ", ")))
		end
	end
end

buildFurniturePool()

-- ── Helpers ───────────────────────────────────────────────────────────────

local function pickRandom(tbl)
	return tbl[math.random(#tbl)]
end

local function shuffleCopy(tbl)
	local copy = table.clone(tbl)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Returns a furniture key for the given category and tier.
-- Falls back through all tiers high→low if the exact tier has nothing,
-- then falls back to the flat fallbackPool if the category isn't mapped at all.
local function pickForCategory(category, jobTier, fallbackPool)
	local catPools = _furnitureByCategory[category]
	if catPools then
		if catPools[jobTier] and #catPools[jobTier] > 0 then
			return pickRandom(catPools[jobTier])
		end
		for _, t in ipairs(TIER_ORDER) do
			if catPools[t] and #catPools[t] > 0 then
				return pickRandom(catPools[t])
			end
		end
	end
	if fallbackPool and #fallbackPool > 0 then
		return pickRandom(fallbackPool)
	end
	return nil
end

-- Returns the best furniture pool at or below the given tier.
local function getFurniturePool(tier)
	local reached = false
	for _, t in ipairs(TIER_ORDER) do
		if t == tier then reached = true end
		if reached and _furniturePool[t] and #_furniturePool[t] > 0 then
			return _furniturePool[t]
		end
	end
	-- Last resort: any tier with furniture
	for _, t in ipairs(TIER_ORDER) do
		if _furniturePool[t] and #_furniturePool[t] > 0 then
			return _furniturePool[t]
		end
	end
	return nil
end

-- ── Tier roll ─────────────────────────────────────────────────────────────
-- Weighted random from GameConfig.JobTierRarity.
-- allowedTiers: set table [tier]=true from LocationManager.GetAvailableTiers().
-- Tiers absent from allowedTiers are skipped so we never generate jobs with no building.

local function rollJobTier(allowedTiers)
	local weights = GameConfig.JobTierRarity
	local total   = 0
	for _, tier in ipairs(TIER_ORDER) do
		local w = weights[tier]
		if w and (not allowedTiers or allowedTiers[tier]) then
			total = total + w
		end
	end
	if total == 0 then return "Starter" end

	local roll       = math.random() * total
	local cumulative = 0
	for _, tier in ipairs(TIER_ORDER) do
		local w = weights[tier]
		if w and (not allowedTiers or allowedTiers[tier]) then
			cumulative = cumulative + w
			if roll < cumulative then return tier end
		end
	end
	return "Starter"
end

-- ── Pay / follower calculations ───────────────────────────────────────────

local function calcPay(tier)
	local range = GameConfig.Economy.payByTier[tier] or GameConfig.Economy.payByTier.Starter
	return math.random(range.min, range.max)
end

local function calcFollowers(tier)
	local range = GameConfig.Followers.gainByTier[tier] or GameConfig.Followers.gainByTier.Starter
	return math.random(range.min, range.max)
end

-- ── Job name builder ──────────────────────────────────────────────────────

local function buildJobName(pieceCount, displayNames, damageLabels, minigames)
	if pieceCount > 1 then
		return table.concat(displayNames, " & ")
	elseif #minigames == 1 then
		return displayNames[1] .. " — " .. damageLabels[1]
	else
		return displayNames[1]
	end
end

-- ── Public API ────────────────────────────────────────────────────────────

local RadiantJobGenerator = {}

function RadiantJobGenerator.Generate(count, allowedTiers)
	local jobs = {}

	for i = 1, count do
		local jobTier = rollJobTier(allowedTiers)
		local cfg     = TIER_CONFIG[jobTier] or TIER_CONFIG.Starter

		local furniturePool = getFurniturePool(jobTier)
		if not furniturePool then
			warn("[RadiantJobGenerator] No furniture available in any tier — skipping job", i)
			continue
		end

		local pieceCount    = math.random(cfg.furnitureCount.min, cfg.furnitureCount.max)
		local shuffledDmg   = shuffleCopy(DAMAGE_POOL)
		local furnitureList = {}
		local displayNames  = {}
		local minigames     = {}
		local damageLabels  = {}

		if pieceCount > 1 then
			-- Multi-piece: one furniture piece + one minigame per slot
			for p = 1, pieceCount do
				local category = cfg.pieces[p] or cfg.pieces[1]
				local key = pickForCategory(category, jobTier, furniturePool)
				if not key then continue end
				table.insert(furnitureList, key)
				table.insert(displayNames,  _furnitureDisplay[key] or toDisplayName(key))
				if shuffledDmg[p] then
					table.insert(minigames,    shuffledDmg[p].minigame)
					table.insert(damageLabels, shuffledDmg[p].label)
				end
			end
		else
			-- Single-piece: one furniture with a minigame chain
			local category = cfg.pieces[1]
			local key = pickForCategory(category, jobTier, furniturePool)
			if not key then continue end
			table.insert(furnitureList, key)
			table.insert(displayNames,  _furnitureDisplay[key] or toDisplayName(key))
			local mgCount = math.random(cfg.minigameCount.min, cfg.minigameCount.max)
			for j = 1, mgCount do
				if shuffledDmg[j] then
					table.insert(minigames,    shuffledDmg[j].minigame)
					table.insert(damageLabels, shuffledDmg[j].label)
				end
			end
		end

		if #furnitureList == 0 then continue end

		local jobName    = buildJobName(pieceCount, displayNames, damageLabels, minigames)
		local flavorPool = FLAVOR_POOL[FLAVOR_GROUP[jobTier] or "Casual"] or FLAVOR_POOL.Casual
		local flavor     = pickRandom(flavorPool)
		local details    = flavor .. " (" .. table.concat(damageLabels, ", ") .. ")"

		-- Physics workflow fields
		local physCfg    = GameConfig.PhysicsWorkflow
		local fullChance = (physCfg.workflowFullChance[jobTier] or 1.0)
		local workflow   = (math.random() < fullChance) and "full" or "half"
		local finishType = (math.random() < 0.5) and "stitch" or "staple"

		table.insert(jobs, {
			id         = i,   -- reassigned by LaptopData with a server-unique ID
			name       = jobName,
			details    = details,
			tier       = jobTier,
			pay        = calcPay(jobTier),
			followers  = calcFollowers(jobTier),
			imageId    = 0,
			furniture  = furnitureList,
			minigames  = minigames,
			difficulty = cfg.difficulty,
			fragile    = cfg.fragile,
			workflow   = workflow,    -- "full" or "half" — controls which tools spawn
			finishType = finishType,  -- "stitch" or "staple" — which finishing minigame
		})
	end

	-- Inject bespoke (tag-based) jobs from GameConfig.BespokeJobs.
	-- Up to 2 eligible entries are picked randomly and appended to the pool.
	local bespoke = GameConfig.BespokeJobs
	if bespoke and #bespoke > 0 then
		local eligible = {}
		for _, bj in ipairs(bespoke) do
			if not allowedTiers or allowedTiers[bj.tier] then
				table.insert(eligible, bj)
			end
		end
		local shuffled = shuffleCopy(eligible)
		for k = 1, math.min(2, #shuffled) do
			local bj = shuffled[k]
			table.insert(jobs, {
				id               = k,   -- reassigned by LaptopData
				name             = bj.name,
				details          = bj.details,
				tier             = bj.tier,
				pay              = bj.pay,
				followers        = bj.followers,
				imageId          = bj.imageId or 0,
				furniture        = {},              -- empty → tag-based scan in LocationManager
				minigames        = bj.minigames,
				difficulty       = bj.difficulty or "Medium",
				fragile          = bj.fragile or false,
				locationOverride = bj.locationOverride,
			})
		end
	end

	return jobs
end

return RadiantJobGenerator
