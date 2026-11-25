--!strict
--[[
	DeployModels: the world-size models of placeable items (bicycle, scooter, car, cart, sled, radio).
	PLACEHOLDERS built from simple Parts; swap a builder for a real model later without touching
	any behavior code, as long as the named parts below stay.

	Shared: the server builds the real object, the client builds the same shape as a
	see-through placement preview (real = false), so the preview matches exactly.

	Conventions
	  - The model's pivot is the center of its footprint ON THE GROUND; -Z is the front.
	  - Every part is Anchored; behavior code unanchors what must move.
	  - "Base" is the root (PrimaryPart): the main body.
	  - Vehicles rest on invisible "Collider" balls at the wheels (they roll over curbs).
	  - Parts with attribute Spin = <radius> spin around their X axis while driving (wheels);
	    Crank parts have Spin too (pedals). Clients animate them.
	  - Seats ("DriverSeat" VehicleSeat, "PassengerSeat" Seat) exist only when real = true.

	API
	  Build(name, real) -> Model   "Item:<itemId>:<scale>" builds a bigger copy of that item's parts
	                               (first part = Base, the others Part2, Part3 ... as in Config/Items)
	  GetSize(name) -> Vector3     axis-aligned size of the model at the identity pivot
	  Exists(name) -> boolean
]]

local ItemConfig = require(script.Parent.Parent.Config.ItemConfig)
local JunkFactory = require(script.Parent.JunkFactory)

local DeployModels = {}

type Builder = (model: Model, real: boolean) -> ()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function addPart(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	position: Vector3,
	rotation: Vector3?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local r = rotation or Vector3.zero
	part.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	part.Parent = model
	return part
end

-- Invisible ball the vehicle rests on (at a wheel). Balls slide over curbs and small steps
-- lower than their radius, where a flat box would get stuck.
local function addCollider(model: Model, radius: number, position: Vector3)
	local part = Instance.new("Part")
	part.Name = "Collider"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * radius * 2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(position)
	part.Parent = model
end

local function addSeat(model: Model, name: string, driver: boolean, size: Vector3, position: Vector3, color: Color3, real: boolean)
	if not real then
		addPart(model, name, Enum.PartType.Block, size, color, Enum.Material.SmoothPlastic, position)
		return
	end
	local seat: BasePart
	if driver then
		local vehicleSeat = Instance.new("VehicleSeat")
		vehicleSeat.HeadsUpDisplay = false
		vehicleSeat.MaxSpeed = 0 -- no legacy hinge driving; the server moves the vehicle
		vehicleSeat.Torque = 0
		seat = vehicleSeat
	else
		seat = Instance.new("Seat")
	end
	seat.Name = name
	seat.Size = size
	seat.Color = color
	seat.Material = Enum.Material.SmoothPlastic
	seat.Anchored = true
	seat.CanCollide = false
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CFrame = CFrame.new(position)
	seat.Parent = model
end

local Block, Cylinder = Enum.PartType.Block, Enum.PartType.Cylinder
local M = Enum.Material
local V = Vector3.new
local UPRIGHT = V(0, 0, 90) -- stands a cylinder up (its axis is X)

local builders: { [string]: Builder } = {
	-- Bicycle: 2 wheels (diameter 2.6), orange frame, one seat.
	Bicycle = function(model: Model, real: boolean)
		local frame = rgb(255, 150, 30)
		local base = addPart(model, "Base", Block, V(1.4, 1.2, 4.4), frame, M.SmoothPlastic, V(0, 1.6, 0))
		base.Transparency = 1 -- the body's mass; it rests on the two ball colliders
		for index, z in { -1.65, 1.65 } do
			local wheel = addPart(model, "Wheel", Cylinder, V(0.3, 2.6, 2.6), rgb(36, 38, 46), M.Slate, V(0, 1.3, z))
			wheel:SetAttribute("Spin", 1.3)
			addPart(model, "Hub" .. index, Cylinder, V(0.34, 0.7, 0.7), rgb(200, 206, 214), M.Metal, V(0, 1.3, z))
			addCollider(model, 1.3, V(0, 1.3, z))
		end
		addPart(model, "TopTube", Cylinder, V(2.9, 0.28, 0.28), frame, M.Metal, V(0, 2.45, -0.05), V(0, 90, 0))
		addPart(model, "DownTube", Cylinder, V(2.4, 0.28, 0.28), frame, M.Metal, V(0, 1.75, -0.6), V(0, 90, -32))
		addPart(model, "SeatPost", Cylinder, V(1.6, 0.26, 0.26), frame, M.Metal, V(0, 2.0, 0.55), UPRIGHT)
		addPart(model, "Fork", Cylinder, V(1.7, 0.24, 0.24), rgb(200, 206, 214), M.Metal, V(0, 2.0, -1.5), V(0, 0, 90 - 12))
		addPart(model, "Handlebar", Cylinder, V(1.8, 0.22, 0.22), rgb(40, 42, 50), M.Metal, V(0, 2.95, -1.55))
		local crank = addPart(model, "Crank", Cylinder, V(0.2, 0.9, 0.9), rgb(200, 206, 214), M.Metal, V(0, 1.25, 0.35))
		crank:SetAttribute("Spin", 2.6) -- turns at half the wheel speed
		addSeat(model, "DriverSeat", true, V(0.8, 0.3, 1.1), V(0, 2.95, 0.7), rgb(40, 42, 50), real)
	end,

	-- Motor scooter: low deck, small wheels, seat box and a front shield.
	Scooter = function(model: Model, real: boolean)
		local paint = rgb(60, 150, 255)
		local base = addPart(model, "Base", Block, V(1.5, 1.1, 4.4), paint, M.SmoothPlastic, V(0, 1.3, 0))
		base.Transparency = 1
		for index, z in { -1.6, 1.6 } do
			local wheel = addPart(model, "Wheel", Cylinder, V(0.45, 1.5, 1.5), rgb(36, 38, 46), M.Slate, V(0, 0.75, z))
			wheel:SetAttribute("Spin", 0.75)
			addPart(model, "Hub" .. index, Cylinder, V(0.5, 0.6, 0.6), rgb(200, 206, 214), M.Metal, V(0, 0.75, z))
			addCollider(model, 0.75, V(0, 0.75, z))
		end
		addPart(model, "Deck", Block, V(1.2, 0.3, 2.4), paint, M.SmoothPlastic, V(0, 0.95, -0.2))
		addPart(model, "Tail", Block, V(1.3, 1.2, 1.7), paint, M.SmoothPlastic, V(0, 1.65, 1.3))
		addPart(model, "Shield", Block, V(1.3, 1.7, 0.25), paint, M.SmoothPlastic, V(0, 1.9, -1.25), V(12, 0, 0))
		addPart(model, "Column", Cylinder, V(2.2, 0.26, 0.26), rgb(200, 206, 214), M.Metal, V(0, 2.2, -1.5), V(0, 0, 90))
		addPart(model, "Handlebar", Cylinder, V(1.9, 0.22, 0.22), rgb(40, 42, 50), M.Metal, V(0, 3.2, -1.45))
		addPart(model, "Headlight", Cylinder, V(0.25, 0.6, 0.6), rgb(255, 240, 180), M.Neon, V(0, 2.5, -1.65), V(0, 90, 0))
		addPart(model, "Exhaust", Cylinder, V(1.1, 0.3, 0.3), rgb(120, 124, 132), M.Metal, V(0.75, 0.9, 1.7), V(0, 90, 0))
		addSeat(model, "DriverSeat", true, V(1, 0.3, 1.4), V(0, 2.4, 1.1), rgb(40, 42, 50), real)
	end,

	-- Wooden sled: planks on two metal runners, with a rope bar at the front.
	WoodenSled = function(model: Model, _real: boolean)
		local wood = rgb(176, 124, 74)
		local base = addPart(model, "Base", Block, V(2.1, 0.3, 3.4), wood, M.WoodPlanks, V(0, 0.65, 0))
		base.CanCollide = true
		for _, x in { -0.8, 0.8 } do
			addPart(model, "Runner", Block, V(0.2, 0.2, 4.1), rgb(70, 76, 90), M.Metal, V(x, 0.1, -0.1))
			for _, z in { -1.1, 1.1 } do
				addPart(model, "Leg", Block, V(0.2, 0.35, 0.3), rgb(124, 82, 52), M.Wood, V(x, 0.35, z))
			end
			addPart(model, "Rail", Block, V(0.15, 0.35, 3.2), rgb(124, 82, 52), M.Wood, V(x * 1.25, 0.95, 0))
		end
		addPart(model, "Back", Block, V(2.1, 0.7, 0.2), rgb(124, 82, 52), M.WoodPlanks, V(0, 1.1, 1.55))
		addPart(model, "Front", Block, V(2.1, 0.4, 0.2), rgb(124, 82, 52), M.WoodPlanks, V(0, 0.95, -1.6))
		addPart(model, "Rope", Cylinder, V(1.6, 0.12, 0.12), rgb(230, 210, 170), M.Fabric, V(0, 1.2, -2.3), V(0, 90, -30))
		addPart(model, "Grip", Cylinder, V(1.1, 0.18, 0.18), rgb(236, 74, 70), M.SmoothPlastic, V(0, 1.6, -3))
	end,

	-- Homemade car: an off-road roadster welded together in the yard. The invisible Base is its
	-- mass; body, fenders, doors, roll cage, lights and spare wheel are decoration.
	HomemadeCar = function(model: Model, real: boolean)
		local paint, dark, steel, chrome = rgb(206, 48, 44), rgb(28, 30, 38), rgb(112, 120, 134), rgb(206, 212, 222)
		local cream, rust, black = rgb(246, 238, 218), rgb(146, 84, 48), rgb(18, 19, 24)
		local glossy, metal = M.SmoothPlastic, M.Metal
		local base = addPart(model, "Base", Block, V(4.6, 1.3, 8.2), paint, glossy, V(0, 1.55, 0))
		base.CanCollide = true
		base.Transparency = 1
		-- Wheels: knobbly tyre, steel rim, spokes, hub cap
		for _, side in { -1, 1 } do
			for _, z in { -2.7, 2.7 } do
				local x = 2.45 * side
				local function turning(p: Part)
					p:SetAttribute("Spin", 1.1)
				end
				turning(addPart(model, "Wheel", Cylinder, V(0.8, 2.2, 2.2), black, M.Slate, V(x, 1.1, z)))
				for lug = 0, 3 do
					turning(addPart(model, "Lug", Block, V(0.86, 2.3, 0.34), black, M.Slate, V(x, 1.1, z), V(lug * 45, 0, 0)))
				end
				turning(addPart(model, "Rim", Cylinder, V(0.9, 1.3, 1.3), steel, metal, V(x, 1.1, z)))
				for spoke = 0, 2 do
					turning(addPart(model, "Spoke", Block, V(0.96, 1.24, 0.2), chrome, metal, V(x, 1.1, z), V(spoke * 60, 0, 0)))
				end
				addPart(model, "HubCap", Cylinder, V(1.02, 0.42, 0.42), rgb(255, 205, 50), metal, V(x, 1.1, z))
				addCollider(model, 1.1, V(x, 1.1, z))
				-- Fender around the wheel
				addPart(model, "Fender", Block, V(1.1, 0.2, 1.7), paint, glossy, V(2.4 * side, 2.5, z))
				addPart(model, "Fender", Block, V(1.1, 0.2, 1.1), paint, glossy, V(2.4 * side, 2.2, z - 1.22), V(-40, 0, 0))
				addPart(model, "Fender", Block, V(1.1, 0.2, 1.1), paint, glossy, V(2.4 * side, 2.2, z + 1.22), V(40, 0, 0))
				addPart(model, "Axle", Cylinder, V(1.6, 0.26, 0.26), dark, metal, V(1.4 * side, 1.1, z))
			end
			-- Running board, door, handle, number, mirror, side pipe
			addPart(model, "Board", Block, V(0.8, 0.16, 2.7), dark, M.DiamondPlate, V(2.45 * side, 1.15, 0))
			addPart(model, "Door", Block, V(0.24, 1.1, 2.3), paint, glossy, V(2.05 * side, 2.25, 0.35))
			addPart(model, "DoorTop", Block, V(0.32, 0.14, 2.4), dark, M.Leather, V(2.05 * side, 2.85, 0.35))
			addPart(model, "Handle", Block, V(0.12, 0.12, 0.5), chrome, metal, V(2.22 * side, 2.55, 1.05))
			addPart(model, "Number", Cylinder, V(0.06, 0.9, 0.9), cream, glossy, V(2.19 * side, 2.25, 0.2))
			addPart(model, "Seven", Block, V(0.07, 0.1, 0.4), dark, glossy, V(2.2 * side, 2.48, 0.2))
			addPart(model, "Seven", Block, V(0.07, 0.5, 0.1), dark, glossy, V(2.2 * side, 2.25, 0.2 - 0.1 * side), V(-22 * side, 0, 0))
			addPart(model, "MirrorArm", Cylinder, V(0.5, 0.08, 0.08), chrome, metal, V(2.1 * side, 3.15, -1), V(0, 0, 20 * side))
			addPart(model, "Mirror", Block, V(0.4, 0.3, 0.12), chrome, metal, V(2.4 * side, 3.25, -1))
			addPart(model, "SidePipe", Cylinder, V(3, 0.28, 0.28), chrome, metal, V(2.15 * side, 1.35, -0.2), V(0, 90, 0))
			-- Lights
			addPart(model, "LampRing", Cylinder, V(0.3, 0.9, 0.9), chrome, metal, V(1.3 * side, 2.1, -4.02), V(0, 90, 0))
			addPart(model, "Headlight", Cylinder, V(0.34, 0.68, 0.68), rgb(255, 242, 190), M.Neon, V(1.3 * side, 2.1, -4.04), V(0, 90, 0))
			addPart(model, "Blinker", Block, V(0.4, 0.2, 0.1), rgb(255, 150, 40), M.Neon, V(1.45 * side, 1.5, -3.98))
			addPart(model, "TailRing", Block, V(0.6, 0.4, 0.1), chrome, metal, V(1.6 * side, 1.95, 4.32))
			addPart(model, "TailLight", Block, V(0.46, 0.28, 0.12), rgb(255, 50, 50), M.Neon, V(1.6 * side, 1.95, 4.34))
			-- Windshield posts and roll cage
			addPart(model, "Post", Cylinder, V(2.2, 0.16, 0.16), dark, metal, V(1.85 * side, 3.6, -0.85), V(0, 90, 70))
			addPart(model, "Cage", Cylinder, V(3.6, 0.24, 0.24), steel, metal, V(1.8 * side, 3.9, 2.1), UPRIGHT)
			addPart(model, "CageBrace", Cylinder, V(3.1, 0.2, 0.2), steel, metal, V(1.6 * side, 3.4, 3.2), V(0, 90, 38))
		end
		-- Frame, cabin, engine bay, tail
		addPart(model, "Chassis", Block, V(3.2, 0.4, 8), dark, metal, V(0, 1.05, 0))
		addPart(model, "Cabin", Block, V(4, 0.7, 3), paint, glossy, V(0, 1.5, 0.5))
		addPart(model, "Nose", Block, V(3.2, 1.2, 2.9), paint, glossy, V(0, 1.85, -2.45))
		addPart(model, "Hood", Block, V(3.3, 0.22, 2.9), paint, glossy, V(0, 2.52, -2.45), V(-4, 0, 0))
		addPart(model, "Tail", Block, V(3.6, 1.1, 2.2), paint, glossy, V(0, 1.85, 3.15))
		addPart(model, "TailLid", Block, V(3.7, 0.16, 2.2), dark, M.DiamondPlate, V(0, 2.48, 3.15))
		for _, x in { -0.5, 0.5 } do -- racing stripes
			addPart(model, "Stripe", Block, V(0.36, 0.05, 2.9), cream, glossy, V(x, 2.65, -2.45), V(-4, 0, 0))
		end
		-- Engine: blower through the hood
		addPart(model, "Blower", Block, V(1.2, 0.55, 1.2), steel, metal, V(0, 2.95, -2.5))
		addPart(model, "Scoop", Block, V(1.3, 0.5, 0.7), chrome, metal, V(0, 3.4, -2.75), V(-10, 0, 0))
		addPart(model, "ScoopMouth", Block, V(1.1, 0.3, 0.1), black, glossy, V(0, 3.44, -3.12), V(-10, 0, 0))
		for _, z in { -2.95, -2.5, -2.05 } do
			addPart(model, "Header", Cylinder, V(3.6, 0.22, 0.22), chrome, metal, V(0, 2.15, z))
		end
		-- Grille and bumpers
		addPart(model, "Grille", Block, V(1.7, 0.95, 0.12), black, glossy, V(0, 1.95, -3.92))
		for index = 0, 4 do
			addPart(model, "GrilleBar", Block, V(0.1, 0.95, 0.12), chrome, metal, V(-0.7 + index * 0.35, 1.95, -4))
		end
		addPart(model, "Bumper", Cylinder, V(4.4, 0.4, 0.4), chrome, metal, V(0, 1.2, -4.25))
		addPart(model, "BullBar", Cylinder, V(2.2, 0.2, 0.2), dark, metal, V(0, 1.75, -4.3))
		for _, x in { -0.9, 0.9 } do
			addPart(model, "BullPost", Cylinder, V(0.8, 0.2, 0.2), dark, metal, V(x, 1.5, -4.3), UPRIGHT)
		end
		addPart(model, "RearBumper", Cylinder, V(4, 0.36, 0.36), chrome, metal, V(0, 1.2, 4.4))
		addPart(model, "Plate", Block, V(1.1, 0.5, 0.06), cream, glossy, V(0, 1.75, 4.3))
		addPart(model, "PlateText", Block, V(0.8, 0.16, 0.07), rgb(40, 70, 150), glossy, V(0, 1.75, 4.31))
		for _, x in { -0.7, 0.7 } do
			addPart(model, "Exhaust", Cylinder, V(0.9, 0.34, 0.34), steel, metal, V(x, 1, 4.4), V(0, 90, 0))
		end
		-- Spare wheel and jerry can on the tail
		addPart(model, "Spare", Cylinder, V(0.6, 1.9, 1.9), black, M.Slate, V(0.6, 2.88, 3.25), UPRIGHT)
		addPart(model, "SpareRim", Cylinder, V(0.66, 1, 1), steel, metal, V(0.6, 2.88, 3.25), UPRIGHT)
		addPart(model, "JerryCan", Block, V(0.9, 1, 0.5), rgb(90, 110, 60), glossy, V(-1, 3.05, 3.4), V(0, 12, 0))
		addPart(model, "JerryCap", Cylinder, V(0.2, 0.24, 0.24), dark, metal, V(-1.2, 3.62, 3.4), UPRIGHT)
		-- Patches of the yard: rust and a riveted plate
		addPart(model, "Rust", Block, V(0.06, 0.5, 0.8), rust, M.CorrodedMetal, V(-1.62, 1.7, -2.2))
		addPart(model, "Rust", Block, V(0.8, 0.05, 0.5), rust, M.CorrodedMetal, V(1.1, 2.64, -1.6), V(-4, 0, 0))
		addPart(model, "Rust", Block, V(0.06, 0.4, 1), rust, M.CorrodedMetal, V(1.82, 1.7, 3.2))
		addPart(model, "Patch", Block, V(0.08, 0.7, 0.9), steel, M.DiamondPlate, V(1.62, 1.8, -2.4))
		-- Windshield, cage top, lamps
		addPart(model, "Windshield", Block, V(3.6, 1.8, 0.1), rgb(150, 215, 255), M.Glass, V(0, 3.6, -0.85), V(20, 0, 0)).Transparency = 0.55
		addPart(model, "ShieldTop", Cylinder, V(3.9, 0.18, 0.18), dark, metal, V(0, 4.6, -0.48))
		addPart(model, "CageTop", Cylinder, V(3.8, 0.24, 0.24), steel, metal, V(0, 5.7, 2.1))
		addPart(model, "CageMid", Cylinder, V(3.6, 0.2, 0.2), steel, metal, V(0, 3.6, 2.1))
		addPart(model, "LampBar", Block, V(3, 0.14, 0.3), dark, metal, V(0, 5.9, 2.05))
		for index = 0, 3 do
			addPart(model, "RoofLamp", Cylinder, V(0.3, 0.56, 0.56), dark, metal, V(-1.2 + index * 0.8, 6.18, 2.05), V(0, 90, 0))
			addPart(model, "RoofLight", Cylinder, V(0.32, 0.42, 0.42), rgb(255, 244, 200), M.Neon, V(-1.2 + index * 0.8, 6.18, 2.03), V(0, 90, 0))
		end
		-- Cockpit
		addPart(model, "Dashboard", Block, V(3.8, 0.5, 0.5), dark, M.Leather, V(0, 2.7, -0.75))
		for _, x in { -1.35, -0.75 } do
			addPart(model, "Gauge", Cylinder, V(0.1, 0.36, 0.36), rgb(120, 240, 190), M.Neon, V(x, 2.75, -0.48), V(0, 90, 0))
		end
		addPart(model, "SteeringColumn", Cylinder, V(1.1, 0.18, 0.18), steel, metal, V(-1.05, 2.75, -0.35), V(0, 90, -30))
		addPart(model, "SteeringWheel", Cylinder, V(0.16, 1.2, 1.2), black, M.Leather, V(-1.05, 3, 0.05), V(0, 90, -30))
		addPart(model, "SteeringHub", Cylinder, V(0.2, 0.45, 0.45), rgb(255, 205, 50), metal, V(-1.05, 3.02, 0.08), V(0, 90, -30))
		addPart(model, "GearStick", Cylinder, V(0.9, 0.12, 0.12), chrome, metal, V(0, 2.3, 0.2), V(0, 0, 80))
		addPart(model, "GearKnob", Enum.PartType.Ball, V(0.3, 0.3, 0.3), paint, glossy, V(0.07, 2.78, 0.2))
		for _, x in { -1.05, 1.05 } do
			addPart(model, "SeatBack", Block, V(1.5, 1.6, 0.35), dark, M.Leather, V(x, 2.95, 1.85), V(10, 0, 0))
			addPart(model, "SeatStripe", Block, V(0.4, 1.62, 0.37), paint, M.Leather, V(x, 2.95, 1.84), V(10, 0, 0))
		end
		addSeat(model, "DriverSeat", true, V(1.5, 0.4, 1.5), V(-1.05, 2.1, 0.95), dark, real)
		addSeat(model, "PassengerSeat", false, V(1.5, 0.4, 1.5), V(1.05, 2.1, 0.95), dark, real)
	end,

	-- Metal cart: open tub on 4 small wheels with a handle at the front (towards the owner).
	MetalCart = function(model: Model, _real: boolean)
		local metal = rgb(150, 170, 196)
		local base = addPart(model, "Base", Block, V(3.4, 0.3, 4.4), metal, M.Metal, V(0, 0.95, 0))
		base.CanCollide = true
		addPart(model, "WallL", Block, V(0.2, 1.3, 4.4), metal, M.Metal, V(-1.6, 1.7, 0))
		addPart(model, "WallR", Block, V(0.2, 1.3, 4.4), metal, M.Metal, V(1.6, 1.7, 0))
		addPart(model, "WallF", Block, V(3.4, 1.3, 0.2), metal, M.Metal, V(0, 1.7, -2.1))
		addPart(model, "WallB", Block, V(3.4, 1.3, 0.2), metal, M.Metal, V(0, 1.7, 2.1))
		local rim = rgb(255, 150, 30)
		addPart(model, "RimL", Block, V(0.3, 0.15, 4.6), rim, M.Metal, V(-1.65, 2.38, 0))
		addPart(model, "RimR", Block, V(0.3, 0.15, 4.6), rim, M.Metal, V(1.65, 2.38, 0))
		addPart(model, "RimF", Block, V(3.6, 0.15, 0.3), rim, M.Metal, V(0, 2.38, -2.15))
		addPart(model, "RimB", Block, V(3.6, 0.15, 0.3), rim, M.Metal, V(0, 2.38, 2.15))
		for _, x in { -1.3, 1.3 } do
			for _, z in { -1.5, 1.5 } do
				local wheel = addPart(model, "Wheel", Cylinder, V(0.3, 0.9, 0.9), rgb(36, 38, 46), M.Slate, V(x, 0.45, z))
				wheel:SetAttribute("Spin", 0.45)
			end
		end
		addPart(model, "Handle", Cylinder, V(1.6, 0.18, 0.18), rgb(40, 42, 50), M.Metal, V(0, 2.2, -2.9), V(0, 90, -25))
		addPart(model, "Grip", Cylinder, V(1.8, 0.24, 0.24), rgb(255, 150, 30), M.SmoothPlastic, V(0, 2.55, -3.6))
	end,

	-- Boombox radio on the ground.
	Radio = function(model: Model, _real: boolean)
		local base = addPart(model, "Base", Block, V(3.4, 2.0, 1.3), rgb(70, 160, 230), M.SmoothPlastic, V(0, 1.0, 0))
		base.CanCollide = true
		for _, x in { -1.0, 1.0 } do
			addPart(model, "Speaker", Cylinder, V(0.12, 1.25, 1.25), rgb(40, 40, 46), M.Slate, V(x, 0.95, -0.66), V(0, 90, 0))
			addPart(model, "Cone", Cylinder, V(0.14, 0.5, 0.5), rgb(200, 206, 214), M.Metal, V(x, 0.95, -0.7), V(0, 90, 0))
		end
		addPart(model, "Display", Block, V(1.0, 0.45, 0.1), rgb(255, 210, 60), M.Neon, V(0, 1.6, -0.66)).Name = "Light"
		addPart(model, "Handle", Block, V(2.6, 0.2, 0.3), rgb(40, 42, 50), M.Metal, V(0, 2.35, 0))
		addPart(model, "Antenna", Cylinder, V(1.6, 0.08, 0.08), rgb(200, 206, 214), M.Metal, V(1.3, 2.7, 0.3), V(0, 0, 70))
	end,
}

-- Turbo kart: an open-wheel formula racer (nose, wings, side pods, engine, suspension).
builders.TurboKart = function(model: Model, real: boolean)
	local paint, dark, carbon, steel, white = rgb(214, 32, 40), rgb(22, 24, 30), rgb(44, 48, 58), rgb(176, 184, 196), rgb(245, 246, 250)
	local glossy, metal = M.SmoothPlastic, M.Metal
	local base = addPart(model, "Base", Block, V(1.9, 0.5, 8.2), carbon, glossy, V(0, 0.75, 0))
	base.CanCollide = true
	-- Wheels: slick tyre, rim, hub nut
	for _, side in { -1, 1 } do
		for _, axle in { { -2.75, 1.9, 0.8, 1.75 }, { 2.75, 2.2, 1.15, 1.85 } } do
			local z, diameter, width, x = axle[1], axle[2], axle[3], axle[4] * side
			local radius = diameter / 2
			local wheel = addPart(model, "Wheel", Cylinder, V(width, diameter, diameter), dark, M.Slate, V(x, radius, z))
			wheel:SetAttribute("Spin", radius)
			local rim = addPart(model, "Rim", Cylinder, V(width + 0.06, diameter * 0.58, diameter * 0.58), steel, metal, V(x, radius, z))
			rim:SetAttribute("Spin", radius)
			for spoke = 0, 2 do
				local bar = addPart(model, "Spoke", Block, V(width + 0.1, diameter * 0.54, 0.16), carbon, metal, V(x, radius, z), V(spoke * 60, 0, 0))
				bar:SetAttribute("Spin", radius)
			end
			addPart(model, "Nut", Cylinder, V(width + 0.2, 0.24, 0.24), rgb(255, 205, 50), metal, V(x, radius, z))
			addCollider(model, radius, V(x, radius, z))
			-- Suspension arms
			addPart(model, "Arm", Cylinder, V(1.3, 0.14, 0.14), dark, metal, V(side * 1.15, radius + 0.2, z - 0.3), V(0, 12 * side, 0))
			addPart(model, "Arm", Cylinder, V(1.3, 0.14, 0.14), dark, metal, V(side * 1.15, radius - 0.15, z + 0.3), V(0, -12 * side, 0))
		end
		-- Side pods with air intakes, mirrors, floor edge
		addPart(model, "SidePod", Block, V(0.9, 0.95, 3), paint, glossy, V(side * 1.25, 1.2, 0.75))
		addPart(model, "PodNose", Cylinder, V(0.95, 0.9, 0.9), dark, glossy, V(side * 1.25, 1.2, -0.72), V(0, 90, 0))
		addPart(model, "PodStripe", Block, V(0.06, 0.3, 2.9), white, glossy, V(side * 1.72, 1.35, 0.75))
		addPart(model, "Floor", Block, V(0.9, 0.12, 4), carbon, glossy, V(side * 1.3, 0.62, 0.5))
		addPart(model, "MirrorStalk", Cylinder, V(0.6, 0.08, 0.08), dark, metal, V(side * 0.95, 1.95, -0.95))
		addPart(model, "Mirror", Block, V(0.4, 0.28, 0.18), paint, glossy, V(side * 1.25, 2.05, -0.95))
		addPart(model, "CockpitSide", Block, V(0.22, 0.7, 2.2), paint, glossy, V(side * 0.85, 1.6, 0.2))
		addPart(model, "Exhaust", Cylinder, V(1, 0.34, 0.34), steel, metal, V(side * 0.4, 1.5, 3.3), V(0, 90, 0))
		addPart(model, "Flame", Cylinder, V(0.12, 0.26, 0.26), rgb(255, 130, 50), M.Neon, V(side * 0.4, 1.5, 3.83), V(0, 90, 0))
		-- Rear wing end plate, front wing end plate
		addPart(model, "EndPlate", Block, V(0.12, 1.4, 1.1), dark, glossy, V(side * 1.5, 2.6, 3.7))
		addPart(model, "FrontPlate", Block, V(0.12, 0.6, 1), dark, glossy, V(side * 1.75, 0.65, -4.7))
		addPart(model, "Halo", Cylinder, V(1.7, 0.16, 0.16), dark, metal, V(side * 0.42, 2.5, 0.05), V(0, 90 + side * 22, 0))
	end
	-- Nose and front wing
	addPart(model, "Monocoque", Block, V(1.6, 0.9, 2.6), paint, glossy, V(0, 1.3, -1.9), V(-3, 0, 0))
	addPart(model, "Nose", Block, V(1.1, 0.6, 1.8), paint, glossy, V(0, 1.1, -3.7), V(-9, 0, 0))
	addPart(model, "NoseTip", Cylinder, V(0.7, 0.5, 0.5), white, glossy, V(0, 0.9, -4.75), V(0, 90, 0))
	addPart(model, "NoseStripe", Block, V(0.4, 0.06, 4.2), white, glossy, V(0, 1.72, -2.9), V(-7, 0, 0))
	addPart(model, "FrontWing", Block, V(3.6, 0.12, 0.9), dark, glossy, V(0, 0.45, -4.75), V(6, 0, 0))
	addPart(model, "FrontFlap", Block, V(3.5, 0.1, 0.4), paint, glossy, V(0, 0.72, -4.4), V(22, 0, 0))
	addPart(model, "HaloFront", Cylinder, V(0.8, 0.16, 0.16), dark, metal, V(0, 2.15, -0.95), V(0, 0, 70))
	-- Steering wheel and dash
	addPart(model, "Dash", Block, V(1.3, 0.25, 0.3), carbon, glossy, V(0, 1.85, -0.75))
	addPart(model, "SteeringWheel", Block, V(0.8, 0.45, 0.14), dark, glossy, V(0, 1.95, -0.4), V(-20, 0, 0))
	addPart(model, "Display", Block, V(0.34, 0.2, 0.05), rgb(90, 240, 160), M.Neon, V(0, 2.0, -0.31), V(-20, 0, 0))
	-- Engine cover, air box, shark fin, rear wing, rain light, diffuser
	addPart(model, "AirBox", Block, V(0.9, 1.2, 0.8), paint, glossy, V(0, 2.1, 1.75))
	addPart(model, "Intake", Cylinder, V(0.1, 0.6, 0.6), dark, glossy, V(0, 2.4, 1.33), V(0, 90, 0))
	addPart(model, "EngineCover", Block, V(1.2, 1, 2.2), paint, glossy, V(0, 1.6, 2.4), V(8, 0, 0))
	addPart(model, "Fin", Block, V(0.1, 0.8, 1.8), white, glossy, V(0, 2.4, 2.7), V(10, 0, 0))
	addPart(model, "RearWing", Block, V(3, 0.14, 0.9), paint, glossy, V(0, 3, 3.75), V(10, 0, 0))
	addPart(model, "RearFlap", Block, V(3, 0.12, 0.5), dark, glossy, V(0, 3.3, 4.05), V(28, 0, 0))
	addPart(model, "WingPost", Block, V(0.14, 1.6, 0.5), dark, glossy, V(0, 2.2, 3.7))
	addPart(model, "RainLight", Block, V(0.3, 0.3, 0.1), rgb(255, 50, 50), M.Neon, V(0, 1.2, 4.12))
	addPart(model, "Diffuser", Block, V(1.8, 0.35, 0.8), dark, glossy, V(0, 0.75, 4), V(-18, 0, 0))
	addSeat(model, "DriverSeat", true, V(1.2, 0.35, 1.4), V(0, 1.15, 0.65), dark, real)
end

-- Jet board: a hovering board; invisible rollers keep it above the ground.
builders.JetBoard = function(model: Model, real: boolean)
	local base = addPart(model, "Base", Block, V(2, 0.4, 5.2), rgb(70, 210, 240), M.SmoothPlastic, V(0, 1.1, 0))
	base.CanCollide = true
	for _, z in { -1.8, 1.8 } do
		addCollider(model, 0.8, V(0, 0.8, z))
	end
	addPart(model, "Nose", Block, V(1.6, 0.35, 1.2), rgb(236, 74, 70), M.SmoothPlastic, V(0, 1.3, -2.9), V(20, 0, 0))
	for _, x in { -0.8, 0.8 } do
		addPart(model, "Blade", Block, V(0.15, 0.4, 4.4), rgb(220, 230, 240), M.Metal, V(x, 0.75, 0))
		addPart(model, "Jet", Cylinder, V(1.4, 0.7, 0.7), rgb(60, 66, 90), M.Metal, V(x, 1.5, 2.2), V(0, 90, 0))
		addPart(model, "Flame", Cylinder, V(0.3, 0.55, 0.55), rgb(80, 220, 255), M.Neon, V(x, 1.5, 2.95), V(0, 90, 0))
	end
	addPart(model, "Column", Cylinder, V(1.8, 0.22, 0.22), rgb(200, 206, 214), M.Metal, V(0, 2.1, -1.6), UPRIGHT)
	addPart(model, "Handlebar", Cylinder, V(1.6, 0.2, 0.2), rgb(40, 42, 50), M.Metal, V(0, 3, -1.6))
	addSeat(model, "DriverSeat", true, V(1, 0.3, 1.3), V(0, 1.75, 0.5), rgb(40, 42, 50), real)
end

-- Golden throne with a real seat.
builders.GoldenThrone = function(model: Model, real: boolean)
	local gold = rgb(255, 205, 50)
	local base = addPart(model, "Base", Block, V(4.2, 1.6, 3.6), gold, M.Metal, V(0, 0.8, 0))
	base.CanCollide = true
	addPart(model, "Cushion", Block, V(2.8, 0.3, 2.6), rgb(190, 40, 70), M.Fabric, V(0, 1.75, -0.2))
	addPart(model, "Back", Block, V(3.4, 5, 0.6), gold, M.Metal, V(0, 4, 1.5)).CanCollide = true
	addPart(model, "BackCushion", Block, V(2.4, 3.4, 0.2), rgb(190, 40, 70), M.Fabric, V(0, 3.7, 1.15))
	for _, x in { -1.75, 1.75 } do
		addPart(model, "Arm", Block, V(0.6, 1.2, 3), gold, M.Metal, V(x, 2.2, 0))
		addPart(model, "Knob", Enum.PartType.Ball, V(0.9, 0.9, 0.9), rgb(120, 210, 255), M.Neon, V(x, 6.6, 1.5))
	end
	addPart(model, "Crown", Block, V(2, 0.5, 0.7), rgb(150, 220, 255), M.Neon, V(0, 6.8, 1.5))
	addSeat(model, "ThroneSeat", false, V(2, 0.3, 2), V(0, 1.95, -0.2), rgb(190, 40, 70), real)
	local seat = model:FindFirstChild("ThroneSeat") :: BasePart
	seat.CanTouch = false -- only the prompt seats somebody
	seat.Transparency = 1
end

-- "Item:<id>:<scale>": the item's own parts, bigger, standing on the ground.
local function itemBuilder(name: string): Builder?
	local id, scaleText = string.match(name, "^Item:([%w_]+):([%d%.]+)$")
	local definition = if id ~= nil then ItemConfig.Get(id) else nil
	local bounds = if id ~= nil then JunkFactory.GetBounds(id) else nil
	local scale = tonumber(scaleText)
	if definition == nil or definition.Parts == nil or bounds == nil or scale == nil then
		return nil
	end
	local parts = definition.Parts
	return function(model: Model, _real: boolean)
		for index, spec in parts do
			local part = addPart(model, if index == 1 then "Base" else `Part{index}`, spec.Shape, spec.Size * scale, spec.Color,
				spec.Material, (spec.Offset - Vector3.new(0, bounds.Min.Y, 0)) * scale, spec.Rotation)
			part.CanCollide = true
			if spec.Material == M.Glass then
				part.Transparency = 0.4
			end
		end
	end
end

local function findBuilder(name: string): Builder?
	return builders[name] or itemBuilder(name)
end

local sizeCache: { [string]: Vector3 } = {}

function DeployModels.Exists(name: string): boolean
	return findBuilder(name) ~= nil
end

function DeployModels.Build(name: string, real: boolean): Model
	local builder = findBuilder(name)
	assert(builder ~= nil, `[DeployModels] unknown model "{name}"`)
	local model = Instance.new("Model")
	model.Name = name
	builder(model, real)
	local base = model:FindFirstChild("Base")
	assert(base ~= nil and base:IsA("BasePart"), `[DeployModels] "{name}" has no Base part`)
	model.PrimaryPart = base
	-- With a PrimaryPart the model pivots around base.CFrame * PivotOffset: put that point at
	-- the origin = the footprint's center on the ground (WorldPivot alone would be ignored).
	base.PivotOffset = base.CFrame:ToObjectSpace(CFrame.new())
	return model
end

function DeployModels.GetSize(name: string): Vector3
	local cached = sizeCache[name]
	if cached ~= nil then
		return cached
	end
	local model = DeployModels.Build(name, false)
	local _, size = model:GetBoundingBox()
	model:Destroy()
	sizeCache[name] = size
	return size
end

return DeployModels
