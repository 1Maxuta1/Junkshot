--!strict
--[[
	JunkService: owns the junk lying in the world (spawning, respawning, expiry, removal).

	What it does
	  - Keeps up to GameConfig.Junk.MaxActive junk objects in Workspace.JunkContainer
	    (created automatically if missing).
	  - Spawn positions: random points inside Parts tagged GameConfig.Junk.SpawnTag
	    (area-weighted), or, if no such Part exists, inside a square around
	    GameConfig.Junk.FallbackCenter. Each point is snapped to the first walkable surface
	    below it, so junk always rests on the ground.
	    Tagged Parts with CanCollide = false are treated as invisible zones and the ground
	    search passes through them; tagged Parts with CanCollide = true count as surfaces.
	  - Every junk object has a Uid (attribute "JunkUid") that stays with it while it is
	    carried and thrown (see Types.CarriedJunk).
	  - Every junk object gets a ProximityPrompt with the Custom style (drawn by the client
	    UI). A trigger does NOT pick anything up by itself: it only fires PickupRequested, and
	    CarryService decides (distance, capacity, cooldown). Exploiters can fire prompts
	    remotely, so the decision must never live here.
	  - Dropped and thrown junk expires after GameConfig.Junk.DroppedLifetime seconds if
	    nobody picks it up. Naturally spawned junk never expires.
	  - Removed models go back to a small per-type pool and are reused by the next spawn.

	Public API (server only)
	  PickupRequested            Signal (player, junk Model)
	  NewUid()                   -> string
	  Claim(junk)                -> (junkId?, uid?)  atomically removes a junk object
	  SpawnAt(id, pos, options?) -> Model?           puts junk on the ground near pos
	  CleanupExpired()           -> number           removes expired junk now (also runs on a timer)
	  GetActiveJunk(), GetActiveCount(), IsActive(junk), IsUidActive(uid), GetByUid(uid),
	  IsClaimable(junk), GetJunkId(junk), GetUid(junk), GetPosition(junk)

	One uid = at most one world object (createJunk refuses a uid that is already in the world).
	A thrown object is created at its landing point immediately but stays locked (no prompt,
	Claim refuses) until it has landed; clients animate that same object along the arc.

	Junk objects are anchored and do not collide, so they cost no physics.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

type ActiveJunk = {
	Uid: string,
	Id: string,
	Position: Vector3,
	ExpiresAt: number?, -- os.clock() deadline; nil = never expires
	ClaimableAt: number, -- os.clock() from which it may be claimed (thrown junk is locked while it flies)
}

type PoolEntry = {
	Id: string,
	Weight: number,
}

export type SpawnOptions = {
	Uid: string?, -- keep an existing identity (drops, throws); a new one is generated otherwise
	Lifetime: number?, -- seconds before it expires; nil = never
	Yaw: number?, -- radians; random when nil
	-- Seconds during which the junk exists in the world but cannot be claimed and shows no
	-- prompt (a throw in flight: clients animate this same object towards its final pivot).
	LockedFor: number?,
	-- Called with the finished model just before it is parented into the world, so a caller can
	-- send a remote event that clients receive BEFORE the object itself (see ThrowService).
	BeforeParent: ((model: Model) -> ())?,
}

local UID_ATTRIBUTE = "JunkUid"
local PROMPT_ACTION_TEXT = "Pick up"
local MARKER_RAY_LIFT = 2 -- studs above a spawn marker's top surface where the ground search starts
local DROP_RAY_LIFT = 4
local DROP_RAY_LENGTH = 60
local MAX_CONSECUTIVE_FAILURES = 30
local FAILURE_WARN_INTERVAL = 30 -- seconds between repeated "cannot spawn" warnings

local JunkService = {}

JunkService.PickupRequested = Signal.new() -- (player: Player, junk: Model)

local random = Random.new()
local started = false
local container: Folder? = nil

local active: { [Model]: ActiveJunk } = {}
local byUid: { [string]: Model } = {}
local activeCount = 0

local spawnPool: { PoolEntry } = {}
local totalWeight = 0

local modelPool: { [string]: { Model } } = {}

local lastFailureWarning = -math.huge

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function getContainer(): Folder
	local name = GameConfig.Junk.ContainerName
	local existing = Workspace:FindFirstChild(name)
	if existing == nil then
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = Workspace
		return folder
	end
	if not existing:IsA("Folder") then
		error(`[JunkService] Workspace.{name} exists but is a {existing.ClassName}, expected Folder`)
	end
	return existing
end

local function buildSpawnPool()
	for id, definition in JunkConfig.Items do
		if definition.SpawnWeight > 0 then
			table.insert(spawnPool, { Id = id, Weight = definition.SpawnWeight })
			totalWeight += definition.SpawnWeight
		end
	end
	assert(#spawnPool > 0, "[JunkService] no junk with SpawnWeight > 0 in JunkConfig")
end

local function pickJunkId(): string
	local roll = random:NextNumber() * totalWeight
	for _, entry in spawnPool do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Id
		end
	end
	return spawnPool[#spawnPool].Id -- floating point safety net
end

local function unregister(model: Model)
	local entry = active[model]
	if entry ~= nil then
		active[model] = nil
		if byUid[entry.Uid] == model then
			byUid[entry.Uid] = nil
		end
		activeCount -= 1
	end
end

-- Takes a model out of the world: back to the pool if there is room, destroyed otherwise.
local function release(model: Model, junkId: string)
	unregister(model) -- before anything else, so a second Claim in the same frame always fails
	local pool = modelPool[junkId]
	if pool == nil then
		pool = {}
		modelPool[junkId] = pool
	end
	if #pool < GameConfig.Junk.PoolSizePerType then
		model.Parent = nil
		table.insert(pool, model)
	else
		model:Destroy()
	end
end

local function getMarkers(): { BasePart }
	local markers: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(GameConfig.Junk.SpawnTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
			table.insert(markers, instance)
		end
	end
	return markers
end

-- Instances the ground search must pass through.
local function buildExcluded(markers: { BasePart }): { Instance }
	local excluded: { Instance } = {}
	if container ~= nil then
		table.insert(excluded, container)
	end
	for _, marker in markers do
		if not marker.CanCollide then
			table.insert(excluded, marker)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(excluded, player.Character)
		end
	end
	return excluded
end

-- First surface below `origin` that is flat enough to rest on.
local function findGround(origin: Vector3, length: number, excluded: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
	if result == nil or result.Normal.Y < GameConfig.Junk.MinGroundNormalY then
		return nil
	end
	return result.Position
end

local function randomOrigin(markers: { BasePart }): Vector3
	local totalArea = 0
	for _, marker in markers do
		totalArea += marker.Size.X * marker.Size.Z
	end

	if totalArea > 0 then
		local pick = random:NextNumber() * totalArea
		local chosen = markers[#markers]
		for _, marker in markers do
			pick -= marker.Size.X * marker.Size.Z
			if pick <= 0 then
				chosen = marker
				break
			end
		end
		local offset = Vector3.new(
			(random:NextNumber() - 0.5) * chosen.Size.X,
			chosen.Size.Y / 2,
			(random:NextNumber() - 0.5) * chosen.Size.Z
		)
		return chosen.CFrame:PointToWorldSpace(offset) + Vector3.new(0, MARKER_RAY_LIFT, 0)
	end

	local half = GameConfig.Junk.FallbackHalfExtent
	local center = GameConfig.Junk.FallbackCenter
	return Vector3.new(
		center.X + (random:NextNumber() * 2 - 1) * half,
		GameConfig.Junk.RayStartHeight,
		center.Z + (random:NextNumber() * 2 - 1) * half
	)
end

local function isFarEnough(position: Vector3): boolean
	local minSpacing = GameConfig.Junk.MinSpacing
	for _, entry in active do
		if (entry.Position - position).Magnitude < minSpacing then
			return false
		end
	end
	return true
end

local function addPrompt(model: Model, root: BasePart, junkId: string)
	local definition = JunkConfig.Get(junkId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = if definition ~= nil then definition.DisplayName else junkId
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.Junk.PickupMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = GameConfig.Input.PickupKey
	prompt.GamepadKeyCode = GameConfig.Input.PickupGamepadKey
	-- Drawn by the client (UI/PickupPrompt) so it matches the game's look on every platform.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = root
	-- The connection lives as long as the model (pooled models keep it).
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		JunkService.PickupRequested:Fire(triggeringPlayer, model)
	end)
end

-- A finished model for junkId: from the pool when possible, freshly built otherwise.
local function acquireModel(junkId: string): Model?
	local pool = modelPool[junkId]
	if pool ~= nil and #pool > 0 then
		return table.remove(pool)
	end

	local model = JunkFactory.Build(junkId, "World")
	if model == nil then
		return nil
	end
	local root = JunkFactory.GetRoot(model)
	if root == nil then
		model:Destroy()
		return nil
	end
	-- Small objects stream in and out as a whole, so a client never sees half a junk.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	addPrompt(model, root, junkId)
	model.Destroying:Connect(function()
		unregister(model) -- also covers junk destroyed by something other than Claim
	end)
	return model
end

-- Puts one junk object on `groundPosition` and registers it.
local function createJunk(junkId: string, groundPosition: Vector3, options: SpawnOptions?): Model?
	local folder = container
	if folder == nil then
		return nil
	end
	local bounds = JunkFactory.GetBounds(junkId)
	if bounds == nil then
		return nil
	end

	local uid = if options ~= nil and options.Uid ~= nil then options.Uid else JunkService.NewUid()
	if byUid[uid] ~= nil then
		warn(`[JunkService] refusing to spawn junk with uid {uid}: it is already in the world`)
		return nil
	end

	local model = acquireModel(junkId)
	if model == nil then
		return nil
	end
	local root = JunkFactory.GetRoot(model)
	if root == nil then
		model:Destroy()
		return nil
	end

	local yaw = if options ~= nil and options.Yaw ~= nil then options.Yaw else random:NextNumber() * math.pi * 2
	-- Bounds.Min.Y is the lowest point relative to the model's origin (a negative number or 0),
	-- so lifting the origin by -Min.Y puts the lowest point exactly on the ground.
	local pivotPosition = Vector3.new(groundPosition.X, groundPosition.Y - bounds.Min.Y, groundPosition.Z)
	model:PivotTo(CFrame.new(pivotPosition) * CFrame.Angles(0, yaw, 0))
	model:SetAttribute(UID_ATTRIBUTE, uid)

	local now = os.clock()
	local lifetime = if options ~= nil then options.Lifetime else nil
	local lockedFor = if options ~= nil and options.LockedFor ~= nil then math.max(options.LockedFor, 0) else 0
	active[model] = {
		Uid = uid,
		Id = junkId,
		Position = root.Position,
		ExpiresAt = if lifetime ~= nil then now + lockedFor + lifetime else nil,
		ClaimableAt = now + lockedFor,
	}
	byUid[uid] = model
	activeCount += 1

	-- Pooled models keep their prompt, so its state is set on every spawn.
	local prompt = root:FindFirstChildOfClass("ProximityPrompt")
	if prompt ~= nil then
		prompt.Enabled = lockedFor <= 0
		if lockedFor > 0 then
			task.delay(lockedFor, function()
				local entry = active[model]
				if entry ~= nil and entry.Uid == uid then
					prompt.Enabled = true
				end
			end)
		end
	end

	if options ~= nil and options.BeforeParent ~= nil then
		options.BeforeParent(model)
	end
	model.Parent = folder -- parent last so clients receive a finished object
	return model
end

local function trySpawn(): boolean
	local junkId = pickJunkId()
	local markers = getMarkers()
	local excluded = buildExcluded(markers)

	for _ = 1, GameConfig.Junk.SpawnAttempts do
		local ground = findGround(randomOrigin(markers), GameConfig.Junk.RayLength, excluded)
		if ground ~= nil and isFarEnough(ground) then
			return createJunk(junkId, ground, nil) ~= nil
		end
	end
	return false
end

-- trySpawn wrapped so one unexpected error cannot kill the spawn loops.
local function safeSpawn(): boolean
	local ok, result = pcall(trySpawn)
	if not ok then
		warn(`[JunkService] spawn error: {tostring(result)}`)
		return false
	end
	return result
end

local function warnSpawnFailure()
	local now = os.clock()
	if now - lastFailureWarning >= FAILURE_WARN_INTERVAL then
		lastFailureWarning = now
		warn(
			"[JunkService] could not find a valid spawn position. Is there ground inside the spawn area "
				.. `(Parts tagged "{GameConfig.Junk.SpawnTag}", or the fallback area around the origin)?`
		)
	end
end

local function fillToMax()
	local perStep = math.max(1, GameConfig.Junk.InitialSpawnPerStep)
	local spawnedThisStep = 0
	local failures = 0

	while activeCount < GameConfig.Junk.MaxActive do
		if safeSpawn() then
			failures = 0
			spawnedThisStep += 1
			if spawnedThisStep >= perStep then
				spawnedThisStep = 0
				task.wait() -- spread the initial fill over several frames
			end
		else
			failures += 1
			if failures >= MAX_CONSECUTIVE_FAILURES then
				warnSpawnFailure()
				return
			end
			task.wait()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function JunkService.Start()
	assert(not started, "[JunkService] Start() called twice")
	started = true

	container = getContainer()
	buildSpawnPool()

	task.spawn(function()
		fillToMax()
		-- Maintenance: top the world back up as players take junk.
		while true do
			task.wait(GameConfig.Junk.RespawnInterval)
			if activeCount < GameConfig.Junk.MaxActive and not safeSpawn() then
				warnSpawnFailure()
			end
		end
	end)

	-- One loop for all junk (no per-object timers).
	task.spawn(function()
		while true do
			task.wait(GameConfig.Junk.CleanupInterval)
			JunkService.CleanupExpired()
		end
	end)
end

function JunkService.NewUid(): string
	return HttpService:GenerateGUID(false)
end

-- Atomically takes a junk object out of the world. Returns (junkId, uid), or nil if it is
-- not an active junk object (already claimed, destroyed, or not junk at all).
function JunkService.Claim(junk: any): (string?, string?)
	local entry = active[junk]
	if entry == nil or os.clock() < entry.ClaimableAt then
		return nil, nil
	end
	release(junk :: Model, entry.Id)
	return entry.Id, entry.Uid
end

-- Places junk on the ground near `position` (a drop or a throw landing). Ignores MaxActive
-- on purpose, so carried junk is never lost because the world is full.
-- Returns nil if there is no ground within reach (e.g. a death in the void) or if
-- options.Uid is already in the world.
function JunkService.SpawnAt(junkId: string, position: Vector3, options: SpawnOptions?): Model?
	if container == nil or not JunkConfig.Exists(junkId) then
		return nil
	end
	local excluded = buildExcluded(getMarkers())
	local ground = findGround(position + Vector3.new(0, DROP_RAY_LIFT, 0), DROP_RAY_LENGTH, excluded)
	if ground == nil then
		return nil
	end
	return createJunk(junkId, ground, options)
end

-- Removes every junk object whose lifetime has run out. Returns how many were removed.
function JunkService.CleanupExpired(): number
	local now = os.clock()
	local expired: { Model } = {}
	for model, entry in active do
		if entry.ExpiresAt ~= nil and now >= entry.ExpiresAt then
			table.insert(expired, model)
		end
	end
	for _, model in expired do
		local entry = active[model]
		if entry ~= nil then
			release(model, entry.Id)
		end
	end
	return #expired
end

function JunkService.GetActiveJunk(): { Model }
	local list: { Model } = {}
	for model in active do
		table.insert(list, model)
	end
	return list
end

function JunkService.GetActiveCount(): number
	return activeCount
end

function JunkService.IsActive(junk: any): boolean
	return active[junk] ~= nil
end

function JunkService.IsUidActive(uid: string): boolean
	return byUid[uid] ~= nil
end

-- The world object of a uid, or nil when that uid is not lying in the world.
function JunkService.GetByUid(uid: string): Model?
	return byUid[uid]
end

-- False for junk that is not in the world or is still locked (a throw in flight).
function JunkService.IsClaimable(junk: any): boolean
	local entry = active[junk]
	return entry ~= nil and os.clock() >= entry.ClaimableAt
end

function JunkService.GetJunkId(junk: any): string?
	local entry = active[junk]
	return if entry ~= nil then entry.Id else nil
end

function JunkService.GetUid(junk: any): string?
	local entry = active[junk]
	return if entry ~= nil then entry.Uid else nil
end

function JunkService.GetPosition(junk: any): Vector3?
	local entry = active[junk]
	return if entry ~= nil then entry.Position else nil
end

return JunkService
