--!strict
--[[
	Theme: colors, fonts and small builders shared by every UI module, so the whole HUD
	keeps one look (bright winter junkyard: white panels, deep blue outlines, warm accents).
]]

local TweenService = game:GetService("TweenService")

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.Colors = table.freeze({
	Panel = rgb(248, 251, 255),
	PanelTint = rgb(226, 238, 255),
	Ink = rgb(24, 44, 86), -- outlines and dark text
	InkSoft = rgb(84, 106, 150),
	White = rgb(255, 255, 255),
	Accent = rgb(255, 150, 30), -- orange: selection, primary action
	AccentDark = rgb(204, 98, 0),
	Sun = rgb(255, 205, 50),
	Ice = rgb(70, 160, 255),
	Success = rgb(52, 196, 110),
	Danger = rgb(236, 72, 72),
})

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamBold

function Theme.Corner(parent: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0.25, 0)
	corner.Parent = parent
	return corner
end

function Theme.Stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Ink
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.TextStroke(parent: TextLabel | TextButton, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Ink
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = parent
	return stroke
end

-- Scaled text that never gets smaller than minSize pixels (readability on phones).
function Theme.Label(props: {
	Name: string,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Font: Enum.Font?,
	MinTextSize: number?,
	MaxTextSize: number?,
	XAlignment: Enum.TextXAlignment?,
	Parent: Instance,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.Name
	label.Text = props.Text
	label.Size = props.Size
	label.Position = props.Position or UDim2.new()
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.TextColor3 = props.Color or Theme.Colors.Ink
	label.Font = props.Font or Theme.Font
	label.TextScaled = true
	label.TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinTextSize or 14
	constraint.MaxTextSize = props.MaxTextSize or 40
	constraint.Parent = label

	label.Parent = props.Parent
	return label
end

-- A short pop for a window that has just become visible.
function Theme.PopIn(frame: GuiObject)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	local s = scale :: UIScale
	s.Scale = 0.82
	TweenService:Create(s, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Shrinks a window and calls `done` when it is gone.
function Theme.PopOut(frame: GuiObject, done: () -> ())
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale == nil then
		done()
		return
	end
	local tween = TweenService:Create(scale, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	tween.Completed:Once(done)
	tween:Play()
end

-- The rows of a list come in one after another.
function Theme.Stagger(list: Instance)
	if game:GetService("Players").LocalPlayer:GetAttribute("LiteGraphics") == true then
		return -- weak phones: the window pop alone
	end
	local index = 0
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and index < 12 then
			index += 1
			local scale = child:FindFirstChildOfClass("UIScale")
			if scale == nil then
				scale = Instance.new("UIScale")
				scale.Parent = child
			end
			local s = scale :: UIScale
			s.Scale = 0.86
			TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, index * 0.028), { Scale = 1 }):Play()
		end
	end
end

return table.freeze(Theme)
