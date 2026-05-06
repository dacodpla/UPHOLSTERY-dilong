--[[
	LaptopBrowser
	Handles all navigation, data population, and button wiring for LaptopGui.

	GUI hierarchy (website pages use the Browsah_Tab template):
	  [PageName] (Frame) → Browsah_Tab → Miscellaneous (CloseButton, BackButton)
	                                    → [PageName] inner content frame

	LoadingScreen and OSScreen have no Browsah_Tab.
	BrowsahHome's Browsah_Tab holds bookmarks directly (not in Miscellaneous).
]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local LaptopGui = PlayerGui:WaitForChild("LaptopGui")

-- ── Remote references ─────────────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("LaptopRemotes", 10)

local function getRemote(name)
	return Remotes and Remotes:WaitForChild(name, 5)
end

-- ── Page list ─────────────────────────────────────────────────────────────
local PAGES = {
	"LoadingScreen",
	"OSScreen",
	"BrowsahHome",
	"TalkogramFeed",
	"TalkogramPost",
	"MoneyMakerPage",
	"ShopPage",
}

local function showPage(name)
	for _, pageName in ipairs(PAGES) do
		local page = LaptopGui:FindFirstChild(pageName)
		if page then
			page.Visible = (pageName == name)
		end
	end
end

-- ── Boot sequence ─────────────────────────────────────────────────────────
local BOOT_DURATION = 2.2

local QUOTES = {
	"every cushion tells a story",
	"stitch by stitch, greatness is sewn",
	"the foam is always greener on the other side",
	"a tack a day keeps the sagging away",
	"measure twice, staple once",
	"fame is just followers. craft is forever",
	"start the grind",
	"who gonna carry the logs bro",
	"the hustle never sleeps, and neither do the deadlines",
	"a perfect staple is a perfect life",
	"you vs the sofa she told you not to worry about",
	"no days off when the fabric calls",
	"prestige jobs don't do themselves",
}

local function playBootSequence()
	showPage("LoadingScreen")

	local loadScreen  = LaptopGui:FindFirstChild("LoadingScreen")
	local progressBar = loadScreen and loadScreen:FindFirstChild("ProgressBar")
	local fill        = progressBar and progressBar:FindFirstChild("Fill")

	if fill then
		fill.Size = UDim2.fromScale(0, 1)
		TweenService:Create(
			fill,
			TweenInfo.new(BOOT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(1, 1) }
		):Play()
	end

	task.wait(BOOT_DURATION)
	showPage("OSScreen")

	local osScreen = LaptopGui:FindFirstChild("OSScreen")
	if osScreen then
		local q1idx = math.random(#QUOTES)
		local q2idx = q1idx % #QUOTES + 1
		local label1 = osScreen:FindFirstChild("QuoteLabel1")
		local label2 = osScreen:FindFirstChild("QuoteLabel2")
		if label1 then label1.Text = QUOTES[q1idx] end
		if label2 then label2.Text = QUOTES[q2idx] end
	end
end

-- ── Feed filter state ─────────────────────────────────────────────────────
local _feedMode = "global"   -- "global" | "server"

local COL_FILTER_ACTIVE   = Color3.fromRGB(60, 130, 220)
local COL_FILTER_INACTIVE = Color3.fromRGB(180, 180, 180)

-- Cached filter button refs (set in wireNavigation)
local _filterGlobalBtn = nil
local _filterServerBtn = nil

local function updateFilterVisuals()
	if _filterGlobalBtn then
		_filterGlobalBtn.BackgroundColor3 =
			(_feedMode == "global") and COL_FILTER_ACTIVE or COL_FILTER_INACTIVE
	end
	if _filterServerBtn then
		_filterServerBtn.BackgroundColor3 =
			(_feedMode == "server") and COL_FILTER_ACTIVE or COL_FILTER_INACTIVE
	end
end

-- ── Populate flags ────────────────────────────────────────────────────────
local _jobsLoaded = false
local _feedLoaded = false
local _shopLoaded = false

-- ── Job population ────────────────────────────────────────────────────────
local function populateJobs()
	if _jobsLoaded then return end
	_jobsLoaded = true

	local page     = LaptopGui:FindFirstChild("MoneyMakerPage")
	if not page then return end
	local scroll   = page:FindFirstChild("JobListScroll", true)
	if not scroll then return end
	local template = scroll:FindFirstChild("JobCardTemplate")
	if not template then return end

	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local rf = getRemote("RequestJobs")
	if not rf then return end
	local jobs = rf:InvokeServer()
	if type(jobs) ~= "table" then return end

	local acceptRE  = getRemote("AcceptJob")

	for _, job in ipairs(jobs) do
		local card = template:Clone()
		card.Visible = true
		card.Name    = "JobCard_" .. job.id
		card.Parent  = scroll

		local nameLabel   = card:FindFirstChild("JobName")
		local detailLabel = card:FindFirstChild("JobDetails")
		local payLabel    = card:FindFirstChild("PayLabel")
		local follLabel   = card:FindFirstChild("FollowersLabel")
		local acceptBtn   = card:FindFirstChild("AcceptButton")
		local presHigh    = card:FindFirstChild("PrestigeHighlight")

		if nameLabel   then nameLabel.Text   = job.name                                 end
		if detailLabel then detailLabel.Text  = job.details                              end
		if payLabel    then payLabel.Text     = "$" .. tostring(job.pay)                 end
		if follLabel   then follLabel.Text    = tostring(job.followers) .. " followers"  end
		if presHigh    then presHigh.Visible  = job.prestige == true                     end

		if acceptBtn and acceptRE then
			local jobId = job.id
			acceptBtn.Activated:Connect(function()
				acceptRE:FireServer(jobId)
				LaptopGui.Enabled = false
				-- GameplayClient takes over: teleport → minigame → submit result
			end)
		end
	end
end

-- ── Post detail (forward declared so populateFeed can reference it) ───────
local loadPost

-- ── Feed population ───────────────────────────────────────────────────────
local function populateFeed()
	if _feedLoaded then return end
	_feedLoaded = true

	updateFilterVisuals()

	local page     = LaptopGui:FindFirstChild("TalkogramFeed")
	if not page then return end
	local grid     = page:FindFirstChild("PhotoGrid", true)
	if not grid then return end
	local template = grid:FindFirstChild("PostCardTemplate")
	if not template then return end

	for _, child in ipairs(grid:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local rf = getRemote("RequestFeed")
	if not rf then return end
	local posts = rf:InvokeServer(_feedMode)
	if type(posts) ~= "table" then return end

	for _, post in ipairs(posts) do
		local card = template:Clone()
		card.Visible         = true
		card.AutoButtonColor = false
		card.Name            = "PostCard_" .. tostring(post.id)
		card.Parent          = grid

		local titleLbl  = card:FindFirstChild("PostTitle")
		local authorLbl = card:FindFirstChild("PostAuthor")
		local likesLbl  = card:FindFirstChild("LikesLabel")
		local imgLbl    = card:FindFirstChild("PostImage")

		if titleLbl  then titleLbl.Text  = post.title                     end
		if authorLbl then authorLbl.Text = "by " .. (post.author or "?")  end
		if likesLbl  then likesLbl.Text  = "♥ " .. tostring(post.likes)  end

		if imgLbl and post.imageId and post.imageId > 0 then
			imgLbl.Image = "rbxassetid://" .. tostring(post.imageId)
		end

		local postId = post.id
		card.Activated:Connect(function()
			loadPost(postId)
		end)
	end
end

-- ── Post detail ───────────────────────────────────────────────────────────
loadPost = function(postId)
	local rf = getRemote("RequestPost")
	if not rf then return end
	local post = rf:InvokeServer(postId)
	if not post then return end

	local page = LaptopGui:FindFirstChild("TalkogramPost")
	if not page then return end

	local titleLbl  = page:FindFirstChild("PostTitle",   true)
	local authorLbl = page:FindFirstChild("AuthorLabel", true)
	if titleLbl  then titleLbl.Text  = post.title                    end
	if authorLbl then authorLbl.Text = "by " .. (post.author or "?") end

	local scroll   = page:FindFirstChild("CommentsScroll", true)
	local template = scroll and scroll:FindFirstChild("CommentTemplate")
	if not scroll or not template then
		showPage("TalkogramPost")
		return
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for _, comment in ipairs(post.comments or {}) do
		local row = template:Clone()
		row.Visible = true
		row.Parent  = scroll

		local authorLb = row:FindFirstChild("CommentAuthor")
		local textLb   = row:FindFirstChild("CommentText")
		if authorLb then authorLb.Text = comment.author end
		if textLb   then textLb.Text   = comment.text   end
	end

	-- Wire send button; tag with postId to avoid re-wiring on the same post
	local inputRow   = page:FindFirstChild("CommentInputRow", true)
	local commentBox = inputRow and inputRow:FindFirstChild("CommentBox")
	local sendBtn    = inputRow and inputRow:FindFirstChild("SendButton")

	if sendBtn and commentBox then
		if sendBtn:GetAttribute("wiredPostId") ~= tostring(postId) then
			sendBtn:SetAttribute("wiredPostId", tostring(postId))
			sendBtn.Activated:Connect(function()
				local text = commentBox.Text
				if text == "" or text == commentBox.PlaceholderText then return end
				local postRE = getRemote("PostComment")
				if postRE then
					postRE:FireServer(postId, text)
					commentBox.Text = ""
					local row = template:Clone()
					row.Visible = true
					row.Parent  = scroll
					local a = row:FindFirstChild("CommentAuthor")
					local t = row:FindFirstChild("CommentText")
					if a then a.Text = player.Name end
					if t then t.Text = text end
				end
			end)
		end
	end

	showPage("TalkogramPost")
end

-- ── Shop population ───────────────────────────────────────────────────────
local SHOP_ITEMS = {
	{ name = "CurvedNeedle", displayName = "Curved Needle",   price = 500, description = "+20% stitch tolerance" },
	{ name = "FoamPressKit", displayName = "Foam Press Kit",  price = 750, description = "+20% foam snap range"  },
	{ name = "PowerStapler", displayName = "Power Stapler",   price = 400, description = "Wider staple good zone" },
	{ name = "TackPuller",   displayName = "Pro Tack Puller", price = 350, description = "More approach time"     },
}

local function populateShop()
	if _shopLoaded then return end
	_shopLoaded = true

	local page = LaptopGui:FindFirstChild("ShopPage")
	if not page then return end

	local rf = getRemote("RequestInventory")
	local owned = rf and rf:InvokeServer() or {}
	local ownedSet = {}
	for _, toolName in ipairs(owned) do ownedSet[toolName] = true end

	local purchaseRE = getRemote("PurchaseTool")

	for _, item in ipairs(SHOP_ITEMS) do
		local itemFrame = page:FindFirstChild("Item_" .. item.name, true)
		if itemFrame then
			local priceLabel = itemFrame:FindFirstChild("PriceLabel")
			local descLabel  = itemFrame:FindFirstChild("DescLabel")
			local buyBtn     = itemFrame:FindFirstChild("BuyButton")
			local ownedLabel = itemFrame:FindFirstChild("OwnedLabel")

			if priceLabel then priceLabel.Text = "$" .. tostring(item.price) end
			if descLabel  then descLabel.Text  = item.description            end

			if ownedSet[item.name] then
				if buyBtn     then buyBtn.Visible     = false end
				if ownedLabel then ownedLabel.Visible = true  end
			else
				if ownedLabel then ownedLabel.Visible = false end
				if buyBtn and purchaseRE then
					local toolName = item.name
					buyBtn.Activated:Connect(function()
						purchaseRE:FireServer(toolName)
						buyBtn.Text = "Purchased!"
						buyBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
						task.delay(1.5, function()
							if buyBtn.Parent then
								buyBtn.Visible = false
								if ownedLabel then ownedLabel.Visible = true end
							end
						end)
					end)
				end
			end
		end
	end
end

-- ── Wire navigation ───────────────────────────────────────────────────────

-- Wires CloseButton → OSScreen and BackButton → backTarget for any page
-- that uses the Browsah_Tab > Miscellaneous pattern.
local function wireBrowsahTab(page, backTarget)
	local tab  = page and page:FindFirstChild("Browsah_Tab")
	local misc = tab  and tab:FindFirstChild("Miscellaneous")
	if not misc then return end

	local closeBtn = misc:FindFirstChild("CloseButton")
	local backBtn  = misc:FindFirstChild("BackButton")

	if closeBtn then
		closeBtn.Activated:Connect(function() showPage("OSScreen") end)
	end
	if backBtn and backTarget then
		backBtn.Activated:Connect(function() showPage(backTarget) end)
	end
end

local function wireNavigation()
	-- ── OSScreen ──────────────────────────────────────────────────────────
	local osScreen = LaptopGui:FindFirstChild("OSScreen")

	local browsahIcon = osScreen and osScreen:FindFirstChild("BrowsahIcon")
	if browsahIcon then
		browsahIcon.Activated:Connect(function() showPage("BrowsahHome") end)
	end

	local shutDown = osScreen and osScreen:FindFirstChild("ShutDownButton", true)
	if shutDown then
		shutDown.Activated:Connect(function() LaptopGui.Enabled = false end)
	end

	-- ── Browsah_Tab chrome on every browser page ──────────────────────────
	wireBrowsahTab(LaptopGui:FindFirstChild("BrowsahHome"),    nil)
	wireBrowsahTab(LaptopGui:FindFirstChild("TalkogramFeed"),  "BrowsahHome")
	wireBrowsahTab(LaptopGui:FindFirstChild("TalkogramPost"),  "TalkogramFeed")
	wireBrowsahTab(LaptopGui:FindFirstChild("MoneyMakerPage"), "BrowsahHome")
	wireBrowsahTab(LaptopGui:FindFirstChild("ShopPage"),       "BrowsahHome")

	-- ── BrowsahHome bookmarks ─────────────────────────────────────────────
	local browsah    = LaptopGui:FindFirstChild("BrowsahHome")
	local browsahTab = browsah and browsah:FindFirstChild("Browsah_Tab")

	local bTalkogram  = browsahTab and browsahTab:FindFirstChild("BookmarkTalkogram")
	local bMoneyMaker = browsahTab and browsahTab:FindFirstChild("BookmarkMoneyMaker")
	local bShop       = browsahTab and browsahTab:FindFirstChild("BookmarkShop")

	if bTalkogram then
		bTalkogram.Activated:Connect(function()
			populateFeed()
			showPage("TalkogramFeed")
		end)
	end
	if bMoneyMaker then
		bMoneyMaker.Activated:Connect(function()
			populateJobs()
			showPage("MoneyMakerPage")
		end)
	end
	if bShop then
		bShop.Activated:Connect(function()
			populateShop()
			showPage("ShopPage")
		end)
	end

	-- ── Feed filter buttons ───────────────────────────────────────────────
	local feedPage = LaptopGui:FindFirstChild("TalkogramFeed")
	_filterGlobalBtn = feedPage and feedPage:FindFirstChild("FilterGlobal", true)
	_filterServerBtn = feedPage and feedPage:FindFirstChild("FilterServer", true)

	local function setFeedFilter(mode)
		_feedMode   = mode
		_feedLoaded = false   -- force reload with new filter
		populateFeed()
	end

	if _filterGlobalBtn then
		_filterGlobalBtn.Activated:Connect(function() setFeedFilter("global") end)
	end
	if _filterServerBtn then
		_filterServerBtn.Activated:Connect(function() setFeedFilter("server") end)
	end
end

-- ── Entry point ───────────────────────────────────────────────────────────

local openedEvent = PlayerGui:WaitForChild("LaptopOpened", 10)

if openedEvent then
	wireNavigation()

	openedEvent.Event:Connect(function()
		_jobsLoaded = false
		_feedLoaded = false
		_shopLoaded = false
		_feedMode   = "global"

		LaptopGui.Enabled = true
		playBootSequence()
	end)
end
