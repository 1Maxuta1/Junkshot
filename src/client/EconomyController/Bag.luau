--!strict
--[[
	Bag: what you own, in one window (B / gamepad View / BAG button).
	  IN YOUR HANDS   carried items (the hotbar), each with STORE
	  CHEST           your base chest (saved), each item with TAKE; chest level + UPGRADE
	Filter chips: ALL / MATERIALS / USABLE / VEHICLES / COLLECTIBLES.
	Storing and taking work standing at your own chest (R on the chest opens this window too).
	Placed objects (vehicles, radio, cart) are in the world: pick them up with their T prompt.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

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

local function newRequestId(): string
	return HttpService:GenerateGUID(false)
end

function Bag.Mount(screenGui: ScreenGui, source: any): Bag
	local window = Window.Mount(screenGui, "BagWindow", "MY BAG", { "BAG" })
	local filter = "ALL"

	local chipRow = Instance.new("Frame")
	chipRow.Name = "Filters"
	chipRow.Size = UDim2.new(1, 0, 0, 44)
	chipRow.AnchorPoint = Vector2.new(0, 0.5)
	chipRow.Position = UDim2.fromScale(0, 0.5)
	chipRow.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.01, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chipRow
	chipRow.Parent = window.Footer
	local chips: { [string]: TextButton } = {}

	local refresh: () -> ()

	for index, name in FILTERS do
		local chip = Window.SmallButton(chipRow, name, Theme.Colors.PanelTint, UDim2.new(1 / #FILTERS - 0.01, 0, 1, 0))
		chip.LayoutOrder = index
		chip.Activated:Connect(function()
			filter = name
			refresh()
		end)
		chips[name] = chip
	end

	refresh = function()
		if not window.IsOpen() then
			return
		end
		for name, chip in chips do
			chip.BackgroundColor3 = if name == filter then Theme.Colors.Accent else Theme.Colors.InkSoft
			local label = chip:FindFirstChild("Label") :: TextLabel?
			if label ~= nil then
				label.TextColor3 = Theme.Colors.White
			end
		end
		local list = window.Content("BAG")
		Window.Clear(list)
		local here = atBase()
		local order = 0
		local function add(): number
			order += 1
			return order
		end

		local carried = source.Carried()
		local capacity = Players.LocalPlayer:GetAttribute("CarryMax") or GameConfig.Carry.MaxJunk
		Window.Header(list, add(), `IN YOUR HANDS  ({#carried}/{capacity})`)
		for _, entry in carried do
			if filter == "ALL" or categoryOf(entry.Id) == filter then
				local row = Window.Row(list, add(), ItemConfig.GetDisplayName(entry.Id),
					`{ItemConfig.GetRarity(entry.Id)}  ·  worth {KlunksFormat.Format(ItemValue.SellPrice(entry.Id))}`, entry.Id)
				local button = Window.SmallButton(row.Right, "STORE", if here then Theme.Colors.Ice else Theme.Colors.InkSoft, UDim2.new(0, 100, 0, 40))
				button.Activated:Connect(function()
					Remotes.GetEvent("StorageMove"):FireServer("Store", entry.Uid)
				end)
			end
		end

		local stored = {}
		for uid, record in source.Stored() do
			table.insert(stored, { Uid = uid, Id = record.id, At = record.acquiredAt })
		end
		table.sort(stored, function(a, b)
			if a.At ~= b.At then
				return a.At > b.At
			end
			return a.Uid < b.Uid
		end)
		local storageMax = Players.LocalPlayer:GetAttribute("StorageMax") or "?"
		local chestLevel = Players.LocalPlayer:GetAttribute("ChestLevel")
		chestLevel = if type(chestLevel) == "number" then chestLevel else 1
		local levelInfo = BaseConfig.Chest.Levels[chestLevel]
		local nextLevel = BaseConfig.Chest.Levels[chestLevel + 1]
		local chestRow = Window.Row(list, add(), `CHEST  ·  {levelInfo.Name}  ·  {#stored}/{storageMax}`,
			if here then "Store and take items here" else "Stand at your chest (C) to store / take", nil)
		if nextLevel ~= nil then
			local playerLevel = Players.LocalPlayer:GetAttribute("Level") or 1
			local locked = playerLevel < (nextLevel.RequiredLevel or 1)
			local text = if locked then `LV {nextLevel.RequiredLevel}` else `UPGRADE {KlunksFormat.Format(nextLevel.Price)}`
			local upgrade = Window.SmallButton(chestRow.Right, text, if here and not locked then Theme.Colors.Accent else Theme.Colors.InkSoft,
				UDim2.new(0, 170, 0, 40))
			if not locked then
				upgrade.Activated:Connect(function()
					Remotes.GetEvent("BaseAction"):FireServer(newRequestId(), "UpgradeChest")
				end)
			end
			chestRow.Subtitle.Text ..= `  ·  next: {nextLevel.Capacity} slots`
		end
		for _, entry in stored do
			if filter == "ALL" or categoryOf(entry.Id) == filter then
				local row = Window.Row(list, add(), ItemConfig.GetDisplayName(entry.Id),
					`{ItemConfig.GetRarity(entry.Id)}  ·  worth {KlunksFormat.Format(ItemValue.SellPrice(entry.Id))}`, entry.Id)
				local button = Window.SmallButton(row.Right, "TAKE", if here then Theme.Colors.Success else Theme.Colors.InkSoft, UDim2.new(0, 100, 0, 40))
				button.Activated:Connect(function()
					Remotes.GetEvent("StorageMove"):FireServer("Take", entry.Uid)
				end)
			end
		end
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
				refresh()
			end
		end,
		Open = function(gamepad: boolean)
			window.Open(nil, gamepad)
			refresh()
		end,
		Close = window.Close,
		IsOpen = window.IsOpen,
		Refresh = refresh,
	}
end

return Bag
