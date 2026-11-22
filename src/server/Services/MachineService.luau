--!strict
--[[
	MachineService: server-authoritative Recycling Machines (one or more, found by tag).

	Lifecycle of one cycle (one processing slot per machine):
	  Idle
	    --TryInsert(player, machineId, uid)--> validated, then WITHOUT yielding:
	        CarryService.TakeByUid (the junk leaves the carry list: consumed exactly once)
	        RewardService.Roll      (rarity + item decided now, kept server-side)
	  AcceptingItem  (InsertDuration)  input slot opens, junk goes in
	  Processing     (ProcessDuration)
	  RewardReady    reward delivered to the owner's saved inventory (InventoryService gives it
	                 its unique uid) and revealed; after RevealDuration -> Idle.
	                 If delivery fails (inventory full / data unavailable) the reward stays in
	                 the output tray for its owner: MachineClaim retries it, and it is also
	                 delivered automatically when the owner leaves. The machine stays busy
	                 until then, so a reward is never dropped.

	Safety
	  - One cycle at a time; inserts while busy are rejected. Every timer carries the cycle
	    number and does nothing if the machine has moved on.
	  - The reward is rolled and delivered on the server only, at most once (Delivered flag).
	  - The owner leaving at ANY point: DataService.OnBeforeRelease delivers the rolled reward
	    into their profile before it is saved, so the consumed junk is never lost and the
	    reward is never duplicated. Death changes nothing (the reward goes to the inventory).

	Replication: the machine model's attributes are the public state (State, OwnerUserId,
	OwnerName, InputJunkId, RewardItemId, RewardRarity, RewardDelivered, PhaseStartedAt
	(server time), PhaseDuration). Clients animate from these; no polling, no extra remote.

	Public API (server only)
	  TryInsert(player, machineId, uid) -> (ok, errorCode?)
	  TryClaim(player, machineId)       -> (ok, errorCode?)
	  GetState(machineId) -> MachineState?
	  StateChanged  Signal (machineId, state)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local RewardService = require(script.Parent.RewardService)

type MachineState = Types.MachineState

type Machine = {
	Id: string,
	Model: Model,
	Anchor: BasePart,
	State: MachineState,
	Cycle: number,
	Owner: Player?, -- nil once the owner has left
	OwnerUserId: number,
	Input: Types.CarriedJunk?,
	RewardItemId: string?,
	RewardRarity: string?,
	Delivered: boolean,
}

local ANCHOR_NAME = "PromptAnchor"
local CLAIMED_REVEAL = 2 -- seconds the reward stays visible after a late claim

local MachineService = {}

MachineService.Errors = table.freeze({
	InvalidArguments = "InvalidArguments",
	UnknownMachine = "UnknownMachine",
	Busy = "Busy",
	DataUnavailable = "DataUnavailable",
	NoCharacter = "NoCharacter",
	TooFar = "TooFar",
	NotCarried = "NotCarried",
	NotOwner = "NotOwner",
	NothingToClaim = "NothingToClaim",
})

MachineService.StateChanged = Signal.new() -- (machineId: string, state: MachineState)

local started = false
local machines: { [string]: Machine } = {}

---------------------------------------------------------------------------------------------
-- State publishing
---------------------------------------------------------------------------------------------

local function setPhase(machine: Machine, state: MachineState, duration: number)
	machine.State = state
	local model = machine.Model
	model:SetAttribute("State", state)
	model:SetAttribute("PhaseStartedAt", Workspace:GetServerTimeNow())
	model:SetAttribute("PhaseDuration", duration)
	MachineService.StateChanged:Fire(machine.Id, state)
end

local function resetToIdle(machine: Machine)
	machine.Cycle += 1 -- invalidates every pending timer of the finished cycle
	machine.Owner = nil
	machine.OwnerUserId = 0
	machine.Input = nil
	machine.RewardItemId = nil
	machine.RewardRarity = nil
	machine.Delivered = false
	local model = machine.Model
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("InputJunkId", "")
	model:SetAttribute("RewardItemId", "")
	model:SetAttribute("RewardRarity", "")
	model:SetAttribute("RewardDelivered", false)
	setPhase(machine, "Idle", 0)
end

-- Runs fn after `delay` seconds unless the machine has started another cycle meanwhile.
local function schedule(machine: Machine, delay: number, fn: () -> ())
	local cycle = machine.Cycle
	task.delay(delay, function()
		if machine.Cycle == cycle then
			fn()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Reward delivery
---------------------------------------------------------------------------------------------

-- Delivers the rolled reward to `player` once. Returns true if it is (now) delivered.
local function deliver(machine: Machine, player: Player): boolean
	if machine.Delivered then
		return true
	end
	local itemId = machine.RewardItemId
	if itemId == nil then
		return false
	end
	local uid, err = RewardService.Deliver(player, itemId)
	if uid == nil then
		warn(`[MachineService] could not deliver {itemId} to {player.Name}: {tostring(err)}`)
		return false
	end
	machine.Delivered = true
	machine.Model:SetAttribute("RewardDelivered", true)
	return true
end

local function revealThenIdle(machine: Machine, seconds: number)
	schedule(machine, seconds, function()
		resetToIdle(machine)
	end)
end

local function complete(machine: Machine)
	local model = machine.Model
	local owner = machine.Owner
	if owner ~= nil and owner.Parent == Players then
		deliver(machine, owner)
	end
	model:SetAttribute("RewardItemId", machine.RewardItemId or "")
	model:SetAttribute("RewardRarity", machine.RewardRarity or "")

	if machine.Delivered then
		setPhase(machine, "RewardReady", MachineConfig.RevealDuration)
		revealThenIdle(machine, MachineConfig.RevealDuration)
	elseif owner ~= nil and owner.Parent == Players then
		-- Hold the reward in the tray for its owner (duration 0 = until claimed).
		setPhase(machine, "RewardReady", 0)
		CarryService.Notify(owner, "Your inventory can't take the reward right now - claim it at the machine")
	else
		-- Owner gone and the leave-time delivery failed as well: nothing can hold it any longer.
		warn(`[MachineService] reward {tostring(machine.RewardItemId)} for user {machine.OwnerUserId} could not be delivered`)
		setPhase(machine, "RewardReady", MachineConfig.RevealDuration)
		revealThenIdle(machine, MachineConfig.RevealDuration)
	end
end

---------------------------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------------------------

local function isMachineId(value: any): boolean
	return Validate.IsString(value, 1, 32) and string.match(value, "^[%w_]+$") ~= nil
end

function MachineService.TryInsert(player: Player, machineId: any, uid: any): (boolean, string?)
	if not isMachineId(machineId) or not Validate.IsUid(uid) then
		return false, MachineService.Errors.InvalidArguments
	end
	local machine = machines[machineId]
	if machine == nil then
		return false, MachineService.Errors.UnknownMachine
	end
	if machine.State ~= "Idle" then
		return false, MachineService.Errors.Busy
	end
	if not DataService.IsLoaded(player) then
		return false, MachineService.Errors.DataUnavailable -- the reward could not be saved
	end
	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return false, MachineService.Errors.NoCharacter
	end
	local maxDistance = MachineConfig.PromptDistance + MachineConfig.DistanceTolerance
	if (root.Position - machine.Anchor.Position).Magnitude > maxDistance then
		return false, MachineService.Errors.TooFar
	end
	if not CarryService.HasUid(player, uid) then
		return false, MachineService.Errors.NotCarried
	end

	-- Validated. From here on nothing yields, so no second request can interleave.
	local record = CarryService.TakeByUid(player, uid)
	if record == nil then
		return false, MachineService.Errors.NotCarried
	end
	local itemId, rarity = RewardService.Roll()

	machine.Cycle += 1
	machine.Owner = player
	machine.OwnerUserId = player.UserId
	machine.Input = record
	machine.RewardItemId = itemId
	machine.RewardRarity = rarity
	machine.Delivered = false

	local model = machine.Model
	model:SetAttribute("Cycle", machine.Cycle) -- lets clients reveal each cycle's reward once
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("InputJunkId", record.Id)
	model:SetAttribute("RewardItemId", "") -- revealed only when ready
	model:SetAttribute("RewardRarity", "")
	model:SetAttribute("RewardDelivered", false)
	setPhase(machine, "AcceptingItem", MachineConfig.InsertDuration)

	schedule(machine, MachineConfig.InsertDuration, function()
		setPhase(machine, "Processing", MachineConfig.ProcessDuration)
		schedule(machine, MachineConfig.ProcessDuration, function()
			complete(machine)
		end)
	end)
	return true, nil
end

function MachineService.TryClaim(player: Player, machineId: any): (boolean, string?)
	if not isMachineId(machineId) then
		return false, MachineService.Errors.InvalidArguments
	end
	local machine = machines[machineId]
	if machine == nil then
		return false, MachineService.Errors.UnknownMachine
	end
	if machine.State ~= "RewardReady" or machine.Delivered then
		return false, MachineService.Errors.NothingToClaim
	end
	if machine.Owner ~= player then
		return false, MachineService.Errors.NotOwner
	end
	if not deliver(machine, player) then
		CarryService.Notify(player, "Your inventory is still full")
		return false, MachineService.Errors.DataUnavailable
	end
	setPhase(machine, "RewardReady", CLAIMED_REVEAL)
	revealThenIdle(machine, CLAIMED_REVEAL)
	return true, nil
end

function MachineService.GetState(machineId: string): MachineState?
	local machine = machines[machineId]
	return if machine ~= nil then machine.State else nil
end

---------------------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------------------

local function addPrompt(anchor: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RecyclePrompt"
	prompt.ActionText = "Recycle"
	prompt.ObjectText = "Recycling Machine"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MachineConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	-- Own key + AlwaysShow: junk prompts (E / X) nearby can never hide or steal this one.
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.KeyboardKeyCode = GameConfig.Input.MachineKey
	prompt.GamepadKeyCode = GameConfig.Input.MachineGamepadKey
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by UI/PickupPrompt
	-- The client opens the machine panel on trigger; the server acts only on MachineInsert.
	prompt:SetAttribute("PromptKind", "Machine")
	prompt.Parent = anchor
end

local function register(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(Workspace) then
		return
	end
	local id = instance:GetAttribute("MachineId")
	if not isMachineId(id) then
		warn(`[MachineService] {instance:GetFullName()} has no valid MachineId attribute`)
		return
	end
	if machines[id] ~= nil then
		warn(`[MachineService] duplicate MachineId "{id}"`)
		return
	end
	local anchor = instance:FindFirstChild(ANCHOR_NAME, true)
	if anchor == nil or not anchor:IsA("BasePart") then
		warn(`[MachineService] machine "{id}" has no {ANCHOR_NAME} part`)
		return
	end

	local machine: Machine = {
		Id = id,
		Model = instance,
		Anchor = anchor,
		State = "Idle",
		Cycle = 0,
		Owner = nil,
		OwnerUserId = 0,
		Input = nil,
		RewardItemId = nil,
		RewardRarity = nil,
		Delivered = false,
	}
	machines[id] = machine
	addPrompt(anchor)
	resetToIdle(machine)
end

-- A leaving owner gets their rolled reward written into the profile before it is saved.
local function onBeforeRelease(player: Player)
	for _, machine in machines do
		if machine.Owner == player then
			machine.Owner = nil
			if machine.State ~= "Idle" and machine.RewardItemId ~= nil then
				local wasDelivered = machine.Delivered
				if deliver(machine, player) and not wasDelivered then
					print(`[MachineService] {player.Name} left during a {machine.State} cycle; reward {machine.RewardItemId} saved to their inventory`)
					if machine.State == "RewardReady" then
						-- It was held in the tray waiting for a claim; the machine can move on.
						revealThenIdle(machine, CLAIMED_REVEAL)
					end
				end
			end
		end
	end
end

function MachineService.Start()
	assert(not started, "[MachineService] Start() called twice")
	started = true

	for _, instance in CollectionService:GetTagged(MachineConfig.Tag) do
		register(instance)
	end
	CollectionService:GetInstanceAddedSignal(MachineConfig.Tag):Connect(register)
	if next(machines) == nil then
		warn(`[MachineService] no machine found (Models tagged "{MachineConfig.Tag}")`)
	end

	DataService.OnBeforeRelease(onBeforeRelease)

	local function reportFailure(player: Player, err: string?)
		if err == MachineService.Errors.Busy then
			CarryService.Notify(player, "The machine is busy - wait a moment")
		elseif err == MachineService.Errors.TooFar then
			CarryService.Notify(player, "Get closer to the machine")
		elseif err == MachineService.Errors.NotCarried then
			CarryService.Notify(player, "You are not carrying that junk any more")
		elseif err == MachineService.Errors.DataUnavailable then
			CarryService.Notify(player, "Your data is still loading - try again")
		end
	end

	RemoteGuard.ConnectEvent(Remotes.GetEvent("MachineInsert"), {
		Name = "MachineInsert",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.MachineInsert,
		Validate = function(machineId: any, uid: any): boolean
			return isMachineId(machineId) and Validate.IsUid(uid)
		end,
	}, function(player: Player, machineId: string, uid: string)
		local ok, err = MachineService.TryInsert(player, machineId, uid)
		if not ok then
			reportFailure(player, err)
		end
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("MachineClaim"), {
		Name = "MachineClaim",
		MaxArgs = 1,
		RateLimit = GameConfig.RateLimits.MachineClaim,
		Validate = isMachineId,
	}, function(player: Player, machineId: string)
		MachineService.TryClaim(player, machineId)
	end)
end

return MachineService
