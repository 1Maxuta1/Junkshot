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

	API
	  ThrowBegan, ThrowReleased, SlotRequested(index), CycleRequested(direction)   Signals
	  InputTypeChanged(kind)   Signal; kind is "KeyboardMouse" | "Gamepad" | "Touch"
	  GetInputKind(), IsThrowHeld(), BeginThrow(), EndThrow(), CancelThrow()
]]

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

-- `source` remembers what started the throw, so only releasing that same input throws.
local function begin(source: Enum.KeyCode | Enum.UserInputType | string)
	if throwHeld then
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

function InputController.Start()
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
