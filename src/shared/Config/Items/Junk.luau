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

local Block, Ball, Cylinder, M = B.Block, B.Ball, B.Cylinder, B.M
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

	def("broken_toaster", "Broken Toaster", 8, (function()
		-- A rounded chrome toaster: two slots (one burnt toast stuck, one half popped), lever,
		-- browning dial, scorch mark, a spring sticking out, feet and a frayed cord.
		local chrome, dark = rgb(205, 208, 218), rgb(34, 34, 40)
		local parts = {
			part(Block, V(1.4, 1.3, 1.2), chrome, M.Metal), -- body (root)
			part(Cylinder, V(1.2, 1.3, 1.3), chrome, M.Metal, V(-0.7, 0, 0), V(0, 90, 0)), -- rounded ends
			part(Cylinder, V(1.2, 1.3, 1.3), chrome, M.Metal, V(0.7, 0, 0), V(0, 90, 0)),
			part(Block, V(2.5, 0.14, 1.26), dark, M.SmoothPlastic, V(0, -0.62, 0)), -- base trim
			part(Block, V(1.5, 0.04, 0.22), dark, M.SmoothPlastic, V(0, 0.655, -0.25)), -- slots
			part(Block, V(1.5, 0.04, 0.22), dark, M.SmoothPlastic, V(0, 0.655, 0.25)),
			part(Block, V(1.1, 0.72, 0.14), rgb(92, 58, 34), M.Sand, V(-0.05, 0.7, -0.25), V(0, 0, 7)), -- burnt toast
			part(Block, V(1.0, 0.5, 0.13), rgb(214, 160, 90), M.Sand, V(0.1, 0.6, 0.25), V(-5, 0, -10)), -- half popped toast
			part(Block, V(0.08, 0.7, 0.05), dark, M.SmoothPlastic, V(0.55, 0.05, -0.61)), -- lever slot
			part(Block, V(0.32, 0.16, 0.24), rgb(220, 56, 50), M.SmoothPlastic, V(0.55, 0.15, -0.72)), -- lever
			part(Cylinder, V(0.08, 0.34, 0.34), dark, M.SmoothPlastic, V(-0.5, 0.05, -0.63), V(0, 90, 0)), -- dial
			part(Block, V(0.04, 0.14, 0.03), rgb(240, 240, 240), M.SmoothPlastic, V(-0.5, 0.11, -0.675), V(0, 0, -35)),
			part(Block, V(0.5, 0.36, 0.02), rgb(60, 52, 44), M.Slate, V(-0.05, 0.38, -0.605), V(0, 0, 12)), -- scorch
			part(Cylinder, V(0.05, 0.28, 0.28), chrome, M.Metal, V(0.85, 0.74, 0), B.UPRIGHT), -- broken spring
			part(Cylinder, V(0.05, 0.28, 0.28), chrome, M.Metal, V(0.88, 0.86, 0.02), V(8, 0, 96)),
			part(Cylinder, V(0.05, 0.28, 0.28), chrome, M.Metal, V(0.92, 0.98, 0.05), V(14, 0, 102)),
		}
		for _, x in { -0.95, 0.95 } do
			for _, z in { -0.42, 0.42 } do
				table.insert(parts, part(Block, V(0.22, 0.1, 0.22), dark, M.SmoothPlastic, V(x, -0.74, z)))
			end
		end
		B.join(parts, B.path({ V(-1.2, -0.45, 0.3), V(-1.55, -0.68, 0.55), V(-1.4, -0.75, 1.1), V(-0.9, -0.76, 1.3) }, 0.09, dark, M.SmoothPlastic))
		table.insert(parts, part(Block, V(0.24, 0.16, 0.3), dark, M.SmoothPlastic, V(-0.75, -0.74, 1.4))) -- plug
		return parts
	end)()),

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

	def("bike_wheel", "Bike Wheel", 5, (function()
		-- A real bicycle wheel: hub, axle, crossed spokes, a silver rim and a knobbly tyre
		-- (the wheel stands in the Y-Z plane, the axle along X).
		local rubber, steel, chrome = rgb(34, 34, 40), rgb(176, 184, 196), rgb(222, 228, 236)
		local parts = {
			part(Cylinder, V(0.5, 0.42, 0.42), chrome, M.Metal), -- hub (root)
			part(Cylinder, V(0.9, 0.13, 0.13), steel, M.Metal), -- axle
			part(Cylinder, V(0.08, 0.62, 0.62), steel, M.Metal, V(-0.2, 0, 0)), -- spoke flanges
			part(Cylinder, V(0.08, 0.62, 0.62), steel, M.Metal, V(0.2, 0, 0)),
		}
		for i = 0, 11 do
			local turn = CFrame.Angles(i * math.pi / 6, 0, 0)
			table.insert(parts, B.at(Block, V(0.34, 0.24, 0.8), rubber, M.Slate, turn * CFrame.new(0, 1.4, 0))) -- tyre
			table.insert(parts, B.at(Block, V(0.2, 0.12, 0.66), steel, M.Metal, turn * CFrame.new(0, 1.22, 0))) -- rim
		end
		for i = 0, 7 do -- 8 bars through the hub = 16 spokes, the two flanges crossing
			local x = if i % 2 == 0 then -0.12 else 0.12
			table.insert(parts, B.at(Block, V(0.04, 2.36, 0.04), chrome, M.Metal, CFrame.new(x, 0, 0) * CFrame.Angles(i * math.pi / 8 + 0.1, 0, 0)))
		end
		table.insert(parts, B.at(Block, V(0.08, 0.2, 0.08), chrome, M.Metal, CFrame.Angles(0.26, 0, 0) * CFrame.new(0, 1.08, 0))) -- valve
		table.insert(parts, B.at(Block, V(0.06, 0.34, 0.14), rgb(255, 140, 30), M.SmoothPlastic, CFrame.Angles(2.2, 0, 0) * CFrame.new(0.13, 0.8, 0))) -- reflector
		return parts
	end)()),

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
		-- Drum with rolled rims, hoops, a yellow hazard band, lid, bung and glowing ooze.
		part(Cylinder, V(2.4, 1.86, 1.86), rgb(60, 200, 90), Enum.Material.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.16, 1.94, 1.94), rgb(40, 40, 45), Enum.Material.Metal, V(0, 1.12, 0), UPRIGHT),
		part(Cylinder, V(0.16, 1.94, 1.94), rgb(40, 40, 45), Enum.Material.Metal, V(0, -1.12, 0), UPRIGHT),
		part(Cylinder, V(0.14, 1.96, 1.96), rgb(40, 40, 45), Enum.Material.Metal, V(0, 0.62, 0), UPRIGHT),
		part(Cylinder, V(0.14, 1.96, 1.96), rgb(40, 40, 45), Enum.Material.Metal, V(0, -0.62, 0), UPRIGHT),
		part(Cylinder, V(0.5, 1.9, 1.9), rgb(255, 204, 48), Enum.Material.SmoothPlastic, V(0, 0, 0), UPRIGHT),
		part(Cylinder, V(0.06, 1.6, 1.6), rgb(36, 120, 60), Enum.Material.Metal, V(0, 1.22, 0), UPRIGHT),
		part(Cylinder, V(0.14, 0.32, 0.32), rgb(176, 188, 204), Enum.Material.Metal, V(0.45, 1.28, 0.2), UPRIGHT),
		part(Ball, V(0.5, 0.3, 0.5), rgb(120, 255, 90), Enum.Material.Neon, V(-0.35, 1.22, -0.3)),
		part(Block, V(0.22, 0.7, 0.08), rgb(120, 255, 90), Enum.Material.Neon, V(-0.55, 0.85, -0.74)),
	}),
}
