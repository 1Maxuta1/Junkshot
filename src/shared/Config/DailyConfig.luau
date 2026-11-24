--!strict
--[[
	DailyConfig: the daily reward (7-day streak), three daily quests and one weekly goal
	(server DailyService, client DailyController). Days and weeks are UTC.

	Everybody gets the same three quests on a day (picked from the day number), one per group, so
	friends can do them together. Rewards are Klunks through EconomyService, no new currency.
	  a full day  = streak reward + about 110 for the quests
	  a full week = about 1300 in total (one race win pays 1500)
]]

export type Quest = { Id: string, Group: number, Event: string, Text: string, Goal: number, Reward: number }

local DailyConfig = {
	DaySeconds = 24 * 60 * 60,
	StreakRewards = { 25, 35, 45, 60, 75, 100, 160 }, -- day 1 .. 7, then from the start again
	Quests = {
		{ Id = "collect15", Group = 1, Event = "Collect", Text = "Pick up 15 different items", Goal = 15, Reward = 30 },
		{ Id = "throw8", Group = 1, Event = "Throw", Text = "Throw 8 items", Goal = 8, Reward = 25 },
		{ Id = "collect25", Group = 1, Event = "Collect", Text = "Pick up 25 different items", Goal = 25, Reward = 45 },
		{ Id = "recycle3", Group = 2, Event = "Recycle", Text = "Finish 3 recycling jobs", Goal = 3, Reward = 40 },
		{ Id = "craft1", Group = 2, Event = "Craft", Text = "Craft something", Goal = 1, Reward = 45 },
		{ Id = "recycle5", Group = 2, Event = "Recycle", Text = "Finish 5 recycling jobs", Goal = 5, Reward = 55 },
		{ Id = "sell100", Group = 3, Event = "Sell", Text = "Earn 100 Klunks at the Scrap Dealer", Goal = 100, Reward = 35 },
		{ Id = "race1", Group = 3, Event = "Race", Text = "Finish a race", Goal = 1, Reward = 60 },
		{ Id = "sell250", Group = 3, Event = "Sell", Text = "Earn 250 Klunks at the Scrap Dealer", Goal = 250, Reward = 60 },
	} :: { Quest },
	Groups = 3,
	Weekly = { Text = "Complete 10 daily quests this week", Goal = 10, Reward = 250 },
}

local byGroup: { { Quest } } = {}
for _, quest in DailyConfig.Quests do
	byGroup[quest.Group] = byGroup[quest.Group] or {}
	table.insert(byGroup[quest.Group], quest)
	table.freeze(quest)
end
assert(#byGroup == DailyConfig.Groups, "[DailyConfig] every group needs a quest")

-- The quests of a day number (the same on every server).
function DailyConfig.QuestsFor(day: number): { Quest }
	local list: { Quest } = {}
	for group = 1, DailyConfig.Groups do
		local options = byGroup[group]
		local random = Random.new(day * 31 + group * 7919)
		table.insert(list, options[random:NextInteger(1, #options)])
	end
	return list
end

function DailyConfig.Day(unix: number): number
	return unix // DailyConfig.DaySeconds
end

-- Weeks start on Monday (day 0 = Thursday, 1 January 1970).
function DailyConfig.Week(day: number): number
	return (day + 3) // 7
end

return DailyConfig
