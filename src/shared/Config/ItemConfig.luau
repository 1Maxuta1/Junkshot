--!strict
--[[
	ItemConfig: THE item catalog. Every physical thing in JUNKSHOT is an item here: junk,
	materials, collectibles, components and crafted creations. They all share one lifecycle
	(world <-> carried, throwable, recyclable) and one model builder (Util/JunkFactory).

	Data lives in Config/Items/*:
	  Junk.luau          everyday scrap (crafting material, never a reward)
	  Materials.luau     crafting parts (spawn in the world, drop from recycling)
	  Collectibles.luau  valuable objects (drop from recycling / mythic crafting, rare finds)
	  Crafted.luau       components and creations that only come from crafting

	Item fields (Types.ItemDefinition)
	  Id, DisplayName, Rarity, Category, Parts (model), Description?
	  NaturalSpawn + SpawnWeight   may appear in the yard (rarity rolled by DropTables.WorldSpawn,
	                               SpawnWeight = relative chance within that rarity)
	  RecyclePool                  may be the result of recycling / mythic crafting
	  CanBeRecycled                recycling input; default: only Category "Junk" (see CanBeRecycled)
	  ItemType, BehaviorId         what the object does (behaviors arrive in Stage 2B)
	  IsDebug                      tests only

	Rules
	  - Item ids are stored in player data: NEVER rename or remove an id that has shipped.
	  - Every non-debug item needs Parts.
	  - Every rarity needs at least one RecyclePool item and one NaturalSpawn item (checked).

	Adding an item: add one entry to the right data module. Nothing else needs to change.
]]

local Types = require(script.Parent.Parent.Types)
local Rarities = require(script.Parent.Rarities)

local SOURCES = {
	require(script.Parent.Items.Junk),
	require(script.Parent.Items.Materials),
	require(script.Parent.Items.Collectibles),
	require(script.Parent.Items.Crafted),
}

local VALID_CATEGORIES = { Junk = true, Material = true, Collectible = true, Component = true, Crafted = true }

local items: { [string]: Types.ItemDefinition } = {}
local rewardPools: { [string]: { string } } = {}
local spawnPools: { [string]: { { Id: string, Weight: number } } } = {}

-- Fail loudly at startup on a broken config instead of corrupting player data later.
for _, source in SOURCES do
	for _, definition in source :: { Types.ItemDefinition } do
		local id = definition.Id
		assert(items[id] == nil, `[ItemConfig] duplicate id "{id}"`)
		assert(string.match(id, "^[%w_]+$") ~= nil, `[ItemConfig] invalid id "{id}"`)
		assert(Rarities.IsValid(definition.Rarity), `[ItemConfig] "{id}" has unknown rarity "{definition.Rarity}"`)
		assert(VALID_CATEGORIES[definition.Category], `[ItemConfig] "{id}" has unknown category "{tostring(definition.Category)}"`)
		local parts = definition.Parts
		if definition.IsDebug ~= true then
			assert(parts ~= nil and #parts > 0, `[ItemConfig] "{id}" needs Parts`)
			for index, spec in parts do
				local size = spec.Size
				assert(size.X > 0 and size.Y > 0 and size.Z > 0, `[ItemConfig] "{id}" part {index} has a non-positive size`)
			end
			if definition.RecyclePool then
				rewardPools[definition.Rarity] = rewardPools[definition.Rarity] or {}
				table.insert(rewardPools[definition.Rarity], id)
			end
			if definition.NaturalSpawn then
				local weight = definition.SpawnWeight or 1
				assert(weight >= 0, `[ItemConfig] "{id}" has a negative SpawnWeight`)
				if weight > 0 then
					spawnPools[definition.Rarity] = spawnPools[definition.Rarity] or {}
					table.insert(spawnPools[definition.Rarity], { Id = id, Weight = weight })
				end
			end
		end
		if parts ~= nil then
			for _, spec in parts do
				table.freeze(spec)
			end
			table.freeze(parts)
		end
		items[id] = table.freeze(definition)
	end
end

for _, rarity in Rarities.Order do
	assert(rewardPools[rarity] ~= nil, `[ItemConfig] no RecyclePool item has rarity "{rarity}"`)
	assert(spawnPools[rarity] ~= nil, `[ItemConfig] no NaturalSpawn item has rarity "{rarity}"`)
	table.sort(rewardPools[rarity])
	table.sort(spawnPools[rarity], function(a, b)
		return a.Id < b.Id
	end)
	table.freeze(rewardPools[rarity])
	for _, entry in spawnPools[rarity] do
		table.freeze(entry)
	end
	table.freeze(spawnPools[rarity])
end

local ItemConfig = {}

ItemConfig.Items = table.freeze(items)

function ItemConfig.Get(itemId: string): Types.ItemDefinition?
	return items[itemId]
end

function ItemConfig.Exists(itemId: any): boolean
	return type(itemId) == "string" and items[itemId] ~= nil
end

-- Item ids that recycling / mythic crafting can produce for a rarity (never empty).
function ItemConfig.GetRewardPool(rarity: string): { string }
	return rewardPools[rarity] or {}
end

-- Weighted item ids that can appear in the world for a rarity (never empty).
function ItemConfig.GetSpawnPool(rarity: string): { { Id: string, Weight: number } }
	return spawnPools[rarity] or {}
end

function ItemConfig.GetRarity(itemId: string): string?
	local definition = items[itemId]
	return if definition ~= nil then definition.Rarity else nil
end

function ItemConfig.GetDisplayName(itemId: string): string
	local definition = items[itemId]
	return if definition ~= nil then definition.DisplayName else itemId
end

-- Recycling (1 item -> a random reward) accepts natural yard junk only. Rewards, materials and
-- creations cannot go back in, otherwise one item could be recycled into money forever.
-- An item can opt in or out with CanBeRecycled = true / false.
function ItemConfig.CanBeRecycled(itemId: string): boolean
	local definition = items[itemId]
	if definition == nil or definition.IsDebug == true then
		return false
	end
	if definition.CanBeRecycled ~= nil then
		return definition.CanBeRecycled
	end
	return definition.Category == "Junk"
end

-- Mythic crafting (3 items -> 1, six hours) accepts any real item.
function ItemConfig.CanBeMythicInput(itemId: string): boolean
	local definition = items[itemId]
	return definition ~= nil and definition.IsDebug ~= true and definition.CanBeRecycled ~= false
end

return table.freeze(ItemConfig)
