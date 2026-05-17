--[[
	RadiantJobGenerator
	Server-side procedural job generator for the global job board.

	All players in the server share the same job pool — no per-player gating.
	Tier distribution is controlled by GameConfig.JobTierRarity weights.
	Higher tiers (Exclusive, Elite, Special) are rarer but accessible to everyone.

	Furniture: scans ServerStorage.FurnitureModels at require time.
	  Each subfolder must have a "Tier" string attribute.
	  DisplayName attribute is optional; falls back to CamelCase splitting.

	Usage:
	  local jobs = RadiantJobGenerator.Generate(count)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- ── Tier ordering (highest → lowest; used for rarity roll + fallback) ────

local TIER_ORDER = { "Special", "Elite", "Exclusive", "Prestige", "Premium", "Mid", "Starter" }

-- ── Damage pool ───────────────────────────────────────────────────────────

local DAMAGE_POOL = {
	{ label = "tack damage",   minigame = "TackRemoval"   },
	{ label = "loose staples", minigame = "StapleGunning" },
	{ label = "foam collapse", minigame = "FoamPadding"   },
	{ label = "torn seam",     minigame = "SeamStitching" },
}

-- ── Client flavor text ────────────────────────────────────────────────────

local FLAVOR_POOL = {
	"Customer needs this done before the weekend.",
	"Handle with care — sentimental piece.",
	"Quick turnaround required.",
	"Client is very particular about fabric tension.",
	"This was my late mother's. Please be gentle.",
	"Going into a rental property — needs to hold up.",
	"Needs to match the existing set.",
	"Rush order. Tip possible.",
	"Condition is worse than the photos suggest.",
	"Client bought the fabric themselves.",
	"Second attempt — first upholsterer botched it.",
	"High-profile client. Discretion appreciated.",
}

-- ── Per-tier game rules ───────────────────────────────────────────────────
-- pieces: furniture categories drawn per piece (Seating / Accent).
-- furnitureCount: how many furniture pieces in the job.
-- minigameCount: chain length for single-piece jobs; ignored for multi-piece.

local TIER_CONFIG = {
	Starter   = { furnitureCount={min=1,max=1}, pieces={"Seating"},                    minigameCount={min=1,max=1}, difficulty="Easy",   fragile=false },
	Mid       = { furnitureCount={min=1,max=2}, pieces={"Seating","Accent"},           minigameCount={min=1,max=2}, difficulty="Medium", fragile=false },
	Premium   = { furnitureCount={min=2,max=2}, pieces={"Seating","Accent"},           minigameCount={min=2,max=2}, difficulty="Hard",   fragile=true  },
	Prestige  = { furnitureCount={min=2,max=3}, pieces={"Seating","Accent","Seating"}, minigameCount={min=2,max=3}, difficulty="Hard",   fragile=true  },
	Exclusive = { furnitureCount={min=2,max=3}, pieces={"Seating","Accent","Accent"},  minigameCount={min=2,max=3}, difficulty="Hard",   fragile=true  },
	Elite     = { furnitureCount={min=3,max=3}, pieces={"Seating","Accent","Accent"},  minigameCount={min=3,max=3}, difficulty="Hard",   fragile=true  },
	Special   = { furnitureCount={min=1,max=3}, pieces={"Seating","Accent","Seating"}, minigameCount={min=2,max=4}, difficulty="Hard",   fragile=true  },
}

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

-- "BarStool" → "Bar Stool"
local function toDisplayName(key)
	return key:gsub("(%l)(%u)", "%1 %2")
end

-- ── Dynamic furniture pool ────────────────────────────────────────────────
-- Built once at require time by scanning ServerStorage.FurnitureModels.
-- Supports any tier string — no hardcoded tier list.

local _furniturePool       = {}   -- [tier] = { key, ... }
local _furnitureByCategory = {}   -- [category][tier] = { key, ... }
local _furnitureDisplay    = {}   -- [key] = display name string

local function pickForCategory(category, jobTier, fallbackPool)
	local catPools = _furnitureByCategory[category]
	if catPools then
		if catPools[jobTier] and #catPools[jobTier] > 0 then
			return pickRandom(catPools[jobTier])
		end
		-- Fall back through all tiers (high → low) until we find furniture
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

-- ── Global tier roll ──────────────────────────────────────────────────────
-- Selects a job tier from GameConfig.JobTierRarity weights.
-- allowedTiers: set table [tier]=true from LocationManager.GetAvailableTiers().
-- Tiers not in allowedTiers are skipped so we never generate jobs with no building.

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

-- ── Furniture pool with tier fallback ────────────────────────────────────
-- For a high-tier job with no matching furniture, falls down to lower tiers.

local function getFurniturePool(tier)
	local reached = false
	for _, t in ipairs(TIER_ORDER) do
		if t == tier then reached = true end
		if reached and _furniturePool[t] and #_furniturePool[t] > 0 then
			return _furniturePool[t]
		end
	end
	for _, t in ipairs(TIER_ORDER) do
		if _furniturePool[t] and #_furniturePool[t] > 0 then
			return _furniturePool[t]
		end
	end
	return nil
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
			-- Multi-piece: one furniture + one minigame per piece
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
			-- Single-piece: pick furniture, then run a minigame chain
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

		local jobName
		if pieceCount > 1 then
			jobName = table.concat(displayNames, " & ")
		elseif #minigames == 1 then
			jobName = displayNames[1] .. " — " .. damageLabels[1]
		else
			jobName = displayNames[1]
		end

		local flavor  = pickRandom(FLAVOR_POOL)
		local details = flavor .. " (" .. table.concat(damageLabels, ", ") .. ")"

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
		})
	end

	return jobs
end

return RadiantJobGenerator
