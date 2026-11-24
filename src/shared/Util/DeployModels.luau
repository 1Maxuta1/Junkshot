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

	-- Homemade car: open-top body, 4 tires, roll bar, driver + passenger seat.
	HomemadeCar = function(model: Model, real: boolean)
		local paint = rgb(236, 74, 70)
		local base = addPart(model, "Base", Block, V(4.6, 1.3, 8.2), paint, M.SmoothPlastic, V(0, 1.55, 0))
		base.CanCollide = true
		for _, x in { -2.45, 2.45 } do
			for _, z in { -2.7, 2.7 } do
				local wheel = addPart(model, "Wheel", Cylinder, V(0.7, 2.2, 2.2), rgb(36, 38, 46), M.Slate, V(x, 1.1, z))
				wheel:SetAttribute("Spin", 1.1)
				addCollider(model, 1.1, V(x, 1.1, z))
			end
		end
		addPart(model, "Hood", Block, V(4.2, 0.5, 2.6), rgb(214, 60, 56), M.SmoothPlastic, V(0, 2.4, -2.6))
		addPart(model, "Engine", Block, V(1.8, 0.8, 1.4), rgb(70, 80, 96), M.Metal, V(0, 2.95, -2.7))
		addPart(model, "Windshield", Block, V(4.0, 1.4, 0.15), rgb(140, 210, 255), M.Glass, V(0, 2.9, -1.15), V(-15, 0, 0)).Transparency = 0.4
		addPart(model, "RollBar", Block, V(4.2, 1.6, 0.3), rgb(200, 206, 214), M.Metal, V(0, 3.0, 2.6))
		addPart(model, "Bumper", Block, V(4.8, 0.5, 0.4), rgb(200, 206, 214), M.Metal, V(0, 1.2, -4.2))
		for _, x in { -1.5, 1.5 } do
			addPart(model, "Headlight", Cylinder, V(0.2, 0.6, 0.6), rgb(255, 240, 180), M.Neon, V(x, 1.75, -4.15), V(0, 90, 0))
		end
		addPart(model, "Exhaust", Cylinder, V(1.2, 0.35, 0.35), rgb(120, 124, 132), M.Metal, V(1.6, 1.1, 4.4), V(0, 90, 0))
		addSeat(model, "DriverSeat", true, V(1.5, 0.4, 1.5), V(-1.05, 2.4, 0.9), rgb(40, 42, 50), real)
		addSeat(model, "PassengerSeat", false, V(1.5, 0.4, 1.5), V(1.05, 2.4, 0.9), rgb(40, 42, 50), real)
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

builders.TurboKart = function(model: Model, real: boolean)
	local paint = rgb(255, 196, 40)
	local base = addPart(model, "Base", Block, V(3.2, 0.7, 6.4), paint, M.Metal, V(0, 1, 0))
	base.CanCollide = true
	for _, x in { -1.9, 1.9 } do
		for _, z in { -2.2, 2.2 } do
			local wheel = addPart(model, "Wheel", Cylinder, V(0.8, 1.8, 1.8), rgb(36, 38, 46), M.Slate, V(x, 0.9, z))
			wheel:SetAttribute("Spin", 0.9)
			addCollider(model, 0.9, V(x, 0.9, z))
		end
	end
	addPart(model, "Nose", Block, V(2.2, 0.5, 1.6), rgb(236, 74, 70), M.SmoothPlastic, V(0, 1.4, -2.6), V(-10, 0, 0))
	addPart(model, "Wing", Block, V(4, 0.2, 0.9), rgb(236, 74, 70), M.SmoothPlastic, V(0, 3.1, 2.8))
	for _, x in { -1.1, 1.1 } do
		addPart(model, "WingPost", Block, V(0.2, 1.6, 0.4), rgb(60, 66, 90), M.Metal, V(x, 2.2, 2.8))
		addPart(model, "Jet", Cylinder, V(2, 0.9, 0.9), rgb(60, 66, 90), M.Metal, V(x, 1.7, 2.4), V(0, 90, 0))
		addPart(model, "Flame", Cylinder, V(0.3, 0.7, 0.7), rgb(255, 120, 40), M.Neon, V(x, 1.7, 3.45), V(0, 90, 0))
	end
	addPart(model, "Wheelbar", Cylinder, V(1.1, 0.18, 0.18), rgb(40, 42, 50), M.Metal, V(0, 2.2, -1))
	addSeat(model, "DriverSeat", true, V(1.5, 0.4, 1.5), V(0, 1.6, 0.5), rgb(40, 42, 50), real)
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
