--!strict
--[[
	RecycleTab: pick one carried item and recycle it into a random reward
	(rarity chances: DropTables.Recycle, rolled on the server).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local RecycleTab = {}

function RecycleTab.Mount(container: Frame, actions: Widgets.Actions, durationFor: (base: number) -> number): Widgets.Tab
	local grid = Widgets.CardGrid(container, "Items", UDim2.fromScale(0.7, 1), UDim2.fromScale(0, 0), Vector2.new(0.31, 0.46))

	local empty = Theme.Label({
		Name = "Empty",
		Text = "Your hands are empty.\nPick up junk in the yard!",
		Size = UDim2.fromScale(0.7, 0.6),
		Position = UDim2.fromScale(0, 0.2),
		Color = Theme.Colors.InkSoft,
		MinTextSize = 13,
		MaxTextSize = 22,
		Parent = container,
	})

	local odds = Theme.Label({
		Name = "Odds",
		Text = "",
		Size = UDim2.fromScale(0.28, 0.62),
		Position = UDim2.fromScale(0.72, 0),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 10,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})
	odds.TextYAlignment = Enum.TextYAlignment.Top
	odds.RichText = true
	local lines = { "<b>Possible rewards</b>" }
	for _, rarity in Rarities.Order do
		local color = Rarities.GetColor(rarity)
		table.insert(lines, string.format('<font color="#%s">%s</font> %g%%', color:ToHex(), rarity, DropTables.Recycle[rarity]))
	end
	odds.Text = table.concat(lines, "\n")

	local button, label = Widgets.Button({
		Name = "Recycle",
		Text = "RECYCLE",
		Size = UDim2.fromScale(0.28, 0.32),
		Position = UDim2.fromScale(0.72, 1),
		AnchorPoint = Vector2.new(0, 1),
		MinSize = Vector2.new(110, 48),
		Parent = container,
	})

	local selected: string? = nil
	local cards: { [string]: Widgets.ItemCard } = {}
	local key = ""
	local canStart = false

	button.Activated:Connect(function()
		if canStart and selected ~= nil then
			actions.Recycle(selected)
		end
	end)

	local function render(view: Widgets.View)
		local recyclable = {}
		for _, entry in view.Carried do
			if ItemConfig.CanBeRecycled(entry.Id) then
				table.insert(recyclable, entry)
			end
		end
		local newKey = Widgets.Key(recyclable)
		if newKey ~= key then
			key = newKey
			Widgets.Clear(grid)
			table.clear(cards)
			for index, entry in recyclable do
				local uid = entry.Uid
				cards[uid] = Widgets.ItemCard(grid, entry.Id, index, function()
					selected = uid
					for cardUid, card in cards do
						card.SetSelected(cardUid == selected)
					end
				end)
			end
		end
		if selected == nil or cards[selected] == nil then
			selected = if recyclable[1] ~= nil then recyclable[1].Uid else nil
		end
		for cardUid, card in cards do
			card.SetSelected(cardUid == selected)
		end
		empty.Visible = #recyclable == 0

		local busy = view.State == "Processing"
		local full = #view.Output >= view.OutputCapacity
		canStart = selected ~= nil and not busy and not full
		button.BackgroundColor3 = if canStart then Theme.Colors.Accent else Theme.Colors.InkSoft
		label.Text = if busy
			then "BUSY"
			elseif full then "TRAY FULL"
			else `RECYCLE\n{Widgets.FormatTime(durationFor(MachineConfig.RecycleDuration))}`
	end

	return { Render = render }
end

return RecycleTab
