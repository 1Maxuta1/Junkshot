--!strict
--[[
	DailyService: daily reward, daily quests and the weekly goal (Config/DailyConfig).

	Saved in profile.Data.Daily = { Day, Progress = { n, n, n }, Claimed = { b, b, b }, Streak,
	RewardDay, Week, WeekDone, WeekClaimed }. The server counts what it sees happen and the
	server clock decides the day. A claim flips its flag before paying, so it pays once; unclaimed
	quest rewards of yesterday are lost, a missed day starts the streak again.

	Player attribute "Daily" (JSON) for the client. The client may only ask to claim.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MachineService = require(script.Parent.MachineService)
local RaceService = require(script.Parent.RaceService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local ThrowService = require(script.Parent.ThrowService)

local DailyService = {}

local started = false
local now: () -> number = os.time -- replaced by DevTests only
local seen: { [Player]: { [string]: boolean } } = {} -- uids that already counted for "different items"

local function integer(value: any): number
	return if Validate.IsInteger(value, 0) then value else 0
end

-- The player's state, moved on to today when the day or week changed.
local function stateOf(player: Player): any?
	local data = DataService.GetData(player) :: any
	if data == nil then
		return nil
	end
	if type(data.Daily) ~= "table" then
		data.Daily = {}
	end
	local state = data.Daily
	local today = DailyConfig.Day(now())
	if state.Day ~= today or type(state.Progress) ~= "table" or type(state.Claimed) ~= "table" then
		state.Day = today
		state.Progress = table.create(DailyConfig.Groups, 0)
		state.Claimed = table.create(DailyConfig.Groups, false)
		seen[player] = nil
	end
	local week = DailyConfig.Week(today)
	if state.Week ~= week then
		state.Week, state.WeekDone, state.WeekClaimed = week, 0, false
	end
	state.Streak = integer(state.Streak)
	state.RewardDay = integer(state.RewardDay)
	state.WeekDone = integer(state.WeekDone)
	return state
end

-- The streak day (1-7) a reward claimed today would be.
local function nextStreak(state: any): number
	local continued = state.RewardDay == state.Day - 1
	return if continued then state.Streak % #DailyConfig.StreakRewards + 1 else 1
end

local function publish(player: Player)
	local state = stateOf(player)
	if state == nil then
		return
	end
	local claimedToday = state.RewardDay == state.Day
	player:SetAttribute("Daily", HttpService:JSONEncode({
		Day = state.Day,
		Progress = state.Progress,
		Claimed = state.Claimed,
		RewardReady = not claimedToday,
		Streak = if claimedToday then state.Streak else nextStreak(state),
		WeekDone = state.WeekDone,
		WeekClaimed = state.WeekClaimed == true,
	}))
end

-- Something happened that may count for today's quests (amount: how much).
function DailyService.Count(player: Player, event: string, amount: number)
	local state = stateOf(player)
	if state == nil then
		return
	end
	local changed = false
	for index, quest in DailyConfig.QuestsFor(state.Day) do
		if quest.Event == event and not state.Claimed[index] and state.Progress[index] < quest.Goal then
			state.Progress[index] = math.min(quest.Goal, state.Progress[index] + amount)
			changed = true
			if state.Progress[index] >= quest.Goal then
				EconomyService.Message(player, `Quest complete: {quest.Text}`, "Success")
			end
		end
	end
	if changed then
		publish(player)
	end
end

function DailyService.ClaimReward(player: Player): boolean
	local state = stateOf(player)
	if state == nil or state.RewardDay == state.Day then
		return false
	end
	state.Streak = nextStreak(state)
	state.RewardDay = state.Day
	EconomyService.Earn(player, DailyConfig.StreakRewards[state.Streak], "Daily")
	publish(player)
	return true
end

function DailyService.ClaimQuest(player: Player, index: any): boolean
	local state = stateOf(player)
	if state == nil or not Validate.IsInteger(index, 1, DailyConfig.Groups) or state.Claimed[index] then
		return false
	end
	local quest = DailyConfig.QuestsFor(state.Day)[index]
	if state.Progress[index] < quest.Goal then
		return false
	end
	state.Claimed[index] = true
	state.WeekDone += 1
	EconomyService.Earn(player, quest.Reward, "Quest")
	publish(player)
	return true
end

function DailyService.ClaimWeekly(player: Player): boolean
	local state = stateOf(player)
	if state == nil or state.WeekClaimed == true or state.WeekDone < DailyConfig.Weekly.Goal then
		return false
	end
	state.WeekClaimed = true
	EconomyService.Earn(player, DailyConfig.Weekly.Reward, "WeeklyQuest")
	publish(player)
	return true
end

function DailyService.SetClockForTest(clock: (() -> number)?)
	now = clock or os.time
end

function DailyService.Start()
	assert(not started, "[DailyService] Start() called twice")
	started = true
	DataService.PlayerLoaded:Connect(publish)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		seen[player] = nil
	end)

	CarryService.ItemAdded:Connect(function(player: Player, _itemId: string, uid: string)
		local list = seen[player]
		if list == nil then
			list = {}
			seen[player] = list
		end
		if not (list :: any)[uid] then
			(list :: any)[uid] = true
			DailyService.Count(player, "Collect", 1)
		end
	end)
	ThrowService.Landed:Connect(function(player: Player)
		DailyService.Count(player, "Throw", 1)
	end)
	MachineService.JobFinished:Connect(function(player: Player, _result: any, kind: string)
		if kind == "Recycle" or kind == "Craft" then
			DailyService.Count(player, kind, 1)
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, amount: number, reason: string)
		if reason == "Sell" then
			DailyService.Count(player, "Sell", amount)
		end
	end)
	RaceService.Finished:Connect(function(player: Player)
		DailyService.Count(player, "Race", 1)
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("DailyClaim"), {
		Name = "DailyClaim",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.DailyClaim,
		Validate = function(what: any): boolean
			return Validate.IsString(what, 1, 10)
		end,
	}, function(player: Player, what: string, index: any)
		if what == "Reward" then
			DailyService.ClaimReward(player)
		elseif what == "Quest" then
			DailyService.ClaimQuest(player, index)
		elseif what == "Weekly" then
			DailyService.ClaimWeekly(player)
		end
	end)

	-- Midnight while playing.
	task.spawn(function()
		local day = DailyConfig.Day(now())
		while true do
			task.wait(10)
			local current = DailyConfig.Day(now())
			if current ~= day then
				day = current
				for _, player in Players:GetPlayers() do
					publish(player)
				end
			end
		end
	end)
end

return DailyService
