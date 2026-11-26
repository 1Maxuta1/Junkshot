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


return {
	material("metal_sheet", "Metal Sheet", "Common", 9, {
		part(Block, V(2.4, 0.2, 1.8), rgb(150, 170, 196), M.Metal),
		part(Block, V(2.4, 0.6, 0.2), rgb(130, 150, 176), M.Metal, V(0, 0.2, 0.85), V(-30, 0, 0)),
	}),
	material("bolt_pack", "Bolt Pack", "Common", 9, (function()
		-- An open cardboard box full of bolts: flaps folded out, a label, bolts and nuts on top.
		local card, cardDark, steel, steelDark = rgb(196, 150, 96), rgb(170, 126, 78), rgb(196, 202, 212), rgb(120, 126, 138)
		local parts = {
			part(Block, V(1.28, 0.55, 0.88), steelDark, M.DiamondPlate, V(0, -0.1, 0)), -- the heap of bolts (root)
			part(Block, V(1.4, 0.08, 1), card, M.Cardboard, V(0, -0.4, 0)),
			part(Block, V(1.4, 0.8, 0.06), card, M.Cardboard, V(0, 0, -0.47)),
			part(Block, V(1.4, 0.8, 0.06), card, M.Cardboard, V(0, 0, 0.47)),
			part(Block, V(0.06, 0.8, 0.88), card, M.Cardboard, V(-0.67, 0, 0)),
			part(Block, V(0.06, 0.8, 0.88), card, M.Cardboard, V(0.67, 0, 0)),
			B.at(Block, V(1.38, 0.04, 0.44), cardDark, M.Cardboard, CFrame.new(0, 0.4, -0.5) * CFrame.Angles(math.rad(25), 0, 0) * CFrame.new(0, 0, -0.22)),
			B.at(Block, V(1.38, 0.04, 0.44), cardDark, M.Cardboard, CFrame.new(0, 0.4, 0.5) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, 0.22)),
			B.at(Block, V(0.44, 0.04, 0.98), cardDark, M.Cardboard, CFrame.new(0.7, 0.4, 0) * CFrame.Angles(0, 0, math.rad(25)) * CFrame.new(0.22, 0, 0)),
			B.at(Block, V(0.44, 0.04, 0.98), cardDark, M.Cardboard, CFrame.new(-0.7, 0.4, 0) * CFrame.Angles(0, 0, math.rad(-25)) * CFrame.new(-0.22, 0, 0)),
			part(Block, V(0.8, 0.4, 0.02), rgb(244, 240, 228), M.SmoothPlastic, V(0, -0.02, -0.505)), -- label
			part(Block, V(0.22, 0.22, 0.025), rgb(220, 60, 50), M.SmoothPlastic, V(-0.22, -0.02, -0.51), V(0, 0, 45)),
			part(Block, V(0.36, 0.05, 0.025), rgb(60, 60, 70), M.SmoothPlastic, V(0.14, 0.04, -0.51)),
			part(Block, V(0.36, 0.05, 0.025), rgb(60, 60, 70), M.SmoothPlastic, V(0.14, -0.08, -0.51)),
		}
		-- Bolts: a threaded shank and a hex head (two crossed blocks), tilted every way.
		local bolts = {
			{ V(-0.35, 0.3, -0.15), 20, -15 }, { V(0.05, 0.32, 0.18), -18, 10 }, { V(0.38, 0.28, -0.12), 8, 30 },
			{ V(-0.1, 0.25, -0.25), -35, -5 }, { V(0.3, 0.3, 0.25), 25, -25 }, { V(-0.4, 0.27, 0.22), -10, 35 },
		}
		for _, bolt in bolts do
			local cf = CFrame.new(bolt[1]) * CFrame.Angles(math.rad(bolt[2]), 0, math.rad(bolt[3]))
			table.insert(parts, B.at(Cylinder, V(0.55, 0.12, 0.12), steel, M.Metal, cf * CFrame.Angles(0, 0, math.pi / 2)))
			table.insert(parts, B.at(Cylinder, V(0.1, 0.25, 0.25), steel, M.Metal, cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)))
		end
		for _, nut in { V(-0.15, 0.2, 0.32), V(0.45, 0.2, 0.05), V(-0.45, 0.2, -0.3) } do
			table.insert(parts, part(Cylinder, V(0.1, 0.26, 0.26), steelDark, M.Metal, nut, V(0, 30, 90)))
		end
		return parts
	end)()),
	material("copper_wire", "Copper Wire", "Uncommon", 6, (function()
		-- A wooden cable spool: copper winding with ridges, flanges with holes, a loose wire end.
		local copper, copperDark, wood, hole = rgb(214, 120, 60), rgb(176, 92, 44), rgb(150, 104, 62), rgb(40, 30, 26)
		local parts = {
			part(Cylinder, V(0.95, 1.45, 1.45), copper, M.Metal), -- winding (root)
			part(Cylinder, V(0.14, 2, 2), wood, M.Wood, V(-0.55, 0, 0)),
			part(Cylinder, V(0.14, 2, 2), wood, M.Wood, V(0.55, 0, 0)),
			part(Cylinder, V(1.3, 0.42, 0.42), hole, M.Wood), -- axle hole
		}
		for i = 0, 5 do -- ridges of the winding
			table.insert(parts, part(Cylinder, V(0.05, 1.5, 1.5), copperDark, M.Metal, V(-0.4 + i * 0.16, 0, 0)))
		end
		for _, x in { -0.55, 0.55 } do
			for i = 0, 3 do
				local a = math.pi / 4 + i * math.pi / 2
				table.insert(parts, part(Cylinder, V(0.16, 0.24, 0.24), hole, M.Wood, V(x, math.cos(a) * 0.72, math.sin(a) * 0.72)))
			end
		end
		B.join(parts, B.path({ V(0.15, 0.72, -0.1), V(0.3, 0.98, -0.45), V(0.15, 1.02, -0.95), V(0.35, 0.72, -1.3), V(0.3, 0.45, -1.4) }, 0.08, copper, M.Metal))
		table.insert(parts, part(Block, V(0.3, 0.2, 0.02), rgb(244, 236, 210), M.SmoothPlastic, V(0.63, 0.4, -0.4), V(0, 90, 0))) -- tag
		return parts
	end)()),
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
	material("crystal_shard", "Crystal Shard", "Epic", 3, (function()
		-- A cluster of six-sided crystals with pointed tips and glowing cores, grown on a rock.
		local parts = {}
		local function crystal(cf: CFrame, d: number, h: number, color: Color3, core: Color3?)
			for i = 0, 2 do -- three crossed slabs make a hexagonal prism
				table.insert(parts, B.clear(B.at(Block, V(d, h, d / math.sqrt(3)), color, M.Glass, cf * CFrame.Angles(0, i * math.pi / 3, 0)), 0.3))
			end
			-- tip: a cube standing on its corner
			table.insert(parts, B.at(Block, V(d * 0.62, d * 0.62, d * 0.62), color, M.Glass,
				cf * CFrame.new(0, h / 2, 0) * CFrame.fromAxisAngle(Vector3.new(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))))
			if core ~= nil then
				table.insert(parts, B.at(Block, V(d * 0.36, h * 0.8, d * 0.36), core, M.Neon, cf))
			end
		end
		crystal(CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(8)), 0.75, 2, rgb(160, 110, 255), rgb(225, 180, 255))
		crystal(CFrame.new(0.55, -0.35, 0.15) * CFrame.Angles(math.rad(10), 0, math.rad(-28)), 0.45, 1.2, rgb(120, 220, 255), rgb(200, 245, 255))
		crystal(CFrame.new(-0.5, -0.4, -0.15) * CFrame.Angles(math.rad(-12), 0, math.rad(30)), 0.4, 1, rgb(200, 150, 255), rgb(240, 210, 255))
		crystal(CFrame.new(0.1, -0.55, -0.5) * CFrame.Angles(math.rad(-35), 0, 0), 0.3, 0.6, rgb(150, 190, 255))
		table.insert(parts, part(Ball, V(1.3, 1.3, 1.3), rgb(78, 74, 92), M.Slate, V(0, -1.2, 0)))
		table.insert(parts, part(Ball, V(0.8, 0.8, 0.8), rgb(92, 86, 104), M.Slate, V(0.6, -1.0, 0.3)))
		table.insert(parts, part(Ball, V(0.12, 0.12, 0.12), rgb(255, 255, 255), M.Neon, V(-0.2, 0.7, -0.35)))
		table.insert(parts, part(Ball, V(0.1, 0.1, 0.1), rgb(255, 255, 255), M.Neon, V(0.75, 0, 0)))
		return parts
	end)()),
}
