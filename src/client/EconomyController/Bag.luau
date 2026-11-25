--!strict
--[[
	Bag: what you own, in one window (B / gamepad View / BAG button / the base chest).

	  top      chest plate: level badge, name, fill bar, UPGRADE
	  left     IN YOUR HANDS, icon cells; tap = store
	  middle   riveted divider with a turning gear
	  right    CHEST, icon cells (equal items are one cell with a count); tap = take one
	  bottom   filter chips

	Storing and taking work standing at your own chest; the server decides. Cells are kept between
	refreshes and 3D previews are made only for cells that are on screen, so a full chest stays
	cheap on phones. Placed objects are in the world: pick them up with their T prompt.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local NotifyController = require(script.Parent.Parent.NotifyController)
local Preview = require(script.Parent.Parent.UI.Preview)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Window)

export type Bag = {
	Tick: () -> (),
	Toggle: (gamepad: boolean) -> (),
	Open: (gamepad: boolean) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Refresh: () -> (),
}

local Bag = {}

local FILTERS = { "ALL", "MATERIALS", "USABLE", "VEHICLES", "COLLECTIBLES" }
local rgb = Color3.fromRGB
local STEEL, NIGHT, GOLD = rgb(52, 66, 98), rgb(26, 33, 54), rgb(255, 205, 60)

type Cell = { Root: TextButton, Viewport: ViewportFrame, Built: boolean, Count: TextLabel, Id: string, Uid: string }
type Pane = { Root: Frame, Title: TextLabel, List: ScrollingFrame, Empty: TextLabel, Cells: { [string]: Cell }, Grid: UIGridLayout }
type Wanted = { Key: string, Id: string, Uid: string, Count: number }

local function categoryOf(itemId: string): string
	local capabilities = ItemCapabilities.Get(itemId)
	if capabilities ~= nil and capabilities.Behavior ~= nil then
		return if capabilities.Behavior.Kind == "Vehicle" then "VEHICLES" else "USABLE"
	end
	local definition = ItemConfig.Get(itemId)
	local category = if definition ~= nil then definition.Category else "Junk"
	if category == "Junk" or category == "Material" or category == "Component" then
		return "MATERIALS"
	end
	return "COLLECTIBLES"
end

-- Same rule as the server (BaseService.IsNearChest), only to explain the buttons.
local function atBase(): boolean
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	for _, chest in CollectionService:GetTagged("BaseChest") do
		if chest:IsA("Model") and chest:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			local offset = chest:GetPivot().Position - root.Position
			return Vector3.new(offset.X, 0, offset.Z).Magnitude <= BaseConfig.Chest.UseDistance
		end
	end
	return false
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function shade(parent: Instance, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), bottom)
	gradient.Parent = parent
end

local function buildPane(parent: Instance, name: string, titleText: string, emptyText: string): Pane
	local root = frame(parent, name, UDim2.new(), UDim2.fromScale(1, 1), STEEL)
	Theme.Corner(root, UDim.new(0, 14))
	Theme.Stroke(root, NIGHT, 3)
	shade(root, rgb(150, 158, 190))
	local head = frame(root, "Head", UDim2.new(), UDim2.new(1, 0, 0, 28), NIGHT)
	Theme.Corner(head, UDim.new(0, 14))
	local title = Theme.Label({ Name = "Title", Text = titleText, Size = UDim2.new(1, -16, 0.82, 0), Position = UDim2.new(0, 8, 0.09, 0),
		Color = GOLD, MinTextSize = 11, MaxTextSize = 18, Parent = head })
	local list = Instance.new("ScrollingFrame")
	list.Name = "Cells"
	list.Position = UDim2.fromOffset(6, 32)
	list.Size = UDim2.new(1, -10, 1, -38)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = GOLD
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(9, 9)
	grid.CellSize = UDim2.fromOffset(84, 92)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local empty = Theme.Label({ Name = "Empty", Text = emptyText, Size = UDim2.new(0.8, 0, 0, 44), Position = UDim2.fromScale(0.5, 0.55),
		AnchorPoint = Vector2.new(0.5, 0.5), Color = rgb(190, 204, 235), Font = Theme.FontBody, MinTextSize = 11, MaxTextSize = 16, Parent = root })
	empty.TextWrapped = true
	return { Root = root, Title = title, List = list, Empty = empty, Cells = {}, Grid = grid }
end

-- 3D previews only for cells that are on screen.
local function fillVisible(pane: Pane)
	local top = pane.List.AbsolutePosition.Y - 60
	local bottom = top + pane.List.AbsoluteSize.Y + 120
	for _, cell in pane.Cells do
		local y = cell.Root.AbsolutePosition.Y
		if not cell.Built and y + cell.Root.AbsoluteSize.Y >= top and y <= bottom then
			cell.Built = true
			Preview.Item(cell.Viewport, cell.Id)
		end
	end
end

local function buildCell(pane: Pane, wanted: Wanted): Cell
	local rarity = ItemConfig.GetRarity(wanted.Id)
	local color = Rarities.GetColor(rarity)
	local root = Instance.new("TextButton")
	root.Name = wanted.Id
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = color:Lerp(rgb(246, 250, 255), 0.72)
	root:SetAttribute("Dressed", true) -- cells have their own look (ButtonStyleController)
	Theme.Corner(root, UDim.new(0, 12))
	Theme.Stroke(root, color, 2.5)
	shade(root, rgb(196, 204, 226))
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Item"
	viewport.Position = UDim2.fromScale(0.06, 0.02)
	viewport.Size = UDim2.fromScale(0.88, 0.68)
	Preview.StyleViewport(viewport)
	viewport.Parent = root
	local plate = frame(root, "Plate", UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), NIGHT)
	Theme.Corner(plate, UDim.new(0, 10))
	local name = Theme.Label({ Name = "Name", Text = ItemConfig.GetDisplayName(wanted.Id), Size = UDim2.fromScale(0.92, 0.86), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Color = color:Lerp(rgb(255, 255, 255), 0.55), MinTextSize = 10, MaxTextSize = 13, Parent = plate })
	name.TextWrapped = true
	local count = Theme.Label({ Name = "Count", Text = "", Size = UDim2.fromOffset(34, 20), Position = UDim2.new(1, -4, 0, 2),
		AnchorPoint = Vector2.new(1, 0), Color = rgb(255, 255, 255), MinTextSize = 11, MaxTextSize = 17, XAlignment = Enum.TextXAlignment.Right, Parent = root })
	Theme.TextStroke(count, NIGHT, 2)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = root
	local function to(value: number, seconds: number)
		TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	to(1, 0.25)
	root.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			to(1.07, 0.12)
		end
	end)
	root.MouseLeave:Connect(function()
		to(1, 0.12)
	end)
	root.MouseButton1Down:Connect(function()
		to(0.92, 0.08)
	end)
	root.MouseButton1Up:Connect(function()
		to(1, 0.18)
	end)
	root.Parent = pane.List
	return { Root = root, Viewport = viewport, Built = false, Count = count, Id = wanted.Id, Uid = wanted.Uid }
end

-- Keeps the cells that stay, pops in new ones, removes the rest.
local function sync(pane: Pane, list: { Wanted }, onCell: (cell: Cell) -> ())
	local keep: { [string]: boolean } = {}
	for order, wanted in list do
		keep[wanted.Key] = true
		local cell = pane.Cells[wanted.Key]
		if cell == nil then
			local made = buildCell(pane, wanted)
			made.Root.Activated:Connect(function()
				onCell(made)
			end)
			pane.Cells[wanted.Key] = made
			cell = made
		end
		local c = cell :: Cell
		c.Uid = wanted.Uid
		c.Root.LayoutOrder = order
		c.Count.Text = if wanted.Count > 1 then `x{wanted.Count}` else ""
	end
	for key, cell in pane.Cells do
		if not keep[key] then
			pane.Cells[key] = nil
			cell.Root:Destroy()
		end
	end
	pane.Empty.Visible = #list == 0
	task.defer(fillVisible, pane) -- after the grid has placed the cells
end

function Bag.Mount(screenGui: ScreenGui, source: any): Bag
	local window = Window.Mount(screenGui, "BagWindow", "MY BAG", { "BAG" })
	window.Content("BAG").Visible = false -- this window draws its own body
	local filter = "ALL"
	local refresh: () -> ()

	-- Chest plate
	local plate = frame(window.Root, "ChestPlate", UDim2.fromOffset(0, 42), UDim2.new(1, 0, 0, 54), STEEL)
	Theme.Corner(plate, UDim.new(0, 14))
	Theme.Stroke(plate, NIGHT, 3)
	shade(plate, rgb(160, 168, 200))
	local badge = frame(plate, "Badge", UDim2.new(0, 8, 0.5, 0), UDim2.fromOffset(40, 40), GOLD)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	Theme.Corner(badge, UDim.new(0.3, 0))
	Theme.Stroke(badge, NIGHT, 2.5)
	shade(badge, rgb(222, 160, 80))
	local badgeText = Theme.Label({ Name = "Level", Text = "1", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Color = rgb(255, 255, 255), MinTextSize = 11, MaxTextSize = 22, Parent = badge })
	Theme.TextStroke(badgeText, NIGHT, 2)
	local chestName = Theme.Label({ Name = "ChestName", Text = "", Size = UDim2.new(0.6, -70, 0, 22), Position = UDim2.fromOffset(58, 4),
		Color = rgb(255, 240, 205), MinTextSize = 11, MaxTextSize = 18, XAlignment = Enum.TextXAlignment.Left, Parent = plate })
	local barBack = frame(plate, "Bar", UDim2.new(0, 58, 1, -22), UDim2.new(0.6, -70, 0, 14), NIGHT)
	Theme.Corner(barBack, UDim.new(1, 0))
	local barFill = frame(barBack, "Fill", UDim2.new(), UDim2.fromScale(0, 1), Theme.Colors.Success)
	Theme.Corner(barFill, UDim.new(1, 0))
	local barText = Theme.Label({ Name = "Text", Text = "", Size = UDim2.fromScale(1, 1), Color = rgb(255, 255, 255), MinTextSize = 10, MaxTextSize = 13, Parent = barBack })
	barText.ZIndex = 3
	Theme.TextStroke(barText, NIGHT, 1.5)
	local upgrade, upgradeLabel = Window.SmallButton(plate, "Upgrade", Theme.Colors.Accent, UDim2.new(0.36, 0, 0, 42), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
	local upgradeLocked = true
	upgrade.Activated:Connect(function()
		if not upgradeLocked then
			Remotes.GetEvent("BaseAction"):FireServer(HttpService:GenerateGUID(false), "UpgradeChest")
		end
	end)

	-- Body: hands | divider | chest
	local body = frame(window.Root, "Body", UDim2.fromOffset(0, 104), UDim2.new(1, 0, 1, -158), STEEL)
	body.BackgroundTransparency = 1
	local leftHolder = frame(body, "Left", UDim2.new(), UDim2.new(0.38, -24, 1, 0), STEEL)
	leftHolder.BackgroundTransparency = 1
	local rightHolder = frame(body, "Right", UDim2.new(0.38, 24, 0, 0), UDim2.new(0.62, -24, 1, 0), STEEL)
	rightHolder.BackgroundTransparency = 1
	local hands = buildPane(leftHolder, "Hands", "IN YOUR HANDS", "Your hands are empty")
	local chest = buildPane(rightHolder, "Chest", "CHEST", "The chest is empty")

	local divider = frame(body, "Divider", UDim2.new(0.38, 0, 0.5, 0), UDim2.new(0, 10, 1, 0), NIGHT)
	divider.AnchorPoint = Vector2.new(0.5, 0.5)
	Theme.Corner(divider, UDim.new(1, 0))
	Theme.Stroke(divider, GOLD, 2)
	for _, y in { 0.1, 0.28, 0.72, 0.9 } do
		local rivet = frame(divider, "Rivet", UDim2.fromScale(0.5, y), UDim2.fromOffset(8, 8), rgb(190, 200, 214))
		rivet.AnchorPoint = Vector2.new(0.5, 0.5)
		Theme.Corner(rivet, UDim.new(1, 0))
	end
	local gear = frame(divider, "Gear", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(40, 40), GOLD)
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.BackgroundTransparency = 1
	gear.ZIndex = 3
	for index = 0, 3 do
		local teeth = frame(gear, "Teeth", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.26, 1), GOLD)
		teeth.AnchorPoint = Vector2.new(0.5, 0.5)
		teeth.Rotation = index * 45
		Theme.Corner(teeth, UDim.new(0.2, 0))
		Theme.Stroke(teeth, NIGHT, 1.5)
	end
	local wheel = frame(gear, "Wheel", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.74), GOLD)
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.ZIndex = 2
	Theme.Corner(wheel, UDim.new(1, 0))
	Theme.Stroke(wheel, NIGHT, 1.5)
	shade(wheel, rgb(215, 150, 80))
	local hub = frame(gear, "Hub", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.28, 0.28), NIGHT)
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.ZIndex = 3
	Theme.Corner(hub, UDim.new(1, 0))
	local gearSpeed = 12
	RunService.Heartbeat:Connect(function(dt: number)
		if window.IsOpen() then
			gear.Rotation += gearSpeed * dt
			gearSpeed += (12 - gearSpeed) * math.min(dt * 3, 1) -- a moved item spins it up, then it calms down
		end
	end)

	-- Filters
	local chipRow = frame(window.Footer, "Filters", UDim2.fromScale(0, 0.5), UDim2.new(1, 0, 0, 40), STEEL)
	chipRow.AnchorPoint = Vector2.new(0, 0.5)
	chipRow.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.015, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chipRow
	local chips: { [string]: TextButton } = {}
	for index, name in FILTERS do
		local chip = Window.SmallButton(chipRow, name, Theme.Colors.InkSoft, UDim2.new(1 / #FILTERS - 0.013, 0, 1, 0))
		chip.LayoutOrder = index
		chip.Activated:Connect(function()
			filter = name
			refresh()
		end)
		chips[name] = chip
	end

	-- The picture of the item flies to the other side (the server moves the real one).
	local function fly(cell: Cell, target: Pane)
		gearSpeed = if target == chest then 420 else -420
		local ghost = cell.Viewport:Clone()
		local camera = ghost:FindFirstChildOfClass("Camera")
		ghost.CurrentCamera = camera
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		local from = cell.Root.AbsolutePosition + cell.Root.AbsoluteSize / 2 - screenGui.AbsolutePosition
		local goal = target.Root.AbsolutePosition + target.Root.AbsoluteSize / 2 - screenGui.AbsolutePosition
		ghost.Position = UDim2.fromOffset(from.X, from.Y)
		ghost.Size = UDim2.fromOffset(70, 70)
		ghost.ZIndex = 50
		ghost.Parent = screenGui
		local tween = TweenService:Create(ghost, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			Size = UDim2.fromOffset(34, 34),
			Rotation = 180,
		})
		tween.Completed:Once(function()
			ghost:Destroy()
		end)
		tween:Play()
	end

	local function move(action: string, cell: Cell, target: Pane)
		if not atBase() then
			NotifyController.Show("Stand at your chest to move items", "Info")
			return
		end
		fly(cell, target)
		Remotes.GetEvent("StorageMove"):FireServer(action, cell.Uid)
	end

	local lastFill = -1
	refresh = function()
		if not window.IsOpen() then
			return
		end
		for name, chip in chips do
			chip.BackgroundColor3 = if name == filter then Theme.Colors.Accent else Theme.Colors.InkSoft
		end
		local small = screenGui.AbsoluteSize.Y < 500
		local cellSize = if small then UDim2.fromOffset(70, 74) else UDim2.fromOffset(88, 96)
		hands.Grid.CellSize, chest.Grid.CellSize = cellSize, cellSize
		plate.Size = UDim2.new(1, 0, 0, if small then 46 else 54)
		plate.Position = UDim2.fromOffset(0, if small then 34 else 42)
		body.Position = UDim2.fromOffset(0, if small then 86 else 104)
		body.Size = UDim2.new(1, 0, 1, if small then -136 else -158)

		local here = atBase()
		local carried = source.Carried()
		local capacity = Players.LocalPlayer:GetAttribute("CarryMax") or GameConfig.Carry.MaxJunk
		hands.Title.Text = `IN YOUR HANDS  {#carried}/{capacity}`
		local handList: { Wanted } = {}
		for _, entry in carried do
			if filter == "ALL" or categoryOf(entry.Id) == filter then
				table.insert(handList, { Key = entry.Uid, Id = entry.Id, Uid = entry.Uid, Count = 1 })
			end
		end
		sync(hands, handList, function(cell: Cell)
			move("Store", cell, chest)
		end)

		-- Equal items share a cell; taking takes the newest one.
		local stored, total = {}, 0
		for uid, record in source.Stored() do
			total += 1
			table.insert(stored, { Uid = uid, Id = record.id, At = record.acquiredAt })
		end
		table.sort(stored, function(a, b)
			if a.At ~= b.At then
				return a.At > b.At
			end
			return a.Uid < b.Uid
		end)
		local chestList: { Wanted } = {}
		local byId: { [string]: Wanted } = {}
		for _, entry in stored do
			if filter == "ALL" or categoryOf(entry.Id) == filter then
				local known = byId[entry.Id]
				if known ~= nil then
					known.Count += 1
				else
					local wanted: Wanted = { Key = entry.Id, Id = entry.Id, Uid = entry.Uid, Count = 1 }
					byId[entry.Id] = wanted
					table.insert(chestList, wanted)
				end
			end
		end
		table.sort(chestList, function(a, b)
			local rankA, rankB = Rarities.GetRank(ItemConfig.GetRarity(a.Id)), Rarities.GetRank(ItemConfig.GetRarity(b.Id))
			if rankA ~= rankB then
				return rankA > rankB
			end
			return a.Id < b.Id
		end)
		sync(chest, chestList, function(cell: Cell)
			move("Take", cell, hands)
		end)
		chest.Title.Text = if here then "CHEST  ·  tap to move" else "CHEST  ·  stand at your chest"

		-- Chest plate
		local level = Players.LocalPlayer:GetAttribute("ChestLevel")
		local chestLevel = if type(level) == "number" then level else 1
		local info, nextLevel = BaseConfig.Chest.Levels[chestLevel], BaseConfig.Chest.Levels[chestLevel + 1]
		local storageMax = Players.LocalPlayer:GetAttribute("StorageMax")
		local max = if type(storageMax) == "number" then storageMax else info.Capacity
		badgeText.Text = tostring(chestLevel)
		chestName.Text = info.Name
		barText.Text = `{total} / {max}`
		local fraction = math.clamp(total / math.max(max, 1), 0, 1)
		barFill.BackgroundColor3 = if fraction >= 1 then Theme.Colors.Danger elseif fraction > 0.8 then Theme.Colors.Accent else Theme.Colors.Success
		if fraction ~= lastFill then
			lastFill = fraction
			TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
		if nextLevel == nil then
			upgradeLocked = true
			upgradeLabel.Text = "MAX LEVEL"
		else
			local playerLevel = Players.LocalPlayer:GetAttribute("Level") or 1
			upgradeLocked = playerLevel < (nextLevel.RequiredLevel or 1)
			upgradeLabel.Text = if upgradeLocked then `NEEDS LV {nextLevel.RequiredLevel}` else `UPGRADE {KlunksFormat.Format(nextLevel.Price)}  ({nextLevel.Capacity} slots)`
		end
		upgrade.BackgroundColor3 = if here and not upgradeLocked then Theme.Colors.Success else Theme.Colors.InkSoft
		local worth = 0
		for _, entry in stored do
			worth += ItemValue.SellPrice(entry.Id)
		end
		window.SetTitle(if worth > 0 then `MY BAG  ·  chest worth {KlunksFormat.Format(worth)}` else "MY BAG")
	end

	for _, pane in { hands, chest } do
		pane.List:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			fillVisible(pane)
		end)
	end

	local lastAtBase: boolean? = nil
	return {
		-- Called twice a second: redraw only when the player walked onto / off their base.
		Tick = function()
			if not window.IsOpen() then
				lastAtBase = nil
				return
			end
			local here = atBase()
			if here ~= lastAtBase then
				if lastAtBase == true then
					window.Close() -- walked away from the chest
					lastAtBase = nil
					return
				end
				lastAtBase = here
				refresh()
			end
		end,
		Toggle = function(gamepad: boolean)
			if window.IsOpen() then
				window.Close()
			else
				window.Open(nil, gamepad)
				window.Content("BAG").Visible = false
				refresh()
			end
		end,
		Open = function(gamepad: boolean)
			window.Open(nil, gamepad)
			window.Content("BAG").Visible = false
			refresh()
		end,
		Close = window.Close,
		IsOpen = window.IsOpen,
		Refresh = refresh,
	}
end

return Bag
