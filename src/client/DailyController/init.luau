--!strict
--[[
	DailyController: the QUESTS button and window (server: DailyService). Shows the Player
	attribute "Daily" and asks to claim; nothing is decided here.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local SupplyDrop = require(script.SupplyDrop)

local DailyController = {}

local localPlayer = Players.LocalPlayer

local function read(): any?
	local raw = localPlayer:GetAttribute("Daily")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, state = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(state) == "table" and type(state.Progress) == "table" and type(state.Claimed) == "table" then state else nil
end

local function claim(what: string, index: number?)
	Remotes.GetEvent("DailyClaim"):FireServer(what, index)
end

local function readyCount(state: any): number
	local count = if state.RewardReady then 1 else 0
	for index, quest in DailyConfig.QuestsFor(state.Day) do
		if not state.Claimed[index] and state.Progress[index] >= quest.Goal then
			count += 1
		end
	end
	if not state.WeekClaimed and state.WeekDone >= DailyConfig.Weekly.Goal then
		count += 1
	end
	return count
end

local function mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotDaily"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local dropGui = Instance.new("ScreenGui") -- its layers use global ZIndex
	dropGui.Name = "JunkshotSupplyDrop"
	dropGui.ResetOnSpawn = false
	dropGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	dropGui.DisplayOrder = 12
	dropGui.Parent = localPlayer:WaitForChild("PlayerGui")
	local window = Window.Mount(gui, "DailyWindow", "QUESTS", { "QUESTS" })
	local open = Window.HudButton("JunkshotDailyButton", "QUESTS", Theme.Colors.Accent, UDim2.new(0, 104, 0, 38), UDim2.new(1, -8, 0, 114))
	local openLabel = open:FindFirstChild("Label") :: TextLabel
	-- Green circle at the corner: how many quest rewards wait to be collected.
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -12, 0, 2)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundColor3 = Theme.Colors.Success
	badge.Font = Enum.Font.FredokaOne
	badge.TextColor3 = Theme.Colors.White
	badge.TextSize = 16
	badge.ZIndex = 3
	badge.Visible = false
	Theme.Corner(badge, UDim.new(1, 0))
	Theme.Stroke(badge, Theme.Colors.Ink, 2)
	badge.Parent = open
	local resetLabel = Theme.Label({
		Name = "Reset",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Colors.InkSoft,
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 16,
		Parent = window.Footer,
	})
	local symbol = GameConfig.Klunks.Symbol

	local drop = SupplyDrop.Mount(dropGui, function()
		claim("Reward")
	end)
	local shownDay: number? = nil
	local readyToShow = false
	local wasReady: boolean? = nil

	local function button(right: Frame, ready: boolean, done: boolean, text: string, action: () -> ())
		local label = if done then "✔ DONE" else text
		local made = Window.SmallButton(right, label, if ready and not done then Theme.Colors.Success else Theme.Colors.InkSoft, UDim2.new(0, 120, 0, 40))
		made.Activated:Connect(function()
			if ready and not done then
				action()
			end
		end)
	end

	-- A finished row turns green with a check mark, a collected one fades.
	local function mark(row: any, finished: boolean, collected: boolean)
		if collected then
			row.Title.Text = "✔ " .. row.Title.Text
			row.Title.TextColor3 = Theme.Colors.InkSoft
			row.Frame.BackgroundColor3 = Color3.fromRGB(232, 238, 244)
		elseif finished then
			row.Title.Text = "✔ " .. row.Title.Text
			row.Title.TextColor3 = Color3.fromRGB(24, 130, 70)
			row.Frame.BackgroundColor3 = Color3.fromRGB(206, 246, 218)
		end
	end

	local function render()
		local state = read()
		local count = if state ~= nil then readyCount(state) else 0
		openLabel.Text = "QUESTS"
		local complete = 0
		if state ~= nil then
			for index, quest in DailyConfig.QuestsFor(state.Day) do
				complete += if (state.Progress[index] or 0) >= quest.Goal and state.Claimed[index] ~= true then 1 else 0
			end
			if state.WeekClaimed ~= true and state.WeekDone >= DailyConfig.Weekly.Goal then
				complete += 1
			end
		end
		badge.Text = tostring(complete)
		badge.Visible = complete > 0
		open.BackgroundColor3 = if count > 0 then Theme.Colors.Success else Theme.Colors.Accent
		if not window.IsOpen() then
			return
		end
		local list = window.Content("QUESTS")
		Window.Clear(list)
		if state == nil then
			Window.Header(list, 1, "Loading...")
			return
		end
		Window.Header(list, 1, "DAILY REWARD")
		local reward = DailyConfig.DayRewards[state.Streak]
		local row = Window.Row(list, 2, `Day {state.Streak} of {#DailyConfig.DayRewards}: {(string.gsub(reward.Text, "\n", " "))}`, if state.RewardReady then "Ready!" else "Come back tomorrow", nil)
		local made = Window.SmallButton(row.Right, if state.RewardReady then "OPEN" else "SHOW", if state.RewardReady then Theme.Colors.Success else Theme.Colors.Ice, UDim2.new(0, 120, 0, 40))
		made.Activated:Connect(function()
			window.Close()
			drop.Open(state)
		end)
		Window.Header(list, 3, "TODAY")
		for index, quest in DailyConfig.QuestsFor(state.Day) do
			local progress = state.Progress[index] or 0
			local questRow = Window.Row(list, 3 + index, quest.Text, `{progress} / {quest.Goal}   +{quest.Reward} {symbol}`, nil)
			local ready = progress >= quest.Goal
			mark(questRow, ready, state.Claimed[index] == true)
			button(questRow.Right, ready, state.Claimed[index] == true, if ready then "CLAIM" else `{math.floor(progress / quest.Goal * 100)}%`, function()
				claim("Quest", index)
			end)
		end
		Window.Header(list, 10, "THIS WEEK")
		local weekly = DailyConfig.Weekly
		local done = math.min(state.WeekDone, weekly.Goal)
		local weekRow = Window.Row(list, 11, weekly.Text, `{done} / {weekly.Goal}   +{weekly.Reward} {symbol}`, nil)
		local weekReady = state.WeekDone >= weekly.Goal
		mark(weekRow, weekReady, state.WeekClaimed == true)
		button(weekRow.Right, weekReady, state.WeekClaimed == true, if weekReady then "CLAIM" else `{math.floor(done / weekly.Goal * 100)}%`, function()
			claim("Weekly")
		end)
	end

	open.Activated:Connect(function()
		if window.IsOpen() then
			window.Close()
		else
			window.Open(nil, InputController.GetInputKind() == "Gamepad")
			render()
		end
	end)
	-- The drop opens by itself once on the first visit of a day (after the tutorial).
	local function maybeOpen()
		local state = read()
		if state == nil then
			return
		end
		if wasReady == true and state.RewardReady ~= true and drop.IsOpen() then
			drop.Open(state) -- redraw with the check mark
			drop.Claimed(state.Streak)
		end
		wasReady = state.RewardReady
		if readyToShow and state.RewardReady == true and shownDay ~= state.Day and localPlayer:GetAttribute("OnboardStep") == nil then
			shownDay = state.Day
			drop.Open(state)
		end
	end
	localPlayer:GetAttributeChangedSignal("Daily"):Connect(function()
		render()
		maybeOpen()
	end)
	localPlayer:GetAttributeChangedSignal("OnboardStep"):Connect(maybeOpen)
	task.delay(5, function() -- the world is there before the window covers it
		readyToShow = true
		maybeOpen()
	end)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	render()
	while true do
		task.wait(1)
		if window.IsOpen() then
			local left = DailyConfig.DaySeconds - Workspace:GetServerTimeNow() % DailyConfig.DaySeconds
			resetLabel.Text = string.format("New quests in %d h %02d min", left // 3600, left % 3600 // 60)
		end
	end
end

function DailyController.Start()
	task.spawn(mount)
end

return DailyController
