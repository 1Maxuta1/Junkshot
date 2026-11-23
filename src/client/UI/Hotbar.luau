--!strict
--[[
	Hotbar: the carried junk at the bottom of the screen.

	  - GameConfig.Carry.MaxJunk slots; each filled slot shows a 3D preview (ViewportFrame) of
	    its junk. Previews are rebuilt only when that slot's junk changes, never per frame.
	  - The selected slot is outlined in orange and slightly larger; its name shows above.
	  - A capacity pill shows "3/6" and turns red (with a short pulse) when full.
	  - Click / tap a slot to select it. Key hints (1-6, LB/RB) follow the active input type.
	All sizes are Scale-based with min/max constraints, so it reads well from phones to 4K.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local Preview = require(script.Parent.Preview)
local Theme = require(script.Parent.Theme)

type Slot = {
	Frame: Frame,
	Stroke: UIStroke,
	Scale: UIScale,
	Viewport: ViewportFrame,
	KeyLabel: TextLabel,
	Uid: string?,
}

export type Hotbar = {
	Update: (list: { { Uid: string, Id: string } }, selectedIndex: number, capacity: number?) -> (),
	SetInputKind: (kind: string) -> (),
	PulseFull: () -> (),
	SlotClicked: BindableEvent,
}

local Hotbar = {}

function Hotbar.Mount(screenGui: ScreenGui): Hotbar
	-- Slots for the largest possible capacity; only `capacity` of them are shown.
	local maxSlots = GameConfig.Carry.MaxJunk + PlayerUpgrades.MaxCarryBonus()
	local capacity = GameConfig.Carry.MaxJunk
	local slotClicked = Instance.new("BindableEvent")

	local root = Instance.new("Frame")
	root.Name = "Hotbar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -10)
	root.Size = UDim2.fromScale(0.44, 0.17)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 5.2
	aspect.Parent = root
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(290, 56)
	sizeLimit.MaxSize = Vector2.new(640, 123)
	sizeLimit.Parent = root

	-- Header row: capacity pill on the left, selected junk name in the middle.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.3)
	header.BackgroundTransparency = 1
	header.Parent = root

	local pill = Instance.new("Frame")
	pill.Name = "Capacity"
	pill.Size = UDim2.fromScale(0.2, 0.9)
	pill.BackgroundColor3 = Theme.Colors.Ink
	Theme.Corner(pill, UDim.new(1, 0))
	pill.Parent = header
	local pillScale = Instance.new("UIScale")
	pillScale.Parent = pill
	local capacityLabel = Theme.Label({
		Name = "Text",
		Text = `0/{maxSlots}`,
		Size = UDim2.fromScale(0.9, 0.9),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 26,
		Parent = pill,
	})

	local nameLabel = Theme.Label({
		Name = "Selected",
		Text = "",
		Size = UDim2.fromScale(0.56, 0.9),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 26,
		Parent = header,
	})
	Theme.TextStroke(nameLabel, Theme.Colors.Ink, 2)

	-- Slot row.
	local row = Instance.new("Frame")
	row.Name = "Slots"
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.fromScale(0, 1)
	row.Size = UDim2.fromScale(1, 0.68)
	row.BackgroundTransparency = 1
	row.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.018, 0)
	layout.Parent = row

	-- Gamepad bumper hints at both ends.
	local function bumperHint(name: string, text: string, order: number): TextLabel
		local hint = Theme.Label({
			Name = name,
			Text = text,
			Size = UDim2.fromScale(0.05, 0.5),
			Color = Theme.Colors.White,
			MinTextSize = 12,
			MaxTextSize = 22,
			Parent = row,
		})
		hint.LayoutOrder = order
		Theme.TextStroke(hint, Theme.Colors.Ink, 2)
		hint.Visible = false
		return hint
	end
	local leftHint = bumperHint("PrevHint", "LB", 0)
	local rightHint = bumperHint("NextHint", "RB", maxSlots + 1)

	local slots: { Slot } = {}
	for index = 1, maxSlots do
		local frame = Instance.new("Frame")
		frame.Name = `Slot{index}`
		frame.LayoutOrder = index
		frame.Size = UDim2.fromScale(0.13, 1)
		frame.BackgroundColor3 = Theme.Colors.Panel
		frame.BackgroundTransparency = 0.25
		Theme.Corner(frame, UDim.new(0.22, 0))
		local stroke = Theme.Stroke(frame, Theme.Colors.Ink, 2.5)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = frame
		local scale = Instance.new("UIScale")
		scale.Parent = frame

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Preview"
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.52)
		viewport.Size = UDim2.fromScale(0.86, 0.86)
		Preview.StyleViewport(viewport)
		viewport.Parent = frame

		local keyLabel = Theme.Label({
			Name = "Key",
			Text = tostring(index),
			Size = UDim2.fromScale(0.34, 0.34),
			Position = UDim2.fromScale(0.04, 0.02),
			Color = Theme.Colors.InkSoft,
			MinTextSize = 10,
			MaxTextSize = 18,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local button = Instance.new("TextButton")
		button.Name = "Hitbox"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Parent = frame
		button.Activated:Connect(function()
			slotClicked:Fire(index)
		end)

		frame.Parent = row
		table.insert(slots, {
			Frame = frame,
			Stroke = stroke,
			Scale = scale,
			Viewport = viewport,
			KeyLabel = keyLabel,
			Uid = nil,
		})
	end

	local wasFull = false
	local selectTween: Tween? = nil

	local function pulseFull()
		pillScale.Scale = 1.25
		TweenService:Create(pillScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	local function applyCapacity(newCapacity: number)
		capacity = math.clamp(newCapacity, 1, maxSlots)
		local width = math.min(0.13, 0.84 / capacity)
		for index, slot in slots do
			slot.Frame.Visible = index <= capacity
			slot.Frame.Size = UDim2.fromScale(width, 1)
		end
	end

	local function update(list: { { Uid: string, Id: string } }, selectedIndex: number, newCapacity: number?)
		if newCapacity ~= nil and newCapacity ~= capacity then
			applyCapacity(newCapacity)
		end
		local count = #list
		capacityLabel.Text = `{count}/{capacity}`
		local full = count >= capacity
		pill.BackgroundColor3 = if full then Theme.Colors.Danger else Theme.Colors.Ink
		if full and not wasFull then
			pulseFull()
		end
		wasFull = full

		for index, slot in slots do
			local entry = list[index]
			local uid = if entry ~= nil then entry.Uid else nil
			if uid ~= slot.Uid then
				slot.Uid = uid
				if entry ~= nil then
					Preview.Junk(slot.Viewport, entry.Id)
				else
					slot.Viewport:ClearAllChildren()
				end
			end

			local selected = index == selectedIndex and entry ~= nil
			slot.Frame.BackgroundTransparency = if entry ~= nil then 0.05 else 0.45
			slot.Frame.BackgroundColor3 = if selected then Color3.fromRGB(255, 236, 200) else Theme.Colors.Panel
			-- Unselected slots show the item's rarity (Common keeps the plain outline).
			local rarity = if entry ~= nil then ItemConfig.GetRarity(entry.Id) else nil
			local rarityColor = if rarity ~= nil and rarity ~= "Common" then Rarities.GetColor(rarity) else Theme.Colors.Ink
			slot.Stroke.Color = if selected then Theme.Colors.Accent else rarityColor
			slot.Stroke.Thickness = if selected then 4 else 2.5
			local targetScale = if selected then 1.1 else 1
			if slot.Scale.Scale ~= targetScale then
				if selected then
					if selectTween ~= nil then
						selectTween:Cancel()
					end
					slot.Scale.Scale = 1
					selectTween = TweenService:Create(slot.Scale, TweenInfo.new(0.12), { Scale = targetScale })
					selectTween:Play()
				else
					slot.Scale.Scale = targetScale
				end
			end
		end

		local selectedEntry = list[selectedIndex]
		if selectedEntry ~= nil then
			local definition = ItemConfig.Get(selectedEntry.Id)
			nameLabel.Text = if definition ~= nil then definition.DisplayName else selectedEntry.Id
		else
			nameLabel.Text = if count == 0 then "Pick up junk!" else ""
		end
	end

	local function setInputKind(kind: string)
		local keyboard = kind == "KeyboardMouse"
		for _, slot in slots do
			slot.KeyLabel.Visible = keyboard
		end
		leftHint.Visible = kind == "Gamepad"
		rightHint.Visible = kind == "Gamepad"
	end

	applyCapacity(capacity)
	update({}, 0)

	return {
		Update = update,
		SetInputKind = setInputKind,
		PulseFull = pulseFull,
		SlotClicked = slotClicked,
	}
end

return Hotbar
