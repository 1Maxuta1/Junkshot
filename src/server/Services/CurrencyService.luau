--!strict
--[[
	CurrencyService: the ONLY code allowed to change a player's Klunks.

	All amounts must be positive integers within GameConfig.Klunks.MaxBalance. Every
	operation validates, checks the balance and mutates in one non-yielding step, so a
	balance can never go negative or be changed halfway.

	Results:  Add/Remove return (success: boolean, errorCode: string?).
	Events:   CurrencyService.Changed fires (player: Player, newBalance: number).
	Clients never call this module; they only receive updates via ReplicationService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataService = require(script.Parent.DataService)

local MAX_BALANCE = GameConfig.Klunks.MaxBalance

local CurrencyService = {}

CurrencyService.Errors = table.freeze({
	DataUnavailable = "DataUnavailable",
	CorruptData = "CorruptData",
	InvalidAmount = "InvalidAmount",
	InsufficientKlunks = "InsufficientKlunks",
	BalanceCap = "BalanceCap",
})

CurrencyService.Changed = Signal.new() -- (player: Player, newBalance: number)

-- Loaded data whose Klunks value is verified, or (nil, errorCode).
local function getVerifiedData(player: Player): (Types.ProfileData?, string?)
	local data = DataService.GetData(player)
	if data == nil then
		return nil, CurrencyService.Errors.DataUnavailable
	end
	if not Validate.IsInteger(data.Klunks, 0, MAX_BALANCE) then
		warn(`[CurrencyService] {player.Name}: Klunks value in profile is invalid ({tostring(data.Klunks)})`)
		return nil, CurrencyService.Errors.CorruptData
	end
	return data, nil
end

-- Returns nil when the player's data is not available.
function CurrencyService.GetKlunks(player: Player): number?
	local data = getVerifiedData(player)
	if data == nil then
		return nil
	end
	return data.Klunks
end

function CurrencyService.HasEnough(player: Player, amount: number): boolean
	if not Validate.IsInteger(amount, 0, MAX_BALANCE) then
		return false
	end
	local data = getVerifiedData(player)
	return data ~= nil and data.Klunks >= amount
end

function CurrencyService.AddKlunks(player: Player, amount: number): (boolean, string?)
	if not Validate.IsInteger(amount, 1, MAX_BALANCE) then
		return false, CurrencyService.Errors.InvalidAmount
	end
	local data, err = getVerifiedData(player)
	if data == nil then
		return false, err
	end
	if data.Klunks + amount > MAX_BALANCE then
		return false, CurrencyService.Errors.BalanceCap
	end

	local stats = data.Stats
	if type(stats) == "table" and Validate.IsFiniteNumber(stats.TotalKlunksEarned) then
		stats.TotalKlunksEarned += amount
	end
	data.Klunks += amount

	CurrencyService.Changed:Fire(player, data.Klunks)
	return true, nil
end

function CurrencyService.RemoveKlunks(player: Player, amount: number): (boolean, string?)
	if not Validate.IsInteger(amount, 1, MAX_BALANCE) then
		return false, CurrencyService.Errors.InvalidAmount
	end
	local data, err = getVerifiedData(player)
	if data == nil then
		return false, err
	end
	if data.Klunks < amount then
		return false, CurrencyService.Errors.InsufficientKlunks
	end

	data.Klunks -= amount

	CurrencyService.Changed:Fire(player, data.Klunks)
	return true, nil
end

return CurrencyService
