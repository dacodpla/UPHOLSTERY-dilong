--[[
	TalkogramHandler
	Manages the Talkogram social feed: DataStore persistence, stub data,
	and remote handlers for RequestFeed, RequestPost, PostComment, LikePost.
	SavePost is exposed so JobPool can create posts on job completion.
]]

local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

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
		warn("[TalkogramHandler] savePost failed:", err)
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

local function init(remotes)
	local RequestFeed = remotes:WaitForChild("RequestFeed")
	local RequestPost = remotes:WaitForChild("RequestPost")
	local PostComment = remotes:WaitForChild("PostComment")
	local LikePost    = remotes:WaitForChild("LikePost")

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
end

return {
	Init     = init,
	SavePost = savePost,
}
