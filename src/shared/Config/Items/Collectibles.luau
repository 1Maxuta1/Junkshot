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
	item("copper_kettle", "Copper Kettle", "Uncommon", (function()
		-- A round copper kettle: foot ring, shoulder band, lid with a wooden knob, a curved spout
		-- and a bail handle over the top.
		local copper, copperDark, brass, wood = rgb(214, 126, 70), rgb(170, 90, 46), rgb(226, 182, 96), rgb(46, 32, 24)
		local parts = {
			part(Ball, V(1.9, 1.9, 1.9), copper, M.Metal), -- body (root)
			part(Cylinder, V(0.22, 1.3, 1.3), copperDark, M.Metal, V(0, -0.82, 0), UPRIGHT), -- foot ring
			part(Cylinder, V(0.08, 1.8, 1.8), copperDark, M.Metal, V(0, 0.35, 0), UPRIGHT), -- shoulder band
			part(Cylinder, V(0.14, 1.0, 1.0), copperDark, M.Metal, V(0, 0.86, 0), UPRIGHT), -- lid
			part(Ball, V(0.7, 0.7, 0.7), copper, M.Metal, V(0, 0.82, 0)),
			part(Cylinder, V(0.2, 0.14, 0.14), brass, M.Metal, V(0, 1.22, 0), UPRIGHT),
			part(Ball, V(0.3, 0.3, 0.3), wood, M.Wood, V(0, 1.36, 0)), -- knob
		}
		-- spout, getting thinner towards the tip
		table.insert(parts, B.tube(V(0.7, -0.25, 0), V(1.15, 0.1, 0), 0.4, copper, M.Metal))
		table.insert(parts, B.tube(V(1.1, 0.05, 0), V(1.4, 0.5, 0), 0.32, copper, M.Metal))
		table.insert(parts, B.tube(V(1.37, 0.45, 0), V(1.58, 0.66, 0), 0.24, copper, M.Metal))
		table.insert(parts, B.tube(V(1.55, 0.63, 0), V(1.63, 0.71, 0), 0.28, brass, M.Metal))
		-- bail handle with a wooden grip
		B.join(parts, B.path({ V(-0.75, 0.55, 0), V(-0.62, 1.58, 0), V(0.45, 1.58, 0), V(0.62, 0.62, 0) }, 0.1, brass, M.Metal))
		table.insert(parts, B.tube(V(-0.42, 1.58, 0), V(0.25, 1.58, 0), 0.24, wood, M.Wood))
		return parts
	end)()),
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
	item("neon_gear", "Neon Gear", "Rare", (function()
		-- A glowing gear: disc, eight clear teeth, a dark hub with a bright axle.
		local glow = rgb(60, 150, 255)
		local parts = {
			part(Cylinder, V(0.5, 2.2, 2.2), glow, M.Neon, nil, UPRIGHT),
			part(Cylinder, V(0.6, 1, 1), rgb(30, 40, 70), M.Metal, nil, UPRIGHT),
			part(Cylinder, V(0.65, 0.35, 0.35), rgb(220, 240, 255), M.Neon, nil, UPRIGHT),
		}
		for i = 0, 7 do
			local angle = i * math.pi / 4
			table.insert(parts, part(Block, V(0.55, 0.5, 0.5), glow, M.Neon,
				V(math.cos(angle) * 1.3, 0, math.sin(angle) * 1.3), V(0, -math.deg(angle), 0)))
		end
		return parts
	end)()),
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
	withBehavior("Ability.PlasmaToast", item("plasma_toaster", "Plasma Toaster", "Epic", {
		part(Block, V(2.2, 1.4, 1.4), rgb(120, 70, 200), M.Metal),
		part(Block, V(1.6, 0.12, 0.35), rgb(220, 120, 255), M.Neon, V(0, 0.72, -0.25)),
		part(Block, V(1.6, 0.12, 0.35), rgb(220, 120, 255), M.Neon, V(0, 0.72, 0.25)),
		part(Block, V(0.35, 0.3, 0.35), rgb(255, 255, 255), M.Neon, V(0.75, 0.3, -0.72)),
	})),
	withBehavior("Deploy.CrystalSnowman", item("crystal_snowman", "Crystal Snowman", "Epic", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(200, 170, 255), M.Glass),
		part(Ball, V(1.3, 1.3, 1.3), rgb(200, 170, 255), M.Glass, V(0, 1.35, 0)),
		part(Ball, V(0.9, 0.9, 0.9), rgb(220, 200, 255), M.Glass, V(0, 2.3, 0)),
		part(Block, V(0.15, 0.15, 0.5), rgb(255, 140, 40), M.Neon, V(0, 2.3, -0.6)),
		part(Cylinder, V(0.6, 0.7, 0.7), rgb(140, 70, 220), M.Neon, V(0, 2.85, 0), UPRIGHT),
	})),
	item("jet_sled", "Jet Sled", "Epic", {
		part(Block, V(1.6, 0.4, 3), rgb(150, 80, 230), M.SmoothPlastic),
		part(Block, V(0.2, 0.2, 3.2), rgb(220, 230, 240), M.Metal, V(-0.6, -0.35, 0)),
		part(Block, V(0.2, 0.2, 3.2), rgb(220, 230, 240), M.Metal, V(0.6, -0.35, 0)),
		part(Cylinder, V(1, 0.7, 0.7), rgb(60, 60, 80), M.Metal, V(0, 0.5, 1.2), V(0, 90, 0)),
		part(Cylinder, V(0.2, 0.55, 0.55), rgb(255, 140, 40), M.Neon, V(0, 0.5, 1.75), V(0, 90, 0)),
	}),

	-- Legendary
	withBehavior("Ability.GoldenWrench", item("golden_wrench", "Golden Wrench", "Legendary", {
		part(Block, V(0.4, 0.3, 2.8), rgb(255, 200, 40), M.Metal),
		part(Block, V(1.2, 0.3, 0.6), rgb(255, 200, 40), M.Metal, V(0, 0, -1.6)),
		part(Block, V(0.35, 0.3, 0.7), rgb(255, 200, 40), M.Metal, V(-0.42, 0, -2.1)),
		part(Block, V(0.35, 0.3, 0.7), rgb(255, 200, 40), M.Metal, V(0.42, 0, -2.1)),
		part(Ball, V(0.35, 0.35, 0.35), rgb(255, 255, 200), M.Neon, V(0, 0.2, 0.9)),
	})),
	item("aurora_orb", "Aurora Orb", "Legendary", {
		part(Ball, V(1.8, 1.8, 1.8), rgb(120, 255, 200), M.Neon),
		part(Cylinder, V(0.15, 2.4, 2.4), rgb(255, 210, 60), M.Metal, nil, V(0, 0, 90)),
		part(Cylinder, V(0.15, 2.4, 2.4), rgb(255, 210, 60), M.Metal, nil, V(0, 90, 0)),
		part(Cylinder, V(0.4, 1.2, 1.2), rgb(60, 50, 80), M.Metal, V(0, -1.1, 0), UPRIGHT),
	}),
	item("frozen_crown", "Frozen Crown", "Legendary", (function()
		-- A gold crown (worn on the head: the origin is the middle of the band): velvet inside,
		-- rims, eight spikes with icy tips (the tall ones glow) and diamond gems around.
		local gold, goldLight = rgb(255, 205, 50), rgb(255, 228, 120)
		local parts = {
			part(Cylinder, V(0.55, 2, 2), gold, M.Metal, nil, UPRIGHT), -- band (root)
			part(Cylinder, V(0.56, 1.76, 1.76), rgb(40, 52, 130), M.Fabric, nil, UPRIGHT), -- velvet inside
			part(Cylinder, V(0.1, 2.12, 2.12), goldLight, M.Metal, V(0, 0.27, 0), UPRIGHT),
			part(Cylinder, V(0.1, 2.12, 2.12), goldLight, M.Metal, V(0, -0.27, 0), UPRIGHT),
		}
		for i = 0, 7 do
			local a = i * math.pi / 4
			local tall = i % 2 == 0
			local h = if tall then 0.8 else 0.5
			local base = CFrame.new(math.cos(a) * 0.95, 0.27, math.sin(a) * 0.95) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-8))
			table.insert(parts, B.at(Block, V(0.14, h, 0.32), gold, M.Metal, base * CFrame.new(0, h / 2, 0)))
			table.insert(parts, B.at(Block, V(0.2, 0.2, 0.2), if tall then rgb(150, 235, 255) else rgb(200, 240, 255),
				if tall then M.Neon else M.Ice, base * CFrame.new(0, h + 0.05, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))))
		end
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			table.insert(parts, B.at(Block, V(0.08, 0.26, 0.26), if i % 2 == 0 then rgb(120, 220, 255) else rgb(90, 120, 255),
				M.Neon, CFrame.new(math.cos(a) * 1.04, 0, math.sin(a) * 1.04) * CFrame.Angles(0, -a, 0) * CFrame.Angles(math.rad(45), 0, 0)))
		end
		return parts
	end)()),

	-- Mythic
	withBehavior("Ability.Starfall", item("starforged_core", "Starforged Core", "Mythic", {
		part(Ball, V(1.6, 1.6, 1.6), rgb(255, 90, 180), M.Neon),
		part(Block, V(2.4, 0.3, 0.3), rgb(255, 230, 120), M.Neon, nil, V(0, 0, 45)),
		part(Block, V(2.4, 0.3, 0.3), rgb(255, 230, 120), M.Neon, nil, V(0, 0, -45)),
		part(Block, V(0.3, 0.3, 2.4), rgb(120, 230, 255), M.Neon, nil, V(45, 0, 0)),
		part(Cylinder, V(0.15, 2.6, 2.6), rgb(40, 30, 70), M.Metal, nil, V(0, 0, 90)),
	})),
	withBehavior("Ability.DragonCall", item("dragon_egg", "Polar Dragon Egg", "Mythic", (function()
		-- A tall see-through ice egg with a glowing heart, scale spots, glowing cracks, in a nest
		-- of ice shards.
		local shell, spot, crack, ice = rgb(140, 225, 255), rgb(150, 110, 255), rgb(170, 245, 255), rgb(200, 238, 255)
		local parts = {
			B.clear(part(Ball, V(1.8, 1.8, 1.8), shell, M.Glass), 0.35), -- shell (root)
			B.clear(part(Ball, V(1.45, 1.45, 1.45), shell, M.Glass, V(0, 0.6, 0)), 0.35),
			B.clear(part(Ball, V(0.95, 0.95, 0.95), shell, M.Glass, V(0, 1.12, 0)), 0.35),
			part(Ball, V(1.0, 1.0, 1.0), rgb(255, 80, 170), M.Neon, V(0, 0.15, 0)), -- heart
			part(Ball, V(0.65, 0.65, 0.65), rgb(255, 140, 210), M.Neon, V(0, 0.7, 0)),
			part(Cylinder, V(0.35, 1.9, 1.9), rgb(60, 50, 90), M.Slate, V(0, -0.9, 0), UPRIGHT), -- nest
		}
		for _, s in { { 0.4, 0.1 }, { 1.6, 0.4 }, { 2.9, -0.2 }, { 4.1, 0.7 }, { 5.3, 0.15 }, { 0.9, 1.05 } } do
			local a, y = s[1], s[2]
			local center = if y > 0.5 then V(0, 0.6, 0) else Vector3.zero
			local r = if y > 0.5 then 0.7 else 0.88
			local dy = y - center.Y
			local flat = math.sqrt(math.max(r * r - dy * dy, 0))
			table.insert(parts, part(Ball, V(0.28, 0.28, 0.28), spot, M.SmoothPlastic, center + V(math.cos(a) * flat, dy, math.sin(a) * flat)))
		end
		B.join(parts, B.path({ V(-0.1, 0.95, -0.62), V(0.08, 0.62, -0.71), V(-0.1, 0.3, -0.83), V(0.1, 0.02, -0.88) }, 0.06, crack, M.Neon))
		for i = 0, 5 do
			local a = i * math.pi / 3 + 0.3
			table.insert(parts, B.at(Block, V(0.22, 0.6, 0.22), ice, M.Ice, CFrame.new(math.cos(a) * 0.85, -0.62, math.sin(a) * 0.85)
				* CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-25))))
		end
		return parts
	end)())),
	withBehavior("Ability.Comet", item("comet_shard", "Comet Shard", "Mythic", {
		part(Block, V(0.9, 2.6, 0.9), rgb(255, 120, 220), M.Neon, nil, V(0, 45, 15)),
		part(Block, V(0.6, 1.6, 0.6), rgb(140, 230, 255), M.Neon, V(0.7, -0.3, 0.2), V(0, 20, -25)),
		part(Block, V(0.5, 1.2, 0.5), rgb(255, 230, 120), M.Neon, V(-0.6, -0.5, -0.2), V(10, 0, 30)),
		part(Cylinder, V(0.4, 1.8, 1.8), rgb(50, 40, 80), M.Slate, V(0, -1.3, 0), UPRIGHT),
	})),
}
