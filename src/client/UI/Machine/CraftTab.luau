--!strict
--[[
	CraftTab: browse recipes (Config/Recipes) by category as icon cells, see the ingredients as
	pictures with how many the player carries, and start crafting. The list and the "can craft" marks are only a convenience;
	the server checks recipe, level, ingredients and machine state again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Types = require(ReplicatedStorage.Shared.Types)
local Preview = require(script.Parent.Parent.Preview)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local CraftTab = {}

local function counts(carried: { Types.CarriedJunk }): { [string]: number }
	local result: { [string]: number } = {}
	for _, entry in carried do
		result[entry.Id] = (result[entry.Id] or 0) + 1
	end
	return result
end

local function hasAll(recipe: Types.Recipe, have: { [string]: number }): boolean
	for _, ingredient in recipe.Ingredients do
		if (have[ingredient.Id] or 0) < ingredient.Count then
			return false
		end
	end
	return true
end

local function isListed(recipe: Types.Recipe, category: string, have: { [string]: number }, level: number): boolean
	if category == "Ready" then
		return recipe.RequiredLevel <= level and hasAll(recipe, have)
	end
	return recipe.Category == category
end

-- Six chips share a narrow row; long category names would shrink to unreadable text.
local CHIP_LABELS: { [string]: string } = {
	Components = "Parts",
	Vehicles = "Rides",
	Tools = "Tools",
	Deployables = "Build",
	Special = "Special",
	Ready = "Ready",
}
local READY = "Ready" -- not a category: every recipe the carried items are enough for

function CraftTab.Mount(container: Frame, actions: Widgets.Actions, durationFor: (base: number) -> number): Widgets.Tab
	-- Left: categories + recipe list
	local categoryRow = Instance.new("Frame")
	categoryRow.Name = "Categories"
	categoryRow.Size = UDim2.fromScale(0.44, 0.2)
	categoryRow.BackgroundTransparency = 1
	categoryRow.Parent = container
	local categoryLayout = Instance.new("UIListLayout")
	categoryLayout.FillDirection = Enum.FillDirection.Horizontal
	categoryLayout.Padding = UDim.new(0.02, 0)
	categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	categoryLayout.Parent = categoryRow

	local listPanel = Widgets.SteelPanel(container, "RecipePanel", UDim2.fromScale(0, 0.23), UDim2.fromScale(0.44, 0.77))
	local list = Instance.new("ScrollingFrame")
	list.Name = "Recipes"
	list.Position = UDim2.fromOffset(3, 3)
	list.Size = UDim2.new(1, -6, 1, -6)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 205, 60)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = listPanel
	local listLayout = Instance.new("UIGridLayout")
	listLayout.CellPadding = UDim2.fromOffset(8, 8)
	listLayout.CellSize = UDim2.new(0.25, -8, 0, 76)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 5)
	listPadding.PaddingRight = UDim.new(0, 7) -- the scroll bar
	listPadding.Parent = list
	listLayout.Parent = list
	local function fit() -- narrow screens: three in a row
		local width = list.AbsoluteSize.X
		listLayout.CellSize = UDim2.new(if width < 300 then 1 / 3 else 0.25, -9, 0, if width < 300 then 68 else 76)
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	Widgets.Divider(container, 0.46)

	-- Right: what it is (picture, name), what it needs (icon cells), the button
	local detail = Widgets.SteelPanel(container, "Detail", UDim2.fromScale(0.48, 0), UDim2.fromScale(0.52, 1))

	local previewBox = Instance.new("Frame")
	previewBox.Name = "PreviewBox"
	previewBox.Position = UDim2.new(0, 6, 0, 6)
	previewBox.Size = UDim2.fromScale(0.22, 0.36)
	previewBox.BackgroundColor3 = Color3.new(1, 1, 1)
	Theme.Corner(previewBox, UDim.new(0, 10))
	local previewStroke = Theme.Stroke(previewBox, Theme.Colors.Ink, 2.5)
	previewBox.Parent = detail
	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.Size = UDim2.fromScale(1, 1)
	Preview.StyleViewport(preview)
	preview.Parent = previewBox
	local title = Theme.Label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(0.75, -22, 0.16, 0),
		Position = UDim2.new(0.22, 16, 0, 5),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 24,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	Theme.TextStroke(title, Widgets.Night, 1.5)
	local description = Theme.Label({
		Name = "Description",
		Text = "",
		Size = UDim2.new(0.75, -22, 0.21, 0),
		Position = UDim2.new(0.22, 16, 0.18, 4),
		Color = Color3.fromRGB(214, 224, 246),
		Font = Theme.FontBody,
		MinTextSize = 10,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	description.TextWrapped = true
	local needs = Instance.new("Frame")
	needs.Name = "Ingredients"
	needs.Position = UDim2.new(0, 8, 0.4, 3)
	needs.Size = UDim2.new(1, -16, 0.35, 0)
	needs.BackgroundTransparency = 1
	local needsLayout = Instance.new("UIListLayout")
	needsLayout.FillDirection = Enum.FillDirection.Horizontal
	needsLayout.Padding = UDim.new(0, 8)
	needsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	needsLayout.Parent = needs
	needs.Parent = detail
	local info = Theme.Label({
		Name = "Info",
		Text = "",
		Size = UDim2.new(0.52, -8, 0.17, 0),
		Position = UDim2.new(0, 8, 0.82, -2),
		Color = Color3.fromRGB(214, 224, 246),
		Font = Theme.FontBody,
		MinTextSize = 10,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	info.RichText = true
	local craftButton, craftLabel = Widgets.Button({
		Name = "Craft",
		Text = "CRAFT",
		Size = UDim2.fromScale(0.42, 0.18),
		Position = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(1, 1),
		MinSize = Vector2.new(104, 34),
		Parent = detail,
	})

	local category = Recipes.Categories[1]
	local selectedId = Recipes.List[1].RecipeId
	local canStart = false
	local lastView: Widgets.View? = nil
	local listKey = ""
	local shownId = "" -- recipe whose pictures are built
	local cells: { [string]: Widgets.IconCell } = {} -- recipe id -> cell
	local needCells: { [string]: Widgets.IconCell } = {} -- item id -> cell
	local categoryButtons: { [string]: TextButton } = {}
	local render: (view: Widgets.View) -> ()

	local names = table.clone(Recipes.Categories) :: { string }
	table.insert(names, READY)
	for index, name in names do
		local chip = Instance.new("TextButton")
		chip.Name = name
		chip.LayoutOrder = index
		chip.Size = UDim2.fromScale(0.148, 0.86)
		chip.BackgroundColor3 = Theme.Colors.PanelTint
		chip.Text = ""
		Theme.Corner(chip, UDim.new(0, 8))
		Theme.Label({
			Name = "Label",
			Text = CHIP_LABELS[name] or name,
			Size = UDim2.fromScale(0.92, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = Theme.Colors.Ink,
			Font = Theme.FontBody,
			MinTextSize = 11,
			MaxTextSize = 15,
			Parent = chip,
		})
		local limit = Instance.new("UISizeConstraint")
		limit.MinSize = Vector2.new(0, 32)
		limit.Parent = chip
		chip.Activated:Connect(function()
			category = name
			listKey = ""
			for _, entry in Recipes.List do
				if entry.Category == name or (name == READY and lastView ~= nil and isListed(entry, name, counts(lastView.Carried), lastView.MachineLevel)) then
					selectedId = entry.RecipeId
					break
				end
			end
			if lastView ~= nil then
				render(lastView)
			end
		end)
		chip.Parent = categoryRow
		categoryButtons[name] = chip
	end

	craftButton.Activated:Connect(function()
		if canStart then
			actions.Craft(selectedId)
		end
	end)

	function render(view: Widgets.View)
		lastView = view
		local have = counts(view.Carried)
		for name, chip in categoryButtons do
			chip.BackgroundColor3 = if name == category then Theme.Colors.Accent else Theme.Colors.PanelTint
		end

		-- Pictures are built once per category (or set of ready recipes); only marks change.
		local marks = {}
		for _, entry in Recipes.List do
			if isListed(entry, category, have, view.MachineLevel) then
				table.insert(marks, entry.RecipeId)
			end
		end
		local newKey = category .. table.concat(marks, ",")
		if newKey ~= listKey then
			listKey = newKey
			for _, cell in cells do
				cell.Root:Destroy()
			end
			table.clear(cells)
			local oldEmpty = listPanel:FindFirstChild("Empty")
			if oldEmpty ~= nil then
				oldEmpty:Destroy()
			end
			if #marks == 0 then
				Theme.Label({
					Name = "Empty",
					Text = "Pick up more junk: nothing can be crafted right now",
					Size = UDim2.new(1, -16, 0, 48),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Color = Color3.fromRGB(200, 212, 240),
					Font = Theme.FontBody,
					MinTextSize = 11,
					MaxTextSize = 15,
					Parent = listPanel,
				}).TextWrapped = true
			end
			for index, entry in Recipes.List do
				if isListed(entry, category, have, view.MachineLevel) then
					local id = entry.RecipeId
					cells[id] = Widgets.IconCell(list, entry.OutputItemId, index, function()
						selectedId = id
						if lastView ~= nil then
							render(lastView)
						end
					end)
				end
			end
		end
		for id, cell in cells do
			local entry = Recipes.Get(id)
			if entry ~= nil then
				local locked = entry.RequiredLevel > view.MachineLevel
				local ready = not locked and hasAll(entry, have)
				cell.Veil.Visible = locked
				cell.Badge.Text = if locked then `LV {entry.RequiredLevel}` elseif ready then "✔" else ""
				cell.Badge.TextColor3 = if ready then Theme.Colors.Success else Color3.new(1, 1, 1)
				local selected = id == selectedId
				cell.Stroke.Color = if selected then Color3.new(1, 1, 1) else Rarities.GetColor(entry.Rarity)
				cell.Stroke.Thickness = if selected then 4.5 else 2.5
			end
		end

		local recipe = Recipes.Get(selectedId)
		if recipe == nil then
			return
		end
		title.Text = recipe.DisplayName
		title.TextColor3 = Rarities.GetColor(recipe.Rarity):Lerp(Color3.new(1, 1, 1), 0.35)
		description.Text = recipe.Description
		local rarityColor = Rarities.GetColor(recipe.Rarity)
		if shownId ~= selectedId then
			shownId = selectedId
			previewBox.BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(246, 250, 255), 0.72)
			previewStroke.Color = rarityColor
			Preview.Item(preview, recipe.OutputItemId)
			for _, cell in needCells do
				cell.Root:Destroy()
			end
			table.clear(needCells)
			local total = math.max(#recipe.Ingredients, 4)
			for index, ingredient in recipe.Ingredients do
				local cell = Widgets.IconCell(needs, ingredient.Id, index, nil)
				cell.Root.Size = UDim2.new(1 / total, -8, 1, 0)
				needCells[ingredient.Id] = cell
			end
		end
		for _, ingredient in recipe.Ingredients do
			local cell = needCells[ingredient.Id]
			if cell ~= nil then
				local count = math.min(have[ingredient.Id] or 0, ingredient.Count)
				local ok = count >= ingredient.Count
				cell.Badge.Text = `{count}/{ingredient.Count}`
				cell.Badge.TextColor3 = if ok then Color3.fromRGB(120, 255, 150) else Color3.fromRGB(255, 120, 110)
				cell.Stroke.Color = if ok then Theme.Colors.Success else Theme.Colors.Danger
				cell.Viewport.ImageTransparency = if ok then 0 else 0.5
			end
		end

		local base = recipe.DurationOverride or (MachineConfig.CraftDurations :: any)[recipe.Rarity]
		local locked = recipe.RequiredLevel > view.MachineLevel
		info.Text = string.format(
			'<font color="#%s">%s</font>\nTime %s · Level %d',
			rarityColor:Lerp(Color3.new(1, 1, 1), 0.35):ToHex(),
			recipe.Rarity,
			Widgets.FormatTime(durationFor(base)),
			recipe.RequiredLevel
		)

		local busy = view.State == "Processing"
		local full = #view.Output >= view.OutputCapacity
		local ready = hasAll(recipe, have)
		canStart = ready and not locked and not busy and not full
		craftButton.BackgroundColor3 = if canStart then Theme.Colors.Accent else Theme.Colors.InkSoft
		craftLabel.Text = if busy
			then "BUSY"
			elseif full then "TRAY FULL"
			elseif locked then `LEVEL {recipe.RequiredLevel}`
			elseif not ready then "MISSING"
			else "CRAFT"
	end

	return { Render = render }
end

return CraftTab
