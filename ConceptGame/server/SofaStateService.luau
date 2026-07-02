--[[
	SofaStateService
	Owns the server-authoritative sofa repair state machine.

	States per sofa:
	  0 DAMAGED      — waiting for TackRemover to be dropped on the cushion
	  1 STRIPPED     — waiting for Sponge to be dropped on the cushion
	  2 FOAM_PLACED  — waiting for Cloth to be dropped on the cushion
	  3 CLOTH_PLACED — waiting for SewingNeedle to be dropped on the cushion
	  4 COMPLETE     — SofaDamaged destroyed, SofaClean cloned in place

	All tool interactions are triggered by dropping (not holding) the item near
	the sofa cushion. Sponge/Cloth poof and are destroyed immediately on landing.
	TackRemover/SewingNeedle start a minigame; they poof on success, stay on fail
	so the player can pick them up and try again.
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local GrabHandler    = require(script.Parent.GrabHandler)
local JobService     = require(script.Parent.JobService)
local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))
local ConceptConfig  = require(Shared:WaitForChild("ConceptConfig"))

-- sofaStates[sofaModel] = { state, cushion }
local sofaStates      = {}
-- pendingMinigame[sofaModel] = player  (blocks double-activation while minigame runs)
local pendingMinigame = {}

local HEARTBEAT_RATE   = 1 / 15   -- 15 Hz drop-detection scan
local MINIGAME_TIMEOUT = 3 * 60   -- 3 min stale-session cleanup

local SofaStateService = {}

-- ── Poof effect ───────────────────────────────────────────────────────────

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

-- ── State advancement ─────────────────────────────────────────────────────

local function advanceSofaState(sofaModel)
	local data = sofaStates[sofaModel]
	if not data then return end

	data.state += 1
	local newState = data.state

	ConceptRemotes.SofaStateChanged:FireAllClients(sofaModel, newState)

	if newState == 4 then
		local pivotCF = sofaModel:GetPivot()
		spawnPoof(sofaModel)
		sofaModel:Destroy()
		sofaStates[sofaModel] = nil

		local template = ServerStorage:FindFirstChild("SofaClean")
		if template then
			local clone = template:Clone()
			clone:PivotTo(pivotCF)
			clone.Parent = workspace
		else
			warn("[SofaStateService] SofaClean template not found in ServerStorage")
		end

		JobService.CheckCompletion()
	end
end

-- ── Init ──────────────────────────────────────────────────────────────────

function SofaStateService.Init()
	for _, sofaModel in ipairs(CollectionService:GetTagged("ConceptSofa")) do
		local cushion = sofaModel:FindFirstChild("Cushion")
		if not cushion or not cushion:IsA("BasePart") then
			warn("[SofaStateService] " .. sofaModel.Name .. " is missing a 'Cushion' BasePart — skipped")
			continue
		end

		sofaStates[sofaModel] = {
			state   = 0,
			cushion = cushion,
		}

		ConceptRemotes.SofaStateChanged:FireAllClients(sofaModel, 0)
	end

	-- Drop-detection heartbeat: scans all Grabbable items that are not currently
	-- held and checks if any are within SnapRadius of a sofa cushion.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < HEARTBEAT_RATE then return end
		acc = 0

		-- Build the set of currently-held entities so we can skip them.
		local heldEntities = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local entity = GrabHandler.GetHeldEntity(player)
			if entity then heldEntities[entity] = true end
		end

		for _, entity in ipairs(CollectionService:GetTagged("Grabbable")) do
			if heldEntities[entity] then continue end

			local name = entity.Name
			if name ~= "Sponge" and name ~= "Cloth"
			and name ~= "TackRemover" and name ~= "SewingNeedle" then
				continue
			end

			local pos
			pcall(function() pos = entity:GetPivot().Position end)
			if not pos then continue end

			for sofaModel, data in pairs(sofaStates) do
				if pendingMinigame[sofaModel] then continue end
				if (data.cushion.Position - pos).Magnitude > ConceptConfig.SnapRadius then continue end

				-- Sponge / Cloth: poof immediately and advance state
				if (name == "Sponge" and data.state == 1)
				or (name == "Cloth"  and data.state == 2) then
					local lastPlayer = GrabHandler.GetLastHolder(entity)
					CollectionService:RemoveTag(entity, "Grabbable")
					spawnPoof(entity)
					if lastPlayer then
						ConceptRemotes.PlaySound:FireClient(lastPlayer, "Snap")
					end
					entity:Destroy()
					advanceSofaState(sofaModel)
					break
				end

				-- TackRemover / SewingNeedle: poof on drop, then start minigame
				if name == "TackRemover" and data.state == 0 then
					local player = GrabHandler.GetLastHolder(entity)
					if not player then continue end
					pendingMinigame[sofaModel] = player
					CollectionService:RemoveTag(entity, "Grabbable")
					ConceptRemotes.PlaySound:FireClient(player, "Snap")
					spawnPoof(entity)
					entity:Destroy()
					ConceptRemotes.StartMinigame:FireClient(
						player, sofaModel, "TackRemoval",
						{ difficulty = "Easy", fragile = false, toolBonus = 0 }
					)
					task.delay(MINIGAME_TIMEOUT, function()
						if pendingMinigame[sofaModel] == player then
							pendingMinigame[sofaModel] = nil
						end
					end)
					break
				end

				if name == "SewingNeedle" and data.state == 3 then
					local player = GrabHandler.GetLastHolder(entity)
					if not player then continue end
					pendingMinigame[sofaModel] = player
					CollectionService:RemoveTag(entity, "Grabbable")
					ConceptRemotes.PlaySound:FireClient(player, "Snap")
					spawnPoof(entity)
					entity:Destroy()
					ConceptRemotes.StartMinigame:FireClient(
						player, sofaModel, "SeamStitching",
						{ difficulty = "Easy", fragile = false, toolBonus = 0 }
					)
					task.delay(MINIGAME_TIMEOUT, function()
						if pendingMinigame[sofaModel] == player then
							pendingMinigame[sofaModel] = nil
						end
					end)
					break
				end
			end
		end
	end)

	ConceptRemotes.ReportMinigameResult.OnServerEvent:Connect(function(player, sofaModel, result)
		if pendingMinigame[sofaModel] ~= player then return end
		pendingMinigame[sofaModel] = nil

		if result ~= "Fail" then
			advanceSofaState(sofaModel)
		end
	end)
end

return SofaStateService
