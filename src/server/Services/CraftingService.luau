--!strict
--[[
	CraftingService: pure crafting rules (no state, no side effects). MachineService asks it
	what to consume and what to produce; it never touches carry lists or machines itself.

	  PlanRecipe(recipe, carried) -> ({ uid }?, missing)
	      Picks exactly the carried uids that satisfy the recipe's ingredients (oldest first).
	      Returns nil plus a { [itemId] = missingCount } table when something is missing.
	  MythicChances(inputIds) -> { [rarity] = percent }
	      DropTables.MythicFor(average input rank): better inputs, better odds.
	  RollMythic(inputIds) -> (itemId, rarityId)
	      A matching MachineConfig.MythicCombos entry gives its fixed result; otherwise a rarity
	      is rolled from MythicChances and an item from that rarity's reward pool.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Types = require(ReplicatedStorage.Shared.Types)
local RewardService = require(script.Parent.RewardService)

local CraftingService = {}

function CraftingService.PlanRecipe(recipe: Types.Recipe, carried: { Types.CarriedJunk }): ({ string }?, { [string]: number })
	local available: { [string]: { string } } = {}
	for _, entry in carried do
		available[entry.Id] = available[entry.Id] or {}
		table.insert(available[entry.Id], entry.Uid)
	end
	local plan: { string } = {}
	local missing: { [string]: number } = {}
	local complete = true
	for _, ingredient in recipe.Ingredients do
		local uids = available[ingredient.Id] or {}
		local have = #uids
		if have < ingredient.Count then
			missing[ingredient.Id] = ingredient.Count - have
			complete = false
		else
			for index = 1, ingredient.Count do
				table.insert(plan, uids[index])
			end
		end
	end
	return if complete then plan else nil, missing
end

function CraftingService.MythicChances(inputIds: { string }): { [string]: number }
	local total = 0
	for _, id in inputIds do
		total += Rarities.GetRank(ItemConfig.GetRarity(id))
	end
	return DropTables.MythicFor(total / math.max(#inputIds, 1))
end

local function sortedKey(ids: { string }): string
	local copy = table.clone(ids)
	table.sort(copy)
	return table.concat(copy, "|")
end

function CraftingService.FindCombo(inputIds: { string }): string?
	local key = sortedKey(inputIds)
	for _, combo in MachineConfig.MythicCombos do
		if sortedKey(combo.Inputs) == key then
			return combo.Result
		end
	end
	return nil
end

function CraftingService.RollMythic(inputIds: { string }): (string, string)
	local combo = CraftingService.FindCombo(inputIds)
	if combo ~= nil and ItemConfig.Exists(combo) then
		return combo, ItemConfig.GetRarity(combo) or "Mythic"
	end
	local rarity = RewardService.RollRarity(CraftingService.MythicChances(inputIds))
	return RewardService.RollItem(rarity), rarity
end

return CraftingService
