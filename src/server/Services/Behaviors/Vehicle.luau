--!strict
--[[
	Vehicle behavior (bicycle, homemade car, any future vehicle): ONE implementation driven by
	Config/Behaviors[...].Vehicle (MaxSpeed, Acceleration, Braking, Coast, ReverseSpeed,
	TurnRate, PassengerCapacity, EngineSoundId, WheelRadius).

	Server-authoritative arcade driving
	  - The vehicle's physics stay owned by the SERVER (SetNetworkOwner(nil)), also while a
	    player sits in it. The client only sends (throttle, steer) in [-1, 1] through the
	    VehicleInput remote (rate limited); the server ignores it from anyone but the current
	    driver, and treats input older than INPUT_TIMEOUT as zero.
	  - Each Heartbeat the server integrates speed (acceleration, braking, coasting, reverse) and
	    heading, then sets a planar LinearVelocity (gravity still acts) and an AlignOrientation
	    that keeps the vehicle upright. Speed can never exceed the config. Hitting a wall pulls
	    the internal speed down to the measured speed (no stored-up launch).
	  - Wheels and pedals are visual only: clients spin them (ItemController/Vehicles).

	Seats and permissions
	  - "DriverSeat" (VehicleSeat): only the owner. Anyone else who ends up in it is ejected.
	  - "PassengerSeat" (Seat, cars only): anybody may ride along.
	  - Prompts: Drive/Ride (E). Leaving: Jump (Space / A / jump button) or the EXIT button;
	    the server then puts the character safely beside the vehicle.
	  - Death of the driver ejects the body; a disconnect empties the seat; the vehicle stops.
	  - Falling off the map returns the vehicle to where it was placed.
	  - It cannot be picked up while someone sits in it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local Vehicle = {}

local INPUT_TIMEOUT = 1 -- seconds without input from the driver = let go of the controls
local MAX_FORCE = 200_000
local MAX_TORQUE = 400_000
local SPEED_SLACK = 8 -- studs/s the internal speed may run ahead of the measured speed
local EXIT_SIDE_GAP = 2.5 -- studs between the vehicle's side and an exiting character

local api: any = nil
local active: { [any]: boolean } = {} -- entry -> true
local driverOf: { [Player]: any } = {} -- player -> entry they drive

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function playerOf(humanoid: Humanoid?): Player?
	if humanoid == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(humanoid.Parent)
end

-- Frees a seat and puts the character next to the vehicle (on the seat's side).
local function exitSafely(entry: any, seat: BasePart, humanoid: Humanoid?)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld ~= nil then
		weld:Destroy()
	end
	if humanoid == nil then
		return
	end
	humanoid.Sit = false
	local character = humanoid.Parent
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local base = entry.Model.PrimaryPart
	if root == nil or not root:IsA("BasePart") or base == nil or entry.Model.Parent == nil then
		return
	end
	local localSeat = base.CFrame:PointToObjectSpace(seat.Position)
	local side = if localSeat.X >= 0 then 1 else -1
	local _, size = entry.Model:GetBoundingBox()
	local spot = base.CFrame * CFrame.new(side * (size.X / 2 + EXIT_SIDE_GAP), 1.5, 0)
	local _, yaw = base.CFrame:ToEulerAnglesYXZ()
	local player = Players:GetPlayerFromCharacter(character)
	task.defer(function()
		if root.Parent ~= nil then
			root.CFrame = CFrame.new(spot.Position) * CFrame.Angles(0, yaw, 0)
			root.AssemblyLinearVelocity = Vector3.zero
			-- While seated the character was part of the server-owned vehicle; give it back.
			if player ~= nil and player.Parent == Players then
				pcall(root.SetNetworkOwner, root, player)
			end
		end
	end)
end

-- Seating merges the character into the vehicle's assembly; claim it for the server again.
local function keepServerOwned(base: BasePart)
	task.defer(function()
		if base.Parent ~= nil and not base.Anchored then
			pcall(base.SetNetworkOwner, base, nil)
		end
	end)
end

local function setDriver(entry: any, player: Player?)
	local state = entry.State
	local previous: Player? = state.Driver
	if previous ~= nil and driverOf[previous] == entry then
		driverOf[previous] = nil
	end
	state.Driver = player
	state.Throttle, state.Steer = 0, 0
	state.LastInputAt = os.clock()
	if player ~= nil then
		driverOf[player] = entry
	end
	entry.Model:SetAttribute("DriverUserId", if player ~= nil then player.UserId else nil)
	if state.Engine ~= nil then
		state.Engine.Playing = player ~= nil
	end
end

local function watchSeat(entry: any, seat: Seat | VehicleSeat, isDriverSeat: boolean, prompt: ProximityPrompt)
	local state = entry.State
	local current: Humanoid? = nil
	local diedConnection: RBXScriptConnection? = nil

	table.insert(entry.Connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if diedConnection ~= nil then
			diedConnection:Disconnect()
			diedConnection = nil
		end
		local previous = current
		current = humanoid
		prompt.Enabled = humanoid == nil

		if humanoid == nil then
			if isDriverSeat then
				setDriver(entry, nil)
			end
			local moved = previous ~= nil and previous.SeatPart ~= nil and previous.SeatPart:IsDescendantOf(entry.Model)
			if previous ~= nil and state.Switching ~= previous and not moved then
				exitSafely(entry, seat, previous)
			end
			return
		end

		local player = playerOf(humanoid)
		keepServerOwned(entry.Model.PrimaryPart)
		if isDriverSeat and player ~= entry.Owner then
			-- Someone else climbed into the driver seat: out they go.
			if player ~= nil then
				api.Notify(player, "Only its owner can drive this")
			end
			current = nil
			exitSafely(entry, seat, humanoid)
			return
		end
		if isDriverSeat then
			setDriver(entry, player)
		end
		diedConnection = humanoid.Died:Connect(function()
			exitSafely(entry, seat, humanoid)
		end)
	end))
	state.SeatCleanup = state.SeatCleanup or {}
	table.insert(state.SeatCleanup, function()
		if diedConnection ~= nil then
			diedConnection:Disconnect()
		end
	end)
end

local function sitIn(entry: any, seat: Seat | VehicleSeat, player: Player)
	if seat.Occupant ~= nil then
		api.Notify(player, "Someone is already sitting there")
		return
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or root == nil or not root:IsA("BasePart") or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return
	end
	if (root.Position - seat.Position).Magnitude > GameConfig.Placement.InteractDistance + 6 then
		return
	end
	seat:Sit(humanoid)
end

---------------------------------------------------------------------------------------------
-- Behavior contract
---------------------------------------------------------------------------------------------

function Vehicle.Init(placement: any)
	api = placement
end

function Vehicle.Attach(entry: any)
	local model: Model = entry.Model
	local base = model.PrimaryPart :: BasePart
	local config = entry.Behavior.Vehicle
	local state = entry.State

	-- One rigid assembly around Base. Spinning parts get a Weld (clients animate its C0).
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= base then
			if part:GetAttribute("Spin") ~= nil then
				local weld = Instance.new("Weld")
				weld.Name = "SpinWeld"
				weld.Part0 = base
				weld.Part1 = part
				weld.C0 = base.CFrame:ToObjectSpace(part.CFrame)
				weld.Parent = part
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = base
				weld.Part1 = part
				weld.Parent = part
			end
			part.Massless = true
			part.CanTouch = part:IsA("Seat") or part:IsA("VehicleSeat")
		end
	end
	-- Everything that touches the ground slides (no friction): the LinearVelocity alone moves it.
	local slippery = PhysicalProperties.new(0.8, 0, 0, 100, 1)
	base.CustomPhysicalProperties = slippery
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Collider" then
			part.CustomPhysicalProperties = slippery
		end
	end
	base.RootPriority = 127 -- stays the assembly root even with characters seated on it
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = base

	local linear = Instance.new("LinearVelocity")
	linear.Name = "Drive"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linear.PrimaryTangentAxis = Vector3.xAxis
	linear.SecondaryTangentAxis = Vector3.zAxis
	linear.PlaneVelocity = Vector2.zero -- parked: acts as a hand brake
	linear.MaxForce = MAX_FORCE
	linear.Parent = base

	local align = Instance.new("AlignOrientation")
	align.Name = "Upright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = MAX_TORQUE
	align.Responsiveness = 40
	local _, yaw = model:GetPivot():ToEulerAnglesYXZ()
	align.CFrame = CFrame.Angles(0, yaw, 0)
	align.Parent = base

	local ok, err = pcall(function()
		base:SetNetworkOwner(nil) -- the server simulates it, always
	end)
	if not ok then
		warn(`[Vehicle] SetNetworkOwner failed: {tostring(err)}`)
	end

	if config.EngineSoundId ~= nil then
		local engine = Instance.new("Sound")
		engine.Name = "Engine"
		engine.SoundId = config.EngineSoundId
		engine.Looped = true
		if config.EngineLoop ~= nil then
			local region = NumberRange.new(config.EngineLoop[1], config.EngineLoop[2])
			engine.PlaybackRegionsEnabled = true
			engine.PlaybackRegion = region
			engine.LoopRegion = region
		end
		engine.Volume = if config.EngineRolling then 0 else config.EngineVolume or 0.35
		engine.RollOffMaxDistance = 90
		engine.Parent = base
		state.Engine = engine
	end

	state.Speed = 0
	state.Yaw = yaw
	state.Throttle, state.Steer = 0, 0
	state.LastInputAt = 0
	state.Linear = linear
	state.Align = align
	state.Home = model:GetPivot()
	model:SetAttribute("MaxSpeed", config.MaxSpeed)
	model:SetAttribute("EnginePitch", config.EnginePitch or 1)
	model:SetAttribute("EngineRolling", if config.EngineRolling then config.EngineVolume else nil)

	local isBike = config.PassengerCapacity == 0
	local driverSeat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	if driverSeat ~= nil then
		local prompt = api.AddPrompt(entry, driverSeat, {
			Name = "DrivePrompt",
			Action = if isBike then "Ride" else "Drive",
			Slot = "Primary",
			OwnerOnly = true,
			Row = 1,
		}, function(player: Player)
			sitIn(entry, driverSeat, player)
		end)
		watchSeat(entry, driverSeat, true, prompt)
	end
	local passengerSeat = model:FindFirstChild("PassengerSeat") :: Seat?
	if passengerSeat ~= nil then
		local prompt = api.AddPrompt(entry, passengerSeat, {
			Name = "RidePrompt",
			Action = "Ride along",
			Slot = "Primary",
			Row = 1,
		}, function(player: Player)
			sitIn(entry, passengerSeat, player)
		end)
		watchSeat(entry, passengerSeat, false, prompt)
	end

	active[entry] = true
end

function Vehicle.Detach(entry: any)
	active[entry] = nil
	local state = entry.State
	if state.Driver ~= nil and driverOf[state.Driver] == entry then
		driverOf[state.Driver] = nil
	end
	if state.SeatCleanup ~= nil then
		for _, cleanup in state.SeatCleanup do
			cleanup()
		end
	end
	for _, name in { "DriverSeat", "PassengerSeat" } do
		local seat = entry.Model:FindFirstChild(name)
		if seat ~= nil and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and seat.Occupant ~= nil then
			exitSafely(entry, seat, seat.Occupant)
		end
	end
end

function Vehicle.CanStore(entry: any): (boolean, string?)
	for _, name in { "DriverSeat", "PassengerSeat" } do
		local seat = entry.Model:FindFirstChild(name)
		if seat ~= nil and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and seat.Occupant ~= nil then
			return false, "Occupied"
		end
	end
	return true, nil
end

-- The input the driver sends. Ignored for anyone who is not driving right now.
function Vehicle.SetInput(player: Player, throttle: number, steer: number): boolean
	local entry = driverOf[player]
	if entry == nil or not active[entry] then
		return false
	end
	local state = entry.State
	state.Throttle = math.clamp(throttle, -1, 1)
	state.Steer = math.clamp(steer, -1, 1)
	state.LastInputAt = os.clock()
	return true
end

-- Moves a seated player to the vehicle's other seat (driver <-> passenger). Yields a moment.
function Vehicle.SwitchSeat(player: Player): (boolean, string?)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local part = if humanoid ~= nil then humanoid.SeatPart else nil
	if humanoid == nil or part == nil then
		return false, nil
	end
	for entry in active do
		if part:IsDescendantOf(entry.Model) then
			local other = entry.Model:FindFirstChild(if part.Name == "DriverSeat" then "PassengerSeat" else "DriverSeat")
			if other == nil or not (other:IsA("Seat") or other:IsA("VehicleSeat")) then
				return false, nil
			end
			if other.Occupant ~= nil then
				return false, "Someone is already sitting there"
			end
			if other.Name == "DriverSeat" and player ~= entry.Owner then
				return false, "Only its owner can drive this"
			end
			if entry.State.Race ~= nil or entry.State.Switching ~= nil then
				return false, nil
			end
			entry.State.Switching = humanoid -- leaving this seat is not getting out
			local weld = part:FindFirstChild("SeatWeld")
			if weld ~= nil then
				weld:Destroy()
			end
			humanoid.Sit = false
			for _ = 1, 10 do
				task.wait(0.1)
				if humanoid.Health <= 0 or other.Occupant ~= nil or entry.Model.Parent == nil then
					break
				end
				other:Sit(humanoid)
				if other.Occupant == humanoid then
					break
				end
			end
			task.wait(0.15) -- the seats' own events of this move
			entry.State.Switching = nil
			if humanoid.SeatPart == nil then
				exitSafely(entry, part, humanoid) -- never leave somebody inside the car
			end
			return humanoid.SeatPart == other, nil
		end
	end
	return false, nil
end

function Vehicle.GetDriven(player: Player): any?
	return driverOf[player]
end

---------------------------------------------------------------------------------------------
-- Races (RaceService)
---------------------------------------------------------------------------------------------

-- race = { MaxSpeed, Frozen } replaces the vehicle's top speed / ignores its driver; nil = normal.
function Vehicle.SetRace(entry: any, race: any?)
	entry.State.Race = race
end

-- Puts the vehicle (and whoever sits in it) at `pivot`, standing still.
function Vehicle.MoveTo(entry: any, pivot: CFrame)
	local base = entry.Model.PrimaryPart
	if base == nil then
		return
	end
	entry.Model:PivotTo(pivot)
	base.AssemblyLinearVelocity = Vector3.zero
	base.AssemblyAngularVelocity = Vector3.zero
	local _, yaw = pivot:ToEulerAnglesYXZ()
	local state = entry.State
	state.Yaw = yaw
	state.Speed = 0
	state.Linear.PlaneVelocity = Vector2.zero
	state.Align.CFrame = CFrame.Angles(0, yaw, 0)
end

-- Seats the owner in the driver seat, wherever they are. Yields a moment.
function Vehicle.Seat(entry: any)
	local player: Player = entry.Owner
	local seat = entry.Model:FindFirstChild("DriverSeat")
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if seat == nil or not seat:IsA("VehicleSeat") or character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	for _ = 1, 10 do
		if seat.Occupant == humanoid or entry.Model.Parent == nil or player.Parent ~= Players then
			return
		end
		if humanoid.SeatPart ~= nil then
			humanoid.Sit = false
			task.wait(0.3)
		end
		character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
		task.wait(0.15)
		if seat.Occupant == nil then
			seat:Sit(humanoid)
		end
		task.wait(0.25)
	end
end

function Vehicle.Eject(entry: any)
	local seat = entry.Model:FindFirstChild("DriverSeat")
	if seat ~= nil and seat:IsA("VehicleSeat") and seat.Occupant ~= nil then
		exitSafely(entry, seat, seat.Occupant)
	end
end

---------------------------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------------------------

local function step(entry: any, dt: number, now: number)
	local state = entry.State
	local base = entry.Model.PrimaryPart
	if base == nil then
		return
	end
	local config = entry.Behavior.Vehicle

	if base.Position.Y < GameConfig.Placement.FallResetY then
		entry.Model:PivotTo(state.Home)
		base.AssemblyLinearVelocity = Vector3.zero
		state.Speed = 0
		local _, yaw = state.Home:ToEulerAnglesYXZ()
		state.Yaw = yaw
	end

	local throttle, steer = 0, 0
	if state.Driver ~= nil and now - state.LastInputAt <= INPUT_TIMEOUT then
		throttle, steer = state.Throttle, state.Steer
	end
	local maxSpeed = config.MaxSpeed
	if state.Race ~= nil then
		maxSpeed = state.Race.MaxSpeed
		if state.Race.Frozen then
			throttle, steer = 0, 0
		end
	end
	if state.Driver == nil and state.Speed == 0 then
		return -- parked: the LinearVelocity already holds it still
	end

	local speed = state.Speed
	if throttle > 0.05 then
		if speed < -0.5 then
			speed = moveToward(speed, 0, config.Braking * dt)
		else
			local target = maxSpeed * throttle
			speed = moveToward(speed, target, (if speed < target then config.Acceleration else config.Coast) * dt)
		end
	elseif throttle < -0.05 then
		if speed > 0.5 then
			speed = moveToward(speed, 0, config.Braking * dt)
		else
			speed = moveToward(speed, -config.ReverseSpeed * -throttle, config.Acceleration * dt)
		end
	else
		speed = moveToward(speed, 0, config.Coast * dt)
	end

	-- Blocked by something? Do not let the internal speed run away from reality.
	local heading = CFrame.Angles(0, state.Yaw, 0)
	local measured = base.AssemblyLinearVelocity:Dot(heading.LookVector)
	speed = math.clamp(speed, measured - SPEED_SLACK, measured + SPEED_SLACK)
	speed = math.clamp(speed, -config.ReverseSpeed, maxSpeed)
	if math.abs(speed) < 0.05 and throttle == 0 then
		speed = 0
	end
	state.Speed = speed

	local grip = math.clamp(math.abs(speed) / (maxSpeed * 0.3), 0, 1)
	local direction = if speed >= 0 then 1 else -1
	state.Yaw -= steer * config.TurnRate * grip * direction * dt
	heading = CFrame.Angles(0, state.Yaw, 0)
	local forward = heading.LookVector
	state.Linear.PlaneVelocity = Vector2.new(forward.X * speed, forward.Z * speed)
	state.Align.CFrame = heading
end

function Vehicle.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for entry in active do
			step(entry, dt, now)
		end
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("VehicleInput"), {
		Name = "VehicleInput",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.VehicleInput,
		Validate = function(throttle: any, steer: any): boolean
			return Validate.IsFiniteNumber(throttle) and Validate.IsFiniteNumber(steer)
		end,
	}, function(player: Player, throttle: number, steer: number)
		Vehicle.SetInput(player, throttle, steer)
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("VehicleSwitch"), {
		Name = "VehicleSwitch",
		MaxArgs = 0,
		RateLimit = GameConfig.RateLimits.VehicleSwitch,
	}, function(player: Player)
		local _, message = Vehicle.SwitchSeat(player)
		if message ~= nil then
			api.Notify(player, message)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		driverOf[player] = nil
	end)
end

return Vehicle
