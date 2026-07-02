-- src/gui/Gameplay/GrabController.client.luau

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

local _enabled = true   -- set false during GUI minigames

local hideItemName   -- forward declared; defined after BillboardGui setup below
local showItemName   -- forward declared; defined after BillboardGui setup below

-- ── Highlights ────────────────────────────────────────────────────────────────

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
	hideItemName()
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
	showItemName(part, Color3.fromRGB(240, 230, 200))
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

-- ── Item name label ──────────────────────────────────────────────────────────
-- Shows the hovered/held item's name as a BillboardGui anchored to the object.
-- White = hovering, gold = holding.

local function toDisplayName(name)
	return name:gsub("(%l)(%u)", "%1 %2")
end

local _nameBoard = Instance.new("BillboardGui")
_nameBoard.Name        = "GrabItemName"
_nameBoard.Size        = UDim2.new(0, 160, 0, 30)
_nameBoard.StudsOffset = Vector3.new(0.8, 1.4, 0)
_nameBoard.MaxDistance = 30
_nameBoard.AlwaysOnTop = false
_nameBoard.Enabled     = false
_nameBoard.Parent      = LocalPlayer:WaitForChild("PlayerGui")

local _nameBg = Instance.new("Frame")
_nameBg.Size                   = UDim2.fromScale(1, 1)
_nameBg.BackgroundColor3       = Color3.fromRGB(10, 8, 16)
_nameBg.BackgroundTransparency = 0.25
_nameBg.BorderSizePixel        = 0
_nameBg.Parent                 = _nameBoard
Instance.new("UICorner", _nameBg).CornerRadius = UDim.new(0, 6)

local _nameLabel = Instance.new("TextLabel")
_nameLabel.Name                   = "NameText"
_nameLabel.Size                   = UDim2.fromScale(1, 1)
_nameLabel.BackgroundTransparency = 1
_nameLabel.Text                   = ""
_nameLabel.TextColor3             = Color3.fromRGB(240, 230, 200)
_nameLabel.Font                   = Enum.Font.GothamBold
_nameLabel.TextSize               = 13
_nameLabel.Parent                 = _nameBg

showItemName = function(part, color)
	local target = resolveHighlightTarget(part)
	_nameBoard.Adornee    = target
	_nameLabel.Text       = toDisplayName(target.Name)
	_nameLabel.TextColor3 = color
	_nameBoard.Enabled    = true
end

hideItemName = function()
	_nameBoard.Enabled = false
	_nameBoard.Adornee = nil
end

-- ── Raycast helpers ───────────────────────────────────────────────────────────

local function getRaycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = LocalPlayer.Character and { LocalPlayer.Character } or {}
	return params
end

local function castFromMouse()
	local camera   = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	return workspace:Raycast(ray.Origin, ray.Direction.Unit * 200, getRaycastParams())
end

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

local function getCarryTarget()
	local camera    = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local hrp       = character and character:FindFirstChild("HumanoidRootPart")

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
	if not _enabled then return end
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
	showItemName(resolvedPart, Color3.fromRGB(255, 210, 60))
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

local THROW_HOLD_THRESHOLD = 0.35
local _rmbDownTime = 0

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not _enabled then return end
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

-- Hover highlight runs on RenderStepped (60 Hz)
RunService.RenderStepped:Connect(function()
	if state.isHolding then return end
	if not _enabled then
		if state.hoveredPart then clearHoverHighlight() end
		return
	end

	if state.hoveredPart and not state.hoveredPart.Parent then
		clearHoverHighlight()
	end

	local result    = castFromMouse()
	local hitPart   = result and result.Instance
	local grabbable = hitPart
		and hitPart:IsA("BasePart")
		and isGrabbableClient(hitPart)
		and isInRange(result)

	local resolvedTarget = grabbable and resolveHighlightTarget(hitPart)
	local currentAdornee = state.highlightHover and state.highlightHover.Adornee

	if grabbable and resolvedTarget ~= currentAdornee then
		createHoverHighlight(hitPart)
	elseif not grabbable and state.hoveredPart then
		clearHoverHighlight()
	end
end)

-- ── Bridge: expose SetEnabled to GameplayClient via BindableEvent ─────────────
-- GameplayClient fires this bridge when it needs to block/restore grab input.

local _bridge = Instance.new("BindableEvent")
_bridge.Name   = "GrabControllerBridge"
_bridge.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- ── Public API ────────────────────────────────────────────────────────────────

local GrabController = {}

function GrabController.Init() end

function GrabController.SetEnabled(val: boolean)
	_enabled = val
	if not val and state.isHolding then
		release()
	end
	if not val then
		clearHoverHighlight()
	end
end

function GrabController.IsHolding()
	return state.isHolding
end

function GrabController.GetHoverName()
	local part = state.hoveredPart
	if not part then return nil end
	local parent = part.Parent
	if parent and parent:IsA("Model") and not parent:IsA("WorldRoot") then
		return parent.Name
	end
	return part.Name
end

_bridge.Event:Connect(function(val)
	GrabController.SetEnabled(val)
end)

return GrabController
