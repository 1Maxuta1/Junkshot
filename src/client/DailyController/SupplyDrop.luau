--!strict
--[[
	SupplyDrop: the big daily reward window (seven day cards in a riveted scrap-metal frame).
	DailyController opens it by itself on the first visit of a day and from the QUESTS window.
	Display only; CLAIM asks the server.

	  Mount(gui, onClaim) -> { Open(state), Close(), IsOpen(), Claimed(day) }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local AudioController = require(script.Parent.Parent.AudioController)
local Preview = require(script.Parent.Parent.UI.Preview)
local Menus = require(script.Parent.Parent.UI.Menus)
local Theme = require(script.Parent.Parent.UI.Theme)

local SupplyDrop = {}

local rgb = Color3.fromRGB
local STEEL, STEEL_DARK, NIGHT, GOLD = rgb(62, 78, 112), rgb(38, 48, 74), rgb(22, 28, 48), rgb(255, 205, 60)

export type SupplyDrop = {
	Open: (state: any) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Claimed: (day: number) -> (),
}

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, zindex: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 1
	f.Parent = parent
	return f
end

local function shade(parent: Instance, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Parent = parent
end

local function text(parent: Instance, name: string, value: string, position: UDim2, size: UDim2, color: Color3, max: number): TextLabel
	local label = Theme.Label({ Name = name, Text = value, Position = position, Size = size, Color = color, MinTextSize = 10, MaxTextSize = max, Parent = parent })
	Theme.TextStroke(label, NIGHT, 2)
	return label
end

-- ------------------------------------------------------------------------------------------
-- Icons (no image assets: a coin stack, an x2 badge, a 3D item)
-- ------------------------------------------------------------------------------------------

local function coinIcon(parent: Instance)
	for index = 0, 2 do
		local coin = frame(parent, "Coin", UDim2.fromScale(0.5 + (index - 1) * 0.2, 0.58 - (if index == 1 then 0.16 else 0)), UDim2.fromScale(0.56, 0.56), GOLD, 2 + (if index == 1 then 2 else 0))
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.SizeConstraint = Enum.SizeConstraint.RelativeYY
		Theme.Corner(coin, UDim.new(1, 0))
		Theme.Stroke(coin, rgb(204, 120, 0), 2)
		shade(coin, rgb(255, 255, 255), rgb(225, 170, 90))
		local mark = Theme.Label({ Name = "K", Text = GameConfig.Klunks.Symbol, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Color = rgb(176, 96, 0), MinTextSize = 10, MaxTextSize = 40, Parent = coin })
		mark.ZIndex = coin.ZIndex + 1
	end
end

local function boltIcon(parent: Instance)
	local disc = frame(parent, "Disc", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.86, 0.86), rgb(70, 170, 255), 2)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.SizeConstraint = Enum.SizeConstraint.RelativeYY
	Theme.Corner(disc, UDim.new(1, 0))
	Theme.Stroke(disc, rgb(210, 240, 255), 2.5)
	shade(disc, rgb(255, 255, 255), rgb(120, 130, 220))
	local mark = Theme.Label({ Name = "X2", Text = "x2", Size = UDim2.fromScale(0.82, 0.7), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Color = GOLD, MinTextSize = 14, MaxTextSize = 60, Parent = disc })
	mark.ZIndex = 3
	Theme.TextStroke(mark, rgb(20, 40, 110), 3)
end

local function itemIcon(parent: Instance, itemId: string, color: Color3)
	local halo = frame(parent, "Halo", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.92, 0.92), color, 1)
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.SizeConstraint = Enum.SizeConstraint.RelativeYY
	halo.BackgroundTransparency = 0.45
	Theme.Corner(halo, UDim.new(1, 0))
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Item"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 2
	Preview.StyleViewport(viewport)
	viewport.Parent = parent
	Preview.Item(viewport, itemId)
end

local function icon(parent: Instance, reward: any)
	if reward.Kind == "Klunks" then
		coinIcon(parent)
	elseif reward.Kind == "Boost" then
		boltIcon(parent)
	else
		itemIcon(parent, reward.Icon, Rarities.GetColor(reward.Rarity))
	end
end

-- ------------------------------------------------------------------------------------------

function SupplyDrop.Mount(gui: ScreenGui, onClaim: () -> ()): SupplyDrop
	local overlay = frame(gui, "SupplyDropOverlay", UDim2.new(0, -100, 0, -100), UDim2.new(1, 200, 1, 200), NIGHT, 20) -- over the top bar too
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Active = true -- no clicks through to the world
	overlay:AddTag("JunkshotMenu") -- the part whose Visible really changes (InputController)

	local panel = frame(overlay, "SupplyDrop", UDim2.fromScale(0.5, 0.5), UDim2.new(0.9, -180, 0.84, -168), STEEL, 21)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1060, 470)
	limit.Parent = panel
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	Theme.Corner(panel, UDim.new(0, 18))
	Theme.Stroke(panel, GOLD, 4)
	shade(panel, rgb(255, 255, 255), rgb(120, 130, 165))

	-- Hazard stripes along the top and bottom edge
	for _, y in { 0, 1 } do
		local band = frame(panel, "Band", UDim2.new(0, 14, y, if y == 0 then 8 else -18), UDim2.new(1, -28, 0, 10), NIGHT, 22)
		band.ClipsDescendants = true
		Theme.Corner(band, UDim.new(1, 0))
		for index = 0, 40 do
			local stripe = frame(band, "Stripe", UDim2.new(0, index * 30 - 10, 0.5, 0), UDim2.fromOffset(12, 30), GOLD, 23)
			stripe.AnchorPoint = Vector2.new(0, 0.5)
			stripe.Rotation = 30
		end
	end
	-- Rivets in the corners
	for _, x in { 0, 1 } do
		for _, y in { 0, 1 } do
			local rivet = frame(panel, "Rivet", UDim2.new(x, if x == 0 then 18 else -18, y, if y == 0 then 32 else -32), UDim2.fromOffset(14, 14), rgb(176, 188, 204), 23)
			rivet.AnchorPoint = Vector2.new(0.5, 0.5)
			Theme.Corner(rivet, UDim.new(1, 0))
			Theme.Stroke(rivet, NIGHT, 2)
			shade(rivet, rgb(255, 255, 255), rgb(120, 125, 140))
		end
	end

	-- Title plate, sticking out at the top
	local plate = frame(panel, "Plate", UDim2.new(0.5, 0, 0, -6), UDim2.new(0.5, 0, 0, 52), rgb(236, 120, 30), 25)
	plate.AnchorPoint = Vector2.new(0.5, 0.35)
	Theme.Corner(plate, UDim.new(0, 12))
	Theme.Stroke(plate, NIGHT, 3)
	shade(plate, rgb(255, 255, 255), rgb(190, 150, 130))
	local title = text(plate, "Title", "DAILY SUPPLY DROP", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), rgb(255, 255, 255), 34)
	title.ZIndex = 26
	for _, side in { -1, 1 } do
		-- turning gear on both sides of the plate
		local gear = frame(plate, "Gear", UDim2.new(0.5 + side * 0.5, side * 6, 0.5, 0), UDim2.fromOffset(62, 62), GOLD, 27)
		gear.AnchorPoint = Vector2.new(0.5, 0.5)
		gear.BackgroundTransparency = 1
		for index = 0, 3 do
			local bar = frame(gear, "Teeth", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.26, 1), GOLD, 27)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Rotation = index * 45
			Theme.Corner(bar, UDim.new(0.2, 0))
			Theme.Stroke(bar, NIGHT, 2)
		end
		local wheel = frame(gear, "Wheel", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.74), GOLD, 28)
		wheel.AnchorPoint = Vector2.new(0.5, 0.5)
		Theme.Corner(wheel, UDim.new(1, 0))
		Theme.Stroke(wheel, NIGHT, 2)
		shade(wheel, rgb(255, 255, 255), rgb(215, 160, 90))
		local hub = frame(gear, "Hub", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.3, 0.3), STEEL_DARK, 29)
		hub.AnchorPoint = Vector2.new(0.5, 0.5)
		Theme.Corner(hub, UDim.new(1, 0))
	end
	local subtitle = text(panel, "Subtitle", "", UDim2.new(0.1, 0, 0, 46), UDim2.new(0.8, 0, 0, 24), rgb(206, 222, 255), 20)
	subtitle.ZIndex = 24

	-- Cards
	local row = frame(panel, "Days", UDim2.new(0.02, 8, 0, 76), UDim2.new(0.96, -16, 1, -168), STEEL_DARK, 22)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.01, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "Claim"
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Position = UDim2.new(0.5, 0, 1, -28)
	claimButton.Size = UDim2.new(0.36, 0, 0, 52)
	claimButton.BackgroundColor3 = Theme.Colors.Success
	claimButton.Text = ""
	claimButton.ZIndex = 24
	Theme.Corner(claimButton, UDim.new(0, 14))
	Theme.Stroke(claimButton, NIGHT, 3)
	claimButton.Parent = panel
	local claimLabel = text(claimButton, "Label", "CLAIM", UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.76), rgb(255, 255, 255), 28)
	claimLabel.ZIndex = 25
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 24)
	closeButton.Size = UDim2.fromOffset(44, 40)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.Text = ""
	closeButton.ZIndex = 26
	Theme.Corner(closeButton, UDim.new(0, 12))
	Theme.Stroke(closeButton, NIGHT, 3)
	closeButton.Parent = panel
	text(closeButton, "Label", "X", UDim2.fromScale(0.1, 0.12), UDim2.fromScale(0.8, 0.76), rgb(255, 255, 255), 22).ZIndex = 27

	local open = false
	local connection: RBXScriptConnection? = nil
	local rays: { Frame } = {}
	local todayCard: Frame? = nil
	local cards: { [number]: Frame } = {}

	local function buildCard(day: number, today: number, ready: boolean): Frame
		local reward = DailyConfig.DayRewards[day]
		local done = day < today or (day == today and not ready)
		local isToday = day == today and ready
		local last = day == #DailyConfig.DayRewards
		local card = frame(row, `Day{day}`, UDim2.new(), UDim2.fromScale(if last then 0.17 else 0.127, if isToday then 1 else 0.9), if last then rgb(96, 62, 150) else STEEL_DARK, 23)
		card.LayoutOrder = day
		card.ClipsDescendants = true
		Theme.Corner(card, UDim.new(0, 12))
		local edge = if isToday then GOLD elseif done then rgb(80, 200, 120) elseif last then rgb(200, 140, 255) else rgb(96, 116, 160)
		Theme.Stroke(card, edge, if isToday then 4 else 2.5)
		shade(card, rgb(255, 255, 255), rgb(140, 145, 175))
		if isToday then
			-- slow sun rays behind the icon
			for index = 0, 3 do
				local ray = frame(card, "Ray", UDim2.fromScale(0.5, 0.45), UDim2.new(0, 16, 2.2, 0), GOLD, 23)
				ray.AnchorPoint = Vector2.new(0.5, 0.5)
				ray.BackgroundTransparency = 0.82
				ray.Rotation = index * 45
				table.insert(rays, ray)
			end
		end
		local head = frame(card, "Head", UDim2.new(), UDim2.fromScale(1, 0.17), edge, 24)
		Theme.Corner(head, UDim.new(0, 12))
		local headText = text(head, "Day", if isToday then "TODAY" elseif day == today + 1 or (not ready and day == today + 1) then "TOMORROW" else `DAY {day}`, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), rgb(255, 255, 255), 18)
		headText.ZIndex = 25
		local holder = frame(card, "Icon", UDim2.fromScale(0.5, 0.46), UDim2.fromScale(0.86, 0.44), NIGHT, 24)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.BackgroundTransparency = 1
		icon(holder, reward)
		for _, descendant in holder:GetDescendants() do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex += 24
			end
		end
		local name = text(card, "Reward", reward.Text, UDim2.fromScale(0.04, 0.7), UDim2.fromScale(0.92, 0.26), rgb(255, 240, 200), 20)
		name.TextWrapped = true
		name.ZIndex = 26
		if done then
			local veil = frame(card, "Veil", UDim2.new(), UDim2.fromScale(1, 1), NIGHT, 27)
			veil.BackgroundTransparency = 0.45
			Theme.Corner(veil, UDim.new(0, 12))
			local check = text(veil, "Check", "✔", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.6, 0.5), rgb(110, 240, 140), 64)
			check.ZIndex = 28
		end
		local cardScale = Instance.new("UIScale")
		cardScale.Scale = 0
		cardScale.Parent = card
		TweenService:Create(cardScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.12 + day * 0.06), { Scale = 1 }):Play()
		if isToday then
			todayCard = card
		end
		cards[day] = card
		return card
	end

	local function close()
		if not open then
			return
		end
		open = false
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		TweenService:Create(overlay, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
		local out = TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out.Completed:Once(function()
			if not open then
				overlay.Visible = false
			end
		end)
		out:Play()
	end

	local function fill(state: any)
		table.clear(rays)
		todayCard = nil
		for _, child in row:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for day = 1, #DailyConfig.DayRewards do
			buildCard(day, state.Streak, state.RewardReady == true)
		end
		subtitle.Text = if state.RewardReady then `Login streak: day {state.Streak}. Come back every day!` else "Claimed for today. See you tomorrow!"
		claimLabel.Text = if state.RewardReady then "CLAIM" else "CLOSE"
		claimButton.BackgroundColor3 = if state.RewardReady then rgb(70, 225, 125) else Theme.Colors.InkSoft
	end

	local ready = false
	claimButton.Activated:Connect(function()
		if ready then
			ready = false
			onClaim()
		else
			close()
		end
	end)
	closeButton.Activated:Connect(close)

	local function openWith(state: any)
		ready = state.RewardReady == true
		fill(state)
		if open then
			return
		end
		open = true
		overlay.Visible = true
		Menus.Opened(close)
		overlay.BackgroundTransparency = 1
		panelScale.Scale = 0.4
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(panelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local family, pitch = ItemSounds.ForEvent("ChestOpen")
		AudioController.PlayItem(family, pitch, nil, 1)
		connection = RunService.RenderStepped:Connect(function(dt: number)
			for _, child in plate:GetChildren() do
				if child.Name == "Gear" and child:IsA("Frame") then
					child.Rotation += dt * (if child.Position.X.Scale > 0.5 then 50 else -50)
				end
			end
			for _, ray in rays do
				ray.Rotation += dt * 18
			end
			if todayCard ~= nil then
				local stroke = todayCard:FindFirstChildOfClass("UIStroke")
				if stroke ~= nil then
					stroke.Thickness = 4 + math.sin(os.clock() * 4) * 1.2
				end
			end
		end)
	end

	-- A burst of golden squares over the claimed card, then the window closes by itself.
	local function claimed(day: number)
		local card = cards[day]
		if not open or card == nil then
			return
		end
		local family, pitch = ItemSounds.ForEvent("DailyClaim")
		AudioController.PlayItem(family, pitch, nil, 1)
		local center = card.AbsolutePosition + card.AbsoluteSize / 2 - overlay.AbsolutePosition
		for index = 1, 22 do
			local spark = frame(overlay, "Spark", UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(12, 12), if index % 3 == 0 then rgb(255, 255, 255) else GOLD, 40)
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			Theme.Corner(spark, UDim.new(0.3, 0))
			local angle = index / 22 * math.pi * 2
			local reach = 90 + math.random() * 120
			local fly = TweenService:Create(spark, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(center.X + math.cos(angle) * reach, center.Y + math.sin(angle) * reach),
				Rotation = 240,
				BackgroundTransparency = 1,
			})
			fly.Completed:Once(function()
				spark:Destroy()
			end)
			fly:Play()
		end
		task.delay(1.6, close)
	end

	local _ = Players
	return {
		Open = openWith,
		Close = close,
		IsOpen = function(): boolean
			return open
		end,
		Claimed = claimed,
	}
end

return SupplyDrop
