--!strict
--[[
	Junk: the everyday scrap lying around the yard (Category "Junk"). Mostly Common/Uncommon,
	a few Rare. Junk is the main crafting material and can be recycled, but it is never a
	recycling reward itself (RecyclePool = false).

	SpawnWeight is a relative chance WITHIN the item's rarity when the world spawns that rarity
	(the rarity itself is rolled from DropTables.WorldSpawn).
]]

local Types = require(script.Parent.Parent.Parent.Types)
local B = require(script.Parent.Builder)

local Block, Ball, Cylinder = B.Block, B.Ball, B.Cylinder
local UPRIGHT, V, rgb, part = B.UPRIGHT, B.V, B.rgb, B.part

local RARITY: { [string]: string } = {
	rusty_can = "Common",
	soda_bottle = "Common",
	old_tire = "Common",
	giant_fork = "Common",
	tin_bucket = "Common",
	wooden_crate = "Common",
	old_boot = "Common",
	pipe_segment = "Common",
	bike_wheel = "Common",
	paint_bucket = "Common",
	broken_toaster = "Uncommon",
	cracked_monitor = "Uncommon",
	rubber_duck = "Uncommon",
	bouncy_spring = "Uncommon",
	car_battery = "Uncommon",
	gear_wheel = "Uncommon",
	broken_lamp = "Uncommon",
	old_radio = "Uncommon",
	dented_trophy = "Rare",
	toxic_barrel = "Rare",
}

local function def(id: string, displayName: string, spawnWeight: number, parts: { Types.JunkPartSpec }): Types.ItemDefinition
	return {
		Id = id,
		DisplayName = displayName,
		Rarity = assert(RARITY[id], `[Items/Junk] no rarity for {id}`),
		Category = "Junk",
		Parts = parts,
		NaturalSpawn = true,
		SpawnWeight = spawnWeight,
		RecyclePool = false,
	}
end

return {
	def("rusty_can", "Rusty Can", 10, {
		part(Cylinder, V(1.5, 1.1, 1.1), rgb(163, 95, 52), Enum.Material.CorrodedMetal, nil, UPRIGHT),
	}),

	def("soda_bottle", "Soda Bottle", 10, {
		part(Cylinder, V(1.8, 0.8, 0.8), rgb(0, 170, 160), Enum.Material.Glass, nil, UPRIGHT),
		part(Cylinder, V(0.7, 0.4, 0.4), rgb(0, 170, 160), Enum.Material.Glass, V(0, 1.25, 0), UPRIGHT),
		part(Cylinder, V(0.2, 0.5, 0.5), rgb(230, 50, 60), Enum.Material.Plastic, V(0, 1.65, 0), UPRIGHT),
	}),

	def("old_tire", "Old Tire", 8, {
		part(Cylinder, V(0.9, 3, 3), rgb(40, 40, 46), Enum.Material.Slate, nil, UPRIGHT),
		part(Cylinder, V(0.95, 1.2, 1.2), rgb(200, 200, 205), Enum.Material.Metal, nil, UPRIGHT),
	}),

	def("broken_toaster", "Broken Toaster", 8, {
		part(Block, V(2.2, 1.4, 1.4), rgb(205, 205, 215), Enum.Material.Metal),
		part(Block, V(0.35, 0.3, 0.35), rgb(230, 60, 60), Enum.Material.Plastic, V(0.5, 0.85, 0)),
		part(Block, V(1.5, 0.1, 0.3), rgb(30, 30, 35), Enum.Material.SmoothPlastic, V(0, 0.72, 0)),
	}),

	def("giant_fork", "Giant Fork", 6, {
		part(Block, V(0.35, 0.2, 2.6), rgb(190, 190, 200), Enum.Material.Metal),
		part(Block, V(1.3, 0.2, 0.4), rgb(190, 190, 200), Enum.Material.Metal, V(0, 0, -1.5)),
		part(Block, V(0.2, 0.2, 1.0), rgb(190, 190, 200), Enum.Material.Metal, V(-0.5, 0, -2.1)),
		part(Block, V(0.2, 0.2, 1.0), rgb(190, 190, 200), Enum.Material.Metal, V(0, 0, -2.1)),
		part(Block, V(0.2, 0.2, 1.0), rgb(190, 190, 200), Enum.Material.Metal, V(0.5, 0, -2.1)),
	}),

	def("cracked_monitor", "Cracked Monitor", 6, {
		part(Block, V(2.4, 1.9, 1.5), rgb(214, 204, 176), Enum.Material.Plastic),
		part(Block, V(2.0, 1.5, 0.1), rgb(25, 70, 80), Enum.Material.SmoothPlastic, V(0, 0.05, -0.8)),
		part(Block, V(1.0, 0.3, 1.0), rgb(190, 180, 150), Enum.Material.Plastic, V(0, -1.1, 0.1)),
	}),

	def("tin_bucket", "Tin Bucket", 9, {
		part(Cylinder, V(1.6, 1.7, 1.7), rgb(120, 145, 170), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.2, 1.9, 1.9), rgb(90, 110, 130), Enum.Material.Metal, V(0, 0.75, 0), UPRIGHT),
	}),

	def("wooden_crate", "Wooden Crate", 9, {
		part(Block, V(2, 2, 2), rgb(176, 130, 80), Enum.Material.WoodPlanks),
		part(Block, V(2.1, 0.25, 2.1), rgb(120, 85, 50), Enum.Material.Wood, V(0, 0.6, 0)),
		part(Block, V(2.1, 0.25, 2.1), rgb(120, 85, 50), Enum.Material.Wood, V(0, -0.6, 0)),
	}),

	def("old_boot", "Old Boot", 7, {
		part(Block, V(1.1, 0.4, 2.4), rgb(60, 40, 25), Enum.Material.Slate),
		part(Block, V(1.0, 1.5, 1.1), rgb(110, 72, 38), Enum.Material.Fabric, V(0, 0.95, 0.55)),
		part(Block, V(1.0, 0.8, 1.2), rgb(110, 72, 38), Enum.Material.Fabric, V(0, 0.6, -0.55)),
	}),

	def("rubber_duck", "Rubber Duck", 5, {
		part(Ball, V(1.8, 1.8, 1.8), rgb(255, 214, 0), Enum.Material.SmoothPlastic),
		part(Ball, V(1.1, 1.1, 1.1), rgb(255, 214, 0), Enum.Material.SmoothPlastic, V(0, 1.1, -0.5)),
		part(Block, V(0.6, 0.25, 0.5), rgb(255, 130, 0), Enum.Material.SmoothPlastic, V(0, 1.0, -1.15)),
	}),

	def("bouncy_spring", "Bouncy Spring", 5, {
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(235, 55, 130), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(235, 55, 130), Enum.Material.Metal, V(0, 0.45, 0), UPRIGHT),
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(235, 55, 130), Enum.Material.Metal, V(0, -0.45, 0), UPRIGHT),
	}),

	def("pipe_segment", "Pipe Segment", 7, {
		part(Cylinder, V(3.2, 1.1, 1.1), rgb(110, 135, 110), Enum.Material.CorrodedMetal),
		part(Cylinder, V(0.3, 1.5, 1.5), rgb(90, 110, 90), Enum.Material.CorrodedMetal, V(1.4, 0, 0)),
		part(Cylinder, V(0.3, 1.5, 1.5), rgb(90, 110, 90), Enum.Material.CorrodedMetal, V(-1.4, 0, 0)),
	}),

	def("car_battery", "Car Battery", 4, {
		part(Block, V(1.9, 1.2, 1.1), rgb(30, 90, 200), Enum.Material.Plastic),
		part(Block, V(1.9, 0.2, 1.1), rgb(20, 60, 140), Enum.Material.Plastic, V(0, 0.65, 0)),
		part(Block, V(0.3, 0.3, 0.3), rgb(220, 40, 40), Enum.Material.Metal, V(-0.55, 0.9, 0)),
		part(Block, V(0.3, 0.3, 0.3), rgb(30, 30, 30), Enum.Material.Metal, V(0.55, 0.9, 0)),
	}),

	def("gear_wheel", "Gear Wheel", 6, {
		part(Cylinder, V(0.5, 2.4, 2.4), rgb(255, 170, 40), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.7, 0.9, 0.9), rgb(60, 60, 70), Enum.Material.Metal, nil, UPRIGHT),
		part(Block, V(0.6, 0.5, 0.6), rgb(255, 170, 40), Enum.Material.Metal, V(1.3, 0, 0)),
		part(Block, V(0.6, 0.5, 0.6), rgb(255, 170, 40), Enum.Material.Metal, V(-1.3, 0, 0)),
		part(Block, V(0.6, 0.5, 0.6), rgb(255, 170, 40), Enum.Material.Metal, V(0, 0, 1.3)),
		part(Block, V(0.6, 0.5, 0.6), rgb(255, 170, 40), Enum.Material.Metal, V(0, 0, -1.3)),
	}),

	def("broken_lamp", "Broken Lamp", 5, {
		part(Cylinder, V(1.8, 0.25, 0.25), rgb(150, 150, 160), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.3, 1.1, 1.1), rgb(90, 90, 100), Enum.Material.Metal, V(0, -1.0, 0), UPRIGHT),
		part(Cylinder, V(1.0, 1.8, 1.8), rgb(255, 200, 120), Enum.Material.Fabric, V(0, 1.2, 0), UPRIGHT),
	}),

	def("old_radio", "Old Radio", 5, {
		part(Block, V(2.4, 1.5, 0.9), rgb(205, 70, 55), Enum.Material.Plastic),
		part(Block, V(1.0, 1.1, 0.1), rgb(40, 40, 45), Enum.Material.Slate, V(-0.55, 0, -0.5)),
		part(Cylinder, V(0.2, 0.45, 0.45), rgb(240, 230, 200), Enum.Material.Plastic, V(0.7, 0.2, -0.5), V(0, 90, 0)),
		part(Cylinder, V(1.6, 0.12, 0.12), rgb(200, 200, 210), Enum.Material.Metal, V(0.9, 1.3, 0), V(0, 0, 60)),
	}),

	def("bike_wheel", "Bike Wheel", 5, {
		part(Cylinder, V(0.3, 3, 3), rgb(60, 60, 70), Enum.Material.Metal),
		part(Cylinder, V(0.5, 0.7, 0.7), rgb(255, 220, 0), Enum.Material.Metal),
	}),

	def("paint_bucket", "Paint Bucket", 7, {
		part(Cylinder, V(1.5, 1.5, 1.5), rgb(235, 235, 235), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.15, 1.3, 1.3), rgb(255, 60, 160), Enum.Material.SmoothPlastic, V(0, 0.7, 0), UPRIGHT),
	}),

	def("dented_trophy", "Dented Trophy", 3, {
		part(Cylinder, V(0.8, 0.3, 0.3), rgb(255, 200, 0), Enum.Material.Metal, nil, UPRIGHT),
		part(Block, V(1.2, 0.4, 1.2), rgb(80, 55, 35), Enum.Material.Wood, V(0, -0.6, 0)),
		part(Cylinder, V(0.9, 1.1, 1.1), rgb(255, 200, 0), Enum.Material.Metal, V(0, 0.85, 0), UPRIGHT),
	}),

	def("toxic_barrel", "Toxic Barrel", 3, {
		part(Cylinder, V(2.4, 1.9, 1.9), rgb(60, 200, 90), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.25, 2.0, 2.0), rgb(40, 40, 45), Enum.Material.Metal, V(0, 0.7, 0), UPRIGHT),
		part(Cylinder, V(0.25, 2.0, 2.0), rgb(40, 40, 45), Enum.Material.Metal, V(0, -0.7, 0), UPRIGHT),
	}),
}
