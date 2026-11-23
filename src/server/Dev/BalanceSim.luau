--!strict
--[[
	BalanceSim: a THEORETICAL progression estimate built from the project's real configuration
	(drop tables, item values, upgrade / chest / base prices, XP rules). Not part of the game:
	run it in Studio's command bar or through MCP:
	  print(require(game.ServerScriptService.Server.Dev.BalanceSim).Report())

	What it models (deliberately simple, every assumption is a parameter below):
	  - A player collects items at PickRate items per minute (walking + carrying + trips),
	    boosted a little by Snow Boots / Bigger Backpack / Grabber Arm.
	  - The yard supply is shared: Replenish target items every Interval, split by Players.
	  - Natural items: rarity from DropTables.WorldSpawn, item from the spawn pool.
	  - Yard junk is recycled while the machine is free (RecycleSeconds per job, after Speed
	    upgrades / clicking), everything else is sold (the Collector keeps Rare+).
	  - Money is spent on the cheapest affordable upgrade in a fixed priority list.
	It does NOT model: crafting, mythic crafting, vehicles, the 6 h jobs, trading, luck streaks.
	Results are Monte-Carlo averages over Runs sessions; label them as estimates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local WeightedRandom = require(ReplicatedStorage.Shared.Util.WeightedRandom)

local BalanceSim = {}

export type Persona = {
	Name: string,
	Minutes: number, -- session length
	PickRate: number, -- items per minute
	Recycles: boolean,
	RecycleSeconds: number, -- seconds per recycle job (clicking shortens it)
	KeepsRare: boolean, -- collector: does not sell Rare+
	Players: number, -- players sharing the yard
}

BalanceSim.Personas = {
	{ Name = "Casual (15 min)", Minutes = 15, PickRate = 2.5, Recycles = true, RecycleSeconds = 30, KeepsRare = false, Players = 4 },
	{ Name = "Regular (30 min)", Minutes = 30, PickRate = 3, Recycles = true, RecycleSeconds = 30, KeepsRare = false, Players = 4 },
	{ Name = "Active (60 min)", Minutes = 60, PickRate = 3.5, Recycles = true, RecycleSeconds = 20, KeepsRare = false, Players = 4 },
	{ Name = "Efficient (60 min)", Minutes = 60, PickRate = 4, Recycles = true, RecycleSeconds = 10, KeepsRare = false, Players = 2 },
	{ Name = "Collector (60 min)", Minutes = 60, PickRate = 3.5, Recycles = true, RecycleSeconds = 30, KeepsRare = true, Players = 4 },
	{ Name = "Busy server (8 players, 30 min)", Minutes = 30, PickRate = 3.5, Recycles = true, RecycleSeconds = 20, KeepsRare = false, Players = 8 },
} :: { Persona }

local RUNS = 300
local MEANINGFUL = 1200 -- price of a "meaningful" upgrade (chest level 3, Bigger Backpack 3 ...)

-- Spend priority: { kind, id } (cheapest affordable unlocked entry is bought first).
local function shopList(): { { Kind: string, Id: string, Level: number, Price: number, RequiredLevel: number } }
	local list = {}
	for _, upgrade in PlayerUpgrades.List do
		for level = 2, #upgrade.Levels do
			local step = upgrade.Levels[level]
			table.insert(list, { Kind = "Player", Id = upgrade.Id, Level = level, Price = step.Price, RequiredLevel = step.RequiredLevel or 1 })
		end
	end
	for level = 2, #BaseConfig.Chest.Levels do
		local step = BaseConfig.Chest.Levels[level]
		table.insert(list, { Kind = "Chest", Id = "Chest", Level = level, Price = step.Price, RequiredLevel = step.RequiredLevel or 1 })
	end
	for level = 2, #BaseConfig.BaseLevels do
		local step = BaseConfig.BaseLevels[level]
		table.insert(list, { Kind = "Base", Id = "Base", Level = level, Price = step.Price, RequiredLevel = step.RequiredLevel or 1 })
	end
	table.sort(list, function(a, b)
		return a.Price < b.Price
	end)
	return list
end

local function levelForXp(totalXp: number): number
	local level = 1
	local left = totalXp
	while level < Progression.MaxLevel and left >= Progression.XpToNext(level) do
		left -= Progression.XpToNext(level)
		level += 1
	end
	return level
end

type Result = {
	Coins: number,
	Earned: number,
	FirstUpgradeAt: number?,
	Upgrade1500At: number?, -- first purchase costing >= 1500
	Bought: number,
	Level: number,
	Found: { [string]: number }, -- rarity -> count (world + recycling)
}

local function simulate(persona: Persona, recycleTable: { [string]: number }, random: Random): Result
	local supplyPerMinute = (math.min(GameConfig.Junk.Replenish.MaxTarget,
		GameConfig.Junk.Replenish.BaseTarget + (persona.Players - 1) * GameConfig.Junk.Replenish.PerPlayer)
		/ (GameConfig.Junk.Replenish.Interval / 60)) / persona.Players
	local initialShare = (GameConfig.Junk.Replenish.BaseTarget + (persona.Players - 1) * GameConfig.Junk.Replenish.PerPlayer) / persona.Players
	local coins = EconomyConfig.StartingBalance
	local earned = 0
	local xp = 0
	local discovered: { [string]: boolean } = {}
	local owned: { [string]: number } = {}
	local found: { [string]: number } = {}
	local machineFreeAt = 0
	local firstUpgrade: number? = nil
	local upgrade1500: number? = nil
	local bought = 0
	local shop = shopList()
	local stock = initialShare -- items available to this player right now
	local carryBonus = 0

	local function gain(itemId: string)
		local rarity = ItemConfig.GetRarity(itemId) or "Common"
		found[rarity] = (found[rarity] or 0) + 1
		if not discovered[itemId] then
			discovered[itemId] = true
			xp += (Progression.Discover :: any)[rarity] or 0
		end
	end

	local function sell(itemId: string)
		local rarity = ItemConfig.GetRarity(itemId) or "Common"
		if persona.KeepsRare and Rarities.GetRank(rarity) >= Rarities.GetRank("Rare") then
			return
		end
		local price = ItemValue.SellPrice(itemId)
		earned += price
		coins += price
		xp += price // Progression.SellCoinsPerXp
	end

	local step = 1 / 6 -- 10 seconds
	local t = 0
	local carry = 0
	while t < persona.Minutes do
		t += step
		stock += supplyPerMinute * step
		local speedBonus = 1 + 0.05 * ((owned.WalkSpeed or 1) - 1) + 0.04 * ((owned.PickupRange or 1) - 1) + 0.04 * carryBonus
		carry += persona.PickRate * speedBonus * step
		while carry >= 1 and stock >= 1 do
			carry -= 1
			stock -= 1
			local rarity = WeightedRandom.PickRarity(DropTables.WorldSpawn, random)
			local itemId = WeightedRandom.PickEntry(ItemConfig.GetSpawnPool(rarity), random).Id
			gain(itemId)
			if persona.Recycles and ItemConfig.CanBeRecycled(itemId) and Rarities.GetRank(rarity) <= Rarities.GetRank("Uncommon")
				and t * 60 >= machineFreeAt
			then
				machineFreeAt = t * 60 + persona.RecycleSeconds
				xp += Progression.Recycle
				local rewardRarity = WeightedRandom.PickRarity(recycleTable, random)
				local pool = ItemConfig.GetRewardPool(rewardRarity)
				local reward = pool[random:NextInteger(1, #pool)]
				gain(reward)
				sell(reward)
			else
				sell(itemId)
			end
		end
		-- Spend
		local level = levelForXp(xp)
		local purchased = true
		while purchased do
			purchased = false
			for _, entry in shop do
				local key = `{entry.Kind}:{entry.Id}`
				local have = owned[if entry.Kind == "Player" then entry.Id else key] or 1
				if have == entry.Level - 1 and coins >= entry.Price and level >= entry.RequiredLevel then
					coins -= entry.Price
					owned[if entry.Kind == "Player" then entry.Id else key] = entry.Level
					if entry.Id == "CarryCapacity" then
						carryBonus += 1
					end
					bought += 1
					firstUpgrade = firstUpgrade or t
					if entry.Price >= MEANINGFUL then
						upgrade1500 = upgrade1500 or t
					end
					purchased = true
					break
				end
			end
		end
	end
	return { Coins = coins, Earned = earned, FirstUpgradeAt = firstUpgrade, Upgrade1500At = upgrade1500, Bought = bought, Level = levelForXp(xp), Found = found }
end


local function average(persona: Persona, recycleTable: { [string]: number }): string
	local random = Random.new(42)
	local coins, bought, level, earned = 0, 0, 0, 0
	local first, firstCount, big, bigCount = 0, 0, 0, 0
	local found: { [string]: number } = {}
	for _ = 1, RUNS do
		local result = simulate(persona, recycleTable, random)
		coins += result.Coins
		earned += result.Earned
		bought += result.Bought
		level += result.Level
		if result.FirstUpgradeAt ~= nil then
			first += result.FirstUpgradeAt
			firstCount += 1
		end
		if result.Upgrade1500At ~= nil then
			big += result.Upgrade1500At
			bigCount += 1
		end
		for rarity, count in result.Found do
			found[rarity] = (found[rarity] or 0) + count
		end
	end
	local lines = {}
	local function rate(rarity: string): string
		local perSession = (found[rarity] or 0) / RUNS
		if perSession <= 0 then
			return `{rarity}: none`
		end
		return string.format("%s: %.2f/session (1 per %.0f min)", rarity, perSession, persona.Minutes / perSession)
	end
	table.insert(lines, string.format("%s - earned %.0f K (%.0f K/min), %.1f purchases, %.0f K left, level %.1f",
		persona.Name, earned / RUNS, earned / RUNS / persona.Minutes, bought / RUNS, coins / RUNS, level / RUNS))
	table.insert(lines, string.format("   first upgrade: %s; first meaningful (" .. MEANINGFUL .. "+) upgrade: %s",
		if firstCount > 0 then string.format("%.1f min (%d%% of sessions)", first / firstCount, math.floor(firstCount / RUNS * 100)) else "never",
		if bigCount > 0 then string.format("%.1f min (%d%% of sessions)", big / bigCount, math.floor(bigCount / RUNS * 100)) else "not in this session"))
	table.insert(lines, "   " .. rate("Rare") .. ", " .. rate("Epic") .. ", " .. rate("Legendary") .. ", " .. rate("Mythic"))
	return table.concat(lines, "\n")
end

-- Expected sell value of one recycle job with a table (coins).
function BalanceSim.RecycleValue(recycleTable: { [string]: number }): number
	local total = 0
	for rarity, chance in recycleTable do
		local pool = ItemConfig.GetRewardPool(rarity)
		local sum = 0
		for _, id in pool do
			sum += ItemValue.SellPrice(id)
		end
		total += chance / 100 * (sum / #pool)
	end
	return total
end

function BalanceSim.Report(recycleTable: { [string]: number }?): string
	local table_ = recycleTable or DropTables.Recycle
	local lines = {
		"THEORETICAL ESTIMATE (Monte Carlo, " .. RUNS .. " sessions per profile; not measured gameplay)",
		string.format("Recycle job expected value: %.1f K (a Common yard item sells for ~10 K)", BalanceSim.RecycleValue(table_)),
	}
	for _, persona in BalanceSim.Personas do
		table.insert(lines, average(persona, table_))
	end
	return table.concat(lines, "\n")
end

return BalanceSim
