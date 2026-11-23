--!strict
--[[
	SellService: selling items to the Scrap Dealer.

	Sell(player, requestId, uids) -> (ok, code?, earned?)
	  The client sends only WHICH items (uids) and a request id. Everything else is decided here:
	    1. request id not processed before (a repeated / doubled request does nothing)
	    2. the player stands at the dealer
	    3. 1..MaxItemsPerSale distinct, well-formed uids
	    4. every uid is the player's own, in their hands or base storage. Items placed in the
	       world, inside a machine, on a machine tray, in a cart or lying in the yard are not
	       there, so they can never be sold.
	    5. every item can be sold (ItemValue.CanSell); price = ItemValue.SellPrice (+ Haggler)
	    6. the payout fits under the balance cap
	  Only when ALL checks pass are the items removed and the money paid, in one step without
	  yielding: no item is lost without payment and no payment happens without the item.
	  If one item is invalid, nothing is sold.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DealerService = require(script.Parent.DealerService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerUpgradeService = require(script.Parent.PlayerUpgradeService)
local ProgressionService = require(script.Parent.ProgressionService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local SellService = {}

SellService.Errors = table.freeze({
	InvalidArguments = "InvalidArguments",
	Duplicate = "Duplicate",
	NotAtDealer = "NotAtDealer",
	NotOwned = "NotOwned",
	NotSellable = "NotSellable",
	BalanceCap = "BalanceCap",
})

local MESSAGES: { [string]: string } = {
	NotAtDealer = "Visit the Scrap Dealer to sell",
	NotOwned = "One of those items is no longer yours",
	NotSellable = "The dealer does not buy that",
	BalanceCap = "Your wallet is full",
}

local started = false

type Pick = { Uid: string, Id: string, Source: "Carry" | "Storage", Price: number }

-- Price list for a set of uids (also used by DevTests). nil + code when anything is invalid.
function SellService.Quote(player: Player, uids: any): ({ Pick }?, number?, string?)
	if type(uids) ~= "table" or #uids < 1 or #uids > EconomyConfig.MaxItemsPerSale then
		return nil, nil, SellService.Errors.InvalidArguments
	end
	local carriedById: { [string]: string } = {}
	for _, entry in CarryService.GetCarried(player) do
		carriedById[entry.Uid] = entry.Id
	end
	local seen: { [string]: boolean } = {}
	local picks: { Pick } = {}
	local total = 0
	for index = 1, #uids do
		local uid = uids[index]
		if not Validate.IsUid(uid) or seen[uid] then
			return nil, nil, SellService.Errors.InvalidArguments
		end
		seen[uid] = true
		local itemId: string? = carriedById[uid]
		local source: "Carry" | "Storage" = "Carry"
		if itemId == nil then
			local record = InventoryService.GetItem(player, uid)
			if record ~= nil then
				itemId = record.id
				source = "Storage"
			end
		end
		if itemId == nil then
			return nil, nil, SellService.Errors.NotOwned
		end
		local price = ItemValue.SellPrice(itemId)
		if price <= 0 then
			return nil, nil, SellService.Errors.NotSellable
		end
		table.insert(picks, { Uid = uid, Id = itemId, Source = source, Price = price })
		total += price
	end
	local bonus = math.floor(total * PlayerUpgradeService.GetSellBonus(player))
	return picks, total + bonus, nil
end

function SellService.Sell(player: Player, requestId: any, uids: any): (boolean, string?, number?)
	if not Validate.IsUid(requestId) then
		return false, SellService.Errors.InvalidArguments
	end
	if EconomyService.IsProcessed(player, requestId) then
		return false, SellService.Errors.Duplicate
	end
	if not DealerService.IsNear(player) then
		return false, SellService.Errors.NotAtDealer
	end
	local picks, payout, code = SellService.Quote(player, uids)
	if picks == nil or payout == nil then
		return false, code
	end
	local balance = EconomyService.GetBalance(player) or 0
	if balance + payout > GameConfig.Klunks.MaxBalance then
		return false, SellService.Errors.BalanceCap
	end

	-- Commit (no yields): remove every item, then pay once.
	for _, pick in picks do
		if pick.Source == "Carry" then
			CarryService.TakeByUid(player, pick.Uid)
		else
			InventoryService.RemoveItem(player, pick.Uid)
		end
	end
	EconomyService.Earn(player, payout, "Sell", requestId)
	EconomyService.MarkProcessed(player, requestId)
	local xp = payout // Progression.SellCoinsPerXp
	if xp > 0 then
		ProgressionService.AddXP(player, xp, "Sell")
	end
	return true, nil, payout
end

function SellService.Start()
	assert(not started, "[SellService] Start() called twice")
	started = true
	RemoteGuard.ConnectEvent(Remotes.GetEvent("SellItems"), {
		Name = "SellItems",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.SellItems,
		Validate = function(requestId: any, uids: any): boolean
			return Validate.IsUid(requestId) and type(uids) == "table"
		end,
	}, function(player: Player, requestId: string, uids: { any })
		local ok, code, earned = SellService.Sell(player, requestId, uids)
		if ok then
			EconomyService.Message(player, `Sold {#uids} item{if #uids == 1 then "" else "s"} for {earned}!`, "Success")
		elseif code ~= nil and MESSAGES[code] ~= nil then
			EconomyService.Message(player, MESSAGES[code], "Warning")
		end
	end)
end

return SellService
