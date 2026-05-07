--[[
	LaptopPromptConfig (Server Script)
	Ensures every laptop ProximityPrompt has the correct settings ON THE SERVER
	so they replicate properly to all clients (fixes team-test inconsistency).
]]

local function configurePrompt(prompt)
	prompt.ActionText            = "Use"
	prompt.ObjectText            = "Laptop"
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Exclusivity           = Enum.ProximityPromptExclusivity.AlwaysShow
end

local function setupLaptop(laptopModel)
	local screenPart = laptopModel:FindFirstChild("Screen", true)
	if not screenPart or not screenPart:IsA("BasePart") then return end

	local prompt = screenPart:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		configurePrompt(prompt)
	end
end

-- Handle laptops already in Workspace
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "Laptop" then
		setupLaptop(child)
	end
end

-- Handle laptops added later (streaming / late load)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Laptop" then
		task.defer(function()
			setupLaptop(child)
		end)
	end
end)

-- Handle Screen descendants that stream in after the model
workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Screen" and descendant:IsA("BasePart") then
		local laptopModel = descendant.Parent
		if laptopModel and laptopModel.Name == "Laptop" then
			local prompt = descendant:FindFirstChildWhichIsA("ProximityPrompt")
			if prompt then
				configurePrompt(prompt)
			end
		end
	end
end)