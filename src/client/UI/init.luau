--!strict
--[[
	UI: the Stage 1 gameplay HUD. Builds one ScreenGui and wires its parts to the controllers:

	  Hotbar        carried junk, selection, capacity "n/6"          (UI/Hotbar)
	  ThrowButton   touch-only hold-to-aim / release-to-throw button (UI/ThrowButton)
	  PickupPrompt  themed ProximityPrompt card                      (UI/PickupPrompt)
	  Feedback      toasts for pickup / full (via NotifyController); throws are reported by
	                ThrowController when the server confirms them.

	Everything is event driven (CarryController.Changed, InputController signals); there are
	no per-frame UI updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Types = require(ReplicatedStorage.Shared.Types)

local CarryController = require(script.Parent.CarryController)
local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)
local Hotbar = require(script.Hotbar)
local PickupPrompt = require(script.PickupPrompt)
local ThrowButton = require(script.ThrowButton)

local UI = {}

local function fullMessage(): string
	return string.format("Carry full (%d/%d)", GameConfig.Carry.MaxJunk, GameConfig.Carry.MaxJunk)
end

local function mount()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotHud"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5

	local hotbar = Hotbar.Mount(screenGui)
	local throwButton = ThrowButton.Mount(screenGui, InputController.BeginThrow, InputController.EndThrow)
	local pickupPrompt = PickupPrompt.Mount(function(prompt: ProximityPrompt)
		-- Instant local feedback; the server sends the same text and the toast is deduplicated.
		-- Only junk prompts have no PromptKind; the machine prompt opens its own panel.
		if prompt:GetAttribute("PromptKind") == nil and CarryController.IsFull() then
			NotifyController.Show(fullMessage(), "Warning")
			hotbar.PulseFull()
		end
	end)

	local function refresh()
		local list = CarryController.GetLocalCarried()
		hotbar.Update(list, CarryController.GetSelectedIndex())
		throwButton.SetEnabled(#list > 0)
		pickupPrompt.SetFull(CarryController.IsFull())
	end

	local function applyInputKind(kind: string)
		hotbar.SetInputKind(kind)
		-- No throwing from behind a menu, so the touch button hides while one is open.
		throwButton.SetVisible(kind == "Touch" and not InputController.IsThrowBlocked())
	end

	hotbar.SlotClicked.Event:Connect(function(index: number)
		CarryController.Select(index)
	end)
	InputController.SlotRequested:Connect(CarryController.Select)
	InputController.CycleRequested:Connect(CarryController.Cycle)
	InputController.InputTypeChanged:Connect(applyInputKind)
	InputController.MenuChanged:Connect(function()
		applyInputKind(InputController.GetInputKind())
	end)

	CarryController.Changed:Connect(refresh)
	CarryController.ItemsAdded:Connect(function(entries: { Types.CarriedJunk })
		local last = entries[#entries]
		local definition = ItemConfig.Get(last.Id)
		local name = if definition ~= nil then definition.DisplayName else last.Id
		local count = #CarryController.GetLocalCarried()
		NotifyController.Show(`Picked up {name} ({count}/{GameConfig.Carry.MaxJunk})`, "Success")
	end)

	applyInputKind(InputController.GetInputKind())
	refresh()
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function UI.Start()
	-- Must not yield (see Main.client): PlayerGui may still be on its way.
	task.spawn(mount)
end

return UI
