--!strict
--[[
	PaintController: painting with a Paint Bucket in the hand.

	  target   the nearest of your own placed objects in reach gets an outline (GetTarget)
	  Open()   the paint window (the action chip / G, ItemController): 3D preview in the chosen
	           color, color field (saturation x brightness) and hue bar to drag, ready colors,
	           PAINT IT and ORIGINAL. The server checks and paints (ItemPaint).
	  splash   drops in the new color and a sound when any object near you is painted
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DeployModels = require(ReplicatedStorage.Shared.Util.DeployModels)
local Paint = require(ReplicatedStorage.Shared.Util.Paint)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local AudioController = require(script.Parent.AudioController)
local CarryController = require(script.Parent.CarryController)
local Window = require(script.Parent.EconomyController.Window)
local Preview = require(script.Parent.UI.Preview)
local Theme = require(script.Parent.UI.Theme)

local PaintController = {}

PaintController.TargetChanged = Signal.new()

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
local PRESETS = {
	rgb(235, 60, 55), rgb(255, 120, 40), rgb(255, 205, 50), rgb(140, 220, 60), rgb(50, 180, 90), rgb(40, 200, 200),
	rgb(60, 150, 245), rgb(50, 70, 190), rgb(140, 80, 230), rgb(255, 90, 180), rgb(250, 160, 200), rgb(140, 85, 45),
	rgb(250, 250, 250), rgb(160, 168, 180), rgb(80, 86, 98), rgb(24, 25, 32), rgb(212, 175, 70), rgb(120, 20, 40),
}

local target: Model? = nil
local outline: Highlight? = nil
local window: any = nil
local openFor: string? = nil -- uid of the object in the window
local hue, saturation, value = 0.6, 0.8, 0.95
local redraw: () -> () = function() end

local function bucketUid(): string?
	local selected = CarryController.GetSelected()
	return if selected ~= nil and selected.Id == Paint.ITEM then selected.Uid else nil
end

function PaintController.GetTarget(): Model?
	return target
end

local function findTarget(): Model?
	if bucketUid() == nil then
		return nil
	end
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local folder = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if root == nil or not root:IsA("BasePart") or folder == nil or (humanoid ~= nil and humanoid.SeatPart ~= nil) then
		return nil
	end
	local best: Model?, bestDistance = nil, GameConfig.Paint.Reach
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == localPlayer.UserId then
			local distance = (model:GetPivot().Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

local function setTarget(model: Model?)
	if model == target then
		return
	end
	target = model
	if outline == nil then
		local h = Instance.new("Highlight")
		h.Name = "PaintOutline"
		h.FillTransparency = 1
		h.OutlineColor = rgb(255, 90, 200)
		h.Parent = localPlayer:WaitForChild("PlayerGui")
		outline = h
	end
	local h = outline :: Highlight
	h.Adornee = model
	h.Enabled = model ~= nil
	PaintController.TargetChanged:Fire()
end

local function currentColor(): Color3
	return Color3.fromHSV(hue, saturation, value)
end

-- Drag inside `pad`: onMove gets 0..1 across and down.
local function draggable(pad: GuiButton, onMove: (x: number, y: number) -> ())
	local function apply(position: Vector3)
		local at, size = pad.AbsolutePosition, pad.AbsoluteSize
		onMove(math.clamp((position.X - at.X) / math.max(size.X, 1), 0, 1), math.clamp((position.Y - at.Y) / math.max(size.Y, 1), 0, 1))
	end
	pad.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		apply(input.Position)
		local moved, ended
		moved = UserInputService.InputChanged:Connect(function(change: InputObject)
			if change == input or (input.UserInputType == Enum.UserInputType.MouseButton1 and change.UserInputType == Enum.UserInputType.MouseMovement) then
				apply(change.Position)
			end
		end)
		ended = UserInputService.InputEnded:Connect(function(done: InputObject)
			if done == input or (input.UserInputType == Enum.UserInputType.MouseButton1 and done.UserInputType == Enum.UserInputType.MouseButton1) then
				moved:Disconnect()
				ended:Disconnect()
			end
		end)
	end)
end

local function box(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function pad(parent: Instance, name: string, position: UDim2, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.Position = position
	b.Size = size
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b:SetAttribute("Dressed", true) -- no button look
	Theme.Corner(b, UDim.new(0, 12))
	Theme.Stroke(b, Theme.Colors.Ink, 3)
	b.Parent = parent
	return b
end

local function knob(parent: Instance): Frame
	local k = box(parent, "Knob", UDim2.new(), UDim2.fromOffset(20, 20), Color3.new(1, 1, 1))
	k.AnchorPoint = Vector2.new(0.5, 0.5)
	k.ZIndex = 5
	Theme.Corner(k, UDim.new(1, 0))
	Theme.Stroke(k, Theme.Colors.Ink, 3)
	return k
end

local function mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotPaint"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9
	window = Window.Mount(gui, "PaintWindow", "PAINT", { "PAINT" })
	local w = window
	w.Content("PAINT").Visible = false -- this window draws its own body

	local body = box(w.Root, "Body", UDim2.fromOffset(0, 46), UDim2.new(1, 0, 1, -98), Theme.Colors.Panel)
	body.BackgroundTransparency = 1
	-- Preview
	local stage = box(body, "Stage", UDim2.new(), UDim2.new(0.42, -8, 1, 0), Color3.new(1, 1, 1))
	Theme.Corner(stage, UDim.new(0, 14))
	Theme.Stroke(stage, Theme.Colors.Ink, 3)
	local stageShade = Instance.new("UIGradient")
	stageShade.Rotation = 90
	stageShade.Color = ColorSequence.new(rgb(78, 98, 150), rgb(26, 33, 58))
	stageShade.Parent = stage
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Size = UDim2.fromScale(1, 1)
	Preview.StyleViewport(viewport)
	viewport.Parent = stage

	-- Color field: hue underneath, white from the left, black from below
	local field = pad(body, "Field", UDim2.new(0.42, 8, 0, 0), UDim2.new(0.58, -8, 0.5, 0))
	local white = box(field, "White", UDim2.new(), UDim2.fromScale(1, 1), Color3.new(1, 1, 1))
	Theme.Corner(white, UDim.new(0, 12))
	local whiteFade = Instance.new("UIGradient")
	whiteFade.Transparency = NumberSequence.new(0, 1)
	whiteFade.Parent = white
	local black = box(field, "Black", UDim2.new(), UDim2.fromScale(1, 1), Color3.new(0, 0, 0))
	black.ZIndex = 2
	Theme.Corner(black, UDim.new(0, 12))
	local blackFade = Instance.new("UIGradient")
	blackFade.Rotation = 90
	blackFade.Transparency = NumberSequence.new(1, 0)
	blackFade.Parent = black
	local fieldKnob = knob(field)
	draggable(field, function(x, y)
		saturation, value = x, 1 - y
		redraw()
	end)

	-- Hue bar
	local bar = pad(body, "Hue", UDim2.new(0.42, 8, 0.5, 9), UDim2.new(0.58, -8, 0, 24))
	local rainbow = Instance.new("UIGradient")
	local stops = {}
	for index = 0, 6 do
		table.insert(stops, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(math.min(index / 6, 0.999), 1, 1)))
	end
	rainbow.Color = ColorSequence.new(stops)
	rainbow.Parent = bar
	local barKnob = knob(bar)
	draggable(bar, function(x)
		hue = math.min(x, 0.999)
		redraw()
	end)

	-- Ready colors
	local grid = box(body, "Presets", UDim2.new(0.42, 8, 0.5, 44), UDim2.new(0.58, -8, 0.5, -44), Theme.Colors.Panel)
	grid.BackgroundTransparency = 1
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.CellSize = UDim2.new(1 / 9, -6, 0.5, -6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, color in PRESETS do
		local chip = pad(grid, "Preset", UDim2.new(), UDim2.new())
		chip.LayoutOrder = index
		chip.BackgroundColor3 = color
		chip.Activated:Connect(function()
			hue, saturation, value = color:ToHSV()
			redraw()
		end)
	end

	local original = Window.SmallButton(w.Footer, "ORIGINAL", Theme.Colors.InkSoft, UDim2.new(0.38, -6, 0, 42), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5))
	local confirm = Window.SmallButton(w.Footer, "PAINT IT!  (1 bucket)", Theme.Colors.Success, UDim2.new(0.62, -6, 0, 42), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))
	local function send(hex: string)
		local bucket = bucketUid()
		if bucket ~= nil and openFor ~= nil then
			Remotes.GetEvent("ItemPaint"):FireServer(bucket, openFor, hex)
		end
		w.Close()
	end
	original.Activated:Connect(function()
		send("")
	end)
	confirm.Activated:Connect(function()
		send(Paint.ToHex(currentColor()))
	end)
	w.Closed.Event:Connect(function()
		openFor = nil
		viewport:ClearAllChildren()
	end)

	redraw = function()
		local color = currentColor()
		field.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		fieldKnob.Position = UDim2.fromScale(saturation, 1 - value)
		fieldKnob.BackgroundColor3 = color
		barKnob.Position = UDim2.fromScale(hue, 0.5)
		barKnob.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		confirm.BackgroundColor3 = color:Lerp(Theme.Colors.Success, 0.25)
		local model = viewport:FindFirstChildOfClass("Model")
		if model ~= nil then
			Paint.Apply(model, color)
		end
	end

	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	PaintController.Open = function(gamepad: boolean)
		local model = target
		if model == nil then
			return
		end
		local deployModel, uid, itemId = model:GetAttribute("DeployModel"), model:GetAttribute("DeployUid"), model:GetAttribute("ItemId")
		if type(deployModel) ~= "string" or type(uid) ~= "string" or not DeployModels.Exists(deployModel) then
			return
		end
		w.Open(nil, gamepad)
		w.Content("PAINT").Visible = false
		openFor = uid
		w.SetTitle(`PAINT  ·  {ItemConfig.GetDisplayName(itemId)}`)
		local now = model:GetAttribute("PaintColor")
		if typeof(now) == "Color3" then
			hue, saturation, value = now:ToHSV()
		end
		Preview.Model(viewport, DeployModels.Build(deployModel, false))
		redraw()
	end
end

function PaintController.Open(_gamepad: boolean) end -- set when the window exists

local function splash(model: Model)
	local color = model:GetAttribute("PaintColor")
	local base = model.PrimaryPart
	if base == nil then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = base
	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/smoke_main.dds"
	drops.Color = ColorSequence.new(if typeof(color) == "Color3" then color else rgb(235, 240, 250))
	drops.Size = NumberSequence.new(1.2, 0.2)
	drops.Transparency = NumberSequence.new(0.1, 1)
	drops.Lifetime = NumberRange.new(0.5, 0.9)
	drops.Speed = NumberRange.new(6, 12)
	drops.SpreadAngle = Vector2.new(180, 180)
	drops.Acceleration = Vector3.new(0, -14, 0)
	drops.Rate = 0
	drops.Parent = holder
	drops:Emit(36)
	task.delay(1.5, holder.Destroy, holder)
	local family, pitch = ItemSounds.ForEvent("Paint")
	AudioController.PlayItem(family, pitch, base, 1)
	-- A flash in the new color
	local flash = Instance.new("Highlight")
	flash.FillColor = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
	flash.FillTransparency = 0.1
	flash.OutlineTransparency = 1
	flash.Adornee = model
	flash.Parent = localPlayer:WaitForChild("PlayerGui")
	local tween = TweenService:Create(flash, TweenInfo.new(0.6), { FillTransparency = 1 })
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	tween:Play()
end

local function watchObjects()
	local folder = Workspace:WaitForChild(PlacementRules.DEPLOYED_FOLDER, 60)
	if folder == nil then
		return
	end
	local function add(model: Instance)
		if model:IsA("Model") then
			model:GetAttributeChangedSignal("PaintColor"):Connect(function()
				splash(model)
			end)
		end
	end
	for _, model in folder:GetChildren() do
		add(model)
	end
	folder.ChildAdded:Connect(add)
end

function PaintController.Start()
	task.spawn(mount)
	task.spawn(watchObjects)
	task.spawn(function()
		while true do
			task.wait(0.2)
			setTarget(findTarget())
			if window ~= nil and window.IsOpen() and bucketUid() == nil then
				window.Close() -- the bucket is gone
			end
		end
	end)
end

return PaintController
