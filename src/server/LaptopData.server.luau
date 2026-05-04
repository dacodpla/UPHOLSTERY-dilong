--[[
	LaptopData
	Server-side handler for the laptop browser.
	Creates LaptopRemotes, manages the Talkogram DataStore feed,
	and handles job acceptance + result submission (auto-post creation).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local GameConfig  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local TIER_TITLES = GameConfig.FeedStitch.tierTitles

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

-- ── DataStore ─────────────────────────────────────────────────────────────

local FeedStore = DataStoreService:GetDataStore("TalkogramFeed")

-- Session-local posts for the "Server" filter; lost on server shutdown
local _serverPosts = {}

-- Session-local comment store; lost on server restart
local _extraComments = {}

-- ── Job data ──────────────────────────────────────────────────────────────

local STUB_JOBS = {
	{
		id        = 1,
		name      = "Dining Chair Refresh",
		details   = "Replace worn seat padding and tacking",
		pay       = 120,
		followers = 8,
		prestige  = false,
		imageId   = 0,   -- replace with real Roblox asset ID once uploaded
		minigames = { "TackRemoval" },
	},
	{
		id        = 2,
		name      = "Velvet Loveseat",
		details   = "Full re-upholster with client fabric",
		pay       = 340,
		followers = 25,
		prestige  = false,
		imageId   = 0,
		minigames = { "SeamStitching" },
	},
	{
		id        = 3,
		name      = "Ottoman Suite",
		details   = "Prestige: 3-piece foam & stitch chain",
		pay       = 800,
		followers = 60,
		prestige  = true,
		imageId   = 0,
		minigames = { "TackRemoval", "FoamPadding", "StapleGunning" },
	},
	{
		id        = 4,
		name      = "Bar Stool Set ×4",
		details   = "Matching staple-gun finish required",
		pay       = 210,
		followers = 14,
		prestige  = false,
		imageId   = 0,
		minigames = { "StapleGunning" },
	},
	{
		id        = 5,
		name      = "Antique Armchair",
		details   = "Delicate fabric — Fragile modifier",
		pay       = 560,
		followers = 38,
		prestige  = false,
		imageId   = 0,
		minigames = { "FoamPadding" },
	},
}

-- Fallback feed shown when DataStore is empty (e.g. first-ever server)
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
			{ author = "VelvetVibes", text = "Prestige work!!" },
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

-- ── Helpers ───────────────────────────────────────────────────────────────

local function findJobById(jobId)
	for _, job in ipairs(STUB_JOBS) do
		if job.id == jobId then return job end
	end
	return nil
end

-- Persists a post to DataStore (GlobalFeed key) and prepends it to the
-- server-local list. Caps the global feed at 100 entries.
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

-- Returns the global DataStore feed, falling back to stub data if empty.
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

RequestJobs.OnServerInvoke = function(_player)
	return STUB_JOBS
end

-- mode = "global" → DataStore feed (fallback: stubs)
-- mode = "server" → session-only _serverPosts
RequestFeed.OnServerInvoke = function(_player, mode)
	if mode == "server" then
		return _serverPosts
	else
		return loadGlobalFeed()
	end
end

RequestPost.OnServerInvoke = function(_player, postId)
	-- Stub feed (numeric IDs 1–4)
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

	-- Session posts and global DataStore posts (string IDs)
	if type(postId) == "string" then
		-- Check in-memory server posts first (no DataStore call needed)
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

		-- Fall back to scanning the global DataStore feed
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
	print("[LaptopData] AcceptJob from", player.Name, "jobId =", jobId)
end)

-- Client fires this after MinigameRunner completes; triggers auto-post creation.
SubmitJobResult.OnServerEvent:Connect(function(player, jobId, result)
	if not TIER_TITLES[result] then return end

	local job = findJobById(jobId)
	if not job then return end

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
	print("[LaptopData] Auto-post by", player.Name, "—", post.title)
end)

PostComment.OnServerEvent:Connect(function(player, postId, text)
	if type(text) ~= "string" then return end
	text = text:sub(1, GameConfig.FeedStitch.commentMaxLength)
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
