--!strict
--[[
	Widgets: building blocks shared by the machine panel's tabs, plus the view/action types the
	panel is driven by. Everything is Scale-sized with minimum pixel sizes for touch (44 px).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- A card with a 3D preview, the item's name and a rarity-colored outline.
function Widgets.ItemCard(parent: Instance, itemId: string, layoutOrder: number, onActivated: () -> ()): ItemCard
	local rarity = ItemConfig.GetRarity(itemId)
	local rarityColor = Rarities.GetColor(rarity)
	local card = Instance.new("TextButton")
	card.Name = `Card{layoutOrder}`
	card.LayoutOrder = layoutOrder
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = Theme.Colors.PanelTint
	Theme.Corner(card, UDim.new(0, 10))
	local stroke = Theme.Stroke(card, if rarity ~= "Common" then rarityColor else Theme.Colors.Ink, 2)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Size = UDim2.fromScale(1, 0.7)
	Preview.StyleViewport(viewport)
	viewport.Parent = card
	Preview.Item(viewport, itemId)

	Theme.Label({
		Name = "Name",
		Text = ItemConfig.GetDisplayName(itemId),
		Size = UDim2.fromScale(0.94, 0.28),
		Position = UDim2.fromScale(0.03, 0.7),
		Color = Theme.Colors.Ink,
		Font = Theme.FontBody,
		MinTextSize = 9,
		MaxTextSize = 15,
		Parent = card,
	})
	local strip = Instance.new("Frame")
	strip.Name = "Rarity"
	strip.Size = UDim2.new(1, -16, 0, 4)
	strip.Position = UDim2.new(0, 8, 0, 4)
	strip.BackgroundColor3 = rarityColor
	strip.BorderSizePixel = 0
	Theme.Corner(strip, UDim.new(1, 0))
	strip.Parent = card

	card.Activated:Connect(onActivated)
	card.Parent = parent
	return {
		Button = card,
		SetSelected = function(selected: boolean)
			card.BackgroundColor3 = if selected then Color3.fromRGB(255, 236, 200) else Theme.Colors.PanelTint
			stroke.Color = if selected then Theme.Colors.Accent elseif rarity ~= "Common" then rarityColor else Theme.Colors.Ink
			stroke.Thickness = if selected then 4 else 2
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
