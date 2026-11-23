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
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)

local CarryController = require(script.Parent.CarryController)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.UI.Theme)
local Placement = require(script.Placement)
local Vehicles = require(script.Vehicles)
local Detector = require(script.Detector)

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
	if capabilities.CanBePlaced then
		action = `Place {name}`
	elseif capabilities.Behavior.Kind == "Detector" then
		action = if Detector.IsOn() then "Detector: switch off" else "Detector: switch on"
	else
		action = `Use {name}`
	end
	local key = keyName()
	chipLabel.Text = if key ~= "" then `[{key}]  {action}` else action
	chip.BackgroundColor3 = if Detector.IsOn() then Theme.Colors.Success else Theme.Colors.Accent
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
	end
	refresh()
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
	task.spawn(mount)
end

return ItemController
