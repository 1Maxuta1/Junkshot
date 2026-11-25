--!strict
--[[
	ThrowService: validates and performs throws of carried junk.

	Flow
	  1. Client fires ThrowRequest(uid, aimTarget). RemoteGuard checks rate limit and types.
	  2. TryThrow validates: cooldown, living character, the player really carries `uid`.
	  3. The server builds the throw itself: origin from the SERVER's character position,
	     velocity from Ballistics.Solve (fixed angle, range and speed clamped by config).
	     The client never sends a velocity or an origin.
	  4. The arc is raycast once (Ballistics.Simulate) to find the landing point. No engine
	     physics is involved, so nothing can be pushed, flung or duplicated.
	     Inside an Aurora Reactor's aura the same arc is flown slower (Ballistics.SlowPoints):
	     only the flight time changes, the landing point does not.
	  5. Lifecycle, in this order and without yielding:
	       carry list --TakeByUid--> record --JunkService.SpawnAt--> ONE world object
	     The world object is created at once at its FINAL pivot and stays locked (no prompt,
	     cannot be claimed) for the flight time. Just before it is parented, ThrowFx goes to
	     nearby clients, so they receive the event first and then move that same object along
	     the arc locally. No second object ever exists, on the server or on any client.
	  6. When the flight time is over the lock expires and it is ordinary dropped junk again
	     (any player can pick it up; it expires if nobody does).
	  If no landing spot exists at all, the record goes back into the thrower's carry list.

	Public API (server only)
	  TryThrow(player, uid, aimTarget) -> (ok, errorCode?)
	  IsInFlight(uid) -> boolean
	  Landed  Signal (thrower: Player, record: CarriedJunk, position: Vector3, hit: Instance?)
	          Fired when the flight time is over. Future systems can react to `hit`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Ballistics = require(ReplicatedStorage.Shared.Util.Ballistics)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local CarryService = require(script.Parent.CarryService)
local JunkService = require(script.Parent.JunkService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local SlowFieldService = require(script.Parent.SlowFieldService)

local WALL_BACKOFF = 1.5 -- studs a wall hit is moved back before searching the ground below it

local ThrowService = {}

ThrowService.Errors = table.freeze({
	InvalidArguments = "InvalidArguments",
	Cooldown = "Cooldown",
	NoCharacter = "NoCharacter",
	NotCarried = "NotCarried",
	NoLanding = "NoLanding",
})

ThrowService.Landed = Signal.new() -- (thrower: Player, record: CarriedJunk, position: Vector3, hit: Instance?)

local started = false
local fxRemote: RemoteEvent? = nil
local lastThrowAt: { [Player]: number } = {}

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and Validate.IsFiniteNumber(value.X)
		and Validate.IsFiniteNumber(value.Y)
		and Validate.IsFiniteNumber(value.Z)
end

-- Everything the arc should pass through: characters and junk.
local function buildParams(): RaycastParams
	local excluded: { Instance } = {}
	local container = Workspace:FindFirstChild(GameConfig.Junk.ContainerName)
	if container ~= nil then
		table.insert(excluded, container)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(excluded, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	params.RespectCanCollide = true -- invisible zones and decorations without collision are ignored
	return params
end

-- Start of the throw: in front of and above the root, unless that point is inside a wall.
local function getOrigin(root: BasePart, params: RaycastParams): Vector3
	local throw = GameConfig.Throw
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.zero

	local raised = root.Position + Vector3.new(0, throw.OriginHeight, 0)
	local desired = raised + flatLook * throw.OriginForward
	if Workspace:Raycast(raised, desired - raised, params) ~= nil then
		return raised
	end
	return desired
end

-- Where the junk comes to rest for a given arc hit.
local function resolveLanding(hit: Ballistics.Hit): Vector3
	local normal = hit.Normal
	if normal ~= nil and normal.Y < GameConfig.Junk.MinGroundNormalY then
		-- Hit a wall or a steep side: fall straight down in front of it.
		return hit.Position + Vector3.new(normal.X, 0, normal.Z) * WALL_BACKOFF
	end
	return hit.Position
end

local function sendFx(fx: Types.ThrowFx, thrower: Player)
	local remote = fxRemote
	if remote == nil then
		return
	end
	local range = GameConfig.Throw.FxRange
	for _, player in Players:GetPlayers() do
		local send = player == thrower
		if not send then
			local character = player.Character
			local pivot = if character ~= nil then character:GetPivot().Position else nil
			send = pivot ~= nil
				and (
					(pivot - fx.Origin).Magnitude <= range
					or (pivot - fx.FinalPivot.Position).Magnitude <= range
				)
		end
		if send then
			remote:FireClient(player, fx)
		end
	end
end

function ThrowService.TryThrow(player: Player, uid: any, aimTarget: any): (boolean, string?)
	if not Validate.IsUid(uid) or not isFiniteVector(aimTarget) then
		return false, ThrowService.Errors.InvalidArguments
	end

	local now = os.clock()
	local last = lastThrowAt[player]
	if last ~= nil and now - last < GameConfig.Throw.Cooldown then
		return false, ThrowService.Errors.Cooldown
	end
	lastThrowAt[player] = now

	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return false, ThrowService.Errors.NoCharacter
	end
	if not CarryService.HasUid(player, uid) then
		return false, ThrowService.Errors.NotCarried
	end

	local params = buildParams()
	local origin = getOrigin(root, params)
	local velocity = Ballistics.Solve(origin, aimTarget, root.CFrame.LookVector)
	local hit = Ballistics.Simulate(origin, velocity, params)
	local landing = resolveLanding(hit)

	-- No yields from the HasUid check to the end, so nobody can interleave.
	local record = CarryService.TakeByUid(player, uid)
	if record == nil then
		return false, ThrowService.Errors.NotCarried
	end

	local slowPoints = Ballistics.SlowPoints(origin, velocity, Ballistics.GetGravity(), hit.Time, SlowFieldService.FactorAt)
	local flightTime = if slowPoints ~= nil then slowPoints[#slowPoints][1] else hit.Time
	local options = {
		Uid = record.Uid,
		Lifetime = GameConfig.Junk.DroppedLifetime,
		LockedFor = flightTime,
		-- Runs after the object is placed but before it replicates, so clients get the event first.
		BeforeParent = function(model: Model)
			sendFx({
				Uid = record.Uid,
				JunkId = record.Id,
				ThrowerUserId = player.UserId,
				Origin = origin,
				Velocity = velocity,
				Gravity = Ballistics.GetGravity(),
				FlightTime = flightTime,
				SlowPoints = slowPoints,
				FinalPivot = model:GetPivot(),
			}, player)
		end,
	}
	local model = JunkService.SpawnAt(record.Id, landing, options)
	if model == nil then
		-- No ground below the landing point (e.g. over the void): it lands at the thrower's feet.
		model = JunkService.SpawnAt(record.Id, root.Position, options)
	end
	if model == nil then
		-- Nowhere to put it: give it back instead of losing it.
		CarryService.AddJunk(player, record.Id, record.Uid)
		return false, ThrowService.Errors.NoLanding
	end

	local landedAt = model:GetPivot().Position
	local hitInstance = hit.Instance
	task.delay(flightTime, function()
		ThrowService.Landed:Fire(player, record, landedAt, hitInstance)
	end)
	return true, nil
end

-- True while the thrown object exists but is still locked (flying).
function ThrowService.IsInFlight(uid: string): boolean
	local model = JunkService.GetByUid(uid)
	return model ~= nil and not JunkService.IsClaimable(model)
end

function ThrowService.Start()
	assert(not started, "[ThrowService] Start() called twice")
	started = true

	fxRemote = Remotes.GetEvent("ThrowFx")

	RemoteGuard.ConnectEvent(Remotes.GetEvent("ThrowRequest"), {
		Name = "ThrowRequest",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.ThrowRequest,
		Validate = function(uid: any, aimTarget: any): boolean
			return Validate.IsUid(uid) and isFiniteVector(aimTarget)
		end,
	}, function(player: Player, uid: string, aimTarget: Vector3)
		ThrowService.TryThrow(player, uid, aimTarget)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastThrowAt[player] = nil
	end)
end

return ThrowService
