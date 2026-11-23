--!strict
--[[
	InventoryService: the ONLY code allowed to add or remove a player's items.

	Items are unique instances: Items[uid] = { id, acquiredAt }. The uid (a GUID) is what
	later systems (stealing, crafting, trading) will reference. Item ids must exist in
	ItemConfig. Debug items (IsDebug) are refused outside Roblox Studio.

	Results:
	  AddItem    -> (uid: string?, errorCode: string?)   success: uid, nil   failure: nil, code
	  RemoveItem -> (success: boolean, errorCode: string?)
	Read functions return COPIES, so callers cannot mutate saved data by accident.
	Events: ItemAdded (player, uid, record), ItemRemoved (player, uid).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataService = require(script.Parent.DataService)

local UID_ATTEMPTS = 5

local InventoryService = {}

InventoryService.Errors = table.freeze({
	DataUnavailable = "DataUnavailable",
	CorruptData = "CorruptData",
	InvalidItemId = "InvalidItemId",
	UnknownItem = "UnknownItem",
	DebugItemNotAllowed = "DebugItemNotAllowed",
	InventoryFull = "InventoryFull",
	UidGenerationFailed = "UidGenerationFailed",
	InvalidUid = "InvalidUid",
	ItemNotFound = "ItemNotFound",
	UidInUse = "UidInUse",
})

InventoryService.ItemAdded = Signal.new() -- (player: Player, uid: string, record: ItemRecord)
InventoryService.ItemRemoved = Signal.new() -- (player: Player, uid: string)

local function copyRecord(record: Types.ItemRecord): Types.ItemRecord
	return { id = record.id, acquiredAt = record.acquiredAt }
end

-- The live Items table (internal use only; never return this to callers), or (nil, errorCode).
local function getLiveItems(player: Player): ({ [string]: Types.ItemRecord }?, string?)
	local data = DataService.GetData(player)
	if data == nil then
		return nil, InventoryService.Errors.DataUnavailable
	end
	if type(data.Items) ~= "table" then
		warn(`[InventoryService] {player.Name}: Items in profile is not a table`)
		return nil, InventoryService.Errors.CorruptData
	end
	return data.Items, nil
end

local function countItems(items: { [string]: Types.ItemRecord }): number
	local count = 0
	for _ in items do
		count += 1
	end
	return count
end

local function generateUid(items: { [string]: Types.ItemRecord }): string?
	for _ = 1, UID_ATTEMPTS do
		local uid = HttpService:GenerateGUID(false)
		if items[uid] == nil then
			return uid
		end
	end
	return nil
end

-- Optional hooks (set by StorageService / PlayerUpgradeService):
--   capacity(player) -> number    the player's storage limit (upgrade); MaxItems stays the hard cap
--   uidInUse(uid) -> boolean      the uid exists elsewhere (hands, world, placed objects)
local capacityProvider: ((Player) -> number)? = nil
local uidInUse: ((string) -> boolean)? = nil

function InventoryService.SetCapacityProvider(provider: (Player) -> number)
	capacityProvider = provider
end

function InventoryService.SetUidGuard(guard: (string) -> boolean)
	uidInUse = guard
end

function InventoryService.GetCapacity(player: Player): number
	local limit = GameConfig.Inventory.MaxItems
	if capacityProvider ~= nil then
		limit = math.min(limit, capacityProvider(player))
	end
	return limit
end

-- True when the uid is in ANY loaded player's storage (one item, one place).
function InventoryService.IsUidStored(uid: string): boolean
	for _, other in game:GetService("Players"):GetPlayers() do
		local data = DataService.GetData(other)
		if data ~= nil and type(data.Items) == "table" and data.Items[uid] ~= nil then
			return true
		end
	end
	return false
end

-- Adds an item to base storage. `uid` keeps the identity of an item that moves in from the
-- hands; without it a new uid is generated (a brand-new item, e.g. a shop purchase).
function InventoryService.AddItem(player: Player, itemId: string, uid: string?): (string?, string?)
	if not Validate.IsItemId(itemId) then
		return nil, InventoryService.Errors.InvalidItemId
	end
	local definition = ItemConfig.Get(itemId)
	if definition == nil then
		return nil, InventoryService.Errors.UnknownItem
	end
	if definition.IsDebug == true and not RunService:IsStudio() then
		return nil, InventoryService.Errors.DebugItemNotAllowed
	end

	local items, err = getLiveItems(player)
	if items == nil then
		return nil, err
	end
	if countItems(items) >= InventoryService.GetCapacity(player) then
		return nil, InventoryService.Errors.InventoryFull
	end

	local finalUid: string? = uid
	if finalUid ~= nil then
		if not Validate.IsUid(finalUid) then
			return nil, InventoryService.Errors.InvalidUid
		end
		if items[finalUid] ~= nil or InventoryService.IsUidStored(finalUid) or (uidInUse ~= nil and uidInUse(finalUid)) then
			return nil, InventoryService.Errors.UidInUse
		end
	else
		finalUid = generateUid(items)
		if finalUid == nil then
			return nil, InventoryService.Errors.UidGenerationFailed
		end
	end
	local newUid = finalUid :: string

	local record: Types.ItemRecord = { id = itemId, acquiredAt = os.time() }
	items[newUid] = record

	InventoryService.ItemAdded:Fire(player, newUid, copyRecord(record))
	return newUid, nil
end

function InventoryService.RemoveItem(player: Player, uid: string): (boolean, string?)
	if not Validate.IsUid(uid) then
		return false, InventoryService.Errors.InvalidUid
	end
	local items, err = getLiveItems(player)
	if items == nil then
		return false, err
	end
	if items[uid] == nil then
		return false, InventoryService.Errors.ItemNotFound
	end

	items[uid] = nil

	InventoryService.ItemRemoved:Fire(player, uid)
	return true, nil
end

-- Returns a copy of the record, or nil if the player does not own that uid.
function InventoryService.GetItem(player: Player, uid: string): Types.ItemRecord?
	if not Validate.IsUid(uid) then
		return nil
	end
	local items = getLiveItems(player)
	if items == nil then
		return nil
	end
	local record = items[uid]
	if record == nil then
		return nil
	end
	return copyRecord(record)
end

function InventoryService.HasItem(player: Player, uid: string): boolean
	return InventoryService.GetItem(player, uid) ~= nil
end

-- Returns nil when data is unavailable.
function InventoryService.GetItemCount(player: Player): number?
	local items = getLiveItems(player)
	if items == nil then
		return nil
	end
	return countItems(items)
end

-- How many items of one ItemConfig id the player owns. Returns nil when data is unavailable.
function InventoryService.CountByItemId(player: Player, itemId: string): number?
	local items = getLiveItems(player)
	if items == nil then
		return nil
	end
	local count = 0
	for _, record in items do
		if record.id == itemId then
			count += 1
		end
	end
	return count
end

-- A copy of the whole inventory (uid -> record). Returns nil when data is unavailable.
function InventoryService.GetAllItems(player: Player): { [string]: Types.ItemRecord }?
	local items = getLiveItems(player)
	if items == nil then
		return nil
	end
	local copy: { [string]: Types.ItemRecord } = {}
	for uid, record in items do
		copy[uid] = copyRecord(record)
	end
	return copy
end

return InventoryService
