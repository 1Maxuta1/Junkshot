--!strict
--[[
	BaseModels: placeholder models of everything on a base, built from Parts (lightweight: no
	transparency tricks, no particles; one PointLight on the lantern only). Swap a builder for
	a real model later; keep the named parts:
	  Chest:     "Body" (prompt parent)
	  Conveyor:  "Belt" (the moving surface), "Hopper"
	  Stand:     "Plinth" (the shown item sits above it)
	Pivot = center of the footprint on the ground, -Z = front. Everything is Anchored.
]]

local BaseModels = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(model: Model, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?, rotation: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	local r = rotation or Vector3.zero
	p.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local V = Vector3.new
local M = Enum.Material
local CYL = Enum.PartType.Cylinder

local function finish(model: Model, primary: BasePart): Model
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:ToObjectSpace(CFrame.new())
	return model
end

-- Chest, one look per level: crate -> reinforced chest -> metal container -> industrial ->
-- secure unit. Sizes grow so the upgrade is visible from across the plot.
local chestBuilders: { (model: Model) -> BasePart } = {
	function(model)
		local wood = rgb(176, 120, 64)
		local body = part(model, "Body", V(4, 3, 3), V(0, 1.5, 0), wood, M.WoodPlanks)
		for _, x in { -1.6, 1.6 } do
			part(model, "Slat", V(0.3, 3.1, 3.1), V(x, 1.5, 0), rgb(130, 84, 44), M.Wood)
		end
		return body
	end,
	function(model)
		local wood = rgb(186, 110, 52)
		local body = part(model, "Body", V(4.6, 3, 3.2), V(0, 1.5, 0), wood, M.WoodPlanks)
		part(model, "Lid", V(4.7, 1, 3.3), V(0, 3.5, 0), rgb(150, 86, 40), M.Wood)
		for _, x in { -2, 0, 2 } do
			part(model, "Band", V(0.3, 4.1, 3.4), V(x, 2, 0), rgb(90, 94, 104), M.Metal)
		end
		part(model, "Lock", V(0.7, 0.8, 0.3), V(0, 2.8, -1.75), rgb(255, 205, 50), M.Metal)
		return body
	end,
	function(model)
		local steel = rgb(70, 160, 230)
		local body = part(model, "Body", V(6, 3.6, 3.8), V(0, 1.8, 0), steel, M.Metal)
		for index = -2, 2 do
			part(model, "Rib", V(0.25, 3.7, 3.9), V(index * 1.2, 1.8, 0), rgb(50, 120, 190), M.Metal)
		end
		part(model, "Door", V(2.4, 2.8, 0.2), V(0, 1.7, -1.95), rgb(40, 100, 170), M.Metal)
		part(model, "Handle", V(0.3, 1.2, 0.3), V(0.8, 1.8, -2.1), rgb(255, 205, 50), M.Metal)
		return body
	end,
	function(model)
		local paint = rgb(255, 150, 30)
		local body = part(model, "Body", V(7.5, 4.4, 4.4), V(0, 2.2, 0), paint, M.Metal)
		for index = -3, 3 do
			part(model, "Rib", V(0.25, 4.5, 4.5), V(index * 1.1, 2.2, 0), rgb(214, 110, 20), M.Metal)
		end
		part(model, "Stripe", V(7.6, 0.4, 4.5), V(0, 3.9, 0), rgb(40, 44, 64), M.Metal)
		part(model, "DoorL", V(1.8, 3.6, 0.2), V(-1, 2, -2.3), rgb(214, 110, 20), M.Metal)
		part(model, "DoorR", V(1.8, 3.6, 0.2), V(1, 2, -2.3), rgb(214, 110, 20), M.Metal)
		part(model, "Light", V(0.6, 0.6, 0.6), V(3.2, 4.7, -1.8), rgb(255, 210, 60), M.Neon, Enum.PartType.Ball)
		return body
	end,
	function(model)
		local body = part(model, "Body", V(8, 5, 5), V(0, 2.5, 0), rgb(40, 44, 64), M.Metal)
		part(model, "Trim", V(8.2, 0.5, 5.2), V(0, 0.25, 0), rgb(190, 90, 255), M.Neon)
		part(model, "TopTrim", V(8.2, 0.4, 5.2), V(0, 5.1, 0), rgb(190, 90, 255), M.Neon)
		part(model, "Vault", V(3.6, 3.6, 0.3), V(0, 2.5, -2.6), rgb(200, 206, 214), M.Metal)
		part(model, "Wheel", V(0.3, 1.8, 1.8), V(0, 2.5, -2.85), rgb(255, 205, 50), M.Metal, CYL, V(0, 90, 0))
		part(model, "Screen", V(1.4, 0.8, 0.2), V(2.9, 3.8, -2.6), rgb(90, 230, 120), M.Neon)
		return body
	end,
}

function BaseModels.Chest(level: number): Model
	local model = Instance.new("Model")
	model.Name = "Chest"
	local builder = chestBuilders[math.clamp(level, 1, #chestBuilders)]
	return finish(model, builder(model))
end

-- A flat pad marking a building slot (locked pads are grey).
function BaseModels.SlotPad(size: number, unlocked: boolean): Model
	local model = Instance.new("Model")
	model.Name = "SlotPad"
	local pad = part(model, "Pad", V(size, 0.12, size), V(0, 0.06, 0), if unlocked then rgb(255, 210, 60) else rgb(150, 160, 180), M.SmoothPlastic)
	pad.CanCollide = false
	pad.CastShadow = false
	local inner = part(model, "Inner", V(size - 2.2, 0.14, size - 2.2), V(0, 0.07, 0), if unlocked then rgb(205, 228, 255) else rgb(226, 230, 238), M.SmoothPlastic)
	inner.CanCollide = false
	inner.CastShadow = false
	local marker = part(model, "Marker", V(1, 1, 1), V(0, 2.5, 0), rgb(255, 255, 255))
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	return finish(model, pad)
end

local buildingBuilders: { [string]: (model: Model) -> BasePart } = {
	Conveyor = function(model)
		local frame = part(model, "Frame", V(3.8, 1, 8.4), V(0, 0.5, -0.6), rgb(70, 80, 96), M.Metal)
		local belt = part(model, "Belt", V(3.4, 0.2, 8), V(0, 1.1, -0.6), rgb(40, 42, 50), M.Fabric)
		belt.Name = "Belt"
		for index = 0, 7 do
			part(model, "Chevron", V(2.4, 0.05, 0.3), V(0, 1.22, -4.2 + index), rgb(255, 205, 50), M.SmoothPlastic)
		end
		part(model, "RailL", V(0.3, 0.6, 8.4), V(-1.9, 1.3, -0.6), rgb(255, 150, 30), M.Metal)
		part(model, "RailR", V(0.3, 0.6, 8.4), V(1.9, 1.3, -0.6), rgb(255, 150, 30), M.Metal)
		local hopper = part(model, "Hopper", V(4, 2.6, 2), V(0, 1.3, 3.8), rgb(70, 160, 230), M.Metal)
		part(model, "HopperMouth", V(3.4, 0.3, 1.6), V(0, 2.65, 3.6), rgb(30, 34, 44), M.Metal)
		return frame
	end,
	StorageRack = function(model)
		local base = part(model, "Base", V(7, 0.4, 3), V(0, 0.2, 0), rgb(130, 84, 44), M.Wood)
		for _, x in { -3.3, 3.3 } do
			part(model, "Post", V(0.4, 6, 0.4), V(x, 3, 1.2), rgb(90, 94, 104), M.Metal)
			part(model, "Post", V(0.4, 6, 0.4), V(x, 3, -1.2), rgb(90, 94, 104), M.Metal)
		end
		for index, y in { 1.6, 3.4, 5.2 } do
			part(model, `Shelf{index}`, V(7, 0.25, 3), V(0, y, 0), rgb(176, 120, 64), M.WoodPlanks)
			for box = -2, 2, 2 do
				part(model, "Box", V(1.4, 1, 1.4), V(box + (index % 2) * 0.4, y + 0.62, 0), if (box + index) % 4 == 0 then rgb(255, 150, 30) else rgb(70, 160, 230), M.SmoothPlastic)
			end
		end
		return base
	end,
	DisplayStand = function(model)
		local base = part(model, "Base", V(3.4, 0.5, 3.4), V(0, 0.25, 0), rgb(40, 44, 64), M.Metal)
		local plinth = part(model, "Plinth", V(2.4, 2.4, 2.4), V(0, 1.7, 0), rgb(255, 255, 255), M.Marble)
		plinth.Name = "Plinth"
		part(model, "Top", V(2.8, 0.3, 2.8), V(0, 3.05, 0), rgb(255, 205, 50), M.Metal)
		return base
	end,
	Lantern = function(model)
		local base = part(model, "Base", V(1.6, 0.4, 1.6), V(0, 0.2, 0), rgb(40, 44, 64), M.Metal)
		part(model, "Pole", V(6, 0.4, 0.4), V(0, 3.2, 0), rgb(40, 44, 64), M.Metal, CYL, V(0, 0, 90))
		local lamp = part(model, "Lamp", V(1.4, 1.6, 1.4), V(0, 6.6, 0), rgb(255, 214, 130), M.Neon)
		part(model, "Cap", V(1.8, 0.4, 1.8), V(0, 7.6, 0), rgb(40, 44, 64), M.Metal)
		part(model, "Snow", V(1.9, 0.25, 1.9), V(0, 7.9, 0), rgb(250, 252, 255), M.Snow)
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 214, 150)
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lamp
		return base
	end,
}

function BaseModels.Building(modelName: string): Model
	local builder = buildingBuilders[modelName]
	assert(builder ~= nil, `[BaseModels] unknown building model "{modelName}"`)
	local model = Instance.new("Model")
	model.Name = modelName
	return finish(model, builder(model))
end

-- A flag pole whose banners grow with the base level (base expansion made visible).
function BaseModels.Flag(level: number): Model
	local model = Instance.new("Model")
	model.Name = "BaseFlag"
	local base = part(model, "Base", V(1.6, 0.4, 1.6), V(0, 0.2, 0), rgb(40, 44, 64), M.Metal)
	part(model, "Pole", V(10, 0.35, 0.35), V(0, 5, 0), rgb(200, 206, 214), M.Metal, CYL, V(0, 0, 90))
	local colors = { rgb(255, 150, 30), rgb(70, 160, 230), rgb(190, 90, 255) }
	for index = 1, math.clamp(level, 1, #colors) do
		part(model, `Banner{index}`, V(0.15, 1.4, 2.6), V(0, 9.4 - (index - 1) * 1.7, 1.4), colors[index], M.Fabric)
	end
	return finish(model, base)
end

return BaseModels
