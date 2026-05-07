--[[
	PlayerHouseManager
	ModuleScript — required by LocationManager.

	Assigns one of the 6 player houses (House_1 … House_6) to each player on join.
	Assignment is session-based: first-come-first-served, freed on disconnect.

	Public API:
	  PlayerHouseManager.GetHouseCFrame(player) → CFrame
	  PlayerHouseManager.GetAssignment(player)  → { index, tier } or nil
	  PlayerHouseManager.SetTier(player, newTier) — called by HousePrestigeManager later

	House tier swapping (future HousePrestigeManager):
	  1. Get slot:  PlayerHouseManager.GetAssignment(player).index
	  2. Destroy:   workspace["House_" .. index]
	  3. Clone new tier model into workspace, name it "House_" .. index
	  4. Call:      PlayerHouseManager.SetTier(player, newTier)
	  5. Teleport:  TeleportToHub:FireClient(player, PlayerHouseManager.GetHouseCFrame(player))
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Houses     = GameConfig.PlayerHouses

local remotesFolder = ReplicatedStorage:WaitForChild("LaptopRemotes")
local TeleportToHub = remotesFolder:WaitForChild("TeleportToHub")

-- ── Internal state ────────────────────────────────────────────────────────

-- _pool[slotIndex] = player.UserId (occupied) or nil (free)
local _pool = {}
for i = 1, Houses.slotCount do _pool[i] = nil end

-- _assignment[player] = { index = N, tier = N }
local _assignment = {}

-- ── Helpers ───────────────────────────────────────────────────────────────

local function getHouseCFrame(player)
	local data = _assignment[player]
	if not data then return CFrame.new(0, 5, 0) end
	local house = workspace:FindFirstChild("House_" .. data.index)
	if house then
		local spawn = house:FindFirstChildWhichIsA("SpawnLocation")
		if spawn then
			return spawn.CFrame + Vector3.new(0, 3, 0)
		end
		return house:GetPivot() + Vector3.new(0, 5, 0)
	end
	warn("[PlayerHouseManager] House_" .. data.index .. " not found in Workspace")
	return CFrame.new(0, 5, 0)
end

local function assignHouse(player)
	for i = 1, Houses.slotCount do
		if _pool[i] == nil then
			_pool[i] = player.UserId
			_assignment[player] = { index = i, tier = 1 }
			print(("[PlayerHouseManager] %s → House_%d (Tier 1)"):format(player.Name, i))
			return i
		end
	end
	warn("[PlayerHouseManager] No free house slot for", player.Name)
	return nil
end

local function releaseHouse(player)
	local data = _assignment[player]
	if not data then return end
	_pool[data.index] = nil
	_assignment[player] = nil
	print(("[PlayerHouseManager] Released House_%d from %s"):format(data.index, player.Name))
end

-- ── Public API ────────────────────────────────────────────────────────────

local PlayerHouseManager = {}

function PlayerHouseManager.GetHouseCFrame(player)
	return getHouseCFrame(player)
end

function PlayerHouseManager.GetAssignment(player)
	return _assignment[player]
end

-- Called by future HousePrestigeManager after it swaps the model
function PlayerHouseManager.SetTier(player, newTier)
	local data = _assignment[player]
	if not data then return end
	data.tier = newTier
	print(("[PlayerHouseManager] %s upgraded to Tier %d"):format(player.Name, newTier))
end

-- ── Player lifecycle ──────────────────────────────────────────────────────

local function onPlayerAdded(player)
	assignHouse(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		TeleportToHub:FireClient(player, getHouseCFrame(player))
	end)
	-- Character may have already loaded before this handler was connected
	if player.Character then
		task.spawn(function()
			task.wait(1)
			TeleportToHub:FireClient(player, getHouseCFrame(player))
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players who joined before this module finished loading
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function() onPlayerAdded(player) end)
end

Players.PlayerRemoving:Connect(function(player)
	releaseHouse(player)
end)

return PlayerHouseManager
