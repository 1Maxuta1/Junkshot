--!strict
--[[
	BuffController: the active bonuses on the left edge, like in an MMO: an icon with its time
	left and a bar that empties. Display only; the server owns every bonus.

	  Craft boost   attribute BoostUntil on your machine (daily reward, Robux boost)
	  Plasma toast  Player attribute ToastedUntil
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)

local Theme = require(script.Parent.UI.Theme)

local BuffController = {}

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB

type Buff = { Id: string, Name: string, Symbol: string, Color: Color3, Until: () -> number }

local function ownMachine(): Instance?
	for _, machine in CollectionService:GetTagged(MachineConfig.Tag) do
		if machine:GetAttribute("OwnerUserId") == localPlayer.UserId and machine:IsDescendantOf(Workspace) then
			return machine
		end
	end
	return nil
end

local BUFFS: { Buff } = {
	{ Id = "Craft", Name = "CRAFT x2", Symbol = "⚡", Color = rgb(70, 170, 255), Until = function(): number
		local machine = ownMachine()
		local value = if machine ~= nil then machine:GetAttribute("BoostUntil") else nil
		return if type(value) == "number" then value else 0
	end },
	{ Id = "Toast", Name = "PLASMA", Symbol = "★", Color = rgb(255, 110, 220), Until = function(): number
		local value = localPlayer:GetAttribute("ToastedUntil")
		return if type(value) == "number" then value else 0
	end },
}

local function clock(seconds: number): string
	local left = math.max(0, math.ceil(seconds))
	if left >= 3600 then
		return string.format("%d:%02d h", left // 3600, left % 3600 // 60)
	end
	return string.format("%d:%02d", left // 60, left % 60)
end

local function mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotBuffs"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 3
	local column = Instance.new("Frame")
	column.Name = "Buffs"
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 10, 0.46, 0)
	column.Size = UDim2.fromOffset(120, 160)
	column.BackgroundTransparency = 1
	column.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = column

	local views: { [string]: { Root: Frame, Time: TextLabel, Fill: Frame, Total: number } } = {}
	local function build(buff: Buff): any
		local root = Instance.new("Frame")
		root.Name = buff.Id
		root.Size = UDim2.fromOffset(118, 46)
		root.BackgroundColor3 = rgb(38, 48, 74)
		Theme.Corner(root, UDim.new(0, 12))
		Theme.Stroke(root, buff.Color, 2.5)
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.Position = UDim2.fromOffset(4, 4)
		badge.Size = UDim2.fromOffset(38, 38)
		badge.BackgroundColor3 = buff.Color
		Theme.Corner(badge, UDim.new(1, 0))
		Theme.Stroke(badge, rgb(255, 255, 255), 2)
		badge.Parent = root
		local symbol = Theme.Label({ Name = "Symbol", Text = buff.Symbol, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Color = Theme.Colors.White, MinTextSize = 12, MaxTextSize = 26, Parent = badge })
		Theme.TextStroke(symbol, rgb(22, 28, 48), 2)
		Theme.Label({ Name = "Name", Text = buff.Name, Size = UDim2.new(1, -52, 0, 16), Position = UDim2.fromOffset(48, 3),
			Color = rgb(255, 236, 180), MinTextSize = 10, MaxTextSize = 14, XAlignment = Enum.TextXAlignment.Left, Parent = root })
		local timeLabel = Theme.Label({ Name = "Time", Text = "", Size = UDim2.new(1, -52, 0, 15), Position = UDim2.fromOffset(48, 18),
			Color = Theme.Colors.White, MinTextSize = 10, MaxTextSize = 14, XAlignment = Enum.TextXAlignment.Left, Parent = root })
		local back = Instance.new("Frame")
		back.Name = "Bar"
		back.Position = UDim2.new(0, 48, 1, -11)
		back.Size = UDim2.new(1, -56, 0, 6)
		back.BackgroundColor3 = rgb(22, 28, 48)
		Theme.Corner(back, UDim.new(1, 0))
		back.Parent = root
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = buff.Color
		Theme.Corner(fill, UDim.new(1, 0))
		fill.Parent = back
		root.Parent = column
		return { Root = root, Time = timeLabel, Fill = fill, Total = 1 }
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	while true do
		local now = Workspace:GetServerTimeNow()
		for _, buff in BUFFS do
			local left = buff.Until() - now
			local view = views[buff.Id]
			if left > 0 then
				if view == nil then
					view = build(buff)
					view.Total = left
					views[buff.Id] = view
				end
				view.Total = math.max(view.Total, left) -- extended while running
				view.Time.Text = clock(left)
				view.Fill.Size = UDim2.fromScale(math.clamp(left / view.Total, 0, 1), 1)
			elseif view ~= nil then
				view.Root:Destroy()
				views[buff.Id] = nil
			end
		end
		task.wait(0.5)
	end
end

function BuffController.Start()
	task.spawn(mount)
end

return BuffController
