local ServerStorage = game:GetService("ServerStorage")

local GrabHandler = require(script.Parent.GrabHandler)

local TOOLS = { "Sponge", "Cloth", "SewingNeedle", "TackRemover" }

local SPAWN_OFFSETS = {
	Vector3.new(-2.5, 1, 0),
	Vector3.new(-0.8, 1, 2),
	Vector3.new( 0.8, 1, 2),
	Vector3.new( 2.5, 1, 0),
}

local ToolboxService = {}

function ToolboxService.Init()
	local toolbox = workspace:FindFirstChild("Toolbox")
	if not toolbox then
		warn("[ToolboxService] Toolbox model not found in Workspace")
		return
	end

	task.spawn(function()
		-- Wait until someone first picks up the toolbox.
		while true do
			task.wait(0.1)
			if not toolbox or not toolbox.Parent then return end
			if GrabHandler.GetHolderOfPart(toolbox) then break end
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText          = "Unpack"
		prompt.ObjectText          = "Toolbox"
		prompt.HoldDuration        = 0
		prompt.KeyboardKeyCode     = Enum.KeyCode.F
		prompt.Style               = Enum.ProximityPromptStyle.Custom
		prompt.RequiresLineOfSight = false
		prompt.Enabled             = true
		prompt.Parent              = toolbox

		-- Keep the prompt visible only while the toolbox is being held.
		task.spawn(function()
			while toolbox and toolbox.Parent do
				task.wait(0.1)
				prompt.Enabled = GrabHandler.GetHolderOfPart(toolbox) ~= nil
			end
		end)

		prompt.Triggered:Connect(function(player)
			if player ~= GrabHandler.GetHolderOfPart(toolbox) then return end
			if not prompt.Enabled then return end
			prompt.Enabled = false

			local basePos = toolbox.CFrame.Position

			GrabHandler.ForceRelease(player)

			for i, name in ipairs(TOOLS) do
				local template = ServerStorage:FindFirstChild(name)
				if template then
					local clone = template:Clone()
					clone:PivotTo(CFrame.new(basePos + SPAWN_OFFSETS[i]))
					clone.Parent = workspace
				else
					warn("[ToolboxService] Template missing from ServerStorage: " .. name)
				end
			end

			toolbox:Destroy()
		end)
	end)
end

return ToolboxService
