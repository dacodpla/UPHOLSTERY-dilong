local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local ConceptRemotes = require(Shared:WaitForChild("ConceptRemotes"))
local ConceptConfig  = require(Shared:WaitForChild("ConceptConfig"))

local jobPlayer = nil
local startTime = nil

local JobService = {}

function JobService.Init()
	-- nothing to init
end

function JobService.StartJob(player)
	jobPlayer = player
	startTime = os.clock()
end

function JobService.CheckCompletion()
	if not jobPlayer then return end
	if #CollectionService:GetTagged("ConceptSofa") > 0 then return end
	JobService.CompleteJob()
end

function JobService.CompleteJob()
	if not jobPlayer then return end

	local elapsed = os.clock() - (startTime or os.clock())
	local par     = ConceptConfig.PrototypeParTime
	local ratio   = elapsed / par

	local grade
	if ratio <= ConceptConfig.GradeThresholds.Perfect then
		grade = "Perfect"
	elseif ratio <= ConceptConfig.GradeThresholds.Good then
		grade = "Good"
	elseif ratio <= ConceptConfig.GradeThresholds.Pass then
		grade = "Pass"
	else
		grade = "Fail"
	end

	ConceptRemotes.ShowJobResult:FireClient(jobPlayer, grade, elapsed)
	jobPlayer = nil
	startTime = nil
end

return JobService
