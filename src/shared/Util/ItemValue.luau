--!strict
--[[
	ItemValue: what an item sells for (rules in Config/EconomyConfig). Shared so the client shows
	exactly the price the server pays; the server never takes a price from the client.

	  SellPrice(itemId) -> number      0 when it cannot be sold
	  CanSell(itemId) -> boolean
	  IngredientValue(recipe) -> number

	Crafted items are worth at most what their ingredients sell for (CraftedFactor below 1), so
	crafting is done for the item's use, never to print money. Functional creations get a small
	floor (FunctionalFloorFactor x rarity value) but still never above their ingredients.
]]

local Behaviors = require(script.Parent.Parent.Config.Behaviors)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local ItemConfig = require(script.Parent.Parent.Config.ItemConfig)
local Recipes = require(script.Parent.Parent.Config.Recipes)

local ItemValue = {}

local cache: { [string]: number } = {}
local computing: { [string]: boolean } = {}

-- Stable value in [-1, 1] from the id, so equal-rarity items differ a little but never change.
local function idJitter(itemId: string): number
	local hash = 0
	for index = 1, #itemId do
		hash = (hash * 31 + string.byte(itemId, index)) % 100003
	end
	return (hash % 2001) / 1000 - 1
end

function ItemValue.CanSell(itemId: string): boolean
	local definition = ItemConfig.Get(itemId)
	if definition == nil or definition.IsDebug == true then
		return false
	end
	local override = EconomyConfig.ItemOverrides[itemId]
	if override ~= nil and (override.CanBeSold == false or override.Special == true) then
		return false
	end
	return true
end

local function baseValue(itemId: string): number
	local rarity = ItemConfig.GetRarity(itemId) or "Common"
	local base = (EconomyConfig.RarityValues :: any)[rarity] or EconomyConfig.RarityValues.Common
	return base * (1 + idJitter(itemId) * EconomyConfig.Variation)
end

local function rawValue(itemId: string): number
	local cached = cache[itemId]
	if cached ~= nil then
		return cached
	end
	local override = EconomyConfig.ItemOverrides[itemId]
	local value: number
	if override ~= nil and override.SellPrice ~= nil then
		value = override.SellPrice
	else
		local recipe = Recipes.Get(itemId)
		if recipe ~= nil and not computing[itemId] then
			computing[itemId] = true
			local ingredients = ItemValue.IngredientValue(recipe)
			computing[itemId] = nil
			value = ingredients * EconomyConfig.CraftedFactor
			local definition = ItemConfig.Get(itemId)
			local behaviorId = if definition ~= nil then definition.BehaviorId else nil
			if behaviorId ~= nil and (Behaviors :: any)[behaviorId] ~= nil then
				local rarity = ItemConfig.GetRarity(itemId) or "Common"
				local floor = ((EconomyConfig.RarityValues :: any)[rarity] or 0) * EconomyConfig.FunctionalFloorFactor
				value = math.max(value, math.min(floor, ingredients))
			end
		else
			value = baseValue(itemId)
		end
	end
	value = math.max(EconomyConfig.MinimumSellPrice, math.floor(value + 0.5))
	cache[itemId] = value
	return value
end

-- What the ingredients of a recipe would sell for together.
function ItemValue.IngredientValue(recipe: any): number
	local total = 0
	for _, ingredient in recipe.Ingredients do
		total += rawValue(ingredient.Id) * ingredient.Count
	end
	return total
end

function ItemValue.SellPrice(itemId: string): number
	if not ItemValue.CanSell(itemId) then
		return 0
	end
	return rawValue(itemId)
end

-- What the dealer charges for a shop entry (Config/ShopConfig): explicit Price, or the item's
-- value x BuyMultiplier rounded up to 5. Always above the sell price, so buy-to-sell loses.
function ItemValue.ShopPrice(entry: any): number
	if entry.Price ~= nil then
		return entry.Price
	end
	local ShopConfig = require(script.Parent.Parent.Config.ShopConfig) :: any
	local price = rawValue(entry.ItemId) * ShopConfig.BuyMultiplier
	return math.max(5, math.ceil(price / 5) * 5)
end

return ItemValue
