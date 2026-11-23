--!strict
--[[
	ItemController: the unified "use the item in your hands" flow for functional items.

	  1. The player selects an item in the hotbar (1-6, LB/RB, tap).
	  2. If it can be placed or used (Util/ItemCapabilities), an action chip appears above the
	     hotbar: "[G] Place Bicycle" / "[G] Detector: switch on". It is a button on touch.
	  3. G / D-pad up / tapping the chip:
	       Place -> Placement preview (green/red) -> confirm -> server validates and places it
	       Use   -> the item acts while carried (Detector)
	  4. Placed objects are used through their own prompts (drive, tow, play ...).

	Sub-modules: Placement (preview), Vehicles (driving input + animation), Detector (scans).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)

local CarryController = require(script.Parent.CarryController)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.UI.Theme)
local Placement = require(script.Placement)
local Vehicles = require(script.Vehicles)
local Detector = require(script.Detector)
local Abilities = require(script.Abilities)
local NotifyController = require(script.Parent.NotifyController)

local ItemController = {}

local chip: TextButton? = nil
local chipLabel: TextLabel? = nil

local function keyName(): string
	local kind = InputController.GetInputKind()
	if kind == "Gamepad" then
		return "D-pad ↑"
	elseif kind == "Touch" then
		return ""
	end
	return GameConfig.Input.UseKey.Name
end

local function selectedAction(): (any?, any?)
	local selected = CarryController.GetSelected()
	if selected == nil then
		return nil, nil
	end
	local capabilities = ItemCapabilities.Get(selected.Id)
	if capabilities == nil or (not capabilities.CanBePlaced and not capabilities.CanBeUsed) then
		return selected, nil
	end
	return selected, capabilities
end

local lastAbilityRequest = 0

-- Seconds until an ability effect is ready (server-published Unix time "Cooldown_<Effect>").
local function abilityTimeLeft(effect: string): number
	local readyAt = Players.LocalPlayer:GetAttribute(`Cooldown_{effect}`)
	if type(readyAt) ~= "number" then
		return 0
	end
	return math.max(0, math.ceil(readyAt - Workspace:GetServerTimeNow()))
end

local function refresh()
	local selected, capabilities = selectedAction()

	-- The detector only works while it is the selected item.
	if Detector.IsOn() and (capabilities == nil or capabilities.Behavior.Kind ~= "Detector") then
		Detector.SetOn(false)
	end
	-- Placing ends when the item is no longer the selected one.
	if Placement.IsActive() and (selected == nil or Placement.GetUid() ~= selected.Uid) then
		Placement.Cancel()
	end

	if chip == nil or chipLabel == nil then
		return
	end
	local show = capabilities ~= nil and not Placement.IsActive() and not Vehicles.IsSeated()
		and not InputController.IsMenuOpen()
	chip.Visible = show
	if not show or selected == nil or capabilities == nil then
		return
	end
	local name = ItemConfig.GetDisplayName(selected.Id)
	local action: string
	local key = keyName()
	local color = if Detector.IsOn() then Theme.Colors.Success else Theme.Colors.Accent
	if capabilities.CanBePlaced then
		action = `Place {name}`
	elseif capabilities.Behavior.Kind == "Detector" then
		action = if Detector.IsOn() then "Detector: switch off" else "Detector: switch on"
	elseif capabilities.Behavior.Kind == "Ability" then
		local ability = capabilities.Behavior.Ability
		local left = abilityTimeLeft(ability.Effect)
		if left > 0 then
			action = string.format("%s  ·  ready in %d:%02d", ability.Name, left // 60, left % 60)
			color = Theme.Colors.InkSoft
		else
			action = ability.Name
			color = Theme.Colors.Ice
			if InputController.GetInputKind() == "KeyboardMouse" then
				key = "Click"
			end
		end
	else
		action = `Use {name}`
	end
	chipLabel.Text = if key ~= "" then `[{key}]  {action}` else action
	chip.BackgroundColor3 = color
end

local function act()
	if Placement.IsActive() then
		Placement.Confirm()
		return
	end
	if Vehicles.IsSeated() or InputController.IsMenuOpen() then
		return
	end
	local selected, capabilities = selectedAction()
	if selected == nil or capabilities == nil then
		return
	end
	if capabilities.CanBePlaced then
		Placement.Start(selected.Uid, selected.Id, capabilities.Behavior)
	elseif capabilities.Behavior.Kind == "Detector" then
		Detector.SetOn(not Detector.IsOn(), selected.Uid, capabilities.Behavior)
	elseif capabilities.Behavior.Kind == "Ability" then
		local ability = capabilities.Behavior.Ability
		local left = abilityTimeLeft(ability.Effect)
		if left > 0 then
			NotifyController.Show(string.format("%s is recharging: %d:%02d", ability.Name, left // 60, left % 60), "Info")
		elseif os.clock() - lastAbilityRequest > 1 then
			lastAbilityRequest = os.clock()
			Remotes.GetEvent("ItemUse"):FireServer(selected.Uid) -- the server checks and broadcasts
		end
	end
	refresh()
end

-- Left click with an ability item selected uses the ability instead of throwing it.
local function onPrimaryClick(): boolean
	local _, capabilities = selectedAction()
	if capabilities == nil or capabilities.Behavior.Kind ~= "Ability" or Placement.IsActive() then
		return false
	end
	act()
	return true
end

local function mount()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotItems"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 6

	local button = Instance.new("TextButton")
	button.Name = "ActionChip"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 0.8, 0)
	button.Size = UDim2.new(0, 280, 0, 44)
	button.BackgroundColor3 = Theme.Colors.Accent
	button.AutoButtonColor = true
	button.Text = ""
	button.Visible = false
	Theme.Corner(button, UDim.new(0, 14))
	Theme.Stroke(button, Theme.Colors.Ink, 2.5)
	local label = Theme.Label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -20, 0.7, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 13,
		MaxTextSize = 22,
		Parent = button,
	})
	Theme.TextStroke(label, Theme.Colors.Ink, 1.5)
	button.Parent = screenGui
	button.Activated:Connect(act)
	chip, chipLabel = button, label

	Placement.Mount(screenGui, refresh)
	Vehicles.Mount(screenGui, refresh)
	Detector.Mount(screenGui, refresh)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	refresh()
end

function ItemController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == GameConfig.Input.UseKey or input.KeyCode == GameConfig.Input.UseGamepadKey then
			act()
		end
	end)
	CarryController.Changed:Connect(refresh)
	InputController.InputTypeChanged:Connect(refresh)
	InputController.MenuChanged:Connect(refresh)
	InputController.SetPrimaryClickHandler(onPrimaryClick)
	Abilities.Start()
	-- Ability cooldown countdown on the chip (only while an ability item is selected).
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local _, capabilities = selectedAction()
		if capabilities ~= nil and capabilities.Behavior.Kind == "Ability" then
			refresh()
		end
	end)
	task.spawn(mount)
end

return ItemController
