local CollectionService = game:GetService("CollectionService")

local ExitService = {}

local function resolvePromptParent(obj)
	if obj:IsA("BasePart") then return obj end
	if obj:IsA("Model") then
		return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

function ExitService.Init()
	task.defer(function()
		local exits = CollectionService:GetTagged("ConceptExit")
		if #exits == 0 then
			warn("[ExitService] No objects found with the ConceptExit tag")
			return
		end

		for _, obj in ipairs(exits) do
			local promptParent = resolvePromptParent(obj)
			if not promptParent then
				warn("[ExitService] ConceptExit object has no BasePart: " .. obj:GetFullName())
				continue
			end

			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText          = "Leave"
			prompt.ObjectText          = ""
			prompt.HoldDuration        = 0
			prompt.KeyboardKeyCode     = Enum.KeyCode.F
			prompt.Style               = Enum.ProximityPromptStyle.Custom
			prompt.RequiresLineOfSight = false
			prompt.Parent              = promptParent

			prompt.Triggered:Connect(function(player)
				player:Kick("Thanks for playing! See you next time.")
			end)
		end
	end)
end

return ExitService
