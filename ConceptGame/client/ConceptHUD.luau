local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))
local SFX            = require(Shared:WaitForChild("SFXPlayer"))
local GrabRemotes    = require(Shared:WaitForChild("GrabRemotes")).Get()
local GrabController = require(script.Parent.GrabController)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local GRADE_COLORS = {
	Perfect = Color3.fromRGB(255, 210,  60),
	Good    = Color3.fromRGB( 90, 180, 220),
	Pass    = Color3.fromRGB(160, 140, 120),
	Fail    = Color3.fromRGB(220,  70,  70),
}

-- ── Fade screen ───────────────────────────────────────────────────────────

local _fadeGui = nil

ConceptRemotes.FadeScreen.OnClientEvent:Connect(function()
	local gui = Instance.new("ScreenGui")
	gui.Name          = "ConceptFade"
	gui.ResetOnSpawn  = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel        = 0
	frame.Parent                 = gui

	gui.Parent = playerGui
	_fadeGui   = gui

	TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
end)

ConceptRemotes.FadeIn.OnClientEvent:Connect(function()
	local gui = _fadeGui
	if not gui then return end
	_fadeGui = nil

	local frame = gui:FindFirstChildWhichIsA("Frame")
	if not frame then gui:Destroy(); return end

	local tween = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function() gui:Destroy() end)
end)

-- ── Job result overlay ────────────────────────────────────────────────────

ConceptRemotes.ShowJobResult.OnClientEvent:Connect(function(grade, elapsedSeconds)
	local gui = Instance.new("ScreenGui")
	gui.Name          = "ConceptJobResult"
	gui.ResetOnSpawn  = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent        = playerGui

	local frame = Instance.new("Frame")
	frame.Size             = UDim2.new(0, 340, 0, 110)
	frame.AnchorPoint      = Vector2.new(0.5, 0.5)
	frame.Position         = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel  = 0
	frame.Parent           = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 16)

	local gradeLabel = Instance.new("TextLabel")
	gradeLabel.Size                = UDim2.new(1, 0, 0, 54)
	gradeLabel.Position            = UDim2.fromOffset(0, 14)
	gradeLabel.BackgroundTransparency = 1
	gradeLabel.Text                = grade:upper()
	gradeLabel.TextColor3          = GRADE_COLORS[grade] or Color3.new(1, 1, 1)
	gradeLabel.Font                = Enum.Font.GothamBold
	gradeLabel.TextSize            = 38
	gradeLabel.Parent              = frame

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Size                 = UDim2.new(1, 0, 0, 32)
	timeLabel.Position             = UDim2.fromOffset(0, 68)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text                 = string.format("%.1f s", elapsedSeconds)
	timeLabel.TextColor3           = Color3.fromRGB(180, 170, 160)
	timeLabel.Font                 = Enum.Font.Gotham
	timeLabel.TextSize             = 22
	timeLabel.Parent               = frame

	task.delay(3, function()
		TweenService:Create(gradeLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(timeLabel,  TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local t = TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		t:Play()
		t.Completed:Connect(function() gui:Destroy() end)
	end)
end)

-- ── NPC animation ─────────────────────────────────────────────────────────

ConceptRemotes.PlayNPCAnimation.OnClientEvent:Connect(function(npc)
	if not npc then return end

	local humanoid  = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animation = ReplicatedStorage:FindFirstChild("Animations")
	animation = animation and animation:FindFirstChild("Animation1")
	if not animation then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationTrack = animator:LoadAnimation(animation)
	animationTrack:Play()
end)

-- ── Character_2 ambient animation ────────────────────────────────────────

ConceptRemotes.PlayAmbientAnimation.OnClientEvent:Connect(function()
	local npc       = workspace:WaitForChild("Character_2")
	local humanoid  = npc:WaitForChild("Humanoid")
	local animation = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Animation2")

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationTrack = animator:LoadAnimation(animation)
	animationTrack.Looped = true
	animationTrack:Play()
end)

-- ── Sound passthrough ─────────────────────────────────────────────────────

ConceptRemotes.PlaySound.OnClientEvent:Connect(function(name)
	SFX.Play(name)
end)

-- ── Cursor hints (item label + prompt hint, both follow mouse) ───────────

local _isHolding      = false
local _holdName       = ""
local _minigameActive = false

local cursorGui = Instance.new("ScreenGui")
cursorGui.Name           = "CursorHint"
cursorGui.ResetOnSpawn   = false
cursorGui.IgnoreGuiInset = true
cursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
cursorGui.DisplayOrder   = 1
cursorGui.Parent         = playerGui

-- Item name (hold / hover)
local holdLabel = Instance.new("TextLabel")
holdLabel.Size                   = UDim2.new(0, 220, 0, 22)
holdLabel.AnchorPoint            = Vector2.new(0, 0)
holdLabel.BackgroundTransparency = 1
holdLabel.TextColor3             = Color3.new(1, 1, 1)
holdLabel.TextStrokeTransparency = 0.4
holdLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
holdLabel.Font                   = Enum.Font.Gotham
holdLabel.TextSize               = 15
holdLabel.TextXAlignment         = Enum.TextXAlignment.Left
holdLabel.Visible                = false
holdLabel.Parent                 = cursorGui

-- Prompt hint (below item label, shown when mouse is over an interactable)
local promptHint = Instance.new("TextLabel")
promptHint.Size                   = UDim2.new(0, 220, 0, 30)
promptHint.AnchorPoint            = Vector2.new(0, 0)
promptHint.BackgroundColor3       = Color3.fromRGB(10, 8, 16)
promptHint.BackgroundTransparency = 0.22
promptHint.BorderSizePixel        = 0
promptHint.TextColor3             = Color3.new(1, 1, 1)
promptHint.TextStrokeTransparency = 0.5
promptHint.TextStrokeColor3       = Color3.new(0, 0, 0)
promptHint.Font                   = Enum.Font.Gotham
promptHint.TextSize               = 14
promptHint.TextXAlignment         = Enum.TextXAlignment.Left
promptHint.TextYAlignment         = Enum.TextYAlignment.Top
promptHint.Visible                = false
promptHint.Parent                 = cursorGui
Instance.new("UICorner", promptHint).CornerRadius = UDim.new(0, 6)

local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft   = UDim.new(0, 8)
hintPad.PaddingRight  = UDim.new(0, 8)
hintPad.PaddingTop    = UDim.new(0, 5)
hintPad.PaddingBottom = UDim.new(0, 5)
hintPad.Parent        = promptHint

-- Sofa repair checklist card (follows cursor, shown when hovering a ConceptSofa)
local sofaCard = Instance.new("Frame")
sofaCard.Size                   = UDim2.new(0, 200, 0, 90)
sofaCard.AnchorPoint            = Vector2.new(0, 0)
sofaCard.BackgroundColor3       = Color3.fromRGB(10, 8, 16)
sofaCard.BackgroundTransparency = 0.22
sofaCard.BorderSizePixel        = 0
sofaCard.Visible                = false
sofaCard.Parent                 = cursorGui
Instance.new("UICorner", sofaCard).CornerRadius = UDim.new(0, 6)

local sofaCardPad = Instance.new("UIPadding")
sofaCardPad.PaddingLeft   = UDim.new(0, 10)
sofaCardPad.PaddingRight  = UDim.new(0, 10)
sofaCardPad.PaddingTop    = UDim.new(0, 8)
sofaCardPad.PaddingBottom = UDim.new(0, 8)
sofaCardPad.Parent        = sofaCard

local sofaCardLabel = Instance.new("TextLabel")
sofaCardLabel.Size                   = UDim2.fromScale(1, 1)
sofaCardLabel.BackgroundTransparency = 1
sofaCardLabel.TextColor3             = Color3.new(1, 1, 1)
sofaCardLabel.TextStrokeTransparency = 0.5
sofaCardLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
sofaCardLabel.Font                   = Enum.Font.Gotham
sofaCardLabel.TextSize               = 13
sofaCardLabel.TextXAlignment         = Enum.TextXAlignment.Left
sofaCardLabel.TextYAlignment         = Enum.TextYAlignment.Top
sofaCardLabel.LineHeight             = 1.45
sofaCardLabel.Parent                 = sofaCard

GrabRemotes.GrabConfirmed.OnClientEvent:Connect(function(resolvedPart)
	_isHolding = true
	local parent = resolvedPart.Parent
	_holdName = (parent and parent:IsA("Model") and not parent:IsA("WorldRoot"))
		and parent.Name or resolvedPart.Name
end)

GrabRemotes.ReleaseConfirmed.OnClientEvent:Connect(function()
	_isHolding = false
end)

GrabRemotes.ThrowConfirmed.OnClientEvent:Connect(function()
	_isHolding = false
end)

-- Checks a single Model for an enabled prompt on itself or on any direct
-- BasePart child. Does NOT recurse into nested sub-models, which is what
-- prevents bleeding across unrelated objects inside a container like Slot_5.
local function findPromptInModel(model)
	local p = model:FindFirstChildOfClass("ProximityPrompt")
	if p and p.Enabled then return p end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			p = child:FindFirstChildOfClass("ProximityPrompt")
			if p and p.Enabled then return p end
		end
	end
	return nil
end

-- Single shared raycast for all HUD hit-detection this frame.
-- Both findHoveredPrompt and findHoveredSofa accept the result as a
-- parameter so we fire exactly one ray per RenderStepped tick.
local function castHUDRay()
	local camera    = workspace.CurrentCamera
	local mousePos  = UserInputService:GetMouseLocation()
	local ray       = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	local character = Players.LocalPlayer.Character
	local params    = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	return workspace:Raycast(ray.Origin, ray.Direction.Unit * 200, params)
end

-- Walk up the hierarchy from the raycast hit until WorldRoot.
-- At each Model we call findPromptInModel (direct BasePart children only)
-- so container models like Slot_5 never surface unrelated nested prompts.
local function findHoveredPrompt(result)
	if not result then return nil end

	local hit = result.Instance

	local p = hit:FindFirstChildOfClass("ProximityPrompt")
	if p and p.Enabled then
		-- fall through to distance check below
	else
		p = nil
		local cur = hit.Parent
		while cur and not cur:IsA("WorldRoot") do
			if cur:IsA("Model") then
				p = findPromptInModel(cur)
				if p then break end
			end
			cur = cur.Parent
		end
	end

	if not p then return nil end

	-- Respect MaxActivationDistance — only show hint when the player
	-- is actually close enough to trigger the prompt.
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - result.Position).Magnitude > p.MaxActivationDistance then
		return nil
	end

	return p
end

local _sofaStates = {}
local SOFA_STEPS  = { "Remove Tacks", "Place Sponge", "Place Cloth", "Sew Seam" }

ConceptRemotes.SofaStateChanged.OnClientEvent:Connect(function(sofaModel, newState)
	if newState < 4 then
		_sofaStates[sofaModel] = newState
	else
		_sofaStates[sofaModel] = nil
	end
end)

local function findHoveredSofa(result)
	if not result then return nil end
	local cur = result.Instance
	while cur and not cur:IsA("WorldRoot") do
		if cur:IsA("Model") and CollectionService:HasTag(cur, "ConceptSofa") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if _minigameActive then
		holdLabel.Visible  = false
		promptHint.Visible = false
		sofaCard.Visible   = false
		return
	end

	local pos     = UserInputService:GetMouseLocation()
	local offsetX = pos.X + 16
	local nextY   = pos.Y + 10

	-- Item name label
	local itemText = _isHolding and _holdName or GrabController.GetHoverName()
	if itemText then
		holdLabel.Text     = itemText
		holdLabel.Position = UDim2.fromOffset(offsetX, nextY)
		holdLabel.Visible  = true
		nextY = nextY + 22 + 3
	else
		holdLabel.Visible = false
	end

	local hudRay = castHUDRay()

	-- Prompt hint (mouse-raycast, not proximity-based)
	local prompt = findHoveredPrompt(hudRay)
	if prompt then
		local req = prompt:GetAttribute("RequiredItem")
		if req then
			promptHint.Text = "[ F ]  " .. prompt.ActionText .. "\n!  needs: " .. req
			promptHint.Size = UDim2.new(0, 220, 0, 50)
		else
			promptHint.Text = "[ F ]  " .. prompt.ActionText
			promptHint.Size = UDim2.new(0, 220, 0, 30)
		end
		promptHint.Position = UDim2.fromOffset(offsetX, nextY)
		promptHint.Visible  = true
		nextY = nextY + promptHint.AbsoluteSize.Y + 4
	else
		promptHint.Visible = false
	end

	-- Sofa repair checklist card
	local sofa = findHoveredSofa(hudRay)
	if sofa then
		local state = _sofaStates[sofa] or 0
		local lines = {}
		for i, step in ipairs(SOFA_STEPS) do
			local done = state >= i
			lines[i] = (done and "\u{2705}" or "\u{274C}") .. "  " .. step
		end
		sofaCardLabel.Text    = table.concat(lines, "\n")
		sofaCard.Size         = UDim2.new(0, 200, 0, 18 + #SOFA_STEPS * 19)
		sofaCard.Position     = UDim2.fromOffset(offsetX, nextY)
		sofaCard.Visible      = true
	else
		sofaCard.Visible = false
	end
end)

-- ── Control guide (bottom-right) ─────────────────────────────────────────────

local guideGui = Instance.new("ScreenGui")
guideGui.Name           = "ControlGuide"
guideGui.ResetOnSpawn   = false
guideGui.IgnoreGuiInset = false
guideGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
guideGui.Parent         = playerGui

local guideBg = Instance.new("Frame")
guideBg.Size                   = UDim2.new(0, 176, 0, 80)
guideBg.AnchorPoint            = Vector2.new(1, 1)
guideBg.Position               = UDim2.new(1, -16, 1, -16)
guideBg.BackgroundColor3       = Color3.fromRGB(10, 8, 16)
guideBg.BackgroundTransparency = 0.28
guideBg.BorderSizePixel        = 0
guideBg.Parent                 = guideGui
Instance.new("UICorner", guideBg).CornerRadius = UDim.new(0, 8)

local guidePad = Instance.new("UIPadding")
guidePad.PaddingLeft   = UDim.new(0, 12)
guidePad.PaddingRight  = UDim.new(0, 12)
guidePad.PaddingTop    = UDim.new(0, 10)
guidePad.PaddingBottom = UDim.new(0, 10)
guidePad.Parent        = guideBg

local guideList = Instance.new("UIListLayout")
guideList.Padding       = UDim.new(0, 4)
guideList.FillDirection = Enum.FillDirection.Vertical
guideList.SortOrder     = Enum.SortOrder.LayoutOrder
guideList.Parent        = guideBg

local CONTROLS = {
	{ key = "LMB", desc = "Grab"         },
	{ key = "RMB", desc = "Drop / Throw" },
	{ key = "F",   desc = "Interact"     },
}

for i, ctrl in ipairs(CONTROLS) do
	local row = Instance.new("Frame")
	row.Size                   = UDim2.new(1, 0, 0, 18)
	row.BackgroundTransparency = 1
	row.LayoutOrder            = i
	row.Parent                 = guideBg

	local keyBadge = Instance.new("TextLabel")
	keyBadge.Size                   = UDim2.new(0, 38, 1, 0)
	keyBadge.BackgroundColor3       = Color3.fromRGB(38, 34, 52)
	keyBadge.BackgroundTransparency = 0
	keyBadge.Text                   = ctrl.key
	keyBadge.TextColor3             = Color3.fromRGB(210, 205, 225)
	keyBadge.Font                   = Enum.Font.GothamBold
	keyBadge.TextSize               = 11
	keyBadge.BorderSizePixel        = 0
	keyBadge.Parent                 = row
	Instance.new("UICorner", keyBadge).CornerRadius = UDim.new(0, 4)

	local descLabel = Instance.new("TextLabel")
	descLabel.Size                   = UDim2.new(1, -46, 1, 0)
	descLabel.Position               = UDim2.fromOffset(46, 0)
	descLabel.BackgroundTransparency = 1
	descLabel.Text                   = ctrl.desc
	descLabel.TextColor3             = Color3.fromRGB(165, 160, 180)
	descLabel.Font                   = Enum.Font.Gotham
	descLabel.TextSize               = 12
	descLabel.TextXAlignment         = Enum.TextXAlignment.Left
	descLabel.BorderSizePixel        = 0
	descLabel.Parent                 = row
end

-- ── Public API ────────────────────────────────────────────────────────────

local ConceptHUD = {}

function ConceptHUD.SetMinigameActive(active)
	_minigameActive = active
	guideBg.Visible = not active
	-- cursor hints (holdLabel + promptHint) are hidden by the RenderStepped guard
end

return ConceptHUD
