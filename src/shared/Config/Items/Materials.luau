--!strict
--[[
	Materials: purpose-made crafting parts (Category "Material"). They lie in the yard
	(NaturalSpawn) and are also recycling rewards (RecyclePool), so recycling junk is a way to
	get the parts recipes need.
]]

local Types = require(script.Parent.Parent.Parent.Types)
local B = require(script.Parent.Builder)

local Block, Ball, Cylinder, M = B.Block, B.Ball, B.Cylinder, B.M
local UPRIGHT, V, rgb, part = B.UPRIGHT, B.V, B.rgb, B.part

local function material(id: string, displayName: string, rarity: string, spawnWeight: number, parts: { Types.JunkPartSpec }): Types.ItemDefinition
	return {
		Id = id,
		DisplayName = displayName,
		Rarity = rarity,
		Category = "Material",
		Parts = parts,
		NaturalSpawn = true,
		SpawnWeight = spawnWeight,
		RecyclePool = true,
	}
end

local _ = Ball

return {
	material("metal_sheet", "Metal Sheet", "Common", 9, {
		part(Block, V(2.4, 0.2, 1.8), rgb(150, 170, 196), M.Metal),
		part(Block, V(2.4, 0.6, 0.2), rgb(130, 150, 176), M.Metal, V(0, 0.2, 0.85), V(-30, 0, 0)),
	}),
	material("bolt_pack", "Bolt Pack", "Common", 9, {
		part(Block, V(1.4, 0.8, 1), rgb(196, 150, 96), M.Cardboard),
		part(Cylinder, V(0.6, 0.3, 0.3), rgb(190, 196, 206), M.Metal, V(-0.35, 0.65, 0), UPRIGHT),
		part(Cylinder, V(0.6, 0.3, 0.3), rgb(190, 196, 206), M.Metal, V(0.05, 0.65, 0.2), UPRIGHT),
		part(Cylinder, V(0.6, 0.3, 0.3), rgb(190, 196, 206), M.Metal, V(0.4, 0.65, -0.15), UPRIGHT),
	}),
	material("copper_wire", "Copper Wire", "Uncommon", 6, {
		part(Cylinder, V(1, 1.4, 1.4), rgb(214, 120, 60), M.Metal),
		part(Cylinder, V(0.15, 1.9, 1.9), rgb(80, 60, 50), M.Wood, V(-0.55, 0, 0)),
		part(Cylinder, V(0.15, 1.9, 1.9), rgb(80, 60, 50), M.Wood, V(0.55, 0, 0)),
	}),
	material("engine_part", "Engine Part", "Uncommon", 5, {
		part(Cylinder, V(1.4, 1.2, 1.2), rgb(120, 130, 146), M.Metal, nil, UPRIGHT),
		part(Cylinder, V(1.2, 0.35, 0.35), rgb(200, 206, 214), M.Metal, V(0, 1.2, 0), UPRIGHT),
		part(Block, V(1.5, 0.3, 1.5), rgb(60, 66, 80), M.Metal, V(0, -0.75, 0)),
	}),
	material("circuit_board", "Circuit Board", "Rare", 4, {
		part(Block, V(2, 0.15, 1.4), rgb(40, 150, 80), M.SmoothPlastic),
		part(Block, V(0.5, 0.15, 0.5), rgb(30, 30, 36), M.SmoothPlastic, V(-0.5, 0.15, 0.2)),
		part(Block, V(0.4, 0.15, 0.6), rgb(30, 30, 36), M.SmoothPlastic, V(0.45, 0.15, -0.2)),
		part(Block, V(0.2, 0.1, 0.2), rgb(255, 210, 60), M.Neon, V(0.7, 0.12, 0.45)),
	}),
	material("crystal_shard", "Crystal Shard", "Epic", 3, {
		part(Block, V(0.8, 2.2, 0.8), rgb(160, 110, 255), M.Glass, nil, V(0, 45, 10)),
		part(Block, V(0.5, 1.4, 0.5), rgb(120, 220, 255), M.Neon, V(0.55, -0.3, 0.2), V(0, 20, -25)),
		part(Block, V(0.45, 1.1, 0.45), rgb(200, 150, 255), M.Neon, V(-0.5, -0.4, -0.2), V(10, 0, 28)),
	}),
}
