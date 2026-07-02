-- src/shared/GrabRemotes.luau
-- Creates RemoteEvents on the server; waits for them on the client.
-- Both sides call Get() to receive the same cached table.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "GrabRemotes"

local EVENT_NAMES = {
	"RequestGrab",      -- C→S: (hitPart: BasePart)
	"RequestRelease",   -- C→S: ()
	"RequestThrow",     -- C→S: (direction: Vector3)
	"GrabConfirmed",    -- S→C: (carryPart: BasePart)
	"GrabFailed",       -- S→C: (reason: string)
	"ReleaseConfirmed", -- S→C: ()
	"ThrowConfirmed",   -- S→C: ()
}

local cache: {[string]: RemoteEvent} = {}

local function Get(): {[string]: RemoteEvent}
	if next(cache) then
		return cache
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name   = FOLDER_NAME
		folder.Parent = ReplicatedStorage

		for _, name in ipairs(EVENT_NAMES) do
			local re = Instance.new("RemoteEvent")
			re.Name   = name
			re.Parent = folder
			cache[name] = re
		end
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)
		assert(folder, "GrabRemotes: folder not found in ReplicatedStorage within 10s")

		for _, name in ipairs(EVENT_NAMES) do
			local re = folder:WaitForChild(name, 10)
			assert(re, "GrabRemotes: RemoteEvent '" .. name .. "' not found within 10s")
			cache[name] = re :: RemoteEvent
		end
	end

	return cache
end

return { Get = Get }
