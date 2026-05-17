--[[
	Leaderboard (placeholder)
	Populates the default Roblox Tab-key scoreboard with usd, followers, and reputation.
	Mirrors values from each player's PlayerData folder so the board stays live.
]]

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name   = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name   = "Cash"
	cash.Parent = leaderstats

	local followers = Instance.new("IntValue")
	followers.Name   = "Followers"
	followers.Parent = leaderstats

	local rep = Instance.new("NumberValue")
	rep.Name   = "Rep"
	rep.Parent = leaderstats

	local pd = player:WaitForChild("PlayerData", 15)
	if not pd then
		warn("[Leaderboard] PlayerData never arrived for", player.Name)
		return
	end

	local usdVal  = pd:WaitForChild("usd",        10)
	local follVal = pd:WaitForChild("followers",   10)
	local repVal  = pd:WaitForChild("reputation",  10)

	if usdVal  then
		cash.Value = usdVal.Value
		usdVal.Changed:Connect(function(v) cash.Value = v end)
	end
	if follVal then
		followers.Value = follVal.Value
		follVal.Changed:Connect(function(v) followers.Value = v end)
	end
	if repVal  then
		local function syncRep(v)
			rep.Value = math.round(v * 10) / 10   -- one decimal place (e.g. 3.2)
		end
		syncRep(repVal.Value)
		repVal.Changed:Connect(syncRep)
	end
end)
