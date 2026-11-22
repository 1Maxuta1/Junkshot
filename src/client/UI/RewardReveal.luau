--!strict
--[[
	RewardReveal: the reward card shown to the player whose junk was recycled.

	Presentation scales with Rarities.Info[rarity].Effect (0 = Common ... 5 = Mythic):
	  0  plain card, simple pop-in
	  1  + rarity-tinted background
	  2  + pulsing glow behind the card
	  3  + spinning 3D preview, stronger outline
	  4  + suspense beat before the reveal, rotating shine on the glow, bigger pop
	  5  + rainbow glow and banner
	All tweens and connections exist only while the card is visible and are cleaned up on Hide.
	The card only presents a result; `note` tells the player where the item is.
	Gamepad: the button gets selection focus.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Preview = require(script.Parent.Preview)
local Theme = require(script.Parent.Theme)

export type RewardReveal = {
	Show: (itemId: string, rarity: string, note: string, gamepad: boolean) -> (),
	Hide: () -> (),
	IsShown: () -> boolean,
}

local SUSPENSE_TIME = 0.8
local SPIN_TIME = 6 -- seconds per preview turn

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 160)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 140)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 100, 255)),
})

local RewardReveal = {}

function RewardReveal.Mount(screenGui: ScreenGui): RewardReveal
	local overlay = Instance.new("Frame")
	overlay.Name = "RewardReveal"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.55
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay:AddTag("JunkshotMenu") -- blocks throwing while shown (InputController)
	overlay.Parent = screenGui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.46)
	holder.Size = UDim2.fromScale(0.34, 0.62)
	holder.BackgroundTransparency = 1
	holder.Parent = overlay
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(280, 260)
	limit.MaxSize = Vector2.new(440, 470)
	limit.Parent = holder
	local holderScale = Instance.new("UIScale")
	holderScale.Parent = holder

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.12, 1.1)
	glow.BackgroundColor3 = Theme.Colors.White
	glow.Parent = holder
	Theme.Corner(glow, UDim.new(0, 30))
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Parent = glow

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Theme.Colors.Panel
	card.Parent = holder
	Theme.Corner(card, UDim.new(0, 22))
	local cardStroke = Theme.Stroke(card, Theme.Colors.Ink, 3)
	local cardGradient = Instance.new("UIGradient")
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.fromScale(1, 0.16)
	banner.BackgroundColor3 = Theme.Colors.Ink
	banner.Parent = card
	Theme.Corner(banner, UDim.new(0, 22))
	local bannerGradient = Instance.new("UIGradient")
	bannerGradient.Parent = banner
	local rarityLabel = Theme.Label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.fromScale(0.9, 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 16,
		MaxTextSize = 34,
		Parent = banner,
	})
	Theme.TextStroke(rarityLabel, Theme.Colors.Ink, 2)

	Theme.Label({
		Name = "YouGot",
		Text = "YOU GOT",
		Size = UDim2.fromScale(0.8, 0.08),
		Position = UDim2.fromScale(0.1, 0.18),
		Color = Theme.Colors.InkSoft,
		MinTextSize = 12,
		MaxTextSize = 20,
		Parent = card,
	})

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.fromScale(0.5, 0.26)
	viewport.Size = UDim2.fromScale(0.62, 0.32)
	Preview.StyleViewport(viewport)
	viewport.Parent = card
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = viewport

	local nameLabel = Theme.Label({
		Name = "ItemName",
		Text = "",
		Size = UDim2.fromScale(0.92, 0.11),
		Position = UDim2.fromScale(0.04, 0.59),
		Color = Theme.Colors.Ink,
		MinTextSize = 16,
		MaxTextSize = 34,
		Parent = card,
	})
	local nameStroke = Theme.TextStroke(nameLabel, Theme.Colors.Ink, 0)

	local note = Theme.Label({
		Name = "Note",
		Text = "",
		Size = UDim2.fromScale(0.92, 0.07),
		-- Ends above the button even at the minimum card height (260 px, button >= 46 px).
		Position = UDim2.fromScale(0.04, 0.7),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 17,
		Parent = card,
	})

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -12)
	button.Size = UDim2.fromScale(0.6, 0.12)
	button.BackgroundColor3 = Theme.Colors.Accent
	button.Text = ""
	button.Parent = card
	Theme.Corner(button, UDim.new(0, 14))
	Theme.Stroke(button, Theme.Colors.Ink, 3)
	local buttonLimit = Instance.new("UISizeConstraint")
	buttonLimit.MinSize = Vector2.new(170, 46)
	buttonLimit.Parent = button
	local buttonLabel = Theme.Label({
		Name = "Label",
		Text = "AWESOME!",
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 15,
		MaxTextSize = 26,
		Parent = button,
	})
	Theme.TextStroke(buttonLabel, Theme.Colors.AccentDark, 2)

	local shown = false
	local token = 0
	local tweens: { Tween } = {}
	local connections: { RBXScriptConnection } = {}

	local function play(tween: Tween)
		table.insert(tweens, tween)
		tween:Play()
	end

	local function cleanup()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		viewport:ClearAllChildren()
	end

	local function hide()
		if not shown then
			return
		end
		shown = false
		token += 1
		cleanup()
		overlay.Visible = false
		if GuiService.SelectedObject == button then
			GuiService.SelectedObject = nil
		end
	end

	local function spinPreview()
		local camera = viewport.CurrentCamera
		local model = viewport:FindFirstChildWhichIsA("Model")
		if camera == nil or model == nil then
			return
		end
		local center = model:GetBoundingBox().Position
		local offset = camera.CFrame.Position - center
		local angle = Instance.new("NumberValue")
		table.insert(connections, angle.Changed:Connect(function(value: number)
			local rotated = CFrame.Angles(0, value, 0) * offset
			camera.CFrame = CFrame.lookAt(center + rotated, center)
		end))
		play(TweenService:Create(angle, TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			Value = math.pi * 2,
		}))
	end

	local function reveal(itemId: string, rarityInfo: Rarities.RarityInfo)
		local definition = ItemConfig.Get(itemId)
		nameLabel.Text = if definition ~= nil then definition.DisplayName else itemId
		nameLabel.TextColor3 = if rarityInfo.Effect >= 1 then rarityInfo.Color else Theme.Colors.Ink
		nameStroke.Thickness = if rarityInfo.Effect >= 1 then 2 else 0
		Preview.Item(viewport, itemId)
		if rarityInfo.Effect >= 3 then
			spinPreview()
		end
		holderScale.Scale = if rarityInfo.Effect >= 4 then 0.7 else 0.85
		play(TweenService:Create(holderScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}))
	end

	button.Activated:Connect(hide)

	return {
		Show = function(itemId: string, rarity: string, noteText: string, gamepad: boolean)
			hide()
			shown = true
			token += 1
			local myToken = token
			note.Text = noteText

			local rarityInfo = Rarities.Get(rarity) or Rarities.Info.Common
			local effect = rarityInfo.Effect
			local color = rarityInfo.Color

			rarityLabel.Text = string.upper(rarityInfo.DisplayName) .. (if effect >= 4 then "!" else "")
			banner.BackgroundColor3 = color
			bannerGradient.Color = if effect >= 5 then RAINBOW else ColorSequence.new(Color3.new(1, 1, 1))
			cardStroke.Color = if effect >= 1 then color else Theme.Colors.Ink
			cardStroke.Thickness = 3 + math.min(effect, 3)
			cardGradient.Color = if effect >= 1
				then ColorSequence.new(Theme.Colors.Panel, Theme.Colors.Panel:Lerp(color, 0.25))
				else ColorSequence.new(Theme.Colors.Panel)

			glow.Visible = effect >= 2
			glow.BackgroundColor3 = color
			glowGradient.Color = if effect >= 5 then RAINBOW else ColorSequence.new(Color3.new(1, 1, 1))
			glow.BackgroundTransparency = 0.6
			if effect >= 2 then
				play(TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					BackgroundTransparency = 0.15,
				}))
			end
			if effect >= 4 then
				glowGradient.Rotation = 0
				play(TweenService:Create(glowGradient, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
					Rotation = 360,
				}))
			end

			overlay.Visible = true
			if gamepad then
				GuiService.SelectedObject = button
			end

			if effect >= 4 then
				-- Suspense beat: the rarity is visible first, the item a moment later.
				nameLabel.Text = "..."
				viewport:ClearAllChildren()
				holderScale.Scale = 0.9
				task.delay(SUSPENSE_TIME, function()
					if shown and token == myToken then
						reveal(itemId, rarityInfo)
					end
				end)
			else
				reveal(itemId, rarityInfo)
			end
		end,
		Hide = hide,
		IsShown = function()
			return shown
		end,
	}
end

return RewardReveal
