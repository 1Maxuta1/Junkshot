--!strict
--[[
	UpgradeModels: small pictures of upgrades for UI/UpgradeReveal. Every level looks richer.

	  Build(id, level) -> Model?   WalkSpeed, PickupRange, Haggler, Speed, Storage, Base (level = slots)
]]

local UpgradeModels = {}

local rgb = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material
local B, C, S = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball
local GOLD, STEEL, DARK, SNOW = rgb(255, 200, 60), rgb(190, 200, 216), rgb(40, 46, 66), rgb(248, 251, 255)
local TIER = { rgb(170, 120, 76), rgb(80, 190, 110), rgb(70, 150, 240), rgb(180, 100, 240), rgb(255, 170, 50), rgb(250, 90, 80) }

local function part(model: Model, shape: Enum.PartType, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, rotation: Vector3?): Part
	local p = Instance.new("Part")
	local r = rotation or Vector3.zero
	p.Shape = shape
	p.Size = size
	p.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.Parent = model
	return p
end

local function tier(level: number): Color3
	return TIER[math.clamp(level, 1, #TIER)]
end

local builders: { [string]: (model: Model, level: number) -> () } = {
	WalkSpeed = function(model, level)
		local color = tier(level)
		for _, x in { -0.8, 0.8 } do
			part(model, B, V(1.1, 0.35, 2.5), V(x, 0.17, -0.25), DARK)
			part(model, B, V(1, 0.8, 2.2), V(x, 0.72, -0.3), color)
			part(model, C, V(1.6, 1.05, 1.05), V(x, 1.7, 0.35), color, nil, V(0, 0, 90))
			part(model, C, V(0.45, 1.3, 1.3), V(x, 2.5, 0.35), SNOW, M.Snow, V(0, 0, 90))
			part(model, B, V(1.06, 0.2, 1.1), V(x, 1.3, 0.3), DARK:Lerp(color, 0.3))
			for index = 0, 2 do
				part(model, B, V(0.7, 0.12, 0.16), V(x, 1.18 + index * 0.35, -0.3 + index * 0.06), SNOW)
			end
			if level >= 3 then -- golden toe
				part(model, B, V(1.06, 0.5, 0.5), V(x, 0.6, -1.3), GOLD, M.Metal)
			end
			if level >= 4 then -- wings
				local side = if x > 0 then 1 else -1
				for index = 0, 2 do
					part(model, B, V(0.14, 0.26, 1.3 - index * 0.3), V(x + side * 0.62, 1.5 + index * 0.28, 0.9), SNOW, nil, V(-30, side * 14, 0))
				end
			end
			if level >= 5 then -- rockets
				part(model, C, V(1, 0.4, 0.4), V(x, 1, 1.1), STEEL, M.Metal, V(0, 0, 90))
				part(model, S, V(0.5, 0.5, 0.5), V(x, 0.35, 1.1), rgb(255, 150, 40), M.Neon)
			end
		end
	end,
	PickupRange = function(model, level)
		local color = tier(level)
		local length = 1.6 + level * 0.5
		part(model, B, V(0.9, 1.1, 0.9), V(0, 0, 0), DARK, M.Metal)
		part(model, B, V(0.35, 1, 0.35), V(0, -0.8, 0.2), color, nil, V(20, 0, 0))
		for index = 0, level do -- telescope
			local width = 0.75 - index * 0.1
			part(model, C, V(length / (level + 1) + 0.1, width, width), V(0, 0.2, -0.5 - (index + 0.5) * length / (level + 1)), if index % 2 == 0 then color else STEEL, M.Metal, V(0, 90, 0))
		end
		local tip = -0.5 - length
		part(model, S, V(0.7, 0.7, 0.7), V(0, 0.2, tip - 0.1), DARK, M.Metal)
		for index = 0, level do -- fingers
			local a = index / (level + 1) * math.pi * 2
			local x, y = math.cos(a), math.sin(a)
			part(model, B, V(0.2, 0.2, 0.9), V(x * 0.4, 0.2 + y * 0.4, tip - 0.6), GOLD, M.Metal, V(math.deg(y) * -0.35 * -1, math.deg(x) * -0.35, 0))
			part(model, B, V(0.18, 0.18, 0.6), V(x * 0.42, 0.2 + y * 0.42, tip - 1.2), GOLD, M.Metal)
		end
		if level >= 3 then
			part(model, S, V(0.45, 0.45, 0.45), V(0, 0.75, 0), rgb(90, 250, 255), M.Neon)
		end
		if level >= 4 then
			for _, x in { -0.6, 0.6 } do
				part(model, C, V(1.1, 0.35, 0.35), V(x, 0.1, 0), rgb(255, 90, 80), M.Metal, V(0, 90, 0))
			end
		end
	end,
	Haggler = function(model, level)
		for stack = 1, level + 1 do
			local a = stack * 1.3
			local x, z = math.cos(a) * 1.25, math.sin(a) * 1.25
			for index = 0, 1 + (stack * 2 + level) % 5 do
				part(model, C, V(0.26, 1.2, 1.2), V(x, 0.13 + index * 0.28, z), if index % 2 == 0 then GOLD else rgb(240, 170, 40), M.Metal, V(0, 0, 90))
			end
		end
		-- the dealer's price tag
		part(model, B, V(1.8, 1.2, 0.16), V(0, 2.4, 0), tier(level))
		part(model, B, V(1.6, 1, 0.2), V(0, 2.4, 0), SNOW)
		part(model, C, V(0.24, 0.3, 0.3), V(-0.6, 2.7, 0), DARK, nil, V(0, 90, 0))
		for index = 1, level - 1 do -- an arrow up for every step
			local x = (index - level / 2) * 0.45
			part(model, B, V(0.14, 0.55, 0.24), V(x, 2.3, 0), rgb(60, 190, 100))
			part(model, B, V(0.12, 0.34, 0.24), V(x - 0.1, 2.5, 0), rgb(60, 190, 100), nil, V(0, 0, -45))
			part(model, B, V(0.12, 0.34, 0.24), V(x + 0.1, 2.5, 0), rgb(60, 190, 100), nil, V(0, 0, 45))
		end
		if level >= 4 then
			part(model, B, V(0.6, 0.6, 0.6), V(0, 3.5, 0), rgb(255, 80, 130), M.Neon, V(45, 45, 0))
		end
	end,
	Speed = function(model, level)
		local function gear(x: number, y: number, size: number, color: Color3)
			for index = 0, 3 do
				part(model, B, V(size * 0.24, size, 0.5), V(x, y, 0), color, M.Metal, V(0, 0, index * 45))
			end
			part(model, C, V(0.6, size * 0.76, size * 0.76), V(x, y, 0), color, M.Metal, V(0, 90, 0))
			part(model, C, V(0.7, size * 0.3, size * 0.3), V(x, y, 0), DARK, M.Metal, V(0, 90, 0))
		end
		gear(0, 0, 3, tier(level))
		if level >= 3 then
			gear(2.1, 1.3, 1.8, GOLD)
		end
		if level >= 5 then
			gear(-2, -1.2, 1.6, STEEL)
		end
		-- lightning, one bolt for every step
		for index = 1, level - 1 do
			local x = (index - level / 2) * 0.8
			part(model, B, V(0.26, 1, 0.2), V(x + 0.14, 0.5, 0.6), rgb(255, 235, 90), M.Neon, V(0, 0, -22))
			part(model, B, V(0.6, 0.24, 0.2), V(x, 0.02, 0.6), rgb(255, 235, 90), M.Neon)
			part(model, B, V(0.26, 1, 0.2), V(x - 0.14, -0.45, 0.6), rgb(255, 235, 90), M.Neon, V(0, 0, -22))
		end
	end,
	Storage = function(model, level)
		part(model, B, V(level * 1.7 + 0.5, 0.3, 2.2), V(0, 0, 0), DARK, M.Metal)
		part(model, B, V(level * 1.7 + 0.7, 0.5, 0.2), V(0, 0.15, -1.1), GOLD, M.Metal)
		part(model, B, V(level * 1.7 + 0.7, 0.5, 0.2), V(0, 0.15, 1.1), GOLD, M.Metal)
		for index = 1, level do
			local x = (index - (level + 1) / 2) * 1.7
			part(model, B, V(1.3, 1.3, 1.3), V(x, 0.8, 0), rgb(186, 132, 80), M.WoodPlanks)
			part(model, B, V(1.36, 0.22, 1.36), V(x, 0.8, 0), tier(level))
			part(model, B, V(0.22, 1.36, 1.36), V(x, 0.8, 0), tier(level))
		end
	end,
	Base = function(model, slots)
		part(model, B, V(8, 0.4, 6), V(0, 0, 0), rgb(225, 236, 250))
		for _, z in { -3, 3 } do
			part(model, B, V(8.2, 0.7, 0.25), V(0, 0.15, z), rgb(235, 70, 70))
		end
		for _, x in { -4, 4 } do
			part(model, B, V(0.25, 0.7, 6.2), V(x, 0.15, 0), rgb(235, 70, 70))
		end
		for index = 0, slots - 1 do
			local x, z = -2.6 + (index % 3) * 2.6, if index < 3 then -1.3 else 1.4
			part(model, B, V(2, 0.15, 2), V(x, 0.28, z), GOLD)
			part(model, B, V(1.4, 0.2, 1.4), V(x, 0.3, z), rgb(205, 228, 255))
			part(model, B, V(0.9, 0.9 + index * 0.2, 0.9), V(x, 0.8 + index * 0.1, z), tier(index + 2))
		end
		part(model, C, V(3.4, 0.16, 0.16), V(3.2, 1.8, 1.9), STEEL, M.Metal, V(0, 0, 90))
		part(model, B, V(1.3, 0.8, 0.1), V(2.5, 3, 1.9), rgb(255, 150, 40))
	end,
}

function UpgradeModels.Build(id: string, level: number): Model?
	local builder = builders[id]
	if builder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	builder(model, level)
	return model
end

return UpgradeModels
