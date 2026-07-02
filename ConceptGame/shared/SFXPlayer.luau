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

local _folder  = ReplicatedStorage:WaitForChild("SFX", 4)
local _looping = {}   -- [name] = cloned Sound currently playing as a loop

function SFXPlayer.Play(name)
	if not _folder then return end
	local sound = _folder:FindFirstChild(name)
	if not sound then return end
	SoundService:PlayLocalSound(sound)
end

function SFXPlayer.PlayLooping(name)
	if not _folder then return end
	if _looping[name] then return end
	local src = _folder:FindFirstChild(name)
	if not src then return end
	local clone = src:Clone()
	clone.Looped = true
	clone.Parent = SoundService
	clone:Play()
	_looping[name] = clone
end

function SFXPlayer.Stop(name)
	local clone = _looping[name]
	if not clone then return end
	clone:Stop()
	clone:Destroy()
	_looping[name] = nil
end

return SFXPlayer
