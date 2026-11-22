--!strict
--[[
	Panel: the personal machine window.

	  Header   title, machine level, close
	  Status   what the machine is doing, a progress bar with the remaining time and the
	           SPEED UP button (every tap = minus one second, validated by the server)
	  Tray     finished items waiting for the player (TAKE moves one into the hands)
	  Tabs     RECYCLE | CRAFT | MYTHIC | UPGRADES (modules next to this file)

	Render(view) is called on state changes; Tick() once per second while open (time text and
	progress only). Gamepad: focus starts on the first tab, B closes.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local RecycleTab = require(script.Parent.RecycleTab)
local CraftTab = require(script.Parent.CraftTab)
local MythicTab = require(script.Parent.MythicTab)
local UpgradesTab = require(script.Parent.UpgradesTab)

export type Panel = {
	Open: (gamepad: boolean) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Render: (view: Widgets.View) -> (),
	Tick: () -> (),
	Closed: BindableEvent,
}

local CLOSE_ACTION = "JunkshotMachinePanelClose"
local TAB_NAMES = { "RECYCLE", "CRAFT", "MYTHIC", "UPGRADES" }

local Panel = {}

function Panel.Mount(screenGui: ScreenGui, actions: Widgets.Actions, durationFor: (base: number) -> number): Panel
	local closed = Instance.new("BindableEvent")

	local root = Instance.new("Frame")
	root.Name = "MachinePanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.47)
	root.Size = UDim2.fromScale(0.66, 0.78)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Visible = false
	root:AddTag("JunkshotMenu") -- blocks throwing while open (InputController)
	Theme.Corner(root, UDim.new(0, 20))
	Theme.Stroke(root, Theme.Colors.Ink, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(430, 300)
	limit.MaxSize = Vector2.new(800, 560)
	limit.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = root
	root.Parent = screenGui

	-- Header
	local title = Theme.Label({
		Name = "Title",
		Text = "MY MACHINE",
		Size = UDim2.new(0.6, 0, 0.09, 0),
		Color = Theme.Colors.AccentDark,
		MinTextSize = 14,
		MaxTextSize = 26,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	local closeButton = Widgets.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Colors.Danger,
		Parent = root,
	})

	-- Status
	local statusLabel = Theme.Label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(0.55, 0, 0.08, 0),
		Position = UDim2.fromScale(0, 0.11),
		Color = Theme.Colors.Ink,
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 18,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	local timeLabel = Theme.Label({
		Name = "Time",
		Text = "",
		Size = UDim2.new(0.15, 0, 0.08, 0),
		Position = UDim2.fromScale(0.56, 0.11),
		Color = Theme.Colors.Ink,
		MinTextSize = 11,
		MaxTextSize = 20,
		XAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	local barBack = Instance.new("Frame")
	barBack.Name = "Progress"
	barBack.Position = UDim2.fromScale(0, 0.2)
	barBack.Size = UDim2.new(0.71, 0, 0.045, 0)
	barBack.BackgroundColor3 = Theme.Colors.PanelTint
	Theme.Corner(barBack, UDim.new(1, 0))
	Theme.Stroke(barBack, Theme.Colors.Ink, 1.5)
	barBack.Parent = root
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Theme.Colors.Accent
	Theme.Corner(barFill, UDim.new(1, 0))
	barFill.Parent = barBack

	local speedButton, speedLabel = Widgets.Button({
		Name = "SpeedUp",
		Text = "SPEED UP\n-1s",
		Size = UDim2.fromScale(0.26, 0.16),
		Position = UDim2.fromScale(1, 0.1),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Colors.Ice,
		MinSize = Vector2.new(100, 48),
		Parent = root,
	})
	local speedScale = Instance.new("UIScale")
	speedScale.Parent = speedButton

	-- Tray
	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.Position = UDim2.fromScale(0, 0.28)
	tray.Size = UDim2.fromScale(1, 0.1)
	tray.BackgroundColor3 = Theme.Colors.PanelTint
	tray.BackgroundTransparency = 0.3
	Theme.Corner(tray, UDim.new(0, 10))
	tray.Parent = root
	local trayLayout = Instance.new("UIListLayout")
	trayLayout.FillDirection = Enum.FillDirection.Horizontal
	trayLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trayLayout.Padding = UDim.new(0, 6)
	trayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trayLayout.Parent = tray
	local trayPadding = Instance.new("UIPadding")
	trayPadding.PaddingLeft = UDim.new(0, 8)
	trayPadding.Parent = tray

	-- Tabs
	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.Position = UDim2.fromScale(0, 0.4)
	tabRow.Size = UDim2.fromScale(1, 0.09)
	tabRow.BackgroundTransparency = 1
	tabRow.Parent = root
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0.015, 0)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromScale(0, 0.52)
	content.Size = UDim2.fromScale(1, 0.48)
	content.BackgroundTransparency = 1
	content.Parent = root

	local tabFrames: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local tabs: { [string]: Widgets.Tab } = {}
	local currentTab = TAB_NAMES[1]
	local open = false
	local lastView: Widgets.View? = nil
	local trayKey = ""
	local barTween: Tween? = nil

	for index, name in TAB_NAMES do
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Visible = index == 1
		frame.Parent = content
		tabFrames[name] = frame

		local button = Widgets.Button({
			Name = name,
			Text = name,
			Size = UDim2.fromScale(0.235, 1),
			Color = Theme.Colors.PanelTint,
			MinSize = Vector2.new(0, 40),
			Parent = tabRow,
		})
		button.LayoutOrder = index
		button.Activated:Connect(function()
			currentTab = name
			for tabName, tabFrame in tabFrames do
				tabFrame.Visible = tabName == name
			end
			for tabName, tabButton in tabButtons do
				tabButton.BackgroundColor3 = if tabName == name then Theme.Colors.Accent else Theme.Colors.PanelTint
			end
		end)
		tabButtons[name] = button
	end
	tabButtons[currentTab].BackgroundColor3 = Theme.Colors.Accent

	tabs.RECYCLE = RecycleTab.Mount(tabFrames.RECYCLE, actions, durationFor)
	tabs.CRAFT = CraftTab.Mount(tabFrames.CRAFT, actions, durationFor)
	tabs.MYTHIC = MythicTab.Mount(tabFrames.MYTHIC, actions)
	tabs.UPGRADES = UpgradesTab.Mount(tabFrames.UPGRADES, actions)

	speedButton.Activated:Connect(function()
		if lastView ~= nil and lastView.State == "Processing" then
			actions.Accelerate()
			speedScale.Scale = 0.9
			TweenService:Create(speedScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end
	end)

	local function tick()
		local view = lastView
		if view == nil or not open then
			return
		end
		if view.State == "Processing" then
			local left = math.max(0, view.CompletesAt - Workspace:GetServerTimeNow())
			local fraction = if view.Duration > 0 then math.clamp(1 - left / view.Duration, 0, 1) else 1
			timeLabel.Text = Widgets.FormatTime(left)
			if barTween ~= nil then
				barTween:Cancel()
			end
			-- Glide to where the bar will be in one second (smooth without per-frame code).
			local nextFraction = if view.Duration > 0 then math.clamp(1 - (left - 1) / view.Duration, 0, 1) else 1
			barFill.Size = UDim2.fromScale(fraction, 1)
			barTween = TweenService:Create(barFill, TweenInfo.new(1, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(nextFraction, 1) })
			barTween:Play()
		else
			timeLabel.Text = ""
			barFill.Size = UDim2.fromScale(if view.State == "RewardReady" then 1 else 0, 1)
		end
	end

	local function renderTray(view: Widgets.View)
		local newKey = Widgets.Key(view.Output) .. "/" .. view.OutputCapacity
		if newKey == trayKey then
			return
		end
		trayKey = newKey
		Widgets.Clear(tray)
		local header = Theme.Label({
			Name = "Header",
			Text = `TRAY {#view.Output}/{view.OutputCapacity}`,
			Size = UDim2.new(0.16, 0, 0.8, 0),
			Color = Theme.Colors.InkSoft,
			MinTextSize = 10,
			MaxTextSize = 16,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = tray,
		})
		header.LayoutOrder = 0
		if #view.Output == 0 then
			local empty = Theme.Label({
				Name = "Empty",
				Text = "Finished items appear here and on your machine's tray",
				Size = UDim2.new(0.8, 0, 0.7, 0),
				Color = Theme.Colors.InkSoft,
				Font = Theme.FontBody,
				MinTextSize = 9,
				MaxTextSize = 14,
				XAlignment = Enum.TextXAlignment.Left,
				Parent = tray,
			})
			empty.LayoutOrder = 1
			return
		end
		for index, entry in view.Output do
			local rarity = ItemConfig.GetRarity(entry.Id)
			local button = Widgets.Button({
				Name = `Take{index}`,
				Text = `TAKE {ItemConfig.GetDisplayName(entry.Id)}`,
				Size = UDim2.new(0.26, 0, 0.85, 0),
				Color = Rarities.GetColor(rarity),
				MinSize = Vector2.new(90, 36),
				Parent = tray,
			})
			button.LayoutOrder = index
			local uid = entry.Uid
			button.Activated:Connect(function()
				actions.Take(uid)
			end)
		end
	end

	local function render(view: Widgets.View)
		lastView = view
		title.Text = `MY MACHINE  ·  LV {view.MachineLevel}`
		if view.State == "Processing" then
			statusLabel.Text = view.JobLabel
		elseif view.State == "RewardReady" then
			statusLabel.Text = "Done! Take your items from the tray"
		else
			statusLabel.Text = "Ready. Choose what to do below."
		end
		speedButton.Visible = view.State == "Processing"
		speedLabel.Text = "SPEED UP\n-1s"
		renderTray(view)
		for _, tab in tabs do
			tab.Render(view)
		end
		tick()
	end

	local function close()
		if not open then
			return
		end
		open = false
		root.Visible = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
		if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		closed:Fire()
	end
	closeButton.Activated:Connect(close)

	return {
		Open = function(gamepad: boolean)
			if not open then
				open = true
				root.Visible = true
				ContextActionService:BindAction(CLOSE_ACTION, function(_, inputState)
					if inputState == Enum.UserInputState.Begin then
						close()
					end
					return Enum.ContextActionResult.Sink
				end, false, Enum.KeyCode.ButtonB)
			end
			if gamepad then
				GuiService.SelectedObject = tabButtons[currentTab]
			end
			tick()
		end,
		Close = close,
		IsOpen = function()
			return open
		end,
		Render = render,
		Tick = tick,
		Closed = closed,
	}
end

return Panel
