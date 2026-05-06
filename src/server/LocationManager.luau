--[[
	LocationManager
	ModuleScript — required by LaptopData.server.luau.

	Tracks free/occupied client location slots per location type.
	On AcceptJob: picks a free slot, clones furniture, randomizes colors, teleports player.
	On SubmitJobResult: destroys furniture, resets colors, teleports player back to hub.

	Workspace structure expected:
	  ClientLocations [Folder]
	    └── StudioApartment [Folder]
	          ├── Slot_1 [Model]  (Floor, Walls, SpawnPad, FurniturePad)
	          └── Slot_2 … Slot_6

	ServerStorage structure expected:
	  FurnitureModels [Folder]
	    └── DiningChair [Folder]
	          ├── Damaged_A [Model]  (parts named FabricPart / FramePart)
	          ├── Damaged_B [Model]
	          └── Damaged_C [Model]
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local GameConfig  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Locations   = GameConfig.Locations

-- ── Remotes (created by LaptopData before this module is required) ────────

local remotesFolder      = ReplicatedStorage:WaitForChild("LaptopRemotes")
local TeleportToLocation = remotesFolder:WaitForChild("TeleportToLocation")
local TeleportToHub      = remotesFolder:WaitForChild("TeleportToHub")
local LocationFull       = remotesFolder:WaitForChild("LocationFull")

-- ── Internal state ────────────────────────────────────────────────────────

-- _pool[locationName][slotIndex] = player.UserId (occupied) or nil (free)
local _pool = {}

-- _playerAssignment[player] = { locationName, slotIndex, slotModel, clone }
local _playerAssignment = {}

-- ── Pool initialisation ───────────────────────────────────────────────────

local clientLocationsFolder = workspace:FindFirstChild("ClientLocations")
if not clientLocationsFolder then
	warn("[LocationManager] No 'ClientLocations' folder in Workspace — teleport disabled")
else
	for _, locationFolder in ipairs(clientLocationsFolder:GetChildren()) do
		_pool[locationFolder.Name] = {}
		for i = 1, Locations.slotCount do
			_pool[locationFolder.Name][i] = nil
		end
	end
end

-- ── Helpers ───────────────────────────────────────────────────────────────

local NEUTRAL_COLOR = Color3.fromRGB(163, 162, 165)
local VARIANT_NAMES = {"Damaged_A", "Damaged_B", "Damaged_C"}

local function pickRandom(tbl)
	return tbl[math.random(#tbl)]
end

local function shuffleCopy(tbl)
	local copy = table.clone(tbl)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function colorizeClone(clone)
	local fabric = pickRandom(Locations.fabricColors)
	local frame  = pickRandom(Locations.frameColors)
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.Name == "FabricPart" then
				desc.Color = fabric
			elseif desc.Name == "FramePart" then
				desc.Color = frame
			end
		end
	end
end

local function colorizeSlot(slotModel, wallColor)
	local floor = slotModel:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Color = wallColor
	end
	local walls = slotModel:FindFirstChild("Walls")
	if walls then
		for _, part in ipairs(walls:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = wallColor
			end
		end
	end
end

local function resetSlotColors(slotModel)
	local floor = slotModel:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Color = NEUTRAL_COLOR
	end
	local walls = slotModel:FindFirstChild("Walls")
	if walls then
		for _, part in ipairs(walls:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = NEUTRAL_COLOR
			end
		end
	end
end

local function getHubCFrame()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then
		return spawn.CFrame + Vector3.new(0, 3, 0)
	end
	return CFrame.new(0, 5, 0)
end

-- ── LocationManager API ───────────────────────────────────────────────────

local LocationManager = {}

function LocationManager.Assign(player, job)
	if not clientLocationsFolder then
		warn("[LocationManager] Assign called but ClientLocations folder is missing")
		LocationFull:FireClient(player)
		return false
	end

	local tierNames = Locations.byTier[job.tier]
	if not tierNames or #tierNames == 0 then
		warn("[LocationManager] No locations configured for tier:", job.tier)
		LocationFull:FireClient(player)
		return false
	end

	-- Search shuffled tier list so all location names get even use
	local shuffled = shuffleCopy(tierNames)
	local chosenName  = nil
	local chosenIndex = nil

	for _, name in ipairs(shuffled) do
		local pool = _pool[name]
		if pool then
			for i = 1, Locations.slotCount do
				if pool[i] == nil then
					chosenName  = name
					chosenIndex = i
					break
				end
			end
		end
		if chosenName then break end
	end

	if not chosenName then
		LocationFull:FireClient(player)
		return false
	end

	-- Mark slot occupied
	_pool[chosenName][chosenIndex] = player.UserId

	local locationFolder = clientLocationsFolder:FindFirstChild(chosenName)
	local slotModel      = locationFolder and locationFolder:FindFirstChild("Slot_" .. chosenIndex)

	if not slotModel then
		warn("[LocationManager] Missing Slot_" .. chosenIndex .. " inside " .. chosenName)
		_pool[chosenName][chosenIndex] = nil
		LocationFull:FireClient(player)
		return false
	end

	-- Clone furniture model
	local clone = nil
	local modelKey = Locations.furnitureModelKey[job.id]
	if modelKey then
		local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
		local typeFolder      = furnitureFolder and furnitureFolder:FindFirstChild(modelKey)
		if typeFolder then
			local variant = typeFolder:FindFirstChild(pickRandom(VARIANT_NAMES))
			if variant then
				clone = variant:Clone()
				local pad = slotModel:FindFirstChild("FurniturePad", true)
				clone.Parent = slotModel
				if pad and pad:IsA("BasePart") then
					local _, bbSize = clone:GetBoundingBox()
					local yOffset = bbSize.Y / 2
					clone:PivotTo(
						CFrame.new(pad.Position + Vector3.new(0, yOffset, 0)) * pad.CFrame.Rotation
					)
				else
					warn("[LocationManager] FurniturePad not found or not a BasePart in", slotModel.Name, "— furniture will be misplaced")
				end
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then part.Anchored = true end
				end
				colorizeClone(clone)
			else
				warn("[LocationManager] No damage variants found in", modelKey)
			end
		else
			warn("[LocationManager] FurnitureModels/" .. tostring(modelKey) .. " not found in ServerStorage")
		end
	end

	-- Add RepairPrompt to furniture clone so player can trigger the minigame
	if clone then
		local repairPart = clone.PrimaryPart
		if not repairPart then
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then repairPart = desc break end
			end
		end
		if repairPart then
			local rp = Instance.new("ProximityPrompt")
			rp.Name                  = "RepairPrompt"
			rp.ActionText            = "Repair"
			rp.ObjectText            = job.name
			rp.MaxActivationDistance = 10
			rp.Parent                = repairPart
		else
			warn("[LocationManager] No BasePart in furniture clone — RepairPrompt skipped")
		end
	end

	-- Add DoorPrompt to the Door part so player can exit or abandon
	local doorPart = slotModel:FindFirstChild("Door", true)
	if doorPart and not doorPart:IsA("BasePart") then
		doorPart = doorPart:FindFirstChildWhichIsA("BasePart")
	end
	local doorPromptInstance = nil
	if doorPart then
		doorPromptInstance = Instance.new("ProximityPrompt")
		doorPromptInstance.Name                  = "DoorPrompt"
		doorPromptInstance.ActionText            = "Leave"
		doorPromptInstance.ObjectText            = "Exit"
		doorPromptInstance.MaxActivationDistance = 8
		doorPromptInstance.Parent                = doorPart
	else
		warn("[LocationManager] No 'Door' BasePart in slot — exit prompt skipped")
	end

	-- Randomize slot colors
	colorizeSlot(slotModel, pickRandom(Locations.wallColors))

	-- Store assignment
	_playerAssignment[player] = {
		locationName = chosenName,
		slotIndex    = chosenIndex,
		slotModel    = slotModel,
		clone        = clone,
		doorPrompt   = doorPromptInstance,
	}

	-- Teleport player (pass clone so client can attach highlight + find prompts)
	local spawnPad = slotModel:FindFirstChild("SpawnPad", true)
	local cframe   = spawnPad and spawnPad.CFrame or slotModel:GetPivot()
	TeleportToLocation:FireClient(player, cframe, job, clone)

	print(("[LocationManager] Assigned %s → %s Slot_%d"):format(player.Name, chosenName, chosenIndex))
	return true
end

function LocationManager.Release(player)
	local assignment = _playerAssignment[player]
	if not assignment then return end

	-- Destroy furniture clone (also removes RepairPrompt inside it)
	if assignment.clone and assignment.clone.Parent then
		assignment.clone:Destroy()
	end

	-- Remove door prompt (persists on the slot which is NOT destroyed)
	if assignment.doorPrompt and assignment.doorPrompt.Parent then
		assignment.doorPrompt:Destroy()
	end

	-- Reset slot appearance
	if assignment.slotModel and assignment.slotModel.Parent then
		resetSlotColors(assignment.slotModel)
	end

	-- Free pool slot
	local pool = _pool[assignment.locationName]
	if pool then
		pool[assignment.slotIndex] = nil
	end

	_playerAssignment[player] = nil

	-- Teleport back to hub
	TeleportToHub:FireClient(player, getHubCFrame())

	print(("[LocationManager] Released %s from %s Slot_%d"):format(
		player.Name, assignment.locationName, assignment.slotIndex
	))
end

-- ── Auto-release on disconnect ─────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	if _playerAssignment[player] then
		-- Don't teleport — player is gone. Just clean up the slot.
		local assignment = _playerAssignment[player]
		if assignment.clone and assignment.clone.Parent then
			assignment.clone:Destroy()
		end
		if assignment.doorPrompt and assignment.doorPrompt.Parent then
			assignment.doorPrompt:Destroy()
		end
		if assignment.slotModel and assignment.slotModel.Parent then
			resetSlotColors(assignment.slotModel)
		end
		local pool = _pool[assignment.locationName]
		if pool then
			pool[assignment.slotIndex] = nil
		end
		_playerAssignment[player] = nil
		print(("[LocationManager] Cleaned up slot for disconnected player %s"):format(player.Name))
	end
end)

return LocationManager
