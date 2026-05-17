--[[
	LaptopData
	Server-side handler for the laptop browser.
	Creates LaptopRemotes, manages the Talkogram DataStore feed,
	and handles job acceptance + result submission (auto-post creation).

	Job board: one global pool shared by all players.
	Generated on server start; refreshed every replenishMin–replenishMax seconds.
	When a player accepts a job it is removed from the pool immediately and
	all clients are notified to refresh their board.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local GameConfig  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local TIER_TITLES = GameConfig.Talkogram.tierTitles

local ADMINS = {
	"beanzonyon",
	"Matthewasiando",
	-- add more names here
}

local RadiantJobGenerator = require(script.Parent:WaitForChild("RadiantJobGenerator", 10)
	or error("[LaptopData] RadiantJobGenerator not found in ServerScriptService — did Rojo sync?"))

-- ── Global job pool ───────────────────────────────────────────────────────

local _globalJobPool   = {}  -- jobs available on the board
local _activeJobs      = {}  -- [jobId] = { job=job, player=player }  (in-progress)
local _playerActiveJob = {}  -- [player] = jobId
local _nextJobId       = 1

-- ── Remote setup ──────────────────────────────────────────────────────────

local remotesFolder = Instance.new("Folder")
remotesFolder.Name   = "LaptopRemotes"
remotesFolder.Parent = ReplicatedStorage

local function makeRemote(name)
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = remotesFolder
	return re
end

local function makeRemoteFunction(name)
	local rf = Instance.new("RemoteFunction")
	rf.Name   = name
	rf.Parent = remotesFolder
	return rf
end

local RequestJobs      = makeRemoteFunction("RequestJobs")
local AcceptJob        = makeRemote("AcceptJob")
local RequestFeed      = makeRemoteFunction("RequestFeed")
local RequestPost      = makeRemoteFunction("RequestPost")
local PostComment      = makeRemote("PostComment")
local LikePost         = makeRemote("LikePost")
local RequestInventory = makeRemoteFunction("RequestInventory")
local PurchaseTool     = makeRemote("PurchaseTool")
local SubmitJobResult  = makeRemote("SubmitJobResult")

local AbandonJob      = makeRemote("AbandonJob")
local JobBoardRefresh = makeRemote("JobBoardRefresh")
local AdminSpawnJob        = makeRemote("AdminSpawnJob")
local AdminRequestLocations = makeRemoteFunction("AdminRequestLocations")

-- Teleport events (fired by LocationManager; listed here so the folder is complete)
makeRemote("TeleportToLocation")
makeRemote("TeleportToHub")
makeRemote("LocationFull")
makeRemote("FurniturePieceRepaired")
makeRemote("StartMinigame")

-- ── LocationManager ───────────────────────────────────────────────────────
-- Required after remotes are created so LocationManager can WaitForChild on them.
local LocationManager = require(script.Parent:WaitForChild("LocationManager", 10)
	or error("[LaptopData] LocationManager ModuleScript not found in ServerScriptService — did Rojo sync?"))

-- ── DataStore ─────────────────────────────────────────────────────────────

local FeedStore = DataStoreService:GetDataStore("TalkogramFeed")

local _serverPosts   = {}
local _extraComments = {}

-- ── Fallback Talkogram feed ───────────────────────────────────────────────

local STUB_FEED = {
	{
		id       = 1,
		title    = "My First Sofa!",
		author   = "CraftyPlayer1",
		imageId  = 0,
		likes    = 3,
		comments = {
			{ author = "ThreadQueen", text = "Looks so clean!" },
			{ author = "FabricFan",   text = "Love the colour choice" },
		},
	},
	{
		id       = 2,
		title    = "Ottoman Empire",
		author   = "StitchWitch99",
		imageId  = 0,
		likes    = 12,
		comments = {
			{ author = "VelvetVibes", text = "Incredible craftsmanship!!" },
		},
	},
	{
		id       = 3,
		title    = "Dining Chair Glow-Up",
		author   = "TackMaster",
		imageId  = 0,
		likes    = 7,
		comments = {},
	},
	{
		id       = 4,
		title    = "Weekend Project",
		author   = "FoamLord",
		imageId  = 0,
		likes    = 1,
		comments = {
			{ author = "CraftyPlayer1", text = "Nice work!" },
		},
	},
}

-- ── Pool management ───────────────────────────────────────────────────────

local function generateGlobalPool()
	local cfg         = GameConfig.JobBoard
	local playerCount = math.max(1, #Players:GetPlayers())
	local lo          = math.floor(playerCount * cfg.poolSizePerPlayer.min)
	local hi          = math.ceil(playerCount  * cfg.poolSizePerPlayer.max)
	local count       = math.clamp(math.random(lo, hi), cfg.poolSizeMin, cfg.poolSizeMax)
	local jobs        = RadiantJobGenerator.Generate(count, LocationManager.GetAvailableTiers())

	-- Assign server-unique IDs to each job in the batch
	for _, job in ipairs(jobs) do
		job.id      = _nextJobId
		_nextJobId = _nextJobId + 1
	end

	_globalJobPool = jobs
	JobBoardRefresh:FireAllClients()
	print(("[LaptopData] Global pool refreshed: %d jobs"):format(#jobs))
end

local function findJobById(jobId)
	-- Active (in-progress) jobs take priority
	local entry = _activeJobs[jobId]
	if entry then return entry.job end
	-- Search available pool
	for _, job in ipairs(_globalJobPool) do
		if job.id == jobId then return job end
	end
	return nil
end

-- ── DataStore helpers ─────────────────────────────────────────────────────

local function savePost(post)
	table.insert(_serverPosts, 1, post)

	local ok, err = pcall(function()
		FeedStore:UpdateAsync("GlobalFeed", function(current)
			local posts = current or {}
			table.insert(posts, 1, post)
			while #posts > 100 do
				table.remove(posts)
			end
			return posts
		end)
	end)
	if not ok then
		warn("[LaptopData] savePost failed:", err)
	end
end

local function loadGlobalFeed()
	local ok, result = pcall(function()
		return FeedStore:GetAsync("GlobalFeed")
	end)
	if ok and result and #result > 0 then
		return result
	end
	return STUB_FEED
end

-- ── Remote handlers ───────────────────────────────────────────────────────

-- Returns the current global pool (all available jobs, same for every player).
RequestJobs.OnServerInvoke = function(_player)
	return _globalJobPool
end

RequestFeed.OnServerInvoke = function(_player, mode)
	if mode == "server" then
		return _serverPosts
	else
		return loadGlobalFeed()
	end
end

RequestPost.OnServerInvoke = function(_player, postId)
	if type(postId) == "number" then
		for _, post in ipairs(STUB_FEED) do
			if post.id == postId then
				local result = {
					id       = post.id,
					title    = post.title,
					author   = post.author,
					imageId  = post.imageId or 0,
					likes    = post.likes,
					comments = {},
				}
				for _, c in ipairs(post.comments or {}) do
					table.insert(result.comments, c)
				end
				local extras = _extraComments[tostring(postId)]
				if extras then
					for _, c in ipairs(extras) do
						table.insert(result.comments, c)
					end
				end
				return result
			end
		end
	end

	if type(postId) == "string" then
		for _, post in ipairs(_serverPosts) do
			if post.id == postId then
				local result = {
					id       = post.id,
					title    = post.title,
					author   = post.author,
					imageId  = post.imageId or 0,
					likes    = post.likes or 0,
					comments = {},
				}
				local extras = _extraComments[postId]
				if extras then
					for _, c in ipairs(extras) do
						table.insert(result.comments, c)
					end
				end
				return result
			end
		end

		local ok, globalFeed = pcall(function()
			return FeedStore:GetAsync("GlobalFeed")
		end)
		if ok and globalFeed then
			for _, post in ipairs(globalFeed) do
				if post.id == postId then
					local result = {
						id       = post.id,
						title    = post.title,
						author   = post.author,
						imageId  = post.imageId or 0,
						likes    = post.likes or 0,
						comments = {},
					}
					local extras = _extraComments[postId]
					if extras then
						for _, c in ipairs(extras) do
							table.insert(result.comments, c)
						end
					end
					return result
				end
			end
		end
	end

	return nil
end

AcceptJob.OnServerEvent:Connect(function(player, jobId)
	if _playerActiveJob[player] then
		warn("[LaptopData] AcceptJob: player", player.Name, "already has an active job")
		return
	end

	-- Find job in the available pool
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
		warn("[LaptopData] AcceptJob: jobId", jobId, "not in pool for player", player.Name)
		JobBoardRefresh:FireClient(player)
		return
	end

	-- Remove from pool and move to active tracking
	table.remove(_globalJobPool, jobIndex)
	_activeJobs[job.id]      = { job = job, player = player }
	_playerActiveJob[player] = job.id

	local ok = LocationManager.Assign(player, job)
	if not ok then
		-- Assignment failed (e.g. no slots free) — put job back in pool
		table.insert(_globalJobPool, job)
		_activeJobs[job.id]      = nil
		_playerActiveJob[player] = nil
		return
	end

	-- Notify all clients so the accepted job disappears from their board
	JobBoardRefresh:FireAllClients()
end)

SubmitJobResult.OnServerEvent:Connect(function(player, jobId, result)
	local entry = _activeJobs[jobId]
	if not entry or entry.player ~= player then
		warn("[LaptopData] SubmitJobResult: invalid jobId", jobId, "for player", player.Name)
		LocationManager.Release(player)
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
		print(("[LaptopData] %s | Pay +$%d | Followers +%d | %s"):format(
			player.Name, job.pay, followerGain, result
		))
	end

	LocationManager.Release(player)
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

	LocationManager.Release(player)
	print("[LaptopData] Job abandoned by", player.Name)
end)

PostComment.OnServerEvent:Connect(function(player, postId, text)
	if type(text) ~= "string" then return end
	text = text:sub(1, GameConfig.Talkogram.commentMaxLength)
	if text == "" then return end
	local key = tostring(postId)
	if not _extraComments[key] then
		_extraComments[key] = {}
	end
	table.insert(_extraComments[key], { author = player.Name, text = text })
end)

LikePost.OnServerEvent:Connect(function(_player, _postId)
	-- Stub: full like tracking wired in later
end)

RequestInventory.OnServerInvoke = function(_player)
	return {}
end

PurchaseTool.OnServerEvent:Connect(function(player, toolName)
	print("[LaptopData] PurchaseTool from", player.Name, "tool =", toolName)
end)

AdminRequestLocations.OnServerInvoke = function(_player)
	return LocationManager.GetLocationNames()
end

AdminSpawnJob.OnServerEvent:Connect(function(player, tier, locationOverride)
	-- Admin check disabled for testing — re-enable by uncommenting:
	-- local ok = false
	-- for _, name in ipairs(ADMINS) do
	-- 	if player.Name == name then ok = true; break end
	-- end
	-- if not ok then return end

	if type(tier) ~= "string" or not GameConfig.JobTierRarity[tier] then return end
	if locationOverride ~= nil and type(locationOverride) ~= "string" then return end

	local jobs = RadiantJobGenerator.Generate(1, { [tier] = true })
	if #jobs == 0 then return end

	local job = jobs[1]
	job.id               = _nextJobId
	_nextJobId           = _nextJobId + 1
	job.locationOverride = locationOverride

	table.insert(_globalJobPool, job)
	JobBoardRefresh:FireAllClients()
	print(("[AdminPanel] %s spawned %s job (location: %s)"):format(
		player.Name, tier, locationOverride or "auto"))
end)

Players.PlayerRemoving:Connect(function(player)
	local jobId = _playerActiveJob[player]
	if jobId then
		_activeJobs[jobId]       = nil
		_playerActiveJob[player] = nil
	end
end)

-- ── Initial pool + periodic refresh ──────────────────────────────────────

generateGlobalPool()

task.spawn(function()
	while true do
		local cfg = GameConfig.JobBoard
		task.wait(math.random(cfg.replenishMin, cfg.replenishMax))
		generateGlobalPool()
	end
end)
