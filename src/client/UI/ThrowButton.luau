--!strict
--[[
	ThrowButton: the touch-screen throw button (visible only while the input type is Touch).

	Hold = aim (the preview arc follows the camera; turn the camera with another finger),
	release = throw. It sits left of / level with Roblox's jump button and away from the
	screen edges; tune POSITION / SIZE_SCALE below if your device layout differs.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

export type ThrowButton = {
	SetVisible: (visible: boolean) -> (),
	SetEnabled: (enabled: boolean) -> (),
}

local POSITION = UDim2.fromScale(0.8, 0.93) -- anchor: bottom-right corner of the button
local SIZE_SCALE = 0.2 -- of the screen height
local MIN_SIZE = 72
local MAX_SIZE = 132

local ThrowButton = {}

function ThrowButton.Mount(screenGui: ScreenGui, onBegin: () -> (), onEnd: () -> ()): ThrowButton
	local button = Instance.new("TextButton")
	button.Name = "ThrowButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = POSITION
	button.Size = UDim2.fromScale(SIZE_SCALE, SIZE_SCALE)
	button.SizeConstraint = Enum.SizeConstraint.RelativeYY
	button.BackgroundColor3 = Theme.Colors.Accent
	button.AutoButtonColor = false
	button.Text = ""
	button.Visible = false
	Theme.Corner(button, UDim.new(1, 0))
	local stroke = Theme.Stroke(button, Theme.Colors.Ink, 3)

	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(MIN_SIZE, MIN_SIZE)
	limit.MaxSize = Vector2.new(MAX_SIZE, MAX_SIZE)
	limit.Parent = button

	local label = Theme.Label({
		Name = "Label",
		Text = "THROW",
		Size = UDim2.fromScale(0.8, 0.4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 30,
		Parent = button,
	})
	Theme.TextStroke(label, Theme.Colors.AccentDark, 2)

	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.Parent = screenGui

	local activeInput: InputObject? = nil
	local endConnection: RBXScriptConnection? = nil

	local function finish()
		if activeInput == nil then
			return
		end
		activeInput = nil
		if endConnection ~= nil then
			endConnection:Disconnect()
			endConnection = nil
		end
		scale.Scale = 1
		onEnd()
	end

	button.InputBegan:Connect(function(input: InputObject)
		local isPress = input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 -- Studio device emulator
		if not isPress or activeInput ~= nil then
			return
		end
		activeInput = input
		scale.Scale = 0.92
		-- Listen globally: the finger may slide off the button before it is lifted.
		endConnection = UserInputService.InputEnded:Connect(function(ended: InputObject)
			if ended == activeInput then
				finish()
			end
		end)
		onBegin()
	end)

	return {
		SetVisible = function(visible: boolean)
			button.Visible = visible
			if not visible then
				finish()
			end
		end,
		SetEnabled = function(enabled: boolean)
			button.BackgroundColor3 = if enabled then Theme.Colors.Accent else Theme.Colors.InkSoft
			stroke.Transparency = if enabled then 0 else 0.4
		end,
	}
end

return ThrowButton
