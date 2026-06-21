--[[
	JobPool
	Manages the global job pool shared by all players, plus active per-player
	job tracking. Applies pay/follower/rep with perk effects, tier-scaled
	penalties on Fail/Abandon, and burns perk charges on Fail (compound failure
	cost). Also injects Hot Jobs into the pool and reports completions to the
	Daily Contract manager.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local TIER_TITLES = GameConfig.Talkogram.tierTitles

local RESULT_ORDER = { Fail = 0, Pass = 1, Good = 2, Perfect = 3 }
local function meetsResult(result, minResult)
	if not minResult then return true end
	return (RESULT_ORDER[result] or 0) >= (RESULT_ORDER[minResult] or 0)
end

-- ── Pool state ────────────────────────────────────────────────────────────

local _globalJobPool   = {}
local _activeJobs      = {}  -- [jobId] = { job, player, source = "board"|"offer" }
local _playerActiveJob = {}  -- [player] = jobId
local _nextJobId       = 1

local _locationManager     = nil
local _radiantJobGen       = nil
local _JobBoardRefresh     = nil
local _perkSystem          = nil
local _dailyContracts      = nil
local _directOfferGen      = nil

-- ── Pool management ───────────────────────────────────────────────────────

local function generateGlobalPool()
	local cfg         = GameConfig.JobBoard
	local playerCount = math.max(1, #Players:GetPlayers())
	local lo          = math.floor(playerCount * cfg.poolSizePerPlayer.min)
	local hi          = math.ceil(playerCount  * cfg.poolSizePerPlayer.max)
	local count       = math.clamp(math.random(lo, hi), cfg.poolSizeMin, cfg.poolSizeMax)
	local jobs        = _radiantJobGen.Generate(count, _locationManager.GetAvailableTiers())

	for _, job in ipairs(jobs) do
		job.id     = _nextJobId
		_nextJobId = _nextJobId + 1
	end

	_globalJobPool = jobs
	_JobBoardRefresh:FireAllClients()
	print(("[JobPool] Global pool refreshed: %d jobs"):format(#jobs))
end

local function cleanupPlayer(player)
	local jobId = _playerActiveJob[player]
	if jobId then
		_activeJobs[jobId]       = nil
		_playerActiveJob[player] = nil
	end
end

local function injectJob(job)
	job.id     = _nextJobId
	_nextJobId = _nextJobId + 1
	table.insert(_globalJobPool, job)
	_JobBoardRefresh:FireAllClients()
end

local function injectActiveJobForPlayer(player, job)
	if not job.id then job.id = _nextJobId; _nextJobId = _nextJobId + 1 end
	_activeJobs[job.id]      = { job = job, player = player, source = "offer" }
	_playerActiveJob[player] = job.id
end

local function clearActiveJobForPlayer(player)
	local jobId = _playerActiveJob[player]
	if jobId then
		_activeJobs[jobId] = nil
		_playerActiveJob[player] = nil
	end
end

-- ── Reward application ────────────────────────────────────────────────────

local function applyRewards(player, job, result)
	local pd = player:FindFirstChild("PlayerData"); if not pd then return 0, 0, 0 end
	local effects = _perkSystem and _perkSystem.GetActiveEffects(player) or {}
	local conditions = effects._conditions or {}

	local function effectActive(key)
		-- If this effect comes from a perk with a min-result condition, gate it.
		for perkId, cond in pairs(conditions) do
			-- (We assume each effect originates from a single perk, which is true
			-- for our small catalog. If a key collides we fail open.)
			local _ = perkId
			if cond.minResult and not meetsResult(result, cond.minResult) then
				-- Only block if THIS perk contributed the key. Cheap check: if the
				-- key matches a known conditional perk's effect.
				-- For our catalog, conditional perks are payMultiplier/followerMultiplier/
				-- repBonus — block those unconditionally if any condition fails.
				if key == "payMultiplier" or key == "followerMultiplier" or key == "repBonus" then
					return false
				end
			end
		end
		return true
	end

	-- Pay
	local payMult = 1.0
	if effects.payMultiplier and effectActive("payMultiplier") then
		payMult = payMult + effects.payMultiplier
	end
	local pay = math.floor(job.pay * payMult)
	local usdVal = pd:FindFirstChild("usd")
	if usdVal then usdVal.Value += pay end
	if _dailyContracts then _dailyContracts.ReportUsdEarned(player, pay) end

	-- Followers
	local followerMult = 1.0 + (GameConfig.Followers.minigameBonus[result] or 0)
	if effects.followerMultiplier and effectActive("followerMultiplier") then
		followerMult = followerMult + effects.followerMultiplier
	end
	local followerGain = math.floor(job.followers * followerMult)
	local follVal = pd:FindFirstChild("followers")
	if follVal then follVal.Value += followerGain end

	-- Reputation
	local repCfg = GameConfig.Reputation
	local repDelta = repCfg.gain[result] or 0
	if effects.repBonus and effectActive("repBonus") then
		repDelta = repDelta + effects.repBonus
	end
	local repVal = pd:FindFirstChild("reputation")
	if repVal then
		repVal.Value = math.clamp(repVal.Value + repDelta, repCfg.minValue, repCfg.maxValue)
	end

	return pay, followerGain, repDelta
end

-- ── Remote handlers ───────────────────────────────────────────────────────

local function init(remotes, locationManager, radiantJobGen, savePost,
	perkSystem, dailyContracts, directOfferGen)
	_locationManager  = locationManager
	_radiantJobGen    = radiantJobGen
	_perkSystem       = perkSystem
	_dailyContracts   = dailyContracts
	_directOfferGen   = directOfferGen
	_JobBoardRefresh  = remotes:WaitForChild("JobBoardRefresh")

	local RequestJobs     = remotes:WaitForChild("RequestJobs")
	local AcceptJob       = remotes:WaitForChild("AcceptJob")
	local SubmitJobResult = remotes:WaitForChild("SubmitJobResult")
	local AbandonJob      = remotes:WaitForChild("AbandonJob")
	local AdminSpawnJob   = remotes:WaitForChild("AdminSpawnJob")
	local JobRewardNotify = remotes:WaitForChild("JobRewardNotify")

	RequestJobs.OnServerInvoke = function(_player)
		return _globalJobPool
	end

	AcceptJob.OnServerEvent:Connect(function(player, jobId)
		if _playerActiveJob[player] then return end

		local jobIndex, job = nil, nil
		for i, j in ipairs(_globalJobPool) do
			if j.id == jobId then jobIndex, job = i, j; break end
		end

		if not job then
			_JobBoardRefresh:FireClient(player)
			return
		end

		table.remove(_globalJobPool, jobIndex)
		_activeJobs[job.id]      = { job = job, player = player, source = "board" }
		_playerActiveJob[player] = job.id

		local ok = locationManager.Assign(player, job)
		if not ok then
			table.insert(_globalJobPool, job)
			_activeJobs[job.id]      = nil
			_playerActiveJob[player] = nil
			return
		end

		_JobBoardRefresh:FireAllClients()
	end)

	SubmitJobResult.OnServerEvent:Connect(function(player, jobId, result)
		local entry = _activeJobs[jobId]
		if not entry or entry.player ~= player then
			locationManager.Release(player)
			return
		end

		local job = entry.job
		_activeJobs[jobId]       = nil
		_playerActiveJob[player] = nil

		-- Capture active perk IDs before BurnCharges (burn may auto-unequip them)
		local activePerkIds = {}
		if _perkSystem then
			local loadout = _perkSystem.GetLoadout(player)
			for i = 1, 5 do
				if (loadout[i] or "") ~= "" then table.insert(activePerkIds, loadout[i]) end
			end
		end

		-- Always burn one charge per equipped perk (per-attempt cost)
		if _perkSystem then _perkSystem.BurnCharges(player, 1) end

		if result == "Fail" then
			-- Compound failure: extra charge burn + tier-scaled rep penalty
			if _perkSystem then _perkSystem.BurnCharges(player, 1) end
			local pd = player:FindFirstChild("PlayerData")
			local penalty = GameConfig.Reputation.failByTier[job.tier] or -0.05
			if pd then
				local repCfg = GameConfig.Reputation
				local effects = _perkSystem and _perkSystem.GetActiveEffects(player) or {}
				if effects.failPenaltyMultiplier then
					penalty = penalty * effects.failPenaltyMultiplier
				end
				local repVal = pd:FindFirstChild("reputation")
				if repVal then
					repVal.Value = math.clamp(repVal.Value + penalty, repCfg.minValue, repCfg.maxValue)
				end
			end
			local perkChargesAfter = {}
			if _perkSystem then
				local allCharges = _perkSystem.GetCharges(player)
				for _, perkId in ipairs(activePerkIds) do
					perkChargesAfter[perkId] = allCharges[perkId] or 0
				end
			end
			JobRewardNotify:FireClient(player, {
				result           = "Fail",
				jobName          = job.name or "?",
				pay              = 0,
				payBonus         = 0,
				followers        = 0,
				followerBonus    = 0,
				repDelta         = penalty,
				perkIds          = activePerkIds,
				perkChargesAfter = perkChargesAfter,
			})
			print(("[JobPool] %s | FAIL | rep penalty applied"):format(player.Name))
			locationManager.Release(player)
			return
		end

		-- Apply rewards and build debrief data for all non-Fail results.
		-- Notify always fires so the client debrief always appears.
		local pay, followerGain, actualRepDelta = 0, 0, 0
		local payBonus, followerBonus = 0, 0

		if TIER_TITLES[result] then
			pay, followerGain, actualRepDelta = applyRewards(player, job, result)

			payBonus            = pay - job.pay
			local baseFollowers = math.floor(job.followers *
				(1 + (GameConfig.Followers.minigameBonus[result] or 0)))
			followerBonus       = followerGain - baseFollowers

			local timestamp = os.time()
			local postId    = tostring(player.UserId) .. "_" .. tostring(timestamp)
			local post = {
				id        = postId,
				author    = player.Name,
				authorId  = player.UserId,
				jobId     = job.id,
				jobName   = job.name,
				imageId   = job.imageId,
				title     = string.format(TIER_TITLES[result], job.name),
				result    = result,
				timestamp = timestamp,
				likes     = 0,
				comments  = {},
			}
			savePost(post)

			if _dailyContracts then
				_dailyContracts.ReportJobCompleted(player, job, result)
			end

			print(("[JobPool] %s | Pay +$%d | Followers +%d | %s"):format(
				player.Name, pay, followerGain, result))
		end

		local perkChargesAfter = {}
		if _perkSystem then
			local allCharges = _perkSystem.GetCharges(player)
			for _, perkId in ipairs(activePerkIds) do
				perkChargesAfter[perkId] = allCharges[perkId] or 0
			end
		end
		JobRewardNotify:FireClient(player, {
			result           = result,
			jobName          = job.name or "?",
			pay              = pay,
			payBonus         = payBonus,
			followers        = followerGain,
			followerBonus    = followerBonus,
			repDelta         = actualRepDelta,
			perkIds          = activePerkIds,
			perkChargesAfter = perkChargesAfter,
		})

		locationManager.Release(player)
	end)

	AbandonJob.OnServerEvent:Connect(function(player)
		local jobId = _playerActiveJob[player]
		local job
		if jobId then
			job = _activeJobs[jobId] and _activeJobs[jobId].job
			_activeJobs[jobId]       = nil
			_playerActiveJob[player] = nil
		end

		-- Capture active perk IDs before BurnCharges
		local activePerkIds = {}
		if _perkSystem then
			local loadout = _perkSystem.GetLoadout(player)
			for i = 1, 5 do
				if (loadout[i] or "") ~= "" then table.insert(activePerkIds, loadout[i]) end
			end
		end

		if _perkSystem then _perkSystem.BurnCharges(player, 1) end

		local penalty = job and (GameConfig.Reputation.abandonByTier[job.tier] or -0.08) or -0.08
		local pd = player:FindFirstChild("PlayerData")
		if pd then
			local repCfg = GameConfig.Reputation
			local effects = _perkSystem and _perkSystem.GetActiveEffects(player) or {}
			if effects.abandonPenaltyMultiplier then
				penalty = penalty * effects.abandonPenaltyMultiplier
			end
			local repVal = pd:FindFirstChild("reputation")
			if repVal then
				repVal.Value = math.clamp(repVal.Value + penalty, repCfg.minValue, repCfg.maxValue)
			end
		end

		local perkChargesAfter = {}
		if _perkSystem then
			local allCharges = _perkSystem.GetCharges(player)
			for _, perkId in ipairs(activePerkIds) do
				perkChargesAfter[perkId] = allCharges[perkId] or 0
			end
		end
		JobRewardNotify:FireClient(player, {
			result           = "Abandon",
			jobName          = job and (job.name or "?") or "?",
			pay              = 0,
			payBonus         = 0,
			followers        = 0,
			followerBonus    = 0,
			repDelta         = penalty,
			perkIds          = activePerkIds,
			perkChargesAfter = perkChargesAfter,
		})

		locationManager.Release(player)
		print("[JobPool] Job abandoned by", player.Name)
	end)

	AdminSpawnJob.OnServerEvent:Connect(function(player, tier, locationOverride)
		if type(tier) ~= "string" or not GameConfig.JobTierRarity[tier] then return end
		if locationOverride ~= nil and type(locationOverride) ~= "string" then return end

		local jobs = radiantJobGen.Generate(1, { [tier] = true })
		if #jobs == 0 then return end
		local job = jobs[1]
		job.id               = _nextJobId
		_nextJobId           = _nextJobId + 1
		job.locationOverride = locationOverride

		table.insert(_globalJobPool, job)
		_JobBoardRefresh:FireAllClients()
		print(("[AdminPanel] %s spawned %s job (location: %s)"):format(
			player.Name, tier, locationOverride or "auto"))
	end)
end

return {
	Init                       = init,
	GeneratePool               = generateGlobalPool,
	CleanupPlayer              = cleanupPlayer,
	InjectJob                  = injectJob,
	InjectActiveJobForPlayer   = injectActiveJobForPlayer,
	ClearActiveJobForPlayer    = clearActiveJobForPlayer,
}
