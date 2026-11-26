--!strict
--[[
	MachineService: every player's PERSONAL Recycling / Crafting machine. One service manages
	all machines; each machine is keyed by its owner and isolated:

	  - Every request acts on the CALLER's own machine. No remote accepts a machine id, so a
	    player cannot insert into, accelerate, claim from or upgrade someone else's machine.
	  - State lives in the owner's profile (ProfileData.Machine, Types.MachineData) and is
	    saved with it. Times are Workspace:GetServerTimeNow() seconds, so a job keeps running
	    while the owner is offline and on any server.

	Machine data
	  Job       the running process { Kind, Label, StartedAt, Duration, Accelerated, Inputs,
	            RecipeId?, Result }. Result is decided WHEN THE JOB STARTS (no re-roll by
	            rejoining). Completion = StartedAt + Duration - Accelerated.
	  Output    finished items waiting for their owner (at most the Storage upgrade's slots;
	            a job can only start when its result has a free slot, so nothing is ever lost).
	  Upgrades  { Speed, Storage, Level } level indexes into MachineConfig.Upgrades.

	Lifecycle of an item through the machine
	  carried --(Recycle/Craft/Mythic: TakeByUid, validated, no yield)--> Job.Inputs
	  Job.Result --(completion)--> Output --(spawned on the tray as a normal world item, reserved
	  for the owner)--> carried (pick it up with E, or the panel's TAKE button). The tray object
	  is the ONE representation: picking it up removes it from Output in the same step
	  (JunkService OnClaimed). It is then an ordinary item: carried, thrown, recycled again.

	No loops: a single task.delay per running job (re-armed when accelerated) moves the result
	to Output while the owner is online; Load() does the same for jobs that finished offline.

	Public state for clients: attributes on the machine model (State, JobKind, JobLabel,
	JobStartedAt, JobCompletesAt, JobDuration, OutputCount, OutputCapacity, Upgrade*, ResultSeq,
	LastResultId, LastResultRarity, BoostUntil, InstantCredits, OwnerUserId, OwnerName).
	The rolled result of a running job is never published.

	Public API (server only)
	  Recycle(player, uid), Craft(player, recipeId), Mythic(player, uidA, uidB, uidC)
	  Accelerate(player), Take(player, uid), BuyUpgrade(player, upgradeId)
	      -> (ok, errorCode?)
	  InstantFinish(player) -> boolean, AddBoost(player, seconds), SetPermanentSpeed(player, on)
	  GetModel(player), GetData(player) (copy), GetRemaining(player)
	  Load(player), Unload(player)          (also used by DevTests to simulate a rejoin)
	  JobFinished  Signal (player, result: CarriedJunk)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local CarryService = require(script.Parent.CarryService)
local CraftingService = require(script.Parent.CraftingService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local JunkService = require(script.Parent.JunkService)
local PlotService = require(script.Parent.PlotService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local RewardService = require(script.Parent.RewardService)

type CarriedJunk = Types.CarriedJunk
type MachineData = Types.MachineData
type MachineJob = Types.MachineJob

type Machine = {
	Player: Player,
	UserId: number,
	Data: MachineData, -- the live table inside the profile
	Model: Model?,
	Anchor: BasePart?,
	OutputPoint: BasePart?,
	Token: number, -- invalidates the pending completion timer
	LastResultId: string,
}

local MACHINE_OFFSET = CFrame.new(0, 0, 6) -- from the plot pad's center (+Z = away from the plaza)
local OUTPUT_SPACING = 2.2

local MachineService = {}

MachineService.Errors = table.freeze({
	NoMachine = "NoMachine",
	InvalidArguments = "InvalidArguments",
	Busy = "Busy",
	OutputFull = "OutputFull",
	TooFar = "TooFar",
	NotCarried = "NotCarried",
	NotRecyclable = "NotRecyclable",
	UnknownRecipe = "UnknownRecipe",
	Locked = "Locked",
	MissingIngredients = "MissingIngredients",
	NoJob = "NoJob",
	ClickLimit = "ClickLimit",
	NotInOutput = "NotInOutput",
	CarryFull = "CarryFull",
	UnknownUpgrade = "UnknownUpgrade",
	MaxLevel = "MaxLevel",
	NotEnoughKlunks = "NotEnoughKlunks",
})

MachineService.JobFinished = Signal.new() -- (player: Player, result: CarriedJunk)

local started = false
local machines: { [Player]: Machine } = {}
local permanentSpeed: { [Player]: boolean } = {}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function upgradeValue(upgradeId: string, level: number): number
	local definition = (MachineConfig.Upgrades :: any)[upgradeId]
	local levels = definition.Levels
	return levels[math.clamp(level, 1, #levels)].Value
end

local function capacity(data: MachineData): number
	return upgradeValue("Storage", data.Upgrades.Storage)
end

local function machineLevel(data: MachineData): number
	return upgradeValue("Level", data.Upgrades.Level)
end

local function completesAt(job: MachineJob): number
	return job.StartedAt + job.Duration - job.Accelerated
end

local function remaining(job: MachineJob): number
	return math.max(0, completesAt(job) - now())
end

-- Base seconds -> real seconds for this machine (Speed upgrade, pass, active boost).
function MachineService.DurationFor(player: Player, base: number, data: MachineData): number
	local multiplier = upgradeValue("Speed", data.Upgrades.Speed)
	if permanentSpeed[player] then
		multiplier *= MonetizationConfig.GamePasses.FastMachine.Multiplier
	end
	if data.BoostUntil > now() then
		multiplier *= MonetizationConfig.Products.SpeedBoost.Multiplier
	end
	return math.max(MachineConfig.MinDuration, math.floor(base * multiplier + 0.5))
end

local function isRecord(value: any): boolean
	return type(value) == "table" and Validate.IsUid(value.Uid) and ItemConfig.Exists(value.Id)
end

-- Repairs a loaded MachineData in place: fills missing fields, drops broken or duplicate
-- records (a uid that is also carried stays with the carry list).
local function sanitize(player: Player, data: any, carry: any)
	local seen: { [string]: boolean } = {}
	if type(carry) == "table" then
		for _, entry in carry do
			if type(entry) == "table" and type(entry.Uid) == "string" then
				seen[entry.Uid] = true
			end
		end
	end

	if type(data.Upgrades) ~= "table" then
		data.Upgrades = {}
	end
	for _, upgradeId in MachineConfig.UpgradeOrder do
		local levels = (MachineConfig.Upgrades :: any)[upgradeId].Levels
		local level = data.Upgrades[upgradeId]
		data.Upgrades[upgradeId] = if Validate.IsInteger(level, 1, #levels) then level else 1
	end
	if not Validate.IsFiniteNumber(data.BoostUntil) then
		data.BoostUntil = 0
	end
	if not Validate.IsFiniteNumber(data.SkipSeconds) or data.SkipSeconds < 0 then
		data.SkipSeconds = 0
	end
	if not Validate.IsInteger(data.InstantCredits, 0) then
		data.InstantCredits = 0
	end
	if not Validate.IsInteger(data.ResultSeq, 0) then
		data.ResultSeq = 0
	end

	local job = data.Job
	if job ~= nil then
		local valid = type(job) == "table"
			and (job.Kind == "Recycle" or job.Kind == "Craft" or job.Kind == "Mythic")
			and Validate.IsFiniteNumber(job.StartedAt)
			and Validate.IsFiniteNumber(job.Duration)
			and job.Duration > 0
			and Validate.IsFiniteNumber(job.Accelerated)
			and job.Accelerated >= 0
			and isRecord(job.Result)
			and not seen[job.Result.Uid]
		if valid then
			seen[job.Result.Uid] = true
			if not Validate.IsFiniteNumber(job.Clicked) or (job.Clicked :: number) < 0 then
				job.Clicked = 0
			end
			if type(job.Label) ~= "string" then
				job.Label = ItemConfig.GetDisplayName(job.Result.Id)
			end
			if type(job.Inputs) ~= "table" then
				job.Inputs = {}
			end
		else
			warn(`[MachineService] {player.Name}: dropped an invalid saved job`)
			data.Job = nil
		end
	end

	local output: { CarriedJunk } = {}
	if type(data.Output) == "table" then
		for _, entry in data.Output do
			if isRecord(entry) and not seen[entry.Uid] then
				seen[entry.Uid] = true
				table.insert(output, { Uid = entry.Uid, Id = entry.Id })
			else
				warn(`[MachineService] {player.Name}: dropped an invalid or duplicate saved output`)
			end
		end
	end
	data.Output = output
end

---------------------------------------------------------------------------------------------
-- World presentation
---------------------------------------------------------------------------------------------

-- Seconds that clicks may still remove from this job.
local function clickLeft(job: any): number
	return math.max(0, math.floor(job.Duration * MachineConfig.MaxClickShare) - (job.Clicked or 0))
end

local function publish(machine: Machine)
	local model = machine.Model
	if model == nil then
		return
	end
	local data = machine.Data
	local job = data.Job
	local state: Types.MachineState = if job ~= nil then "Processing" elseif #data.Output > 0 then "RewardReady" else "Idle"
	model:SetAttribute("State", state)
	model:SetAttribute("JobKind", if job ~= nil then job.Kind else "")
	model:SetAttribute("JobLabel", if job ~= nil then job.Label else "")
	model:SetAttribute("JobStartedAt", if job ~= nil then job.StartedAt else 0)
	model:SetAttribute("JobDuration", if job ~= nil then job.Duration else 0)
	model:SetAttribute("JobCompletesAt", if job ~= nil then completesAt(job) else 0)
	model:SetAttribute("ClickLeft", if job ~= nil then clickLeft(job) else 0)
	model:SetAttribute("OutputCount", #data.Output)
	local outputs = table.create(#data.Output)
	for index, entry in data.Output do
		outputs[index] = `{entry.Uid}:{entry.Id}`
	end
	model:SetAttribute("OutputList", table.concat(outputs, ",")) -- "uid:id,uid:id" for the panel
	model:SetAttribute("OutputCapacity", capacity(data))
	model:SetAttribute("UpgradeSpeed", data.Upgrades.Speed)
	model:SetAttribute("UpgradeStorage", data.Upgrades.Storage)
	model:SetAttribute("UpgradeLevel", data.Upgrades.Level)
	model:SetAttribute("MachineLevel", machineLevel(data))
	model:SetAttribute("BoostUntil", data.BoostUntil)
	model:SetAttribute("InstantCredits", data.InstantCredits)
	model:SetAttribute("LastResultId", machine.LastResultId)
	model:SetAttribute("LastResultRarity", ItemConfig.GetRarity(machine.LastResultId) or "")
	model:SetAttribute("ResultSeq", data.ResultSeq) -- last: clients react to it
end

local function outputPosition(machine: Machine, index: number): Vector3?
	local point = machine.OutputPoint
	if point == nil then
		return nil
	end
	local offset = (index - 1) - (capacity(machine.Data) - 1) / 2
	return (point.CFrame * CFrame.new(offset * OUTPUT_SPACING, 0, 0)).Position
end

local removeOutput: (machine: Machine, uid: string) -> ()

-- Puts every Output record that is not yet in the world onto the tray (reserved for the owner).
local function spawnOutputs(machine: Machine)
	if machine.Model == nil then
		return
	end
	local ownerName = machine.Player.DisplayName
	for index, entry in machine.Data.Output do
		if not JunkService.IsUidActive(entry.Uid) then
			local position = outputPosition(machine, index)
			if position ~= nil then
				local uid = entry.Uid
				JunkService.SpawnAt(entry.Id, position, {
					Uid = uid,
					Yaw = 0,
					ReservedFor = machine.UserId,
					ObjectText = `{ownerName}'s {ItemConfig.GetDisplayName(entry.Id)}`,
					OnClaimed = function()
						removeOutput(machine, uid)
					end,
				})
			end
		end
	end
end

function removeOutput(machine: Machine, uid: string)
	local output = machine.Data.Output
	for index, entry in output do
		if entry.Uid == uid then
			table.remove(output, index)
			break
		end
	end
	publish(machine)
end

-- Moves a finished job's result into Output. Safe to call any time.
local function settle(machine: Machine)
	local data = machine.Data
	local job = data.Job
	if job == nil or remaining(job) > 0 then
		return
	end
	data.Job = nil
	local result = { Uid = job.Result.Uid, Id = job.Result.Id }
	table.insert(data.Output, result)
	data.ResultSeq += 1
	machine.LastResultId = result.Id
	machine.Token += 1
	spawnOutputs(machine)
	publish(machine)
	MachineService.JobFinished:Fire(machine.Player, { Uid = result.Uid, Id = result.Id }, job.Kind)
end

-- One task.delay per running job; re-armed whenever the completion time changes.
local function schedule(machine: Machine)
	machine.Token += 1
	local job = machine.Data.Job
	if job == nil then
		return
	end
	local token = machine.Token
	task.delay(remaining(job) + 0.05, function()
		if machine.Token == token and machines[machine.Player] == machine then
			settle(machine)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Requests (all act on the caller's own machine)
---------------------------------------------------------------------------------------------

local function isNear(machine: Machine, player: Player): boolean
	local root = CarryService.GetLiveRoot(player)
	local anchor = machine.Anchor
	return root ~= nil and anchor ~= nil and (root.Position - anchor.Position).Magnitude <= MachineConfig.UseDistance
end

-- Common checks before a job starts. Returns the machine or (nil, errorCode).
local function readyToStart(player: Player, outputs: number): (Machine?, string?)
	local machine = machines[player]
	if machine == nil then
		return nil, MachineService.Errors.NoMachine
	end
	if machine.Data.Job ~= nil then
		return nil, MachineService.Errors.Busy
	end
	if #machine.Data.Output + outputs > capacity(machine.Data) then
		return nil, MachineService.Errors.OutputFull
	end
	if not isNear(machine, player) then
		return nil, MachineService.Errors.TooFar
	end
	return machine, nil
end

local function carriedId(player: Player, uid: string): string?
	for _, entry in CarryService.GetCarried(player) do
		if entry.Uid == uid then
			return entry.Id
		end
	end
	return nil
end

local applyStoredSkip: (machine: Machine) -> ()

local function startJob(machine: Machine, job: MachineJob)
	machine.Data.Job = job
	schedule(machine)
	publish(machine)
	if job.Duration >= 60 then
		applyStoredSkip(machine)
	end
end

function MachineService.Recycle(player: Player, uid: any): (boolean, string?)
	if not Validate.IsUid(uid) then
		return false, MachineService.Errors.InvalidArguments
	end
	local machine, err = readyToStart(player, 1)
	if machine == nil then
		return false, err
	end
	local itemId = carriedId(player, uid)
	if itemId == nil then
		return false, MachineService.Errors.NotCarried
	end
	if not ItemConfig.CanBeRecycled(itemId) then
		return false, MachineService.Errors.NotRecyclable
	end

	-- Validated; nothing below yields.
	local record = CarryService.TakeByUid(player, uid)
	if record == nil then
		return false, MachineService.Errors.NotCarried
	end
	local resultId = RewardService.RollRecycle(record.Id)
	startJob(machine, {
		Kind = "Recycle",
		Label = `Recycling {ItemConfig.GetDisplayName(record.Id)}`,
		StartedAt = now(),
		Duration = MachineService.DurationFor(player, MachineConfig.RecycleDuration, machine.Data),
		Accelerated = 0,
		Inputs = { record },
		Result = { Uid = JunkService.NewUid(), Id = resultId },
	})
	return true, nil
end

function MachineService.Craft(player: Player, recipeId: any): (boolean, string?)
	local recipe = Recipes.Get(recipeId)
	if recipe == nil then
		return false, MachineService.Errors.UnknownRecipe
	end
	local machine, err = readyToStart(player, recipe.OutputAmount)
	if machine == nil then
		return false, err
	end
	if not recipe.IsUnlockedByDefault or recipe.RequiredLevel > machineLevel(machine.Data) then
		return false, MachineService.Errors.Locked
	end
	local plan = CraftingService.PlanRecipe(recipe, CarryService.GetCarried(player))
	if plan == nil then
		return false, MachineService.Errors.MissingIngredients
	end

	-- Validated; nothing below yields, so the planned uids are still carried.
	local inputs: { CarriedJunk } = {}
	for _, uid in plan do
		local record = CarryService.TakeByUid(player, uid)
		if record ~= nil then
			table.insert(inputs, record)
		end
	end
	local base = recipe.DurationOverride or (MachineConfig.CraftDurations :: any)[recipe.Rarity]
	startJob(machine, {
		Kind = "Craft",
		Label = `Crafting {recipe.DisplayName}`,
		StartedAt = now(),
		Duration = MachineService.DurationFor(player, base, machine.Data),
		Accelerated = 0,
		Inputs = inputs,
		RecipeId = recipe.RecipeId,
		-- OutputAmount is 1 for every recipe today; more would need several result records.
		Result = { Uid = JunkService.NewUid(), Id = recipe.OutputItemId },
	})
	return true, nil
end

function MachineService.Mythic(player: Player, uidA: any, uidB: any, uidC: any): (boolean, string?)
	local uids = { uidA, uidB, uidC }
	for _, uid in uids do
		if not Validate.IsUid(uid) then
			return false, MachineService.Errors.InvalidArguments
		end
	end
	if uidA == uidB or uidA == uidC or uidB == uidC then
		return false, MachineService.Errors.InvalidArguments -- one item cannot fill two slots
	end
	local machine, err = readyToStart(player, 1)
	if machine == nil then
		return false, err
	end
	local inputIds: { string } = {}
	for _, uid in uids do
		local itemId = carriedId(player, uid)
		if itemId == nil then
			return false, MachineService.Errors.NotCarried
		end
		if not ItemConfig.CanBeMythicInput(itemId) then
			return false, MachineService.Errors.NotRecyclable
		end
		table.insert(inputIds, itemId)
	end

	-- Validated; nothing below yields.
	local inputs: { CarriedJunk } = {}
	for _, uid in uids do
		local record = CarryService.TakeByUid(player, uid)
		if record ~= nil then
			table.insert(inputs, record)
		end
	end
	local resultId = CraftingService.RollMythic(inputIds)
	startJob(machine, {
		Kind = "Mythic",
		Label = "Wish Furnace", -- player-facing name of Mythic Crafting
		StartedAt = now(),
		Duration = MachineConfig.MythicDuration, -- always exactly six hours
		Accelerated = 0,
		Inputs = inputs,
		Result = { Uid = JunkService.NewUid(), Id = resultId },
	})
	return true, nil
end

-- One valid click removes exactly MachineConfig.SecondsPerClick (never below zero), until the
-- clicks of this job have removed MachineConfig.MaxClickShare of it.
function MachineService.Accelerate(player: Player): (boolean, string?)
	local machine = machines[player]
	if machine == nil then
		return false, MachineService.Errors.NoMachine
	end
	local job = machine.Data.Job
	if job == nil then
		return false, MachineService.Errors.NoJob
	end
	local left = remaining(job)
	if left <= 0 then
		settle(machine)
		return false, MachineService.Errors.NoJob
	end
	if clickLeft(job) < MachineConfig.SecondsPerClick then
		return false, MachineService.Errors.ClickLimit
	end
	local removed = math.min(MachineConfig.SecondsPerClick, left)
	job.Accelerated += removed
	job.Clicked = (job.Clicked or 0) + removed
	if remaining(job) <= 0 then
		settle(machine)
	else
		schedule(machine)
		publish(machine)
	end
	return true, nil
end

-- Moves one finished item from the tray into the owner's hands.
function MachineService.Take(player: Player, uid: any): (boolean, string?)
	if not Validate.IsUid(uid) then
		return false, MachineService.Errors.InvalidArguments
	end
	local machine = machines[player]
	if machine == nil then
		return false, MachineService.Errors.NoMachine
	end
	local itemId: string? = nil
	for _, entry in machine.Data.Output do
		if entry.Uid == uid then
			itemId = entry.Id
		end
	end
	if itemId == nil then
		return false, MachineService.Errors.NotInOutput
	end
	if CarryService.IsFull(player) then
		return false, MachineService.Errors.CarryFull
	end
	if not isNear(machine, player) then
		return false, MachineService.Errors.TooFar
	end

	-- Validated; nothing below yields.
	local model = JunkService.GetByUid(uid)
	if model ~= nil then
		JunkService.Claim(model, player) -- OnClaimed removes it from Output
	else
		removeOutput(machine, uid)
	end
	local ok = CarryService.AddJunk(player, itemId, uid)
	if not ok then
		-- Cannot happen after the checks above; never lose the item.
		table.insert(machine.Data.Output, { Uid = uid, Id = itemId })
		spawnOutputs(machine)
		publish(machine)
		return false, MachineService.Errors.CarryFull
	end
	return true, nil
end

function MachineService.BuyUpgrade(player: Player, upgradeId: any): (boolean, string?)
	local machine = machines[player]
	if machine == nil then
		return false, MachineService.Errors.NoMachine
	end
	local definition = if type(upgradeId) == "string" then (MachineConfig.Upgrades :: any)[upgradeId] else nil
	if definition == nil then
		return false, MachineService.Errors.UnknownUpgrade
	end
	local current = machine.Data.Upgrades[upgradeId] :: number
	if current >= #definition.Levels then
		return false, MachineService.Errors.MaxLevel
	end
	local price = definition.Levels[current + 1].Price
	if price > 0 then
		local paid = EconomyService.Spend(player, price, `MachineUpgrade:{upgradeId}`)
		if not paid then
			return false, MachineService.Errors.NotEnoughKlunks
		end
	end
	(machine.Data.Upgrades :: any)[upgradeId] = current + 1
	publish(machine)
	return true, nil
end

-- Monetization: finish the running job now, or keep a credit for the next one.
function MachineService.InstantFinish(player: Player): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local machine = machines[player]
	local job = data.Machine.Job
	if machine ~= nil and job ~= nil then
		job.Accelerated = job.Duration
		settle(machine)
	else
		data.Machine.InstantCredits += 1
		if machine ~= nil then
			publish(machine)
		end
	end
	return true
end

-- Applies bought time to the running job; what is left over waits for the next one.
local function applySkip(machine: Machine)
	local data = machine.Data
	local job = data.Job
	local credit = data.SkipSeconds
	if job == nil or type(credit) ~= "number" or credit <= 0 then
		return
	end
	local used = math.min(credit, remaining(job))
	data.SkipSeconds = credit - used
	job.Accelerated += used
	if remaining(job) <= 0 then
		settle(machine)
	else
		schedule(machine)
		publish(machine)
	end
end

applyStoredSkip = applySkip

-- Monetization: removes up to `seconds` from the running job. Without a job the time is kept for
-- the next long one (StartJob), so a purchase is never lost.
function MachineService.SkipTime(player: Player, seconds: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local machine = machines[player]
	if machine ~= nil and machine.Data.Job ~= nil then
		local before = machine.Data.SkipSeconds
		machine.Data.SkipSeconds = seconds
		applySkip(machine)
		machine.Data.SkipSeconds = before -- an hourly tier pays for ONE job; its rest is not kept
		return true
	end
	data.Machine.SkipSeconds = math.max(0, data.Machine.SkipSeconds or 0) + seconds
	return true
end

-- Golden Wrench: takes up to `seconds` off the running job. Not for the Wish Furnace: its six
-- hours shrink only by clicks and bought time. Returns the seconds removed (0 = nothing to do).
function MachineService.TuneUp(player: Player, seconds: number): number
	local machine = machines[player]
	local job = if machine ~= nil then machine.Data.Job else nil
	if machine == nil or job == nil then
		return 0 -- any running job counts, the Wish Furnace too
	end
	local removed = math.min(seconds, remaining(job))
	if removed <= 0 then
		return 0
	end
	job.Accelerated += removed
	if remaining(job) <= 0 then
		settle(machine)
	else
		schedule(machine)
		publish(machine)
	end
	return removed
end

-- The player whose working machine (any job, the Wish Furnace too) is nearest to `position`.
function MachineService.NearestWorking(position: Vector3, range: number): Player?
	local best: Player? = nil
	local bestDistance = range
	for player, machine in machines do
		local model, job = machine.Model, machine.Data.Job
		if model ~= nil and job ~= nil then
			local distance = (model:GetPivot().Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Monetization: jobs started during the next `seconds` use the boost multiplier.
function MachineService.AddBoost(player: Player, seconds: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.Machine.BoostUntil = math.max(data.Machine.BoostUntil, now()) + seconds
	local machine = machines[player]
	if machine ~= nil then
		publish(machine)
	end
	return true
end

function MachineService.SetPermanentSpeed(player: Player, enabled: boolean)
	permanentSpeed[player] = if enabled then true else nil
end

function MachineService.GetModel(player: Player): Model?
	local machine = machines[player]
	return if machine ~= nil then machine.Model else nil
end

function MachineService.GetRemaining(player: Player): number?
	local machine = machines[player]
	local job = if machine ~= nil then machine.Data.Job else nil
	return if job ~= nil then remaining(job) else nil
end

-- A deep copy for tests and tools (never the live table).
function MachineService.GetData(player: Player): MachineData?
	local machine = machines[player]
	if machine == nil then
		return nil
	end
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local result = {}
		for key, child in value do
			result[key] = copy(child)
		end
		return result
	end
	return copy(machine.Data)
end

---------------------------------------------------------------------------------------------
-- Load / unload
---------------------------------------------------------------------------------------------

local function buildModel(machine: Machine, plot: Model)
	local assets = ServerStorage:FindFirstChild("Assets")
	local template = if assets ~= nil then assets:FindFirstChild(MachineConfig.TemplateName) else nil
	if template == nil or not template:IsA("Model") then
		warn(`[MachineService] ServerStorage.Assets.{MachineConfig.TemplateName} is missing`)
		return
	end
	local model = template:Clone()
	model.Name = `Machine_{machine.UserId}`
	-- Place it by the bottom of its "Base" part (independent of the model's saved pivot).
	local target = PlotService.GetPlotCFrame(plot) * MACHINE_OFFSET
	local base = model:FindFirstChild("Base")
	if base ~= nil and base:IsA("BasePart") then
		local baseBottom = base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
		model:PivotTo(target * baseBottom:Inverse() * model:GetPivot())
	else
		model:PivotTo(target)
	end
	model:SetAttribute("MachineId", tostring(machine.UserId))
	model:SetAttribute("OwnerUserId", machine.UserId)
	model:SetAttribute("OwnerName", machine.Player.DisplayName)

	local anchor = model:FindFirstChild("PromptAnchor", true)
	if anchor ~= nil and anchor:IsA("BasePart") then
		machine.Anchor = anchor
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MachinePrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = `{machine.Player.DisplayName}'s Machine`
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = MachineConfig.PromptDistance
		prompt.RequiresLineOfSight = false
		-- Own key + AlwaysShow: junk prompts (E / X) nearby can never hide or steal this one.
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		prompt.KeyboardKeyCode = GameConfig.Input.MachineKey
		prompt.GamepadKeyCode = GameConfig.Input.MachineGamepadKey
		prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by UI/PickupPrompt
		prompt:SetAttribute("PromptKind", "Machine")
		prompt:SetAttribute("OwnerUserId", machine.UserId) -- other players' clients hide it
		prompt.Parent = anchor
	end
	local point = model:FindFirstChild("RewardPoint", true)
	if point ~= nil and point:IsA("BasePart") then
		machine.OutputPoint = point
	end
	machine.Model = model
	model.Parent = plot
end

function MachineService.Load(player: Player)
	if machines[player] ~= nil then
		return
	end
	local profileData = DataService.GetData(player)
	local plot = PlotService.GetPlot(player)
	if profileData == nil or plot == nil then
		return
	end
	if type(profileData.Machine) ~= "table" then
		(profileData :: any).Machine = {}
	end
	sanitize(player, profileData.Machine, profileData.Carry)

	local machine: Machine = {
		Player = player,
		UserId = player.UserId,
		Data = profileData.Machine,
		Model = nil,
		Anchor = nil,
		OutputPoint = nil,
		Token = 0,
		LastResultId = "",
	}
	machines[player] = machine
	buildModel(machine, plot)
	settle(machine) -- finished while the owner was away
	schedule(machine)
	spawnOutputs(machine)
	publish(machine)
end

-- Removes the machine from the world. Its data stays in the profile (saved with it).
function MachineService.Unload(player: Player)
	local machine = machines[player]
	if machine == nil then
		return
	end
	machines[player] = nil
	machine.Token += 1 -- cancels the completion timer
	for _, entry in machine.Data.Output do
		JunkService.Despawn(entry.Uid) -- the tray copy; the record stays in Output
	end
	if machine.Model ~= nil then
		machine.Model:Destroy()
	end
end

-- Studio-only helper for DevTests: moves a running job's start back in time, as if the
-- owner had been offline for `seconds`.
function MachineService.DebugShiftJob(player: Player, seconds: number)
	assert(RunService:IsStudio(), "DebugShiftJob is Studio-only")
	local data = DataService.GetData(player)
	local job = if data ~= nil then data.Machine.Job else nil
	if job ~= nil then
		job.StartedAt -= seconds
	end
end

---------------------------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------------------------

local MESSAGES: { [string]: string } = {
	NoMachine = "Your machine is still loading",
	Busy = "Your machine is busy - wait or speed it up",
	OutputFull = "Take the finished items off the tray first",
	TooFar = "Get closer to your machine",
	NotCarried = "You are not carrying that any more",
	NotRecyclable = "That item cannot go into the machine",
	Locked = "Upgrade the machine level to unlock this recipe",
	MissingIngredients = "You are missing some ingredients",
	CarryFull = "Your hands are full - throw something first",
	MaxLevel = "Already at the highest level",
	NotEnoughKlunks = "Not enough Klunks",
}

local function report(player: Player, err: string?)
	local message = if err ~= nil then MESSAGES[err] else nil
	if message ~= nil then
		CarryService.Notify(player, message)
	end
end

local function isShortString(value: any): boolean
	return Validate.IsString(value, 1, 64) and string.match(value, "^[%w_]+$") ~= nil
end

function MachineService.Start()
	assert(not started, "[MachineService] Start() called twice")
	started = true

	PlotService.PlotAssigned:Connect(function(player: Player)
		MachineService.Load(player)
	end)
	PlotService.PlotReleased:Connect(function(player: Player)
		MachineService.Unload(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		MachineService.Unload(player)
		permanentSpeed[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		MachineService.Load(player)
	end

	local function bind(name: string, maxArgs: number, validate: (...any) -> boolean, handler: (Player, ...any) -> (boolean, string?))
		RemoteGuard.ConnectEvent(Remotes.GetEvent(name), {
			Name = name,
			MaxArgs = maxArgs,
			RateLimit = (GameConfig.RateLimits :: any)[name] or (if name == "MachineRecycle"
					or name == "MachineCraft"
					or name == "MachineMythic"
				then GameConfig.RateLimits.MachineStart
				else nil),
			Validate = validate,
		}, function(player: Player, ...: any)
			local ok, err = handler(player, ...)
			if not ok then
				report(player, err)
			end
		end)
	end

	bind("MachineRecycle", 1, Validate.IsUid, MachineService.Recycle)
	bind("MachineCraft", 1, isShortString, MachineService.Craft)
	bind("MachineMythic", 3, function(a: any, b: any, c: any): boolean
		return Validate.IsUid(a) and Validate.IsUid(b) and Validate.IsUid(c)
	end, MachineService.Mythic)
	bind("MachineAccelerate", 0, function(): boolean
		return true
	end, function(player: Player): (boolean, string?)
		local ok = MachineService.Accelerate(player)
		return ok, nil -- a click on a finished machine is not worth a message
	end)
	bind("MachineTake", 1, Validate.IsUid, MachineService.Take)
	bind("MachineUpgrade", 1, isShortString, MachineService.BuyUpgrade)
end

return MachineService
