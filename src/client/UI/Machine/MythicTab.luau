--!strict
--[[
	MythicTab: Mythic Crafting. Exactly three slots; tap a carried item to fill the next empty
	slot, tap a slot to empty it. The odds shown come from the same DropTables row the server
	uses (better inputs -> better odds); the server rolls the real result. Always 6 hours.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Preview = require(script.Parent.Parent.Preview)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local MythicTab = {}

function MythicTab.Mount(container: Frame, actions: Widgets.Actions): Widgets.Tab
	local slotsRow = Instance.new("Frame")
	slotsRow.Name = "Slots"
	slotsRow.Size = UDim2.fromScale(0.46, 0.5)
	slotsRow.BackgroundTransparency = 1
	slotsRow.Parent = container
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0.03, 0)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = slotsRow

	local odds = Theme.Label({
		Name = "Odds",
		Text = "",
		Size = UDim2.fromScale(0.46, 0.26),
		Position = UDim2.fromScale(0, 0.52),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 9,
		MaxTextSize = 14,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})
	odds.RichText = true
	odds.TextYAlignment = Enum.TextYAlignment.Top

	local startButton, startLabel = Widgets.Button({
		Name = "Start",
		Text = "START",
		Size = UDim2.fromScale(0.46, 0.2),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Color = Rarities.GetColor("Mythic"),
		MinSize = Vector2.new(140, 46),
		Parent = container,
	})

	local grid = Widgets.CardGrid(container, "Items", UDim2.fromScale(0.5, 1), UDim2.fromScale(0.5, 0), Vector2.new(0.31, 0.46))
	local hint = Theme.Label({
		Name = "Hint",
		Text = "Carry items to put them in the slots",
		Size = UDim2.fromScale(0.5, 0.4),
		Position = UDim2.fromScale(0.5, 0.3),
		Color = Theme.Colors.InkSoft,
		MinTextSize = 12,
		MaxTextSize = 18,
		Parent = container,
	})

	local slots: { string? } = { nil, nil, nil }
	local slotFrames: { TextButton } = {}
	local slotViewports: { ViewportFrame } = {}
	local idOf: { [string]: string } = {}
	local lastView: Widgets.View? = nil
	local key = ""
	local canStart = false
	local render: (view: Widgets.View) -> ()

	for index = 1, MachineConfig.MythicInputs do
		local slot = Instance.new("TextButton")
		slot.Name = `Slot{index}`
		slot.LayoutOrder = index
		slot.Size = UDim2.fromScale(0.3, 1)
		slot.Text = ""
		slot.BackgroundColor3 = Theme.Colors.PanelTint
		Theme.Corner(slot, UDim.new(0, 12))
		Theme.Stroke(slot, Rarities.GetColor("Mythic"), 2.5)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = slot
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.fromScale(1, 1)
		Preview.StyleViewport(viewport)
		viewport.Parent = slot
		Theme.Label({
			Name = "Plus",
			Text = "+",
			Size = UDim2.fromScale(0.5, 0.5),
			Position = UDim2.fromScale(0.25, 0.25),
			Color = Theme.Colors.InkSoft,
			MinTextSize = 14,
			MaxTextSize = 40,
			Parent = slot,
		})
		slot.Activated:Connect(function()
			slots[index] = nil
			if lastView ~= nil then
				render(lastView)
			end
		end)
		slot.Parent = slotsRow
		slotFrames[index] = slot
		slotViewports[index] = viewport
	end

	startButton.Activated:Connect(function()
		local a, b, c = slots[1], slots[2], slots[3]
		if canStart and a ~= nil and b ~= nil and c ~= nil then
			actions.Mythic(a, b, c)
			slots = { nil, nil, nil }
		end
	end)

	function render(view: Widgets.View)
		lastView = view
		table.clear(idOf)
		local free = {}
		for _, entry in view.Carried do
			idOf[entry.Uid] = entry.Id
		end
		-- Drop slots whose item is no longer carried.
		for index = 1, MachineConfig.MythicInputs do
			local uid = slots[index]
			if uid ~= nil and idOf[uid] == nil then
				slots[index] = nil
			end
		end
		local used: { [string]: boolean } = {}
		for _, uid in slots do
			if uid ~= nil then
				used[uid] = true
			end
		end
		for _, entry in view.Carried do
			if not used[entry.Uid] and ItemConfig.CanBeRecycled(entry.Id) then
				table.insert(free, entry)
			end
		end

		local newKey = Widgets.Key(free)
		if newKey ~= key then
			key = newKey
			Widgets.Clear(grid)
			for index, entry in free do
				local uid = entry.Uid
				Widgets.ItemCard(grid, entry.Id, index, function()
					for slotIndex = 1, MachineConfig.MythicInputs do
						if slots[slotIndex] == nil then
							slots[slotIndex] = uid
							break
						end
					end
					if lastView ~= nil then
						render(lastView)
					end
				end)
			end
		end
		hint.Visible = #free == 0 and next(used) == nil

		local inputIds = {}
		for index = 1, MachineConfig.MythicInputs do
			local uid = slots[index]
			local viewport = slotViewports[index]
			local plus = slotFrames[index]:FindFirstChild("Plus") :: TextLabel?
			if uid ~= nil then
				Preview.Item(viewport, idOf[uid])
				table.insert(inputIds, idOf[uid])
			else
				viewport:ClearAllChildren()
			end
			if plus ~= nil then
				plus.Visible = uid == nil
			end
		end

		if #inputIds == MachineConfig.MythicInputs then
			local total = 0
			for _, id in inputIds do
				total += Rarities.GetRank(ItemConfig.GetRarity(id))
			end
			local chances = DropTables.MythicFor(total / #inputIds)
			local lines = { "<b>Result chances</b>" }
			for _, rarity in Rarities.Order do
				local chance = chances[rarity]
				if chance > 0 then
					table.insert(lines, string.format('<font color="#%s">%s</font> %.1f%%', Rarities.GetColor(rarity):ToHex(), rarity, chance))
				end
			end
			odds.Text = table.concat(lines, "  ")
		else
			odds.Text = "Fill all three slots. Rarer items give better odds!"
		end

		local busy = view.State == "Processing"
		local full = #view.Output >= view.OutputCapacity
		canStart = #inputIds == MachineConfig.MythicInputs and not busy and not full
		startButton.AutoButtonColor = canStart
		startButton.BackgroundTransparency = if canStart then 0 else 0.5
		startLabel.Text = if busy
			then "BUSY"
			elseif full then "TRAY FULL"
			else `START  {Widgets.FormatTime(MachineConfig.MythicDuration)}`
	end

	return { Render = render }
end

return MythicTab
