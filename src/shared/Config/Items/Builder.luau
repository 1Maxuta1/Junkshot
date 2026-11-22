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

return Builder
