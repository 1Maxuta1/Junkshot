--!strict
--[[
	MachinePanel: the Recycling Machine window (pure presentation; MachineController decides
	what to show and sends requests; the server decides everything).

	  Header      title + close button
	  Status      "Pick junk to recycle" / "Busy: Alex is recycling" / "Recycling..."
	  Item grid   the local player's carried junk (3D previews); tap/click/A to select
	  Progress    bar driven by one tween per phase (no per-frame code)
	  Action      big RECYCLE button, or CLAIM REWARD when a held reward waits for this player

	Scale-based layout with min/max sizes; centered above the hotbar, clear of the touch
	thumbstick and jump button. Buttons are at least 44 px tall. Gamepad: the first card gets
	selection focus on open, B closes (bound only while open).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Preview = require(script.Parent.Preview)
local Theme = require(script.Parent.Theme)

export type View = {
	Status: string,
	Items: { Types.CarriedJunk },
	SelectedUid: string?,
	ShowItems: boolean, -- false while the machine is busy (grid replaced by the status)
	ActionText: string,
	ActionEnabled: boolean,
	ActionKind: "Recycle" | "Claim" | "None",
	Progress: { Fraction: number, Remaining: number }?, -- nil hides the bar
	-- A slim status + progress strip near the top instead of the full window, so the machine's
	-- animation stays visible while it works.
	Compact: boolean,
}

export type Callbacks = {
	OnSelect: (uid: string) -> (),
	OnAction: (kind: string) -> (),
	OnClose: () -> (),
}

export type Panel = {
	Open: (gamepad: boolean) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Render: (view: View) -> (),
}

local CLOSE_ACTION = "JunkshotMachinePanelClose" -- B on a gamepad closes the panel

local MachinePanel = {}

function MachinePanel.Mount(screenGui: ScreenGui, callbacks: Callbacks): Panel
	local root = Instance.new("Frame")
	root.Name = "MachinePanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.44)
	root.Size = UDim2.fromScale(0.46, 0.6)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Visible = false
	Theme.Corner(root, UDim.new(0, 22))
	Theme.Stroke(root, Theme.Colors.Ink, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(330, 250)
	limit.MaxSize = Vector2.new(620, 470)
	limit.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = root
	root.Parent = screenGui

	-- Header
	local title = Theme.Label({
		Name = "Title",
		Text = "RECYCLING MACHINE",
		Size = UDim2.new(1, -60, 0.14, 0),
		Color = Theme.Colors.Ink,
		MinTextSize = 16,
		MaxTextSize = 30,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	title.TextColor3 = Theme.Colors.AccentDark

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.fromScale(1, 0)
	closeButton.Size = UDim2.fromOffset(46, 46)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.Text = "X"
	closeButton.Font = Theme.Font
	closeButton.TextSize = 24
	closeButton.TextColor3 = Theme.Colors.White
	Theme.Corner(closeButton, UDim.new(1, 0))
	Theme.Stroke(closeButton, Theme.Colors.Ink, 2)
	closeButton.Parent = root

	local status = Theme.Label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.fromScale(0, 0.15),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 13,
		MaxTextSize = 20,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})

	-- Item grid
	local grid = Instance.new("Frame")
	grid.Name = "Items"
	grid.Position = UDim2.fromScale(0, 0.27)
	grid.Size = UDim2.fromScale(1, 0.48)
	grid.BackgroundTransparency = 1
	grid.Parent = root
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromScale(0.31, 0.47)
	gridLayout.CellPadding = UDim2.fromScale(0.035, 0.06)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local empty = Theme.Label({
		Name = "Empty",
		Text = "No junk to recycle.\nPick some up in the yard!",
		Size = UDim2.fromScale(1, 0.48),
		Position = UDim2.fromScale(0, 0.27),
		Color = Theme.Colors.InkSoft,
		MinTextSize = 14,
		MaxTextSize = 24,
		Parent = root,
	})
	empty.Visible = false

	-- Progress bar
	local barBack = Instance.new("Frame")
	barBack.Name = "Progress"
	barBack.Position = UDim2.fromScale(0, 0.45)
	barBack.Size = UDim2.new(1, 0, 0, 22)
	barBack.BackgroundColor3 = Theme.Colors.PanelTint
	barBack.Visible = false
	Theme.Corner(barBack, UDim.new(1, 0))
	Theme.Stroke(barBack, Theme.Colors.Ink, 2)
	barBack.Parent = root
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Theme.Colors.Accent
	Theme.Corner(barFill, UDim.new(1, 0))
	barFill.Parent = barBack

	-- Action button
	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.fromScale(0.5, 1)
	action.Size = UDim2.new(0.6, 0, 0.17, 0)
	action.BackgroundColor3 = Theme.Colors.Accent
	action.AutoButtonColor = true
	action.Text = ""
	Theme.Corner(action, UDim.new(0, 14))
	Theme.Stroke(action, Theme.Colors.Ink, 3)
	local actionLimit = Instance.new("UISizeConstraint")
	actionLimit.MinSize = Vector2.new(180, 48)
	actionLimit.Parent = action
	action.Parent = root
	local actionLabel = Theme.Label({
		Name = "Label",
		Text = "RECYCLE",
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 16,
		MaxTextSize = 30,
		Parent = action,
	})
	Theme.TextStroke(actionLabel, Theme.Colors.AccentDark, 2)

	local cards: { [string]: TextButton } = {}
	local cardKey = ""
	local currentView: View? = nil
	local actionKind = "None"
	local actionEnabled = false
	local barTween: Tween? = nil
	local open = false

	local function rebuildCards(items: { Types.CarriedJunk })
		local key = ""
		for _, entry in items do
			key ..= entry.Uid .. ";"
		end
		if key == cardKey then
			return
		end
		cardKey = key
		for _, card in cards do
			card:Destroy()
		end
		table.clear(cards)
		for index, entry in items do
			local card = Instance.new("TextButton")
			card.Name = `Card{index}`
			card.LayoutOrder = index
			card.Text = ""
			card.AutoButtonColor = false
			card.BackgroundColor3 = Theme.Colors.PanelTint
			Theme.Corner(card, UDim.new(0, 12))
			local stroke = Theme.Stroke(card, Theme.Colors.Ink, 2)
			stroke.Name = "Outline"

			local viewport = Instance.new("ViewportFrame")
			viewport.Name = "Preview"
			viewport.Size = UDim2.fromScale(1, 0.72)
			Preview.StyleViewport(viewport)
			viewport.Parent = card
			Preview.Junk(viewport, entry.Id)

			local definition = JunkConfig.Get(entry.Id)
			Theme.Label({
				Name = "Name",
				Text = if definition ~= nil then definition.DisplayName else entry.Id,
				Size = UDim2.fromScale(0.94, 0.26),
				Position = UDim2.fromScale(0.03, 0.72),
				Color = Theme.Colors.Ink,
				MinTextSize = 11,
				MaxTextSize = 18,
				Parent = card,
			})

			local uid = entry.Uid
			card.Activated:Connect(function()
				callbacks.OnSelect(uid)
			end)
			card.Parent = grid
			cards[uid] = card
		end
	end

	local function applyLayout(compact: boolean)
		if compact then
			root.Position = UDim2.fromScale(0.5, 0.27)
			root.Size = UDim2.fromScale(0.36, 0.13)
			limit.MinSize = Vector2.new(300, 86)
			limit.MaxSize = Vector2.new(520, 110)
			title.Visible = false
			status.Position = UDim2.fromScale(0, 0)
			status.Size = UDim2.new(1, -54, 0.45, 0)
			barBack.Position = UDim2.new(0, 0, 0.55, 0)
			barBack.Size = UDim2.new(1, -54, 0, 20)
		else
			root.Position = UDim2.fromScale(0.5, 0.44)
			root.Size = UDim2.fromScale(0.46, 0.6)
			limit.MinSize = Vector2.new(330, 250)
			limit.MaxSize = Vector2.new(620, 470)
			title.Visible = true
			status.Position = UDim2.fromScale(0, 0.15)
			status.Size = UDim2.new(1, 0, 0.1, 0)
			barBack.Position = UDim2.fromScale(0, 0.45)
			barBack.Size = UDim2.new(1, 0, 0, 22)
		end
	end

	local function render(view: View)
		currentView = view
		applyLayout(view.Compact)
		status.Text = view.Status

		rebuildCards(view.Items)
		local hasItems = #view.Items > 0
		grid.Visible = view.ShowItems and hasItems
		empty.Visible = view.ShowItems and not hasItems
		for uid, card in cards do
			local selected = uid == view.SelectedUid
			card.BackgroundColor3 = if selected then Color3.fromRGB(255, 236, 200) else Theme.Colors.PanelTint
			local outline = card:FindFirstChild("Outline") :: UIStroke?
			if outline ~= nil then
				outline.Color = if selected then Theme.Colors.Accent else Theme.Colors.Ink
				outline.Thickness = if selected then 4 else 2
			end
		end

		actionKind = view.ActionKind
		actionEnabled = view.ActionEnabled
		action.Visible = view.ActionKind ~= "None" and not view.Compact
		actionLabel.Text = view.ActionText
		action.BackgroundColor3 = if not actionEnabled
			then Theme.Colors.InkSoft
			elseif view.ActionKind == "Claim" then Theme.Colors.Success
			else Theme.Colors.Accent

		local progress = view.Progress
		if barTween ~= nil then
			barTween:Cancel()
			barTween = nil
		end
		barBack.Visible = progress ~= nil
		if progress ~= nil then
			barFill.Size = UDim2.fromScale(math.clamp(progress.Fraction, 0, 1), 1)
			if progress.Remaining > 0 then
				barTween = TweenService:Create(barFill, TweenInfo.new(progress.Remaining, Enum.EasingStyle.Linear), {
					Size = UDim2.fromScale(1, 1),
				})
				barTween:Play()
			end
		end
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
		callbacks.OnClose()
	end

	closeButton.Activated:Connect(close)
	action.Activated:Connect(function()
		if actionEnabled then
			callbacks.OnAction(actionKind)
		end
	end)

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
				local view = currentView
				local first = if view ~= nil and view.Items[1] ~= nil then cards[view.Items[1].Uid] else nil
				GuiService.SelectedObject = first or action
			end
		end,
		Close = close,
		IsOpen = function()
			return open
		end,
		Render = render,
	}
end

return MachinePanel
