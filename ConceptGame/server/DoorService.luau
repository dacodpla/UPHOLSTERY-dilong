local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))

-- Dialogue lines and how long each stays on screen.
local DIALOGUE = {
	{ text = "oh... sofa guy? right?",  duration = 2.2 },
	{ text = "come on in.", duration = 2.0 },
}

local DoorService = {}

local function resolvePromptParent(obj)
	if obj:IsA("BasePart") then return obj end
	if obj:IsA("Model") then
		return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- Blocking pivot tween — moves every part of a Model via PivotTo.
local function pivotTween(obj, targetCF, duration)
	local startCF  = obj:GetPivot()
	local elapsed  = 0
	local lastTime = os.clock()
	repeat
		local now = os.clock()
		elapsed   = elapsed + (now - lastTime)
		lastTime  = now
		local alpha = math.min(elapsed / duration, 1)
		local t     = 1 - (1 - alpha) * (1 - alpha)
		obj:PivotTo(startCF:Lerp(targetCF, t))
		if alpha < 1 then RunService.Heartbeat:Wait() end
	until elapsed >= duration
end

local TYPEWRITER_CPS = 28   -- characters per second

-- Shows dialogue lines above the NPC's head with a typewriter effect.
local function showDialogue(npc)
	local head = npc:FindFirstChild("Head")
		or npc:FindFirstChild("HumanoidRootPart")
		or npc.PrimaryPart
	if not head then return end

	local gui = Instance.new("BillboardGui")
	gui.Size         = UDim2.fromOffset(280, 58)
	gui.StudsOffset  = Vector3.new(0, 1, 0)
	gui.AlwaysOnTop  = true
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

	for _, line in ipairs(DIALOGUE) do
		label.Text = ""
		-- Typewriter
		for i = 1, #line.text do
			label.Text = string.sub(line.text, 1, i)
			if i % 2 == 0 then
				ConceptRemotes.PlaySound:FireAllClients("Typewriter")
			end
			task.wait(1 / TYPEWRITER_CPS)
		end
		-- Hold for any remaining duration after typing finishes
		local remaining = line.duration - (#line.text / TYPEWRITER_CPS)
		if remaining > 0 then
			task.wait(remaining)
		end
	end

	gui:Destroy()
end

function DoorService.Init()
	local JobService = require(script.Parent.JobService)

	task.defer(function()
		local doors = CollectionService:GetTagged("ConceptDoor")
		if #doors == 0 then
			warn("[DoorService] No parts found with the ConceptDoor tag")
			return
		end

		-- Single NPC for this prototype.
		local npcs = CollectionService:GetTagged("ConceptNPC")
		local npc  = npcs[1]
		if not npc then
			warn("[DoorService] No ConceptNPC-tagged model found — add the tag to the NPC in Studio")
		end

		for _, door in ipairs(doors) do
			local promptParent = resolvePromptParent(door)
			if promptParent then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText          = "Knock"
				prompt.ObjectText          = ""
				prompt.HoldDuration        = 0
				prompt.KeyboardKeyCode     = Enum.KeyCode.F
				prompt.Style               = Enum.ProximityPromptStyle.Custom
				prompt.RequiresLineOfSight = false
				prompt.Parent              = promptParent

				local used = false
				prompt.Triggered:Connect(function(player)
					if used then return end
					used = true
					prompt.Enabled = false

					-- t=0   Knock sound + animation fire immediately.
					ConceptRemotes.PlaySound:FireClient(player, "Knock")
					if npc then
						ConceptRemotes.PlayNPCAnimation:FireAllClients(npc)
					end

					-- t=1s  Door swings open.
					task.wait(1)
					ConceptRemotes.PlaySound:FireClient(player, "DoorOpen")
					local openCF = door:GetPivot() * CFrame.Angles(0, math.rad(-30), 0)
					pivotTween(door, openCF, 0.8)   -- finishes at t=1.8s

					-- t=3s  Dialogue starts (1 + 0.8 + 1.2 = 3.0s from knock).
					task.wait(1.2)
					if npc then
						showDialogue(npc)   -- 4.2s total → ends at t=7.2s, exactly when animation ends
					else
						task.wait(4.2)
					end

					-- t=7.7s  Brief hold, then fade.
					task.wait(0.5)

					-- Fade to black, teleport, fade back in.
					ConceptRemotes.FadeScreen:FireClient(player)
					task.wait(0.4)

					local spawns = CollectionService:GetTagged("ConceptRoomSpawn")
					if #spawns > 0 then
						local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if hrp then
							hrp.CFrame = spawns[1].CFrame + Vector3.new(0, 3, 0)
						end
					end

					JobService.StartJob(player)
					ConceptRemotes.FadeIn:FireClient(player)
				end)
			else
				warn("[DoorService] ConceptDoor object has no BasePart: " .. door:GetFullName())
			end
		end
	end)
end

return DoorService
