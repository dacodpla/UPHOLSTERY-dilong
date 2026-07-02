--[[
	ConceptRemotes
	Creates (server) or fetches (client) the RemoteEvent folder used by the
	prototype game loop. Same pattern as GrabRemotes.

	Events:
	  ReportMinigameResult  C→S  (sofaModel: Model, result: string)
	  StartMinigame         S→C  (sofaModel: Model, minigameName: string, config: table)
	  ShowJobResult         S→C  (grade: string, elapsedSeconds: number)
	  SofaStateChanged      S→C  (sofaModel: Model, newState: number)
	  FadeScreen            S→C  (no args)
	  FadeIn                S→C  (no args)
	  PlaySound             S→C  (name: string)  — plays a named sound from ReplicatedStorage.SFX
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local FOLDER_NAME = "ConceptRemotes"
local EVENT_NAMES = {
	"ReportMinigameResult",
	"StartMinigame",
	"ShowJobResult",
	"SofaStateChanged",
	"FadeScreen",
	"FadeIn",
	"PlayNPCAnimation",
	"PlayAmbientAnimation",
	"PlaySound",
}

local ConceptRemotes = {}

if RunService:IsServer() then
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in ipairs(EVENT_NAMES) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		ConceptRemotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)
	if folder then
		for _, name in ipairs(EVENT_NAMES) do
			ConceptRemotes[name] = folder:WaitForChild(name, 10)
		end
	else
		warn("[ConceptRemotes] Folder not found within 10 seconds")
	end
end

return ConceptRemotes
