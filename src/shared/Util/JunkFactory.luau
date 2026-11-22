--!strict
--[[
	JunkFactory: builds the Model of any catalog item (Config/ItemConfig) from its Parts.
	Shared, because the server builds the real world objects and clients build cosmetic copies
	(carried on the back, hotbar and reward previews).

	Modes
	  "World"    anchored, non-colliding, non-queryable. Costs no physics (good for mobile).
	  "Cosmetic" unanchored but massless and non-colliding; meant to be welded to a character.
	             Pass `targetSize` to scale the largest dimension down to that many studs.

	The model has NO PrimaryPart. Its WorldPivot is the junk's origin, so PivotTo() places the
	origin. The first part is named "Root" (use GetRoot). Parts keep their config rotation.
	GetBounds() gives the junk's size/extents relative to its origin, computed from the config
	alone, so the server can stand an object on the ground without building it first.
]]

local ItemConfig = require(script.Parent.Parent.Config.ItemConfig)

local Types = require(script.Parent.Parent.Types)

export type Mode = "World" | "Cosmetic"
export type Bounds = { Min: Vector3, Max: Vector3, Size: Vector3 }

local MIN_PART_SIZE = 0.05
local ROOT_NAME = "Root"

local JunkFactory = {}

local boundsCache: { [string]: Bounds } = {}

local function specCFrame(spec: Types.JunkPartSpec, scale: number): CFrame
	local rotation = spec.Rotation
	return CFrame.new(spec.Offset * scale)
		* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

-- Half-size of the axis-aligned box that contains a rotated box.
local function halfExtents(cframe: CFrame, size: Vector3): Vector3
	local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		0.5 * (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z),
		0.5 * (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z),
		0.5 * (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z)
	)
end

local function partsBounds(cacheKey: string, parts: { Types.JunkPartSpec }): Bounds
	local cached = boundsCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, spec in parts do
		local cframe = specCFrame(spec, 1)
		local half = halfExtents(cframe, spec.Size)
		min = min:Min(cframe.Position - half)
		max = max:Max(cframe.Position + half)
	end
	local bounds: Bounds = { Min = min, Max = max, Size = max - min }
	boundsCache[cacheKey] = bounds
	return bounds
end

-- Extents relative to the item's origin (unscaled). nil for unknown or part-less (debug) items.
function JunkFactory.GetBounds(itemId: string): Bounds?
	local definition = ItemConfig.Get(itemId)
	if definition == nil or definition.Parts == nil then
		return nil
	end
	return partsBounds(itemId, definition.Parts)
end

local buildParts -- forward declaration (defined below)

-- Builds any catalog item (junk, material, collectible, crafted). nil for unknown ids.
function JunkFactory.Build(itemId: string, mode: Mode, targetSize: number?): Model?
	local definition = ItemConfig.Get(itemId)
	local bounds = JunkFactory.GetBounds(itemId)
	if definition == nil or definition.Parts == nil or bounds == nil then
		return nil
	end
	local model = buildParts(itemId, definition.Parts, bounds, mode, targetSize)
	if model ~= nil then
		model:SetAttribute("JunkId", itemId)
	end
	return model
end

function buildParts(name: string, parts: { Types.JunkPartSpec }, bounds: Bounds, mode: Mode, targetSize: number?): Model?
	local scale = 1
	if targetSize ~= nil then
		local largest = math.max(bounds.Size.X, bounds.Size.Y, bounds.Size.Z)
		if largest > 0 then
			scale = targetSize / largest
		end
	end

	local isWorld = mode == "World"
	local model = Instance.new("Model")
	model.Name = name

	local root: BasePart? = nil
	for index, spec in parts do
		local piece = Instance.new("Part")
		piece.Name = if index == 1 then ROOT_NAME else `Part{index}`
		piece.Shape = spec.Shape
		piece.Size = Vector3.new(
			math.max(spec.Size.X * scale, MIN_PART_SIZE),
			math.max(spec.Size.Y * scale, MIN_PART_SIZE),
			math.max(spec.Size.Z * scale, MIN_PART_SIZE)
		)
		piece.Color = spec.Color
		piece.Material = spec.Material
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		piece.CFrame = specCFrame(spec, scale)
		piece.Anchored = isWorld
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.Massless = true
		piece.CastShadow = isWorld
		piece.Parent = model

		if root == nil then
			root = piece
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = piece
			weld.Parent = piece
		end
	end

	if root == nil then
		model:Destroy()
		return nil
	end

	model.WorldPivot = CFrame.new()
	return model
end

function JunkFactory.GetRoot(model: Instance): BasePart?
	local root = model:FindFirstChild(ROOT_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

return JunkFactory
