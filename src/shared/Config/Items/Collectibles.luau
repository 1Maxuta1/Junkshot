--!strict
--[[
	Collectibles: valuable finished objects (Category "Collectible"), 3 per rarity.
	They are recycling / mythic-crafting rewards (RecyclePool) and can also be found lying in
	the yard with the world rarity chances (NaturalSpawn).

	The two debug_* items exist only for tests; InventoryService refuses them outside Studio
	and they never spawn or drop.
]]

local Types = require(script.Parent.Parent.Parent.Types)
local B = require(script.Parent.Builder)

local Block, Ball, Cylinder, M = B.Block, B.Ball, B.Cylinder, B.M
local UPRIGHT, V, rgb, part = B.UPRIGHT, B.V, B.rgb, B.part

-- Mythic items with an ability (Config/Behaviors "Ability.*": click to use, then a cooldown).
local function withBehavior(behaviorId: string, definition: Types.ItemDefinition): Types.ItemDefinition
	definition.BehaviorId = behaviorId
	return definition
end

local function item(id: string, displayName: string, rarity: string, parts: { Types.JunkPartSpec }): Types.ItemDefinition
	return {
		Id = id,
		DisplayName = displayName,
		Rarity = rarity,
		Category = "Collectible",
		Parts = parts,
		NaturalSpawn = true,
		SpawnWeight = 1,
		RecyclePool = true,
	}
end

return {
	-- Debug items (tests only; no model, never spawned or rewarded).
	{ Id = "debug_rusty_gear", DisplayName = "DEBUG Rusty Gear", Rarity = "Common", Category = "Collectible", IsDebug = true },
	{ Id = "debug_golden_toaster", DisplayName = "DEBUG Golden Toaster", Rarity = "Epic", Category = "Collectible", IsDebug = true },

	-- Common
	item("tin_robot", "Tin Robot", "Common", {
		part(Block, V(1.6, 1.8, 1.2), rgb(176, 188, 204), M.Metal),
		part(Block, V(1.2, 1, 1), rgb(196, 206, 220), M.Metal, V(0, 1.45, 0)),
		part(Ball, V(0.35, 0.35, 0.35), rgb(255, 80, 70), M.Neon, V(0, 2.15, 0)),
		part(Block, V(0.5, 0.2, 0.1), rgb(40, 50, 70), M.SmoothPlastic, V(0, 1.5, -0.52)),
	}),
	item("snow_globe", "Snow Globe", "Common", {
		part(Cylinder, V(0.6, 1.8, 1.8), rgb(150, 96, 60), M.Wood, nil, UPRIGHT),
		part(Ball, V(1.7, 1.7, 1.7), rgb(210, 236, 255), M.Glass, V(0, 1.1, 0)),
		part(Ball, V(0.7, 0.7, 0.7), rgb(255, 255, 255), M.SmoothPlastic, V(0, 0.9, 0)),
	}),
	item("patched_mitten", "Patched Mitten", "Common", {
		part(Block, V(1.4, 1.8, 0.6), rgb(220, 70, 70), M.Fabric),
		part(Block, V(0.6, 0.8, 0.55), rgb(220, 70, 70), M.Fabric, V(0.85, 0.1, 0), V(0, 0, -30)),
		part(Block, V(1.5, 0.4, 0.65), rgb(250, 250, 250), M.Fabric, V(0, -0.9, 0)),
		part(Block, V(0.5, 0.5, 0.05), rgb(255, 200, 60), M.Fabric, V(-0.2, 0.3, -0.31)),
	}),

	-- Uncommon
	item("copper_kettle", "Copper Kettle", "Uncommon", {
		part(Ball, V(1.9, 1.9, 1.9), rgb(214, 126, 70), M.Metal),
		part(Cylinder, V(0.3, 1.2, 1.2), rgb(60, 60, 70), M.Metal, V(0, 0.95, 0), UPRIGHT),
		part(Cylinder, V(1.2, 0.35, 0.35), rgb(214, 126, 70), M.Metal, V(1.1, 0.2, 0), V(0, 0, 40)),
		part(Block, V(0.2, 1, 1.4), rgb(60, 60, 70), M.Metal, V(-1, 0.4, 0)),
	}),
	item("ice_skate", "Ice Skate", "Uncommon", {
		part(Block, V(0.9, 1.4, 2), rgb(80, 200, 120), M.SmoothPlastic),
		part(Block, V(0.9, 0.8, 0.9), rgb(80, 200, 120), M.SmoothPlastic, V(0, 1.05, 0.55)),
		part(Block, V(0.15, 0.25, 2.6), rgb(220, 230, 240), M.Metal, V(0, -0.85, 0)),
	}),
	item("spring_bot", "Spring Bot", "Uncommon", {
		part(Ball, V(1.5, 1.5, 1.5), rgb(80, 210, 140), M.SmoothPlastic),
		part(Cylinder, V(0.3, 1.1, 1.1), rgb(235, 55, 130), M.Metal, V(0, -0.95, 0), UPRIGHT),
		part(Cylinder, V(0.3, 1.1, 1.1), rgb(235, 55, 130), M.Metal, V(0, -1.3, 0), UPRIGHT),
		part(Ball, V(0.45, 0.45, 0.45), rgb(255, 255, 255), M.Neon, V(0, 0.2, -0.6)),
	}),

	-- Rare
	item("neon_gear", "Neon Gear", "Rare", {
		part(Cylinder, V(0.5, 2.4, 2.4), rgb(60, 150, 255), M.Neon, nil, UPRIGHT),
		part(Cylinder, V(0.6, 0.9, 0.9), rgb(30, 40, 70), M.Metal, nil, UPRIGHT),
		part(Block, V(0.6, 0.5, 0.6), rgb(60, 150, 255), M.Neon, V(1.3, 0, 0)),
		part(Block, V(0.6, 0.5, 0.6), rgb(60, 150, 255), M.Neon, V(-1.3, 0, 0)),
		part(Block, V(0.6, 0.5, 0.6), rgb(60, 150, 255), M.Neon, V(0, 0, 1.3)),
		part(Block, V(0.6, 0.5, 0.6), rgb(60, 150, 255), M.Neon, V(0, 0, -1.3)),
	}),
	item("arcade_joystick", "Arcade Joystick", "Rare", {
		part(Block, V(2.2, 0.6, 1.6), rgb(40, 60, 120), M.SmoothPlastic),
		part(Cylinder, V(1.2, 0.25, 0.25), rgb(30, 30, 40), M.Metal, V(-0.4, 0.8, 0), UPRIGHT),
		part(Ball, V(0.6, 0.6, 0.6), rgb(255, 60, 60), M.SmoothPlastic, V(-0.4, 1.45, 0)),
		part(Cylinder, V(0.15, 0.45, 0.45), rgb(60, 150, 255), M.Neon, V(0.5, 0.35, -0.2), UPRIGHT),
		part(Cylinder, V(0.15, 0.45, 0.45), rgb(255, 210, 60), M.Neon, V(0.5, 0.35, 0.35), UPRIGHT),
	}),
	item("frost_lantern", "Frost Lantern", "Rare", {
		part(Block, V(1.3, 0.25, 1.3), rgb(40, 50, 80), M.Metal, V(0, -0.9, 0)),
		part(Block, V(1.1, 1.5, 1.1), rgb(140, 210, 255), M.Glass),
		part(Ball, V(0.7, 0.7, 0.7), rgb(120, 200, 255), M.Neon),
		part(Block, V(1.3, 0.25, 1.3), rgb(40, 50, 80), M.Metal, V(0, 0.9, 0)),
		part(Cylinder, V(0.15, 0.7, 0.7), rgb(40, 50, 80), M.Metal, V(0, 1.2, 0)),
	}),

	-- Epic
	item("plasma_toaster", "Plasma Toaster", "Epic", {
		part(Block, V(2.2, 1.4, 1.4), rgb(120, 70, 200), M.Metal),
		part(Block, V(1.6, 0.12, 0.35), rgb(220, 120, 255), M.Neon, V(0, 0.72, -0.25)),
		part(Block, V(1.6, 0.12, 0.35), rgb(220, 120, 255), M.Neon, V(0, 0.72, 0.25)),
		part(Block, V(0.35, 0.3, 0.35), rgb(255, 255, 255), M.Neon, V(0.75, 0.3, -0.72)),
	}),
	item("crystal_snowman", "Crystal Snowman", "Epic", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(200, 170, 255), M.Glass),
		part(Ball, V(1.3, 1.3, 1.3), rgb(200, 170, 255), M.Glass, V(0, 1.35, 0)),
		part(Ball, V(0.9, 0.9, 0.9), rgb(220, 200, 255), M.Glass, V(0, 2.3, 0)),
		part(Block, V(0.15, 0.15, 0.5), rgb(255, 140, 40), M.Neon, V(0, 2.3, -0.6)),
		part(Cylinder, V(0.6, 0.7, 0.7), rgb(140, 70, 220), M.Neon, V(0, 2.85, 0), UPRIGHT),
	}),
	item("jet_sled", "Jet Sled", "Epic", {
		part(Block, V(1.6, 0.4, 3), rgb(150, 80, 230), M.SmoothPlastic),
		part(Block, V(0.2, 0.2, 3.2), rgb(220, 230, 240), M.Metal, V(-0.6, -0.35, 0)),
		part(Block, V(0.2, 0.2, 3.2), rgb(220, 230, 240), M.Metal, V(0.6, -0.35, 0)),
		part(Cylinder, V(1, 0.7, 0.7), rgb(60, 60, 80), M.Metal, V(0, 0.5, 1.2), V(0, 90, 0)),
		part(Cylinder, V(0.2, 0.55, 0.55), rgb(255, 140, 40), M.Neon, V(0, 0.5, 1.75), V(0, 90, 0)),
	}),

	-- Legendary
	item("golden_wrench", "Golden Wrench", "Legendary", {
		part(Block, V(0.4, 0.3, 2.8), rgb(255, 200, 40), M.Metal),
		part(Block, V(1.2, 0.3, 0.6), rgb(255, 200, 40), M.Metal, V(0, 0, -1.6)),
		part(Block, V(0.35, 0.3, 0.7), rgb(255, 200, 40), M.Metal, V(-0.42, 0, -2.1)),
		part(Block, V(0.35, 0.3, 0.7), rgb(255, 200, 40), M.Metal, V(0.42, 0, -2.1)),
		part(Ball, V(0.35, 0.35, 0.35), rgb(255, 255, 200), M.Neon, V(0, 0.2, 0.9)),
	}),
	item("aurora_orb", "Aurora Orb", "Legendary", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(120, 255, 200), M.Neon),
		part(Cylinder, V(0.15, 2.4, 2.4), rgb(255, 210, 60), M.Metal, nil, V(0, 0, 90)),
		part(Cylinder, V(0.15, 2.4, 2.4), rgb(255, 210, 60), M.Metal, nil, V(0, 90, 0)),
		part(Cylinder, V(0.4, 1.2, 1.2), rgb(60, 50, 80), M.Metal, V(0, -1.1, 0), UPRIGHT),
	}),
	item("frozen_crown", "Frozen Crown", "Legendary", {
		part(Cylinder, V(0.6, 2, 2), rgb(255, 205, 50), M.Metal, nil, UPRIGHT),
		part(Block, V(0.35, 0.9, 0.35), rgb(255, 205, 50), M.Metal, V(0.8, 0.6, 0)),
		part(Block, V(0.35, 0.9, 0.35), rgb(255, 205, 50), M.Metal, V(-0.8, 0.6, 0)),
		part(Block, V(0.35, 0.9, 0.35), rgb(255, 205, 50), M.Metal, V(0, 0.6, 0.8)),
		part(Block, V(0.35, 0.9, 0.35), rgb(255, 205, 50), M.Metal, V(0, 0.6, -0.8)),
		part(Ball, V(0.5, 0.5, 0.5), rgb(140, 220, 255), M.Neon, V(0, 0.15, -1)),
	}),

	-- Mythic
	withBehavior("Ability.Starfall", item("starforged_core", "Starforged Core", "Mythic", {
		part(Ball, V(1.6, 1.6, 1.6), rgb(255, 90, 180), M.Neon),
		part(Block, V(2.4, 0.3, 0.3), rgb(255, 230, 120), M.Neon, nil, V(0, 0, 45)),
		part(Block, V(2.4, 0.3, 0.3), rgb(255, 230, 120), M.Neon, nil, V(0, 0, -45)),
		part(Block, V(0.3, 0.3, 2.4), rgb(120, 230, 255), M.Neon, nil, V(45, 0, 0)),
		part(Cylinder, V(0.15, 2.6, 2.6), rgb(40, 30, 70), M.Metal, nil, V(0, 0, 90)),
	})),
	item("dragon_egg", "Polar Dragon Egg", "Mythic", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(110, 220, 255), M.Glass),
		part(Ball, V(1.3, 1.3, 1.3), rgb(255, 80, 170), M.Neon),
		part(Ball, V(1.5, 1.5, 1.5), rgb(110, 220, 255), M.Glass, V(0, 0.75, 0)),
		part(Cylinder, V(0.4, 2, 2), rgb(60, 50, 90), M.Slate, V(0, -0.9, 0), UPRIGHT),
	}),
	withBehavior("Ability.Comet", item("comet_shard", "Comet Shard", "Mythic", {
		part(Block, V(0.9, 2.6, 0.9), rgb(255, 120, 220), M.Neon, nil, V(0, 45, 15)),
		part(Block, V(0.6, 1.6, 0.6), rgb(140, 230, 255), M.Neon, V(0.7, -0.3, 0.2), V(0, 20, -25)),
		part(Block, V(0.5, 1.2, 0.5), rgb(255, 230, 120), M.Neon, V(-0.6, -0.5, -0.2), V(10, 0, 30)),
		part(Cylinder, V(0.4, 1.8, 1.8), rgb(50, 40, 80), M.Slate, V(0, -1.3, 0), UPRIGHT),
	})),
}
