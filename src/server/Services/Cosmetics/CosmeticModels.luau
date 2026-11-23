--!strict
--[[
	CosmeticModels: placeholder models of cosmetics, built from Parts (stylised, lightweight,
	no physics: everything is Massless / non-colliding / non-queryable).

	  Backpack / ToolSkin   built around the origin = the attachment point on the character's
	                        back; CosmeticsService welds them to the torso.
	  Companion             pivot = its feet; anchored, animated by every client locally.
]]

local CosmeticModels = {}

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

local B, C, S = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball
local V = Vector3.new
local M = Enum.Material

local builders: { [string]: (model: Model) -> BasePart } = {
	-- Orange scrapper backpack with a snow cap, straps and a little lantern.
	FrostyBackpack = function(model)
		local body = part(model, "Body", B, V(1.7, 1.9, 0.8), V(0, 0, 0.35), rgb(255, 150, 30))
		part(model, "Pocket", B, V(1.3, 0.8, 0.3), V(0, -0.45, 0.85), rgb(214, 110, 20))
		part(model, "Flap", B, V(1.8, 0.45, 0.95), V(0, 0.85, 0.35), rgb(70, 160, 230))
		part(model, "Snow", B, V(1.85, 0.22, 1), V(0, 1.12, 0.35), rgb(250, 252, 255), M.Snow)
		part(model, "Roll", C, V(1.9, 0.55, 0.55), V(0, -1.05, 0.4), rgb(176, 120, 64), M.Fabric)
		part(model, "Lantern", S, V(0.35, 0.35, 0.35), V(0.7, 0.3, 0.85), rgb(255, 214, 130), M.Neon)
		return body
	end,
	-- Icy shovel strapped diagonally across the back.
	FrostbiteShovel = function(model)
		local handle = part(model, "Handle", C, V(3.2, 0.22, 0.22), V(0, 0, 0.95), rgb(200, 230, 255), M.Glass, V(0, 0, 60))
		part(model, "Grip", B, V(0.7, 0.18, 0.18), V(-0.85, -1.45, 0.95), rgb(70, 160, 230), M.SmoothPlastic, V(0, 0, 60))
		part(model, "Blade", B, V(0.9, 1.1, 0.12), V(0.9, 1.5, 0.95), rgb(140, 220, 255), M.Ice, V(0, 0, -30))
		part(model, "Frost", B, V(0.95, 0.2, 0.16), V(0.75, 1.95, 0.95), rgb(250, 252, 255), M.Snow, V(0, 0, -30))
		return handle
	end,
	-- Snowbot: round body, big friendly eye, antenna, snow hat, tiny legs.
	Snowbot = function(model)
		local body = part(model, "Body", S, V(1.8, 1.8, 1.8), V(0, 1.6, 0), rgb(200, 210, 226), M.Metal)
		part(model, "Belly", B, V(1.1, 0.7, 0.2), V(0, 1.3, -0.8), rgb(70, 160, 230))
		part(model, "Visor", C, V(0.2, 1, 1), V(0, 1.9, -0.82), rgb(40, 44, 64), M.SmoothPlastic, V(0, 90, 0))
		part(model, "Eye", S, V(0.45, 0.45, 0.45), V(0, 1.9, -0.92), rgb(120, 230, 255), M.Neon)
		part(model, "Hat", C, V(0.6, 1.6, 1.6), V(0, 2.55, 0), rgb(250, 252, 255), M.Snow, V(0, 0, 90))
		part(model, "Pompom", S, V(0.45, 0.45, 0.45), V(0, 3, 0), rgb(255, 90, 90))
		part(model, "Antenna", C, V(0.7, 0.1, 0.1), V(0.5, 2.9, 0), rgb(200, 206, 214), M.Metal, V(0, 0, 70))
		part(model, "Tip", S, V(0.25, 0.25, 0.25), V(0.62, 3.25, 0), rgb(255, 205, 50), M.Neon)
		for _, x in { -0.45, 0.45 } do
			part(model, "Leg", C, V(0.7, 0.35, 0.35), V(x, 0.45, 0), rgb(90, 94, 104), M.Metal, V(0, 0, 90))
			part(model, "Foot", B, V(0.45, 0.2, 0.6), V(x, 0.1, -0.1), rgb(255, 150, 30))
			part(model, "Arm", C, V(0.6, 0.25, 0.25), V(x * 2.2, 1.5, 0), rgb(200, 210, 226), M.Metal, V(0, 0, if x < 0 then -30 else 30))
		end
		return body
	end,
}

-- Builds a cosmetic model. `anchored` for companions (clients move them), false for things
-- welded to a character.
function CosmeticModels.Build(name: string, anchored: boolean): Model?
	local builder = builders[name]
	if builder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	local primary = builder(model)
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:ToObjectSpace(CFrame.new())
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
	return model
end

return CosmeticModels
