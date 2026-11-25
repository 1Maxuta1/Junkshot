--!strict
--[[
	Widgets: building blocks shared by the machine panel's tabs, plus the view/action types the
	panel is driven by. Everything is Scale-sized with minimum pixel sizes for touch (44 px).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Types = require(ReplicatedStorage.Shared.Types)
local Preview = require(script.Parent.Parent.Preview)
local Theme = require(script.Parent.Parent.Theme)

-- Everything the panel shows, built by MachineController from the machine's attributes and the
-- local player's own state. Read-only for the UI.
export type View = {
	State: string, -- "Idle" | "Processing" | "RewardReady"
	JobKind: string,
	JobLabel: string,
	StartedAt: number,
	CompletesAt: number,
	ClickLeft: number, -- seconds clicks may still remove from this job
	Duration: number,
	Output: { Types.CarriedJunk },
	OutputCapacity: number,
	Upgrades: { Speed: number, Storage: number, Level: number },
	MachineLevel: number,
	Carried: { Types.CarriedJunk },
	Klunks: number,
	BoostUntil: number,
	InstantCredits: number,
}

-- Requests the panel can make. The server validates every one of them.
export type Actions = {
	Recycle: (uid: string) -> (),
	Craft: (recipeId: string) -> (),
	Mythic: (uidA: string, uidB: string, uidC: string) -> (),
	Accelerate: () -> (),
	Take: (uid: string) -> (),
	Upgrade: (upgradeId: string) -> (),
	BuyProduct: (key: string) -> (),
	BuyPass: (key: string) -> (),
}

export type Tab = {
	Render: (view: View) -> (),
}

local Widgets = {}

function Widgets.FormatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

-- A big rounded button with a scaled label. Returns the button and its label.
function Widgets.Button(props: {
	Name: string,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	MinSize: Vector2?,
	Parent: Instance,
}): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = props.Name
	button.Size = props.Size
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = props.Color or Theme.Colors.Accent
	button.AutoButtonColor = true
	button.Text = ""
	Theme.Corner(button, UDim.new(0, 12))
	Theme.Stroke(button, Theme.Colors.Ink, 2.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = props.MinSize or Vector2.new(44, 44)
	limit.Parent = button
	local label = Theme.Label({
		Name = "Label",
		Text = props.Text,
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 12,
		MaxTextSize = 24,
		Parent = button,
	})
	Theme.TextStroke(label, Theme.Colors.Ink, 1.5)
	button.Parent = props.Parent
	return button, label
end

export type ItemCard = {
	Button: TextButton,
	SetSelected: (selected: boolean) -> (),
}

local STEEL, NIGHT = Color3.fromRGB(52, 66, 98), Color3.fromRGB(26, 33, 54)
Widgets.Night = NIGHT

local function shade(parent: Instance, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), bottom)
	gradient.Parent = parent
end

-- A dark steel panel, like the ones of the chest window (EconomyController/Bag).
function Widgets.SteelPanel(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Position = position
	panel.Size = size
	panel.BackgroundColor3 = STEEL
	panel.BorderSizePixel = 0
	Theme.Corner(panel, UDim.new(0, 12))
	Theme.Stroke(panel, NIGHT, 3)
	shade(panel, Color3.fromRGB(150, 158, 190))
	panel.Parent = parent
	return panel
end

-- The riveted divider with a gear between two panels.
function Widgets.Divider(parent: Instance, x: number)
	local gold = Color3.fromRGB(255, 205, 60)
	local bar = Instance.new("Frame")
	bar.Name = "Divider"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(x, 0.5)
	bar.Size = UDim2.new(0, 8, 1, 0)
	bar.BackgroundColor3 = NIGHT
	bar.BorderSizePixel = 0
	Theme.Corner(bar, UDim.new(1, 0))
	Theme.Stroke(bar, gold, 2)
	for index = 0, 3 do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(0.5, 0.5)
		tooth.Size = UDim2.fromOffset(7, 28)
		tooth.Rotation = index * 45
		tooth.BackgroundColor3 = gold
		tooth.BorderSizePixel = 0
		tooth.ZIndex = 2
		Theme.Corner(tooth, UDim.new(0.2, 0))
		Theme.Stroke(tooth, NIGHT, 1.5)
		tooth.Parent = bar
	end
	for layer, size in { 20, 8 } do
		local disc = Instance.new("Frame")
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromOffset(size, size)
		disc.BackgroundColor3 = if layer == 1 then gold else NIGHT
		disc.BorderSizePixel = 0
		disc.ZIndex = 2 + layer
		Theme.Corner(disc, UDim.new(1, 0))
		if layer == 1 then
			Theme.Stroke(disc, NIGHT, 1.5)
		end
		disc.Parent = bar
	end
	bar.Parent = parent
end

export type IconCell = { Root: TextButton, Stroke: UIStroke, Badge: TextLabel, Viewport: ViewportFrame, Veil: Frame }

-- The icon cell of the chest window: 3D picture on the rarity color, dark name plate, a badge
-- in the corner. Veil darkens it (locked or missing).
function Widgets.IconCell(parent: Instance, itemId: string, layoutOrder: number, onActivated: (() -> ())?): IconCell
	local color = Rarities.GetColor(ItemConfig.GetRarity(itemId))
	local root = Instance.new("TextButton")
	root.Name = itemId
	root.LayoutOrder = layoutOrder
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = color:Lerp(Color3.fromRGB(246, 250, 255), 0.72)
	root:SetAttribute("Dressed", true) -- cells have their own look (ButtonStyleController)
	Theme.Corner(root, UDim.new(0, 10))
	local stroke = Theme.Stroke(root, color, 2.5)
	shade(root, Color3.fromRGB(196, 204, 226))
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Position = UDim2.fromScale(0.06, 0.02)
	viewport.Size = UDim2.fromScale(0.88, 0.68)
	Preview.StyleViewport(viewport)
	viewport.Parent = root
	Preview.Item(viewport, itemId)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Position = UDim2.fromScale(0, 0.69)
	plate.Size = UDim2.fromScale(1, 0.31)
	plate.BackgroundColor3 = NIGHT
	plate.BorderSizePixel = 0
	Theme.Corner(plate, UDim.new(0, 9))
	plate.Parent = root
	local name = Theme.Label({
		Name = "Name",
		Text = ItemConfig.GetDisplayName(itemId),
		Size = UDim2.fromScale(0.94, 0.9),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.55),
		MinTextSize = 9,
		MaxTextSize = 13,
		Parent = plate,
	})
	name.TextWrapped = true
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = NIGHT
	veil.BackgroundTransparency = 0.45
	veil.BorderSizePixel = 0
	veil.ZIndex = 3
	veil.Visible = false
	Theme.Corner(veil, UDim.new(0, 10))
	veil.Parent = root
	local badge = Theme.Label({
		Name = "Badge",
		Text = "",
		Size = UDim2.new(0.6, 0, 0, 18),
		Position = UDim2.new(1, -4, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Color = Color3.new(1, 1, 1),
		MinTextSize = 11,
		MaxTextSize = 17,
		XAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	badge.ZIndex = 4
	Theme.TextStroke(badge, NIGHT, 2)
	if onActivated ~= nil then
		local scale = Instance.new("UIScale")
		scale.Parent = root
		local function to(value: number, seconds: number)
			TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = value }):Play()
		end
		root.MouseButton1Down:Connect(function()
			to(0.93, 0.08)
		end)
		root.MouseButton1Up:Connect(function()
			to(1, 0.18)
		end)
		root.MouseLeave:Connect(function()
			to(1, 0.12)
		end)
		root.Activated:Connect(onActivated)
	end
	root.Parent = parent
	return { Root = root, Stroke = stroke, Badge = badge, Viewport = viewport, Veil = veil }
end

-- A selectable icon cell (recycling, Wish Furnace).
function Widgets.ItemCard(parent: Instance, itemId: string, layoutOrder: number, onActivated: () -> ()): ItemCard
	local color = Rarities.GetColor(ItemConfig.GetRarity(itemId))
	local cell = Widgets.IconCell(parent, itemId, layoutOrder, onActivated)
	cell.Root.Name = `Card{layoutOrder}`
	return {
		Button = cell.Root,
		SetSelected = function(selected: boolean)
			cell.Stroke.Color = if selected then Theme.Colors.Accent else color
			cell.Stroke.Thickness = if selected then 5 else 2.5
		end,
	}
end

-- A horizontally wrapping grid for item cards.
function Widgets.CardGrid(parent: Instance, name: string, size: UDim2, position: UDim2, cellScale: Vector2): Frame
	local grid = Instance.new("Frame")
	grid.Name = name
	grid.Size = size
	grid.Position = position
	grid.BackgroundTransparency = 1
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(cellScale.X, cellScale.Y)
	layout.CellPadding = UDim2.fromScale(0.02, 0.04)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = parent
	return grid
end

-- Destroys every child except layout objects.
function Widgets.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIGridStyleLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- A list key that changes only when the uids change (so cards are rebuilt only then).
function Widgets.Key(list: { Types.CarriedJunk }): string
	local parts = table.create(#list)
	for index, entry in list do
		parts[index] = entry.Uid
	end
	return table.concat(parts, ";")
end

return Widgets
