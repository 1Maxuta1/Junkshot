--!strict
--[[
	InputController: turns raw input into game actions, so the rest of the client does not care
	whether the player uses a keyboard, a gamepad or a touch screen.

	Bindings come from GameConfig.Input:
	  Throw   ThrowKeys (F, ButtonR2) and, if ThrowWithMouseButton, the left mouse button.
	          Hold = aim (preview arc), release = throw.
	  Slots   SlotKeys (1-6) select a slot; NextSlotKeys / PrevSlotKeys (R1 / L1) cycle.
	  Touch   the HUD throw button calls BeginThrow() / EndThrow(); hotbar slots are tapped.

	Input that the game UI or chat already handled (gameProcessedEvent) is ignored, so typing
	in chat or clicking a button never throws.

	Menus: any GuiObject tagged MENU_TAG ("JunkshotMenu") blocks throwing while it is shown
	(machine panel, reward card, future shops...). Opening a menu cancels a throw being aimed.

	API
	  ThrowBegan, ThrowReleased, SlotRequested(index), CycleRequested(direction)   Signals
	  InputTypeChanged(kind)   Signal; kind is "KeyboardMouse" | "Gamepad" | "Touch"
	  GetInputKind(), IsThrowHeld(), BeginThrow(), EndThrow(), CancelThrow()
	  IsMenuOpen(), MenuChanged(open)   Signal
	  MENU_TAG   tag a menu's root GuiObject with it (CollectionService) to block throwing
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type InputKind = "KeyboardMouse" | "Gamepad" | "Touch"

local InputController = {}

InputController.ThrowBegan = Signal.new()
InputController.ThrowReleased = Signal.new()
InputController.ThrowCancelled = Signal.new()
InputController.SlotRequested = Signal.new() -- (index: number)
InputController.CycleRequested = Signal.new() -- (direction: number)
InputController.InputTypeChanged = Signal.new() -- (kind: InputKind)
InputController.MenuChanged = Signal.new() -- (open: boolean)
InputController.MENU_TAG = "JunkshotMenu"

local menus: { [GuiObject]: RBXScriptConnection } = {}
local menuOpen = false
local blockers: { [string]: boolean } = {}
local primaryClickHandler: (() -> boolean)? = nil

-- ItemController: return true from the handler to take a left click for an item ability.
function InputController.SetPrimaryClickHandler(handler: (() -> boolean)?)
	primaryClickHandler = handler
end

local throwHeld = false
local throwSource: Enum.KeyCode | Enum.UserInputType | string | nil = nil
local inputKind: InputKind = "KeyboardMouse"

local throwKeys: { [Enum.KeyCode]: boolean } = {}
local slotByKey: { [Enum.KeyCode]: number } = {}
local cycleByKey: { [Enum.KeyCode]: number } = {}

for _, key in GameConfig.Input.ThrowKeys do
	throwKeys[key] = true
end
for index, key in GameConfig.Input.SlotKeys do
	slotByKey[key] = index
end
for _, key in GameConfig.Input.NextSlotKeys do
	cycleByKey[key] = 1
end
for _, key in GameConfig.Input.PrevSlotKeys do
	cycleByKey[key] = -1
end

local function kindFromInputType(inputType: Enum.UserInputType): InputKind?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(inputType.Name, "Gamepad") ~= nil then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "KeyboardMouse"
	end
	return nil
end

local function setKind(inputType: Enum.UserInputType)
	local kind = kindFromInputType(inputType)
	if kind ~= nil and kind ~= inputKind then
		inputKind = kind
		InputController.InputTypeChanged:Fire(kind)
	end
end

local function isShown(gui: GuiObject): boolean
	if not gui.Visible or not gui:IsDescendantOf(game) then
		return false
	end
	local screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
	return screen ~= nil and screen.Enabled
end

-- `source` remembers what started the throw, so only releasing that same input throws.
local function begin(source: Enum.KeyCode | Enum.UserInputType | string)
	if throwHeld or menuOpen or next(blockers) ~= nil then
		return
	end
	throwHeld = true
	throwSource = source
	InputController.ThrowBegan:Fire()
end

local function release(source: Enum.KeyCode | Enum.UserInputType | string)
	if not throwHeld or throwSource ~= source then
		return
	end
	throwHeld = false
	throwSource = nil
	InputController.ThrowReleased:Fire()
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local keyCode = input.KeyCode

	if throwKeys[keyCode] then
		begin(keyCode)
	elseif GameConfig.Input.ThrowWithMouseButton and input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- A selected item with a click ability (Comet Shard ...) uses the click instead of throwing.
		if primaryClickHandler ~= nil and primaryClickHandler() then
			return
		end
		begin(Enum.UserInputType.MouseButton1)
	elseif slotByKey[keyCode] ~= nil then
		InputController.SlotRequested:Fire(slotByKey[keyCode])
	elseif cycleByKey[keyCode] ~= nil then
		InputController.CycleRequested:Fire(cycleByKey[keyCode])
	end
end

-- Releases are handled even when gameProcessed, so a held throw can never get stuck.
local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if throwKeys[input.KeyCode] then
		release(input.KeyCode)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		release(Enum.UserInputType.MouseButton1)
	end
end

function InputController.GetInputKind(): InputKind
	return inputKind
end

function InputController.IsThrowHeld(): boolean
	return throwHeld
end

-- Touch throw button.
function InputController.BeginThrow()
	begin("TouchButton")
end

function InputController.EndThrow()
	release("TouchButton")
end

-- Drops a held throw without throwing (e.g. the character died while aiming).
function InputController.CancelThrow()
	if throwHeld then
		throwHeld = false
		throwSource = nil
		InputController.ThrowCancelled:Fire()
	end
end

function InputController.IsMenuOpen(): boolean
	return menuOpen
end

-- Throwing is unavailable while a menu is open or any system blocks it (placing an item,
-- sitting in a vehicle ...). MenuChanged also fires when this changes.
function InputController.IsThrowBlocked(): boolean
	return menuOpen or next(blockers) ~= nil
end

function InputController.SetThrowBlocked(reason: string, blocked: boolean)
	local was = InputController.IsThrowBlocked()
	blockers[reason] = if blocked then true else nil
	if blocked then
		InputController.CancelThrow()
	end
	if InputController.IsThrowBlocked() ~= was then
		InputController.MenuChanged:Fire(menuOpen)
	end
end

local function refreshMenus()
	local open = false
	for gui in menus do
		if isShown(gui) then
			open = true
			break
		end
	end
	if open == menuOpen then
		return
	end
	menuOpen = open
	if open then
		InputController.CancelThrow() -- a menu opened while aiming: never throw from behind it
	end
	InputController.MenuChanged:Fire(open)
end

local function trackMenu(instance: Instance)
	if not instance:IsA("GuiObject") or menus[instance] ~= nil then
		return
	end
	menus[instance] = instance:GetPropertyChangedSignal("Visible"):Connect(refreshMenus)
	refreshMenus()
end

local function untrackMenu(instance: Instance)
	local connection = menus[instance :: GuiObject]
	if connection ~= nil then
		connection:Disconnect()
		menus[instance :: GuiObject] = nil
		refreshMenus()
	end
end

function InputController.Start()
	for _, instance in CollectionService:GetTagged(InputController.MENU_TAG) do
		trackMenu(instance)
	end
	CollectionService:GetInstanceAddedSignal(InputController.MENU_TAG):Connect(trackMenu)
	CollectionService:GetInstanceRemovedSignal(InputController.MENU_TAG):Connect(untrackMenu)
	setKind(UserInputService:GetLastInputType())
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		inputKind = "Touch"
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.LastInputTypeChanged:Connect(setKind)
	UserInputService.WindowFocusReleased:Connect(InputController.CancelThrow)
end

return InputController
