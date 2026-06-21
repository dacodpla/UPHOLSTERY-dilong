--[[
	DailyContractManager
	3 rotating challenges per UTC day. All server players share the same daily 3
	(pool seeded by date so it is deterministic per day).
	Progress is stored on player.PlayerData.dailyContracts.

	Reward kinds:
	  usd        -> PlayerData.usd += amount
	  perkCharge -> PerkSystem.GrantCharge(player, perkId, qty)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService  = game:GetService("DataStoreService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PerkSystem = require(ServerScriptService:WaitForChild("PerkSystem"))

local DailyStore = DataStoreService:GetDataStore("DailyContracts_v1")

local TIER_ORDER = { Starter=1, Mid=2, Premium=3, Prestige=4, Exclusive=5, Elite=6, Special=7 }

local DailyContractManager = {}
local _playerState = {}  -- [player] = { date, progress, claimed, sessionUsdEarned }

local function todayKey() return os.date("!%Y-%m-%d") end

local function dateSeed(dateStr)
	local n = 0
	for c in dateStr:gmatch(".") do n = n * 31 + c:byte() end
	return n
end

local function pickDailyContracts()
	local pool = GameConfig.DailyContracts.pool
	local count = GameConfig.DailyContracts.dailyCount
	local rng = Random.new(dateSeed(todayKey()))
	local copy = {}
	for _, c in ipairs(pool) do table.insert(copy, c) end
	-- Fisher-Yates with seeded rng
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	local out = {}
	for i = 1, math.min(count, #copy) do table.insert(out, copy[i]) end
	return out
end

local function loadFor(player)
	local date = todayKey()
	local state = { date = date, progress = {}, claimed = {}, sessionUsdEarned = 0 }
	local ok, saved = pcall(function()
		return DailyStore:GetAsync("Player_" .. player.UserId)
	end)
	if ok and saved and saved.date == date then
		state.progress = saved.progress or {}
		state.claimed  = saved.claimed  or {}
	end
	_playerState[player] = state
end

local function saveFor(player)
	local state = _playerState[player]; if not state then return end
	pcall(function()
		DailyStore:SetAsync("Player_" .. player.UserId, {
			date = state.date, progress = state.progress, claimed = state.claimed,
		})
	end)
end

function DailyContractManager.GetTodaysContracts()
	return pickDailyContracts()
end

function DailyContractManager.GetPlayerStatus(player)
	local state = _playerState[player]; if not state then return {} end
	local contracts = pickDailyContracts()
	local out = {}
	for _, c in ipairs(contracts) do
		table.insert(out, {
			id          = c.id,
			description = c.description,
			goal        = c.goal,
			reward      = c.reward,
			progress    = state.progress[c.id] or 0,
			claimed     = state.claimed[c.id]  or false,
		})
	end
	return out
end

function DailyContractManager.ReportJobCompleted(player, job, result)
	local state = _playerState[player]; if not state then return end
	if state.date ~= todayKey() then
		-- Day rolled over
		state.date = todayKey()
		state.progress = {}
		state.claimed = {}
	end

	local contracts = pickDailyContracts()
	for _, c in ipairs(contracts) do
		if state.claimed[c.id] then continue end
		local goal = c.goal
		local progress = state.progress[c.id] or 0

		if goal.kind == "jobs" then
			local minTier = goal.minTier
			local meets = true
			if minTier and (TIER_ORDER[job.tier] or 0) < (TIER_ORDER[minTier] or 0) then
				meets = false
			end
			if meets then progress += 1 end
		elseif goal.kind == "perfects" then
			if result == "Perfect" then
				if not goal.fragileOnly or job.fragile then
					progress += 1
				end
			end
		elseif goal.kind == "earnUsd" then
			progress = state.sessionUsdEarned
		elseif goal.kind == "minigameChain" then
			if #(job.minigames or {}) >= (goal.minLength or 1) then
				progress += 1
			end
		end

		state.progress[c.id] = progress
	end
end

function DailyContractManager.ReportUsdEarned(player, amount)
	local state = _playerState[player]; if not state then return end
	state.sessionUsdEarned = (state.sessionUsdEarned or 0) + amount
	-- Re-evaluate any earnUsd contracts
	for _, c in ipairs(pickDailyContracts()) do
		if c.goal.kind == "earnUsd" then
			state.progress[c.id] = state.sessionUsdEarned
		end
	end
end

function DailyContractManager.ClaimReward(player, contractId)
	local state = _playerState[player]; if not state then return false end
	if state.claimed[contractId] then return false end

	local contract
	for _, c in ipairs(pickDailyContracts()) do
		if c.id == contractId then contract = c; break end
	end
	if not contract then return false end

	local progress = state.progress[contractId] or 0
	local goalCount = contract.goal.count or contract.goal.amount or 1
	if progress < goalCount then return false end

	local reward = contract.reward
	if reward.kind == "usd" then
		local pd = player:FindFirstChild("PlayerData")
		if pd and pd:FindFirstChild("usd") then pd.usd.Value += reward.amount end
	elseif reward.kind == "perkCharge" then
		PerkSystem.GrantCharge(player, reward.perkId, reward.qty or 1)
	end

	state.claimed[contractId] = true
	saveFor(player)
	return true
end

function DailyContractManager.Init()
	Players.PlayerAdded:Connect(loadFor)
	for _, p in ipairs(Players:GetPlayers()) do loadFor(p) end
	Players.PlayerRemoving:Connect(function(p)
		saveFor(p)
		_playerState[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(Players:GetPlayers()) do saveFor(p) end
		end
	end)
end

return DailyContractManager
