--!strict
--[[
	EconomyService: the one validation path for every currency movement in the game.

	CurrencyService still owns the balance (it is the only code that writes data.Klunks); every
	gameplay system goes through HERE instead, which adds:
	  - a reason and a transaction id for every movement, logged in profile.Data.Economy
	    (last EconomyConfig.TransactionLog entries, for support and debugging)
	  - duplicate protection: request ids that were already processed are refused, and the
	    list of processed ids is saved with the profile, so even a retry after a rejoin is safe
	  - a feedback event to the player's client (EconomyFx: "+120 K" / "-500 K")

	API (server only)
	  GetBalance(player) -> number?
	  Earn(player, amount, reason, txId?) -> (ok, code?)
	  Spend(player, amount, reason, txId?) -> (ok, code?)
	  CanAfford(player, amount) -> boolean
	  IsProcessed(player, requestId) -> boolean   (check BEFORE touching anything else)
	  MarkProcessed(player, requestId)            (in the same non-yielding step as the change)
	  GetTransactions(player) -> { Transaction }  (copies)
	Amounts must be positive integers; the client never supplies an amount or a price.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

EconomyService.Errors = table.freeze({
	DataUnavailable = "DataUnavailable",
	InvalidAmount = "InvalidAmount",
	Duplicate = "Duplicate",
	NotEnough = "NotEnough",
})

local function economyOf(player: Player): Types.EconomyData?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local economy = data.Economy
	if type(economy) ~= "table" then
		economy = { Transactions = {}, Requests = {} }
		data.Economy = economy
	end
	if type(economy.Transactions) ~= "table" then
		economy.Transactions = {}
	end
	if type(economy.Requests) ~= "table" then
		economy.Requests = {}
	end
	return economy
end

local function fx(player: Player, payload: { [string]: any })
	if player.Parent == Players then
		Remotes.GetEvent("EconomyFx"):FireClient(player, payload)
	end
end

local function log(player: Player, kind: string, amount: number, reason: string, txId: string?)
	local economy = economyOf(player)
	if economy == nil then
		return
	end
	table.insert(economy.Transactions, {
		Id = txId or HttpService:GenerateGUID(false),
		Type = kind,
		Amount = amount,
		Reason = reason,
		Balance = CurrencyService.GetKlunks(player) or 0,
		At = os.time(),
	})
	while #economy.Transactions > EconomyConfig.TransactionLog do
		table.remove(economy.Transactions, 1)
	end
end

function EconomyService.GetBalance(player: Player): number?
	return CurrencyService.GetKlunks(player)
end

function EconomyService.CanAfford(player: Player, amount: number): boolean
	return CurrencyService.HasEnough(player, amount)
end

function EconomyService.IsProcessed(player: Player, requestId: string): boolean
	local economy = economyOf(player)
	if economy == nil then
		return false
	end
	return table.find(economy.Requests, requestId) ~= nil
end

function EconomyService.MarkProcessed(player: Player, requestId: string)
	local economy = economyOf(player)
	if economy == nil then
		return
	end
	table.insert(economy.Requests, requestId)
	while #economy.Requests > EconomyConfig.RecentRequests do
		table.remove(economy.Requests, 1)
	end
end

function EconomyService.Earn(player: Player, amount: number, reason: string, txId: string?): (boolean, string?)
	if not Validate.IsInteger(amount, 1) then
		return false, EconomyService.Errors.InvalidAmount
	end
	local ok, code = CurrencyService.AddKlunks(player, amount)
	if not ok then
		return false, code
	end
	log(player, "Earn", amount, reason, txId)
	fx(player, { Kind = "Earn", Amount = amount, Reason = reason })
	return true, nil
end

function EconomyService.Spend(player: Player, amount: number, reason: string, txId: string?): (boolean, string?)
	if not Validate.IsInteger(amount, 1) then
		return false, EconomyService.Errors.InvalidAmount
	end
	if not CurrencyService.HasEnough(player, amount) then
		return false, EconomyService.Errors.NotEnough
	end
	local ok, code = CurrencyService.RemoveKlunks(player, amount)
	if not ok then
		return false, code
	end
	log(player, "Spend", amount, reason, txId)
	fx(player, { Kind = "Spend", Amount = amount, Reason = reason })
	return true, nil
end

-- A short message on the player's screen (shared by the economy services).
function EconomyService.Message(player: Player, text: string, kind: string?)
	fx(player, { Kind = "Message", Text = text, Style = kind or "Info" })
end

function EconomyService.GetTransactions(player: Player): { Types.Transaction }
	local economy = economyOf(player)
	local copy: { Types.Transaction } = {}
	if economy ~= nil then
		for index, entry in economy.Transactions do
			copy[index] = table.clone(entry)
		end
	end
	return copy
end

return EconomyService
