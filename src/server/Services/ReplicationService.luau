--!strict
--[[
	ReplicationService: the only bridge between server-side data and a player's own client.

	  - GetSnapshot (RemoteFunction): returns the caller's Klunks + items. Nothing else
	    from the profile (Version, Stats, Settings) ever leaves the server.
	  - DataChanged (RemoteEvent): pushes each change to the owning player only.

	Every change carries a per-player Seq. The snapshot carries the Seq it was built at, so
	the client can ignore events older than its snapshot (remote events and function
	returns are not ordered relative to each other).

	Read-only: it listens to CurrencyService / InventoryService and never modifies data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local CurrencyService = require(script.Parent.CurrencyService)
local InventoryService = require(script.Parent.InventoryService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local ReplicationService = {}

local started = false
local seqByPlayer: { [Player]: number } = {}

local function nextSeq(player: Player): number
	local seq = (seqByPlayer[player] or 0) + 1
	seqByPlayer[player] = seq
	return seq
end

local function buildSnapshot(player: Player): Types.DataSnapshot?
	local klunks = CurrencyService.GetKlunks(player)
	local items = InventoryService.GetAllItems(player)
	if klunks == nil or items == nil then
		return nil -- data not loaded (yet): the client retries
	end
	return { Seq = seqByPlayer[player] or 0, Klunks = klunks, Items = items }
end

function ReplicationService.Start()
	assert(not started, "[ReplicationService] Start() called twice")
	started = true

	local getSnapshot = Remotes.GetFunction("GetSnapshot")
	local dataChanged = Remotes.GetEvent("DataChanged")

	local function send(player: Player, change: Types.DataChange)
		if player.Parent == Players then
			dataChanged:FireClient(player, change)
		end
	end

	RemoteGuard.BindFunction(getSnapshot, {
		Name = "GetSnapshot",
		MaxArgs = 0,
		RateLimit = GameConfig.RateLimits.GetSnapshot,
	}, function(player: Player): any
		return buildSnapshot(player)
	end)

	CurrencyService.Changed:Connect(function(player: Player, balance: number)
		send(player, { Seq = nextSeq(player), Kind = "Klunks", Klunks = balance })
	end)

	InventoryService.ItemAdded:Connect(function(player: Player, uid: string, record: Types.ItemRecord)
		send(player, {
			Seq = nextSeq(player),
			Kind = "ItemAdded",
			Uid = uid,
			Id = record.id,
			AcquiredAt = record.acquiredAt,
		})
	end)

	InventoryService.ItemRemoved:Connect(function(player: Player, uid: string)
		send(player, { Seq = nextSeq(player), Kind = "ItemRemoved", Uid = uid })
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		seqByPlayer[player] = nil
	end)
end

return ReplicationService
