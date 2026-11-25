--!strict
--[[
	UpgradeReveal: the short full-screen moment after an upgrade (turning rays, the new thing in
	3D, its name and what changed). Tap closes it; it also closes by itself. A new one replaces
	the one on screen. Display only.

	  Show({ Model, Head, Name, Detail, Color, Seconds? })   takes over the model
	  Sparks(player, color)                                  sparks around a character
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)

local AudioController = require(script.Parent.Parent.AudioController)
local Preview = require(script.Parent.Preview)
local Theme = require(script.Parent.Theme)

export type Content = {
	Model: Model,
	Head: string,
	Name: string,
	Detail: string,
	Color: Color3,
	Seconds: number?,
}

local UpgradeReveal = {}

local GUI_NAME = "JunkshotUpgradeReveal"
local rgb = Color3.fromRGB
local NIGHT = rgb(16, 20, 38)

function UpgradeReveal.Sparks(player: Player, color: Color3)
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Position = Vector3.new(0, 0.5, 1)
	holder.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(45)
	task.delay(1.5, holder.Destroy, holder)
end

local token = 0
function UpgradeReveal.Show(content: Content)
	token += 1
	local mine = token
	local color = content.Color
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local before = playerGui:FindFirstChild(GUI_NAME)
	if before ~= nil then
		before:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local shade = Instance.new("TextButton")
	shade.Name = "UpgradeReveal"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = NIGHT
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade:SetAttribute("Dressed", true) -- no button look
	shade:AddTag("JunkshotMenu")
	shade.Parent = gui

	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.44)
	stage.Size = UDim2.fromScale(0.62, 0.62)
	stage.BackgroundTransparency = 1
	stage.Parent = shade
	local square = Instance.new("UIAspectRatioConstraint")
	square.Parent = stage
	local stageScale = Instance.new("UIScale")
	stageScale.Scale = 0.2
	stageScale.Parent = stage

	local rays = Instance.new("Frame")
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.5, 1.5)
	rays.BackgroundTransparency = 1
	rays.Parent = stage
	for index = 0, 5 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.06, 1)
		ray.Rotation = index * 30
		ray.BackgroundColor3 = color
		ray.BorderSizePixel = 0
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
	end
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.8, 0.8)
	disc.BackgroundColor3 = color:Lerp(NIGHT, 0.6)
	disc.BackgroundTransparency = 0.25
	Theme.Corner(disc, UDim.new(1, 0))
	Theme.Stroke(disc, color, 4)
	disc.Parent = stage

	local viewport = Instance.new("ViewportFrame")
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(0.9, 0.9)
	Preview.StyleViewport(viewport)
	viewport.Parent = stage
	content.Model.Parent = viewport
	local box, size = content.Model:GetBoundingBox()
	local center = box.Position
	local distance = math.max(size.Magnitude * 1.45, 2)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local function label(name: string, text: string, y: number, height: number, textColor: Color3, max: number)
		local l = Theme.Label({
			Name = name,
			Text = text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(0.8, height),
			Color = textColor,
			MinTextSize = 12,
			MaxTextSize = max,
			Parent = shade,
		})
		Theme.TextStroke(l, NIGHT, 3)
	end
	label("Head", content.Head, 0.1, 0.09, rgb(255, 214, 90), 44)
	label("UpgradeName", content.Name, 0.8, 0.1, color:Lerp(Color3.new(1, 1, 1), 0.4), 48)
	label("Detail", content.Detail, 0.885, 0.07, rgb(255, 255, 255), 30)
	label("Tap", "tap to continue", 0.95, 0.04, rgb(180, 190, 220), 16)
	gui.Parent = playerGui

	TweenService:Create(shade, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stageScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local family, pitch = ItemSounds.ForEvent("PackUpgrade")
	AudioController.PlayItem(family, pitch, nil, 1)
	local started = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		rays.Rotation = t * 25
		local angle = t * 0.9 - 6 * math.exp(-t * 2.5) -- a fast turn that settles
		camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(angle), 0.3, math.cos(angle)).Unit * distance, center)
	end)
	gui.Destroying:Connect(function()
		connection:Disconnect()
	end)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		for _, d in shade:GetChildren() do
			if d:IsA("TextLabel") then
				d.Visible = false
			end
		end
		TweenService:Create(shade, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stageScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.22, gui.Destroy, gui)
	end
	shade.Activated:Connect(function()
		if os.clock() - started > 0.5 then
			close()
		end
	end)
	task.delay(content.Seconds or 5, function()
		if mine == token then
			close()
		end
	end)
end

return UpgradeReveal
