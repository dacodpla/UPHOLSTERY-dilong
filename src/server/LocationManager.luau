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

-- SlotPhysicsService: lazy-required to avoid circular dependency.
-- LocationManager.Assign calls RegisterSlot; SlotPhysicsService lazily
-- requires us for HandlePieceRepaired.
local _slotPhysicsService = nil
local function getSlotPhysicsService()
	if not _slotPhysicsService then
		_slotPhysicsService = require(script.Parent:WaitForChild("SlotPhysicsService"))
	end
	return _slotPhysicsService
end

-- ── Internal state ────────────────────────────────────────────────────────

-- _pool[locationName][slotIndex] = player.UserId (occupied) or nil (free)
local _pool = {}

-- _slotCounts[locationName] = number of Slot_N templates discovered
local _slotCounts = {}

-- _locationsByTier[tier] = { locationName, ... }  — kept for admin/generator APIs; not used for slot selection
local _locationsByTier = {}

-- _maxFurniture[locationName] = number  — MaxFurniture attribute on the location folder.
-- If the slot has more Repairable models than this, a random subset is chosen per job.
local _maxFurniture = {}

-- _bespokeOnlyLocations[locationName] = true  — set BespokeOnly (bool) attribute on the folder
-- These locations are excluded from procedural job assignment; only reachable via locationOverride
local _bespokeOnlyLocations = {}

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
-- Discovers locations dynamically from ServerStorage.
-- Optional folder attributes:
--   Tier         (string)  — gates which jobs can use this location (Starter/Mid/Premium/…).
--   MaxFurniture (number)  — caps how many Repairable pieces are used per job; excess are
--                            chosen randomly so every visit feels different.
--   BespokeOnly  (bool)    — excludes this location from procedural job assignment.
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

				local maxFurniture = locationFolder:GetAttribute("MaxFurniture")
				if type(maxFurniture) == "number" and maxFurniture > 0 then
					_maxFurniture[locationFolder.Name] = math.floor(maxFurniture)
				end

				if locationFolder:GetAttribute("BespokeOnly") == true then
					_bespokeOnlyLocations[locationFolder.Name] = true
				end

				print(("[LocationManager] Registered '%s' (Tier: %s, %d slots, MaxFurniture: %s%s)"):format(
					locationFolder.Name, tier, slotCount,
					_maxFurniture[locationFolder.Name] and tostring(_maxFurniture[locationFolder.Name]) or "unlimited",
					_bespokeOnlyLocations[locationFolder.Name] and ", BespokeOnly" or ""))
			else
				warn(("[LocationManager] '%s' has no Slot_N models — skipping"):format(locationFolder.Name))
			end
		end
	end
end

-- ── Helpers ───────────────────────────────────────────────────────────────

-- Returns a pure-rotation CFrame for a tagged origin Model.
-- Priority order:
--   1. PrimaryPart.CFrame           — set a PrimaryPart in Studio for reliable visual rotation
--   2. RotationY attribute (degrees) — lightweight fallback if no PrimaryPart; Y-axis only
--   3. First BasePart.CFrame        — last resort; works if the model's parts are individually rotated
local function getOriginCF(model: Model): CFrame
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	local rotY = model:GetAttribute("RotationY")
	if type(rotY) == "number" then
		local bbCF = model:GetBoundingBox()
		return bbCF * CFrame.Angles(0, math.rad(rotY), 0)
	end
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	return firstPart and firstPart.CFrame or model:GetPivot()
end

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

function LocationManager.GetLocationsByTier()
	local result = {}
	for tier, names in pairs(_locationsByTier) do
		result[tier] = table.clone(names)
	end
	return result
end

-- Returns the first furniture key actually placed in the player's current slot.
-- For tag-based slots this reflects the Repairable model's FurnitureKey attribute,
-- not job.furniture which may be a generic placeholder set by RadiantJobGenerator.
function LocationManager.GetActualFurnitureKey(player)
	local assignment = _playerAssignment[player]
	if not assignment then return nil end
	return assignment.furnitureKeys and assignment.furnitureKeys[1] or nil
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

	-- Collect every free slot across locations that match this job's tier.
	local tierNames = _locationsByTier[job.tier]
	if not tierNames or #tierNames == 0 then
		warn("[LocationManager] No locations registered for tier:", job.tier)
		LocationFull:FireClient(player)
		return false
	end

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

	-- Procedural jobs skip BespokeOnly locations (reserved for bespoke jobs via locationOverride)
	if not job.locationOverride then
		local filtered = {}
		for _, slot in ipairs(freeSlots) do
			if not _bespokeOnlyLocations[slot.name] then
				table.insert(filtered, slot)
			end
		end
		if #filtered > 0 then
			freeSlots = filtered
		end
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

	-- Build the repair target list. Two modes:
	--   Tag-based : slot template has Models with Repairable=true attribute (position-accurate, no FurniturePad needed).
	--   Pad-based : job.furniture has entries → clone from ServerStorage onto FurniturePad_N.
	local repairableModels = {}
	for _, desc in ipairs(slotModel:GetDescendants()) do
		if desc:IsA("Model") and desc:GetAttribute("Repairable") == true then
			table.insert(repairableModels, desc)
		end
	end
	local isTagBased      = #repairableModels > 0
	local cloneList         = {}
	local taggedModelsList  = {}
	local furnitureKeysList = {}

	if isTagBased then
		local cap = _maxFurniture[chosenName]

		local selectedModels
		if cap and #repairableModels > cap then
			-- Fisher-Yates shuffle on a copy, then take the first `cap` entries
			local shuffled = table.clone(repairableModels)
			for i = #shuffled, 2, -1 do
				local j = math.random(i)
				shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
			end
			selectedModels = {}
			for i = 1, cap do
				selectedModels[i] = shuffled[i]
			end
		else
			selectedModels = repairableModels
		end

		-- Sort the selected subset by RepairOrder (lower = first), then by Name for stability
		table.sort(selectedModels, function(a, b)
			local oa = a:GetAttribute("RepairOrder") or 999
			local ob = b:GetAttribute("RepairOrder") or 999
			if oa ~= ob then return oa < ob end
			return a.Name < b.Name
		end)

		local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
		local maxPieces = #selectedModels  -- location defines piece count; client falls back to minigames[1] for extra pieces

		for i = 1, maxPieces do
			local taggedModel  = selectedModels[i]
			local furnitureKey = taggedModel:GetAttribute("FurnitureKey")

			if not furnitureKey then
				warn(("[LocationManager]   Repairable '%s' has no FurnitureKey — skipping piece %d"):format(taggedModel.Name, i))
				continue
			end

			local typeFolder = furnitureFolder and furnitureFolder:FindFirstChild(furnitureKey)
			if not typeFolder then
				warn("[LocationManager]   FurnitureModels/" .. furnitureKey .. " not found — skipping piece " .. i)
				continue
			end

			-- Position the damage clone at the tagged model's bounding-box base.
			-- GetBoundingBox() gives us the AABB center (reliable X/Y/Z) independent of PrimaryPart.
			-- getOriginCF() gives us the actual Studio rotation via PrimaryPart or first BasePart.
			local bbCF, tagSize = taggedModel:GetBoundingBox()
			local tagBaseY      = bbCF.Position.Y - tagSize.Y / 2
			local originCF      = getOriginCF(taggedModel)
			local tagRotation   = CFrame.fromMatrix(Vector3.zero, originCF.XVector, originCF.YVector, originCF.ZVector)

			local variants = getDamagedVariants(typeFolder)
			if #variants == 0 then
				warn("[LocationManager]   No Damaged variants in FurnitureModels/" .. furnitureKey)
				continue
			end

			local clone = pickRandom(variants):Clone()
			clone.Parent = slotModel
			local _, dmgSize = clone:GetBoundingBox()
			clone:PivotTo(CFrame.new(bbCF.X, tagBaseY + dmgSize.Y / 2, bbCF.Z) * tagRotation)
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then part.Anchored = true end
			end
			if taggedModel:GetAttribute("RandomColor") == true then
				colorizeClone(clone)
			end

			-- Hide the tagged model while the damage clone is shown
			for _, part in ipairs(taggedModel:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Transparency = 1
					part.CanCollide   = false
				end
			end

			table.insert(cloneList,         clone)
			table.insert(taggedModelsList,  taggedModel)
			table.insert(furnitureKeysList, furnitureKey)

			local anchor = clone.PrimaryPart
			if not anchor then
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then anchor = part; break end
				end
			end
			print(("[LocationManager]   Tag piece %d '%s' → %s"):format(i, furnitureKey, taggedModel.Name))
		end
	else
		-- Pad-based: clone Damaged_X variants from ServerStorage onto FurniturePad_N
		local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
		for i, furnitureKey in ipairs(job.furniture) do
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
					if pad:GetAttribute("RandomColor") == true then
						colorizeClone(clone)
					end
					table.insert(cloneList, clone)
				else
					warn("[LocationManager] No damage variants in", furnitureKey)
				end
			end
		end
	end

	-- Add DoorPrompt to the Handle part inside the Door model so player can exit or abandon
	local doorModel = slotModel:FindFirstChild("Door", true)
	local doorHandle = doorModel and doorModel:FindFirstChild("Handle")
	local doorPromptInstance = nil
	if doorHandle and doorHandle:IsA("BasePart") then
		doorPromptInstance = Instance.new("ProximityPrompt")
		doorPromptInstance.Name                  = "DoorPrompt"
		doorPromptInstance.ActionText            = "Leave"
		doorPromptInstance.ObjectText            = "Exit"
		doorPromptInstance.MaxActivationDistance = 8
		doorPromptInstance.Style                 = Enum.ProximityPromptStyle.Custom
		doorPromptInstance.Parent                = doorHandle
	else
		warn("[LocationManager] No 'Door/Handle' BasePart in slot — exit prompt skipped")
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
		furnitureKeys = isTagBased and furnitureKeysList or (job.furniture or {}),
		taggedModels  = taggedModelsList,
		doorPrompt    = doorPromptInstance,
		tagBased      = isTagBased,
	}

	-- Register the slot with the physics service so drop detection and state machines run.
	local spawnPad = slotModel:FindFirstChild("SpawnPad", true)
	local spawnCF  = spawnPad and spawnPad.CFrame or slotModel:GetPivot()

	local piecesForPhysics = {}
	for i, clone in ipairs(cloneList) do
		piecesForPhysics[i] = { clone = clone }
	end

	getSlotPhysicsService().RegisterSlot(player, {
		job             = job,
		pieces          = piecesForPhysics,
		spawnCF         = spawnCF,
		onPieceComplete = function(pieceIndex)
			LocationManager.HandlePieceRepaired(player, pieceIndex)
		end,
	})

	-- Teleport player; send full clone list so client can build the checklist HUD
	TeleportToLocation:FireClient(player, spawnCF, job, cloneList, chosenName)

	print(("[LocationManager] Assigned %s → %s Slot_%d"):format(player.Name, chosenName, chosenIndex))
	return true
end

-- HandlePieceRepaired is called both by SlotPhysicsService (physics workflow)
-- and by FurniturePieceRepaired.OnServerEvent (legacy path, kept for compatibility).
function LocationManager.HandlePieceRepaired(player, pieceIndex)
	local assignment = _playerAssignment[player]
	if not assignment then return end
	if type(pieceIndex) ~= "number" then return end

	local fabricColor, frameColor
	local damagedClone = assignment.clones[pieceIndex]
	if damagedClone and damagedClone.Parent then
		for _, desc in ipairs(damagedClone:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc.Name == "FabricPart" and not fabricColor then fabricColor = desc.Color end
				if desc.Name == "FramePart"  and not frameColor  then frameColor  = desc.Color end
			end
		end
		damagedClone:Destroy()
	end
	assignment.clones[pieceIndex] = nil

	local furnitureKey = assignment.furnitureKeys[pieceIndex]
	if not furnitureKey then return end

	local function applyColors(model)
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc.Name == "FabricPart" and fabricColor then desc.Color = fabricColor end
				if desc.Name == "FramePart"  and frameColor  then desc.Color = frameColor  end
			end
		end
	end

	if assignment.tagBased then
		local furnitureFolder = ServerStorage:FindFirstChild("FurnitureModels")
		local typeFolder      = furnitureFolder and furnitureFolder:FindFirstChild(furnitureKey)
		local defaultModel    = typeFolder and typeFolder:FindFirstChild("Default")
		if not defaultModel then
			warn("[LocationManager] No 'Default' model in FurnitureModels/" .. furnitureKey)
			return
		end
		local fixedClone = defaultModel:Clone()
		fixedClone.Parent = assignment.slotModel
		local taggedModel = assignment.taggedModels and assignment.taggedModels[pieceIndex]
		if taggedModel then
			local bbCF, tagSize = taggedModel:GetBoundingBox()
			local tagBaseY      = bbCF.Position.Y - tagSize.Y / 2
			local originCF      = getOriginCF(taggedModel)
			local tagRotation   = CFrame.fromMatrix(Vector3.zero, originCF.XVector, originCF.YVector, originCF.ZVector)
			local _, fixSize    = fixedClone:GetBoundingBox()
			fixedClone:PivotTo(CFrame.new(bbCF.X, tagBaseY + fixSize.Y / 2, bbCF.Z) * tagRotation)
		end
		for _, desc in ipairs(fixedClone:GetDescendants()) do
			if desc:IsA("BasePart") then desc.Anchored = true end
		end
		applyColors(fixedClone)
		assignment.fixedClones[pieceIndex] = fixedClone
	else
		local fixedClone = placeFurnitureDefault(assignment.slotModel, furnitureKey, pieceIndex)
		if fixedClone then
			applyColors(fixedClone)
			assignment.fixedClones[pieceIndex] = fixedClone
		end
	end
end

function LocationManager.Release(player)
	local assignment = _playerAssignment[player]
	if not assignment then return end

	-- Clear immediately so door/events can't double-fire
	_playerAssignment[player] = nil

	-- Unregister the physics slot so the heartbeat stops scanning for this player
	getSlotPhysicsService().UnregisterSlot(player)

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
	_playerAssignment[player] = nil
	getSlotPhysicsService().UnregisterSlot(player)
	-- Player is gone — no teleport needed, just destroy the slot clone
	if assignment.slotModel and assignment.slotModel.Parent then
		assignment.slotModel:Destroy()
	end
	local pool = _pool[assignment.locationName]
	if pool then pool[assignment.slotIndex] = nil end
	print(("[LocationManager] Cleaned up slot for disconnected player %s"):format(player.Name))
end)

-- ── FurniturePieceRepaired: legacy remote path — delegates to HandlePieceRepaired ─

FurniturePieceRepaired.OnServerEvent:Connect(function(player, pieceIndex)
	LocationManager.HandlePieceRepaired(player, pieceIndex)
end)

return LocationManager
