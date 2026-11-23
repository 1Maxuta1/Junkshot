--!strict
--[[
	UpgradesTab: Klunks upgrades (MachineConfig.Upgrades) and the optional Robux section
	(MonetizationConfig). Products with id 0 are shown as "Coming soon" and cannot be bought.
	Prices and levels shown here are informational; the server checks and charges.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local UpgradesTab = {}

local function describe(upgradeId: string, value: number): string
	if upgradeId == "Speed" then
		return `{math.floor((1 - value) * 100 + 0.5)}% faster`
	elseif upgradeId == "Storage" then
		return `{value} tray slot{if value == 1 then "" else "s"}`
	end
	return `Level {value}`
end

type Row = { Info: TextLabel, Button: TextButton, Label: TextLabel }

function UpgradesTab.Mount(container: Frame, actions: Widgets.Actions): Widgets.Tab
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Parent = container
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	local function row(order: number, title: string, buttonColor: Color3?): Row
		local frame = Instance.new("Frame")
		frame.Name = title
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, -10, 0, 52)
		frame.BackgroundColor3 = Theme.Colors.PanelTint
		Theme.Corner(frame, UDim.new(0, 10))
		frame.Parent = scroller
		local info = Theme.Label({
			Name = "Info",
			Text = title,
			Size = UDim2.new(0.68, -10, 1, -8),
			Position = UDim2.fromOffset(10, 4),
			Color = Theme.Colors.Ink,
			Font = Theme.FontBody,
			MinTextSize = 10,
			MaxTextSize = 16,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		info.RichText = true
		local button, label = Widgets.Button({
			Name = "Buy",
			Text = "BUY",
			Size = UDim2.new(0.3, -6, 1, -8),
			Position = UDim2.new(1, -4, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = buttonColor,
			Parent = frame,
		})
		return { Info = info, Button = button, Label = label }
	end

	local upgradeRows: { [string]: Row } = {}
	for index, upgradeId in MachineConfig.UpgradeOrder do
		local definition = (MachineConfig.Upgrades :: any)[upgradeId]
		local entry = row(index, definition.DisplayName)
		entry.Button.Activated:Connect(function()
			actions.Upgrade(upgradeId)
		end)
		upgradeRows[upgradeId] = entry
	end

	local robuxHeader = Theme.Label({
		Name = "RobuxHeader",
		Text = "Robux boosts (optional)",
		Size = UDim2.new(1, -10, 0, 26),
		Color = Theme.Colors.InkSoft,
		MinTextSize = 12,
		MaxTextSize = 18,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = scroller,
	})
	robuxHeader.LayoutOrder = 50

	local order = 51
	for key, product in MonetizationConfig.Products do
		if not product.ShowInMachine then
			continue
		end
		local entry = row(order, product.DisplayName, Theme.Colors.Success)
		order += 1
		local available = product.ProductId ~= 0
		entry.Info.Text = `<b>{product.DisplayName}</b>\n{product.Description}`
		entry.Label.Text = if available then "R$" else "SOON"
		entry.Button.BackgroundColor3 = if available then Theme.Colors.Success else Theme.Colors.InkSoft
		entry.Button.Activated:Connect(function()
			if available then
				actions.BuyProduct(key)
			end
		end)
	end
	for key, pass in MonetizationConfig.GamePasses do
		if not pass.ShowInMachine then
			continue
		end
		local entry = row(order, pass.DisplayName, Theme.Colors.Success)
		order += 1
		local available = pass.GamePassId ~= 0
		entry.Info.Text = `<b>{pass.DisplayName}</b>\n{pass.Description}`
		entry.Label.Text = if available then "PASS" else "SOON"
		entry.Button.BackgroundColor3 = if available then Theme.Colors.Success else Theme.Colors.InkSoft
		entry.Button.Activated:Connect(function()
			if available then
				actions.BuyPass(key)
			end
		end)
	end

	local function render(view: Widgets.View)
		for upgradeId, entry in upgradeRows do
			local definition = (MachineConfig.Upgrades :: any)[upgradeId]
			local level = (view.Upgrades :: any)[upgradeId] :: number
			local current = definition.Levels[level].Value
			local nextLevel = definition.Levels[level + 1]
			if nextLevel == nil then
				entry.Info.Text = `<b>{definition.DisplayName}</b>  MAX\n{describe(upgradeId, current)}`
				entry.Label.Text = "MAX"
				entry.Button.BackgroundColor3 = Theme.Colors.InkSoft
			else
				local affordable = view.Klunks >= nextLevel.Price
				entry.Info.Text = `<b>{definition.DisplayName}</b>  {level}/{#definition.Levels}\n{describe(upgradeId, current)} -> {describe(upgradeId, nextLevel.Value)}`
				entry.Label.Text = KlunksFormat.Format(nextLevel.Price)
				entry.Button.BackgroundColor3 = if affordable then Theme.Colors.Accent else Theme.Colors.InkSoft
			end
		end
	end

	return { Render = render }
end

return UpgradesTab
