--!strict
--[[
	Crafted: everything that only comes out of the machine's Crafting mode.

	Category "Component"  intermediate parts used by bigger recipes (engines, motors, frames).
	Category "Crafted"    finished creations. ItemType says what kind of object it is and
	                      BehaviorId links it to Config/Behaviors (driving, towing, scanning,
	                      playing music). Items whose BehaviorId has no entry there yet are
	                      carryable/throwable items like any other.

	Models are simple placeholders built from parts (clearly replaceable later).
	None of these spawn in the world or drop from recycling.
]]

local Types = require(script.Parent.Parent.Parent.Types)
local B = require(script.Parent.Builder)

local Block, Ball, Cylinder, M = B.Block, B.Ball, B.Cylinder, B.M
local UPRIGHT, V, rgb, part = B.UPRIGHT, B.V, B.rgb, B.part

local SIDE = V(0, 90, 0) -- cylinder axis along Z (wheels seen from the side)

local function crafted(
	id: string,
	displayName: string,
	rarity: string,
	category: string,
	itemType: string,
	behaviorId: string?,
	description: string,
	parts: { Types.JunkPartSpec }
): Types.ItemDefinition
	return {
		Id = id,
		DisplayName = displayName,
		Rarity = rarity,
		Category = category,
		ItemType = itemType,
		BehaviorId = behaviorId,
		Description = description,
		Parts = parts,
		NaturalSpawn = false,
		RecyclePool = false,
	}
end

local function wheel(offset: Vector3, diameter: number, color: Color3?): Types.JunkPartSpec
	return part(Cylinder, V(0.35, diameter, diameter), color or rgb(40, 42, 50), M.Slate, offset)
end

local _ = SIDE

return {
	---------------------------------------------------------------------------------------------
	-- Components
	---------------------------------------------------------------------------------------------
	crafted("battery_pack", "Battery Pack", "Uncommon", "Component", "Component", nil, "Two batteries wired together.", (function()
		-- Two big cells on a tray: labels, terminals, straps with buckles, red and black wires and
		-- a little charge display.
		local blue, yellow, steel, black = rgb(40, 110, 220), rgb(255, 210, 60), rgb(200, 206, 216), rgb(30, 30, 36)
		local parts = {
			part(Block, V(1.8, 0.8, 0.3), rgb(54, 58, 70), M.SmoothPlastic), -- spacer between the cells (root)
			part(Block, V(2.0, 0.16, 1.9), black, M.SmoothPlastic, V(0, -0.47, 0)), -- tray
			part(Block, V(0.6, 0.08, 0.3), black, M.SmoothPlastic, V(0, 0.46, 0)), -- display
		}
		for _, z in { -0.5, 0.5 } do
			table.insert(parts, part(Cylinder, V(1.8, 0.85, 0.85), blue, M.SmoothPlastic, V(0, 0, z)))
			table.insert(parts, part(Cylinder, V(0.5, 0.87, 0.87), yellow, M.SmoothPlastic, V(-0.3, 0, z)))
			table.insert(parts, part(Cylinder, V(0.08, 0.87, 0.87), steel, M.Metal, V(0.88, 0, z)))
			table.insert(parts, part(Cylinder, V(0.14, 0.3, 0.3), steel, M.Metal, V(0.98, 0, z))) -- + terminal
			table.insert(parts, part(Cylinder, V(0.05, 0.6, 0.6), steel, M.Metal, V(-0.92, 0, z))) -- - plate
		end
		for _, x in { -0.55, 0.45 } do
			table.insert(parts, part(Block, V(0.18, 0.05, 1.86), black, M.Fabric, V(x, 0.44, 0)))
			table.insert(parts, part(Block, V(0.22, 0.08, 0.16), steel, M.Metal, V(x, 0.47, -0.55)))
		end
		for i = 0, 3 do
			table.insert(parts, part(Block, V(0.08, 0.04, 0.12), if i < 3 then rgb(80, 255, 120) else rgb(60, 70, 64), M.Neon, V(-0.18 + i * 0.12, 0.51, 0)))
		end
		B.join(parts, B.path({ V(1.04, 0, -0.5), V(1.25, 0.25, -0.15), V(1.05, 0.5, 0.3) }, 0.08, rgb(220, 50, 50), M.SmoothPlastic))
		B.join(parts, B.path({ V(-0.95, 0, 0.5), V(-1.18, 0.25, 0.15), V(-1.0, 0.5, -0.3) }, 0.08, black, M.SmoothPlastic))
		table.insert(parts, part(Block, V(0.2, 0.12, 0.14), rgb(220, 50, 50), M.SmoothPlastic, V(1.02, 0.52, 0.32)))
		table.insert(parts, part(Block, V(0.2, 0.12, 0.14), black, M.SmoothPlastic, V(-0.98, 0.52, -0.32)))
		return parts
	end)()),
	crafted("metal_frame", "Metal Frame", "Uncommon", "Component", "Component", nil, "A welded frame of pipes.", {
		part(Cylinder, V(2.6, 0.35, 0.35), rgb(140, 160, 180), M.Metal, V(0, 0, -0.9)),
		part(Cylinder, V(2.6, 0.35, 0.35), rgb(140, 160, 180), M.Metal, V(0, 0, 0.9)),
		part(Cylinder, V(1.8, 0.35, 0.35), rgb(140, 160, 180), M.Metal, V(-1.2, 0, 0), V(0, 90, 0)),
		part(Cylinder, V(1.8, 0.35, 0.35), rgb(140, 160, 180), M.Metal, V(1.2, 0, 0), V(0, 90, 0)),
		part(Block, V(2.3, 0.1, 1.6), rgb(170, 186, 204), M.Metal, V(0, -0.15, 0)),
	}),
	crafted("small_engine", "Small Engine", "Rare", "Component", "Component", nil, "Rebuilt from salvaged parts. It even starts.", {
		part(Block, V(1.8, 1.4, 1.4), rgb(70, 80, 96), M.Metal),
		part(Cylinder, V(0.3, 1.4, 1.4), rgb(220, 60, 50), M.Metal, V(1.05, 0, 0)),
		part(Cylinder, V(0.9, 0.35, 0.35), rgb(190, 196, 206), M.Metal, V(-0.5, 1.1, 0.3), UPRIGHT),
		part(Block, V(1.2, 0.3, 1), rgb(255, 150, 30), M.SmoothPlastic, V(0, 0.85, 0)),
	}),
	crafted("electric_motor", "Electric Motor", "Rare", "Component", "Component", nil, "Copper coils and a battery: pure torque.", {
		part(Cylinder, V(1.8, 1.3, 1.3), rgb(60, 130, 230), M.Metal),
		part(Cylinder, V(0.3, 1.4, 1.4), rgb(214, 120, 60), M.Metal, V(-1, 0, 0)),
		part(Cylinder, V(0.8, 0.3, 0.3), rgb(200, 206, 214), M.Metal, V(1.3, 0, 0)),
	}),
	crafted("control_panel", "Control Panel", "Epic", "Component", "Component", nil, "Screens, switches and a brain.", {
		part(Block, V(2.2, 1.4, 0.8), rgb(60, 66, 90), M.SmoothPlastic),
		part(Block, V(1.4, 0.8, 0.1), rgb(80, 230, 200), M.Neon, V(-0.25, 0.15, -0.42)),
		part(Ball, V(0.3, 0.3, 0.3), rgb(255, 70, 70), M.Neon, V(0.75, 0.3, -0.42)),
		part(Ball, V(0.3, 0.3, 0.3), rgb(255, 210, 60), M.Neon, V(0.75, -0.2, -0.42)),
	}),

	---------------------------------------------------------------------------------------------
	-- Vehicles (functional in Stage 2B)
	---------------------------------------------------------------------------------------------
	crafted("wooden_sled", "Wooden Sled", "Common", "Crafted", "Vehicle", "Vehicle.Sled", "Planks on runners. Downhill only.", {
		part(Block, V(1.4, 0.25, 3), rgb(176, 124, 74), M.WoodPlanks),
		part(Block, V(0.15, 0.25, 3.3), rgb(70, 76, 90), M.Metal, V(-0.6, -0.3, 0)),
		part(Block, V(0.15, 0.25, 3.3), rgb(70, 76, 90), M.Metal, V(0.6, -0.3, 0)),
		part(Block, V(1.4, 0.6, 0.2), rgb(176, 124, 74), M.WoodPlanks, V(0, 0.4, -1.4)),
	}),
	crafted("bicycle", "Bicycle", "Uncommon", "Crafted", "Vehicle", "Vehicle.Bicycle", "Two wheels and a pipe. Faster than walking.", {
		part(Cylinder, V(2, 0.2, 0.2), rgb(255, 138, 30), M.SmoothPlastic, V(0, 0.62, -0.1), V(0, 90, 4)),
		wheel(V(0, -0.5, -1.35), 1.8),
		wheel(V(0, -0.5, 1.35), 1.8),
		part(Cylinder, V(0.38, 1.4, 1.4), rgb(204, 210, 220), M.Metal, V(0, -0.5, -1.35)),
		part(Cylinder, V(0.38, 1.4, 1.4), rgb(204, 210, 220), M.Metal, V(0, -0.5, 1.35)),
		part(Cylinder, V(1.8, 0.2, 0.2), rgb(255, 138, 30), M.SmoothPlastic, V(0, 0, -0.4), V(0, 90, -42)),
		part(Cylinder, V(1.4, 0.18, 0.18), rgb(255, 138, 30), M.SmoothPlastic, V(0, 0.1, 0.45), V(0, 90, 70)),
		part(Cylinder, V(1.5, 0.16, 0.16), rgb(34, 36, 44), M.Metal, V(0, 0.3, -1.1), V(0, 90, 66)),
		part(Block, V(0.4, 0.16, 0.8), rgb(34, 36, 44), M.SmoothPlastic, V(0, 0.95, 0.7)),
		part(Cylinder, V(1.3, 0.14, 0.14), rgb(204, 210, 220), M.Metal, V(0, 1.05, -0.85)),
	}),
	crafted("metal_cart", "Metal Cart", "Uncommon", "Crafted", "Vehicle", "Tool.Cart", "Carries extra junk around the yard.", (function()
		-- An open metal tub with a rolled rim, ribs and rivets, four wheels with hubs on two
		-- axles and a push handle with a rubber grip.
		local tub, tubDark, steel, dark = rgb(150, 170, 196), rgb(112, 130, 152), rgb(204, 210, 220), rgb(40, 42, 50)
		local parts = {
			part(Block, V(1.6, 0.1, 2.2), tubDark, M.DiamondPlate, V(0, -0.35, 0)), -- floor (root)
			part(Block, V(0.08, 0.8, 2.4), tub, M.Metal, V(-0.88, 0, 0)),
			part(Block, V(0.08, 0.8, 2.4), tub, M.Metal, V(0.88, 0, 0)),
			part(Block, V(1.8, 0.8, 0.08), tub, M.Metal, V(0, 0, -1.18)),
			part(Block, V(1.8, 0.8, 0.08), tub, M.Metal, V(0, 0, 1.18)),
			part(Cylinder, V(2.46, 0.11, 0.11), steel, M.Metal, V(-0.9, 0.42, 0), V(0, 90, 0)), -- rolled rim
			part(Cylinder, V(2.46, 0.11, 0.11), steel, M.Metal, V(0.9, 0.42, 0), V(0, 90, 0)),
			part(Cylinder, V(1.86, 0.11, 0.11), steel, M.Metal, V(0, 0.42, -1.2)),
			part(Cylinder, V(1.86, 0.11, 0.11), steel, M.Metal, V(0, 0.42, 1.2)),
			part(Block, V(0.03, 0.3, 0.42), rgb(150, 96, 60), M.CorrodedMetal, V(-0.925, -0.12, 0.35)), -- rust patch
		}
		for _, x in { -0.93, 0.93 } do
			for _, z in { -0.5, 0.5 } do
				table.insert(parts, part(Block, V(0.06, 0.78, 0.12), tubDark, M.Metal, V(x, 0, z))) -- ribs
			end
			for _, z in { -0.9, -0.3, 0.3, 0.9 } do
				table.insert(parts, part(Ball, V(0.09, 0.09, 0.09), steel, M.Metal, V(x * 1.01, 0.3, z))) -- rivets
			end
		end
		for _, z in { -0.75, 0.75 } do
			table.insert(parts, part(Cylinder, V(2.1, 0.12, 0.12), dark, M.Metal, V(0, -0.5, z))) -- axle
			for _, x in { -1.0, 1.0 } do
				table.insert(parts, wheel(V(x, -0.5, z), 0.8))
				table.insert(parts, part(Cylinder, V(0.38, 0.34, 0.34), steel, M.Metal, V(x, -0.5, z)))
			end
		end
		table.insert(parts, B.tube(V(-0.7, 0.42, 1.2), V(-0.62, 0.98, 1.78), 0.12, dark, M.Metal))
		table.insert(parts, B.tube(V(0.7, 0.42, 1.2), V(0.62, 0.98, 1.78), 0.12, dark, M.Metal))
		table.insert(parts, B.tube(V(-0.68, 0.98, 1.78), V(0.68, 0.98, 1.78), 0.12, dark, M.Metal))
		table.insert(parts, B.tube(V(-0.42, 0.98, 1.78), V(0.42, 0.98, 1.78), 0.2, rgb(220, 60, 50), M.SmoothPlastic)) -- grip
		return parts
	end)()),
	crafted("scooter", "Scooter", "Rare", "Crafted", "Vehicle", "Vehicle.Scooter", "A motor scooter with questionable brakes.", {
		part(Block, V(0.9, 0.25, 2.6), rgb(60, 150, 255), M.SmoothPlastic),
		wheel(V(0, -0.35, -1.2), 0.9),
		wheel(V(0, -0.35, 1.2), 0.9),
		part(Cylinder, V(2, 0.2, 0.2), rgb(200, 206, 214), M.Metal, V(0, 1, -1.2), UPRIGHT),
		part(Block, V(0.7, 0.5, 0.7), rgb(70, 80, 96), M.Metal, V(0, 0.35, 0.9)),
	}),
	crafted("homemade_car", "Homemade Car", "Epic", "Crafted", "Vehicle", "Vehicle.Car", "Four tires, a frame and an engine. Drive it home.", {
		part(Block, V(1.7, 0.7, 3.6), rgb(206, 48, 44), M.SmoothPlastic),
		part(Block, V(0.5, 0.06, 1.4), rgb(246, 238, 218), M.SmoothPlastic, V(0, 0.38, -1)),
		part(Block, V(0.6, 0.4, 0.6), rgb(206, 212, 222), M.Metal, V(0, 0.5, -1)),
		part(Block, V(1.3, 0.1, 1), rgb(28, 30, 38), M.SmoothPlastic, V(0, 0.36, 0.35)),
		part(Block, V(1.5, 0.6, 0.08), rgb(150, 215, 255), M.Glass, V(0, 0.65, -0.25)),
		part(Block, V(1.6, 0.12, 0.12), rgb(112, 120, 134), M.Metal, V(0, 1.35, 0.95)),
		part(Block, V(0.12, 1, 0.12), rgb(112, 120, 134), M.Metal, V(-0.74, 0.85, 0.95)),
		part(Block, V(0.12, 1, 0.12), rgb(112, 120, 134), M.Metal, V(0.74, 0.85, 0.95)),
		part(Cylinder, V(0.1, 0.4, 0.4), rgb(255, 242, 190), M.Neon, V(-0.55, 0.05, -1.82), V(0, 90, 0)),
		part(Cylinder, V(0.1, 0.4, 0.4), rgb(255, 242, 190), M.Neon, V(0.55, 0.05, -1.82), V(0, 90, 0)),
		wheel(V(-1.15, -0.4, -1.2), 1.1),
		wheel(V(1.15, -0.4, -1.2), 1.1),
		wheel(V(-1.15, -0.4, 1.2), 1.1),
		wheel(V(1.15, -0.4, 1.2), 1.1),
	}),
	crafted("turbo_kart", "Turbo Kart", "Legendary", "Crafted", "Vehicle", "Vehicle.Kart", "A homemade car with a jet strapped on.", {
		part(Block, V(2, 0.5, 3.2), rgb(255, 196, 40), M.Metal),
		part(Cylinder, V(1.6, 0.9, 0.9), rgb(60, 66, 90), M.Metal, V(0, 0.6, 1.2), V(0, 90, 0)),
		part(Cylinder, V(0.3, 0.75, 0.75), rgb(255, 120, 40), M.Neon, V(0, 0.6, 2), V(0, 90, 0)),
		wheel(V(-1.05, -0.3, -1.1), 0.9),
		wheel(V(1.05, -0.3, -1.1), 0.9),
		wheel(V(-1.05, -0.3, 1.1), 0.9),
		wheel(V(1.05, -0.3, 1.1), 0.9),
	}),

	---------------------------------------------------------------------------------------------
	-- Tools (functional in Stage 2B)
	---------------------------------------------------------------------------------------------
	crafted("flashlight", "Flashlight", "Uncommon", "Crafted", "Tool", "Tool.Flashlight", "Lights up the dark corners of the yard.", {
		part(Cylinder, V(2, 0.6, 0.6), rgb(60, 66, 90), M.Metal),
		part(Cylinder, V(0.4, 0.9, 0.9), rgb(255, 210, 60), M.Metal, V(1.1, 0, 0)),
		part(Cylinder, V(0.1, 0.75, 0.75), rgb(255, 245, 200), M.Neon, V(1.32, 0, 0)),
	}),
	crafted("metal_detector", "Metal Detector", "Rare", "Crafted", "Tool", "Tool.Detector", "Beeps faster near valuable items.", {
		part(Cylinder, V(2.8, 0.2, 0.2), rgb(200, 206, 214), M.Metal, V(0, 0.3, 0), V(0, 0, 70)),
		part(Cylinder, V(0.15, 1.3, 1.3), rgb(255, 150, 30), M.SmoothPlastic, V(0.5, -1, 0), UPRIGHT),
		part(Block, V(0.5, 0.4, 0.6), rgb(40, 150, 80), M.SmoothPlastic, V(-0.45, 1.4, 0)),
		part(Ball, V(0.2, 0.2, 0.2), rgb(80, 255, 140), M.Neon, V(-0.45, 1.65, 0)),
	}),
	crafted("scrap_magnet", "Scrap Magnet", "Rare", "Crafted", "Tool", "Tool.Magnet", "Pulls nearby scrap towards you.", {
		part(Block, V(0.6, 1.8, 0.6), rgb(220, 50, 50), M.SmoothPlastic, V(-0.7, 0, 0)),
		part(Block, V(0.6, 1.8, 0.6), rgb(220, 50, 50), M.SmoothPlastic, V(0.7, 0, 0)),
		part(Block, V(2, 0.6, 0.6), rgb(220, 50, 50), M.SmoothPlastic, V(0, 0.9, 0)),
		part(Block, V(0.62, 0.4, 0.62), rgb(200, 206, 214), M.Metal, V(-0.7, -0.9, 0)),
		part(Block, V(0.62, 0.4, 0.62), rgb(200, 206, 214), M.Metal, V(0.7, -0.9, 0)),
	}),

	---------------------------------------------------------------------------------------------
	-- Deployables (placeable in Stage 2B)
	---------------------------------------------------------------------------------------------
	crafted("storage_box", "Storage Box", "Common", "Crafted", "Deployable", "Deploy.Storage", "A sturdy box to keep things in.", {
		part(Block, V(2.2, 1.4, 1.6), rgb(176, 124, 74), M.WoodPlanks),
		part(Block, V(2.3, 0.25, 1.7), rgb(120, 85, 50), M.Wood, V(0, 0.8, 0)),
		part(Block, V(0.4, 0.4, 0.1), rgb(200, 206, 214), M.Metal, V(0, 0.4, -0.82)),
	}),
	crafted("spring_launcher", "Spring Launcher", "Uncommon", "Crafted", "Deployable", "Deploy.Launcher", "Step on it. Fly.", {
		part(Block, V(2.2, 0.3, 2.2), rgb(70, 76, 90), M.Metal),
		part(Cylinder, V(0.3, 1.3, 1.3), rgb(235, 55, 130), M.Metal, V(0, 0.45, 0), UPRIGHT),
		part(Cylinder, V(0.3, 1.3, 1.3), rgb(235, 55, 130), M.Metal, V(0, 0.85, 0), UPRIGHT),
		part(Block, V(1.8, 0.25, 1.8), rgb(255, 150, 30), M.SmoothPlastic, V(0, 1.2, 0)),
	}),
	crafted("boombox_radio", "Boombox Radio", "Rare", "Crafted", "Deployable", "Deploy.Radio", "Place it and play some yard tunes.", (function()
		-- An 80s boombox: two speakers with cones, a tape deck with reels, an EQ display, buttons
		-- on top, a carry handle and a telescopic antenna.
		local body, panel, steel, black = rgb(70, 160, 230), rgb(40, 44, 56), rgb(205, 212, 222), rgb(22, 22, 26)
		local SIDE_ON = V(0, 90, 0) -- cylinder facing the front
		local parts = {
			part(Block, V(2.6, 1.4, 0.9), body, M.SmoothPlastic), -- body (root)
			part(Block, V(2.5, 1.3, 0.04), panel, M.SmoothPlastic, V(0, 0, -0.46)),
			part(Block, V(0.55, 0.45, 0.04), rgb(30, 34, 46), M.Glass, V(0, -0.15, -0.49)), -- tape window
			part(Cylinder, V(0.05, 0.16, 0.16), rgb(240, 240, 240), M.SmoothPlastic, V(-0.12, -0.15, -0.515), SIDE_ON),
			part(Cylinder, V(0.05, 0.16, 0.16), rgb(240, 240, 240), M.SmoothPlastic, V(0.12, -0.15, -0.515), SIDE_ON),
			part(Block, V(0.55, 0.2, 0.04), black, M.SmoothPlastic, V(0, 0.3, -0.49)), -- EQ display
		}
		for _, x in { -0.8, 0.8 } do
			table.insert(parts, part(Cylinder, V(0.08, 0.95, 0.95), steel, M.Metal, V(x, -0.05, -0.5), SIDE_ON))
			table.insert(parts, part(Cylinder, V(0.06, 0.8, 0.8), black, M.Fabric, V(x, -0.05, -0.53), SIDE_ON))
			table.insert(parts, part(Cylinder, V(0.06, 0.45, 0.45), rgb(50, 50, 58), M.SmoothPlastic, V(x, -0.05, -0.56), SIDE_ON))
			table.insert(parts, part(Ball, V(0.22, 0.22, 0.22), steel, M.Metal, V(x, -0.05, -0.56)))
		end
		for i, h in { 0.08, 0.14, 0.1, 0.16 } do
			table.insert(parts, part(Block, V(0.06, h, 0.03), if i % 2 == 0 then rgb(255, 210, 60) else rgb(80, 255, 140), M.Neon,
				V(-0.18 + (i - 1) * 0.12, 0.22 + h / 2, -0.515)))
		end
		for i = 0, 4 do
			table.insert(parts, part(Block, V(0.18, 0.08, 0.18), if i == 2 then rgb(230, 60, 60) else steel, M.SmoothPlastic, V(-0.4 + i * 0.2, 0.74, -0.1)))
		end
		table.insert(parts, part(Block, V(0.14, 0.35, 0.14), steel, M.Metal, V(-0.95, 0.87, 0.1)))
		table.insert(parts, part(Block, V(0.14, 0.35, 0.14), steel, M.Metal, V(0.95, 0.87, 0.1)))
		table.insert(parts, part(Cylinder, V(2.04, 0.16, 0.16), steel, M.Metal, V(0, 1.05, 0.1)))
		table.insert(parts, part(Cylinder, V(0.9, 0.22, 0.22), black, M.SmoothPlastic, V(0, 1.05, 0.1)))
		table.insert(parts, B.tube(V(1.1, 0.7, 0.3), V(1.45, 1.95, 0.3), 0.05, steel, M.Metal)) -- antenna
		table.insert(parts, part(Ball, V(0.1, 0.1, 0.1), steel, M.Metal, V(1.45, 1.96, 0.3)))
		return parts
	end)()),
	crafted("generator", "Generator", "Epic", "Crafted", "Deployable", "Deploy.Generator", "Powers nearby gadgets.", (function()
		-- A portable generator in a yellow tube frame: finned engine with a pull start, alternator
		-- with a control panel (outlets, switch, status light), fuel tank and an exhaust pipe.
		-- GadgetController: Part2 = exhaust tip (smoke), Part3 = status light. Keep the order.
		local yellow, dark, steel, red = rgb(255, 196, 40), rgb(60, 66, 80), rgb(190, 196, 206), rgb(220, 60, 50)
		local parts = {
			part(Block, V(1.0, 0.9, 0.9), dark, M.Metal, V(-0.45, -0.3, 0)), -- engine (root)
			part(Block, V(0.3, 0.12, 0.3), rgb(40, 40, 46), M.Metal, V(0.95, 1.3, 0.55)), -- exhaust tip (Part2)
			part(Block, V(0.18, 0.14, 0.05), rgb(80, 255, 140), M.Neon, V(0.35, -0.12, -0.52)), -- status light (Part3)
			part(Cylinder, V(0.9, 0.8, 0.8), rgb(60, 140, 90), M.Metal, V(0.55, -0.3, 0)), -- alternator
			part(Block, V(0.72, 0.55, 0.06), rgb(34, 36, 44), M.SmoothPlastic, V(0.55, -0.3, -0.47)), -- panel
			part(Block, V(0.16, 0.16, 0.04), rgb(255, 150, 40), M.SmoothPlastic, V(0.5, -0.42, -0.51)), -- outlets
			part(Block, V(0.16, 0.16, 0.04), rgb(255, 150, 40), M.SmoothPlastic, V(0.75, -0.42, -0.51)),
			part(Block, V(0.08, 0.14, 0.06), red, M.SmoothPlastic, V(0.75, -0.14, -0.52)), -- switch
			part(Block, V(1.6, 0.5, 1.1), yellow, M.SmoothPlastic, V(-0.1, 0.68, 0)), -- fuel tank
			part(Block, V(1.62, 0.12, 0.02), rgb(30, 30, 36), M.SmoothPlastic, V(-0.1, 0.62, -0.555)),
			part(Cylinder, V(0.12, 0.3, 0.3), rgb(30, 30, 36), M.SmoothPlastic, V(-0.5, 0.98, 0), UPRIGHT), -- fuel cap
			part(Cylinder, V(0.7, 0.3, 0.3), rgb(80, 84, 96), M.Metal, V(0.6, 0.25, 0.5)), -- muffler
			part(Block, V(0.06, 0.5, 0.05), rgb(30, 30, 36), M.SmoothPlastic, V(-0.45, -0.25, -0.475)), -- pull cord
			part(Block, V(0.35, 0.1, 0.1), red, M.SmoothPlastic, V(-0.45, -0.02, -0.53)), -- pull handle
		}
		table.insert(parts, B.tube(V(0.85, 0.3, 0.55), V(0.95, 1.25, 0.55), 0.12, rgb(80, 84, 96), M.Metal))
		for i = 0, 3 do -- cooling fins on the engine
			table.insert(parts, part(Block, V(0.05, 1.0, 1.0), dark, M.Metal, V(-0.85 + i * 0.14, -0.3, 0)))
		end
		for _, x in { -1.15, 1.15 } do
			for _, z in { -0.75, 0.75 } do
				table.insert(parts, part(Cylinder, V(1.9, 0.14, 0.14), yellow, M.Metal, V(x, 0, z), UPRIGHT)) -- frame posts
			end
			table.insert(parts, part(Cylinder, V(1.64, 0.14, 0.14), yellow, M.Metal, V(x, 0.95, 0), V(0, 90, 0))) -- top cross
		end
		for _, z in { -0.75, 0.75 } do
			table.insert(parts, part(Cylinder, V(2.44, 0.14, 0.14), yellow, M.Metal, V(0, 0.95, z))) -- top rails
			table.insert(parts, part(Block, V(2.5, 0.14, 0.2), dark, M.Metal, V(0, -0.88, z))) -- skids
		end
		return parts
	end)()),

	---------------------------------------------------------------------------------------------
	-- Gadgets (Behaviors Kind "Gadget"). Part numbers are used by client/GadgetController: keep
	-- the order.
	---------------------------------------------------------------------------------------------
	crafted("glass_panel", "Glass Panel", "Common", "Crafted", "Deployable", "Deploy.Panel", "Melted bottles. Build windows and walls.", {
		part(Block, V(2.8, 2.4, 0.15), rgb(150, 220, 230), M.Glass),
		part(Block, V(3, 0.15, 0.3), rgb(150, 170, 196), M.Metal, V(0, -1.25, 0)),
		part(Block, V(3, 0.15, 0.3), rgb(150, 170, 196), M.Metal, V(0, 1.25, 0)),
	}),
	crafted("neon_tv", "Neon Television", "Rare", "Crafted", "Deployable", "Deploy.Television", "Five channels. Shows the yard news and the next race.", {
		part(Block, V(3, 1.9, 0.5), rgb(40, 44, 66), M.SmoothPlastic, V(0, 0.4, 0)),
		part(Block, V(2.6, 1.5, 0.1), rgb(20, 24, 40), M.SmoothPlastic, V(0, 0.4, -0.26)),
		part(Block, V(3.1, 0.12, 0.55), rgb(60, 150, 255), M.Neon, V(0, 1.4, 0)),
		part(Block, V(1.6, 0.4, 1), rgb(60, 66, 90), M.Metal, V(0, -0.75, 0)),
	}),
	crafted("disco_ball", "Disco Ball", "Rare", "Crafted", "Deployable", "Deploy.Disco", "Spins, glows, makes everyone dance.", (function()
		-- A mirror ball on a stand: a dark ball (the grout) covered with 46 small mirror tiles in
		-- rings, a bracket, and party lights around the base. Tiles are tiny parts without shadow
		-- or collision. GadgetController: Part2 = ball; the tiles around it spin with it.
		local center = V(0, 1.2, 0)
		local parts = {
			part(Cylinder, V(0.3, 1.6, 1.6), rgb(50, 50, 70), M.Metal, V(0, -1.6, 0), UPRIGHT), -- stand (root)
			part(Ball, V(1.56, 1.56, 1.56), rgb(70, 74, 92), M.Foil, center), -- ball (Part2)
			part(Cylinder, V(2.2, 0.2, 0.2), rgb(160, 166, 180), M.Metal, V(0, -0.5, 0), UPRIGHT), -- pole
			part(Cylinder, V(0.2, 0.42, 0.42), rgb(120, 126, 140), M.Metal, V(0, 0.45, 0), UPRIGHT), -- bracket
			part(Cylinder, V(0.1, 1.66, 1.66), rgb(255, 80, 200), M.Neon, V(0, -1.47, 0), UPRIGHT), -- base glow ring
		}
		for i, color in { rgb(255, 80, 80), rgb(80, 200, 255), rgb(255, 220, 60), rgb(120, 255, 140) } do
			local a = (i - 1) * math.pi / 2 + math.pi / 4
			table.insert(parts, part(Ball, V(0.22, 0.22, 0.22), color, M.Neon, V(math.cos(a) * 0.62, -1.38, math.sin(a) * 0.62)))
		end
		for _, ring in { { -60, 6 }, { -30, 10 }, { 0, 12 }, { 30, 10 }, { 60, 6 } } do
			for k = 0, ring[2] - 1 do
				local lon = (k + (if ring[1] % 60 == 0 then 0 else 0.5)) / ring[2] * math.pi * 2
				local tint = if (k + ring[2]) % 5 == 0 then rgb(210, 225, 255) else rgb(238, 242, 250)
				table.insert(parts, B.at(Block, V(0.05, 0.34, 0.34), tint, M.Foil,
					CFrame.new(center) * CFrame.Angles(0, lon, 0) * CFrame.Angles(0, 0, math.rad(ring[1])) * CFrame.new(0.79, 0, 0)))
			end
		end
		table.insert(parts, part(Cylinder, V(0.05, 0.3, 0.3), rgb(238, 242, 250), M.Foil, center + V(0, 0.79, 0), UPRIGHT)) -- top tile
		table.insert(parts, part(Cylinder, V(0.05, 0.3, 0.3), rgb(238, 242, 250), M.Foil, center - V(0, 0.79, 0), UPRIGHT))
		return parts
	end)()),
	crafted("duck_fountain", "Duck Fountain", "Uncommon", "Crafted", "Deployable", "Deploy.Fountain", "The duck is in charge of the water.", {
		part(Cylinder, V(0.6, 2.6, 2.6), rgb(120, 145, 170), M.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.1, 2.3, 2.3), rgb(90, 190, 240), M.Glass, V(0, 0.3, 0), UPRIGHT),
		part(Ball, V(1, 1, 1), rgb(255, 214, 50), M.SmoothPlastic, V(0, 0.7, 0)),
		part(Ball, V(0.6, 0.6, 0.6), rgb(255, 214, 50), M.SmoothPlastic, V(0, 1.3, -0.2)),
		part(Block, V(0.3, 0.12, 0.3), rgb(255, 130, 40), M.SmoothPlastic, V(0, 1.25, -0.55)),
	}),
	crafted("snow_machine", "Snow Machine", "Rare", "Crafted", "Deployable", "Deploy.SnowMachine", "Your own little winter.", {
		part(Block, V(1.8, 1.2, 1.8), rgb(90, 160, 220), M.Metal),
		part(Cylinder, V(0.9, 0.9, 0.9), rgb(214, 126, 70), M.Metal, V(0, 0.9, 0), UPRIGHT),
		part(Ball, V(1, 1, 1), rgb(230, 244, 255), M.Glass, V(0, 1.6, 0)),
	}),
	crafted("frost_lamp", "Frost Lamp", "Rare", "Crafted", "Deployable", "Deploy.FrostLamp", "A street lamp with a frosty heart.", {
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(40, 50, 80), M.Metal, V(0, -2.2, 0), UPRIGHT),
		part(Ball, V(0.9, 0.9, 0.9), rgb(150, 215, 255), M.SmoothPlastic, V(0, 2.2, 0)),
		part(Cylinder, V(4, 0.25, 0.25), rgb(40, 50, 80), M.Metal, V(0, -0.1, 0), UPRIGHT),
		part(Cylinder, V(0.2, 1.1, 1.1), rgb(40, 50, 80), M.Metal, V(0, 2.75, 0), UPRIGHT),
	}),
	crafted("robot_band", "Robot Band", "Uncommon", "Crafted", "Deployable", "Deploy.Band", "Two tin robots and a lot of rhythm.", {
		part(Block, V(3.2, 0.4, 1.6), rgb(80, 50, 120), M.SmoothPlastic, V(0, -1, 0)),
		part(Block, V(0.8, 1, 0.7), rgb(236, 74, 70), M.Metal, V(-0.9, -0.2, 0)),
		part(Block, V(0.6, 0.5, 0.5), rgb(196, 206, 220), M.Metal, V(-0.9, 0.6, 0)),
		part(Block, V(0.8, 1, 0.7), rgb(60, 150, 255), M.Metal, V(0.9, -0.2, 0)),
		part(Block, V(0.6, 0.5, 0.5), rgb(196, 206, 220), M.Metal, V(0.9, 0.6, 0)),
	}),
	crafted("crystal_beacon", "Crystal Beacon", "Epic", "Crafted", "Deployable", "Deploy.Beacon", "A beam of light everybody can see.", {
		part(Cylinder, V(0.5, 2.2, 2.2), rgb(60, 50, 90), M.Metal, V(0, -0.9, 0), UPRIGHT),
		part(Block, V(0.8, 2, 0.8), rgb(180, 130, 255), M.Neon, V(0, 0.4, 0), V(0, 45, 0)),
		part(Block, V(0.4, 1, 0.4), rgb(140, 200, 255), M.Neon, V(0.6, -0.2, 0.2), V(0, 20, -20)),
	}),
	crafted("toast_cannon", "Toast Cannon", "Uncommon", "Crafted", "Deployable", "Deploy.ToastCannon", "Breakfast, at high altitude.", {
		part(Block, V(2, 1.2, 1.4), rgb(190, 196, 206), M.Metal),
		part(Block, V(1.5, 0.15, 0.3), rgb(40, 40, 46), M.SmoothPlastic, V(0, 0.6, 0)),
		part(Cylinder, V(0.3, 0.8, 0.8), rgb(235, 55, 130), M.Metal, V(0, -0.75, 0), UPRIGHT),
	}),
	crafted("plasma_cannon", "Plasma Fireworks", "Epic", "Crafted", "Deployable", "Deploy.PlasmaCannon", "The toast cannon, but it is plasma now.", {
		part(Block, V(2, 1, 2), rgb(120, 70, 200), M.Metal),
		part(Cylinder, V(1.6, 0.7, 0.7), rgb(60, 50, 90), M.Metal, V(-0.5, 1.2, 0), UPRIGHT),
		part(Cylinder, V(1.6, 0.7, 0.7), rgb(60, 50, 90), M.Metal, V(0.5, 1.2, 0), UPRIGHT),
		part(Block, V(2.1, 0.15, 2.1), rgb(220, 120, 255), M.Neon, V(0, 0.2, 0)),
	}),
	crafted("high_five_machine", "High-Five Machine", "Uncommon", "Crafted", "Deployable", "Deploy.HighFive", "It believes in you.", {
		part(Block, V(1.4, 1, 1.4), rgb(255, 150, 30), M.SmoothPlastic, V(0, -1, 0)),
		part(Block, V(1.2, 1.4, 0.5), rgb(220, 70, 70), M.Fabric, V(0, 1.1, 0)),
		part(Cylinder, V(1.4, 0.3, 0.3), rgb(200, 206, 214), M.Metal, V(0, 0, 0), UPRIGHT),
	}),
	crafted("arcade_machine", "Arcade Machine", "Rare", "Crafted", "Deployable", "Deploy.Arcade", "Reaction Rush: beat the best time of the yard.", {
		part(Block, V(1.8, 3.2, 1.4), rgb(60, 70, 170), M.SmoothPlastic),
		part(Block, V(1.5, 1.1, 0.1), rgb(20, 24, 40), M.SmoothPlastic, V(0, 0.6, -0.72)),
		part(Block, V(1.7, 0.2, 0.7), rgb(30, 34, 60), M.SmoothPlastic, V(0, -0.3, -0.95)),
		part(Ball, V(0.35, 0.35, 0.35), rgb(255, 60, 60), M.SmoothPlastic, V(-0.4, 0, -1)),
		part(Block, V(1.6, 0.36, 0.14), rgb(255, 80, 180), M.Neon, V(0, 1.36, -0.79)),
	}),
	crafted("hologram_projector", "Hologram Projector", "Legendary", "Crafted", "Deployable", "Deploy.Hologram", "Shows a hologram of any item you hold.", {
		part(Cylinder, V(0.5, 2, 2), rgb(40, 50, 80), M.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.1, 1.5, 1.5), rgb(120, 255, 220), M.Neon, V(0, 0.28, 0), UPRIGHT),
	}),
	crafted("rocket_boots", "Rocket Boots", "Uncommon", "Crafted", "Tool", "Ability.RocketBoots", "Two old boots with a very strong opinion about gravity.", (function()
		-- The same pair the character wears (client/CarryController buildBoot): navy boots with
		-- orange toe caps and cuffs, a glowing stripe, a chrome booster with a nozzle and fins.
		local navy, orange, chrome, black = rgb(38, 46, 74), rgb(255, 132, 30), rgb(205, 212, 224), rgb(26, 27, 32)
		local parts = {
			part(Block, V(0.5, 0.12, 0.4), black, M.Fabric, V(0, 0.2, 0.15)), -- the laces tying the pair (root)
		}
		for _, x in { -0.62, 0.62 } do
			local function at(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?, upright: boolean?)
				table.insert(parts, part(shape or Block, size, color, material, V(x, -0.9, 0) + offset, if upright then UPRIGHT else nil))
			end
			at(V(1.16, 0.2, 1.5), V(0, 0.1, -0.05), black, M.Slate)
			at(V(1.1, 0.5, 1.2), V(0, 0.42, 0.05), navy, M.SmoothPlastic)
			at(V(1.12, 0.42, 0.5), V(0, 0.38, -0.56), orange, M.Metal)
			at(V(1.06, 1.05, 0.98), V(0, 1.12, 0.15), navy, M.SmoothPlastic)
			at(V(1.16, 0.2, 1.08), V(0, 1.7, 0.15), orange, M.Metal)
			at(V(1.1, 0.1, 1.02), V(0, 0.9, 0.15), rgb(90, 230, 255), M.Neon)
			at(V(0.95, 0.48, 0.48), V(0, 1.0, 0.82), chrome, M.Metal, Cylinder, true)
			at(V(0.12, 0.52, 0.52), V(0, 1.5, 0.82), orange, M.Metal, Cylinder, true)
			at(V(0.22, 0.56, 0.56), V(0, 0.42, 0.82), black, M.Metal, Cylinder, true)
			at(V(0.06, 0.38, 0.38), V(0, 0.29, 0.82), rgb(255, 170, 60), M.Neon, Cylinder, true)
			at(V(0.06, 0.4, 0.32), V(-0.32, 0.62, 1.0), rgb(236, 74, 70), M.Metal)
			at(V(0.06, 0.4, 0.32), V(0.32, 0.62, 1.0), rgb(236, 74, 70), M.Metal)
		end
		return parts
	end)()),
	crafted("jet_board", "Jet Board", "Epic", "Crafted", "Vehicle", "Vehicle.JetBoard", "A jet sled on ice skates. What could go wrong?", {
		part(Block, V(1.2, 0.25, 3), rgb(70, 210, 240), M.SmoothPlastic),
		part(Block, V(0.1, 0.25, 2.6), rgb(220, 230, 240), M.Metal, V(-0.4, -0.25, 0)),
		part(Block, V(0.1, 0.25, 2.6), rgb(220, 230, 240), M.Metal, V(0.4, -0.25, 0)),
		part(Cylinder, V(0.9, 0.5, 0.5), rgb(60, 66, 90), M.Metal, V(0, 0.35, 1.2), V(0, 90, 0)),
	}),
	crafted("teleport_pad", "Teleport Pad", "Epic", "Crafted", "Deployable", "Deploy.Teleport", "Place two: travel from one to the other.", {
		part(Cylinder, V(0.35, 2.6, 2.6), rgb(40, 50, 80), M.Metal, nil, UPRIGHT),
		part(Cylinder, V(0.1, 2.1, 2.1), rgb(120, 90, 255), M.Neon, V(0, 0.2, 0), UPRIGHT),
		part(Cylinder, V(0.45, 0.5, 0.5), rgb(90, 220, 255), M.Neon, V(0, 0.1, 0), UPRIGHT),
	}),
	crafted("golden_throne", "Golden Throne", "Legendary", "Crafted", "Deployable", "Deploy.Throne", "For the ruler of the junkyard.", (function()
		-- A gold throne: plinth with claw feet, velvet seat and arched back, pillars with glowing
		-- finials, scrolled armrests, gems and a little crown on top.
		local gold, goldDark, velvet, ice = rgb(255, 205, 50), rgb(214, 160, 30), rgb(190, 40, 70), rgb(150, 220, 255)
		local SIDE_ON = V(0, 90, 0)
		local parts = {
			part(Block, V(1.8, 0.7, 1.5), gold, M.Metal, V(0, -0.75, 0)), -- seat base (root)
			part(Block, V(2.0, 0.15, 1.7), goldDark, M.Metal, V(0, -1.15, 0)), -- plinth
			part(Block, V(1.5, 0.22, 1.3), velvet, M.Fabric, V(0, -0.3, -0.05)), -- seat cushion
			part(Block, V(1.6, 1.8, 0.25), gold, M.Metal, V(0, 0.5, 0.65)), -- back
			part(Cylinder, V(0.25, 1.6, 1.6), gold, M.Metal, V(0, 1.4, 0.65), SIDE_ON), -- arch
			part(Block, V(1.2, 1.3, 0.08), velvet, M.Fabric, V(0, 0.5, 0.5)),
			part(Cylinder, V(0.08, 1.2, 1.2), velvet, M.Fabric, V(0, 1.15, 0.5), SIDE_ON),
			part(Block, V(0.3, 0.3, 0.06), ice, M.Neon, V(0, 1.2, 0.44), V(0, 0, 45)), -- gem on the back
			part(Block, V(0.7, 0.2, 0.15), gold, M.Metal, V(0, 2.28, 0.65)), -- crown
		}
		for i = -1, 1 do
			table.insert(parts, part(Block, V(0.16, 0.16, 0.16), ice, M.Neon, V(i * 0.25, 2.44, 0.65), V(45, 0, 45)))
			table.insert(parts, part(Block, V(0.16, 0.16, 0.05), if i == 0 then velvet else ice, M.Neon, V(i * 0.5, -0.75, -0.765), V(0, 0, 45)))
		end
		for _, x in { -0.85, 0.85 } do
			table.insert(parts, part(Cylinder, V(2.0, 0.22, 0.22), goldDark, M.Metal, V(x, 0.6, 0.62), UPRIGHT)) -- pillar
			table.insert(parts, part(Ball, V(0.36, 0.36, 0.36), ice, M.Neon, V(x, 1.72, 0.62))) -- finial
			table.insert(parts, part(Block, V(0.25, 0.25, 1.4), gold, M.Metal, V(x, 0.1, -0.05))) -- armrest
			table.insert(parts, part(Block, V(0.22, 0.45, 0.22), gold, M.Metal, V(x, -0.18, -0.65)))
			table.insert(parts, part(Ball, V(0.32, 0.32, 0.32), goldDark, M.Metal, V(x, 0.12, -0.75))) -- scroll
			for _, z in { -0.7, 0.7 } do
				table.insert(parts, part(Ball, V(0.3, 0.3, 0.3), goldDark, M.Metal, V(x * 1.05, -1.25, z))) -- claw feet
			end
		end
		return parts
	end)()),
	crafted("dragon_incubator", "Dragon Incubator", "Mythic", "Crafted", "Deployable", "Deploy.Incubator", "The egg hatched. It likes flying.", {
		part(Cylinder, V(0.6, 2.4, 2.4), rgb(40, 50, 80), M.Metal, nil, UPRIGHT),
		part(Ball, V(1.5, 1.5, 1.5), rgb(120, 220, 255), M.Ice, V(0, 0.9, 0)),
		part(Cylinder, V(0.15, 2.1, 2.1), rgb(255, 150, 60), M.Neon, V(0, 0.3, 0), UPRIGHT),
	}),
	crafted("cosmic_gate", "Cosmic Gate", "Mythic", "Crafted", "Deployable", "Deploy.CosmicGate", "A window to the stars.", {
		part(Block, V(3, 0.4, 1.4), rgb(50, 40, 80), M.Metal, V(0, -1.9, 0)),
		part(Cylinder, V(0.15, 2.8, 2.8), rgb(60, 40, 110), M.Glass, nil, V(0, 90, 0)),
		part(Ball, V(0.5, 0.5, 0.5), rgb(255, 220, 120), M.Neon, V(0, 1.6, 0)),
		part(Ball, V(0.5, 0.5, 0.5), rgb(150, 200, 255), M.Neon, V(1.5, -0.5, 0)),
		part(Ball, V(0.5, 0.5, 0.5), rgb(255, 120, 220), M.Neon, V(-1.5, -0.5, 0)),
	}),

	---------------------------------------------------------------------------------------------
	-- Special creations
	---------------------------------------------------------------------------------------------
	crafted("scrap_snowman", "Scrap Snowman", "Common", "Crafted", "Deployable", "Deploy.Snowman", "A snowman built from cans. Very festive.", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(196, 204, 216), M.Metal),
		part(Ball, V(1.3, 1.3, 1.3), rgb(196, 204, 216), M.Metal, V(0, 1.4, 0)),
		part(Cylinder, V(0.9, 1, 1), rgb(120, 145, 170), M.Metal, V(0, 2.4, 0), UPRIGHT),
		part(Block, V(0.15, 0.15, 0.5), rgb(255, 140, 40), M.SmoothPlastic, V(0, 1.4, -0.7)),
	}),
	crafted("junk_robot", "Junk Robot", "Epic", "Crafted", "Collectible", "Companion.Robot", "It beeps. It follows. It is your friend.", {
		part(Block, V(1.6, 1.6, 1.2), rgb(120, 145, 170), M.Metal),
		part(Block, V(1.1, 0.9, 0.9), rgb(140, 160, 186), M.Metal, V(0, 1.3, 0)),
		part(Ball, V(0.3, 0.3, 0.3), rgb(80, 230, 255), M.Neon, V(-0.25, 1.35, -0.46)),
		part(Ball, V(0.3, 0.3, 0.3), rgb(80, 230, 255), M.Neon, V(0.25, 1.35, -0.46)),
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(255, 170, 40), M.Metal, V(-1, 0, 0)),
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(255, 170, 40), M.Metal, V(1, 0, 0)),
	}),
	crafted("golden_trophy", "Golden Trophy", "Legendary", "Crafted", "Collectible", nil, "The dented trophy, restored to glory.", (function()
		-- A gold cup with a rounded bowl, rolled rim, two curved handles and gems, on a stem with a
		-- knot, standing on a two-step wooden base with an engraved plaque.
		local gold, goldLight, goldDark, wood = rgb(255, 205, 50), rgb(255, 228, 120), rgb(186, 136, 30), rgb(80, 55, 35)
		local parts = {
			part(Cylinder, V(1.1, 1.3, 1.3), gold, M.Metal, V(0, 0.75, 0), UPRIGHT), -- cup (root)
			part(Ball, V(1.3, 1.3, 1.3), gold, M.Metal, V(0, 0.45, 0)), -- bowl
			part(Cylinder, V(0.06, 1.16, 1.16), goldDark, M.Metal, V(0, 1.29, 0), UPRIGHT), -- inside
			part(Cylinder, V(0.12, 1.46, 1.46), goldLight, M.Metal, V(0, 1.3, 0), UPRIGHT), -- rim
			part(Cylinder, V(0.4, 0.3, 0.3), gold, M.Metal, V(0, -0.35, 0), UPRIGHT), -- stem
			part(Ball, V(0.45, 0.45, 0.45), goldLight, M.Metal, V(0, -0.3, 0)), -- knot
			part(Cylinder, V(0.1, 0.8, 0.8), gold, M.Metal, V(0, -0.55, 0), UPRIGHT), -- foot
			part(Block, V(1.15, 0.2, 1.15), wood, M.Wood, V(0, -0.7, 0)),
			part(Block, V(1.5, 0.4, 1.5), wood, M.Wood, V(0, -1.0, 0)),
			part(Block, V(0.8, 0.24, 0.03), gold, M.Metal, V(0, -1.0, -0.765)), -- plaque
			part(Block, V(0.55, 0.04, 0.035), goldDark, M.Metal, V(0, -0.96, -0.77)),
			part(Block, V(0.4, 0.04, 0.035), goldDark, M.Metal, V(0, -1.04, -0.77)),
			part(Block, V(0.32, 0.32, 0.06), rgb(160, 110, 255), M.Neon, V(0, 0.8, -0.66), V(0, 0, 45)), -- gem
			part(Block, V(0.16, 0.16, 0.05), rgb(120, 220, 255), M.Neon, V(-0.35, 0.6, -0.58), V(0, -30, 45)),
			part(Block, V(0.16, 0.16, 0.05), rgb(120, 220, 255), M.Neon, V(0.35, 0.6, -0.58), V(0, 30, 45)),
		}
		for _, s in { -1, 1 } do
			B.join(parts, B.path({ V(s * 0.62, 1.1, 0), V(s * 1.0, 1.05, 0), V(s * 1.05, 0.6, 0), V(s * 0.6, 0.42, 0) }, 0.14, gold, M.Metal))
		end
		return parts
	end)()),
	crafted("aurora_reactor", "Aurora Reactor", "Mythic", "Crafted", "Deployable", "Deploy.Reactor", "Crystal power in a glass bottle.", {
		part(Cylinder, V(0.5, 2.4, 2.4), rgb(50, 40, 80), M.Metal, V(0, -1.2, 0), UPRIGHT),
		part(Ball, V(2.2, 2.2, 2.2), rgb(170, 220, 255), M.Glass),
		part(Ball, V(1.1, 1.1, 1.1), rgb(255, 80, 180), M.Neon),
		part(Cylinder, V(0.15, 2.6, 2.6), rgb(120, 255, 200), M.Neon, nil, V(0, 0, 90)),
		part(Cylinder, V(0.5, 1.2, 1.2), rgb(50, 40, 80), M.Metal, V(0, 1.2, 0), UPRIGHT),
	}),
}
