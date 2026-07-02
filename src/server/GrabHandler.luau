-- src/server/GrabHandler.luau

local Players           = game:GetService("Players")
local PhysicsService    = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("GrabConfig"))
local Remotes = require(Shared:WaitForChild("GrabRemotes")).Get()

-- grabState[userId] = {
--   player, heldPart, originalCollisionGroups,
--   ancestryConn, unanchoredParts
-- }
local grabState    = {}
local lastGrabTime = {}
local lastHolder   = {}   -- [entity] = player, updated on every release / throw

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Returns (physicsRoot, taggedEntity).
-- physicsRoot  = the BasePart to drive with velocity.
-- taggedEntity = the Model or BasePart that actually carries the Grabbable tag;
--                used to scope unanchoring so we NEVER touch anything outside it.
local function resolveGrabbable(hitPart)
	if CollectionService:HasTag(hitPart, Config.GRABBABLE_TAG) then
		return hitPart, hitPart
	end
	local current = hitPart.Parent
	while current do
		if current:IsA("Model") and CollectionService:HasTag(current, Config.GRABBABLE_TAG) then
			local root = current.PrimaryPart
				or current:FindFirstChildWhichIsA("BasePart")
				or hitPart
			return root, current
		end
		current = current.Parent
	end
	return nil, nil
end

local function applyPlayerCollisionGroup(character)
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = Config.GROUP_PLAYERS
		end
	end
	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CollisionGroup = Config.GROUP_PLAYERS
		end
	end)
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

local function recordLastHolder(entry, player)
	pcall(function()
		local part   = entry.heldPart
		local parent = part and part.Parent
		if part   then lastHolder[part]   = player end
		if parent and parent:IsA("Model") and not parent:IsA("WorldRoot") then
			lastHolder[parent] = player
		end
	end)
end

local function cleanupPlayer(player)
	local entry = grabState[player.UserId]
	if not entry then return end

	recordLastHolder(entry, player)

	pcall(function() entry.ancestryConn:Disconnect() end)

	for part, origGroup in pairs(entry.originalCollisionGroups) do
		pcall(function() part.CollisionGroup = origGroup end)
	end

	for _, part in ipairs(entry.unanchoredParts) do
		pcall(function() part:SetNetworkOwner(nil) end)
	end

	grabState[player.UserId] = nil
end

-- ── Request Handlers ──────────────────────────────────────────────────────────

local function onRequestGrab(player, hitPart)
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then return end

	local userId = player.UserId

	if grabState[userId] then
		Remotes.GrabFailed:FireClient(player, "AlreadyHolding")
		return
	end

	local now = tick()
	if lastGrabTime[userId] and (now - lastGrabTime[userId]) < Config.GRAB_COOLDOWN then
		Remotes.GrabFailed:FireClient(player, "Cooldown")
		return
	end
	lastGrabTime[userId] = now

	local resolved, grabbableEntity = resolveGrabbable(hitPart)
	if not resolved then
		Remotes.GrabFailed:FireClient(player, "NotGrabbable")
		return
	end

	for _, entry in pairs(grabState) do
		if entry.heldPart == resolved then
			Remotes.GrabFailed:FireClient(player, "AlreadyHeld")
			return
		end
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		Remotes.GrabFailed:FireClient(player, "NotAlive")
		return
	end

	if (hrp.Position - resolved.Position).Magnitude > Config.MAX_GRAB_DISTANCE_SVR then
		Remotes.GrabFailed:FireClient(player, "TooFar")
		return
	end

	if resolved.AssemblyMass > Config.MAX_OBJECT_MASS then
		Remotes.GrabFailed:FireClient(player, "TooHeavy")
		return
	end

	local unanchoredParts = {}
	if grabbableEntity then
		if grabbableEntity:IsA("Model") then
			for _, desc in ipairs(grabbableEntity:GetDescendants()) do
				if desc:IsA("BasePart") and desc.Anchored then
					desc.Anchored = false
					table.insert(unanchoredParts, desc)
				end
			end
		elseif grabbableEntity:IsA("BasePart") and grabbableEntity.Anchored then
			grabbableEntity.Anchored = false
			table.insert(unanchoredParts, grabbableEntity)
		end
	end

	local originalCollisionGroups = {}
	local entityParts = {}
	if grabbableEntity then
		if grabbableEntity:IsA("Model") then
			for _, desc in ipairs(grabbableEntity:GetDescendants()) do
				if desc:IsA("BasePart") then
					table.insert(entityParts, desc)
				end
			end
		elseif grabbableEntity:IsA("BasePart") then
			table.insert(entityParts, grabbableEntity)
		end
	end
	for _, part in ipairs(entityParts) do
		originalCollisionGroups[part] = part.CollisionGroup
		part.CollisionGroup = Config.GROUP_HELD
	end

	local anyOwned = false
	for _, part in ipairs(unanchoredParts) do
		local ok = pcall(function() part:SetNetworkOwner(player) end)
		if ok then anyOwned = true end
	end
	local ok = pcall(function() resolved:SetNetworkOwner(player) end)
	if ok then anyOwned = true end

	if not anyOwned then
		for _, part in ipairs(unanchoredParts) do
			pcall(function() part.Anchored = true end)
		end
		for part, origGroup in pairs(originalCollisionGroups) do
			pcall(function() part.CollisionGroup = origGroup end)
		end
		Remotes.GrabFailed:FireClient(player, "PhysicsError")
		return
	end

	local ancestryConn
	ancestryConn = resolved.AncestryChanged:Connect(function()
		if not resolved:IsDescendantOf(workspace) then
			ancestryConn:Disconnect()
			cleanupPlayer(player)
			Remotes.ReleaseConfirmed:FireClient(player)
		end
	end)

	grabState[userId] = {
		player                  = player,
		heldPart                = resolved,
		originalCollisionGroups = originalCollisionGroups,
		ancestryConn            = ancestryConn,
		unanchoredParts         = unanchoredParts,
	}

	Remotes.GrabConfirmed:FireClient(player, resolved)
end

local function onRequestRelease(player)
	if not grabState[player.UserId] then return end
	cleanupPlayer(player)
	Remotes.ReleaseConfirmed:FireClient(player)
end

local function onRequestThrow(player, throwDir)
	local entry = grabState[player.UserId]
	if not entry then return end

	local dir = Vector3.new(0, 0, -1)
	if typeof(throwDir) == "Vector3"
		and throwDir.Magnitude > 0.001
		and throwDir.X == throwDir.X
	then
		dir = throwDir.Unit
	end

	local heldPart                = entry.heldPart
	local unanchoredParts         = entry.unanchoredParts
	local originalCollisionGroups = entry.originalCollisionGroups
	local speed                   = Config.THROW_SPEED

	recordLastHolder(entry, player)
	pcall(function() entry.ancestryConn:Disconnect() end)
	for part, origGroup in pairs(originalCollisionGroups) do
		pcall(function() part.CollisionGroup = origGroup end)
	end
	grabState[player.UserId] = nil

	for _, part in ipairs(unanchoredParts) do
		pcall(function() part:SetNetworkOwner(nil) end)
	end
	pcall(function() heldPart:SetNetworkOwner(nil) end)
	pcall(function() heldPart.AssemblyLinearVelocity = dir * speed end)

	Remotes.ThrowConfirmed:FireClient(player)
end

-- ── Public API ────────────────────────────────────────────────────────────────

local GrabHandler = {}

function GrabHandler.Init()
	pcall(function() PhysicsService:RegisterCollisionGroup(Config.GROUP_PLAYERS) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(Config.GROUP_HELD) end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(Config.GROUP_PLAYERS, Config.GROUP_HELD, false)
	end)

	local function onCharacterAdded(character)
		applyPlayerCollisionGroup(character)
	end

	local function onPlayerAdded(player)
		if player.Character then onCharacterAdded(player.Character) end
		player.CharacterAdded:Connect(onCharacterAdded)
		player.CharacterRemoving:Connect(function()
			if grabState[player.UserId] then
				cleanupPlayer(player)
				Remotes.ReleaseConfirmed:FireClient(player)
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		for entity, p in pairs(lastHolder) do
			if p == player then lastHolder[entity] = nil end
		end
		task.delay(Config.DISCONNECT_DELAY, function()
			cleanupPlayer(player)
			lastGrabTime[player.UserId] = nil
		end)
	end)

	Remotes.RequestGrab.OnServerEvent:Connect(onRequestGrab)
	Remotes.RequestRelease.OnServerEvent:Connect(onRequestRelease)
	Remotes.RequestThrow.OnServerEvent:Connect(onRequestThrow)
end

function GrabHandler.GetHeldEntity(player)
	local entry = grabState[player.UserId]
	if not entry then return nil end
	local part   = entry.heldPart
	local parent = part.Parent
	if parent and parent:IsA("Model") and not parent:IsA("WorldRoot") then
		return parent
	end
	return part
end

function GrabHandler.GetLastHolder(entity)
	return lastHolder[entity]
end

function GrabHandler.GetHolderOfPart(part)
	for _, entry in pairs(grabState) do
		if entry.heldPart == part or entry.heldPart.Parent == part then
			return entry.player
		end
	end
	return nil
end

function GrabHandler.ForceRelease(player)
	if not grabState[player.UserId] then return end
	cleanupPlayer(player)
	Remotes.ReleaseConfirmed:FireClient(player)
end

return GrabHandler
