--!strict
--[[
	Window: the shared look of the economy windows (Scrap Dealer, Bag): a rounded panel with a
	title, a close button, optional tabs, one scrolling content area per tab and a footer.
	Everything is Scale-sized with pixel minimums (touch targets >= 44 px), no hover needed.
	Tagged "JunkshotMenu", so throwing is blocked while it is open. Gamepad: B closes, focus
	starts on the first tab.

	Also small builders for list rows and buttons (Window.Row, Window.SmallButton).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local Theme = require(script.Parent.Parent.UI.Theme)

export type Window = {
	Root: Frame,
	Footer: Frame,
	Content: (tab: string) -> ScrollingFrame,
	Open: (tab: string?, gamepad: boolean?) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	CurrentTab: () -> string,
	SetTitle: (text: string) -> (),
	TabChanged: BindableEvent,
	Closed: BindableEvent,
}

local Window = {}

function Window.SmallButton(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2?, anchor: Vector2?): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = size
	button.Position = position or UDim2.new()
	button.AnchorPoint = anchor or Vector2.zero
	button.BackgroundColor3 = color
	button.Text = ""
	button.AutoButtonColor = true
	Theme.Corner(button, UDim.new(0, 10))
	Theme.Stroke(button, Theme.Colors.Ink, 2)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(40, 32)
	limit.Parent = button
	local label = Theme.Label({
		Name = "Label",
		Text = text,
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 11,
		MaxTextSize = 18,
		Parent = button,
	})
	Theme.TextStroke(label, Theme.Colors.Ink, 1.2)
	if parent.Name == "Right" then
		local flex = Instance.new("UIFlexItem") -- several buttons in one row shrink to fit
		flex.FlexMode = Enum.UIFlexMode.Shrink
		flex.Parent = button
	end
	button.Parent = parent
	return button, label
end

-- A HUD button under every window (its own ScreenGui below them all).
function Window.HudButton(name: string, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 4
	local button = Window.SmallButton(gui, text, color, size, position, Vector2.new(1, 0))
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return button
end

-- One list row: rarity strip, title, subtitle, and room on the right for buttons.
export type Row = { Frame: Frame, Title: TextLabel, Subtitle: TextLabel, Right: Frame }

function Window.Row(parent: Instance, order: number, title: string, subtitle: string, itemId: string?): Row
	local frame = Instance.new("Frame")
	frame.Name = `Row{order}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, 52)
	frame.BackgroundColor3 = Theme.Colors.PanelTint
	Theme.Corner(frame, UDim.new(0, 10))
	local rarity = if itemId ~= nil then ItemConfig.GetRarity(itemId) else nil
	local strip = Instance.new("Frame")
	strip.Name = "Rarity"
	strip.Size = UDim2.new(0, 6, 1, -12)
	strip.Position = UDim2.new(0, 6, 0, 6)
	strip.BorderSizePixel = 0
	strip.BackgroundColor3 = if rarity ~= nil then Rarities.GetColor(rarity) else Theme.Colors.Accent
	Theme.Corner(strip, UDim.new(1, 0))
	strip.Parent = frame
	local titleLabel = Theme.Label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(0.55, -20, 0, 24),
		Position = UDim2.new(0, 18, 0, 4),
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 17,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local subtitleLabel = Theme.Label({
		Name = "Subtitle",
		Text = subtitle,
		Size = UDim2.new(0.55, -20, 0, 18),
		Position = UDim2.new(0, 18, 0, 28),
		Font = Theme.FontBody,
		Color = Theme.Colors.InkSoft,
		MinTextSize = 9,
		MaxTextSize = 13,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -6, 0.5, 0)
	right.Size = UDim2.new(0.45, 0, 1, -8)
	right.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = right
	right.Parent = frame
	frame.Parent = parent
	return { Frame = frame, Title = titleLabel, Subtitle = subtitleLabel, Right = right }
end

-- A section header inside a list.
function Window.Header(parent: Instance, order: number, text: string)
	local label = Theme.Label({
		Name = `Header{order}`,
		Text = text,
		Size = UDim2.new(1, -8, 0, 24),
		Color = Theme.Colors.AccentDark,
		MinTextSize = 12,
		MaxTextSize = 18,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	label.LayoutOrder = order
end

function Window.Clear(list: Instance)
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function Window.Mount(screenGui: ScreenGui, name: string, title: string, tabs: { string }): Window
	local closeAction = `Junkshot{name}Close`
	local tabChanged = Instance.new("BindableEvent")
	local closed = Instance.new("BindableEvent")

	local root = Instance.new("Frame")
	root.Name = name
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.47)
	root.Size = UDim2.fromScale(0.66, 0.8)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Visible = false
	root:AddTag("JunkshotMenu")
	Theme.Corner(root, UDim.new(0, 20))
	Theme.Stroke(root, Theme.Colors.Ink, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 220)
	limit.MaxSize = Vector2.new(820, 580)
	limit.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = root
	root.Parent = screenGui
	local function fit() -- phones: use almost the whole screen
		local small = screenGui.AbsoluteSize.Y < 500
		root.Size = if small then UDim2.fromScale(0.94, 0.98) else UDim2.fromScale(0.66, 0.8)
		root.Position = UDim2.fromScale(0.5, if small then 0.5 else 0.47)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local titleLabel = Theme.Label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(0.7, 0, 0, 34),
		Color = Theme.Colors.AccentDark,
		MinTextSize = 16,
		MaxTextSize = 28,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	local closeButton = Window.SmallButton(root, "X", Theme.Colors.Danger, UDim2.new(0, 44, 0, 40), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))

	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.Position = UDim2.new(0, 0, 0, 44)
	tabRow.Size = UDim2.new(1, 0, 0, if #tabs > 1 then 40 else 0)
	tabRow.BackgroundTransparency = 1
	tabRow.Visible = #tabs > 1
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0.015, 0)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow
	tabRow.Parent = root

	local contentTop = if #tabs > 1 then 90 else 46
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, 46)
	footer.BackgroundTransparency = 1
	footer.Parent = root

	local contents: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local current = tabs[1]

	local function showTab(tab: string)
		current = tab
		for tabName, list in contents do
			list.Visible = tabName == tab
		end
		for tabName, button in tabButtons do
			button.BackgroundColor3 = if tabName == tab then Theme.Colors.Accent else Theme.Colors.PanelTint
			local label = button:FindFirstChild("Label") :: TextLabel?
			if label ~= nil then
				label.TextColor3 = if tabName == tab then Theme.Colors.White else Theme.Colors.Ink
			end
		end
		tabChanged:Fire(tab)
	end

	for index, tab in tabs do
		local list = Instance.new("ScrollingFrame")
		list.Name = tab
		list.Position = UDim2.new(0, 0, 0, contentTop)
		list.Size = UDim2.new(1, 0, 1, -(contentTop + 52))
		list.BackgroundColor3 = Theme.Colors.Panel
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 8
		list.ScrollBarImageColor3 = Theme.Colors.InkSoft
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.Visible = index == 1
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		list.Parent = root
		contents[tab] = list

		if #tabs > 1 then
			local button = Window.SmallButton(tabRow, tab, Theme.Colors.PanelTint, UDim2.new(1 / #tabs - 0.015, 0, 1, 0))
			button.LayoutOrder = index
			button.Activated:Connect(function()
				showTab(tab)
			end)
			tabButtons[tab] = button
		end
	end

	local open = false
	local function close()
		if not open then
			return
		end
		open = false
		root.Visible = false
		ContextActionService:UnbindAction(closeAction)
		if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		closed:Fire()
	end
	closeButton.Activated:Connect(close)

	return {
		Root = root,
		Footer = footer,
		Content = function(tab: string): ScrollingFrame
			return contents[tab]
		end,
		Open = function(tab: string?, gamepad: boolean?)
			showTab(tab or current)
			if open then
				return
			end
			open = true
			root.Visible = true
			ContextActionService:BindAction(closeAction, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonB)
			if gamepad then
				GuiService.SelectedObject = tabButtons[tabs[1]] or closeButton
			end
		end,
		Close = close,
		IsOpen = function(): boolean
			return open
		end,
		CurrentTab = function(): string
			return current
		end,
		SetTitle = function(text: string)
			titleLabel.Text = text
		end,
		TabChanged = tabChanged,
		Closed = closed,
	}
end

return Window
