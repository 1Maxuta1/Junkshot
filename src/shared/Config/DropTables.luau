--!strict
--[[
	DropTables: every rarity probability in the game, in percent. Separate systems get
	separate tables, so rebalancing one never changes another. Each table must add up to 100
	(checked at startup). Rolling happens on the server only (RewardService).

	  Recycle      result rarity of the machine's Recycling mode for a Common input
	  RecycleBy    the same for every input rarity (RecycleFor): rarer junk, better results.
	               Average result / selling the input: Common 2.5, Uncommon 1.3, Rare 1.1,
	               Epic 1.0, Legendary 0.8, Mythic 0.6 - a gamble, never a money printer
	  WorldSpawn   rarity of items appearing in the yard (JunkService)
	  Mythic       rows for the Mythic Crafting mode, indexed by the AVERAGE rarity rank of
	               the three inputs (1 = three Commons ... 6 = three Mythics). A fractional
	               average blends the two neighbouring rows, so every better input helps.
]]

local Rarities = require(script.Parent.Rarities)

export type Table = { [string]: number }

local DropTables = {}

-- Stage 4 balance (was 55 / 25 / 12 / 6 / 1.8 / 0.2): a recycle was worth ~50 K against ~10 K for
-- the Common it consumes, and Legendaries came every 15-40 minutes. Now a recycle is worth
-- ~25 K (still 2.5x selling the junk) and Legendary / Mythic results stay rare. See README.
DropTables.Recycle = {
	Common = 70,
	Uncommon = 22,
	Rare = 6,
	Epic = 1.6,
	Legendary = 0.35,
	Mythic = 0.05,
} :: Table

DropTables.RecycleBy = {
	Common = DropTables.Recycle,
	Uncommon = { Common = 50, Uncommon = 34, Rare = 12, Epic = 3, Legendary = 0.9, Mythic = 0.1 },
	Rare = { Common = 14, Uncommon = 34, Rare = 36, Epic = 12, Legendary = 3.5, Mythic = 0.5 },
	Epic = { Common = 0, Uncommon = 16, Rare = 36, Epic = 36, Legendary = 10, Mythic = 2 },
	Legendary = { Common = 0, Uncommon = 0, Rare = 15, Epic = 42, Legendary = 33, Mythic = 10 },
	Mythic = { Common = 0, Uncommon = 0, Rare = 0, Epic = 18, Legendary = 42, Mythic = 40 },
} :: { [string]: Table }

DropTables.WorldSpawn = {
	Common = 72,
	Uncommon = 21,
	Rare = 5.4,
	Epic = 1.3,
	Legendary = 0.25,
	Mythic = 0.05,
} :: Table

DropTables.Mythic = {
	[1] = { Common = 55, Uncommon = 30, Rare = 12, Epic = 3, Legendary = 0, Mythic = 0 },
	[2] = { Common = 30, Uncommon = 38, Rare = 22, Epic = 8, Legendary = 2, Mythic = 0 },
	[3] = { Common = 10, Uncommon = 28, Rare = 35, Epic = 19, Legendary = 7, Mythic = 1 },
	[4] = { Common = 0, Uncommon = 12, Rare = 33, Epic = 36, Legendary = 15, Mythic = 4 },
	[5] = { Common = 0, Uncommon = 0, Rare = 18, Epic = 42, Legendary = 30, Mythic = 10 },
	[6] = { Common = 0, Uncommon = 0, Rare = 0, Epic = 35, Legendary = 45, Mythic = 20 },
} :: { [number]: Table }

local function validate(name: string, tableValue: Table)
	local total = 0
	for rarity, chance in tableValue do
		assert(Rarities.IsValid(rarity), `[DropTables] {name}: unknown rarity "{rarity}"`)
		assert(chance >= 0, `[DropTables] {name}: negative chance for {rarity}`)
		total += chance
	end
	assert(math.abs(total - 100) < 1e-6, `[DropTables] {name} adds up to {total}, expected 100`)
	table.freeze(tableValue)
end

for _, rarity in Rarities.Order do
	assert(DropTables.RecycleBy[rarity] ~= nil, `[DropTables] RecycleBy is missing {rarity}`)
	validate(`RecycleBy.{rarity}`, DropTables.RecycleBy[rarity])
end
table.freeze(DropTables.RecycleBy)
validate("WorldSpawn", DropTables.WorldSpawn)
for rank = 1, #Rarities.Order do
	assert(DropTables.Mythic[rank] ~= nil, `[DropTables] Mythic is missing row {rank}`)
	validate(`Mythic[{rank}]`, DropTables.Mythic[rank])
end
table.freeze(DropTables.Mythic)

function DropTables.RecycleFor(rarity: string?): Table
	return DropTables.RecycleBy[rarity or "Common"] or DropTables.Recycle
end

-- The Mythic row for an average input rank (1..6), blending the two nearest rows.
function DropTables.MythicFor(averageRank: number): Table
	local clamped = math.clamp(averageRank, 1, #Rarities.Order)
	local low = math.floor(clamped)
	local high = math.min(low + 1, #Rarities.Order)
	local blend = clamped - low
	local result: Table = {}
	for _, rarity in Rarities.Order do
		result[rarity] = (DropTables.Mythic[low][rarity] or 0) * (1 - blend) + (DropTables.Mythic[high][rarity] or 0) * blend
	end
	return result
end

return table.freeze(DropTables)
