--[[
	JobPool
	Manages the global job pool shared by all players.
	Handles job acceptance, submission, and abandonment.
	Also wires up the AdminSpawnJob remote for dev/QA use.
	SavePost (from TalkogramHandler) is injected via Init so completed
	jobs automatically create a Talkogram post.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local TIER_TITLES = GameConfig.Talkogram.tierTitles

-- ── Pool state ────────────────────────────────────────────────────────────

local _globalJobPool   = {}  -- jobs available on the board
local _activeJobs      = {}  -- [jobId] = { job=job, player=player }
local _playerActiveJob = {}  -- [player] = jobId
local _nextJobId       = 1

-- Set by Init
local _locationManager = nil
local _radiantJobGen   = nil
local _JobBoardRefresh = nil

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

-- ── Remote handlers ───────────────────────────────────────────────────────

local function init(remotes, locationManager, radiantJobGen, savePost)
	_locationManager = locationManager
	_radiantJobGen   = radiantJobGen
	_JobBoardRefresh = remotes:WaitForChild("JobBoardRefresh")

	local RequestJobs     = remotes:WaitForChild("RequestJobs")
	local AcceptJob       = remotes:WaitForChild("AcceptJob")
	local SubmitJobResult = remotes:WaitForChild("SubmitJobResult")
	local AbandonJob      = remotes:WaitForChild("AbandonJob")
	local AdminSpawnJob   = remotes:WaitForChild("AdminSpawnJob")

	-- Returns the current global pool (same list for every player).
	RequestJobs.OnServerInvoke = function(_player)
		return _globalJobPool
	end

	AcceptJob.OnServerEvent:Connect(function(player, jobId)
		if _playerActiveJob[player] then
			warn("[JobPool] AcceptJob: player", player.Name, "already has an active job")
			return
		end

		local jobIndex = nil
		local job      = nil
		for i, j in ipairs(_globalJobPool) do
			if j.id == jobId then
				jobIndex = i
				job      = j
				break
			end
		end

		if not job then
			warn("[JobPool] AcceptJob: jobId", jobId, "not in pool for player", player.Name)
			_JobBoardRefresh:FireClient(player)
			return
		end

		-- Remove from pool and track as active
		table.remove(_globalJobPool, jobIndex)
		_activeJobs[job.id]      = { job = job, player = player }
		_playerActiveJob[player] = job.id

		local ok = locationManager.Assign(player, job)
		if not ok then
			-- Assignment failed (e.g. no slots free) — return job to pool
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
			warn("[JobPool] SubmitJobResult: invalid jobId", jobId, "for player", player.Name)
			locationManager.Release(player)
			return
		end

		local job = entry.job
		_activeJobs[jobId]       = nil
		_playerActiveJob[player] = nil

		local followerGain = 0
		if TIER_TITLES[result] then
			local pd = player:FindFirstChild("PlayerData")
			if pd then
				local usdVal = pd:FindFirstChild("usd")
				if usdVal then
					usdVal.Value = usdVal.Value + job.pay
				end

				local resultBonus = GameConfig.Followers.minigameBonus[result] or 0
				followerGain      = math.floor(job.followers * (1 + resultBonus))
				local follVal     = pd:FindFirstChild("followers")
				if follVal then
					follVal.Value = follVal.Value + followerGain
				end

				local repCfg = GameConfig.Reputation
				local repVal = pd:FindFirstChild("reputation")
				if repVal then
					local delta = repCfg.gain[result] or 0
					repVal.Value = math.clamp(repVal.Value + delta, repCfg.minValue, repCfg.maxValue)
				end
			end

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
			print(("[JobPool] %s | Pay +$%d | Followers +%d | %s"):format(
				player.Name, job.pay, followerGain, result
			))
		end

		locationManager.Release(player)
	end)

	AbandonJob.OnServerEvent:Connect(function(player)
		local jobId = _playerActiveJob[player]
		if jobId then
			_activeJobs[jobId]       = nil
			_playerActiveJob[player] = nil
		end

		local pd = player:FindFirstChild("PlayerData")
		if pd then
			local repVal = pd:FindFirstChild("reputation")
			if repVal then
				local repCfg = GameConfig.Reputation
				repVal.Value = math.clamp(repVal.Value + repCfg.gain.Abandon, repCfg.minValue, repCfg.maxValue)
			end
		end

		locationManager.Release(player)
		print("[JobPool] Job abandoned by", player.Name)
	end)

	AdminSpawnJob.OnServerEvent:Connect(function(player, tier, locationOverride)
		-- Admin check disabled for testing — re-enable by uncommenting:
		-- local ADMINS = { "beanzonyon", "Matthewasiando" }
		-- local ok = false
		-- for _, name in ipairs(ADMINS) do
		-- 	if player.Name == name then ok = true; break end
		-- end
		-- if not ok then return end

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
	Init          = init,
	GeneratePool  = generateGlobalPool,
	CleanupPlayer = cleanupPlayer,
}
