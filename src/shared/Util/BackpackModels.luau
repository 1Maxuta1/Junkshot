--!strict
--[[
	BackpackModels: the backpack that comes with every level of the Bigger Backpack upgrade
	(level 1 = none). Looks only: the capacity is Config/PlayerUpgrades.

	  Build(level)  model around the origin = the middle of a torso, +Z behind it; parts are
	                massless, do not collide and are not anchored. PrimaryPart = the body.
	  Names[level]  shown when the pack is new
	Attributes for BackpackController: Spin (turns around the Core), Pulse (neon / light pulse).
]]

local BackpackModels = {}

BackpackModels.Names = { "", "SCRAP SATCHEL", "EXPLORER PACK", "STARFORGE REACTOR PACK" }
BackpackModels.Colors = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 170, 70),
	Color3.fromRGB(90, 180, 255),
	Color3.fromRGB(90, 255, 240),
}

local rgb = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material
local B, C, S = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball

local function part(model: Model, name: string, shape: Enum.PartType, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, rotation: Vector3?): Part
	local p = Instance.new("Part")
	local r = rotation or Vector3.zero
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function straps(model: Model, color: Color3, buckle: Color3)
	for _, x in { -0.62, 0.62 } do
		part(model, "Strap", B, V(0.24, 1.5, 0.08), V(x, 0.05, -0.56), color, M.Fabric)
		part(model, "StrapTop", B, V(0.24, 0.08, 1.2), V(x, 0.83, 0), color, M.Fabric)
		part(model, "Buckle", B, V(0.3, 0.16, 0.1), V(x, -0.2, -0.58), buckle, M.Metal)
	end
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local builders: { [number]: (model: Model) -> BasePart } = {
	-- Patched leather satchel with a rolled top.
	[2] = function(model)
		local leather, dark, brass = rgb(150, 92, 48), rgb(98, 58, 32), rgb(232, 180, 70)
		local body = part(model, "Body", B, V(1.5, 1.4, 0.6), V(0, -0.1, 0.85), leather, M.Leather)
		part(model, "Bottom", C, V(1.56, 0.64, 0.64), V(0, -0.8, 0.85), dark, M.Leather)
		part(model, "Roll", C, V(1.6, 0.66, 0.66), V(0, 0.62, 0.85), dark, M.Leather)
		part(model, "Flap", B, V(1.36, 0.8, 0.1), V(0, 0.28, 1.2), rgb(176, 112, 60), M.Leather)
		for _, x in { -0.4, 0.4 } do
			part(model, "Belt", B, V(0.18, 1.3, 0.08), V(x, 0, 1.25), dark, M.Leather)
			part(model, "BeltBuckle", B, V(0.28, 0.24, 0.1), V(x, -0.14, 1.28), brass, M.Metal)
		end
		part(model, "Patch", B, V(0.46, 0.4, 0.05), V(0, -0.5, 1.17), rgb(70, 130, 200), M.Fabric, V(0, 0, 8))
		for _, x in { -0.82, 0.82 } do
			part(model, "Bolt", C, V(0.12, 0.3, 0.3), V(x, 0.62, 0.85), brass, M.Metal)
		end
		straps(model, dark, brass)
		return body
	end,
	-- Expedition pack: frame, side pockets, bedroll and a warm lantern.
	[3] = function(model)
		local blue, navy, orange, steel = rgb(46, 118, 206), rgb(26, 50, 96), rgb(255, 150, 40), rgb(190, 198, 212)
		local body = part(model, "Body", B, V(1.7, 1.7, 0.8), V(0, 0, 0.95), blue, M.Fabric)
		part(model, "Lid", B, V(1.8, 0.4, 0.95), V(0, 0.92, 0.97), navy, M.Fabric)
		part(model, "LidTrim", B, V(1.84, 0.1, 0.99), V(0, 0.74, 0.97), orange, M.Fabric)
		part(model, "Pocket", B, V(1.15, 0.8, 0.3), V(0, -0.35, 1.45), navy, M.Fabric)
		part(model, "PocketZip", B, V(1.0, 0.08, 0.06), V(0, -0.05, 1.61), orange, M.Neon)
		part(model, "Gear", C, V(0.06, 0.5, 0.5), V(0, -0.42, 1.61), steel, M.Metal, V(0, 90, 0))
		part(model, "GearHub", C, V(0.08, 0.2, 0.2), V(0, -0.42, 1.62), navy, M.Metal, V(0, 90, 0))
		for _, x in { -1, 1 } do
			part(model, "Side", C, V(1.1, 0.5, 0.5), V(x, -0.25, 0.95), navy, M.Fabric, V(0, 0, 90))
			part(model, "SideCap", C, V(0.14, 0.54, 0.54), V(x, 0.34, 0.95), orange, M.SmoothPlastic, V(0, 0, 90))
			part(model, "Pole", C, V(2.1, 0.12, 0.12), V(x * 0.76, 0.1, 0.5), steel, M.Metal, V(0, 0, 90))
			part(model, "RollBelt", C, V(0.16, 0.66, 0.66), V(x * 0.5, -1.12, 0.98), orange, M.Fabric)
		end
		part(model, "Bedroll", C, V(1.9, 0.6, 0.6), V(0, -1.12, 0.98), rgb(226, 214, 180), M.Fabric)
		part(model, "LanternTop", C, V(0.12, 0.34, 0.34), V(1.0, 0.78, 1.3), steel, M.Metal, V(0, 0, 90))
		local lantern = part(model, "Lantern", C, V(0.36, 0.28, 0.28), V(1.0, 0.54, 1.3), rgb(255, 214, 120), M.Neon, V(0, 0, 90))
		lantern:SetAttribute("Pulse", true)
		light(lantern, rgb(255, 200, 110), 9, 0.9)
		straps(model, navy, orange)
		return body
	end,
	-- Reactor: white and gold armour, a turning ring around a glowing core, wings, two thrusters.
	[4] = function(model)
		local white, dark, gold, cyan = rgb(238, 242, 250), rgb(34, 38, 58), rgb(255, 196, 60), rgb(80, 250, 255)
		local body = part(model, "Body", B, V(1.5, 1.8, 0.7), V(0, 0, 0.9), dark, M.Metal)
		part(model, "PlateTop", B, V(1.7, 0.5, 0.85), V(0, 0.78, 0.95), white)
		part(model, "PlateTrim", B, V(1.74, 0.09, 0.89), V(0, 0.55, 0.95), gold, M.Metal)
		part(model, "PlateLow", B, V(1.3, 0.5, 0.85), V(0, -0.8, 0.95), white)
		part(model, "PlateLowTrim", B, V(1.34, 0.09, 0.89), V(0, -0.58, 0.95), gold, M.Metal)
		part(model, "CoreBack", C, V(0.16, 1.1, 1.1), V(0, 0, 1.3), dark, M.Metal, V(0, 90, 0))
		local core = part(model, "Core", S, V(0.62, 0.62, 0.62), V(0, 0, 1.38), cyan, M.Neon)
		core:SetAttribute("Pulse", true)
		light(core, cyan, 6, 0.6)
		for index = 0, 5 do -- the ring: six blocks, all turning around the core
			local tooth = part(model, "Ring", B, V(0.36, 0.16, 0.2), Vector3.zero, gold, M.Metal)
			tooth.CFrame = CFrame.new(0, 0, 1.42) * CFrame.Angles(0, 0, math.rad(index * 60)) * CFrame.new(0, 0.48, 0)
			tooth:SetAttribute("Spin", true)
		end
		for _, x in { -1, 1 } do
			part(model, "Tank", C, V(1.3, 0.5, 0.5), V(x * 0.98, 0.05, 0.95), white, M.SmoothPlastic, V(0, 0, 90))
			part(model, "TankBand", C, V(0.12, 0.54, 0.54), V(x * 0.98, 0.35, 0.95), gold, M.Metal, V(0, 0, 90))
			part(model, "TankGlow", C, V(0.14, 0.53, 0.53), V(x * 0.98, -0.05, 0.95), cyan, M.Neon, V(0, 0, 90))
			part(model, "TankCap", S, V(0.5, 0.5, 0.5), V(x * 0.98, 0.7, 0.95), gold, M.Metal)
			local nozzle = part(model, "Nozzle", C, V(0.36, 0.58, 0.58), V(x * 0.98, -0.78, 0.95), dark, M.Metal, V(0, 0, 90))
			local flame = Instance.new("ParticleEmitter")
			flame.Name = "Flame"
			flame.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			flame.Color = ColorSequence.new(rgb(220, 255, 255), cyan)
			flame.LightEmission = 1
			flame.Size = NumberSequence.new(0.42, 0)
			flame.Transparency = NumberSequence.new(0.2, 1)
			flame.Lifetime = NumberRange.new(0.2, 0.4)
			flame.Speed = NumberRange.new(3, 5)
			flame.SpreadAngle = Vector2.new(8, 8)
			flame.Rate = 7
			flame.EmissionDirection = Enum.NormalId.Left -- the cylinder's axis, down
			flame.Parent = nozzle
			part(model, "Wing", B, V(1.15, 0.26, 0.1), V(x * 1.5, 0.72, 1.2), white, M.SmoothPlastic, V(0, x * -14, x * 32))
			part(model, "WingEdge", B, V(1.15, 0.07, 0.12), V(x * 1.46, 0.87, 1.2), cyan, M.Neon, V(0, x * -14, x * 32))
			part(model, "WingLow", B, V(0.8, 0.2, 0.1), V(x * 1.42, 0.22, 1.2), gold, M.Metal, V(0, x * -14, x * 12))
		end
		straps(model, dark, gold)
		return body
	end,
}

function BackpackModels.Build(level: number): Model?
	local builder = builders[math.min(level, #BackpackModels.Names)]
	if builder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "UpgradeBackpack"
	model:SetAttribute("Level", level)
	local primary = builder(model)
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:ToObjectSpace(CFrame.new())
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= primary then
			if p:GetAttribute("Spin") ~= nil then
				local weld = Instance.new("Weld") -- moved by BackpackController
				weld.Part0 = primary
				weld.Part1 = p
				weld.C0 = primary.CFrame:ToObjectSpace(p.CFrame)
				weld.Parent = p
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	return model
end

return BackpackModels
