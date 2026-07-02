-- src/client/GrabController.luau

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("GrabConfig"))
local Remotes = require(Shared:WaitForChild("GrabRemotes")).Get()

local LocalPlayer = Players.LocalPlayer

local state = {
	isHolding      = false,
	heldPart       = nil,
	hoveredPart    = nil,
	highlightHover = nil,
	highlightHeld  = nil,
	canGrab        = true,
}

-- ── Highlights ────────────────────────────────────────────────────────────────

-- Adornee the whole Model when possible so the outline wraps the full silhouette.
local function resolveHighlightTarget(part)
	local parent = part.Parent
	if parent and parent:IsA("Model") and not parent:IsA("WorldRoot") then
		return parent
	end
	return part
end

local function clearHoverHighlight()
	if state.highlightHover then
		state.highlightHover:Destroy()
		state.highlightHover = nil
	end
	state.hoveredPart = nil
end

local function createHoverHighlight(part)
	clearHoverHighlight()
	state.hoveredPart = part
	local h = Instance.new("Highlight")
	h.Adornee             = resolveHighlightTarget(part)
	h.FillTransparency    = 1
	h.OutlineColor        = Color3.fromRGB(255, 255, 255)
	h.OutlineTransparency = 0
	h.Parent              = workspace.CurrentCamera
	state.highlightHover  = h
end

local function clearHeldHighlight()
	if state.highlightHeld then
		state.highlightHeld:Destroy()
		state.highlightHeld = nil
	end
end

local function createHeldHighlight(part)
	clearHeldHighlight()
	local h = Instance.new("Highlight")
	h.Adornee             = resolveHighlightTarget(part)
	h.FillTransparency    = 1
	h.OutlineColor        = Color3.fromRGB(255, 210, 80)
	h.OutlineTransparency = 0
	h.Parent              = workspace.CurrentCamera
	state.highlightHeld   = h
end

-- ── Raycast helpers ───────────────────────────────────────────────────────────

local function getRaycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = LocalPlayer.Character and { LocalPlayer.Character } or {}
	return params
end

-- WYSIWYG raycast: always fires from the CAMERA through the mouse cursor so
-- the hit is exactly what the player sees on screen.  A long range (200 studs)
-- ensures the ray reaches objects regardless of how far the camera is zoomed out
-- in third-person.  Reach is enforced separately via isInRange().
local function castFromMouse()
	local camera   = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	return workspace:Raycast(ray.Origin, ray.Direction.Unit * 200, getRaycastParams())
end

-- Returns true when the hit position is within grab range of the character.
-- Using the hit position (not part centre) matches what the player physically
-- moused-over and stays consistent with the server's HRP-distance check.
local function isInRange(result)
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not result then return false end
	return (hrp.Position - result.Position).Magnitude <= Config.MAX_GRAB_DISTANCE
end

local function isGrabbableClient(part)
	if CollectionService:HasTag(part, Config.GRABBABLE_TAG) then return true end
	local cur = part.Parent
	while cur do
		if cur:IsA("Model") and CollectionService:HasTag(cur, Config.GRABBABLE_TAG) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- ── Carry target ──────────────────────────────────────────────────────────────
-- Mouse ray direction from camera, origin anchored at HRP so the object stays
-- in front of the character in both first- and third-person.

local function getCarryTarget()
	local camera   = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	local mousePos = UserInputService:GetMouseLocation()
	local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y)

	if hrp then
		local aimPoint = ray.Origin + ray.Direction.Unit * 500
		local aimDir   = (aimPoint - hrp.Position).Unit
		return hrp.Position + Vector3.new(0, Config.CARRY_HEIGHT, 0)
			+ aimDir * Config.CARRY_DISTANCE
	end

	return ray.Origin + ray.Direction.Unit * Config.CARRY_DISTANCE
end

-- ── Core state ────────────────────────────────────────────────────────────────

local function clearHeldState()
	state.isHolding = false
	state.heldPart  = nil
	state.canGrab   = true
	clearHoverHighlight()
	clearHeldHighlight()
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function tryGrab()
	if not state.canGrab then return end
	state.canGrab = false

	local result = castFromMouse()
	if not result or not result.Instance:IsA("BasePart") or not isInRange(result) then
		state.canGrab = true
		return
	end

	Remotes.RequestGrab:FireServer(result.Instance)
	task.delay(2, function()
		if not state.canGrab then state.canGrab = true end
	end)
end

local function release()
	if not state.isHolding then return end
	state.isHolding = false
	Remotes.RequestRelease:FireServer()
end

local function throw()
	if not state.isHolding or not state.heldPart then return end

	state.isHolding = false

	local lookDir  = workspace.CurrentCamera.CFrame.LookVector
	local throwDir = (lookDir + Vector3.new(0, Config.THROW_UP_BIAS, 0)).Unit

	state.heldPart.AssemblyLinearVelocity  = throwDir * Config.THROW_SPEED
	state.heldPart.AssemblyAngularVelocity = Vector3.zero

	Remotes.RequestThrow:FireServer(throwDir)
end

-- ── Remote responses ──────────────────────────────────────────────────────────

Remotes.GrabConfirmed.OnClientEvent:Connect(function(resolvedPart)
	state.isHolding = true
	state.heldPart  = resolvedPart
	state.canGrab   = true
	clearHoverHighlight()
	createHeldHighlight(resolvedPart)
end)

Remotes.GrabFailed.OnClientEvent:Connect(function(_reason)
	state.canGrab = true
end)

Remotes.ReleaseConfirmed.OnClientEvent:Connect(function()
	clearHeldState()
end)

Remotes.ThrowConfirmed.OnClientEvent:Connect(function()
	clearHeldState()
end)

-- ── Input ─────────────────────────────────────────────────────────────────────
-- LMB          → grab
-- RMB (tap)    → put down
-- RMB (hold)   → throw

local THROW_HOLD_THRESHOLD = 0.35   -- seconds RMB must be held to count as a throw
local _rmbDownTime = 0

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not state.isHolding then tryGrab() end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and state.isHolding then
		_rmbDownTime = os.clock()
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and state.isHolding then
		if (os.clock() - _rmbDownTime) >= THROW_HOLD_THRESHOLD then
			throw()
		else
			release()
		end
	end
end)

-- ── Physics loop (Heartbeat = physics rate ~240 Hz) ───────────────────────────

RunService.Heartbeat:Connect(function()
	if state.isHolding and state.heldPart then
		if not state.heldPart.Parent then
			clearHeldState()
			return
		end
		local target       = getCarryTarget()
		local displacement = target - state.heldPart.Position
		local dist         = displacement.Magnitude
		if dist > 0.05 then
			local speed = math.min(dist * Config.CARRY_SPEED, Config.MAX_CARRY_SPEED)
			state.heldPart.AssemblyLinearVelocity = (displacement / dist) * speed
		else
			state.heldPart.AssemblyLinearVelocity = Vector3.zero
		end
		state.heldPart.AssemblyAngularVelocity = Vector3.zero
	end
end)

-- Hover highlight runs on RenderStepped (visual, 60 Hz) rather than Heartbeat
-- (physics, ~240 Hz) — no need to raycast faster than the frame rate.
RunService.RenderStepped:Connect(function()
	if state.isHolding then return end

	-- Clear stale reference if the hovered part was destroyed
	if state.hoveredPart and not state.hoveredPart.Parent then
		clearHoverHighlight()
	end

	local result    = castFromMouse()
	local hitPart   = result and result.Instance
	local grabbable = hitPart
		and hitPart:IsA("BasePart")
		and isGrabbableClient(hitPart)
		and isInRange(result)

	-- Compare resolved adornee (the whole Model) so moving between BaseParts
	-- of the same Model does not destroy and recreate the Highlight every frame.
	local resolvedTarget = grabbable and resolveHighlightTarget(hitPart)
	local currentAdornee = state.highlightHover and state.highlightHover.Adornee

	if grabbable and resolvedTarget ~= currentAdornee then
		createHoverHighlight(hitPart)
	elseif not grabbable and state.hoveredPart then
		clearHoverHighlight()
	end
end)

-- ── Public API ────────────────────────────────────────────────────────────────

local GrabController = {}

function GrabController.Init() end

function GrabController.GetHoverName()
	local part = state.hoveredPart
	if not part then return nil end
	local parent = part.Parent
	if parent and parent:IsA("Model") and not parent:IsA("WorldRoot") then
		return parent.Name
	end
	return part.Name
end

return GrabController
