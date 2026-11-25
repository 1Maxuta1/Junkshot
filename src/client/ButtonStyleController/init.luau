--!strict
--[[
	ButtonStyleController: the look of every button, in one place and easy to take back.

	GameConfig.UI.ButtonStyle
	  "Chunky"   shaded like a thick toy button: light top edge, darker bottom lip, soft gradient;
	             it sinks a little while pressed and brightens under the mouse
	  "Classic"  the flat buttons from before (this module then does nothing at all)

	Only decoration is added (children and a gradient); sizes, colors and actions stay with the
	code that made the button. Hotbar slots and full-screen buttons are left alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local ButtonStyleController = {}

local MAX_HEIGHT = 84 -- taller buttons are cards or pages, not buttons
local MIN_HEIGHT = 24
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function strip(name: string, position: UDim2, size: UDim2, color: Color3, transparency: number, radius: UDim): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = 0 -- under the button's own label
	frame.Active = false
	frame.Interactable = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
	return frame
end

local function dress(button: TextButton)
	if button:GetAttribute("Dressed") == true or button.Text ~= "" or button:FindFirstAncestor("Hotbar") ~= nil then
		return
	end
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner == nil or button:FindFirstChildOfClass("UIStroke") == nil then
		return
	end
	local height = button.AbsoluteSize.Y
	if height < MIN_HEIGHT or height > MAX_HEIGHT then
		return
	end
	button:SetAttribute("Dressed", true)

	local gradient = Instance.new("UIGradient")
	gradient.Name = "StyleGradient"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(240, 240, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 205, 212)),
	})
	gradient.Parent = button

	local radius = corner.CornerRadius
	strip("StyleLip", UDim2.new(0, 2, 1, -7), UDim2.new(1, -4, 0, 5), Color3.new(0, 0, 0), 0.78, radius).Parent = button
	strip("StyleShine", UDim2.new(0, 5, 0, 3), UDim2.new(1, -10, 0.3, 0), Color3.new(1, 1, 1), 0.72, radius).Parent = button

	local scale = button:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	local s = scale :: UIScale
	local function to(value: number, info: TweenInfo)
		TweenService:Create(s, info, { Scale = value }):Play()
	end
	button.MouseButton1Down:Connect(function()
		to(0.93, PRESS)
	end)
	button.MouseButton1Up:Connect(function()
		to(1, RELEASE)
	end)
	button.MouseEnter:Connect(function()
		gradient.Offset = Vector2.new(0, 0.18)
	end)
	button.MouseLeave:Connect(function()
		gradient.Offset = Vector2.zero
		to(1, RELEASE)
	end)
end

-- Buttons inside closed windows have no size yet: they are dressed when they get one.
local function watch(instance: Instance)
	if not instance:IsA("TextButton") then
		return
	end
	dress(instance)
	if instance:GetAttribute("Dressed") ~= true then
		local connection: RBXScriptConnection
		connection = instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			dress(instance)
			if instance:GetAttribute("Dressed") == true then
				connection:Disconnect()
			end
		end)
	end
end

function ButtonStyleController.Start()
	if GameConfig.UI.ButtonStyle ~= "Chunky" then
		return
	end
	task.spawn(function()
		local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui.DescendantAdded:Connect(function(instance: Instance)
			task.defer(watch, instance) -- its corner and stroke are added right after it
		end)
		for _, instance in gui:GetDescendants() do
			watch(instance)
		end
	end)
end

return ButtonStyleController
