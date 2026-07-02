--[[
	SlotPhysicsService
	Server module — owns the per-slot, per-furniture drop-detection state machines
	for the physics-based repair workflow.

	Each furniture piece in a slot progresses through a sequence of states driven by
	the player physically dropping the right tool near the furniture's bounding box:

	  Full workflow:
	    "NeedsTacks"  → drop TackRemover  → TackRemoval GUI minigame
	    "NeedsSponge" → drop Sponge       → snap (poof, no minigame)
	    "NeedsCloth"  → drop Cloth        → snap (poof, no minigame)
	    "NeedsFinish" → drop SewingNeedle (stitch) or StapleGun (staple) → GUI minigame
	    "Complete"    → LocationManager swaps damaged→default model

	  Half workflow:
	    Starts at "NeedsCloth" — skips tack-removal and sponge phases.

	All state is owned by this module. LocationManager registers/unregisters slots
	via RegisterSlot / UnregisterSlot.

	Grade is computed from elapsed time vs par time so individual minigame results
	don't affect the final score — only speed does.
]]

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local TweenService      = game:GetService("TweenService")

local GrabHandler = require(script.Parent.GrabHandler)
local GameConfig  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local remotesFolder               = ReplicatedStorage:WaitForChild("LaptopRemotes")
local StartMinigame               = remotesFolder:WaitForChild("StartMinigame")
local SofaStateChanged            = remotesFolder:WaitForChild("SofaStateChanged")
local PhysicsJobGrade             = remotesFolder:WaitForChild("PhysicsJobGrade")
local ReportPhysicsMinigameResult = remotesFolder:WaitForChild("ReportPhysicsMinigameResult")

local HEARTBEAT_RATE = 1 / 15   -- 15 Hz drop scan

local PhysCfg          = GameConfig.PhysicsWorkflow
local SNAP_RADIUS      = PhysCfg.snapRadius
local PAR_TIME         = PhysCfg.parTimeByTier
local GRADE_THRESHOLDS = PhysCfg.gradeThresholds

-- _slots[player] = {
--   job         = job table,
--   startTime   = os.clock(),
--   parTime     = number,
--   toolbox     = Model or nil,
--   toolboxConn = RBXScriptConnection or nil,
--   toolboxPrompt = ProximityPrompt or nil,
--   toolboxUnpacked = bool,
--   pieces = {
--     [i] = {
--       state      = string (NeedsTacks / NeedsSponge / NeedsCloth / NeedsFinish / Complete),
--       workflow   = "full" or "half",
--       finishType = "stitch" or "staple",
--       clone      = Model ref (the damaged furniture in workspace),
--       difficulty = string,
--       fragile    = bool,
--       pending    = bool (true while waiting for minigame result),
--     }
--   },
--   onPieceComplete = function(pieceIndex),  -- callback → LocationManager
-- }
local _slots = {}

-- ── Poof effect (server-side so it replicates to all) ─────────────────────────

local function spawnPoof(model)
	local cf, sz
	pcall(function() cf, sz = model:GetBoundingBox() end)
	if not cf then cf = model:GetPivot(); sz = Vector3.new(2, 1, 2) end
	local center = cf.Position
	local maxDim = math.max(sz.X, sz.Y, sz.Z)
	local minDim = math.min(sz.X, sz.Y, sz.Z)
	local rng    = Random.new()

	local COLORS = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(200, 235, 255),
		Color3.fromRGB(255, 235, 160),
		Color3.fromRGB(180, 255, 200),
		Color3.fromRGB(255, 200, 230),
	}

	local flash = Instance.new("Part")
	flash.Shape        = Enum.PartType.Ball
	flash.Size         = Vector3.new(minDim * 0.3, minDim * 0.3, minDim * 0.3)
	flash.Anchored     = true
	flash.CanCollide   = false
	flash.CastShadow   = false
	flash.Material     = Enum.Material.Neon
	flash.Color        = Color3.fromRGB(255, 255, 255)
	flash.Transparency = 0.1
	flash.Position     = center
	flash.Parent       = workspace
	TweenService:Create(flash,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(maxDim * 3, maxDim * 3, maxDim * 3), Transparency = 1 }
	):Play()
	task.delay(0.25, function() if flash.Parent then flash:Destroy() end end)

	for i = 1, 14 do
		local p = Instance.new("Part")
		p.Shape        = Enum.PartType.Ball
		p.Size         = Vector3.new(minDim * 0.25, minDim * 0.25, minDim * 0.25)
		p.Anchored     = true
		p.CanCollide   = false
		p.CastShadow   = false
		p.Material     = Enum.Material.SmoothPlastic
		p.Color        = COLORS[(i - 1) % #COLORS + 1]
		p.Transparency = 0.05
		p.Position     = center + Vector3.new(
			rng:NextNumber(-sz.X * 0.55, sz.X * 0.55),
			rng:NextNumber(-sz.Y * 0.3,  sz.Y * 0.5),
			rng:NextNumber(-sz.Z * 0.55, sz.Z * 0.55)
		)
		p.Parent = workspace
		local finalSize = maxDim * rng:NextNumber(0.8, 1.1)
		local drift = Vector3.new(
			rng:NextNumber(-sz.X * 0.7, sz.X * 0.7),
			rng:NextNumber(sz.Y * 0.9,  sz.Y * 2.2),
			rng:NextNumber(-sz.Z * 0.7, sz.Z * 0.7)
		)
		TweenService:Create(p,
			TweenInfo.new(rng:NextNumber(0.45, 0.65), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(finalSize, finalSize, finalSize), Transparency = 1, Position = p.Position + drift }
		):Play()
		task.delay(0.7, function() if p.Parent then p:Destroy() end end)
	end
end

-- ── Grade calculation ─────────────────────────────────────────────────────────

local function computeGrade(elapsed, parTime)
	if parTime <= 0 then return "Pass" end
	local ratio = elapsed / parTime
	if ratio <= GRADE_THRESHOLDS.Perfect then
		return "Perfect"
	elseif ratio <= GRADE_THRESHOLDS.Good then
		return "Good"
	elseif ratio <= GRADE_THRESHOLDS.Pass then
		return "Pass"
	else
		return "Fail"
	end
end

-- ── State helpers ─────────────────────────────────────────────────────────────

local function getInitialState(workflow)
	return workflow == "half" and "NeedsCloth" or "NeedsTacks"
end

local function getExpectedTool(piece)
	local state      = piece.state
	local finishType = piece.finishType
	if state == "NeedsTacks"  then return "TackRemover",  "minigame_TackRemoval"   end
	if state == "NeedsSponge" then return "Sponge",       "snap"                   end
	if state == "NeedsCloth"  then return "Cloth",        "snap"                   end
	if state == "NeedsFinish" then
		if finishType == "staple" then
			return "StapleGun",     "minigame_StapleGunning"
		else
			return "SewingNeedle",  "minigame_SeamStitching"
		end
	end
	return nil, nil
end

local function nextState(currentState, workflow)
	if currentState == "NeedsTacks"  then return "NeedsSponge" end
	if currentState == "NeedsSponge" then return "NeedsCloth"  end
	if currentState == "NeedsCloth"  then return "NeedsFinish" end
	if currentState == "NeedsFinish" then return "Complete"    end
	return "Complete"
end

-- ── Toolbox spawning ──────────────────────────────────────────────────────────

local SPAWN_OFFSETS = {
	Vector3.new(-2.0, 0.5, 1.5),
	Vector3.new(-0.7, 0.5, 2.0),
	Vector3.new( 0.7, 0.5, 2.0),
	Vector3.new( 2.0, 0.5, 1.5),
	Vector3.new(-1.5, 0.5, -1.5),
	Vector3.new( 1.5, 0.5, -1.5),
}

local function buildToolList(slotData)
	local job    = slotData.job
	local tools  = {}
	local base   = PhysCfg.toolsByWorkflow[job.workflow or "full"] or PhysCfg.toolsByWorkflow.full
	local finish = (job.finishType == "staple") and "StapleGun" or "SewingNeedle"
	local count  = #slotData.pieces

	for _ = 1, count do
		for _, toolName in ipairs(base) do
			table.insert(tools, toolName)
		end
		table.insert(tools, finish)
	end
	return tools
end

local function spawnTools(basePos, tools)
	local spawned = {}
	for i, toolName in ipairs(tools) do
		local template = ServerStorage:FindFirstChild(toolName)
		if not template then
			warn("[SlotPhysicsService] ServerStorage." .. toolName .. " not found — skipping")
			continue
		end
		local clone = template:Clone()
		local offset = SPAWN_OFFSETS[(i - 1) % #SPAWN_OFFSETS + 1]
		clone:PivotTo(CFrame.new(basePos + offset))
		clone.Parent = workspace
		table.insert(spawned, clone)
	end
	return spawned
end

local function setupToolbox(player, slotData, spawnCF)
	local template = ServerStorage:FindFirstChild("Toolbox")
	if not template then
		-- No Toolbox model in ServerStorage — spawn tools directly instead
		warn("[SlotPhysicsService] Toolbox not found in ServerStorage — spawning tools directly")
		spawnTools(spawnCF.Position, buildToolList(slotData))
		slotData.toolboxUnpacked = true
		return
	end

	local toolbox = template:Clone()
	toolbox:PivotTo(spawnCF * CFrame.new(0, 0.5, -3))  -- in front of player (-Z = forward)
	toolbox.Parent = workspace
	slotData.toolbox        = toolbox
	slotData.toolboxUnpacked = false

	-- Gold outline so the player sees the toolbox immediately on arrival
	local hl = Instance.new("Highlight")
	hl.FillTransparency    = 1
	hl.OutlineColor        = Color3.fromRGB(255, 210, 60)
	hl.OutlineTransparency = 0
	hl.Parent              = toolbox
end

-- ── All-complete check ────────────────────────────────────────────────────────

local function checkAllComplete(player, slotData)
	for _, piece in ipairs(slotData.pieces) do
		if piece.state ~= "Complete" then return end
	end

	-- All pieces done — compute grade from elapsed time
	local elapsed = os.clock() - slotData.startTime
	local grade   = computeGrade(elapsed, slotData.parTime)

	PhysicsJobGrade:FireClient(player, grade)
	print(("[SlotPhysicsService] %s completed all pieces in %.1fs (par %.1fs) → %s"):format(
		player.Name, elapsed, slotData.parTime, grade))
end

-- ── Piece state advancement ───────────────────────────────────────────────────

local function advancePiece(player, slotData, pieceIdx, piece)
	piece.state   = nextState(piece.state, piece.workflow)
	piece.pending = false

	SofaStateChanged:FireClient(player, pieceIdx, piece.state)

	if piece.state == "Complete" then
		-- Tell LocationManager to swap the damaged model for the Default model
		slotData.onPieceComplete(pieceIdx)
		checkAllComplete(player, slotData)
	end
end

-- ── Tool drop handler ─────────────────────────────────────────────────────────

local function handleToolDrop(player, slotData, pieceIdx, piece, entity, action)
	CollectionService:RemoveTag(entity, "Grabbable")
	spawnPoof(entity)
	entity:Destroy()

	if action == "snap" then
		advancePiece(player, slotData, pieceIdx, piece)
	else
		-- action = "minigame_TackRemoval" / "minigame_SeamStitching" / "minigame_StapleGunning"
		local minigameName = action:sub(10)  -- strip "minigame_"
		piece.pending = true

		-- Capture active perk effects from PerkSystem (best-effort)
		local activeEffects = nil
		local PerkSystem = pcall(function()
			local ps = require(script.Parent.PerkSystem)
			activeEffects = ps.GetActiveEffects(player)
		end)

		StartMinigame:FireClient(player, pieceIdx, minigameName, {
			fragile       = piece.fragile,
			toolBonus     = 0,
			difficulty    = piece.difficulty,
			activeEffects = activeEffects,
		})
	end
end

-- ── Toolbox hold detection (heartbeat sub-task) ───────────────────────────────

local function tickToolbox(player, slotData)
	if slotData.toolboxUnpacked then return end
	local toolbox = slotData.toolbox
	if not toolbox or not toolbox.Parent then return end

	local heldEntity = GrabHandler.GetHeldEntity(player)
	if heldEntity ~= toolbox then
		-- Player not holding toolbox — disable prompt if it exists
		if slotData.toolboxPrompt then
			slotData.toolboxPrompt.Enabled = false
		end
		return
	end

	-- Player IS holding the toolbox — create prompt if needed
	if not slotData.toolboxPrompt then
		-- Support both Model (with PrimaryPart) and bare BasePart templates
		local anchor
		if toolbox:IsA("BasePart") then
			anchor = toolbox
		else
			anchor = toolbox.PrimaryPart or toolbox:FindFirstChildWhichIsA("BasePart")
		end
		if not anchor then return end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText           = "Unpack"
		prompt.ObjectText           = "Toolbox"
		prompt.HoldDuration         = 0
		prompt.KeyboardKeyCode      = Enum.KeyCode.F
		prompt.Style                = Enum.ProximityPromptStyle.Custom
		prompt.RequiresLineOfSight  = false
		prompt.Parent               = anchor
		slotData.toolboxPrompt      = prompt

		prompt.Triggered:Connect(function(trigPlayer)
			if trigPlayer ~= player then return end
			if slotData.toolboxUnpacked then return end
			slotData.toolboxUnpacked = true
			prompt:Destroy()
			slotData.toolboxPrompt = nil

			GrabHandler.ForceRelease(player)

			local basePos = toolbox:IsA("BasePart")
				and toolbox.CFrame.Position
				or  toolbox:GetPivot().Position
			spawnPoof(toolbox)
			toolbox:Destroy()
			slotData.toolbox = nil

			spawnTools(basePos, buildToolList(slotData))
		end)
	end

	slotData.toolboxPrompt.Enabled = true
end

-- ── 15 Hz drop-detection heartbeat ───────────────────────────────────────────

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < HEARTBEAT_RATE then return end
	acc = 0

	-- Build held-entity set so we skip items currently being carried
	local heldEntities = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local e = GrabHandler.GetHeldEntity(p)
		if e then heldEntities[e] = true end
	end

	for player, slotData in pairs(_slots) do
		-- Toolbox sub-tick
		tickToolbox(player, slotData)

		-- Per-piece drop detection
		for pieceIdx, piece in ipairs(slotData.pieces) do
			if piece.state == "Complete" or piece.pending then continue end

			local clone = piece.clone
			if not clone or not clone.Parent then continue end

			local clonePos
			pcall(function()
				local bbCF, _ = clone:GetBoundingBox()
				clonePos = bbCF.Position
			end)
			if not clonePos then continue end

			local expectedTool, action = getExpectedTool(piece)
			if not expectedTool then continue end

			for _, entity in ipairs(CollectionService:GetTagged("Grabbable")) do
				if heldEntities[entity] then continue end
				if entity.Name ~= expectedTool then continue end

				local ePos
				pcall(function() ePos = entity:GetPivot().Position end)
				if not ePos then continue end

				if (ePos - clonePos).Magnitude > SNAP_RADIUS then continue end

				-- Verify this tool was last held by the slot's player
				local lastHolder = GrabHandler.GetLastHolder(entity)
				if lastHolder ~= player then continue end

				handleToolDrop(player, slotData, pieceIdx, piece, entity, action)
				break  -- one tool per piece per tick
			end
		end
	end
end)

-- ── Minigame result from client ───────────────────────────────────────────────
-- The client fires this after MinigameRunner.Run() completes (pass OR fail).
-- State always advances regardless of result — speed is the grading lever.

ReportPhysicsMinigameResult.OnServerEvent:Connect(function(player, pieceIdx)
	local slotData = _slots[player]
	if not slotData then return end
	if type(pieceIdx) ~= "number" then return end

	local piece = slotData.pieces[pieceIdx]
	if not piece or not piece.pending then return end

	advancePiece(player, slotData, pieceIdx, piece)
end)

-- ── Public API ────────────────────────────────────────────────────────────────

local SlotPhysicsService = {}

--[[
	RegisterSlot — called by LocationManager.Assign after furniture clones exist.

	slotData = {
	  job            = job table (needs .workflow, .finishType, .difficulty, .fragile, .tier),
	  pieces         = { [i] = { clone = Model } },   -- only clone is required; rest filled here
	  spawnCF        = CFrame of the SpawnPad,
	  onPieceComplete = function(pieceIndex),          -- callback to LocationManager
	}
]]
function SlotPhysicsService.RegisterSlot(player, slotData)
	if _slots[player] then
		SlotPhysicsService.UnregisterSlot(player)
	end

	local job = slotData.job
	local physPieces = {}
	for i, pieceInfo in ipairs(slotData.pieces) do
		physPieces[i] = {
			state      = getInitialState(job.workflow or "full"),
			workflow   = job.workflow   or "full",
			finishType = job.finishType or "stitch",
			clone      = pieceInfo.clone,
			difficulty = job.difficulty or "Easy",
			fragile    = job.fragile    == true,
			pending    = false,
		}
		-- Notify client of initial state so the checklist renders correctly
		SofaStateChanged:FireClient(player, i, physPieces[i].state)
	end

	local baseParTime = (PAR_TIME[job.tier] or PAR_TIME.Starter)
	local totalParTime = baseParTime * #physPieces

	local slot = {
		job             = job,
		startTime       = os.clock(),
		parTime         = totalParTime,
		toolbox         = nil,
		toolboxPrompt   = nil,
		toolboxUnpacked = false,
		pieces          = physPieces,
		onPieceComplete = slotData.onPieceComplete,
	}
	_slots[player] = slot

	-- Spawn toolbox near SpawnPad
	setupToolbox(player, slot, slotData.spawnCF)

	print(("[SlotPhysicsService] Registered slot for %s — %d piece(s), workflow=%s, finishType=%s, parTime=%.0fs"):format(
		player.Name, #physPieces, job.workflow or "full", job.finishType or "stitch", totalParTime))
end

function SlotPhysicsService.UnregisterSlot(player)
	local slot = _slots[player]
	if not slot then return end

	-- Clean up toolbox if not yet unpacked
	if slot.toolbox and slot.toolbox.Parent then
		slot.toolbox:Destroy()
	end

	_slots[player] = nil
end

return SlotPhysicsService
