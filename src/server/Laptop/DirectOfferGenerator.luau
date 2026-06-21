--[[
	DirectOfferGenerator
	Per-player personal job offers gated by reputation tier (GDD §3.2).
	Offers expire after 5 minutes. Cleaner than the shared board:
	once an offer is generated it belongs only to that player.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local EXPIRY_SEC = 300  -- 5 min per GDD

local _radiantJobGen = nil
local _onDirectOffersChanged = nil
local _playerOffers     = {}  -- [player] = { offers = { {id, expiresAt, ...}, ... } }
local _nextOfferId      = 1
local _playerWorkers    = {}  -- [player] = task handle

local function findRule(rep)
	for _, rule in ipairs(GameConfig.Reputation.directOfferRules) do
		if rep >= rule.minRep and rep <= rule.maxRep then
			return rule
		end
	end
	return nil
end

local function pruneExpired(player)
	local state = _playerOffers[player]; if not state then return end
	local now = os.time()
	local kept = {}
	for _, offer in ipairs(state.offers) do
		if offer.expiresAt > now then table.insert(kept, offer) end
	end
	state.offers = kept
end

local DirectOfferGenerator = {}

function DirectOfferGenerator.GetOffers(player)
	pruneExpired(player)
	local state = _playerOffers[player]
	return state and state.offers or {}
end

function DirectOfferGenerator.FindOffer(player, offerId)
	local offers = DirectOfferGenerator.GetOffers(player)
	for _, offer in ipairs(offers) do
		if offer.id == offerId then return offer end
	end
	return nil
end

function DirectOfferGenerator.ConsumeOffer(player, offerId)
	local state = _playerOffers[player]; if not state then return nil end
	for i, offer in ipairs(state.offers) do
		if offer.id == offerId then
			table.remove(state.offers, i)
			if _onDirectOffersChanged then _onDirectOffersChanged(player) end
			return offer
		end
	end
	return nil
end

function DirectOfferGenerator.RefreshFor(player)
	local pd = player:FindFirstChild("PlayerData"); if not pd then return end
	local rep = (pd:FindFirstChild("reputation") and pd.reputation.Value) or 0
	local rule = findRule(rep)

	_playerOffers[player] = _playerOffers[player] or { offers = {} }
	local state = _playerOffers[player]

	if not rule then
		state.offers = {}
		if _onDirectOffersChanged then _onDirectOffersChanged(player) end
		return
	end

	pruneExpired(player)

	-- Top off the offer count
	local needed = rule.count - #state.offers
	if needed <= 0 then return end

	local allowedTiers = {}
	for _, t in ipairs(rule.tiers) do allowedTiers[t] = true end

	local now = os.time()
	for _ = 1, needed do
		local jobs = _radiantJobGen.Generate(1, allowedTiers)
		if jobs[1] then
			local job = jobs[1]
			job.id        = _nextOfferId
			job.expiresAt = now + EXPIRY_SEC
			_nextOfferId  = _nextOfferId + 1
			table.insert(state.offers, job)
		end
	end

	if _onDirectOffersChanged then _onDirectOffersChanged(player) end
end

local function startWorkerFor(player)
	if _playerWorkers[player] then return end
	_playerWorkers[player] = task.spawn(function()
		while player.Parent do
			local pd = player:FindFirstChild("PlayerData")
			if pd then
				local rep = (pd:FindFirstChild("reputation") and pd.reputation.Value) or 0
				local rule = findRule(rep)
				DirectOfferGenerator.RefreshFor(player)
				if rule then
					task.wait(rule.refreshSec)
				else
					task.wait(30)  -- check again soon in case rep crosses 1.0
				end
			else
				task.wait(5)
			end
		end
	end)
end

local function stopWorkerFor(player)
	_playerOffers[player]  = nil
	_playerWorkers[player] = nil
end

function DirectOfferGenerator.Init(radiantJobGen, onDirectOffersChanged)
	_radiantJobGen           = radiantJobGen
	_onDirectOffersChanged   = onDirectOffersChanged

	Players.PlayerAdded:Connect(startWorkerFor)
	for _, player in ipairs(Players:GetPlayers()) do startWorkerFor(player) end
	Players.PlayerRemoving:Connect(stopWorkerFor)
end

return DirectOfferGenerator
