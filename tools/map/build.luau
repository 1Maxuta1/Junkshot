--[[
	Builds the JUNKSHOT Stage 1 map into src/map/Map.rbxm (Rojo syncs it to Workspace.Map).

	Run from the project root:   lune run tools/map/build
	Re-run after changing this file or Prefabs.luau. Edits made to Workspace.Map inside Studio
	are overwritten by Rojo, so change the layout here.

	Layout (top view, origin = center, ground top at y = 0 = the Baseplate's top)

	        corner landmark          BASE              corner landmark
	                   BASE    +-- ring road --+    BASE
	                     zone  |   spoke       |  zone
	            BASE ----spoke-- PLAZA (spawns, --spoke---- BASE
	                     zone  |  recycler site)  zone
	                   BASE    +---------------+    BASE
	        corner landmark          BASE              corner landmark

	  - PLAZA: r = 40 around the origin. 4 spawns and the reserved Recycling Machine site.
	  - 4 SPOKES (0/90/180/270 deg) connect the plaza with the RING ROAD (r = 150).
	  - 4 COLLECTION ZONES in the diagonals (45/135/225/315 deg), each with its own look and
	    a tagged JunkSpawn area. Props sit only on their outer edges, so the inner side
	    (towards the plaza) is always open.
	  - 8 BASE PLOTS outside the ring road (r = 180), reserved for a later stage.
	  - Container wall + invisible collision wall at |x|, |z| = 223; pines behind it.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Prefabs = require("./Prefabs")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local C = Prefabs.Colors
local Part = Prefabs.Part

local OUTPUT = "src/map/Map.rbxm"

local PLAZA_RADIUS = 40
local SPOKE_WIDTH = 12
local RING_RADIUS = 150
local RING_WIDTH = 14
local PLOT_RADIUS = 180
local PLOT_SIZE = 44
local ZONE_RADIUS = 92
local ZONE_SIZE = 66
local YARD_HALF = 223 -- inner face of the boundary
local RECYCLER_SITE_SIZE = 28

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function polar(radius, degrees)
	local angle = math.rad(degrees)
	return Vector3.new(radius * math.cos(angle), 0, radius * math.sin(angle))
end

-- CFrame at `position` whose -Z (front) looks towards `target` on the horizontal plane.
local function facing(position, target)
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function yaw(degrees)
	return CFrame.Angles(0, math.rad(degrees), 0)
end

local map = Instance.new("Folder")
map.Name = "Map"

local ORIGIN = Vector3.new(0, 0, 0)

---------------------------------------------------------------------------------------------
-- Ground: spokes and ring road (thin, slightly darker "plowed" paths)
---------------------------------------------------------------------------------------------

local ground = folder(map, "Paths")

for index, degrees in { 0, 90, 180, 270 } do
	local length = RING_RADIUS - PLAZA_RADIUS + 4
	local center = polar(PLAZA_RADIUS + length / 2 - 2, degrees)
	Part(ground, {
		Name = `Spoke{index}`,
		Size = Vector3.new(SPOKE_WIDTH, 0.2, length),
		CFrame = facing(center, ORIGIN) * CFrame.new(0, 0.1, 0),
		Color = C.Path,
		CastShadow = false,
	})
end

for index = 0, 7 do
	local a = index * 45
	local fromPoint = polar(RING_RADIUS, a)
	local toPoint = polar(RING_RADIUS, a + 45)
	local center = (fromPoint + toPoint) / 2
	local length = (toPoint - fromPoint).Magnitude + RING_WIDTH * 0.42 -- overlap the joints
	-- Alternate heights by 0.01 so overlapping joints never z-fight.
	local height = if index % 2 == 0 then 0.1 else 0.11
	Part(ground, {
		Name = `Ring{index + 1}`,
		Size = Vector3.new(RING_WIDTH, 0.2, length),
		CFrame = facing(center, toPoint) * CFrame.new(0, height, 0),
		Color = C.Path,
		CastShadow = false,
	})
end

---------------------------------------------------------------------------------------------
-- Plaza: spawns, bollards, lamps and the reserved Recycling Machine site
---------------------------------------------------------------------------------------------

local plaza = folder(map, "Plaza")

Part(plaza, {
	Name = "Rim",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, PLAZA_RADIUS * 2 + 4, PLAZA_RADIUS * 2 + 4),
	CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = C.Ice,
	CastShadow = false,
})
Part(plaza, {
	Name = "Floor",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.4, PLAZA_RADIUS * 2, PLAZA_RADIUS * 2),
	CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = C.PlazaTop,
	CastShadow = false,
})

-- Reserved site: invisible marker for the future machine + yellow hazard frame on the floor.
local site = Part(plaza, {
	Name = "RecyclerSite",
	Size = Vector3.new(RECYCLER_SITE_SIZE, 1, RECYCLER_SITE_SIZE),
	CFrame = CFrame.new(0, 0.9, 0),
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CastShadow = false,
})
site:AddTag("RecyclerSite")
site:SetAttribute("Reserved", "RecyclingMachine")

-- The Recycling Machine itself, centered on the site, its front (input/output) facing the
-- south spoke (-Z). The ground under it is the plaza floor (top at y = 0.4).
Prefabs.RecyclingMachine(plaza, CFrame.new(0, 0.4, 0), "Main")

local half = RECYCLER_SITE_SIZE / 2
for index, edge in {
	{ Vector3.new(RECYCLER_SITE_SIZE, 0.1, 1.4), Vector3.new(0, 0, -half) },
	{ Vector3.new(RECYCLER_SITE_SIZE, 0.1, 1.4), Vector3.new(0, 0, half) },
	{ Vector3.new(1.4, 0.1, RECYCLER_SITE_SIZE), Vector3.new(-half, 0, 0) },
	{ Vector3.new(1.4, 0.1, RECYCLER_SITE_SIZE), Vector3.new(half, 0, 0) },
} do
	Part(plaza, {
		Name = `SiteFrame{index}`,
		Size = edge[1],
		CFrame = CFrame.new(edge[2] + Vector3.new(0, 0.45, 0)),
		Color = C.Yellow,
		CastShadow = false,
	})
end
for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
	Prefabs.Bollard(plaza, CFrame.new(corner * half + Vector3.new(0, 0.4, 0)), C.Orange)
end

local spawns = folder(map, "Spawns")
for index, degrees in { 45, 135, 225, 315 } do
	local position = polar(25, degrees) + Vector3.new(0, 0.4, 0)
	-- Face outwards, towards this direction's collection zone.
	Prefabs.Spawn(spawns, facing(position, position * 2), index)
end

for index = 0, 7 do
	local degrees = 22.5 + index * 45
	Prefabs.Bollard(plaza, CFrame.new(polar(PLAZA_RADIUS - 3, degrees) + Vector3.new(0, 0.4, 0)), if index % 2 == 0
		then C.Orange
		else C.Teal)
end

local lights = folder(map, "Lamps")
for _, degrees in { 0, 90, 180, 270 } do
	-- Plaza lamps stand beside each spoke mouth.
	local position = polar(PLAZA_RADIUS - 4, degrees + 12) + Vector3.new(0, 0.4, 0)
	Prefabs.Lamp(lights, CFrame.new(position), true)
end

---------------------------------------------------------------------------------------------
-- Collection zones
---------------------------------------------------------------------------------------------

local zonesFolder = folder(map, "Zones")

-- Zone-local coordinates: x across, z along the radius; NEGATIVE z points OUTWARDS (back edge
-- at z = -33). The JunkSpawn area covers x in [-28, 28], z in [-21, 31]; props stay outside it.
local SPAWN_AREA = { X = 56, Z = 52, CenterZ = 5 }

local zones = {
	{
		Name = "Container Stacks",
		Degrees = 45,
		Accent = C.Orange,
		Build = function(parent, at)
			Prefabs.Container(parent, at(-16, 0, -28.5), C.Red)
			Prefabs.Container(parent, at(-16, 9, -28.5), C.Yellow)
			Prefabs.Container(parent, at(10, 0, -28.5), C.Blue)
			Prefabs.Container(parent, at(33.5, 0, -12, 90), C.Teal)
			Prefabs.Barrel(parent, at(26, 0, -29), C.Orange)
			Prefabs.Barrel(parent, at(29.5, 0, -26), C.Red)
			Prefabs.Lamp(parent, at(-31, 0, -31), true)
		end,
	},
	{
		Name = "Tire Mountain",
		Degrees = 135,
		Accent = C.Purple,
		Build = function(parent, at)
			Prefabs.JunkHeap(parent, at(-20, 0, -34), 1, 11)
			Prefabs.JunkHeap(parent, at(16, 0, -33), 0.8, 23)
			Prefabs.TireStack(parent, at(-1, 0, -28), 4)
			Prefabs.TireStack(parent, at(33, 0, -10), 3)
			Prefabs.TireStack(parent, at(33, 0, 2), 2)
			Prefabs.SnowPile(parent, at(-37, 0, -8, 90), 0.6)
			Prefabs.Lamp(parent, at(31, 0, -27), false)
		end,
	},
	{
		Name = "Pine Hollow",
		Degrees = 225,
		Accent = C.Green,
		Build = function(parent, at)
			Prefabs.Pine(parent, at(-24, 0, -30), 1)
			Prefabs.Pine(parent, at(-6, 0, -33), 1.15)
			Prefabs.Pine(parent, at(12, 0, -30), 0.9)
			Prefabs.Pine(parent, at(28, 0, -29), 1.05)
			Prefabs.Pine(parent, at(-34, 0, -12), 0.85)
			Prefabs.Pine(parent, at(34, 0, -8), 0.9)
			Prefabs.LogPile(parent, at(-15, 0, -25))
			Prefabs.SnowPile(parent, at(20, 0, -26), 0.45)
			Prefabs.Lamp(parent, at(-34, 0, 6), true)
		end,
	},
	{
		Name = "Old Sheds",
		Degrees = 315,
		Accent = C.Blue,
		Build = function(parent, at)
			Prefabs.Shed(parent, at(-19, 0, -28, 180), C.Blue, C.Red)
			Prefabs.Shed(parent, at(14, 0, -28, 180), C.Yellow, C.Teal)
			Prefabs.Barrel(parent, at(33, 0, -14), C.Green)
			Prefabs.Barrel(parent, at(33, 0, -18.5), C.Orange)
			Prefabs.Barrel(parent, at(30.5, 0, -30), C.Red)
			Prefabs.Lamp(parent, at(-1.5, 0, -30), true)
		end,
	},
}

for index, zone in zones do
	local center = polar(ZONE_RADIUS, zone.Degrees)
	local outward = polar(1, zone.Degrees)
	local zoneCFrame = CFrame.lookAt(center, center + outward) -- -Z points outwards

	local zoneFolder = folder(zonesFolder, `Zone{index}`)
	zoneFolder:SetAttribute("DisplayName", zone.Name)

	local function at(x, y, z, yawDegrees)
		return zoneCFrame * CFrame.new(x, y, z) * yaw(yawDegrees or 0)
	end

	Part(zoneFolder, {
		Name = "Ground",
		Size = Vector3.new(ZONE_SIZE + 2, 0.1, ZONE_SIZE + 2),
		CFrame = zoneCFrame * CFrame.new(0, 0.05, 0),
		Color = C.Snow:Lerp(zone.Accent, 0.1),
		CastShadow = false,
	})
	Prefabs.JunkSpawnArea(zoneFolder, at(0, 0.1, SPAWN_AREA.CenterZ), SPAWN_AREA.X, SPAWN_AREA.Z, "JunkSpawnArea")
	-- Sign at the inner corner, readable from the plaza.
	Prefabs.Sign(zoneFolder, at(-22, 0, 35, 180), string.upper(zone.Name), zone.Accent)

	local props = folder(zoneFolder, "Props")
	zone.Build(props, at)
end

---------------------------------------------------------------------------------------------
-- Base plots (reserved, empty)
---------------------------------------------------------------------------------------------

local plots = folder(map, "BasePlots")
local plotColors = { C.Red, C.Orange, C.Yellow, C.Green, C.Teal, C.Blue, C.Purple, C.Ice }
for index = 1, 8 do
	local degrees = (index - 1) * 45
	local position = polar(PLOT_RADIUS, degrees)
	-- -Z faces the center, so the plot's sign stands at the ring road.
	Prefabs.BasePlot(plots, facing(position, ORIGIN), index, plotColors[index], PLOT_SIZE)
end

---------------------------------------------------------------------------------------------
-- Lamps along the spokes, decorations between areas, corner landmarks
---------------------------------------------------------------------------------------------

for index, degrees in { 0, 90, 180, 270 } do
	for step, radius in { 72, 122 } do
		local side = if (index + step) % 2 == 0 then 1 else -1
		local spokeCFrame = facing(polar(radius, degrees), ORIGIN)
		Prefabs.Lamp(lights, spokeCFrame * CFrame.new(side * (SPOKE_WIDTH / 2 + 3), 0, 0), step == 1)
	end
end

local decor = folder(map, "Decor")

-- Snow piles flanking the spokes near the ring road (outside zones and paths).
for _, degrees in { 0, 90, 180, 270 } do
	local spokeCFrame = facing(polar(132, degrees), ORIGIN)
	Prefabs.SnowPile(decor, spokeCFrame * CFrame.new(-17, 0, 0) * yaw(90), 0.55)
	Prefabs.SnowPile(decor, spokeCFrame * CFrame.new(17, 0, 0) * yaw(-90), 0.5)
end

-- Pines and snow in the strips between the plots and the boundary.
for index = 0, 7 do
	local degrees = index * 45 + 22.5
	local base = polar(196, degrees)
	Prefabs.Pine(decor, CFrame.new(base) * yaw(index * 17), 0.95 + (index % 3) * 0.1)
	Prefabs.SnowPile(decor, facing(polar(176, degrees), ORIGIN), 0.5)
end

-- Corner landmarks (outside the plots, inside the boundary).
local landmarks = folder(map, "Landmarks")
local function cornerCFrame(degrees, radius)
	local position = polar(radius, degrees)
	return facing(position, ORIGIN)
end

do -- North-east: the crane and a container stack
	local cf = cornerCFrame(45, 262)
	Prefabs.Crane(landmarks, cf * yaw(135))
	Prefabs.Container(landmarks, cf * CFrame.new(-16, 0, -6) * yaw(20), C.Purple)
	Prefabs.Container(landmarks, cf * CFrame.new(-16, 9, -6) * yaw(28), C.Orange)
	Prefabs.Container(landmarks, cf * CFrame.new(16, 0, -2) * yaw(-25), C.Green)
end
do -- North-west: Junk Mountain
	local cf = cornerCFrame(135, 262)
	Prefabs.JunkHeap(landmarks, cf, 1.9, 7)
	Prefabs.JunkHeap(landmarks, cf * CFrame.new(-22, 0, -4), 0.9, 3)
	Prefabs.JunkHeap(landmarks, cf * CFrame.new(22, 0, -2), 0.8, 5)
end
do -- South-west: pine grove
	local cf = cornerCFrame(225, 262)
	for index, offset in { { 0, 0, 1.3 }, { -14, 6, 1 }, { 14, 4, 1.1 }, { -6, -12, 0.9 }, { 9, -11, 0.85 }, { -22, -6, 0.8 } } do
		Prefabs.Pine(landmarks, cf * CFrame.new(offset[1], 0, offset[2]) * yaw(index * 31), offset[3])
	end
	Prefabs.SnowPile(landmarks, cf * CFrame.new(0, 0, -20), 0.7)
end
do -- South-east: workshop corner
	local cf = cornerCFrame(315, 262)
	Prefabs.Shed(landmarks, cf * CFrame.new(-8, 0, 2), C.Red, C.Blue)
	Prefabs.TireStack(landmarks, cf * CFrame.new(12, 0, -6), 5)
	Prefabs.TireStack(landmarks, cf * CFrame.new(17, 0, 1), 3)
	Prefabs.JunkHeap(landmarks, cf * CFrame.new(10, 0, 14), 0.9, 13)
	Prefabs.Lamp(landmarks, cf * CFrame.new(-1, 0, -9), true)
end

---------------------------------------------------------------------------------------------
-- Boundary: container wall, invisible collision wall, backdrop pines
---------------------------------------------------------------------------------------------

local boundary = folder(map, "Boundary")
local wallColors = { C.Red, C.Blue, C.Yellow, C.Teal, C.Orange, C.Green, C.Purple }

local CONTAINER_STEP = 24.4
local sides = {
	{ Axis = "X", Sign = 1 },
	{ Axis = "X", Sign = -1 },
	{ Axis = "Z", Sign = 1 },
	{ Axis = "Z", Sign = -1 },
}
local wallIndex = 0
for _, side in sides do
	-- X sides run the full length (covering the corners); Z sides fit between them.
	local runHalf = if side.Axis == "X" then YARD_HALF + 9 else YARD_HALF
	local count = math.floor(runHalf * 2 / CONTAINER_STEP)
	local start = -((count - 1) * CONTAINER_STEP) / 2
	for index = 0, count - 1 do
		wallIndex += 1
		local along = start + index * CONTAINER_STEP
		local depth = side.Sign * (YARD_HALF + 4.5)
		local position = if side.Axis == "X" then Vector3.new(along, 0, depth) else Vector3.new(depth, 0, along)
		local cf = CFrame.new(position) * (if side.Axis == "X" then CFrame.new() else yaw(90))
		Prefabs.Container(boundary, cf, wallColors[(wallIndex % #wallColors) + 1], "WallContainer")
		if wallIndex % 5 == 0 then
			Prefabs.Container(boundary, cf * CFrame.new(0, 9, 0) * yaw(4), wallColors[((wallIndex + 3) % #wallColors) + 1], "WallContainer")
		end
	end

	-- Invisible wall on the inner face: keeps players and thrown junk inside the yard.
	local wallCenter = side.Sign * (YARD_HALF + 1)
	Part(boundary, {
		Name = "Barrier",
		Size = if side.Axis == "X"
			then Vector3.new(YARD_HALF * 2 + 4, 120, 2)
			else Vector3.new(2, 120, YARD_HALF * 2 + 4),
		CFrame = CFrame.new(if side.Axis == "X" then Vector3.new(0, 60, wallCenter) else Vector3.new(wallCenter, 60, 0)),
		Transparency = 1,
		CastShadow = false,
	})

	-- Backdrop pines outside the wall.
	local treeCount = 13
	for index = 0, treeCount - 1 do
		local along = -YARD_HALF + 20 + index * ((YARD_HALF * 2 - 40) / (treeCount - 1))
		local depth = side.Sign * (YARD_HALF + 20 + (index % 2) * 6)
		local position = if side.Axis == "X" then Vector3.new(along, 0, depth) else Vector3.new(depth, 0, along)
		Prefabs.Pine(boundary, CFrame.new(position) * yaw(index * 23), 1.15 + (index % 3) * 0.15)
	end
end

---------------------------------------------------------------------------------------------
-- Write
---------------------------------------------------------------------------------------------

fs.writeDir("src/map")
fs.writeFile(OUTPUT, roblox.serializeModel({ map }))
print(`[map] wrote {OUTPUT}: {Prefabs.GetPartCount()} parts`)
