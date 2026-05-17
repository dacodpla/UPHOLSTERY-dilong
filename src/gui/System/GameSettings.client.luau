-- Disable the reset character button.
-- SetCore can fail if called before CoreGui is ready, so retry until it succeeds.
local StarterGui = game:GetService("StarterGui")
local ok = false
while not ok do
	ok = pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
	if not ok then task.wait() end
end
