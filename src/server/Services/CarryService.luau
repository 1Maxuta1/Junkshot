--!strict
--[[
	CarryService: the server-side carry list (GameConfig.Carry.MaxJunk items per player, more with
	the Bigger Backpack upgrade: GetCapacity).

	Design
	  - The list holds Types.CarriedJunk records { Uid, Id } of ANY catalog item (ItemConfig).
	    A picked-up object leaves the world and keeps its Uid; when it is thrown or dropped it is
	    re-created from that record, so one object can never exist twice.
	  - The list is SAVED in the profile (ProfileData.Carry) on every change and restored when
	    the player's data loads; nothing can be carried before that. Leaving the game keeps the
	    items with the player.
	  - A Uid can be owned by one place only: one player's list, or the world. AddJunk and
	    TryPickup refuse anything else. Objects reserved for another player (a machine's
	    output tray) cannot be picked up.
	  - Pickup is validated here, never trusted from the client: player alive, junk still
	    available, distance to the junk, carry capacity, per-player cooldown.
	  - The list is published as the Player attribute "CarryList": "uid:id,uid:id" (oldest
	    first). Attributes replicate to every client and only when they change, so each client
	    can draw junk on any player's back by itself (client CarryController) and the HUD can
	    show the local list. No remote and no server-side visuals are needed for that.
	  - If a player dies, the carried items are dropped on the ground where they were (anyone can
	    take them). A death with no ground within reach (a void) loses them.

	Public API (server only)
	  TryPickup(player, junk)     -> (ok, errorCode?)   used by the prompt handler
	  AddJunk(player, id, uid?)   -> (ok, errorCode?)
	  TakeByUid(player, uid)      -> CarriedJunk?       removes one record (used by throwing)
	  PopTop(player)              -> CarriedJunk?       last picked up, first out
	  GetCarried(player)          -> copy of the list, GetCount, IsFull, HasUid
	  Clear(player)               empties the list without dropping
	  DropAll(player, pos?)       empties the list and puts the junk on the ground near pos
	  GetLiveRoot(player)         -> BasePart?          root part of a living character
	  Notify(player, message)     rate-limited short message to that player
	  Changed                     Signal (player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local DataService = require(script.Parent.DataService)
local JunkService = require(script.Parent.JunkService)

type CarriedJunk = Types.CarriedJunk

local LIST_ATTRIBUTE = "CarryList"
local NOTIFY_INTERVAL = 1 -- seconds between identical messages per player
local DROP_RING_RADIUS = 2.5

local CarryService = {}

CarryService.Errors = table.freeze({
	NoState = "NoState",
	NoCharacter = "NoCharacter",
	Cooldown = "Cooldown",
	JunkGone = "JunkGone",
	NotReady = "NotReady",
	TooFar = "TooFar",
	CarryFull = "CarryFull",
	InvalidJunkId = "InvalidJunkId",
	UnknownJunk = "UnknownJunk",
	InvalidUid = "InvalidUid",
	UidInUse = "UidInUse",
	Reserved = "Reserved",
})

CarryService.Changed = Signal.new() -- (player: Player)
CarryService.ItemAdded = Signal.new() -- (player: Player, itemId: string, uid: string) entered the hands

local started = false
local notifyRemote: RemoteEvent? = nil

-- Upgrades (PlayerUpgradeService) plug in here; without them the GameConfig values apply.
local capacityBonus: ((Player) -> number)? = nil
local pickupRange: ((Player) -> number)? = nil

function CarryService.SetCapacityBonusProvider(provider: (Player) -> number)
	capacityBonus = provider
end

function CarryService.SetPickupRangeProvider(provider: (Player) -> number)
	pickupRange = provider
end

-- How many items this player can carry (GameConfig.Carry.MaxJunk + Bigger Backpack).
function CarryService.GetCapacity(player: Player): number
	local bonus = if capacityBonus ~= nil then capacityBonus(player) else 0
	return GameConfig.Carry.MaxJunk + bonus
end

-- Studs from which this player may pick things up (Grabber Arm upgrade).
function CarryService.GetPickupRange(player: Player): number
	return if pickupRange ~= nil then pickupRange(player) else GameConfig.Junk.PickupMaxDistance
end

local carried: { [Player]: { CarriedJunk } } = {}
local ownerByUid: { [string]: Player } = {}
local lastPickupAt: { [Player]: number } = {}
local lastNotify: { [Player]: { Text: string, At: number } } = {}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function publish(player: Player)
	local list = carried[player]
	local value: string? = nil
	if list ~= nil and #list > 0 then
		local parts = table.create(#list)
		for index, entry in list do
			parts[index] = `{entry.Uid}:{entry.Id}`
		end
		value = table.concat(parts, ",")
	end
	player:SetAttribute(LIST_ATTRIBUTE, value)
	player:SetAttribute("CarryMax", CarryService.GetCapacity(player))
	-- Saved with the profile (ProfileStore auto-saves; the session ends with a final save).
	local data = DataService.GetData(player)
	if data ~= nil and list ~= nil then
		local saved = table.create(#list)
		for index, entry in list do
			saved[index] = { Uid = entry.Uid, Id = entry.Id }
		end
		data.Carry = saved
	end
	CarryService.Changed:Fire(player)
end

local function insertRecord(player: Player, list: { CarriedJunk }, junkId: string, uid: string)
	table.insert(list, { Uid = uid, Id = junkId })
	ownerByUid[uid] = player
	publish(player)
	CarryService.ItemAdded:Fire(player, junkId, uid)
end

-- Re-publishes the list (e.g. after the capacity changed through an upgrade).
function CarryService.Refresh(player: Player)
	if carried[player] ~= nil then
		publish(player)
	end
end

local function removeAt(player: Player, list: { CarriedJunk }, index: number): CarriedJunk
	local entry = table.remove(list, index) :: CarriedJunk
	if ownerByUid[entry.Uid] == player then
		ownerByUid[entry.Uid] = nil
	end
	publish(player)
	return { Uid = entry.Uid, Id = entry.Id }
end

local function rootPosition(character: Model?): Vector3?
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

-- The player's root part, only if the character exists and is alive.
function CarryService.GetLiveRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Sends a short message to one player. The same text is sent at most once per second.
function CarryService.Notify(player: Player, message: string)
	local remote = notifyRemote
	if remote == nil or player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local last = lastNotify[player]
	if last ~= nil and last.Text == message and now - last.At < NOTIFY_INTERVAL then
		return
	end
	lastNotify[player] = { Text = message, At = now }
	remote:FireClient(player, message)
end

-- Adds junk directly (no world object involved). A new uid is generated when none is given.
function CarryService.AddJunk(player: Player, junkId: string, uid: string?): (boolean, string?)
	if not Validate.IsItemId(junkId) then
		return false, CarryService.Errors.InvalidJunkId
	end
	local definition = ItemConfig.Get(junkId)
	if definition == nil or definition.IsDebug == true then
		return false, CarryService.Errors.UnknownJunk
	end
	local list = carried[player]
	if list == nil then
		return false, CarryService.Errors.NoState
	end
	if #list >= CarryService.GetCapacity(player) then
		return false, CarryService.Errors.CarryFull
	end

	local finalUid = uid or JunkService.NewUid()
	if not Validate.IsUid(finalUid) then
		return false, CarryService.Errors.InvalidUid
	end
	if ownerByUid[finalUid] ~= nil or JunkService.IsUidActive(finalUid) then
		return false, CarryService.Errors.UidInUse
	end

	insertRecord(player, list, junkId, finalUid)
	return true, nil
end

-- Removes and returns the record with this uid, or nil if the player does not carry it.
function CarryService.TakeByUid(player: Player, uid: string): CarriedJunk?
	local list = carried[player]
	if list == nil then
		return nil
	end
	for index, entry in list do
		if entry.Uid == uid then
			return removeAt(player, list, index)
		end
	end
	return nil
end

-- Last picked up, first out. Returns nil when the player carries nothing.
function CarryService.PopTop(player: Player): CarriedJunk?
	local list = carried[player]
	if list == nil or #list == 0 then
		return nil
	end
	return removeAt(player, list, #list)
end

-- Copies: changing them does not change the real list.
function CarryService.GetCarried(player: Player): { CarriedJunk }
	local list = carried[player]
	local copy: { CarriedJunk } = {}
	if list ~= nil then
		for index, entry in list do
			copy[index] = { Uid = entry.Uid, Id = entry.Id }
		end
	end
	return copy
end

function CarryService.HasUid(player: Player, uid: string): boolean
	return ownerByUid[uid] == player
end

-- True when anyone on this server carries the uid.
function CarryService.IsUidCarried(uid: string): boolean
	return ownerByUid[uid] ~= nil
end

function CarryService.GetCount(player: Player): number
	local list = carried[player]
	return if list ~= nil then #list else 0
end

function CarryService.IsFull(player: Player): boolean
	return CarryService.GetCount(player) >= CarryService.GetCapacity(player)
end

function CarryService.Clear(player: Player)
	local list = carried[player]
	if list ~= nil and #list > 0 then
		for _, entry in list do
			if ownerByUid[entry.Uid] == player then
				ownerByUid[entry.Uid] = nil
			end
		end
		table.clear(list)
		publish(player)
	end
end

-- Empties the list and puts every carried object on the ground in a ring around `position`.
function CarryService.DropAll(player: Player, position: Vector3?)
	local list = carried[player]
	if list == nil or #list == 0 then
		return
	end

	local entries = table.clone(list)
	CarryService.Clear(player)

	if position == nil then
		warn(`[CarryService] {player.Name}: no position to drop {#entries} junk at, they are lost`)
		return
	end

	for index, entry in entries do
		local angle = (index / #entries) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * DROP_RING_RADIUS
		JunkService.SpawnAt(entry.Id, position + offset, {
			Uid = entry.Uid,
			Lifetime = GameConfig.Junk.DroppedLifetime,
		})
	end
end

-- Validates and performs a pickup. Returns (true, nil) or (false, errorCode).
function CarryService.TryPickup(player: Player, junk: any): (boolean, string?)
	local list = carried[player]
	if list == nil then
		return false, CarryService.Errors.NoState
	end

	local now = os.clock()
	local last = lastPickupAt[player]
	if last ~= nil and now - last < GameConfig.Carry.PickupCooldown then
		return false, CarryService.Errors.Cooldown
	end
	lastPickupAt[player] = now

	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return false, CarryService.Errors.NoCharacter
	end

	local junkPosition = JunkService.GetPosition(junk)
	if junkPosition == nil then
		return false, CarryService.Errors.JunkGone
	end
	if not JunkService.IsClaimable(junk) then
		return false, CarryService.Errors.NotReady -- still flying after a throw
	end
	if not JunkService.CanClaim(junk, player) then
		return false, CarryService.Errors.Reserved -- waiting on someone else's machine tray
	end

	local maxDistance = CarryService.GetPickupRange(player) + GameConfig.Carry.PickupDistanceTolerance
	if (root.Position - junkPosition).Magnitude > maxDistance then
		return false, CarryService.Errors.TooFar
	end

	if #list >= CarryService.GetCapacity(player) then
		CarryService.Notify(player, string.format("Carry full (%d/%d)", #list, CarryService.GetCapacity(player)))
		return false, CarryService.Errors.CarryFull
	end

	-- Everything is validated; from here on nothing yields, so nobody can interleave.
	local junkId, uid = JunkService.Claim(junk, player)
	if junkId == nil or uid == nil then
		return false, CarryService.Errors.JunkGone
	end
	if ownerByUid[uid] ~= nil then
		-- Cannot happen through normal play. The uid already exists with its owner, so the world
		-- copy is the duplicate: discard it instead of creating a second owner.
		warn(`[CarryService] uid {uid} was in the world and carried at the same time; world copy discarded`)
		return false, CarryService.Errors.UidInUse
	end
	insertRecord(player, list, junkId, uid)
	return true, nil
end

---------------------------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------------------------

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		CarryService.DropAll(player, rootPosition(character))
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(LIST_ATTRIBUTE, nil)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(hookCharacter, player, character)
	end)
	if player.Character ~= nil then
		task.spawn(hookCharacter, player, player.Character)
	end
end

-- Restores the saved list once the profile is loaded. Invalid, unknown, duplicate or
-- already-existing uids are dropped (never duplicated); at most MaxJunk entries are kept.
local function restore(player: Player)
	if carried[player] ~= nil then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local list: { CarriedJunk } = {}
	local saved = data.Carry
	if type(saved) == "table" then
		for _, entry in saved do
			if #list >= CarryService.GetCapacity(player) then
				break
			end
			local uid = if type(entry) == "table" then entry.Uid else nil
			local id = if type(entry) == "table" then entry.Id else nil
			local definition = if type(id) == "string" then ItemConfig.Get(id) else nil
			if Validate.IsUid(uid) and definition ~= nil and definition.IsDebug ~= true
				and ownerByUid[uid] == nil and not JunkService.IsUidActive(uid)
			then
				table.insert(list, { Uid = uid, Id = id })
				ownerByUid[uid] = player
			else
				warn(`[CarryService] {player.Name}: dropped an invalid saved carried item ({tostring(id)})`)
			end
		end
	end
	carried[player] = list
	publish(player)
end

local function onPlayerRemoving(player: Player)
	-- Nothing is dropped: the list is already saved in the profile and leaves with the player.
	local list = carried[player]
	if list ~= nil then
		for _, entry in list do
			if ownerByUid[entry.Uid] == player then
				ownerByUid[entry.Uid] = nil
			end
		end
	end
	carried[player] = nil
	lastPickupAt[player] = nil
	lastNotify[player] = nil
end

-- Restores the hands now if that has not happened yet (Signal handlers run in no fixed order,
-- so services that depend on the hands call this first). Safe to call any number of times.
function CarryService.EnsureRestored(player: Player)
	restore(player)
end

-- Drops the in-memory list and restores it from the saved profile, exactly like a rejoin.
-- Used by DevTests to verify persistence without leaving the server.
function CarryService.ReloadFromSave(player: Player)
	onPlayerRemoving(player)
	restore(player)
end

function CarryService.Start()
	assert(not started, "[CarryService] Start() called twice")
	started = true

	notifyRemote = Remotes.GetEvent("Notify")

	JunkService.PickupRequested:Connect(function(player: Player, junk: Model)
		-- The result is not needed here: CarryService reports what the player must know.
		CarryService.TryPickup(player, junk)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.PlayerLoaded:Connect(restore)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		if DataService.IsLoaded(player) then
			restore(player)
		end
	end
end

return CarryService
