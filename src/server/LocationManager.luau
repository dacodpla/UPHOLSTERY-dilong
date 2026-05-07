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

local GameConfig         = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Locations          = GameConfig.Locations
local PlayerHouseManager = require(script.Parent:WaitForChild("PlayerHouseManager", 10)
	or error("[LocationManager] PlayerHouseManager not found in ServerScriptService"))

-- ── Remotes (created by LaptopData before this module is required) ────────

local remotesFolder          = ReplicatedStorage:WaitForChild("LaptopRemotes")
local TeleportToLocation     = remotesFolder:WaitForChild("TeleportToLocation")
local TeleportToHub          = remotesFolder:WaitForChild("TeleportToHub")
local LocationFull           = remotesFolder:WaitForChild("LocationFull")
local FurniturePieceRepaired = remotesFolder:WaitForChild("FurniturePieceRepaired")
local StartMinigame          = remotesFolder:WaitForChild("StartMinigame")

-- ── Internal state ────────────────────────────────────────────────────────

-- _pool[locationName][slotIndex] = player.UserId (occupied) or nil (free)
local _pool = {}

-- _playerAssignment[player] = { locationName, slotIndex, slotModel, clones, fixedClones, furnitureKeys, doorPrompt }
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

local function getDamagedVariants(typeFolder)
	local variants = {}
	for _, child in ipairs(typeFolder:GetChildren()) do
		if child.Name ~= "Default" then
			table.insert(variants, child)
		end
	end
	return variants
end

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

local function placeFurnitureDefault(slotModel, furnitureKey, padIndex)
	local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
	local typeFolder = furnitureFolder and furnitureFolder:FindFirstChild(furnitureKey)
	if not typeFolder then
		warn("[LocationManager] FurnitureModels/" .. furnitureKey .. " not found for Default placement")
		return nil
	end
	local defaultModel = typeFolder:FindFirstChild("Default")
	if not defaultModel then
		warn("[LocationManager] No 'Default' model in", furnitureKey)
		return nil
	end
	local pad = slotModel:FindFirstChild("FurniturePad_" .. padIndex, true)
	local fixedClone = defaultModel:Clone()
	fixedClone.Parent = slotModel
	if pad and pad:IsA("BasePart") then
		local _, bbSize = fixedClone:GetBoundingBox()
		fixedClone:PivotTo(
			CFrame.new(pad.Position + Vector3.new(0, bbSize.Y / 2, 0)) * pad.CFrame.Rotation
		)
	end
	for _, part in ipairs(fixedClone:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	return fixedClone
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

	-- Clone all furniture pieces listed in job.furniture onto numbered pads
	local cloneList = {}
	local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")

	for i, furnitureKey in ipairs(job.furniture or {}) do
		local padName    = "FurniturePad_" .. i
		local pad        = slotModel:FindFirstChild(padName, true)
		local typeFolder = furnitureFolder and furnitureFolder:FindFirstChild(furnitureKey)

		if not typeFolder then
			warn("[LocationManager] FurnitureModels/" .. tostring(furnitureKey) .. " not found — skipping piece", i)
		elseif not pad or not pad:IsA("BasePart") then
			warn("[LocationManager] " .. padName .. " not found or not a BasePart in", slotModel.Name, "— skipping piece", i)
		else
			local variants = getDamagedVariants(typeFolder)
			if #variants > 0 then
				local clone = pickRandom(variants):Clone()
				clone.Parent = slotModel
				local _, bbSize = clone:GetBoundingBox()
				local yOffset = bbSize.Y / 2
				clone:PivotTo(
					CFrame.new(pad.Position + Vector3.new(0, yOffset, 0)) * pad.CFrame.Rotation
				)
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then part.Anchored = true end
				end
				colorizeClone(clone)
				table.insert(cloneList, clone)
			else
				warn("[LocationManager] No damage variants in", furnitureKey)
			end
		end
	end

	-- RepairPrompt on FurniturePad_N — independent of furniture model structure
	local repairPrompts = {}
	for i = 1, #cloneList do
		local padName = "FurniturePad_" .. i
		local pad = slotModel:FindFirstChild(padName, true)
		if pad and pad:IsA("BasePart") then
			local rp = Instance.new("ProximityPrompt")
			rp.Name                = "RepairPrompt"
			rp.ActionText          = "Repair"
			rp.ObjectText          = job.name
			rp.MaxActivationDistance = 10
			rp.RequiresLineOfSight = false
			rp.Exclusivity         = Enum.ProximityPromptExclusivity.AlwaysShow
			rp.Parent              = pad
			repairPrompts[i]       = rp
			rp.Triggered:Connect(function(triggeringPlayer)
				if not _playerAssignment[triggeringPlayer] then return end
				rp.Enabled = false
				StartMinigame:FireClient(triggeringPlayer, i)
			end)
			print(("[LocationManager]   Piece %d RepairPrompt on %s"):format(i, padName))
		else
			warn(("[LocationManager]   %s not found — RepairPrompt piece %d skipped"):format(padName, i))
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
		locationName  = chosenName,
		slotIndex     = chosenIndex,
		slotModel     = slotModel,
		clones        = cloneList,
		fixedClones   = {},
		furnitureKeys = job.furniture or {},
		repairPrompts = repairPrompts,
		doorPrompt    = doorPromptInstance,
	}

	-- Teleport player; send full clone list so client wires a prompt per piece
	local spawnPad = slotModel:FindFirstChild("SpawnPad", true)
	local cframe   = spawnPad and spawnPad.CFrame or slotModel:GetPivot()
	TeleportToLocation:FireClient(player, cframe, job, cloneList)

	print(("[LocationManager] Assigned %s → %s Slot_%d"):format(player.Name, chosenName, chosenIndex))
	return true
end

function LocationManager.Release(player)
	local assignment = _playerAssignment[player]
	if not assignment then return end

	-- Destroy any remaining damaged clones and all fixed (Default) clones
	for _, clone in pairs(assignment.clones or {}) do
		if clone and clone.Parent then clone:Destroy() end
	end
	for _, fixedClone in pairs(assignment.fixedClones or {}) do
		if fixedClone and fixedClone.Parent then fixedClone:Destroy() end
	end

	-- Remove RepairPrompts (on pads, which persist — must be explicitly removed)
	for _, rp in pairs(assignment.repairPrompts or {}) do
		if rp and rp.Parent then rp:Destroy() end
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

	-- Teleport back to player's house
	TeleportToHub:FireClient(player, PlayerHouseManager.GetHouseCFrame(player))

	print(("[LocationManager] Released %s from %s Slot_%d"):format(
		player.Name, assignment.locationName, assignment.slotIndex
	))
end

-- ── Auto-release on disconnect ─────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	if _playerAssignment[player] then
		-- Don't teleport — player is gone. Just clean up the slot.
		local assignment = _playerAssignment[player]
		for _, clone in pairs(assignment.clones or {}) do
			if clone and clone.Parent then clone:Destroy() end
		end
		for _, fixedClone in pairs(assignment.fixedClones or {}) do
			if fixedClone and fixedClone.Parent then fixedClone:Destroy() end
		end
		for _, rp in pairs(assignment.repairPrompts or {}) do
			if rp and rp.Parent then rp:Destroy() end
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

-- ── FurniturePieceRepaired: swap damaged clone → Default model ────────────

FurniturePieceRepaired.OnServerEvent:Connect(function(player, pieceIndex)
	local assignment = _playerAssignment[player]
	if not assignment then return end
	if type(pieceIndex) ~= "number" then return end

	local damagedClone = assignment.clones[pieceIndex]
	if damagedClone and damagedClone.Parent then
		damagedClone:Destroy()
	end
	assignment.clones[pieceIndex] = nil

	local furnitureKey = assignment.furnitureKeys[pieceIndex]
	if furnitureKey then
		local fixedClone = placeFurnitureDefault(assignment.slotModel, furnitureKey, pieceIndex)
		if fixedClone then
			assignment.fixedClones[pieceIndex] = fixedClone
		end
	end
end)

return LocationManager
