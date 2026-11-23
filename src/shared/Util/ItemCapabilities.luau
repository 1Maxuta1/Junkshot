--!strict
--[[
	ItemCapabilities: what a player can do with an item, derived from the catalog
	(Config/ItemConfig), the behaviors (Config/Behaviors) and the recipes (Config/Recipes).
	Shared, so the client shows exactly the actions the server will accept.

	  Get(itemId) -> Capabilities?
	    CanBeCarried   every catalog item
	    CanBePlaced    has a "Place" behavior (vehicles, cart, radio ...)
	    CanBeUsed      has a "Use" behavior (detector ...)
	    CanBeSold      Util/ItemValue.CanSell (Config/EconomyConfig)
	    CanBeRecycled  ItemConfig.CanBeRecycled
	    CanBeCrafted   some recipe produces it
	    BehaviorId, Behavior   the behavior config (nil for plain items)
]]

local Behaviors = require(script.Parent.Parent.Config.Behaviors)
local ItemConfig = require(script.Parent.Parent.Config.ItemConfig)
local Recipes = require(script.Parent.Parent.Config.Recipes)
local ItemValue = require(script.Parent.ItemValue)

export type Capabilities = {
	CanBeCarried: boolean,
	CanBePlaced: boolean,
	CanBeUsed: boolean,
	CanBeSold: boolean,
	CanBeRecycled: boolean,
	CanBeCrafted: boolean,
	BehaviorId: string?,
	Behavior: any?,
}

local ItemCapabilities = {}

local cache: { [string]: Capabilities } = {}

function ItemCapabilities.Get(itemId: string): Capabilities?
	local cached = cache[itemId]
	if cached ~= nil then
		return cached
	end
	local definition = ItemConfig.Get(itemId)
	if definition == nil then
		return nil
	end
	local behaviorId = definition.BehaviorId
	local behavior = if behaviorId ~= nil then (Behaviors :: any)[behaviorId] else nil
	local capabilities: Capabilities = table.freeze({
		CanBeCarried = true,
		CanBePlaced = behavior ~= nil and behavior.Mode == "Place",
		CanBeUsed = behavior ~= nil and behavior.Mode == "Use",
		CanBeSold = ItemValue.CanSell(itemId),
		CanBeRecycled = ItemConfig.CanBeRecycled(itemId),
		CanBeCrafted = Recipes.Get(itemId) ~= nil,
		BehaviorId = if behavior ~= nil then behaviorId else nil,
		Behavior = behavior,
	})
	cache[itemId] = capabilities
	return capabilities
end

-- The behavior config of an item, or nil when it has none.
function ItemCapabilities.GetBehavior(itemId: string): any?
	local capabilities = ItemCapabilities.Get(itemId)
	return if capabilities ~= nil then capabilities.Behavior else nil
end

return ItemCapabilities
