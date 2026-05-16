--[[
	LocationManager
	ModuleScript — required by LaptopData.server.luau.

	Tracks free/occupied client location slots per location type.
	On AcceptJob: picks a free slot, clones the slot template from ServerStorage into
	  Workspace/ActiveSlots, clones furniture, randomizes colors, teleports player.
	On SubmitJobResult: destroys the entire slot clone (takes furniture + prompts with it),
	  teleports player back to hub.

	ServerStorage structure expected:
	  ClientLocations [Folder]
	    └── StudioApartment [Folder]   ← Tier="Starter" attribute
	          ├── Slot_1 [Model]  (Floor, Walls, SpawnPad, FurniturePad_N, Door)
	          └── Slot_2 … Slot_6
	  FurnitureModels [Folder]
	    └── TwoSofa [Folder]
	          ├── Damaged_A [Model]  (parts named FabricPart / FramePart)
	          └── Default   [Model]
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

-- _slotCounts[locationName] = number of Slot_N templates discovered
local _slotCounts = {}

-- _locationsByTier[tier] = { locationName, ... }  — built from Tier attribute on each folder
local _locationsByTier = {}

-- _playerAssignment[player] = { locationName, slotIndex, slotModel, clones, fixedClones, furnitureKeys, repairPrompts, doorPrompt }
local _playerAssignment = {}

-- ── Slot template source + active slot container ──────────────────────────
-- Templates live in ServerStorage — no Workspace cost until a player needs one.
-- Active clones are parented into Workspace/ActiveSlots for the job's duration.

local serverLocationsFolder = ServerStorage:FindFirstChild("ClientLocations")

local _activeSlotsFolder = workspace:FindFirstChild("ActiveSlots")
if not _activeSlotsFolder then
	_activeSlotsFolder = Instance.new("Folder")
	_activeSlotsFolder.Name   = "ActiveSlots"
	_activeSlotsFolder.Parent = workspace
end

-- ── Pool initialisation ───────────────────────────────────────────────────
-- Discovers locations dynamically from ServerStorage. Each subfolder must have
-- a "Tier" string attribute ("Starter" / "Mid" / "Premium" / "Prestige").
-- Slot count is inferred by counting Slot_N Model children in the template folder.

if not serverLocationsFolder then
	warn("[LocationManager] No 'ClientLocations' folder in ServerStorage — teleport disabled")
else
	for _, locationFolder in ipairs(serverLocationsFolder:GetChildren()) do
		if locationFolder:IsA("Folder") then
			local slotCount = 0
			for _, child in ipairs(locationFolder:GetChildren()) do
				if child:IsA("Model") then
					local n = tonumber(child.Name:match("^Slot_(%d+)$"))
					if n and n > slotCount then slotCount = n end
				end
			end

			if slotCount > 0 then
				_pool[locationFolder.Name]       = {}
				_slotCounts[locationFolder.Name] = slotCount

				local tier = locationFolder:GetAttribute("Tier")
				if not tier then
					warn(("[LocationManager] '%s' has no 'Tier' attribute — defaulting to Starter"):format(locationFolder.Name))
					tier = "Starter"
				end
				if not _locationsByTier[tier] then
					_locationsByTier[tier] = {}
				end
				table.insert(_locationsByTier[tier], locationFolder.Name)

				print(("[LocationManager] Registered '%s' (Tier: %s, %d slots)"):format(locationFolder.Name, tier, slotCount))
			else
				warn(("[LocationManager] '%s' has no Slot_N models — skipping"):format(locationFolder.Name))
			end
		end
	end
end

-- ── Helpers ───────────────────────────────────────────────────────────────

local function getDamagedVariants(typeFolder)
	local variants = {}
	for _, child in ipairs(typeFolder:GetChildren()) do
		if child.Name:sub(1, 7) == "Damaged" then
			table.insert(variants, child)
		end
	end
	return variants
end

local function pickRandom(tbl)
	return tbl[math.random(#tbl)]
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
		local bbCF, bbSize = fixedClone:GetBoundingBox()
		local pivotToBottom = fixedClone:GetPivot().Position.Y - bbCF.Position.Y + bbSize.Y / 2
		fixedClone:PivotTo(pad.CFrame * CFrame.new(0, pivotToBottom, 0))
	end
	for _, part in ipairs(fixedClone:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	return fixedClone
end

-- ── LocationManager API ───────────────────────────────────────────────────

local LocationManager = {}

-- Returns a set of tier strings that have at least one registered location.
-- Used by RadiantJobGenerator to avoid generating jobs for non-existent buildings.
function LocationManager.GetLocationNames()
	local names = {}
	for name in pairs(_pool) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function LocationManager.GetAvailableTiers()
	local tiers = {}
	for tier, names in pairs(_locationsByTier) do
		if #names > 0 then
			tiers[tier] = true
		end
	end
	return tiers
end

function LocationManager.Assign(player, job)
	if not serverLocationsFolder then
		warn("[LocationManager] Assign called but ClientLocations folder is missing from ServerStorage")
		LocationFull:FireClient(player)
		return false
	end

	local tierNames = _locationsByTier[job.tier]
	if not tierNames or #tierNames == 0 then
		warn("[LocationManager] No locations registered for tier:", job.tier)
		LocationFull:FireClient(player)
		return false
	end

	-- Search shuffled tier list so all location names get even use
	-- Collect every free slot across all locations of this tier, then pick randomly.
	-- This ensures all 6 layout variants get equal exposure rather than always
	-- filling slot 1 before slot 2, etc.
	local freeSlots = {}
	for _, name in ipairs(tierNames) do
		local pool = _pool[name]
		if pool then
			for i = 1, (_slotCounts[name] or 0) do
				if pool[i] == nil then
					table.insert(freeSlots, { name = name, index = i })
				end
			end
		end
	end

	if #freeSlots == 0 then
		LocationFull:FireClient(player)
		return false
	end

	-- Admin-spawned jobs may request a specific location
	if type(job.locationOverride) == "string" then
		local filtered = {}
		for _, slot in ipairs(freeSlots) do
			if slot.name == job.locationOverride then
				table.insert(filtered, slot)
			end
		end
		if #filtered > 0 then
			freeSlots = filtered
		else
			warn("[LocationManager] locationOverride '" .. job.locationOverride .. "' has no free slots — using tier fallback")
		end
	end

	local chosen      = freeSlots[math.random(#freeSlots)]
	local chosenName  = chosen.name
	local chosenIndex = chosen.index

	-- Mark slot occupied
	_pool[chosenName][chosenIndex] = player.UserId

	-- Clone the slot template from ServerStorage into the live ActiveSlots folder
	local templateFolder = serverLocationsFolder:FindFirstChild(chosenName)
	local slotTemplate   = templateFolder and templateFolder:FindFirstChild("Slot_" .. chosenIndex)

	if not slotTemplate then
		warn("[LocationManager] Missing template Slot_" .. chosenIndex .. " in ServerStorage/" .. chosenName)
		_pool[chosenName][chosenIndex] = nil
		LocationFull:FireClient(player)
		return false
	end

	local slotModel = slotTemplate:Clone()
	slotModel.Name  = chosenName .. "_Slot_" .. chosenIndex
	slotModel.Parent = _activeSlotsFolder

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
				local bbCF, bbSize = clone:GetBoundingBox()
				local pivotToBottom = clone:GetPivot().Position.Y - bbCF.Position.Y + bbSize.Y / 2
				clone:PivotTo(pad.CFrame * CFrame.new(0, pivotToBottom, 0))
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
			rp.Style               = Enum.ProximityPromptStyle.Custom
			rp.Enabled             = (i == 1)   -- only the first prompt is active initially
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
		doorPromptInstance.Style                 = Enum.ProximityPromptStyle.Custom
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

	-- Clear immediately so door/events can't double-fire
	_playerAssignment[player] = nil

	-- Teleport first — iris transition plays while the slot is still behind it
	TeleportToHub:FireClient(player, PlayerHouseManager.GetHouseCFrame(player))

	-- Delay destruction so the model persists through the transition (iris ~1s + buffer)
	local slotModel = assignment.slotModel
	local pool      = _pool[assignment.locationName]
	local slotIndex = assignment.slotIndex
	local locName   = assignment.locationName

	task.delay(4, function()
		if slotModel and slotModel.Parent then slotModel:Destroy() end
		if pool then pool[slotIndex] = nil end
	end)

	print(("[LocationManager] Released %s from %s Slot_%d"):format(
		player.Name, locName, slotIndex
	))
end

-- ── Auto-release on disconnect ─────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	local assignment = _playerAssignment[player]
	if not assignment then return end
	-- Player is gone — no teleport needed, just destroy the slot clone
	if assignment.slotModel and assignment.slotModel.Parent then
		assignment.slotModel:Destroy()
	end
	local pool = _pool[assignment.locationName]
	if pool then pool[assignment.slotIndex] = nil end
	_playerAssignment[player] = nil
	print(("[LocationManager] Cleaned up slot for disconnected player %s"):format(player.Name))
end)

-- ── FurniturePieceRepaired: swap damaged clone → Default model ────────────

FurniturePieceRepaired.OnServerEvent:Connect(function(player, pieceIndex)
	local assignment = _playerAssignment[player]
	if not assignment then return end
	if type(pieceIndex) ~= "number" then return end

	-- Capture colors before destroying the damaged clone
	local fabricColor, frameColor
	local damagedClone = assignment.clones[pieceIndex]
	if damagedClone and damagedClone.Parent then
		for _, desc in ipairs(damagedClone:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc.Name == "FabricPart" and not fabricColor then
					fabricColor = desc.Color
				elseif desc.Name == "FramePart" and not frameColor then
					frameColor = desc.Color
				end
			end
		end
		damagedClone:Destroy()
	end
	assignment.clones[pieceIndex] = nil

	local furnitureKey = assignment.furnitureKeys[pieceIndex]
	if furnitureKey then
		local fixedClone = placeFurnitureDefault(assignment.slotModel, furnitureKey, pieceIndex)
		if fixedClone then
			for _, desc in ipairs(fixedClone:GetDescendants()) do
				if desc:IsA("BasePart") then
					if desc.Name == "FabricPart" and fabricColor then
						desc.Color = fabricColor
					elseif desc.Name == "FramePart" and frameColor then
						desc.Color = frameColor
					end
				end
			end
			assignment.fixedClones[pieceIndex] = fixedClone
		end
	end

	-- Enable the next RepairPrompt now that this piece is done
	local nextPrompt = assignment.repairPrompts[pieceIndex + 1]
	if nextPrompt and nextPrompt.Parent then
		nextPrompt.Enabled = true
	end
end)

return LocationManager
