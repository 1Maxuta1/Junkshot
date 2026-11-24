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
	local window = Window.Mount(gui, "DailyWindow", "QUESTS", { "QUESTS" })
	local open = Window.HudButton("JunkshotDailyButton", "QUESTS", Theme.Colors.Accent, UDim2.new(0, 104, 0, 38), UDim2.new(1, -8, 0, 114))
	local openLabel = open:FindFirstChild("Label") :: TextLabel
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

	local function button(right: Frame, ready: boolean, done: boolean, text: string, action: () -> ())
		local label = if done then "DONE" else text
		local made = Window.SmallButton(right, label, if ready and not done then Theme.Colors.Success else Theme.Colors.InkSoft, UDim2.new(0, 120, 0, 40))
		made.Activated:Connect(function()
			if ready and not done then
				action()
			end
		end)
	end

	local function render()
		local state = read()
		local count = if state ~= nil then readyCount(state) else 0
		openLabel.Text = if count > 0 then `QUESTS ({count})` else "QUESTS"
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
		local reward = DailyConfig.StreakRewards[state.Streak] or 0
		local row = Window.Row(list, 2, `Day {state.Streak} of {#DailyConfig.StreakRewards}: +{reward} {symbol}`, "Come back tomorrow for a bigger one", nil)
		button(row.Right, state.RewardReady == true, state.RewardReady ~= true, "CLAIM", function()
			claim("Reward")
		end)
		Window.Header(list, 3, "TODAY")
		for index, quest in DailyConfig.QuestsFor(state.Day) do
			local progress = state.Progress[index] or 0
			local questRow = Window.Row(list, 3 + index, quest.Text, `{progress} / {quest.Goal}   +{quest.Reward} {symbol}`, nil)
			local ready = progress >= quest.Goal
			button(questRow.Right, ready, state.Claimed[index] == true, if ready then "CLAIM" else `{math.floor(progress / quest.Goal * 100)}%`, function()
				claim("Quest", index)
			end)
		end
		Window.Header(list, 10, "THIS WEEK")
		local weekly = DailyConfig.Weekly
		local done = math.min(state.WeekDone, weekly.Goal)
		local weekRow = Window.Row(list, 11, weekly.Text, `{done} / {weekly.Goal}   +{weekly.Reward} {symbol}`, nil)
		local weekReady = state.WeekDone >= weekly.Goal
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
	localPlayer:GetAttributeChangedSignal("Daily"):Connect(render)
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
