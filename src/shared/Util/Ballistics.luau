--!strict
--[[
	Ballistics: the throw arc, shared so the server (authority) and the client (aim preview and
	flight visual) compute exactly the same curve.

	  Solve(origin, aimTarget, fallbackDirection) -> velocity
	      Velocity for a throw at GameConfig.Throw.LaunchAngle that lands at aimTarget, with
	      the horizontal distance clamped to [MinRange, MaxRange] and the speed clamped to what
	      MaxRange needs on flat ground. The caller never chooses the speed directly.
	  PositionAt(origin, velocity, gravity, t) -> Vector3
	  Simulate(origin, velocity, params) -> Hit
	      Walks the arc in SimulationStep segments with one raycast each, up to MaxFlightTime.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

export type Hit = {
	Position: Vector3,
	Normal: Vector3?, -- nil when nothing was hit before MaxFlightTime
	Instance: Instance?,
	Time: number, -- seconds from release to Position
}

local Ballistics = {}

local UP = Vector3.new(0, 1, 0)
local EPSILON = 1e-3

local function config()
	return GameConfig.Throw
end

function Ballistics.GetGravity(): number
	return config().Gravity
end

-- Highest launch speed: the speed that reaches MaxRange on flat ground.
function Ballistics.GetMaxSpeed(): number
	local throw = config()
	local angle = math.rad(throw.LaunchAngle)
	return math.sqrt(throw.Gravity * throw.MaxRange / math.sin(2 * angle))
end

function Ballistics.Solve(origin: Vector3, aimTarget: Vector3, fallbackDirection: Vector3): Vector3
	local throw = config()
	local angle = math.rad(throw.LaunchAngle)
	local gravity = throw.Gravity

	local flat = Vector3.new(aimTarget.X - origin.X, 0, aimTarget.Z - origin.Z)
	local direction: Vector3
	local distance = flat.Magnitude
	if distance < EPSILON then
		local fallbackFlat = Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		direction = if fallbackFlat.Magnitude > EPSILON then fallbackFlat.Unit else Vector3.new(0, 0, -1)
		distance = throw.MinRange
	else
		direction = flat.Unit
	end
	distance = math.clamp(distance, throw.MinRange, throw.MaxRange)

	-- Height difference to the target, limited so absurd aim points cannot produce odd arcs.
	local rise = math.clamp(aimTarget.Y - origin.Y, -throw.MaxRange, throw.MaxRange)

	-- Speed for a fixed launch angle that passes through (distance, rise).
	local cos = math.cos(angle)
	local denominator = 2 * cos * cos * (distance * math.tan(angle) - rise)
	local maxSpeed = Ballistics.GetMaxSpeed()
	local speed = maxSpeed
	if denominator > EPSILON then
		speed = math.sqrt(gravity * distance * distance / denominator)
	end
	speed = math.clamp(speed, 0, maxSpeed)

	return direction * (speed * cos) + UP * (speed * math.sin(angle))
end

function Ballistics.PositionAt(origin: Vector3, velocity: Vector3, gravity: number, t: number): Vector3
	return origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
end

function Ballistics.Simulate(origin: Vector3, velocity: Vector3, params: RaycastParams): Hit
	local throw = config()
	local gravity = throw.Gravity
	local step = math.max(throw.SimulationStep, 1 / 120)
	local maxTime = throw.MaxFlightTime

	local previous = origin
	local t = 0
	while t < maxTime do
		local nextT = math.min(t + step, maxTime)
		local point = Ballistics.PositionAt(origin, velocity, gravity, nextT)
		local segment = point - previous
		local result = workspace:Raycast(previous, segment, params)
		if result ~= nil then
			local fraction = if segment.Magnitude > EPSILON
				then (result.Position - previous).Magnitude / segment.Magnitude
				else 0
			return {
				Position = result.Position,
				Normal = result.Normal,
				Instance = result.Instance,
				Time = t + (nextT - t) * fraction,
			}
		end
		previous = point
		t = nextT
	end

	return { Position = previous, Normal = nil, Instance = nil, Time = maxTime }
end

return Ballistics
