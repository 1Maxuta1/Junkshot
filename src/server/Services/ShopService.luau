--!strict
--[[
	ShopService: buying items from the Scrap Dealer (data in Config/ShopConfig).

	Buy(player, requestId, entryId) -> (ok, code?, where?)
	  Checks before anything changes: request id new, entry exists, player level high enough,
	  standing at the dealer, enough money, and a free place for the item (hands first, base
	  storage second). Then: charge once (EconomyService.Spend, request id as transaction id),
	  deliver once (a brand-new uid), remember the request id. If delivery still failed the
	  money is refunded in the same step, so a purchase can never be paid twice or lost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DealerService = require(script.Parent.DealerService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local JunkService = require(script.Parent.JunkService)
local ProgressionService = require(script.Parent.ProgressionService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local ShopService = {}

ShopService.Errors = table.freeze({
	InvalidArguments = "InvalidArguments",
	UnknownEntry = "UnknownEntry",
	Duplicate = "Duplicate",
	LevelTooLow = "LevelTooLow",
	NotAtDealer = "NotAtDealer",
	NotEnough = "NotEnough",
	NoSpace = "NoSpace",
})

local MESSAGES: { [string]: string } = {
	LevelTooLow = "Reach a higher player level first",
	NotAtDealer = "Visit the Scrap Dealer to buy",
	NotEnough = "Not enough money",
	NoSpace = "Your hands and your storage are full",
}

local byId: { [string]: any } = {}
for _, entry in ShopConfig.Entries do
	assert(byId[entry.Id] == nil, `[ShopService] duplicate shop entry "{entry.Id}"`)
	assert(ItemConfig.Exists(entry.ItemId), `[ShopService] shop entry "{entry.Id}" sells unknown item "{entry.ItemId}"`)
	assert(ItemValue.ShopPrice(entry) > ItemValue.SellPrice(entry.ItemId),
		`[ShopService] "{entry.Id}" would sell for more than it costs`)
	byId[entry.Id] = entry
end

local started = false

function ShopService.Buy(player: Player, requestId: any, entryId: any): (boolean, string?, string?)
	if not Validate.IsUid(requestId) or type(entryId) ~= "string" then
		return false, ShopService.Errors.InvalidArguments
	end
	local entry = byId[entryId]
	if entry == nil then
		return false, ShopService.Errors.UnknownEntry
	end
	if EconomyService.IsProcessed(player, requestId) then
		return false, ShopService.Errors.Duplicate
	end
	if ProgressionService.GetLevel(player) < (entry.RequiredLevel or 1) then
		return false, ShopService.Errors.LevelTooLow
	end
	if not DealerService.IsNear(player) then
		return false, ShopService.Errors.NotAtDealer
	end
	local price = ItemValue.ShopPrice(entry)
	if not EconomyService.CanAfford(player, price) then
		return false, ShopService.Errors.NotEnough
	end
	local toHands = not CarryService.IsFull(player)
	local storageCount = InventoryService.GetItemCount(player) or math.huge
	if not toHands and storageCount >= InventoryService.GetCapacity(player) then
		return false, ShopService.Errors.NoSpace
	end

	-- Commit (no yields).
	local paid = EconomyService.Spend(player, price, `Shop:{entryId}`, requestId)
	if not paid then
		return false, ShopService.Errors.NotEnough
	end
	local uid = JunkService.NewUid()
	local delivered = false
	local where = "Hands"
	if toHands then
		delivered = CarryService.AddJunk(player, entry.ItemId, uid)
	end
	if not delivered then
		where = "Storage"
		delivered = InventoryService.AddItem(player, entry.ItemId, uid) ~= nil
	end
	if not delivered then
		EconomyService.Earn(player, price, `Refund:{entryId}`)
		return false, ShopService.Errors.NoSpace
	end
	EconomyService.MarkProcessed(player, requestId)
	return true, nil, where
end

function ShopService.Start()
	assert(not started, "[ShopService] Start() called twice")
	started = true
	RemoteGuard.ConnectEvent(Remotes.GetEvent("ShopBuy"), {
		Name = "ShopBuy",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.ShopBuy,
		Validate = function(requestId: any, entryId: any): boolean
			return Validate.IsUid(requestId) and Validate.IsString(entryId, 1, 64)
		end,
	}, function(player: Player, requestId: string, entryId: string)
		local ok, code, where = ShopService.Buy(player, requestId, entryId)
		if ok then
			local name = ItemConfig.GetDisplayName(byId[entryId].ItemId)
			EconomyService.Message(player, if where == "Hands" then `Bought {name}!` else `Bought {name} - sent to your base storage`, "Success")
		elseif code ~= nil and MESSAGES[code] ~= nil then
			EconomyService.Message(player, MESSAGES[code], "Warning")
		end
	end)
end

return ShopService
