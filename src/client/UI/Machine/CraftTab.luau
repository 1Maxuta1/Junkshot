--!strict
--[[
	CraftTab: browse recipes (Config/Recipes) by category, see which ingredients the player
	carries, and start crafting. The list and the "can craft" marks are only a convenience;
	the server checks recipe, level, ingredients and machine state again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
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

	local list = Instance.new("ScrollingFrame")
	list.Name = "Recipes"
	list.Position = UDim2.fromScale(0, 0.23)
	list.Size = UDim2.fromScale(0.44, 0.77)
	list.BackgroundColor3 = Theme.Colors.PanelTint
	list.BackgroundTransparency = 0.3
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	Theme.Corner(list, UDim.new(0, 10))
	list.Parent = container
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 9)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 8) -- the scroll bar
	listPadding.Parent = list
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	-- Right: details
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Position = UDim2.fromScale(0.47, 0)
	detail.Size = UDim2.fromScale(0.53, 1)
	detail.BackgroundTransparency = 1
	detail.Parent = container

	local title = Theme.Label({
		Name = "Title",
		Text = "",
		Size = UDim2.fromScale(1, 0.15),
		Color = Theme.Colors.Ink,
		MinTextSize = 14,
		MaxTextSize = 24,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	Theme.TextStroke(title, Theme.Colors.Ink, 0)
	local description = Theme.Label({
		Name = "Description",
		Text = "",
		Size = UDim2.fromScale(1, 0.12),
		Position = UDim2.fromScale(0, 0.15),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 10,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	local ingredients = Theme.Label({
		Name = "Ingredients",
		Text = "",
		Size = UDim2.fromScale(0.62, 0.44),
		Position = UDim2.fromScale(0, 0.29),
		Color = Theme.Colors.Ink,
		Font = Theme.FontBody,
		MinTextSize = 10,
		MaxTextSize = 16,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	ingredients.RichText = true
	ingredients.TextYAlignment = Enum.TextYAlignment.Top
	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.Position = UDim2.fromScale(0.64, 0.27)
	preview.Size = UDim2.fromScale(0.36, 0.46)
	Preview.StyleViewport(preview)
	preview.Parent = detail
	local info = Theme.Label({
		Name = "Info",
		Text = "",
		Size = UDim2.fromScale(0.5, 0.25),
		Position = UDim2.fromScale(0, 0.75),
		Color = Theme.Colors.InkSoft,
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
		Size = UDim2.fromScale(0.42, 0.21),
		Position = UDim2.new(1, -4, 1, -4),
		AnchorPoint = Vector2.new(1, 1),
		MinSize = Vector2.new(104, 40),
		Parent = detail,
	})

	local category = Recipes.Categories[1]
	local selectedId = Recipes.List[1].RecipeId
	local canStart = false
	local lastView: Widgets.View? = nil
	local listKey = ""
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

		-- Rebuild the list only when the category or the craftable set changes.
		local marks = {}
		for _, entry in Recipes.List do
			if isListed(entry, category, have, view.MachineLevel) then
				table.insert(marks, entry.RecipeId .. (if hasAll(entry, have) then "+" else "-"))
			end
		end
		local newKey = category .. table.concat(marks, ",") .. tostring(view.MachineLevel)
		if newKey ~= listKey then
			listKey = newKey
			Widgets.Clear(list)
			if #marks == 0 then
				Theme.Label({
					Name = "Empty",
					Text = "Pick up more junk: nothing can be crafted right now",
					Size = UDim2.new(1, -8, 0, 48),
					Color = Theme.Colors.InkSoft,
					Font = Theme.FontBody,
					MinTextSize = 11,
					MaxTextSize = 15,
					Parent = list,
				}).TextWrapped = true
			end
			for index, entry in Recipes.List do
				if isListed(entry, category, have, view.MachineLevel) then
					local row = Instance.new("TextButton")
					row.Name = entry.RecipeId
					row.LayoutOrder = index
					row.Size = UDim2.new(1, -14, 0, 34)
					row.BackgroundColor3 = Theme.Colors.Panel
					row.Text = ""
					Theme.Corner(row, UDim.new(0, 8))
					Theme.Stroke(row, Rarities.GetColor(entry.Rarity), 2)
					local locked = entry.RequiredLevel > view.MachineLevel
					local ready = not locked and hasAll(entry, have)
					Theme.Label({
						Name = "Label",
						Text = (if ready then "✔ " elseif locked then "🔒 " else "") .. entry.DisplayName,
						Size = UDim2.new(1, -16, 1, -8),
						Position = UDim2.fromOffset(8, 4),
						Color = if locked then Theme.Colors.InkSoft else Theme.Colors.Ink,
						Font = Theme.FontBody,
						MinTextSize = 10,
						MaxTextSize = 16,
						XAlignment = Enum.TextXAlignment.Left,
						Parent = row,
					})
					local id = entry.RecipeId
					row.Activated:Connect(function()
						selectedId = id
						if lastView ~= nil then
							render(lastView)
						end
					end)
					row.Parent = list
				end
			end
		end
		for _, row in list:GetChildren() do
			if row:IsA("TextButton") then
				row.BackgroundColor3 = if row.Name == selectedId then Color3.fromRGB(255, 236, 200) else Theme.Colors.Panel
			end
		end

		local recipe = Recipes.Get(selectedId)
		if recipe == nil then
			return
		end
		title.Text = recipe.DisplayName
		title.TextColor3 = Rarities.GetColor(recipe.Rarity)
		description.Text = recipe.Description
		local lines = {}
		for _, ingredient in recipe.Ingredients do
			local count = have[ingredient.Id] or 0
			local ok = count >= ingredient.Count
			table.insert(lines, string.format(
				'<font color="#%s">%d/%d</font>  %s',
				(if ok then Theme.Colors.Success else Theme.Colors.Danger):ToHex(),
				math.min(count, ingredient.Count),
				ingredient.Count,
				ItemConfig.GetDisplayName(ingredient.Id)
			))
		end
		ingredients.Text = table.concat(lines, "\n")
		Preview.Item(preview, recipe.OutputItemId)

		local base = recipe.DurationOverride or (MachineConfig.CraftDurations :: any)[recipe.Rarity]
		local locked = recipe.RequiredLevel > view.MachineLevel
		info.Text = string.format(
			'<font color="#%s">%s</font>\nTime %s · Level %d',
			Rarities.GetColor(recipe.Rarity):ToHex(),
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
