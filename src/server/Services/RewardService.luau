--!strict
--[[
	RewardService: server-side reward rolling. The client never chooses a rarity or an item.

	  RollRarity(chances)     -> rarityId   chances = a DropTables table (percent per rarity)
	  RollItem(rarityId)      -> itemId     uniform pick from ItemConfig.GetRewardPool
	  RollRecycle(inputId?)   -> (itemId, rarityId)   the Recycling mode result; rarer junk has
	                          better odds (DropTables.RecycleFor)

	Balancing lives in DropTables (chances) and ItemConfig (pools); nothing here needs to change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local WeightedRandom = require(ReplicatedStorage.Shared.Util.WeightedRandom)

local RewardService = {}

local random = Random.new()

function RewardService.RollRarity(chances: { [string]: number }): string
	return WeightedRandom.PickRarity(chances, random)
end

function RewardService.RollItem(rarityId: string): string
	local pool = ItemConfig.GetRewardPool(rarityId)
	assert(#pool > 0, `[RewardService] empty reward pool for {rarityId}`) -- ItemConfig checks this at startup
	return pool[random:NextInteger(1, #pool)]
end

function RewardService.RollRecycle(inputId: string?): (string, string)
	local inputRarity = if inputId ~= nil then ItemConfig.GetRarity(inputId) else nil
	local rarityId = RewardService.RollRarity(DropTables.RecycleFor(inputRarity))
	return RewardService.RollItem(rarityId), rarityId
end

return RewardService
