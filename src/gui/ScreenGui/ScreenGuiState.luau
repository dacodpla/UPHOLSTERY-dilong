-- Shared HUD state module.
-- ScreenGuiInit controls deferred mode; the three stat scripts listen to FlushEvent.
local State = {}

State.deferred   = false
State.FlushEvent = Instance.new("BindableEvent")

function State.BeginDeferred()
	State.deferred = true
end

function State.Flush()
	State.deferred = false
	State.FlushEvent:Fire()
end

return State
