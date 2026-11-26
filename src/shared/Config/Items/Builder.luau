--!strict
--[[
	Builder: small helpers shared by the item data modules (Junk, Materials, Collectibles,
	Crafted). Keeps every definition short and in one format.

	Model conventions (see Util/JunkFactory)
	  - Parts[1] is the Root part; keep it near the middle of the object.
	  - Cylinders are built along X. Rotation UPRIGHT (0, 0, 90) stands them up (Size.X = height).
	  - Rotation is in degrees. -Z is the object's "front".
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Builder = {}

Builder.Block = Enum.PartType.Block
Builder.Ball = Enum.PartType.Ball
Builder.Cylinder = Enum.PartType.Cylinder
Builder.M = Enum.Material
Builder.UPRIGHT = Vector3.new(0, 0, 90)
Builder.V = Vector3.new

function Builder.rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

function Builder.part(
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	offset: Vector3?,
	rotation: Vector3?
): Types.JunkPartSpec
	return {
		Shape = shape,
		Size = size,
		Color = color,
		Material = material,
		Offset = offset or Vector3.zero,
		Rotation = rotation or Vector3.zero,
	}
end

-- Like part(), placed by a whole CFrame (handy for rings of pieces around a center).
function Builder.at(shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material, cframe: CFrame): Types.JunkPartSpec
	local x, y, z = cframe:ToEulerAnglesXYZ()
	return Builder.part(shape, size, color, material, cframe.Position, Vector3.new(math.deg(x), math.deg(y), math.deg(z)))
end

-- A straight bar from a to b (Block, its length along the line).
function Builder.bar(a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material): Types.JunkPartSpec
	return Builder.at(Enum.PartType.Block, Vector3.new(thickness, thickness, (b - a).Magnitude), color, material, CFrame.lookAt((a + b) / 2, b))
end

-- A round rod (Cylinder) from a to b.
function Builder.tube(a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material): Types.JunkPartSpec
	return Builder.at(Enum.PartType.Cylinder, Vector3.new((b - a).Magnitude, diameter, diameter), color, material,
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0))
end

-- A chain of tubes through the points (a bent wire, a handle, a spout).
function Builder.path(points: { Vector3 }, diameter: number, color: Color3, material: Enum.Material): { Types.JunkPartSpec }
	local list = {}
	for index = 1, #points - 1 do
		table.insert(list, Builder.tube(points[index], points[index + 1], diameter, color, material))
	end
	return list
end

-- The same spec, see-through.
function Builder.clear(spec: Types.JunkPartSpec, transparency: number): Types.JunkPartSpec
	spec.Transparency = transparency
	return spec
end

-- Appends every spec of `extra` to `list` and returns `list`.
function Builder.join(list: { Types.JunkPartSpec }, extra: { Types.JunkPartSpec }): { Types.JunkPartSpec }
	for _, spec in extra do
		table.insert(list, spec)
	end
	return list
end

return Builder
