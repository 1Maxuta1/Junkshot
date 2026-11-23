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
	crafted("battery_pack", "Battery Pack", "Uncommon", "Component", "Component", nil, "Two batteries wired together.", {
		part(Block, V(1.8, 1.1, 1.2), rgb(40, 110, 220), M.SmoothPlastic),
		part(Block, V(1.9, 0.2, 1.3), rgb(255, 210, 60), M.Neon, V(0, 0.2, 0)),
		part(Block, V(0.3, 0.3, 0.3), rgb(220, 50, 50), M.Metal, V(-0.5, 0.7, 0)),
	}),
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
		part(Cylinder, V(2.6, 0.3, 0.3), rgb(255, 150, 30), M.Metal, V(0, 0.2, 0), V(0, 90, 20)),
		wheel(V(0, -0.5, -1.3), 1.8),
		wheel(V(0, -0.5, 1.3), 1.8),
		part(Block, V(0.4, 0.15, 0.7), rgb(40, 40, 46), M.SmoothPlastic, V(0, 0.9, 0.6)),
		part(Cylinder, V(1.2, 0.15, 0.15), rgb(60, 66, 80), M.Metal, V(0, 1.05, -1)),
	}),
	crafted("metal_cart", "Metal Cart", "Uncommon", "Crafted", "Vehicle", "Tool.Cart", "Carries extra junk around the yard.", {
		part(Block, V(1.8, 0.8, 2.4), rgb(150, 170, 196), M.Metal),
		wheel(V(-1, -0.5, 0), 1.2),
		wheel(V(1, -0.5, 0), 1.2),
		part(Cylinder, V(1.6, 0.2, 0.2), rgb(60, 66, 80), M.Metal, V(0, 0.7, 1.5), V(0, 90, -40)),
	}),
	crafted("scooter", "Scooter", "Rare", "Crafted", "Vehicle", "Vehicle.Scooter", "A motor scooter with questionable brakes.", {
		part(Block, V(0.9, 0.25, 2.6), rgb(60, 150, 255), M.SmoothPlastic),
		wheel(V(0, -0.35, -1.2), 0.9),
		wheel(V(0, -0.35, 1.2), 0.9),
		part(Cylinder, V(2, 0.2, 0.2), rgb(200, 206, 214), M.Metal, V(0, 1, -1.2), UPRIGHT),
		part(Block, V(0.7, 0.5, 0.7), rgb(70, 80, 96), M.Metal, V(0, 0.35, 0.9)),
	}),
	crafted("homemade_car", "Homemade Car", "Epic", "Crafted", "Vehicle", "Vehicle.Car", "Four tires, a frame and an engine. Drive it home.", {
		part(Block, V(2.2, 0.8, 3.4), rgb(236, 74, 70), M.SmoothPlastic),
		part(Block, V(1.8, 0.8, 1.6), rgb(140, 210, 255), M.Glass, V(0, 0.8, 0.2)),
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
	crafted("boombox_radio", "Boombox Radio", "Rare", "Crafted", "Deployable", "Deploy.Radio", "Place it and play some yard tunes.", {
		part(Block, V(2.4, 1.4, 0.9), rgb(70, 160, 230), M.SmoothPlastic),
		part(Cylinder, V(0.1, 0.9, 0.9), rgb(40, 40, 46), M.Slate, V(-0.65, 0, -0.48), V(0, 90, 0)),
		part(Cylinder, V(0.1, 0.9, 0.9), rgb(40, 40, 46), M.Slate, V(0.65, 0, -0.48), V(0, 90, 0)),
		part(Block, V(1.8, 0.2, 0.2), rgb(200, 206, 214), M.Metal, V(0, 0.95, 0)),
	}),
	crafted("generator", "Generator", "Epic", "Crafted", "Deployable", "Deploy.Generator", "Powers nearby gadgets.", {
		part(Block, V(2.4, 1.4, 1.6), rgb(255, 196, 40), M.Metal),
		part(Cylinder, V(1.2, 0.9, 0.9), rgb(60, 140, 90), M.Metal, V(0, 1.1, 0.3), V(0, 90, 0)),
		part(Block, V(0.4, 0.3, 0.1), rgb(80, 255, 140), M.Neon, V(-0.7, 0.2, -0.82)),
		part(Block, V(2.6, 0.2, 1.8), rgb(60, 66, 80), M.Metal, V(0, -0.8, 0)),
	}),

	---------------------------------------------------------------------------------------------
	-- Special creations
	---------------------------------------------------------------------------------------------
	crafted("scrap_snowman", "Scrap Snowman", "Common", "Crafted", "Collectible", nil, "A snowman built from cans. Very festive.", {
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
	crafted("golden_trophy", "Golden Trophy", "Legendary", "Crafted", "Collectible", nil, "The dented trophy, restored to glory.", {
		part(Block, V(1.4, 0.5, 1.4), rgb(80, 55, 35), M.Wood, V(0, -0.9, 0)),
		part(Cylinder, V(0.9, 0.35, 0.35), rgb(255, 205, 50), M.Metal, V(0, -0.25, 0), UPRIGHT),
		part(Cylinder, V(1.2, 1.5, 1.5), rgb(255, 205, 50), M.Metal, V(0, 0.75, 0), UPRIGHT),
		part(Ball, V(0.4, 0.4, 0.4), rgb(160, 110, 255), M.Neon, V(0, 1.55, 0)),
	}),
	crafted("aurora_reactor", "Aurora Reactor", "Mythic", "Crafted", "Deployable", "Deploy.Reactor", "Crystal power in a glass bottle.", {
		part(Cylinder, V(0.5, 2.4, 2.4), rgb(50, 40, 80), M.Metal, V(0, -1.2, 0), UPRIGHT),
		part(Ball, V(2.2, 2.2, 2.2), rgb(170, 220, 255), M.Glass),
		part(Ball, V(1.1, 1.1, 1.1), rgb(255, 80, 180), M.Neon),
		part(Cylinder, V(0.15, 2.6, 2.6), rgb(120, 255, 200), M.Neon, nil, V(0, 0, 90)),
		part(Cylinder, V(0.5, 1.2, 1.2), rgb(50, 40, 80), M.Metal, V(0, 1.2, 0), UPRIGHT),
	}),
}
