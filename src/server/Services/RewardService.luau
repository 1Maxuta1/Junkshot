--!strict
--[[
	RewardService: server-side reward rolling and delivery. The client never chooses a rarity
	or an item.

	  RollRarity()            -> rarityId   weighted by Rarities chances
	  RollItem(rarityId)      -> itemId     uniform pick from ItemConfig.GetRewardPool
	  Roll()                  -> (itemId, rarityId)
	  Deliver(player, itemId) -> (uid?, errorCode?)
	      Adds the item to the player's saved inventory through InventoryService (the only code
	      allowed to add items), which assigns the unique item uid.

	Balancing lives in Rarities (chances) and ItemConfig (pools); nothing here needs to change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local InventoryService = require(script.Parent.InventoryService)

local RewardService = {}

local random = Random.new()

function RewardService.RollRarity(): string
	local roll = random:NextNumber() * 100
	for _, rarityId in Rarities.Order do
		local info = Rarities.Info[rarityId]
		roll -= info.Chance
		if roll < 0 then
			return rarityId
		end
	end
	return Rarities.Order[1] -- floating point safety net (chances add up to exactly 100)
end

function RewardService.RollItem(rarityId: string): string
	local pool = ItemConfig.GetRewardPool(rarityId)
	assert(#pool > 0, `[RewardService] empty reward pool for {rarityId}`) -- ItemConfig checks this at startup
	return pool[random:NextInteger(1, #pool)]
end

function RewardService.Roll(): (string, string)
	local rarityId = RewardService.RollRarity()
	return RewardService.RollItem(rarityId), rarityId
end

function RewardService.Deliver(player: Player, itemId: string): (string?, string?)
	return InventoryService.AddItem(player, itemId)
end

return RewardService
