--!strict
--[[
	CreatureModels: placeholder world-event creatures built from Parts (stylised, lightweight).

	Every creature model:
	  - pivot = its feet; PrimaryPart "Root" (invisible) carries the prompt and the billboard
	  - anchored, non-colliding, non-queryable, no shadows from small parts: no physics at all
	  - a "Loot" part (the rare item it carries) that glows in the reward rarity color
	  - a rarity ring on the ground, a thin light pillar (visible from far away) and a few slow
	    sparkles. Clients add the motion (client/CreatureController); nothing runs per frame here.
]]

local CreatureModels = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(model: Model, name: string, shape: Enum.PartType, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, rotation: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	local r = rotation or Vector3.zero
	p.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local B, C, S = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball
local V = Vector3.new
local M = Enum.Material

-- Builders draw the creature around the origin (feet at y = 0, facing -Z) and return nothing.
local builders: { [string]: (model: Model, glow: Color3) -> () } = {
	-- Scrap Fox: orange fox with a white chest, big bushy tail and a glowing loot gear on its back.
	ScrapFox = function(model, glow)
		local fur, light, dark = rgb(255, 130, 40), rgb(255, 244, 230), rgb(46, 40, 52)
		part(model, "Body", B, V(1.7, 1.5, 3), V(0, 1.75, 0.2), fur)
		part(model, "Chest", B, V(1.3, 1.1, 0.4), V(0, 1.65, -1.35), light)
		part(model, "Head", B, V(1.6, 1.4, 1.4), V(0, 2.75, -1.5), fur)
		part(model, "Cheeks", B, V(1.7, 0.6, 1), V(0, 2.3, -1.65), light)
		part(model, "Snout", B, V(0.7, 0.55, 0.8), V(0, 2.45, -2.45), light)
		part(model, "Nose", B, V(0.32, 0.28, 0.2), V(0, 2.65, -2.86), dark)
		for _, x in { -0.42, 0.42 } do
			part(model, "Eye", B, V(0.24, 0.34, 0.1), V(x, 3, -2.21), dark)
			part(model, "Ear", B, V(0.5, 0.75, 0.25), V(x * 1.25, 3.75, -1.35), fur, nil, V(0, 0, if x < 0 then 12 else -12))
			part(model, "EarInner", B, V(0.28, 0.45, 0.1), V(x * 1.25, 3.7, -1.5), light, nil, V(0, 0, if x < 0 then 12 else -12))
		end
		for _, x in { -0.55, 0.55 } do
			for _, z in { -0.9, 1.2 } do
				part(model, "Leg", B, V(0.45, 1.1, 0.45), V(x, 0.55, z), fur)
				part(model, "Paw", B, V(0.5, 0.25, 0.6), V(x, 0.12, z - 0.05), dark)
			end
		end
		part(model, "Tail", B, V(0.9, 0.9, 2.2), V(0, 2.4, 2.4), fur, nil, V(35, 0, 0))
		part(model, "TailTip", B, V(0.95, 0.95, 0.8), V(0, 3.05, 3.3), light, nil, V(35, 0, 0))
		-- The loot it carries: a glowing gear on a little strap.
		part(model, "Strap", B, V(1.8, 0.2, 0.5), V(0, 2.55, 0.2), rgb(120, 76, 40), M.Fabric)
		local loot = part(model, "Loot", C, V(0.45, 1.5, 1.5), V(0, 3.2, 0.3), glow, M.Neon, V(0, 90, 0))
		for i = 0, 3 do
			part(model, "Tooth", B, V(0.4, 0.4, 1.9), V(0, 3.2, 0.3), glow, M.Neon, V(i * 45, 0, 0))
		end
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(glow)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.35, 0)
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(1, 2.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = loot
	end,
}

-- Builds a creature. `glow` = the reward rarity color. Returns nil for an unknown model name.
function CreatureModels.Build(name: string, glow: Color3): Model?
	local builder = builders[name]
	if builder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name

	local root = part(model, "Root", B, V(3, 4, 4.5), V(0, 2, 0), glow)
	root.Transparency = 1
	builder(model, glow)

	-- Rarity presentation: ground ring + light pillar.
	local ring = part(model, "RarityRing", C, V(0.2, 6.5, 6.5), V(0, 0.12, 0), glow, M.Neon, V(0, 0, 90))
	ring.Transparency = 0.35
	local pillar = part(model, "Pillar", C, V(60, 0.8, 0.8), V(0, 34, 0), glow, M.Neon, V(0, 0, 90))
	pillar.Transparency = 0.6

	model.PrimaryPart = root
	root.PivotOffset = root.CFrame:ToObjectSpace(CFrame.new())
	return model
end

function CreatureModels.Has(name: string): boolean
	return builders[name] ~= nil
end

return CreatureModels
