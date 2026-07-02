local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))
local MinigameRunner = require(Shared:WaitForChild("Minigames"):WaitForChild("MinigameRunner"))
local ConceptHUD     = require(script.Parent.ConceptHUD)

ConceptRemotes.StartMinigame.OnClientEvent:Connect(function(sofaModel, minigameName, config)
	-- Hide item label and unlock mouse before the minigame starts.
	-- RenderStepped loop re-applies every frame to fight the first-person camera
	-- script, which continuously re-locks the cursor to screen centre.
	local prevBehavior        = UserInputService.MouseBehavior
	local prevMouseIconEnabled = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior      = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled   = true
	ConceptHUD.SetMinigameActive(true)

	local unlockConn = RunService.RenderStepped:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	local result = MinigameRunner.Run(minigameName, config)

	-- Restore everything after the minigame finishes.
	unlockConn:Disconnect()
	UserInputService.MouseBehavior    = prevBehavior
	UserInputService.MouseIconEnabled = prevMouseIconEnabled
	ConceptHUD.SetMinigameActive(false)

	ConceptRemotes.ReportMinigameResult:FireServer(sofaModel, result or "Fail")
end)

return {}
