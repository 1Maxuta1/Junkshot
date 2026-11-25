--!strict
--[[
	Remotes: the single registry of every RemoteEvent / RemoteFunction.

	Server: call Remotes.Init() once at startup. It creates ReplicatedStorage.Remotes and the
	        remotes below, reusing anything that already exists (it never duplicates).
	Both:   Remotes.GetEvent(name) / Remotes.GetFunction(name) return the remote and raise a
	        clear error if it is missing or has the wrong class.

	To add a remote: add it to `definitions` and nothing else. RemoteFunctions are only ever
	called client -> server; the server never invokes a client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 15

-- name -> class name
local definitions: { [string]: string } = {
	GetSnapshot = "RemoteFunction", -- client -> server: read-only snapshot of own data
	DataChanged = "RemoteEvent", -- server -> client: incremental updates to own data
	Notify = "RemoteEvent", -- server -> client: short message text for the local player
	ThrowRequest = "RemoteEvent", -- client -> server: (uid, aimTarget) throw one carried junk
	ThrowFx = "RemoteEvent", -- server -> clients: a validated throw to draw locally (Types.ThrowFx)
	-- Machine requests always act on the CALLER's own machine; no machine id is ever accepted.
	MachineRecycle = "RemoteEvent", -- client -> server: (uid) recycle one carried item
	MachineCraft = "RemoteEvent", -- client -> server: (recipeId) craft from carried items
	MachineMythic = "RemoteEvent", -- client -> server: (uidA, uidB, uidC) mythic crafting
	MachineAccelerate = "RemoteEvent", -- client -> server: () one click = minus one second
	MachineTake = "RemoteEvent", -- client -> server: (uid) move a finished item into the hands
	MachineUpgrade = "RemoteEvent", -- client -> server: (upgradeId) buy the next level
	-- Machine state needs no remote: it is published as attributes on each machine model.
	-- Functional items (PlacementService). Actions ON placed objects go through their prompts.
	ItemPlace = "RemoteEvent", -- client -> server: (uid, groundPosition, yaw) place a carried item
	ItemUse = "RemoteEvent", -- client -> server: (uid) use a carried item (detector scan)
	ItemFx = "RemoteEvent", -- server -> client: result of a use (e.g. detector signal)
	VehicleSwitch = "RemoteEvent", -- client -> server: () move to the other seat of the vehicle
	VehicleInput = "RemoteEvent", -- client -> server: (throttle, steer) in [-1, 1], driver only
	-- Economy (Stage 3). Prices, totals and results are always decided on the server; the
	-- request id (a GUID made by the client) only makes a repeated request a no-op.
	SellItems = "RemoteEvent", -- client -> server: (requestId, { uid }) sell at the Scrap Dealer
	ShopBuy = "RemoteEvent", -- client -> server: (requestId, entryId) buy a shop entry
	PlayerUpgradeBuy = "RemoteEvent", -- client -> server: (requestId, upgradeId) next level
	StorageMove = "RemoteEvent", -- client -> server: ("Store" | "Take", uid) hands <-> base storage
	EconomyFx = "RemoteEvent", -- server -> client: { Kind, Amount?, Reason?, Text? } feedback
	-- Bases (Stage 4). Always the CALLER's own base; no base / plot id is ever accepted.
	BaseAction = "RemoteEvent", -- client -> server: (requestId, action, slotId?, buildingId?)
	SaveSettings = "RemoteEvent", -- client -> server: ({ Music, Sfx, Muted }) audio settings
	AudioCue = "RemoteEvent", -- server -> client: (cueName) a short sound for that player
	AbilityFx = "RemoteEvent", -- server -> clients: { Effect, UserId, Position, Direction } comet / starfall
	OnboardingSkip = "RemoteEvent", -- client -> server: () ends the tutorial
	DailyClaim = "RemoteEvent", -- client -> server: ("Reward" | "Quest" | "Weekly", index?)
	HoldItem = "RemoteEvent", -- client -> server: (uid | "") the selected carried item, shown in the hand
	TradeAction = "RemoteEvent", -- client -> server: (action, a?, b?) Trade Station; see TradeService
	TradeState = "RemoteEvent", -- server -> client: invite / session / closed
	-- Cosmetics and monetization (no remote can grant anything; ownership is server-verified).
	CosmeticEquip = "RemoteEvent", -- client -> server: (category, cosmeticId | "") equip an OWNED cosmetic
}

local Remotes = {}

Remotes.Definitions = table.freeze(definitions)

local function createRemote(className: string, name: string): Instance
	local remote: Instance
	if className == "RemoteEvent" then
		remote = Instance.new("RemoteEvent")
	elseif className == "RemoteFunction" then
		remote = Instance.new("RemoteFunction")
	else
		error(`[Remotes] Unsupported remote class "{className}" for "{name}"`)
	end
	remote.Name = name
	return remote
end

-- Server only. Safe to call more than once.
function Remotes.Init(): Folder
	assert(RunService:IsServer(), "[Remotes] Init() must be called on the server")

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local folder: Folder
	local isNew = false

	if existing == nil then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		isNew = true
	elseif existing:IsA("Folder") then
		folder = existing
	else
		error(`[Remotes] ReplicatedStorage.{FOLDER_NAME} exists but is a {existing.ClassName}, expected Folder`)
	end

	for name, className in definitions do
		local remote = folder:FindFirstChild(name)
		if remote == nil then
			local created = createRemote(className, name)
			created.Parent = folder
		elseif remote.ClassName ~= className then
			error(`[Remotes] "{name}" exists as {remote.ClassName}, expected {className}`)
		end
	end

	-- Parent last so clients never see a half-filled folder.
	if isNew then
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function waitForRemote(name: string, className: string): Instance
	if definitions[name] ~= className then
		error(`[Remotes] "{name}" is not a defined {className}`)
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	if folder == nil then
		error(`[Remotes] ReplicatedStorage.{FOLDER_NAME} not found (did the server call Remotes.Init()?)`)
	end
	local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
	if remote == nil then
		error(`[Remotes] Remote "{name}" not found in {FOLDER_NAME}`)
	end
	return remote
end

function Remotes.GetEvent(name: string): RemoteEvent
	local remote = waitForRemote(name, "RemoteEvent")
	if not remote:IsA("RemoteEvent") then
		error(`[Remotes] "{name}" is a {remote.ClassName}, expected RemoteEvent`)
	end
	return remote
end

function Remotes.GetFunction(name: string): RemoteFunction
	local remote = waitForRemote(name, "RemoteFunction")
	if not remote:IsA("RemoteFunction") then
		error(`[Remotes] "{name}" is a {remote.ClassName}, expected RemoteFunction`)
	end
	return remote
end

return Remotes
