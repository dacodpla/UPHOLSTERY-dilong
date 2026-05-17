--[[
	SFXPlayer
	Thin wrapper for playing 2-D (non-positional) UI sounds from ReplicatedStorage.SFX.

	Expected Sound instances to add in Studio under ReplicatedStorage > SFX:
	  TackHit, TackPerfect, TackMiss
	  StaplePerfect, StapleGood, StapleMiss
	  StitchThread, StitchComplete
	  FoamSnap, FoamRotate
	  ResultPerfect, ResultGood, ResultPass, ResultFail

	If the SFX folder or a specific Sound is missing, Play() does nothing.
	Set SoundId + Volume on each Sound in Studio; this module only triggers playback.
]]

local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SFXPlayer = {}

-- WaitForChild with a short timeout so we don't block forever in dev environments.
local _folder = ReplicatedStorage:WaitForChild("SFX", 4)

function SFXPlayer.Play(name)
	if not _folder then return end
	local sound = _folder:FindFirstChild(name)
	if not sound then return end
	SoundService:PlayLocalSound(sound)
end

return SFXPlayer
