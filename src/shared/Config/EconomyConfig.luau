--!strict
--[[
	EconomyConfig: the numbers of the economy. All prices are SERVER-decided; the client only
	shows them. The currency itself (name, symbol, cap) is GameConfig.Klunks — rename it there.

	Item values (Util/ItemValue reads these)
	  1. ItemOverrides[id].SellPrice wins when present.
	  2. Crafted items: CraftedFactor x the value of their recipe's ingredients (recursive), so
	     selling a creation is never MORE profitable than selling what went into it. Its rarity
	     value is the floor only when that is still below the ingredients (functional bonus).
	  3. Everything else: RarityValues[rarity] (+ the item's small Id-based variation, so not
	     every Common is worth exactly the same).
	  Final price >= MinimumSellPrice. Items with CanBeSold = false (or Special) cannot be sold.

	Why recycling is not a money printer
	  Only natural junk can be recycled (ItemConfig.CanBeRecycled). A recycle's expected value is
	  about 50, so turning yard junk into rewards pays, but rewards cannot be fed back in.
]]

local EconomyConfig = {
	StartingBalance = 25, -- new profiles only

	RarityValues = {
		Common = 10,
		Uncommon = 30,
		Rare = 90,
		Epic = 220,
		Legendary = 600,
		Mythic = 1800,
	},
	-- +/- this fraction of the rarity value, derived from the item id (stable, not random).
	Variation = 0.4,
	CraftedFactor = 0.85, -- a crafted item sells for this share of its ingredients' value
	FunctionalFloorFactor = 0.6, -- functional crafted items sell for at least this x rarity value
	MinimumSellPrice = 1,

	ItemOverrides = {
		-- Unique crafted showpieces: kept, not sold.
		aurora_reactor = { CanBeSold = false, Special = true },
		-- Rare natural finds stay valuable.
		dented_trophy = { SellPrice = 110 },
		toxic_barrel = { SellPrice = 95 },
		crystal_shard = { SellPrice = 260 },
	} :: { [string]: { SellPrice: number?, CanBeSold: boolean?, Special: boolean? } },

	-- Requests
	MaxItemsPerSale = 40,
	DealerDistance = 16, -- studs: sell / buy only standing at the Scrap Dealer
	RecentRequests = 60, -- processed request ids remembered per player (duplicate protection)
	TransactionLog = 50, -- last transactions kept in the profile (support / debugging)
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(EconomyConfig)

return EconomyConfig
