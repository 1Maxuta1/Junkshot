--!strict
--[[
	PickupPrompt: draws every ProximityPrompt with Style = Custom (junk and the machine).

	One small BillboardGui card per prompt that Roblox currently shows; usually one junk card
	(junk prompts use OnePerButton) plus, near the machine, the machine card (its own key,
	AlwaysShow). Cards are created on PromptShown and destroyed on PromptHidden. Roblox still
	owns detection, key handling and the server-side Triggered event; this only draws.
	On touch each card is a button that triggers its prompt.

	When the local player is already full, junk cards turn red ("Carry full 6/6") so the
	player sees it before pressing anything. The server still makes the real decision.
	A prompt's "PromptKind" attribute marks non-junk prompts (e.g. "Machine", "Deployable").
	Placed objects can carry several prompts; "CardOffset" (studs) stacks their cards, and
	prompts with "OwnerOnly" are hidden for everyone but "OwnerUserId".
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Theme = require(script.Parent.Theme)

export type PickupPrompt = {
	SetFull: (full: boolean) -> (),
}

type Card = {
	Gui: BillboardGui,
	Stroke: UIStroke,
	Badge: Frame,
	KeyLabel: TextLabel,
	ActionLabel: TextLabel,
	ObjectLabel: TextLabel,
	InputType: Enum.ProximityPromptInputType,
	Watch: RBXScriptConnection?, -- removes the card if the prompt leaves the world
}

local CARD_SIZE = UDim2.fromOffset(230, 64)
local JUNK_OFFSET = Vector3.new(0, 2.6, 0)
local MACHINE_OFFSET = Vector3.new(0, 4, 0)

local PickupPrompt = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function isJunk(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute("PromptKind") == nil
end

-- Items reserved for another player (their machine tray) and other players' machines.
local function isForSomeoneElse(prompt: ProximityPrompt): boolean
	local me = Players.LocalPlayer.UserId
	local reserved = prompt:GetAttribute("ReservedFor")
	if type(reserved) == "number" and reserved ~= me then
		return true
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	if type(owner) ~= "number" or owner == me then
		return false
	end
	-- Other players' machines, and owner-only actions on other players' placed objects.
	return prompt:GetAttribute("PromptKind") == "Machine" or prompt:GetAttribute("OwnerOnly") == true
end

function PickupPrompt.Mount(onTriggeredLocally: (prompt: ProximityPrompt) -> ()): PickupPrompt
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local cards: { [ProximityPrompt]: Card } = {}
	local full = false

	local function render(prompt: ProximityPrompt, card: Card)
		card.KeyLabel.Text = keyText(prompt, card.InputType)
		if full and isJunk(prompt) then
			card.ActionLabel.Text = "Carry full"
			local capacity = Players.LocalPlayer:GetAttribute("CarryMax") or GameConfig.Carry.MaxJunk
			card.ObjectLabel.Text = `{capacity}/{capacity} - throw something first`
			card.Badge.BackgroundColor3 = Theme.Colors.Danger
			card.Stroke.Color = Theme.Colors.Danger
		else
			card.ActionLabel.Text = prompt.ActionText
			card.ObjectLabel.Text = prompt.ObjectText
			card.Badge.BackgroundColor3 = if isJunk(prompt) then Theme.Colors.Accent else Theme.Colors.Success
			card.Stroke.Color = Theme.Colors.Ink
		end
	end

	local function createCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): Card
		local gui = Instance.new("BillboardGui")
		gui.Name = "JunkshotPrompt"
		gui.Adornee = prompt.Parent
		gui.Size = CARD_SIZE
		local cardOffset = prompt:GetAttribute("CardOffset")
		gui.StudsOffset = if type(cardOffset) == "number" then Vector3.new(0, cardOffset, 0)
			elseif isJunk(prompt) then JUNK_OFFSET
			else MACHINE_OFFSET
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Active = true -- needed for the touch button inside

		local button = Instance.new("TextButton")
		button.Name = "Card"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundColor3 = Theme.Colors.Panel
		button.AutoButtonColor = false
		button.Text = ""
		Theme.Corner(button, UDim.new(0, 16))
		local stroke = Theme.Stroke(button, Theme.Colors.Ink, 3)
		button.Parent = gui

		local badge = Instance.new("Frame")
		badge.Name = "Key"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 8, 0.5, 0)
		badge.Size = UDim2.new(0, 48, 0, 48)
		badge.BackgroundColor3 = Theme.Colors.Accent
		Theme.Corner(badge, UDim.new(0, 12))
		Theme.Stroke(badge, Theme.Colors.Ink, 2)
		badge.Parent = button

		local keyLabel = Theme.Label({
			Name = "Text",
			Text = "",
			Size = UDim2.fromScale(0.86, 0.7),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = Theme.Colors.White,
			MinTextSize = 12,
			MaxTextSize = 26,
			Parent = badge,
		})
		Theme.TextStroke(keyLabel, Theme.Colors.Ink, 1.5)

		local actionLabel = Theme.Label({
			Name = "Action",
			Text = "",
			Size = UDim2.new(1, -70, 0.5, -4),
			Position = UDim2.new(0, 64, 0, 6),
			Color = Theme.Colors.Ink,
			MinTextSize = 14,
			MaxTextSize = 24,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		local objectLabel = Theme.Label({
			Name = "Object",
			Text = "",
			Size = UDim2.new(1, -70, 0.42, -4),
			Position = UDim2.new(0, 64, 0.5, 2),
			Color = Theme.Colors.InkSoft,
			Font = Theme.FontBody,
			MinTextSize = 12,
			MaxTextSize = 18,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})

		local card: Card = {
			Gui = gui,
			Stroke = stroke,
			Badge = badge,
			KeyLabel = keyLabel,
			ActionLabel = actionLabel,
			ObjectLabel = objectLabel,
			InputType = inputType,
		}

		-- Touch: the whole card is the button.
		button.Activated:Connect(function()
			if card.InputType == Enum.ProximityPromptInputType.Touch and cards[prompt] == card then
				prompt:InputHoldBegin()
				task.defer(function()
					prompt:InputHoldEnd()
				end)
			end
		end)

		gui.Parent = playerGui -- in PlayerGui (not Workspace) so it can receive taps
		return card
	end

	local function removeCard(prompt: ProximityPrompt)
		local card = cards[prompt]
		if card ~= nil then
			cards[prompt] = nil
			if card.Watch ~= nil then
				card.Watch:Disconnect()
			end
			card.Gui:Destroy()
		end
	end

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		if isForSomeoneElse(prompt) then
			-- Someone else's reward or machine: hide it locally (the server refuses it anyway).
			-- When a pooled object is reused without a reservation, show it again.
			prompt.Enabled = false
			prompt:GetAttributeChangedSignal("ReservedFor"):Once(function()
				prompt.Enabled = true
			end)
			return
		end
		removeCard(prompt)
		local card = createCard(prompt, inputType)
		cards[prompt] = card
		-- Picked-up junk leaves the world (it is pooled): its card must go even without PromptHidden.
		card.Watch = prompt.AncestryChanged:Connect(function()
			if not prompt:IsDescendantOf(workspace) then
				removeCard(prompt)
			end
		end)
		render(prompt, card)
	end)

	ProximityPromptService.PromptHidden:Connect(removeCard)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == Players.LocalPlayer and prompt.Style == Enum.ProximityPromptStyle.Custom then
			onTriggeredLocally(prompt)
		end
	end)

	return {
		SetFull = function(value: boolean)
			if full ~= value then
				full = value
				for prompt, card in cards do
					render(prompt, card)
				end
			end
		end,
	}
end

return PickupPrompt
