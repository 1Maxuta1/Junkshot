--!strict
--[[
	DataController: a READ-ONLY client mirror of the player's own Klunks and items.

	The server owns all data. This module only displays what the server sends:
	  1. waits for the server to mark the player as loaded (Player attribute "DataLoaded")
	  2. listens to DataChanged (events that arrive before the snapshot are buffered)
	  3. requests one snapshot via GetSnapshot, then replays buffered events newer than it

	Other client code (future HUD / inventory UI) reads from here:
	  DataController.GetKlunks(), GetItems(), IsReady(), and DataController.Changed:Connect(fn)

	Nothing in here can change real data; editing these values on the client has no effect.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local SNAPSHOT_ATTEMPTS = 3
local SNAPSHOT_RETRY_DELAY = 2

local localPlayer = Players.LocalPlayer

local DataController = {}

DataController.Changed = Signal.new() -- fires with no arguments after any update

local klunks = 0
local items: { [string]: Types.ItemRecord } = {}
local ready = false
local lastSeq = 0
local pending: { Types.DataChange } = {}

local function applyChange(change: Types.DataChange)
	if change.Seq <= lastSeq then
		return -- older than what we already have
	end
	lastSeq = change.Seq

	if change.Kind == "Klunks" then
		klunks = change.Klunks
	elseif change.Kind == "ItemAdded" then
		items[change.Uid] = { id = change.Id, acquiredAt = change.AcquiredAt }
	elseif change.Kind == "ItemRemoved" then
		items[change.Uid] = nil
	end

	DataController.Changed:Fire()
end

local function requestSnapshot(): Types.DataSnapshot?
	local getSnapshot = Remotes.GetFunction("GetSnapshot")
	for attempt = 1, SNAPSHOT_ATTEMPTS do
		local ok, result = pcall(function(): any
			return getSnapshot:InvokeServer()
		end)
		if ok and result ~= nil then
			return result
		end
		if attempt < SNAPSHOT_ATTEMPTS then
			task.wait(SNAPSHOT_RETRY_DELAY)
		end
	end
	return nil
end

function DataController.Start()
	-- Must not yield (see Main.client): do all waiting inside a spawned task.
	task.spawn(function()
		while localPlayer:GetAttribute("DataLoaded") ~= true do
			localPlayer:GetAttributeChangedSignal("DataLoaded"):Wait()
		end

		-- Connect BEFORE requesting the snapshot so no change can be missed in between.
		Remotes.GetEvent("DataChanged").OnClientEvent:Connect(function(change: Types.DataChange)
			if not ready then
				table.insert(pending, change)
				return
			end
			applyChange(change)
		end)

		local snapshot = requestSnapshot()
		if snapshot == nil then
			warn("[DataController] could not get a data snapshot from the server")
			return
		end

		klunks = snapshot.Klunks
		items = snapshot.Items
		lastSeq = snapshot.Seq
		ready = true

		for _, change in pending do
			applyChange(change)
		end
		table.clear(pending)

		DataController.Changed:Fire()
		print(`[DataController] ready: {KlunksFormat.Format(klunks)}`)
	end)
end

function DataController.IsReady(): boolean
	return ready
end

function DataController.GetKlunks(): number
	return klunks
end

-- A copy; modifying it does not affect the mirror.
function DataController.GetItems(): { [string]: Types.ItemRecord }
	local copy: { [string]: Types.ItemRecord } = {}
	for uid, record in items do
		copy[uid] = { id = record.id, acquiredAt = record.acquiredAt }
	end
	return copy
end

return DataController
