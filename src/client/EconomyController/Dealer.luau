--!strict
--[[
	Dealer: the Scrap Dealer window (opened with the booth's prompt, R / Y / tap).

	  SELL      every item in your hands and base storage with its price; tap rows to select,
	            SELL sells the selection, SELL ALL sells everything sellable (tap twice to
	            confirm). The total shown uses the same prices as the server (Util/ItemValue).
	  SHOP      Config/ShopConfig entries by category; locked ones show the level they need.
	  UPGRADES  Config/PlayerUpgrades with current -> next effect and price.
	Every action sends only ids plus a fresh request id; the server decides the result.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local BackpackModels = require(ReplicatedStorage.Shared.Util.BackpackModels)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local Theme = require(script.Parent.Parent.UI.Theme)
local UpgradeModels = require(script.Parent.Parent.UI.UpgradeModels)
local Window = require(script.Parent.Window)

export type Source = {
	Carried: () -> { { Uid: string, Id: string } },
	Stored: () -> { [string]: { id: string, acquiredAt: number } },
	Balance: () -> number,
}

export type Dealer = {
	Open: (gamepad: boolean) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Refresh: () -> (),
}

local Dealer = {}

local CONFIRM_SECONDS = 3

local function newRequestId(): string
	return HttpService:GenerateGUID(false)
end

local function playerLevel(): number
	local level = Players.LocalPlayer:GetAttribute("Level")
	return if type(level) == "number" then level else 1
end

local function upgradeLevel(id: string): number
	local level = Players.LocalPlayer:GetAttribute(`Upgrade_{id}`)
	return if type(level) == "number" then level else 1
end

local function formatUpgradeValue(id: string, value: number): string
	if id == "CarryCapacity" then
		return `{GameConfig.Carry.MaxJunk + value} slots`
	elseif id == "Haggler" then
		return `+{math.floor(value * 100 + 0.5)}%`
	elseif id == "WalkSpeed" then
		return `{value} speed`
	elseif id == "PickupRange" then
		return `{value} studs`
	end
	return `{value} items`
end

function Dealer.Mount(screenGui: ScreenGui, source: Source): Dealer
	local window = Window.Mount(screenGui, "DealerWindow", "SCRAP DEALER", { "SELL", "SHOP", "UPGRADES" })
	local selected: { [string]: boolean } = {}
	local confirmUntil = 0

	-- Footer (SELL tab only)
	local summary = Theme.Label({
		Name = "Summary",
		Text = "",
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 17,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = window.Footer,
	})
	local sellButton, sellLabel = Window.SmallButton(window.Footer, "SELL", Theme.Colors.Success,
		UDim2.new(0.22, 0, 0, 46), UDim2.new(0.74, 0, 0.5, 0), Vector2.new(1, 0.5))
	local sellAllButton, sellAllLabel = Window.SmallButton(window.Footer, "SELL ALL", Theme.Colors.Accent,
		UDim2.new(0.24, 0, 0, 46), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))

	local function sellableEntries(): { { Uid: string, Id: string, Where: string, Price: number } }
		local list = {}
		for _, entry in source.Carried() do
			table.insert(list, { Uid = entry.Uid, Id = entry.Id, Where = "HANDS", Price = ItemValue.SellPrice(entry.Id) })
		end
		return list -- only what you carry: chest items have to be brought here
	end

	local function bonusOf(total: number): number
		return ItemValue.HagglerBonus(total, PlayerUpgrades.ValueAt("Haggler", upgradeLevel("Haggler")))
	end

	local function renderSell()
		local list = window.Content("SELL")
		Window.Clear(list)
		local entries = sellableEntries()
		local present: { [string]: boolean } = {}
		local count, total = 0, 0
		for index, entry in entries do
			present[entry.Uid] = true
			local rarity = ItemConfig.GetRarity(entry.Id) or "Common"
			local priceText = if entry.Price > 0 then KlunksFormat.Format(entry.Price) else "not for sale"
			local row = Window.Row(list, index, ItemConfig.GetDisplayName(entry.Id), `{rarity}  ·  {entry.Where}  ·  {priceText}`, entry.Id)
			if entry.Price > 0 then
				local isSelected = selected[entry.Uid] == true
				local toggle = Window.SmallButton(row.Right, if isSelected then "SELECTED" else "SELECT",
					if isSelected then Theme.Colors.Success else Theme.Colors.InkSoft, UDim2.new(0, 110, 0, 40))
				toggle.Activated:Connect(function()
					selected[entry.Uid] = if selected[entry.Uid] then nil else true
					renderSell()
				end)
				if isSelected then
					row.Frame.BackgroundColor3 = Color3.fromRGB(220, 248, 226)
					count += 1
					total += entry.Price
				end
			end
		end
		for uid in selected do
			if not present[uid] then
				selected[uid] = nil
			end
		end
		if #entries == 0 then
			Window.Header(list, 1, "Your hands are empty - bring items from the yard or your chest!")
		end
		local bonus = bonusOf(total)
		summary.Text = `{count} selected  ·  you get {KlunksFormat.Format(total + bonus)}` .. (if bonus > 0 then `  (+{KlunksFormat.Format(bonus)} Haggler)` else "")
		sellButton.AutoButtonColor = count > 0
		sellLabel.Text = "SELL"
		if os.clock() > confirmUntil then
			sellAllLabel.Text = "SELL ALL"
		end
	end

	sellButton.Activated:Connect(function()
		local uids = {}
		for uid in selected do
			table.insert(uids, uid)
			if #uids >= EconomyConfig.MaxItemsPerSale then
				break
			end
		end
		if #uids == 0 then
			return
		end
		Remotes.GetEvent("SellItems"):FireServer(newRequestId(), uids)
		table.clear(selected)
	end)

	sellAllButton.Activated:Connect(function()
		local now = os.clock()
		if now > confirmUntil then
			-- First tap: ask for confirmation.
			local total = 0
			for _, entry in sellableEntries() do
				total += entry.Price
			end
			confirmUntil = now + CONFIRM_SECONDS
			sellAllLabel.Text = `SURE? {KlunksFormat.Format(total + bonusOf(total))}`
			task.delay(CONFIRM_SECONDS, function()
				if os.clock() >= confirmUntil then
					sellAllLabel.Text = "SELL ALL"
				end
			end)
			return
		end
		confirmUntil = 0
		sellAllLabel.Text = "SELL ALL"
		local uids = {}
		for _, entry in sellableEntries() do
			if entry.Price > 0 and #uids < EconomyConfig.MaxItemsPerSale then
				table.insert(uids, entry.Uid)
			end
		end
		if #uids > 0 then
			Remotes.GetEvent("SellItems"):FireServer(newRequestId(), uids)
			table.clear(selected)
		end
	end)

	local function renderShop()
		local list = window.Content("SHOP")
		Window.Clear(list)
		local balance = source.Balance()
		local level = playerLevel()
		local order = 0
		for _, category in ShopConfig.Categories do
			order += 1
			Window.Header(list, order, string.upper(category))
			for _, entry in ShopConfig.Entries do
				if entry.Category == category then
					order += 1
					local price = ItemValue.ShopPrice(entry)
					local required = entry.RequiredLevel or 1
					local rarity = ItemConfig.GetRarity(entry.ItemId) or "Common"
					local row = Window.Row(list, order, ItemConfig.GetDisplayName(entry.ItemId),
						`{rarity}  ·  sells for {KlunksFormat.Format(ItemValue.SellPrice(entry.ItemId))}`, entry.ItemId)
					local locked = level < required
					local affordable = balance >= price
					local text = if locked then `LV {required}` else `BUY {KlunksFormat.Format(price)}`
					local color = if locked or not affordable then Theme.Colors.InkSoft else Theme.Colors.Success
					local button = Window.SmallButton(row.Right, text, color, UDim2.new(0, 140, 0, 40))
					if not locked then
						button.Activated:Connect(function()
							Remotes.GetEvent("ShopBuy"):FireServer(newRequestId(), entry.Id)
						end)
					end
				end
			end
		end
	end

	local function renderUpgrades()
		local list = window.Content("UPGRADES")
		Window.Clear(list)
		local balance = source.Balance()
		local level = playerLevel()
		for index, upgrade in PlayerUpgrades.List do
			local current = upgradeLevel(upgrade.Id)
			local nextLevel = upgrade.Levels[current + 1]
			local now = formatUpgradeValue(upgrade.Id, upgrade.Levels[current].Value)
			local subtitle = if nextLevel ~= nil
				then `{upgrade.Description}  ·  {now} -> {formatUpgradeValue(upgrade.Id, nextLevel.Value)}`
				else `{upgrade.Description}  ·  {now} (max)`
			local row = Window.Row(list, index, `{upgrade.DisplayName}  ·  Lv {current}/{#upgrade.Levels}`, subtitle, nil)
			local shown = math.min(current + 1, #upgrade.Levels) -- what the next level looks like
			Window.RowIcon(row, if upgrade.Id == "CarryCapacity" then BackpackModels.Build(shown) else UpgradeModels.Build(upgrade.Id, shown))
			local text, color, enabled
			if nextLevel == nil then
				text, color, enabled = "MAX", Theme.Colors.InkSoft, false
			elseif level < (nextLevel.RequiredLevel or 1) then
				text, color, enabled = `LV {nextLevel.RequiredLevel}`, Theme.Colors.InkSoft, false
			else
				text = `BUY {KlunksFormat.Format(nextLevel.Price)}`
				color = if balance >= nextLevel.Price then Theme.Colors.Success else Theme.Colors.InkSoft
				enabled = true
			end
			local button = Window.SmallButton(row.Right, text, color, UDim2.new(0, 140, 0, 40))
			if enabled then
				button.Activated:Connect(function()
					Remotes.GetEvent("PlayerUpgradeBuy"):FireServer(newRequestId(), upgrade.Id)
				end)
			end
		end
	end

	local function refresh()
		if not window.IsOpen() then
			return
		end
		local tab = window.CurrentTab()
		window.Footer.Visible = tab == "SELL"
		if tab == "SELL" then
			renderSell()
		elseif tab == "SHOP" then
			renderShop()
		else
			renderUpgrades()
		end
	end
	window.TabChanged.Event:Connect(refresh)

	return {
		Open = function(gamepad: boolean)
			window.Open(nil, gamepad)
			refresh()
		end,
		Close = window.Close,
		IsOpen = window.IsOpen,
		Refresh = refresh,
	}
end

return Dealer
