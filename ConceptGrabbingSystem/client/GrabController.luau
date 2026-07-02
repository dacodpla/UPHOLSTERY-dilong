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
	isHolding         = false,
	heldPart          = nil,
	hoveredPart       = nil,
	selectionBoxHover = nil,
	selectionBoxHeld  = nil,
	canGrab           = true,
}

-- ── Highlights ────────────────────────────────────────────────────────────────

local function clearHoverHighlight()
	if state.selectionBoxHover then
		state.selectionBoxHover:Destroy()
		state.selectionBoxHover = nil
	end
	state.hoveredPart = nil
end

local function createHoverHighlight(part)
	clearHoverHighlight()
	state.hoveredPart = part
	local sb = Instance.new("SelectionBox")
	sb.Adornee             = part
	sb.Color3              = Color3.fromRGB(255, 255, 255)
	sb.LineThickness       = 0.05
	sb.SurfaceTransparency = 0.75
	sb.SurfaceColor3       = Color3.fromRGB(180, 210, 255)
	sb.Parent              = workspace.CurrentCamera
	state.selectionBoxHover = sb
end

local function clearHeldHighlight()
	if state.selectionBoxHeld then
		state.selectionBoxHeld:Destroy()
		state.selectionBoxHeld = nil
	end
end

local function createHeldHighlight(part)
	clearHeldHighlight()
	local sb = Instance.new("SelectionBox")
	sb.Adornee             = part
	sb.Color3              = Color3.fromRGB(255, 200, 0)
	sb.LineThickness       = 0.04
	sb.SurfaceTransparency = 0.85
	sb.SurfaceColor3       = Color3.fromRGB(255, 200, 0)
	sb.Parent              = workspace.CurrentCamera
	state.selectionBoxHeld = sb
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Config.GRAB_KEY then
		if state.isHolding then release() else tryGrab() end
		return
	end

	if input.KeyCode == Config.THROW_KEY and state.isHolding then
		throw()
		return
	end

	if Config.USE_MOUSE_THROW
		and input.UserInputType == Enum.UserInputType.MouseButton1
		and state.isHolding
	then
		throw()
	end
end)

-- ── Physics loop (Heartbeat = physics rate ~240 Hz) ───────────────────────────

RunService.Heartbeat:Connect(function()
	if state.isHolding and state.heldPart then
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

	-- Hover highlight: only show on grabbable parts within reach.
	if not state.isHolding then
		local result    = castFromMouse()
		local hitPart   = result and result.Instance
		local grabbable = hitPart
			and hitPart:IsA("BasePart")
			and isGrabbableClient(hitPart)
			and isInRange(result)

		if grabbable and hitPart ~= state.hoveredPart then
			createHoverHighlight(hitPart)
		elseif not grabbable and state.hoveredPart then
			clearHoverHighlight()
		end
	end
end)

-- ── Public API ────────────────────────────────────────────────────────────────

local GrabController = {}
function GrabController.Init() end
return GrabController
