--[[
    MoneyMaker_Tab.client.luau
    Fetches the shared job pool and renders each job as a cloned JobCard.

    Expected GUI tree — rename your Studio instances to match:
      LaptopGui → LaptopScreen → Apps → MoneyMaker_Tab
        └── JobCard  (Frame, Visible = false — template, never shown directly)
                ├── UIListLayout
                ├── NameLabel      (TextLabel)  ← job.name
                ├── DetailsLabel   (TextLabel)  ← job.details
                ├── TierLabel      (TextLabel)  ← job.tier
                ├── PayLabel       (TextLabel)  ← job.pay
                └── FollowersLabel (TextLabel)  ← job.followers

    If MoneyMaker_Tab also has a UIListLayout, cloned cards will stack
    automatically. Otherwise add one manually in Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local SFX               = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SFXPlayer"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MoneyMaker_Tab  = playerGui
    :WaitForChild("LaptopGui")
    :WaitForChild("LaptopScreen")
    :WaitForChild("Apps")
    :WaitForChild("MoneyMaker_Tab")

local scrollFrame     = MoneyMaker_Tab:WaitForChild("JobListScroll")
local jobCardTemplate = scrollFrame:WaitForChild("JobCardTemplate")

local LaptopRemotes          = ReplicatedStorage:WaitForChild("LaptopRemotes")
local RequestJobs            = LaptopRemotes:WaitForChild("RequestJobs")
local AcceptJob              = LaptopRemotes:WaitForChild("AcceptJob")
local JobBoardRefresh        = LaptopRemotes:WaitForChild("JobBoardRefresh")
local RequestLocationsByTier = LaptopRemotes:WaitForChild("RequestLocationsByTier")

local _locationsByTier = {}

-- "StudioApartment" → "Studio Apartment"
local function splitCamelCase(s)
	return (s:gsub("(%l)(%u)", "%1 %2"))
end

local TIER_COLOR = {
    Starter   = Color3.fromRGB(180, 180, 180),
    Mid       = Color3.fromRGB(100, 200, 100),
    Premium   = Color3.fromRGB(80,  160, 220),
    Prestige  = Color3.fromRGB(160, 80,  220),
    Exclusive = Color3.fromRGB(220, 160, 40),
    Elite     = Color3.fromRGB(220, 60,  60),
    Special   = Color3.fromRGB(220, 120, 220),
}

local function clearCards()
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") and child ~= jobCardTemplate then
            child:Destroy()
        end
    end
end

local function populateBoard(jobs)
    clearCards()
    for _, job in ipairs(jobs) do
        local card = jobCardTemplate:Clone()
        card.Name    = "JobCard_" .. job.id
        card.Visible = true

        -- Bespoke jobs show their specific location; procedural jobs show all locations
        -- registered for that tier (the actual slot is chosen randomly among them at accept time).
        local displayName
        if job.locationOverride then
            displayName = splitCamelCase(job.locationOverride)
        else
            local locs = _locationsByTier[job.tier] or {}
            local names = {}
            for _, n in ipairs(locs) do
                table.insert(names, splitCamelCase(n))
            end
            displayName = #names > 0 and table.concat(names, " / ") or job.name
        end
        card:WaitForChild("JobName").Text    = displayName
        card:WaitForChild("JobDetails").Text = job.details
        card:WaitForChild("PayLabel").Text       = "$" .. tostring(job.pay)
        card:WaitForChild("FollowersLabel").Text = "+" .. tostring(job.followers) .. " followers"

        local color = TIER_COLOR[job.tier]
        if color then
            card:WaitForChild("PrestigeHighlight").BackgroundColor3 = color
        end

        local tierLabel = card:FindFirstChild("TierLabel")
        if tierLabel then
            tierLabel.Text = job.tier
        end

        card:WaitForChild("AcceptButton").MouseButton1Click:Connect(function()
            SFX.Play("JobAccept")
            AcceptJob:FireServer(job.id)
        end)

        card.Parent = scrollFrame
    end
end

local function refreshBoard()
    _locationsByTier = RequestLocationsByTier:InvokeServer() or {}
    local jobs = RequestJobs:InvokeServer()
    if jobs then
        populateBoard(jobs)
    end
end

-- Re-render whenever a job is accepted or the pool replenishes
JobBoardRefresh.OnClientEvent:Connect(function()
    SFX.Play("BoardRefresh")
    refreshBoard()
end)

refreshBoard()
