--!strict
--[[
	WeightedRandom: weighted picks used by every drop/spawn roll.

	  PickRarity(chances, random)   chances = { [rarityId] = weight } (e.g. a DropTables table);
	                                iterates in Rarities.Order so results are deterministic for a
	                                given random state.
	  PickEntry(entries, random)    entries = { { Weight: number, ... } } -> one entry
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)

local WeightedRandom = {}

function WeightedRandom.PickRarity(chances: { [string]: number }, random: Random): string
	local total = 0
	for _, rarityId in Rarities.Order do
		total += chances[rarityId] or 0
	end
	local roll = random:NextNumber() * total
	local last = Rarities.Order[1]
	for _, rarityId in Rarities.Order do
		local weight = chances[rarityId] or 0
		if weight > 0 then
			last = rarityId
			roll -= weight
			if roll < 0 then
				return rarityId
			end
		end
	end
	return last -- floating point safety net
end

function WeightedRandom.PickEntry<T>(entries: { T & { Weight: number } }, random: Random): T
	local total = 0
	for _, entry in entries do
		total += entry.Weight
	end
	local roll = random:NextNumber() * total
	for _, entry in entries do
		roll -= entry.Weight
		if roll < 0 then
			return entry
		end
	end
	return entries[#entries]
end

return WeightedRandom
