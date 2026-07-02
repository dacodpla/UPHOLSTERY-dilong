local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))

local DIALOGUES = {
	"hm?",
	"need something?",
	"...",
	"you good?",
	"oh?",
}

local TYPEWRITER_CPS  = 28
local DIALOGUE_HOLD   = 1.5   -- seconds to hold after typing finishes
local DIALOGUE_MIN    = 6     -- min seconds between lines
local DIALOGUE_MAX    = 14    -- max seconds between lines
local FACE_RATE       = 0.1   -- seconds between facing updates

local NPCService = {}

-- Shared dialogue bubble style (matches DoorService).
local function showBubble(head, text)
local gui = Instance.new("BillboardGui")
	gui.Size         = UDim2.fromOffset(280, 58)
	gui.StudsOffset  = Vector3.new(0, 1, 0)
	gui.AlwaysOnTop  = true
	gui.MaxDistance  = 12
	gui.ResetOnSpawn = false
	gui.Parent       = head

	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = Color3.fromRGB(12, 10, 18)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel        = 0
	bg.Parent                 = gui
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, -18, 1, -14)
	label.Position               = UDim2.fromOffset(9, 7)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3       = Color3.new(0, 0, 0)
	label.Font                   = Enum.Font.Gotham
	label.TextSize               = 24
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextWrapped            = true
	label.Parent                 = bg

	for i = 1, #text do
		label.Text = string.sub(text, 1, i)
		if i % 2 == 0 then
			ConceptRemotes.PlaySound:FireAllClients("Typewriter")
		end
		task.wait(1 / TYPEWRITER_CPS)
	end
	task.wait(DIALOGUE_HOLD)
	gui:Destroy()
end

function NPCService.Init()
	local npc = workspace:WaitForChild("Character_2", 10)
	if not npc then
		warn("[NPCService] Character_2 not found in Workspace")
		return
	end

	local head = npc:FindFirstChild("Head")
		or npc:FindFirstChild("HumanoidRootPart")
		or npc.PrimaryPart

	-- Fire animation to a client when their character loads.
	local function sendAnimTo(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			ConceptRemotes.PlayAmbientAnimation:FireClient(player)
		end)
		if player.Character then
			ConceptRemotes.PlayAmbientAnimation:FireClient(player)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		sendAnimTo(player)
	end
	Players.PlayerAdded:Connect(sendAnimTo)

	-- Face the nearest player continuously.
	task.spawn(function()
		while npc and npc.Parent do
			task.wait(FACE_RATE)
			local players = Players:GetPlayers()
			if #players > 0 then
				local playerHRP = players[1].Character
					and players[1].Character:FindFirstChild("HumanoidRootPart")
				if playerHRP then
					local pivot   = npc:GetPivot()
					local lookDir = (playerHRP.Position - pivot.Position) * Vector3.new(1, 0, 1)
					if lookDir.Magnitude > 0.5 then
						npc:PivotTo(CFrame.new(pivot.Position, pivot.Position + lookDir.Unit))
					end
				end
			end
		end
	end)

	-- Random dialogue loop.
	if head then
		local rng = Random.new()
		task.spawn(function()
			while npc and npc.Parent do
				task.wait(rng:NextNumber(DIALOGUE_MIN, DIALOGUE_MAX))
				if #Players:GetPlayers() > 0 then
					local line = DIALOGUES[rng:NextInteger(1, #DIALOGUES)]
					showBubble(head, line)   -- blocks until bubble is gone
				end
			end
		end)
	end
end

return NPCService
