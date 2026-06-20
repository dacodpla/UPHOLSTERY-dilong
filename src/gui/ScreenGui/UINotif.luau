local TweenService = game:GetService("TweenService")

local FLOAT_PX   = 48
local DURATION   = 1
local TWEEN_INFO = TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local UINotif = {}

-- Spawns a floating "+X" label anchored to the right side of anchorFrame.
function UINotif.spawn(screenGui: ScreenGui, anchorFrame: GuiObject, text: string, color: Color3)
	local absPos  = anchorFrame.AbsolutePosition
	local absSize = anchorFrame.AbsoluteSize

	local startX = absPos.X + absSize.X + 10
	local startY = absPos.Y + absSize.Y * 0.5 - 14

	local label = Instance.new("TextLabel")
	label.Size              = UDim2.fromOffset(0, 28)
	label.AutomaticSize     = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.TextColor3        = color
	label.TextTransparency  = 0
	label.Text              = text
	label.Font              = Enum.Font.GothamBold
	label.TextSize          = 48
	label.TextXAlignment    = Enum.TextXAlignment.Left
	label.ZIndex            = 100
	label.Position          = UDim2.fromOffset(startX, startY)
	label.Parent            = screenGui

	TweenService:Create(label, TWEEN_INFO, {
		Position        = UDim2.fromOffset(startX, startY - FLOAT_PX),
		TextTransparency = 1,
	}):Play()

	task.delay(DURATION, function()
		label:Destroy()
	end)
end

return UINotif
