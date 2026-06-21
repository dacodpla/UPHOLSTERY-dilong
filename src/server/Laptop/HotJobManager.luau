--[[
	HotJobManager
	Every 5-8 minutes, generates a "Hot Job" with 3.0× pay, +75% followers.
	Broadcasts a 10-second countdown before the job appears on the shared board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local HotJobManager = {}

local _radiantJobGen     = nil
local _injectIntoPool    = nil
local _hotJobCountdownRE = nil

local function pickRandom(t) return t[math.random(#t)] end

local function generateHotJob()
	local cfg = GameConfig.HotJobs
	local tier = pickRandom(cfg.tiers)
	local jobs = _radiantJobGen.Generate(1, { [tier] = true })
	if not jobs[1] then return end
	local job = jobs[1]
	job.isHotJob   = true
	job.pay        = math.floor(job.pay * cfg.payMultiplier)
	job.followers  = math.floor(job.followers * (1 + cfg.followerBonus))
	return job
end

function HotJobManager.Init(radiantJobGen, injectIntoPool, hotJobCountdownRE)
	_radiantJobGen     = radiantJobGen
	_injectIntoPool    = injectIntoPool
	_hotJobCountdownRE = hotJobCountdownRE

	task.spawn(function()
		while true do
			local cfg = GameConfig.HotJobs
			task.wait(math.random(cfg.intervalMin, cfg.intervalMax))
			local job = generateHotJob()
			if job then
				_hotJobCountdownRE:FireAllClients(cfg.countdownSec, job.tier)
				task.wait(cfg.countdownSec)
				_injectIntoPool(job)
				print(("[HotJobManager] Hot Job released | %s | $%d"):format(job.tier, job.pay))
			end
		end
	end)
end

return HotJobManager
