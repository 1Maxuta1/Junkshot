--!strict
--[[
	CarryService: the server-side carry list (up to GameConfig.Carry.MaxJunk junk per player).

	Design
	  - The list holds Types.CarriedJunk records { Uid, Id } (runtime state, not saved). A
	    picked-up object leaves the world and keeps its Uid; when it is thrown or dropped it is
	    re-created from that record, so one object can never exist twice.
	  - A Uid can be owned by one place only: one player's list, or the world. AddJunk and
	    TryPickup refuse anything else.
	  - Pickup is validated here, never trusted from the client: player alive, junk still
	    available, distance to the junk, carry capacity, per-player cooldown.
	  - The list is published as the Player attribute "CarryList": "uid:id,uid:id" (oldest
	    first). Attributes replicate to every client and only when they change, so each client
	    can draw junk on any player's back by itself (client CarryController) and the HUD can
	    show the local list. No remote and no server-side visuals are needed for that.
	  - If a player dies, respawns or leaves, the carried junk is dropped on the ground where
	    they were. A death with no ground within reach (a void) loses the junk.

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
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
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
})

CarryService.Changed = Signal.new() -- (player: Player)

local started = false
local notifyRemote: RemoteEvent? = nil

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
	CarryService.Changed:Fire(player)
end

local function insertRecord(player: Player, list: { CarriedJunk }, junkId: string, uid: string)
	table.insert(list, { Uid = uid, Id = junkId })
	ownerByUid[uid] = player
	publish(player)
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
	if not JunkConfig.Exists(junkId) then
		return false, CarryService.Errors.UnknownJunk
	end
	local list = carried[player]
	if list == nil then
		return false, CarryService.Errors.NoState
	end
	if #list >= GameConfig.Carry.MaxJunk then
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

function CarryService.GetCount(player: Player): number
	local list = carried[player]
	return if list ~= nil then #list else 0
end

function CarryService.IsFull(player: Player): boolean
	return CarryService.GetCount(player) >= GameConfig.Carry.MaxJunk
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

	local maxDistance = GameConfig.Junk.PickupMaxDistance + GameConfig.Carry.PickupDistanceTolerance
	if (root.Position - junkPosition).Magnitude > maxDistance then
		return false, CarryService.Errors.TooFar
	end

	if #list >= GameConfig.Carry.MaxJunk then
		CarryService.Notify(player, string.format("Carry full (%d/%d)", #list, GameConfig.Carry.MaxJunk))
		return false, CarryService.Errors.CarryFull
	end

	-- Everything is validated; from here on nothing yields, so nobody can interleave.
	local junkId, uid = JunkService.Claim(junk)
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
	if carried[player] ~= nil then
		return
	end
	carried[player] = {}
	player:SetAttribute(LIST_ATTRIBUTE, nil)

	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(hookCharacter, player, character)
	end)
	-- Respawns without a death (e.g. LoadCharacter) must not keep junk on an invisible back.
	player.CharacterRemoving:Connect(function(character: Model)
		CarryService.DropAll(player, rootPosition(character))
	end)
	if player.Character ~= nil then
		task.spawn(hookCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	CarryService.DropAll(player, rootPosition(player.Character))
	carried[player] = nil
	lastPickupAt[player] = nil
	lastNotify[player] = nil
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
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CarryService
