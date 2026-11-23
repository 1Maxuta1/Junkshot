--!strict
--[[
	Hud: the always-visible economy corner (top right, under Roblox's top bar).
	  - Balance pill: the currency, counting up/down smoothly on change; a short "+120" / "-500"
	    floats out of it when money is earned or spent (EconomyFx from the server).
	  - Level badge with an XP bar (Player attributes Level / XP / XPNext).
	  - BAG button (also key B / gamepad View) opens the bag.
	Updates only when the data changes; the count-up is one short tween, no per-frame work.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local Theme = require(script.Parent.Parent.UI.Theme)

export type Hud = {
	SetBalance: (value: number) -> (),
	Float: (amount: number) -> (),
	RefreshLevel: () -> (),
	BagClicked: BindableEvent,
}

local Hud = {}

function Hud.Mount(screenGui: ScreenGui): Hud
	local localPlayer = Players.LocalPlayer
	local bagClicked = Instance.new("BindableEvent")

	local corner = Instance.new("Frame")
	corner.Name = "EconomyCorner"
	corner.AnchorPoint = Vector2.new(1, 0)
	corner.Position = UDim2.new(1, -10, 0, 8)
	corner.Size = UDim2.new(0, 230, 0, 96)
	corner.BackgroundTransparency = 1
	corner.Parent = screenGui

	-- Balance pill
	local pill = Instance.new("Frame")
	pill.Name = "Balance"
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, 0, 0, 0)
	pill.Size = UDim2.new(1, 0, 0, 42)
	pill.BackgroundColor3 = Theme.Colors.Ink
	Theme.Corner(pill, UDim.new(1, 0))
	Theme.Stroke(pill, Theme.Colors.Sun, 2.5)
	local pillScale = Instance.new("UIScale")
	pillScale.Parent = pill
	pill.Parent = corner
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 6, 0.5, 0)
	coin.Size = UDim2.new(0, 32, 0, 32)
	coin.BackgroundColor3 = Theme.Colors.Sun
	Theme.Corner(coin, UDim.new(1, 0))
	Theme.Stroke(coin, Theme.Colors.AccentDark, 2)
	coin.Parent = pill
	Theme.Label({
		Name = "Mark",
		Text = "K",
		Size = UDim2.fromScale(0.8, 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.AccentDark,
		MinTextSize = 12,
		MaxTextSize = 20,
		Parent = coin,
	})
	local balanceLabel = Theme.Label({
		Name = "Amount",
		Text = "0 K",
		Size = UDim2.new(1, -54, 0.8, 0),
		Position = UDim2.new(0, 44, 0.1, 0),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 24,
		XAlignment = Enum.TextXAlignment.Right,
		Parent = pill,
	})

	-- Level badge + XP bar + BAG button
	local levelBadge = Instance.new("Frame")
	levelBadge.Name = "Level"
	levelBadge.Position = UDim2.new(0, 0, 0, 50)
	levelBadge.Size = UDim2.new(1, -78, 0, 40)
	levelBadge.BackgroundColor3 = Theme.Colors.Panel
	Theme.Corner(levelBadge, UDim.new(0, 12))
	Theme.Stroke(levelBadge, Theme.Colors.Ink, 2.5)
	levelBadge.Parent = corner
	local levelLabel = Theme.Label({
		Name = "Text",
		Text = "LV 1",
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.new(0, 8, 0, 2),
		Color = Theme.Colors.Ink,
		MinTextSize = 11,
		MaxTextSize = 16,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = levelBadge,
	})
	local barBack = Instance.new("Frame")
	barBack.Name = "XpBar"
	barBack.Position = UDim2.new(0, 8, 0, 24)
	barBack.Size = UDim2.new(1, -16, 0, 10)
	barBack.BackgroundColor3 = Theme.Colors.PanelTint
	Theme.Corner(barBack, UDim.new(1, 0))
	barBack.Parent = levelBadge
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Theme.Colors.Success
	Theme.Corner(barFill, UDim.new(1, 0))
	barFill.Parent = barBack

	local bag = Instance.new("TextButton")
	bag.Name = "Bag"
	bag.AnchorPoint = Vector2.new(1, 0)
	bag.Position = UDim2.new(1, 0, 0, 50)
	bag.Size = UDim2.new(0, 70, 0, 44)
	bag.BackgroundColor3 = Theme.Colors.Accent
	bag.Text = ""
	Theme.Corner(bag, UDim.new(0, 12))
	Theme.Stroke(bag, Theme.Colors.Ink, 2.5)
	local bagLabel = Theme.Label({
		Name = "Label",
		Text = "BAG",
		Size = UDim2.fromScale(0.85, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 12,
		MaxTextSize = 20,
		Parent = bag,
	})
	Theme.TextStroke(bagLabel, Theme.Colors.Ink, 1.5)
	bag.Parent = corner
	bag.Activated:Connect(function()
		bagClicked:Fire()
	end)

	-- Smooth count: a NumberValue tweened towards the new balance.
	local shown = Instance.new("NumberValue")
	shown.Value = 0
	shown.Changed:Connect(function(value: number)
		balanceLabel.Text = KlunksFormat.Format(math.floor(value + 0.5))
	end)
	local countTween: Tween? = nil
	local initialized = false

	local function setBalance(value: number)
		if countTween ~= nil then
			countTween:Cancel()
		end
		if not initialized then
			initialized = true
			shown.Value = value
			balanceLabel.Text = KlunksFormat.Format(value)
			return
		end
		countTween = TweenService:Create(shown, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = value })
		countTween:Play()
	end

	local function float(amount: number)
		local label = Theme.Label({
			Name = "Float",
			Text = (if amount > 0 then "+" else "") .. KlunksFormat.Format(amount),
			Size = UDim2.new(0, 160, 0, 30),
			Position = UDim2.new(0, -8, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Color = if amount > 0 then Theme.Colors.Success else Theme.Colors.Danger,
			MinTextSize = 16,
			MaxTextSize = 24,
			XAlignment = Enum.TextXAlignment.Right,
			Parent = corner,
		})
		Theme.TextStroke(label, Theme.Colors.Ink, 2)
		local tween = TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, -8, 0, 60),
			TextTransparency = 1,
		})
		tween.Completed:Connect(function()
			label:Destroy()
		end)
		tween:Play()
		pillScale.Scale = 1.12
		TweenService:Create(pillScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end

	local function refreshLevel()
		local level = localPlayer:GetAttribute("Level")
		local xp = localPlayer:GetAttribute("XP")
		local nextXp = localPlayer:GetAttribute("XPNext")
		levelLabel.Text = if type(level) == "number" then `LV {level}` else "LV 1"
		local ratio = 0
		if type(xp) == "number" and type(nextXp) == "number" and nextXp > 0 then
			ratio = math.clamp(xp / nextXp, 0, 1)
			levelLabel.Text ..= `   {xp}/{nextXp} XP`
		elseif type(nextXp) == "number" and nextXp == 0 then
			ratio = 1
			levelLabel.Text ..= "   MAX"
		end
		TweenService:Create(barFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
	for _, attribute in { "Level", "XP", "XPNext" } do
		localPlayer:GetAttributeChangedSignal(attribute):Connect(refreshLevel)
	end
	refreshLevel()

	return {
		SetBalance = setBalance,
		Float = float,
		RefreshLevel = refreshLevel,
		BagClicked = bagClicked,
	}
end

return Hud
