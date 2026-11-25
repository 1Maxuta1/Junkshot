--!strict
--[[
	DailyConfig: the daily reward (7-day streak), three daily quests and one weekly goal
	(server DailyService, client DailyController). Days and weeks are UTC.

	Everybody gets the same three quests on a day (picked from the day number), one per group, so
	friends can do them together. Rewards are Klunks through EconomyService, no new currency.
	  a full week = 500 from the days, two machine boosts, two items, and the quests
]]

export type Quest = { Id: string, Group: number, Event: string, Text: string, Goal: number, Reward: number }

local DailyConfig = {
	DaySeconds = 24 * 60 * 60,
	-- Day 1 .. 7 of the login streak, then from the start again.
	--   Klunks  Amount        Boost  Minutes (MachineService.AddBoost: jobs started take half)
	--   Item    Rarity (a random reward item), Icon = item shown on the card
	DayRewards = {
		{ Kind = "Klunks", Amount = 50, Text = "50 KLUNKS" },
		{ Kind = "Boost", Minutes = 30, Text = "CRAFT x2\n30 MIN" },
		{ Kind = "Klunks", Amount = 100, Text = "100 KLUNKS" },
		{ Kind = "Item", Rarity = "Rare", Icon = "neon_gear", Text = "RARE ITEM" },
		{ Kind = "Boost", Minutes = 60, Text = "CRAFT x2\n60 MIN" },
		{ Kind = "Klunks", Amount = 200, Text = "200 KLUNKS" },
		{ Kind = "Item", Rarity = "Epic", Icon = "plasma_toaster", Klunks = 150, Text = "EPIC ITEM\n+150 KLUNKS" },
	} :: { any },
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

for _, reward in DailyConfig.DayRewards do
	assert(reward.Kind == "Klunks" or reward.Kind == "Boost" or reward.Kind == "Item", "[DailyConfig] unknown reward kind")
	table.freeze(reward)
end

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
