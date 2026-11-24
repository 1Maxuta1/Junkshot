--!strict
--[[
	NotifyController: short toast messages at the top of the screen.

	Sources
	  - the server's Notify remote (fixed text such as "Carry full (6/6)")
	  - other client controllers: NotifyController.Show(text, kind)

	kind: "Info" | "Success" | "Warning" (sets the accent color).
	At most MAX_VISIBLE toasts are shown; the same text within DEDUPE_WINDOW seconds is shown
	once, so a local message and the matching server message never stack.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.UI.Theme)

export type Kind = "Info" | "Success" | "Warning"

local DURATION = 2.2
local MAX_LENGTH = 120
local MAX_VISIBLE = 3
local DEDUPE_WINDOW = 1

local ACCENTS: { [Kind]: Color3 } = {
	Info = Theme.Colors.Ice,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Danger,
}

local NotifyController = {}

local stack: Frame? = nil
local visible: { Frame } = {}
local lastShown: { [string]: number } = {}
local order = 0

local function build(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotToasts"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Stack"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.fromScale(0.36, 0.3)
	frame.BackgroundTransparency = 1

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(260, 0)
	sizeLimit.MaxSize = Vector2.new(460, math.huge)
	sizeLimit.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	frame.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return frame
end

local function removeToast(toast: Frame)
	local index = table.find(visible, toast)
	if index ~= nil then
		table.remove(visible, index)
	end
	toast:Destroy()
end

function NotifyController.Show(message: string, kind: Kind?)
	local parent = stack
	if parent == nil or #message == 0 then
		return
	end
	local now = os.clock()
	local last = lastShown[message]
	if last ~= nil and now - last < DEDUPE_WINDOW then
		return
	end
	lastShown[message] = now

	while #visible >= MAX_VISIBLE do
		removeToast(visible[1])
	end

	order += 1
	local resolvedKind: Kind = kind or "Info"
	local accent = ACCENTS[resolvedKind] or Theme.Colors.Ice

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.LayoutOrder = order
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundColor3 = Theme.Colors.Panel
	Theme.Corner(toast, UDim.new(0, 14))
	Theme.Stroke(toast, Theme.Colors.Ink, 2.5)

	local strip = Instance.new("Frame")
	strip.Name = "Accent"
	strip.Size = UDim2.new(0, 12, 1, -12)
	strip.Position = UDim2.new(0, 8, 0, 6)
	strip.BackgroundColor3 = accent
	Theme.Corner(strip, UDim.new(1, 0))
	strip.Parent = toast

	Theme.Label({
		Name = "Text",
		Text = message,
		Size = UDim2.new(1, -36, 1, -10),
		Position = UDim2.new(0, 28, 0, 5),
		Color = Theme.Colors.Ink,
		MinTextSize = 14,
		MaxTextSize = 22,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
	})

	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = toast

	toast.Parent = parent
	table.insert(visible, toast)
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	task.delay(DURATION, function()
		if toast.Parent == nil then
			return
		end
		local fade = TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 0.6 })
		fade.Completed:Once(function()
			removeToast(toast)
		end)
		fade:Play()
	end)
end

function NotifyController.Start()
	-- Must not yield (see Main.client): all waiting happens inside the spawned task.
	-- Messages sent before the toast stack exists are dropped (nothing important is lost).
	task.spawn(function()
		stack = build()
		-- (message, kind?) - kind defaults to "Warning" (most server messages are refusals).
		Remotes.GetEvent("Notify").OnClientEvent:Connect(function(message: any, kind: any)
			if type(message) == "string" and #message > 0 and #message <= MAX_LENGTH then
				NotifyController.Show(message, if kind == "Info" or kind == "Success" then kind else "Warning")
			end
		end)
	end)
end

return NotifyController
