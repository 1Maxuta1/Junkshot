--!strict
--[[
	StorageService: moves items between the hands (CarryService) and the base storage
	(InventoryService). The item keeps its uid; it is MOVED, never copied.

	  Move(player, "Store" | "Take", uid) -> (ok, code?)
	    Only while standing at your own base chest (BaseService; storage lives at your base, so the hand
	    limit still matters out in the yard). Store needs a free storage slot, Take a free hand.
	    Remove-then-add happens in one step without yielding; if the second half fails the item
	    goes straight back where it was.

	It also wires the "one uid, one place" rule across systems: stored uids count as active
	for CarryService (JunkService.RegisterUidSource) and InventoryService refuses uids that are
	in hands, in the world or placed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local JunkService = require(script.Parent.JunkService)
local BaseService = require(script.Parent.BaseService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local StorageService = {}

StorageService.Errors = table.freeze({
	InvalidArguments = "InvalidArguments",
	NotAtBase = "NotAtBase",
	NotCarried = "NotCarried",
	NotStored = "NotStored",
	StorageFull = "StorageFull",
	HandsFull = "HandsFull",
})

local MESSAGES: { [string]: string } = {
	NotAtBase = "Use your chest at your base for that",
	StorageFull = "Your chest is full - upgrade it at your base",
	HandsFull = "Your hands are full",
}

local started = false

-- Stage 4: the storage is the base chest, so items move in / out standing at YOUR chest.
function StorageService.IsAtBase(player: Player): boolean
	return BaseService.IsNearChest(player)
end

function StorageService.Move(player: Player, action: any, uid: any): (boolean, string?)
	if (action ~= "Store" and action ~= "Take") or not Validate.IsUid(uid) then
		return false, StorageService.Errors.InvalidArguments
	end
	if not StorageService.IsAtBase(player) then
		return false, StorageService.Errors.NotAtBase
	end
	if action == "Store" then
		if not CarryService.HasUid(player, uid) then
			return false, StorageService.Errors.NotCarried
		end
		if (InventoryService.GetItemCount(player) or math.huge) >= InventoryService.GetCapacity(player) then
			return false, StorageService.Errors.StorageFull
		end
		local item = CarryService.TakeByUid(player, uid)
		if item == nil then
			return false, StorageService.Errors.NotCarried
		end
		local stored, code = InventoryService.AddItem(player, item.Id, item.Uid)
		if stored == nil then
			CarryService.AddJunk(player, item.Id, item.Uid) -- put it back
			return false, code
		end
		return true, nil
	end

	local record = InventoryService.GetItem(player, uid)
	if record == nil then
		return false, StorageService.Errors.NotStored
	end
	if CarryService.IsFull(player) then
		return false, StorageService.Errors.HandsFull
	end
	InventoryService.RemoveItem(player, uid)
	local taken, code = CarryService.AddJunk(player, record.id, uid)
	if not taken then
		InventoryService.AddItem(player, record.id, uid) -- put it back
		return false, code
	end
	return true, nil
end

function StorageService.Start()
	assert(not started, "[StorageService] Start() called twice")
	started = true

	JunkService.RegisterUidSource(InventoryService.IsUidStored)
	InventoryService.SetUidGuard(function(uid: string): boolean
		return CarryService.IsUidCarried(uid) or JunkService.IsUidActive(uid)
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("StorageMove"), {
		Name = "StorageMove",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.StorageMove,
		Validate = function(action: any, uid: any): boolean
			return (action == "Store" or action == "Take") and Validate.IsUid(uid)
		end,
	}, function(player: Player, action: string, uid: string)
		local ok, code = StorageService.Move(player, action, uid)
		if not ok and code ~= nil and MESSAGES[code] ~= nil then
			EconomyService.Message(player, MESSAGES[code], "Warning")
		end
	end)
end

return StorageService
